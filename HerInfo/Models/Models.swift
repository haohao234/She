//
//  Models.swift
//  她的信息本 · 数据模型层（SwiftData，iOS 17+）
//
//  字段与设计规范页「数据模型建议」逐条对应，示例值也取自原型里的真实数据。
//  每条字段后面都标了它对应哪一屏 —— 这是为了反过来检验：
//  如果一个字段没有任何一屏用到它，那它就不该存在。
//

import Foundation
import SwiftData

// MARK: - 记录

/// 对应 02 分类浏览 / 03 新增记录 / 07 历史版本 / 21 首条引导 / 31 记录详情 / 34 记录配图
@Model
final class Record {

    /// 稳定 id。用 String 而不是 UUID 是为了与导出（35 屏 JSON）里的 id 一致 ——
    /// 导出的文件将来被读回来时，靠它认得出同一条记录。
    @Attribute(.unique) var id: String

    /// 分类。**只有四个值** —— 多一个值就要多一套配色、多一段文案、多一条筛选项。
    var cat: Category

    var title: String
    var body: String

    /// 标签。展示在记录卡底部（02 屏）。
    var tags: [String]

    /// 图片。一条记录最多 9 张 —— 这个上限写在 UI 上（34 屏），也写在这里。
    @Relationship(deleteRule: .cascade, inverse: \Photo.record)
    var photos: [Photo] = []

    /// 提醒。一条记录最多挂一个 —— 挂两个的话，「这条记录在提醒我什么」就说不清了。
    @Relationship(deleteRule: .cascade, inverse: \Reminder.record)
    var reminder: Reminder?

    /// 版本号。每次自动保存 +1，对应 07 屏的历史版本与 31 屏的「第 12 版」。
    /// **版本号长在记录上，不是长在历史表里** —— 这样列表页不用 join 就能显示「第 N 版」。
    var version: Int

    /// 非 nil 即置顶。封顶 3 条（25 屏 / 30 屏的「已置顶」）。
    /// 用时间戳而不是 Bool：置顶顺序需要「最近置顶的在上」。
    var pinnedAt: Date?

    /// 软删除。非 nil 即进回收站（26 / 27 / 29 屏）。
    /// 30 天后由本地任务真删 —— 30 天是「想起来找」与「占地方」之间的经验值。
    var deletedAt: Date?

    var createdAt: Date
    var updatedAt: Date

    init(id: String = Record.newID(),
         cat: Category,
         title: String,
         body: String = "",
         tags: [String] = [],
         version: Int = 1,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.cat = cat
        self.title = title
        self.body = body
        self.tags = tags
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func newID() -> String { "r_" + UUID().uuidString.prefix(6).lowercased() }
}

// MARK: - 图片

/// 对应 34 记录配图
@Model
final class Photo {

    @Attribute(.unique) var id: String

    /// **只存 hash，不存路径、不存 URL。**
    /// 路径会随「重装 App / 换手机 / 系统清理沙盒」失效，hash 不会；
    /// 存 URL 则意味着图片在别人服务器上 —— 这个 App 的承诺是数据不出本机。
    /// 落地时对应 `FileManager` 沙盒内 `Photos/<hash>.jpg`。
    var hash: String

    /// 排序位。长按拖动排序改的就是它。
    var order: Int

    /// 拍摄/添加时间，用于导出时写 EXIF 补充信息（35 屏「包含图片」）。
    var addedAt: Date

    var record: Record?

    init(id: String = "p_" + UUID().uuidString.prefix(6).lowercased(),
         hash: String,
         order: Int,
         addedAt: Date = .now) {
        self.id = id
        self.hash = hash
        self.order = order
        self.addedAt = addedAt
    }

    /// 一条记录最多 9 张。到顶后 34 屏的添加格置灰 ——
    /// 不给「还能再加」的错觉，比加完再报错好。
    static let maxPerRecord = 9
}

// MARK: - 她的档案

/// 对应 01 首页名片 / 15 首次使用 / 17 详情 / 33 编辑
@Model
final class Profile {

    var name: String

    /// 在一起的日子。与 01 屏的「在一起 428 天」对得上 —— 天数由它算出来，不另存。
    var together: Date

    /// 生日。只存月日的话跨年算年龄会错，所以存完整日期，年份允许是占位值。
    var birthday: Date?

    var city: String

    /// 头像同样是 hash，理由见 Photo.hash。
    var avatarHash: String?

