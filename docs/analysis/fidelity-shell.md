# 01 概览 · 09 设置 · 设计稿 ↔ 实现 逐元素对照（fidelity-shell）

> **结论先行**：`01-dashboard` 与 `09-settings` 的**结构与文案口径**和实机高度一致——概览页四卡（存储/负载/可释放/最近操作）、设置四 tab + 确认弹窗的层级、文案、开关默认态都对得上，且比 monitor 页诚实（虚数值一律走占位/"尚未采样"，不编数字）。
> 主要差异集中在**全站几何/侧栏**层（与 monitor 同源）：
> - **S1 · 侧栏 footer 画错〔P38f 现读改判：**已落地**，这条作为"待改"过期〕**：原判"01-dashboard 仍画成分隔线 + 设置 nav-item，需补一个侧栏 footer 组件"——组件早就在（`docs/design-system/tokens.css:286` 起 `.sidebar-footer`，含 `.vol-line`/`.vol-bar.low`/`.foot-btn`），稿侧 **20 张里 16 张在用**（21 处实例，含本页 `docs/design-system/screens/shell/01-dashboard.html:43`）；落地的动作是 `0c61fbf`（2026-09-30「十张稿统一侧栏footer组件+清洗占位数字」），**它比写下这条判定的 `e96c95bc` 还早一个提交**（同日、可 `git merge-base --is-ancestor` 验），所以这条从出生就是假的。实机一侧核对仍对得上：`Sources/MacMaster/MainWindow.swift:123` 是 `Divider()`，:125 调 `volumeFooter`（定义 141–166），其下一个「设置」按钮（:128-135）。**这一族现在真正还开的只有三处侧栏面**：`docs/design-system/screens/mmui/components.html:141-142` 仍是旧的"1px 线 + 设置 nav-item"（全站唯一残留的旧画法），`docs/design-system/screens/mmdisk/04b-disk-confirm.html:76-84` 与 `docs/design-system/screens/mmdisk/04e-disk-rescan.html:45-53`（另一块在 :100-108）**整块没画 footer**——不是画错，是没画；`mmui/05-states.html` 无侧栏，不在这一面内。改这三处要重渲染，排口见 `release-readiness.md` §7.35。
> - **I10a · 侧栏宽度（P6.2b 重测后已落地）**：原记"`NavigationSplitView(min:200, ideal:220, max:280)` 实测分隔线在 x=220"——**这个数复现不了**。P6.2b 在 raw @2x PNG 上量到改前实机是 **200pt**（分隔线 x=401px），并用两次否证实验确定机制：往 SwiftUI 自己写的 `NSSplitView Subview Frames…` 里手写 260pt 不被读、把 `ideal` 改成 240 重构建仍出 200pt，**首屏宽度取的是 `min`**。现已改 `min:220`，实测 440px@2x = 220pt，与稿 `--sidebar-w: 220px` 对齐。全过程见 `fidelity-guardian.md` §6.3（同一处骨架，两页共用）。
> - **I10b · 标题栏（P38a 现读改判：已落地，且"实现该改"这一半本来就无可改之物）**：`--titlebar-h` 现在就是 **52px**（`tokens.css` 第 31 行，c74f045 那笔共享层收口改的、第 317 行在引用它）；实现侧从来没有"标题栏高度"这个常量——全仓 Swift 只有窗口样式那 1 处 `titlebar` 命中，52pt 是 AppKit 自己画的标题栏，不由我们出。此前这条写的"令牌 38 / 待集成阶段落地"整句过期。
> - **S3 · 内容底色**：概览用 `MMColor.contentBackground`，令牌 `--c-content-bg` 是白/`#282828`（controlBackground 档）；monitor 页实测页面底是 `windowBackgroundColor`（`#2B2B2C` 级）。两页"卡浮在页面上"的对比度是否一致需真机核对。
> - **S4 · 缺 under-page 卡片 token**：monitor 私有 `card()` 用 `cardBackground`(underPage)，本页 `MMCard` 用 `controlBackground`——令牌层尚无统一 under-page 变体（monitor 路线已提，本页不重复）。
>
> 另：设计稿内有**占位/虚构数字**（`2.4 GB`/`46`/`3.5 GB`/`3 / 20`/`Macintosh HD 94%`），实机均为动态值或空态，属 S2 类，已在 §3 逐条标出。〔**P38f 现读收窄**：这一串里侧栏那一族（`2.4 GB`/`46`/红点）已由 `0c61fbf` 从 `01-dashboard.html` 删净，判据见 §1 表格「侧栏尾数」那一行——**但"这一族清完了"不等于全站侧栏干净**：现读全仓 `class="tail"` 还有 **9 行 / 4 份文件**（`components.html:135/136/139`、`08-optimizer.html:576/751`、`03c-uninstaller-trash.html:85/86`、`03e-uninstaller-watch.html:92/93`），后两组是实机同源的真值形态，03c/03e 那两格给"应用卸载"挂尾数则**实机永远不画**（`MainWindow.swift:105-110` 只给清理行挂），这一条是 P38f 新发现、登记在 `release-readiness.md` §7.35；剩下的都还在，且各自情况不同——`3.5 GB` 在 `:95` 与 `:98` 两处，`Macintosh HD` 那档现在是**组件示例值**（`:47` 的 `6% 可用` 与 `:49` 容量条 `width:94%`，画的是"快满了"那一档、不是本机读数），`3 / 20` 现在住在 `09-settings.html`（`:241`、`:341`、`:541`），而且 `:545` 已经自己写明"3 / 20 是示例数"，那一处算已按本条要求标过。〕
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
| 设计稿 | `docs/design-system/screens/shell/01-dashboard.html`、`09-settings.html`（P38e 起 09a–09i 九块 artboard；改稿前是 09a–09e 五块） |
| 渲染 | `cd docs/design-system && ./render.sh screens/shell/01-dashboard.html 1160 780` / `09-settings.html 1100 6800`（2x）。**P38e 现读更正这一格**：它此前写的是 `1160 1500`，而当时入库的 PNG 是 2200×7800（=1100×3900 CSS）——两者从来不是同一条命令，登记错了。`render.sh` 的 `--window-size` 高度**就是截图高度，Chrome 不会自动展开整页**（本轮先用 1500 试渲染，只拿到 2200×3000，下半截直接截断），所以高度必须按页面真实 `scrollHeight` 给：09 现在实测 6741，取 6800 |
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
| 模块列表「系统清理 2.4 GB」「应用卸载 46」 | `MainWindow.swift:105-110` | ✅（P38f 现读，稿侧已清） | 实机仅在 `dashboard.reclaimState == .measured` 时显示真实值，否则该格为空（不显示 "—"）——代码一侧照旧；**稿子一侧这两个值在 `01-dashboard.html` 已经没有了**（同一笔 `0c61fbf`「清洗侧栏虚构占位」删的，与下一行那个红点同一批），现在全站只剩 `components.html:135-136` 还写着 `2.4 GB`/`46`，而那一页是元素清单、tail 在那里是**组件示例**不是页面主张 | 低 | 设计稿该改 S2 → **概览稿已落地（P38f）**，`01-dashboard` 仍写死的占位只剩内容区「可立即释放 3.5 GB」（:95 与 :98 那颗按钮） |
| **侧栏 footer（S1）** | `MainWindow.swift:141-166` `volumeFooter`（P38f 现读：调用在 `:125`，其上是 `Divider()` `:123`、其下是「设置」按钮 `:128-135`） | ✅（P38f 现读） | 实机 = `Macintosh HD` + 百分比 + 红色容量条（低空间转红）+ 带边框「设置」按钮；**稿子这一侧已经改成同一个组件**——`tokens.css:286` 的 `.sidebar-footer` 在 16 张稿里画着，本页 `01-dashboard.html:43` 就是其中一处；原判"稿子画成分隔线 + 设置 nav-item"由 `0c61fbf` 作废，而那条判定写在它之后的 `e96c95bc` 里，**出生即假** | 中 | 设计稿该改 S1 → **稿侧已落地（P38f）**；只剩 `components.html:141-142` 的旧画法与 04b/04e 三处未画 footer，判据见本文开头「结论先行」的 S1 那一格 |
| 隐私守护红点 | `01-dashboard.html:40` | ✅（P36 现读） | 稿子 :40 现读是纯 nav-item、无红点——commit `0c61fbf`「清洗侧栏虚构占位（含隐私守护红点）」已删；实机 `SidebarView`（`MainWindow.swift:61` 起）本无模块红点逻辑 → 两侧一致，红点已不存在 | 低 | 设计稿该改 S2 → **稿侧已落地** |
| 状态栏「4 个卷 · 文件系统 APFS · 上次清理 3 天前」 | `MainWindow.swift:277-301` `statusBar` | ❌ | 稿子多画"索引正常""Spotlight 已排除 2 个路径"——实机状态栏**无这两段**（代码未输出） | 低 | 设计稿该改 S2 |
| 侧栏宽 220（`--sidebar-w`）/ 标题栏 52（`--titlebar-h`，P38a 现读：令牌已由 38 改为 52） | `MainWindow.swift:22`（`.navigationSplitViewColumnWidth`，P29 现读：此前引 `:18` 落在那段解释注释上） / 实机 52pt | ✅ / ✅ | **P6.2b**：侧栏改前实测量 **200pt**（不是这里原记的 220），现 `min:220` 后实测 220pt，本条关闭；**P38a 现读**：标题栏令牌已改为 52px、与实机同源，两侧都不欠，本条也关闭（实现侧无标题栏高度常量） | 低 | I10a / I10b **都已落地**（P38a） |
| 「可释放空间」卡右上「全部」（稿 `01-dashboard.html` 画的是 `全部 + chevron-right`） | `MainWindow.swift` `cardHeader("可释放空间", trailing:)` | ✅（P6.2b 起） | 改前只有一个蓝色"全部"，读起来像筛选开关；稿里那半枚 `chevron.right` 才是"点了会离开这一页"的唯一提示。现已补 `全部 ›`（`p62b-fidelity/02-dashboard-history-full.png`） | 低 | 实现该改 I11 → **已落地** |
| 网络 / 磁盘 I/O 迷你图 `.spark i{flex:1}`（12 等分槽） | `MMDesign.swift` `MMSparkline`（`slotCount` 固定、`maxWidth:.infinity` 等分） | ✅（P6.2b 起） | 改前每根钉死 10pt 靠左排：首帧只有一根细柱孤零零贴在左边，读起来像图坏了，且柱子随采样次数往右爬、同一张图前后宽度不一样。现横轴满宽、柱从右端往左长（`01` 首帧 vs `02` 满轴两张） | 中 | 实现该改 I12 → **已落地** |

