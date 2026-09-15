//
//  BrowseView.swift
//  对应画布 02 分类浏览 · 喜好 / 25 排序与置顶 / 31 记录详情
//
//  分类页的核心不是「列表」，是「换类的成本要低」——
//  四个胶囊横排在顶部，一屏之内不用退出就能换一类。
//

import SwiftUI
import SwiftData

// MARK: - 02 分类浏览

struct BrowseView: View {
    @Binding var path: [Route]

    @Query(filter: #Predicate<Record> { $0.deletedAt == nil },
           sort: \Record.updatedAt, order: .reverse)
    private var all: [Record]

    /// 当前分类是「这一屏的临时状态」，不进数据库 ——
    /// 它和 25 屏的长期排序偏好、30 屏的筛选草稿是三份不同的状态，不能互相写回。
    @State private var cat: Category = .like

    /// 排序偏好。25 屏改的就是它。
    @AppStorage("listSort") private var sortRaw: String = ListSort.recent.rawValue

    /// 26 屏：长按哪一条、点了「删掉」、等着确认的那条。
    @State private var pendingDelete: Record?

    @Environment(\.modelContext) private var ctx

    private var sort: ListSort { ListSort(rawValue: sortRaw) ?? .recent }

    private var list: [Record] {
        let base = all.filter { $0.cat == cat }
        switch sort {
        case .recent:   return base.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest:   return base.sorted { $0.updatedAt < $1.updatedAt }
        case .pinned:   return base.sorted {
            ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast)
        }
        }
    }

    /// 空态里那个「新建一条」按钮。**整个 App 一条记录都没有时不显示** ——
    /// 那种情况下三张起手卡就是入口，再给一个按钮只是多一个要读的东西。
    ///
    /// 显式写出返回类型，而不是在调用处写 `firstEver ? nil : (title:…, run:…)`：
    /// `nil` 和元组放进同一个三元里，Swift 的类型推断偶尔会推不出来，
    /// 而报错会落在离现场很远的地方。这里写清楚，调用处就只剩一个 `emptyAction`。
    private var emptyAction: (title: String, run: () -> Void)? {
        guard !all.isEmpty else { return nil }
        return (title: "新建一条", run: { path.append(.recordEdit(id: "")) })
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {

                // 顶行：返回 + 标题 + 排序
                HStack(spacing: 10) {
                    // 「分类」既是 tab 的根、也会被 push 进来。
                    // 根的时候**不显示返回键**（而不是显示一个点了会崩的键）——
                    // 对空数组调 removeLast() 是直接 fatalError，
                    // 而它崩的时机是「用户点了分类 tab 又点了返回」，看起来完全不像 bug。
                    if path.isEmpty {
                        Color.clear.frame(width: 30, height: 44)
                    } else {
                        Button { path.removeLast() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(C.ink)
                                .frame(width: 30, height: 44)
                        }
                        .pressDown()
                    }

                    Text("分类记录")
                        .font(Typo.pageTitle)
                        .foregroundStyle(C.ink)

                    Spacer(minLength: 0)

                    Button { path.append(.sortPin) } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 17))
                            .foregroundStyle(C.ink2)
                            .frame(width: 30, height: 44)
                    }
                    .pressDown()
                }
                .padding(.horizontal, S.screen - 4)

                // 四个分类胶囊。横排不滚动 ——
                // 四个中文短标签在这个宽度里放得下，横滑会藏住后面两个。
                // 未选中是 `.normal`（白底 + `--line2` 描边），**不带分类浅底** ——
                // 02 屏 PNG 里那三枚是白的，浅底那一套是给别处用的。
                HStack(spacing: 8) {
                    ForEach(Category.allCases) { c in
                        Pill(text: c.title,
                             style: cat == c ? .selected : .normal,
                             tint: c.tint) {
                            withAnimation(.easeOut(duration: 0.18)) { cat = c }
                        }
                    }
                }
                .padding(.horizontal, S.screen)

                // 列表标题 + 计数
                HStack {
                    Text(cat.title)
                        .font(Typo.cardTitle)
                        .foregroundStyle(C.ink)
                    Spacer()
                    Text("\(list.count) 条 · \(sort.metaLabel)")
                        .font(Typo.numCaption)
                        .foregroundStyle(C.ink3)
                }
                .padding(.horizontal, S.screen)
                .padding(.top, 18)
                .padding(.bottom, 10)

                ScrollView {
                    if list.isEmpty {
                        // 06 空态。两层判断要分开：
                        //  · 标题 —— 按**当前分类**换（「还没有记下她的喜好」…）
                        //  · 起手卡组 —— 只在**整个 App 一条都没有**时给
                        //
                        // 这不是同一个条件。一个有 30 条记录的人切到空的「讨厌的事」，
                        // 他要的是「换个分类看看」，不是被问一次「她爱吃什么」。
                        // 三张卡是给第一次打开 App 的人的开场白，文案里
                        // 「先从这三件开始」的「开始」就是这个意思。
                        let firstEver = all.isEmpty

                        VStack(spacing: 0) {
                            EmptyState(
                                symbol: "square.grid.2x2",
                                title: cat.emptyTitle,
                                message: firstEver
                                    ? "想到就记一条，先从这三件开始"
                                    : "看到什么就记一句，\n下次翻回来的时候你会庆幸记了",
                                action: emptyAction
                            )

                            if firstEver {
                                StarterCardGroup { topic in
                                    path.append(.starterEdit(topic: topic.rawValue))
                                }
                                .padding(.horizontal, S.screen)
                                .padding(.bottom, 24)
                            }
                        }
                    } else {
                        VStack(spacing: S.innerGapL) {
                            ForEach(list) { r in
                                RecordCard(record: r) {
                                    path.append(.recordDetail(id: r.id))
                                }
                                // 26 屏那条「长按记录 → 删掉」的入口。
                                // **长按，而不是每行摆一个删除按钮** —— 破坏性动作
                                // 不该出现在一屏能划过的十几个位置上。
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDelete = r
                                    } label: {
                                        Label("删掉", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, S.screen)
                        .padding(.bottom, 16)
                    }
                }
            }

            // 浮起按钮。放在导航上方 108 处，不是贴在屏底 ——
            // 贴底会被底部导航盖住一半。
            Button { path.append(.recordEdit(id: "")) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [C.primarySoft, C.primaryDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    // 全稿唯一的主色投影 = 规范的 L4。2026-09-14 收进 `Shadow.primaryGlow*`，
                    // 之前只有这一处用得上，所以数字一直散在这里、规范那条在代码里没有落点。
                    .shadow(color: Shadow.primaryGlowColor,
                            radius: Shadow.primaryGlowRadius,
                            y: Shadow.primaryGlowY)
            }
            .pressDown()
            .padding(.trailing, S.screen)
            .padding(.bottom, 108)
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let r = pendingDelete {
                TrashConfirmOverlay(
                    title: r.title,
                    meta: r.trashMeta,
                    reminderCount: r.liveReminderCount,
                    onCancel: { pendingDelete = nil },
                    onConfirm: {
                        let target = r
                        pendingDelete = nil
                        moveToTrash(target)
                    })
            }
        }
        .animation(.easeOut(duration: 0.24), value: pendingDelete?.id)
    }

    /// 删掉之后给一条带「撤销」的轻提示。
    ///
    /// **撤销是「只确认一次」唯一的兜底。** 26 屏敢只做一次确认，
    /// 靠的就是有退路；而退路得看得见才算数 —— 不能指望用户自己想起来
    /// 去「设置 › 数据 › 回收站」里翻回来。
    private func moveToTrash(_ r: Record) {
        HerInfoStore.moveToTrash(r, in: ctx)
        ToastCenter.shared.show("已移到回收站 · 30 天内可恢复",
                                actionTitle: "撤销") {
            HerInfoStore.restoreFromTrash(r, in: ctx)
        }
    }
}

