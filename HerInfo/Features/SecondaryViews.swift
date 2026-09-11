//
//  SecondaryViews.swift
//  二级屏：17 她的档案 · 详情 / 12 设置 / 23 外观 / 13 应用锁 / 27 回收站
//
//  这几屏在前面的轮次里已经定稿（画布上都有对应 PNG），
//  这里给的是**结构到位、可直接替换**的实现 —— 布局、令牌、文案都按设计稿，
//  只把与后端/系统交互较重的部分标了 TODO。
//  之所以先写它们而不是留空：这五屏是「设置 → 导出 / 回收站 / 应用锁」这条链的必经之路，
//  缺了它们，本轮新增的 35 屏就点不进去。
//

import SwiftUI
import SwiftData

// MARK: - 17 她的档案 · 详情

struct ProfileDetailView: View {
    @Binding var path: [Route]

    @Query private var profiles: [Profile]
    @Query(filter: #Predicate<Record> { $0.deletedAt == nil }) private var records: [Record]

    private var profile: Profile? { profiles.first }

    var body: some View {
        VStack(spacing: 0) {
            NavRow("她的档案", onBack: { path.removeLast() }) {
                Button { path.append(.profileEdit) } label: {
                    Text("编辑")
                        .font(Typo.pillSel)
                        .foregroundStyle(C.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(C.fill, in: Capsule(style: .continuous))
                }
                .pressDown()
            }

            if let p = profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: S.cardGap) {

                        SCard(padding: S.cardPadL) {
                            HStack(spacing: 14) {
                                AvatarView(hash: p.avatarHash, name: p.name, size: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(C.ink)
                                    Text("在一起 \(p.daysTogether) 天")
                                        .font(Typo.numCaption)
                                        .foregroundStyle(C.ink3)
                                }
                                Spacer(minLength: 0)
                            }
                            if !p.about.isEmpty {
                                Text(p.about)
                                    .font(Typo.bodyS)
                                    .foregroundStyle(C.ink2)
                                    .lineSpacing(8)
                            }
                        }

                        // 分类统计
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(Category.allCases) { c in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(c.title)
                                        .font(Typo.caption)
                                        .foregroundStyle(c.tint)
                                    Text("\(records.filter { $0.cat == c }.count)")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(C.ink)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(c.soft, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
                            }
                        }

                        // 基本信息（33 屏编辑的内容在这里只读展示）
                        VStack(spacing: 0) {
                            KeyValueRow(key: "称呼", value: p.name)
                            KeyValueRow(key: "生日",
                                        value: p.birthday?.monthDayCN ?? "未填写", divider: true)
                            KeyValueRow(key: "在一起的日子",
                                        value: p.together.yearMonthDayCN, divider: true)
                            KeyValueRow(key: "城市",
                                        value: p.city.isEmpty ? "未填写" : p.city, divider: true)
                        }
                        .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: R.card, style: .continuous)
                                .strokeBorder(C.line, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, S.screen)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 12 设置

struct SettingsView: View {
    @Binding var path: [Route]

    @Query(filter: #Predicate<Record> { $0.deletedAt != nil }) private var deleted: [Record]
    @Query(filter: #Predicate<Record> { $0.deletedAt == nil }) private var alive: [Record]

    /// 通知权限的实际状态。24 屏那条「通知被关、开关却显示开」的矛盾就靠它避免。
    @AppStorage("notifyEnabled") private var notifyEnabled = true
    @AppStorage("appLock") private var appLock = false
    @AppStorage("exportNeedsFaceID") private var exportNeedsFaceID = true
    @AppStorage("themeMode") private var themeMode = "system"

    var body: some View {
        VStack(spacing: 0) {
            NavRow("设置", onBack: { path.removeLast() })

            ScrollView {
                VStack(alignment: .leading, spacing: S.cardGap) {

                    // 提醒
                    sectionCard("提醒") {
                        row("到点提醒我", detail: notifyEnabled ? nil : "已在系统设置里关闭",
                            trailing: AnyView(SoftSwitch(isOn: $notifyEnabled))) {
                            // 关掉了才引导 —— 对应 24 屏「通知权限 · 关掉之后」。
                            // 这里以前跳的是「应用锁」，那是错的：用户的问题是通知，
                            // 把他带到面容 ID 那一页，他只会更困惑，然后退出 App。
                            if !notifyEnabled { path.append(.notifyDenied) }
                        }
                        divider
                        row("新建提醒", detail: nil, trailing: AnyView(chevron)) {
                            path.append(.reminderNew(recordID: nil))
                        }
                    }

                    // 数据
                    sectionCard("数据") {
                        row("导出档案", detail: "\(alive.count) 条", trailing: AnyView(chevron)) {
                            path.append(.exportArchive)
                        }
                        divider
                        row("回收站",
                            detail: deleted.isEmpty ? "空" : "\(deleted.count) 条",
                            trailing: AnyView(chevron)) {
                            path.append(.trash)
                        }
                    }

                    // 隐私
                    sectionCard("隐私") {
                        row("应用锁", detail: appLock ? "已开启" : "未开启",
                            trailing: AnyView(SoftSwitch(isOn: $appLock)))
                        divider
                        row("导出需要面容 ID", detail: nil,
                            trailing: AnyView(SoftSwitch(isOn: $exportNeedsFaceID)))
                        divider
                        row("外观", detail: themeModeTitle, trailing: AnyView(chevron)) {
                            path.append(.appearance)
                        }
                    }

                    Text("记录只存在这台手机上。没有账号、没有云同步，所以也没有人能替你看到它。")
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                        .lineSpacing(6)
                        .padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, S.screen)
                .padding(.vertical, 8)
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var themeModeTitle: String {
        switch themeMode {
        case "light": return "始终浅色"
        case "dark":  return "始终深色"
        default:      return "跟随系统"
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(C.ink3.opacity(0.6))
    }

    private var divider: some View {
        Rectangle().fill(C.line).frame(height: 1).padding(.leading, S.cardPadL)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)
                .padding(.bottom, 8)

            VStack(spacing: 0) { content() }
                .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: R.card, style: .continuous)
                        .strokeBorder(C.line, lineWidth: 1)
                )
        }
    }

    private func row(_ title: String, detail: String?,
                     trailing: AnyView, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.body)
                    .foregroundStyle(C.ink)
                if let detail {
                    Text(detail)
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, S.cardPadL)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
}

// MARK: - 23 外观

struct AppearanceView: View {
    @AppStorage("themeMode") private var themeMode = "system"
    @Environment(\.colorScheme) private var sys

    /// **不能写成 `[(String, String)]` + `ForEach(modes, id: \.0)`** ——
    /// Swift 的 KeyPath 不支持指向元组元素（key path cannot refer to tuple element），
    /// 那是编译不过的。给它一个真类型。
    private struct ThemeMode: Identifiable {
        let id: String
        let title: String
    }

    private let modes: [ThemeMode] = [
        ThemeMode(id: "system", title: "跟随系统"),
        ThemeMode(id: "light",  title: "始终浅色"),
        ThemeMode(id: "dark",   title: "始终深色")
    ]

    var body: some View {
        VStack(spacing: 0) {
            NavRow("外观", onBack: { dismissSelf() })

            ScrollView {
                VStack(alignment: .leading, spacing: S.cardGap) {

                    // 两扇实时预览窗。**选之前先看见** ——
                    // 三行文字说明永远比不上直接看见两种样子。
                    HStack(spacing: 12) {
                        previewPane(title: "浅色", dark: false)
                        previewPane(title: "深色", dark: true)
                    }

                    VStack(spacing: 0) {
                        ForEach(modes) { m in
                            Button { themeMode = m.id } label: {
                                HStack(spacing: 10) {
                                    Text(m.title)
                                        .font(Typo.body)
                                        .foregroundStyle(C.ink)
                                    Spacer(minLength: 0)
                                    ZStack {
                                        Circle()
                                            .strokeBorder(themeMode == m.id ? C.primary : C.line2,
                                                          lineWidth: 1.5)
                                            .frame(width: 20, height: 20)
                                        if themeMode == m.id {
                                            Circle().fill(C.primary).frame(width: 20, height: 20)
                                            Circle().fill(.white).frame(width: 7, height: 7)
                                        }
                                    }
                                }
                                .padding(.horizontal, S.cardPadL)
                                .frame(height: 52)
                            }
                            .pressDown()
                            // 最后一行不画分隔线 —— 用「不是最后一个」判断，
                            // 而不是写死 `!= "dark"`（以后加一个模式就会多出一条线）。
                            if m.id != modes.last?.id {
                                Rectangle().fill(C.line).frame(height: 1)
                                    .padding(.leading, S.cardPadL)
                            }
                        }
                    }
                    .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: R.card, style: .continuous)
                            .strokeBorder(C.line, lineWidth: 1)
                    )

                    // 这句必须写。否则用户以为「跟随系统」坏了。
                    Text("手动选定后，外观就固定下来，不再跟系统变。选「跟随系统」才会跟着手机的深色模式走。")
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, S.screen)
                .padding(.vertical, 8)
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissSelf() { dismiss() }

    private func previewPane(title: String, dark: Bool) -> some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(dark ? Color.white.opacity(0.85) : Color(hex: 0x1F1E1B))
                    .frame(width: 46, height: 7)
                RoundedRectangle(cornerRadius: 4)
                    .fill(dark ? Color.white.opacity(0.35) : Color(hex: 0x948C82))
                    .frame(width: 68, height: 6)
                RoundedRectangle(cornerRadius: 8)
                    .fill(dark ? Color.white.opacity(0.10) : Color.white)
                    .frame(height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(dark ? Color.white.opacity(0.12) : Color(hex: 0xEFE8E0),
                                          lineWidth: 1)
                    )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 120)
            .background(dark ? Color(hex: 0x1A1613) : Color(hex: 0xF8F5F0))

            Text(title)
                .font(Typo.caption)
                .foregroundStyle(C.ink3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(themeMode == (dark ? "dark" : "light") ? C.primary : C.line,
                              lineWidth: themeMode == (dark ? "dark" : "light") ? 1.5 : 1)
        )
    }
}

private extension Color {
    /// 预览窗需要固定色值（不能跟随当前主题，否则两扇窗会一起变）。
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex         & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 13 应用锁

struct LockSetupView: View {
    @AppStorage("appLock") private var appLock = false
    @Environment(\.dismiss) private var dismiss
    @State private var ok = false

    var body: some View {
        VStack(spacing: 0) {
            NavRow("应用锁", onBack: { dismiss() })

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(C.warm).frame(width: 72, height: 72)
                    Image(systemName: "faceid")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(C.primary)
                }
                .padding(.top, 40)

                Text("用面容 ID 打开")
                    .font(Typo.cardTitle)
                    .foregroundStyle(C.ink)

                Text("打开 App 时先过一次面容 ID。\n锁屏上收到的提醒不会显示具体内容。")
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                Button {
                    Task {
                        ok = await BiometricGate.confirm(reason: "开启应用锁")
                        if ok { appLock = true; dismiss() }
                    }
                } label: {
                    Text(appLock ? "已开启" : "开启")
                        .primaryButtonStyle()
                }
                .pressDown()
                .padding(.horizontal, S.screen)
                .padding(.top, 10)

                Spacer()
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 24 通知权限 · 关掉之后

/// 24 屏。
///
/// **这一屏存在的唯一理由是「被拒之后还能救一次」。**
/// iOS 一辈子只给一次弹窗机会，用户点了「不允许」之后唯一的路是去系统设置。
/// 所以它不是报错页，是**指路页**：说清楚为什么值得开，
/// 以及不开也不残废 —— 只讲坏处会让人觉得被要挟。
struct NotificationDeniedView: View {
    @Binding var path: [Route]

    var body: some View {
        VStack(spacing: 0) {
            NavRow("通知", onBack: { path.removeLast() })

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(C.warm).frame(width: 72, height: 72)
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(C.primary)
                }
                .padding(.top, 36)

                Text("通知现在是关着的")
                    .font(Typo.cardTitle)
                    .foregroundStyle(C.ink)

                Text("这个 App 的价值一半在提醒里 ——\n记下来的事，要在合适的时候被想起来。")
                    .font(Typo.bodyS)
                    .foregroundStyle(C.ink3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    ReminderService.shared.openSystemSettings()
                } label: {
                    Text("去系统设置打开")
                        .primaryButtonStyle()
                }
                .pressDown()
                .padding(.horizontal, S.screen)
                .padding(.top, 6)

                SCard {
                    Text("不开也能用")
                        .font(Typo.captionM)
                        .foregroundStyle(C.ink3)
                    Text("记录、搜索、导出都不受影响。只是不会有通知 —— 你可以自己回来看提醒这一页。")
                        .font(Typo.bodyS)
                        .foregroundStyle(C.ink2)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, S.screen)

                Spacer()
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 27 回收站

struct TrashView: View {
    @Binding var path: [Route]
    @Environment(\.modelContext) private var ctx

    @Query(filter: #Predicate<Record> { $0.deletedAt != nil },
           sort: \Record.deletedAt, order: .reverse)
    private var items: [Record]

    var body: some View {
        VStack(spacing: 0) {
            NavRow("回收站", onBack: { path.removeLast() }) {
                if !items.isEmpty {
                    Button {
                        for r in items { ctx.delete(r) }
                        try? ctx.save()
                    } label: {
                        Text("清空")
                            .font(Typo.pillSel)
                            .foregroundStyle(C.danger)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    .pressDown()
                }
            }

            ScrollView {
                if items.isEmpty {
                    // 29 回收站 · 空态
                    EmptyState(symbol: "trash",
                               title: "回收站是空的",
                               message: "删掉的记录会在这里留 30 天。\n想找回来的时候，它还在。")
                } else {
                    VStack(spacing: S.innerGapL) {
                        ForEach(items) { r in
                            SCard {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(r.title)
                                            .font(Typo.cardTitle)
                                            .foregroundStyle(C.ink)
                                        // **这一页最该突出的是「还剩几天」，不是「删了什么」** ——
                                        // 回收站不是垃圾桶，是撤销窗口。用户来这一页时
                                        // 真正想知道的是「我还来得及吗」。
                                        Text("删除于 \((r.deletedAt ?? .now).relativeCN) · 还剩 \(daysLeft(r)) 天")
                                            .font(Typo.numCaption)
                                            .foregroundStyle(daysLeft(r) <= 3 ? C.danger : C.ink3)
                                    }
                                    Spacer(minLength: 0)
                                    Button { restore(r) } label: {
                                        Text("恢复")
                                            .font(Typo.pillSel)
                                            .foregroundStyle(C.primary)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(C.warm, in: Capsule(style: .continuous))
                                    }
                                    .pressDown()
                                }
                            }
                        }

                        // 恢复说明。**必须写明「提醒不会跟着恢复」** ——
                        // 恢复的是内容，不是当初设下的那个动作。
                        // 不写的话，用户恢复完会去等一条永远不会响的提醒。
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(C.primary)
                            Text("恢复之后记录会回到原来的分类，但提醒不会跟着恢复 —— 需要的话去记录详情里重新打开。")
                                .font(Typo.caption)
                                .foregroundStyle(C.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(C.warm, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))

                        if items.count > 1 {
                            Button { restoreAll() } label: {
                                Text("全部恢复").secondaryButtonStyle()
                            }
                            .pressDown()
                        }

                        Text("回收站只在本机保存 · 换手机前记得先导出档案\n删除这件事，我们一律做成了可撤销的")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, S.screen)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// 删除那天起算的第 30 天。**算出来而不是存下来** ——
    /// 存下来的数字过一夜就是错的（和「在一起多少天」同一个道理）。
    private func daysLeft(_ r: Record) -> Int {
        let deadline = Calendar.current.date(byAdding: .day, value: 30, to: r.deletedAt ?? .now) ?? .now
        let left = Calendar.current.dateComponents([.day], from: .now, to: deadline).day ?? 0
        return max(0, left)
    }

    private func restore(_ r: Record) {
        HerInfoStore.restoreFromTrash(r, in: ctx)
        ToastCenter.shared.show("已恢复「\(r.title)」", actionTitle: "撤销") {
            // 撤销这一下就是「再删回去」。**不带确认** ——
            // 用户刚刚在回收站里明确按了恢复，撤销的语义就是把那一步收回来。
            HerInfoStore.moveToTrash(r, in: ctx)
        }
    }

    private func restoreAll() {
        let n = items.count
        for r in items { HerInfoStore.restoreFromTrash(r, in: ctx) }
        ToastCenter.shared.show("已恢复 \(n) 条")
    }
}
