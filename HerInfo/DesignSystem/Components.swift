//
//  Components.swift
//  我的宝宝江林桐 · 复用组件层
//
//  36 屏里的每个组件在这里只有一个实现。视图文件只做「组合」，
//  不自己写样式 —— 这是让 36 屏看起来是一套东西的唯一办法。
//
//  【图标策略】设计稿里 5 个底部 tab 图标是手绘 SVG。到 iOS 上换成 SF Symbols：
//  它们自动跟随字号与字重、矢量不需要切图、且是系统自身的语言。
//  对应关系：首页 house · 分类 square.grid.2x2 · 搜索 magnifyingglass · 提醒 bell
//  （设计稿的手绘版本仍保留在画布上作为「如果不考虑系统一致性」的备选。）
//

import SwiftUI
// PhotoCell / AvatarView 要拿 UIImage 来显示真实图片（PhotoStore 读出来的）。
import UIKit
// PhotoGrid 的拖动排序用 .onDrop(of: [.text], …)，UTType 在这里。
import UniformTypeIdentifiers

// MARK: - 卡片

/// 所有区块的容器。36 屏里的白色圆角块都是它。
struct SCard<Content: View>: View {
    var radius: CGFloat = R.card
    var padding: CGFloat = S.cardPad
    var shadow: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: S.innerGap) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: radius, padding: padding, shadow: shadow)
    }
}

// MARK: - 导航行

/// 二级页顶部的返回 / 标题 / 右侧操作。
/// 标题固定居中，左右两侧各留一个 44×44 的位（不占位的话标题会随按钮出现而偏移）。
struct NavRow<Trailing: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, onBack: (() -> Void)? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(Typo.navTitle)
                .foregroundStyle(C.ink)

            HStack(spacing: 0) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(C.ink2)
                            .frame(width: 44, height: 44)
                    }
                    .pressDown()
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }

                Spacer(minLength: 0)

                trailing
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, S.screen - 6)
    }
}

// MARK: - 胶囊

enum PillStyle {
    /// 规范 `.pill` 的默认写法：**卡面白底 + 1px `--line2` 描边**。分类胶囊（02 屏顶那一排）用它。
    /// 2026-09-14 之前这颗是「分类浅底、无描边」，和画布对不上 ——
    /// 02 屏 PNG 里那三枚未选中胶囊是白的（`#FFFFFF` 19425 像素）加一圈 `#EAE2D8` 描边，
    /// 不是四分类的浅底。
    case normal
    /// `--fill` 底、**无描边**。规范里的 `.pill.flat` / `.pill.tiny` 都是它 ——
    /// 标签、筛选项、搜索范围、编辑器里的标签，全 App 的中性胶囊都走这一档。
    case flat
    case selected
    case dashed
}

/// 胶囊的三档尺寸。**三档都是对着画布量出来的，不是随手分的**：
///
/// | 档 | 字号 | 盒高 | 左右内距 | 画布出处 |
/// |---|---|---|---|---|
/// | `.regular` | 12 | 32 | 12 | `3:136` 分类胶囊 · `15:648` 筛选胶囊（明写 `height 32`） |
/// | `.small`   | 11 | 27 | 10 | `3:254` 编辑器里的标签 · `3:998` 档位标签 · `8:526` 新增标签 |
/// | `.tag`     | 10 | 24 | 10 | `3:154` 记录卡底部那排标签（PNG 实测 4 字 = 60×24） |
///
/// **盒高必须写死，不能靠上下内距撑出来。** 画布上这三种文字的行高是 18 / 15 / 14
/// （≈1.4 倍字号），而 SwiftUI `Font.system(size:)` 的行高只有 ≈1.19 倍
/// （12 号 → 14.3）。用 `padding(.vertical, 7)` 去凑，12 号胶囊只有 28 高，
/// **比设计矮 4pt** —— 全 App 的胶囊都矮一档，这就是 2026-09-14 查出来的那处分歧。
enum PillSize {
    case regular, small, tag

    var height: CGFloat {
        switch self {
        case .regular: return 32
        case .small:   return 27
        case .tag:     return 24
        }
    }

    var hPad: CGFloat {
        switch self {
        case .regular:      return 12
        case .small, .tag:  return 10
        }
    }

    func font(_ medium: Bool) -> Font {
        switch self {
        case .regular: return medium ? Typo.pillSel : Typo.pill
        case .small:   return medium ? Typo.pillSM  : Typo.pillS
        case .tag:     return medium ? Typo.pillTM  : Typo.pillT
        }
    }
}

