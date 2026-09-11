//
//  ReminderService.swift
//  提醒落地：本地通知 + 地理围栏
//
//  这一层是设计与 iOS 真实能力之间的**唯一翻译处**。
//  设计稿里「定时 / 场景」的两分法，到这里变成两套完全不同的系统 API：
//    定时 → UNCalendarNotificationTrigger（离线的、纯本地的、数量几乎不限）
//    场景 → CLCircularRegion（系统级限制：单 App 最多 20 个）
//
//  20 这个数字不是实现细节，它已经改变了设计（05 屏要显示「已用 3/20」）。
//  所以它写在代码里、也写在交接文档里，避免下一个人把它当成可调参数。
//
//  【与锁屏通知扩展的分工】这一层负责「让通知准时响、并且带上够用的信息」；
//  「展开后长什么样」是 HerInfoNotification 那个 target 的事。
//  两边的接口只有一处：`HINotify` 契约里的分类 id、动作 id、userInfo 键。
//

import Foundation
import UserNotifications
import CoreLocation
import SwiftData
import UIKit

@MainActor
final class ReminderService: NSObject {
    static let shared = ReminderService()

    /// iOS 单 App 能同时监听的区域数量上限。**这是系统常量，不是我们选的。**
    static let maxGeofences = 20

    private let center = UNUserNotificationCenter.current()
    private let location = CLLocationManager()

    private override init() {
        super.init()
        center.delegate = self
        location.delegate = self
        // 分类必须在排第一条通知之前注册。没有它，通知照常弹，
        // 只是展开后没有「1 小时后 / 今天不用了」两个按钮 —— 同样不报错。
        registerCategories()
    }

    // MARK: - 权限

    /// 通知权限。**一辈子只问一次机会** ——
    /// 用户点了「不允许」就再也没有第二次，所以 16 屏把「不读取聊天记录」
    /// 直接印在了请求页上：用户敢点允许，靠的是那句话。
    func requestNotificationPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func requestLocationPermission() async -> CLAuthorizationStatus {
        location.requestWhenInUseAuthorization()
        return location.authorizationStatus
    }

    /// 被拒之后不能问第二次，只能引导去设置（对应 24 屏）。
    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 注册通知分类

