//
//  HerInfoApp.swift
//  她的信息本 · 应用入口
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

@main
struct HerInfoApp: App {

    @Environment(\.scenePhase) private var scenePhase

    /// 一个容器，全 App 共用。
    /// 建失败时**不要静默退回内存库** —— 那会让用户以为数据存下来了，
    /// 重启后发现全没了。宁可崩在一个说得清的地方。
    private let container: ModelContainer = {
        do {
            return try HerInfoStore.container()
        } catch {
            fatalError("数据容器创建失败：\(error)")
        }
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
        HerInfoStore.cleanupExpiredTrash(in: ctx)

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
        //   ① 记录自己的配图 ② 历史版本里存的图快照 ③ 头像
        // 这里用的 `all` 是**不过滤删除状态的** —— 回收站里的记录还能恢复，
        // 它的配图当然还得留着。
        let revisions = (try? ctx.fetch(FetchDescriptor<Revision>())) ?? []
        let avatar = (try? ctx.fetch(FetchDescriptor<Profile>()))?.first?.avatarHash
        PhotoStore.purgeOrphans(keeping: PhotoStore.referencedHashes(records: all,
                                                                     revisions: revisions,
                                                                     avatar: avatar))

        drainInbox()
    }

    /// 把通知扩展丢进共享收件箱的打标落成真正的记录。
    /// **启动与每次回前台各一次** —— 用户可能在 App 从没打开过的情况下，
    /// 只在锁屏上打了标，那些打标一直躺在收件箱里等这一步。
    @MainActor
    private func drainInbox() {
        HerInfoStore.drainMoodInbox(into: container.mainContext)
    }
}
