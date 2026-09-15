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
    private let container: ModelContainer = {
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

        // ⓪ **先自愈关系表，必须排在最前面。**
        //
        // 库里可能留着「墓碑 `Photo`」：行已经不在库里了，却还挂在
        // `Record.photos` 这个关系里。它是「只 `ctx.delete(p)`、不先把 `p.record`
        // 摘掉」留下的，而它一旦留在关系里，后果是成对出现的：
        //   · 编辑那条记录 → 保存时读 `Photo.hash` → 崩（用户报的那个闪退）；
        //   · **下一次启动** → 启动流程里读 `record.photos` → 还是崩，
        //     用户看到的就是第二句「连 APP 都打不开了」。
        // 两个源头都已修（`RecordEditorView.save` / `VersionHistoryView.restore`），
        // 这一步清的是历史遗留 —— 不清掉它，老用户升级上来照样打不开。
        HerInfoStore.repairPhotoLinks(in: ctx)

        // 库被挪走重建过 → **如实说一句**。不是静默换一个空库。
        announceStoreResetIfAny()

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

        // 回收站 30 天到期清理。**必须在清孤儿图片之前** ——
        // 先让记录真的消失，它引用的图片才会在同一次启动里被扫成孤儿。
        // 这一步是在兑现 27 屏印在屏幕上的那句「30 天后自动清掉」。
        //
        // **关系表不可信时跳过**（见 `HerInfoStore.photoLinksTrustworthy`）：
        // 它是级联删除，会顺着 `Record.photos` 往下走。那种状态下宁可这一轮不清理
        // （记录多留一次启动，无害），也不在一条来路不明的关系上做删除。
        // 这个分支实际上很少走到：`false` 只在「自愈动到一半就崩了」时出现，
        // 而那种崩溃会连带让库开不了 → 走容器兜底 → 换上来的是空库，压根没有关系表。
        if HerInfoStore.photoLinksTrustworthy {
            HerInfoStore.cleanupExpiredTrash(in: ctx)
        }

        // 重排提醒
        let all = (try? ctx.fetch(FetchDescriptor<Record>())) ?? []
        ReminderService.shared.rescheduleAll(all)

        // 清掉没有任何地方引用的图片文件。
        //
        // **只在启动时做一次**，理由见 PhotoStore.purgeOrphans：
        // 「一张图什么时候可以删」要在四个地方分别判断对（移除配图 / 清空回收站 /
        // 删记录 / 恢复历史版本），太容易漏一个；按「现有引用全集」扫一遍不会误删。
        //
        // 三处引用都要算上，**少算一处就会把还在用的图删掉**：
        //   ① 配图行本身 ② 历史版本里存的图快照 ③ 头像
        //
        // ① 是**从 `Photo` 表取的**，不是从 `record.photos` 关系取的 ——
        // 关系里可能挂着墓碑（同上），而这一步跑在启动流程里，崩了就是 App 打不开。
        // 两边集合等价：`hash` 本来就在 `Photo` 行上。而且这里**不过滤记录是否在回收站**：
        // 回收站里的记录还能恢复，它的配图当然还得留着。
        let revisions = (try? ctx.fetch(FetchDescriptor<Revision>())) ?? []
        let photos = (try? ctx.fetch(FetchDescriptor<Photo>())) ?? []
        let avatar = (try? ctx.fetch(FetchDescriptor<Profile>()))?.first?.avatarHash
        PhotoStore.purgeOrphans(keeping: PhotoStore.referencedHashes(photos: photos,
                                                                     revisions: revisions,
                                                                     avatar: avatar))

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
