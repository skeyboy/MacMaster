# 01 概览 · 09 设置 · 设计稿 ↔ 实现 逐元素对照（fidelity-shell）

> **结论先行**：`01-dashboard` 与 `09-settings` 的**结构与文案口径**和实机高度一致——概览页四卡（存储/负载/可释放/最近操作）、设置四 tab + 确认弹窗的层级、文案、开关默认态都对得上，且比 monitor 页诚实（虚数值一律走占位/"尚未采样"，不编数字）。
> 主要差异集中在**全站几何/侧栏**层（与 monitor 同源）：
> - **S1 · 侧栏 footer 画错〔P38f 现读改判：**已落地**，这条作为"待改"过期〕**：原判"01-dashboard 仍画成分隔线 + 设置 nav-item，需补一个侧栏 footer 组件"——组件早就在（`docs/design-system/tokens.css:287` 起 `.sidebar-footer`，含 `.vol-line`/`.vol-bar.low`/`.foot-btn`），稿侧 **20 张里 19 张在用**（实例 25 处；**P41f 现读**：旧记 16 张 / 21 处，P39 之后 04b/04e/09 等各自装上了组件，唯一不含侧栏的是 `mmui/05-states.html`——它整页没有 `class="sidebar"`，是组件状态页，不算缺口。含本页 `docs/design-system/screens/shell/01-dashboard.html:43`）；落地的动作是 `0c61fbf`（2026-09-30「十张稿统一侧栏footer组件+清洗占位数字」），**它比写下这条判定的 `e96c95bc` 还早一个提交**（同日、可 `git merge-base --is-ancestor` 验），所以这条从出生就是假的。实机一侧核对仍对得上：`Sources/MacMaster/MainWindow.swift:123` 是 `Divider()`，:125 调 `volumeFooter`（定义 141–166），其下一个「设置」按钮（:128-135）。**这一族现在真正还开的只有三处侧栏面**：`docs/design-system/screens/mmui/components.html` 改稿前第 141-142 行 仍是旧的"1px 线 + 设置 nav-item"（全站唯一残留的旧画法），`docs/design-system/screens/mmdisk/04b-disk-confirm.html` 改稿前第 76-84 行 与 `docs/design-system/screens/mmdisk/04e-disk-rescan.html` 改稿前第 45-53 行（另一块在 :100-108）**整块没画 footer**——不是画错，是没画；`mmui/05-states.html` 无侧栏，不在这一面内。改这三处要重渲染，排口见 `release-readiness.md` §7.35。〔**P39 三处全改完、九张 png 重渲染**：`components.html:141` 现读是 `<div class="sidebar-footer">`，04b 第 84-92 行与 04e 两块补了 footer；这一族今天只剩 §7.35 末段那两处"只登记没动"的账，判据与像素在 `release-readiness.md` §7.36。〕
> - **I10a · 侧栏宽度（P6.2b 重测后已落地）**：原记"`NavigationSplitView(min:200, ideal:220, max:280)` 实测分隔线在 x=220"——**这个数复现不了**。P6.2b 在 raw @2x PNG 上量到改前实机是 **200pt**（分隔线 x=401px），并用两次否证实验确定机制：往 SwiftUI 自己写的 `NSSplitView Subview Frames…` 里手写 260pt 不被读、把 `ideal` 改成 240 重构建仍出 200pt，**首屏宽度取的是 `min`**。现已改 `min:220`，实测 440px@2x = 220pt，与稿 `--sidebar-w: 220px` 对齐。全过程见 `fidelity-guardian.md` §6.3（同一处骨架，两页共用）。
> - **I10b · 标题栏（P38a 现读改判：已落地，且"实现该改"这一半本来就无可改之物）**：`--titlebar-h` 现在就是 **52px**（`tokens.css` 第 31 行，c74f045 那笔共享层收口改的、第 318 行在引用它——**P41f 现读**：原文写 317，`--sidebar-w-min` 那一笔 +1 顶的，散文式坐标不在量尺与重指工具的覆盖面里）；实现侧从来没有"标题栏高度"这个常量——全仓 Swift 只有窗口样式那 1 处 `titlebar` 命中，52pt 是 AppKit 自己画的标题栏，不由我们出。此前这条写的"令牌 38 / 待集成阶段落地"整句过期。
> - **S3 · 内容底色**：概览用 `MMColor.contentBackground`，令牌 `--c-content-bg` 是白/`#282828`（controlBackground 档）；monitor 页实测页面底是 `windowBackgroundColor`（`#2B2B2C` 级）。两页"卡浮在页面上"的对比度是否一致需真机核对。
> - **S4 · 缺 under-page 卡片 token**：monitor 私有 `card()` 用 `cardBackground`(underPage)，本页 `MMCard` 用 `controlBackground`——令牌层尚无统一 under-page 变体（monitor 路线已提，本页不重复）。
>
> 另：设计稿内有**占位/虚构数字**（`2.4 GB`/`46`/`3.5 GB`/`3 / 20`/`Macintosh HD 94%`），实机均为动态值或空态，属 S2 类，已在 §3 逐条标出。〔**P38f 现读收窄**：这一串里侧栏那一族（`2.4 GB`/`46`/红点）已由 `0c61fbf` 从 `01-dashboard.html` 删净，判据见 §1 表格「侧栏尾数」那一行——**但"这一族清完了"不等于全站侧栏干净**：现读全仓 `class="tail"` 还有 **9 行 / 4 份文件**（`components.html:135/136/139`、`08-optimizer.html:576/751`、`03c-uninstaller-trash.html:85/86`、`03e-uninstaller-watch.html:92/93`），后两组是实机同源的真值形态，03c/03e 那两格给"应用卸载"挂尾数则**实机永远不画**（`MainWindow.swift:105-110` 只给清理行挂），这一条是 P38f 新发现、登记在 `release-readiness.md` §7.35；剩下的都还在，且各自情况不同——`3.5 GB` 在 `:95` 与 `:98` 两处，`Macintosh HD` 那档现在是**组件示例值**（`:47` 的 `6% 可用` 与 `:49` 容量条 `width:94%`，画的是"快满了"那一档、不是本机读数），`3 / 20` 现在住在 `09-settings.html`（`:241`、`:341`、`:541`），而且 `:545` 已经自己写明"3 / 20 是示例数"，那一处算已按本条要求标过。〔**P39 现读把这一条的侧栏那一半翻了**：上面那句"03c/03e 那两格给'应用卸载'挂尾数"里那个值是 `45`，写在两份稿的旧第 86、93 行，本轮已删（实机永远不给非清理行挂尾数），所以"9 行 / 4 份文件"现读成 **7 行 / 4 份文件**（`grep -rn 'class="tail' docs/design-system/screens --include='*.html'`：components 3、08 2、03c 1、03e 1，剩下的都是合法形状），两页 png 同轮重渲染，判据在 `release-readiness.md` §7.36。〕
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
| 设计稿 | `docs/design-system/screens/shell/01-dashboard.html`、`09-settings.html`（P38e 起 09a–09i 九块 artboard；改稿前是 09a–09e 五块）、`01b-dashboard-undo-states.html`（**P55 新起**，四块画板，只画概览「最近操作」那一行的撤回态——它为什么另起一稿而不改进 `01-dashboard.html`，见 §6） |
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
| 最近操作：撤回/已撤回/废纸篓已清空 | `MainWindow.swift:638-689`（**P55 现读重指**：`recentCard` 在 `:638-661`、`recentRowView` 在 `:663-689`，三分支依次是 `:676`（`isUndone` → `:677`「已撤回」）、`:678`（`canUndo` → `:679`「撤回」按钮）、`:681-684`（都读不到落点 → `:684` 那枚徽章）；此前这一格写 `:626-687`，而 `:626` 现读是 `reclaimRowView` 里的 `Text(MMFormat.bytes(row.bytes))`——**落在另一张卡的行上**，不是空白行，所以门禁一路放行，与 §1.2 那条 P35b 注同一类漂移） | ✅→❌（**P55 两头各翻一半**：措辞那一半改判，"三态都覆盖"那一半现读作废） | **先更正这一格原来那句 ✅**：它写的是"三种态都覆盖，文案一致"，而稿侧现读**只画了一态**——`01-dashboard.html:162-170` 那三行的右列是「撤回」两枚 + `badge warn`「查看」一枚，**「已撤回」与「废纸篓已清空」这两个串在全稿现读各 0 处**（`grep -c` 现读）。也就是态没覆盖、文案也没有可对的对象；而 `badge warn`「查看」那一支**实机根本不画**（`:665-667` 只有勾选/警告两种图标，右列除 `:677`/`:679`/`:684` 没有第四支）。这一条查不出来的理由与本文开头 P29 那句是同一个：**画面上没有的行，永远不会被判成差异**。再说改判那一半，它成立且不依赖稿侧——`canUndo` 问的是「落点路径 `fileExists` 还读不读得到」（`FileTrashService.swift:294-300`，其中 `:298`），**用户倒了垃圾**与**外接卷被拔掉**都让它为假，画面上却一律印同一句话；跨卷那一档从头到尾没人倒过垃圾（`docs/verification/p53-cross-volume-trash/` 03→04→05 三张），那四个字在那一行上是假话。改判后的判据来自实测而不是猜想：**删除时就把落点的 `volumeUUIDString` 记进台账**（拔盘之后再问，`resourceValues` 直接抛错，问不到了），呈现时「记录的 UUID ∉ 当前挂载卷的 UUID 集合」⟹「盘已取下」，「∈ 集合但落点读不到」⟹ 那句老话仍然实话。两条陷阱同样量过：挂载点目录在 detach 之后**还在**（空目录，且它的卷身份已经变成主卷那一个，拿「目录在不在」当判据会把「盘已取下」判成「盘还在」，正好判反）；「当前挂载 UUID 集合」也不能复用候选根那一路——`VolumeRoots.passesFilter`（`VolumeRoots.swift:99-104`）还要过一道 `browsable`，而夹具卷以 `-nobrowse` 挂着时枚举里明明有它、`browsable` 却是假（档 A 第 11 条），过那道滤就漏。逐条读数 `docs/verification/p55-undo-badge-criterion/00-criterion-reading.log`（档 A 挂载中 15 条卷、档 B 已拔盘 14 条），稿面 `docs/design-system/screens/shell/01b-dashboard-undo-states.html`（现状逐字照代码 / 改判后四档 / 五档文案合同 / 后端配合清单——它把这几支逐条画全，`03h-uninstaller-external-volume.html` 画板 3 那三行只有「撤回」按钮／建议措辞／现状措辞，没有「已撤回」，而 `01-dashboard.html` 一支都没画）。指针来源 `fidelity-uninstaller.md` §18.5 | 高 | 实现该改 **I16**（改那四个字属实现轮，要单独授权）；稿面 **P55 已落地**（另起 01b，没动 `01-dashboard.html`，理由与代价见 §6）；「三态都覆盖」作废后新登记的这一格是 **S2**（见 §3 那一条） |
| 「撤回」按钮在废纸篓清空后消失 | `MainWindow.swift:678-684`（**P55 现读重指**：`else if operation.canUndo` 在 `:678`、按钮在 `:679-680`、读不到落点那一支的徽章在 `:684`；此前这一格写 `:664-673`，那一段是同一行的**图标与标题**，指的不是按钮——同样不是空白行，门禁也一路放行） | ✅ | 不靠用户点错才报错，一致。**P55 注**：这一条的结构判定不变（按钮仍在 `canUndo` 为假时消失），改判动的只是它旁边那枚徽章**说什么原因**（见上一行）；稿 `01-dashboard.html:162-170` 那三行的**行名是虚构形状**——实机第一行逐字是「移入废纸篓 <体积>」（`:670`）、副行是「<相对时间> · N 项」（`:691-699`），稿里写的「清理系统缓存 2.3 GB」「卸载 OldApp 386 MB」「3 项跳过：文件被占用」和那枚 `badge warn`「查看」分支实机都不画，登记为 S2，见 §3 | — | — |

