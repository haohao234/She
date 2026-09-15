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
    case reminderEdit(recordID: String)  // 32 编辑已有提醒（05 点条目进来的那条路）
    case search                       // 04 搜索 · 全局查找
    case recordDetail(id: String)     // 31 记录详情
    case versionHistory(id: String)   // 07 历史版本 · 左右对比（新）
    case recordEdit(id: String)       // 34 记录配图（新）
    case starterEdit(topic: String)   // 21 首条记录引导 · 预填好的编辑器（新）
    case trash                        // 27 回收站
    case exportArchive                // 35 导出档案（新）
    case lock                         // 13 应用锁
    case notifyDenied                 // 24 通知权限 · 关掉之后（新）
    case mood                         // 09 情绪打标 / 10 打标之后的建议（新）
    case cycle                        // 37 生理期首页（新）
}

// MARK: - 容器

/// 四个 tab + 底部胶囊导航。
/// **只有 4 个 tab** —— 设置不在这里，它是从首页右上角压进来的一页。
struct RootView: View {
    @State private var tab: HomeTab = .home
    @State private var path: [Route] = []
    @Environment(\.modelContext) private var ctx

    /// 上一次看到的「通知能不能发」。用来判断**这次回前台是不是刚被打开** ——
    /// 只有「false → true」那一次才值得重排，见 `rescheduleAfterPermissionChange()`。
    /// 显式写 `= nil`：它同时表示「还不知道」，而未知不该被当成「不能发」。
    @State private var lastNotifyOn: Bool? = nil

    /// 15 / 16 两屏首次使用走完没有。
    /// **用 `@AppStorage` 而不是查「有没有 Profile」** —— 用户完全可能在
    /// 引导里填了名字之后又把它删掉，那时他不该被送回引导页重新走一遍。
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    /// 13 屏应用锁。**这个开关以前只被「自己」读写** ——
    /// 设置页能拨、状态也存得住（`@AppStorage("appLock")`），但没有任何地方
    /// 在打开 App 时读它，所以它是「能开但不锁」。
    /// 这里把它接上：App 起来 / 回到前台时先过一遍面容或设备密码。
    ///
    /// 三个细节是刻意的：
    /// ① `locked` 初始 `false`、在 `.task` 里立即置位 —— 不能写成 `= appLock`，
    ///    因为 `@State` 的初值在 `@AppStorage` 读到的值之前就定了，会读到 false；
    ///    而 `.task` 在首帧之后跑，所以锁面会「晚一帧」出现。为了不让人看到
    ///    那一帧的真实内容，锁面本身就不透明（见 `AppLockCover`）。
    /// ② 引导没走完不锁 —— 15/16 屏时 App 里还没有任何可保护的内容，
    ///    一进来就弹面容只会让人莫名其妙。
    /// ③ **回前台也要锁**（`scenePhase == .active`）。只在启动时锁的话，
    ///    切出去看一眼再回来就绕过去了 —— 而「锁住她的信息」这件事，
    ///    恰恰是在「别人拿到你手机」时才要生效的。
    @AppStorage("appLock") private var appLock = false
    @State private var locked = false
    @Environment(\.scenePhase) private var scenePhase

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

            // 配图全屏预览（31 记录详情 / 34 编辑器都从这里进）。
            //
            // **必须挂在 Stack 之上，不能长在宿主屏里。** 这个 App 的手势侧滑返回
            // 是活的，而预览页要左右滑翻图 —— 长在被 push 出来的那屏里的话，
            // 手指从屏幕左边一划会同时翻图和 pop 掉底下那屏。
            // 盖在这上面之后，最上层先把触摸接住，那条侧滑就起不来了。
            //
            // zIndex 5：盖住轻提示（预览时顶上不该再飘一条提示），
            // 但**低于**锁面的 10 —— 锁的意义就是「谁都别看到」，
            // 那时候屏幕上正显示着照片，更不能例外。
            PhotoViewerLayer()
                .zIndex(5)

