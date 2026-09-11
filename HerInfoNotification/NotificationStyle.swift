//
//  NotificationStyle.swift
//  锁屏通知的视觉语言（只服务于通知内容扩展）
//
//  【为什么不放进 App 的 Tokens.swift】
//  那套令牌是「米色底 + 暖灰字」的世界，值是双档动态色。
//  通知永远画在深色壁纸上，用的是一套白阶透明度 —— 两套东西没有交集。
//  硬塞进同一个枚举，只会让「通知里那个 0.14 的白」看起来像主 App 的某个令牌，
//  然后下一个人去改它，发现改了没反应。
//
//  【有交集的部分不在这里，在共享契约里】
//  主色三档与四个分类色，通知与主 App 必须一模一样 ——
//  它们定义在 `HINotify`（两个 target 共用的一份），这里只负责包成 Color。
//  所以这个文件里**一个十六进制值都没有**：能共用的都共用了，
//  剩下的白阶透明度则是通知独有的语言，本来就不该共享。
//

import SwiftUI

/// 0xRRGGBB → Color。通知在深色底上，不需要动态色，所以是个纯函数。
func hiColor(_ hex: UInt32) -> Color {
    Color(red:   Double((hex >> 16) & 0xFF) / 255,
          green: Double((hex >> 8)  & 0xFF) / 255,
          blue:  Double(hex         & 0xFF) / 255)
}

enum NStyle {

    // MARK: 面
    /// 通知卡底。系统展开后会自己铺一层毛玻璃，这里只补一点提亮。
    static let cardFill = Color.white.opacity(0.14)

    // MARK: 字（白阶）
    static let ink  = Color.white
    static let ink2 = Color.white.opacity(0.78)
    static let ink3 = Color.white.opacity(0.55)
    static let ink4 = Color.white.opacity(0.45)

    // MARK: 线
    static let hairline = Color.white.opacity(0.14)

    // MARK: 按钮
    static let actionFill   = Color.white.opacity(0.16)
    static let actionBorder = Color.white.opacity(0.22)

    // MARK: 主色（取自共享契约，与屏幕上的主色是同一份值）
    static let primary     = hiColor(HINotify.Primary.dark)
    static let primarySoft = hiColor(HINotify.Primary.softDark)
    static let primaryDeep = hiColor(HINotify.Primary.deepDark)

    static let primaryGradient = LinearGradient(
        colors: [primarySoft, primaryDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: 圆角
    static let rImage: CGFloat = 20
    static let rCard: CGFloat  = 22
    static let rPill: CGFloat  = 100
}
