//
//  EditorView.swift
//  对应画布 03 新增记录 · 自动保存 / 34 记录配图 · 插入照片
//           / 21 首条记录引导 · 带引导的编辑器
//
//  03 / 34 / 21 是**同一个编辑器的三种态**：
//  - 新建态（03）：分类 → 标题 → 图片 → 内容 → 标签 → 提醒开关
//  - 编辑态（34）：字段与新建态完全相同，另显示「本地版本 N」
//  - 引导态（21）：分类 / 标题 / 标签预填好，内容留白只给示范，
//                   状态条换成「起手引导 · 标题已帮你填好」+「换一题」
//
//  **三态的字段表是同一张**（2026-09-14 起）。
//  图片那一栏原来是编辑态独有的 —— 当时的意思是「新建时先把话记下来，
//  照片之后回来补」。用户明确要「新建时也能直接加图」，于是拆掉了那层门。
//  拆掉之后这一屏只有**一张**字段表，不再是「新建少一栏」的两套。
//
//  34 屏那一条最要紧的产品判断是：**图片紧跟标题，不塞在正文下面**。
//  一条「她说想要这个」配上照片，半年后还认得出是哪一款；纯文字不能。
//  所以图片是一等字段，不是附件 —— 这条与「新建时能不能加图」无关，两者不冲突。
//
//  21 屏那一条是：**引导只做「填一半」，不做「替你写」**。
//  真正拦住新用户的是「不知道写什么」，所以标题替他定了；
//  而正文一个字都不预填 —— 填了他会以为那是标准答案，然后删掉重写。
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct RecordEditorView: View {
    @Binding var path: [Route]

    /// 空 = 新建（03），非空 = 编辑（34）
    let editingID: String

    /// 非空 = 21 屏的起手引导态。**它只在新建时才有意义** ——
    /// 编辑一条已有的记录时不该再问「要不要换一题」。
    let starterID: String

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

    /// 当前这一题。`nil` = 不是引导态 → 状态条显示自动保存状态。
    @State private var starter: StarterTopic?

    /// 相册选择器的选中结果。**选完立刻落盘换成 hash，原图不留** ——
    /// 这一层如果留着 PhotosPickerItem，就等于把「原图」带进了数据模型，
    /// 而 PhotosPickerItem 换台设备就失效了，存它没有任何意义。
    @State private var picked: [PhotosPickerItem] = []
    @State private var pickingPhotos = false

    /// 正在导入。**一次只跑一批。**
    ///
    /// 上一批还在读相册（iCloud 里的图要现下载，可能好几秒），用户又点了一次「＋」，
    /// 两批就会交叉：先结束的那批会把 `picked` 清成空数组，
    /// 把后选的那张从选择结果里直接抹掉 —— 界面上的表现是「选了，但没进来」。
    @State private var importing = false

    /// 上一次落盘时的内容指纹。**它决定「要不要涨版本」** ——
    /// 没有它的话，点一下输入框再离开也能涨一版，
    /// 31 屏那个「第 12 版」就成了一句没有含义的话。
    @State private var lastSnapshot = ""

    /// 新建时真正落盘出来的那一条。**必须自己拿着它。**
    ///
    /// `@Query` 的谓词在 `init` 里就定死了 —— 新建时用的是哨兵 id
    /// `"\u{0}__new__"`（为了绕开 `#Predicate` 捕获变量的限制），
    /// 而 `Record.newID()` 生成的是随机 id。**两者永远不会相等**，
    /// 所以新插入的记录不会出现在 `existing` 里，`record` 会一直是 nil。
    ///
    /// 后果是：每改一次内容都走「新建」分支 → 每 0.8 秒的自动保存都再插一条。
    /// 打字慢一点，列表里就会出现好几条几乎一样的记录。
    /// 自己拿着这条引用，「新建」只会发生一次。
    @State private var created: Record?

    private var isEditing: Bool { !editingID.isEmpty }
    private var record: Record? { created ?? existing.first }

    init(path: Binding<[Route]>, editingID: String, starterID: String) {
        self._path = path
        self.editingID = editingID
        self.starterID = starterID
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

                Button { saveAndLeave() } label: {
                    Text(isEditing ? "保存" : "完成")
                        .font(Typo.btn)
                        .foregroundStyle(C.primary)
                        .frame(width: 52, alignment: .trailing)
                }
                .pressDown()
            }
            .padding(.horizontal, S.screen)
            .frame(height: 44)

            // 状态条。**它是状态条，不是进度条** ——
            // 不说「还差几条」，只回答「我记下来了吗」。记录一旦变成任务就没人愿意记。
            //
            // 21 屏的引导态换成 StarterHintBar（见 StarterPrompts.swift）：
            // 两条讲的都是「现在是什么情况」，叠在一起就是一个没人读的双行状态区，
            // 而这一屏真正要说清楚的只有一件事 —— 标题是替你填的，可以换。
            Group {
                if let starter {
                    StarterHintBar(topic: starter) { shuffleStarter() }
                } else {
                    autoSaveBar
                }
            }
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

                    // —— 图片字段：紧跟标题 ——
                    // 组件只画格子，「从相册取图」这一步归这里 ——
                    // 把 PhotosUI 塞进设计系统会让它绑死一个平台能力。
                    //
                    // **三态都显示这一栏**（03 新建 / 21 起手引导 / 34 编辑）。
                    //
                    // 这里原来套着 `if isEditing`：新建时先把话记下来，照片是之后
                    // 从详情页点「编辑」回来补的。那是**刻意的**，不是漏写 ——
                    // 当时的理由是「新记录没人会一步把图也配好」，少一栏能让新建更快。
                    //
                    // 2026-09-14 用户明确要「新建时也能直接加图」，于是去掉这个分支。
                    // 去掉之后三态的字段顺序终于完全一样（分类 → 标题 → 图片 → 内容 →
                    // 标签 → 提醒），同一屏的三种态不再各有一套字段表 —— 对实现和
                    // 对用户都是更简单的那一边：他在 34 学会的位置，回到 03 依然成立。
                    //
                    // 图片紧跟标题、不塞在正文下面，这条不变：
                    // 一条「她说想要这个」配上照片，半年后还认得出是哪一款；纯文字不能。
                    FieldBlock(label: "图片",
                               caption: photoHashes.isEmpty ? nil : "\(photoHashes.count)/\(Photo.maxPerRecord)") {
                        PhotoGrid(hashes: $photoHashes, onAdd: { pickingPhotos = true })
                        Text("长按可以拖动排序 · 最多 \(Photo.maxPerRecord) 张")
                            .font(Typo.caption)
                            .foregroundStyle(C.ink3)
                    }

                    FieldBlock(label: "内容") {
                        // 21 屏那个「只给一条示范」就落在这里：
                        // 它是 **placeholder**，不是预填值 —— 正文一格是空的。
                        SField(placeholder: starter?.placeholder ?? "她怎么说的、当时是什么情况…",
                               text: $body_,
                               multiline: true)
                    }

                    FieldBlock(label: "标签") {
                        FlowLayout(spacing: 8) {
                            ForEach(tags, id: \.self) { t in
                                // 参数顺序必须跟属性声明顺序一致：
                                // Pill 的存储属性是 text / style / tint / soft / tiny / onTap，
                                // 把 tiny 写在 tint 前面是编译不过的（"argument must precede"）。
                                Pill(text: t, tint: C.primary, soft: C.fill, tiny: true)
                            }
                            Pill(text: "＋ 新增标签", style: .dashed) { addTag() }
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
                        // 脚注的判据从「是不是编辑态」改成了「现在有没有图」。
                        //
                        // 条件写成 `photoHashes.isEmpty && !isEditing` 而不是逐一罗列四种
                        // 组合，是为了**让画布上已有的那两句一个字都不动**：
                        //   34（编辑态）→ 「图片会和记录一起导出，也会出现在档案里」；
                        //   03（新建 · 无图）→ 「内容会自动保存，重复编辑会保留历史版本」。
                        // 三态合一之后多出来的那个新状态（新建 · 有图）走前一句 ——
                        // 图确实会跟着记录导出、也确实会出现在档案里，说明书上的话直接适用，
                        // 不必为它单造一句新文案。
                        Text(photoHashes.isEmpty && !isEditing
                             ? "内容会自动保存，重复编辑会保留历史版本"
                             : "图片会和记录一起导出，也会出现在档案里")
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
                Button(action: { saveAndLeave() }) {
                    Text("保存记录")
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
        // 08 屏 · 键盘工具栏（见文件末尾的 KeyboardActionBar）。
        // **必须挂在 `placement: .keyboard` 上**，不能自己画一条钉在屏幕底部。
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                KeyboardActionBar(category: cat,
                                  reminderOn: remindsMe,
                                  onPick: { cat = $0 },
                                  onTag: { addTag() },
                                  onReminder: { remindsMe.toggle() })
            }
        }
        .onAppear(perform: loadIfNeeded)
        // 自动保存：改动后 0.8s 落一次盘。
        // 用 debounce 而不是每次按键都写 —— 写库太频繁会让打字卡顿。
        .onChange(of: title) { _, _ in scheduleAutoSave() }
        .onChange(of: body_) { _, _ in scheduleAutoSave() }
        .onChange(of: cat) { _, _ in scheduleAutoSave() }
        .onChange(of: photoHashes) { _, _ in scheduleAutoSave() }
        // 提醒开关也要落盘。**这一条是 08 屏带进来的** ——
        // 工具栏上那枚「提醒」把拨开关这个动作挪到了键盘上方，
        // 拨完接着打字才落盘、拨完直接退就丢，那这个入口就是假的。
        // 内容区那个 SoftSwitch 走同一条路径，两处永远一致。
        .onChange(of: remindsMe) { _, _ in scheduleAutoSave() }
        // 相册。**用系统选择器，不自己写一个相册浏览界面** ——
        // 系统选择器只把用户勾中的那几张交给 App，不需要「访问整个相册」的权限。
        // 「她的照片只存在这台手机上，不会上传」这句话能被相信，前提就是这里。
        .photosPicker(isPresented: $pickingPhotos,
                      selection: $picked,
                      maxSelectionCount: max(1, Photo.maxPerRecord - photoHashes.count),
                      matching: .images)
        .onChange(of: picked) { _, items in ingest(items) }
    }

    /// 03 / 34 那条状态条。抽出来只是因为 21 屏要把它整条换掉（见上面 body 里的 Group）。
    @ViewBuilder
    private var autoSaveBar: some View {
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
    }

    /// 新增一个标签。
    /// **内容区那颗「＋ 新增标签」与键盘工具栏上那枚「标签」共用它** ——
    /// 两处各写一遍 `tags.append(…)`，将来改命名规则就会只改一处。
    private func addTag() {
        tags.append("新标签\(tags.count + 1)")
    }

    // MARK: 21 屏 · 起手引导

    /// 把一题「填一半」落到字段上。
    ///
    /// **`body_` 一定是空的。** 这一条是这个功能成立与否的关键：
    /// 预填正文等于替用户写了答案，他会以为「原来要这么写」，
    /// 然后要么照抄，要么删干净重来 —— 两种都比空白更费事。
    /// 所以这里只搬「选」的字段（分类 / 标签），加一个替他定好的标题。
    private func applyStarter(_ topic: StarterTopic) {
        cat = topic.cat
        title = topic.title
        tags = topic.tags
        body_ = ""
        remindsMe = true
    }

    /// 「换一题」。
    ///
    /// 三条边界，都是「用户已经动过的东西不碰」：
    ///   · 标题 —— 只在**他没改过**的时候跟着换。他已经自己起了一个名字，
    ///            说明他不在用这题了，这时候覆盖他等于把他刚写的字删了。
    ///   · 分类 / 标签 —— 跟着换。它们是「替他选」的字段，且换完在屏幕上看得见，
    ///                   随时可以点回去。
    ///   · 正文 —— **永远不碰**。他可能已经写了两行，换题不该让那些字消失。
    private func shuffleStarter() {
        guard let cur = starter else { return }
        let nxt = cur.next
        let titleUntouched = title == cur.title
        starter = nxt
        if titleUntouched { title = nxt.title }
        cat = nxt.cat
        tags = nxt.tags
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
    ///
    /// **这里不再构造 `UIImage`。** 以前是
    /// `UIImage(data:) → PhotoStore.saveAsync(raw)`，看似没问题 ——
    /// 但 `UIImage(data:)` 是懒解码，真正把一张 48MP 原图解成位图（≈195MB）
    /// 发生在 `PhotoStore` 里那句 `draw` 上。改成直接把原始 `Data` 交给
    /// `PhotoStore` 之后，解码由 ImageIO 的缩略图接口只做长边 ≤ 2048 那一份。
    /// 这一段是「导入失败然后闪退」的现场，理由写在 `PhotoStore` 文件头。
    @MainActor
    private func ingest(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        // 正在导入时把这一批退回去，并清掉选择态 ——
        // 留着的话相册那边会显示「已选中」，而这里永远不会处理它。
        guard !importing else { picked = []; return }
        importing = true

        Task {
            // 数一下有几张没读出来。以前是**完全安静地跳过**：
            // 格子不出现、也没有任何解释，看起来就是「点了没反应」。
            var failed = 0

            for item in items {
                guard photoHashes.count < Photo.maxPerRecord else { break }

                // 一张图读不出来就跳过。**不该因为她选的某一张有问题，
                // 连她已经写好的那句话一起存不上。**
                guard let data = try? await item.loadTransferable(type: Data.self),
                      !data.isEmpty,
                      let hash = await PhotoStore.saveAsync(data)
                else { failed += 1; continue }

                // 内容寻址：同一张照片再选一次，不会变成两格。
                if !photoHashes.contains(hash) { photoHashes.append(hash) }
            }

            picked = []
            importing = false

            // 说不出来由的失败最像 bug。这里只讲事实、给一个能做的动作，
            // 不报错码、不说「请重试」，也不拦着用户接着用。
            if failed > 0 {
                ToastCenter.shared.show(failed == items.count
                                        ? "这张图没能读出来，换一张试试"
                                        : "有 \(failed) 张没能读出来，其余已经加进去了")
            }
        }
    }

    // MARK: 读写

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        if let r = record {
            cat = r.cat
            title = r.title
            body_ = r.body
            tags = r.tags
            photoHashes = Photo.uniqueHashes(r.photos.sorted { $0.order < $1.order }.map(\.hash))
            remindsMe = r.reminder?.isOn ?? false
            version = r.version
            lastSnapshot = snapshot
            return
        }

        // 新建 + 带起手题（21 屏）。
        // 放在这里而不是 init 里：`@State` 的初始值在 init 里赋值会被
        // SwiftUI 在首次 body 求值后覆盖掉，只有 onAppear 之后写才留得住。
        if !starterID.isEmpty {
            let t = StarterTopic.from(starterID)
            starter = t
            applyStarter(t)
        }

        // **「刚打开时的样子」也要记成基线**（新建态尤其重要）。
        // `save` 拿它当「用户到底写没写东西」的判据 —— 见下面的 guard。
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
            // **新建时，「和刚打开时一模一样」就不建记录。**
            //
            // 这条守卫是 21 屏带进来的：起手引导会**预填**标题（「她爱吃什么」），
            // 而预填会触发 onChange → 0.8 秒后自动落盘 → 列表里凭空多出一条
            // 标题是「她爱吃什么」、正文空白的记录。
            // 它不是用户记的，是 App 自己写的。用户点开起手卡又退出去，
            // 结果多了一条记录 —— 这种 bug 看起来完全不像 bug，只会让人困惑。
            //
            // 判据复用 `lastSnapshot`（它在 `loadIfNeeded` 末尾被设成初始态）：
            // 内容跟初始态一致 = 用户一个字都没写。
            guard snapshot != lastSnapshot else { return }
            let fresh = Record(cat: cat, title: title, body: body_, tags: tags)
            ctx.insert(fresh)
            created = fresh
            target = fresh
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
            // `!p.isDeleted` 那一句不能省。
            // `ctx.delete(p)` 只是**登记**删除，`target.photos` 要到下一次 save
            // 之后才会真的少掉这一条 —— 于是这个 `first(where:)` 有可能捞回一个
            // 刚刚在上一个循环里被登记删除的对象。往它身上写 `order`，
            // SwiftData 会直接 fatalError（"model instance was invalidated…"），
            // 表现就是「删掉一张图再保存 → 闪退」。
            // 判成「没找到」之后会走下面的 else 插一条新的，行为也是对的。
            if let p = target.photos.first(where: { $0.hash == h && !$0.isDeleted }) {
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

    /// 手动保存：落盘 → 回上一屏 → 一条带「已记下什么」的轻提示（22 屏）。
    ///
    /// **提示只说「已记下什么」**，不报条数、不问评分、不提示「还差几条」——
    /// 记录这件事一旦变成任务进度，就没人愿意记了。这也是它 3 秒就走的原因：
    /// 它不是确认框，是一条通知。
    ///
    /// 只有手动保存才弹。自动保存每 0.8 秒就可能落一次盘，
    /// 那个路径上弹提示会把屏幕变成闪光灯。
    private func saveAndLeave() {
        // 什么都没写就按「保存记录」（21 屏起手卡点进来又直接退出，最容易走到这里）——
        // 上面 `save` 会拒绝新建，于是**既不该留下记录，也不该弹提示**。
        // 弹「已记下」是在说一句假话：用户什么都没记。
        let willRecord = record != nil || snapshot != lastSnapshot

        save()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        path.removeLast()

        guard willRecord else { return }
        ToastCenter.shared.show(t.isEmpty ? "已记下" : "已记下「\(t)」")
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

// MARK: - 08 屏 · 键盘工具栏

/// 键盘上方那一条。
///
/// **它只存在于键盘弹起的时候，所以只能挂在 `placement: .keyboard` 上。**
/// 原型说明把这件事讲得很准：「工具栏是键盘的附属条，不占用页面纵向空间，
/// 真机上它随键盘一起升降，不需要单独控制显隐」。自己画一条钉在屏幕底部的话，
/// 键盘一收起就会留下一条孤零零的空条 —— 那正是 08 屏想避免的。
///
/// 装的是「键盘弹起来之后够不到的那几个字段」：08 屏的内容区里，
/// 「记住这件事，合适的时候提醒我」那一行正好被键盘顶出可视区，
/// 这就是工具栏里要有一枚「提醒」的原因 —— 它不是快捷方式，是**唯一的入口**。
///
/// **字号用 12 不用画布的 11。** 画布那 11px 是为了让四枚胶囊在 375 宽里挤得下
/// （四枚 + gap 8 + 左右各 20 正好占满）；真机键盘工具栏的宽度够，
/// 就回到全 App 所有胶囊统一的 `Typo.pill`。落地差异，design 稿见 08 屏。
///
/// **画布上还有第四枚「记录时间」，这里刻意没做。** 它不是漏了：
/// 数据模型里只有 `createdAt` / `updatedAt`（记录什么时候被写下），
/// 没有「这件事是什么时候发生的」这个字段，03 / 08 两屏的字段区里也都没有它。
/// 补这一枚要先定义那个字段 —— 它会牵动导出、版本快照与通知契约三处。
/// **留一个点了没反应的胶囊，比少一个更糟**（08 屏那条「工具栏不占纵向空间」
/// 的判断是同一个道理：不承诺不存在的交互）。
private struct KeyboardActionBar: View {

    let category: Category
    let reminderOn: Bool
    let onPick: (Category) -> Void
    let onTag: () -> Void
    let onReminder: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 第一枚是「软选中」：warm 底 + 主色字。
            // 它和内容区那排分类胶囊（`.selected` = 实心主色 + 白字）**不是同一个态** ——
            // 这里陈述的只是「当前是什么」，不是「你正在选什么」。
            // 做成实心会让人以为键盘上还挂着一个等着被确认的选项。
            Menu {
                ForEach(Category.allCases, id: \.self) { c in
                    Button(c.title) { onPick(c) }
                }
            } label: {
                chip("分类 · \(category.title)", soft: true)
            }

            Button { onTag() } label: { chip("标签") }
                .buttonStyle(.plain)

            Button { onReminder() } label: {
                chip(reminderOn ? "提醒 · 开" : "提醒 · 关")
            }
            .buttonStyle(.plain)
        }
    }

    private func chip(_ text: String, soft: Bool = false) -> some View {
        Text(text)
            .font(soft ? Typo.pillSel : Typo.pill)
            .foregroundStyle(soft ? C.primary : C.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(soft ? C.warm : C.card, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(soft ? Color.clear : C.line2, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
    }
}
