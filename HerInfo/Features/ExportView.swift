//
//  ExportView.swift
//  对应画布 35 导出档案 · 范围与格式
//
//  三种格式是**三个不同的目的**，所以每一行写「适合什么」而不是只写扩展名：
//    PDF      → 给别人看（打印、发给家人）
//    Markdown → 给自己存（丢进任意笔记软件，能读能改）
//    JSON     → 给下一个手机用（换机恢复，字段完整）
//
//  12 屏那条「导出需要面容 ID」在这里兑现 ——
//  导出是一次性动作，但它带走的是全部记录。这一步值得多挡一下。
//

import SwiftUI
import SwiftData
import LocalAuthentication

struct ExportView: View {
    @Binding var path: [Route]

    @Query(filter: #Predicate<Record> { $0.deletedAt == nil },
           sort: \Record.updatedAt, order: .reverse)
    private var records: [Record]

    /// 历史版本。「包含内容 › 历史版本」这一行以前是个假开关 ——
    /// 它记下了用户的选择，却没有把版本交出去。这里补上。
    @Query private var revisions: [Revision]

    @State private var scope: ExportScope = .all
    @State private var format: ExportFormat = .pdf
    @State private var cat: Category = .like
    @State private var includePhotos = true
    @State private var includeVersions = true
    @State private var includeReminders = false
    @State private var working = false
    @State private var resultURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            NavRow("导出档案", onBack: { path.removeLast() })

            ScrollView {
                VStack(alignment: .leading, spacing: S.cardGap) {

                    // 范围
                    SCard {
                        Text("导出范围")
                            .font(Typo.captionM)
                            .foregroundStyle(C.ink3)

                        radioRow(ExportScope.all,
                                 title: "全部",
                                 detail: "\(records.count) 条")
                        radioRow(ExportScope.category,
                                 title: "按分类",
                                 detail: cat.title)
                        radioRow(ExportScope.withRemind,
                                 title: "只导有提醒的",
                                 detail: "\(records.filter { $0.reminder != nil }.count) 条")

                        if scope == .category {
                            Rectangle().fill(C.line).frame(height: 1)
                            ChipRow(options: Category.allCases,
                                    label: { $0.title },
                                    selection: $cat)
                                .padding(.top, 4)
                        }
                    }

                    // 格式
                    SCard {
                        Text("文件格式")
                            .font(Typo.captionM)
                            .foregroundStyle(C.ink3)

                        ForEach(ExportFormat.allCases) { f in
                            Button { format = f } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    radio(on: format == f)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.title)
                                            .font(Typo.body)
                                            .foregroundStyle(C.ink)
                                        Text(f.detail)
                                            .font(Typo.caption)
                                            .foregroundStyle(C.ink3)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                            }
                            .pressDown()
                        }
                    }

                    // 包含内容
                    SCard {
                        Text("包含内容")
                            .font(Typo.captionM)
                            .foregroundStyle(C.ink3)

                        switchRow("图片", detail: "会明显变大", isOn: $includePhotos)
                        Rectangle().fill(C.line).frame(height: 1)
                        switchRow("历史版本", detail: "每一版的旧正文", isOn: $includeVersions)
                        Rectangle().fill(C.line).frame(height: 1)
                        switchRow("提醒", detail: "导出后不带走提醒设置", isOn: $includeReminders)
                    }

                    // 提示。这句要显式断行 —— 自动折行会把「别等丢了」断在难看的字上。
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 14))
                            .foregroundStyle(C.primary)
                        Text("导出需要过一次面容 ID。\n换手机前先导一份，别等丢了才想起来")
                            .font(Typo.bodyS)
                            .foregroundStyle(C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(C.warm, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))

                    if let url = resultURL {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(C.care)
                            Text("已导出到「文件」：\(url.lastPathComponent)")
                                .font(Typo.caption)
                                .foregroundStyle(C.ink2)
                        }
                    }
                }
                .padding(.horizontal, S.screen)
                .padding(.vertical, 8)
            }

            VStack(spacing: 0) {
                Rectangle().fill(C.line).frame(height: 1)
                Button(action: runExport) {
                    HStack(spacing: 8) {
                        if working { ProgressView().tint(.white) }
                        Text(working ? "正在导出…" : "导出 · \(count) 条")
                    }
                    .primaryButtonStyle()
                }
                .disabled(working)
                .pressDown()
                .padding(.horizontal, S.screen)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(C.card)
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: 小组件

    private func radioRow(_ s: ExportScope, title: String, detail: String) -> some View {
        Button { scope = s } label: {
            HStack(spacing: 10) {
                radio(on: scope == s)
                Text(title)
                    .font(Typo.body)
                    .foregroundStyle(C.ink)
                Spacer(minLength: 0)
                Text(detail)
                    .font(Typo.numCaption)
                    .foregroundStyle(C.ink3)
            }
            .padding(.vertical, 9)
        }
        .pressDown()
    }

    /// 单选圆：选中 = 实心主色 + 白色内点。
    private func radio(on: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(on ? C.primary : C.line2, lineWidth: 1.5)
                .frame(width: 20, height: 20)
            if on {
                Circle().fill(C.primary).frame(width: 20, height: 20)
                Circle().fill(.white).frame(width: 7, height: 7)
            }
        }
    }

    private func switchRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.body)
                    .foregroundStyle(C.ink)
                Text(detail)
                    .font(Typo.caption)
                    .foregroundStyle(C.ink3)
            }
            Spacer(minLength: 0)
            SoftSwitch(isOn: isOn)
        }
        .padding(.vertical, 9)
    }

    // MARK: 逻辑

    private var payload: [Record] {
        switch scope {
        case .all:        return records
        case .category:   return records.filter { $0.cat == cat }
        case .withRemind: return records.filter { $0.reminder != nil }
        }
    }

    private var count: Int { payload.count }

    private func runExport() {
        working = true
        Task {
            // ① 面容 ID 挡一道。「设备无生物识别」时退化到设备密码，
            //    而不是直接放行 —— 放行等于这条提示是假的。
            let ok = await BiometricGate.confirm(reason: "导出她的档案")
            guard ok else { await MainActor.run { working = false }; return }

            // ② 真导出
            let url = try? await ExportService.shared.export(
                payload,
                revisions: revisions,
                format: format,
                includePhotos: includePhotos,
                includeVersions: includeVersions,
                includeReminders: includeReminders
            )

            await MainActor.run {
                resultURL = url
                working = false
            }
        }
    }
}

// MARK: - 枚举

enum ExportScope: String, CaseIterable, Identifiable {
    case all, category, withRemind
    var id: String { rawValue }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, markdown, json
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf:      return "PDF"
        case .markdown: return "Markdown"
        case .json:     return "JSON"
        }
    }

    /// 写「适合什么」，不写扩展名 ——
    /// 用户不关心 .md，用户关心「导出来之后我拿它干什么」。
    var detail: String {
        switch self {
        case .pdf:      return "适合打印或发给别人看，排版固定"
        case .markdown: return "适合丢进笔记软件，以后还能改"
        case .json:     return "适合换手机时导回来，字段最完整"
        }
    }

    var ext: String {
        switch self {
        case .pdf:      return "pdf"
        case .markdown: return "md"
        case .json:     return "json"
        }
    }
}

// MARK: - 生物识别

enum BiometricGate {
    /// 返回是否通过。**取消 / 失败都返回 false**，不静默放行。
    static func confirm(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        // 优先面容 ID，没有则退化到设备密码。
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return false
        }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                              localizedReason: reason)) ?? false
    }
}
