//
//  Tokens.swift
//  我的宝宝江林桐 · 设计令牌层
//
//  这一层是设计稿与代码之间唯一的接口。
//  36 屏里出现的每一个颜色、字号、圆角、间距都只能从这里取，
//  视图文件里不允许出现字面色值 —— 否则改一次色要翻 36 个文件。
//
//  为什么用 UIColor(dynamicProvider:) 而不是 Asset Catalog 的 Color Set：
//  这样零配置就能跑起来（拖进 Xcode 直接编译），颜色也集中在一个文件里，
//  设计师对着规范页改这一处即可。正式接入时若产品/设计希望「改色不改代码」，
//  再把这里替换成同名的 Color Set（命名保持一致，视图层一行都不用动）。
//

import SwiftUI
import UIKit

// MARK: - 十六进制色值 → UIColor

extension UIColor {
    /// 从 0xRRGGBB 构造。设计稿里所有色值都是这个格式。
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8)  & 0xFF) / 255,
            blue:  CGFloat(hex         & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - 双档色：一个名字，浅色与深色两个值

extension Color {
    /// 声明一个跟随系统外观切换的语义色。
    /// - Parameters:
    ///   - light: 浅色下的字面值
    ///   - dark:  深色下的字面值
    static func dual(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }
}

// MARK: - 色彩令牌

/// 与设计规范页「设计令牌」章节逐值对应。改这里 = 改全案。
enum C {

    // 基础面
    static let bg     = Color.dual(0xF8F5F0, 0x1A1613)   // 页面底
    static let card   = Color.dual(0xFFFFFF, 0x241F1B)   // 卡片面
    static let fill   = Color.dual(0xF1EAE2, 0x2E2823)   // 浅槽底（分段轨道 / 输入底）

    // 文字三级
    static let ink    = Color.dual(0x1F1E1B, 0xF3EEE8)   // 主文字
    static let ink2   = Color.dual(0x5C5A55, 0xBCB2A8)   // 次文字
    static let ink3   = Color.dual(0x948C82, 0x9A9187)   // 说明文字 / 占位符

    // 线
    static let line   = Color.dual(0xEFE8E0, 0x342D27)   // 细边框
    static let line2  = Color.dual(0xEAE2D8, 0x2E2823)   // 稍重的边框 / 分隔

    // 主色。三档值取自 `HINotify.Primary` —— 锁屏通知扩展与 PDF 导出
    // 也要用同一个主色，定义放在共享契约里，三处就不会各走各的。
    static let primary = Color.dual(HINotify.Primary.light, HINotify.Primary.dark)
    /// 主按钮渐变用的两端。设计稿是 140° 渐变，SwiftUI 里用 .topLeading → .bottomTrailing 近似。
    static let primaryDeep = Color.dual(HINotify.Primary.deepLight, HINotify.Primary.deepDark)
    static let primarySoft = Color.dual(HINotify.Primary.softLight, HINotify.Primary.softDark)

    // 四分类辅助色（与主色刻意同亮度区间，保证并排时不打架）。
    // 色值取自 `HINotify.Cat` —— 锁屏通知扩展也要画这四个色点，
    // 定义放在共享契约里，就不会出现「改了一处、通知里还是旧色」。
    static let like   = Color.dual(HINotify.Cat.like.lightHex,
                                   HINotify.Cat.like.darkHex)    // 喜好 —— 主色系
    static let trait_ = Color.dual(HINotify.Cat.trait_.lightHex,
                                   HINotify.Cat.trait_.darkHex)  // 性格与外貌
    static let care   = Color.dual(HINotify.Cat.care.lightHex,
                                   HINotify.Cat.care.darkHex)    // 在意的事
    static let hate   = Color.dual(HINotify.Cat.hate.lightHex,
                                   HINotify.Cat.hate.darkHex)    // 讨厌的事

    // 四分类的浅底（卡片 / 胶囊的未选中底）
    static let warm   = Color.dual(0xFAEDE6, 0x3A2621)   // 喜好浅底 / 高亮底
    static let sand   = Color.dual(0xF7F0E1, 0x352D1E)   // 性格浅底
    static let moss   = Color.dual(0xEDF1E7, 0x232C20)   // 在意浅底
    static let mist   = Color.dual(0xECF0F3, 0x212930)   // 讨厌浅底

    /// 危险色。**刻意不等于主色** —— 删除是破坏性动作，
    /// 如果它和「保存」同一个颜色，用户会靠颜色区分不了两件事。
    static let danger = Color.dual(0xB0523C, 0xD98672)

    // 版本对比（07 屏）用的两组色。**刻意不进公开的 16 个令牌** ——
    // 它们只出现在「旧版原文 / 新版新增」这两个 diff 块上，
    // 加进公开令牌就等于逼规范页与交互原型各长两档，只为这两块存在。
    //
    // 旧版那组是「退到背景里」：底比页面底还浅一档，字比 ink3 再淡一档。
    // diff 的两侧必须**一退一进** —— 两边都加重就分不出哪边是新的了。
    static let diffOldBg  = Color.dual(0xF5F2ED, 0x2E2823)
    static let diffOldInk = Color.dual(0xA79E95, 0x8A8279)

    /// 高亮底 / 高亮文字。设计规范里本来就有这两档值（`#F7E0D6` / `#B0523C`），
    /// 只是此前没有任何组件用到，所以一直没落成令牌。
    /// 深色档按「高亮降饱和」推：`#F7E0D6` → `#4A2F25`；
    /// 而高亮文字的深色档**就是主色的深色档**，所以直接取契约值，
    /// 不把 `0xD37C63` 再抄一遍（抄一遍就是一处将来会漂移的副本）。
    static let hiBg  = Color.dual(0xF7E0D6, 0x4A2F25)
    static let hiInk = Color.dual(0xB0523C, HINotify.Primary.dark)

    /// 开关轨道（关）。它不在公开的 16 个令牌里，因为只有开关一个组件用它。
    static let switchTrack = Color.dual(0xE3DCD3, 0x2E2823)

    /// 配图全屏预览的底（见 `PhotoViewer`）。
    ///
    /// **这是全案唯一一个浅深两档取同一个值的面**，理由不是偷懒：
    /// 预览页的任务是「把这张图看清楚」，底要是跟着主题走，
    /// 同一张照片在浅色下与深色下会呈现出两种明度关系 ——
    /// 那「这张图是不是偏色」就永远说不清了。照片要在暗底上判断，
    /// 所有修图软件清一色黑底是同一个道理。
    ///
    /// 取深色档的页面底（`C.bg` 深色那一档的字面值）而**不是纯黑**：
    /// 纯黑在 OLED 上和熄屏的屏幕边缘连成一片，图的四边到哪儿为止就看不出来了。
    static let viewerScrim = Color(uiColor: UIColor(hex: 0x1A1613))

    // 打标档位（09 / 10 屏）用的三组色，同样不进公开的 16 个。
    //
    // **不新造色相** —— 那三档正好落在已有的三个色相上：
    // 挺好 = 在意的事（草木绿）／有点累 = 性格与外貌（暖褐）／心情差 = 主色（陶土红）。
    // 所以实心色一律**引用**分类与主色，不把 hex 再抄一遍 ——
    // 抄一遍就是一处将来会漂移的副本（深色档也就跟着自动对了）。
    static let moodGood  = Category.care.tint
    static let moodTired = Category.trait_.tint
    static let moodDown  = C.primary

    /// 浅底那三个是**打标档位专属**的：比分类卡那三块底更浅、更贴近页面底色。
    /// 因为它们是「一整排能按的按钮」，底色压深了会让这一排从卡片里跳出来。
    /// 深色档直接取分类那套暗底（同色相，不另调）。
    static let moodGoodSoft  = Color.dual(0xF2F5EE, 0x232C20)
    static let moodTiredSoft = Color.dual(0xF8F2E6, 0x352D1E)
    static let moodDownSoft  = Color.dual(0xFBF8F4, 0x3A2621)
}

// MARK: - 生理期（37~41 屏）

/// 生理期专用的四档色。
///
/// **刻意不给生理期一个「专属粉」** —— 这是这块设计上最要紧的一条分寸。
/// 粉 = 生理期是最省事的做法，但它同时也说了一句「这是件特殊的事」，
/// 而这里要的恰恰是「平常地记一下」。所以：
/// 经期用主色（她本来就是主角）、易孕用「在意的事」那支草木绿、
/// 底弧用「性格与外貌」那支砂色。**全部是已有色相的引用，
/// 一个新 hex 都没造** —— 于是深色档自动跟着已有那套走，不会漂。
enum CYC {

    /// 经期：主色。**引用不重抄** —— 抄一遍就是一处将来会漂移的副本。
    static let period     = C.primary

    /// 经期浅底（日期块底、统计块的底）。
    static let periodSoft = C.warm

    /// 易孕窗口：草木绿（= 在意的事那支）。
    static let fertile    = Category.care.tint

    /// 非经期那段的底弧。比页面底深一点点就够。
    static let track      = Color.dual(0xEDE6DC, 0x2E2823)

    /// 40 屏页脚那句「不是医学判断」的底与字。
    /// **用砂色不用 danger** —— 它是「说明」不是「警告」，
    /// 拿危险色就把它写成了一条错误，而它其实是句实话。
    ///
    /// 字的深色档直接引用分类色，**不把 hex 再抄一遍** ——
    /// 抄一遍 `0xC79A5C` 就是又造了一处将来会漂移的副本
    /// （这行最早就是抄的，被 `check-swift.js` 的「共用色防漂移」抓了一次）。
    static let noteBg  = C.sand
    static let noteInk = Color.dual(0x8A6532, HINotify.Cat.trait_.darkHex)
}

// MARK: - 分类

/// 四条分类。`cat` 在数据模型里只存这四个值 —— 多一个值就要多一套配色与文案。
enum Category: String, CaseIterable, Codable, Identifiable {
    case like, trait_, care, hate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .like:   return "喜好"
        case .trait_: return "性格与外貌"
        case .care:   return "在意的事"
        case .hate:   return "讨厌的事"
        }
    }

    var tint: Color {
        switch self {
        case .like:   return C.like
        case .trait_: return C.trait_
        case .care:   return C.care
        case .hate:   return C.hate
        }
    }

    /// 06 空态那句话。**按分类换，不用一句通用文案** ——
    /// 「这个分类还没有记录」是对的但没温度：它描述的是数据库，
    /// 而这句描述的是「你还不知道她什么」。画布 06 写的正是喜好那一句，原文照搬。
    var emptyTitle: String {
        switch self {
        case .like:   return "还没有记下她的喜好"
        case .trait_: return "还没有记下她什么样"
        case .care:   return "还不知道她在意什么"
        case .hate:   return "还不知道她讨厌什么"
        }
    }

    var soft: Color {
        switch self {
        case .like:   return C.warm
        case .trait_: return C.sand
        case .care:   return C.moss
        case .hate:   return C.mist
        }
    }
}

