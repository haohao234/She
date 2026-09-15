//
//  PhotoViewer.swift
//  配图全屏预览：把 105pt 格子里那张图看全
//
//  【它补的是什么洞】
//  画布上 34 屏的说明写着：
//    「点两张照片 → 原型保留静态（**真实设备上是全屏预览**）」
//  这句承诺此前一直没有落点 —— `PhotoGrid` 只画 105pt 的格子，
//  而格子用的是 `scaledToFill`（**裁过的**）。所以用户能看见「这里有一张图」，
//  却没有任何办法看到**那张图本身**：一张竖拍的人像，在格子里只看得到中间那一条。
//
//  这不是「少个锦上添花的东西」——「图片是一等公民，不是附件」是这个 App 的说法，
//  而一个点不开的附件不算一等公民。用户的原话是「图片导入进去了，
//  但是保存后却无法打开查看这个图片」，说的正是这件事。
//
//  【三个刻意的做法】
//
//  ① **挂在 `RootView` 最外层（和 `ToastLayer` 同一层），不是宿主屏里的 `.overlay`。**
//     宿主屏都在 `NavigationStack` 里，而这个 App 的手势侧滑返回是活的
//     （编辑器注释里那句「三颗出口按钮：完成 / 返回 / 手势侧滑」就是证据）。
//     预览页要左右滑翻图 —— 如果它长在某张被 push 出来的屏里，
//     手指从屏幕左边一划会**同时**做两件事：翻图 + pop 掉底下那屏。
//     盖在 Stack 之上以后，最上层先把触摸接住，那条侧滑手势根本起不来。
//
//  ② **底是固定深色**，浅色深色两档同一个值（理由写在 `C.viewerScrim` 上）。
//
//  ③ **点图外的底收起，点图本身不收起。** 翻完页手指常停在图上，
//     「点一下图就关」会让人在翻页时莫名其妙掉出预览；
//     而右上角的 ✕ 一直亮着，所以「怎么收起」这件事从来不需要用户猜。
//
//  【和格子的一处关键区别】
//  格子是 `scaledToFill`（填满、裁掉多余），预览是 `scaledToFit`（看全、留黑边）。
//  两者刻意相反：格子的任务是「让人扫一眼知道这里有个什么」，
//  预览的任务是「把这张图看清楚」——裁掉任何一边都算没做到。
//

import SwiftUI
import UIKit

// MARK: - 那一层

/// 全 App 唯一的那一层预览。
///
/// **为什么要一个全局的**：触发点有两个（31 记录详情 / 34 编辑器），
/// 而画面上只能有一张 —— 同一份理由写在 `ToastCenter` 头上。
///
/// 刻意**不加 `@MainActor`**，和 `ToastCenter` 同一个原因：
/// `PhotoViewerLayer` 在属性初始化器里取 `.shared` 会落在非隔离上下文
/// （属性初始化器不继承 `body` 的隔离），Swift 5 模式下会一路报警告。
/// 它的每个方法本来就只在主线程被调用。
final class PhotoViewerCenter: ObservableObject {
    static let shared = PhotoViewerCenter()
    private init() {}

    /// 当前这一屏要翻的那几张（顺序就是格子里的顺序）。
    @Published private(set) var hashes: [String] = []
    /// 从第几张看起。**它是「进场参数」，不是「当前页码」** ——
    /// 用户在预览里左右滑到第 5 张之后，这个值不会跟着变（也不需要变）：
    /// 翻页状态归 `PhotoViewer` 自己的 `@State` 管，回到格子就作废。
    @Published private(set) var index = 0
    @Published private(set) var visible = false

    /// 打开预览。`hashes` 为空时什么也不做 ——
    /// 空数组会得到一个「全黑的空屏 + 找不到图」的画面，那不是用户要求的。
    func open(_ hashes: [String], at index: Int) {
        guard !hashes.isEmpty else { return }
        self.hashes = hashes
        self.index = min(max(0, index), hashes.count - 1)
        withAnimation(.easeOut(duration: 0.22)) { visible = true }
    }

    func close() {
        withAnimation(.easeIn(duration: 0.18)) { visible = false }
    }
}

/// 挂在 `RootView` 上的那一层。全 App 共用。
struct PhotoViewerLayer: View {
    @ObservedObject private var center = PhotoViewerCenter.shared

    /// 显式 init 的理由见 `SegmentControl` —— `private` 存储属性会让
    /// 逐成员初始化器降级成 `private`，于是 `RootView` 里那句 `PhotoViewerLayer()`
    /// 会报 inaccessible（而报错位置在 RootView，不在这个文件里）。
    init() {}

