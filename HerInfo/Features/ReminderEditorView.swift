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
//  【2026-09-15 补的三处，都是「设计有、代码没有」】
//  · **时间可改**：那个大字以前是纯 `Text`，没有日期选择器 ——
//    这一屏叫「新建提醒」，而它唯一不能改的就是时间。
//  · **星期几可选**：「每周」那一枚胶囊的文字会变成「每周三」，
//    但点它只切到「每周」，没有任何地方能改是星期几 —— 于是永远落在周三。
//  · **场景真接上**：地点那行的「更换」按钮错接到「选记录」上，
//    `latitude` / `longitude` 从来没被写过，而 `ReminderService.scheduleGeo`
//    第一句就是 `guard let lat = ... else { return }` ——
//    表现是「场景提醒看着设好了，一条围栏都没注册过」。
//

import SwiftUI
import SwiftData
import CoreLocation

struct ReminderEditorView: View {
    @Binding var path: [Route]

    /// 编辑哪一条提醒。nil = 新建。
    ///
    /// **按提醒 id、不按记录 id。** 2026-10-27 起提醒可以不挂记录，
    /// 按记录 id 找的话这一类根本进不来（见 `Route.reminderEdit`）。
    var reminderID: String? = nil

    /// 新建时预选一条记录。nil = 自由编辑（不关联任何记录）。
    ///
    /// 「必须选一条记录才能建提醒」是这一屏此前的硬门槛 ——
    /// 而用户想记的常常是「周三记得订花」这种没有对应记录的事。
    var presetRecordID: String? = nil

    @Environment(\.modelContext) private var ctx

    /// 正在编辑的那一条（nil = 新建）。
    ///
    /// **不能像以前那样靠 `record.reminder` 反查** —— 自由编辑的提醒
    /// 根本不在任何 `record` 上，反查永远是 nil。
    @State private var existing: Reminder?

    @State private var kind: ReminderKind = .date
    @State private var targetRecord: Record?
    /// 「自由编辑」时用户自己写的标题。挂了记录时不用它（标题取那条记录的）。
    @State private var freeTitle = ""
    /// 默认值取自 12 屏「默认提醒时间」那一行（**设计稿给的是 20:30**）。
    /// 此前这里写死 20:00、且设置页没有那一行，于是这个时间无处可改。
    @State private var time = ReminderService.defaultTime
    @State private var draftTime = ReminderService.defaultTime
    @State private var repeatRule: RepeatRule = .weekly
    @State private var weekday = 4           // 周三
    @State private var leadMinutes = 10
    @State private var placeName = "公司"
    @State private var radius: Double = 300
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var placeAddress: String?
    @State private var resolving = false
    @State private var message = "该给她买白玫瑰了"

    @State private var showRecordPicker = false
    @State private var showTimePicker = false
    @State private var showDeleteConfirm = false

    private let leadOptions = [0, 10, 60, 60 * 24]

    /// 是不是在改一条已经存在的提醒。
    private var isEditing: Bool { reminderID != nil }

    /// 这条提醒最终写进 `content.title` 的那一行 —— 也就是通知的第一行。
    ///
    /// 挂记录 → 那条记录的标题（与 `ReminderService.userInfo` 一致）；
    /// 自由编辑 → 用户自己写的标题。预览与实物读的是同一个值，
    /// 不然又会出现「预览里看到的话和真发出去的话不是同一句」。
    private var resolvedTitle: String {
        if let rec = targetRecord { return rec.title }
        return freeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 通知正文那一句。
    ///
    /// 自由编辑时「提醒文案」可以留空 —— 那时把标题接过来当正文。
    /// **不能留空**：`content.body` 为空的通知在锁屏上只剩一行标题，
    /// 看起来像一条没写完的消息；而用户其实只是把标题写在了标题框里。
    private var resolvedMessage: String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? resolvedTitle : text
    }

    /// 场景的四个触发点。
    ///
    /// **后两个是 2026-09-15 换过的。** 原设计给的是
    /// 「到公司 / 到家 / 连上车载 / 打开购物 App」，而后两个 iOS 做不到：
    ///   · 「打开购物 App」—— 系统不允许一个 App 监听另一个 App 被启动，那是沙盒边界；
    ///   · 「连上车载」—— 要 CarPlay 场景适配 + entitlement，不是本地能开的东西。
    /// 与其留两枚永远不亮的胶囊，不如把这一行**收回唯一能做的心智上**：
    /// 「到某个地方就提醒」。名字仍然由用户定（最后一枚就是自定义）。
    private static let presetPlaces = ["公司", "家", "商场"]

