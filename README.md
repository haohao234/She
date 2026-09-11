# 她的信息本 · iOS 起步骨架

这份代码是**设计稿到 iOS 之间的桥**，不是成品 App。

它的用途有两个：一是让工程师不用从零猜设计意图，二是**反过来验证设计能不能落地** ——
有些决策（比如地理围栏只能绑 20 个点、中文该用系统字体还是捆绑 Noto）只有在写代码时才会浮出来，
它们已经被写回设计说明里。

---

## 一、怎么跑起来

工程结构由 `project.yml` 声明，**不需要在 Xcode 里手工建 target、拖文件、
勾 Compile Sources、加 App Groups**。那些步骤里最容易漏的三件事
（契约文件少勾一个 target、App Group 少开一边、扩展 bundle id 没挂到主 App 下）
在这份声明里是结构性的，漏不了。

### 路线 A：手上没有 Mac（先走这条）

代码推上 GitHub 就自动编译，报错直接回在 Actions 的日志里。
`.github/workflows/ios-build.yml` 已经写好，push 就触发。

1. 新建一个仓库（**三个初始化勾都不要勾**）
2. **双击本目录下的 `push-to-github.bat`**，在弹出的窗口里粘贴一次仓库地址 —— 剩下的它自己做
3. 等 3–5 分钟，看 Actions → 「错误（error）」那一段
4. 把那段贴回来，我按行改

> **本地仓库已经建好**（分支 `main`），要敲的命令已经封进 `push-to-github.bat`，
> 所以全程只需要「双击 + 粘贴一次地址」。
> 逐步操作、每一步的验证点与坑，看 **`她的信息本-iOS编译操作指引.html`**。

**为什么是双击一个脚本，而不是敲命令：** 这台机器上装的是随工具附带的
**便携版 git** —— 它既不在系统 PATH 里（直接敲 `git` 会提示「不是内部或外部命令」），
也没有 Git Bash（那是装了 Git for Windows 之后才有的）。
`push-to-github.bat` 自己会去找 git，并用**脚本自身的位置**定位仓库目录，
所以它不依赖任何环境配置；它也**必须待在本目录里**，挪出去就认不到仓库了。

> 该文件不进仓库（已在 `.gitignore` 里）—— 它硬编码了本机便携版 git 的查找逻辑，
> 对别的机器没有意义。

它只编译、不签名、不跑模拟器。因为现在要的不是「App 跑起来了吗」，
而是「它编译得过吗」。**这一步是为了让真正的编译器说话 —— 静态通读
再仔细也替代不了它。** 免费额度足够（私有仓库每月 2000 分钟，
macOS runner 折合实际约 200 分钟 ≈ 40 次编译）。

### 路线 B：有 Mac，想真正调试

```bash
brew install xcodegen
xcodegen generate          # 生成 HerInfo.xcodeproj
open HerInfo.xcodeproj
```

然后在 Xcode 里选一次自己的 Team（两个 target 都要选），⌘B。
真机跑还需要一份带 App Groups 的 provisioning profile。

`.xcodeproj` 是生成物、不入库 —— 想改工程结构就改 `project.yml` 再重新生成。
这样做的好处是：工程变更能被 review，而不是一堆 UUID 的 XML 在那里对不上。

### 几个已经配好、不用再管的点

- **最低版本 iOS 17.0**（SwiftData 与 `Layout` 协议的门槛；降到 16 要换回 Core Data）
- **语言模式是 Swift 5**。Swift 6 会把「严格并发」从警告升级成错误，
  而骨架里那几处 delegate 回调正是靠警告先暴露出来的。
  想主动复现那些并发问题：把 `project.yml` 里的 `SWIFT_VERSION` 改成 `"6.0"` 再编译。
- **Info.plist 两份都已写好**，含四条「少了不报错」的用途/文件共享键，
  以及扩展那六个 NSExtension 键。文件里每条都写了「缺了会怎样」。
- 不需要任何第三方依赖，也没有 CocoaPods / SPM 要装。

## 二、已经写好的是什么

