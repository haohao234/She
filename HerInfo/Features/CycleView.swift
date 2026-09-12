//
//  CycleView.swift
//  我的宝宝江林桐 · 生理期（37 生理期首页 / 38 记录经期 / 39 周期记录 / 40 经期提醒 / 41 空态）
//
//  ─────────────────────────────────────────────────────────────
//  这块功能的四条设计分寸（改这一屏前先读一遍）
//  ─────────────────────────────────────────────────────────────
//  ① **不给生理期一个「专属粉」。** 粉 = 生理期最省事，但它同时说了一句
//     「这是件特殊的事」。这块要的是「平常地记一下」，所以颜色全部引用已有色相。
//
//  ② **不做健康建议。** 这不是医疗工具。它做的事只有两件：把日子记下来、
//     按规律把下次算出来。所以全篇找不到「建议你」「应该注意」这类句子。
//
//  ③ **文案一律说「她」。** 这是他的 App，记的是她的事。
//     写成「本次经期已持续 3 天」是病历口气；「经期第 3 天 · 4 天后结束」才对。
//
//  ④ **圆点是主角、数字是配角。** 37 屏那一圈点阵是视觉重心，
//     环心那个「4」只是注解。不做数据仪表盘 —— 这里不是看板。
//
//  ─────────────────────────────────────────────────────────────
//  算出来的东西不落库
//  ─────────────────────────────────────────────────────────────
//  周期天数 / 下次预测 / 是否正在经期中，全部由 `CycleStats` 现算。
//  库里只有「一次经期」这一件事（`CyclePeriod`）。这样改了开始日之后，
//  首页 / 趋势 / 提醒三处不可能各显示一个数字。
//

import SwiftUI
import SwiftData

// MARK: - 37 生理期首页

struct CycleView: View {

    @Environment(\.modelContext) private var ctx
    @Query(sort: \CyclePeriod.startedAt, order: .reverse) private var periods: [CyclePeriod]

    /// 38 屏那个记录页以 sheet 弹出。
    @State private var showRecord = false
    /// 39 屏。
    @State private var showStats = false
    /// 40 屏。
    @State private var showNotify = false

