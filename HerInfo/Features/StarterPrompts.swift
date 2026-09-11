//
//  StarterPrompts.swift
//  对应画布 06 起手卡组 / 21 首条记录引导 · 带引导的编辑器
//
//  这一条产品线只回答一个问题：**新用户对着空白输入框，不知道写什么。**
//
//  做法是「替他填一半，不替他写」：
//  - 标题**替他定了**（改标题比想标题容易得多，而「不知道写什么」八成卡在标题上）
//  - 内容**一个字都不填**，只给一条示范当占位（
//    填了的话，用户会以为那就是「标准答案」，然后把它删掉重写 —— 比空白更费事）
//  - 分类和标签预选好（这两个是「选」，不是「写」，替他选没有副作用）
//  - 提醒打开（这一条记录的价值就在于合适的时候被想起来）
//
//  三张卡的文案与画布 06 逐字一致。**没有「跳过」按钮** ——
//  三张卡本身就是选项，点任意一张都是开始，不需要再给一个「我什么都不选」的出口。
//

import SwiftUI

// MARK: - 起手题

/// 06 起手卡组里的三张卡，和 21 屏「换一题」轮换的是同一份数据。
///
/// 每一题自带分类与标签 —— 因为「填一半」这件事必须落到具体字段上，
/// 让调用方去猜「她爱吃什么该归到哪一类」是没必要的重复判断。
enum StarterTopic: String, CaseIterable, Identifiable {
    case food, flower, habit

    var id: String { rawValue }

    /// 卡标题，同时也是 21 屏预填进输入框的标题。
    var title: String {
        switch self {
        case .food:   return "她爱吃什么"
        case .flower: return "她喜欢的花"
        case .habit:  return "她的小习惯"
        }
    }

    /// 卡说明。**写的是「可以记哪些」，不是「这道题有多重要」** ——
    /// 空态里不需要再劝人记录，只要告诉他这道题大概长什么样。
    var hint: String {
        switch self {
        case .food:   return "常点的、爱吃的、绝对不碰的"
        case .flower: return "送花的、她说好看的、香不香"
        case .habit:  return "睡前的、出门前的、固定动作"
        }
    }

    /// 图标。画布上是手绘的碗 / 花 / 月亮，到 iOS 上用系统符号代替：
    /// 这三个名字在 iOS 17 上都有，且形状与画布上的三个图形是同一个意思。
    var symbol: String {
        switch self {
        case .food:   return "fork.knife"
        case .flower: return "camera.macro"     // 系统里唯一画成花的符号
        case .habit:  return "moon.stars"
        }
    }

    var cat: Category {
        switch self {
        case .food:   return .like
        case .flower: return .like
        case .habit:  return .trait_
        }
    }

    var tags: [String] {
        switch self {
        case .food:   return ["口味与忌口"]
        case .flower: return ["送礼参考"]
        case .habit:  return ["生活习惯"]
        }
    }

    /// 内容框的示范。**它是 placeholder，不是预填值** ——
    /// 21 屏画的就是这个：灰色占位 + 一个光标，正文一格空的。
    ///
    /// 三句都写成「比如：…」开头，是为了跟真正的正文区分开。
    /// 用户第一眼就该知道「这是给我的例子」，而不是「App 已经替我写了半句」。
    var placeholder: String {
        switch self {
        case .food:
            return "比如：常点的川菜、爱喝三分糖的奶茶、绝对不碰香菜和折耳根…"
        case .flower:
            return "比如：喜欢白玫瑰和洋桔梗、受不了百合的香味、上次送的向日葵她很喜欢…"
        case .habit:
            return "比如：睡前一定要把手机充上电、出门前会照三次镜子、奶茶只喝热的…"
        }
    }

    /// 「换一题」轮到的下一题。
    ///
    /// 按 `allCases` 顺序转一圈，**不做「同一分类内轮换」** ——
    /// 那样在喜好里就只有两题可换，第三下会看起来像按钮坏了。
    /// 换一题换的不只是标题，分类和标签也会跟着换，这是这一题的属性，不是副作用。
    var next: StarterTopic {
        let all = StarterTopic.allCases
        guard let i = all.firstIndex(of: self) else { return .food }
        return all[(i + 1) % all.count]
    }

    /// 从路由参数还原。认不出来就退回第一题 ——
    /// 路由参数只可能由本文件写出来，认不出来说明是旧版本遗留的深链，
    /// 与其让编辑器空着，不如给第一题。
    static func from(_ raw: String) -> StarterTopic {
        StarterTopic(rawValue: raw) ?? .food
    }
}

// MARK: - 06 起手卡组

/// 空态下面那三张卡。
///
/// **只在「整个 App 一条记录都没有」时出现**，不是「当前分类为空」就出现 ——
/// 一个有 30 条记录的人切到空的「讨厌的事」，他要的是换个分类看看，
/// 不是被问一次「她爱吃什么」。这三张卡是给**第一次打开 App 的人**的开场白，
/// 文案里那句「先从这三件开始」就是这个意思。
struct StarterCardGroup: View {
    let onPick: (StarterTopic) -> Void

    init(onPick: @escaping (StarterTopic) -> Void) {
        self.onPick = onPick
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(StarterTopic.allCases) { t in
                StarterCard(topic: t) { onPick(t) }
            }
        }
    }
}

/// 单张起手卡：图标底 32 → 标题 / 说明 → 箭头。
private struct StarterCard: View {
    let topic: StarterTopic
    let onTap: () -> Void

    init(topic: StarterTopic, onTap: @escaping () -> Void) {
        self.topic = topic
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(topic.cat.soft).frame(width: 32, height: 32)
                    Image(systemName: topic.symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(topic.cat.tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(Typo.bodyS.weight(.medium))
                        .foregroundStyle(C.ink)
                    Text(topic.hint)
                        .font(Typo.caption)
                        .foregroundStyle(C.ink2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.ink3.opacity(0.7))
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(C.card, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: R.input, style: .continuous)
                    .strokeBorder(C.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pressDown()
    }
}

// MARK: - 21 屏那条引导提示条

/// 21 屏把「自动保存状态」那条换成了它。
///
/// **为什么是替换而不是叠加**：两条都讲状态，同时挂在输入框上方会变成
/// 一个没人读的双行状态区。而这一屏真正需要说明的只有一件事 ——
/// 「标题不是你写的，是我替你填的，不满意可以换」。
struct StarterHintBar: View {
    let topic: StarterTopic
    let onShuffle: () -> Void

    init(topic: StarterTopic, onShuffle: @escaping () -> Void) {
        self.topic = topic
        self.onShuffle = onShuffle
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(C.primary)

            Text("起手引导 · 标题已帮你填好")
                .font(Typo.numCaption)
                .foregroundStyle(C.primary)

            Spacer(minLength: 0)

            Button(action: onShuffle) {
                Text("换一题")
                    .font(Typo.numCaption)
                    .foregroundStyle(C.primary)
            }
            .buttonStyle(.plain)
            .pressDown()
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(C.warm, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