### 1.5 侧栏 + 状态栏

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- | --- |
| 模块列表「系统清理 2.4 GB」「应用卸载 46」 | `MainWindow.swift:105-110` | ✅（P38f 现读，稿侧已清） | 实机仅在 `dashboard.reclaimState == .measured` 时显示真实值，否则该格为空（不显示 "—"）——代码一侧照旧；**稿子一侧这两个值在 `01-dashboard.html` 已经没有了**（同一笔 `0c61fbf`「清洗侧栏虚构占位」删的，与下一行那个红点同一批），现在全站只剩 `components.html:135-136` 还写着 `2.4 GB`/`46`，而那一页是元素清单、tail 在那里是**组件示例**不是页面主张 | 低 | 设计稿该改 S2 → **概览稿已落地（P38f）**，`01-dashboard` 仍写死的占位只剩内容区「可立即释放 3.5 GB」（:95 与 :98 那颗按钮） |
| **侧栏 footer（S1）** | `MainWindow.swift:141-166` `volumeFooter`（P38f 现读：调用在 `:125`，其上是 `Divider()` `:123`、其下是「设置」按钮 `:128-135`） | ✅（P38f 现读） | 实机 = `Macintosh HD` + 百分比 + 红色容量条（低空间转红）+ 带边框「设置」按钮；**稿子这一侧已经改成同一个组件**——`tokens.css:287` 的 `.sidebar-footer` 在 19 张稿里画着（实例 25 处；**P41f 现读**，旧记 16 张），本页 `01-dashboard.html:43` 就是其中一处；原判"稿子画成分隔线 + 设置 nav-item"由 `0c61fbf` 作废，而那条判定写在它之后的 `e96c95bc` 里，**出生即假** | 中 | 设计稿该改 S1 → **稿侧已落地（P38f）**；只剩 `components.html` 改稿前第 141-142 行 的旧画法与 04b/04e 三处未画 footer，判据见本文开头「结论先行」的 S1 那一格；**P39 这两处已改稿并重渲染**（`release-readiness.md` §7.36） |
| 隐私守护红点 | `01-dashboard.html:40` | ✅（P36 现读） | 稿子 :40 现读是纯 nav-item、无红点——commit `0c61fbf`「清洗侧栏虚构占位（含隐私守护红点）」已删；实机 `SidebarView`（`MainWindow.swift:61` 起）本无模块红点逻辑 → 两侧一致，红点已不存在 | 低 | 设计稿该改 S2 → **稿侧已落地** |
| 状态栏「4 个卷 · 文件系统 APFS · 上次清理 3 天前」 | `MainWindow.swift:277-301` `statusBar` | ❌ | 稿子多画"索引正常""Spotlight 已排除 2 个路径"——实机状态栏**无这两段**（代码未输出） | 低 | 设计稿该改 S2 |
| 侧栏宽 220（`--sidebar-w`）/ 标题栏 52（`--titlebar-h`，P38a 现读：令牌已由 38 改为 52） | `MainWindow.swift:22`（`.navigationSplitViewColumnWidth`，P29 现读：此前引 `:18` 落在那段解释注释上） / 实机 52pt | ✅ / ✅ | **P6.2b**：侧栏改前实测量 **200pt**（不是这里原记的 220），现 `min:220` 后实测 220pt，本条关闭；**P38a 现读**：标题栏令牌已改为 52px、与实机同源，两侧都不欠，本条也关闭（实现侧无标题栏高度常量） | 低 | I10a / I10b **都已落地**（P38a） |
| 「可释放空间」卡右上「全部」（稿 `01-dashboard.html` 画的是 `全部 + chevron-right`） | `MainWindow.swift` `cardHeader("可释放空间", trailing:)` | ✅（P6.2b 起） | 改前只有一个蓝色"全部"，读起来像筛选开关；稿里那半枚 `chevron.right` 才是"点了会离开这一页"的唯一提示。现已补 `全部 ›`（`p62b-fidelity/02-dashboard-history-full.png`） | 低 | 实现该改 I11 → **已落地** |
| 网络 / 磁盘 I/O 迷你图 `.spark i{flex:1}`（12 等分槽） | `MMDesign.swift` `MMSparkline`（`slotCount` 固定、`maxWidth:.infinity` 等分） | ✅（P6.2b 起） | 改前每根钉死 10pt 靠左排：首帧只有一根细柱孤零零贴在左边，读起来像图坏了，且柱子随采样次数往右爬、同一张图前后宽度不一样。现横轴满宽、柱从右端往左长（`01` 首帧 vs `02` 满轴两张） | 中 | 实现该改 I12 → **已落地** |