    var body: some View {
        Group {
            if center.visible {
                PhotoViewer(hashes: center.hashes,
                            startAt: center.index,
                            onClose: { center.close() })
                    // 淡入淡出，不做「从缩略图放大」那条转场 ——
                    // 那个转场要拿到格子在图上的绝对位置（`anchorPreference`
                    // 一路往上传），为一个 0.2 秒的动画铺这么多管线不划算。
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: center.visible)
        .allowsHitTesting(center.visible)
    }
}

// MARK: - 预览本身

/// 一张配图的全屏预览。左右滑翻同一屏里的其他图。
struct PhotoViewer: View {

    let hashes: [String]
    let onClose: () -> Void

    @State private var index: Int

    /// 预览要的是**这张图存下来的全部像素**（文件本来就是长边 ≤ 2048），
    /// 所以直接取 `PhotoStore.maxPixel`，不再自己算一个「屏幕够用就行」的小值 ——
    /// 那等于把文件里已经有的像素又扔掉一次。
    ///
    /// 代价要写清楚：一张 2048×1536 解出来约 12MB，而 `TabView` 会同时留活
    /// 当前页和相邻页（最多 3 张）≈ 36MB。这在「看一张图」的场景里是合理的，
    /// 但如果以后有人要把预览接到别的、可能同时挂很多张的地方，
    /// 这个数**必须先降下来**，不能照搬。
    private static let maxPixel = PhotoStore.maxPixel

    init(hashes: [String], startAt: Int, onClose: @escaping () -> Void) {
        self.hashes = hashes
        self.onClose = onClose
        // 夹一下边界：调用方传进来的下标可能来自一个刚刚被删掉一张图的数组。
        // 不夹的话 `TabView` 的 `selection` 会指向一个不存在的 tag，
        // 画面停在一张**谁也不认识**的空白页上（而且没有任何报错）。
        _index = State(initialValue: min(max(0, startAt), max(0, hashes.count - 1)))
    }

    var body: some View {
        ZStack {
            // 铺满整屏（含安全区）—— 图应该顶到屏幕边缘，不该在刘海下面留一条底。
            C.viewerScrim
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            // 翻页交给系统的 page 样式，不自己写 `DragGesture` 去凑一个跟手的翻页 ——
            // 那是把系统已经做对的事重做一遍，而且做不对（惯性、边界回弹、
            // 与纵向手势的仲裁都得自己来）。
            TabView(selection: $index) {
                ForEach(Array(hashes.enumerated()), id: \.offset) { i, hash in
                    FullPhotoView(hash: hash, maxPixel: Self.maxPixel)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // 顶部这条**不**忽略安全区：它要给系统状态栏让位
            // （这个 App 没有隐藏状态栏，时间与电量一直是用户能看见的）。
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    // 「3 / 9」· 等宽数字。只有一张时不显示 ——
                    // 「1 / 1」是句废话，而它占的位置正好是图上最干净的一条边。
                    if hashes.count > 1 {
                        Text("\(index + 1) / \(hashes.count)")
                            .font(Typo.numCaptionM)
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(.white.opacity(0.16), in: Capsule(style: .continuous))
                    }
                    Spacer(minLength: 0)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .pressDown()
                }
                .padding(.horizontal, S.screen)
                .padding(.top, 8)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 预览里的一张图。
private struct FullPhotoView: View {
    let hash: String
    let maxPixel: CGFloat

    @State private var image: UIImage?
    /// 读完了、但没拿到图。**必须和「还在读」分开** ——
    /// 否则文件真的缺失时会永远停在转圈上，看起来像卡死，
    /// 而下一次崩溃日志里什么也查不到（因为它根本没崩，只是在等）。
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 36, weight: .light))
                    Text("这张图的文件不在这台手机上")
                        .font(Typo.caption)
                }
                .foregroundStyle(.white.opacity(0.5))
            } else {
                ProgressView()
                    .tint(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 与 `PhotoCell` 同一套写法：磁盘 IO 与解码都不压主线程。
        // `maxPixel` 一起进 id —— 它变了必须重新解码，否则会拿着旧尺寸的位图。
        .task(id: hash + "@\(Int(maxPixel))") {
            image = nil
            failed = false
            let loaded = await PhotoStore.load(hash, maxPixel: maxPixel)
            image = loaded
            failed = (loaded == nil)
        }
    }
}
