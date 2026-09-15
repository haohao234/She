//
//  MoodView.swift
//  对应画布 09 情绪打标 · 手动快捷入口 / 10 打标之后 · 即时建议
//
//  这两屏是「聊天里出现情绪关键词就提醒」那条路在 iOS 上的**合规替代**：
//  沙盒不允许读第三方聊天记录，所以情绪只能由用户自己给出。
//  09 屏负责「给」，10 屏负责「给完之后顺手能做什么」。
//
//  10 屏那块面板最容易做错的地方是**建议从哪来**。
//  它不是模型生成的吗，是「检索 + 排序」—— 把档案里相关的记录翻出来，
//  按来源分组、按更新时间排。页脚那句「建议来自你记录过的内容 · 按更新时间排序」
//  只有真的这么做时才成立，所以下面一条写死的示例文案都没有。
//  原型说明里也把这一点写明了：「它不是模型生成的建议，是检索加排序的结果」。
//

import SwiftUI
import SwiftData

// MARK: - 档位配色

/// 09 屏那三个按钮的配色。
///
/// **不新造色相** —— 三档正好落在已有的三个色相上：
/// 挺好 = 在意的事（草木绿）／有点累 = 性格与外貌（暖褐）／心情差 = 主色（陶土红）。
/// 实心色因此一律取令牌，不写 hex（写一遍就是一处将来会漂移的副本）。
private extension MoodLevel {

    var boardTint: Color {
        switch self {
        case .happy: return C.moodGood
        case .tired: return C.moodTired
        case .down:  return C.moodDown
        default:     return C.ink3
        }
    }

    var boardSoft: Color {
        switch self {
        case .happy: return C.moodGoodSoft
        case .tired: return C.moodTiredSoft
        case .down:  return C.moodDownSoft
        default:     return C.fill
        }
    }
}

// MARK: - 09 屏 · 情绪打标

struct MoodBoardView: View {
    @Binding var path: [Route]

    @Environment(\.modelContext) private var ctx

    /// 已按时间倒序。第一条就是「最近一次打标」。
    @Query(sort: \Mood.at, order: .reverse) private var moods: [Mood]

    /// 刚打下的那一档。非空 = 拉起 10 屏那块面板。
    @State private var justMarked: MoodLevel?

    private var latest: Mood? { moods.first }

    var body: some View {
        VStack(spacing: 0) {
            NavRow("她的档案", onBack: { path.removeLast() }) {
                Button { path.append(.starterEdit(topic: "")) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("记一条")
                            .font(Typo.pillSel)
                    }
                    .foregroundStyle(C.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(C.warm, in: Capsule(style: .continuous))
                }
                .pressDown()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: S.cardGap) {
                    markCard
                    entriesBlock

                    Text("打标记录会存进档案，之后在搜索里也能找到")
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, S.screen)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let level = justMarked {
                MoodSuggestOverlay(
                    level: level,
                    onRecord: {
                        justMarked = nil
                        path.append(.starterEdit(topic: ""))
                    },
                    onRemind: { setTwoHourReminder(level) },
                    onDismiss: { justMarked = nil }
                )
            }
        }
    }

    // MARK: 打标卡

    private var markCard: some View {
        SCard(padding: S.cardPadL) {

            HStack(spacing: 8) {
                Text("她今天怎么样？")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(C.ink)
                Spacer(minLength: 0)
                Text("手动打标")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            }

            HStack(spacing: 8) {
                ForEach(MoodLevel.boardCases, id: \.self) { l in
                    levelButton(l)
                }
            }
            .padding(.top, 2)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(C.ink2)
                // 这句话是给用户看的**合规承诺**，不是装饰 ——
                // 「打标只记下这一刻」这句话成立，用户才愿意用。
                Text("打标只记下这一刻，不会读取任何聊天内容")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            Rectangle()
                .fill(C.line2)
                .frame(height: 1)
                .padding(.vertical, 2)

            HStack(spacing: 8) {
                Text("最近一次打标")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
                Spacer(minLength: 0)
                Text(lastMarkText)
                    .font(Typo.numCaption)
                    .foregroundStyle(C.ink2)
            }
        }
    }