    // 星期那一组（名字 + 选项值）**已收口到 `Reminder.weekdayNames` /
    // `Reminder.weekdayOptions`**：05 屏卡片第三行也要念同一句话，
    // 两个文件各存一份迟早会分叉。这里不再留副本。

    var body: some View {
        VStack(spacing: 0) {

            NavRow(isEditing ? "编辑提醒" : "新建提醒",
                   onBack: { path.removeLast() }) {
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

                    // ① 提醒对象 —— **可选**。
                    //
                    // 以前这里是硬门槛：不选一条记录就存不下去。可用户想记的
                    // 常常是「周三记得订花」这种没有对应记录的事 ——
                    // 为了建一条提醒，先被迫去造一条记录，那是本末倒置。
                    //
                    // 现在两条路，各自说清代价：
                    //   · 选一条记录 → 通知标题取那条记录的标题，点通知能跳回那条记录；
                    //   · 不选（自由编辑）→ 自己写标题，提醒照样响，只是点通知没有落点。
                    SCard {
                        HStack {
                            Text("提醒对象")
                                .font(Typo.captionM)
                                .foregroundStyle(C.ink3)
                            Spacer()
                            Button { showRecordPicker = true } label: {
                                Text(targetRecord == nil ? "选一条记录" : "更换")
                                    .font(Typo.pillSel)
                                    .foregroundStyle(C.primary)
                            }
                        }
                        HStack(spacing: 10) {
                            Circle()
                                .fill(targetRecord?.cat.tint ?? C.ink3)
                                .frame(width: 8, height: 8)
                            Text(targetRecord?.title ?? "自由编辑 · 不关联记录")
                                .font(Typo.body)
                                .foregroundStyle(targetRecord == nil ? C.ink3 : C.ink)
                            Spacer(minLength: 0)
                            // 断开记录**不丢字**：那段标题搬进下面的标题框（见 `unlinkRecord`）。
                            if targetRecord != nil {
                                Button("取消关联") { unlinkRecord() }
                                    .font(Typo.caption)
                                    .foregroundStyle(C.ink3)
                            }
                        }

                        // 只有自由编辑才需要标题 —— 挂记录时那一行由记录提供。
                        if targetRecord == nil {
                            Rectangle().fill(C.line).frame(height: 1)
                            FieldBlock(label: "标题") {
                                SField(placeholder: "这条提醒叫什么，比如「订一束白玫瑰」",
                                       text: $freeTitle)
                            }
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
                    //
                    // **场景那一档不给这一组。** 「提前 10 分钟」在定时提醒里是真的
                    // （`scheduleDate` 会把触发时刻往前挪），而场景提醒是
                    // `CLCircularRegion` 在「进入」那一刻回调的 ——
                    // 物理上不存在「进入前 10 分钟」。留着它只有两种结局：
                    // 用户以为设上了、或者发现设了没用。两种都比没有更糟。
                    if kind == .date {
                        SCard {
                            Text("提前多久")
                                .font(Typo.captionM)
                                .foregroundStyle(C.ink3)
                            ChipRow(options: leadOptions,
                                    label: { leadLabel($0) },
                                    selection: $leadMinutes)
                        }
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
                        // **措辞跟着「有没有关联记录」变。**
                        // 自由编辑的提醒点开没有落点可跳 —— 还写「点开回到这条记录」
                        // 就是一句兑现不了的承诺。
                        Text(targetRecord == nil
                             ? (kind == .date
                                ? "到点会推送一条通知。没有关联记录，点开就停在提醒列表"
                                : "到你设的地方附近时会推送一条通知。没有关联记录，点开停在提醒列表")
                             : (kind == .date
                                ? "到点会推送一条通知，点开直接回到这条记录"
                                : "到你设的地方附近时会推送一条通知，点开回到这条记录"))
                            .font(Typo.caption)
                            .foregroundStyle(C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // 删除 —— **只在编辑态出现**。新建到一半没有「删除」可言。
                    //
                    // 05 屏卡片上也有一个垃圾桶，两处都留着：列表里是「扫一眼就删掉」，
                    // 编辑器里是「点进去看清楚了再删」。这是同一个人在不同时刻的两种意图。
                    if isEditing {
                        Button { showDeleteConfirm = true } label: {
                            Text("删除这条提醒")
                                .font(Typo.pillSel)
                                .foregroundStyle(C.danger)
                                .frame(maxWidth: .infinity)
                                .frame(height: PillSize.regular.height)
                                .background(C.fill, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
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
        .sheet(isPresented: $showTimePicker) { timePickerSheet }
        .alert("删除这条提醒？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) { deleteExisting() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后不再提醒，也不能恢复。已有记录不受影响。")
        }
        .task { loadTarget() }
    }

    // MARK: 定时块

    private var timeBlock: some View {
        SCard {
            Text("时间")
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)

            // 大时间：36 / 600 / 等宽数字。「等宽」是必须的 ——
            // 否则数字一变宽度，整行都在跳。
            //
            // **这一块整体是一个按钮。** 此前它是一个死掉的 `Text` ——
            // 于是这一屏唯一不能改的东西恰好是它的主角。可点的范围做成
            // 「数字 + 右边的重复说明」一整个矩形：只让三个数字笔画可点
            // 在真机上是要瞄准的。
            Button {
                draftTime = time
                showTimePicker = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(time.hhmm)
                        .font(Typo.timeBig)
                        .foregroundStyle(C.ink)
                    Text(dateLabel)
                        .font(Typo.body)
                        .foregroundStyle(C.ink2)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(C.line).frame(height: 1)

            FieldBlock(label: "重复") {
                ChipRow(options: RepeatRule.allCases,
                        label: { $0.title },
                        selection: $repeatRule)

                // 「每周」选中后多摊出一排星期。
                //
                // 定稿里那一枚胶囊的文字会变成「每周三」，可点它只切到「每周」——
                // **没有任何地方能改它落在星期几**，于是「每周」永远是周三。
                // 这里把「哪一天」显式摆出来，而不是藏进第二次点击。
                if repeatRule == .weekly {
                    ChipRow(options: Reminder.weekdayOptions,
                            label: { Reminder.weekdayNames[$0] },
                            selection: $weekday)
                }
            }
        }
    }

    /// 大时间右边那一行小字：这条提醒**落在什么时候**。
    ///
    /// 每种规则说的东西不同，而且要说得出区别 —— 尤其「每月 / 每年」：
    /// 它们的具体日子是上面那行大字里选的（点开就是日期 + 时间的选择器），
    /// 所以这里必须把那个日子念出来，否则用户改完了在界面上看不到任何变化。
    /// 算法本身**不在这里** —— 在 `Reminder.makeRepeatLine`。
    /// 05 屏卡片第三行说的就是同一句话（「每月 13 号 · 提前 1 天」），
    /// 两处各写一份 switch 的话，改了一边另一边就悄悄旧了。
    private var dateLabel: String {
        Reminder.makeRepeatLine(rule: repeatRule, weekday: weekday, time: time,
                                dayOfMonth: Calendar.current.component(.day, from: time))
    }

    /// 选择器要不要连日期一起给。
    ///
    /// 「每天 / 每周」只需要时分 —— 星期几由上面那排胶囊决定，
    /// 日期给它反而是个没人看的空转字段。
    /// 而「仅一次 / 每月 / 每年」的日子**只能在这里选**，不给就是没处可改。
    private var timePicksDate: Bool {
        switch repeatRule {
        case .daily, .weekly: return false
        case .none, .monthly, .yearly: return true
        }
    }

    // MARK: 场景块

    private var placeBlock: some View {
        SCard {
            Text("地点")
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)

            // 四个触发点。前三枚是高频地点，最后一枚让用户自己起名。
            //
            // 这一排**取代**了原来那个错接的「更换」按钮 ——
            // 它当时跳的是「选记录」，于是地点永远是硬编码的「公司」，
            // 而用户按了那个按钮会莫名其妙地看到一个记录列表。
            ChipRow(options: Self.presetPlaces + [Self.customPlaceTag],
                    label: { $0 == Self.customPlaceTag ? "自定义" : "到\($0)" },
                    selection: placeSelection)

            if placeSelection.wrappedValue == Self.customPlaceTag {
                SField(placeholder: "给这个地点起个名字，比如「她爸妈家」", text: $placeName)
            }

            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16))
                    .foregroundStyle(C.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("到「\(placeName.isEmpty ? "某处" : placeName)」附近")
                        .font(Typo.body)
                        .foregroundStyle(C.ink)
                    Text(placeCoordLine)
                        .font(Typo.caption)
                        .foregroundStyle(latitude == nil ? C.ink3 : C.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // 取坐标。**这是场景提醒真正能被"设上"的那一步。**
            //
            // 设计稿在这一块只给了地点名，没有交代坐标从哪来 ——
            // 而 `CLCircularRegion` 必须有真实经纬度。让用户凭空填一个地址，
            // 系统既解析不出「公司」这种叫法，解析出来也未必是他站的地方。
            // 所以用「取当前位置」，并把他当下站的地方反查成一个能认的地址名，
            // 让他有机会发现「取错了」。
            Button {
                Task { await resolveCurrentPlace() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: resolving ? "location.fill" : "location")
                        .font(.system(size: 13, weight: .medium))
                    Text(resolving ? "正在定位…" : (latitude == nil ? "取当前位置" : "重新取当前位置"))
                        .font(Typo.pillSel)
                }
                .foregroundStyle(C.primary)
                .padding(.horizontal, 14)
                .frame(height: PillSize.regular.height)
                .background(C.warm, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(resolving)

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

    /// 自定义那一枚胶囊的标记值。**用一个不太可能被当成地点名的字符串** ——
    /// 拿「自定义」本身当值时，用户真给地点起名「自定义」就会卡在这上面。
    private static let customPlaceTag = "\u{1}custom"

    /// chip 的绑定：读的是「当前名字在不在预设里」，写的是「把名字换成它」。
    ///
    /// 之所以不把 `placeName` 直接给 ChipRow：那一排里选中的是**名字**，
    /// 而自定义那一枚代表的是「名字不在预设里」这个状态 ——
    /// 两者是同一个值的两种读法，用一个计算绑定就够，不必再存一个枚举。
    private var placeSelection: Binding<String> {
        Binding(
            get: { Self.presetPlaces.contains(placeName) ? placeName : Self.customPlaceTag },
            set: { v in
                if v == Self.customPlaceTag {
                    // 进自定义时把名字清掉，让输入框的占位提示露出来 ——
                    // 留着一个「商场」会让人以为那已经是自定义的名字了。
                    if Self.presetPlaces.contains(placeName) { placeName = "" }
                } else {
                    placeName = v
                }
            })
    }

    /// 坐标那一行。三种状态要说得出区别，因为它们对应三件不同的事。
    private var placeCoordLine: String {
        guard let lat = latitude, let lon = longitude else {
            return "还没有坐标 —— 取一次当前位置才存得下去"
        }
        if let placeAddress { return "\(placeAddress) · \(String(format: "%.4f, %.4f", lat, lon))" }
        return String(format: "%.4f, %.4f", lat, lon)
    }

    /// 取当前位置 → 存坐标 → 反查一个能认的地名。
    private func resolveCurrentPlace() async {
        resolving = true
        defer { resolving = false }

        guard let c = await ReminderService.shared.currentCoordinate() else {
            // **拿不到必须说出来。** 静默跳过的话用户会按「保存」，
            // 然后得到一条永远不响的提醒 —— 那正是这个功能此前的病根。
            ToastCenter.shared.show("取不到位置，检查一下定位权限")
            return
        }
        latitude = c.latitude
        longitude = c.longitude
        placeAddress = await Self.reverseName(c)
    }

    /// 反查一个可读地名。**失败就返回 nil、界面上少一段字**，不报错 ——
    /// 反查要联网，而「取坐标」这件事本身不需要网，不该被它拖住。
    private static func reverseName(_ c: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
        guard let marks = try? await geocoder.reverseGeocodeLocation(loc),
              let p = marks.first else { return nil }
        return [p.name, p.locality, p.administrativeArea]
            .compactMap { $0 }
            .first
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
                        // 通知横幅上那个「发件人」名字。必须与 CFBundleDisplayName
                        // 一致 —— 否则真机弹出来的通知与这里预览的不是同一个名字。
                        Text("我的宝宝江林桐")
                            .font(Typo.captionM)
                            .foregroundStyle(C.ink)
                        Spacer()
                        Text("现在")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                    }
                    // **先标题、后正文 —— 跟真机上一样。**
                    //
                    // 通知横幅上最醒目的是 `content.title`，而
                    // `ReminderService.scheduleDate` 把它设成记录的标题
                    // （`content.title = r.title`，`r.title` 在保存时被写成 `rec.title`）。
                    // 此前预览只画了正文，于是「保存前先看见它长什么样」少了一半 ——
                    // 锁屏上先被看见的那一行恰恰没画。
                    //
                    // 标题为空时不画标题行：记录只加了图、没写字的那种，
                    // 真机上也没有这一行。**预览不编**，编了就等于又骗一次。
                    // 标题读 `resolvedTitle` —— **和 `content.title` 是同一个值**。
                    // 以前读的是 `targetRecord?.title`，自由编辑时永远是 nil，
                    // 于是预览少画一行，而真机上那一行是存在的。
                    if !resolvedTitle.isEmpty {
                        Text(resolvedTitle)
                            .font(Typo.bodyS)
                            .foregroundStyle(C.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 这一行是提醒的正文 ——
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

    /// 预览那一行 = 正文 + 触发条件。
    ///
    /// **这不是第二处实现，是同一处**：算法在
    /// `Reminder.makePreviewLine(...)`，这里只是把还没落库的那几个 `@State`
    /// 喂给它。此前两边各写一遍，于是切到「场景」时预览显示「到公司附近」，
    /// 而真正排出去的通知正文写的是「提前 10 分钟」——
    /// 预览和实物不是同一句话，那一块预览就白设了。
    private var previewLine: String {
        Reminder.makePreviewLine(kind: kind,
                                 message: resolvedMessage,
                                 placeName: placeName.isEmpty ? nil : placeName,
                                 leadMinutes: leadMinutes)
    }

    /// chip 上那一行字。**带「提前」前缀**，因为它是可选项的标签，不是正文 ——
    /// 正文里由 `leadText` 拼，两处不要混用。
    private func leadLabel(_ m: Int) -> String {
        m == 0 ? "准时" : "提前 \(Reminder.leadText(for: m))"
    }

    // MARK: 时间选择

    /// 32 屏那个大数字点开后的样子。
    ///
    /// 复用 12 屏「默认提醒时间」同一种做法（系统 wheel）——
    /// 时间是系统级惯例，自己排一排数字只会让人多花两秒找「分钟在哪」。
    private var timePickerSheet: some View {
        VStack(spacing: 0) {
            // ⚠️ 这一行**必须写 `trailing:`**。`NavRow` 的参数是
            // `(_ title:, onBack: = nil, @ViewBuilder trailing:)` —— 这里不传 `onBack`，
            // 于是「不写标签的尾随闭包」只能靠**向后匹配**落到 `trailing` 上，
            // Swift 6 已把那条路标成 deprecation warning，
            // 而本工程的流水线**有 warning 就红**（2026-09-15 实测：就是这么红的一次）。
            NavRow("提醒时间", trailing: {
                Button {
                    time = draftTime
                    showTimePicker = false
                } label: {
                    Text("完成")
                        .font(Typo.pillSel)
                        .foregroundStyle(C.primary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(C.warm, in: Capsule(style: .continuous))
                }
                .pressDown()
            })

            // 选择器给不给日期，随「重复」那一排而定 —— 见 `timePicksDate`。
            DatePicker("", selection: $draftTime,
                       displayedComponents: timePicksDate
                           ? [.date, .hourAndMinute]
                           : .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.top, 4)

            Text(timePicksDate
                 ? "日子和时刻都在这里选 —— 「仅一次」就只在选中的那一天响一次。"
                 : "只取时分 —— 哪天响由上面那一排「重复」决定。")
                .font(Typo.caption)
                .foregroundStyle(C.ink3)
                .padding(.horizontal, S.screen)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .background(C.bg)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    // MARK: 读写

    private func loadTarget() {
        // 编辑：按**提醒 id** 取那一条 —— 挂不挂记录都取得到。
        if let mid = reminderID {
            // `#Predicate` 的泛型参数要写出来。省略时靠上下文推断，
            // 而宏展开发生在类型检查之前，推断失败时报的是「无法推断 Predicate 的类型」，
            // 那个错误信息不会指向这里。
            let d = FetchDescriptor<Reminder>(predicate: #Predicate<Reminder> { $0.id == mid })
            guard let m = try? ctx.fetch(d).first else { return }
            existing = m
            targetRecord = m.record
            // 自由编辑的提醒，标题存在 `Reminder.title` 里 —— 搬回输入框。
            // 挂着记录的那些不搬：那个标题属于记录，不该在这里被改成提醒自己的。
            freeTitle = (m.record == nil) ? m.title : ""
            apply(m)
            return
        }

        // 新建：最多预选一条记录（05 屏的入口现在传 nil，这条路是给以后的
        // 「从某条记录直接加提醒」留的）。
        guard let rid = presetRecordID else {
            // **自由编辑：把示例文案清掉。** 「该给她买白玫瑰了」是记录那一路的
            // 示例句，留着它，用户得先删掉一行别人的话才能写自己的。
            // 正文空着没关系 —— `resolvedMessage` 会拿标题顶上。
            message = ""
            return
        }
        let d = FetchDescriptor<Record>(predicate: #Predicate<Record> { $0.id == rid })
        targetRecord = try? ctx.fetch(d).first
        // 这条记录**已经有一条提醒**了 → 直接进编辑态。
        // 不然用户要把整张表填完、按保存才被拦下，刚才那几分钟白写。
        if let m = targetRecord?.reminder {
            existing = m
            apply(m)
        }
    }

    /// 把一条已有提醒的字段灌进各个 `@State`。
    ///
    /// **少灌一项就是一处静默回退** —— 用户进来看一眼再按保存，
    /// 那一项会被写回默认值，而界面全程没有提示。
    private func apply(_ m: Reminder) {
        message = m.message
        kind = m.kind
        leadMinutes = m.leadMinutes
        repeatRule = m.repeatRule
        // **老数据里可能是「公元 1 年」**：早期默认值用
        // `DateComponents(hour:minute:)` 造，缺省年月日被填成 1。
        // 那种时刻一进「仅一次」的过期判断就永远是过去，改时间也救不回来 ——
        // 在这里归到今天（时分不变），下面 `save()` 会把它写回去。
        time = ReminderService.normalize(m.time)

        // **下面这五项曾经漏掉，后果是「编辑即损坏」。**
        //
        // 它们不在上面那批里，于是进来看一眼再按保存，用户之前调好的东西
        // 会被静默写回默认值：设的「每周一」变回周三（`weekday` 的默认 4）、
        // 半径从 500 米变回 300、地点从「家」变回「公司」，
        // 场景提醒的坐标被清成 nil（于是这条提醒再也不响）。
        // 界面全程没有任何提示 —— 用户只会觉得「这功能自己会变」。
        weekday = m.weekday ?? 4
        radius = m.radius
        placeName = m.placeName ?? "公司"
        latitude = m.latitude
        longitude = m.longitude
    }

    /// 断开记录 → **文字不丢**：把那段标题搬进自由编辑的标题框。
    ///
    /// 不搬的话，用户点一下「取消关联」，通知标题就凭空少了一行 ——
    /// 而那行字原本是写得好好的。
    private func unlinkRecord() {
        if let rec = targetRecord, freeTitle.isEmpty { freeTitle = rec.title }
        targetRecord = nil
    }

    /// 真删。跟 05 屏那个垃圾桶是同一套动作（见 `ReminderListView.remove`）。
    private func deleteExisting() {
        guard let m = existing else { return }
        // **先取 id、再删对象**：删完再读属性读到的是墓碑。
        let id = m.id
        if let rec = m.record { rec.reminder = nil }
        MissedReminders.shared.forget(id)
        ctx.delete(m)
        try? ctx.save()
        Task { await ReminderService.shared.cancel(reminderID: id) }
        path.removeLast()
    }

    private func save() {
        // **不再强制选记录。** 标题是通知横幅上的第一行，所以它必须有 ——
        // 挂记录时由那条记录提供，自由编辑时要用户自己写（见 `resolvedTitle`）。
        // 之前这里是一句 `guard let rec = targetRecord else { 先选一条记录 }`，
        // 于是「周三记得订花」这种没有对应记录的事，根本建不成提醒。
        let title = resolvedTitle
        guard !title.isEmpty else {
            ToastCenter.shared.show("给这条提醒起个标题，或者选一条记录")
            return
        }

        // **没坐标就不许保存。** 存下去就是一条永远不会响的提醒，
        // 而用户会以为设好了 —— 这个功能此前就是这个状态。
        if kind == .geo, latitude == nil || longitude == nil {
            ToastCenter.shared.show("场景提醒要先取一次当前位置")
            return
        }

        // 「仅一次」选了个已经过去的时间 = 一条永远不响的提醒。
        // `UNCalendarNotificationTrigger` 不会为过去的时间报错，它就静静地什么都不做，
        // 用户那边表现为「设了、没响、也没提示」—— 又是那个最坏的形态。
        //
        // 先归一化再判断：老数据里 `time` 可能是「公元 1 年」（见 `apply(_:)`），
        // 不归一化的话，今天 12:00 也会被算成过去。
        let fireTime = ReminderService.normalize(time)
        if kind == .date, repeatRule == .none {
            let trigger = fireTime.addingTimeInterval(-Double(leadMinutes) * 60)
            guard trigger >= .now else {
                // 两件事分开说，否则用户会以为是自己选错了时间：
                // 前者是时间本身过去了，后者只是「提前量」那一截过去了。
                ToastCenter.shared.show(fireTime < .now
                    ? "这个时间已经过去了，换一个"
                    : "提前 \(Reminder.leadText(for: leadMinutes)) 那一截已经过了，换「准时」或者往后挪一点")
                return
            }
        }

        // **一条记录最多挂一个提醒**（`Record.reminder` 的注释里写着这条规则）。
        // 把一条自由提醒挂到「已经有提醒」的记录上，原来那条会静默变成孤儿 ——
        // 它不再属于任何记录，却还在列表里、还会响。挡住，并说清该去哪删。
        if let rec = targetRecord, let other = rec.reminder, other.id != existing?.id {
            ToastCenter.shared.show("「\(rec.title)」已经有一条提醒了，先去列表里删掉它")
            return
        }

        let m: Reminder
        if let e = existing {
            m = e
        } else {
            m = Reminder(kind: kind, title: title, message: resolvedMessage)
            ctx.insert(m)
        }
        m.kind = kind
        m.title = title
        m.repeatRule = repeatRule
        m.weekday = weekday
        m.time = fireTime
        // **`dayOfMonth` 此前从来没有被写过。** 少了它，`scheduleDate` 里
        // `comps.day = nil`，「每月」就会退化成「每天」响 —— 而界面上写着「每月」。
        // 值直接取 `time` 的那一天：用户是在时间选择器里选的，
        // 落一份下来只是为了让排程那一步不必再去问日历。
        m.dayOfMonth = (repeatRule == .monthly || repeatRule == .yearly)
            ? Calendar.current.component(.day, from: fireTime) : nil
        // **场景提醒把提前量归零。** 界面上那一组在场景态是**不画的**（见上面 `if kind == .date`），
        // 于是它带着一个用户看不见、也改不了的旧值落库 —— 而
        // `Reminder.previewLine` 会把它印进通知正文，就出现了
        // 「进入公司附近 · 提前 10 分钟」这种自相矛盾的一句话。
        // 归零不是「丢掉用户的选择」：那个选择在场景这一路本来就不成立。
        m.leadMinutes = kind == .geo ? 0 : leadMinutes
        m.placeName = kind == .geo ? (placeName.isEmpty ? nil : placeName) : nil
        m.radius = radius
        // **这两行此前没有。** 少了它们，`ReminderService.scheduleGeo` 第一句
        // `guard let lat = r.latitude` 就 return —— 一条围栏都注册不上，
        // 而界面上一切正常。用户报的「场景提醒没有实现」就是这一处。
        m.latitude = kind == .geo ? latitude : nil
        m.longitude = kind == .geo ? longitude : nil
        m.message = resolvedMessage
        m.isOn = true
        m.record = targetRecord
        try? ctx.save()

        // **保存这一刻是授权意愿最强的瞬间**（他刚写完这条提醒），
        // 所以顺手把权限问一次；问过就不再弹了（见
        // `requestNotificationPermissionIfNeeded`）。
        // 排在 `schedule` 之前 —— 反过来的话，第一次保存必然因为没权限而排不上。
        Task {
            _ = await ReminderService.shared.requestNotificationPermissionIfNeeded()
            await ReminderService.shared.schedule(m)
        }
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
                        Spacer(minLength: 0)
                        // **把「已经有了」提前说出来。** 不说的话，用户选完、
                        // 写到一半按保存才被拦下（一条记录最多挂一个提醒），
                        // 而那时候他已经不知道该删哪一条了。
                        if r.reminder != nil {
                            Pill(text: "已有提醒", style: .flat, soft: C.warm, size: .tag,
                                 emphasis: false, textTint: C.ink3)
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