    /// 分类与动作。
    ///
    /// 动作只放两个，且都是**后台动作**（不带 `.foreground`）：
    /// 锁屏上该做的是「轻决定」—— 推迟、今天不用了。
    /// 打标需要先看一眼内容再选，所以它属于**展开态**，由扩展视图自己画。
    /// 这个分法和 14 屏脚注那句「上滑查看，长按可直接打标」是同一件事。
    private func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: HINotify.Action.snoozeOneHour,
            title: "1 小时后",
            options: [])
        let done = UNNotificationAction(
            identifier: HINotify.Action.doneToday,
            title: "今天不用了",
            options: [])

        let category = UNNotificationCategory(
            identifier: HINotify.reminderCategory,
            actions: [snooze, done],
            intentIdentifiers: [],
            options: [])

        center.setNotificationCategories([category])
    }

    // MARK: - 额度

    /// 已占用的场景点数。05 / 32 屏那句「已用 3 / 20」应该读它，而不是写死一个 3。
    var usedGeofences: Int { location.monitoredRegions.count }

    // MARK: - 排程

    func schedule(_ reminder: Reminder) async {
        guard reminder.isOn else { return }

        switch reminder.kind {
        case .date: await scheduleDate(reminder)
        case .geo:  scheduleGeo(reminder)
        }
    }

    private func scheduleDate(_ r: Reminder) async {
        let content = UNMutableNotificationContent()
        content.title = r.title
        content.body = r.previewLine        // 与 32 屏「通知预览」逐字一致
        content.sound = .default
        // 分类决定「长按展开后有没有按钮、走不走扩展」——
        // 它就是主 App 与通知扩展之间那根唯一的线。
        content.categoryIdentifier = HINotify.reminderCategory
        content.userInfo = Self.userInfo(for: r)
        attachFirstPhoto(of: r, to: content)

        var comps = Calendar.current.dateComponents([.hour, .minute], from: r.time)

        // 提前量在这里生效：把触发时刻整体往前挪。
        // 设计上「提前 10 分钟」是用户要的余量，落到系统里就是触发时间 −10min。
        if r.leadMinutes > 0 {
            var d = Calendar.current.date(from: comps) ?? .now
            d.addTimeInterval(-Double(r.leadMinutes) * 60)
            comps = Calendar.current.dateComponents([.hour, .minute], from: d)
        }

        switch r.repeatRule {
        case .none:    break
        case .daily:   break                       // 只有 hour/minute，天然就是每天
        case .weekly:  comps.weekday = r.weekday
        case .monthly: comps.day = r.dayOfMonth
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: comps,
            repeats: r.repeatRule != .none
        )

        let req = UNNotificationRequest(identifier: r.id, content: content, trigger: trigger)
        try? await center.add(req)
    }

    private func scheduleGeo(_ r: Reminder) {
        guard let lat = r.latitude, let lon = r.longitude else { return }

        // 额度检查。到顶后**必须走开关式管理**，不能静默失败 ——
        // 静默失败的表现是「设了提醒但从来不会响」，那是最坏的一种 bug。
        let monitored = location.monitoredRegions
        guard monitored.count < Self.maxGeofences else {
            // 05 屏应当在这里给出「已用 20/20，先关掉一个」的提示
            return
        }

        // 已经在监听同一个 id 就不要再监一次。
        // 重复 startMonitoring 同一个 identifier 不报错、也不会更新半径 ——
        // 「以为改了半径其实没改」是最难查的一类问题。
        guard !monitored.contains(where: { $0.identifier == r.id }) else { return }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            radius: r.radius,
            identifier: r.id
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false        // 只在进入时提醒 —— 离开时不打扰
        location.startMonitoring(for: region)
    }

    /// 撤掉一条提醒。
    ///
    /// 注意第二段：用户点过「1 小时后」之后，系统里多了一条 **snooze_ 前缀的副本**。
    /// 只按原 id 撤是不够的 —— 那样「关掉提醒之后它还响一次」，
    /// 而这类 bug 极难复现（要先点过推迟、再关开关、还要等到点）。
    func cancel(_ reminder: Reminder) async {
        center.removePendingNotificationRequests(withIdentifiers: [reminder.id])

        let prefix = "snooze_\(reminder.id)_"
        let copies = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        if !copies.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: copies)
        }

        if let region = location.monitoredRegions.first(where: { $0.identifier == reminder.id }) {
            location.stopMonitoring(for: region)
        }
    }

    /// 启动时重排一次。**必须做** ——
    /// 卸载重装、重启、系统清理都会丢掉待发通知，而用户以为提醒还在。
    func rescheduleAll(_ records: [Record]) {
        for r in records.compactMap(\.reminder) where r.isOn {
            Task { await schedule(r) }
        }
    }

    // MARK: - 通知里带什么

    /// 载荷。键名全部来自 `HINotify.Key` ——
    /// 扩展那一侧就是照这些键读的，写错一个的表现是「展开后少一块」。
    private static func userInfo(for r: Reminder) -> [String: Any] {
        var info: [String: Any] = [
            HINotify.Key.title:      r.title,
            HINotify.Key.body:       r.previewLine,
            HINotify.Key.reminderID: r.id,
            HINotify.Key.version:    r.record?.version ?? 1,
            HINotify.Key.photoCount: r.record?.photos.count ?? 0
        ]
        if let rid = r.record?.id { info[HINotify.Key.recordID] = rid }
        // rawValue 与 HINotify.Cat 的 case 名一致（like / trait_ / care / hate）
        if let cat = r.record?.cat.rawValue { info[HINotify.Key.cat] = cat }
        return info
    }

    /// 把记录的第一张配图挂到通知上。
    ///
    /// 走 `UNNotificationAttachment`：**系统会把文件拷进这条通知自己的目录**，
    /// 所以扩展读得到，而我们不需要为图片开共享容器。
    /// 找不到文件就安静跳过 —— 一条没配图的提醒仍然是一条完整的提醒。
    private func attachFirstPhoto(of r: Reminder, to content: UNMutableNotificationContent) {
        guard let hash = r.record?.photos.sorted(by: { $0.order < $1.order }).first?.hash,
              let url = Self.photoURL(hash),
              let att = try? UNNotificationAttachment(identifier: "photo",
                                                      url: url,
                                                      options: nil)
        else { return }
        content.attachments = [att]
    }

    /// 图片在沙盒里的位置。
    ///
    /// **路径的唯一真相是 `PhotoStore.url(for:)`** —— 这里以前又自己拼了一遍
    /// `Documents/Photos/<hash>.jpg`。两处一旦不一致，通知就没有配图，
    /// 而那是典型的「不报错」的故障：通知照常响，只是缺一张图，
    /// 没人会想到是路径拼错了。同一件事只应该有一个定义处。
    static func photoURL(_ hash: String) -> URL? {
        PhotoStore.exists(hash) ? PhotoStore.url(for: hash) : nil
    }
}

