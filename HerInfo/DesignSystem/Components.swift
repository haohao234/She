//
//  Components.swift
//  她的信息本 · 复用组件层
//
//  36 屏里的每个组件在这里只有一个实现。视图文件只做「组合」，
//  不自己写样式 —— 这是让 36 屏看起来是一套东西的唯一办法。
//
//  【图标策略】设计稿里 4 个底部 tab 图标是手绘 SVG。到 iOS 上换成 SF Symbols：
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

enum PillStyle { case normal, selected, dashed }

/// 分类胶囊 / 标签 / 单选胶囊。内边距 7·12、圆角 100、字号 12。
struct Pill: View {
    let text: String
    var style: PillStyle = .normal
    var tint: Color = C.primary
    var soft: Color = C.warm
    var tiny: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Text(text)
            .font(style == .selected ? Typo.pillSel : Typo.pill)
            .foregroundStyle(fg)
            .padding(.horizontal, tiny ? 9 : 12)
            .padding(.vertical, tiny ? 4 : 7)
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
        case .dashed:   return C.ink3
        }
    }

    private var bg: Color {
        switch style {
        case .selected: return tint
        case .normal:   return soft
        case .dashed:   return .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .selected: return tint
        case .normal:   return .clear
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
                     style: selection == opt ? .selected : .normal,
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(record.title)
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
                Text(record.body)
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink2)
                    .lineSpacing(6)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if !record.tags.isEmpty || !record.photos.isEmpty {
                HStack(spacing: 6) {
                    if !record.photos.isEmpty {
                        Label("\(record.photos.count)", systemImage: "photo")
                            .font(Typo.pill)
                            .foregroundStyle(C.ink3)
                    }
                    ForEach(record.tags, id: \.self) { t in
                        Pill(text: t, tiny: true)
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

    /// 「＋」被点。上层在这里打开 PhotosPicker。
    var onAdd: () -> Void = {}

    /// 能不能删、能不能拖排序。详情页只看，编辑器才能改。
    var editable: Bool = true

    @State private var dragging: String?

    private let cell: CGFloat = 105
    private let gap: CGFloat = 10

    /// 显式 init 的理由见 `SegmentControl`（private let 会让
    /// 逐成员初始化器降级成 private）。
    init(hashes: Binding<[String]>,
         maxCount: Int = Photo.maxPerRecord,
         editable: Bool = true,
         onAdd: @escaping () -> Void = {}) {
        self._hashes = hashes
        self.maxCount = maxCount
        self.editable = editable
        self.onAdd = onAdd
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
    case home, category, search, remind
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:     return "首页"
        case .category: return "分类"
        case .search:   return "搜索"
        case .remind:   return "提醒"
        }
    }

    /// 设计稿是手绘 SVG，这里换 SF Symbols（理由见文件头注释）。
    var symbol: String {
        switch self {
        case .home:     return "house"
        case .category: return "square.grid.2x2"
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
