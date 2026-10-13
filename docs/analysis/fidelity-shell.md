# 01 概览 · 09 设置 · 设计稿 ↔ 实现 逐元素对照（fidelity-shell）

> **结论先行**：`01-dashboard` 与 `09-settings` 的**结构与文案口径**和实机高度一致——概览页四卡（存储/负载/可释放/最近操作）、设置四 tab + 确认弹窗的层级、文案、开关默认态都对得上，且比 monitor 页诚实（虚数值一律走占位/"尚未采样"，不编数字）。
> 主要差异集中在**全站几何/侧栏**层（与 monitor 同源）：
> - **S1 · 侧栏 footer 画错**：`01-dashboard.html` 仍画成"分隔线 + 设置 nav-item"，实机是 `Macintosh HD` + 百分比 + 红色容量条 + 带边框设置按钮（`MainWindow.swift` `volumeFooter`）。需补一个侧栏 footer 组件，八张稿一起换。
> - **I10a · 侧栏宽度（P6.2b 重测后已落地）**：原记"`NavigationSplitView(min:200, ideal:220, max:280)` 实测分隔线在 x=220"——**这个数复现不了**。P6.2b 在 raw @2x PNG 上量到改前实机是 **200pt**（分隔线 x=401px），并用两次否证实验确定机制：往 SwiftUI 自己写的 `NSSplitView Subview Frames…` 里手写 260pt 不被读、把 `ideal` 改成 240 重构建仍出 200pt，**首屏宽度取的是 `min`**。现已改 `min:220`，实测 440px@2x = 220pt，与稿 `--sidebar-w: 220px` 对齐。全过程见 `fidelity-guardian.md` §6.3（同一处骨架，两页共用）。
> - **I10b · 标题栏 52 vs 令牌 38**：仍未落地——改令牌会影响全部模块的像素基线，按 #53 约定**只出规格、待集成阶段落地**。
> - **S3 · 内容底色**：概览用 `MMColor.contentBackground`，令牌 `--c-content-bg` 是白/`#282828`（controlBackground 档）；monitor 页实测页面底是 `windowBackgroundColor`（`#2B2B2C` 级）。两页"卡浮在页面上"的对比度是否一致需真机核对。
> - **S4 · 缺 under-page 卡片 token**：monitor 私有 `card()` 用 `cardBackground`(underPage)，本页 `MMCard` 用 `controlBackground`——令牌层尚无统一 under-page 变体（monitor 路线已提，本页不重复）。
>
> 另：设计稿内有**占位/虚构数字**（`2.4 GB`/`46`/`3.5 GB`/`3 / 20`/`Macintosh HD 94%`），实机均为动态值或空态，属 S2 类，已在 §3 逐条标出。
>
> **更正（P29，2026-10-09）：上面那句"设置四 tab…和实机高度一致"只对了一半，而且对的那一半不是重点。**
> 这一页的 ✅ 当时核的是"稿上有的东西画面对不对得上"，而用户报的是**"设置里的功能几乎不可用"**——
> 那是另一类问题，逐元素对照表本来查不出来：**画面上没有的行，不代表功能不需要它**
> （通知授权状态、登录项"待批准"这两档稿子根本没画，所以永远不会被判成差异），
> **脚注逐字对上，也不代表脚注说的是实话**（"清理模块接入这些开关后生效"两句都是假的）。
> P29 按"每一行有没有真实后端"重查了一遍，落地 I13/I14/I15 三条，逐行见 §2 那几行新加的 ❌→P29 改；
> 本轮**改了 `Sources/`**（上面 §0 那行"未改 Sources/"是 P3 那一版的范围声明，保留作历史）。
>
> **I4/I5 在本页不触发**：本页 `MMCard` 复用正确（I4 是 monitor 私有 `card()` 问题），本页 `MMKeyRow` 标签未出现 80pt 撑破（I5 是 monitor 内存卡问题），故组件层无可立即落的改动。