    /// 一句话。33 屏才收集 —— 第一次只问名字和纪念日，问太多人就退出去了。
    var about: String

    init(name: String,
         together: Date,
         birthday: Date? = nil,
         city: String = "",
         avatarHash: String? = nil,
         about: String = "") {
        self.name = name
        self.together = together
        self.birthday = birthday
        self.city = city
        self.avatarHash = avatarHash
        self.about = about
    }

    /// 「在一起 428 天」。算出来而不是存下来 —— 存下来的数字过一夜就是错的。
    var daysTogether: Int {
        Calendar.current.dateComponents([.day], from: together, to: .now).day ?? 0
    }
}

// MARK: - 提醒

/// 对应 05 提醒 / 32 新建提醒 / 14 锁屏通知
@Model
final class Reminder {

    @Attribute(.unique) var id: String

    /// **只有两种。** 定时（date）与场景（geo）不是「两种参数」，是两种心智模型：
    /// 前者「到点响」，后者「到地方响」。混成一个模型会让表单变成一堆可选字段。
    var kind: ReminderKind

    var title: String

    // —— 定时 ——
    /// 重复方式。none / daily / weekly / monthly
    var repeatRule: RepeatRule
    /// 星期几（weekly 时有效）。1 = 周日，与 Calendar 一致。
    var weekday: Int?
    /// 每月几号（monthly 时有效）。
    var dayOfMonth: Int?
    /// 触发时刻。只取时分，日期部分由 repeatRule 决定。
    var time: Date

    /// 提前多久（分钟）。**与 time 刻意分成两组** ——
    /// 「每周三 20:00」是事实，「提前 10 分钟」是你想要的余量。
    /// 混在一起用户就算不清到底几点响。
    var leadMinutes: Int

    // —— 场景 ——
    /// 地点名（「公司」「花店」）。**只绑少数高频点** ——
    /// iOS 单个 App 最多监听 20 个 CLCircularRegion，做成「想加多少加多少」一定崩。
    var placeName: String?
    /// 经度 / 纬度。存下来是为了不必每次反查地理编码（那是网络请求，且要配额）。
    var latitude: Double?
    var longitude: Double?
    /// 半径（米）。默认 300 —— 太小会因定位漂移反复触发，太大等于整条街都算。
    var radius: Double = 300

    /// 通知上那一行字。32 屏的「通知预览」就是它 ——
    /// 提醒的成败全在这行字上，所以它必须在设计里可见可改。
    var message: String

    var isOn: Bool

    var record: Record?

    init(id: String = "m_" + UUID().uuidString.prefix(6).lowercased(),
         kind: ReminderKind,
         title: String,
         repeatRule: RepeatRule = .none,
         weekday: Int? = nil,
         dayOfMonth: Int? = nil,
         time: Date = .now,
         leadMinutes: Int = 10,
         placeName: String? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         radius: Double = 300,
         message: String,
         isOn: Bool = true) {
        self.id = id
        self.kind = kind
        self.title = title
        self.repeatRule = repeatRule
        self.weekday = weekday
        self.dayOfMonth = dayOfMonth
        self.time = time
        self.leadMinutes = leadMinutes
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.message = message
        self.isOn = isOn
    }

    /// 通知正文（32 屏预览的那一行）。提前量与文案用 · 连起来 ——
    /// 这样用户看一眼就知道「这条通知会在什么时候、说什么」。
    var previewLine: String {
        leadMinutes == 0 ? message : "\(message) · 提前 \(leadLabel)"
    }

    var leadLabel: String {
        switch leadMinutes {
        case 0:          return "准时"
        case 10:         return "10 分钟"
        case 60:         return "1 小时"
        case 60 * 24:    return "1 天"
        default:         return "\(leadMinutes) 分钟"
        }
    }
}

enum ReminderKind: String, Codable, CaseIterable {
    case date, geo
    var title: String { self == .date ? "定时" : "场景" }
}

enum RepeatRule: String, Codable, CaseIterable {
    case none, daily, weekly, monthly
    var title: String {
        switch self {
        case .none:    return "仅一次"
        case .daily:   return "每天"
        case .weekly:  return "每周"
        case .monthly: return "每月"
        }
    }
}

// MARK: - 情绪打标

/// 对应 09 情绪打标 / 10 打标之后
@Model
final class Mood {

    @Attribute(.unique) var id: String

    var level: MoodLevel

    var at: Date

