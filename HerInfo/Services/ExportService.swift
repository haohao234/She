//
//  ExportService.swift
//  导出落地：PDF / Markdown / JSON
//
//  三种格式走三条不同的路：
//    JSON     → Codable 编码，字段最完整，是唯一能「导回来」的格式
//    Markdown → 拼字符串，给人读的，标题层级对应分类
//    PDF      → UIGraphicsPDFRenderer 排版，排版固定、不依赖任何 App
//
//  导出全部落「文件」App 的 onMyiPhone/我的宝宝江林桐/ 下 ——
//  用户能自己找到、能自己删除。不做「分享到某个云」，因为数据不出本机是这个 App 的承诺。
//

import Foundation
import SwiftData
import UIKit

@MainActor
final class ExportService {
    static let shared = ExportService()
    private init() {}

    func export(_ records: [Record],
                revisions: [Revision],
                format: ExportFormat,
                includePhotos: Bool,
                includeVersions: Bool,
                includeReminders: Bool) async throws -> URL {

        let dir = try exportDirectory()
        let stamp = DateFormatter.fileStamp.string(from: .now)
        let name = "我的宝宝江林桐-\(stamp).\(format.ext)"
        let url = dir.appendingPathComponent(name)

        switch format {
        case .json:
            try buildJSON(records, revisions: revisions, includePhotos: includePhotos,
                          includeVersions: includeVersions,
                          includeReminders: includeReminders)
                .write(to: url, atomically: true, encoding: .utf8)
            // 图片是 JSON 之外的东西：base64 塞进去会让文件涨约三分之一，
            // 而且塞完就再也没法用任何图片工具打开。跟 JSON 并排拷一份。
            if includePhotos { copyPhotos(records, beside: url) }

        case .markdown:
            // Markdown 只写「有几版」，不把每一版正文铺开 ——
            // 它是给人读的，不是给人比对的；要看每一版请走 JSON。
            try buildMarkdown(records,
                              revisions: includeVersions ? revisions : [],
                              includeReminders: includeReminders)
                .write(to: url, atomically: true, encoding: .utf8)

        case .pdf:
            // PDF 不带历史版本。**这是刻意的，不是漏了** ——
            // PDF 的用途是「打印或发给别人看」，历史版本是给自己翻的。
            // 把每一版旧正文铺进 PDF，只会让这份东西没法给别人看。
            try buildPDF(records, includeReminders: includeReminders).write(to: url)
        }

        return url
    }

    /// 把引用的配图拷到导出文件旁边。
    ///
    /// **为什么必须真拷一份，而不是「JSON 里留个 hash 让他自己去沙盒找」**：
    /// 用户拿到文件之后会用「文件」App 把它拖到 U 盘 / 发到微信 / 存进网盘 ——
    /// 拖走的只有他勾中的那个文件。图还留在 App 沙盒里的话，
    /// 这份 JSON 换到新手机上就是一堆指向空气的 hash，
    /// 而注释里那句「换机时按 hash 重新关联」也就成了一句空话。
    ///
    /// 目录名取 `我的宝宝江林桐-20260911-1130 配图`：与文件并排、名字对得上，
    /// 用户在「文件」里一眼看得出这两样是一起的。
    private func copyPhotos(_ records: [Record], beside fileURL: URL) {
        let hashes = Set(records.flatMap { $0.photos.map(\.hash) })
        guard !hashes.isEmpty else { return }

        let base = fileURL.deletingPathExtension().lastPathComponent
        let dir = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(base) 配图", isDirectory: true)

        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        for h in hashes {
            let src = PhotoStore.url(for: h)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dir.appendingPathComponent(src.lastPathComponent)
            // 覆盖上一次导出的同一个 hash。文件名相同就代表内容一模一样
            // （内容寻址），所以覆盖不会丢掉任何东西。
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
        }
    }

