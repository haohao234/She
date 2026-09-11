//
//  ShareContract.swift
//  主 App ↔ 分享扩展之间的唯一契约
//
//  【为什么单独一个文件，不塞进 NotificationContract.swift】
//  那一份的名字叫「主 App ↔ 通知扩展」，它描述的是**一次打标**；
//  这一份描述的是一次**分享**，落下去是一条**记录**。两件事共用一个文件没有好处，
//  只会让它变成「三个 target 的杂烩」—— 以后要改通知，得先看懂分享的部分。
//  所以分享相关的类型（SharedItem / Inbox / Cat）一个都不进那一份。
//
//  【但 App Group 的名字必须共用】
//  所以这里引用 `HINotify.appGroup`，而不是把字符串再写一遍。
//  写成两份的失败方式与分类 id 写成两份一模一样：
//  扩展往 A 容器写、主 App 从 B 容器读 —— **分享进来的东西静默丢失**，
//  不报错、不崩溃、日志里什么也没有。
//  这也正是分享扩展 target 需要同时引 NotificationContract.swift 的原因：
//  不是为了那几个类型，是为了那一个字符串、和那几个色值。
//
//  【仍然只依赖 Foundation】
//  不引 SwiftData（扩展没有理由把数据库框架链进来）、不引 SwiftUI / UIKit
//  （这里只描述「一次分享长什么样」，不描述它怎么显示）。
//  颜色不在这里 —— 扩展要的四个分类色与主色直接从 `HINotify.Cat` /
//  `HINotify.Primary` 取，**一行 hex 都不抄**。
//

import Foundation

enum HIShare {

    /// 共享容器。与通知扩展**同一个**（`group.com.herinfo.app`）。
    /// 引用而不是重写，理由见文件头。
    static let appGroup = HINotify.appGroup

    // MARK: - 归到哪一类

    /// 分享进来的东西要归到哪一类 —— **由用户在扩展里点，不由我们猜。**
    ///
    /// `Record.cat` 是必填的四值枚举，没有「未分类」；
    /// 而「她这条算喜好还是在意的事」本身就是一次判断 ——
    /// 猜错了留下的是**一条错数据**，比少一条糟得多。
    /// 这与打标那条纪律是同一条：只有用户给的信号才记。
    ///
    /// `case` 名与 `Category`（Tokens.swift）的 rawValue **逐个对应**，
    /// `check-swift.js` 会校验对齐 —— 那边的 rawValue 是 SwiftData 的持久化值，
    /// 改一个必须改另一个。
    enum Cat: String, CaseIterable {
        case like, trait_, care, hate

        var title: String {
            switch self {
            case .like:   return "喜好"
            case .trait_: return "性格与外貌"
            case .care:   return "在意的事"
            case .hate:   return "讨厌的事"
            }
        }
    }

    // MARK: - 一次分享

    /// 扩展 → 主 App 这条单向通道里装的那一条。
    ///
    /// **`cat` 是 String 不是 `Category`** —— `Category` 活在 Tokens.swift 里，
    /// 那个文件还带着整套配色、字体与间距令牌。扩展不该为了一个枚举
    /// 把整个设计系统链进来（链进来的后果是：改 App 的令牌会让扩展一起编译失败）。
    struct SharedItem: Codable, Sendable {
        let title: String
        let body: String
        let cat: String
        let at: Date
    }

    // MARK: - 从一段文字整理出一条记录

    /// 分享进来的往往是一坨「带前后空行、缩进不齐」的文本。
    /// 这里做的是**最小必要的整理**：不该在这里替用户改写任何一句话。
    enum Compose {

        /// 标题取到多少字。20 是记录卡标题（`lineLimit(1)`）在 375 宽里
        /// 放得下的经验值 —— 拿整段当标题的话，列表页每条都是一句被腰斩的话，
        /// 反而看不出是哪一条。
        static let titleLimit = 20

