//
//  VersionHistoryView.swift
//  对应画布 07 历史版本 · 左右对比
//
//  这一屏要回答的是「我上次改了什么」，不是「一共有几版」——
//  后者一个数字就够了，而数字帮不了任何一个想回到上一版的用户。
//
//  三条产品判断：
//
//  1. **一退一进。** 旧版那块往背景里退（更浅的底 + 更淡的字），
//     新版那块往前跳（高亮底 + 主色字）。两边都加重，就分不出哪边是新的了。
//
//  2. **恢复不是回滚，是「把旧内容写成一个新版本」。**
//     页脚那句「恢复会新增一个版本，当前内容不会丢失」不是安慰话 ——
//     它就是实现方式。少了这句话，没人敢按那个按钮。
//
//  3. **只有差异行配高亮。** 两边都有的那几行照常显示，
//     全都标成差异等于没有重点。
//
//  对比区的模型是「**当前版 vs 某个历史版**」：右边永远是当前版，
//  左版由用户在「全部版本」里挑。这一屏的任务就是让用户挑一版跟现在比，
//  再决定要不要回到它 —— 所以列表点的是**左边**那版，不是右边。
//

import SwiftUI
import SwiftData

struct VersionHistoryView: View {
    @Binding var path: [Route]
    let recordID: String

    @Environment(\.modelContext) private var ctx
    @Query private var records: [Record]
    @Query private var revisions: [Revision]

    /// 用户挑出来对比的那一版（显示在左边）。0 = 还没挑过，用默认值。
    @State private var comparing = 0