// MARK: - 字体

/// **字体在 iOS 上的落地判断（这是设计稿与系统之间最有价值的一处差异）**
///
/// 设计稿中文用 Noto Sans SC、数字用 Inter。到了 iOS 上：
///
/// - **中文直接用系统字体**（`.system` → 苹方 PingFang SC）。
///   苹方是 iOS 上渲染质量最好的中文字体，且自带系统级字重与动态字距。
///   若强行捆绑 Noto Sans SC 的三个字重（Regular/Medium/SemiBold），
///   大约增加 15MB 包体，换来的是一套屏幕字体略逊于系统的中文 —— 不划算。
///
/// - **数字用 SF Pro + `.monospacedDigit()`**。
///   Inter 与 SF Pro 在数字上的视觉差异极小，而 `.monospacedDigit()`
///   能让数字等宽 —— 这在「20:00」这类时间与「128 条」这类计数上是必须的，
///   否则数字一变宽度整行都在跳。
///
/// - 若设计坚持跨平台一致（比如同时要出 Android 版），
///   再走捆绑字体方案：把 `NotoSansSC-Medium.otf` 等拖进 target，
///   在 Info.plist 的 `UIAppFonts` 里登记，然后用 `Font.custom("Noto Sans SC", size:)`。
///   **Token 层已经收口，届时只改这一个文件。**
enum Typo {
    /// 页面大标题 · 20 / 600
    static let pageTitle   = Font.system(size: 20, weight: .semibold)
    /// 导航行标题 · 17 / 500
    static let navTitle    = Font.system(size: 17, weight: .medium)
    /// 卡片题 · 15 / 500
    static let cardTitle   = Font.system(size: 15, weight: .medium)
    /// 卡片题（弱） · 15 / 400
    static let cardTitleR  = Font.system(size: 15, weight: .regular)
    /// 正文 · 14 / 400
    static let body        = Font.system(size: 14)
    /// 正文小 · 13 / 400（多行输入用 13，行高 22）
    static let bodyS       = Font.system(size: 13)
    /// 按钮字 · 14 / 500
    static let btn         = Font.system(size: 14, weight: .medium)
    /// 胶囊 / 标签 · 12 / 400（选中 500）
    static let pill        = Font.system(size: 12)
    static let pillSel     = Font.system(size: 12, weight: .medium)
    /// 胶囊中号 · 11（编辑器里的标签 `3:255`、心情档位标签 `3:999`）
    static let pillS       = Font.system(size: 11)
    static let pillSM      = Font.system(size: 11, weight: .medium)
    /// 胶囊小号 · 10（记录卡底部那排标签 `3:155`、详情页分类标记 `3:334`）
    static let pillT       = Font.system(size: 10)
    static let pillTM      = Font.system(size: 10, weight: .medium)
    /// 说明 · 11 / 400
    static let caption     = Font.system(size: 11)
    /// 顶栏小标题 · 12 / 500
    static let captionM    = Font.system(size: 12, weight: .medium)
    /// 底部 tab 标签 · 10 / 400
    static let tabLabel    = Font.system(size: 10)
    /// 大时间（32 屏） · 36 / 600 · 数字等宽
    static let timeBig     = Font.system(size: 36, weight: .semibold).monospacedDigit()
    /// 时间行 / 计数（凡是要对齐的数字都用它）· 12 / 400 · 等宽
    static let numCaption  = Font.system(size: 12).monospacedDigit()
    /// 时间行强调 · 12 / 500 · 等宽
    static let numCaptionM = Font.system(size: 12, weight: .medium).monospacedDigit()
}

