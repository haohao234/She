//
//  PhotoStore.swift
//  配图的落盘层：全 App 唯一的「图片文件 ↔ hash」出口
//
//  【它补的是什么洞】
//  在这之前，代码里只有 hash 这个**字符串**，没有任何东西真的把图片写成文件：
//    · PhotoGrid 的「＋」往数组里塞的是 "hash:new0" 这种假值
//    · PhotoCell 画的是一个分类渐变
//    · 33 屏「换一张头像」的按钮体是空的
//    · ReminderService.attachFirstPhoto 去 Documents/Photos/<hash>.jpg 找文件 —— 那里永远是空的
//    · ExportService 的 JSON 写着「图片单独放在文件夹里」—— 而它从没拷过一张图
//  结果是「配图」这整条产品线是**演出来的**：每一屏都画得对，但没有一张真照片。
//
//  【三个不许改的决定】
//
//  ① hash 必须是**内容哈希**，不能是随机 UUID。
//     导出的 JSON 里存的就是它，注释写着「换机时按 hash 重新关联」——
//     随机 UUID 换机之后就是一堆谁也认不出的名字，那句承诺当场作废。
//     内容寻址顺带解决第二件事：同一张图重复添加不会占两份空间。
//
//  ② 存的是**压缩后的副本**（长边 ≤ 2048、JPEG 0.82），不是原图。
//     12MP 原图约 3–4MB，一条记录 9 张就是 30MB 起；
//     长边 2048 大约 300–500KB。锁屏通知和 105×105 缩略图都用不到原图的像素 ——
//     存原图只会让「占用空间」这个数字变难看。
//
//  ③ 读的时候**必须降采样**，不能 `UIImage(contentsOfFile:)`。
//     后者会把整张图按原尺寸解码进内存（2048×1536 ≈ 12MB 位图），
//     一屏 9 张就是 100MB+，列表滚动直接卡死。
//     `CGImageSourceCreateThumbnailAtIndex` 只解出要用的那点像素。
//
//  【曾经会闪退：写入侧把整张原图解开了】
//  上面第 ③ 条只管了「读」。**写入侧当时是漏的** ——
//  `save` 收的是 `UIImage`，而 `UIImage(data:)` 是**懒解码**：
//  它只拿着压缩字节，真正解成位图是在第一次 `draw` 的时候。
//  于是 `jpegData` 里那句 `image.draw(in:)` 就是「第一次」，
//  一张 8064×6048 的 48MP 原图要在那一刻一次性解出约 195MB 的位图。
//  两个后果叠在一起，就是用户在真机上看到的「导入失败然后闪退」：
//    · 内存一紧，解码先失败 → 格子不出现（看起来像「导入失败」）
//    · 再紧一点，App 被系统直接杀掉（就是闪退）
//  而且 `Task.detached` 跑在协作线程池上，**那条线程的自动释放池
//  可能整批图处理完都不会清一次**，9 张图就是 9 份临时缓冲一起堆着。
//
//  **修法是让写入侧和读取侧用同一招**：入参从 `UIImage` 换成相册给的
//  原始 `Data`，用 `CGImageSourceCreateThumbnailAtIndex` 只解出长边 ≤ 2048
//  的那点像素（≈12MB），原图从头到尾没有被整张解开过；
//  再用 `autoreleasepool` 把每张图的临时对象在那一轮就放掉。
//

import UIKit
import CryptoKit

enum PhotoStore {

    // MARK: - 位置