## 2. 09-settings 逐元素（09a–09e）

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| sheet「500 宽 + 高度按内容」+ MMPageHeader「设置」+ xmark 关闭 | 稿 `09-settings.html:12`（`.sheet{position:relative;width:500px;height:auto…}`）；实机 header `SettingsView.swift:21-31`、`.frame(width:500,height:560)` `:59` | ❌→P29 改 | **实现把高度钉死在 400**：「清理」这一栏有 5 个 Section，400 高只露到第二组的标题行（`docs/verification/p29-before/cleaner.png`），用户翻不到下面的行，看着就像功能不在——这正是"设置几乎不可用"里最直观的一条。现提到 560，同一栏露到「监听」第一行（`p29-after/cleaner.png`），**「删除历史」「排除项」仍要滚动**：差距从"看不全"变成"仍要滚"，没有变成"已一致"。稿那一格是 CSS 才办得到的按内容展开，实机 sheet 需要一个确定高度（`:56-58` 记着这个理由；顺带一条：那段注释写的"8 个分组"数错了，现读是 5 个 Section，注释是编译输入、改它要重跑全部取证，本轮只在文档里记这笔） | 中 | 实现该改 I15 → **已落地**；稿子该改 S2 → **P38e 已改稿**：09a 的 cap（`:84`）写明"宽 500pt 由实现钉死、实机高 560pt、Form 内滚动"，09c 里画了一条红虚线 `.fold`（样式 `:66`、元素 `:261`，绝对定位在 sheet 顶往下 560px）标"以下要滚动"，浏览器实测该线正好切在「监听」第一行的脚注上（`监听` 分组 `228-236`、线在 560、分组起点 473）。**这条线只是稿面标记，不当像素基线** |
| 设置页的**入口**（稿只画了侧栏底部那一枚按钮） | 应用菜单「设置…」+ ⌘, `MacMasterApp.swift:46-49`；侧栏按钮 `MainWindow.swift:128-135`；菜单栏下拉「设置...」`MenuBarManager.swift:354-356`→`386-391`（发 `.mmOpenSettings`，`SystemSettings.swift:40`），三处收在 `MacMasterApp.swift:93-95` | ❌→P29 改 | 改前只有侧栏那一枚：主窗口一收进菜单栏，全 app 没有任何地方能进设置；⌘, 与应用菜单那一格是空的，而 macOS 用户的第一个反射就是这两处。现三处入口都在，且不再各写各的状态 | 中 | 实现该改 I13 → **已落地**；稿子该改 S2 → **P38e 已改稿**：新增 09f（`09-settings.html:364-426`）画三处入口——应用菜单那一支、主窗口侧栏底部那一枚、菜单栏下拉那一支，条目文字逐字取自 `MM_DUMP_MENUS=1` 的 stderr 转储（`docs/verification/p29-after/00-*.log`），**不用合成点击**；cap 里同时记了两处 dump 口径不一样（应用菜单会把快捷键拼成 `⌘,`，菜单栏那一支只拼标题和子菜单的 ` ▸`） |
| 系统设置深链（稿 09 没画这一层） | `MMReveal.openSystemSettings(pane:)`（`MMDesign.swift:519-522`）+ `MMSettingsPane`（`SystemSettings.swift:16-33`） | ❌→P29 改 | 改前调用方传的是**整串 URL**，而这一支函数自己还要拼 `x-apple.systempreferences:` 前缀——拼出来是双前缀死链：清理页的权限横幅按下去系统设置一动没动（实测 `docs/verification/p29-panes-v3/pane-urls.log` C 档），而 `NSWorkspace.open` 不返回成败，所以画面也没有任何失败痕迹。现参数收成枚举，scheme 全仓只在 `SystemSettings.swift:25` 出现，"手写 URL 当参数"没有编译期入口 | 高 | 实现该改 I13 → **已落地** |
| 四 tab 分段（通用/监控/清理/关于） | `SettingsView.swift:33-42` `Picker(.segmented)`；档位枚举 `SettingsTab` `:367-380` | ✅ | 一致 | — | — |
| 09a 语言（简/英）、启动（开机启动/最小化菜单栏） | `SettingsView.swift:65-120`（语言 `67-83`、启动 `85-116`） | ⚠️ | 视觉一致；**稿子以前只画了"注册失败橙色脚注"没画"等系统批准"这一档**（见下两行，P38e 已补 09g）。**语言是死开关**，见下方补记 | 低 | ~~待集成阶段落地（错误态规格）~~ 语言项 P7a 已处理 / 状态可见项 I14 已落地、稿子待改 S2 → **P38e 已改稿**（语言那一格画成禁用态：分段 `.seg.off` 在 `09-settings.html:110`、脚注 `:111` 逐字照实现；四档见 09g） |
| 09a 登录项：开关拨上去以后的真实状态 | `SettingsView.swift:90-110`；状态来源 `LaunchBehavior.swift:31`（`isOn`）`:37-46`（`statusCaption`）`:49`（`needsSystemSettings`） | ❌→P29 改 | 改前只认 `.enabled`：`SMAppService` 注册成功但落在 `.requiresApproval`（macOS 要用户在「登录项与扩展」里再点一次允许）时，开关自己弹回"关"、什么话也不说——用户只会认为它坏了。现这一档显示"已注册，但要你再允许一次"，并配「打开系统设置 · 登录项」出口；`.notFound`（从 `.build` 直接跑）也各有一句。**照片只证到"没话说"的那一档**：这台机器实测 `.enabled`，画面是默认那句（`p29-after/general.png`），`.requiresApproval`/`.notFound` 两句要真换一台机器的系统状态才拍得到，本轮只有代码与单测凭据 | 高 | 实现该改 I14 → **已落地**；稿子该改 S2 → **P38e 已改稿**：新增 09g（`09-settings.html:428-471`）把四档并排画全（`.requiresApproval` / `.notFound` / 注册抛错 `lastError` / `.enabled` 与未注册走默认那句），文案逐字照 `LaunchBehavior.swift:37-46`、`:20`+`SettingsView.swift:90-92`；cap 里如实写明**只有默认那一档有照片**（这台机器实测 `.enabled`），另三档只能照代码分支画、不是能量合成输入造出来的 |
| 09b 通知：两个开关之上的系统授权状态 | `SettingsView.swift:142-163`（脚注 `147-151`、跳转按钮 `152-157`、两开关 `158-159`）；判据 `NotificationStatus.swift:27-42`（`caption`）`:46-51`（`needsSystemSettings`），每次进这一栏重读 `.task` `SettingsView.swift:169` | ❌→P29 改 | 改前这里**从没读过系统的授权状态**：开关说的是"希望通知"，系统记的是"允不允许发通知"，用户在系统设置里拒过一次以后开关照样拨得动、`requestAuthorization` 也不会再弹（只在"未决定"时有效），于是这一栏看着一切正常、实际一条通知都发不出去。现在这一档写在两个开关**上方**（摆下方就要滚动才看到，而"要滚动才看到"正是这一页被报不可用的形状），并配「打开系统设置 · 通知」。**这一档在这台机器上是真实状态、不用夹具**：用户此前拒过一次，改后画面第一行就是那句橙色的"系统里已拒绝…"加跳转按钮（`p29-after/monitor.png`），而改前那一栏在 400 高下**连标题都在折线以下**（`p29-before/monitor.png` 只拍到「刷新频率」为止），下面那两个开关无论拨成什么、系统这边一直是"已拒绝"——这一条和上面清理栏那句假脚注，是本轮两处**在改前照片里就直接看得见**的假话，其余各条要靠代码才看得出来 | 高 | 实现该改 I14 → **已落地**；稿子该改 S2 → **P38e 已改稿**：新增 09h（`09-settings.html:473-520`）画四档（`.denied` / `.notDetermined` / `.provisional` / `nil`，文字逐字照 `NotificationStatus.swift:31-38`，④ 不配跳转按钮的理由在 `:44-45`），并写明**①那一档就是这台机器的现状**（照片 `p29-after/monitor.png` 第一行），09b 的 cap 也补了"脚注排在两个开关**上方**"这一条位置合同。**账（稿子不改、只登记）**：实现那两句脚注本身有两处说得不准——① `.notDetermined` 那句写"把**上面**任一开关打开时才会弹授权询问"，可这一句就排在两个开关**上方**，指代相反（`SettingsView.swift:144-146` 那条注释定的就是位置）；② "什么时候弹询问"也不由这一栏决定，真正的调用点在 `MenuBarManager.swift:219-228` 的采样循环里，而 `notifyHighCPU`/`notifyLowMemory` 出厂默认就是开（`AppSettings.swift:156-157`），所以全新系统上应用一起来就已经弹过了，不是等用户去拨。③④两档没有这个问题。**改源码要单独授权，稿子照现状画**（09h 的 cap 末尾同一段话） |

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
| 09c 扫描范围 4 + 安全 2 + 监听 + 删除历史 + 排除项 | `SettingsView.swift:172-270`（扫描 `174-185`、安全 `187-190`、监听 `192-204`、删除历史 `206-228`、排除项 `230-259`） | ⚠️ | 实机「监听」分组有**两个**开关（`watchTrashForResidualCleanup` `193` + `watchAppFolderChanges` `198`，后者 P5.3c 加的），**改稿前**稿 09c 那一段标题还是「废纸篓」、只画了一个；"台账条目 3/20" 实机 N 动态、排除项默认空列表（稿子示例值） | 低 | 设计稿该改 S2 → **P38e 已改稿**：分组改名「监听」并补第二个开关（`09-settings.html:228-236`，逐字照 `:193`/`:198` 两行的标题与脚注），五组标题在 cap（`:181`）里列全；"3 / 20" 与排除项两条示例值在 cap 里标成"稿子示例值，实机 N 动态 / 默认空列表"。另见 §3 那两条**假脚注**的更正 |
| 09c 扫描范围/排除项两处脚注的口径 | `SettingsView.swift:179-184`、`:254-258` | ❌→P29 改 | 改前两句写的是"设置已持久化；清理模块接入这些开关后生效""清理模块消费该列表后生效"（第一句在 `p29-before/cleaner.png` 里就印在画面上）——**那句是假的**：四个开关从 P29 现读起就有消费点（清理页扫描、概览「重新测量」），排除项列表就是清理页「已排除」面板读的那一份。假话的代价不是"说多了"，是用户以为整页都没接、根本不去拨它 | 高 | 实现该改 I14 → **已落地**（文案改成实话；稿 `:178`/`:215` 那两格当时还留着旧的假话 → **P38e 已换**：扫描范围脚注在 `09-settings.html:218`、排除项脚注在 `:257`，两句逐字照实现的 `SettingsView.swift:179-184`/`:254-258`） |
| 09c N=0 时「清空删除历史」置灰、historyFileURL=nil 时整行降级 | `SettingsView.swift:226-227`、`:220-224` | ❌ | 两种降级态**改稿前**稿子没画（09c 画的是有记录启用态）；档位必须照代码存在 | 低 | 设计稿该改 S2 → **P38e 已改稿**：新增 09i（`09-settings.html:522-552`）画这两档，cap 里明写"由代码分支决定、没有实机照片"（拍 nil 那一档要真换一台拿不到 Application Support 的机器，不是能量合成输入造出来的） |
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
- **设计稿该改（S 类）**：S1（侧栏 footer，全站）→ **P38f 现读：稿侧已落地，这条从写下那天就是假的**（组件在 `tokens.css:286`，16 张稿在用；改稿动作是 `0c61fbf`，比这份审计的 `e96c95bc` 早一个提交）——残留只有 `components.html:141-142` 的旧画法与 04b/04e 三处没画 footer，判据见开头「结论先行」的 S1 那一格、排口见 `release-readiness.md` §7.35、S2（占位/虚构数字：2.4GB/46/3.5GB/3/20/94%/红点/索引正常/Spotlight 排除/台账降级态未画；**P29 追加的六条 P38e 已全部改稿**——09 补了 ⌘,/应用菜单/菜单栏下拉三个入口（09f）、登录项四档（09g）、通知四档（09h）、09c 分组改名「监听」并补第二个开关、`:178`/`:215` 两格假脚注换成实话、sheet 标实机 560 且用红虚线标"以下要滚动"；这一批里只剩**台账降级态 09i 无照片**（只能照代码分支画）与**其他页的占位数字**未清）。
- **两边都改（0 条）**。
- **待集成阶段落地（全站几何，只出规格不落地）**：~~I10b（标题栏 52 vs 38）、S3（content 底色档）~~——**P38a 现读作废这两件**：`--titlebar-h` 已是 52px、`--c-content-bg` 有 3 处 `var()` 引用且实现侧 23 处命中，两项都早在 c74f045 那笔落地。这一条现在只剩 **S4**（under-page 卡片 token：`--c-card-content` / `--c-card-under-page` 已声明、**`var()` 消费者 0 处**，接线还是删要逐屏决定）。**I10a（侧栏）已由 P6.2b 落地。**
- **待真机测量（⚠️）**：存储堆叠条 9 段、CPU/内存仪表指针角度与口径、内存构成条、可释放行高图标对齐、S3 两页对比度一致性。