// MARK: - 圆角

/// 圆角是分层级的：越大的面用越大的圆角。
/// 一律用 `.continuous` —— iOS 的连续曲率圆角（俗称超椭圆），
/// 和 CSS 的 `border-radius` 不是同一条曲线，肉眼看「更软更贵」。
enum R {
    /// 记录卡 · 20（**记录卡的默认圆角是 20，不是 16**）
    static let card: CGFloat      = 20
    /// 大区块卡 / 说明板 · 28
    static let cardBig: CGFloat   = 28
    /// 输入框 · 16
    static let input: CGFloat     = 16
    /// 图片格 · 14
    static let photo: CGFloat     = 14
    /// 轻提示 · 14
    static let toast: CGFloat     = 14
    /// 底部面板顶角 · 30
    static let sheet: CGFloat     = 30
    /// 胶囊 / 按钮 · 100
    static let pill: CGFloat      = 100
    /// 底部导航外框 · 36
    static let tabOuter: CGFloat  = 36
    /// 底部导航单项 · 26
    static let tabItem: CGFloat   = 26
}

// MARK: - 间距

/// 手机屏只有 375 宽，间距是排版的主要手段。
/// 基准：屏左右 20、卡片内 16~20、卡内纵向 10~16。
enum S {
    /// 屏左右安全边
    static let screen: CGFloat     = 20
    /// 卡片内边距（标准）
    static let cardPad: CGFloat    = 16
    /// 卡片内边距（宽松，用于含多行的块）
    static let cardPadL: CGFloat   = 20
    /// 卡与卡之间
    static let cardGap: CGFloat    = 16
    /// 卡内纵向间距
    static let innerGap: CGFloat   = 10
    /// 卡内纵向间距（松）
    static let innerGapL: CGFloat  = 14
    /// 行内元素间距
    static let rowGap: CGFloat     = 8
    /// 底部导航外层留白：左右 21 / 上 12 / 下 21
    static let tabInset  = EdgeInsets(top: 12, leading: 21, bottom: 21, trailing: 21)
}

