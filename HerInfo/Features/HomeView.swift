//
//  HomeView.swift
//  对应画布 01 首页 · 她的档案（+ 全局容器 RootView）
//
//  首页只回答一个问题：**今天有什么是她相关的**。
//  所以顺序是「她的名片 → 最近的提醒 → 四条分类」，而不是「功能入口列表」。
//

import SwiftUI
import SwiftData

// MARK: - 路由

/// 屏与屏之间的路。骨架阶段先落这几条主干 + 本轮的四个入口，
/// 其余二级页按同一模式加 case 即可。
enum Route: Hashable {
    case profile                      // 17 她的档案 · 详情
    case profileEdit                  // 33 编辑她的档案（新）
    case settings                     // 12 设置
    case appearance                   // 23 外观
    case sortPin                      // 25 排序与置顶
    case reminders                    // 05 提醒 · 定时与场景
    case reminderNew(recordID: String?)  // 32 新建提醒（新）
    case search                       // 04 搜索 · 全局查找
    case recordDetail(id: String)     // 31 记录详情
    case recordEdit(id: String)       // 34 记录配图（新）
    case starterEdit(topic: String)   // 21 首条记录引导 · 预填好的编辑器（新）
    case trash                        // 27 回收站
    case exportArchive                // 35 导出档案（新）
    case lock                         // 13 应用锁
    case notifyDenied                 // 24 通知权限 · 关掉之后（新）
}

// MARK: - 容器

/// 四个 tab + 底部胶囊导航。
/// **只有 4 个 tab** —— 设置不在这里，它是从首页右上角压进来的一页。
struct RootView: View {
    @State private var tab: HomeTab = .home
    @State private var path: [Route] = []
    @Environment(\.modelContext) private var ctx

    /// 15 / 16 两屏首次使用走完没有。
    /// **用 `@AppStorage` 而不是查「有没有 Profile」** —— 用户完全可能在
    /// 引导里填了名字之后又把它删掉，那时他不该被送回引导页重新走一遍。
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        ZStack(alignment: .top) {
            if hasOnboarded {
                mainStack
            } else {
                OnboardingView(finished: $hasOnboarded)
            }

            // 轻提示挂在这一层，所以它跨屏存活：存完记录 pop 回列表之后，
            // 那条「已记下 …」还在（22 屏拍的就是这个瞬间）。
            ToastLayer()
        }
        .background(C.bg)
        .animation(.easeOut(duration: 0.28), value: hasOnboarded)
    }

    private var mainStack: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                C.bg.ignoresSafeArea()

                Group {
                    switch tab {
                    case .home:     HomeView(path: $path)
                    case .category: BrowseView(path: $path)
                    case .search:   SearchView(path: $path)
                    case .remind:   ReminderListView(path: $path)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    // 底部导航是浮在内容之上的，所以内容区要多留 95 的空间
                    // （导航 62 + 上 12 + 下 21 = 95），否则最后一张卡会被压住。
                    Color.clear.frame(height: 95)
                }

                TabPill(selection: $tab)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .profile:
                    ProfileDetailView(path: $path)
                case .profileEdit:
                    ProfileEditView(path: $path)
                case .settings:
                    SettingsView(path: $path)
                case .appearance:
                    AppearanceView()
                case .sortPin:
                    SortPinView(path: $path)
                case .reminders:
                    ReminderListView(path: $path)
                case .reminderNew(let rid):
                    ReminderEditorView(path: $path, recordID: rid)
                case .search:
                    SearchView(path: $path)
                case .recordDetail(let id):
                    RecordDetailView(path: $path, recordID: id)
                case .recordEdit(let id):
                    RecordEditorView(path: $path, editingID: id, starterID: "")
                case .starterEdit(let topic):
                    RecordEditorView(path: $path, editingID: "", starterID: topic)
                case .trash:
                    TrashView(path: $path)
                case .exportArchive:
                    ExportView(path: $path)
                case .lock:
                    LockSetupView()
                case .notifyDenied:
                    NotificationDeniedView(path: $path)
                }
            }
        }
        .tint(C.primary)
        // 点通知 → 跳到那条记录。这是 32 屏脚注「点开直接回到这条记录」的落地点；
        // 没有这两个监听，通知就只是一句会消失的话，点了什么也不会发生。
        .onReceive(NotificationCenter.default.publisher(for: .openRecord)) { note in
            guard let rid = note.object as? String else { return }
            path.append(.recordDetail(id: rid))
        }
        // 通知上的「今天不用了」。
        .onReceive(NotificationCenter.default.publisher(for: .reminderDone)) { note in
            guard let mid = note.object as? String else { return }
            HerInfoStore.markReminderDone(reminderID: mid, in: ctx)
        }
    }
}

// MARK: - 01 首页

struct HomeView: View {
    @Binding var path: [Route]

