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
                HStack(spacing: 8) {
                    ForEach(Category.allCases) { c in
                        Pill(text: c.title,
                             style: cat == c ? .selected : .normal,
                             tint: c.tint,
                             soft: c.soft) {
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
                        EmptyState(symbol: "square.grid.2x2",
                                   title: "这个分类还没有记录",
                                   message: "看到什么就记一句，\n下次翻回来的时候你会庆幸记了",
                                   action: ("新建一条", { path.append(.recordEdit(id: "")) }))
                    } else {
                        VStack(spacing: S.innerGapL) {
                            ForEach(list) { r in
                                RecordCard(record: r) {
                                    path.append(.recordDetail(id: r.id))
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
                    .shadow(color: C.primary.opacity(0.35), radius: 14, y: 6)
            }
            .pressDown()
            .padding(.trailing, S.screen)
            .padding(.bottom, 108)
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
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

    init(path: Binding<[Route]>, recordID: String) {
        self._path = path
        self.recordID = recordID
        _records = Query(filter: #Predicate<Record> { $0.id == recordID })
    }

    private var record: Record? { records.first }

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
                                Pill(text: r.cat.title, style: .selected,
                                     tint: r.cat.tint, soft: r.cat.soft, tiny: true)
                                if let m = r.reminder, m.isOn {
                                    Pill(text: m.kind == .date ? "已挂提醒" : "到\(m.placeName ?? "那")提醒",
                                         tiny: true, tint: C.care, soft: C.moss)
                                }
                                Spacer(minLength: 0)
                            }

                            Text(r.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(C.ink)

                            Text(r.body)
                                .font(Typo.bodyS)
                                .foregroundStyle(C.ink2)
                                .lineSpacing(8)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 6) {
                                ForEach(r.tags, id: \.self) { t in
                                    Pill(text: t, tiny: true)
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

                        if !history.isEmpty {
                            SCard {
                                HStack {
                                    Text("历史版本")
                                        .font(Typo.captionM)
                                        .foregroundStyle(C.ink3)
                                    Spacer()
                                    Text("\(history.count) 个")
                                        .font(Typo.numCaption)
                                        .foregroundStyle(C.ink3)
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
                            }
                        }

                        // 删除。**刻意放在最后、且用危险色** ——
                        // 它离正文最远，因为手滑的成本取决于中间隔了多少东西。
                        Button {
                            // 软删除：只置 deletedAt，不真删（26 / 27 / 29 屏）。
                            // **必须 save()** —— 少了这一行，删除只活在内存里，
                            // 重启一次记录就回来了，而用户只会以为是自己记错了。
                            r.deletedAt = .now
                            try? ctx.save()
                            path.removeLast()
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
    }
}
