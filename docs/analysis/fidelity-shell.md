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
| 标题「概览」 | `MainWindow.swift:252` `MMPageHeader("概览", …)` | ✅ | 一致 | — | — |
| 副标题「本机状态 · 数据更新于 21:15:04」 | `DashboardView.headerSubtitle`（`MainWindow.swift:264`） | ❌ | 稿子写死"本机状态 · 数据更新于 HH:mm:ss"；实机是"上次采样 <relative> · CPU/内存/磁盘均为本机实时读数"。**实机更诚实**（不编固定时刻），稿子是占位措辞 | 低 | 设计稿该改 S2 |
| 右上「刷新」按钮 | `MainWindow.swift:253-261` `arrow.clockwise` + `measureReclaimable()` | ✅ | 图标/位置/禁用态（测量中禁用）一致 | — | — |

### 1.2 存储卡

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「存储」+ 低空间徽章「可用空间偏低」 | `MainWindow.swift:298,301` `MMBadge(..., tint: destructive)` | ✅ | 仅低空间时出现，口径一致 | — | — |
| 「28.1 GB 可用 · 共 494.4 GB」 | `MainWindow.swift:305` | ✅ | 动态值，文案格式一致 | — | — |
| 堆叠条 9 段 + 图例 | `MainWindow.swift:317,318` `MMStackedBar`/`MMLegend` ← `StorageBreakdown.segments` | ⚠️待量 | 稿子画了 9 段固定占比（应用/开发者/系统/缓存/媒体/文档/可清理/废纸篓/可用）；实机段集与配色由 `StorageBreakdown.segments(total:available:reclaimable:trash:)` 决定，**段数/宽度/配色需逐段真机核对** | 中 | 待真机测量 |
| 「可立即释放 3.5 GB（缓存 2.4 + 废纸篓 1.1）」 | `MainWindow.swift:369-390` `releaseText`/`releaseDetail` | ❌ | 稿子写死 3.5/2.4/1.1；实机 = `reclaimState` 实测 + 废纸篓实测，没扫到显示"尚未测量"占位（不编数字） | 低 | 设计稿该改 S2 |
| 「查看占用排行」「清理 X GB」按钮 | `MainWindow.swift:328-331` | ✅ | 一致 | — | — |

### 1.3 系统负载卡

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「系统负载」+ 平稳徽章 | `MainWindow.swift:402-409` `LoadVerdict.text` | ✅ | 口径一致 | — | — |
| CPU 仪表「23%」+「2.1/10 核」+「4 性能+6 能效」 | `MainWindow.swift:412-418` `gaugeRow` / `DashboardText.cpuCaliberNote` | ✅(语义) | 仪表填 `model.cpuLoad`（总占用），注脚是核数；与稿子层级一致 ⚠️待量（指针角度需真机） | 低 | 待真机测量 |
| 内存仪表「65%」+「15.6/24 GB」+「交换 0 MB」 | `MainWindow.swift:419-423` | ⚠️待核 | 稿子 65% 疑似 = used/total；实机仪表填 `model.memory?.pressure`（内存压力），数值口径可能不同 → **需真机核对 pressure 与 used/total 是否同一档** | 中 | 待真机测量 |
| 内存构成堆叠条 | `MainWindow.swift:486-509` `memoryComposition` | ✅(语义) | 缺段不画绿条（诚实）⚠️待量 | 低 | 待真机测量 |
| 网络 / 磁盘 I/O 迷你图 + 注脚 | `MainWindow.swift:436-460` `metricMini` | ✅ | "等待差分"/"IOKit 未返回统计" 占位文案与降级口径一致 | — | — |

### 1.4 可释放空间卡 / 最近操作卡

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 可释放前三分类 + 废纸篓 + 锁定行（iOS 备份） | `MainWindow.swift:549-567` `reclaimRows` | ✅(语义) | 只读分类置灰加锁、前三+废纸篓；稿子数字为示例 ⚠️待量（行高/图标对齐） | 低 | 待真机测量 |
| 最近操作：撤回/已撤回/废纸篓已清空 | `MainWindow.swift:618-679` | ✅ | 三种态都覆盖，文案一致 | — | — |
| 「撤回」按钮在废纸篓清空后消失 | `MainWindow.swift:656-665` | ✅ | 不靠用户点错才报错，一致 | — | — |