    @Query(filter: #Predicate<Record> { $0.deletedAt == nil },
           sort: \Record.updatedAt, order: .reverse)
    private var records: [Record]

    @Query private var profiles: [Profile]

    /// 「记录第 128 天」= 从第一次打开算起。存首次启动时间，不存天数 ——
    /// 存下来的数字过一夜就是错的。
    @AppStorage("firstLaunchAt") private var firstLaunchAt: Double = 0

    private var profile: Profile? { profiles.first }

    private var recordDay: Int {
        let start = firstLaunchAt == 0 ? Date.now : Date(timeIntervalSince1970: firstLaunchAt)
        return (Calendar.current.dateComponents([.day], from: start, to: .now).day ?? 0) + 1
    }

    private func count(_ cat: Category) -> Int {
        records.filter { $0.cat == cat }.count
    }

    /// 最近一条还开着的提醒。首页那条暖色横条就是它 ——
    /// 首页不列全部提醒，只列**最近会发生的那一条**，因为首页是「看一眼就走」的地方。
    private var nextReminder: Reminder? {
        records.compactMap(\.reminder).filter(\.isOn).first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: S.cardGap) {

                // 顶行：问候 + 设置 + 头像
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(Typo.pageTitle)
                            .foregroundStyle(C.ink)
                        Text("\(Date.now.monthDayCN) · 记录第 \(recordDay) 天")
                            .font(Typo.numCaption)
                            .foregroundStyle(C.ink3)
                    }

                    Spacer(minLength: 0)

                    Button { path.append(.settings) } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(C.ink2)
                            .frame(width: 36, height: 36)
                            .background(C.fill, in: Circle())
                    }
                    .pressDown()

                    Button { path.append(.profile) } label: {
                        // 用 AvatarView，而不是在这里再画一遍渐变圆 ——
                        // 首页右上角这个头像是「她设过头像没有」唯一的常驻信号，
                        // 画在两处就一定会有一处忘了跟着改。
                        AvatarView(hash: profile?.avatarHash,
                                   name: profile?.name ?? "她",
                                   size: 36)
                    }
                    .pressDown()
                }

                // 搜索栏。它是一整条按钮，不是输入框 ——
                // 点它进 04 屏再打字，这样首页不会被键盘顶起来。
                Button { path.append(.search) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(C.ink3)
                        Text("搜索喜好、忌口、雷点…")
                            .font(Typo.bodyS)
                            .foregroundStyle(C.ink3)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(C.card, in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(C.line, lineWidth: 1))
                }
                .pressDown()

                // 她的名片
                if let profile {
                    Button { path.append(.profile) } label: {
                        SCard(radius: R.cardBig, padding: S.cardPadL) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(C.warm).frame(width: 44, height: 44)
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(C.primary)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(C.ink)
                                    Text("在一起 \(profile.daysTogether) 天 · 记录第 \(recordDay) 天")
                                        .font(Typo.numCaption)
                                        .foregroundStyle(C.ink3)
                                }
                                Spacer(minLength: 0)
                                Text("完整度 \(completeness(profile))%")
                                    .font(Typo.caption)
                                    .foregroundStyle(C.primary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(C.warm, in: Capsule(style: .continuous))
                            }

                            HStack(spacing: 0) {
                                statBlock("\(records.count)", "记录条目")
                                statBlock("\(records.filter { !$0.tags.isEmpty }.count)", "喜好标签")
                                statBlock("\(records.compactMap(\.reminder).filter(\.isOn).count)", "提醒规则")
                            }
                            .padding(.top, 4)
                        }
                    }
                    .pressDown()
                }

                // 最近的提醒
                if let m = nextReminder {
                    Button { path.append(.reminders) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill(C.primary).frame(width: 40, height: 40)
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.kind == .date
                                     ? "\(m.leadLabel)后 · \(m.time.hhmm)"
                                     : "到\(m.placeName ?? "那个地方")附近时")
                                    .font(Typo.captionM)
                                    .foregroundStyle(C.primary)
                                Text(m.message)
                                    .font(Typo.bodyS)
                                    .foregroundStyle(C.ink)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(C.primary)
                                .padding(.top, 12)
                        }
                        .padding(16)
                        .background(C.warm, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
                    }
                    .pressDown()
                }

                // 四条分类
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("分类记录")
                            .font(Typo.cardTitle)
                            .foregroundStyle(C.ink)
                        Spacer()
                        Text("全部 \(records.count) 条")
                            .font(Typo.numCaption)
                            .foregroundStyle(C.ink3)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(Category.allCases) { cat in
                            Button {
                                path.append(.search)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Circle().fill(cat.tint).frame(width: 7, height: 7)
                                        Text(cat.title)
                                            .font(Typo.caption)
                                            .foregroundStyle(cat.tint)
                                    }
                                    Text("\(count(cat))")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(C.ink)
                                    Text("条记录")
                                        .font(Typo.caption)
                                        .foregroundStyle(C.ink3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(cat.soft,
                                            in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
                            }
                            .pressDown()
                        }
                    }
                }
            }
            .padding(.horizontal, S.screen)
            .padding(.top, 8)
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if firstLaunchAt == 0 { firstLaunchAt = Date.now.timeIntervalSince1970 }
        }
    }

    private func statBlock(_ num: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(num)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(C.ink)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(C.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11:  return "早上好，阿哲"
        case 11..<14: return "中午好，阿哲"
        case 14..<18: return "下午好，阿哲"
        default:      return "晚上好，阿哲"
        }
    }

    /// 档案完整度。**这是 33 屏的存在理由** ——
    /// 15 屏第一次只问名字和纪念日，剩下的（头像/生日/城市/一句话）在这里补，
    /// 这个百分比就是「还有多少能补」的度量。
    private func completeness(_ p: Profile) -> Int {
        var filled = 2   // name + together 必然有
        if p.avatarHash != nil { filled += 1 }
        if p.birthday != nil { filled += 1 }
        if !p.city.isEmpty { filled += 1 }
        if !p.about.isEmpty { filled += 1 }
        return Int(Double(filled) / 6.0 * 100)
    }
}