/// 分类胶囊 / 标签 / 单选胶囊。圆角 100，尺寸见 `PillSize`，四种样子见 `PillStyle`。
struct Pill: View {
    let text: String
    var style: PillStyle = .flat
    var tint: Color = C.primary
    /// `.flat` 的底色。**默认 `C.fill`** —— 画布上记录卡的标签、编辑器里的标签、
    /// 搜索筛选项用的都是这个中性浅槽色（02 屏 PNG 里 `#F1EAE2` 13386 像素、
    /// 误用的 `#FAEDE6` 0 像素）。只有心情档位标签那种「带色标签」才显式传 `C.warm`。
    var soft: Color = C.fill
    var size: PillSize = .regular
    /// 带色标签在画布上是 500（分类标记 `3:334`、档位标签 `3:999` 都是 Medium），
    /// 中性标签一律 400。选中态本身就带 500，不用再传这个。
    var emphasis: Bool = false
    /// `.flat` 的**文字色**。`nil` → `C.ink2`（中性标签）。
    ///
    /// 2026-09-14 补：画布上的「带色标签」是**浅底 + 带色字**，不是深灰字 ——
    /// 心情档位标签 `3:998` 是 `C.warm` 底 + **主色字**，详情页「已挂提醒」`3:157`
    /// 是砂底 + **绿字**。而 `.normal` 时代 `tint` 在非选中态**完全没被用上**，
    /// 那两个调用点传的 `tint:` 一直是死参数，字都被渲染成了 `C.ink2`。
    /// 现在文字色有独立出口，别再用 `tint` 兼职（`tint` 只管 `.selected` 的底和描边）。
    var textTint: Color? = nil
    var onTap: (() -> Void)?

    var body: some View {
        Text(text)
            .font(size.font(style == .selected || emphasis))
            .foregroundStyle(fg)
            .lineLimit(1)
            .padding(.horizontal, size.hPad)
            .frame(height: size.height)
            .background(bg, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, style: strokeStyle)
            )
            .contentShape(Capsule(style: .continuous))
            .onTapGesture { onTap?() }
    }

    private var fg: Color {
        switch style {
        case .selected: return .white
        case .normal:   return C.ink2
        case .flat:     return textTint ?? C.ink2
        case .dashed:   return C.ink3
        }
    }

    private var bg: Color {
        switch style {
        case .selected: return tint
        case .normal:   return C.card
        case .flat:     return soft
        case .dashed:   return .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .selected: return tint
        case .normal:   return C.line2
        case .flat:     return .clear
        case .dashed:   return C.line2
        }
    }

    private var strokeStyle: StrokeStyle {
        style == .dashed
            ? StrokeStyle(lineWidth: 1, dash: [4, 3])
            : StrokeStyle(lineWidth: 1)
    }
}

/// 可换行的胶囊组，同组单选。
/// 用于 32 屏的「每天 / 每周三 / 每月 / 仅一次」—— 选项文字会长短不一，
/// 用胶囊自动换行，不用分段控件（分段控件要求每项等宽且占满一行）。
struct ChipRow<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { opt in
                Pill(text: label(opt),
                     style: selection == opt ? .selected : .flat,
                     onTap: { selection = opt })
            }
        }
    }
}

/// 简易流式布局（从 iOS 16 起 `Layout` 协议可用，这里用它换来「自动换行」）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - 开关

/// 44 × 26 定制开关。不用系统 `Toggle` ——
/// 系统样式的尺寸与配色都是固定的，和这套令牌接不上。
struct SoftSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? C.primary : C.switchTrack)
                .frame(width: 44, height: 26)

            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                // 滑块投影在深色下**保留** —— 它是让圆点「浮在轨道上」的关键，
                // 不是层级阴影。删掉它，圆点就变成贴在轨道上的一个白斑。
                .shadow(color: Shadow.thumbColor,
                        radius: Shadow.thumbRadius, y: Shadow.thumbY)
                .padding(2)
        }
        .frame(width: 44, height: 26)
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - 分段控件