    /// **来源必须记。** iOS 沙盒不允许读第三方聊天记录，
    /// 所以这条数据的合法性完全取决于「是谁给的」：
    /// 手动 / 锁屏 / 快捷指令 / 分享扩展。留一个 .chat 值就等于把违规路径写进了模型。
    var source: MoodSource

    init(id: String = "d_" + UUID().uuidString.prefix(6).lowercased(),
         level: MoodLevel,
         at: Date = .now,
         source: MoodSource = .manual) {
        self.id = id
        self.level = level
        self.at = at
        self.source = source
    }
}

/// 五个情绪档。
///
/// **rawValue 与共享契约里的 `HINotify.Mood` 逐个对应。**
/// 那边是主 App 与通知扩展共用的（锁屏上那五个打标胶囊要用），
/// 这边是 SwiftData 的持久化枚举 —— 它搬不走，所以两边靠 rawValue 对齐，
/// 文案只在 `HINotify.Mood` 里写一遍，这里转过去取。
/// `check-swift.js` 会校验这五个 rawValue 是否一一对上。
enum MoodLevel: String, Codable, CaseIterable {
    case happy, tired, down, angry, calm

    /// 转到共享契约里的那一份。
    var hi: HINotify.Mood? { HINotify.Mood(rawValue: rawValue) }

    var title: String  { hi?.title ?? rawValue }
    /// 09 屏用图标；锁屏通知上的那五个胶囊只有文字（一行要塞五个）。
    var symbol: String { hi?.symbol ?? "circle" }

    /// **09 屏那三个能按的按钮。**
    ///
    /// 手动打标只给三档、锁屏通知给五档 —— 这是画布上的分法，不是遗漏：
    /// 手动那三个是「1 秒完成」的大按钮，多了就快不起来；
    /// 而锁屏通知那一行要塞下五个胶囊，位置决定它只能是五个。
    /// `angry` / `calm` 因此只从锁屏来，09 屏上不出现。
    static let boardCases: [MoodLevel] = [.happy, .tired, .down]

    /// 09 屏按钮上的说法。
    ///
    /// **它和上面的 `title` 不是同一份东西，别合并。** `title` 转发自共享契约，
    /// 那是**锁屏通知胶囊**上的文案（开心 / 累 / 低落 / 生气 / 平静）——
    /// 一行五个，字越短越好；而 09 屏是三个大按钮，说法更口语
    /// （挺好 / 有点累 / 心情差）。画布上这两处本来就是两套词，
    /// 合并成一个会让其中一处变得别扭。
    var boardTitle: String {
        switch self {
        case .happy: return "挺好"
        case .tired: return "有点累"
        case .down:  return "心情差"
        case .angry: return "生气"
        case .calm:  return "平静"
        }
    }
}

enum MoodSource: String, Codable {
    case manual        // 09 屏的快捷入口
    case lockscreen    // 14 屏通知上直接选
    case shortcut      // 快捷指令 / 锁屏小组件
    case shareSheet    // 分享扩展
    /// 长按 App 图标。
    ///
    /// **和 `.shortcut` 分成两个值，是有意的** —— 它们看起来都是「系统级入口」，
    /// 但一个是用户喊出来的、一个是手指按出来的，出问题时排查方向完全不同；
    /// 合成一个值就再也分不清了。加 case 不会影响已有数据
    /// （rawValue 是持久的，老记录的旧值照旧解得出来）。
    case quickAction
}

// MARK: - 历史版本

/// 对应 07 历史版本 · **恢复 = 新增一条，不覆盖** ——
/// 覆盖式恢复会让「我想看看昨天写的那版」变成一句空话。
@Model
final class Revision {

    @Attribute(.unique) var id: String

    var recordID: String
    var version: Int

    /// 快照。存整份正文而不是 diff —— 记录本来就是几十个字的东西，
    /// 存 diff 省下的空间远远抵不过「读一条历史要重放整条链」的复杂度。
    var titleSnapshot: String
    var bodySnapshot: String
    var photoHashes: [String]
    var catRaw: String

    var at: Date