// MARK: - 04 搜索 / 05 提醒（tab 根，也会被 push 进来）

struct SearchView: View {
    @Binding var path: [Route]
    @Query(filter: #Predicate<Record> { $0.deletedAt == nil }) private var records: [Record]
    @State private var q = ""

    /// 这一屏既是「搜索」tab 的根，也会被 push 进来。
    /// **根的时候不能再有返回键** —— 对空数组调 `removeLast()` 是直接崩，
    /// 而它崩的时机是「用户点了搜索 tab 又点了返回」，看起来完全不像 bug。
    private var backAction: (() -> Void)? {
        path.isEmpty ? nil : { path.removeLast() }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavRow("搜索", onBack: backAction)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SField(placeholder: "搜索喜好、忌口、雷点…", text: $q)
                        .padding(.horizontal, S.screen)

                    let hits = records.filter {
                        q.isEmpty ? true
                        : $0.title.localizedStandardContains(q)
                          || $0.body.localizedStandardContains(q)
                    }

                    if hits.isEmpty && !q.isEmpty {
                        EmptyState(symbol: "magnifyingglass",
                                   title: "没找到「\(q)」",
                                   message: "换个说法试试，或者新建一条记录把它记下来")
                    } else {
                        VStack(spacing: S.innerGapL) {
                            ForEach(hits) { r in
                                RecordCard(record: r) { path.append(.recordDetail(id: r.id)) }
                            }
                        }
                        .padding(.horizontal, S.screen)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ReminderListView: View {
    @Binding var path: [Route]
    @Query(filter: #Predicate<Record> { $0.deletedAt == nil }) private var records: [Record]
    @Environment(\.modelContext) private var ctx

    /// 同 SearchView：它既是 tab 根、也会被 push 进来。
    private var backAction: (() -> Void)? {
        path.isEmpty ? nil : { path.removeLast() }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavRow("提醒", onBack: backAction) {
                Button { path.append(.reminderNew(recordID: nil)) } label: {
                    Text("新建提醒")
                        .font(Typo.pillSel)
                        .foregroundStyle(C.primary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(C.warm, in: Capsule(style: .continuous))
                }
                .pressDown()
            }

            ScrollView {
                VStack(spacing: S.innerGapL) {
                    ForEach(records.compactMap(\.reminder)) { m in
                        SCard {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(m.kind == .date ? "定时 · \(m.time.hhmm)" : "场景 · \(m.placeName ?? "")")
                                        .font(Typo.numCaptionM)
                                        .foregroundStyle(C.primary)
                                    Text(m.message)
                                        .font(Typo.bodyS)
                                        .foregroundStyle(C.ink)
                                    Text(m.previewLine)
                                        .font(Typo.caption)
                                        .foregroundStyle(C.ink3)
                                }
                                Spacer(minLength: 0)
                                // 以前这里是 `.constant(m.isOn)` —— 一个永远不动的常量绑定。
                                // 表现是「开关看得见、拨不动」，而且拨了也不会重排通知。
                                SoftSwitch(isOn: Binding(
                                    get: { m.isOn },
                                    set: { on in
                                        m.isOn = on
                                        try? ctx.save()
                                        Task {
                                            if on { await ReminderService.shared.schedule(m) }
                                            else  { await ReminderService.shared.cancel(m) }
                                        }
                                    }))
                            }
                        }
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

// 日期格式统一放在 SecondaryViews.swift 末尾的 Extensions 区，
// 避免多个文件各自定义 monthDayCN 造成重复符号。