## 4. 没能验证到的部分（诚实列出）

1. 概览折叠线以下的**逐像素**核对：P6.2b 的两帧（1100×760pt 视口）已把内存构成条、可释放三行、最近操作四行**拍进画面**（无需滚动），但段宽/行高这类数还没逐个量——`02-dashboard-history-full.png` 是 raw PNG，可直接用 `Scripts/pixel-probe.swift` 续量。
2. 设置各 tab 的滚动截断点：P29 已在 560 高下拍到四栏（`docs/verification/p29-after/{general,monitor,cleaner,about}.png`，脚本 `Scripts/p29-settings-capture.sh`），09c 的「删除历史」「排除项」两组**仍在折线以下**、没进照片；逐屏"滚到底"的截图通路还没有。
2b. 登录项的 `.requiresApproval` 与 `.notFound` 两档、通知的 `.notDetermined`/`.authorized` 两档：**这台机器拿不到**（前者系统真实状态是 `.enabled`，后者是 `.denied`，见上面 §2 两行）。这几档只有代码 + 单测凭据，没有照片；要拍就得动系统的登录项/通知授权设置，那是用户机器的真实状态，本轮没动。
3. 浅色 vs 深色的**交叉**核对：P6.2b 两帧都是 `MM_APPEARANCE=light`（与稿同源），暗档这一轮没重拍；侧栏 220pt、`全部 ›`、sparkline 满轴在暗档下的对比度未量。
4. S3 跨页对比度（概览 contentBackground vs 实机 windowBackground）需两页同框真机截图。

