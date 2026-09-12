//
//  SearchFilterView.swift
//  我的宝宝江林桐
//
//  30 屏 · 搜索筛选与范围（含 04 屏的结果统计行）
//
//  这一屏最容易做错的**不是布局，是状态的所有权**。
//  搜索页上同时存在三份看起来都像「筛选」的东西，它们不能互相写回：
//
//    1. 25 屏的排序 —— 长期偏好，写回设置，关掉 App 还在
//    2. 30 屏的筛选 —— 只活一次搜索，改动搜索词就该失效
//    3. 这一次的搜索词本身 —— 更短命
//
//  把 2 当成 1 来做（存进设置），用户会发现「我随手筛了一下，
//  列表的默认排序被改了」。所以 `SearchFilter` 刻意不落库，
//  而且**一有风吹草动就自己作废**：改词、点最近搜索、换分类，都会清掉它。
//
//  另一半是「按之前先知道结果有多少条」：面板底部那行
//  「按这些条件，会筛出 N 条」和主按钮上的 N，用的必须是
//  与列表**同一份判断** —— 所以数字在搜索页算好传进来，面板自己不查库。
//

import SwiftUI

// MARK: - 三组条件

/// 时间范围。三档，含「全部」。
enum SearchRange: String, CaseIterable, Identifiable {
    case week  = "本周"
    case month = "本月"
    case all   = "全部"

    var id: String { rawValue }
}

/// 「只看」。
///
/// **这一组是单选，不是多选** —— 画布与交互原型都是单选。
/// 代价是没法同时看「已置顶 + 带提醒的」。
///
/// 真要改成多选，必须**同时**给一个「不限」选项：否则「一枚都没选」
/// 会等价于「一条都不显示」，那比不能组合更糟 —— 用户只是想取消约束，
/// 结果看到了空列表，然后会以为自己的记录丢了。
enum SearchOnly: String, CaseIterable, Identifiable {
    case reminder   = "带提醒的"
    case hasHistory = "有历史版本"
    case pinned     = "已置顶"

    var id: String { rawValue }
}

/// 这一次搜索里的排序。
/// **与 25 屏的 `ListSort` 是两份不同的东西**：那份是长期偏好（写回设置），
/// 这份只活在一次搜索里 —— 选项也不一样（这里是「按分类」，那边是「置顶优先」）。
enum SearchSort: String, CaseIterable, Identifiable {
    case recent     = "最近编辑"
    case oldest     = "最早记录"
    case byCategory = "按分类"

    var id: String { rawValue }
}

/// 一次搜索的临时收窄条件。三个字段各有默认值 —— 见 `standard`。
struct SearchFilter: Equatable {
    var range: SearchRange = .month
    var only:  SearchOnly  = .reminder
    var sort:  SearchSort  = .recent

    /// 「重置 / 清空条件」回到的那个状态。
    ///
    /// **它的语义是「回到出厂」，不是「全部变空」** ——
    /// 画布上「本月 / 带提醒的 / 最近编辑」三枚本来就是选中态，
    /// 面板一拉开就该是这副样子。把重置做成清空，
    /// 用户每重置一次都要重新选三组，那是惩罚而不是恢复。
    static let standard = SearchFilter()

    var isStandard: Bool { self == .standard }

    /// 把一条记录按这三组条件过一遍。
    ///
    /// **面板里那个预览数字与列表必须共用这一个方法。**
    /// 各自算各自的，两个数字迟早会对不上 ——
    /// 而「按之前说 3 条、按下去出 5 条」比不给预览更伤信任。
    func accepts(_ r: Record, now: Date = .now, cal: Calendar = .current) -> Bool {
        switch range {
        case .week:
            // 「本周」按**最近 7 天**算，不按自然周 ——
            // 自然周在周日晚上会突然只剩一天，用户没法预期。
            guard let from = cal.date(byAdding: .day, value: -7, to: now) else { break }
            if r.updatedAt < from { return false }
        case .month:
            // 「本月」按自然月。这里用日历比较而不是比字符串月份 ——
            // 跨年时会算错（1 月的记录会被判成「本月」）。
            if !cal.isDate(r.updatedAt, equalTo: now, toGranularity: .month) { return false }
        case .all:
            break
        }

        switch only {
        case .reminder:   if r.reminder?.isOn != true { return false }
        case .hasHistory: if r.version <= 1 { return false }
        case .pinned:     if r.pinnedAt == nil { return false }
        }

        return true
    }