    /// 导出落点：`文件 App / onMyiPhone / 我的宝宝江林桐 /`。
    ///
    /// **这个名字跟 App 显示名走，但它不是数据格式。**
    /// 换名字时老目录不会被搬走 —— 用户如果之前导出过，会看到两个目录。
    /// 这是刻意的：**搬目录要读旧文件、可能失败，而失败时用户看到的是
    /// 「我的备份不见了」**。宁可多一个空目录，也不要动已有的文件。
    /// 真要清，让用户自己去「文件」里删。
    private func exportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("我的宝宝江林桐", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - JSON（换机恢复用）

    private struct ExportPayload: Codable {
        struct Pic: Codable {
            let hash: String
            let order: Int
        }

        /// 一条历史版本。**存整份快照而不是 diff**，理由见 Models.swift 的 Revision。
        struct Rev: Codable {
            let version: Int
            let title: String
            let body: String
            let at: Date
        }

        struct Rec: Codable {
            let id: String
            let cat: String
            let title: String
            let body: String
            let tags: [String]
            let photos: [Pic]
            let version: Int
            let createdAt: Date
            let updatedAt: Date
            let reminder: String?
            /// 「包含内容 › 历史版本」打开时才有值。
            /// **用 nil 而不是空数组来区分「这次没导」和「这条没有历史」** ——
            /// 空数组会让读回来的人以为「这条从来没改过」。
            let revisions: [Rev]?
        }

        let exportedAt: Date
        let appVersion: String
        /// 版本号写进文件，换机导回时能判断格式是否兼容。
        let schemaVersion: Int
        /// **导出的是「数据」，不是「文件路径」。**
        /// 图片由 `copyPhotos` 拷到并排的「…配图」文件夹里，这里只留 hash ——
        /// 换机时按 hash 重新关联。
        let records: [Rec]
    }

    private func buildJSON(_ records: [Record],
                           revisions: [Revision],
                           includePhotos: Bool,
                           includeVersions: Bool,
                           includeReminders: Bool) -> String {
        // 按 recordID 分组一次，避免在 map 里对每条记录都全表扫一遍。
        let revBy: [String: [Revision]] = includeVersions
            ? Dictionary(grouping: revisions, by: \.recordID)
            : [:]

        let payload = ExportPayload(
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            schemaVersion: 1,
            records: records.map { r in
                ExportPayload.Rec(
                    id: r.id,
                    cat: r.cat.rawValue,
                    title: r.title,
                    body: r.body,
                    tags: r.tags,
                    photos: includePhotos
                        ? r.photos.sorted { $0.order < $1.order }
                                  .map { ExportPayload.Pic(hash: $0.hash, order: $0.order) }
                        : [],
                    version: r.version,
                    createdAt: r.createdAt,
                    updatedAt: r.updatedAt,
                    reminder: includeReminders ? r.reminder?.message : nil,
                    revisions: includeVersions
                        ? (revBy[r.id] ?? [])
                            .sorted { $0.version > $1.version }
                            .map { ExportPayload.Rev(version: $0.version,
                                                     title: $0.titleSnapshot,
                                                     body: $0.bodySnapshot,
                                                     at: $0.at) }
                        : nil
                )
            }
        )

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(payload),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    // MARK: - Markdown（给自己存）

    private func buildMarkdown(_ records: [Record],
                              revisions: [Revision],
                              includeReminders: Bool) -> String {
        let revBy = Dictionary(grouping: revisions, by: \.recordID)

        var out = "# 我的宝宝江林桐\n\n"
        out += "导出时间：\(DateFormatter.cnFull.string(from: .now))　·　\(records.count) 条\n\n"

        // 按分类分章 —— 这是 Markdown 的优势：标题层级天然就是目录。
        for cat in Category.allCases {
            let list = records.filter { $0.cat == cat }
            guard !list.isEmpty else { continue }
            out += "## \(cat.title)（\(list.count)）\n\n"
            for r in list {
                out += "### \(r.title)\n\n"
                if !r.body.isEmpty { out += "\(r.body)\n\n" }
                if !r.tags.isEmpty { out += "标签：\(r.tags.joined(separator: "、"))\n\n" }
                if !r.photos.isEmpty { out += "配图：\(r.photos.count) 张\n\n" }
                if includeReminders, let m = r.reminder {
                    out += "> 提醒：\(m.previewLine)\n\n"
                }
                out += "— 更新于 \(DateFormatter.cnFull.string(from: r.updatedAt))　第 \(r.version) 版"
                // 只报「共几版」，不铺开旧正文 —— 理由见 export() 里的注释。
                if let revs = revBy[r.id], !revs.isEmpty {
                    out += "　·　有 \(revs.count) 版历史"
                }
                out += "\n\n"
            }
        }
        return out
    }

    // MARK: - PDF（给别人看）

    /// A4 + 中文字体。用系统字体（苹方）—— 这是 iOS 上渲染中文最稳的选择。
    private func buildPDF(_ records: [Record], includeReminders: Bool) -> Data {
        let pageW: CGFloat = 595, pageH: CGFloat = 842      // A4 @72dpi
        let margin: CGFloat = 48
        let textW = pageW - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))

        return renderer.pdfData { ctx in
            var y = margin

            func newPageIfNeeded(_ needed: CGFloat) {
                if y + needed > pageH - margin {
                    ctx.beginPage()
                    y = margin
                }
            }

            ctx.beginPage()

            // 标题
            let title = "我的宝宝江林桐"
            title.draw(at: CGPoint(x: margin, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: UIColor(hex: 0x1F1E1B)
            ])
            y += 34

            "共 \(records.count) 条 · 导出于 \(DateFormatter.cnFull.string(from: .now))"
                .draw(at: CGPoint(x: margin, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor(hex: 0x948C82)
                ])
            y += 28

            for cat in Category.allCases {
                let list = records.filter { $0.cat == cat }
                guard !list.isEmpty else { continue }

                newPageIfNeeded(48)
                // 分类色条 + 名称
                UIColor(hex: cat.hex).setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: y + 3, width: 3, height: 14),
                             cornerRadius: 1.5).fill()
                "\(cat.title)（\(list.count)）".draw(at: CGPoint(x: margin + 10, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: UIColor(hex: 0x1F1E1B)
                ])
                y += 30

                for r in list {
                    let bodyAttr: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 11),
                        .foregroundColor: UIColor(hex: 0x5C5A55)
                    ]
                    let bodyRect = (r.body as NSString).boundingRect(
                        with: CGSize(width: textW, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin],
                        attributes: bodyAttr, context: nil)

