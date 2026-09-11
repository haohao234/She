//
//  EditorView.swift
//  对应画布 03 新增记录 · 自动保存 / 34 记录配图 · 插入照片
//
//  03 与 34 是**同一个编辑器的两种态**：
//  - 新建态（03）：分类 → 标题 → 内容 → 标签 → 提醒开关
//  - 编辑态（34）：在标题下插入**图片**字段，并显示「本地版本 N」
//
//  34 屏那一条最要紧的产品判断是：**图片紧跟标题，不塞在正文下面**。
//  一条「她说想要这个」配上照片，半年后还认得出是哪一款；纯文字不能。
//  所以图片在编辑态里是一等字段，不是附件。
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct RecordEditorView: View {
    @Binding var path: [Route]

    /// 空 = 新建（03），非空 = 编辑（34）
    let editingID: String

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @Query private var existing: [Record]

    @State private var cat: Category = .like
    @State private var title = ""
    @State private var body_ = ""
    @State private var tags: [String] = []
    @State private var photoHashes: [String] = []
    @State private var remindsMe = true
    @State private var version = 1
    @State private var loaded = false
    @State private var saveState: SaveState = .idle

    /// 相册选择器的选中结果。**选完立刻落盘换成 hash，原图不留** ——
    /// 这一层如果留着 PhotosPickerItem，就等于把「原图」带进了数据模型，
    /// 而 PhotosPickerItem 换台设备就失效了，存它没有任何意义。
    @State private var picked: [PhotosPickerItem] = []
    @State private var pickingPhotos = false

    /// 上一次落盘时的内容指纹。**它决定「要不要涨版本」** ——
    /// 没有它的话，点一下输入框再离开也能涨一版，
    /// 31 屏那个「第 12 版」就成了一句没有含义的话。
    @State private var lastSnapshot = ""

    private var isEditing: Bool { !editingID.isEmpty }
    private var record: Record? { existing.first }

    init(path: Binding<[Route]>, editingID: String) {
        self._path = path
        self.editingID = editingID
        // 新建时给一个永不匹配的 id，而不是在 #Predicate 里写分支 ——
        // #Predicate 宏对捕获变量的表达式很挑，用常量最稳。
        let target = editingID.isEmpty ? "\u{0}__new__" : editingID
        _existing = Query(filter: #Predicate<Record> { $0.id == target })
    }

    var body: some View {
        VStack(spacing: 0) {

            // 顶行：取消 / 标题 / 完成
            HStack {
                Button { path.removeLast() } label: {
                    Text("取消")
                        .font(Typo.body)
                        .foregroundStyle(C.ink2)
                        .frame(width: 52, alignment: .leading)
                }
                .pressDown()

                Spacer()
                Text(isEditing ? "编辑记录" : "新建记录")
                    .font(Typo.pageTitle)
                    .foregroundStyle(C.ink)
                Spacer()

                Button { save(); path.removeLast() } label: {
                    Text(isEditing ? "保存" : "完成")
                        .font(Typo.btn)
                        .foregroundStyle(C.primary)
                        .frame(width: 52, alignment: .trailing)
                }
                .pressDown()
            }
            .padding(.horizontal, S.screen)
            .frame(height: 44)

            // 自动保存条。**它是状态条，不是进度条** ——
            // 不说「还差几条」，只回答「我记下来了吗」。记录一旦变成任务就没人愿意记。
            HStack(spacing: 8) {
                Circle()
                    .fill(C.care)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    )
                Text(saveState.label)
                    .font(Typo.numCaption)
                    .foregroundStyle(C.ink2)
                Spacer()
                Text("本地版本 \(version)")
                    .font(Typo.numCaption)
                    .foregroundStyle(C.ink3)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(C.moss, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, S.screen)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    FieldBlock(label: "分类") {
                        ChipRow(options: Category.allCases,
                                label: { $0.title },
                                selection: $cat)
                    }

                    FieldBlock(label: "标题") {
                        SField(placeholder: "比如：喜欢的白玫瑰", text: $title)
                    }

                    // —— 34 屏的图片字段：紧跟标题 ——
                    // 组件只画格子，「从相册取图」这一步归这里 ——
                    // 把 PhotosUI 塞进设计系统会让它绑死一个平台能力。
                    FieldBlock(label: "图片",
                               caption: photoHashes.isEmpty ? nil : "\(photoHashes.count)/\(Photo.maxPerRecord)") {
                        PhotoGrid(hashes: $photoHashes, onAdd: { pickingPhotos = true })
                        Text("长按可以拖动排序 · 最多 \(Photo.maxPerRecord) 张")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                    }

                    FieldBlock(label: "内容") {
                        SField(placeholder: "她怎么说的、当时是什么情况…", text: $body_, multiline: true)
                    }

                    FieldBlock(label: "标签") {
                        FlowLayout(spacing: 8) {
                            ForEach(tags, id: \.self) { t in
                                // 参数顺序必须跟属性声明顺序一致：
                                // Pill 的存储属性是 text / style / tint / soft / tiny / onTap，
                                // 把 tiny 写在 tint 前面是编译不过的（"argument must precede"）。
                                Pill(text: t, tint: C.primary, soft: C.fill, tiny: true)
                            }
                            Pill(text: "＋ 新增标签", style: .dashed) {
                                tags.append("新标签\(tags.count + 1)")
                            }
                        }
                    }

                    // 提醒开关。默认开启 —— 这条记录的价值就在于「合适的时候被想起来」。
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(C.warm).frame(width: 32, height: 32)
                            Image(systemName: "bell")
                                .font(.system(size: 14))
                                .foregroundStyle(C.primary)
                        }
                        Text("记住这件事，合适的时候提醒我")
                            .font(Typo.bodyS)
                            .foregroundStyle(C.ink)
                        Spacer(minLength: 0)
                        SoftSwitch(isOn: $remindsMe)
                    }
                    .padding(14)
                    .background(C.card, in: RoundedRectangle(cornerRadius: R.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: R.input, style: .continuous)
                            .strokeBorder(C.line, lineWidth: 1)
                    )

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(C.ink2)
                        Text(isEditing
                             ? "图片会和记录一起导出，也会出现在档案里"
                             : "内容会自动保存，重复编辑会保留历史版本")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink2)
                    }
                }
                .padding(.horizontal, S.screen)
                .padding(.bottom, 20)
            }

            // 底部保存按钮
            VStack(spacing: 0) {
                Rectangle().fill(C.line).frame(height: 1)
                Button(action: { save(); path.removeLast() }) {
                    Text(isEditing ? "保存记录" : "保存记录")
                        .primaryButtonStyle()
                }
                .pressDown()
                .padding(.horizontal, S.screen)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(C.card)
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadIfNeeded)
        // 自动保存：改动后 0.8s 落一次盘。
        // 用 debounce 而不是每次按键都写 —— 写库太频繁会让打字卡顿。
        .onChange(of: title) { _, _ in scheduleAutoSave() }
        .onChange(of: body_) { _, _ in scheduleAutoSave() }
        .onChange(of: cat) { _, _ in scheduleAutoSave() }
        .onChange(of: photoHashes) { _, _ in scheduleAutoSave() }
        // 相册。**用系统选择器，不自己写一个相册浏览界面** ——
        // 系统选择器只把用户勾中的那几张交给 App，不需要「访问整个相册」的权限。
        // 「她的照片只存在这台手机上，不会上传」这句话能被相信，前提就是这里。
        .photosPicker(isPresented: $pickingPhotos,
                      selection: $picked,
                      maxSelectionCount: max(1, Photo.maxPerRecord - photoHashes.count),
                      matching: .images)
        .onChange(of: picked) { _, items in ingest(items) }
    }

    // MARK: 配图

    /// 把相册里选中的图**落盘成文件**，换回 hash 存进记录。
    ///
    /// 在这段之前，「＋」是往数组里塞一个 `"hash:new0"` 这样的假值：
    /// 界面上看得到格子，磁盘上什么都没有，导出时也带不走一张。
    /// 「配图」那条产品线当时是演出来的。
    ///
    /// 三件事按这个顺序做，缺一件都不成立：
    ///   ① 选中的原图 → 压缩副本（长边 2048 / JPEG 0.82，PhotoStore 里做）
    ///   ② 压缩后的字节算 SHA-256 → 当文件名（内容寻址）
    ///   ③ 只把 hash 存进数组
    @MainActor
    private func ingest(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                guard photoHashes.count < Photo.maxPerRecord else { break }
                // 一张图读不出来就跳过。**不该因为她选的某一张有问题，
                // 连她已经写好的那句话一起存不上。**
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let raw = UIImage(data: data),
                      let hash = await PhotoStore.saveAsync(raw)
                else { continue }
                // 内容寻址：同一张照片再选一次，不会变成两格。
                if !photoHashes.contains(hash) { photoHashes.append(hash) }
            }
            picked = []
        }
    }

    // MARK: 读写

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let r = record else { return }
        cat = r.cat
        title = r.title
        body_ = r.body
        tags = r.tags
        photoHashes = r.photos.sorted { $0.order < $1.order }.map(\.hash)
        remindsMe = r.reminder?.isOn ?? false
        version = r.version
        lastSnapshot = snapshot
    }

    /// 内容指纹。用不可能出现在正文里的控制字符拼接 ——
    /// 用逗号的话「a,b」和「a」+「b」会撞成同一个指纹。
    private var snapshot: String {
        [cat.rawValue, title, body_,
         tags.joined(separator: "\u{1F}"),
         photoHashes.joined(separator: "\u{1F}")]
            .joined(separator: "\u{1E}")
    }

    /// 保存。
    ///
    /// `bump` = 这是自动保存（编辑过程中每停 0.8 秒落一次盘）。
    /// 手动按「保存记录」时传 false —— 手动那一次不该额外再涨一版。
    private func save(bump: Bool = false) {
        let target: Record
        if let r = record {
            target = r
        } else {
            target = Record(cat: cat, title: title, body: body_, tags: tags)
            ctx.insert(target)
        }

        target.cat = cat
        target.title = title
        target.body = body_
        target.tags = tags
        target.updatedAt = .now

        // **只有内容真的变了才涨版本。**
        // 否则点一下输入框再离开就能涨一版，「第 12 版」会变成一句没有含义的话。
        if bump && snapshot != lastSnapshot {
            target.version += 1
            version = target.version
            // 版本快照：恢复 = 新增一条，不覆盖
            ctx.insert(Revision(recordID: target.id,
                                version: target.version,
                                titleSnapshot: title,
                                bodySnapshot: body_,
                                photoHashes: photoHashes,
                                catRaw: cat.rawValue))
        }
        lastSnapshot = snapshot

        // 图片：按数组顺序重排 order，删掉已经不在数组里的
        let keep = Set(photoHashes)
        for p in target.photos where !keep.contains(p.hash) {
            ctx.delete(p)
        }
        for (idx, h) in photoHashes.enumerated() {
            if let p = target.photos.first(where: { $0.hash == h }) {
                p.order = idx
            } else {
                let p = Photo(hash: h, order: idx)
                p.record = target
                ctx.insert(p)
            }
        }

        syncReminder(for: target)
        try? ctx.save()
    }

    /// 提醒开关落到真实的 `Reminder` 上。
    ///
    /// 三种情况要分清，否则会出现「开关看着是开的、其实根本没有提醒」：
    ///   · 打开且已有一条 → 只把开关拨回去（用户之前调好的时间要留着）
    ///   · 打开且还没有   → 建一条默认提醒（每周三 20:00），他去 05 / 32 里再调
    ///   · 关掉           → **只关开关，不删提醒**。删掉的话再打开一次，
    ///                       他上次调好的那个时间就没了 —— 而那个时间才是他在意的
    private func syncReminder(for target: Record) {
        if remindsMe {
            if let m = target.reminder {
                guard !m.isOn else { return }
                m.isOn = true
                Task { await ReminderService.shared.schedule(m) }
            } else {
                let time = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? .now
                let m = Reminder(kind: .date,
                                 title: target.title,
                                 repeatRule: .weekly,
                                 weekday: 4,
                                 time: time,
                                 leadMinutes: 10,
                                 message: target.title.isEmpty ? "该看看这条记录了" : target.title)
                m.record = target
                ctx.insert(m)
                Task { await ReminderService.shared.schedule(m) }
            }
        } else if let m = target.reminder, m.isOn {
            m.isOn = false
            Task { await ReminderService.shared.cancel(m) }
        }
    }

    @State private var saveTask: Task<Void, Never>?

    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveState = .pending
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                save(bump: true)
                saveState = .saved
            }
        }
    }

    enum SaveState {
        case idle, pending, saved
        var label: String {
            switch self {
            case .idle:    return "还没有改动"
            case .pending: return "正在保存…"
            case .saved:   return "已自动保存 · 刚刚"
            }
        }
    }
}
