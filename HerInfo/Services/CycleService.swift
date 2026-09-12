//
//  CycleService.swift
//  我的宝宝江林桐 · 生理期的落库与提醒
//
//  拆成两个东西，各管一件事：
//    · `CyclePeriodStore` —— 写。只有这一个入口，删改都走它。
//    · `CycleReminder`    —— 排通知。**它是唯一的出口**：
//                            首页、提醒页、保存之后都调它，没有第二处在排。
//
//  为什么不把这些直接写在 View 里：
//  通知这件事有个隐蔽的坑 —— **它和界面状态是两份东西**。
//  用户在 40 屏把「提前 2 天」改成「提前 3 天」，如果只在界面里改、
//  忘了重排系统里的通知，那屏幕上写着 3 天、手机还是第 2 天响。
//  分成一个出口之后，这种不一致就没有地方发生了。
//

import Foundation
import SwiftData
import UserNotifications

// MARK: - 写入口

/// 生理期的唯一写入口。
///
/// **做成一个薄壳而不是直接在 View 里 `ctx.insert`**：因为「同一天记了两次」
/// 是这件事最常见的误操作（手快点了两下、或者隔天忘了已经记过）。
/// 真正该问的问题不是「要不要再插一条」，而是「这一天是不是已经有一次了」。
/// 把这个判断收在这里，界面就不用各自判一遍。
struct CyclePeriodStore {

    let context: ModelContext
    /// 已经取好的一串（按开始日倒序）。用来判重。不传就现查。
    private let existing: [CyclePeriod]

    init(context: ModelContext) {
        self.context = context
        let d = FetchDescriptor<CyclePeriod>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        self.existing = (try? context.fetch(d)) ?? []
    }

    /// 记一次 / 改一次。
    ///
    /// - `id` 传值 = 改那一条；传 nil = 新记。
    /// - **同一天已有记录时不新增，而是覆盖那一条的持续天数** ——
    ///   这是刻意的：她这一天来了，只可能是一次经期的开始，
    ///   不该出现两条开始日相同的记录。多出来的那两条会让平均周期算成 0 天。
    @discardableResult
    func upsert(id: String?,
                startedAt: Date,
                durationDays: Int,
                isManual: Bool) -> CyclePeriod {

        let cal = Calendar.current

        if let id, let hit = existing.first(where: { $0.id == id }) {
            hit.startedAt = startedAt
            hit.durationDays = durationDays
            try? context.save()
            return hit
        }

        // 同一天已经有别的记录 → 改它，不加新的。
        if let sameDay = existing.first(where: { cal.isDate($0.startedAt, inSameDayAs: startedAt) }) {
            sameDay.durationDays = durationDays
            try? context.save()
            return sameDay
        }

        let fresh = CyclePeriod(startedAt: startedAt,
                                durationDays: durationDays,
                                isManual: isManual)
        context.insert(fresh)
        try? context.save()
        return fresh
    }

    func delete(_ p: CyclePeriod) {
        context.delete(p)
        try? context.save()
    }
}

// MARK: - 通知

/// 生理期提醒的唯一出口。
///
/// 排的是**一次性通知**，不是重复通知 —— 理由见下面 `rescheduleAll` 的注释。
enum CycleReminder {

    /// 通知的 id 前缀。**用前缀是为了能一次清干净** ——
    /// 不加前缀就得靠「记住排过哪些 id」，而那个列表本身也会漂。
    static let idPrefix = "cycle.lead."

    /// 全部重排。
    ///
    /// **每次都是「先全撤，再按最新数据重排」。** 不做增量 ——
    /// 增量要维护「已排的对不对」这件事，而重排的代价只是一次
    /// `removePendingNotificationRequests`。在只有一条待排通知的情况下，
    /// 全量重来永远比增量可靠。
    ///
    /// **用 `UNCalendarNotificationTrigger` 一次性触发，不带 repeats。**
    /// 这是这块功能最容易写错的地方：日期是算出来的**具体某一天**，
    /// 不是「每天这个时候」。如果写成重复触发、又只给 `hour/minute`，
    /// 系统会理解成「每天 9 点提醒她可能要来了」—— 变成天天响。
    /// 所以下面 `comps` 必须带上年月日。
    static func rescheduleAll(context: ModelContext,
                              leadDays: Int,
                              hour: Int,
                              enabled: Bool) async {

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard enabled else { return }

        let desc = FetchDescriptor<CyclePeriod>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let periods = (try? context.fetch(desc)) ?? []
        let stats = CycleStats(models: periods)

        guard let next = stats.nextStart else { return }

        let cal = Calendar.current
        // 提前量在这里生效：整体往前挪 leadDays 天。
        guard let fireDay = cal.date(byAdding: .day, value: -leadDays, to: next) else { return }

        // **已经过去的日子不再排。** 排一个过去的时间，系统会立刻抛出来 —
        // 那表现就是「刚记完，手机马上响一声」，像个 bug。
        let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: fireDay) ?? fireDay
        guard fire > .now else { return }

        var comps = cal.dateComponents([.year, .month, .day], from: fire)
        comps.hour = hour
        comps.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "她可能要开始了"
        // 文案取自 40 屏那个可编辑的输入框。
        let custom = UserDefaults.standard.string(forKey: "cycleMessage")
        content.body = (custom?.isEmpty == false) ? custom! : "按规律推算，这两天差不多了。"
        content.sound = .default
        // 与 05/32 屏的提醒共用同一个分类 —— 长按展开、打标那套才认得出它。
        content.categoryIdentifier = HINotify.reminderCategory

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: idPrefix + "next",
                                        content: content,
                                        trigger: trigger)
        try? await center.add(req)
    }
}

// MARK: - 日期格式

/// 生理期这块用到的日期写法。
///
/// **刻意不复用 `ExportService` 里那两个**（`fileStamp` / `cnFull`）——
/// 那两个是给导出文件用的（`2026 年 9 月 8 日 20:30`、文件名时间戳），
/// 而这里要的是「9月10日」「周四」「9月」这种短写法。
/// 硬塞进一个格式化器只会让它长出一堆可选参数。
extension DateFormatter {

    /// `9月10日` —— 38 屏那个大日期、列表行的标题。
    static let cycleFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    /// `周四` —— 只在大日期旁边出现，给一个「噢原来是那天」的锚点。
    static let cycleWeekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f
    }()

    /// `10` —— 列表行左边日期块里的那个日。
    static let cycleDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "d"
        return f
    }()

    /// `9月` —— 日期块下半、柱状图底下的月份。
    static let cycleMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f
    }()
}