                    newPageIfNeeded(24 + bodyRect.height + 24)

                    r.title.draw(at: CGPoint(x: margin, y: y), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: UIColor(hex: 0x1F1E1B)
                    ])
                    y += 18

                    if !r.body.isEmpty {
                        (r.body as NSString).draw(
                            with: CGRect(x: margin, y: y, width: textW, height: bodyRect.height),
                            options: [.usesLineFragmentOrigin], attributes: bodyAttr, context: nil)
                        y += bodyRect.height + 4
                    }

                    if includeReminders, let m = r.reminder {
                        "提醒 · \(m.previewLine)".draw(at: CGPoint(x: margin, y: y), withAttributes: [
                            .font: UIFont.systemFont(ofSize: 10),
                            .foregroundColor: UIColor(hex: HINotify.Primary.light)
                        ])
                        y += 14
                    }

                    "更新于 \(DateFormatter.cnFull.string(from: r.updatedAt))　第 \(r.version) 版"
                        .draw(at: CGPoint(x: margin, y: y), withAttributes: [
                            .font: UIFont.systemFont(ofSize: 9),
                            .foregroundColor: UIColor(hex: 0x948C82)
                        ])
                    y += 26
                }
                y += 8
            }
        }
    }
}

// MARK: - 小工具

private extension Category {
    /// PDF 渲染走的是 UIKit 字面值，不能用 SwiftUI 的动态色，
    /// 所以这里给一份浅色档的 hex。**导出的 PDF 是纸质语义，不跟随深色。**
    ///
    /// 色值从共享契约取 —— 以前这里又抄了一遍四个 hex，结果是
    /// 「主 App 换了配色、导出的 PDF 还是旧色」。同一件事只应该有一个定义处。
    var hex: UInt32 {
        switch self {
        case .like:   return HINotify.Cat.like.lightHex
        case .trait_: return HINotify.Cat.trait_.lightHex
        case .care:   return HINotify.Cat.care.lightHex
        case .hate:   return HINotify.Cat.hate.lightHex
        }
    }
}

private extension DateFormatter {
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()

    static let cnFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
        return f
    }()
}
