//
//  ShareViewController.swift
//  分享扩展的入口（系统级分享面板里那一项）
//
//  【它只做三件事】
//    1. 从 `extensionContext.inputItems` 里取出那段文字
//    2. 把它交给 SwiftUI 画的那块面板
//    3. 用户点了「存下这条」→ 丢进共享收件箱 → 关闭自己
//
//  **它不写数据库。** 收件箱（`HIShare.Inbox`）是扩展唯一能碰的存储，
//  落成 `Record` 是主 App 的事。理由见 ShareContract.swift 里 `Inbox` 那段。
//
//  【没有 @main】—— 入口由 Info.plist 的 `NSExtensionPrincipalClass` 指定，
//  两者并存会直接崩（`check-project.py` 会查这一条）。
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    /// 面板高度。系统会按这个值给我们一块地方。
    ///
    /// **不给「自适应高度」**：分享面板的高度是**我们报给系统**的，
    /// 用 `hug_contents` 那套想法在这里不成立 —— 那会让 SwiftUI 按内容算高度，
    /// 而内容里有一个会滚动的区域，两者会互相拉扯。
    /// 定一个够放下「顶栏 + 预览 + 分类 + 按钮」的高度最稳。
    private let panelHeight: CGFloat = 452

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        preferredContentSize = CGSize(width: 0, height: panelHeight)
        Task { [weak self] in await self?.presentComposer() }
    }

    // MARK: - 取文字

    /// 按优先级读：先纯文本，再 URL。
    ///
    /// 两个都试是因为分享来源五花八门 —— 从 Safari 来的是 URL，
    /// 从备忘录 / 微信（原文）来的是纯文本，而有些 App 两样都给。
    /// **取到第一样就走**，不做拼接：把「标题 + 链接」拼起来是替用户改写内容。
    private func extractText() async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return "" }

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let value = await load(provider, as: UTType.plainText.identifier)
                    if let text = value as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let value = await load(provider, as: UTType.url.identifier)
                    if let url = value as? URL { return url.absoluteString }
                }
            }
        }
        return ""
    }

    private func load(_ provider: NSItemProvider, as identifier: String) async -> NSSecureCoding? {
        // `loadItem` 返回的是 NSSecureCoding —— 真机上有来源 App 给不出值时
        // 会抛错，这里退成 nil 让上层继续试下一个 provider，而不是整块空着。
        try? await provider.loadItem(forTypeIdentifier: identifier, options: nil)
    }

    // MARK: - 面板

    @MainActor
    private func presentComposer() async {
        let text = await extractText()

        let root = ShareComposeView(
            text: text,
            onSave: { [weak self] cat in self?.save(text: text, cat: cat) },
            onCancel: { [weak self] in self?.close() }
        )

        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    // MARK: - 存与关

    private func save(text: String, cat: HIShare.Cat) {
        // 整理出来的正文为空时（比如来源只给了个读不出的附件），
        // 什么都不存 —— 存一条空记录比不存更让人困惑。
        if let item = HIShare.Compose.item(from: text, cat: cat) {
            HIShare.Inbox.push(item)
        }
        close()
    }

    /// 关闭自己。**必须调 `completeRequest`** —— 不调的话分享面板会一直挂着，
    /// 而用户已经点了「存下这条」，看起来像卡住了。
    ///
    /// 落库与提示都由主 App 负责：扩展做完就退场，不留任何常驻状态。
    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
