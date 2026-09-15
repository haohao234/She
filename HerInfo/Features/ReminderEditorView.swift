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
    /// 提醒挂在哪条记录上。nil = 还没选（从 05 屏的「新建提醒」进来时的状态）。
    let recordID: String?
    /// 是不是在改一条已经存在的提醒（05 屏点条目进来的那条路）。
    ///
    /// 只看它换标题 —— 因为「新建到一半、目标记录早就有一条提醒」这种情况
    /// 走的是同一段读写逻辑，不该长成第二套界面。
    var isEditing: Bool = false

    @Environment(\.modelContext) private var ctx

    @State private var kind: ReminderKind = .date
    @State private var targetRecord: Record?
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

    private let leadOptions = [0, 10, 60, 60 * 24]

    /// 场景的四个触发点。
    ///
    /// **后两个是 2026-09-15 换过的。** 原设计给的是
    /// 「到公司 / 到家 / 连上车载 / 打开购物 App」，而后两个 iOS 做不到：
    ///   · 「打开购物 App」—— 系统不允许一个 App 监听另一个 App 被启动，那是沙盒边界；
    ///   · 「连上车载」—— 要 CarPlay 场景适配 + entitlement，不是本地能开的东西。
    /// 与其留两枚永远不亮的胶囊，不如把这一行**收回唯一能做的心智上**：
    /// 「到某个地方就提醒」。名字仍然由用户定（最后一枚就是自定义）。
    private static let presetPlaces = ["公司", "家", "商场"]

    /// 星期。`Calendar` 里 1 = 周日、7 = 周六 —— 与 `Reminder.weekday` 的约定一致。
    private static let weekdayNames = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private static let weekdayOptions = [1, 2, 3, 4, 5, 6, 7]

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
                        Text(kind == .date
                             ? "到点会推送一条通知，点开直接回到这条记录"
                             : "到你设的地方附近时会推送一条通知，点开回到这条记录")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
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
                    ChipRow(options: Self.weekdayOptions,
                            label: { Self.weekdayNames[$0] },
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
    private var dateLabel: String {
        switch repeatRule {
        case .weekly:
            // **上限是 7，不是 6。** 数组下标 1…7 才对应周日…周六；
            // 写 6 的话周六会被夹成周五 —— 一个只在周六才出现、所以很难被撞见的错。
            return Self.weekdayNames[min(max(weekday, 1), 7)]
        case .daily:   return "每天"
        case .monthly: return "每月 \(Calendar.current.component(.day, from: time)) 号"
        case .yearly:  return "每年 \(time.monthDayCN)"
        case .none:    return "\(time.monthDayCN) · 仅一次"
        }
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

    /// 预览那一行 = 正文 + 触发条件。
    ///
    /// **这不是第二处实现，是同一处**：算法在
    /// `Reminder.makePreviewLine(...)`，这里只是把还没落库的那几个 `@State`
    /// 喂给它。此前两边各写一遍，于是切到「场景」时预览显示「到公司附近」，
    /// 而真正排出去的通知正文写的是「提前 10 分钟」——
    /// 预览和实物不是同一句话，那一块预览就白设了。
    private var previewLine: String {
        Reminder.makePreviewLine(kind: kind,
                                 message: message,
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
            NavRow("提醒时间") {
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
            }

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
    }

    private func save() {
        guard let rec = targetRecord else {
            ToastCenter.shared.show("先选一条要提醒的记录")
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
        if kind == .date, repeatRule == .none,
           time.addingTimeInterval(-Double(leadMinutes) * 60) < .now {
            ToastCenter.shared.show("这个时间已经过去了，换一个")
            return
        }

        let m = rec.reminder ?? Reminder(kind: kind, title: rec.title, message: message)
        m.kind = kind
        m.title = rec.title
        m.repeatRule = repeatRule
        m.weekday = weekday
        m.time = time
        // **`dayOfMonth` 此前从来没有被写过。** 少了它，`scheduleDate` 里
        // `comps.day = nil`，「每月」就会退化成「每天」响 —— 而界面上写着「每月」。
        // 值直接取 `time` 的那一天：用户是在时间选择器里选的，
        // 落一份下来只是为了让排程那一步不必再去问日历。
        m.dayOfMonth = (repeatRule == .monthly || repeatRule == .yearly)
            ? Calendar.current.component(.day, from: time) : nil
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
        m.message = message
        m.isOn = true
        m.record = rec
        if rec.reminder == nil { ctx.insert(m) }
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