## 2. 09-settings 逐元素（09a–09e）

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| sheet「500 宽 + 高度按内容」+ MMPageHeader「设置」+ xmark 关闭 | 稿 `09-settings.html:12`（`.sheet{position:relative;width:500px;height:auto…}`）；实机 header `SettingsView.swift:21-31`、`.frame(width:500,height:560)` `:59` | ❌→P29 改 | **实现把高度钉死在 400**：「清理」这一栏有 5 个 Section，400 高只露到第二组的标题行（`docs/verification/p29-before/cleaner.png`），用户翻不到下面的行，看着就像功能不在——这正是"设置几乎不可用"里最直观的一条。现提到 560，同一栏露到「监听」第一行（`p29-after/cleaner.png`），**「删除历史」「排除项」仍要滚动**：差距从"看不全"变成"仍要滚"，没有变成"已一致"。稿那一格是 CSS 才办得到的按内容展开，实机 sheet 需要一个确定高度（`:56-58` 记着这个理由；顺带一条：那段注释写的"8 个分组"数错了，现读是 5 个 Section，注释是编译输入、改它要重跑全部取证，本轮只在文档里记这笔） | 中 | 实现该改 I15 → **已落地**；稿子该改 S2 → **P38e 已改稿**：09a 的 cap（`:84`）写明"宽 500pt 由实现钉死、实机高 560pt、Form 内滚动"，09c 里画了一条红虚线 `.fold`（样式 `:66`、元素 `:261`，绝对定位在 sheet 顶往下 560px）标"以下要滚动"，浏览器实测该线正好切在「监听」第一行的脚注上（`监听` 分组 `228-236`、线在 560、分组起点 473）。**这条线只是稿面标记，不当像素基线** |
| 设置页的**入口**（稿只画了侧栏底部那一枚按钮） | 应用菜单「设置…」+ ⌘, `MacMasterApp.swift:59-62`；侧栏按钮 `MainWindow.swift:128-135`；菜单栏下拉「设置...」`MenuBarManager.swift:354-356`→`386-391`（发 `.mmOpenSettings`，`SystemSettings.swift:40`），三处收在 `MacMasterApp.swift:106-108` | ❌→P29 改 | 改前只有侧栏那一枚：主窗口一收进菜单栏，全 app 没有任何地方能进设置；⌘, 与应用菜单那一格是空的，而 macOS 用户的第一个反射就是这两处。现三处入口都在，且不再各写各的状态 | 中 | 实现该改 I13 → **已落地**；稿子该改 S2 → **P38e 已改稿**：新增 09f（`09-settings.html:364-426`）画三处入口——应用菜单那一支、主窗口侧栏底部那一枚、菜单栏下拉那一支，条目文字逐字取自 `MM_DUMP_MENUS=1` 的 stderr 转储（`docs/verification/p29-after/00-*.log`），**不用合成点击**；cap 里同时记了两处 dump 口径不一样（应用菜单会把快捷键拼成 `⌘,`，菜单栏那一支只拼标题和子菜单的 ` ▸`） |
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