### 1.5 侧栏 + 状态栏

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- | --- |
| 模块列表「系统清理 2.4 GB」「应用卸载 46」 | `MainWindow.swift:101-106` | ❌ | 稿子写死占位；实机仅在 `dashboard.reclaimState == .measured` 时显示真实值，否则该格为空（不显示 "—"） | 低 | 设计稿该改 S2 |
| **侧栏 footer（S1）** | `MainWindow.swift:137-162` `volumeFooter` | ❌ | 实机 = `Macintosh HD` + 百分比 + 红色容量条（低空间转红）+ 带边框「设置」按钮；**稿子画成"分隔线 + 设置 nav-item"**，沿用 01–06 错误画法 | 中 | 设计稿该改 S1（全站） |
| 隐私守护红点 | `01-dashboard.html:40` | ❌ | 稿子给"隐私守护"画了红点；实机 `SidebarView` 无任何模块红点逻辑 → **稿子虚构**，应删 | 低 | 设计稿该改 S2 |
| 状态栏「4 个卷 · 文件系统 APFS · 上次清理 3 天前」 | `MainWindow.swift:272-290` `statusBar` | ❌ | 稿子多画"索引正常""Spotlight 已排除 2 个路径"——实机状态栏**无这两段**（代码未输出） | 低 | 设计稿该改 S2 |
| 侧栏宽 220（`--sidebar-w`）/ 标题栏 38（`--titlebar-h`） | `MainWindow.swift:18` / 实机 52pt | ✅ / ❌ | **P6.2b**：侧栏改前实测量 **200pt**（不是这里原记的 220），现 `min:220` 后实测 220pt，本条关闭；标题栏 52 vs 令牌 38 仍开，归集成阶段 | 低 | I10a **已落地** / I10b 待落地 |
| 「可释放空间」卡右上「全部」（稿 `01-dashboard.html` 画的是 `全部 + chevron-right`） | `MainWindow.swift` `cardHeader("可释放空间", trailing:)` | ✅（P6.2b 起） | 改前只有一个蓝色"全部"，读起来像筛选开关；稿里那半枚 `chevron.right` 才是"点了会离开这一页"的唯一提示。现已补 `全部 ›`（`p62b-fidelity/02-dashboard-history-full.png`） | 低 | 实现该改 I11 → **已落地** |
| 网络 / 磁盘 I/O 迷你图 `.spark i{flex:1}`（12 等分槽） | `MMDesign.swift` `MMSparkline`（`slotCount` 固定、`maxWidth:.infinity` 等分） | ✅（P6.2b 起） | 改前每根钉死 10pt 靠左排：首帧只有一根细柱孤零零贴在左边，读起来像图坏了，且柱子随采样次数往右爬、同一张图前后宽度不一样。现横轴满宽、柱从右端往左长（`01` 首帧 vs `02` 满轴两张） | 中 | 实现该改 I12 → **已落地** |

## 2. 09-settings 逐元素（09a–09e）

| 稿内条目 | 实现出处 | 一致? | 差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 500×400 sheet + MMPageHeader「设置」+ xmark 关闭 | `SettingsView.swift:20-30,55` | ✅ | 一致（稿子按内容展开高度，已注明实机固定 400 内部滚动） | — | — |
| 四 tab 分段（通用/监控/清理/关于） | `SettingsView.swift:32-41` `Picker(.segmented)` | ✅ | 一致 | — | — |
| 09a 语言（简/英）、启动（开机启动/最小化菜单栏） | `SettingsView.swift:61-97` | ⚠️ | 视觉一致；注册失败橙色脚注实机有（`loginItem.lastError`）、稿子注明"没画"→ 规格待补。**语言是死开关**，见下方补记 | 低 | ~~待集成阶段落地（错误态规格）~~ 语言项 P7a 已处理 |

