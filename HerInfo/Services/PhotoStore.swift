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
    /// 返回 nil = 存不下来。**调用方应该安静跳过，而不是把整条记录也存失败** ——
    /// 一张图没存上，不该连她写的那句话一起丢掉。
    @discardableResult
    static func save(_ image: UIImage) -> String? {
        guard let data = jpegData(image, maxPixel: maxPixel) else { return nil }
        let hash = digest(data)
        let target = url(for: hash)

        // 同一张图（内容一模一样）已经有文件了 —— 直接沿用，不重写。
        if FileManager.default.fileExists(atPath: target.path) { return hash }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            return nil
        }
        return hash
    }

    /// 异步存。**界面一律走这个，不要直接调 `save`** ——
    /// 缩放渲染 + JPEG 编码 + 写文件是几十到上百毫秒的活，
    /// 连着存 9 张就是肉眼可见的卡顿。相册选完图那一下正落在主线程上。
    static func saveAsync(_ image: UIImage) async -> String? {
        await Task.detached(priority: .userInitiated) { save(image) }.value
    }

    /// 压到长边 ≤ maxPixel 再转 JPEG。    ///
    /// 用 `UIGraphicsImageRenderer` 而不是 `UIGraphicsBeginImageContext`：
    /// 后者在 @3x 设备上会按屏幕缩放因子出图，同一张原图在三台设备上得到三种尺寸，
    /// 而内容哈希要求「同一张图在任何设备上都要算出同一个 hash」。
    /// 所以这里把 scale 固定成 1，尺寸完全由像素决定。
    static func jpegData(_ image: UIImage, maxPixel: CGFloat) -> Data? {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        guard w > 0, h > 0 else { return nil }

        let ratio = min(1, maxPixel / max(w, h))
        let size = CGSize(width: (w * ratio).rounded(), height: (h * ratio).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true          // 照片没有透明通道，不透明能让 JPEG 更小
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
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

    /// 图片占用的字节数。12 屏设置里的「占用空间」用它。
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