/// 32 屏「定时 / 场景」。两选一、且两个选项要同时可见时用它。
/// 选中态是「底换成卡面 + 主色字」，靠**浮起来**而不是亮起来 ——
/// 用主色实心的话，它和下面那个「保存」主按钮就抢了同一层视觉。
struct SegmentControl<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Namespace private var ns

    /// **必须显式写 init。**
    /// `@Namespace` 是 private 存储属性，而结构体的默认逐成员初始化器
    /// 会因为存在 private 存储属性而**整体降级为 private** ——
    /// 结果是「本文件能编译、别的文件调用时报 inaccessible」，
    /// 而报错位置在调用方，很容易被误判成调用写错了。
    /// `SField`（@FocusState private）与 `PhotoGrid`（private let）同理。
    init(options: [T], label: @escaping (T) -> String, selection: Binding<T>) {
        self.options = options
        self.label = label
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { opt in
                let on = selection == opt
                Text(label(opt))
                    .font(.system(size: 13, weight: on ? .medium : .regular))
                    .foregroundStyle(on ? C.primary : C.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: R.pill, style: .continuous)
                                .fill(C.card)
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { selection = opt }
                    }
            }
        }
        .padding(4)
        .background(C.fill, in: Capsule(style: .continuous))
    }
}

// MARK: - 输入框

/// 单行 14/20 · 内边距 14 · 圆角 16；多行 13/22 · 固定高 104。
/// 聚焦态：描边换主色 + 3px 主色 10% 光晕。
struct SField: View {
    var placeholder: String
    @Binding var text: String
    var multiline: Bool = false
    var height: CGFloat = 104
    @FocusState private var focused: Bool

    /// 显式 init 的理由见 `SegmentControl`（private 的 @FocusState 会让
    /// 逐成员初始化器降级成 private）。
    init(placeholder: String, text: Binding<String>,
         multiline: Bool = false, height: CGFloat = 104) {
        self.placeholder = placeholder
        self._text = text
        self.multiline = multiline
        self.height = height
    }

    var body: some View {
        Group {
            if multiline {
                TextEditor(text: $text)
                    .font(Typo.bodyS)
                    .lineSpacing(22 - 13 * 1.2)
                    .scrollContentBackground(.hidden)
                    .frame(height: height)
            } else {
                TextField(placeholder, text: $text)
                    .font(Typo.body)
            }
        }
        .foregroundStyle(C.ink)
        .tint(C.primary)
        .focused($focused)
        .padding(multiline ? 10 : 14)
        .background(C.bg, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: R.input, style: .continuous)
                .strokeBorder(focused ? C.primary : C.line, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: R.input, style: .continuous)
                .strokeBorder(C.primary.opacity(focused ? 0.10 : 0), lineWidth: 3)
        )
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}

// MARK: - 字段区块

/// 「字段名 + 内容」的一段。03 / 33 / 34 屏里反复出现。
struct FieldBlock<Content: View>: View {
    let label: String
    var caption: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label)
                    .font(Typo.captionM)
                    .foregroundStyle(C.ink3)
                if let caption {
                    Text(caption)
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3.opacity(0.8))
                }
            }
            content
        }
    }
}

// MARK: - 记录卡

/// 内边距 16 · 圆角 20（**记录卡的默认圆角是 20，不是 16**）· 内部纵向 10。整卡可点。
struct RecordCard: View {
    let record: Record
    var onTap: (() -> Void)?

    /// 搜索命中词。非空时把标题与正文里的这一小段标出来（04 屏）。
    /// 默认 nil —— 列表页（02 / 05）不需要它，传了才是搜索。
    var highlight: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(highlighted(record.title, highlight))
                    .font(Typo.cardTitle)
                    .foregroundStyle(C.ink)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if record.pinnedAt != nil {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(C.primary)
                }

                Text(record.updatedAt.relativeCN)
                    .font(Typo.numCaption)
                    .foregroundStyle(C.ink3)
            }

            if !record.body.isEmpty {
                Text(highlighted(record.body, highlight))
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink2)
                    .lineSpacing(6)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            // 配图张数走标量（`record.photoHashes`），不走 `record.photos` 关系。
            // 这一行在列表里**每一条记录都要跑一次**，是关系读取最密集的地方 ——
            // 也就是说它是「墓碑对象」最容易撞上的地方之一（见 `Record.photoHashes`）。
            if !record.tags.isEmpty || !record.photoHashes.isEmpty {
                HStack(spacing: 6) {
                    if !record.photoHashes.isEmpty {
                        Label("\(record.photoHashes.count)", systemImage: "photo")
                            .font(Typo.pill)
                            .foregroundStyle(C.ink3)
                    }
                    ForEach(record.tags, id: \.self) { t in
                        // 记录卡底部的标签：画布上是 10 号（`3:155`），不是 12。
                        Pill(text: t, size: .tag)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: R.card)
        .overlay(alignment: .leading) {
            // 左侧 3px 分类色条：让四类在一屏里能靠颜色扫过去，
            // 而不是逐条读文字。这是列表页唯一的分类线索，所以放在最边缘。
            UnevenRoundedRectangle(
                topLeadingRadius: R.card, bottomLeadingRadius: R.card
            )
            .fill(record.cat.tint)
            .frame(width: 3)
        }
        .contentShape(RoundedRectangle(cornerRadius: R.card, style: .continuous))
        .onTapGesture { onTap?() }
    }
}

