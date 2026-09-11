//
//  MoodIntent.swift
//  09 屏「系统级入口」里的第二行：快捷指令 / 锁屏小组件。
//
//  **它不需要新 target。** iOS 16 起 `AppIntent` 可以直接定义在主 App 里，
//  `import AppIntents` 之后会自动出现在系统「快捷指令」的动作列表里，
//  也能被挂到锁屏小组件上。
//  （交接文档早先写的是「情绪打标要新建 App Intent + Share Extension 两个 target」，
//   这句话有一半是错的 —— 这个文件就是那一半的反例。）
//
//  与 09 屏那三个按钮的关系是「同一个动作、不同的入口」。
//  它**不直接写库**，而是走 `HerInfoStore.notePendingMood` ——
//  因为快捷指令完全可能在 App 根本没起来的时候跑，那一刻没有 `ModelContext`。
//  这与锁屏打标走的是同一个模式：入口只负责记下意图，落库统一在 App 里做。
//

import AppIntents

/// `AppIntent` 的参数必须是 `AppEnum`，而 `MoodLevel` 是 `Codable` 的持久化枚举
/// （它身上还挂着 SwiftData）。
///
/// **不把 `MoodLevel` 本身改成 `AppEnum`** —— 那会让数据模型去依赖 AppIntents，
/// 模型不该知道「这个 App 有没有做快捷指令」。所以这里做一座薄薄的桥。
///
/// 只桥**三档**，与 09 屏那三个按钮一致：手动给的那三个是「1 秒完成」的动作，
/// 加到五档就把「快捷」这件事本身抵消了。锁屏上那五个是另一回事
/// （位置决定的宽度，不是同一批选项）。
enum MoodLevelOption: String, AppEnum {
    case happy, tired, down

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "情绪档位")
    }

    static var caseDisplayRepresentations: [MoodLevelOption: DisplayRepresentation] {
        [
            .happy: DisplayRepresentation(title: "挺好",
                                          image: .init(systemName: "face.smiling")),
            .tired: DisplayRepresentation(title: "有点累",
                                          image: .init(systemName: "zzz")),
            .down:  DisplayRepresentation(title: "心情差",
                                          image: .init(systemName: "cloud.rain"))
        ]
    }

    var level: MoodLevel {
        switch self {
        case .happy: return .happy
        case .tired: return .tired
        case .down:  return .down
        }
    }
}

struct MarkMoodIntent: AppIntent {

    static var title: LocalizedStringResource { "记下她今天怎么样" }

    static var description: IntentDescription? {
        IntentDescription("不打开 App，直接记下她今天的状态。")
    }

    /// **不因此打开 App。**
    ///
    /// 打标本身是 1 秒钟的事，为了记一个标把用户从锁屏拽进 App，
    /// 等于把轻动作做重了 —— 想慢慢写点什么的话，那一头还有 09 屏。
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "她今天", description: "挺好 / 有点累 / 心情差")
    var level: MoodLevelOption

    init() {}

    init(level: MoodLevelOption) {
        self.level = level
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        HerInfoStore.notePendingMood(level.level, source: .shortcut)
        return .result(dialog: "已记下：她今天\(level.level.boardTitle)")
    }
}

/// 让这个动作出现在「快捷指令」的建议里，也能在 Spotlight 里直接说出一整句。
///
/// `phrases` 里每一句都必须包含 `\(.applicationName)` —— 这是系统的硬要求，
/// 少了它整个 provider 不生效，而且**不报错**。
struct HerInfoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MarkMoodIntent(),
                    phrases: ["用\(.applicationName)记下她今天怎么样",
                              "\(.applicationName)她心情差"],
                    shortTitle: "记下她今天怎么样",
                    systemImageName: "heart.text.square")
    }
}
