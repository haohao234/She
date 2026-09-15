//
//  HerInfoApp.swift
//  我的宝宝江林桐 · 应用入口
//
//  【Xcode 里怎么起】
//  1. File → New → Project → iOS App，Interface 选 SwiftUI，Language 选 Swift
//  2. 把 HerInfo/ 整个文件夹拖进 target（勾 Copy items if needed）
//  3. Target → General → Minimum Deployments 设为 iOS 17.0（SwiftData 的门槛）
//  4. Info.plist 加两条用途说明，否则申请权限时会被系统拒绝：
//       NSLocationWhenInUseUsageDescription  → 「到你常去的地方时，提醒你记过的事」
//       NSFaceIDUsageDescription             → 「用来锁住她的信息，只有你能打开」
//  5. 不需要任何第三方依赖
//

import SwiftUI
import SwiftData
import UIKit

@main
struct HerInfoApp: App {

    @Environment(\.scenePhase) private var scenePhase

    /// 长按 App 图标那一项的接法。
    ///
    /// **只能走 `UIApplicationDelegate`** —— SwiftUI 没有对应的场景回调，
    /// `.onOpenURL` 收的是 URL，接不到 shortcut。
    /// 它只做一件事：把「打了哪一档」记进待落库队列。
    /// 落库交给下面同一个 `drainInbox`，因为此刻 `ModelContext` 还拿不到 ——
    /// 容器是 App 这个结构体的属性，而 delegate 比它先存在。
    @UIApplicationDelegateAdaptor(QuickActionDelegate.self) private var quickActions

    /// 一个容器，全 App 共用。
    ///
    /// **建失败时不再直接 `fatalError`。**
    ///
    /// 原来这里只有一句 `fatalError("数据容器创建失败")`，想法是对的 ——
    /// 不要静默退回内存库，那会让用户以为数据存下来了、重启后发现全没了。
    /// 但代价在 2026-09-15 显出来了：**贵到离谱**。
    /// 导入配图时一次保存中途被打断，库停在自相矛盾的状态上，
    /// 此后每次点图标都在这一行崩 —— 用户看到的是「连 APP 都打不开了」，
    /// 而且他没有任何办法区分「重装能好」还是「重装会丢数据」，只能干瞪眼。
    ///
    /// 现在分两级，只有第二级才崩：
    ///   ① 先照常开；开不了 → ② 把整份库文件挪到一边、新建一份空的（数据还在盘上，
    ///      见 `HerInfoStore.containerAfterSettingAsideBrokenStore`，而且**会如实告诉用户**）；
    ///   ③ 连新建都失败（磁盘满 / 沙盒异常）→ 这时崩是诚实的，因为没别的可做了。
    /// **守门这一步必须排在打开库之前**（`LaunchGuard.begin()` 在第一行）——
    /// 保守启动的第三级是「把库整份挪走再新建」，而库一旦被 SwiftData 打开，
    /// 再挪就等于把那个连接指向一个不存在的文件。
    private let container: ModelContainer = {
        let mode = LaunchGuard.begin()

        // 上一轮连保守启动都没走完 → 库整份挪走、新建一份空的。
        // 挪走而不是删掉：数据还在盘上，而且**会如实告诉用户**
        // （见 `HerInfoStore.storeResetKey` 与 `announceStoreResetIfAny`）。
        if mode == .rebuild,
           let fresh = HerInfoStore.containerAfterSettingAsideBrokenStore() {
            return fresh
        }

        if let ok = try? HerInfoStore.container() { return ok }
        if let fresh = HerInfoStore.containerAfterSettingAsideBrokenStore() { return fresh }
        fatalError("数据容器创建失败：磁盘或沙盒异常")
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(nil)   // 跟随系统；23 屏的三态开关在这里接管
                .task {
                    // 启动时重排一次提醒 —— 重装 / 重启 / 系统清理都会丢掉待发通知，
                    // 而用户以为提醒还在。这是最容易漏、后果最重的一步。
                    await bootstrap()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // 回到前台也要收一次收件箱：用户完全可能开着 App 的时候
            // 在锁屏上打了一个标再切回来。
            guard phase == .active else { return }
            drainInbox()
        }
    }

