//
//  NotificationContract.swift
//  主 App ↔ 通知内容扩展（NC Extension）之间的唯一契约
//
//  【为什么单独有这个文件】
//  通知内容扩展是**独立进程**：它有自己的入口、自己的生命周期，看不到主 App 的内存。
//  两边都要用到的每一个字符串（分类 id、动作 id、userInfo 的键、App Group 名）
//  必须只写一遍 —— 写两遍就一定会分叉，而分叉的表现是
//  「通知照常弹，但长按展开后是系统默认样子」：不报错、不崩溃，只是白做。
//
//  【怎么加进工程（重要）】
//  这个文件要同时属于**两个 target** 的 Compile Sources：
//      HerInfo（主 App） ＋ HerInfoNotification（扩展）
//  所以它只依赖 Foundation 与 UserNotifications。
//  **绝不 import SwiftData、绝不引用 Models.swift 里的类型** ——
//  那些是主 App 的数据模型，扩展没有理由把它们链进来（多一份类型、多一份崩溃面）。
//  需要跨进程传的值，在这里一律降级成 String / Int 这类纯数据。
//

import Foundation
import UserNotifications

// MARK: - 契约

enum HINotify {

    /// 共享容器。扩展是独立进程，收件箱只能放在这里。
    ///
    /// **为什么图片不走共享容器**：配图用 `UNNotificationAttachment` 交给系统搬运，
    /// 系统会把文件拷进通知自己的目录，扩展直接就能读。
    /// 所以共享容器**只为收件箱而存在** —— 这是它能做到最小的原因。
    static let appGroup = "group.com.herinfo.app"

    // MARK: 分类与动作

    /// 提醒通知的分类。
    /// **必须与扩展 Info.plist 里的 `UNNotificationExtensionCategory` 逐字一致。**
    static let reminderCategory = "HI_REMIND"

    /// 分类动作。**只有两个，这是刻意的** ——
    /// 收起态能做的都是「轻决定」：推迟、今天不用了。
    /// 打标需要先看一眼内容再选，所以它放在**展开态**里（见 NotificationContentView），
    /// 正好对上 14 屏脚注那句「上滑查看，长按可直接打标」。
    enum Action {
        /// 「1 小时后」——后台动作，由主 App 的 delegate 重排一条通知。
        static let snoozeOneHour = "HI_SNOOZE_1H"
        /// 「今天不用了」——后台动作，只改这一条的开关，不删记录。
        static let doneToday = "HI_DONE"
    }

    enum Key {
        static let recordID   = "hi.recordID"
        static let reminderID = "hi.reminderID"
        static let title      = "hi.title"
        static let body       = "hi.body"
        static let cat        = "hi.cat"
        static let version    = "hi.version"
        static let photoCount = "hi.photoCount"
    }

    // MARK: 五个情绪档

    /// 锁屏通知上的打标胶囊要用它，主 App 的 09 屏也要用它。
    ///
    /// `case` 名与 `Models.swift` 里 `MoodLevel` 的 rawValue **逐个对应** ——
    /// 那边是 SwiftData 的持久化枚举（不能搬走），
    /// 所以这里的 rawValue 就是两者之间的桥，改一个必须改另一个。
    /// `check-swift.js` 会校验这五个 rawValue 是否对齐。
    enum Mood: String, CaseIterable {
        case happy, tired, down, angry, calm

        var title: String {
            switch self {
            case .happy: return "开心"
            case .tired: return "累"
            case .down:  return "低落"
            case .angry: return "生气"
            case .calm:  return "平静"
            }
        }

        /// 09 屏用图标，通知上只用文字（那一行要塞 5 个，图标放不下）。
        var symbol: String {
            switch self {
            case .happy: return "face.smiling"
            case .tired: return "zzz"
            case .down:  return "cloud.rain"
            case .angry: return "flame"
            case .calm:  return "leaf"
            }
        }
    }

    // MARK: 主色（**屏幕 / 锁屏通知 / 导出的 PDF 共用同一份**）

    /// 三档主色，浅深各一。
    ///
    /// 为什么放在共享契约里，而不是只放在 App 的 `Tokens.swift`：
    /// 同一个主色要在三个地方一模一样 —— 屏幕上是动态色、锁屏通知上是深色档、
    /// 导出的 PDF 上是浅色档（打印语义，不跟随主题）。
    /// 只要有一处自己抄一遍，就会出现「主 App 换了色、通知和 PDF 还是旧的」。
    /// `check-swift.js` 会检查这些 hex 只在这个文件里出现一次。
    enum Primary {
        static let light: UInt32     = 0xC0614A
        static let dark: UInt32      = 0xD37C63
        static let softLight: UInt32 = 0xCE6E56
        static let softDark: UInt32  = 0xE08D74
        static let deepLight: UInt32 = 0xB4523C
        static let deepDark: UInt32  = 0xC26A54
    }

    // MARK: 四个分类色（**设计令牌在这一处的唯一真相**）

