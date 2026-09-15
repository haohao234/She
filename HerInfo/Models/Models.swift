//
//  Models.swift
//  我的宝宝江林桐 · 数据模型层（SwiftData，iOS 17+）
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

    /// **配图的真相。** 顺序 = 用户在编辑器里一张张拖出来的顺序；
    /// 元素是 `PhotoStore` 沙盒里 `Photos/<hash>.jpg` 的 hash。
    ///
    /// **为什么把它从关系搬到标量。** 三份真机崩溃日志（10:25 / 11:10 / 11:49）
    /// 的 trap 地址**逐字节相同**（`SwiftData + 0x9e77c`），而三次的调用方
    /// 各不相同：两次在 `RecordEditorView.save` 里读 `target.photos`，
    /// 一次在 `ReminderService.photoIndex` 里读 `Photo.hash`。三次的共同点只有
    /// 一个 —— **都在读 `Photo` 这个模型对象**。上一轮把读取从「关系数组」
    /// 换成「`Photo` 全表 fetch」，看着换了条路，其实还是同一个动作，所以照崩。
    ///
    /// 结论：**只要读取经过 `Photo`，就有崩的余地；换路径没用，只能不读。**
    /// 而这件事本来就没有必要经过它 —— `Revision.photoHashes` 从第一天起
    /// 就是标量数组，历史版本能这么存，当前状态当然也能。
    ///
    /// 搬过来之后，读配图变成读一个 `[String]`：列表卡片的「📷 N」、
    /// 详情页的九宫格、编辑页打开与保存、历史版本恢复、导出、通知附件、
    /// 启动时的孤儿图片统计 —— 全都是纯内存操作，一条崩路径都不剩。
    ///
    /// `Photo` 表因此退成**只读的历史数据**：只用于老库的一次性回填
    /// （见 `HerInfoStore.backfillPhotoHashes`），不再写、不再读。
    ///
    /// **2026-09-15 续：`photos` 这个关系本身也删了**（`Photo.record` 一并删）。
    /// 上一版留了它，理由是「删关系要冒一次迁移风险」—— 那个理由不成立：
    /// 这一版**本来就要跑一次迁移**（就是新增上面这个 `photoHashes`），
    /// 同一次迁移里多删两个关系，风险与只加一个属性相同。
    ///
    /// 而留着它的代价是实的：**`ctx.delete(record)` 会按 `deleteRule: .cascade`
    /// 去解析 `photos`、把 `Photo` 行 fault 出来删** —— 于是「删掉一条挂着配图的
    /// 老记录」（回收站 30 天清理 / 撤销刚建的那条 / 用户手动清空）仍要
    /// materialize `Photo`，仍可能崩在同一个 trap 上。
    /// **业务代码不读它了，框架内部还在读。** 删掉关系，这条路才真的断。
    var photoHashes: [String] = []

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

    /// **12 位十六进制，不是 6 位。** 2026-09-14 从 `prefix(6)` 提上来的。
    ///
    /// 这个 id 是 `@Attribute(.unique)` 的键，六个模型都用同一招生成
    /// （`r_` 记录 / `p_` 图片 / `m_` 提醒 / `d_` 心情 / `c_` 周期 / `v_` 版本）。
    /// 原来取 `UUID().uuidString.prefix(6)` = `16^6` ≈ 1677 万个可能值，
    /// 也就是 **24 bit 熵** —— 对一张会长期增长的表，这个空间小得危险：
    ///
    ///     表里行数    300     1000     2000     3000     5000
    ///     至少撞一次  0.27%    2.9%    11.2%    23.5%    52.5%
    ///
    /// 而全项目 14 处 `ctx.save()` 都是 `try? ctx.save()` **一个字都不报**，
    /// 真撞上只会静默丢数据或改错行。最容易撞的是 `Revision`
    /// —— 它每次编辑 +1 就插一行，是这几张表里长得最快的。
    ///
    /// 12 位 = `16^12` ≈ 48 bit：一万行撞一次的概率是 1.8e-5 %。
    /// **改长不改短、不改前缀，也不需要迁移** —— 老的 6 位 id 仍是合法的
    /// 字符串主键，与新 id 共存没有任何问题（它们本来就只是不重复的字符串）。
    /// 唯一的可见影响是导出的 JSON 里 id 变长，设计规范里的示例已同步成 12 位。
    static func newID() -> String { "r_" + UUID().uuidString.prefix(12).lowercased() }
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

    // ⚠️ **这里原来有一个 `var record: Record?`，与 `Record.photos` 互为反向。
    // 2026-09-15 一并删了。** 只删 `Record.photos` 是不够的：只要反向关系还在，
    // `ctx.delete(record)` 时 SwiftData 仍要维护它（把 `Photo.record` 置空），
    // 照样得把 `Photo` 对象 fault 出来。
    // 所以 `Photo` 行现在**不再知道自己属于哪条记录** —— 配图的归属以
    // `Record.photoHashes` 为准（它才是真相，见那里的说明）。

    // id 取 12 位，理由见 `Record.newID()`（6 位 = 24 bit，会撞唯一约束且撞了不报错）。
    init(id: String = "p_" + UUID().uuidString.prefix(12).lowercased(),
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

    /// 按顺序去重。**读出来显示之前必须过一遍。**
    ///
    /// `PhotoGrid` 用 hash 当 `ForEach` 的 id（内容寻址天然唯一，所以当时
    /// 直接写了 `id: \.self`）。这条假设在**写入侧**是成立的：`ingest` 有
    /// `!photoHashes.contains(hash)` 那道去重，`save` 也是先
    /// `first(where:)` 找到了就复用、不会插第二条。
    ///
    /// 但「恢复历史版本」那条路是照 `Revision.photoHashes` 整份重放的，
    /// 一旦某个快照和当前记录撞上同一张图，同一条记录里就会出现两行同 hash 的
    /// `Photo`。**说清后果，不夸张**：
    ///   · SwiftUI 在 id 重复时不保证行为 —— 运行时会打
    ///     「the ID … occurs multiple times within the collection, this will give
    ///     undefined results」这句警告，**它不承诺崩，但也不承诺不崩**；
    ///   · **真正一定会错的是拖动排序**：`PhotoDropDelegate` 靠
    ///     `hashes.firstIndex(of:)` 定位，重复值下永远命中第一个 ——
    ///     拖的是第二张，动的是第一张。
    ///
    /// 所以去重放在「读」这一侧：写入侧那两道是优化，这里才是保证。
    static func uniqueHashes(_ hashes: [String]) -> [String] {
        var seen = Set<String>()
        return hashes.filter { seen.insert($0).inserted }
    }
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

    // id 取 12 位，理由见 `Record.newID()`。
    init(id: String = "m_" + UUID().uuidString.prefix(12).lowercased(),
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

    // id 取 12 位，理由见 `Record.newID()`。
    init(id: String = "d_" + UUID().uuidString.prefix(12).lowercased(),
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

// MARK: - 生理期

/// 对应 37 生理期首页 / 38 记录经期 / 39 周期记录 / 40 经期提醒 / 41 空态。
///
/// **一条记录 = 一次经期**（开始日 + 持续几天），不是「一天一条」。
/// 这是这一块最要紧的选择：记的是「这次」，不是「今天她来了」。
/// 按天存的话，用户要么每天来点一次、要么我们就得猜她哪天结束；
/// 按「一次」存，只需要她记开始那天 —— 剩下的是算出来的。
@Model
final class CyclePeriod {

    @Attribute(.unique) var id: String

    /// 这次经期的**第一天**。整个模型只围绕这一个日子展开。
    var startedAt: Date

    /// 持续几天。38 屏给的是 3~7 的快捷胶囊。
    ///
    /// **默认 5 天，但这不是医学默认值** —— 它是「不确定就先按 5 天算」。
    /// 所以这个字段允许是一个「用户没明说」的值，界面上不能假装她填过。
    var durationDays: Int

    /// 是不是用户手动填的。
    /// 目前只有手动一种，留下它是为了将来「按规律自动补一条」时，
    /// 界面上能区分「她真的来了」和「我们猜她来了」——
    /// **这两件事在界面上的分量完全不同，不能长得一样。**
    var isManual: Bool

    var createdAt: Date

    // id 取 12 位，理由见 `Record.newID()`。
    init(id: String = "c_" + UUID().uuidString.prefix(12).lowercased(),
         startedAt: Date,
         durationDays: Int = 5,
         isManual: Bool = true,
         createdAt: Date = .now) {
        self.id = id
        self.startedAt = startedAt
        self.durationDays = durationDays
        self.isManual = isManual
        self.createdAt = createdAt
    }
}

// MARK: - 生理期统计

/// 从一串 `CyclePeriod` 里算出来的全部派生量。
///
/// **一个都不落库。** 这样「改了一次开始日」之后，首页 / 趋势 / 提醒三处
/// 不可能各自显示不同的数字 —— 它们读的是同一个入参。
/// 理由与 31 屏的「不存快照」同源：多存一份就是第二份真相。
///
/// **内部存的是值、不是 `CyclePeriod` 对象**（`Entry`）。有两个原因：
///  ① 38 屏要预览「还没保存的这一次」，而那是**不该被插进数据库**的一条。
///     早先的写法是造一个 `CyclePeriod(id:"preview", …)` 塞进数组 ——
///     但 `@Model` 的对象是持久化对象，随手 new 一个又不用，
///     轻则每次重算都造一个（`previewStats` 是计算属性，每帧都跑），
///     重则被 SwiftData 判成「已创建未插入」而报错。
///  ② 统计本身只需要 `开始日 + 天数 + id` 三样东西，
///     拿着整个持久化对象是**用不着的耦合**。
struct CycleStats {

    /// 参与统计的一次经期 —— 只是三个值，不是数据库里的那一行。
    struct Entry {
        let id: String
        let startedAt: Date
        let durationDays: Int
    }

    /// 推算用的周期长度。**28 天是社会常识值、不是医学判断** ——
    /// 40 屏页脚那句「不是医学判断」说的就是这件事。
    /// 一旦有 ≥2 次记录，就用实际平均覆盖它。
    static let defaultCycle = 28

    /// 38 屏给的是 3~7 天。
    static let durationRange = 3...7

    /// 已按开始日从新到旧排好。
    let periods: [Entry]

    init(periods: [Entry]) {
        self.periods = periods.sorted { $0.startedAt > $1.startedAt }
    }

    /// 从落库的那些记录建一份。
    init(models: [CyclePeriod]) {
        self.init(periods: models.map {
            Entry(id: $0.id, startedAt: $0.startedAt, durationDays: $0.durationDays)
        })
    }

    /// 38 屏用：在落库记录之外，再追加一条「还没保存的这次」。
    /// **不造 `CyclePeriod` 对象**，所以不会碰到 SwiftData 的那条线。
    func adding(id: String, startedAt: Date, durationDays: Int) -> CycleStats {
        CycleStats(periods: periods + [Entry(id: id,
                                             startedAt: startedAt,
                                             durationDays: durationDays)])
    }

    /// 38 屏改一条时用：先把原记录摘掉，再加进新的值。
    func replacing(id: String, startedAt: Date, durationDays: Int) -> CycleStats {
        adding(id: id, startedAt: startedAt, durationDays: durationDays)
            .removing(id: id, keepNewest: true)
    }

    /// 去掉某个 id（`keepNewest` = 同 id 只去掉最早出现的那一条）。
    private func removing(id: String, keepNewest: Bool) -> CycleStats {
        var seen = false
        var out: [Entry] = []
        for e in periods {
            if e.id == id && !(keepNewest && seen) {
                seen = true
                continue
            }
            out.append(e)
        }
        return CycleStats(periods: out)
    }

    var isEmpty: Bool { periods.isEmpty }
    var latest: Entry? { periods.first }

    /// 平均周期天数。**不足两次时退回 28** —— 一次记录算不出周期，这是数学事实。
    var averageCycle: Int {
        let gaps = validGaps
        guard !gaps.isEmpty else { return Self.defaultCycle }
        return Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
    }

    /// 波动 ±N 天。**不足两次时为 nil** —— 界面据此不显示，而不是显示 ±0 天。
    var wobble: Int? {
        let gaps = validGaps
        guard let mx = gaps.max(), let mn = gaps.min() else { return nil }
        return max(0, (mx - mn) / 2)
    }

    /// 相邻两次之间的间隔。
    ///
    /// **明显不合理的间隔（<15 天或 >60 天）不参与统计** ——
    /// 一次误记（比如同一次经期被记了两遍）会把平均值与稳定性彻底带歪，
    /// 而屏幕上「28 天」变成「16 天」时，用户不会想到是自己那条误记。
    /// 宁可退回常识值，也不要一个被污染的数字。
    private var validGaps: [Int] {
        guard periods.count >= 2 else { return [] }
        return (0..<(periods.count - 1))
            .map { days(from: periods[$0 + 1].startedAt, to: periods[$0].startedAt) }
            .filter { $0 >= 15 && $0 <= 60 }
    }

    var nextStart: Date? {
        guard let last = latest else { return nil }
        return Calendar.current.date(byAdding: .day, value: averageCycle, to: last.startedAt)
    }

    /// 今天是不是落在某一次经期里。
    func currentPeriod(on today: Date = .now) -> Entry? {
        periods.first { p in
            let d = days(from: p.startedAt, to: today)
            return d >= 0 && d < p.durationDays
        }
    }

    /// 「经期第 N 天」。不在经期中时为 nil。
    func currentDay(on today: Date = .now) -> Int? {
        guard let p = currentPeriod(on: today) else { return nil }
        return days(from: p.startedAt, to: today) + 1
    }

    /// 还有几天结束。**环心说「4 天后结束」而不是「已经第 3 天」** ——
    /// 前者回答的是「还要难受几天」，比后者有用。
    func daysUntilEnd(on today: Date = .now) -> Int? {
        guard let p = currentPeriod(on: today) else { return nil }
        return p.durationDays - days(from: p.startedAt, to: today)
    }

    /// 距离下次经期还有几天。**负值有意义** —— 表示已经过了预测日还没记，
    /// 界面应当据此说「比预计晚了 N 天」而不是把数字吞掉。
    func daysUntilNext(on today: Date = .now) -> Int? {
        guard let n = nextStart else { return nil }
        return days(from: today, to: n)
    }

    /// 39 屏那 6 根柱子。
    var recentSix: [Entry] { Array(periods.prefix(6)) }

    /// 「很规律」的判据。**给说法不给分数** —— 界面上只有「很规律 / 有点波动」
    /// 两种说法，没有百分制。做一个精确到小数点的「规律指数」，
    /// 等于让用户在身体本来就会波动的事上追求一个不该追求的数字。
    var isRegular: Bool {
        guard periods.count >= 3, let w = wobble else { return false }
        return w <= 3
    }

    /// 两次相隔几天。**必须归零时分再比** —— 否则「今天 09:00 → 明天 01:00」
    /// 与「今天 09:00 → 今天 20:00」都是同一天的事，却会算出 1 和 0 两个答案。
    func days(from: Date, to: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: from),
                                  to: cal.startOfDay(for: to)).day ?? 0
    }
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

    // id 取 12 位，理由见 `Record.newID()`。
    // **这个模型最该改**：每次编辑 +1 就插一行，是六张表里长得最快的。
    init(id: String = "v_" + UUID().uuidString.prefix(12).lowercased(),
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
        // `Photo` 留在 schema 里，**不是因为有谁在用**（两个关系已删、代码一行都不读），
        // 而是因为：把它移出 schema 等于让 SwiftData **删掉整张表** ——
        // 那是比「留一张没人读的表」重得多的迁移动作。
        // 留着它，老库那批行就在原处放着，既不影响打开，也留了一线恢复的余地。
        Photo.self,
        Profile.self,
        Reminder.self,
        Mood.self,
        Revision.self,
        // 生理期（37~41 屏）。**新模型必须登记在这里** ——
        // 少写一个类型，运行时就是「找不到 model」的崩溃，编译期一声不吭。
        CyclePeriod.self
    ])

    /// 应用用这个（落盘）。
    @MainActor
    static func container() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: false)
        )
    }

    /// 「数据库打不开、已经挪到一边并新建了一份」的时间戳。
    ///
    /// 由下面的 `containerAfterSettingAsideBrokenStore` 写，
    /// `HerInfoApp` 启动时读它 —— 见到就弹一句实话（见 `announceStoreResetIfAny`）。
    /// 用 `UserDefaults` 而不是文件：它只在**挪库成功之后**写，
    /// 不在崩溃路径上，不需要 `.atomic` 那种强度。
    static let storeResetKey = "hi.store.setAsideAt"

    /// 容器打不开时的最后一道：**把现有库文件整份挪到一边，再新建一份空的**。
    ///
    /// 原来 `HerInfoApp` 在 `container()` 抛错时直接 `fatalError` —— 想法是对的
    /// （不要静默退回内存库，那会让用户以为数据存下来了），但代价是**永久打不开**：
    /// 用户每次点图标都在同一个地方崩，连「是不是该重装」都无从判断。
    ///
    /// 挪走而不是删掉：`default.store` 连同 `-shm` / `-wal` 整份搬到
    /// `Application Support/broken-<时间戳>/`，数据还在盘上（重装之前拿得回来），
    /// App 当场能用；而且这件事**会如实告诉他**（见 `storeResetKey`），
    /// 不是静默换一个空库。
    ///
    /// 返回 nil = 连新建都失败（磁盘满 / 沙盒异常）—— 那种情况崩是诚实的。
    @MainActor
    static func containerAfterSettingAsideBrokenStore() -> ModelContainer? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory,
                                    in: .userDomainMask).first else { return nil }

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let aside = support.appendingPathComponent("broken-\(stamp)", isDirectory: true)
        try? fm.createDirectory(at: aside, withIntermediateDirectories: true)

        // SwiftData 的默认库是这三个文件一组，**必须一起搬** ——
        // 只搬 .store 而留下 -wal，新库会读到旧的未提交事务。
        for suffix in ["default.store", "default.store-shm", "default.store-wal"] {
            let src = support.appendingPathComponent(suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.moveItem(at: src, to: aside.appendingPathComponent(suffix))
        }

        guard let fresh = try? container() else { return nil }
        UserDefaults.standard.set(stamp, forKey: storeResetKey)
        return fresh
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

    // MARK: - 老库的配图搬进标量（一次性）

    /// 「配图搬家」这件事做过了没有。见下面的 `backfillPhotoHashes`。
    static let photoBackfillKey = "hi.backfill.photoHashes.v1"

    /// 把老库里存在 `Photo` 关系上的配图，按最新一版历史快照搬进 `Record.photoHashes`。
    ///
    /// **为什么必须有这一步。** `Record.photoHashes` 是 2026-09-15 新增的标量属性，
    /// 老库里每一条记录的这个字段都是空的。不回填的话，用户升级上来看到的
    /// 是一份**没有配图的档案** —— 图片文件都还在沙盒里，只是没人知道它们属于谁。
    ///
    /// **回填来源为什么是 `Revision.photoHashes`，而不是 `Photo` 关系。**
    /// `Revision.photoHashes` 是标量数组，读它完全不碰 `Photo` 对象；
    /// 而 `Photo` 对象正是三份崩溃日志（10:25 / 11:10 / 11:49）的共同点 ——
    /// 见 `Record.photoHashes` 的说明。`Photo` 关系那条路**就是崩点本身**，
    /// 拿它来回填等于把崩溃搬到启动流程的最前面。
    ///
    /// 精度上够用：每次内容变化都会 `save(bump:)` 插一条带 `photoHashes` 的
    /// `Revision`（编辑器里加图、删图、换序都算内容变化），所以
    /// 「版本号最大的那条快照」就是「最后一次保存时的配图」。
    ///
    /// **只做一次。** 做成每次都跑的话，用户主动清空一条记录的全部配图之后，
    /// 下次启动会被它原样加回来 —— 那是个比「看不到图」更糟的 bug：
    /// 用户删掉的东西自己回来了。
    ///
    /// 返回真正填了几条记录。
    @MainActor
    @discardableResult
    static func backfillPhotoHashes(in ctx: ModelContext) -> Int {
        let d = UserDefaults.standard
        if d.bool(forKey: photoBackfillKey) { return 0 }

        let records = (try? ctx.fetch(FetchDescriptor<Record>())) ?? []
        guard !records.isEmpty else {
            // 空库（新用户 / 刚挪库重建过）没什么可搬的，直接收工。
            d.set(true, forKey: photoBackfillKey)
            return 0
        }
        let revisions = (try? ctx.fetch(FetchDescriptor<Revision>())) ?? []

        // 每条记录取版本号最大的那条快照。用显式比较而不是 `max(by:)`，
        // 因为这里要的是「版本号最大」这个全序，不是「任意一个更大的」。
        var newest: [String: Revision] = [:]
        for v in revisions {
            if let cur = newest[v.recordID], cur.version >= v.version { continue }
            newest[v.recordID] = v
        }

        var filled = 0
        for r in records where r.photoHashes.isEmpty {
            guard let v = newest[r.id], !v.photoHashes.isEmpty else { continue }
            r.photoHashes = Photo.uniqueHashes(v.photoHashes)
            filled += 1
        }
        if filled > 0 { try? ctx.save() }
        // **标记写在保存之后。** 反过来的话，保存失败也会被记成「搬完了」，
        // 而那批配图就再也回不来了。
        d.set(true, forKey: photoBackfillKey)
        return filled
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

    // MARK: 撤销「刚记下的那一条」

    /// 把「刚建出来、又被撤销掉」的那条记录**真删掉**。
    ///
    /// **它跟 `moveToTrash` 不是一件事，别混。**
    ///   · `moveToTrash` 撤的是「我删掉了一条记过的记录」—— 有内容、有价值，
    ///     所以要留 30 天的退路；
    ///   · 这里撤的是「它根本不该存在」—— 用户手一滑点中「完成」，
    ///     立刻又按了撤销。把它塞进回收站是错的：27 屏会因此多出一条
    ///     「📷 1、没标题」的残骸，而用户以为自己撤销之后什么都没留下。
    ///
    /// 所以这里删干净：版本行、记录本身（提醒行由 `Record` 上的级联删除带走，
    /// 不重复删）。
    ///
    /// **图片行不再被带走了**（2026-09-15 删了 `photos` 关系）：老库里那些
    /// `Photo` 行会留在原处。它们没人读、也不占内存，图片文件由
    /// `PhotoStore.purgeOrphans` 按引用全集清 —— 所以不需要为它们额外做什么。
    ///
    /// **图片文件不在这里删** —— 沿用这个 App 一贯的分工：文件只由
    /// `PhotoStore.purgeOrphans` 在下次启动时按「引用全集」统一清。
    /// 好处之一是撤销之后立刻重选同一张图，hash 不变、文件还在，直接复用。
    ///
    /// 提醒必须先撤通知：提醒行会被级联删掉，但**系统里已经排好的那条通知
    /// 不会自己消失** —— 不撤的话，用户撤销掉的记录照样会在晚上响一次，
    /// 而他再也找不到它、不知道该去关什么。
    @MainActor
    static func discardDraft(_ record: Record, in ctx: ModelContext) {
        // 先把 id 取出来。删完再碰这个模型对象，就可能触到失效对象（见 `cancel(reminderID:)`）。
        let reminderID = record.reminder?.isOn == true ? record.reminder?.id : nil
        if let rid = reminderID {
            Task { await ReminderService.shared.cancel(reminderID: rid) }
        }

        // 版本行得按 id 自己捞：`Revision` 不是关系属性，它只存了一个 `recordID`。
        // 新建那一次 `save(bump: true)` 已经插了一条，不删就会在 07 屏留下一行
        // 指向一条不存在的记录的孤魂。
        let key = record.id
        let d = FetchDescriptor<Revision>(predicate: #Predicate { $0.recordID == key })
        if let revs = try? ctx.fetch(d) {
            for v in revs { ctx.delete(v) }
        }

        ctx.delete(record)
        try? ctx.save()
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