> **补记（P7a，2026-10-05）：这一行的 ✅ 当初只核了"长得像"，没核"按下去有没有用"。**
> `app.language` 只有持久化没有生效端：`Localization.localized(_:)`（`Packages/MMCore/Sources/MMCore/Localization.swift:202`）
> 与便捷函数 `L(_:)`（`:208`）**在全仓界面代码里零调用点**（现读
> `grep -rnE '(^|[^A-Za-z0-9_])L\(' --include='*.swift' Packages Sources`，除定义与两处注释外无命中），
> 全站文案是一套写死的中文。也就是说这台机器上 `app.language=en` 存着、界面却一个字也不会变，
> 而选择器还能改——**这是"控件在、状态存、效果无"三件套齐全的死开关**。
> → 已把选择器 `.disabled(true)`（`SettingsView.swift:75`）并加脚注
> 「界面文案尚未接入多语言，切换不会改变界面」（`:76`）；`AppSettings.swift:11` 的文档注释同步改成
> "持久化是好的，**生效不是**"。真机取证 `docs/verification/p7-settings-lang/{png,log}`。
> **这不是"改好了"，是把假话改成实话**：接不接多语言仍是产品决定，接法有两种
> （把界面字符串逐个走 `L(_:)`，或干脆删掉 `Localization.swift` 与这个开关），本页不代选。
> 设置页其余各行的键都有真实消费方（逐个对过代码），**语言是全站唯一一个**。
> 两个容易误判成死开关的，把通路记在这里免得下轮再数一遍：
> `launchAtLogin` 是**回填值**而不是指令——`LaunchBehavior.swift:30/46` 从 `SMAppService.mainApp`
> 的注册状态反写这个键，真正干活的是同文件的 `register()/unregister()`（`:37/:39`）；
> `monitorRefreshInterval`（界面上那个 1/2/5 选择器，`SettingsView.swift:118`）没有直接消费方，
> 它经 `AppSettings.swift:203-204` 算成 `monitorRefreshIntervalSeconds`，
> 由 `MenuBarManager.swift:103/128` 取用。
| 09b 监控三开关 + 间隔(1/2/5) + 两通知 | `SettingsView.swift:99-129` | ✅ | 逐字对上；**行首无图标**（稿子已按实机去图标） | — | — |
| 09b 阈值脚注「CPU ≥85% / 内存 ≥90% / 5 分钟冷却」 | `SettingsView.swift:122` | ✅ | 静态说明，一致 | — | — |
| 09c 扫描范围 4 + 安全 2 + 废纸篓 1 + 删除历史 + 排除项 | `SettingsView.swift:131-218` | ✅ | 一致；"台账条目 3/20" 实机 N 动态、排除项默认空列表（稿子示例值） | 低 | 设计稿该改 S2（示例值标注） |
| 09c N=0 时「清空删除历史」置灰、historyFileURL=nil 时整行降级 | `SettingsView.swift:176-177,165-174` | ❌ | 两种降级态稿子**没画**（09c 画的是有记录启用态）；档位必须照代码存在 | 低 | 设计稿该改 S2（补降级态） |
| 09d 关于：版本兜底 1.0.0(1)、反馈问题 disabled、未配置官方渠道 | `SettingsView.swift:233-268` | ✅ | 一致；"不做虚构链接"底线守住了 | — | — |
| 09e 清空确认弹窗「清空 N 条记录」+ 取消 | `SettingsView.swift:211-217` | ✅ | 逐字照抄实现文案，一致 | — | — |

## 3. 差异归属汇总

> **复核 2026-10-04（P6.5b）**：本轮把六份 fidelity 文档的"实现该改"逐条重对代码，**本页是唯一一条
> "已落地"写上去、而对代码核得一字不差的**——I11/I12 两处的坐标、形态、判据全部仍在原位：
> I11 = `MainWindow.swift:580-584`（`Text("全部")` + `Image(systemName:"chevron.right").font(.caption2)`，
> 注释 `:580-581` 还留着"那半枚箭头是'点了会离开这一页'"的原始理由）；
> I12 = `MMSparkline`（`MMDesign.swift:1051-1089`，`slotCount` 默认 12、`:1055`；未满的槽用 `Color.clear`
> 撑位而不是画 2pt 矮柱，`:1064-1068`，判据"没轮到 ≠ 读不到"写在注释里），调用点 `MainWindow.swift:534`，
> 数据侧 `DashboardModel.swift:92-118` 把"读不到"压成 `nil` 槽、量不到时整列空出来（`:114-118`）。
> **本页没有需要更正的落地记录。** 唯一要补的是下面第 5 行那句"待真机测量"里新添的一项边界（见 §5 第 2 条补记：
> 侧栏 `max:280` 那端没有取证手段，与"没拍"不是一回事）。

- **实现该改（P6.2b 落地 2 条）**：I11「全部」缺 `chevron-right` affordance、I12 sparkline 首帧稀疏且槽宽钉死（均见 §1.5 表）。I4/I5 在本页不触发；无"把未知当已知"类缺陷（本页占位/降级文案正确）。
- **设计稿该改（S 类）**：S1（侧栏 footer，全站）、S2（占位/虚构数字：2.4GB/46/3.5GB/3/20/94%/红点/索引正常/Spotlight 排除/台账降级态未画）。
- **两边都改（0 条）**。
- **待集成阶段落地（全站几何，只出规格不落地）**：I10b（标题栏 52 vs 38）、S3（content 底色档）、S4（under-page 卡片 token，monitor 已提）。**I10a（侧栏）已由 P6.2b 落地。**
- **待真机测量（⚠️）**：存储堆叠条 9 段、CPU/内存仪表指针角度与口径、内存构成条、可释放行高图标对齐、S3 两页对比度一致性。

