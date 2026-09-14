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

    /// `Documents/Photos/` —— **与 `ReminderService.photoURL` 的约定一致**。
    ///
    /// 不放进 App Group：通知的配图走 `UNNotificationAttachment`，
    /// 由系统把文件拷进那条通知自己的目录，扩展读得到。
    /// 共享容器只为打标收件箱而存在 —— 这是它能做到最小的原因。
    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Photos", isDirectory: true)
    }

    static func url(for hash: String) -> URL {
        directory.appendingPathComponent("\(hash).jpg")
    }

    static func exists(_ hash: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: hash).path)
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

    static func delete(_ hash: String) {
        try? FileManager.default.removeItem(at: url(for: hash))
        cache.removeObject(forKey: key(hash, maxPixel))
    }

    /// 清掉没有任何地方引用的图片文件，返回删掉的张数。
    ///
    /// **为什么必须有这个兜底，而不是「在每一步精细地删文件」**
    /// 「一张图什么时候可以删」比它看起来难：
    ///   · 用户从记录里移除了一张图 —— 但这条记录的**历史版本**可能还引用着它
    ///     （`Revision.photoHashes` 存的是快照，31 屏要靠它显示旧版的图）
    ///   · 「清空回收站」是在记录之外删数据，最容易漏
    ///   · 记录被删了、但 Revision 行还在，也是一种引用
    /// 精细删除要在四个地方分别想对；这里是**只在启动时按「现有引用全集」扫一遍**。
    /// 代价：删掉的图会多留到下次启动。换来：一次都不会误删。
    @discardableResult
    static func purgeOrphans(keeping referenced: Set<String>) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where name.hasSuffix(".jpg") {
            let hash = String(name.dropLast(4))
            guard !referenced.contains(hash) else { continue }
            try? FileManager.default.removeItem(at: url(for: hash))
            removed += 1
        }
        if removed > 0 { cache.removeAllObjects() }
        return removed
    }

    // MARK: - 引用集合与占用

    /// 数出「还被引用的 hash 全集」。
    /// **三处都要算上**（记录 / 历史版本 / 头像）—— 少算一处就会把还在用的图删掉。
    static func referencedHashes(records: [Record],
                                revisions: [Revision],
                                avatar: String?) -> Set<String> {
        var set = Set<String>()
        for r in records { for p in r.photos { set.insert(p.hash) } }
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
