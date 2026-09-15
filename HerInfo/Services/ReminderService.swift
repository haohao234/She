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

    /// 等定位授权结论的那一次 `await`。见 `requestLocationPermission()`。
    ///
    /// 只可能有一个在等（授权弹窗全局只有一个），所以用一个可选值而不是数组 ——
    /// 数组会让人以为「可以并发等多次」，那个假设不成立。
    private var locationAuthContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    /// 等「取一次位置」的那一次 `await`。见 `currentCoordinate()`。
    private var locationOnceContinuation: CheckedContinuation<CLLocation?, Never>?

    /// 「这条排不上」这类话一次启动只说一次。见 `warnCannotSchedule(_:)`。
    private var didWarnSchedule = false

    private override init() {
        super.init()
        center.delegate = self
        location.delegate = self
        // 围栏的尺度是 200~500 米，所以要的是「百米级」而不是「最佳精度」——
        // 后者会连 GPS 一起唤醒，为了一个几百米的圈白耗电。
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // 分类必须在排第一条通知之前注册。没有它，通知照常弹，
        // 只是展开后没有「1 小时后 / 今天不用了」两个按钮 —— 同样不报错。
        registerCategories()
    }

    // MARK: - 权限

    /// 通知权限的**真实**状态。
    ///
    /// > 2026-09-15 补的一处硬伤。此前全工程**从不读它** ——
    /// > 设置页那个「到点提醒我」开关读的是一个 `@AppStorage` 布尔
    /// > （默认 `true`，而**没有任何地方写过它**），所以真实情况是
    /// > 「用户明明拒了通知，开关却一直显示开」；同时所有 `center.add()`
    /// > 都写成 `try?`，没权限时**静默失败**。
    /// > 两者叠起来，用户看到的就是他报的那句话：
    /// > **提醒设好了，但一次都没响过，App 也一声不吭。**
    func notificationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 「现在还能不能发通知」。
    ///
    /// `.provisional` 也算能 —— 它只是不静默弹横幅，通知照样进通知中心。
    /// `.ephemeral`（App Clip）不在本 App 的讨论范围，但按「能发」处理更安全：
    /// 真正要紧的是 `.denied` 与 `.notDetermined` 这两种「发不出去」。
    func canNotify() async -> Bool {
        let s = await notificationStatus()
        return s == .authorized || s == .provisional || s == .ephemeral
    }

    /// **只在「还没问过」时才弹系统框。这一条是提醒能不能响的关键。**
    ///
    /// iOS 的通知授权一辈子只问一次，所以「什么时候问」比「问什么」重要得多。
    /// 此前唯一的请求点在 15/16 屏首次引导，而它由 `hasOnboarded` 控制 ——
    /// 那个标记一旦为 true 就再也不会回到引导页。后果是：
    /// **装过一次 App 的人，此后新建多少条提醒都不会被问第二次**，
    /// 权限停在 `.notDetermined`，`add()` 全部静默失败。
    ///
    /// 现在把它挂到「用户真的要一条提醒」这个时刻上 ——
    /// 那是授权意愿最强的瞬间，也是系统框即便被拒也不显得莫名其妙的时机。
    /// 不重复问的理由见上：`.denied` 之后 `requestAuthorization` 不弹框、
    /// 直接返回 false，再调多少次都没用，唯一的出路是引导去设置（24 屏）。
    @discardableResult
    func requestNotificationPermissionIfNeeded() async -> UNAuthorizationStatus {
        let before = await notificationStatus()
        guard before == .notDetermined else { return before }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await notificationStatus()
    }

    /// 15/16 屏首次引导用。
    ///
    /// 语义与 `requestNotificationPermissionIfNeeded` 完全一致 ——
    /// 保留这个「不问条件、直接要一个 Bool」的名字，是因为引导页那个按钮
    /// 读起来就是这个意思，而首次引导时权限必然是 `.notDetermined`。
    func requestNotificationPermission() async -> Bool {
        let s = await requestNotificationPermissionIfNeeded()
        return s == .authorized || s == .provisional || s == .ephemeral
    }

    /// 请求「使用期间」定位权限。
    ///
    /// **不能像以前那样「调一下、立刻读 `authorizationStatus`」** ——
    /// `requestWhenInUseAuthorization()` 只是把系统弹窗排上队就立刻返回，
    /// 紧接着读到的还是 `.notDetermined`。那样写出来的代码
    /// 「看着请求了、其实什么也没等到」，而调用方会把那个 `.notDetermined`
    /// 误判成「用户拒绝了」。
    ///
    /// 这里用 continuation 等回调：系统只在**真正有结论**时才调
    /// `locationManagerDidChangeAuthorization`（包括「本来早就授权过」这一次）。
    func requestLocationPermission() async -> CLAuthorizationStatus {
        let now = location.authorizationStatus
        guard now == .notDetermined else { return now }
        return await withCheckedContinuation { cont in
            locationAuthContinuation = cont
            location.requestWhenInUseAuthorization()
        }
    }

    /// 被拒之后不能问第二次，只能引导去设置（对应 24 屏）。
    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 取一次当前位置

    /// 取当前位置的坐标。
    ///
    /// **返回 nil 表示拿不到，调用方必须把这件事说出来** ——
    /// 拿不到坐标还存下去的场景提醒，是一条永远不会响的提醒，
    /// 而界面上它看起来完全正常。这正是这个功能此前的状态。
    ///
    /// 为什么自己实现一个「取一次」：`CLLocationManager` 的常规用法是持续回调，
    /// 而这里要的是「按一下、拿一个点、结束」—— `requestLocation()` 正好是这个语义
    /// （取到一次就自动停，不持续唤醒定位）。
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        let auth = await requestLocationPermission()
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else { return nil }

        let loc: CLLocation? = await withCheckedContinuation { cont in
            locationOnceContinuation = cont
            location.requestLocation()
        }
        return loc?.coordinate
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

    // MARK: - 默认时间（12 屏「默认提醒时间」）

    /// 全 App 新建提醒时的默认时刻。**设计稿给的是 20:30**（12 屏那一行），
    /// 而代码里此前写死成 20:00、且没有任何地方可以改 ——
    /// 那正是用户报的「想修改提醒时间，发现无法修改」。
    ///
    /// 存的是「从零点起的分钟数」，不是 `Date`：
    /// 这里要的是**一天里的一个时刻**，不是一个时间点。
    /// 存 `Date` 会让它在夏令时切换、时区变化时漂掉，而分钟数是绝对的。
    /// 读回来时用「今天 + 该分钟数」重建，得到的就是一个干净的「今天 20:30」。
    /// 标 `nonisolated`：View 的属性初始化器里就要读到它
    /// （`@State private var defaultTime = ReminderService.defaultTime`），
    /// 而属性初始化器跑在 View 的 `init` 里、不是 `body` 里，不在主 actor 上。
    /// 它只读 `UserDefaults`，没有任何需要隔离的状态。
    nonisolated static var defaultTime: Date {
        let d = UserDefaults.standard
        guard d.object(forKey: defaultTimeKey) != nil else {
            return Calendar.current.date(from: DateComponents(hour: 20, minute: 30)) ?? .now
        }
        let minutes = max(0, min(24 * 60 - 1, d.integer(forKey: defaultTimeKey)))
        return Calendar.current.date(from: DateComponents(hour: minutes / 60,
                                                          minute: minutes % 60)) ?? .now
    }

    nonisolated static func setDefaultTime(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        UserDefaults.standard.set((c.hour ?? 20) * 60 + (c.minute ?? 30),
                                  forKey: defaultTimeKey)
    }

    /// 带 `hi.` 前缀，与 `LaunchGuard` / `PhotoStore` 那几个自用键的命名一致 ——
    /// 这个前缀在本工程里的含义是「内部状态，不是设计令牌」。
    nonisolated private static let defaultTimeKey = "hi.reminder.defaultTime"

    // MARK: - 额度

    /// 已占用的场景点数。05 / 32 屏那句「已用 3 / 20」应该读它，而不是写死一个 3。
    ///
    /// 读的是**系统真的在监听几个**（`monitoredRegions`），不是「模型里有几条」——
    /// 这两者在权限被拒时会分叉（模型里有 3 条、系统一个也没监听），
    /// 而这一行要回答的是「还剩多少额度可用」，那就该以系统的答案为准。
    /// 权限被拒这件事由设置页那一行与 24 屏负责说，不在这里混着说。
    var usedGeofences: Int { location.monitoredRegions.count }

    // MARK: - 排程

    /// - Parameter photoIndex: 「记录 id → 配图 hash（已按 order 排好）」的索引。
    ///   批量重排时由 `rescheduleAll` 建一次、所有提醒共用；单条排程传 nil，
    ///   函数自己按 `reminder.modelContext` 现建一份。
    ///   **索引存在的唯一理由是：不要去读 `record.photos` 那个关系**（见 `photoIndex(from:)`）。
    func schedule(_ reminder: Reminder, photoIndex: [String: [String]]? = nil) async {
        guard reminder.isOn else { return }

        // **先问权限，再排。**
        //
        // 权限没给时 `center.add()` 会失败，而失败一旦被 `try?` 吞掉，
        // 表现就是「提醒设好了、永远不响、App 一声不吭」—— 这个功能此前的病根之一。
        // 排不下去就**别装作排上了**：发一条意图出去，由 UI 提示并引导去设置（24 屏）。
        //
        // 场景那一路也要看通知权限：地理围栏的进入事件最终是靠一条本地通知
        // 说出来的（`didEnterRegion` 里那次 `add`），没权限它同样白响一场。
        guard await canNotify() else {
            warnCannotSchedule("通知权限没打开，提醒发不出去")
            return
        }

        switch reminder.kind {
        case .date: await scheduleDate(reminder, photoIndex: photoIndex)
        case .geo:  scheduleGeo(reminder)
        }
    }

    /// 排不上时最多提示一次。`reason` 直接就是给用户看的那句话。
    ///
    /// 启动重排会连着排 N 条，不去重的话用户一开机就被弹 N 次同样的提示 ——
    /// 那会让「去设置里打开通知」这件正事本身被淹掉。
    private func warnCannotSchedule(_ reason: String) {
        guard !didWarnSchedule else { return }
        didWarnSchedule = true
        NotificationCenter.default.post(name: .reminderCannotSchedule, object: reason)
    }

    private func scheduleDate(_ r: Reminder, photoIndex: [String: [String]]?) async {
        let index = photoIndex ?? Self.photoIndex(of: r.record)
        let content = UNMutableNotificationContent()
        content.title = r.title
        content.body = r.previewLine        // 与 32 屏「通知预览」逐字一致
        content.sound = .default
        // 分类决定「长按展开后有没有按钮、走不走扩展」——
        // 它就是主 App 与通知扩展之间那根唯一的线。
        content.categoryIdentifier = HINotify.reminderCategory
        content.userInfo = Self.userInfo(for: r, photoIndex: index)
        attachFirstPhoto(of: r, photoIndex: index, to: content)

        let cal = Calendar.current

        // 「哪一天响」按重复规则取 —— **只取该规则真正用得上的字段**。
        //
        // 多取一个字段就会把规则钉死：「每天」要是带上 `day`，它就变成
        // 「只有今天那一号响」，而界面上仍然写着「每天」。
        // 反过来少取一个也会走样：这正是「每月」此前的状态 ——
        // `r.dayOfMonth` 从来没有被写过（见 `ReminderEditorView.save`），
        // 于是 `comps.day = nil`，「每月」实际按「每天」响。
        //
        // 抽成局部函数是因为提前量那一步之后要**重取一次**（跨午夜时
        // hour/minute 会变），而重取的字段集必须和第一次完全一致 ——
        // 两处各写一遍，改一处漏一处。
        func makeComps(from d: Date) -> DateComponents {
            switch r.repeatRule {
            case .daily:
                return cal.dateComponents([.hour, .minute], from: d)

            case .weekly:
                var c = cal.dateComponents([.hour, .minute], from: d)
                c.weekday = r.weekday
                return c

            case .monthly:
                var c = cal.dateComponents([.hour, .minute], from: d)
                // 兜一层：老数据里 `dayOfMonth` 可能是 nil，那就按 `time` 当天算，
                // 而不是像以前那样把它落成「每天」。
                c.day = r.dayOfMonth ?? cal.component(.day, from: r.time)
                return c

            case .yearly:
                var c = cal.dateComponents([.hour, .minute], from: d)
                // 月份取 `r.time` 的 —— 「纪念日 / 生日」是年复一年的，
                // 这一档 2026-09-15 才补上（此前只有 仅一次/每天/每周/每月）。
                c.month = cal.component(.month, from: r.time)
                c.day   = r.dayOfMonth ?? cal.component(.day, from: r.time)
                return c

            case .none:
                // 仅一次：整条日期都要，否则系统会把它理解成「下一个」。
                return cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            }
        }

        var comps = makeComps(from: r.time)

        // 提前量在这里生效：把触发时刻整体往前挪。
        // 设计上「提前 10 分钟」是用户要的余量，落到系统里就是触发时间 − 提前量。
        if r.leadMinutes > 0 {
            let d = (cal.date(from: comps) ?? r.time)
                .addingTimeInterval(-Double(r.leadMinutes) * 60)
            comps = makeComps(from: d)
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: comps,
            repeats: r.repeatRule != .none
        )

        let req = UNNotificationRequest(identifier: r.id, content: content, trigger: trigger)
        try? await center.add(req)
    }

    private func scheduleGeo(_ r: Reminder) {
        // 没有坐标 = 这条场景提醒从来没被真正设过（见 `ReminderEditorView.save`）。
        // 以前这里是**静默 return**，于是「看着设好了、其实一条围栏都没注册」——
        // 用户报的「场景提醒没实现」，正是这一句加上保存那一步一起造成的。
        // 现在保存那一步会挡住没坐标的情况，这里留作第二道闸：
        // 老库里已有的脏数据（`latitude` 为 nil）走到这儿要说出来，不再装作排上了。
        guard let lat = r.latitude, let lon = r.longitude else {
            warnCannotSchedule("这条场景提醒还没设过地点")
            return
        }

        // 额度检查。到顶后**必须走开关式管理**，不能静默失败 ——
        // 静默失败的表现是「设了提醒但从来不会响」，那是最坏的一种 bug。
        // 05 屏那句「已用 20/20，先关掉一个」现在真的会出现了。
        let monitored = location.monitoredRegions
        guard monitored.count < Self.maxGeofences else {
            warnCannotSchedule("场景点已用满 \(Self.maxGeofences) 个，先关掉一个")
            return
        }

        // 已经在监听同一个提醒就不要再监一次。
        // 重复 startMonitoring 同一个 identifier 不报错、也不会更新半径 ——
        // 「以为改了半径其实没改」是最难查的一类问题。
        //
        // 判据是**解析出来的 reminderID**、不是整个 identifier：
        // 提醒换绑了记录时 identifier 会变，那种情况**应当**重建围栏。
        guard !monitored.contains(where: { ReminderGeo.parse($0.identifier)?.reminderID == r.id })
        else { return }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            radius: r.radius,
            identifier: ReminderGeo.makeID(reminderID: r.id, recordID: r.record?.id)
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false        // 只在进入时提醒 —— 离开时不打扰
        location.startMonitoring(for: region)

        // **把「进入时该说的那句话」落一份到 UserDefaults。**
        //
        // 为什么不能到进入那一刻再读：`didEnterRegion` 可能在 App 没在运行、
        // 或刚被系统拉起来、数据库都还没开的时候到达 —— 那时既拿不到
        // `Reminder` 对象，也不该在定位回调里去做开库这种重活。
        // 存成纯值之后，那一刻只需要一次 `UserDefaults` 读取。
        GeoNote.write(reminderID: r.id,
                      title: r.title,
                      body: r.previewLine,
                      recordID: r.record?.id)
    }

    /// 撤掉一条提醒。
    ///
    /// 注意第二段：用户点过「1 小时后」之后，系统里多了一条 **snooze_ 前缀的副本**。
    /// 只按原 id 撤是不够的 —— 那样「关掉提醒之后它还响一次」，
    /// 而这类 bug 极难复现（要先点过推迟、再关开关、还要等到点）。
    func cancel(_ reminder: Reminder) async {
        await cancel(reminderID: reminder.id)
    }

    /// 按 id 撤。**给「先把模型删掉、再撤通知」那条路用。**
    ///
    /// 撤销一条刚记下的记录时，提醒行走 `Record` 上的级联删除一起没了 ——
    /// 那个模型对象随即失效，再去读它的任何属性都可能触到失效对象。
    /// 这个坑本项目踩过一次（往已登记删除的 `Photo` 上写 `order` 会让
    /// SwiftData 直接 `fatalError`），所以那条路必须在删除**之前**把 id 取出来。
    ///
    /// 撤的仍是同一批东西（原 id + `snooze_` 前缀的副本 + 地理围栏），
    /// 不因为改成按 id 就少撤一样 —— 少撤一样就是「关掉的提醒还会响一次」。
    func cancel(reminderID: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])

        let prefix = "snooze_\(reminderID)_"
        let copies = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        if !copies.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: copies)
        }

        // 围栏标识是 `geo:<提醒 id>:<记录 id>`（见 `scheduleGeo`），
        // 所以这里是「解析出来的提醒 id 相等」，不是字符串相等 ——
        // 写成字符串相等的话，**关掉一条场景提醒不会真的撤掉围栏**：
        // 它会继续响，而用户以为自己关掉了。
        // 后面那半句认的是「裸提醒 id」那种老格式，老围栏才撤得掉。
        if let region = location.monitoredRegions.first(where: {
            $0.identifier == reminderID
                || ReminderGeo.parse($0.identifier)?.reminderID == reminderID
        }) {
            location.stopMonitoring(for: region)
        }

        // 那句话的副本一起清掉。不清的话它会一直留在 `UserDefaults` 里，
        // 而提醒 id 是随机生成的 —— 每建一条、删一条就漏一份，
        // 属于那种「跑一年才发现存储里躺着几千条死数据」的问题。
        GeoNote.remove(reminderID: reminderID)
    }

    /// 启动时重排一次。**必须做** ——
    /// 卸载重装、重启、系统清理都会丢掉待发通知，而用户以为提醒还在。
    ///
    /// 配图索引在这里建一次、所有提醒共用 —— 每条提醒各建一次就是 N 次全表扫描。
    /// 上下文从记录自己身上取（启动那一步的调用方拿不到 `ModelContext`）。
    func rescheduleAll(_ records: [Record]) {
        let index = Self.photoIndex(from: records)
        for r in records.compactMap(\.reminder) where r.isOn {
            Task { await schedule(r, photoIndex: index) }
        }
    }

    // MARK: - 通知里带什么

    /// 「记录 id → 它配图的 hash（已按顺序排好）」。
    ///
    /// **读的是 `Record.photoHashes` 这个标量数组，不碰任何模型关系。**
    ///
    /// 这里曾经写的是「从 `Photo` 表 fetch 全表再按 `p.record?.id` 分桶」，
    /// 当时的想法是「绕开 `record.photos` 关系就不会碰到墓碑对象」。
    /// 那是错的，而且错得很有教益：2026-09-15 的 11:49 那份真机日志正是崩在这一句，
    /// trap 地址与「读 `record.photos`」那两次**逐字节相同**（`SwiftData + 0x9e77c`）。
    /// 也就是说真正的判据不是「读关系还是读表」，而是**「读不读 `Photo` 这个模型对象」**。
    ///
    /// 现在标量数组把这件事彻底绕开了：`photoHashes` 就是一个 `[String]`，
    /// 读到它不需要 SwiftData 参与任何反序列化。见 `Record.photoHashes`。
    ///
    /// 这一步跑在**启动重排**里，所以它崩的后果不是「某条提醒没排上」，
    /// 而是 **App 打不开** —— 它值得比别处多一层的谨慎。
    private static func photoIndex(from records: [Record]) -> [String: [String]] {
        var index: [String: [String]] = [:]
        for r in records { index[r.id] = r.photoHashes }
        return index
    }

    /// 单独一条记录的版本。`scheduleDate` 在拿不到批量索引时用它。
    private static func photoIndex(of record: Record?) -> [String: [String]] {
        guard let r = record else { return [:] }
        return [r.id: r.photoHashes]
    }

    /// 载荷。键名全部来自 `HINotify.Key` ——
    /// 扩展那一侧就是照这些键读的，写错一个的表现是「展开后少一块」。
    ///
    /// 配图张数走传进来的 `photoIndex`，**不再写 `r.record?.photos.count`**：
    /// 那个关系里可能挂着墓碑，而这一句在启动重排时会被执行到（见 `photoIndex(from:)`）。
    /// 其余几项（版本 / 分类 / recordID）读的都是 `Record` 自己的标量属性，不碰集合关系。
    private static func userInfo(for r: Reminder, photoIndex: [String: [String]]) -> [String: Any] {
        let recordID = r.record?.id
        var info: [String: Any] = [
            HINotify.Key.title:      r.title,
            HINotify.Key.body:       r.previewLine,
            HINotify.Key.reminderID: r.id,
            HINotify.Key.version:    r.record?.version ?? 1,
            HINotify.Key.photoCount: recordID.flatMap { photoIndex[$0]?.count } ?? 0
        ]
        if let rid = recordID { info[HINotify.Key.recordID] = rid }
        // rawValue 与 HINotify.Cat 的 case 名一致（like / trait_ / care / hate）
        if let cat = r.record?.cat.rawValue { info[HINotify.Key.cat] = cat }
        return info
    }

    /// 把记录的第一张配图挂到通知上。
    ///
    /// 走 `UNNotificationAttachment`：**系统会把文件拷进这条通知自己的目录**，
    /// 所以扩展读得到，而我们不需要为图片开共享容器。
    /// 找不到文件就安静跳过 —— 一条没配图的提醒仍然是一条完整的提醒。
    private func attachFirstPhoto(of r: Reminder,
                                  photoIndex: [String: [String]],
                                  to content: UNMutableNotificationContent) {
        guard let rid = r.record?.id,
              let hash = photoIndex[rid]?.first,
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

    /// 定位授权有结论了（或本来就已有结论，delegate 一设上就会回调一次）。
    ///
    /// **必须是 nonisolated** —— 同下面的区域回调，CoreLocation 在它自己的
    /// 线程上回调，声明成主线程隔离会编译不过。
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in resumeLocationAuthIfNeeded(s) }
    }

    /// 把等在那里的 `requestLocationPermission()` 放行。
    ///
    /// `guard let` 而不是先赋 nil 再判空：没有人在等的时候（绝大多数回调）
    /// 这一句直接返回，顺手把「给一个已经 resume 过的 continuation 再 resume 一次」
    /// 那个必崩的操作从结构上排除了。
    @MainActor
    private func resumeLocationAuthIfNeeded(_ s: CLAuthorizationStatus) {
        guard let c = locationAuthContinuation else { return }
        locationAuthContinuation = nil
        c.resume(returning: s)
    }

    /// 「取一次位置」的回调。
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in resumeLocationOnce(last) }
    }

    /// 取位置失败也要放行。
    ///
    /// 不放行的话那边会**永远等在那句 `await` 上** —— 界面上表现为
    /// 「点了『取当前位置』，一直转圈」，既不成功也不报错。
    /// 定位服务被系统关掉、飞行模式、室内收不到星，都会走到这里。
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in resumeLocationOnce(nil) }
    }

    @MainActor
    private func resumeLocationOnce(_ loc: CLLocation?) {
        guard let c = locationOnceContinuation else { return }
        locationOnceContinuation = nil
        c.resume(returning: loc)
    }

    /// 进入场景点。**这类回调必须是 nonisolated** ——
    /// CoreLocation 在它自己的线程上回调，声明成主线程隔离会编译不过。
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didEnterRegion region: CLRegion) {
        // 只认自己编出来的那种标识。老格式（裸提醒 id）解析不出来 ——
        // 那种情况宁可不发这条通知，也不发一条「点了跳不动」的通知。
        guard let r = region as? CLCircularRegion,
              let ids = ReminderGeo.parse(r.identifier) else { return }

        // **正文用用户自己写的那句话** —— 那正是 32 屏「通知预览」承诺的那一行。
        // 此前这里写死了「这里有你记过的事」，用户写的字一个都没发出去，
        // 于是「保存前先看见它长什么样」这件事在场景提醒上是假的。
        let note = GeoNote.read(reminderID: ids.reminderID)

        let content = UNMutableNotificationContent()
        // 缓存里没有（更早版本留下的围栏、或提醒刚被删）时退回一句**仍然成立**的话，
        // 而不是空字符串 —— 一条没有正文的通知是更坏的结果。
        content.title = note?.title ?? "到你常去的地方了"
        content.body  = note?.body  ?? "这里有你记过的事"
        content.sound = .default
        content.categoryIdentifier = HINotify.reminderCategory
        // 两个 id 都要带：`recordID` 给「点通知跳那条记录」用，
        // `reminderID` 给通知上那两个按钮（1 小时后 / 今天不用了）用。
        // 此前这里只放了一个提醒 id、却写在 `recordID` 键上 ——
        // 后果就是**点场景通知什么也不发生**（拿提醒 id 去查记录，查不到，静默作罢）。
        var info: [String: Any] = [HINotify.Key.reminderID: ids.reminderID]
        if let rec = ids.recordID ?? note?.recordID { info[HINotify.Key.recordID] = rec }
        content.userInfo = info

        let req = UNNotificationRequest(
            identifier: "geo_\(ids.reminderID)_\(Int(Date.now.timeIntervalSince1970))",
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

    /// 「这条提醒排不上」。`object` 是**一句直接给用户看的话**
    /// （通知权限没开 / 场景点用满 / 这条还没设过地点）。
    ///
    /// 专门造一个的理由：此前所有失败路径都是静默的（`try?` 或裸 `return`），
    /// 于是「提醒不响」这件事在用户那边**完全没有信息** ——
    /// 他既不知道是权限问题、额度问题，还是自己压根没设过地点，
    /// 只能得出一个笼统的结论：「这个功能是坏的」。
    static let reminderCannotSchedule = Notification.Name("HerInfo.reminderCannotSchedule")
}

// MARK: - 地理围栏标识

/// 地理围栏标识：`geo:<提醒 id>:<记录 id>`。
///
/// **为什么两个 id 都要编进这一个字符串**：
/// `CLCircularRegion` 只给一个 String 标识，而进入那一刻系统只把这个字符串还回来
/// （App 完全可能没在运行 —— 那正是这个功能存在的场景）。
/// 那一瞬既拿不到数据库、也拿不到 `Reminder` 对象，要能跳到那条记录，
/// 就只能靠它自己带够信息。
///
/// 此前这里只存了提醒 id，而 `didEnterRegion` 把它当**记录 id** 用 ——
/// 表现是「点场景通知什么也不发生」（拿那个 id 去查记录，查不到，就静默作罢了）。
///
/// **为什么做成一个独立的私有类型、而不是 `ReminderService` 的静态方法**：
/// 这两个函数要同时被主线程上的排程和 CoreLocation 自己线程上的进入回调调用。
/// 放在 `@MainActor` 的 `ReminderService` 里，每个都得手工标 `nonisolated`，
/// 而漏标一个的表现是「编译能过、运行到那一条才炸」。
/// 做成一组无状态的纯函数，这件事就从「记得标」变成「本来就没有」。
private enum ReminderGeo {

    static let prefix = "geo:"

    static func makeID(reminderID: String, recordID: String?) -> String {
        "\(prefix)\(reminderID):\(recordID ?? "")"
    }

    /// 解析不出来的（比如更早版本留下的裸提醒 id）返回 nil ——
    /// 调用方一律按「这不是我们认识的围栏」处理，而不是猜。
    static func parse(_ id: String) -> (reminderID: String, recordID: String?)? {
        guard id.hasPrefix(prefix) else { return nil }
        let rest = id.dropFirst(prefix.count)
        // `maxSplits: 1`：记录 id 里万一出现冒号也不能被切开。
        let parts = rest.split(separator: ":", maxSplits: 1,
                               omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return nil }
        let rec = parts.count > 1 ? String(parts[1]) : ""
        return (String(first), rec.isEmpty ? nil : rec)
    }
}

// MARK: - 场景通知要说的话

/// 进入场景点时那条通知的正文：`提醒 id → (标题, 正文, 记录 id)`。
///
/// **为什么要存一份**：`didEnterRegion` 到达的那一刻，App 很可能没在运行 ——
/// 那正是这个功能存在的场景。系统把 App 拉起来之后，数据库未必已经就绪，
/// 而定位回调用的是 `CLLocationManager` 自己的线程，也不该在那里做开库这种重活。
/// 存成纯值之后，那一刻只需要一次 `UserDefaults` 读。
///
/// **此前这里没有**，于是场景通知写死「到你常去的地方了 / 这里有你记过的事」，
/// 而用户写在「提醒文案」里的那句话一个字都没发出去 ——
/// 32 屏「通知预览」承诺的「保存前先看见它长什么样」在场景这一路是假的。
///
/// **为什么是文件级的独立类型、而不是 `ReminderService` 的嵌套类型**：
/// 和 `ReminderGeo` 同一个理由 —— 嵌套在 `@MainActor` 的类里会跟着继承主线程隔离，
/// 而这个函数必须能在 CoreLocation 的线程上直接调用，
/// 每个方法都得手工标 `nonisolated`，漏标一个就是「编译能过、运行到那一条才炸」。
/// 做成一组无状态的纯函数，这件事从「记得标」变成「本来就没有」。
private enum GeoNote {

    /// 带 `hi.` 前缀，与别的自用键一致（那个前缀在本工程的含义是
    /// 「内部状态，不是设计令牌」）。
    static let key = "hi.reminder.geoNotes"

    static func write(reminderID: String, title: String, body: String, recordID: String?) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        var one: [String: String] = ["title": title, "body": body]
        if let recordID { one["recordID"] = recordID }
        all[reminderID] = one
        UserDefaults.standard.set(all, forKey: key)
    }

    /// 读不到就返回 nil —— 调用方退回一句仍然成立的话，而不是猜。
    static func read(reminderID: String) -> (title: String, body: String, recordID: String?)? {
        guard let all = UserDefaults.standard.dictionary(forKey: key),
              let raw = all[reminderID] as? [String: String],
              let title = raw["title"], let body = raw["body"] else { return nil }
        return (title, body, raw["recordID"])
    }

    static func remove(reminderID: String) {
        guard var all = UserDefaults.standard.dictionary(forKey: key) else { return }
        all.removeValue(forKey: reminderID)
        UserDefaults.standard.set(all, forKey: key)
    }
}