    /// 锁屏通知永远画在深色底上，所以扩展要的是**深色档**的四个色值。
    /// `Tokens.swift` 里的 `C.like / C.trait_ / C.care / C.hate` 也从这里取值，
    /// 这样「四个分类色」只有一个定义处，改色不会只改到一半。
    enum Cat: String, CaseIterable {
        case like, trait_, care, hate

        var lightHex: UInt32 {
            switch self {
            case .like:   return 0xC0614A
            case .trait_: return 0xB4874A
            case .care:   return 0x7C9070
            case .hate:   return 0x6C7C8C
            }
        }

        var darkHex: UInt32 {
            switch self {
            case .like:   return 0xD37C63
            case .trait_: return 0xC79A5C
            case .care:   return 0x8FA681
            case .hate:   return 0x8397A8
            }
        }

        var title: String {
            switch self {
            case .like:   return "喜好"
            case .trait_: return "性格与外貌"
            case .care:   return "在意的事"
            case .hate:   return "讨厌的事"
            }
        }
    }

    // MARK: 通知里带的载荷（主 App 写入 → 扩展读出）

    struct Payload {
        let recordID: String?
        let reminderID: String?
        let title: String
        let body: String
        let cat: Cat?
        let version: Int
        let photoCount: Int

        static let empty = Payload(recordID: nil, reminderID: nil,
                                   title: "", body: "", cat: nil,
                                   version: 1, photoCount: 0)

        /// 从 userInfo 读。**缺字段时退到系统画的那份内容** ——
        /// 扩展宁可少画一块，也不能因为一个字段缺失就整块空白。
        init(userInfo: [AnyHashable: Any],
             fallbackTitle: String,
             fallbackBody: String) {
            self.recordID   = userInfo[Key.recordID] as? String
            self.reminderID = userInfo[Key.reminderID] as? String
            self.title      = userInfo[Key.title] as? String ?? fallbackTitle
            self.body       = userInfo[Key.body] as? String ?? fallbackBody
            self.cat        = (userInfo[Key.cat] as? String).flatMap(Cat.init(rawValue:))
            self.version    = userInfo[Key.version] as? Int ?? 1
            self.photoCount = userInfo[Key.photoCount] as? Int ?? 0
        }

        init(recordID: String?, reminderID: String?, title: String, body: String,
             cat: Cat?, version: Int, photoCount: Int) {
            self.recordID = recordID
            self.reminderID = reminderID
            self.title = title
            self.body = body
            self.cat = cat
            self.version = version
            self.photoCount = photoCount
        }
    }

    // MARK: 打标收件箱（扩展 → 主 App 的单向通道）

    /// 一次打标。
    ///
    /// **level 是 String 而不是 `MoodLevel`** —— `MoodLevel` 活在 Models.swift 里，
    /// 那是 SwiftData 的类型。扩展不该为了一个枚举把数据库框架链进来。
    struct MoodMark: Codable, Sendable {
        let recordID: String?
        let level: String
        let at: Date
    }

    /// 收件箱。
    ///
    /// 【为什么不直接写库】
    /// 扩展与主 App 是两个进程，同时开同一个 SwiftData 库会有写冲突，
    /// 而扩展被系统回收的时机完全不可控 —— 在那种地方做数据库事务是不负责任的做法。
    /// 打标是「一次性轻信息」，所以走**单向收件箱**：
    /// 扩展只管往里丢，主 App 在启动/回前台时取走并落成真正的 `Mood` 行。
    /// 这个方向只有一条，也就没有并发问题。
    enum Inbox {
        private static let key = "pendingMoodMarks"

        private static var defaults: UserDefaults? {
            UserDefaults(suiteName: HINotify.appGroup)
        }

        /// 扩展侧调用。
        ///
        /// 说明：`UserDefaults` 的写入是异步落盘的，而扩展可能紧接着就被系统杀掉。
        /// 这里不调用已废弃的 `synchronize()`；若真机上发现丢打标，
        /// 改成「写小文件到共享容器 + fsync」即可（接口不用变）。
        static func push(_ mark: MoodMark) {
            guard let d = defaults else { return }
            var list = read(d)
            list.append(mark)
            write(d, list)
        }

        /// 主 App 侧调用：取出并清空。**先清空再返回** ——
        /// 取走之后才落库，中间被打断也不该重复落两次。
        static func drain() -> [MoodMark] {
            guard let d = defaults else { return [] }
            let list = read(d)
            write(d, [])
            return list
        }

        private static func read(_ d: UserDefaults) -> [MoodMark] {
            guard let data = d.data(forKey: key),
                  let list = try? JSONDecoder().decode([MoodMark].self, from: data)
            else { return [] }
            return list
        }

        private static func write(_ d: UserDefaults, _ list: [MoodMark]) {
            let data = (try? JSONEncoder().encode(list)) ?? Data()
            d.set(data, forKey: key)
        }
    }
}
