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
        /// 上一次连保守启动都没走完 → 库整份挪走重建。
        case rebuild
    }

    /// 本次启动的模式。`bootstrap` 读它决定跳过哪些步骤。
    private(set) static var mode: Mode = .normal

    /// 这一轮是不是保守启动。
    static var isSafe: Bool { mode != .normal }

    // MARK: - 两个动作

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
            // 上次的标记还没清 → 它没走到 `finish()`。而 `finish()` 是启动后
            // **5 秒**才调用的（见 `HerInfoApp`），所以这里的含义是
            // 「上次启动后 5 秒内就没了」—— 那只能是崩，或者被手动杀掉。
            // 两种情况的处置是一样的，都值得走一次保守路径。
            let last = Mode(rawValue: p.mode) ?? .normal
            m = (last == .normal) ? .safe : .rebuild
        }

        mode = m
        write(State(startedAt: Date.now.timeIntervalSince1970, mode: m.rawValue))
        return m
    }

    /// 启动流程真的走完了。
    ///
    /// **故意延后到启动后 5 秒**（调用点在 `HerInfoApp`），而不是紧跟在
    /// `bootstrap()` 后面 —— 因为用户报的「一点进去直接闪退」很可能发生在
    /// 首屏渲染时，那已经在 `bootstrap()` 之后了。只认 `bootstrap()` 走完，
    /// 这类崩溃就永远不会被记下来，保守路径也就永远不会启动。
    static func finish() {
        write(State(startedAt: 0, mode: Mode.normal.rawValue))
    }
}