    init(path: Binding<[Route]>, recordID: String) {
        self._path = path
        self.recordID = recordID
        // 与 31 详情页同一写法：谓词里只放常量，不捕获变量。
        _records = Query(filter: #Predicate<Record> { $0.id == recordID })
    }

    private var record: Record? { records.first }

    /// 新 → 旧。
    private var versions: [Revision] {
        revisions.filter { $0.recordID == recordID }.sorted { $0.version > $1.version }
    }

    private var current: Revision? { versions.first }

    /// 左边那版。默认取「当前版的前一版」——
    /// 用户进这一屏，十次有九次就是想把刚才那次改动撤回去。
    private var target: Revision? {
        if comparing > 0,
           let v = versions.first(where: { $0.version == comparing }),
           v.version != current?.version {
            return v
        }
        return versions.dropFirst().first
    }

    var body: some View {
        VStack(spacing: 0) {
            NavRow("版本历史", onBack: { path.removeLast() }) {
                Text("共 \(versions.count) 个版本")
                    .font(Typo.numCaption)
                    .foregroundStyle(C.ink3)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: S.cardGap) {
                    if let r = record {
                        titleBlock(r)
                    }

                    if let c = current, let t = target {
                        compare(t, c)
                        changeNote(from: t, to: c)
                        restoreBlock(t)
                    } else if current != nil {
                        // 只有一版。**这不是错误，是起点** ——
                        // 用「还没有可对比的旧版本」而不是「暂无数据」。
                        //
                        // 这里写成 `current != nil` 而不是 `let c = current`：
                        // 这个分支只判断「有没有一版」，并不用那一版本身，
                        // 绑定一个不用的变量会被编译器报
                        // 「value 'c' was defined but never used」。
                        // 那条警告从这一屏建起来就在，直到第 25 轮才被发现 ——
                        // 因为在那之前只看 CI 是不是绿的，没看它数出来的条数。
                        SCard {
                            Text("这是第一版")
                                .font(Typo.cardTitle)
                                .foregroundStyle(C.ink)
                            Text("再编辑几次，这里就会出现可以左右对比的历史版本。")
                                .font(Typo.caption)
                                .foregroundStyle(C.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if versions.count > 1 {
                        allVersions
                    }

                    Text("最近 30 天的版本会一直保留，重要内容建议开启云同步")
                        .font(Typo.caption)
                        .foregroundStyle(C.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, S.screen)
                .padding(.vertical, 8)
            }
        }
        .background(C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - 记录标题块（告诉用户这是哪条记录的版本史）

    private func titleBlock(_ r: Record) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 分类标记：和详情页 `3:334` 同一个样子 —— 实心分类色 + 白字、10 号 Medium。
            // 顺序要跟 Pill 的存储属性一致（text / style / tint / soft / size / emphasis / textTint / onTap）。
            Pill(text: r.cat.title, style: .selected,
                 tint: r.cat.tint, size: .tag)
            Text(r.title)
                .font(Typo.cardTitle)
                .foregroundStyle(C.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 左右对比

    private func compare(_ old: Revision, _ new: Revision) -> some View {
        let d = diff(old.bodySnapshot, new.bodySnapshot)
        return HStack(alignment: .top, spacing: 10) {
            VersionCard(side: .old,
                        title: "版本 \(old.version)",
                        stamp: "\(old.at.monthDayCN) \(old.at.hhmm)",
                        common: d.common, changed: d.removed)
            VersionCard(side: .new,
                        title: "版本 \(new.version) · 当前",
                        stamp: "\(new.at.monthDayCN) \(new.at.hhmm)",
                        common: d.common, changed: d.added)
        }
    }

    // MARK: - 改动说明

    private func changeNote(from old: Revision, to new: Revision) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(C.primary)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            Text(summary(from: old, to: new))
                .font(Typo.pill)
                .foregroundStyle(C.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(C.line, lineWidth: 1)
        )
    }

    // MARK: - 恢复

    private func restoreBlock(_ t: Revision) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { restore(to: t) } label: {
                Text("恢复到第 \(t.version) 版")
                    .font(Typo.btn)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(C.primary, in: Capsule(style: .continuous))
            }
            .pressDown()

            // 这句是这一屏的定心丸：不写清「当前内容不会丢」，没人敢按上面那个按钮。
            Text("恢复会新增一个版本，当前内容不会丢失")
                .font(Typo.caption)
                .foregroundStyle(C.ink3)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - 全部版本

    private var allVersions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("全部版本 · 由自动保存生成")
                .font(Typo.captionM)
                .foregroundStyle(C.ink3)

            VStack(spacing: 8) {
                ForEach(versions) { v in
                    versionRow(v)
                }
            }
        }
    }

    private func versionRow(_ v: Revision) -> some View {
        let isCurrent = v.version == current?.version
        let isComparing = v.version == target?.version
        return Button {
            // 点当前版 = 取消挑选，回到默认的「当前版的前一版」。
            comparing = isCurrent ? 0 : v.version
        } label: {
            HStack(spacing: 10) {
                Text(isCurrent ? "版本 \(v.version) · 当前" : "版本 \(v.version)")
                    .font(Typo.pillSel)
                    .foregroundStyle(isCurrent || isComparing ? C.ink : C.ink2)
                Spacer(minLength: 8)
                Text("\(v.at.monthDayCN) \(v.at.hhmm)")
                    .font(Typo.numCaption)
                    .foregroundStyle(C.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isComparing ? C.hiBg : C.line,
                                  lineWidth: isComparing ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .pressDown()
    }

    // MARK: - 恢复动作

    /// **恢复 = 把一个旧快照写成新版本**，不是把记录退回去。
    ///
    /// 页脚那句承诺就是这个实现：先把旧内容落成 `version + 1`，
    /// 于是「恢复前的内容」原封不动留在历史里 —— 恢复本身也是可逆的。
    /// 如果实现成「删掉后面几版」，那句承诺就成了一句假话。
    private func restore(to v: Revision) {
        guard let r = record else { return }
        let before = r.version

        r.cat = Category(rawValue: v.catRaw) ?? r.cat
        r.title = v.titleSnapshot
        r.body = v.bodySnapshot
        r.updatedAt = .now
        r.version += 1
        ctx.insert(Revision(recordID: r.id,
                            version: r.version,
                            titleSnapshot: v.titleSnapshot,
                            bodySnapshot: v.bodySnapshot,
                            photoHashes: v.photoHashes,
                            catRaw: v.catRaw))

        // 配图跟着快照走。**只改 Photo 行，不碰文件** ——
        // 被移出的图可能还被更早的版本引用着，删文件是启动时孤儿清理的事。
        let keep = Set(v.photoHashes)
        for p in r.photos where !keep.contains(p.hash) {
            ctx.delete(p)
        }
        for (idx, h) in v.photoHashes.enumerated() {
            // `!p.isDeleted` 与 34 屏 `RecordEditorView.save` 里那一处是同一个理由：
            // `ctx.delete(p)` 只是登记删除，上面的 `r.photos` 要到下一次 save
            // 才会真的少掉这一条 —— 这个 `first(where:)` 可能捞回一个刚被登记
            // 删除的对象，往它身上写 `order` 会让 SwiftData 直接 fatalError。
            if let p = r.photos.first(where: { $0.hash == h && !$0.isDeleted }) {
                p.order = idx
            } else {
                let p = Photo(hash: h, order: idx)
                p.record = r
                ctx.insert(p)
            }
        }

        try? ctx.save()
        comparing = 0

        ToastCenter.shared.show("已回到第 \(v.version) 版的内容 · 现在是第 \(r.version) 版",
                                actionTitle: "撤销") {
            // 撤销不走特殊通道 —— 它就是「再把恢复前的那一版恢复一次」。
            // 版本号会再 +1，这是诚实的：内容确实又变了一次，
            // 而这个 App 的规矩是每次改动都留痕，不给撤销开后门。
            if let prev = versions.first(where: { $0.version == before }) {
                restore(to: prev)
            }
        }
    }

    // MARK: - 差异计算

    /// 行级差异。用「计数池」而不是最长公共子序列：
    /// 一条记录原本就是几行字、顺序不会乱跳，计数池能正确处理重复行，
    /// 也不会像 LCS 那样把「一句被改写」报成「删一行 + 加一行」两处噪声。
    private func diff(_ old: String, _ new: String)
        -> (common: [String], removed: [String], added: [String]) {

        let oldLines = lines(of: old)
        let newLines = lines(of: new)

        var pool: [String: Int] = [:]
        for l in oldLines { pool[l, default: 0] += 1 }

        var common: [String] = []
        var added: [String] = []
        for l in newLines {
            if let n = pool[l], n > 0 {
                pool[l] = n - 1
                common.append(l)
            } else {
                added.append(l)
            }
        }

        // 池子里没被消耗掉的，就是只在旧版里出现过的行。
        var removed: [String] = []
        var left = pool
        for l in oldLines where (left[l] ?? 0) > 0 {
            removed.append(l)
            left[l]! -= 1
        }

        return (common, removed, added)
    }

    /// 一行文字的两种说法之间是什么关系。
    ///
    /// 分三种而不是两种，是因为「多了一句」和「改成了一句」在用户听来是两件事：
    /// 前者是补充，后者是推翻。而它们的差别只是**旧内容有没有被完整保留**，
    /// 用公共前后缀一比就知道，不需要真的做语义理解。
    private enum LineChange {
        case appended(String)            // 新版把旧话加长了一点
        case removed(String)             // 新版比旧版少了一段
        case rewritten(String, String)   // 真的换了个说法
    }

    private func classify(_ old: String, _ new: String) -> LineChange {
        let a = Array(old), b = Array(new)

        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }

        var s = 0
        while s < a.count - p, s < b.count - p,
              a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }

        let oldMid = trimPunct(String(a[p..<(a.count - s)]))
        let newMid = trimPunct(String(b[p..<(b.count - s)]))

        if oldMid.isEmpty && !newMid.isEmpty { return .appended(newMid) }
        if newMid.isEmpty && !oldMid.isEmpty { return .removed(oldMid) }
        return .rewritten(oldMid.isEmpty ? clip(old) : oldMid,
                          newMid.isEmpty ? clip(new) : newMid)
    }

    /// 一句话说清改了什么。逐字对齐画布那句「版本 3 比版本 2 多了一句「不要太浓」」。
    private func summary(from old: Revision, to new: Revision) -> String {
        let head = "版本 \(new.version) 比版本 \(old.version)"

        if old.titleSnapshot != new.titleSnapshot {
            return "\(head) 把标题改成了「\(clip(new.titleSnapshot))」"
        }

        let d = diff(old.bodySnapshot, new.bodySnapshot)

        switch (d.removed.count, d.added.count) {
        case (0, 0):
            return old.photoHashes != new.photoHashes
                ? "\(head) 只动了配图，文字没改"
                : "\(head) 内容没有变化"

        case (1, 1):
            switch classify(d.removed[0], d.added[0]) {
            case .appended(let s):  return "\(head) 多了一句「\(clip(s))」"
            case .removed(let s):   return "\(head) 少了「\(clip(s))」"
            case .rewritten(let a, let b):
                return "\(head) 把「\(clip(a))」改成了「\(clip(b))」"
            }

        case (let r, 0):
            return "\(head) 少了 \(r) 句"

        case (0, let a):
            return "\(head) 多了 \(a) 句"

        default:
            return "\(head) 改了 \(max(d.removed.count, d.added.count)) 处"
        }
    }

    private func trimPunct(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "，。、；：！？,.!?;: "))
    }

    private func lines(of s: String) -> [String] {
        s.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func clip(_ s: String) -> String {
        s.count <= 14 ? s : String(s.prefix(14)) + "…"
    }
}

// MARK: - 对比卡

/// 一侧的对比卡。**旧版和新版只差一组颜色与描边** ——
/// 结构完全一样，这样两边的文字位置才能逐行对齐；
/// 一旦结构不同，眼睛就得在两卡之间来回找「同一句话在哪」。
private struct VersionCard: View {
    enum Side { case old, new }

    let side: Side
    let title: String
    let stamp: String
    let common: [String]
    let changed: [String]

    init(side: Side, title: String, stamp: String,
         common: [String], changed: [String]) {
        self.side = side
        self.title = title
        self.stamp = stamp
        self.common = common
        self.changed = changed
    }

    private var accent: Color { side == .new ? C.primary : C.ink2 }
    private var border: Color { side == .new ? C.primary : C.line }
    private var chipBg: Color { side == .new ? C.hiBg : C.diffOldBg }
    private var chipInk: Color { side == .new ? C.hiInk : C.diffOldInk }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.pillSel)
                    .foregroundStyle(accent)
                Text(stamp)
                    .font(Typo.tabLabel)
                    .foregroundStyle(C.ink3)
            }

            Rectangle()
                .fill(C.fill)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(common.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Typo.caption)
                        .foregroundStyle(C.ink2)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !changed.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(changed.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Typo.caption)
                                .foregroundStyle(chipInk)
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                    .background(chipBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(C.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(border, lineWidth: side == .new ? 1.5 : 1)
        )
    }
}
