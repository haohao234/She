//
//  ReminderEditorView.swift
//  对应画布 32 新建提醒 · 定时与场景
//
//  这一屏有两处刻意的设计判断，代码要照着实现，否则会在系统层走样：
//
//  ① **「时间」与「提前多久」必须分成两组。**
//     「每周三 20:00」是事实，「提前 10 分钟」是你想要的余量。
//     混在一组里，用户会算不清到底几点响 —— 而这正是提醒功能唯一会出错的点。
//
//  ② **通知预览放在表单最后一块。**
//     提醒的成败全在通知上那一行字。按下保存前先看见它长什么样，
//     是这一屏唯一不可省略的东西。
//
//  ③ 场景提醒受 iOS 限制：单个 App 最多监听 20 个 CLCircularRegion。
//     所以这里不做「想加多少加多少」，而是「从已有的高频地点里选」。
//

import SwiftUI
import SwiftData
import CoreLocation

struct ReminderEditorView: View {
    @Binding var path: [Route]
    /// 提醒挂在哪条记录上。nil = 还没选（从 05 屏的「新建提醒」进来时的状态）。
    let recordID: String?

    @Environment(\.modelContext) private var ctx

    @State private var kind: ReminderKind = .date
    @State private var targetRecord: Record?
    @State private var time = Calendar.current.date(from: DateComponents(hour: 20, minute: 0))!
    @State private var repeatRule: RepeatRule = .weekly
    @State private var weekday = 4           // 周三
    @State private var leadMinutes = 10
    @State private var placeName: String? = "公司"
    @State private var radius: Double = 300
    @State private var message = "该给她买白玫瑰了"
    @State private var showRecordPicker = false

    private let leadOptions = [0, 10, 60, 60 * 24]