## 4. 没能验证到的部分（诚实列出）

1. 概览折叠线以下的**逐像素**核对：P6.2b 的两帧（1100×760pt 视口）已把内存构成条、可释放三行、最近操作四行**拍进画面**（无需滚动），但段宽/行高这类数还没逐个量——`02-dashboard-history-full.png` 是 raw PNG，可直接用 `Scripts/pixel-probe.swift` 续量。
2. 设置各 tab 在 400pt 高度内的实际滚动截断点（09c 废纸篓段落在折线以下，实机未截到）。
3. 浅色 vs 深色的**交叉**核对：P6.2b 两帧都是 `MM_APPEARANCE=light`（与稿同源），暗档这一轮没重拍；侧栏 220pt、`全部 ›`、sparkline 满轴在暗档下的对比度未量。
4. S3 跨页对比度（概览 contentBackground vs 实机 windowBackground）需两页同框真机截图。

## 5. 提请协调者（协调路 #53 落）

1. **S1 侧栏 footer 组件**：在 `tokens.css`/`screen.css` 增 `.sidebar-footer`（容量行 + 红色容量条 + 带边框设置按钮），八张稿（01–07 + 本页）一起换，消除"分隔线+设置 nav-item"错误画法。
2. **I10b/S3/S4 全站几何修正**：调令牌 `--titlebar-h`→52、补 `--c-content-bg` 与 under-page 变体；**改动会作废全部模块像素基线，待集成阶段统一落地**，本页不单独改。**I10a（侧栏）P6.2b 已落地**，但落地位置是 `MainWindow.swift:22` 的 `min:`（首屏宽度只认 `min`，`ideal` 与 AppKit 那条持久化记录都不参与），令牌 `--sidebar-w: 220px` 本来就是对的、没动；顺带一条待办：`--sidebar-w-min: 200px` 全仓从未被引用（仅 `tokens.css:33` 声明处一处命中），而应用现在也拖不到 200，要么删令牌要么把稿改成 220。
   **P6.5b 补一条取证边界（协调者需要知道"**量不到**"和"**没量**"的分别）**：
   `min: 220, ideal: 220, max: 280` 这一行的**窄端在代码层就结掉了**——`min` 同时是 AppKit 给分隔线的下界，
   拖不过 220，所以"用户拖窄到 220 以下会怎样"是个不可能状态，不需要照片（详见 `fidelity-guardian.md` §6.6.5 第 1 条）。
   **宽端 `max:280` 则根本没有采集通路**：壳层六个启动钩子
   （`MM_OPEN_MODULE` `MainWindow.swift:51`、`MM_SHOW_SETTINGS` `:46`、`MM_SETTINGS_TAB` `SettingsView.swift:11`、
   `MM_WINDOW_SIZE` `LaunchBehavior.swift:111`、`MM_APPEARANCE` `:81`、`MM_PROBE_WINDOW` `WindowProbe.swift:12`）
   没有一个能移动分隔线；`MM_WINDOW_SIZE` 走 `window.setContentSize`（`LaunchBehavior.swift:120`），
   加宽的部分归 detail 面板、侧栏仍停在 `min`；写 `NSSplitView Subview Frames…` 已被
   `fidelity-guardian.md` §6.3 实验 B 否证；剩下的唯一办法是**拖分隔线=合成操作，红线禁止**。
   → 要量 280 就得先立项一个设列宽的启动钩子（如 `MM_SIDEBAR_WIDTH`），那属新增钩子、要走 hook-ledger 流程；
   **本轮不加**。这条现在记为**取证边界**，别再当"欠一张照片"重复登记。
3. **09c 降级态补画**：N=0 置灰、「在访达中显示」整行缺失两档，出规格给 mmuninstaller/清理路线补 artboard。
4. **S2 占位数字清洗**：稿内 `2.4 GB`/`46`/`3.5 GB`/`3 / 20`/`94%`/`红点`/`索引正常`/`Spotlight 已排除` 标"示例值/虚构"或改为动态占位，避免被当成实测。