## 5. 提请协调者（协调路 #53 落）

1. **S1 侧栏 footer 组件（P38f 现读改判：这一条作为待办作废，剩下的只是三处没跟上的侧栏）**：`.sidebar-footer` 早就在 `docs/design-system/tokens.css:286`（容量行 + 容量条 + `.foot-btn` 带边框设置按钮），"八张稿一起换"这件事由 `0c61fbf`（2026-09-30，十张稿）做完、后来新增的稿各自从一开始就在用，现读 **20 张里 16 张在用**。因此本条不再提请任何人做组件；**唯一还开的是三处侧栏面**：`docs/design-system/screens/mmui/components.html:141-142`（全站唯一还在画"1px 线 + 设置 nav-item"的一格，它同时带着 `.mini-sidebar { width: 216px }` 那一处，见 `coordination-audit.md` §4「直接做③」末段把 216 排进 v1.4 的那半句）与 `docs/design-system/screens/mmdisk/04b-disk-confirm.html:76-84`、`docs/design-system/screens/mmdisk/04e-disk-rescan.html:45-53`（同文件另一块在 :100-108）——后两者是**整块没画 footer**，不是画错。这三处的改法就是照 `01-dashboard.html:43-51` 抄那一块，但改完要重渲染那三页（`components.png` 上一轮实测与 HEAD 字节相同，所以它一旦真改了就会真变），排口与代价见 `release-readiness.md` §7.35。
2. **I10b/S3/S4 全站几何修正（P38a 现读改判：前两件已落地，剩的那件不是"调令牌"）**：`--titlebar-h` 已是 52px、`--c-content-bg` 与两个卡底令牌（`--c-card-content` / `--c-card-under-page`）也都已声明（同一笔 c74f045），**所以"改动会作废全部模块像素基线"这件事已经发生过一次**；真正仍开的是**那两个卡底令牌至今 0 处 `var()` 引用**——接线还是删要逐屏决定，判据见 `coordination-audit.md` §2。**这一条不等决定的部分（I10b/S3）本轮已翻，S4 那半句等 §5 第 2 条**。**I10a（侧栏）P6.2b 已落地**，但落地位置是 `MainWindow.swift:22` 的 `min:`（首屏宽度只认 `min`，`ideal` 与 AppKit 那条持久化记录都不参与），令牌 `--sidebar-w: 220px` 本来就是对的、没动；顺带一条待办：`--sidebar-w-min: 200px` 全仓从未被引用（仅 `tokens.css:33` 声明处一处命中），而应用现在也拖不到 200，要么删令牌要么把稿改成 220。
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
3. **09c 降级态补画**：~~出规格给 mmuninstaller/清理路线补 artboard~~ → **P38e 已落地**：09i（`09-settings.html:522-552`）画 N=0 置灰与 `historyFileURL=nil` 整行降级两档，规格来源就是 `SettingsView.swift:220-224`/`:226-227` 两个分支，cap 里如实标"没有照片"。
4. **S2 占位数字清洗**：稿内 `2.4 GB`/`46`/`3.5 GB`/`3 / 20`/`94%`/`红点`/`索引正常`/`Spotlight 已排除` 标"示例值/虚构"或改为动态占位，避免被当成实测。〔**P38f 现读：这一串分三档**——①**概览稿侧栏那一族（`2.4 GB`/`46`/红点）已清完**（`0c61fbf`），但这三个**具体串**今天只剩元素清单 `components.html:135/136/139` 还当组件示例写着；侧栏尾数这一族全仓还有 6 行活着（`08-optimizer.html:576/751`、`03c-uninstaller-trash.html:85/86`、`03e-uninstaller-watch.html:92/93`），03c/03e 那两格是 P38f 新发现的"实机永远不画"的形状差，见开头那句与 `release-readiness.md` §7.35；②`3 / 20` 在 09 稿重画时已按本条要求标了"示例数"（`09-settings.html:545`）；③剩下的 `3.5 GB`（`:95`/`:98`）、`索引正常`/`Spotlight 已排除 2 个路径`（`:180`/`:182`）在本页**原样还在**，仍是要清洗的那一半，只是它不再需要协调层统筹——纯本模块改稿，代价是重渲染 `01-dashboard.png`，排口见 `release-readiness.md` §7.35。〕
5. **09-settings 需要一次同步（P29 之后稿子落后实现两轮）**：要补的是①设置入口（⌘, 与应用菜单那一格、菜单栏下拉「设置...」，稿只画了侧栏按钮）、②登录项"待系统批准"档 + 「打开系统设置 · 登录项」、③通知授权四档脚注 + 「打开系统设置 · 通知」、④「监听」分组第二个开关（P5.3c 加的，稿那一段标题还叫「废纸篓」）、⑤`:178`/`:215` 两格脚注（实现已经把它们改成实话）、⑥sheet 实机 560 且清理栏仍需滚动。**这些是实现侧已落地的既有事实，不是新需求**；改稿会作废 09 的像素基线，所以和 S1/S3/S4 一样排到集成阶段统一做，本轮只登记。
   **→ P38e（2026-10-14）六条全部改完，这一条收口**：`09-settings.html` 从 319 行涨到 552 行，artboard 由 09a–09e 五块变 09a–09i 九块（新增 09f 三入口 / 09g 登录项四档 / 09h 通知四档 / 09i 删除历史两档降级），②③④⑥ 逐条落在 §2 对应那六行的"归属"列里。**这一刀只动 09，没有和 S 系列合并**（S1 侧栏 footer、S2 占位数字、S3/S4 全站几何各自另算）——按 #53 的约定"一次只作废一批基线"，09 的像素基线已经作废：`09-settings.png` 按全高重渲染为 **1100×6800 CSS（@2x 2200×13600）**，旧图 1100×3900 那一版连同它上面"五块 artboard"的读数一起作废。稿里那条 560 红虚线是**标记不是基线**（各层高度按元素各自画、不由 560 反推），这条在 09c 的 cap 里写死了，免得下一轮有人拿它当量出来的数。