    init(id: String = "v_" + UUID().uuidString.prefix(6).lowercased(),
         recordID: String,
         version: Int,
         titleSnapshot: String,
         bodySnapshot: String,
         photoHashes: [String] = [],
         catRaw: String = Category.like.rawValue,
         at: Date = .now) {
        self.id = id
        self.recordID = recordID
        self.version = version
        self.titleSnapshot = titleSnapshot
        self.bodySnapshot = bodySnapshot
        self.photoHashes = photoHashes
        self.catRaw = catRaw
        self.at = at
    }
}

// MARK: - 容器

/// 一次性把要入库的模型登记在这里。少写一个类型，运行时就是「找不到 model」的崩溃。
enum HerInfoStore {
    static let schema = Schema([
        Record.self,
        Photo.self,
        Profile.self,
        Reminder.self,
        Mood.self,
        Revision.self
    ])

    /// 应用用这个（落盘）。
    @MainActor
    static func container() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
    }

    /// 预览用这个（内存，不污染真机数据）。
    @MainActor
    static func previewContainer() throws -> ModelContainer {
        let c = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        seed(c.mainContext)
        return c
    }

    /// 演示用的种子数据。文案与画布 01/02 屏逐字一致。
    ///
    /// **只在两种情况下跑，都不面向真实用户：**
    /// 1. SwiftUI 预览（`previewContainer()` 调它，好在 Xcode 里看到有内容的界面）；
    /// 2. 命令行传 `-hi-seed` 启动（给截图 / 演示用）。
    ///
    /// 以前它是「首次启动的默认行为」—— 用户第一次打开 App 会看到
    /// 一个叫「小满」的档案和 4 条记录，而「她叫什么」一次都没被问过。
    /// 现在首次启动走 `OnboardingView`（画布 15/16 屏），这里不再自动调用。
    @MainActor
    static func seed(_ ctx: ModelContext) {
        ctx.insert(Profile(
            name: "小满",
            together: Calendar.current.date(byAdding: .day, value: -428, to: .now)!,
            birthday: Calendar.current.date(from: DateComponents(year: 2000, month: 3, day: 14)),
            city: "杭州",
            about: "话不多，但什么事都记得。"
        ))

        let r1 = Record(cat: .like, title: "白玫瑰与满天星",
                        body: "她说想要一束白玫瑰，不要红玫瑰。满天星是加分项，但不要太多，会显得乱。",
                        tags: ["礼物", "已挂提醒"], version: 12)
        r1.pinnedAt = .now
        ctx.insert(r1)

        ctx.insert(Record(cat: .trait_, title: "笑起来右边有个酒窝",
                          body: "不常笑，但笑起来右边有个酒窝，眼睛会眯成一条线。",
                          tags: ["外貌"], version: 2))
        ctx.insert(Record(cat: .care, title: "换季会过敏",
                          body: "三月和九月容易过敏，家里常备氯雷他定。",
                          tags: ["身体"], version: 3))
        ctx.insert(Record(cat: .hate, title: "香水味太重",
                          body: "讨厌香水味太重的人，坐电梯遇到会屏住呼吸。",
                          tags: ["气味"], version: 1))

        let m = Reminder(kind: .date, title: "你们的纪念日",
                         repeatRule: .monthly, dayOfMonth: 10,
                         time: Calendar.current.date(from: DateComponents(hour: 20, minute: 30))!,
                         leadMinutes: 10,
                         message: "该给她买白玫瑰了")
        m.record = r1
        ctx.insert(m)

        try? ctx.save()
    }

    // MARK: - 来自锁屏通知的两件事

    /// 把通知扩展丢进收件箱的打标，落成真正的 `Mood` 行。
    ///
    /// **在 App 启动与每次回到前台时各调一次。**
    /// 扩展是独立进程，它只能把打标丢进共享收件箱；
    /// 「什么时候变成数据」由主 App 说了算 —— 这条边界一旦模糊，
    /// 就会出现两个进程同时写一个库的情况。
    ///
    /// 来源一律记 `.lockscreen`：`MoodSource` 存在的意义就是「这条数据是谁给的」，
    /// 写错了等于把不存在的采集路径写进了数据里。
    @MainActor
    static func drainMoodInbox(into ctx: ModelContext) {
        let marks = HINotify.Inbox.drain()
        guard !marks.isEmpty else { return }
        for m in marks {
            guard let level = MoodLevel(rawValue: m.level) else { continue }
            ctx.insert(Mood(level: level, at: m.at, source: .lockscreen))
        }
        try? ctx.save()
    }

    // MARK: 快捷入口的打标（长按图标 / 快捷指令）