// MARK: - 图片格

/// 105 × 105 · 圆角 14 · 横向间距 10。
/// **一行正好 3 个**：105×3 + 10×2 = 335 = 375 − 40（左右各 20）。这是算出来的，不是凑的。
///
/// 这个组件只负责「画格子 + 排顺序」，**不负责去相册取图**：
/// 系统相册选择器属于功能层，长在设计系统里会让它绑死 PhotosUI。
/// 上层（RecordEditorView）把选择结果落成 hash 再传进来。
struct PhotoGrid: View {
    @Binding var hashes: [String]
    var maxCount: Int = Photo.maxPerRecord

    /// 点开了第几张（0 起）。上层在这里调起全屏预览（`PhotoViewerCenter`）。
    ///
    /// **传下标而不是 hash** —— 预览页要能左右翻同一屏里的其他图，
    /// 而「从第几张开始」这件事只有位置表达得出来：同一个 hash 可能同时
    /// 存在于另一条记录的格子里，光凭它定位不到「这一屏的第几个」。
    var onOpen: ((Int) -> Void)?

    /// 「＋」被点。上层在这里打开 PhotosPicker。
    var onAdd: () -> Void = {}

    /// 能不能删、能不能拖排序。详情页只看，编辑器才能改。
    var editable: Bool = true

    @State private var dragging: String?

    private let cell: CGFloat = 105
    private let gap: CGFloat = 10

    /// 显式 init 的理由见 `SegmentControl`（private let 会让
    /// 逐成员初始化器降级成 private）。
    ///
    /// **参数顺序 = 存储属性的声明顺序**（`onOpen` 在 `onAdd` 之前）——
    /// 调用处必须照这个顺序写，否则报 "argument must precede argument"。
    /// 这条规矩有专门一道校验（`.workbuddy/checks/check-argorder.py`）。
    init(hashes: Binding<[String]>,
         maxCount: Int = Photo.maxPerRecord,
         onOpen: ((Int) -> Void)? = nil,
         onAdd: @escaping () -> Void = {},
         editable: Bool = true) {
        self._hashes = hashes
        self.maxCount = maxCount
        self.onOpen = onOpen
        self.onAdd = onAdd
        self.editable = editable
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 3)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: gap) {
            // 内容寻址的 hash 天然唯一，所以 id 可以直接用自己。
            ForEach(hashes, id: \.self) { hash in
                PhotoCell(hash: hash, size: cell,
                          onRemove: editable ? { remove(hash) } : nil)
                    // 拖动排序 —— 把界面上那句「长按可以拖动排序」变成真的。
                    // 用 onDrag/onDrop 而不是 .draggable：后者在 LazyVGrid 里
                    // 拿不到「插到第几个」的位置信息，只能知道「放到了网格里」。
                    .onDrag {
                        guard editable else { return NSItemProvider() }
                        dragging = hash
                        return NSItemProvider(object: hash as NSString)
                    }
                    .onDrop(of: [.text], delegate: PhotoDropDelegate(item: hash,
                                                                     hashes: $hashes,
                                                                     dragging: $dragging))
                    // 点开看大图（见 `PhotoViewer`）。
                    //
                    // 为什么必须有：格子是 `scaledToFill` —— **裁过的**。
                    // 竖拍的照片在格子里只看得到中间一条，「图片是一等公民」
                    // 这句话就落不了地：能看见「这里有张图」，看不到那张图本身。
                    //
                    // 和上面那条 `.onDrag` 不打架：拖要**按住不放**，
                    // 点是一按就抬。两条手势的判定条件本来就不重叠，
                    // 所以「长按拖动排序」和「点开预览」可以同时成立。
                    //
                    // 写在 `.onDrag` / `.onDrop` **之后**（更靠外层）：手指
                    // 一按就抬时由它接住，一旦移动超过容差它就自己让位给拖动。
                    .onTapGesture {
                        guard let onOpen,
                              let i = hashes.firstIndex(of: hash) else { return }
                        onOpen(i)
                    }
            }

            if editable && hashes.count < maxCount {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(C.primary)
                        .frame(width: cell, height: cell)
                        .background(C.bg, in: RoundedRectangle(cornerRadius: R.photo, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: R.photo, style: .continuous)
                                .strokeBorder(C.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                }
                .pressDown()
            }
        }
        // 到 9 张后添加格消失，而不是置灰 —— 不留「还能再加」的错觉。
        .animation(.easeOut(duration: 0.2), value: hashes.count)
    }

    /// 从数组里移除。**不在这里删文件** ——
    /// 这条记录的历史版本可能还引用着它，删早了旧版的图就白了。
    /// 文件交给 `PhotoStore.purgeOrphans` 在启动时按引用全集清。
    private func remove(_ hash: String) {
        hashes.removeAll { $0 == hash }
    }
}

