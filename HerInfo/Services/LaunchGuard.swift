//
//  LaunchGuard.swift
//  我的宝宝江林桐 · 启动守门
//
//  【它存在的理由，一句话】
//  这一层保证的是**「最坏情况下也点得开」**，而不是「一定不崩」。
//
//  【为什么需要「不保证不崩」这种东西】
//  2026-09-15 一天里收到四份真机崩溃日志，其中三份的 trap 地址**逐字节相同**
//  （`SwiftData + 0x9e77c`），而三次的调用方各不相同：
//    · 10:25 / 11:10 —— `RecordEditorView.save` 里读 `target.photos`；
//    · 11:49        —— `ReminderService.photoIndex` 里读 `Photo.hash`。
//  我据此把「读配图」从关系数组搬到了标量数组（见 `Record.photoHashes`），
//  那条路径现在应该已经不存在了。
//
//  但「应该」不算数。同一个 bug 已经反复了三轮，代码层面的判断错过两次
//  （第一次判成「自动保存的 Task 比 View 活得久」，第二次判成「守卫写法不对」）。
//  所以这一层不去猜第四次，而是**接受「可能还有没想到的地方」**：
//    · 崩了 → 记住「这次启动没走完」→ 下次换一条更保守的路走；
//    · 保守的路也崩 → 把库整份挪到一边、新建一份空的，并**如实告诉用户**
//      （旧数据没删，见 `storeResetKey`）。
//  最坏的结果因此从「永久打不开」变成「数据在一边、App 能用」。
//
//  【2026-10-27 的事故：判据错了，代价是用户以为记录全没了】
//  上面那套判据原来是「上次启动后 5 秒内就没了 ⇒ 当它崩了」。这个假设是错的：
//  `finish()` 靠一个 5 秒的 `Task.sleep` 复位，而**用户上滑关掉、或系统回收，
//  都不会等这 5 秒**。于是「打开看一眼就关」变成了「启动崩溃」：
//      normal 那次没走完 → 下次 .safe
//      .safe 那次也没走完 → 再下次 .rebuild → 整库搬走、新建空库
//  真机上攒出了 **9 个 `broken-*` 目录**（10-21 ~ 10-27），而用户只是正常地
//  开关 App。真正的数据在第一个目录里躺了六天，界面上却是一个空库。
//
//  ⇒ 判据改成**看「首屏有没有画出来」**，而不是看「有没有熬过 5 秒」：
//    · `rendered == false` → 连界面都没出来，只能是启动期崩溃，降级是对的；
//    · `rendered == true`  → 界面已经出来了。用户划掉、系统回收、锁屏后被杀，
//      全都长这样，**一律不降级**，更不许 `.rebuild`。
//  这一条把「谁能触发整库搬家」从「任何人手快关两次」收窄到「真的启动即崩」。
//
//  【为什么用文件而不是 UserDefaults 记状态】
//  崩溃发生在启动后 100 多毫秒，而 UserDefaults 的写入是异步落盘的 ——
//  它很可能赶不上。这里的标记正是「下次启动要知道这次崩了」的唯一依据，
//  丢一次就等于这一层白写。`.atomic` 写文件是「要么旧内容、要么新内容」，
//  在这里比 UserDefaults 靠得住。
//

import Foundation

@MainActor
enum LaunchGuard {

    // MARK: - 状态落在哪