    @MainActor
    private func bootstrap() async {
        let ctx = container.mainContext

        // ⓪ **这次是不是保守启动。**
        //
        // 判据在 `LaunchGuard`：上一次启动后 5 秒内就没了（崩了，或被手动杀掉），
        // 这一次就走保守路径。**保守路径的定义是「只保留让界面能开的最小集」**，
        // 跳过下面四件会碰模型对象的事：
        //
        //   · 老库配图的回填      → 不跳（见展开说明）
        //   · 回收站 30 天清理    → 跳过
        //   · 提醒重排            → 跳过
        //   · 孤儿图片清理        → 跳过
        //
        // 为什么这四件可以跳过：它们的共同点是**晚一次没有后果**。
        // 提醒下一次启动会重排；回收站里的记录多留一次启动，不损失什么
        // （那一步本来就是「30 天后清理」，不是「必须第 30 天清理」）；
        // 孤儿图片多占一次启动的磁盘，也一样。
        // 而它们全都要读模型对象 —— 那正是把 App 拖死在启动路径上的东西。
        //
        // **收件箱（`drainInbox`）不跳**：它是「锁屏上打的那个标」唯一一次
        // 落库的机会，跳过就是丢用户刚给过的信号。UI 也不跳（它不在这儿）。
        //
        // 一句话：宁可这一轮少做四件事，也要让屏幕先亮起来。
        let safe = LaunchGuard.isSafe

        // ① 把老库的配图搬进标量（一次性）。**两种模式都做。**
        //
        // 它是保守名单里唯一不跳的一步，理由有两条：
        //   · 它**只读 `Revision`（标量）写 `Record`（标量）**，全程不碰 `Photo`
        //     这个模型对象 —— 而三份崩溃日志的共同点恰恰是「读 `Photo`」；
        //   · 它的收益是「用户的配图还在不在」。回填不成功，用户升级上来看到的
        //     是一份没有配图的档案（文件都还在沙盒里，只是没人知道它们属于谁）。
        //     这个代价比「少重排一次提醒」大得多。
        HerInfoStore.backfillPhotoHashes(in: ctx)

        // 库被挪走重建过 → **如实说一句**。不是静默换一个空库。
        announceStoreResetIfAny()
        announceSafeLaunchIfAny(safe)

        // **不再在首次启动写「示例数据」。**
        //
        // 这里以前会插入一个叫「小满」的档案 + 4 条记录 + 1 条提醒，
        // 后果是：用户第一次打开 App，看到的是别人的女朋友，
        // 而「她叫什么」这个问题一次都没被问过。
        // 15 屏（先告诉我，她是谁）就是为了把这个起点补上 ——
        // 所以现在首次启动看到的是引导，不是一份假的档案。
        //
        // 想在真机上看有数据的样子：启动参数加 `-hi-seed`
        // （Xcode → Scheme → Arguments Passed On Launch，或 `xcrun simctl launch … -hi-seed`）。
        // 那是**开发者的显式动作**，不再是一个用户看不见的默认行为。
        if ProcessInfo.processInfo.arguments.contains("-hi-seed") {
            let existing = (try? ctx.fetchCount(FetchDescriptor<Record>())) ?? 0
            if existing == 0 { HerInfoStore.seed(ctx) }
        }

        let all = (try? ctx.fetch(FetchDescriptor<Record>())) ?? []

        if !safe {
            // ② 回收站 30 天到期清理。**必须在清孤儿图片之前** ——
            // 先让记录真的消失，它引用的图片才会在同一次启动里被扫成孤儿。
            // 这一步是在兑现 27 屏印在屏幕上的那句「30 天后自动清掉」。
            //
            // 它同时是最需要保守模式兜底的一步：它是**级联删除**（提醒行）。
            //
            // > 2026-09-15 更正：这里原来写着「级联会顺着 `photos` 关系碰到老库里的
            // > `Photo` 行」—— 那两个关系已经删掉了，这层风险没有了。
            // > 保守模式仍然跳过这一步，剩下的理由是：**「删数据」这件事本身
            // > 就该排在「能打开」之后** —— 不是因为它现在会崩。
            HerInfoStore.cleanupExpiredTrash(in: ctx)

            // ③ 重排提醒。卸载重装、重启、系统清理都会丢掉待发通知，
            // 而用户以为提醒还在。这是最容易漏、后果最重的一步。
            ReminderService.shared.rescheduleAll(all)
        }

        // ④ 清掉没有任何地方引用的图片文件。
        //
        // **只在启动时做一次**，理由见 `PhotoStore.purgeOrphans`：
        // 「一张图什么时候可以删」要在四个地方分别判断对（移除配图 / 清空回收站 /
        // 删记录 / 恢复历史版本），太容易漏一个；按「现有引用全集」扫一遍不会误删。
        //
        // **回填没做完就绝不做这一步。** 引用全集是从 `Record.photoHashes` 数的，
        // 而老库这一列在回填之前是空的 —— 那时候扫一遍等于把用户所有配图
        // 当成孤儿删掉。宁可让孤儿多占一会儿磁盘，也不能有一次误删。
        let backfilled = UserDefaults.standard.bool(forKey: HerInfoStore.photoBackfillKey)
        if !safe, backfilled {
            let revisions = (try? ctx.fetch(FetchDescriptor<Revision>())) ?? []
            let avatar = (try? ctx.fetch(FetchDescriptor<Profile>()))?.first?.avatarHash
            PhotoStore.purgeOrphans(keeping: PhotoStore.referencedHashes(records: all,
                                                                         revisions: revisions,
                                                                         avatar: avatar))
        }

        // ⑤ 「这次启动真的走完了」。
        //
        // **故意延后 5 秒，而不是紧跟在后面。** 用户报的「一点进去直接闪退」
        // 很可能发生在首屏渲染时 —— 那已经在 `bootstrap()` 之后了。
        // 只认 `bootstrap()` 走完的话，这类崩溃永远不会被记下来，
        // 保守启动也就永远不会触发，等于这一层白写。
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            LaunchGuard.finish()
        }