/// 拖动排序的落点逻辑。
///
/// 真正干活的只有 `dropEntered` 里那三行：把被拖的那个从原位置摘出来、
/// 插到当前经过的位置。其余是必须实现但无事可做的协议方法。
private struct PhotoDropDelegate: DropDelegate {
    let item: String
    @Binding var hashes: [String]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let from = dragging,
              from != item,
              let i = hashes.firstIndex(of: from),
              let j = hashes.firstIndex(of: item)
        else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            hashes.move(fromOffsets: IndexSet(integer: i), toOffset: j > i ? j + 1 : j)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
}

/// 一张配图。
///
/// **读不到图时回落到渐变，而不是留一个空白洞** —— 用户看到的应该永远是
/// 「这里有一张图」，而不是「这里坏了」。文件缺失只可能是还没落盘或已被清理，
/// 两种情况都不该在界面上表现成破损。
struct PhotoCell: View {
    let hash: String
    var size: CGFloat = 105
    /// 非 nil 时右上角出现删除角标（只有编辑器会传）。
    var onRemove: (() -> Void)?

    @State private var image: UIImage?

    /// 显式 init 的理由见 `SegmentControl` ——
    /// 只要有一个 `private` 存储属性，逐成员初始化器就会**降级成 private**。
    /// 这个组件眼下只在同一文件里被构造，但下一个用它的人不会知道这件事。
    init(hash: String, size: CGFloat = 105, onRemove: (() -> Void)? = nil) {
        self.hash = hash
        self.size = size
        self.onRemove = onRemove
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [C.primarySoft, C.primaryDeep],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: R.photo, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: R.photo, style: .continuous)
                    .strokeBorder(C.line, lineWidth: 1)
            )

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.45), in: Circle())
                }
                .padding(5)
            }
        }
        // 加载放在 .task 里：磁盘 IO 与解码都不该压在主线程。
        // maxPixel 给 3 倍是为了 Retina 下不糊，同时远小于原图。
        .task(id: hash) {
            image = await PhotoStore.load(hash, maxPixel: size * 3)
        }
    }
}

// MARK: - 头像

/// 圆头像。没设过的时候**不显示灰色剪影，而显示名字的第一个字** ——
/// 剪影是「查无此人」的语义，名字首字是「就是她」。
/// 一个还没填完的档案，最不该看起来像出错了。
struct AvatarView: View {
    var hash: String?
    var name: String
    var size: CGFloat = 72

    @State private var image: UIImage?

    init(hash: String?, name: String, size: CGFloat = 72) {
        self.hash = hash
        self.name = name
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [C.primarySoft, C.primaryDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        Text(String(name.prefix(1)))
                            .font(.system(size: size * 0.36, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: hash) {
            guard let hash, !hash.isEmpty else { image = nil; return }
            image = await PhotoStore.load(hash, maxPixel: size * 3)
        }
    }
}

// MARK: - 键值行

/// 31 / 33 屏的「字段名 · 值」。左右分居，值右对齐。
struct KeyValueRow: View {
    let key: String
    let value: String
    var divider: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(key)
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink3)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(C.ink)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, S.cardPadL)
            .padding(.vertical, 15)

            if divider {
                Rectangle()
                    .fill(C.line)
                    .frame(height: 1)
                    .padding(.leading, S.cardPadL)
            }
        }
    }
}

// MARK: - 底部导航