- **实现该改（P6.2b 落地 2 条 / P29 落地 3 条 / P55 新增 1 条待授权）**：I11「全部」缺 `chevron-right` affordance、I12 sparkline 首帧稀疏且槽宽钉死（均见 §1.5 表）。**P29（设置页可用性轮）新增三条**：I13 设置入口与系统设置深链（⌘,/应用菜单/菜单栏下拉三处收口 + `MMSettingsPane` 枚举堵掉双前缀死链）、I14 状态可见性与两处假脚注（登录项 `.requiresApproval`、通知授权状态、扫描范围/排除项"未接入"的假话）、I15 sheet 高度 400→560。**P55 新增 I16（未落地，本轮零代码改动）**：概览「最近操作」那一行在 `canUndo` 为假那一支只有一句措辞（`MainWindow.swift:684`），而它有两种成因（倒了垃圾／拔了外接卷），跨卷那一档说的是假话——要按 `01b-dashboard-undo-states.html` 画板 3 的 C／D／E 三支拆开，判据与前置缺口（台账要落点 `volumeUUIDString`、新字段必须可选、两条陷阱）逐条在那张稿的画板 4；改源码要单独授权，本轮只出规格。I4/I5 在本页不触发；无"把未知当已知"类缺陷（本页占位/降级文案正确）。
- **设计稿该改（S 类）**：S1（侧栏 footer，全站）→ **P38f 现读：稿侧已落地，这条从写下那天就是假的**（组件在 `tokens.css:287`，19 张稿在用、实例 25 处；**P41f 现读**，旧记 16 张；改稿动作是 `0c61fbf`，比这份审计的 `e96c95bc` 早一个提交）——残留只有 `components.html` 改稿前第 141-142 行 的旧画法与 04b/04e 三处没画 footer，判据见开头「结论先行」的 S1 那一格、排口见 `release-readiness.md` §7.35（**P39 这两处已改完并重渲染，S1 这一面今天清零**，见 §7.36）、S2（占位/虚构数字：2.4GB/46/3.5GB/3/20/94%/红点/索引正常/Spotlight 排除/台账降级态未画；**P29 追加的六条 P38e 已全部改稿**——09 补了 ⌘,/应用菜单/菜单栏下拉三个入口（09f）、登录项四档（09g）、通知四档（09h）、09c 分组改名「监听」并补第二个开关、`:178`/`:215` 两格假脚注换成实话、sheet 标实机 560 且用红虚线标"以下要滚动"；这一批里只剩**台账降级态 09i 无照片**（只能照代码分支画）与**其他页的占位数字**未清）、**P55 新增两格 S2（在 `01-dashboard.html`，登记未动）**：①「最近操作」那一卡三行的**行名是虚构形状**——`01-dashboard.html:163/166/169` 写的是「清理系统缓存 2.3 GB」「卸载 OldApp 386 MB」「3 项跳过：文件被占用」，外加 `:170` 那枚 `badge warn`「查看」，而实机那一卡第一行逐字只有「移入废纸篓 <体积>」（`MainWindow.swift:670`）、副行只有「<相对时间> · N 项」（失败时才追加「· N 项失败」，`:691-699`），右列除 `:677`/`:679`/`:684` 也没有第四支；②「已撤回」「废纸篓已清空」两枚徽章在该稿现读各 **0 处**，也就是这一卡的态从来没画全过（判据与逐字来源见 §1.4 那一行）。**这两格本轮没在 `01-dashboard.html` 上动**：改它要重渲染 `01-dashboard.png` 那份基线，按「一次只作废一批基线」排到集成批次；P55 的画法先落在 `01b-dashboard-undo-states.html`（画板 1 是逐字照代码的现状），落地那一轮再决定要不要并回 01。
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