// MARK: - 投影

/// 五级投影，**全部用暖灰，不用纯黑**。
/// 纯黑投影在米色底上会发脏，暖灰（带一点红黄）才像是「光从上方来」。
///
/// ## ⚠️ 这里的 `l1…l5` **不是**设计规范那张「投影 · 五级」卡的 L0–L4
///
/// 规范上的 L0–L4 是 **CSS 写法**（`0 20 40 −34 · #1F1E1B 50%` 这种），而 SwiftUI /
/// Core Animation **没有 spread（第四个长度）**，`shadowRadius` 又约等于 CSS blur 的**一半**
/// （CSS blur 16 → radius 8）。所以两边**不能直译**：照抄 `50%` 会糊成一块黑，
/// 照抄 blur 会得到一圈过大的虚影。下面这五组是**按视觉重调过的值**，
/// 对齐的是「分几层、每层做什么」，不是数字。
///
/// 2026-09-14 把对应关系写明，免得下次又有人拿 `l4` 去对规范的 L4：
///
/// | 规范 | 用途 | 这里 |
/// |---|---|---|
/// | L0 描边 | 绝大多数卡片 | 不是投影，`cardSurface` 里那圈 `C.line` 描边 |
/// | L1 软卡 | 离开底色的卡 | `l1` |
/// | L2 浮起 | 提醒卡、重点内容块 | `l2` |
/// | L3 面板 | 底部面板、键盘 | `l4`（规范没单列底部导航，`l3` 是它） |
/// | L4 主色 | 浮起按钮（全稿唯一带色的投影） | `primaryGlow` |
/// | — | 轻提示 / 模态（规范没单列） | `l5` |
enum Shadow {
    /// L1 · 卡片静置（规范 L1 软卡）
    static let l1Color  = Color.black.opacity(0.06)
    static let l1Radius: CGFloat = 8
    static let l1Y: CGFloat      = 2

