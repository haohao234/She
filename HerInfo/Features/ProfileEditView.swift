//
//  ProfileEditView.swift
//  对应画布 33 编辑她的档案
//
//  这一屏的存在理由是**分批收集**：
//  15 屏第一次只问了「称呼」和「在一起的日子」两件事 —— 问太多人就退出去了。
//  剩下的（头像 / 生日 / 城市 / 一句话）全在这里补。
//  所以它的语气是「随时可以补」，不是「你必须填完」。
//

import SwiftUI
import SwiftData

struct ProfileEditView: View {
    @Binding var path: [Route]

    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]

    @State private var name = ""
    @State private var birthday = Date.now
    @State private var together = Date.now
    @State private var city = ""
    @State private var about = ""
    @State private var loaded = false
    @State private var saved = false

    private var profile: Profile? { profiles.first }

    var body: some View {
        VStack(spacing: 0) {
            // 注意：这一屏没有右侧操作按钮。
            // 删掉原本的「编辑」按钮后，导航行必须左对齐 —— 标题居中会让人以为还有别的操作。
            NavRow("编辑她的档案", onBack: { path.removeLast() })

            ScrollView {
                VStack(alignment: .leading, spacing: S.cardGap) {

                    // 头像。72×72 + 首字兜底 ——
                    // 没设过头像时不显示灰色剪影，而显示她名字的第一个字。
                    SCard(padding: S.cardPadL) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(LinearGradient(colors: [C.primarySoft, C.primaryDeep],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Text(String(name.prefix(1)))
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    // 真机上：PhotosPicker → 存沙盒 → 记 hash
                                } label: {
                                    Text("换一张头像")
                                        .font(Typo.pillSel)
                                        .foregroundStyle(C.primary)
                                }
                                Text("她的照片只存在这台手机上，不会上传")
                                    .font(Typo.caption)
                                    .foregroundStyle(C.ink3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    // 基本信息。四行 key-value，行与行之间用细线分隔。
                    VStack(spacing: 0) {
                        editRow("称呼", text: $name)
                        divider
                        dateRow("生日", date: $birthday)
                        divider
                        dateRow("在一起的日子", date: $together)
                        divider
                        editRow("城市", text: $city)
                    }
                    .background(C.card, in: RoundedRectangle(cornerRadius: R.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: R.card, style: .continuous)
                            .strokeBorder(C.line, lineWidth: 1)
                    )

                    // 一句话
                    FieldBlock(label: "关于她") {
                        SField(placeholder: "一句话就好，不用长",
                               text: $about, multiline: true, height: 88)
                    }

                    // 提示卡。这一句是给「改错了」兜底 ——
                    // 档案是最容易被误改的一块，所以必须有退路。
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundStyle(C.primary)
                        Text("改完会自动存一版历史，随时能翻回旧的样子")
                            .font(Typo.bodyS)
                            .foregroundStyle(C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(C.warm, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
                }
                .padding(.horizontal, S.screen)
                .padding(.vertical, 8)
            }

            VStack(spacing: 0) {
                Rectangle().fill(C.line).frame(height: 1)
                Button(action: save) {
                    Text(saved ? "已保存" : "保存修改")
                        .primaryButtonStyle()
                }
                .disabled(saved)
                .pressDown()
                .padding(.horizontal, S.screen)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(C.card)
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
    }

    private var divider: some View {
        Rectangle().fill(C.line).frame(height: 1).padding(.leading, S.cardPadL)
    }

    /// 可编辑的键值行。值右对齐 —— 和 31 屏的只读键值行视觉一致，
    /// 但这里的值是可点的，所以给了一整块点击区域。
    private func editRow(_ key: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(Typo.bodyS)
                .foregroundStyle(C.ink3)

            Spacer(minLength: 0)

            TextField("未填写", text: text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(C.ink)
                .multilineTextAlignment(.trailing)
                .tint(C.primary)
        }
        .padding(.horizontal, S.cardPadL)
        .padding(.vertical, 15)
    }

    /// 日期行。用 `DatePicker` 而不是文本框 ——
    /// 日期是唯一一类「用户不该手打」的输入：格式歧义多、还容易打错。
    /// `.compact` 样式的值与 key 同一行，视觉上和其它键值行一致。
    private func dateRow(_ key: String, date: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(Typo.bodyS)
                .foregroundStyle(C.ink3)

            Spacer(minLength: 0)

            DatePicker("", selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(C.primary)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .padding(.horizontal, S.cardPadL)
        .padding(.vertical, 11)
    }

    private func load() {
        guard !loaded, let p = profile else { return }
        loaded = true
        name = p.name
        together = p.together
        city = p.city
        about = p.about
        if let b = p.birthday { birthday = b }
    }

    private func save() {
        guard let p = profile else { return }
        p.name = name
        p.together = together
        p.city = city
        p.about = about
        p.birthday = birthday

        // 档案的历史版本（33 屏提示卡承诺的那个机制）。
        //
        // 这里以前有三处是错的，凑在一起的效果是「机制看起来有、其实没有」：
        //   ① 插在 `ctx.save()` **之后** —— 那条快照从来没落过盘；
        //   ② version 写死 1 —— 每次都是「第 1 版」，历史列表看不出先后；
        //   ③ 关联键用 `profile:<名字>` —— 改一次名字就换了一条链，
        //      而「改名字」恰恰是最需要能翻回旧样子的那一次修改。
        // 现在：固定键 `profile`，版本号按已有条数递增。
        let key = "profile"
        let existing = (try? ctx.fetch(FetchDescriptor<Revision>(
            predicate: #Predicate<Revision> { $0.recordID == key })))?.count ?? 0

        ctx.insert(Revision(recordID: key,
                            version: existing + 1,
                            titleSnapshot: name,
                            bodySnapshot: about,
                            // 档案不是四分类里的一条记录，用一个专属标记，
                            // 免得它被当成「喜好」混进分类统计
                            catRaw: "profile"))

        try? ctx.save()
        saved = true
        path.removeLast()
    }
}