    /// **图片从 `Documents/Photos/` 搬到了 `Library/Application Support/Photos/`。**
    ///
    /// 【为什么必须搬】`Info.plist` 里 `UIFileSharingEnabled = true`（导出功能
    /// 需要它 —— 用户要能在「文件」App 里把导出件拖走），代价是**整个 `Documents/`
    /// 都摊在「文件」App → onMyiPhone → 她的信息本 里**。于是 `Photos/` 和导出目录
    /// 并排躺在用户手边：任何一次「清理一下」都可能把它删掉，而后果是
    /// **记录全在、图一张不剩**，界面上只说一句「这张图的文件不在这台手机上」——
    /// 看起来像手机的问题，实际上是 App 把数据放在了不该放的地方。
    ///
    /// **导出目录留在 `Documents` 不动**：它存在的唯一理由就是让用户拿出去，
    /// 藏起来等于把这个功能作废。
    ///
    /// 不放进 App Group：通知的配图走 `UNNotificationAttachment`，
    /// 由系统把文件拷进那条通知自己的目录，扩展读得到。
    /// 共享容器只为打标收件箱而存在 —— 这是它能做到最小的原因。
    static let legacyDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Photos", isDirectory: true)
    }()

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Photos", isDirectory: true)
    }()

    /// 「搬完了没有」。
    ///
    /// **判据是这个开关，不是「新位置有没有文件」** —— 用户还没导入过任何图时
    /// 新位置本来就是空的，拿它当判据会每次启动都试图搬一遍。
    /// 开关**只在搬完并校验过之后**才翻（见 `migrateDirectoryIfNeeded()`）。
    private static let movedKey = "hi.photos.dir.v2"

    /// 图片在哪。**读和写都只认这一个出口**（`ReminderService.photoURL` 也走它）。
    ///
    /// 开关没翻之前一律返回老位置。这一条是承重的：任何一次
    /// 「文件还在老地方、App 去新地方找」都会表现成**所有图同时消失** ——
    /// 而这个 App 的图片读取层只有一个判据（`fileExists`），到时候
    /// 除了「这张图的文件不在这台手机上」，它没有任何别的可说。
    static var directory: URL {
        UserDefaults.standard.bool(forKey: movedKey) ? supportDirectory : legacyDirectory
    }

    static func url(for hash: String) -> URL {
        directory.appendingPathComponent("\(hash).jpg")
    }

    static func exists(_ hash: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: hash).path)
    }

    // MARK: - 一次性搬家（启动时调一次）

    /// 把老位置的图片整份搬到 `Application Support`。返回「现在是不是在新位置」。
    ///
    /// 【为什么写成这样】三条都是被「图会消失」这件事逼出来的：
    ///
    ///  ① **开关没翻就不换位置。** 搬不动（磁盘满 / 沙盒异常）就原地不动，
    ///     App 继续用老位置 —— 图仍然读得到，只是还留在「文件」App 里。
    ///     宁可下一轮再搬，也不要出现「搬了一半的目录」。
    ///  ② **中途失败要把已经搬过去的搬回来。** 半搬状态是最坏的结果：
    ///     开关不会翻、App 仍读老位置，而刚搬走的那几张会当场表现成图不见了。
    ///  ③ **逐个搬、跳过已存在的同名**（内容寻址：同名即同内容），
    ///     而不是整目录 `moveItem` —— 后者碰上已存在的新位置目录会直接失败。
    @discardableResult
    static func migrateDirectoryIfNeeded() -> Bool {
        let fm = FileManager.default
        let d = UserDefaults.standard

        if d.bool(forKey: movedKey) {
            try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            return true
        }

        // 老位置压根没有 → 没什么可搬的，直接把开关翻掉。
        // （用户装过带这一版逻辑的包又退回去、再装回来时会走到这里。）
        guard fm.fileExists(atPath: legacyDirectory.path) else {
            try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            d.set(true, forKey: movedKey)
            return true
        }

        guard let names = try? fm.contentsOfDirectory(atPath: legacyDirectory.path),
              !names.isEmpty else {
            // 老位置是空的（用户还没导入过图）→ 同样不需要搬。
            try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            d.set(true, forKey: movedKey)
            return true
        }

        var moved: [String] = []
        do {
            try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            for name in names {
                let src = legacyDirectory.appendingPathComponent(name)
                let dst = supportDirectory.appendingPathComponent(name)
                // 已经有同名的就不动它。`Photos/.trash` 也在这里面，一起搬。
                if fm.fileExists(atPath: dst.path) { continue }
                try fm.moveItem(at: src, to: dst)
                moved.append(name)
            }
        } catch {
            // ② 把已经搬过去的逐个搬回来。搬不回来的（极端情况）也不删 ——
            //    宁可留一份在新位置，也不要让它凭空消失。
            for name in moved {
                let back = legacyDirectory.appendingPathComponent(name)
                if fm.fileExists(atPath: back.path) { continue }
                try? fm.moveItem(at: supportDirectory.appendingPathComponent(name), to: back)
            }
            return false
        }

        // 搬完**校验一遍**：老位置还剩着 `.jpg` 就不算搬完，开关不翻。
        let left = (try? fm.contentsOfDirectory(atPath: legacyDirectory.path)) ?? []
        guard !left.contains(where: { $0.hasSuffix(".jpg") }) else { return false }
        if left.isEmpty { try? fm.removeItem(at: legacyDirectory) }

        // 开关写在最后 —— 反过来（先翻开关、再搬家）会在搬失败时
        // 让 App 去新位置找一堆还在老位置的图。
        d.set(true, forKey: movedKey)
        return true
    }

    // MARK: - 写

    /// 长边上限。2048 足够锁屏全宽显示，又不会让一张图占几 MB。
    static let maxPixel: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.82

    /// 存一张图，返回它的 hash（内容寻址）。
    ///
    /// **入参是相册给的原始字节，不是 `UIImage`** —— 理由见文件头
    /// 「曾经会闪退：写入侧把整张原图解开了」。简单说：只要不构造 `UIImage`，
    /// 就不可能有一整张原图的位图被解出来。
    ///
    /// 返回 nil = 存不下来。**调用方应该安静跳过，而不是把整条记录也存失败** ——
    /// 一张图没存上，不该连她写的那句话一起丢掉。
    @discardableResult
    static func save(_ data: Data) -> String? {
        guard let jpeg = jpegData(from: data, maxPixel: maxPixel) else { return nil }
        return persist(jpeg)
    }

    /// 异步存。**界面一律走这个，不要直接调 `save`** ——
    /// 降采样 + JPEG 编码 + 写文件是几十到上百毫秒的活，
    /// 连着存 9 张就是肉眼可见的卡顿。相册选完图那一下正落在主线程上。
    static func saveAsync(_ data: Data) async -> String? {
        await Task.detached(priority: .userInitiated) {
            // **`autoreleasepool` 不能省。**
            // `Task.detached` 跑在协作线程池上，那条线程什么时候清自动释放池
            // 不由我们决定 —— 实测上它可能在「整批图都处理完」之前都不清。
            // 少了这一层，每一轮解码与渲染产生的临时缓冲会一直堆着：
            // 选 9 张就是 9 份。包一层 = 每张图处理完就把临时对象放掉。
            autoreleasepool { save(data) }
        }.value
    }

    /// 内容寻址的那一步：算了 hash，文件已经在就沿用，不在才写。
    private static func persist(_ jpeg: Data) -> String? {
        let hash = digest(jpeg)
        let target = url(for: hash)

        // 同一张图（内容一模一样）已经有文件了 —— 直接沿用，不重写。
        if FileManager.default.fileExists(atPath: target.path) { return hash }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: target, options: .atomic)
        } catch {
            return nil
        }
        return hash
    }

    /// 压到长边 ≤ maxPixel 再转 JPEG。**入参是原图字节。**
    ///
    /// 分两步，两步都有理由：
    ///
    /// ① `CGImageSourceCreateThumbnailAtIndex` —— 只解出要用的那点像素。
    ///    它与下面「读」那一侧的 `decode` 是同一个办法：写和读从此不再是两套。
    ///    `kCGImageSourceCreateThumbnailWithTransform` 顺手把 EXIF 方向烤进像素里，
    ///    所以竖拍的照片不会在这里躺倒（这一点以前只在读的时候管了）。
    ///
    ///    **`kCGImageSourceThumbnailMaxPixelSize` 是「上限」，不是「目标」。**
    ///    Apple 的原话是「creates the thumbnail from the full image, **subject to
    ///    the limit** specified by kCGImageSourceThumbnailMaxPixelSize」，
    ///    而且这套选项里**根本没有「最小尺寸」那一项**（只能往下缩，不能要求放大）。
    ///    所以源图比 maxPixel 小时，出来的就是源图自己那么大 ——
    ///    上一版那句 `let ratio = min(1, maxPixel / max(w, h))` 的夹子因此不必再写，
    ///    **不是忘了写。**
    ///
    /// ② `UIGraphicsImageRenderer` 再画一遍 —— 不是为了缩放（①已经缩完了），
    ///    只是为了把颜色空间统一、并且用 `opaque = true` 丢掉透明通道，让 JPEG 更小。
    ///    用 `UIGraphicsImageRenderer` 而不是 `UIGraphicsBeginImageContext`：
    ///    后者在 @3x 设备上会按屏幕缩放因子出图，同一张原图在三台设备上得到三种尺寸，
    ///    而内容哈希要求「同一张图在任何设备上都要算出同一个 hash」。
    ///    所以这里把 scale 固定成 1，尺寸完全由像素决定。
    static func jpegData(from data: Data, maxPixel: CGFloat) -> Data? {
        guard !data.isEmpty else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return nil }

        let seed = UIImage(cgImage: cg)
        let w = seed.size.width * seed.scale
        let h = seed.size.height * seed.scale
        // `isFinite` 那一句不是凑数的：`UIGraphicsImageRenderer` 拿到 NaN
        // 尺寸时不是返回 nil，是直接抛异常。护栏要拦在它前面。
        guard w.isFinite, h.isFinite, w > 0, h > 0 else { return nil }
        let size = CGSize(width: w.rounded(), height: h.rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true          // 照片没有透明通道，不透明能让 JPEG 更小
        let flattened = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            seed.draw(in: CGRect(origin: .zero, size: size))
        }
        return flattened.jpegData(compressionQuality: jpegQuality)
    }

    /// 内容哈希：SHA-256 取前 8 字节 = 16 个 hex 字符。
    ///
    /// 取 8 字节是刻意的：完整 32 字节做文件名太长，而 64 bit 的碰撞概率
    /// 在「一个人手机里的照片」这个量级上可以忽略（十亿张图撞一次）。
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 读

    /// 解码结果缓存。键里带上目标尺寸 —— 105 缩略图和 2048 全屏是两份不同的位图，
    /// 用同一个键会把缩略图当成大图返回（界面糊），反过来则白白占内存。
    private static let cache = NSCache<NSString, UIImage>()

    private static func key(_ hash: String, _ maxPixel: CGFloat) -> NSString {
        "\(hash)@\(Int(maxPixel))" as NSString
    }

    /// 同步读。**只适合已经在后台线程、或尺寸很小的场合**（如列表缩略图首帧）。
    /// 界面里请优先用 `load(_:maxPixel:)`。
    static func image(_ hash: String, maxPixel: CGFloat) -> UIImage? {
        let k = key(hash, maxPixel)
        if let hit = cache.object(forKey: k) { return hit }
        guard let img = decode(url(for: hash), maxPixel: maxPixel) else { return nil }
        cache.setObject(img, forKey: k)
        return img
    }

    /// 异步读。给 SwiftUI 的 `.task` 用 —— 磁盘 IO 与解码都不该压在主线程。
    static func load(_ hash: String, maxPixel: CGFloat) async -> UIImage? {
        let k = key(hash, maxPixel)
        if let hit = cache.object(forKey: k) { return hit }
        let fileURL = url(for: hash)
        let img: UIImage? = await Task.detached(priority: .userInitiated) {
            decode(fileURL, maxPixel: maxPixel)
        }.value
        if let img { cache.setObject(img, forKey: k) }
        return img
    }

    private static func decode(_ fileURL: URL, maxPixel: CGFloat) -> UIImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // 尊重 EXIF 方向：手机竖拍的照片在文件里是横的，
            // 少了这一条，读出的人像会躺倒 —— 而这在编辑页里看不见，只在详情页才暴露。
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - 删

    /// 图片的回收站：`Photos/.trash/`。
    ///
    /// **它存在的唯一理由是「删除不可回」。** 这个 App 只有一处删图片
    /// （下面的 `purgeOrphans`），而那一处是按「引用全集」扫出来的结果办事的 ——
    /// 全集一旦算错，错的是**一批**，不是一个。直接 `removeItem` 的话，
    /// 算错与丢光之间没有任何缓冲：用户点开哪张、哪张说文件不在。
    /// 先进回收站，就有了第二次机会（见 `purgeOrphans` 的 ④）。
    static var trashDirectory: URL {
        directory.appendingPathComponent(".trash", isDirectory: true)
    }

    /// **真删一张。全工程没有调用点** —— 保留它是为了让「文件级删除」
    /// 这件事有一个带名字的出口，而不是散落在别处。
    /// 正常路径一律走 `purgeOrphans`（进回收站 → 下一轮才真删）。
    static func delete(_ hash: String) {
        try? FileManager.default.removeItem(at: url(for: hash))
        try? FileManager.default.removeItem(at: trashDirectory.appendingPathComponent("\(hash).jpg"))
        cache.removeObject(forKey: key(hash, maxPixel))
    }

    /// 一次清理的结果。**调用方要拿它说一句实话** —— 这个结构体是被
    /// 「图没了、App 一声不响」逼出来的：以前它只返回一个张数，
    /// 而唯一会看那个数的人是没人。
    struct PurgeReport {
        /// 这次挪进回收站的（还没真删）。
        var trashed = 0
        /// 又在记录里被引用上、从回收站搬回来的。
        var restored = 0
        /// 在回收站里躺够时间、这次真删的。
        var removed = 0
        /// 非 nil = 这次整体跳过，原因是它。
        var skipped: String?
        /// **被记录引用着、文件却不在的** —— 用户已经丢掉的图。
        /// 这不是这次清理造成的（这次一张都没删它），但必须让他知道。
        var referencedMissing = 0

        var didAnything: Bool { trashed > 0 || restored > 0 || removed > 0 }
    }

    /// 清掉没有任何地方引用的图片文件。
    ///
    /// **为什么必须有这个兜底，而不是「在每一步精细地删文件」**
    /// 「一张图什么时候可以删」比它看起来难：
    ///   · 用户从记录里移除了一张图 —— 但这条记录的**历史版本**可能还引用着它
    ///     （`Revision.photoHashes` 存的是快照，31 屏要靠它显示旧版的图）
    ///   · 「清空回收站」是在记录之外删数据，最容易漏
    ///   · 记录被删了、但 Revision 行还在，也是一种引用
    /// 精细删除要在四个地方分别想对；这里是**只在启动时按「现有引用全集」扫一遍**。
    /// 代价：删掉的图会多留到下次启动。换来：一次都不会误删。
    ///
    /// ---
    ///
    /// 【2026-09-21：这一段重写了。用户报「今天查看导入的图片，发现看不到了，
    ///  显示这张图的文件不在这台手机上」—— 记录还在、图没了。】
    ///
    /// 全工程扫过一遍：**能删图片文件的地方只有这一处**
    /// （`PhotoStore.delete` 一个调用点都没有；`ExportService` 只往导出目录写；
    /// 两个扩展碰不到这个目录）。所以那个症状只能由这一处造成，而它原来是这样的：
    ///
    ///     按引用全集扫一遍，不在集合里就 `removeItem`。
    ///
    /// 三个口子，每一个都能单独造成「记录全在、图一张不剩」，而且**不可回、无声**：
    ///
    ///  ① **它的输入是一个 unchecked 的 `try? fetch ?? []`。** 那次读失败
    ///     （库正忙 / 迁移中 / 磁盘紧）与「一条记录都没有」在这段代码眼里
    ///     长得一模一样，而处置是「把磁盘上所有图都当孤儿删光」。
    ///     一个记录都没有、磁盘上却有 20 张图的库，不是空库，是**读坏了**。
    ///  ② **库被挪走重建之后，引用全集合法地为空。** 老库还在
    ///     `broken-<时间戳>/` 里躺着、那句「旧数据未删」也还在屏幕上，
    ///     可下一次正常启动就会把它引用过的图全删掉 —— 记录回得来、图回不来。
    ///  ③ **删了就是删了**：没有回收站、没有日志、没有一句提示。
    ///     用户只能靠一张张点开才发现，然后什么也做不了。
    ///
    /// 所以现在四道闸，一起才对：
    ///
    ///  ① **列不出目录 → 什么也不做。**
    ///  ② **磁盘上有图、引用集却是空的 → 整体跳过**（那是读坏了的签名，不是「全是孤儿」）。
    ///  ③ 不在引用集里的 → **挪进 `.trash/`，不是删**。而且**先看回收站里有没有
    ///     又被引用上的，有就搬回来** —— 这就是内容寻址那句「换机时按 hash
    ///     重新关联」的同一条思路：用户把同一张图再加一次，hash 一样，
    ///     旧记录里那些「图不在了」的格子当场自己好了。
    ///  ④ 回收站里躺够 `trashGraceHours` 还没人引用的，才真删。
    ///     留这一轮的意义是：万一某一次的引用集是错的，图还在回收站里；
    ///     下一次正确的启动会按 ③ 把它们搬回去。
    ///
    /// **两道一起才成立的判据**：② 挡住「一次读失败就全灭」，
    /// ③④ 把「算错了」的后果从「永久丢失」降成「多占几天磁盘」。
    @discardableResult
    static func purgeOrphans(keeping referenced: Set<String>) -> PurgeReport {
        var report = PurgeReport()
        let fm = FileManager.default

        // ① 列不出目录：可能是数据保护还没解开（锁屏状态下的后台启动）。
        //    这时候**什么都不做** —— 把「读不到」当成「没有」是这次事故的形状。
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
            report.skipped = "图片目录列不出来"
            return report
        }
        let onDisk = names.filter { $0.hasSuffix(".jpg") }.map { String($0.dropLast(4)) }

        // ② 读坏了的签名 —— 整体跳过。删掉不可回，多留一层只是占点磁盘，
        //    两种代价不对称，所以一律往「留」那边倒。
        if referenced.isEmpty && !onDisk.isEmpty {
            report.skipped = "引用集为空，但磁盘上还有 \(onDisk.count) 张图"
            return report
        }

        // ③-a 回收站里**又被引用上**的，先搬回来。
        //     放在删除之前：一个 hash 同时可能「在回收站里」且「被记录引用」，
        //     那种情况下它的归宿是记录，不是垃圾桶。
        if let inTrash = try? fm.contentsOfDirectory(atPath: trashDirectory.path) {
            for name in inTrash where name.hasSuffix(".jpg") {
                let hash = String(name.dropLast(4))
                guard referenced.contains(hash) else { continue }
                do {
                    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                    try fm.moveItem(at: trashDirectory.appendingPathComponent(name),
                                    to: url(for: hash))
                    report.restored += 1
                } catch {
                    // 搬不回来就先放着 —— 它在回收站里躺着，不会更糟。
                }
            }
        }

        // ③-b 不在引用集里的 → 挪进回收站（**不是删**）。
        for hash in onDisk where !referenced.contains(hash) {
            let dst = trashDirectory.appendingPathComponent("\(hash).jpg")
            do {
                try fm.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
                try fm.moveItem(at: url(for: hash), to: dst)
                // 记下「什么时候进的回收站」。`moveItem` 会把老的修改时间一起带过来，
                // 所以不能拿它当判据 —— 必须在这里盖一个时间戳，④ 才有得比。
                try? fm.setAttributes([.modificationDate: Date.now], ofItemAtPath: dst.path)
                report.trashed += 1
            } catch {
                // 挪不动就留在原地。它是个孤儿，多占一点磁盘而已 ——
                // 这里**绝不能退化成 removeItem**：搬不动就删，等于把
                // 「删之前留一手」这道闸在磁盘最紧的时候自动关掉。
            }
        }

        // ④ 回收站里躺够时间的 → 真删。
        if let inTrash = try? fm.contentsOfDirectory(atPath: trashDirectory.path) {
            let deadline = Date.now.addingTimeInterval(-trashGraceHours * 3600)
            for name in inTrash where name.hasSuffix(".jpg") {
                let hash = String(name.dropLast(4))
                // ③-a 已经把「又被引用上」的搬走了，这里再挡一次是同一条判据的第二道。
                guard !referenced.contains(hash) else { continue }
                let filePath = trashDirectory.appendingPathComponent(name)
                // 时间戳取不到（文件刚被系统动过 / 属性读失败）→ **不动它**。
                // 这里不写 `?? .now` 那种兜底：读不到时间就当成「刚进桶」，
                // 多留一天是安全的，而错删一次是不可回的。
                guard let values = try? filePath.resourceValues(forKeys: [.contentModificationDateKey]),
                      let at = values.contentModificationDate,
                      at < deadline else { continue }
                try? fm.removeItem(at: filePath)
                report.removed += 1
            }
        }

        // ⑤ 报出「被引用着、文件却不在」的数目。**这里不删任何东西**：
        //    那行 hash 本身就是「把这张图找回来」的全部凭据
        //    （用户再选一次同一张图，会算出同一个 hash）。删掉它才是真的丢。
        report.referencedMissing = referenced.reduce(into: 0) { acc, hash in
            if !fm.fileExists(atPath: url(for: hash).path) { acc += 1 }
        }

        if report.didAnything { cache.removeAllObjects() }
        return report
    }

    /// 孤儿在回收站里要躺多久才真删。
    ///
    /// **按时间而不是按「启动了几次」**：用户一小时内开合 App 五次是很正常的事，
    /// 按次数算的话，一次算错的引用集只需要被开合两次就兑现成了永久丢失。
    /// 一天之内他会重启很多次、也会自己去看一眼 —— 那是这个宽限期真正在等的东西。
    static let trashGraceHours: Double = 24

    // MARK: - 引用集合与占用

    /// 数出「还被引用的 hash 全集」。
    /// **三处都要算上**（记录配图 / 历史版本快照 / 头像）—— 少算一处就会把还在用的图删掉。
    ///
    /// **三个入参读的都是标量**：`Record.photoHashes`、`Revision.photoHashes`、
    /// `Profile.avatarHash`。这里**一次都不碰 `Photo` 模型对象** ——
    /// 而这个函数跑在**启动流程**里，崩了的后果不是「少清几张图」，是 **App 打不开**。
    ///
    /// 这一段换过两次写法，都是被同一个 bug 逼的：
    ///   · 最早：`for r in records { for p in r.photos { … } }` —— 走关系，会撞墓碑；
    ///   · 上一版：从 `Photo` 全表 fetch 再读 `p.hash` —— 看着绕开了关系，
    ///     其实还是读 `Photo` 对象，一样会撞（11:49 那份日志崩的就是同族的写法）；
    ///   · 现在：读标量。**判据从来不是「关系还是表」，而是「读不读那个模型对象」。**
    static func referencedHashes(records: [Record],
                                revisions: [Revision],
                                avatar: String?) -> Set<String> {
        var set = Set<String>()
        for r in records { for h in r.photoHashes { set.insert(h) } }
        for v in revisions { for h in v.photoHashes { set.insert(h) } }
        if let a = avatar, !a.isEmpty { set.insert(a) }
        return set
    }

    /// 图片占用的字节数。
    ///
    /// **目前画布上没有对应的入口** —— 12 屏内容区已经排满，加「占用空间」这一行
    /// 要挤掉别的行，所以按约定不加。这两个函数留着是因为它们与上面的 `referencedHashes`
    /// 同属「本地图片的家底」：真要加那一行时，直接 `humanSize(totalBytes())` 即可，
    /// 不必回头补实现。**没有入口 ≠ 漏写。**
    static func totalBytes() -> Int64 {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var total: Int64 = 0
        for name in names {
            let p = directory.appendingPathComponent(name)
            let size = (try? p.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    /// 「12.4 MB」这种人看的写法。0.1 MB 以下按 KB 显示。
    static func humanSize(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        let mb = Double(bytes) / 1024 / 1024
        if mb < 0.1 { return "\(max(1, bytes / 1024)) KB" }
        return String(format: "%.1f MB", mb)
    }
}