        /// 去掉首尾空行、把连续空行压成一个、每行去首尾空白。
        ///
        /// **只做这些。** 不合并段落、不改标点、不截断正文 ——
        /// 正文是她的原话，多删一个字都是在改用户的数据。
        static func normalize(_ raw: String) -> String {
            let lines = raw
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            var out: [String] = []
            for line in lines {
                // 连续空行压成一个；开头的空行直接丢（`out` 为空时 last 也当空看）
                if line.isEmpty, out.last?.isEmpty ?? true { continue }
                out.append(line)
            }
            while out.last?.isEmpty == true { out.removeLast() }
            return out.joined(separator: "\n")
        }

        /// 标题 = 首行，超过 `titleLimit` 截断加省略号。
        ///
        /// **首行是一个网址时，标题取域名。** 「她发的那个链接」是分享进来最常见的东西之一，
        /// 而 `https://www.xiaohongshu.com/discovery/item/66f…` 在列表里根本认不出来 ——
        /// 域名一眼就知道是哪儿的。正文仍然是完整的那条网址，一个字没少。
        ///
        /// 只有一行时，标题与正文会是同一句 —— **这是刻意的**：
        /// 另一种做法是把首行从正文里摘掉，可那样「一句话的分享」
        /// 存下来就只剩空正文了，而空正文的记录在列表里看着像坏的。
        static func title(from text: String) -> String {
            let first = text
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? text
            let base = first.isEmpty ? text : first

            // `contains("://")` 是必需的：`URL(string:)` 对「随便一句话」也会返回
            // 一个相对 URL（host 为 nil），只看 host 会把正常文案也引到分支里来。
            if base.contains("://"), let host = URL(string: base)?.host(), !host.isEmpty {
                return host
            }
            return base.count <= titleLimit ? base : String(base.prefix(titleLimit)) + "…"
        }

        /// 组装。**正文为空时返回 nil** —— 一条没有内容的记录不该被存下来，
        /// 那只会让用户下次打开时困惑「这条是我存的吗」。
        static func item(from raw: String, cat: Cat) -> SharedItem? {
            let body = normalize(raw)
            guard !body.isEmpty else { return nil }
            return SharedItem(title: title(from: body),
                              body: body,
                              cat: cat.rawValue,
                              at: .now)
        }
    }

    // MARK: - 收件箱（扩展 → 主 App 的单向通道）

    /// 【为什么不直接写库】
    /// 扩展与主 App 是两个进程，同时开同一个 SwiftData 库会有写冲突，
    /// 而扩展被系统回收的时机完全不可控 —— 在那种地方做数据库事务是不负责任的做法。
    /// 分享是「一次性轻信息」，所以走**单向收件箱**：扩展只管往里丢，
    /// 主 App 在启动 / 回前台时取走并落成真正的 `Record` 行。
    /// 这个方向只有一条，也就没有并发问题。
    ///
    /// 与 `HINotify.Inbox`（打标收件箱）是同一个模式、不同的键 ——
    /// 两边共用一个键的话，一次分享会被当成一次打标读出来。
    enum Inbox {
        private static let key = "pendingSharedItems"

        private static var defaults: UserDefaults? {
            UserDefaults(suiteName: appGroup)
        }

        /// 扩展侧调用。
        ///
        /// `UserDefaults` 的写入是异步落盘的，而扩展可能紧接着就被系统杀掉。
        /// 这里不调用已废弃的 `synchronize()`；若真机上发现丢分享，
        /// 改成「写小文件到共享容器 + fsync」即可（接口不用变）。
        static func push(_ item: SharedItem) {
            guard let d = defaults else { return }
            var list = read(d)
            list.append(item)
            write(d, list)
        }

        /// 主 App 侧调用：取出并清空。**先清空再返回** ——
        /// 取走之后才落库，中间被打断也不该重复落两次。
        static func drain() -> [SharedItem] {
            guard let d = defaults else { return [] }
            let list = read(d)
            write(d, [])
            return list
        }

        private static func read(_ d: UserDefaults) -> [SharedItem] {
            guard let data = d.data(forKey: key),
                  let list = try? JSONDecoder().decode([SharedItem].self, from: data)
            else { return [] }
            return list
        }

        private static func write(_ d: UserDefaults, _ list: [SharedItem]) {
            let data = (try? JSONEncoder().encode(list)) ?? Data()
            d.set(data, forKey: key)
        }
    }
}
