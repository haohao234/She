//
//  NotificationContentView.swift
//  展开态通知里「系统画不出来的那一部分」
//
//  系统会自己画：应用图标 + 应用名 + 时间 + 标题 + 正文 + 两个动作按钮。
//  所以这个文件**不从标题开始画** —— 再画一遍只会得到两行标题。
//  它画的是画布 36 屏上「配图」以下的那些块：配图 / 元信息 / 快捷打标。
//
//  【一处与 34 屏刻意相反的判断】
//  编辑器（34 屏）里图片**紧跟标题**：那是你在写它的地方，图片是内容的一部分。
//  锁屏通知里图片在**正文下方**：一是系统原生顺序如此（系统的富通知就是图在文下），
//  二是扫一眼通知时先读字、再看图 —— 顺序反了，人得先滑过一张图才知道这条在说什么。
//  两条规则看起来矛盾，其实各自都对，因为它们回答的不是同一个问题。
//

import SwiftUI
import UIKit

struct NotificationContentView: View {
    let payload: HINotify.Payload
    let image: UIImage?
    let expanded: Bool
    let onMark: (HINotify.Mood) -> Void

    /// 打完标之后的短暂确认。**必须有这个反馈** ——
    /// 锁屏上的按钮点下去如果只是把通知收走，用户不知道到底记上了没有，
    /// 而「不知道记上没记上」会让人再打开 App 看一遍，那这个快捷入口就白做了。
    @State private var marked: HINotify.Mood?

    var body: some View {
        Group {
            if expanded {
                stack
            } else {
                // 收起态：**什么都不画**。
                // 系统把通知条压得很矮，这里如果放图或放一排胶囊，
                // 收起的样子就变成一条被切掉一半的怪东西。
                // 画布 14 屏（收起态）能逐字对得上，靠的就是这个分支。
                Color.clear.frame(height: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 展开态

    private var stack: some View {
        VStack(alignment: .leading, spacing: 14) {
            photo

            HStack(spacing: 6) {
                if let cat = payload.cat {
                    Circle()
                        .fill(hiColor(cat.darkHex))
                        .frame(width: 7, height: 7)
                    Text(cat.title)
                        .font(.system(size: 12))
                        .foregroundStyle(NStyle.ink3)
                }
                Text("· 第 \(payload.version) 版")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(NStyle.ink3)
                Spacer(minLength: 0)
            }

            Rectangle().fill(NStyle.hairline).frame(height: 1)

            moodSection
        }
    }

    /// 配图。用系统搬过来的附件 —— 见 NotificationViewController.loadImage()。
    @ViewBuilder
    private var photo: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: NStyle.rImage, style: .continuous))
                // 有几张图要写出来：通知上只能放一张，得让用户知道还有别的。
                .overlay(alignment: .bottomTrailing) {
                    if payload.photoCount > 1 {
                        Text("1 / \(payload.photoCount)")
                            .font(.system(size: 11))
                            .foregroundStyle(NStyle.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.35), in: Capsule(style: .continuous))
                            .padding(8)
                    }
                }
        } else if payload.photoCount > 0 {
            // 有图但读不出来（附件被系统清掉、文件损坏）。
            // **给一个「图没了」的位，不要静默消失** —— 留白会让通知看起来排版坏了。
            RoundedRectangle(cornerRadius: NStyle.rImage, style: .continuous)
                .fill(NStyle.actionFill)
                .frame(height: 88)
                .overlay(
                    Text("配图暂时读不出来")
                        .font(.system(size: 12))
                        .foregroundStyle(NStyle.ink3)
                )
        }
    }

    /// 快捷打标。**五个等宽**，不是自适应宽 ——
    /// 五个长度不一的胶囊排在一起，中点会歪，看起来像是随手放的。
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("她今天怎么样？")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NStyle.ink2)
                Spacer(minLength: 0)
                Text("记进她的档案")
                    .font(.system(size: 11))
                    .foregroundStyle(NStyle.ink4)
            }

            HStack(spacing: 6) {
                ForEach(HINotify.Mood.allCases, id: \.self) { m in
                    Button {
                        guard marked == nil else { return }
                        marked = m
                        onMark(m)
                    } label: {
                        Text(marked == m ? "已记下" : m.title)
                            .font(.system(size: 12, weight: marked == m ? .medium : .regular))
                            .foregroundStyle(marked == m ? NStyle.ink
                                             : (marked == nil ? NStyle.ink2 : NStyle.ink4))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                marked == m ? NStyle.primary : NStyle.actionFill,
                                in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(marked == m ? NStyle.primary : NStyle.actionBorder,
                                                  lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(marked != nil)
                }
            }
        }
    }
}