    /// 排序。三种都必须是**全序**：同值时用 id 做最后的 tiebreaker。
    /// 否则 SwiftData 每次取出来的顺序会抖，列表看起来像在随机重排。
    func sorted(_ list: [Record]) -> [Record] {
        switch sort {
        case .recent:
            return list.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
        case .oldest:
            return list.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        case .byCategory:
            return list.sorted { a, b in
                if a.cat.sortRank != b.cat.sortRank {
                    return a.cat.sortRank < b.cat.sortRank
                }
                return (a.updatedAt, a.id) > (b.updatedAt, b.id)
            }
        }
    }
}

private extension Category {
    /// 分类的固定次序：喜好 → 性格与外貌 → 在意的事 → 讨厌的事。
    ///
    /// **不要图省事去比 `rawValue`。** 四个 rawValue 的字母序是
    /// `care / hate / like / trait_`，和设计里的顺序完全不是一回事 ——
    /// 界面上会出现「在意的事 → 讨厌的事 → 喜好 → 性格」，用户会以为排序坏了。
    /// （交互原型里那一版就是比字符串排的，那是个真 bug，别照抄。）
    var sortRank: Int {
        switch self {
        case .like:   return 0
        case .trait_: return 1
        case .care:   return 2
        case .hate:   return 3
        }
    }
}

// MARK: - 结果统计行

/// 04 屏那行「找到 N 条结果」+ 右边那枚「筛选」。
///
/// 两个数字的口径不同，别合并成一个：
///
///  · **没套筛选** → 「找到 N 条结果」，N = 搜索命中数
///  · **套了筛选** → 「找到 N 条结果 · 已筛掉 M 条」，
///    N = 筛完剩下的，M = 被条件砍掉的那部分
///
/// 用户想知道的是「我的条件砍掉了多少」，所以第二个数字
/// **只在真的套了筛选之后才出现** —— 平时挂在那里只会变成噪声。
struct SearchResultHeader: View {
    let shown: Int
    let dropped: Int
    let isFiltered: Bool
    let onFilter: () -> Void

    var body: some View {
        HStack(spacing: S.rowGap) {
            Text(isFiltered
                 ? "找到 \(shown) 条结果 · 已筛掉 \(dropped) 条"
                 : "找到 \(shown) 条结果")
                // 等宽数字。这里的数字会随着打字一路变（6 → 3 → 1），
                // 不等宽的话整行宽度一直在跳，旁边那枚「筛选」也跟着左右滑。
                // 与规范页「数字一律等宽」是同一条规矩。
                .font(Typo.numCaptionM)
                .foregroundStyle(C.ink3)

            Spacer(minLength: 0)

            Button(action: onFilter) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .medium))
                    Text("筛选")
                        .font(Typo.caption)
                        .fontWeight(.medium)
                }
                // 画布把漏斗画成 #B0523C、把「筛选」两个字写成 #C0614A。
                // 两个红差 2 个色阶，11px 字号下没人看得出来 ——
                // 所以统一用 `hiInk`：它本来就是「暖底上的文字」那一当。
                // 留两个值只会多一处将来会漂移的副本。
                .foregroundStyle(C.hiInk)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(C.warm, in: Capsule(style: .continuous))
            }
            .pressDown()
        }
    }
}

// MARK: - 面板本体

/// 30 屏的面板。挂法看 `SearchFilterOverlay`。
struct SearchFilterPanel: View {
    @Binding var draft: SearchFilter