            // 13 屏的锁面。盖在最上层（含轻提示）—— 它的意义就是「谁都别看到」。
            if hasOnboarded && locked {
                AppLockCover { locked = false }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background(C.bg)
        .animation(.easeOut(duration: 0.28), value: hasOnboarded)
        .animation(.easeOut(duration: 0.18), value: locked)
        .task {
            // 冷启动：按当前设置决定要不要立刻锁。
            if hasOnboarded && appLock { locked = true }
            // 记下起来那一刻的权限状态 —— 它是后面「有没有变化」的基准。
            // 不记的话，用户第一次从系统设置切回来时 `lastNotifyOn` 是 nil，
            // 而 nil 不等于 false，那次该做的重排就会被漏掉。
            lastNotifyOn = await ReminderService.shared.canNotify()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if hasOnboarded && appLock { locked = true }
            Task { await rescheduleAfterPermissionChange() }
        }
    }

    /// 权限从「发不出去」变成「能发」的那一次，**重排一遍已有提醒**。
    ///
    /// 用户被引导去系统设置打开通知，再切回来 —— 如果这里不重排，
    /// 已设的那几条要等到**下一次冷启动**才排上，而他此刻的理解是
    /// 「我刚开了通知，它就该响了」。这个空档足够让他再报一次「提醒不响」。
    ///
    /// 只在**变化**的那一次排：每次回前台都全量重排会让「刚切出去又切回来」
    /// 变成一次没必要的全表扫描 + N 次 `add()`。
    private func rescheduleAfterPermissionChange() async {
        let on = await ReminderService.shared.canNotify()
        defer { lastNotifyOn = on }
        guard on, lastNotifyOn == false else { return }

        let d = FetchDescriptor<Record>(predicate: #Predicate<Record> { $0.deletedAt == nil })
        ReminderService.shared.rescheduleAll((try? ctx.fetch(d)) ?? [])
    }

    private var mainStack: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                C.bg.ignoresSafeArea()

                Group {
                    switch tab {
                    case .home:     HomeView(path: $path)
                    case .category: BrowseView(path: $path)
                    // 生理期**不做成 push 出去的二级页**，而是一个平级 tab ——
                    // 它是要「经常看一眼」的东西（还有几天、是不是正好在经期），
                    // 藏在两级菜单后面，这个「看一眼」就发生了。
                    case .cycle:    CycleView()
                    case .search:   SearchView(path: $path, onCancel: { tab = .home })
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
                case .reminderEdit(let rid):
                    // **同一个 `ReminderEditorView`，只是标题不同。**
                    // 不另写一屏「编辑提醒」：那一屏的字段、校验、通知预览
                    // 与新建态逐项相同，分成两个文件只会让以后改文案的人漏掉一半。
                    ReminderEditorView(path: $path, recordID: rid, isEditing: true)
                case .search:
                    // 被 push 上来时，「取消」= 退回上一层。
                    SearchView(path: $path, onCancel: { path.removeLast() })
                case .recordDetail(let id):
                    RecordDetailView(path: $path, recordID: id)
                case .versionHistory(let id):
                    VersionHistoryView(path: $path, recordID: id)
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
                case .mood:
                    MoodBoardView(path: $path)
                case .cycle:
                    CycleView()
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
        // 「这条提醒排不上」—— **把原因直接说出来。**
        //
        // 这一段是本轮补的关键一环：此前所有失败路径都是静默的
        // （`try?` 或裸 `return`），于是「提醒不响」在用户那边没有任何信息 ——
        // 他既不知道是权限问题、额度问题，还是自己压根没设过地点，
        // 只能得出一个笼统的结论：「这个功能是坏的」。
        .onReceive(NotificationCenter.default.publisher(for: .reminderCannotSchedule)) { note in
            guard let reason = note.object as? String else { return }
            ToastCenter.shared.show(reason)
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

    /// 首页问候语。
    ///
    /// **刻意不随时段变化** —— 原来写了四段「早上好/中午好/下午好/晚上好」，
    /// 但这句话是「我对她说」，不是「系统在报时」。四个变体换来换去，
    /// 反而像是在播报时间。统一成一句「你好啊，江林桐」：
    /// 她是这个 App 的主角，这句话是写给人看的，不是给状态栏看的。
    private var greeting: String {
        "你好啊，江林桐"
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

    /// 「取消」按下去做什么。**由外壳决定**，因为答案取决于它是怎么来的：
    /// 被 push 进来时是「退回上一层」，作为 tab 根时是「回首页」。
    /// 写在里面就只能二选一，另一种情况下那个按钮会变成假动作。
    let onCancel: () -> Void

    @Query(filter: #Predicate<Record> { $0.deletedAt == nil }) private var records: [Record]

    @State private var q = ""

    /// 「只看某一类」。nil = 全部。
    /// **它是分类范围（04 屏），不是 30 屏那三组条件** ——
    /// 两者在界面上挨着，但一个是「在哪些分类里找」，
    /// 另一个是「找出来的怎么收窄」，混成一个会说不清。
    @State private var scope: Category?

    /// 最近搜索词。用 `\u{1F}` 拼串存，不落库。
    ///
    /// **不预置任何示例词。** 04 画布上那四枚（白玫瑰 / 生日 / 忌口 / 雷点）
    /// 是「用过一阵之后的样子」，不是出厂状态 —— 首启就摆出来，
    /// 等于告诉用户「你搜过这些」，而其实一次都没搜过。
    /// 这也是当初删掉「小满」那条示例数据同一个判断。
    @AppStorage("hi.search.recent") private var recentRaw = ""
    private var recent: [String] {
        recentRaw.components(separatedBy: "\u{1F}").filter { !$0.isEmpty }
    }

    /// 面板里**正在编辑**的条件。
    @State private var draft = SearchFilter.standard
    /// 已经**按下去生效**的条件。nil = 这次搜索没有套筛选。
    ///
    /// 两份状态是这一屏的关键：面板里改来改去都不该影响列表，
    /// 只有点了「看 N 条结果」才生效。合成一份的话，
    /// 用户每点一枚胶囊列表就抖一次，而点遮罩想「算了」也回不去。
    @State private var applied: SearchFilter?
    @State private var showFilter = false

    @FocusState private var focused: Bool
    @State private var didAutoFocus = false

    /// 这一屏既是「搜索」tab 的根，也会被 push 进来。
    /// **根的时候不能再有返回键** —— 对空数组调 `removeLast()` 是直接崩，
    /// 而它崩的时机是「用户点了搜索 tab 又点了返回」，看起来完全不像 bug。
    private var backAction: (() -> Void)? {
        path.isEmpty ? nil : { path.removeLast() }
    }

    // MARK: 命中与呈现

    /// 搜索命中：**分类范围 + 搜索词**。
    ///
    /// 刻意**不含** 30 屏那三组条件 —— 「已筛掉 M 条」里的 M 说的正是
    /// 「被那三组砍掉了多少」，分子分母都得建立在「命中」上。
    private var hits: [Record] {
        records.filter { r in
            if let scope, r.cat != scope { return false }
            guard !q.isEmpty else { return true }
            return r.title.localizedStandardContains(q)
                || r.body.localizedStandardContains(q)
        }
    }

    /// 真正显示的列表。没套筛选时按「最近编辑」—— 搜索结果默认
    /// 就该是最近提到过的排前面，这也是原型里 `renderResults` 的默认口径。
    private var shown: [Record] {
        guard let applied else {
            return hits.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
        }
        return applied.sorted(hits.filter { applied.accepts($0) })
    }

    /// 面板底部那个「会筛出几条」。**与 `shown` 用同一个 `accepts`** ——
    /// 各算各的迟早会对不上，而「按之前说 3 条、按下去出 5 条」
    /// 比不给预览更伤信任。
    private var draftPreview: Int {
        hits.filter { draft.accepts($0) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            ScrollView {
                VStack(alignment: .leading, spacing: S.innerGapL) {
                    if !recent.isEmpty {
                        hintRow("最近搜索", actionTitle: "清空") { recentRaw = "" }

                        FlowLayout(spacing: S.rowGap) {
                            ForEach(recent, id: \.self) { term in
                                Pill(text: term, style: .normal) {
                                    q = term
                                    voidFilter()          // 换词 = 条件作废
                                    focused = false
                                }
                            }
                        }
                    }

                    Text("只看某一类")
                        .font(Typo.captionM)
                        .foregroundStyle(C.ink3)

                    FlowLayout(spacing: S.rowGap) {
                        Pill(text: "全部", style: scope == nil ? .selected : .normal) {
                            scope = nil
                            voidFilter()
                        }
                        ForEach(Category.allCases) { c in
                            Pill(text: c.title, style: scope == c ? .selected : .normal) {
                                scope = c
                                voidFilter()
                            }
                        }
                    }

                    if hits.isEmpty && !q.isEmpty {
                        // 28 屏。这里**不出现结果统计行与「筛选」** ——
                        // 一条都没有的时候，给筛选入口是把人往死路上引。
                        EmptyState(symbol: "magnifyingglass",
                                   title: "没找到「\(q)」",
                                   message: "它可能还没被记下来，或者你记的时候用的是别的说法。")
                            .padding(.top, S.screen)
                    } else {
                        SearchResultHeader(shown: shown.count,
                                           dropped: hits.count - shown.count,
                                           isFiltered: applied != nil,
                                           onFilter: {
                                               draft = applied ?? .standard
                                               showFilter = true
                                           })

                        VStack(spacing: S.innerGapL) {
                            ForEach(shown) { r in
                                RecordCard(record: r,
                                           onTap: { path.append(.recordDetail(id: r.id)) },
                                           highlight: q.isEmpty ? nil : q)
                            }
                        }
                    }
                }
                .padding(.horizontal, S.screen)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if showFilter {
                SearchFilterOverlay(
                    draft: $draft,
                    previewCount: draftPreview,
                    onApply: {
                        applied = draft
                        showFilter = false
                        focused = false
                    },
                    onClear: {
                        draft = .standard
                        applied = nil        // 「重置」是**回到出厂**，不是「变空」
                    },
                    onDismiss: { showFilter = false })   // 点遮罩：只关面板，不套用
            }
        }
        .animation(.easeOut(duration: 0.24), value: showFilter)
        .onChange(of: q) { _, _ in voidFilter() }
        .onSubmit(of: .search) { remember(q) }
        .task {
            // 只自动聚焦一次。每次 appear 都聚焦的话，
            // 从记录详情退回来会再把键盘弹起来，把刚看过的结果全挡住。
            guard !didAutoFocus else { return }
            didAutoFocus = true
            // 等推入动画走完再聚焦。立刻置 `focused = true` 的话，
            // 输入框可能还没进视图树，那一次赋值会被丢掉 ——
            // 表现就是「有时候键盘自己弹出来、有时候不弹」，最难查的那种。
            try? await Task.sleep(for: .milliseconds(320))
            focused = true
        }
    }

    // MARK: 搜索栏（04 / 08 屏）

    /// 返回箭头 + 输入框 + 取消。
    ///
    /// **输入框那圈主色描边就是 08 屏的「键盘态」。** 它不只是好看：
    /// 这一屏有两个可以「退」的东西（回上一层 / 清掉搜索词），
    /// 描边把「现在在编辑的是这个框」说清楚，用户才敢确定
    /// 那个 × 清掉的是词、而不是退出这一屏。
    private var searchBar: some View {
        HStack(spacing: S.rowGap) {
            if let back = backAction {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(C.ink)
                        .frame(width: 30, height: 44)
                }
                .pressDown()
            }

            HStack(spacing: S.rowGap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(C.ink3)

                TextField("搜索喜好、忌口、雷点…", text: $q)
                    .font(Typo.body)
                    .foregroundStyle(C.ink)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !q.isEmpty {
                    Button { q = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(C.ink3.opacity(0.55))
                            .frame(width: 26, height: 26)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(C.card, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(focused ? C.primary : C.line2,
                                  lineWidth: focused ? 1.5 : 1)
            )

            Button(action: onCancel) {
                Text("取消")
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink2)
                    .padding(.vertical, 8)
            }
            .pressDown()
        }
        .padding(.horizontal, S.screen)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: 小件

    private func hintRow(_ title: String, actionTitle: String,
                         action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)
            Spacer(minLength: 0)
            Button(action: action) {
                Text(actionTitle)
                    .font(Typo.captionM)
                    .foregroundStyle(C.ink3)
                    .padding(.vertical, 4)
            }
            .pressDown()
        }
    }

    /// 只要搜索条件一变，这一轮的临时筛选就作废。
    ///
    /// 这是 30 屏的规矩：筛选只负责「这一次搜索」。
    /// 让它活着跨过一次改词，用户下次就会看到「我明明搜别的词，
    /// 怎么还是只剩这 3 条」——然后开始怀疑数据丢了。
    private func voidFilter() {
        applied = nil
        draft = .standard
    }

    /// 记一条最近搜索。去重后放最前，最多留 6 条 ——
    /// 再多会把「只看某一类」挤到一屏之外，而那一排的使用频率更高。
    private func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = recent.filter { $0 != t }
        list.insert(t, at: 0)
        recentRaw = list.prefix(6).joined(separator: "\u{1F}")
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
                VStack(alignment: .leading, spacing: S.innerGapL) {

                    // 分组标题照 05 屏定稿。**分两块不是为了好看** ——
                    // 「定时」与「场景」是两种心智（到点响 / 到地方响），
                    // 混在一列里，用户会以为是自己设的那个时间坏了。
                    if !dateReminders.isEmpty {
                        groupLabel("定时提醒 · 按日期")
                        ForEach(dateReminders) { reminderCard($0) }
                    }

                    if !geoReminders.isEmpty {
                        // 组标题说「地方」不说「时候」：这个功能在 iOS 上能做的
                        // 只有「到某个地点就提醒」。「见到她」「她情绪低落」那类
                        // 触发点系统给不了 —— 见 `ReminderEditorView.presetPlaces`。
                        groupLabel("场景提醒 · 到了这些地方主动提醒我")
                        ForEach(geoReminders) { reminderCard($0) }
                    }

                    if reminders.isEmpty {
                        Text("还没有提醒。记下一条在意的事，再给它定个时间。")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, S.screen)
                .padding(.vertical, 8)
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: 列表

    private var reminders: [Reminder] { records.compactMap(\.reminder) }
    private var dateReminders: [Reminder] { reminders.filter { $0.kind == .date } }
    private var geoReminders:  [Reminder] { reminders.filter { $0.kind == .geo } }

    private func groupLabel(_ t: String) -> some View {
        Text(t)
            .font(Typo.captionM)
            .foregroundStyle(C.ink3)
            .padding(.horizontal, 4)
    }

    private func reminderCard(_ m: Reminder) -> some View {
        SCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.kind == .date
                         ? "定时 · \(m.time.hhmm)"
                         : "场景 · 到「\(m.placeName ?? "某处")」附近")
                        .font(Typo.numCaptionM)
                        .foregroundStyle(C.primary)
                    Text(m.message)
                        .font(Typo.bodyS)
                        .foregroundStyle(C.ink)
                    if let detail = detailLine(m) {
                        Text(detail)
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                    }
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
        // **整张卡可点进编辑。**
        //
        // 此前这里没有任何入口 —— 05 屏是所有提醒的列表页，而条目一个都点不动，
        // `Route` 里也只有「新建」。于是用户看得见那条提醒，
        // 却没有任何一条路能走进去改它，那正是「想修改提醒时间，发现无法修改」。
        //
        // `contentShape` 不能省：SCard 的内容在纵向是「文字多高就多高」，
        // 不铺满卡片时点在空白处不响应，而空白处恰恰占了大半张卡。
        // 开关那一下不会走到这里 —— `SoftSwitch` 内层有自己的手势，先响应。
        .contentShape(Rectangle())
        .onTapGesture {
            guard let rid = m.record?.id else {
                // 提醒理论上都挂在记录上。真出现悬空的要如实说一句 ——
                // 静默什么都不发生，用户只会以为「点不动」。
                ToastCenter.shared.show("这条提醒没有关联的记录，删掉重建一条")
                return
            }
            path.append(.reminderEdit(recordID: rid))
        }
    }

    /// 卡片第三行。**只在它比正文多说了点什么时才返回值。**
    ///
    /// 两个理由，都是「同一句话在卡上出现两遍」：
    ///   · 定时 + 准时：`previewLine` 就等于正文本身，照画会印两遍；
    ///   · 场景：「到哪儿」第一行那个「场景 · 到「公司」附近」已经说过了，
    ///     所以这一档改成说范围 —— 那才是它多余的信息。
    private func detailLine(_ m: Reminder) -> String? {
        let s = m.kind == .geo
            ? "进入 \(Int(m.radius)) 米范围时提醒"
            : m.previewLine
        return s == m.message ? nil : s
    }
}

// 日期格式统一放在 SecondaryViews.swift 末尾的 Extensions 区，
// 避免多个文件各自定义 monthDayCN 造成重复符号。

// MARK: - 13 屏 应用锁

/// 锁面。
///
/// **它是不透明的整屏遮挡，不是一个半透明蒙层。** 这一点必须如此：
/// `locked` 是在首帧之后由 `.task` / `scenePhase` 置位的，所以理论上
/// 有一帧没有遮挡 —— 如果是蒙层，那一帧的真内容会透出来，锁就白上了。
/// 全不透明 + 盖在最上层，才能保证「要么看不到，要么看到的是锁」。
///
/// 文案沿用 13 屏的那两句，只是动词从「开启」换成「解锁」——
/// 同一个界面在两种状态下说话要一致，否则用户会以为自己点错了地方。
struct AppLockCover: View {

    /// 验过了，把锁交还给 RootView。
    var onUnlock: () -> Void

    @State private var failed = false
    @State private var busy = false

    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(C.warm).frame(width: 72, height: 72)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(C.primary)
                }

                Text("我的宝宝江林桐")
                    .font(Typo.cardTitle)
                    .foregroundStyle(C.ink)

                Text(failed
                     ? "没有通过验证。\n她的信息只有你能看，再试一次。"
                     : "用面容 ID 打开。\n锁屏上收到的提醒不会显示具体内容。")
                    .font(Typo.bodyS)
                    .foregroundStyle(failed ? C.danger : C.ink3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                Button {
                    Task { await unlock() }
                } label: {
                    Text(busy ? "验证中…" : "解锁")
                        .primaryButtonStyle()
                }
                .pressDown()
                .disabled(busy)
                .padding(.horizontal, S.screen)
                .padding(.top, 10)
            }
            .padding(.horizontal, S.screen)
        }
        // 进来就自动弹一次 —— 让用户去点「解锁」等于多一步。
        // 失败后再把按钮显露出来，由他自己决定要不要重试。
        .task { await unlock() }
    }

    /// 过一次生物识别。
    ///
    /// **失败不放行。** `BiometricGate.confirm` 对「用户取消」与「认证失败」
    /// 都返回 false —— 这里同样一律留在锁面。宁可多试一次，
    /// 也不要出现「按了取消反而进去了」这种事。
    private func unlock() async {
        guard !busy else { return }
        busy = true
        // 面容 ID 系统弹窗上那行字。写 App 名而不是「打开」——
        // 弹窗标题已经在显示 App 名了，这里再说一遍产品名是重复。
        let ok = await BiometricGate.confirm(reason: "打开我的宝宝江林桐")
        busy = false
        if ok {
            failed = false
            onUnlock()
        } else {
            failed = true
        }
    }
}