// MARK: - 通知到达

extension ReminderService: UNUserNotificationCenterDelegate {

    /// 前台也显示。这个 App 的通知不是「打扰」，是它存在的意义 ——
    /// 用户很可能正开着它等这条提醒。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// 点通知 / 点通知上的按钮。
    ///
    /// 这个方法**特意写成 nonisolated**：它由系统在它自己的队列上调用，
    /// 声明成 nonisolated 才不会和类上的 @MainActor 打架（这是 Swift 6 严格并发下
    /// 最容易报错的地方之一）。需要碰状态时再显式 `await` 跳回主线程。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // 只取出 Sendable 的纯值再跨界 —— 不要把 userInfo 那个字典带过去。
        let content = response.notification.request.content
        let title = content.title
        let body = content.body
        let reminderID = content.userInfo[HINotify.Key.reminderID] as? String
        let recordID = content.userInfo[HINotify.Key.recordID] as? String

        switch response.actionIdentifier {
        case HINotify.Action.snoozeOneHour:
            // 场景提醒是「到地方才响」，推迟它没有语义 —— 只对定时提醒生效。
            guard let reminderID else { return }
            await snooze(reminderID: reminderID, recordID: recordID,
                         title: title, body: body)

        case HINotify.Action.doneToday:
            guard let reminderID else { return }
            // 不在这里动数据库：只发一个意图，由 App 侧落库。
            NotificationCenter.default.post(name: .reminderDone, object: reminderID)

        default:
            // 直接点通知 → 带着 recordID 回到那条记录（32 屏脚注承诺的行为）。
            if let recordID {
                NotificationCenter.default.post(name: .openRecord, object: recordID)
            }
        }
    }

    /// 「1 小时后」。**产生的是另一条通知**（identifier 前缀 `snooze_`），
    /// 所以它不会覆盖原来那条，原提醒的开关也还留着。
    /// 撤原提醒时会把副本一起撤掉 —— 见 `cancel(_:)`。
    @MainActor
    private func snooze(reminderID: String, recordID: String?,
                        title: String, body: String) async {
        let fire = Date.now.addingTimeInterval(60 * 60)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // 保持同一个分类：推迟之后还能再推迟一次、还能「今天不用了」。
        content.categoryIdentifier = HINotify.reminderCategory
        var info: [String: Any] = [
            HINotify.Key.title: title,
            HINotify.Key.body: body,
            HINotify.Key.reminderID: reminderID
        ]
        if let recordID { info[HINotify.Key.recordID] = recordID }
        content.userInfo = info

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fire)

        let req = UNNotificationRequest(
            identifier: "snooze_\(reminderID)_\(Int(fire.timeIntervalSince1970))",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))

        try? await center.add(req)
    }
}

// MARK: - 进出场景

extension ReminderService: CLLocationManagerDelegate {

    /// 进入场景点。**这类回调必须是 nonisolated** ——
    /// CoreLocation 在它自己的线程上回调，声明成主线程隔离会编译不过。
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didEnterRegion region: CLRegion) {
        guard let r = region as? CLCircularRegion else { return }

        let content = UNMutableNotificationContent()
        content.title = "到你常去的地方了"
        content.body = "这里有你记过的事"
        content.sound = .default
        content.categoryIdentifier = HINotify.reminderCategory
        content.userInfo = [HINotify.Key.recordID: r.identifier]

        let req = UNNotificationRequest(
            identifier: "geo_\(r.identifier)_\(Int(Date.now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        // `add` 是 async throws —— 这里必须放进 Task 里 await，
        // 直接从同步回调里调用是编译不过的（早期版本就错在这里）。
        Task { try? await UNUserNotificationCenter.current().add(req) }
    }
}

extension Notification.Name {
    /// 点通知 → 跳记录。RootView 监听它来推路由。
    static let openRecord = Notification.Name("HerInfo.openRecord")

    /// 通知上的「今天不用了」。**ReminderService 只发这个意图，不自己动数据库** ——
    /// 排程与存储是两件事，让一个对象同时管两件，改一处就会碰到另一处。
    static let reminderDone = Notification.Name("HerInfo.reminderDone")
}