## 0. 对照方法

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/shell/01-dashboard.html`、`09-settings.html`（09a–09e 五块 artboard） |
| 渲染 | `cd docs/design-system && ./render.sh screens/shell/01-dashboard.html 1160 780` / `09-settings.html 1160 1500`（2x） |
| 实机 | `build/MacMaster.app`，`MM_OPEN_MODULE=dashboard`（或 `MM_SHOW_SETTINGS`）+ `MM_SETTINGS_TAB=<tab>` 启动，按 **pid** 匹配 windowid，`screencapture -o -x -l<id>` |
| 像素取证 | 同 `fidelity-monitor.md` §0 的 CoreGraphics 取色路径 |
| 可用钩子 | 壳层 `MM_OPEN_MODULE` / `MM_SHOW_SETTINGS` / `MM_SETTINGS_TAB`（`README §2`） |
| 硬约束 | 全程零合成事件；未改 `Sources/`、`Packages/`、`docs/design-system/*.css`；未跑 `swift build`；只 `kill` 自己启用的实例 |

> **测量诚实声明**：P3 审计这一版本环境无头，当时所有"实机像素"项一律标 **「待真机测量」**。**P6.2b 起了两帧实机截图**（`docs/verification/p62b-fidelity/01-dashboard-first-frame.png`、`02-dashboard-history-full.png`，raw @2x 2200×1520 px = 1100×760 pt，`MM_APPEARANCE=light`），据此关掉了侧栏、`全部 ›`、sparkline 三条；**其余像素项（堆叠条分段、仪表指针角度、内存构成条、可释放行高）仍无照片依据**，往下看 §4。

## 1. 01-dashboard 逐元素

### 1.1 页头（MMPageHeader）

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「概览」 | `MainWindow.swift:253` `MMPageHeader("概览", …)` | ✅ | 一致 | — | — |
| 副标题「本机状态 · 数据更新于 21:15:04」 | `DashboardView.headerSubtitle`（`MainWindow.swift:265`） | ❌ | 稿子写死"本机状态 · 数据更新于 HH:mm:ss"；实机是"上次采样 <relative> · CPU/内存/磁盘均为本机实时读数"。**实机更诚实**（不编固定时刻），稿子是占位措辞 | 低 | 设计稿该改 S2 |
| 右上「刷新」按钮 | `MainWindow.swift:254-262` `arrow.clockwise` + `measureReclaimable()` | ✅ | 图标/位置/禁用态（测量中禁用）一致 | — | — |

### 1.2 存储卡

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「存储」+ 低空间徽章「可用空间偏低」 | `MainWindow.swift:309,312` `MMBadge(..., tint: destructive)` | ✅ | 仅低空间时出现，口径一致 | — | — |
| 「28.1 GB 可用 · 共 494.4 GB」 | `MainWindow.swift:316` | ✅ | 动态值，文案格式一致 | — | — |
| 堆叠条 9 段 + 图例 | `MainWindow.swift:325,326` `MMStackedBar`/`MMLegend` ← `StorageBreakdown.segments` | ⚠️待量 | 稿子画了 9 段固定占比（应用/开发者/系统/缓存/媒体/文档/可清理/废纸篓/可用）；实机段集与配色由 `StorageBreakdown.segments(total:available:reclaimable:trash:)` 决定，**段数/宽度/配色需逐段真机核对** | 中 | 待真机测量 |
| 「可立即释放 3.5 GB（缓存 2.4 + 废纸篓 1.1）」 | `MainWindow.swift:380-401` `releaseText`/`releaseDetail` | ❌ | 稿子写死 3.5/2.4/1.1；实机 = `reclaimState` 实测 + 废纸篓实测，没扫到显示"尚未测量"占位（不编数字） | 低 | 设计稿该改 S2 |
| 「查看占用排行」「清理 X GB」按钮 | `MainWindow.swift:339,341` | ✅ | 一致 | — | — |

> **P35b 行号重指**（2026-10-12 现跑 `p16-citation-audit.sh`，硬失败里 `MainWindow.swift` 第 302 行落在空白行上）：
> 页脚 `statusBar` 从 `:277` 起，P35b 在「N 个卷」那一支加了读不到时的占位分支（`:280` 有数、`:283` 读数失败），
> 存储卡整块因此比上一版往下漂。但**偏移量并不是一个常数**：卡标题 +10、堆叠条那两行只 +7。
> 也就是说旧号里至少有一格在本轮之前就已经偏了（偏到别的内容上，而那一行不是空白，所以门禁一直放行）。
> 这一族现在每一格都是逐条 grep 定位的，不是"整体 +N"推出来的。

### 1.3 系统负载卡

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「系统负载」+ 平稳徽章 | `MainWindow.swift:410-417` `LoadVerdict.text` | ✅ | 口径一致 | — | — |
| CPU 仪表「23%」+「2.1/10 核」+「4 性能+6 能效」 | `MainWindow.swift:420-426` `gaugeRow` / `DashboardText.cpuCaliberNote` | ✅(语义) | 仪表填 `model.cpuLoad`（总占用），注脚是核数；与稿子层级一致 ⚠️待量（指针角度需真机） | 低 | 待真机测量 |
| 内存仪表「65%」+「15.6/24 GB」+「交换 0 MB」 | `MainWindow.swift:427-431` | ⚠️待核 | 稿子 65% 疑似 = used/total；实机仪表填 `model.memory?.pressure`（内存压力），数值口径可能不同 → **需真机核对 pressure 与 used/total 是否同一档** | 中 | 待真机测量 |
| 内存构成堆叠条 | `MainWindow.swift:494-517` `memoryComposition` | ✅(语义) | 缺段不画绿条（诚实）⚠️待量 | 低 | 待真机测量 |
| 网络 / 磁盘 I/O 迷你图 + 注脚 | `MainWindow.swift:444-468` `metricMini` | ✅ | "等待差分"/"IOKit 未返回统计" 占位文案与降级口径一致 | — | — |

### 1.4 可释放空间卡 / 最近操作卡

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 可释放前三分类 + 废纸篓 + 锁定行（iOS 备份） | `MainWindow.swift:557-575` `reclaimRows` | ✅(语义) | 只读分类置灰加锁、前三+废纸篓；稿子数字为示例 ⚠️待量（行高/图标对齐） | 低 | 待真机测量 |
| 最近操作：撤回/已撤回/废纸篓已清空 | `MainWindow.swift:626-687` | ✅ | 三种态都覆盖，文案一致 | — | — |
| 「撤回」按钮在废纸篓清空后消失 | `MainWindow.swift:664-673` | ✅ | 不靠用户点错才报错，一致 | — | — |

### 1.5 侧栏 + 状态栏

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- | --- |
| 模块列表「系统清理 2.4 GB」「应用卸载 46」 | `MainWindow.swift:105-110` | ❌ | 稿子写死占位；实机仅在 `dashboard.reclaimState == .measured` 时显示真实值，否则该格为空（不显示 "—"） | 低 | 设计稿该改 S2 |
| **侧栏 footer（S1）** | `MainWindow.swift:141-166` `volumeFooter` | ❌ | 实机 = `Macintosh HD` + 百分比 + 红色容量条（低空间转红）+ 带边框「设置」按钮；**稿子画成"分隔线 + 设置 nav-item"**，沿用 01–06 错误画法 | 中 | 设计稿该改 S1（全站） |
| 隐私守护红点 | `01-dashboard.html:40` | ✅（P36 现读） | 稿子 :40 现读是纯 nav-item、无红点——commit `0c61fbf`「清洗侧栏虚构占位（含隐私守护红点）」已删；实机 `SidebarView`（`MainWindow.swift:61` 起）本无模块红点逻辑 → 两侧一致，红点已不存在 | 低 | 设计稿该改 S2 → **稿侧已落地** |
| 状态栏「4 个卷 · 文件系统 APFS · 上次清理 3 天前」 | `MainWindow.swift:277-301` `statusBar` | ❌ | 稿子多画"索引正常""Spotlight 已排除 2 个路径"——实机状态栏**无这两段**（代码未输出） | 低 | 设计稿该改 S2 |
| 侧栏宽 220（`--sidebar-w`）/ 标题栏 38（`--titlebar-h`） | `MainWindow.swift:22`（`.navigationSplitViewColumnWidth`，P29 现读：此前引 `:18` 落在那段解释注释上） / 实机 52pt | ✅ / ❌ | **P6.2b**：侧栏改前实测量 **200pt**（不是这里原记的 220），现 `min:220` 后实测 220pt，本条关闭；标题栏 52 vs 令牌 38 仍开，归集成阶段 | 低 | I10a **已落地** / I10b 待落地 |
| 「可释放空间」卡右上「全部」（稿 `01-dashboard.html` 画的是 `全部 + chevron-right`） | `MainWindow.swift` `cardHeader("可释放空间", trailing:)` | ✅（P6.2b 起） | 改前只有一个蓝色"全部"，读起来像筛选开关；稿里那半枚 `chevron.right` 才是"点了会离开这一页"的唯一提示。现已补 `全部 ›`（`p62b-fidelity/02-dashboard-history-full.png`） | 低 | 实现该改 I11 → **已落地** |
| 网络 / 磁盘 I/O 迷你图 `.spark i{flex:1}`（12 等分槽） | `MMDesign.swift` `MMSparkline`（`slotCount` 固定、`maxWidth:.infinity` 等分） | ✅（P6.2b 起） | 改前每根钉死 10pt 靠左排：首帧只有一根细柱孤零零贴在左边，读起来像图坏了，且柱子随采样次数往右爬、同一张图前后宽度不一样。现横轴满宽、柱从右端往左长（`01` 首帧 vs `02` 满轴两张） | 中 | 实现该改 I12 → **已落地** |

## 2. 09-settings 逐元素（09a–09e）

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| sheet「500 宽 + 高度按内容」+ MMPageHeader「设置」+ xmark 关闭 | 稿 `09-settings.html:12`（`width:500px; height:auto`）；实机 header `SettingsView.swift:21-31`、`.frame(width:500,height:560)` `:59` | ❌→P29 改 | **实现把高度钉死在 400**：「清理」这一栏有 5 个 Section，400 高只露到第二组的标题行（`docs/verification/p29-before/cleaner.png`），用户翻不到下面的行，看着就像功能不在——这正是"设置几乎不可用"里最直观的一条。现提到 560，同一栏露到「监听」第一行（`p29-after/cleaner.png`），**「删除历史」「排除项」仍要滚动**：差距从"看不全"变成"仍要滚"，没有变成"已一致"。稿那一格是 CSS 才办得到的按内容展开，实机 sheet 需要一个确定高度（`:56-58` 记着这个理由；顺带一条：那段注释写的"8 个分组"数错了，现读是 5 个 Section，注释是编译输入、改它要重跑全部取证，本轮只在文档里记这笔） | 中 | 实现该改 I15 → **已落地**；稿子该改 S2（标实机 560 + 仍需滚动） |
| 设置页的**入口**（稿只画了侧栏底部那一枚按钮） | 应用菜单「设置…」+ ⌘, `MacMasterApp.swift:45-50`；侧栏按钮 `MainWindow.swift:128-135`；菜单栏下拉「设置...」`MenuBarManager.swift:354-356`→`386-391`（发 `.mmOpenSettings`，`SystemSettings.swift:40`），三处收在 `MacMasterApp.swift:93-95` | ❌→P29 改 | 改前只有侧栏那一枚：主窗口一收进菜单栏，全 app 没有任何地方能进设置；⌘, 与应用菜单那一格是空的，而 macOS 用户的第一个反射就是这两处。现三处入口都在，且不再各写各的状态 | 中 | 实现该改 I13 → **已落地**；稿子该改 S2（补入口，至少一条 ⌘, 注记） |
| 系统设置深链（稿 09 没画这一层） | `MMReveal.openSystemSettings(pane:)`（`MMDesign.swift:519-522`）+ `MMSettingsPane`（`SystemSettings.swift:16-33`） | ❌→P29 改 | 改前调用方传的是**整串 URL**，而这一支函数自己还要拼 `x-apple.systempreferences:` 前缀——拼出来是双前缀死链：清理页的权限横幅按下去系统设置一动没动（实测 `docs/verification/p29-panes-v3/pane-urls.log` C 档），而 `NSWorkspace.open` 不返回成败，所以画面也没有任何失败痕迹。现参数收成枚举，scheme 全仓只在 `SystemSettings.swift:25` 出现，"手写 URL 当参数"没有编译期入口 | 高 | 实现该改 I13 → **已落地** |
| 四 tab 分段（通用/监控/清理/关于） | `SettingsView.swift:33-42` `Picker(.segmented)`；档位枚举 `SettingsTab` `:367-380` | ✅ | 一致 | — | — |
| 09a 语言（简/英）、启动（开机启动/最小化菜单栏） | `SettingsView.swift:65-120`（语言 `67-83`、启动 `85-116`） | ⚠️ | 视觉一致；**稿子只画了"注册失败橙色脚注"没画"等系统批准"这一档**（见下两行）。**语言是死开关**，见下方补记 | 低 | ~~待集成阶段落地（错误态规格）~~ 语言项 P7a 已处理 / 状态可见项 I14 已落地、稿子待改 S2 |
| 09a 登录项：开关拨上去以后的真实状态 | `SettingsView.swift:90-110`；状态来源 `LaunchBehavior.swift:31`（`isOn`）`:37-46`（`statusCaption`）`:49`（`needsSystemSettings`） | ❌→P29 改 | 改前只认 `.enabled`：`SMAppService` 注册成功但落在 `.requiresApproval`（macOS 要用户在「登录项与扩展」里再点一次允许）时，开关自己弹回"关"、什么话也不说——用户只会认为它坏了。现这一档显示"已注册，但要你再允许一次"，并配「打开系统设置 · 登录项」出口；`.notFound`（从 `.build` 直接跑）也各有一句。**照片只证到"没话说"的那一档**：这台机器实测 `.enabled`，画面是默认那句（`p29-after/general.png`），`.requiresApproval`/`.notFound` 两句要真换一台机器的系统状态才拍得到，本轮只有代码与单测凭据 | 高 | 实现该改 I14 → **已落地**；稿子该改 S2（补这两档 + 跳转按钮） |
| 09b 通知：两个开关之上的系统授权状态 | `SettingsView.swift:142-163`（脚注 `147-151`、跳转按钮 `152-157`、两开关 `158-159`）；判据 `NotificationStatus.swift:27-42`（`caption`）`:46-51`（`needsSystemSettings`），每次进这一栏重读 `.task` `SettingsView.swift:169` | ❌→P29 改 | 改前这里**从没读过系统的授权状态**：开关说的是"希望通知"，系统记的是"允不允许发通知"，用户在系统设置里拒过一次以后开关照样拨得动、`requestAuthorization` 也不会再弹（只在"未决定"时有效），于是这一栏看着一切正常、实际一条通知都发不出去。现在这一档写在两个开关**上方**（摆下方就要滚动才看到，而"要滚动才看到"正是这一页被报不可用的形状），并配「打开系统设置 · 通知」。**这一档在这台机器上是真实状态、不用夹具**：用户此前拒过一次，改后画面第一行就是那句橙色的"系统里已拒绝…"加跳转按钮（`p29-after/monitor.png`），而改前那一栏在 400 高下**连标题都在折线以下**（`p29-before/monitor.png` 只拍到「刷新频率」为止），下面那两个开关无论拨成什么、系统这边一直是"已拒绝"——这一条和上面清理栏那句假脚注，是本轮两处**在改前照片里就直接看得见**的假话，其余各条要靠代码才看得出来 | 高 | 实现该改 I14 → **已落地**；稿子该改 S2（补未决定/已拒/静默三档） |

> **补记（P7a，2026-10-05）：这一行的 ✅ 当初只核了"长得像"，没核"按下去有没有用"。**
> `app.language` 只有持久化没有生效端：`Localization.localized(_:)`（`Packages/MMCore/Sources/MMCore/Localization.swift:202`）
> 与便捷函数 `L(_:)`（`:208`）**在全仓界面代码里零调用点**（现读
> `grep -rnE '(^|[^A-Za-z0-9_])L\(' --include='*.swift' Packages Sources`，除定义与两处注释外无命中），
> 全站文案是一套写死的中文。也就是说这台机器上 `app.language=en` 存着、界面却一个字也不会变，
> 而选择器还能改——**这是"控件在、状态存、效果无"三件套齐全的死开关**。
> → 已把选择器 `.disabled(true)`（`SettingsView.swift:79`）并加脚注
> 「界面文案尚未接入多语言，切换不会改变界面」（`:80`，说明写在 `:76-78` 的注释里）；`AppSettings.swift:11` 的文档注释同步改成
> "持久化是好的，**生效不是**"。真机取证 `docs/verification/p7-settings-lang/{png,log}`。
> **这不是"改好了"，是把假话改成实话**：接不接多语言仍是产品决定，接法有两种
> （把界面字符串逐个走 `L(_:)`，或干脆删掉 `Localization.swift` 与这个开关），本页不代选。
> 设置页其余各行的键都有真实消费方（逐个对过代码），**语言是全站唯一一个**。
> 两个容易误判成死开关的，把通路记在这里免得下轮再数一遍：
> `launchAtLogin` 是**回填值**而不是指令——`LaunchBehavior.swift:54/70` 从 `SMAppService.mainApp`
> 的注册状态反写这个键，真正干活的是同文件的 `register()/unregister()`（P29 后在 `:61`/`:63`，
> 这一句此前引的 `:37`/`:39` 已经不作数——那一行现在是别的代码）；
> `monitorRefreshInterval`（界面上那个 1/2/5 选择器，`SettingsView.swift:134`）没有直接消费方，
> 它经 `AppSettings.swift:204-205` 算成 `monitorRefreshIntervalSeconds`，
> 由 `MenuBarManager.swift:115/140` 取用。
| 09b 监控三开关 + 间隔(1/2/5) | `SettingsView.swift:122-141` | ✅ | 逐字对上；**行首无图标**（稿子已按实机去图标）；两个通知开关见上面那行 | — | — |
| 09b 阈值脚注「CPU ≥85% / 内存 ≥90% / 5 分钟冷却」 | `SettingsView.swift:160-162` | ✅ | 静态说明，一致 | — | — |
| 09c 扫描范围 4 + 安全 2 + 监听 + 删除历史 + 排除项 | `SettingsView.swift:172-270`（扫描 `174-185`、安全 `187-190`、监听 `192-204`、删除历史 `206-228`、排除项 `230-259`） | ⚠️ | 实机「监听」分组有**两个**开关（`watchTrashForResidualCleanup` `193` + `watchAppFolderChanges` `198`，后者 P5.3c 加的），稿 09c 那一段（`09-settings.html:189-192`）标题还是「废纸篓」、只画了一个；"台账条目 3/20" 实机 N 动态、排除项默认空列表（稿子示例值） | 低 | 设计稿该改 S2（补第二个开关 + 分组改名 + 示例值标注）；另见 §3 那两条**假脚注**的更正 |
| 09c 扫描范围/排除项两处脚注的口径 | `SettingsView.swift:179-184`、`:254-258` | ❌→P29 改 | 改前两句写的是"设置已持久化；清理模块接入这些开关后生效""清理模块消费该列表后生效"（第一句在 `p29-before/cleaner.png` 里就印在画面上）——**那句是假的**：四个开关从 P29 现读起就有消费点（清理页扫描、概览「重新测量」），排除项列表就是清理页「已排除」面板读的那一份。假话的代价不是"说多了"，是用户以为整页都没接、根本不去拨它 | 高 | 实现该改 I14 → **已落地**（文案改成实话，稿 `:178`/`:215` 那两格还留着旧的假话，要跟着换） |
| 09c N=0 时「清空删除历史」置灰、historyFileURL=nil 时整行降级 | `SettingsView.swift:226-227`、`:220-224` | ❌ | 两种降级态稿子**没画**（09c 画的是有记录启用态）；档位必须照代码存在 | 低 | 设计稿该改 S2（补降级态） |
| 09d 关于：版本兜底 1.0.0(1)、反馈问题 disabled、未配置官方渠道 | `SettingsView.swift:302-350`（`versionText` `352-356`、反馈行 `324`、disabled 按钮 `334-337`） | ✅ | 一致；"不做虚构链接"底线守住了 | — | — |
| 09e 清空确认弹窗「清空 N 条记录」+ 取消 | `SettingsView.swift:263-269` | ✅ | 逐字照抄实现文案，一致 | — | — |

## 3. 差异归属汇总

> **复核 2026-10-04（P6.5b）**：本轮把六份 fidelity 文档的"实现该改"逐条重对代码，**本页是唯一一条
> "已落地"写上去、而对代码核得一字不差的**——I11/I12 两处的坐标、形态、判据全部仍在原位：
> I11 = `MainWindow.swift:588-592`（`Text("全部")` + `Image(systemName:"chevron.right").font(.caption2)`，
> 注释 `:580-581` 还留着"那半枚箭头是'点了会离开这一页'"的原始理由）；
> I12 = `MMSparkline`（`MMDesign.swift:1057-1095`，`slotCount` 默认 12、`:1059`；未满的槽用 `Color.clear`
> 撑位而不是画 2pt 矮柱，`:1064-1068`，判据"没轮到 ≠ 读不到"写在注释里），调用点 `MainWindow.swift:542`，
> 数据侧 `DashboardModel.swift:96-122` 把"读不到"压成 `nil` 槽、量不到时整列空出来（`:118-122`）。
> **本页没有需要更正的落地记录。** 唯一要补的是下面第 5 行那句"待真机测量"里新添的一项边界（见 §5 第 2 条补记：
> 侧栏 `max:280` 那端没有取证手段，与"没拍"不是一回事）。

- **实现该改（P6.2b 落地 2 条 / P29 落地 3 条）**：I11「全部」缺 `chevron-right` affordance、I12 sparkline 首帧稀疏且槽宽钉死（均见 §1.5 表）。**P29（设置页可用性轮）新增三条**：I13 设置入口与系统设置深链（⌘,/应用菜单/菜单栏下拉三处收口 + `MMSettingsPane` 枚举堵掉双前缀死链）、I14 状态可见性与两处假脚注（登录项 `.requiresApproval`、通知授权状态、扫描范围/排除项"未接入"的假话）、I15 sheet 高度 400→560。I4/I5 在本页不触发；无"把未知当已知"类缺陷（本页占位/降级文案正确）。
- **设计稿该改（S 类）**：S1（侧栏 footer，全站）、S2（占位/虚构数字：2.4GB/46/3.5GB/3/20/94%/红点/索引正常/Spotlight 排除/台账降级态未画；**P29 追加**：09 未画 ⌘, 与菜单栏「设置...」两个入口、未画登录项"待系统批准"与通知"未决定/已拒/静默"三档及其跳转按钮、09c 的「废纸篓」分组已是「监听」且少画第二个开关、`:178`/`:215` 两格脚注仍是实现已经改掉的假话、sheet 实机 560 且清理栏仍需滚动）。
- **两边都改（0 条）**。
- **待集成阶段落地（全站几何，只出规格不落地）**：I10b（标题栏 52 vs 38）、S3（content 底色档）、S4（under-page 卡片 token，monitor 已提）。**I10a（侧栏）已由 P6.2b 落地。**
- **待真机测量（⚠️）**：存储堆叠条 9 段、CPU/内存仪表指针角度与口径、内存构成条、可释放行高图标对齐、S3 两页对比度一致性。

## 4. 没能验证到的部分（诚实列出）

1. 概览折叠线以下的**逐像素**核对：P6.2b 的两帧（1100×760pt 视口）已把内存构成条、可释放三行、最近操作四行**拍进画面**（无需滚动），但段宽/行高这类数还没逐个量——`02-dashboard-history-full.png` 是 raw PNG，可直接用 `Scripts/pixel-probe.swift` 续量。
2. 设置各 tab 的滚动截断点：P29 已在 560 高下拍到四栏（`docs/verification/p29-after/{general,monitor,cleaner,about}.png`，脚本 `Scripts/p29-settings-capture.sh`），09c 的「删除历史」「排除项」两组**仍在折线以下**、没进照片；逐屏"滚到底"的截图通路还没有。
2b. 登录项的 `.requiresApproval` 与 `.notFound` 两档、通知的 `.notDetermined`/`.authorized` 两档：**这台机器拿不到**（前者系统真实状态是 `.enabled`，后者是 `.denied`，见上面 §2 两行）。这几档只有代码 + 单测凭据，没有照片；要拍就得动系统的登录项/通知授权设置，那是用户机器的真实状态，本轮没动。
3. 浅色 vs 深色的**交叉**核对：P6.2b 两帧都是 `MM_APPEARANCE=light`（与稿同源），暗档这一轮没重拍；侧栏 220pt、`全部 ›`、sparkline 满轴在暗档下的对比度未量。
4. S3 跨页对比度（概览 contentBackground vs 实机 windowBackground）需两页同框真机截图。

## 5. 提请协调者（协调路 #53 落）

1. **S1 侧栏 footer 组件**：在 `tokens.css`/`screen.css` 增 `.sidebar-footer`（容量行 + 红色容量条 + 带边框设置按钮），八张稿（01–07 + 本页）一起换，消除"分隔线+设置 nav-item"错误画法。
2. **I10b/S3/S4 全站几何修正**：调令牌 `--titlebar-h`→52、补 `--c-content-bg` 与 under-page 变体；**改动会作废全部模块像素基线，待集成阶段统一落地**，本页不单独改。**I10a（侧栏）P6.2b 已落地**，但落地位置是 `MainWindow.swift:22` 的 `min:`（首屏宽度只认 `min`，`ideal` 与 AppKit 那条持久化记录都不参与），令牌 `--sidebar-w: 220px` 本来就是对的、没动；顺带一条待办：`--sidebar-w-min: 200px` 全仓从未被引用（仅 `tokens.css:33` 声明处一处命中），而应用现在也拖不到 200，要么删令牌要么把稿改成 220。
   **P6.5b 补一条取证边界（协调者需要知道"**量不到**"和"**没量**"的分别）**：
   `min: 220, ideal: 220, max: 280` 这一行的**窄端在代码层就结掉了**——`min` 同时是 AppKit 给分隔线的下界，
   拖不过 220，所以"用户拖窄到 220 以下会怎样"是个不可能状态，不需要照片（详见 `fidelity-guardian.md` §6.6.5 第 1 条）。
   **宽端 `max:280` 则根本没有采集通路**：壳层七个启动钩子
   （`MM_OPEN_MODULE` `MainWindow.swift:52`、`MM_SHOW_SETTINGS` `:47`、`MM_SETTINGS_TAB` `SettingsView.swift:13`、
   `MM_WINDOW_SIZE` `LaunchBehavior.swift:135`、`MM_APPEARANCE` `:105`、`MM_PROBE_WINDOW` `WindowProbe.swift:12`、
   `MM_DUMP_MENUS` `LaunchBehavior.swift:182`）
   没有一个能移动分隔线；`MM_WINDOW_SIZE` 走 `window.setContentSize`（`LaunchBehavior.swift:144`），
   加宽的部分归 detail 面板、侧栏仍停在 `min`；写 `NSSplitView Subview Frames…` 已被
   `fidelity-guardian.md` §6.3 实验 B 否证；剩下的唯一办法是**拖分隔线=合成操作，红线禁止**。
   → 要量 280 就得先立项一个设列宽的启动钩子（如 `MM_SIDEBAR_WIDTH`），那属新增钩子、要走 hook-ledger 流程；
   **本轮不加**。这条现在记为**取证边界**，别再当"欠一张照片"重复登记。
3. **09c 降级态补画**：N=0 置灰、「在访达中显示」整行缺失两档，出规格给 mmuninstaller/清理路线补 artboard。
4. **S2 占位数字清洗**：稿内 `2.4 GB`/`46`/`3.5 GB`/`3 / 20`/`94%`/`红点`/`索引正常`/`Spotlight 已排除` 标"示例值/虚构"或改为动态占位，避免被当成实测。
5. **09-settings 需要一次同步（P29 之后稿子落后实现两轮）**：要补的是①设置入口（⌘, 与应用菜单那一格、菜单栏下拉「设置...」，稿只画了侧栏按钮）、②登录项"待系统批准"档 + 「打开系统设置 · 登录项」、③通知授权四档脚注 + 「打开系统设置 · 通知」、④「监听」分组第二个开关（P5.3c 加的，稿那一段标题还叫「废纸篓」）、⑤`:178`/`:215` 两格脚注（实现已经把它们改成实话）、⑥sheet 实机 560 且清理栏仍需滚动。**这些是实现侧已落地的既有事实，不是新需求**；改稿会作废 09 的像素基线，所以和 S1/S3/S4 一样排到集成阶段统一做，本轮只登记。