    /// `Application Support/launch-state.json`。
    ///
    /// 和 SwiftData 的 `default.store` 同一个目录 —— 但**它俩的寿命不一样**：
    /// 库会被 `containerAfterSettingAsideBrokenStore` 整份挪走，
    /// 而这个文件必须留在原地，否则「刚挪完库」的下一次启动会认不出状态。
    private static var stateURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first
        else { return nil }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("launch-state.json")
    }

    private struct State: Codable {
        /// 本次启动开始的时间（秒）。**它还在 = 上次没走到 `finish()`。**
        var startedAt: TimeInterval
        /// 上次用的模式。`normal` / `safe` / `rebuild`。
        var mode: String
        /// 首屏有没有真的画出来。
        ///
        /// **可选类型是故意留的**：10-27 之前的版本写出来的文件里没有这个键，
        /// 而 `nil` 必须按「已渲染」处理（旧文件的 `startedAt > 0` 更可能是
        /// 被划掉而不是崩溃）—— 升级后的第一次启动绝不能因此少一次降级判断，
        /// 更不能因此触发 `.rebuild`。宁可放过一次真崩溃，也不能再搬一次库。
        var rendered: Bool? = nil
    }

    private static func read() -> State? {
        guard let u = stateURL, let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private static func write(_ s: State) {
        guard let u = stateURL, let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: u, options: .atomic)
    }

    // MARK: - 三种模式

    enum Mode: String {
        /// 正常启动：所有启动步骤都跑。
        case normal
        /// 保守启动：**只保留「界面能开」的最小集**，跳过所有会碰模型对象的启动步骤。
        /// 代价是这一次启动不重排提醒、不清回收站、不清孤儿图片 —— 都会在
        /// 下一次正常启动时补上，所以最坏也就是「晚一次」。
        case safe
        /// 上一次**连首屏都没画出来**（不是「被划掉」）→ 库整份挪走重建。
        /// 这是全 App 唯一会动用户库文件的分支，判据必须严到「启动即崩」。
        case rebuild
    }

    /// 本次启动的模式。`bootstrap` 读它决定跳过哪些步骤。
    private(set) static var mode: Mode = .normal

    /// 这一轮是不是保守启动。
    static var isSafe: Bool { mode != .normal }

    // MARK: - 三个动作

    /// 记下「这次启动了」—— **必须排在容器建立之前**。
    ///
    /// 排在最前面的原因只有一个：`rebuild` 要在 SwiftData 打开库文件之前
    /// 把库挪走（打开之后再挪，那个连接就指向一个不存在的文件了）。
    @discardableResult
    static func begin() -> Mode {
        let previous = read()

        var m: Mode = .normal
        // 判据是 `startedAt > 0`，**不是「文件在不在」** ——
        // `finish()` 之后文件仍然在（它写的是 `startedAt = 0`），拿文件存在与否
        // 当判据会让每次正常启动都被当成崩溃重启。
        if let p = previous, p.startedAt > 0 {
            // 上次没走到 `finish()`。**但不等于它崩了** —— 见文件头的 10-27 事故。
            // 只有「首屏都没画出来」才算启动期崩溃；`rendered` 为 `true`
            // 或 `nil`（旧版本文件）都按「界面已经出来过」处理，不降级。
            if p.rendered == false {
                let last = Mode(rawValue: p.mode) ?? .normal
                m = (last == .normal) ? .safe : .rebuild
            }
        }

        mode = m
        write(State(startedAt: Date.now.timeIntervalSince1970, mode: m.rawValue, rendered: false))
        return m
    }

    /// 「首屏已经画出来了」—— 由 `RootView` 的 `.onAppear` 调用。
    ///
    /// 这一笔是整套判据里**最有信息量的一笔**：它把「启动期崩溃」和
    /// 「打开后被划掉」彻底分开了。写进去之后，这一次启动无论怎么结束
    /// （划掉、被系统回收、锁屏被杀），下一次都**不会**降级、更不会搬库。
    ///
    /// 只改 `rendered`，**不动 `startedAt`** —— 那个值是「这次启动从什么时候开始」，
    /// 由 `begin()` 定，`finish()` 才负责清零。
    static func markRendered() {
        guard let cur = read(), cur.startedAt > 0, cur.rendered != true else { return }
        write(State(startedAt: cur.startedAt, mode: cur.mode, rendered: true))
    }

    /// 启动流程真的走完了。
    ///
    /// **仍然延后到启动后 5 秒**（调用点在 `HerInfoApp`），因为它是给
    /// `announceSafeLaunchIfAny` 用的「这一轮是否完整」的标记；
    /// 但**它已经不再是「是否崩溃」的判据**了 —— 那件事交给 `markRendered()`，
    /// 所以「5 秒内被划掉」不再有任何后果。
    static func finish() {
        write(State(startedAt: 0, mode: Mode.normal.rawValue, rendered: true))
    }
}