/// 高 62 · 圆角 36 · 内边距 4 · 卡面底 + 描边。
/// **只有 4 个** —— 设置不在这里，它是从首页右上角压进来的一页。
struct TabPill: View {
    @Binding var selection: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases) { tab in
                let on = selection == tab
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: on ? .semibold : .regular))
                        Text(tab.title)
                            .font(Typo.tabLabel)
                    }
                    .foregroundStyle(on ? .white : C.ink3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: R.tabItem, style: .continuous)
                                .fill(C.primary)
                        }
                    }
                }
                .pressDown()
            }
        }
        .padding(4)
        .frame(height: 62)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.tabOuter, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: R.tabOuter, style: .continuous)
                .strokeBorder(C.line, lineWidth: 1)
        )
        .shadow(color: Shadow.l3Color, radius: Shadow.l3Radius, y: Shadow.l3Y)
        .padding(S.tabInset)
    }
}

enum HomeTab: String, CaseIterable, Identifiable {
    /// **顺序就是 tab 栏里从左到右的顺序。**
    /// 生理期排在「分类」与「搜索」之间 —— 画布 37 屏上就是这个位次：
    /// 它是一件「要经常看一眼」的事，不是设置类的深入口。
    /// 加一个 case，`TabPill` 那边靠 `allCases` 自动多一格，那里不用改。
    case home, category, cycle, search, remind
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:     return "首页"
        case .category: return "分类"
        case .cycle:    return "生理期"
        case .search:   return "搜索"
        case .remind:   return "提醒"
        }
    }

    /// 设计稿是手绘 SVG，这里换 SF Symbols（理由见文件头注释）。
    var symbol: String {
        switch self {
        case .home:     return "house"
        case .category: return "square.grid.2x2"
        // 37 屏那颗是自绘的「一圈点」，SF Symbols 里最接近的语义是循环。
        case .cycle:    return "arrow.triangle.2.circlepath"
        case .search:   return "magnifyingglass"
        case .remind:   return "bell"
        }
    }
}

// MARK: - 空态

/// 06 / 28 / 29 三屏共用。图标底 64×64 圆角、主色图标、一句标题、一段说明。
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(C.warm)
                    .frame(width: 64, height: 64)
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(C.primary)
            }
            .padding(.bottom, 2)

            Text(title)
                .font(Typo.cardTitle)
                .foregroundStyle(C.ink)

            Text(message)
                .font(Typo.bodyS)
                .foregroundStyle(C.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            if let action {
                Button(action: action.run) {
                    Text(action.title)
                        .font(Typo.btn)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 40)
                        .background(C.primary, in: Capsule(style: .continuous))
                }
                .pressDown()
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 轻提示（22 屏）

/// 22 屏那条从顶部滑下来的深色横幅。
///
/// **它是一条通知，不是一个确认框。** 只说「已记下什么」，不报条数、
/// 不问评分、不提示「还差几条」—— 记录这件事一旦变成任务进度，就没人愿意记了。
/// 所以它 3 秒自动走，右边留一个「撤销」就够了。
///
/// 底色是**固定深色**，不跟随主题（浅色下 #2E2823 / 深色下 #3A342E，只差一档）：
/// 它是浮在内容之上的，必须一眼和页面本身区分开。文字用暖白而不是纯白 ——
/// 纯白在暖调深底上会发蓝。
struct ToastBar: View {
    let text: String
    var actionTitle: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(C.primary).frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(uiColor: UIColor(hex: 0xF3EEE8)))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(C.primary)
                }
                .pressDown()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.dual(0x2E2823, 0x3A342E),
                    in: RoundedRectangle(cornerRadius: R.toast, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
    }
}