    /// 三个档位按钮。
    ///
    /// **选中 = 最近一次打的就是这一档**，不是「你正按着它」——
    /// 打完标立刻弹面板，按钮不会停在按下的样子。
    /// 这样下次进来还能一眼看到她最近的状态，比三个恒定的浅底按钮多一层信息，
    /// 也和画布上那一枚实心的样子对得上。
    private func levelButton(_ l: MoodLevel) -> some View {
        let on = latest?.level == l
        return Button { mark(l) } label: {
            Text(l.boardTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Color.white : l.boardTint)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(on ? l.boardTint : l.boardSoft,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var lastMarkText: String {
        guard let m = latest else { return "还没打过标" }
        return "\(m.at.monthDayCN) · \(m.level.boardTitle)"
    }

    /// 打标 = 落一条 `Mood` + 拉起建议面板。
    ///
    /// `source` 记成 `.manual` —— 模型里那一列是**合法性凭据**：
    /// 这条数据是用户在这台手机上自己点的，不是从哪儿读来的。
    private func mark(_ l: MoodLevel) {
        ctx.insert(Mood(level: l, source: .manual))
        try? ctx.save()
        justMarked = l
    }

    // MARK: 系统级入口

    private var entriesBlock: some View {
        VStack(alignment: .leading, spacing: S.innerGap) {
            Text("系统级入口 · 不打开 App 也能打标")
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)

            VStack(spacing: 10) {
                ForEach(MoodEntry.all) { e in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(e.soft).frame(width: 36, height: 36)
                            Image(systemName: e.symbol)
                                .font(.system(size: 16))
                                .foregroundStyle(C.ink2)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title)
                                .font(Typo.bodyS)
                                .foregroundStyle(C.ink)
                            Text(e.note)
                                .font(Typo.caption)
                                .foregroundStyle(C.ink3)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(C.ink3)
                    }
                    .padding(14)
                    .background(C.card, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: R.input, style: .continuous)
                            .strokeBorder(C.line, lineWidth: 1)
                    )
                }
            }
        }
    }

    /// 09 屏下半部分那四行。
    ///
    /// **它们是「系统级入口」，不是 App 里的按钮** —— 每一行对应一个 iOS 能力，
    /// 所以底色顺着那件事挑（暖 / 沙 / 苔 / 冷灰），不套用 App 的分类色。
    /// 画布上给的正是这四组。
    private struct MoodEntry: Identifiable {
        let id = UUID()
        let symbol: String
        let soft: Color
        let title: String
        let note: String

        static let all: [MoodEntry] = [
            MoodEntry(symbol: "hand.tap",
                      soft: C.warm,
                      title: "长按 App 图标",
                      note: "快捷菜单里直接选档位，1 秒完成"),
            MoodEntry(symbol: "mic",
                      soft: C.sand,
                      title: "快捷指令 / 锁屏小组件",
                      note: "喊一声「她心情不好」，或用锁屏按钮打标"),
            MoodEntry(symbol: "square.and.arrow.up",
                      soft: C.moss,
                      title: "分享扩展",
                      note: "把她的原话分享进来，自动存成一条记录"),
            MoodEntry(symbol: "bell.badge",
                      soft: Category.hate.soft,
                      title: "在通知上直接换档位",
                      note: "打标打错了，长按通知就能改成别的档")
        ]
    }

    // MARK: 「2 小时后提醒我」

    /// 建一条**一次性**提醒，然后跳到 05 屏。
    ///
    /// 为什么不是只跳转：面板上写的是「2 小时后提醒我」，那就得真的有一件事会在
    /// 2 小时后响。只跳过去、让用户自己再设一遍，等于这个按钮是句空话。
    ///
    /// `repeatRule: .none`（仅一次）+ `leadMinutes: 0`（准时）——
    /// 这是「随手设一个」，不是「定一个长期提醒」；后者归 32 屏。
    private func setTwoHourReminder(_ level: MoodLevel) {
        let m = Reminder(kind: .date,
                         title: "她今天\(level.boardTitle)",
                         repeatRule: .none,
                         time: Date.now.addingTimeInterval(2 * 3600),
                         leadMinutes: 0,
                         message: "看看她今天怎么样，顺手做点什么")
        ctx.insert(m)
        try? ctx.save()
        Task { await ReminderService.shared.schedule(m) }

        justMarked = nil
        path.append(.reminders)
    }
}

// MARK: - 10 屏 · 打标之后的即时建议

/// 面板的三条来源。**它们在画布上是固定顺序的**，因为顺序本身有含义：
/// 「她说过的话 → 现在最想要的 → 千万别做」= 从「她是谁」走到「现在做什么」。
private enum SuggestSource: String, CaseIterable {
    case said  = "她说过的话"
    case want  = "现在最想要的"
    case never = "千万别做"

    /// 胶囊底色与字色。**与分类色同源**，不是随手挑的三个颜色：
    /// 前两条来自「喜好」，第三条来自「讨厌的事」。
    var badgeSoft: Color {
        switch self {
        case .said:  return C.warm
        case .want:  return C.sand
        case .never: return Category.hate.soft
        }
    }

    var badgeInk: Color {
        switch self {
        case .said:  return C.primary
        case .want:  return C.trait_
        case .never: return C.hate
        }
    }
}

/// 从底部推上来的那块面板。用 `ZStack` 覆盖而不是系统 `.sheet`，
/// 为了跟 26 屏的删除面板、30 屏的筛选面板走同一条路（全 App 三块面板一个做法）。
struct MoodSuggestOverlay: View {
    let level: MoodLevel
    let onRecord: () -> Void
    let onRemind: () -> Void
    let onDismiss: () -> Void

    @Query(filter: #Predicate<Record> { $0.deletedAt == nil },
           sort: \Record.updatedAt, order: .reverse)
    private var records: [Record]