    var body: some View {
        VStack(spacing: 0) {

            NavRow("新建提醒", onBack: { path.removeLast() }) {
                Button(action: save) {
                    Text("保存")
                        .font(Typo.pillSel)
                        .foregroundStyle(C.primary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(C.warm, in: Capsule(style: .continuous))
                }
                .pressDown()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: S.cardGap) {

                    // ① 提醒对象：提醒挂的是「一条记录」，不是一个自由文本。
                    //    这样点开通知能直接回到那条记录 —— 否则通知只是一句话，没有落点。
                    SCard {
                        HStack {
                            Text("提醒对象")
                                .font(Typo.captionM)
                                .foregroundStyle(C.ink3)
                            Spacer()
                            Button { showRecordPicker = true } label: {
                                Text(targetRecord == nil ? "选择一条记录" : "更换")
                                    .font(Typo.pillSel)
                                    .foregroundStyle(C.primary)
                            }
                        }
                        HStack(spacing: 10) {
                            Circle()
                                .fill(targetRecord?.cat.tint ?? C.ink3)
                                .frame(width: 8, height: 8)
                            Text(targetRecord?.title ?? "还没有选")
                                .font(Typo.body)
                                .foregroundStyle(targetRecord == nil ? C.ink3 : C.ink)
                            Spacer(minLength: 0)
                        }
                    }

                    // ② 提醒方式：两选一，且两个选项要同时可见 → 用分段控件
                    SegmentControl(options: ReminderKind.allCases,
                                   label: { $0.title },
                                   selection: $kind)

                    // ③ 时间 / 地点 —— 随方式整体换块，而不是在同一组里加可选字段。
                    //    混在一起会让表单变成「一半字段是灰的」，那是表单最难用的形态。
                    if kind == .date {
                        timeBlock
                    } else {
                        placeBlock
                    }

                    // ④ 提前多久。**独立成组**，理由见文件头。
                    SCard {
                        Text("提前多久")
                            .font(Typo.captionM)
                            .foregroundStyle(C.ink3)
                        ChipRow(options: leadOptions,
                                label: { leadLabel($0) },
                                selection: $leadMinutes)
                    }

                    // ⑤ 提醒文案
                    FieldBlock(label: "提醒文案") {
                        SField(placeholder: "给未来的自己留一句话", text: $message)
                    }

                    // ⑥ 通知预览 —— 表单最后一块，保存前唯一必须看见的东西
                    notificationPreview

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(C.ink2)
                        Text("到点会推送一条通知，点开直接回到这条记录")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink2)
                    }
                }
                .padding(.horizontal, S.screen)
                .padding(.vertical, 8)
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showRecordPicker) {
            RecordPickerSheet(picked: $targetRecord)
        }
        .task { loadTarget() }
    }

    // MARK: 定时块

    private var timeBlock: some View {
        SCard {
            Text("时间")
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)

            // 大时间：36 / 600 / 等宽数字。
            // 等宽是必须的 —— 否则数字一变宽度，整行都在跳。
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(time.hhmm)
                    .font(Typo.timeBig)
                    .foregroundStyle(C.ink)
                Text(weekdayLabel)
                    .font(Typo.body)
                    .foregroundStyle(C.ink2)
                Spacer(minLength: 0)
            }

            Rectangle().fill(C.line).frame(height: 1)

            FieldBlock(label: "重复") {
                ChipRow(options: RepeatRule.allCases,
                        label: { $0.title == "每周" ? weekdayLabel : $0.title },
                        selection: $repeatRule)
            }
        }
    }

    private var weekdayLabel: String {
        switch repeatRule {
        case .weekly:
            let names = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return names[min(max(weekday, 0), 6)]
        case .daily:   return "每天"
        case .monthly: return "每月"
        case .none:    return "仅一次"
        }
    }

    // MARK: 场景块

    private var placeBlock: some View {
        SCard {
            HStack {
                Text("地点")
                    .font(Typo.captionM)
                    .foregroundStyle(C.ink3)
                Spacer()
                Button { showRecordPicker = true } label: {
                    Text("更换")
                        .font(Typo.pillSel)
                        .foregroundStyle(C.primary)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16))
                    .foregroundStyle(C.primary)
                Text("到 \(placeName ?? "某处") 附近")
                    .font(Typo.body)
                    .foregroundStyle(C.ink)
                Spacer(minLength: 0)
            }

            Rectangle().fill(C.line).frame(height: 1)

            FieldBlock(label: "范围") {
                ChipRow(options: [200.0, 300.0, 500.0],
                        label: { "\(Int($0)) 米" },
                        selection: $radius)
                // iOS 单 App 最多监听 20 个 CLCircularRegion —— 所以这里是「选」
                // 而不是「加」，且应当在 05 屏给出额度提示。
                // 这个数字**从 ReminderService 读**，不写死：写死的那个 3
                // 会在用户真的加了第四个场景点时变成一句假话。
                Text("已用 \(ReminderService.shared.usedGeofences) / \(ReminderService.maxGeofences) 个场景点 · 太多会互相干扰，也会耗电")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            }
        }
    }

    // MARK: 通知预览

    /// 真机上这里应该请求一次 UNNotificationContent 的预览，
    /// 保证「设计里看到的样子」和「锁屏上出现的样子」是同一个。
    private var notificationPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通知预览")
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)

            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [C.primarySoft, C.primaryDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("她的信息本")
                            .font(Typo.captionM)
                            .foregroundStyle(C.ink)
                        Spacer()
                        Text("现在")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                    }
                    // 这一行就是提醒的全部 ——
                    // 保存前能看见它，是这一屏存在的意义。
                    Text(previewLine)
                        .font(Typo.bodyS)
                        .foregroundStyle(C.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(C.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(C.line, lineWidth: 1)
            )
        }
    }

    private var previewLine: String {
        let lead = leadLabel(leadMinutes)
        return lead == "准时" ? message : "\(message) · 提前 \(lead)"
    }

    private func leadLabel(_ m: Int) -> String {
        switch m {
        case 0:           return "准时"
        case 10:          return "提前 10 分钟"
        case 60:          return "提前 1 小时"
        case 60 * 24:     return "提前 1 天"
        default:          return "提前 \(m) 分钟"
        }
    }

    // MARK: 读写

    private func loadTarget() {
        guard let rid = recordID else { return }
        // `#Predicate` 的泛型参数要写出来。省略时靠上下文推断，
        // 而宏展开发生在类型检查之前，推断失败时报的是「无法推断 Predicate 的类型」，
        // 那个错误信息不会指向这里。
        let d = FetchDescriptor<Record>(predicate: #Predicate<Record> { $0.id == rid })
        targetRecord = try? ctx.fetch(d).first
        if let m = targetRecord?.reminder {
            message = m.message
            kind = m.kind
            leadMinutes = m.leadMinutes
            repeatRule = m.repeatRule
            time = m.time
        }
    }

    private func save() {
        guard let rec = targetRecord else { return }
        let m = rec.reminder ?? Reminder(kind: kind, title: rec.title, message: message)
        m.kind = kind
        m.title = rec.title
        m.repeatRule = repeatRule
        m.weekday = weekday
        m.time = time
        m.leadMinutes = leadMinutes
        m.placeName = kind == .geo ? placeName : nil
        m.radius = radius
        m.message = message
        m.isOn = true
        m.record = rec
        if rec.reminder == nil { ctx.insert(m) }
        try? ctx.save()

        // 真机上落地在这里：
        //   ReminderService.schedule(m) 内部会调
        //   UNUserNotificationCenter.add(request) 或
        //   CLMonitor / CLLocationManager.startMonitoring(for: CLCircularRegion)
        Task { await ReminderService.shared.schedule(m) }
        path.removeLast()
    }
}

// MARK: - 选记录

struct RecordPickerSheet: View {
    @Binding var picked: Record?
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Record> { $0.deletedAt == nil },
           sort: \Record.updatedAt, order: .reverse)
    private var records: [Record]

    var body: some View {
        NavigationStack {
            List(records) { r in
                Button {
                    picked = r
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(r.cat.tint).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title)
                                .font(Typo.body)
                                .foregroundStyle(C.ink)
                            Text(r.cat.title)
                                .font(Typo.caption)
                                .foregroundStyle(C.ink3)
                        }
                    }
                }
            }
            .navigationTitle("选一条记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