        drainInbox()
    }

    /// 「库打不开、已经把它挪到一边、现在用的是一份新的」——
    /// 这件事必须让用户知道。
    ///
    /// 否则他看到的是「我的记录全没了」，而 App 一声不吭 —— 那比崩还让人难受：
    /// 崩了他知道出事了，静默清空他会以为自己记错了、或者怪到手机上。
    ///
    /// 只说一次（说完清标记）。**盘上的 `broken-<时间戳>/` 目录一个字节都不动** ——
    /// 数据还在设备上，真要找回有据可查，所以文案里要把这一点说出来，
    /// 而不是只说一句「已重置」。这两个字（未删）才是用户真正的定心丸。
    @MainActor
    private func announceStoreResetIfAny() {
        let d = UserDefaults.standard
        guard d.string(forKey: HerInfoStore.storeResetKey) != nil else { return }
        d.removeObject(forKey: HerInfoStore.storeResetKey)
        ToastCenter.shared.show("数据库曾打不开，已移到一边并新建（旧数据未删）")
    }

    /// 「这一次是以保守模式起来的」—— 也要说一句。
    ///
    /// 不说的话有个更难查的后果：用户会发现**提醒少了一次**、**回收站里的东西
    /// 该消失的没消失**，而 App 一声不吭 —— 那是「静默降级」，
    /// 和「静默换一个空库」是同一种毛病。说了之后，用户至少知道
    /// 「它知道自己出过问题，下一次会补上」。
    ///
    /// 安全模式下 `finish()` 会在 5 秒后把模式复位，所以这一句最多出现一次。
    @MainActor
    private func announceSafeLaunchIfAny(_ safe: Bool) {
        guard safe else { return }
        ToastCenter.shared.show("上次启动没能走完，这次先保证能打开（部分整理已跳过）")
    }

    /// 把三个系统级入口记下的东西落成真正的数据。
    ///
    /// **启动与每次回前台各一次** —— 用户完全可能在 App 从没打开过的情况下，
    /// 只在锁屏上打了个标、或从别处分享了一段话进来，
    /// 那些东西一直躺在队列里等这一步。
    @MainActor
    private func drainInbox() {
        let ctx = container.mainContext
        // ① 通知扩展丢进共享收件箱的打标（跨进程，走 App Group）
        HerInfoStore.drainMoodInbox(into: ctx)
        // ② 长按图标 / 快捷指令记下的打标（不跨进程，走普通 UserDefaults）
        HerInfoStore.drainQuickMood(into: ctx)
        // ③ 分享扩展送进来的记录（跨进程，走 App Group）
        //
        // **落了东西才弹提示。** 这是分享这条路唯一需要主 App 配合的地方：
        // 分享扩展存完就退场了，用户在 App 里看不到任何痕迹，
        // 而「刚才存下来了没有」正是分享之后最想确认的一件事。
        // 提示里的条数是**数出来的**，不是写死的。
        let shared = HerInfoStore.drainShareInbox(into: ctx)
        if shared > 0 {
            ToastCenter.shared.show(shared == 1
                                    ? "已存下分享的 1 条"
                                    : "已存下分享的 \(shared) 条")
        }
    }
}

// MARK: - 长按 App 图标

/// 处理长按图标菜单里被点中的那一项。
///
/// 两个回调都要接，缺一个就有半条路是哑的：
///   · `performActionFor` —— App 已经在后台时走这里；
///   · `didFinishLaunching` 的 `launchOptions` —— App **没在运行**时走这里。
///
/// 而第二种恰恰是最常用的路径（这个 App 平时不在后台挂着），
/// 只接 `performActionFor` 的话，「杀进程之后长按图标打标」会静默失效。
/// 两个都接带来的重复风险，由 `HerInfoStore.notePendingMood` 里那道
/// 2 秒去重护栏兜住 —— 与其赌系统的回调行为，不如让记一次这件事本身幂等。
final class QuickActionDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                        [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            HerInfoStore.acceptQuickAction(item.type)
        }
        return true
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        // 返回它是否被处理了 —— 认不出来的 type 要如实回 false，
        // 而不是一律回 true 把问题吞掉。
        completionHandler(HerInfoStore.acceptQuickAction(shortcutItem.type))
    }
}