    init(level: MoodLevel,
         onRecord: @escaping () -> Void,
         onRemind: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.level = level
        self.onRecord = onRecord
        self.onRemind = onRemind
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 遮罩点一下只关面板，不做事 —— 和 30 屏那条一致：
            // 点背景就顺手改掉点东西，是最容易让人以为「App 自己乱动」的做法。
            C.ink.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            sheet
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {

            // 顶部小横条。**这块面板是可以下拉收起的**（`presentationDragIndicator`
            // 那种手感），所以画它不算承诺一个不存在的交互 ——
            // 30 屏那块不吃下拉手势，那边就没画。
            Capsule()
                .fill(C.line2)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(Typo.cardTitle)
                        .foregroundStyle(C.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("已打标 · 刚刚")
                        .font(Typo.caption)
                        .foregroundStyle(C.primary)
                }
                Spacer(minLength: 0)
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(C.ink3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                // 档位标签 = 画布 `3:998`：`C.warm` 底 + **主色字** + 11 号 Medium。
                // 不是记录卡那种中性小标签（`.tag` / `C.ink2`），别混用。
                Pill(text: level.boardTitle, soft: C.warm, size: .small,
                     emphasis: true, textTint: C.primary)
                Text("档位随时可改，长按通知也能换")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(C.line2)
                .frame(height: 1)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                Text(countLine)
                    .font(Typo.captionM)
                    .foregroundStyle(C.ink3)

                if items.isEmpty {
                    emptyHint
                } else {
                    VStack(spacing: 8) {
                        ForEach(items, id: \.1.id) { src, rec in
                            row(src, rec)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                // 两个按钮直接用全 App 那一对样式（次按钮 / 主按钮）——
                // 面板上再定一套高度和渐变，就是在同一个 App 里开第二套按钮。
                Button { onRecord() } label: {
                    Text("记一条").secondaryButtonStyle()
                }
                .buttonStyle(.plain)

                Button { onRemind() } label: {
                    Text("2 小时后提醒我").primaryButtonStyle()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            Text("建议来自你记录过的内容 · 按更新时间排序")
                .font(Typo.caption)
                .foregroundStyle(C.ink3)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(EdgeInsets(top: 16, leading: S.screen, bottom: 40, trailing: S.screen))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.card,
                    in: RoundedRectangle(cornerRadius: R.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, y: -4)
    }

    // MARK: 建议从哪来

    /// 三条建议 = 「检索 + 排序」的结果，不是写死的文案。
    ///
    /// 三条各自的取法（都在 `records` 这个已按 `updatedAt` 倒序的数组上做）：
    ///   · 她说过的话 → 喜好里**最早**的一条。那是她提了很久、还没被忘掉的事，
    ///                  正好和「已经记下来的那些」呼应。
    ///   · 现在最想要的 → 喜好里**最新**的一条。
    ///   · 千万别做 → 讨厌的事里**最新**的一条。
    ///
    /// 用 `used` 去重：喜好只有一条时，前两条会落在同一条记录上，
    /// 去重后如实变成两条 —— 面板上那个数字是数出来的，不是编的。
    private var items: [(SuggestSource, Record)] {
        let likes = records.filter { $0.cat == .like }
        let hates = records.filter { $0.cat == .hate }

        var out: [(SuggestSource, Record)] = []
        var used = Set<String>()

        if let said = likes.last, !used.contains(said.id) {
            out.append((.said, said)); used.insert(said.id)
        }
        if let want = likes.first, !used.contains(want.id) {
            out.append((.want, want)); used.insert(want.id)
        }
        if let never = hates.first, !used.contains(never.id) {
            out.append((.never, never)); used.insert(never.id)
        }
        return out
    }

    private var countLine: String {
        items.isEmpty
            ? "档案里还没有能和这一档对上的记录"
            : "从你的档案里找到 \(items.count) 条相关记录"
    }

    private var headline: String {
        switch level {
        case .happy: return "她今天挺好 · 可以顺手做点什么"
        case .tired: return "她有点累 · 现在可以做什么"
        case .down:  return "她心情不好 · 现在可以做什么"
        default:     return "她今天怎么样 · 现在可以做什么"
        }
    }

    /// 一条记录都没有时的样子。**不写「暂无数据」** ——
    /// 那是在描述数据库；这里要说的是「先去记一条，之后这里就有东西了」。
    private var emptyHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14))
                .foregroundStyle(C.ink3)
            Text("先去记一条她的喜好或讨厌的事，下次打标这里就会有东西可看")
                .font(Typo.caption)
                .foregroundStyle(C.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(C.fill, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
    }

    private func row(_ src: SuggestSource, _ rec: Record) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(src.rawValue)
                    .font(Typo.captionM)
                    .foregroundStyle(src.badgeInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(src.badgeSoft, in: Capsule(style: .continuous))
                Text("\(rec.updatedAt.monthDayCN) · \(rec.cat.title)")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
                Spacer(minLength: 0)
            }
            Text(rec.title.isEmpty ? rec.body : rec.title)
                .font(Typo.bodyS)
                .foregroundStyle(C.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(C.bg, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: R.input, style: .continuous)
                .strokeBorder(C.line, lineWidth: 1)
        )
    }
}