    /// 按当前草稿算「会筛出几条」。**由搜索页算好传进来** ——
    /// 面板不自己去查数据库：它只要一个数字，
    /// 而「哪些记录算命中」的判断必须和列表用的是同一份。
    let previewCount: Int
    let onApply: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: S.innerGapL) {
            HStack(alignment: .firstTextBaseline) {
                Text("筛选")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(C.ink)

                Spacer(minLength: 0)

                Button(action: onClear) {
                    Text("重置")
                        .font(Typo.captionM)
                        .foregroundStyle(C.hiInk)
                        .padding(.vertical, 2)
                }
                .pressDown()
            }

            chipLine("时间范围", SearchRange.allCases, draft.range) { draft.range = $0 }
            chipLine("只看",     SearchOnly.allCases,  draft.only)  { draft.only  = $0 }
            chipLine("排序",     SearchSort.allCases,  draft.sort)  { draft.sort  = $0 }

            // 这行数字不是装饰。功能越多的筛选面板，越需要在下手之前
            // 就给一个即时反馈 —— 否则用户只能靠「反复开关面板试」来找条件，
            // 而每试一次都要多两次点击。
            Text("按这些条件，会筛出 \(previewCount) 条")
                .font(Typo.numCaptionM)
                .foregroundStyle(C.ink3)

            HStack(spacing: S.innerGap) {
                Button(action: onClear) {
                    Text("清空条件").secondaryButtonStyle()
                }
                .pressDown()

                Button(action: onApply) {
                    Text("看 \(previewCount) 条结果")
                        .font(Typo.btn)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(C.primary, in: Capsule(style: .continuous))
                }
                .pressDown()
            }
        }
        .padding(EdgeInsets(top: 16, leading: S.screen, bottom: 24, trailing: S.screen))
        // 圆角只画上面两个 —— 下面两个角在屏幕外。
        // 与 26 屏的删除面板用同一套外框参数，别让两块底部面板长得不一样。
        .background(C.card, in: RoundedRectangle(cornerRadius: R.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, y: -4)
    }

    /// 一组胶囊。**同组单选**，选中的用主色实心、其余是浅槽底。
    ///
    /// 用 `FlowLayout` 自动折行而不是 `HStack`：
    /// 「有历史版本」那一条加上前两枚就超过 375 - 40 的可用宽，
    /// 写死成一行会直接溢出屏幕右缘，而且不会报错。
    private func chipLine<T: Hashable & Identifiable>(
        _ title: String,
        _ options: [T],
        _ selected: T,
        pick: @escaping (T) -> Void
    ) -> some View where T.ID == String {
        VStack(alignment: .leading, spacing: S.rowGap) {
            Text(title)
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)

            FlowLayout(spacing: S.rowGap) {
                ForEach(options) { o in
                    Pill(text: o.id,
                         style: o == selected ? .selected : .normal,
                         onTap: { pick(o) })
                }
            }
        }
    }
}

// MARK: - 挂法

/// 30 屏的挂法：遮罩与面板一起从下方进来。
///
/// 用 `ZStack` 覆盖而不是系统 `.sheet`，是为了跟 26 屏的删除面板一致 ——
/// 同一套「底部面板」在两屏长得不一样、动得不一样，比少一层实现糟得多。
///
/// **刻意不画那个小横条（grabber）。** 画布上画了，因为那是平台惯例；
/// 但这块面板不吃下拉手势（只能点遮罩或按钮关），画一条横条
/// 等于承诺一个不存在的交互 —— 用户会去拖它，然后发现拖不动。
/// 以后真做了拖拽关闭，再把横条补上。
struct SearchFilterOverlay: View {
    @Binding var draft: SearchFilter
    let previewCount: Int
    let onApply: () -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // 遮罩：**只关面板，不套用筛选。**
            // 点一下背景就把列表按新条件改掉，是最容易让人以为
            // 「这个 App 自己乱动」的做法 —— 用户点遮罩的心智是「算了」，
            // 不是「就这样吧」。
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            SearchFilterPanel(draft: $draft,
                              previewCount: previewCount,
                              onApply: onApply,
                              onClear: onClear)
                .transition(.move(edge: .bottom))
        }
    }
}