1. **S1 侧栏 footer 组件（P38f 现读改判：这一条作为待办作废，剩下的只是三处没跟上的侧栏）**：`.sidebar-footer` 早就在 `docs/design-system/tokens.css:287`（容量行 + 容量条 + `.foot-btn` 带边框设置按钮），"八张稿一起换"这件事由 `0c61fbf`（2026-09-30，十张稿）做完、后来新增的稿各自从一开始就在用，现读 **20 张里 19 张在用**（实例 25 处；**P41f 现读**，旧记 16 张 / 21 处）。因此本条不再提请任何人做组件；**唯一还开的是三处侧栏面**：`docs/design-system/screens/mmui/components.html` 改稿前第 141-142 行（全站唯一还在画"1px 线 + 设置 nav-item"的一格，它同时带着 `.mini-sidebar { width: 216px }` 那一处，见 `coordination-audit.md` §4「直接做③」末段把 216 排进 v1.4 的那半句）与 `docs/design-system/screens/mmdisk/04b-disk-confirm.html` 改稿前第 76-84 行、`docs/design-system/screens/mmdisk/04e-disk-rescan.html` 改稿前第 45-53 行（同文件另一块在 :100-108）——后两者是**整块没画 footer**，不是画错。这三处的改法就是照 `01-dashboard.html:43-51` 抄那一块，但改完要重渲染那三页（`components.png` 上一轮实测与 HEAD 字节相同，所以它一旦真改了就会真变），排口与代价见 `release-readiness.md` §7.35。〔**P39 做完了，改法也正是那一句**：三处都照 `01-dashboard.html:43-51` 那一块补/换（`components.html:141` 现读就是 `<div class="sidebar-footer">`、04b 第 84-92 行、04e 两块），九张 png 重渲染、两条像素判据在 `release-readiness.md` §7.36；同轮把 03c/03e 那两格非法尾数删了，S1 这一面今天清零。〕
2. **I10b/S3/S4 全站几何修正（P38a 现读改判：前两件已落地，剩的那件不是"调令牌"）**：`--titlebar-h` 已是 52px、`--c-content-bg` 与两个卡底令牌（`--c-card-content` / `--c-card-under-page`）也都已声明（同一笔 c74f045），**所以"改动会作废全部模块像素基线"这件事已经发生过一次**；真正仍开的是**那两个卡底令牌至今 0 处 `var()` 引用**——接线还是删要逐屏决定，判据见 `coordination-audit.md` §2。**这一条不等决定的部分（I10b/S3）本轮已翻，S4 那半句等 §5 第 2 条**。**I10a（侧栏）P6.2b 已落地**，但落地位置是 `MainWindow.swift:22` 的 `min:`（首屏宽度只认 `min`，`ideal` 与 AppKit 那条持久化记录都不参与），令牌 `--sidebar-w: 220px` 本来就是对的、没动；顺带一条待办：`--sidebar-w-min: 200px` 全仓从未被引用（仅 `tokens.css:33` 声明处一处命中），而应用现在也拖不到 200，要么删令牌要么把稿改成 220。〔**P41 已做，选了改值**：`:33` 现在写 `220px`（+ 一行注释到 `:34`），"0 消费者"这条判据现读仍为 0，所以这一串里"删令牌还是改值"那个选择不用再付重指债；`coordination-audit.md` §1 那一格与 §5 附赠段是同一批更正。〕
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
4. **S2 占位数字清洗**：稿内 `2.4 GB`/`46`/`3.5 GB`/`3 / 20`/`94%`/`红点`/`索引正常`/`Spotlight 已排除` 标"示例值/虚构"或改为动态占位，避免被当成实测。〔**P38f 现读：这一串分三档**——①**概览稿侧栏那一族（`2.4 GB`/`46`/红点）已清完**（`0c61fbf`），但这三个**具体串**今天只剩元素清单 `components.html:135/136/139` 还当组件示例写着；侧栏尾数这一族全仓还有 6 行活着（`08-optimizer.html:576/751`、`03c-uninstaller-trash.html:85/86`、`03e-uninstaller-watch.html:92/93`），03c/03e 那两格是 P38f 新发现的"实机永远不画"的形状差，见开头那句与 `release-readiness.md` §7.35；②`3 / 20` 在 09 稿重画时已按本条要求标了"示例数"（`09-settings.html:545`）；③剩下的 `3.5 GB`（`:95`/`:98`）、`索引正常`/`Spotlight 已排除 2 个路径`（`:180`/`:182`）在本页**原样还在**，仍是要清洗的那一半，只是它不再需要协调层统筹——纯本模块改稿，代价是重渲染 `01-dashboard.png`，排口见 `release-readiness.md` §7.35。〔**P39 翻了这一条的侧栏那一半**：上面列的 03c 旧第 85、86 行与 03e 旧第 92、93 行里，每份稿的那一格"应用卸载"尾数（值 `45`）已删掉——实机永远不给非清理行挂尾数；每份稿各留一行「系统清理」的真值形态，`08-optimizer` 与元素清单那几处按 §7.35 的定性不动。**这一族现读 7 行 / 4 份文件**，两页已重渲染，判据在 `release-readiness.md` §7.36。〕
5. **09-settings 需要一次同步（P29 之后稿子落后实现两轮）**：要补的是①设置入口（⌘, 与应用菜单那一格、菜单栏下拉「设置...」，稿只画了侧栏按钮）、②登录项"待系统批准"档 + 「打开系统设置 · 登录项」、③通知授权四档脚注 + 「打开系统设置 · 通知」、④「监听」分组第二个开关（P5.3c 加的，稿那一段标题还叫「废纸篓」）、⑤`:178`/`:215` 两格脚注（实现已经把它们改成实话）、⑥sheet 实机 560 且清理栏仍需滚动。**这些是实现侧已落地的既有事实，不是新需求**；改稿会作废 09 的像素基线，所以和 S1/S3/S4 一样排到集成阶段统一做，本轮只登记。
   **→ P38e（2026-10-14）六条全部改完，这一条收口**：`09-settings.html` 从 319 行涨到 552 行，artboard 由 09a–09e 五块变 09a–09i 九块（新增 09f 三入口 / 09g 登录项四档 / 09h 通知四档 / 09i 删除历史两档降级），②③④⑥ 逐条落在 §2 对应那六行的"归属"列里。**这一刀只动 09，没有和 S 系列合并**（S1 侧栏 footer、S2 占位数字、S3/S4 全站几何各自另算）——按 #53 的约定"一次只作废一批基线"，09 的像素基线已经作废：`09-settings.png` 按全高重渲染为 **1100×6800 CSS（@2x 2200×13600）**，旧图 1100×3900 那一版连同它上面"五块 artboard"的读数一起作废。稿里那条 560 红虚线是**标记不是基线**（各层高度按元素各自画、不由 560 反推），这条在 09c 的 cap 里写死了，免得下一轮有人拿它当量出来的数。