    /// L2 · 卡片悬停 / 浮起（规范 L2 浮起）
    static let l2Color  = Color.black.opacity(0.07)
    static let l2Radius: CGFloat = 14
    static let l2Y: CGFloat      = 4

    /// L3 · 底部导航（规范里没有单列这一层，它是「贴在屏底的一整条」专用）
    static let l3Color  = Color.black.opacity(0.08)
    static let l3Radius: CGFloat = 20
    static let l3Y: CGFloat      = 8

    /// L4 · 浮层 / 底部面板
    static let l4Color  = Color.black.opacity(0.09)
    static let l4Radius: CGFloat = 28
    static let l4Y: CGFloat      = 12

    /// L5 · 轻提示 / 模态
    static let l5Color  = Color.black.opacity(0.12)
    static let l5Radius: CGFloat = 36
    static let l5Y: CGFloat      = 18

    /// **规范 L4 · 全稿唯一带颜色的投影**（浮起按钮）。2026-09-14 从 `BrowseView` 里
    /// 手写的那行收进来的 —— 之前只有那一处用得着，所以它一直散在调用点上，
    /// 规范的 L4 在代码里等于没有落点。
    ///
    /// 规范写的是 `0 10 22 −10 · #BF614A 90%`，那是 **CSS**：`90%` 的透明度配上
    /// `spread −10`（把影子整体收小 10）之后，实际是一圈紧贴的浅光晕。
    /// SwiftUI 没有 spread，照抄 `90%` 会糊成一块脏色，所以这里沿用 02 / 06 屏
    /// 已经验收过的那一组值（不要因为「和规范不一样」去改它）。
    static let primaryGlowColor  = C.primary.opacity(0.35)
    static let primaryGlowRadius: CGFloat = 14
    static let primaryGlowY: CGFloat      = 6

    /// 滑块专用：它要让圆点「浮在轨道上」，深色下也必须保留。
    static let thumbColor  = Color(uiColor: UIColor(hex: 0x1F1E1B, alpha: 0.45))
    static let thumbRadius: CGFloat = 6
    static let thumbY: CGFloat      = 2
}

// MARK: - 便捷修饰符

extension View {
    /// 卡片面：底 + 描边 + 一级投影。36 屏里所有 `.card` 都用它。
    func cardSurface(radius: CGFloat = R.card,
                     padding: CGFloat = S.cardPad,
                     shadow: Bool = true) -> some View {
        self
            .padding(padding)
            .background(C.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(C.line, lineWidth: 1)
            )
            .shadow(color: shadow ? Shadow.l1Color : .clear,
                    radius: shadow ? Shadow.l1Radius : 0,
                    y: shadow ? Shadow.l1Y : 0)
    }

    /// 主按钮：140° 渐变 + 白字。
    func primaryButtonStyle() -> some View {
        self
            .font(Typo.btn)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                LinearGradient(colors: [C.primarySoft, C.primaryDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule(style: .continuous)
            )
    }

    /// 次按钮：卡面底 + 描边。
    func secondaryButtonStyle() -> some View {
        self
            .font(Typo.btn)
            .foregroundStyle(C.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(C.card, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(C.line2, lineWidth: 1))
    }

    /// 按下态：整体下移 1px。**不做缩放、不改颜色** ——
    /// 缩放会让文字跟着糊，改色会让「按住了」和「选中了」混淆。
    func pressDown() -> some View {
        buttonStyle(PressDownStyle())
    }
}

struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