    private var stats: CycleStats { CycleStats(periods: periods) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if stats.isEmpty {
                    CycleEmptyCard { showRecord = true }
                } else {
                    ringCard
                    statRow
                    recentCard
                }
            }
            .padding(.horizontal, S.screen)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
        .background(C.bg)
        .navigationTitle("生理期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("周期记录") { showStats = true }
                    Button("经期提醒") { showNotify = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(C.ink2)
                }
            }
        }
        .sheet(isPresented: $showRecord) {
            CycleRecordSheet(existing: nil)
        }
        .sheet(isPresented: $showStats) {
            NavigationStack { CycleStatsView() }
        }
        .sheet(isPresented: $showNotify) {
            NavigationStack { CycleNotifyView() }
        }
    }

    // MARK: 周期环

    private var ringCard: some View {
        VStack(spacing: 14) {
            CycleRing(stats: stats)
                .frame(width: 190, height: 190)
                .padding(.top, 6)

            // 「她昨天说有点不舒服」→ 记下第一天的入口。
            // **放在环下面而不是做成第三个按钮** —— 这句话是「由此去记」的提醒，
            // 不是并列的第三个动作。
            Button {
                showRecord = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(C.card).frame(width: 28, height: 28)
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(C.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recordPromptTitle)
                            .font(Typo.bodyS)
                            .foregroundStyle(C.ink)
                        Text("记下经期第一天，下次就能提前提醒你")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(C.ink3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(CYC.periodSoft, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.cardBig, style: .continuous))
    }

    /// 正在经期中时说「正在经期」，否则说「记一次新的」。
    /// **不编一句「她昨天说有点不舒服」** —— 那是画布上的示例数据，
    /// 真机上我们并不知道她说过什么，写死就是造谣。
    private var recordPromptTitle: String {
        stats.currentPeriod() != nil ? "还在经期里" : "她开始了吗"
    }

    // MARK: 三栏统计

    private var statRow: some View {
        HStack(spacing: 0) {
            statCell("\(stats.averageCycle)", "周期天数")
            divider
            statCell("\(stats.latest?.durationDays ?? 0)", "经期天数")
            divider
            statCell(shortDay(stats.latest?.startedAt), "上次开始")
        }
        .padding(.vertical, 16)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(C.line).frame(width: 1, height: 30)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(C.ink)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(C.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 最近几次

    private var recentCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("最近几次")
                    .font(Typo.cardTitle)
                    .foregroundStyle(C.ink)
                Spacer()
                Button {
                    showStats = true
                } label: {
                    HStack(spacing: 2) {
                        Text("全部").font(Typo.captionM)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(C.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            ForEach(Array(stats.periods.prefix(4).enumerated()), id: \.element.id) { idx, p in
                if idx > 0 { Rectangle().fill(C.line).frame(height: 1) }
                CycleRow(period: p, stats: stats, showGap: true)
                    .padding(.vertical, 11)
            }
        }
        .padding(18)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }
}

// MARK: - 周期环（37 屏的核心图形）

/// 一圈点阵 + 环心那个数字。
///
/// **为什么是点阵不是实心进度环**：实心环读起来像「完成了百分之多少」，
/// 而月经周期不是一件在推进度的事。点阵读起来像日历上的记号 —— 这才对。
///
/// 点数固定 28 个（`CycleStats.defaultCycle`），每个点代表周期里的一天：
/// 前 `durationDays` 个是经期（实心主色），中间的易孕窗是草木绿，
/// 其余是砂色。**正在经期中的那几天被放大**，一眼能看出「现在第几天」。
struct CycleRing: View {

    let stats: CycleStats

    /// 图形外径。点的大小按它换算，**缩小容器时要一起改**（铁律 20 的思路）。
    private let ringSize: CGFloat = 190

    private var total: Int { CycleStats.defaultCycle }

    var body: some View {
        ZStack {
            ForEach(0..<total, id: \.self) { i in
                dot(at: i)
            }

            VStack(spacing: 2) {
                if let day = stats.currentDay() {
                    Text("经期第 \(day) 天")
                        .font(Typo.captionM)
                        .foregroundStyle(C.primary)
                    if let left = stats.daysUntilEnd() {
                        Text("\(left)")
                            .font(.system(size: 44, weight: .semibold).monospacedDigit())
                            .foregroundStyle(C.ink)
                        Text("天后结束")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                    }
                } else if let days = stats.daysUntilNext() {
                    Text("距离下次").font(Typo.captionM).foregroundStyle(C.ink2)
                    Text("\(max(0, days))")
                        .font(.system(size: 44, weight: .semibold).monospacedDigit())
                        .foregroundStyle(C.ink)
                    Text(days >= 0 ? "天" : "天（已过）")
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                }
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    /// 第 i 个点。
    ///
    /// 角度用 `-90°` 起步（12 点位置）**顺时针** —— 与日历上「从这天起」的
    /// 直觉一致。算角度而不是手摆位置：手摆位置在点数一变就全乱。
    private func dot(at i: Int) -> some View {
        let radius = ringSize / 2 - 14
        let angle = Double(i) / Double(total) * 2 * .pi - .pi / 2
        let x = ringSize / 2 + radius * cos(angle)
        let y = ringSize / 2 + radius * sin(angle)

        return Circle()
            .fill(color(at: i))
            .frame(width: size(at: i), height: size(at: i))
            .position(x: x, y: y)
    }

    /// 第 i 天属于哪一段。
    private func color(at i: Int) -> Color {
        guard let p = stats.latest else { return CYC.track }
        if i < p.durationDays { return CYC.period }

        // 易孕窗：按常识推算为「下次经期前 14 天前后各 3 天」。
        // **这是推算不是判断** —— 40 屏页脚那句说的就是这件事。
        let remaining = stats.averageCycle - p.durationDays
        let ovu = max(0, remaining - 14)
        if i >= p.durationDays + ovu && i < p.durationDays + ovu + 6 { return CYC.fertile }

        return CYC.track
    }

    /// 正在经期中的那几天放大一点 —— 这是环上唯一的「当前」标记。
    private func size(at i: Int) -> CGFloat {
        guard let day = stats.currentDay() else { return 9 }
        return i == day - 1 ? 15 : 9
    }
}

// MARK: - 一次经期那一行（37 / 39 屏共用）

struct CycleRow: View {

    let period: CyclePeriod
    let stats: CycleStats
    /// 39 屏右侧显示「距上次 N 天」，37 屏的最近列表不显示。
    var showGap: Bool = false

    private var isCurrent: Bool {
        stats.currentPeriod()?.id == period.id
    }

    private var dayLabel: String {
        let f = DateFormatter.cycleDay
        return f.string(from: period.startedAt)
    }

    private var monthLabel: String {
        DateFormatter.cycleMonth.string(from: period.startedAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // 日期块：日 + 月。**数字是配角**，所以块小、字也小。
            VStack(spacing: 1) {
                Text(dayLabel)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isCurrent ? C.primary : C.ink)
                Text(monthLabel)
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            }
            .frame(width: 44, height: 48)
            .background(isCurrent ? CYC.periodSoft : C.fill,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle)
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink)
                Text(rowSub)
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            }

            Spacer(minLength: 0)

            if isCurrent {
                Text("正在")
                    .font(Typo.caption)
                    .foregroundStyle(C.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CYC.periodSoft, in: Capsule())
            } else if showGap, let gap = gapDays {
                Text("\(gap) 天")
                    .font(Typo.numCaption)
                    .foregroundStyle(C.ink2)
            }
        }
    }

    private var rowTitle: String {
        if isCurrent { return "经期第 \(stats.currentDay() ?? 1) 天" }
        let f = DateFormatter.cycleFull
        return "\(f.string(from: period.startedAt)) 开始"
    }

    private var rowSub: String {
        var s = "持续 \(period.durationDays) 天"
        if showGap, let gap = gapDays { s += " · 距上次 \(gap) 天" }
        else if !showGap, stats.isRegular, !isCurrent { s += " · 挺规律" }
        return s
    }

    /// 与上一次相隔几天。最近一次没有「上一次」，返回 nil。
    private var gapDays: Int? {
        guard let idx = stats.periods.firstIndex(where: { $0.id == period.id }),
              idx + 1 < stats.periods.count else { return nil }
        return stats.days(from: stats.periods[idx + 1].startedAt, to: period.startedAt)
    }
}

// MARK: - 38 记录经期

struct CycleRecordSheet: View {

    /// 传 nil = 新记一次；传值 = 改这一次。
    let existing: CyclePeriod?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CyclePeriod.startedAt, order: .reverse) private var periods: [CyclePeriod]

    @State private var startedAt: Date = .now
    /// **默认 5 但不是「已选」** —— 见下方 pill 的注释。
    @State private var duration: Int = 5
    @State private var didPickDuration = false
    @State private var remindMe = true
    @AppStorage("cycleLeadDays") private var leadDays = 2
    @AppStorage("cycleNotifyHour") private var notifyHour = 9

    init(existing: CyclePeriod?) {
        self.existing = existing
        if let e = existing {
            _startedAt = State(initialValue: e.startedAt)
            _duration = State(initialValue: e.durationDays)
            _didPickDuration = State(initialValue: true)
        }
    }

    /// 这次记录之后会变成的那一串（用来预览提醒文案）。
    /// 把「还没保存的这一次」先算进去，否则预览说的是保存前的旧规律。
    private var previewStats: CycleStats {
        var list = periods
        if let e = existing { list.removeAll { $0.id == e.id } }
        list.append(CyclePeriod(id: "preview", startedAt: startedAt, durationDays: duration))
        return CycleStats(periods: list)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateCard
                    durationCard
                    remindCard
                }
                .padding(.horizontal, S.screen)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(C.bg)
            .navigationTitle(existing == nil ? "记录经期" : "修改这次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(C.ink2)
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .presentationDetents([.large])
    }

    // MARK: 开始日

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                Text("这次的开始日").font(Typo.captionM).foregroundStyle(C.ink2)
                Text("必填").font(Typo.caption).foregroundStyle(C.primary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DateFormatter.cycleFull.string(from: startedAt))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(C.ink)
                Text(DateFormatter.cycleWeekday.string(from: startedAt))
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink3)
            }

            HStack(spacing: 8) {
                quick("昨天", days: -1)
                quick("今天", days: 0)
                quick("前天", days: -2)
                // 日历选择器做成同一排的第四颗胶囊 —— **不为它单独开一屏**，
                // 因为 90% 的情况就用上面三颗，展开日历是少数派。
                DatePicker("", selection: $startedAt, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }

    private func quick(_ title: String, days: Int) -> some View {
        let target = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let on = Calendar.current.isDate(startedAt, inSameDayAs: target)
        return Button {
            startedAt = target
        } label: {
            Text(title)
                .font(Typo.btn)
                .foregroundStyle(on ? .white : C.ink2)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(on ? C.primary : C.fill,
                            in: RoundedRectangle(cornerRadius: 100, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 持续几天

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("持续几天").font(Typo.captionM).foregroundStyle(C.ink2)
                Text("不确定就先不填").font(Typo.caption).foregroundStyle(C.ink3)
            }

            HStack(spacing: 8) {
                ForEach(Array(CycleStats.durationRange), id: \.self) { d in
                    // **选中态只在「用户点过」之后才亮** ——
                    // 默认值是 5，但那是「不知道就先按 5 算」，
                    // 一进来就把 5 画成选中，等于替她回答了这个问题。
                    let on = didPickDuration && duration == d
                    Button {
                        duration = d
                        didPickDuration = true
                    } label: {
                        Text("\(d)")
                            .font(Typo.btn)
                            .foregroundStyle(on ? .white : C.ink2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(on ? C.primary : C.fill,
                                        in: RoundedRectangle(cornerRadius: 100, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }

    // MARK: 提醒

    private var remindCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("会提前告诉我").font(Typo.captionM).foregroundStyle(C.ink2)

            Toggle(isOn: $remindMe) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("下次经期前 \(leadDays) 天提醒我")
                        .font(Typo.bodyS)
                        .foregroundStyle(C.ink)
                    Text(remindSubtitle)
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                }
            }
            .tint(C.primary)

            if remindMe {
                // 通知长什么样 —— 与 32 屏「通知预览」同一个做法：
                // **保存前能看见它，是这一屏存在的意义。**
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(C.primary)
                            .frame(width: 38, height: 38)
                        Image(systemName: "drop.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("我的宝宝江林桐")
                                .font(Typo.captionM)
                                .foregroundStyle(C.ink)
                            Spacer()
                            Text("现在").font(Typo.caption).foregroundStyle(C.ink3)
                        }
                        Text(notifyTitle)
                            .font(Typo.bodyS)
                            .foregroundStyle(C.ink)
                        Text(notifyBody)
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(C.fill, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
            }
        }
        .padding(18)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }

    private var remindSubtitle: String {
        guard let next = previewStats.nextStart else {
            return "记满两次之后，我就能算出规律"
        }
        let d = DateFormatter.cycleFull.string(from: next)
        return "按 \(previewStats.averageCycle) 天周期推算，\(d) 左右"
    }

    private var notifyTitle: String { "她可能要开始了" }

    private var notifyBody: String {
        "按规律推算，这两天差不多了。提前备好红糖和她爱喝的那个。"
    }

    // MARK: 底部保存

    private var saveBar: some View {
        VStack(spacing: 0) {
            // 一条发丝线 + 实底，与 03 屏那个底部保存条同一做法。
            // **不用 `.bar` 材质** —— 毛玻璃在这套暖色底上会把下面滚过去的内容
            // 透出来一层灰，而这个按钮要的是「按下去就记下了」的确定感。
            Rectangle().fill(C.line).frame(height: 1)

            VStack(spacing: 8) {
                Button {
                    save()
                } label: {
                    Text("记下来").primaryButtonStyle()
                }
                .pressDown()

                Text("记下之后，我会按规律帮你算下次大概什么时候")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            }
            .padding(.horizontal, S.screen)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(C.card)
    }

    private func save() {
        let store = CyclePeriodStore(context: ctx)
        store.upsert(id: existing?.id, startedAt: startedAt,
                     durationDays: duration, isManual: true)
        // 提醒跟着重排 —— 日子变了，通知也得跟着变。
        // **不在 save 里直接排通知**：通知是「派生结果」，
        // 统一由 rescheduleAll 一个出口负责，免得出现两处都在排的情况。
        Task { await CycleReminder.rescheduleAll(context: ctx,
                                                 leadDays: leadDays,
                                                 hour: notifyHour,
                                                 enabled: remindMe) }
        dismiss()
    }
}

// MARK: - 39 周期记录

struct CycleStatsView: View {

    @Environment(\.modelContext) private var ctx
    @Query(sort: \CyclePeriod.startedAt, order: .reverse) private var periods: [CyclePeriod]
    @Environment(\.dismiss) private var dismiss

    private var stats: CycleStats { CycleStats(periods: periods) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if stats.isEmpty {
                    Text("还没有记录。\n记下一次之后，这里会长出规律。")
                        .font(Typo.bodyS)
                        .foregroundStyle(C.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    regularCard
                    everyCard
                }
            }
            .padding(.horizontal, S.screen)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(C.bg)
        .navigationTitle("周期记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }.foregroundStyle(C.ink2)
            }
        }
    }

    private var regularCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("这半年的规律").font(Typo.cardTitle).foregroundStyle(C.ink)
                Spacer()
                // 不足三次不评价「规律」—— 两次记录谈规律没有意义。
                if stats.periods.count >= 3 {
                    Text(stats.isRegular ? "很规律" : "有点波动")
                        .font(Typo.captionM)
                        .foregroundStyle(stats.isRegular ? Category.care.tint : CYC.noteInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(stats.isRegular ? C.moss : CYC.noteBg, in: Capsule())
                }
            }

            barChart

            HStack(spacing: 0) {
                miniStat("\(stats.averageCycle)天", "平均周期")
                miniStat(stats.wobble.map { "±\($0)天" } ?? "—", "波动")
                miniStat("\(stats.periods.count)次", "近半年")
            }
        }
        .padding(18)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }

    /// 6 根柱子 = 最近 6 次的持续天数。
    ///
    /// **柱高按实际天数等比，不是按「在 3~7 里的位置」** ——
    /// 后者会把 5 天与 6 天画得差不多高，而它们本来也只差一天。
    /// 高度映射到 40~110 这个区间，免得 3 天的柱子短到看不见。
    private var barChart: some View {
        let items = stats.recentSix.reversed()
        let maxD = max(7, items.map(\.durationDays).max() ?? 7)

        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(items), id: \.id) { p in
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(C.primary)
                        .frame(height: barHeight(p.durationDays, maxD))
                    Text(DateFormatter.cycleMonth.string(from: p.startedAt))
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 150, alignment: .bottom)
    }

    private func barHeight(_ days: Int, _ maxD: Int) -> CGFloat {
        let ratio = CGFloat(days) / CGFloat(maxD)
        return 40 + ratio * 70
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(C.ink)
            Text(label).font(Typo.caption).foregroundStyle(C.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private var everyCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("每一次").font(Typo.cardTitle).foregroundStyle(C.ink)
                Spacer()
                Text("共 \(stats.periods.count) 次").font(Typo.caption).foregroundStyle(C.ink3)
            }
            .padding(.bottom, 12)

            ForEach(Array(stats.periods.enumerated()), id: \.element.id) { idx, p in
                if idx > 0 { Rectangle().fill(C.line).frame(height: 1) }
                CycleRow(period: p, stats: stats, showGap: true)
                    .padding(.vertical, 11)
            }
        }
        .padding(18)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }
}

// MARK: - 40 经期提醒

struct CycleNotifyView: View {

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @AppStorage("cycleLeadDays") private var leadDays = 2
    @AppStorage("cycleNotifyHour") private var notifyHour = 9
    @AppStorage("cycleNotifyOn") private var notifyOn = true
    @AppStorage("cycleMessage") private var message =
        "她可能要开始了。红糖和她爱喝的那个。"

    @State private var showDeniedHint = false

    private let hourChoices = [8, 9, 10, 12, 20]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                leadCard
                messageCard
                noteCard
            }
            .padding(.horizontal, S.screen)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(C.bg)
        .navigationTitle("经期提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }.foregroundStyle(C.ink2)
            }
        }
        .task { await reschedule() }
        .alert("通知被关掉了", isPresented: $showDeniedHint) {
            Button("去设置") { ReminderService.shared.openSystemSettings() }
            Button("知道了", role: .cancel) { }
        } message: {
            // **权限被拒不是错误是状态**（24 屏定下的）。
            // 这里直接给一条出路，而不是让她反复点开关。
            Text("系统里的通知开关是关的，这边排了也不会响。\n去设置里打开就能收到。")
        }
    }

    // MARK: 提前量 + 几点

    private var leadCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("提前多久告诉我").font(Typo.captionM).foregroundStyle(C.ink2)

            HStack(spacing: 8) {
                ForEach([0, 1, 2, 3], id: \.self) { d in
                    let on = leadDays == d
                    Button {
                        leadDays = d
                        Task { await reschedule() }
                    } label: {
                        Text(d == 0 ? "当天" : "\(d) 天")
                            .font(Typo.btn)
                            .foregroundStyle(on ? .white : C.ink2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(on ? C.primary : C.fill,
                                        in: RoundedRectangle(cornerRadius: 100, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(C.line).frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当天几点说").font(Typo.bodyS).foregroundStyle(C.ink)
                    Text("别太早，她醒来再提醒").font(Typo.caption).foregroundStyle(C.ink3)
                }
                Spacer()
                Menu {
                    ForEach(hourChoices, id: \.self) { h in
                        Button(String(format: "%02d:00", h)) {
                            notifyHour = h
                            Task { await reschedule() }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(String(format: "%02d:00", notifyHour))
                            .font(.system(size: 19, weight: .semibold).monospacedDigit())
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                    }
                    .foregroundStyle(C.primary)
                }
            }

            Toggle("开启提醒", isOn: $notifyOn)
                .font(Typo.bodyS)
                .tint(C.primary)
                .onChange(of: notifyOn) { _, _ in Task { await reschedule() } }
        }
        .padding(18)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }

    // MARK: 提醒里说什么

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("提醒里说什么").font(Typo.captionM).foregroundStyle(C.ink2)
                Text("点一下能改").font(Typo.caption).foregroundStyle(C.ink3)
            }

            TextField("", text: $message, axis: .vertical)
                .font(Typo.bodyS)
                .foregroundStyle(C.ink)
                .lineLimit(2...4)
                .padding(12)
                .background(C.fill, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
                .onChange(of: message) { _, _ in Task { await reschedule() } }

            HStack(spacing: 8) {
                preset("提醒我别惹她")
                preset("该买红糖了")
            }
        }
        .padding(18)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
    }

    private func preset(_ text: String) -> some View {
        Button {
            message = text
            Task { await reschedule() }
        } label: {
            Text(text)
                .font(Typo.captionM)
                .foregroundStyle(C.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(CYC.periodSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 边界说明

    private var noteCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(CYC.noteInk)
                .padding(.top, 1)
            Text("提醒是按你记下的日子推算的，不是医学判断。周期会有波动，日期差几天很正常 —— 别拿它当准点。")
                .font(Typo.caption)
                .foregroundStyle(CYC.noteInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CYC.noteBg, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
    }

    private func reschedule() async {
        let granted = await ReminderService.shared.requestNotificationPermission()
        if !granted && notifyOn { showDeniedHint = true }
        await CycleReminder.rescheduleAll(context: ctx,
                                          leadDays: leadDays,
                                          hour: notifyHour,
                                          enabled: notifyOn)
    }
}

// MARK: - 41 空态

struct CycleEmptyCard: View {

    let onRecord: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // 空环：一圈砂色点，没有一天是实的。
            // **画出来而不是放个图标** —— 它同时把「记完之后这里会长出什么」说清楚了。
            ZStack {
                ForEach(0..<CycleStats.defaultCycle, id: \.self) { i in
                    let r: CGFloat = 62
                    let a = Double(i) / Double(CycleStats.defaultCycle) * 2 * .pi - .pi / 2
                    Circle()
                        .fill(CYC.track)
                        .frame(width: 8, height: 8)
                        .position(x: 80 + r * cos(a), y: 80 + r * sin(a))
                }
                Text("还没有记录")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            }
            .frame(width: 160, height: 160)

            VStack(spacing: 6) {
                Text("记下她的经期")
                    .font(Typo.cardTitle)
                    .foregroundStyle(C.ink)
                Text("记一次就行，剩下的我来算")
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink3)
            }

            Button {
                onRecord()
            } label: {
                Text("记下这次").primaryButtonStyle()
            }
            .pressDown()

            // 三点说明：**先说清「要几件事」，再说「能得到什么」**。
            // 空态最怕的是不知道要填多少 —— 这里直接给一个数字：一次。
            VStack(alignment: .leading, spacing: 10) {
                bullet("只需要开始日和大概几天")
                bullet("记满两次就开始算规律")
                bullet("提前几天提醒你，日期能改")
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(C.card, in: RoundedRectangle(cornerRadius: R.cardBig, style: .continuous))
    }

    private func bullet(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(C.primary.opacity(0.5)).frame(width: 5, height: 5)
            Text(text).font(Typo.caption).foregroundStyle(C.ink2)
        }
    }
}