## 6. P55 本轮账（2026-10-19：把 §18.5 那根指针落成两个面）

- **这一轮动的面**：①新稿 `docs/design-system/screens/shell/01b-dashboard-undo-states.html`（现读 221 行，四块画板：现状逐字照代码／改判后四档＋老记录降级档／五档文案合同／后端配合清单）+ 渲染 `01b-dashboard-undo-states.png` = **1760×3280 px**（880×1640 CSS @2x，命令 `cd docs/design-system && ./render.sh screens/shell/01b-dashboard-undo-states.html 880 1640`）；②`docs/design-system/README.md:16` 那一行目录树补上 `01b`（就地改，该文件行数不变）；③本文 §0 设计稿那一格、§1.4 那两行、§3 两条汇总就地改判；④`fidelity-uninstaller.md` §18.5 那条"属另一轮"的指针标成已落地（同样就地，1058 行不变）。**零代码改动**：`MainWindow.swift:684` 那四个字属实现轮（I16），要单独授权。
- **另起一稿而不改进 `01-dashboard.html`，理由与代价都记清楚**：动 01 就得把它那份像素基线作废，而 01 上欠的不止这一族（§3 那条 S2 还压着 `3.5 GB`、`索引正常`、`Spotlight 已排除` 一串），按"一次只作废一批基线"排到集成批次。代价是**同一张卡今天有两份稿**：`01-dashboard.html:162-170` 是旧画法（三行虚构行名 + 一支实机不画的「查看」），`01b` 画板 1 是逐字照代码的现状。这个分岔只写在本档——01 那份稿本轮一字节没动，稿内没有指向 01b 的注释。
- **只有稿面能量的一件事：改判不需要任何让步顺序**。DOM 实测（13px/10px 两档字号、44px 行高、`--sp-3`=12px）：右列那枚徽标「废纸篓已清空」占 **74px**，「盘已取下」与「无法撤回」各 **54px**，「已撤回」44px，「撤回」按钮 42px；卡宽 352 时标签列从 239 让到 259、卡宽 330 时从 217 让到 237，两档下都 `scrollWidth==clientWidth`（不截断）。也就是说新措辞比旧措辞**短 20px**，I16 落地时不会撞上 P25/P26 那一族页头/副行截断缺陷——这一条不用等真机就能定。
- **判据是量出来的，不是推出来的**：`Scripts/p55-undo-badge-criterion.sh`（91 行）配单文件探针 `Scripts/p55-detach-criterion-probe.swift`（105 行，`swiftc` 直编、不链任何生产源文件），复用 `Scripts/p53-cross-volume-fixture.sh` 那块挂在 `/tmp` 下的卷，把同一条问句在**挂载中／已拔盘**两档各问一遍，读数是 `docs/verification/p55-undo-badge-criterion/00-criterion-reading.log`（档 A 枚举 15 条卷、档 B 14 条；落点那一格从"报得出 UUID"变成"`resourceValues` 直接抛错"）。三件事就此定死：**卷身份只能在删除那一刻取**；**挂载点目录不能当判据**（detach 后它还在、且报的是主卷）；**「当前挂载 UUID 集合」不能复用候选根那道 `browsable` 滤**（`-nobrowse` 挂上的真卷 `browsable=假` 却在集合里）。这三条各是 01b 画板 4 的第 1、3、4 项。
- **`03h` 画板 5 第五条那根指针：只登记、不改稿**。那一支要 01 系与本文付账，今天付了；`03h-uninstaller-external-volume.html` 是 P54 刚立的像素基线，为了在它 cap 里追一句"已落地"而重渲染不划算。落地记录有三个可读面：本文 §1.4 那一行、§3 的 I16 与那两格 S2、`fidelity-uninstaller.md` §18.5 的指针。
- **本轮没有照片可拍**：画面上今天还没有「盘已取下」这一档，拍不到不存在的东西（同 01b 画板 4 第 6 条）。I16 落地那一轮要在同一支夹具上重拍 P53 的 `04` 那一档，03↔04 的像素判据沿用 `uninstaller-app-body-risk.md` §10 第 2 项那句"不要求只有那一行变了"（概览页是活数页）。
- **副本面账（本轮 md 全改完之后现读，这一格只写数不重抄那两个字，所以它自己不进到它数的数里）**：计数口径 `grep -rn '盘已取下' docs --include='*.md' | wc -l` 同一条换个串。现读 **「那五个字」13 行 / 5 份文档**（`feature-roadmap.md` 2、`fidelity-uninstaller.md` 2、本文 3、`uninstaller-app-body-risk.md` 5、`uninstally-adoption.md` 1；本文是 `:77`/`:144`/`:182` 这三行（`:77` 原本就有，**本轮新增的是 §3 那条 S2 与 §6 稿面量那一格**；本节下面那条记这个数的行刻意只写「那五个字」不重抄，所以它不进自己数的数）——P54 那轮登记的是 11 行 / 5 份（`fidelity-uninstaller.md:999`），份数不变、本文这一份从 1 行变 3 行；`uninstaller-app-body-risk.md` 那五处与 `feature-roadmap.md` 那两处**一行没涨**（本轮在它们里的补充各落在自己原有那一行内，就地补句不加行）。**「盘已取下」8 行 / 4 份文档**（同一串清单少了 `uninstally-adoption.md`——它那一行写的是"那一格怎么改判属 01 系的账"，没引用新措辞）。`.html` 侧两份稿各有增量：那五个字 **12 行**（01b 8、03h 4），新措辞 **10 行**（01b 6、03h 4）。
- **引用门禁三跑到定点**（归档 `docs/verification/p55-citations/` 下三份：`audit.log`、`audit-postadd.log`、`audit-final.log`；第一跑与第二跑只差日期与跟踪文件数 1569→1570，第二跑与第三跑**逐字只差一个日期**——中间那次只往归档目录里加了一份日志，四个数不动）：**引用条次 1525、唯一「路径+行段」1133、两头都不到 0、位置存疑 139、硬失败 2**。条次比 P54 那一跑（1513 / 1126 / 0 / 137）涨 12 条、唯一涨 7 条，全部来自本轮这两面新稿与新日志；存疑涨 2 条是提示级，没有落空白行。**那两处硬失败不是本轮引入的**：两处都落在设置页那一份源码文件上（一处由 `feature-roadmap.md` 第 1038 行引、一处由本文第 102 行引），而工作树里那份源码正被外来那一族（QuickLook + 设置页）改着——现读它 413 行、HEAD 那份 385 行，差 28 行，被引的那两个位置在未提交的版本里正好是空白行。**本轮一行没碰 `Sources/`**，所以这两处该由那一族提交之后一起重指，现在改反而会对不上它自己的树。