    /// 这两个入口**都可能在没有 `ModelContext` 的地方被触发**：
    /// 快捷指令可以在 App 压根没起来时跑，长按图标是 App 刚被唤起的那一瞬。
    /// 所以它们只负责「把意图记下来」，落库统一交给 `drainQuickMood` ——
    /// 这和通知扩展那条单向收件箱是**同一个模式**，只是这一个不跨进程，
    /// 用普通 `UserDefaults` 就够，不需要 App Group。
    ///
    /// 好处不只是省事：三个入口（锁屏 / 快捷指令 / 长按图标）因此不会各写一套
    /// 写库逻辑，`MoodSource` 也就不会有人在某一路上记错。
    private static let quickMoodKey = "hi.mood.pending"

    /// 记下一个待落库的打标。
    ///
    /// **带一道 2 秒去重护栏。** 从长按菜单冷启动 App 时，系统可能既把那一项放进
    /// `launchOptions`、又回调一次 `performActionFor`；两个回调都接的话就会记两条。
    /// 而打标是用户自己给的信号，**多一条就是伪造**。
    /// 去重比「只接其中一个回调」稳：后者要赌系统的行为，前者不用赌。
    static func notePendingMood(_ level: MoodLevel, source: MoodSource) {
        var list = (UserDefaults.standard.array(forKey: quickMoodKey) as? [[String: Any]]) ?? []
        let now = Date.now.timeIntervalSince1970

        if let last = list.last,
           (last["level"] as? String) == level.rawValue,
           (last["source"] as? String) == source.rawValue,
           let t = last["at"] as? TimeInterval,
           now - t < 2 {
            return
        }

        list.append(["level": level.rawValue,
                     "source": source.rawValue,
                     "at": now])
        UserDefaults.standard.set(list, forKey: quickMoodKey)
    }

    /// 落库。**先取走再落库** —— 与 `HINotify.Inbox.drain` 同一条纪律：
    /// 取走之后才写库，中间被打断也不该重复落两次，
    /// 而「宁可少一条也别多一条」是因为打标是用户自己给的信号，多一条就是伪造。
    static func drainQuickMood(into ctx: ModelContext) {
        let raw = (UserDefaults.standard.array(forKey: quickMoodKey) as? [[String: Any]]) ?? []
        guard !raw.isEmpty else { return }
        UserDefaults.standard.set([[String: Any]](), forKey: quickMoodKey)

        for item in raw {
            guard let lv = item["level"] as? String,
                  let level = MoodLevel(rawValue: lv) else { continue }
            let src = (item["source"] as? String).flatMap(MoodSource.init(rawValue:)) ?? .shortcut
            let at: Date
            if let t = item["at"] as? TimeInterval {
                at = Date(timeIntervalSince1970: t)
            } else {
                at = .now
            }
            ctx.insert(Mood(level: level, at: at, source: src))
        }
        try? ctx.save()
    }

    // MARK: 分享扩展送进来的记录

    /// 把分享扩展丢进收件箱的内容落成真正的 `Record`。
    ///
    /// 与 `drainMoodInbox` 是**同一条纪律**：先取走再落库，且只在这里写库 ——
    /// 扩展是独立进程，两边同时开一个 SwiftData 库会有写冲突，
    /// 而扩展被系统回收的时机完全不可控。
    ///
    /// 返回真正落下的条数，好让界面能说一句「已存下 N 条」——
    /// **说真实条数**：分类 rawValue 万一认不出（`Cat` 与 `Category` 脱节，
    /// 由 `check-swift.js` 防着），那一条会被跳过，提示里就不该把它算进去。
    ///
    /// **不做去重**：同一段话被分享两次，那就是用户分享了两次。
    /// 替他合并会把「我刚才存的那条呢」变成一个说不清的问题 ——
    /// 这与打标那条「宁可少一条也别多一条」不冲突：
    /// 那里多一条是**伪造**（用户没打过的标），这里多一条是**照做**。
    @MainActor
    @discardableResult
    static func drainShareInbox(into ctx: ModelContext) -> Int {
        let items = HIShare.Inbox.drain()
        guard !items.isEmpty else { return 0 }

        var saved = 0
        for item in items {
            guard let cat = Category(rawValue: item.cat) else { continue }
            ctx.insert(Record(cat: cat,
                              title: item.title,
                              body: item.body,
                              createdAt: item.at,
                              updatedAt: item.at))
            saved += 1
        }
        if saved > 0 { try? ctx.save() }
        return saved
    }

