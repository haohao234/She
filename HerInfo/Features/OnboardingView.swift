//
//  OnboardingView.swift
//  对应画布 15 首次使用 · 建立她的档案 / 16 首次使用 · 开启通知
//
//  两屏是一条流程，所以放在一个文件里 —— 它们共用同一条两步的步骤条。
//
//  【在这之前发生了什么】
//  在这份文件之前，App 第一次启动会**直接往库里写一个叫「小满」的档案和 4 条记录**
//  （见 HerInfoStore.seed）。也就是说：用户第一次打开，看到的是别人的女朋友 ——
//  而「她叫什么」这个问题一次都没被问过。
//  15 屏的存在就是为了把这个起点补上，所以 seed 不再自动跑。
//
//  【三条不能改的判断】
//  ① **不做「跳过」按钮。** 档案是这个 App 的全部意义，没有档案它就是个空壳，
//     所以第一步不让人绕开 —— 但只拦这两项。
//  ② **只问两件事**（怎么称呼她、在一起的日子）。前面十几屏都建立在
//     「已经记了 128 条」之上；多问一条，第一次打开的人就会退出去。
//  ③ **先说清楚，再请求通知。** iOS 的通知权限一辈子只弹一次 ——
//     弹过之后用户点了「不允许」，就只能去系统设置里捞回来。
//     所以 16 屏是四个理由先摆出来，用户心里有数了再按那个按钮。
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    /// 走完两屏后置 true。`RootView` 靠它决定显示引导还是主界面。
    @Binding var finished: Bool

    @Environment(\.modelContext) private var ctx

    /// 15 → 16 两屏共用一条步骤条，所以是同一个变量。
    @State private var step = 0

    @State private var name = ""
    @State private var together = Date.now
    @State private var working = false

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 显式 init：这个组件要跨文件构造（`RootView`），
    /// 而它带着一堆 `@State private` 存储属性 —— 和 `SegmentControl` 同理，
    /// 手写一个 init 就永远不用担心逐成员初始化器的可见性。
    init(finished: Binding<Bool>) {
        self._finished = finished
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingSteps(step: step)

            ScrollView {
                if step == 0 { introduce } else { notify }
            }

            footer
        }
        .background(C.bg)
    }

    // MARK: 15 先告诉我，她是谁

    private var introduce: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("先告诉我，她是谁")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(C.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("这两项随时能改，其他内容以后再慢慢记")
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SCard(radius: 24, padding: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("我平时叫她")
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                    TextField("她的名字", text: $name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(C.ink)
                        .tint(C.primary)
                }

                Rectangle().fill(C.line).frame(height: 1)

                HStack(spacing: 12) {
                    Text("我们在一起的日子")
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                    Spacer(minLength: 0)
                    // 日期是唯一一类不该手打的输入：格式歧义多、还容易打错。
                    DatePicker("", selection: $together, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(C.primary)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14))
                    .foregroundStyle(C.danger)
                Text("不上传、不联网，数据只在这台手机上")
                    .font(Typo.caption)
                    .foregroundStyle(C.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(C.warm, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("之后随时能补")
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink2)
                FlowLayout(spacing: 8) {
                    ForEach(["口味与忌口", "纪念日", "雷区", "她的日常"], id: \.self) { t in
                        // 用 `.normal`（浅底无边框）而不是 `.dashed` ——
                        // `.dashed` 在这个 App 里是「＋ 新增」的专属样子，
                        // 这四个只是说明「以后还能补什么」，不是四个可点的入口。
                        Pill(text: t, tiny: true)
                    }
                }
            }
        }
        .padding(.horizontal, S.screen)
        .padding(.top, 26)
        .padding(.bottom, 20)
    }

    // MARK: 16 别错过重要的日子

    private var notify: some View {
        VStack(spacing: 28) {
            VStack(spacing: 28) {
                ZStack {
                    Circle().fill(C.warm).frame(width: 88, height: 88)
                    Image(systemName: "bell")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(C.primary)
                }

                VStack(spacing: 10) {
                    Text("别错过重要的日子")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(C.ink)
                    Text("提醒只在你允许的时候送达，随时能关")
                        .font(Typo.bodyS)
                        .foregroundStyle(C.ink2)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 12) {
                reason("bell", "到点提醒", "纪念日、她的生日，到了那天会叫你")
                reason("mappin.and.ellipse", "场景提醒", "到公司、到家附近时提醒你，最多 20 个地点")
                // 这一条不是客套话，是这个项目的一条红线：iOS 沙盒不允许读第三方聊天内容，
                // 所以情绪判断只能靠用户自己打标。把它印在权限页上，用户才敢点允许。
                reason("lock.shield", "只看你记的", "不读取聊天记录，只提醒你自己写下的内容")
                reason("switch.2", "随时可关", "不想要了，在「设置」里一键停掉")
            }
        }
        .padding(.horizontal, S.screen)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private func reason(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(C.warm).frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(C.primary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(C.ink)
                Text(detail)
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 底部

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: primary) {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(.white) }
                    Text(step == 0 ? "继续" : "允许通知")
                }
                .primaryButtonStyle()
                // 名字是空的就不放行。**不做「跳过」是 15 屏刻意的** ——
                // 但这个按钮也不该看着能按、按了什么都不发生。
                .opacity(step == 0 && !canContinue ? 0.45 : 1)
            }
            .disabled(step == 0 && !canContinue)
            .pressDown()

            if step == 0 {
                Text("下一步：让提醒真的能响起来")
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            } else {
                Button(action: finish) {
                    Text("以后再说，去设置里开")
                        .font(Typo.caption)
                        .foregroundStyle(C.primary)
                }
            }
        }
        .padding(.horizontal, S.screen)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(C.card)
    }

    // MARK: 动作

    /// 15 屏的「继续」。**档案在这一步就落盘**，不是等两屏都走完 ——
    /// 否则用户在 16 屏这里杀掉 App，15 屏填的两项就白填了。
    private func primary() {
        guard step == 0 else {
            Task { await askForNotifications() }
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ctx.insert(Profile(name: trimmed, together: together))
        try? ctx.save()
        withAnimation(.easeOut(duration: 0.22)) { step = 1 }
    }

    /// 16 屏的「允许通知」。
    /// **先落 finish 再弹系统框**：无论用户答应还是拒绝，都该进主界面 ——
    /// 把「拒绝了权限」做成一堵墙，用户会以为这个 App 用不了，然后卸载。
    private func askForNotifications() async {
        working = true
        _ = await ReminderService.shared.requestNotificationPermission()
        working = false
        finish()
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.28)) { finished = true }
    }
}

/// 两屏共用的步骤条。**它存在的意义是告诉用户「只有两步」** ——
/// 让人知道前面还有多少，是愿不愿意走完的前提。
private struct OnboardingSteps: View {
    let step: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? C.primary : C.line2)
                    .frame(width: i <= step ? 22 : 8, height: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, S.screen)
        .padding(.top, 14)
        .animation(.easeOut(duration: 0.22), value: step)
    }
}
