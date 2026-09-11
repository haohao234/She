//
//  ShareComposeView.swift
//  分享扩展里那块面板（系统分享面板弹出时看到的样子）
//
//  【为什么不复用 App 里的 Pill / ChipRow / Typo】
//  那些在 `Components.swift` 与 `Tokens.swift` 里，都是主 App 的设计系统。
//  把它们链进扩展有两个代价，都不划算：
//    ① 为了让扩展编译过，那块设计系统就再也改不动了 ——
//       它一旦引了主 App 专属的东西（PhotosUI、某个 @Model 类型），扩展先编译失败；
//    ② 分享面板是**系统级**的。用户在系统里设了特大字体，这块面板就该跟着变大 ——
//       而这只能靠系统语义字体（`.headline` / `.footnote`）拿到，
//       照抄 App 里那几个固定字号反而会让它在大字体下变成罐头。
//
//  【但品牌色必须共用】
//  主色与四个分类色取自 `HINotify`，**一行 hex 都不写**。
//  与锁屏通知、PDF 导出同源 —— 任何一处自己抄一遍，
//  就会出现「主 App 换了色、分享面板还是旧的」。
//

import SwiftUI
import UIKit

struct ShareComposeView: View {

    /// 已经过 `HIShare.Compose.normalize` 之前的原文。
    let text: String
    let onSave: (HIShare.Cat) -> Void
    let onCancel: () -> Void

    /// 用户点了哪一类。**nil 就是还没点** —— 不给默认值，
    /// 因为「替用户先选一个」等于伪造他的判断。
    @State private var picked: HIShare.Cat?

    /// 显式 init（与主 App 组件同一条约定）。
    /// 有 `@State` 这类属性包装器的视图，逐成员初始化器的可访问性
    /// 会跟着属性包装器走；手写一个最省心，也免得将来加一个 private 属性
    /// 就把 init 降级成 private（报错位置还在调用方，不在这个文件里）。
    init(text: String,
         onSave: @escaping (HIShare.Cat) -> Void,
         onCancel: @escaping () -> Void) {
        self.text = text
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var body_: String { HIShare.Compose.normalize(text) }
    private var isEmptyShare: Bool { body_.isEmpty }
    private var canSave: Bool { picked != nil && !isEmptyShare }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isEmptyShare { emptyHint } else { previewCard }
                    if !isEmptyShare { categoryPicker }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 14)
            }

            footer
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - 顶栏

    private var header: some View {
        ZStack {
            Text("存进她的信息本")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))

            HStack {
                Button("取消") { onCancel() }
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    // MARK: - 正文预览

    /// 只显示、不编辑。
    ///
    /// **不在这里做输入框**：分享扩展里的键盘会把这块面板顶得只剩两行，
    /// 而「改文字」在 App 的记录里做得更舒服（那里有分类、标签、配图、
    /// 历史版本一起在）。所以这里只让用户确认「读到的是不是这段」。
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(body_)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .label))
                .lineSpacing(4)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 「原文 · N 字」不是装饰，是在告诉用户「这里一个字都没改过」——
            // 它对应 ShareContract.swift 里 normalize 那句承诺。
            HStack(spacing: 5) {
                Text("原文")
                Text("·")
                Text("\(body_.count) 字")
            }
            .font(.caption)
            .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 归类

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("归到哪一类？")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(HIShare.Cat.allCases, id: \.self) { cat in
                    chip(cat)
                }
            }

            // 安慰用户「现在不必想清楚」—— 这才是他会需要的承诺。
            // （不是「请选对」：分类选错了改起来只要一秒，卡在这里才真的费事。）
            Text("存下来之后，分类和文字都还能改。")
                .font(.caption)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
    }

    private func chip(_ cat: HIShare.Cat) -> some View {
        let on = picked == cat
        return Button {
            picked = cat
        } label: {
            Text(cat.title)
                .font(on ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(on ? Color.white : Color(uiColor: .label))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(on ? brandColor : Color(uiColor: .secondarySystemBackground),
                            in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(on ? Color.clear : Color(uiColor: .separator), lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 读不到文字时

    /// 这是**必须存在的一屏**：来源 App 只给了一个我们读不出的附件时，
    /// 空白面板会让人以为扩展坏了。这里如实说明，并给一条真的走得通的路 ——
    /// 与主 App 的 06 空态、10 屏空提示是同一条纪律（不写「暂无数据」）。
    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这次分享里没有读到文字")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))

            Text("这里只收文字和网址。图片可以先存到相册，再回到 App 里加进那条记录。")
                .font(.footnote)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 底栏

    /// 按钮文案**随状态变**，而不是只有一个灰掉的「保存」：
    /// 「先选一个分类」告诉用户差什么，「没有读到文字」告诉他这次没戏。
    /// 一个灰按钮什么也不说，用户只会反复点它。
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color(uiColor: .separator))

            Button {
                if let cat = picked { onSave(cat) }
            } label: {
                Text(buttonTitle)
                    .font(.headline)
                    .foregroundStyle(canSave ? Color.white : Color(uiColor: .secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(canSave ? brandColor : Color(uiColor: .tertiarySystemFill),
                                in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var buttonTitle: String {
        if isEmptyShare { return "没有读到文字" }
        return picked == nil ? "先选一个分类" : "存下这条"
    }

    // MARK: - 取色

    /// 主色。取自共享契约的浅 / 深两档，跟随系统外观。
    ///
    /// 为什么不 `import` Tokens.swift 拿 `C.primary`：
    /// 那个文件还带着整套令牌（字体 / 间距 / 圆角 / 阴影），
    /// 为了一个颜色把设计系统整个链进扩展不划算 —— 代价见本文件开头。
    ///
    /// 为什么不用 `Color(uiColor:)` 的现成写法：契约里存的是 `UInt32`（0xC0614A），
    /// 而 `UIColor(hex:)` 那个便利初始化器在主 App 的 Tokens.swift 里，
    /// 扩展拿不到，所以这里就地拆一次字节。**拆的是契约给的数，不是抄的色。**
    private var brandColor: Color {
        Color(uiColor: UIColor { trait in
            let v = trait.userInterfaceStyle == .dark
                ? HINotify.Primary.dark
                : HINotify.Primary.light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