/// 轻提示的唯一出口。
///
/// **为什么需要一个全局的**：轻提示的触发点散在四个地方（存记录 / 删记录 /
/// 恢复 / 改档案），而它必须只有一条 —— 同时滑下来两条叠在一起是最糟的观感。
/// 谁后弹谁覆盖前一条，倒计时也跟着重置。
///
/// 刻意**不加 `@MainActor`**：加了之后，`ToastLayer` 在属性初始化器里取
/// `ToastCenter.shared` 就落在非隔离上下文里（属性初始化器不继承 `body` 的隔离），
/// Swift 5 模式下会一路报警告。它的每个方法本来就只在主线程被调用。
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    private init() {}

    @Published private(set) var text = ""
    @Published private(set) var actionTitle: String?
    @Published private(set) var visible = false

    /// 每次弹出都换一个值。视图的动画用它驱动 ——
    /// 同样的文案连着弹两次（比如连存两条同名记录）也要重新播一次动画。
    @Published private(set) var token = 0

    private var onAction: (() -> Void)?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String,
              actionTitle: String? = nil,
              onAction: (() -> Void)? = nil) {
        self.text = text
        self.actionTitle = actionTitle
        self.onAction = onAction
        token += 1
        withAnimation(.easeOut(duration: 0.26)) { visible = true }

        hideTask?.cancel()
        // 3 秒后自动收起。用 `Task { @MainActor in }` 而不是裸 `Task {}` ——
        // 后者会跑到全局执行器上，在那里改 `@Published` 属于跨线程改 UI 状态。
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            ToastCenter.shared.dismiss()
        }
    }

    /// 点「撤销」。**先收起再执行** —— 反过来的话，撤销动作里如果又弹了一条
    /// （比如撤销后提示别的话），会被紧接着的 `dismiss()` 一起收掉。
    func performAction() {
        let act = onAction
        dismiss()
        act?()
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        withAnimation(.easeIn(duration: 0.2)) { visible = false }
    }
}

/// 挂在 `RootView` 最上层的那一条。全 App 共用。
struct ToastLayer: View {
    @ObservedObject private var center = ToastCenter.shared

    /// 显式 init 的理由见 `SegmentControl` —— `private` 存储属性会让
    /// 逐成员初始化器降级成 `private`，于是 `RootView` 里那句 `ToastLayer()`
    /// 会直接报 inaccessible（而报错位置在 RootView，不在这个文件里）。
    init() {}

    var body: some View {
        Group {
            if center.visible {
                // 位置写死在 64pt（状态栏 44 + 20）：它不能跟着安全区走，
                // 否则刘海机和老机型上会滑到两个完全不同的高度。
                ToastBar(text: center.text,
                         actionTitle: center.actionTitle,
                         onAction: { center.performAction() })
                    .padding(.horizontal, S.screen)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: center.token)
        .allowsHitTesting(center.visible)
    }
}

// MARK: - 删除二次确认（26 屏）

/// 26 屏那块面板本身。外面还有遮罩，见 `TrashConfirmOverlay`。
///
/// 两条说明缺一不可，因为它们回答的是两个不同的问题：
///   · 「挂着提醒会一起取消」= **后果**。用户怕的不是删除，是删完才发现提醒也没了
///   · 「30 天内都能找回」= **承诺**。有退路，流程才敢只确认一次
/// 少了上面那条，用户会在删完之后被吓一跳；少了下面那条，他就得停下来犹豫。
struct TrashConfirmPanel: View {
    let title: String
    /// 「喜好 · 9 月 8 日记下 · 挂着 1 个提醒」。
    let meta: String
    /// > 0 才显示「会一起取消」那条。没有提醒却写「提醒会取消」，是凭空吓人。
    let reminderCount: Int
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("删掉这条记录？")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(C.ink)
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15))
                        .foregroundStyle(C.ink3)
                        .frame(width: 28, height: 28)
                }
            }

            // 被删的那条记录本身。**把它摆出来，而不是只问一句「确定吗」** ——
            // 用户需要在按下之前再看一眼自己删的是什么。
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(C.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(C.bg, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: R.input, style: .continuous)
                    .strokeBorder(C.line, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                if reminderCount > 0 {
                    ConfirmNote(text: "这条记录挂着的提醒会一起取消。", tone: .consequence)
                }
                ConfirmNote(text: "删掉后 30 天内都能在回收站找回。", tone: .promise)
            }

            HStack(spacing: 10) {
                Button(action: onCancel) { Text("先留着").secondaryButtonStyle() }
                    .pressDown()

                Button(action: onConfirm) {
                    Text("删掉")
                        .font(Typo.btn)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(C.danger, in: Capsule(style: .continuous))
                }
                .pressDown()
            }

            Text("回收站的入口在 设置 › 数据")
                .font(Typo.caption)
                .foregroundStyle(C.ink3)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 24, trailing: 20))
        // 圆角只画上面两个 —— 下面两个角在屏幕外。用 `RoundedRectangle` 再让
        // 宿主裁掉下缘，比 `UnevenRoundedRectangle` 少一层版本风险。
        .background(C.card, in: RoundedRectangle(cornerRadius: R.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, y: -4)
    }
}

/// 面板里那两条说明。颜色分开是有意的：
/// 后果用砂色（提醒），承诺用暖色（主色）—— 一眼能分出「坏消息」和「别担心」。
struct ConfirmNote: View {
    enum Tone { case consequence, promise }