| 文件 | 状态 | 对应画布 |
|---|---|---|
| `project.yml` | 完成 | **工程声明的唯一真相**：两个 target、共享契约、App Groups、Info.plist 全部固化在这里 |
| `HerInfo/Info.plist` | 完成 | 四条「少了不报错」的键（定位/FaceID 用途说明、文件可见、就地打开） |
| `HerInfoNotification/Info.plist` | 完成 | 扩展六个 NSExtension 键，含 `CFBundlePackageType = XPC!` |
| `Shared/NotificationContract.swift` | 完成 | 主 App ↔ 通知扩展的唯一契约（两个 target 共用） |
| `DesignSystem/Tokens.swift` | 完成 | 规范页「设计令牌」16 项 × 浅深两档 |
| `DesignSystem/Components.swift` | 完成 | 规范页「组件库」14 个组件 |
| `Models/Models.swift` | 完成 | 规范页「数据模型」6 张表 |
| `Features/HomeView.swift` | 完成 | **01** 首页 · 她的档案 |
| `Features/BrowseView.swift` | 完成 | **02** 分类浏览 / 25 排序置顶 / 31 记录详情 |
| `Features/EditorView.swift` | 完成 | **03** 新增记录 / **34** 记录配图 |
| `Features/ReminderEditorView.swift` | 完成 | **32** 新建提醒 |
| `Features/ProfileEditView.swift` | 完成 | **33** 编辑她的档案 |
| `Features/ExportView.swift` | 完成 | **35** 导出档案 |
| `Features/SecondaryViews.swift` | 结构到位 | 17 / 12 / 27 完整；23 / 13 完整 |
| `Services/ReminderService.swift` | 完成 | 通知 + 地理围栏，含 20 个区域上限处理 |
| `Services/ExportService.swift` | 完成 | 三种格式都是真实现，不是占位 |
| `HerInfoNotification/NotificationViewController.swift` | 完成 | **36** 展开态入口：取通知、读附件、转发点击 |
| `HerInfoNotification/NotificationContentView.swift` | 完成 | **36** 展开态那三块：配图 / 元信息 / 五个胶囊 |
| `HerInfoNotification/NotificationStyle.swift` | 完成 | 通知专用白阶透明度；零 hex，色值取自契约 |

**覆盖了主流程 01→02→03→04→05、本轮新增的 32/33/34/35，
以及 36 屏整套通知内容扩展（独立 target + 共享契约），
加上设置链 12→35 / 12→27 / 12→13→23。**

一共 17 个 Swift 源文件（主 App 13 + 扩展 3 + 两者共用的契约 1），
外加 2 份 `Info.plist`、1 份 `project.yml`、1 条 CI 流水线。

## 三、还需要铺开的

剩下的是**同一模式的重复劳动**，不是新判断：

- 06 空态 / 07 历史版本对比 / 08 键盘态 / 09-10 情绪打标
- 15-16 首次使用（两个 Onboarding 页）
- 21 首条记录引导 / 22 保存后轻提示 / 24 通知权限降级 / 26 删除二次确认
- 28 搜索空态 / 29 回收站空态 / 30 搜索筛选面板

每个都能照 `EditorView` / `ExportView` 的写法直接搬。

> 14 / 36 锁屏通知**不在这份清单里** —— 它是这套骨架里唯一需要动工程配置的东西，
> 已经整块写完了（两个 target、共享契约、Info.plist 六个键、主 App 侧六处接线）。
> 想核对「哪个键漏了会白做」，看交接文档的「通知内容扩展」一章。
**如果照搬时发现某一屏需要「新写一个组件」，那多半意味着设计里那屏用了别人没有的样式 ——
先回头看设计，别急着加组件。**

## 四、三处设计稿与 iOS 的差异（重要）

### 1. 字体：中文用系统，数字用 SF Pro

设计稿是 `Noto Sans SC` + `Inter`。到了 iOS：

- **中文直接用 `.system`（苹方）**。它是 iOS 上渲染质量最好的中文字体，
  而且自带系统级字重与动态字距。强行捆绑 Noto Sans SC 三个字重大约多 15MB 包体，
  换来的是一套略逊于系统的中文 —— 不划算。