    /// 长按菜单那几项的 type 前缀。
    ///
    /// **Info.plist 里的字符串必须与它一致，而两边对不上时系统不报任何错** ——
    /// 菜单照样显示，点下去也只是没人处理。所以这里写成常量，
    /// 让 Info.plist 的注释里有处可引，两边不至于各写各的。
    static let quickActionPrefix = "hi.mood."

    /// 解析长按菜单里被点中的那一项（`hi.mood.down` → `.down`）。
    /// 返回是否认得它 —— 不认得要如实回 false，让系统知道这次没被处理。
    @discardableResult
    static func acceptQuickAction(_ type: String) -> Bool {
        guard type.hasPrefix(quickActionPrefix) else { return false }
        guard let level = MoodLevel(rawValue: String(type.dropFirst(quickActionPrefix.count))) else {
            return false
        }
        notePendingMood(level, source: .quickAction)
        return true
    }

    /// 通知上的「今天不用了」。
    ///
    /// **只关掉这一条提醒的开关，不删记录、不删提醒。**
    /// 用户的动作是「今天别提醒我」，不是「这件事不重要了」——
    /// 把两者混起来，第二天他会发现那条记录也没了。
    @MainActor
    static func markReminderDone(reminderID: String, in ctx: ModelContext) {
        let d = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == reminderID })
        guard let m = try? ctx.fetch(d).first else { return }
        m.isOn = false
        try? ctx.save()
    }

    // MARK: 回收站

    /// 把一条记录移进回收站。
    ///
    /// **软删除 + 必须 `save()`。** 少了保存这一步，删除只活在内存里，
    /// 重启一次记录就回来了 —— 而用户只会以为是自己记错了。
    ///
    /// 顺带把挂着的提醒一起停掉：26 屏那句后果说明（「挂着的提醒会一起取消」）
    /// 是必须兑现的，否则删掉的记录还会照常在晚上响，而用户已经找不到它、
    /// 也就不知道自己该去关什么。
    ///
    /// 反过来，**恢复时不把提醒打开** —— 恢复的是内容，不是当初设下的那个动作（27 屏）。
    @MainActor
    static func moveToTrash(_ record: Record, in ctx: ModelContext) {
        record.deletedAt = .now
        if let m = record.reminder, m.isOn {
            m.isOn = false
            Task { await ReminderService.shared.cancel(m) }
        }
        try? ctx.save()
    }

    @MainActor
    static func restoreFromTrash(_ record: Record, in ctx: ModelContext) {
        record.deletedAt = nil
        try? ctx.save()
    }

    /// 回收站的 30 天到期清理，返回真正删掉的条数。
    ///
    /// **这是在兑现 27 屏印在屏幕上的那句话**：「30 天后自动清掉，清掉就找不回来了」。
    /// 少了这一步，那句话就是假的，而且回收站会一直长大 ——
    /// 一个永不清理的回收站，在用户眼里等于「你其实没删掉任何东西」。
    ///
    /// 必须在 `PhotoStore.purgeOrphans` **之前**跑：先让记录真的消失，
    /// 它引用的图片才会在同一次启动里被扫成孤儿一起清掉。
    @MainActor
    @discardableResult
    static func cleanupExpiredTrash(in ctx: ModelContext) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let d = FetchDescriptor<Record>(predicate: #Predicate { $0.deletedAt != nil })
        guard let dead = try? ctx.fetch(d) else { return 0 }
        var removed = 0
        for r in dead {
            guard let at = r.deletedAt, at < cutoff else { continue }
            ctx.delete(r)
            removed += 1
        }
        if removed > 0 { try? ctx.save() }
        return removed
    }
}

extension Record {
    /// 还开着的提醒条数。一条记录最多挂一个提醒，所以只会是 0 或 1 ——
    /// 26 屏靠它决定要不要显示「提醒会一起取消」那条后果。
    var liveReminderCount: Int { reminder?.isOn == true ? 1 : 0 }

    /// 26 屏确认面板上那行小字：「喜好 · 3月14日记下 · 挂着 1 个提醒」。
    /// **它存在的唯一意义，是让用户在按下「删掉」之前再看一眼自己删的是什么。**
    var trashMeta: String {
        var parts = [cat.title, "\(createdAt.monthDayCN)记下"]
        if liveReminderCount > 0 { parts.append("挂着 \(liveReminderCount) 个提醒") }
        return parts.joined(separator: " · ")
    }
}