    let text: String
    let tone: Tone

    private var icon: String {
        switch tone {
        case .consequence: return "exclamationmark.circle"
        case .promise:     return "plus.circle"
        }
    }

    private var fg: Color {
        switch tone {
        case .consequence: return Color(uiColor: UIColor(hex: 0x8A6532))
        case .promise:     return C.primary
        }
    }

    private var bg: Color {
        switch tone {
        case .consequence: return C.sand
        case .promise:     return C.warm
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(fg)
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(fg)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 遮罩 + 面板。挂在宿主屏最外层。
///
/// 遮罩用 `Color.black.opacity()` 而不是整个视图的 `.opacity()` ——
/// 后者会把面板一起压淡，看起来像「半透明地浮着」。
struct TrashConfirmOverlay: View {
    let title: String
    let meta: String
    let reminderCount: Int
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            TrashConfirmPanel(title: title,
                              meta: meta,
                              reminderCount: reminderCount,
                              onCancel: onCancel,
                              onConfirm: onConfirm)
                .transition(.move(edge: .bottom))
        }
    }
}

// MARK: - 分类色点

/// 首页四条分类的入口。色点是这套设计的分类语言：一屏之内靠颜色分辨四类。
struct CategoryDot: View {
    let cat: Category
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(cat.tint)
                .frame(width: 8, height: 8)

            Text(cat.title)
                .font(Typo.body)
                .foregroundStyle(C.ink)

            Spacer(minLength: 0)

            Text("\(count)")
                .font(Typo.numCaption)
                .foregroundStyle(C.ink3)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(C.ink3.opacity(0.6))
        }
        .padding(.horizontal, S.cardPad)
        .frame(height: 48)
    }
}

// MARK: - 工具

/// 把命中的那段词标出来（04 屏记录卡上那几处浅底）。
///
/// 用 `AttributedString` 的**背景色**，不是描边、不是下划线：
///
///  · 描边会在中文笔画密集的地方把字糊掉（「玫瑰」两字描一圈就成一团）
///  · 下划线和汉字的字脚打架，13px 下看着像排版错位
///  · 一块浅底是唯一在 13px 中文上仍然读得清、且不改变字形的做法
///
/// `term` 为空、或正文里根本没有它时**原样返回**。
/// 绝不退化成「给整句加底色」——那会让「命中在哪里」这件事彻底失效，
/// 而搜索页最该回答的就是这个问题。
///
/// 匹配规则刻意与搜索用的 `localizedStandardContains` 对齐
/// （忽略大小写与变音符）。两边不一致就会出「搜得到、但高亮不出来」，
/// 那比不高亮更让人怀疑结果。
func highlighted(_ text: String, _ term: String?) -> AttributedString {
    var out = AttributedString(text)
    guard let term, !term.isEmpty else { return out }

    let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    var from = text.startIndex
    while from < text.endIndex,
          let hit = text.range(of: term, options: opts, range: from..<text.endIndex) {
        if let lo = AttributedString.Index(hit.lowerBound, within: out),
           let hi = AttributedString.Index(hit.upperBound, within: out) {
            out[lo..<hi].backgroundColor = C.hiBg
            out[lo..<hi].foregroundColor = C.hiInk
        }
        from = hit.upperBound
    }
    return out
}

extension Date {
    /// 「3 天前」「今天」「上周」。列表页的时间列全都用它。
    var relativeCN: String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: self, to: .now).day ?? 0
        switch days {
        case ..<0:  return "刚刚"
        case 0:     return "今天"
        case 1:     return "昨天"
        case 2...6: return "\(days) 天前"
        case 7...13: return "上周"
        case 14...29: return "\(days / 7) 周前"
        case 30...364: return "\(days / 30) 个月前"
        default:    return "\(days / 365) 年前"
        }
    }

    /// 「20:00」。用等宽数字，避免不同数字宽度把整行顶得抖动。
    var hhmm: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }

    /// 「3月14日」。生日用它 —— 生日不带年份。
    var monthDayCN: String {
        let c = Calendar.current.dateComponents([.month, .day], from: self)
        return "\(c.month ?? 1)月\(c.day ?? 1)日"
    }

    /// 「2025年7月10日」。在一起的日子用它 —— 这个必须带年份。
    var yearMonthDayCN: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return "\(c.year ?? 2026)年\(c.month ?? 1)月\(c.day ?? 1)日"
    }
}