- **数字用 SF Pro + `.monospacedDigit()`**。Inter 与 SF Pro 在数字上差异极小，
  而等宽数字是必须的：`20:00` 这类时间、`128 条` 这类计数，
  不设等宽的话数字一变宽度整行都在跳。

真要跨平台一致（比如同时出 Android），再走捆绑字体方案 —— **Token 层已经收口，只改一个文件**。

### 2. 图标：手绘 SVG → SF Symbols

底部 4 个 tab 图标在设计稿里是手绘 SVG，代码里换成
`house` / `square.grid.2x2` / `magnifyingglass` / `bell`。
理由：自动跟随字号与字重、矢量不用切图、且是系统自身的语言。
其余手绘图标同理优先找 SF Symbols 对应项，找不到的再导出 SVG 当资产。

### 3. 地理围栏：**20 是硬上限**

iOS 单个 App 最多监听 20 个 `CLCircularRegion`。这不是可调参数 ——
它已经改变了设计（05 屏要显示「已用 3/20」，加满后只能关一个才能再加）。
所以 `ReminderService.maxGeofences` 写成常量，且到顶时不静默失败。

## 五、这份代码的诚实说明

**它没有在 Xcode 里编译过。** 开发这个骨架的环境是 Windows，
没有 Xcode 与 iOS SDK —— 这不是偷懒，是 Apple 的硬约束：
Xcode 只跑在 macOS 上，交叉编译到 iOS 也不合法。

所以分两层说清楚：

**已经做过的（静态层）** —— 五份校验脚本，全部通过：

| 脚本 | 管什么 |
|---|---|
| `check-swift.js` | 括号配平、类型引用闭合、Route 与导航对齐、关键常量落地（17 项） |
| `check-project.py` | `project.yml` 路径自洽、两份 plist 合法、**跨文件契约一致性**（分类 id / App Group） |
| `check-handoff.js` | 交接文档 12 章齐全、37 屏逐条、验收清单 |
| `check-prototype.js` / `check-spec.js` | 设计侧两份 HTML 交付物 |

逐行通读 5524 行之后，把能确定的都改掉了（22 类），其中：
`ForEach(modes, id: \.0)` 这种 KeyPath 指元组元素的写法、`add()` 缺 `try/await`、
有 `private` 存储属性导致逐成员 init 整体降级为 private、
tab 根屏对空 `path` 调 `removeLast()` 会直接 `fatalError`。

**还没有做过的（编译器层）** —— 以下三类**必须要真机编译才能发现**，
在 `编译预检清单.md` 里每类都给了两种修法：

1. `#Predicate` 宏对捕获变量的限制（我按最保守的写法处理了，但宏的行为只有编译器知道）
2. Swift 6 严格并发下 `UNUserNotificationCenterDelegate` / `CLLocationManagerDelegate`
   的 `nonisolated` 标注（已按 iOS 17 的 async 版本写，但可能有 actor 隔离告警）
3. `FlowLayout` 自定义 `Layout` 的边界情况

预计首次编译会有若干警告与少量错误，都在上面这三类里。
**走「路线 A」把日志拿回来，就能把这三类一次性收掉。**

**其中最容易悄悄失败的是通知扩展**，因为它的失败方式不是报错：
分类 id 对不上、`UserInteractionEnabled` 没写 `true`、`CFBundlePackageType`
不是 `XPC!`，结果都只是「通知照弹，长按展开回到系统默认样子」。
所以这几个键在 `Info.plist` 里都加了注释，`check-project.py` 会守住它们，
交接文档里也单列了一张表。

---

## 六、图标与资源

- **不需要切图**：所有图标走 SF Symbols，所有色值走 `Tokens.swift`。
- **不需要捆绑字体**：见上文第 1 条。
- 唯一的资产是 App Icon 与启动图，按 1024×1024 源图出即可。
  品牌色 `#C0614A`，标记是渐变 `linear-gradient(140°, #CE6E56 → #B4523C)`。