/// 排序方式。**与 30 屏的搜索筛选是两份状态** ——
/// 这份是长期偏好（写回设置），那份只活在一次搜索里（关掉即失效）。
enum ListSort: String, CaseIterable, Identifiable {
    case recent, oldest, pinned
    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "最近更新"
        case .oldest: return "最早记录"
        case .pinned: return "置顶优先"
        }
    }

    var metaLabel: String {
        switch self {
        case .recent: return "按更新时间"
        case .oldest: return "按创建时间"
        case .pinned: return "置顶在最前"
        }
    }
}

// MARK: - 25 排序与置顶

struct SortPinView: View {
    @Binding var path: [Route]
    @Query(filter: #Predicate<Record> { $0.deletedAt == nil }) private var records: [Record]
    @AppStorage("listSort") private var sortRaw: String = ListSort.recent.rawValue

    var body: some View {
        VStack(spacing: 0) {
            NavRow("排序与置顶", onBack: { path.removeLast() })

            ScrollView {
                VStack(alignment: .leading, spacing: S.cardGap) {

                    SCard {
                        Text("排序方式")
                            .font(Typo.captionM)
                            .foregroundStyle(C.ink3)

                        ForEach(ListSort.allCases) { s in
                            Button {
                                sortRaw = s.rawValue
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title)
                                            .font(Typo.body)
                                            .foregroundStyle(C.ink)
                                        Text(s.metaLabel)
                                            .font(Typo.caption)
                                            .foregroundStyle(C.ink3)
                                    }
                                    Spacer(minLength: 0)
                                    // 单选圆：选中是实心主色 + 白点
                                    ZStack {
                                        Circle()
                                            .strokeBorder(sortRaw == s.rawValue ? C.primary : C.line2,
                                                          lineWidth: 1.5)
                                            .frame(width: 20, height: 20)
                                        if sortRaw == s.rawValue {
                                            Circle().fill(C.primary).frame(width: 20, height: 20)
                                            Circle().fill(.white).frame(width: 7, height: 7)
                                        }
                                    }
                                }
                                .padding(.vertical, 10)
                            }
                            .pressDown()
                        }
                    }

                    SCard {
                        HStack {
                            Text("已置顶")
                                .font(Typo.captionM)
                                .foregroundStyle(C.ink3)
                            Spacer()
                            // 封顶 3 条：置顶一多就等于没置顶。
                            Text("\(records.filter { $0.pinnedAt != nil }.count) / 3")
                                .font(Typo.numCaption)
                                .foregroundStyle(C.ink3)
                        }

                        Text("长按任意一条记录可以置顶它。置顶的会一直排在列表最前，最多 3 条。")
                            .font(Typo.bodyS)
                            .foregroundStyle(C.ink2)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, S.screen)
                .padding(.vertical, 8)
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 31 记录详情

struct RecordDetailView: View {
    @Binding var path: [Route]
    let recordID: String

    @Environment(\.modelContext) private var ctx
    @Query private var records: [Record]
    @Query private var revisions: [Revision]

    /// 26 屏：确认面板开着没有。
    @State private var confirmingDelete = false

    init(path: Binding<[Route]>, recordID: String) {
        self._path = path
        self.recordID = recordID
        _records = Query(filter: #Predicate<Record> { $0.id == recordID })
    }

    private var record: Record? { records.first }

    /// 配图，按 order 排 —— 那个顺序是用户在编辑器里一张张拖出来的，
    /// 不是随机的。详情页如果按数据库返回顺序画，编辑时的拖动就白做了。
    ///
    /// 出去重是必须的：`PhotoGrid` 拿 hash 当 `ForEach` 的 id，
    /// 重复值会让 SwiftUI 进「不保证行为」的状态（并打
    /// 「the ID … occurs multiple times」），详情页的拖动排序也一定定位错。
    /// 理由见 `Photo.uniqueHashes`。
    private var photoHashes: [String] {
        Photo.uniqueHashes((record?.photos ?? []).sorted { $0.order < $1.order }.map(\.hash))
    }

    private var history: [Revision] {
        revisions.filter { $0.recordID == recordID }.sorted { $0.version > $1.version }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavRow("记录详情", onBack: { path.removeLast() }) {
                Button { path.append(.recordEdit(id: recordID)) } label: {
                    Text("编辑")
                        .font(Typo.pillSel)
                        .foregroundStyle(C.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(C.fill, in: Capsule(style: .continuous))
                }
                .pressDown()
            }

            if let r = record {
                ScrollView {
                    VStack(alignment: .leading, spacing: S.cardGap) {

                        SCard {
                            HStack(spacing: 8) {
                                // 分类标记：画布上是 10 号、500（`3:334`），实心分类色 + 白字。
                                Pill(text: r.cat.title, style: .selected,
                                     tint: r.cat.tint, size: .tag)
                                if let m = r.reminder, m.isOn {
                                    // 顺序必须跟 Pill 的存储属性一致
                                    // （text / style / tint / soft / size / emphasis / textTint / onTap），
                                    // 写成 size:…, tint:… 会报 "argument 'tint' must precede argument 'size'"。
                                    // 「已挂提醒」在画布上是 10 号 Regular（`3:157`），**砂底绿字** ——
                                    // 字色走 `textTint`，不是 `tint`（`tint` 只管 `.selected` 的底与描边）。
                                    Pill(text: m.kind == .date ? "已挂提醒" : "到\(m.placeName ?? "那")提醒",
                                         soft: C.moss, size: .tag, textTint: C.care)
                                }
                                Spacer(minLength: 0)
                            }

                            Text(r.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(C.ink)

                            // 与 34 屏同一条判断：**图片紧跟标题，不塞在正文下面**。
                            // 一条「她说想要这个」配上照片，半年后还认得出是哪一款；
                            // 纯文字不能。详情页是只读的，所以不给删除角标、也不给添加格。
                            if !photoHashes.isEmpty {
                                PhotoGrid(hashes: .constant(photoHashes), editable: false)
                            }

                            Text(r.body)
                                .font(Typo.bodyS)
                                .foregroundStyle(C.ink2)
                                .lineSpacing(8)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 6) {
                                ForEach(r.tags, id: \.self) { t in
                                    Pill(text: t, size: .tag)
                                }
                            }
                        }

                        if let m = r.reminder {
                            SCard {
                                Text("提醒")
                                    .font(Typo.captionM)
                                    .foregroundStyle(C.ink3)
                                Text(m.previewLine)
                                    .font(Typo.bodyS)
                                    .foregroundStyle(C.ink)
                                Text(m.kind == .date
                                     ? "\(m.repeatRule.title) \(m.time.hhmm)"
                                     : "到 \(m.placeName ?? "") 附近 · 半径 \(Int(m.radius)) 米")
                                    .font(Typo.numCaption)
                                    .foregroundStyle(C.ink3)
                            }
                        }

                        // 记录信息
                        VStack(spacing: 0) {
                            KeyValueRow(key: "分类", value: r.cat.title)
                            KeyValueRow(key: "创建于", value: r.createdAt.relativeCN, divider: true)
                            KeyValueRow(key: "更新于", value: r.updatedAt.relativeCN, divider: true)
                            KeyValueRow(key: "当前版本", value: "第 \(r.version) 版", divider: true)
                        }
                        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: R.card, style: .continuous)
                                .strokeBorder(C.line, lineWidth: 1)
                        )

                        // 07 屏的入口。**整块可点，不给每行配箭头** ——
                        // 点哪一行都是去同一页（到那页再挑跟哪一版比），
                        // 三行各挂一个箭头只会让人以为它们去三个地方。
                        if !history.isEmpty {
                            Button { path.append(.versionHistory(id: recordID)) } label: {
                                SCard {
                                    HStack {
                                        Text("历史版本")
                                            .font(Typo.captionM)
                                            .foregroundStyle(C.ink3)
                                        Spacer()
                                        Text("\(history.count) 个")
                                            .font(Typo.numCaption)
                                            .foregroundStyle(C.ink3)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(C.ink3.opacity(0.6))
                                    }
                                    ForEach(history.prefix(3)) { v in
                                        HStack {
                                            Text("第 \(v.version) 版")
                                                .font(Typo.bodyS)
                                                .foregroundStyle(C.ink)
                                            Spacer()
                                            Text(v.at.relativeCN)
                                                .font(Typo.numCaption)
                                                .foregroundStyle(C.ink3)
                                        }
                                    }
                                    if history.count > 3 {
                                        Text("左右对比全部 \(history.count) 个版本")
                                            .font(Typo.caption)
                                            .foregroundStyle(C.ink3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .pressDown()
                        }

                        // 删除。**刻意放在最后、且用危险色** ——
                        // 它离正文最远，因为手滑的成本取决于中间隔了多少东西。
                        Button {
                            // 26 屏：删除是破坏性动作，**先弹确认面板**。
                            // 以前这里直接置 deletedAt 就 pop —— 手滑一下记录就进了回收站，
                            // 而 26 屏那两条说明（会连带失去什么 / 有 30 天退路）一条都看不到。
                            confirmingDelete = true
                        } label: {
                            Text("删除这条记录")
                                .font(Typo.btn)
                                .foregroundStyle(C.danger)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(C.card, in: Capsule(style: .continuous))
                                .overlay(Capsule(style: .continuous).strokeBorder(C.line2, lineWidth: 1))
                        }
                        .pressDown()
                    }
                    .padding(.horizontal, S.screen)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if confirmingDelete, let r = record {
                TrashConfirmOverlay(
                    title: r.title,
                    meta: r.trashMeta,
                    reminderCount: r.liveReminderCount,
                    onCancel: { confirmingDelete = false },
                    onConfirm: {
                        confirmingDelete = false
                        moveToTrash(r)
                    })
            }
        }
        .animation(.easeOut(duration: 0.24), value: confirmingDelete)
    }

    /// 删掉 + 一条带「撤销」的轻提示。撤销是「只确认一次」唯一的兜底。
    private func moveToTrash(_ r: Record) {
        HerInfoStore.moveToTrash(r, in: ctx)
        path.removeLast()
        ToastCenter.shared.show("已移到回收站 · 30 天内可恢复",
                                actionTitle: "撤销") {
            HerInfoStore.restoreFromTrash(r, in: ctx)
        }
    }
}
