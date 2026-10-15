# 04 磁盘分析 · 设计稿 ↔ 实现 逐元素对照（fidelity-disk）

> **结论先行**：04 稿（`docs/design-system/screens/mmdisk/04-disk.html`）只画了**一种状态**——treemap
> 已扫描 + Xcode 选中且已标记的首屏。把这一屏逐元素拆开，结构、文案、配色三层**大体对得上**：
> 7 类分类模型与色值（`#AF52DE/#5E5CE6/#30B0C7/#28CD41/#8E8E93/#FF9500/#A2845E`）与实现
> `DiskClassify.swift:28-37` 逐字一致，分段控件、筛选框宽 132、treemap 圆角 3pt、详情面板 268pt
> 宽均对得上，副标题的字段与 `MMFormat` 输出格式一致——**但这一条 P26 之后要打折**：
> 实现现在只报三段（占用 · 路径 · 文件数），稿内的"扫描用时"整段出页头，见 §1.2 与
> `docs/analysis/header-truncation-audit.md` §8。
>
> 真正的缺口分两类：
> 1. **设计稿覆盖不全**（占大头）：列表视图态、大文件列表态、确认删除 sheet、撤回 toast、扫描中态、
>    空态、过滤态——这些实现里都画得出来，但 **04 稿一个 artboard 都没有**，还有一整块
>    "值得看一眼"面板实现里有、稿里没有。这正好踩在本项目"每屏 artboard 要覆盖该视图真能画出的每一种状态"的红线上，
>    判 **设计稿该改 · 中**（S1/S2）。
> 2. **一处真硬伤在钩子**（**本条写于审计当时，现已不成立——P20 现读源码更正**）：
>    `MM_DISK_SCAN` 等扫描类钩子当时**没有 /tmp 越界拦截**，直接 `expandingTildeInPath` 后 `scan`，
>    违反本项目"扫描类钩子只认 /tmp、越界即忽略"的明线纪律（README §5），
>    一旦被设成真实用户目录会去枚举真实磁盘树，当时判 **实现该改 · 高**（I1）。
>    **现在两个钩子都有守卫**：`MMDisk.swift:175-180`（`MM_DISK_SCAN`，越界写 stderr「不在 /tmp 之下，
>    忽略该钩子」后 `return`）与 `MMDisk.swift:1086-1094`（`MM_DISK_SELECT`，含非 /tmp 路径则整钩子忽略）。
>    这一条留在原文里是因为它是本项目"文档比代码老"最典型的一例：
>    **四道硬判据抓不到它**（改前那条锚点指过去的行存在、非空白、不歧义，只是那一行已经不是那件事了），
>    能抓它的只有"去源码里读一眼"——见 `release-readiness.md` §7.7 那条"路径存在、说法不成立"的盲区。
>
> 另外有若干像素级/措辞级偏差（header 带高度、详情图标、徽章文案、各状态栏高度等），
> 无头环境无法真机测量，凡像素项一律标 `⚠️待真机测量`，没有编造任何数字。
>
> 逐元素对照 **31 项**，其中 **18 项存在需归属的差异**（**高 1 / 中 3 / 低 14**）：〔**P40 现读重算这一组数**（口径＝把 §1 那十张子表的每一行数一遍，取法 `awk 'NR>=56 && NR<=158 && /^\| / && $0 !~ /^\| 稿内条目/ && $0 !~ /^\| ---/' docs/analysis/fidelity-disk.md`，再按列拆）：今天这张表是 **53 行 / 10 张子表**，严重度分布 **高 0 / 中 6 / 低 34 / 标"无"1 / 无差异"—"12**，归属分布 **设计稿该改 18 行 / 实现该改 15 行 / 记录 3 行 / ⚠️待真机测量 3 行 / 两边都可 1 行 / 已收口 1 行 / "—"12 行**——所以"31 项 / 18 项"这两个数都是**当初那一读的账**， §1 从 P6 起又长进来了 P8/P26/P35b 三批行没人回头数；**"高 1"这条已经不成立**（唯一那一条高危是 I1，`1145f05` 就修完了，本行下方与 §2 都记过"判高没判错、修的人没回写"）。今天能一口咬定的说法是：**需归属 34 行**（18 稿侧 + 15 实现侧 + 1 两边都可），另有 记录 3 / 待定 3 / 已收口 1 / 无差异 12。**这一句只重数了 §1 这张表，没有逐条重验那 53 行里每一枚坐标**——坐标是按下面两条线在修的：本轮实物重开磁盘代码时撞见的旧落点（§2 I1/I11 那一簇与 §1.3 面包屑那一行）逐条改对，其余仍在原位。〕
> **实现该改 12 条**（I1–I12）、**设计稿该改 6 条**（S1–S6，含 S5 全站侧栏 footer）。〔**P38f 现读**：这 6 条里 **S5 那半条作废**（`.sidebar-footer` 在 `tokens.css:287`，04 稿由 `0c61fbf` 当天换上、现读 19 张稿在用（实例 25 处；**P41f 现读**，旧记 16 张）），但**本模块反而多出一处真的还开着**：同系列的 04b/04e 两块 artboard 各画了侧栏却**整块没画 footer**（`04b-disk-confirm.html` 改稿前第 76-84 行、`04e-disk-rescan.html` 改稿前第 45-53 行 与同文件 :100-108），这是"没画"不是"画错"，要补就得重渲染那两页，排口见 `release-readiness.md` §7.35。〔**P39 这一处补完了**：`04b-disk-confirm.html` 第 84-92 行、`04e-disk-rescan.html` 第 53-61 与 :117-125 三块 footer 都按 `04-disk.html:47-55` 的形状画上，两页 png 重渲染（补画把 04b 的页头副标题从第 87 行顶到第 96 行，引它的四处已重指）；本模块这一面今天没有还开的稿账，全文在 `release-readiness.md` §7.36。〕〔**P40 现读这两句的条数**：§3 的标题写"6 条"、清单实际列到 **S7**（P6.5b 新增那一条没回头改标题），所以设计稿该改是 **7 条**，今天**还开 5 条**——S1 仍开（现读三份 mmdisk 稿里搜不到"值得看一眼"，`findingsPanel` 至今没有 artboard）、**S2 作废了一半**（"确认删除 sheet"与"撤回 toast"两档已由 `04b-disk-confirm.html` 的三块 artboard 覆盖：04b 废纸篓确认、04c 永久删除确认、04d 两条回执吐司；**列表视图 / 大文件列表 / 扫描中 / 空态 / 过滤态这五档仍然一块 artboard 都没有**，逐份现读 `grep -n '扫描中\|过滤\|大文件' docs/design-system/screens/mmdisk/*.html` 只回两段 `seg` 标签）、S3 仍开（`04-disk.html:62` 仍是 Treemap/列表 两段）、S4 仍开、S7 仍开（`:154` 的 `#i-box`、`:163` 的「文件数 42,180」、`:164` 的绝对日期、`:169`/`:172`/`:175` 那三行内联 `height:32px` 本轮逐条打开看过，一处没动）；S5/S6 已落地（`0c61fbf` + P39）。§2 那 12 条的分布沿用本节末段 P8 那一读（改稿 4 / 协调层 4 / 部分落地 1），本轮按实物复核过其中 6 条（I3/I4/I6/I9/I10/I11），**判定一条没变**；顺带把 I2 那句"全仓恰好四处"重跑了一遍 `grep -rn 'MMBadge(risk:' Packages Sources`——**四处逐字全在登记的那几行上**（`MMDesign.swift:866`、`MMUninstaller.swift:1871`、`MMOptimizer.swift:533` 与 `:872`），所以本行上方 P35b 那句"四处里只有 866 还落在原行上"是**当时那一读**，已经不是今天的话。**还有一条编号都没有的稿侧欠账**：§1.2 末行那句"改的是稿：`:60` 与 `04b-disk-confirm.html:96` 的样例待同步"，本轮现读**两处副标题都还写着「扫描用时」**（04 那一行是 `~/Library · 695,682 个文件 · 271.4 GB · 扫描用时 7.6 s`，04b 那一行是 `175.0 MB · 44 个文件 · 扫描用时 0.3 s · /tmp/…`），P26 请出页头的那一段在稿里还站着——它没进 S 清单，所以 §0 这一组数从来没有算过它。〕
> **另有 13 项状态因为缺设计 artboard / 无法真机测量而完全没能验证**（见 §4）。〔**P40 现读**：这一句的 **13** 对得上——§4 那张表今天正好 13 行（`#` 从 1 数到 13）。**但其中两行的"为什么验不了"已经过期**：#3（确认删除 sheet）与 #4（撤回 toast）写的是"稿无 artboard；无头"，而稿侧那一半在 P5 就补上了（`04b-disk-confirm.html` 的 04b/04c/04d 三块），今天这两行欠的只是**实机那一档照片**，不再是"没有稿可照"。#1/#2/#5/#6/#7 那五行的"稿无 artboard"本轮逐条现读**仍然成立**。〕

## 0. 对照方法（先说清楚哪些是量出来的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmdisk/04-disk.html`（**仅 1 个 artboard**：treemap 已扫描 + Xcode 选中态） |
| 渲染 | `cd docs/design-system && ./render.sh screens/mmdisk/04-disk.html`（2x）。本次**未重新渲染**——无头环境不跑 `render.sh` |
| 实机 | **无**。本环境无运行实例、禁止启动 App / 截图 / 合成事件，所有"实机"数字一律留空并标 `⚠️待真机测量` |
| 像素取证 | **无**。无 CoreGraphics 取色、无 `screencapture`。所有几何判据来自**代码 + tokens.css + 04 HTML** 的静态推导，推导不出的标 `⚠️` |
| 可用钩子 | 全部在 `MMDisk.swift`：`MM_OPEN_TAB`(:43-44、`MMDisk.swift` ViewMode)、`MM_DISK_DEPTH`(:128)、`MM_DISK_FILTER`(:132)、`MM_DISK_SCAN`(:135)、`MM_DISK_SELECT`(:996)、`MM_SHOW_CONFIRM`(:1009)、`MM_SHOW_TOAST`(:1025)。grep `ProcessInfo.processInfo.environment Packages/MMDisk/` → 7 命中，即本模块**已有**状态钩子（与 monitor 模块"0 钩子"形成对照，详见 §4.1） |
| 硬约束 | 全程**未发合成事件、未改 `Sources/`/`Packages/` 共享层、未 `pkill`、未 `git` 任何操作**；只新建本文件 `docs/analysis/fidelity-disk.md`。`MM_DISK_SCAN` 越界问题**只记录不修改**，交协调者决定（见 §提请协调者） |

实机测得的锚点（本表所有"一致"判定的基准，凡代码可静态核对的均列出处；凡只能真机看的标 ⚠️）：

- 页头 46pt：`MMPageHeader` `MMMetric.toolbar = 46`（`MMDesign.swift:114,307`），与 `screen.css` `.toolbar { height: 46px }`、04 稿 `.toolbar` 一致 ✓。
- 详情栏 268pt：`MMMetric.inspector = 268`（`MMDesign.swift:89`），与 `screen.css` `.inspector { width: 268px }`、04 稿 `.inspector` 一致 ✓。
- treemap 圆角 3pt：`TreemapView.swift:464` `roundedRect: rect, cornerRadius: 3`，与 04 稿 `.blk { border-radius: 3px }` 一致 ✓。
- 7 类色值：04 稿 `<div class="cap">` 配色与 `DiskClassify.color`（`DiskClassify.swift:28-37`）逐字相同 ✓。
- 徽章高 18pt：`MMBadge` `.frame(height: 18)`（`MMDesign.swift:268`），与 `tokens.css` `.badge { height: 18px }` 一致 ✓。

## 1. 逐元素对照表

严重度定义：**高** = 用户会读到错误结论 / 违反安全红线；**中** = 视觉或语义明显跑偏，或整块 UI 在稿中缺失导致无法核对；**低** = 像素级偏差、措辞口径、占位数据。

### 1.1 标题栏与侧栏（shell / 共享层）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题栏 traffic + "MacMaster"（sparkles 图标） | shell `Sources/MacMaster`（非本模块） | ✅（代码外推） | 04 稿画法与全站壳一致；本模块不拥有标题栏 | — | — |
| 侧栏 7 个 nav-item（概览/系统清理/应用卸载/磁盘分析/系统监控/隐私守护/系统优化） | shell 导航 | ✅ | 图标与 04 稿逐一对得上（`i-gauge/sparkles/app-x/treemap/activity/shield-check/speed`） | — | — |
| 侧栏「磁盘分析」为 active（treemap 图标 + accent） | `MM_OPEN_MODULE=disk` 高亮 | ✅ | 由壳工程导航真源决定 | — | — |
| 侧栏尾数占位「系统清理 2.4 GB」「应用卸载 46」 | 壳层渲染其他模块数据 | ✅（P38f 现读） | 纯占位（与 07 稿同源错误）；本机数字应另行回填——**04 稿里这两个尾数已由 `0c61fbf` 删掉**，现读全仓只剩元素清单 `components.html:135-136` 还把它们当组件示例写着 | 低 | 设计稿该改 S6 → **稿侧已落地（P38f）** |
| **侧栏 footer** | 实机 = 卷容量行（`Macintosh HD` + 红色容量条）+ 带边框「设置」按钮 | ⚠️（P38f 现读：04 已换、04b/04e 没画） | 04 稿（与 01–07 一致）画成「分隔线 + 设置 nav-item」，缺容量行。属全站缺口——**这一半由 `0c61fbf` 作废**（04 稿现在用的是 `tokens.css:287` 的 `.sidebar-footer`）；**但同系列剩下的两块 artboard 反而一处没画 footer**：`04b-disk-confirm.html` 改稿前第 76-84 行、`04e-disk-rescan.html` 改稿前第 45-53 行 与同文件 :100-108，形状是"侧栏到导航列表就断"，不是画错 | **中** | 设计稿该改 S5（全站）→ **04 稿已落地**，本模块新开一处"04b/04e 补画 footer"，代价是要重渲染那两页的 png，排口见 `release-readiness.md` §7.35；**P39 已补画并重渲染两页**（`release-readiness.md` §7.36） |

### 1.2 工具栏（页头 / MMPageHeader）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「磁盘分析」 | `MMDisk.swift:200` `MMPageHeader("磁盘分析", subtitle:)` | ✅ | 逐字一致 | — | — |
| 副标题「~/Library · 695,682 个文件 · 271.4 GB · 扫描用时 7.6 s」 | `:235-241` `headerSubtitle` → `:1585-1591` `DiskHeaderCopy`（两处行号 **P35b 现读重指**，前一版是 230-236 / 1555-1561） | ❌ **P26 起不一致** | 实现是**三段**：`占用 · 路径 · N 个文件`，**没有"扫描用时"**。稿内四字段的顺序本来也与实现不同（实现把占用放最前，稿放最后）。P26 逐屏窄窗实拍把"用时"整段请出页头：1000 pt 下副标题是中间截断，第四段会被切成 `….1 s` 这种读起来像真数的半句（判据与两张照片见 `docs/analysis/header-truncation-audit.md` §8）。**改的是稿**：`:60` 与 `04b-disk-confirm.html:96` 的样例待同步 | 低 | 记录 → **设计稿该改（P26 新增）** |
| 分段控件「Treemap / 列表」 | `:21-41` `ViewMode` rawValue | ⚠️ 部分 | **实现有 3 段**：Treemap/列表/大文件；04 稿只画 2 段，缺「大文件」段（但 README §2 钩子列 `MM_OPEN_TAB(large)`、产品规划 2.1 也列大文件，故属稿缺） | 低 | 设计稿该改 S3 |
| 筛选框「筛选名称」宽 132 + 搜索图标 | `:203-205` `TextField.frame(width: 132)` | ✅ | 宽 132 与稿一致；系统 `roundedBorder` 是否带搜索图标 ⚠️待真机测量 | — | — |
| 按钮「重新扫描」（refresh 图标） | `:209-214`（重新扫描）/ `:216-222`（选择目录） | ⚠️ 部分 | 实现有**两个**按钮：重新扫描（重枚举当前层）+ 选择目录（borderedProminent）；稿只画 1 个「重新扫描」。稿内单按钮语义≈重扫全根，实现"重新扫描"= 重枚举当前导航层 | 低 | 实现该改 I‑（见 §2 记一笔） |

### 1.3 面包屑栏（breadcrumbBar）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 「Macintosh HD › lee › Library › Developer」（末项加粗） | `:382-388` `BreadcrumbView` | ⚠️ 部分 | 实现面包屑从**扫描根**起（`navigationStack`），不前缀卷名；若扫 `~/Library` 则首项是 `Library` 而非 `Macintosh HD`。稿假定从卷根扫到 Developer | 低 | 设计稿该改（稿内示意 vs 实现通用） |
| 行首「‹」返回箭头 | 无对应元素 | ❌ | 实现面包屑项本身可点击上跳，无独立返回 chevron；键盘 Esc / 手势 onBack 负责返回 | 低 | 实现该改 I‑（低，见 §2） |
| 右侧徽章「已标记 3 项 · 48.6 GB」 | `:272-280` marked 时 `MMBadge("已标记 N 项 · X")` | ✅（结构） | 文案与触发条件一致；但**稿内写 3 项、treemap 内仅 1 个勾标**——稿内自相矛盾（见 S4） | 低 | 设计稿该改 S4 |
| 面包屑栏高 26px | `:382` `.frame(height: 34)`（**P40 现读重指**，从前这格写 `:379`——那一行今天是下面 I8 那枚「卷可用」徽章，两格引的是同一个数上的两个东西） | ❌ | **P6.6 实测 34pt**（@2x 边界 y=194..261=68px），稿 26px 的差是真的 8pt | 低 | 实现该改 I11 |
| 「判不了 N 个目录」徽章（过滤深层未测） | `:266-270` | ✅（代码分支） | 实现独有；稿无对应态（过滤态缺 artboard） | 低 | 设计稿该改 S2 |

### 1.4 Treemap 主体（正常态 / 选中态 / 标记态）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 7 类色块：开发者/应用数据/媒体/文档/缓存/日志/其他 | `DiskClassify.swift:12-39` + `TreemapView` 布局 | ✅ | 色相与顺序逐字一致 | — | — |
| 面积 = 实际占用（st_blocks×512） | `MMDisk.swift:1983-2020` `readEntries` 取 `st_blocks*512` | ✅（数据口径） | 实现确用分配大小；但见 I7 图例文案漏注 | 低 | 实现该改 I7 |
| 选中块：2px accent 描边 | `TreemapView.swift:527-528` `stroke(accent, lineWidth: 2)` | ✅ | 与稿 `.sel { outline: 2px #0A84FF }` 一致 | — | — |
| 标记块：斜纹 + 右下勾标 | `TreemapView.swift:478-525` 白纹 + 勾标 | ⚠️ 部分 | 稿对 Xcode 同时画 **暗纹(reclaimable) + 勾标(marked)**；实现**标记后暗纹让位给白纹**。取舍不同，视觉略异 | 低 | 实现该改 I12 |
| 可清理斜纹（hatch） | `TreemapView.swift:472-475` 暗纹 0.20 | ✅（语义） | 与稿斜纹语义一致（色相=种类、斜纹=可清） | — | — |
| 退色块 `dim`（如 Other 8.3 GB、iCloud 只读子块） | 无对应实现 | ⚠️ | 稿 `.dim` 语义未定义（只读？非首要？），实现用**深度提亮**(`TreemapPalette.shade`) 表达层级，无显式 dim 态 | 低 | 设计稿该改（dim 语义请定） |
| header 带（目录名带）默认高 20px | `TreemapLayoutOptions.headerHeight = 14`（`TreemapView.swift:116`） | ❌ | **P6.6 实测 14pt**（父块与嵌套子块同一个值，28px@2x）；稿默认 20px、稿自绘 16px | 低 | 实现该改 I9 |
| 块内标签阈值（≥40pt 才画） | `TreemapView.swift:500-516` 宽≥68高≥30 / 宽≥34高≥16 | ⚠️ | 稿未给阈值；代码阈值与稿示意块大小能否容下文字需 ⚠️待真机测量 | 低 | ⚠️ |
| treemap 背景 = under-page | 容器背景 | ⚠️ | 稿 `.treemap { background: var(--c-under-page) }`；实现 treemap 由 Canvas 绘制，块间空隙透出 content 背景，是否填 under-page ⚠️待真机测量 | 低 | ⚠️ |
| 「其余 N 项」合并块 | `TreemapLayout.place` `others:`（`TreemapView.swift:151-161`；P36 现读：合并块在 `place`（`:140` 起）里组装，不在 `compute`（`:132`）里） | ✅（代码分支） | 面积守恒合并，稿未显式画；属 disktree 采纳项，稿未覆盖 | 低 | 设计稿该改 S2 |

### 1.5 图例

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 7 色块 + 「可清理（斜纹）」+ 说明 | `MMDisk.swift:479-524` `legend` | ✅（结构） | 色块顺序一致 | — | — |
| 说明「面积 = 实际磁盘占用（st_blocks × 512）· 双击下钻 · ⌘ 点击标记」 | `:499-501` | ❌ | 实现说明**省略了 `(st_blocks × 512)`** 注脚，写「面积 = 实际磁盘占用 · 双击下钻 · ⌘ 点击标记」。数据确为 st_blocks，但文案精度低于稿 | 低 | 实现该改 I7 |
| 深度分段控件（1–4 层） | `:482-495` `Picker("深度")` | ⚠️ 部分 | 稿无此控件（对应 `MM_DISK_DEPTH` 钩子）；实现独有，稿缺 artboard | 低 | 设计稿该改 S2/S3 |

### 1.6 详情面板（inspector，选中 Xcode 时）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 头部图标 cube.box 紫（`i-box` + `--c-purple`） | `MMDisk.swift:689-690` `folder.fill/doc.fill` 按 `risk.color` | ❌ | 稿用 `i-box` 紫色图标；实现用 folder/doc 图标按风险色（safe=绿）。形状与颜色都不同 | 低 | 实现该改 I3 |
| 徽章「可安全清理」(safe) | `:685` `MMBadge(risk:)` → `risk.label`（`Risk.swift:14-20` = "安全"） | ❌ | 稿文案「可安全清理」=`risk.groupTitle`；实现 `MMBadge(risk:)` 用的是 `risk.label`="安全"。徽章文案与稿不符 | 低 | 实现该改 I2 |
| 路径「~/Library/Developer/Xcode」 | `:687` `node.path` | ✅ | 真实路径，夹具下为 /tmp 路径 | — | — |
| 四宫格：占用 / 实际占比 / 文件数 / 最后修改 | `:701-708` `MMStatItem` | ⚠️ 部分 | 实现四格为**占用 / 占当前层 / 子项 / 修改** | 低 | 实现该改 I4/I5/I6 |
| └「实际占比 17.0%」 | `:703` `占当前层` = `node.size/levelTotal` | ❌ | 稿「实际占比」暗示占总扫描量；实现「占当前层」分母随导航层变化。措辞与口径不同 | 低 | 实现该改 I5 |
| └「文件数 42,180」 | `:704` `子项 = children.count` | ❌ | 稿=递归文件数；实现=**直接子项数**（非文件数）。指标不同 | 低 | 实现该改 I4 |
| └「最后修改 2026-09-12」(绝对日期) | `:707` `MMFormat.relative` | ❌ | 稿绝对日期；实现相对时间（"3 个月前"），代码注释称绝对时间戳在 268pt 宽内会被截。取舍有意 | 低 | 两边都可（I6/ S‑） |
| 内部构成 3 行（DerivedData 28.4 / iOS DeviceSupport 12.1 / Archives 5.7） | `:710-729` `children.prefix(6)` | ✅（结构） | 实现取前 6 项按大小排序；稿画 3 项 | 低 | 记录 |
| └ 行高 32px | `:721-723` `MMMetric.rowCompact = 28` | ❌ | 稿 32pt vs 实现 28pt ⚠️待真机测量 | 低 | 实现该改 I10 |
| 按钮「在访达中显示」+「取消标记」(destructive) | `:732-741` `MMRevealButton` + 标记切换 | ⚠️ 部分 | 实现只有标记/取消标记普通按钮（非 destructive 样式）；稿「取消标记」标红。取消标记非破坏操作，impl 不标红更合理 | 低 | 设计稿该改 S‑（稿标红存疑） |
| 底部说明「DerivedData 可由 Xcode 重新生成…」 | `:746-757` `reclaim.note` + `risk.groupNote` | ✅（信息更全） | 实现同时给 reclaim 注 + 风险 groupNote，信息比稿更全；措辞不完全一致 | 低 | 记录 |

### 1.7 底部栏（statusbar / actionBar）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 「卷可用 28.1 GB」 | `:773` / `:283` actionBar summary（未标记时） | ✅（内容） | 未标记态文案一致 | — | — |
| 「统计不含符号链接目标 · 硬链接只计一次」 | `:775` actionBar note | ✅ | 与稿逐字一致 | — | — |
| 「标记后预计 76.7 GB」 | `:286` 面包屑徽章「卷可用 X → Y」 / `:1040` 确认 sheet | ⚠️ 部分 | 稿放在**底部状态栏**；实现放在**面包屑徽章 + 确认 sheet**，底部栏改为标记合计。位置不同但信息齐 | 低 | 实现该改 I8 |
| 底部栏高 28px（状态栏） | `MMDesign.swift:349` `MMActionBar` `MMMetric.actionBar = 52` | ❌ | 稿 28pt 状态栏 vs 实现 52pt 动作栏；**内容一致**（未标记时），容器样式/高度不同 ⚠️待真机测量 | 低 | 实现该改 I8 |

### 1.8 「值得看一眼」面板（实现独有）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| （稿中无此面板） | `MMDisk.swift:390-453` `findingsPanel` | ❌ | 实现在面包屑下插入整块「值得看一眼 · N 项 · 合计 X」面板（disktree #4 采纳）；**04 稿完全没画**，无法核对排版/文案 | **中** | 设计稿该改 S1 |

### 1.9 状态：选中 / 标记 / 确认删除 / 撤回 toast

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 选中 + 标记态（Xcode 勾标 + 描边） | `:996-1030` `applySelectionHook` + `TreemapView` 选中/标记绘法 | ⚠️ | 代码可构造；稿仅静态画了这一态，无独立 artboard；视觉 ⚠️待真机测量 | 低 | ⚠️ |
| 确认删除 sheet「把 N 项移入废纸篓？」+ 可回收/被拦分列 | `:1034-1114` `markConfirmSheet` | ❌ | **稿无确认 sheet artboard**；实现面板含 targets / blocked（lock 图标 + 原因）/ absorbed 提示，文案较稿丰富 | **中** | 设计稿该改 S2 |
| 撤回 toast「已移入废纸篓 X · 共 N 项 · 撤回」 | `:107-118` `MMUndoToast` | ❌ | **稿无 toast artboard**；`MM_SHOW_TOAST` 仅借用选中项数字摆一拍（`:1025-1029`），属合成态 | 低 | 设计稿该改 S2 |
| `MM_DISK_SCAN` 只认 /tmp，越界忽略 | `:171-176` 有守卫 | ✅ | **P20 现读更正：这一行原本记的是"缺失 ❌"**，当时判 I1（高）。现在越界会写 stderr「不在 /tmp 之下，忽略该钩子」并 `return`，`MM_DISK_SELECT` 同口径在 `:1086-1094` | 无 | 已收口（见 §0 第 2 条） |

### 1.10 状态：列表视图 / 大文件列表 / 扫描中 / 空态 / 过滤

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 列表视图（名称/占比条/大小行） | `:522-588` `listView` + `:592-634` `nodeRow` | ❌ | **稿无列表视图 artboard**；实现有完整列表+占比条+过滤态 | **中** | 设计稿该改 S2 |
| 大文件列表态（MM_OPEN_TAB=large） | `:647-670` `largeFilesList` | ❌ | **稿无大文件列表 artboard**；实现有，且分段控件还多一段「大文件」 | **中** | 设计稿该改 S2/S3 |
| 扫描中态（indeterminate ProgressView） | `:199-250` `scanningView` | ❌ | **稿无扫描中 artboard** | 低 | 设计稿该改 S2 |
| 空态（未扫描 / 层为空 / 过滤无命中） | `:181-194` `placeholder`、`:526`、`:566`、`:441` | ❌ | **稿无空态 artboard** | 低 | 设计稿该改 S2 |
| 过滤态（命中保色 / 祖先退色 / 判不了徽标） | `:456-463`、`DiskTreeFilter.swift` | ❌ | **稿无过滤态 artboard**；实现两级 tier（`TreemapView.swift:7-12,428-434`）对应 disktree 口径 | 中 | 设计稿该改 S2 |

## 2. 实现该改（12 条，按严重度排序）

> **复核 2026-10-04（P6.5b）**：**4 条已落地（I1/I2/I5/I7）、2 条部分落地（I4/I8）、6 条仍未做（I3/I6/I9/I10/I11/I12）**。
> **P8 更新（2026-10-05）**：I4 从"部分落地"变**已落地**（走回退标签那一支，见 §12），
> 所以这一族现在是 **5 条已落地（I1/I2/I4/I5/I7）、1 条部分落地（I8）、6 条仍未做（I3/I6/I9/I10/I11/I12）**。
> 落地集中在三个提交：`1145f05`（2026-09-30，补 /tmp 守卫）、`5e1dfe3`（2026-09-30，详情文案口径，
> commit body 直接按 I2/I5/I4/I7 编号写的）、`f249ee0`（2026-10-01，P2 撤掉假投影）。
> 另外这一轮纠正了三处**清单自身**的问题：① I1 的"唯一破口"说法已经不成立（守卫后来覆盖了三个钩子）；
> ② I9/I12 的文件在 **MMUI** 不在 MMDisk（`Packages/MMUI/Sources/MMUI/TreemapView.swift`，自 `4e6d4c1` 初始化就在共享包里），
> 清单当时只写了裸文件名；③ I10 判反了方向——实现和**令牌**一致，是稿内一处内联样式顶掉了自己的令牌。
> 逐条给今天的坐标；未做的六条里 I9/I10/I11 还挂着 `⚠️待真机测量`，四天没量。
>
> **P6.6 收口（2026-10-04）**：挂了四天没量的那三条 `⚠️待真机测量`（I9/I10/I11）里，**I9 与 I11 已经量掉了**
> （`Scripts/p66-layout-measure.sh` → `docs/verification/p66-layout/`，@2x 色带边界，见 §2 对应条目），
> **I10 判定为"不需要量"**（要改的是稿的内联样式，实现与令牌一致），只剩 I3/I6 属改稿、I2/I8/I12 属协调层。
> 这一轮同时把 §1 表里那两行的"⚠️待真机测量"改成实测量，别再让下一个人以为还要跑一次。

1. **【高】I1 · `MM_DISK_SCAN` / `MM_DISK_SELECT` 缺 /tmp 越界拦截**
   `MMDisk.swift:139-140` 直接 `guard ... let root = env["MM_DISK_SCAN"] ... await scan(rootPath: (root as NSString).expandingTildeInPath)`，
   不检查路径是否落在 `/tmp` 之下。`MM_DISK_SELECT`(:998) 同样不限前缀，只靠"先扫过才有节点"间接约束。
   按 README §5 红线——"钩子一律只认 /tmp 之下的夹具路径，越界就写 stderr 并忽略"——这是本模块对那条红线的
   **唯一破口**：一旦被设成真实目录（如 `MM_DISK_SCAN=~` 或 `/`），`scan()` 会去 `lstat`/`readdir` 真实磁盘树，
   即使扫描本身只读，也会触碰真实用户文件、且深度 20 的整树枚举极重。
   → 建议：在 `MMDisk.swift` 的扫描钩子入口加 `root.hasPrefix("/tmp")` 判定，否则 `stderr` 写"MM_DISK_SCAN 仅接受 /tmp 之下路径"并 `return`。
   **本环境未修改**（硬约束 #4 优先"提请协调者"），见 §提请协调者。
   **✅ 已落地（`1145f05`，2026-09-30）**，且比建议更严：
   - `MM_DISK_SCAN`：`MMDisk.swift:178-182`，同时认 `/tmp/` 与 `/private/tmp/`（后者是 `/tmp` 的真实身份，只判前缀会漏），
     越界写 stderr「MM_DISK_SCAN=… 不在 /tmp 之下，忽略该钩子」后 `return`，不扫描；
   - `MM_DISK_SELECT`：`:1091-1096`（**P40 现读重指**，原记 `:1099-1104`——那一段今天落在"只重放一次"那段注释上），**任一**目标不在 /tmp 之下就把整个钩子忽略（不是逐条丢弃），
     理由是"预选并展开"会连带把真实目录的整层拉进截图；
   - 入口注释（`:176-177`，P40 现读；原记 `:180-181`）点名依据是 hook-ledger §4.3，所以这条现在是被账本约束的，不再是各模块自便。
   **后来补的第三个**：`MM_DISK_RESCAN` 是 `828e457`（2026-10-03，P6.2a 标记跨重扫）新加的钩子，
   它自己带同样的守卫（`:187-195`，P40 现读；原记 `:193-197`）——新钩子沿用了守卫形状，说明这条红线已经起效了。
   **所以原清单"唯一破口"这句要撤回**：当时确实是磁盘独有的破口，今天磁盘反而是**覆盖最全的一页**
   （**P40 现读口径**：三个钩子、**三处守卫**，`grep -c 'hasPrefix("/tmp/")' Packages/MMDisk/Sources/MMDisk/MMDisk.swift` → 3，SCAN 在 `:178`、RESCAN 在 `:189`、SELECT 在 `:1092`，每处都同时认 `/tmp/` 与 `/private/tmp/` 两个前缀。从前这里写的是"四个判据"，对不上今天的实物面）。判高没有判错，只是修它的人没回写这里。
2. **【低】I2 · 详情徽章文案「安全」≠ 稿「可安全清理」**
   `MMBadge(risk:)`(`MMDesign.swift:255-256`) 取 `risk.label`（`Risk.swift:14-16`，`.safe`="安全"），稿 `.badge.safe` 文本为「可安全清理」（= `risk.groupTitle`）。
   → 建议：徽章改取 `risk.groupTitle`，或 04 稿改文案为「安全」。两者择一。
   **✅ 本页已落地（`5e1dfe3`），但组件默认值没动，问题升级成站级的**：
   详情徽章现为 `MMBadge(risk.groupTitle, tint: risk.color, systemImage: risk == .readOnly ? "lock" : nil)`
   （`MMDisk.swift:779`）。可共享的 `MMBadge.init(risk:)`（现 `MMDesign.swift:255-256`）**仍取 `risk.label`**，
   今天还有四个调用点在用「安全」这一套（P16 现读 `grep -rn "MMBadge(risk:"`，全仓恰好四处）：`MMDesign.swift:866`（`MMItemRow` 的行内徽章）、
   `MMUninstaller.swift:1871`、`MMOptimizer.swift:533` 与 `:872`。
   （**P35b 现读重指**：这一串是 P16 那一次 grep 的读数，本轮重跑同一条命令，四处里**只有 `MMDesign.swift:866` 还落在原行上**，
   其余三处已经各自走了一批行号；"恰好四处"这条主张仍然成立，所以门禁给的是**位置存疑**而不是硬失败——
   行号不空、文件命中、句子不错，只有"它指的那一行是不是那句话说的东西"没人管。这一类本轮记进 `release-readiness.md` §1 那一格。）
   → 这不是漏改，是一个**没写下来的站级约定**：行内徽章用短标签（列宽只有 44–92pt，「可安全清理」放不下），
   分组/详情徽章用长说法（`risk.groupTitle` 本来就是分组标题）。建议按这个口径把约定写进 MMUI 注释并划掉本条，
   **而不是**统一成一种——统一成 `groupTitle` 会把三页的行内徽章撑破。归协调层。
3. **【低】I3 · 详情头部图标不符稿**
   稿用 `i-box`（cube.box）紫色；实现 `MMDisk.swift:689` 用 `folder.fill`/`doc.fill` 按 `risk.color`。形状与颜色都不同。
   → 建议：统一为稿的 cube.box 紫，或更新稿说明图标随风险色变化。
   **❌ 仍未做（复核 2026-10-04）**：详情头部图标现在是 `MMDisk.swift:772`
   （`node.isDirectory ? "folder.fill" : "doc.fill"`，随风险色），稿侧对应处仍是
   `docs/design-system/screens/mmdisk/04-disk.html:154` 的 `#i-box` + `--c-purple`。
   顺带纠正清单当时的一个混淆：`:688` 那处 `folder.fill`/`doc.fill` 是**列表视图的行图标**，不是详情头部，
   稿在列表段没有画死图标，所以只有 `:772` 这一处算差异。**这一条倾向改稿**——"形状随类型、颜色随风险"
   比一律一个紫色方块携带的信息多，而且是实现先做对的。
4. **【低】I4 · 详情「子项」≠ 稿「文件数」**
   `MMDisk.swift:800` 显示 `children.count`（直接子节点数）；稿写「文件数 42,180」（递归文件数）。两者量的是不同东西。
   → 建议：若需"文件数"，应递归累加 `collect` 得到的 `fileCount`；或稿改文案为「子项」。`disktree-adoption` 里 `fileCount` 已统计（`:1466`），可直接喂给详情。
   **⚠️ 部分落地（`5e1dfe3`）——而且这一改留下了新的坑**：标签已换成「文件数」（当时在 `MMDisk.swift` 第 792 行，
   **P35b 现读已在 `:800`**，且下一段会说明它随后又回退成「子项」），
   数值仍是 `children.count`，代码里自己承认（当时那两行注释，现读在 `:798` 那一行——它已经把结论改成
   「标签必须等于数值真实的口径：这里是**直接子项数**，不是稿里那个递归「文件数」」）。
   也就是说这一格**当时读起来比改之前更容易误会**：「子项 12」没人会当递归数看，「文件数 12」会被当成"这个目录只有 12 个文件"。
   **并且建议里那句"`fileCount` 已统计、可直接喂"是错的**（复核确认）：`fileCount` 只有**扫描根级**那一份
   （`DiskScanResult.fileCount` 与 `ScanOutput.fileCount`，由 `performScan` 根上那段 `collect` 累加），
   `DiskTreeNode` 里**没有**每节点的递归文件数字段（结构体只有 size/isDirectory/children/category/
   modificationDate/descendantsMeasured 那一族，没有计数）。
   要真做出"文件数"必须给遍历器加一个每节点递归计数——这是 MMDisk 的 `FileTreeWalker` 改动，不是文案改动。
   **✅ 已收口（P8，2026-10-05）——走"回退标签"这一支，并补上封顶那一档**：标签回到「子项」
   （`MMDisk.swift:800`），判定从视图里抽成可单测的纯函数 `DiskInspectorText.childCount(of:enumerated:)`
   （`:1643-1647`，枚举声明在 `:1642`）：文件→「—」、量到的目录→`MMFormat.count(直接子项数)`、
   **`descendantsMeasured == false` 的封顶节点→「未枚举」**。最后这一档是复核时才查出来的、
   比原条目更糟的一处：`if depth >= maxDepth`（`:1939`，`maxDepth = 20` 见 `:1779`）那一支造的节点
   `children` 是空的（字节靠 `deepSize` 兜底，`:1943`），照 `children.count` 显示就是**对着一个 2.2 MB
   的目录说"文件数 0"**——那是把"没量到"写成"没有"，比标签错更严重。
   单测：`Packages/MMDisk/Tests/MMDiskTests/DiskInspectorTextTests.swift` 四档各一条
   （含"未枚举那一档不许出现 0"）。实机：`docs/verification/p8-disk-depth/`
   （`Scripts/p8-disk-depth-capture.sh` + 20 层夹具 `Scripts/disk-depth-fixture.sh`），
   三档画面上分别是 **未枚举**（占用 2.2 MB 同时给着，正是这一对）/ **2**（与下面「内部构成」
   那两行 L02+marker.bin 逐字对得上）/ **—**。
   **没有做**每节点递归文件数：详情这一格答的是"这一层装了什么"，递归数对下钻决策没有帮助。
   于是这一条变成**稿侧待改**——`docs/design-system/screens/mmdisk/04-disk.html:163` 仍写「文件数 42,180」，
   与 I3（`:154` 的 `#i-box`）、I6（`:164` 的绝对日期）可以并成一次重绘。
5. **【低】I5 · 「占当前层」vs 稿「实际占比」**
   `MMDisk.swift:685` 分母 `levelTotal` 随导航层变化；稿「实际占比」暗示占总扫描量。措辞/口径不一致。
   → 建议：稿明确"占当前层"，或实现在根层用 `scannedSize` 作分母并改标签。
   **✅ 已落地（`5e1dfe3`），走"改实现"这一支**：详情现为
   `MMStatItem("实际占比", MMFormat.percent(totalScanned > 0 ? Double(node.size) / Double(totalScanned) : 0))`
   （`MMDisk.swift:797`），`totalScanned` 取 `scanResult?.scannedSize ?? 0`（`:768`）——分母不再随下钻漂移，
   标签与算法终于同一口径。**"占当前层"没有丢**：列表行仍按 `levelTotal` 算占比（`:685`），
   那里"这一层里谁大"才是有用信息。两处分别对应两个问题，是对的。
6. **【低】I6 · 修改时间绝对 vs 相对**
   `MMDisk.swift:803` `MMFormat.relative`；稿绝对日期。实现注释已说明绝对时间戳在 268pt 内会被截。属有意取舍，两可。
   → 建议：保留相对，但稿应改为相对时间示例，避免"稿画绝对、实现相对"的落差。
   **❌ 仍未做（复核 2026-10-04）**：`MMDisk.swift:803` 仍是 `MMFormat.relative(modDate(of: node.path))`，
   取舍理由写在紧邻注释里（`:798-799`：这格要答"多久没动过"，且完整时间戳会被截成"2026-09-30 01:…"）。
   没动的是**稿**（`04-disk.html:164` 仍画绝对日期）。这一条本来就判"两可"，缺的是稿侧一次改示例——
   与 I3 可以并成一次 `04-disk.html` 重绘，见 §3 末尾那条合并建议。
7. **【低】I7 · 图例漏注 `(st_blocks × 512)`**
   数据确用分配大小（`MMDisk.swift` 的 `readEntries`，现 `:1893` 起、取值在 `:1916`），但 `legend(filtered:)`
   当时写「面积 = 实际磁盘占用」而稿写「面积 = 实际占用（st_blocks × 512）」——数据口径对，文案精度低于稿。
   → 建议：图例补回 `(st_blocks × 512)` 注脚，与稿对齐，也兑现 disktree 采纳的口径承诺。
   **✅ 已落地（`5e1dfe3`）**：图例现为 `MMDisk.swift:598-600`，非过滤态
   「面积 = 实际磁盘占用（st_blocks × 512）· 双击下钻 · ⌘ 点击标记」，与稿 `04-disk.html:148` 同口径。
   比建议多做了一步的**是对的**：过滤态另给一句「过滤中：面积 = 命中占用 · 实色 = 命中 · 淡色 = 含命中的祖先」（`:589`），
   因为过滤时面积换成了命中体积，注脚若只有一份就会假报口径（`:585-586` 有说明）。
8. **【低】I8 · 底部栏 52pt 动作栏 vs 稿 28pt 状态栏**
   未标记态内容一致（卷可用 / 统计不含…），但容器是 `MMActionBar`(52pt,`MMDesign.swift:349`) 而非稿的 28pt 状态栏；"标记后预计"也被挪到面包屑。
   → 建议：标记后底部栏出现动作按钮是合理的，但稿需补画"标记后动作栏"artboard；未标记态可考虑降级为更薄的状态条以贴合稿。
   **⚠️ 半件落地，且落地的那一半比原建议更重要（`f249ee0`，2026-10-01，P2）**：
   "标记后预计"这个投影被**取消**而不是挪位置——面包屑处现在只报当下事实
   （`MMDisk.swift:379` `MMBadge("卷可用 …")`），理由与实测都在注释里（`:374-378`）：
   同卷把条目移进 `~/.Trash` 不改变可用空间（`Scripts/trash-space-measure.swift`，200 MiB 文件实测 0 变化），
   所以「卷可用 X → Y」的 Y 是一个**不会兑现的数**；投影只留在两块确认面板里，且分清口径
   （`:1168` 回收后"清空废纸篓后卷可用"、`:1212` 永久删除"这一步当场生效"）。
   这一条把 I8 的**语义**一半解决了，**几何**一半没动：容器仍是 `MMActionBar`（调用点 `:865`，
   高度 `MMMetric.actionBar = 52`，`MMDesign.swift:115`），稿仍是 28pt 状态栏、也仍没画"标记后动作栏"。
   → 归协调层（动 `MMActionBar` 高度影响多页）；稿侧待补的那张 artboard 记在 §3 S2。
9. **【低】I9 · treemap header 带 14pt vs 稿 20pt**
   `TreemapLayoutOptions.headerHeight = 14`(`TreemapView.swift:116`)；稿 `.cap` 默认 20px（子块 16px）。⚠️待真机测量确认视觉落差。
   → 建议：若真机看 header 带过窄，提到 18–20pt；或稿改 14pt。
   **❌ 仍未做，且先纠正归属**：文件是 `Packages/MMUI/Sources/MMUI/TreemapView.swift:116`（**共享包**，
   自 `4e6d4c1` 就在 MMUI 里，不在 MMDisk——清单当时只写裸文件名，读者会去磁盘包找不到）。
   稿侧也**不是单一值**：`04-disk.html:9` 的 `--cap` 默认 20px，而稿内实际画的五个块全部内联覆写成 16px
   （`:88`、`:90`、`:119`、`:125`、`:138`）。所以现在是**实现 14 / 稿默认 20 / 稿自绘 16** 三个数，
   而 `⚠️待真机测量` 挂了四天没量。**改共享组件的默认值需要协调者**（MMDisk 也可以在 `options` 里覆盖，
   但那就是第五个值了）。这一条与 I10/I11 同批：先量，再决定往哪边收。
   **✅ 已量（P6.6，2026-10-04）**：`docs/verification/p66-layout/01-disk-root.png`（@2x，2200×2000 px = 1100×1000 pt），
   用 `swift Scripts/pixel-probe.swift <png> scan x <x> <y起> <y止>` 沿一条无字竖线打色带：
   Downloads/Documents 两块父块的 header 带都是 **y=290..317 = 28px = 14pt**；
   `02-disk-drill.png` 里钻到 Library 后，嵌套的 Developer 带 **290..317** 与它的子块 Xcode 带 **320..347**
   也都是 28px —— **实现不分层，每一层都是 14pt**，"子块 16px"这一档实现里不存在。
   所以三个数今天量成了：**实现 14pt（实测）/ 稿默认 20px / 稿自绘 16px**，实现比稿默认窄 6pt。
   观感上真正的问题不是"14pt 太窄"而是**嵌套时 header 会叠**：两层 header 吃掉 28pt 才轮到内容，
   稿的 20px 若照搬，两层就是 40pt。→ 值本身仍是协调层决定（改 `MMUI` 默认值影响全站），
   但**"要不要随深度递减"这个新问题只有量了才看得见**，建议带着这句去协调。
10. **【低】I10 · 内部构成行高 28pt vs 稿 32px**
    `MMMetric.rowCompact = 28`(`MMDesign.swift:111`，2026-10-04 现读；原文记 `:83` 已漂)；稿 `.rrow` 32px。⚠️待真机测量。
    **❌ 仍未做，但方向判反了——这条应改稿**（复核 2026-10-04）：实现的 28pt 就是设计令牌的值
    （`MMDesign.swift:111` `rowCompact = 28` ↔ `docs/design-system/tokens.css:37` `--row-h-compact: 28px`）；
    32px 来自稿里那三行**内联**样式（`04-disk.html:169`、`:172`、`:175` `style="height:32px;padding:0 var(--sp-2)"`），
    而 `.rrow` 的基线是 `var(--row-h-regular)`=44px（`screen.css:54-56` + `tokens.css:38`）。
    也就是说稿用内联顶掉了自己的令牌，还顶出一个第三值。**实现与令牌一致，破口在稿**：
    把那三处 `height:32px` 删掉、让它落回 `--row-h-compact`（或明确写 28px）即可。
    列入 §3 该改，不再算实现差异。
    **⏳ P6.6 没有量它，而且要先纠正上一轮的一句话**：§2 I11 那里写的"量一次磁盘页即可同时结掉 I9/I10/I11"
    是**过于乐观的**——I10 问的「内部构成」行在**详情面板**里，而 P6.6 那两张磁盘图都在 Treemap tab，
    面板根本没出现（要拍得再开一档 `MM_OPEN_TAB=list` + `MM_DISK_SELECT`）。没补这一档是因为**它的判定不依赖测量**：
    实现 28pt == 令牌 28px 已经是代码级事实（`MMDesign.swift:111` ↔ `tokens.css:37`），
    量出来只会再确认一遍，而该改的是稿里那三行内联。留作**改稿后的一次复核**，不算取证欠账。
11. **【低】I11 · 面包屑栏 34pt vs 稿 26px**
    `.frame(height: 34)`（写作当时引的 291 行现已漂成别的内容，P16 现读全文件**只有这一处** `.frame(height: 34)`，当时落在 `MMDisk.swift:390`；**P40 现读在 `:382`**，而 `:390` 今天是 `findingsPanel` 的声明行——**门禁四道判据对它全绿**：文件在、行不越界、那一行有字、无歧义，只是那一行说的不是这件事）；稿 `.crumbs` 26px。⚠️待真机测量。
    **❌ 仍未做**：锚点 `MMDisk.swift:382`（P40 现读重指，原记 `:390`），值没变；
    稿侧 `screen.css:126` `.crumbs{… height: 26px}`。差 8pt，方向是实现更厚——这一条**先量再改**：
    34pt 是 P4 最小窗口核对（task #55）之后仍在的值，压到 26 要看面包屑里的徽章与
    「这些路径这次没扫到」提示（`:362-368`）会不会挤。量一次磁盘页即可同时结掉 I9/I10/I11 三个 `⚠️待真机测量`
    （同一屏，一次截图，不用分别跑）。
    **✅ 已量（P6.6，2026-10-04）**：`01-disk-root.png` 上沿 x=600/1700/2150/2180 四条竖线都撞出同一组边界——
    分隔线 **y=194..195**、白条 **y=196..261**，合起来 **68px = 34pt**，与 `.frame(height: 34)` 逐像素吻合；
    稿侧 26px 的差**是真的 8pt**，不是舍入。
    **"压到 26 会不会挤"这一问现在有数了**：栏里那枚「卷可用 41.66 GB」药丸实测 **y=212..247 = 36px = 18pt 高**，
    34pt 栏还剩 16pt 上下留白；照稿压到 26pt 只剩 8pt（每侧 4pt）。
    `02-disk-drill.png` 里面包屑已经是两级（`macmaster-disk-fixture › Library`）+ 右侧两枚徽章，
    栏高**没有随级数增长**（同样是 194..261），说明它是固定框、装不下只会横向截。
    → 结论：**8pt 差成立，但"改哪边"要连徽章一起判**。要么稿抬到 32–34px（承认徽章需要高度），
    要么实现压到 26px 并**同时**把徽章降到 ≤16pt——单改 `.frame` 会把药丸挤成贴边。仍属协调层（`screen.css` 是稿侧共享样式）。
12. **【低】I12 · 标记后暗纹让位白纹**
    稿对 Xcode 同时画 reclaimable 暗纹 + marked 勾标；实现 `TreemapView.swift:472-481` 标记后暗纹被白纹覆盖，只看到白纹+勾标。
    → 建议：标记态是否保留一层暗纹底以同时表达"可清+已标"，与稿作者确认；属视觉取舍，非错误。
    **❌ 仍未做，且它是**带理由的**没做（复核 2026-10-04）**：`Packages/MMUI/Sources/MMUI/TreemapView.swift:469-481`
    ——暗纹（`.black 0.20`，spacing 6）判据是 `cell.item.reclaimable, !isMarked`，亮纹（`.white 0.4`，spacing 7 + 勾标）判据是 `isMarked`；
    紧邻注释写明"暗纹是属性、亮纹是意图，两者不能撞车，所以一旦被标记暗纹就让位"。
    这不是漏实现，是一个**与稿相反的设计决定**，需要稿侧拍板：要么稿改成"标记后只画亮纹+勾标"，
    要么给出一个能同时读出的第三种画法（例如勾标底色沿用可清色相）。同 I9：文件在 MMUI，改它属协调层。

> 另外两笔不在差异计数内、但记于此：① 工具栏"重新扫描"语义（重枚举当前层 vs 稿的重扫全根）与多出的"选择目录"按钮（§1.2）；
> ② 面包屑行首缺独立返回箭头（§1.3）。均无真机落差风险，列为低优先，随 1.2/1.3 一并处理。

> **P6.5b 收口小结（磁盘页）**：12 条里真正还"欠代码"的是 4 条，而且没有一条是高危——I1 那条高危早在一号
> 就修完了没回写。剩下的分布是：**改稿 3 条**（I3 图标、I6 时间示例、I10 行高）、
> **改共享组件需协调 3 条**（I2 徽章口径约定、I9 header 带、I12 暗纹让位）、
> **需一次测量才能定 3 条**（I9/I10/I11 同屏，一次截图可结）、
> **需一个遍历器字段才能定 1 条**（I4，且建议回退标签）。
> 稿侧三条（I3/I6/I10）值得**并成一次 `04-disk.html` 重绘**，别分三次改同一个文件。
>
> **P6.6 之后这一段只剩两类**（2026-10-04）：`需一次测量才能定 3 条` 那格作废了——量完之后是
> **I9 = 14pt（实测，父块与嵌套子块同值）、I11 = 34pt（实测，栏内徽章自己就占 18pt）**，
> I10 不需要量（改稿）。所以真正的分布是：**改稿 3 条**（I3/I6/I10）、
> **协调层 4 条**（I2 徽章口径、I8 动作栏高度、I12 暗纹让位，加上 I9/I11 这一对"数值往哪边收"——
> 它们现在带实测数，不再是要先去量的空位）、**I4 等一个遍历器字段**。
>
> **P8 之后（2026-10-05）**：`I4 等一个遍历器字段` 这一格也作废了。遍历器字段**决定不做**
> （详情那一格答"这一层装了什么"，递归数对下钻没有帮助），改成标签回退「子项」+
> 封顶节点说「未枚举」，所以 I4 从"欠代码"变成**欠稿一次改示例**，与 I3/I6 并成同一次
> `04-disk.html` 重绘即可。真正欠的清单因此是：**改稿 4 条**（I3/I4/I6/I10）、
> **协调层 4 条**（I2/I8/I12 + I9/I11 那一对数值）、**部分落地 1 条**（I8 见 §2 原条目）。

## 3. 设计稿该改（清单 7 条 S1–S7；P40 现读还开 5 条，标题从前写 6 条）

1. **【中】S1 · 04 稿缺「值得看一眼」面板**
   实现 `MMDisk.swift:390-453` 在面包屑下插入整块发现面板（disktree #4 已采纳），稿完全没画。该面板是模块核心信息区，
   无 artboard 即无法核对其排版、徽标色（`kindTint`）、截断与合计文案。
   → 补一个 artboard：面包屑下 6 行发现（可回收/久未触碰/大文件 三色徽标 + 名称中段截断 + 原因 + 大小 + 箭头）。
2. **【中】S2 · 04 稿状态覆盖严重不全**
   列表视图态、大文件列表态、确认删除 sheet、撤回 toast、扫描中态、空态（未扫描/层空/过滤无命中）、过滤命中态——
   **实现都能画，稿一个 artboard 都没有**。这直接违反 README §4"每屏 artboard 要覆盖该视图真能画出的每一种状态"。
   → 至少补：列表视图 artboard、大文件列表 artboard、确认删除 sheet artboard、撤回 toast artboard、扫描中 artboard、空态 artboard、过滤态（保色/退色/判不了）artboard。
3. **【低】S3 · 分段控件缺「大文件」段**
   稿只有 Treemap/列表 两段；实现 `ViewMode` 有 3 段（含大文件），且 README §2 钩子明确列 `MM_OPEN_TAB(large)`。
   → 稿分段控件补「大文件」段，与模块契约一致。
4. **【低】S4 · 稿内自相矛盾**
   ① 面包屑写「Macintosh HD › lee › Library › Developer」，副标题却写「~/Library · …」——根不一致；
   ② 面包屑徽章「已标记 3 项 · 48.6 GB」但 treemap 内仅 Xcode 一个勾标。属稿内占位数据相互打架。
   → 统一为同一扫描根的连贯示意（例如都基于 `~/Library` 起点，且标记数=图内勾标数）。
5. **【中】S5 · 侧栏 footer 全站画错**（沿用 `fidelity-monitor.md` S1）
   01–08 各稿都画成「分隔线 + 设置 nav-item」，实机是**卷容量行（Macintosh HD + 红色容量条）+ 带边框设置按钮**。
   04 稿为系列一致沿用了错误画法。正确做法是在 tokens/screen 层补一个侧栏 footer 组件，八张稿一起换；
   实现侧属 shell 共享层（非 mmdisk 能改），故记此待协调者统筹。〔**P38f 现读：这条作废、并且换了形状**——组件与"八张稿一起换"都由 `0c61fbf`（2026-09-30）做完，04 稿当时就在换的那十张里；今天 20 张稿 19 张在用、实例 25 处（**P41f 现读**，旧记 16 张 / 21 处）。本模块因此不再欠协调者，**反而欠自己一处**：后画的 04b/04e 两块 artboard 的侧栏**整块没画 footer**（`04b-disk-confirm.html` 改稿前第 76-84 行、`04e-disk-rescan.html` 改稿前第 45-53 行 与同文件 :100-108），补画要重渲染这两页的 png，见 `release-readiness.md` §7.35。〔**P39 补完、两页已重渲染**，本条今天没有尾巴，见 §7.36。〕
6. **【低】S6 · 侧栏尾数占位**（沿用 `fidelity-monitor.md` S2）
   「系统清理 2.4 GB」「应用卸载 46」在 04 稿无数据来源，应改成与实机一致的数值或留空，避免"稿子数字像实测"。
7. **【低】S7 · 稿内三处滞后/自相矛盾，建议并成一次 `04-disk.html` 重绘**（P6.5b 复核新增）
   这三处都在 §2 复核时从"实现差异"改判为"稿差异"，且都在同一个文件里，分三次改只会互相顶：
   - 详情头部图标 `#i-box`（`:154`）——实现按类型给形状、按风险给颜色（`MMDisk.swift:780`），信息量更大，改稿不改实现；
   - 「修改」示例（`:164`）应换成相对时间（"3 天前"），与实现的 `MMFormat.relative` 一致（`:800`，理由在 `:798-799`）；
   - 「内部构成」三行的内联 `height:32px`（`:169`/`:172`/`:175`）顶掉了自家令牌
     `--row-h-compact: 28px`（`tokens.css:37`），删掉内联即可回到一致口径——这一处见 §2 I10。
   另外**记一笔不算差异的**：稿默认 `--cap: 20px`（`:9`）与稿内实际画的 16px（`:88` 起五处）自己就不一致，
   实现取 14（`MMUI/Sources/MMUI/TreemapView.swift:116`）。三个数同时存在时，"谁对"这种问法不成立——
   先按 §2 I9/I11 的待测量一次截图，再由量到的那个值反推稿与令牌。
   **P6.6 量完了，这一句可以落地成具体改稿建议**：实机是 **header 带 14pt（每层同值）** 与 **面包屑栏 34pt（栏内徽章自己占 18pt）**。
   于是稿侧有两个数要动，而且方向不同：`--cap: 20px` 与那五处内联 16px **两个都不对实机**，
   但"照实机改成 14"要先回答**嵌套时是否随深度递减**（两层 14pt 已经吃掉 28pt，两层 20pt 就是 40pt）；
   `.crumbs{height:26px}`（`screen.css:126`）则**几乎肯定是稿错了**——26px 装一枚 18pt 药丸只剩每侧 4pt 呼吸，
   而这条样式是全站共享的，改它影响所有页，所以这两处仍归协调层拍板，只是现在**带着数去拍**。

## 4. 没能验证到的部分（逐条写明缺什么，不写"应该没问题"）

以下状态**只在代码里读到分支**，无设计 artboard、且无实机截图可核。根因统一是：04 稿只画了 treemap 已扫描+选中这一种态，
而本模块虽有 7 个钩子，无头环境仍无法真机渲染（禁启动 App / 禁截图 / 禁合成事件）。

| # | 未验证项 | 为什么验不了 | 需要什么才能验 |
| --- | --- | --- | --- |
| 1 | 列表视图态（名称/占比条/大小行） | 稿无 artboard；无头 | 补 04 稿列表 artboard + `MM_OPEN_TAB=list` 起实例按 pid 抓窗 |
| 2 | 大文件列表态 | 稿无 artboard；无头 | 补 artboard + `MM_OPEN_TAB=large` 抓窗 |
| 3 | 确认删除 sheet（targets/blocked/absorbed） | 稿无 artboard；无头 | 补 artboard + `MM_DISK_SCAN`(fix 后 /tmp) + `MM_SHOW_CONFIRM` 抓窗 |
| 4 | 撤回 toast 排版/文案 | 稿无 artboard；无头 | 补 artboard + `MM_SHOW_TOAST` 抓窗 |
| 5 | 扫描中态（indeterminate ProgressView 文案） | 稿无 artboard；无头 | 补 artboard + 暂停钩子 |
| 6 | 空态三档（未扫描 / 层空 / 过滤无命中） | 稿无 artboard；无头 | 补 artboard |
| 7 | 过滤态（保色/退色两级 + 判不了徽标） | 稿无 artboard；无头 | 补 artboard + `MM_DISK_FILTER` 抓窗 |
| 8 | treemap 全部像素几何（块位置、header 带 14pt、斜纹密度、标签阈值、背景 under-page） | 无头、Canvas 绘制 | ~~需要起实例取色~~ **P6.6 已做一半**：`docs/verification/p66-layout/01`+`02` 用 `pixel-probe.swift … scan x` 量到 header 带 14pt（父块/嵌套同值）、块间底色 (236,237,237)、斜纹周期 12px≈6pt；**仍未量**的是标签阈值（宽≥68/高≥30 那组）与"块位置是否逐像素复现稿" |
| 9 | 选中/标记态的描边+勾标+暗纹/白纹叠加观感 | 稿仅为静态示意、无独立态 | 同上抓窗 |
| 10 | 详情面板四宫格在 268pt 内的真实折行/截断 | 无头 | 同上抓窗 |
| 11 | 浅色模式配色 | 稿按设计系统浅色档，实机未跑 | 浅色外观下重跑 `render.sh` + 真机截图 |
| 12 | `MMFormat.bytes/count/percent/relative` 各 locale 输出 | 只在本机默认 locale 量过 | `MMFormat` 单测矩阵，不属稿能验证 |
| 13 | 真实扫描数字（文件数、各类占用） | 无 /tmp 夹具、禁止碰真实目录 | 协调者提供 /tmp 夹具树后 `MM_DISK_SCAN` 跑一遍 |

**已验证的部分**（与上表相对，避免把整页写成"没验过"）：页头 46pt、详情栏 268pt、treemap 圆角 3pt、7 类分类与色值逐字一致、
副标题四字段顺序与 `MMFormat` 格式一致、徽章高 18pt、筛选框宽 132、分段控件存在、`st_blocks×512` 数据口径已落地、
选中 2px accent 描边、可清理暗纹语义、面包屑/底部栏文案内容、底部"统计不含…"注脚逐字一致、
「值得看一眼」面板的存在与字段来源、`MM_DISK_SCAN` 越界红线的缺失（代码静态确认）。

## 4.1 可注入档位映射（参照 #50 monitor 写法）

monitor 模块因"0 钩子"补了 `MM_MONITOR_FIXTURE/HOLD`；mmdisk **已有 7 个钩子**，缺口不在"有没有钩子"，
而在 **`MM_DISK_SCAN` 越界未拦（I1）** 与 **04 稿缺对应 artboard（S1/S2）**。逐项对应如下：

| §4 # | 未验证项 | 可用钩子 | 启动方式（按 pid 抓窗，全程零合成事件） |
| --- | --- | --- | --- |
| 1 | 列表视图态 | `MM_OPEN_TAB=list` | `MM_OPEN_TAB=list MM_DISK_SCAN=/tmp/夹具 …/MacMaster &` → 按 pid 抓窗 |
| 2 | 大文件列表态 | `MM_OPEN_TAB=large` | 同上，`MM_OPEN_TAB=large` |
| 3 | 确认删除 sheet | `MM_DISK_SCAN`+`MM_DISK_SELECT`+`MM_SHOW_CONFIRM` | 三钩同起，选中并标记后弹 sheet |
| 4 | 撤回 toast | `MM_DISK_SCAN`+`MM_DISK_SELECT`+`MM_SHOW_TOAST` | 同上，借用选中项数字摆一拍（合成态） |
| 5 | 扫描中态 | `MM_DISK_SCAN`（需暂停） | 当前无"冻结首帧"钩子，需补 `MM_DISK_HOLD=hold`（参照 `GuardianLoadHook`） |
| 6 | 空态三档 | `MM_DISK_SCAN=/tmp/空夹具` 等 | 不同夹具树触发各档 |
| 7 | 过滤态 | `MM_DISK_FILTER` | `MM_DISK_FILTER=DerivedData` 起实例 |
| 8–9 | treemap 像素几何 / 选中标记观感 | `MM_DISK_SCAN`+`MM_DISK_SELECT`(`MM_SHOW_CONFIRM`) | /tmp 夹具树 + 抓窗取色 |
| 10–11 | 详情折行 / 浅色 | 同上 + 浅色外观 | 浅色下重跑 `render.sh` + 真机截图 |
| 12–13 | locale / 真实数字 | `MMFormat` 单测 + /tmp 夹具 | 单测矩阵；协调者提供夹具 |

> **B/D 稿换夹具口径实测值**：04 稿目前**没有** B/D 这类分态 artboard，无法"换夹具重出"。
> 复核时 04 稿应**先补 S1/S2 所列 artboard**，再用上表钩子逐档构造真机态重出，不再依赖单一 treemap 示意。

**验证命令骨架**（集成阶段统一跑，全程零合成事件、`--pid` 抓窗；`MM_DISK_SCAN` 修复越界拦截后方可执行）：

```bash
# 重建（隔离，不碰现有 build）
swift build -o /tmp/mm-build --scratch-path /tmp/mm-scratch 2>/dev/null || \
  ./make-app.sh -o /tmp/mm-out -s /tmp/mm-scratch

# 逐档：起实例 → 按 pid 抓窗 → 杀自己记下的 pid（MM_DISK_SCAN 仅接受 /tmp 夹具）
MM_OPEN_TAB=list MM_DISK_SCAN=/tmp/mmdisk-fixture/root /path/to/MacMaster.app/Contents/MacOS/MacMaster &
APP_PID=$!
WIN=$(swift Scripts/window-ids.swift --pid "$APP_PID")
screencapture -o -x -l"$WIN" /tmp/mmshot/disk-list.png
kill "$APP_PID"   # 只 kill 自己记下的 pid
```

> 注意：上面的 `swift build`/`make-app.sh` 产物路径与隔离参数（`-o`/`-s` + `--scratch-path`）是
> 按 README §5 红线写的**约定骨架**，具体入口以仓库 `Package.swift`/`make-app.sh` 实际参数为准；
> 本环境无运行实例，未实际执行。

## 提请协调者

1. **`MM_DISK_SCAN` / `MM_DISK_SELECT` 越界红线的修复归属**（对应 I1，高）——**已落地，本条撤下（P20 现读）**
   本模块当时是唯一破了"扫描类钩子只认 /tmp"红线的地方（改前那两条锚点指到扫描入口与选中钩子，
   都没有前缀校验）。按硬约束 #4「优先提请协调者」，当时请协调者确认：是否在 `MMDisk/Sources` 内照
   `GuardianFixtureHooks.swift` 口径补 `/tmp` 守卫（越界写 stderr 并 `return`）。
   **现在的实现正是这个口径**：`MMDisk.swift:175-180` 与 `MMDisk.swift:1086-1094`，
   且两处的拒绝文案都被 `Scripts/p18-hook-typo-proof.sh` 的负向档实拍钉住（`hook-typo-audit.md` §5
   把 `MM_DISK_SCAN` 归在 A 类"改前就会说话"，说的就是这一条已经会自己开口）。
   **本审计当时未改此代码**，等协调者拍板——这一句保留原文，因为它是"提请协调者"这一类条目的样板：
   条目不会自动消失，得有人回来划掉。
2. **04 稿 artboard 补全的统筹**（对应 S1/S2/S3，中）
   列表视图、大文件列表、确认删除 sheet、撤回 toast、扫描中、空态、过滤态、值得看一眼面板、大文件分段——
   共需新增约 9 个 artboard。建议由设计稿 owner 统一补，避免各模块自行脑补。
3. **侧栏 footer 全站组件**（对应 S5，中，沿用 monitor S1）
   属 shell 共享层（tokens/screen.css + `Sources/MacMaster`），非 mmdisk 可改；请协调者统筹八张稿一起换。〔**P38f 现读：这件统筹已经发生过了，只是没人来记账**——组件在 `tokens.css:287`、`0c61fbf` 一次换了十张稿（04 在其中）。本条提请作废，但**磁盘这一路自己新开一处**：`04b`/`04e` 两块侧栏没画 footer，补画要重渲染这两页 png，见 `release-readiness.md` §7.35。〔**P39 已补画并重渲染**，这一处清了，见 §7.36。〕
4. **`MM_DISK_HOLD=hold` 首帧冻结钩子**（对应 §4 #5）
   当前无"扫描中首帧"冻结钩子，请协调者决定是否照 `GuardianLoadHook` 补一个，以便截图扫描中态。
5. **/tmp 夹具树的提供**（对应 §4 #13）
   真实扫描数字与 treemap 像素几何的验证依赖一份 /tmp 下的代表性夹具目录树；请协调者或测试侧提供，
   切勿指向真实用户目录（硬约束 #6）。
6. **`DeletionGuard` 与 mmdisk 标记的衔接复核**（参考 `deletion-guard.md`）
   实现 `DiskRemoval.plan`(`DiskRemoval.swift:71`) 自有一套 `systemFirstComponents`/`isVolumeRoot` 裁决，
   与 `MMCore/DeletionGuard`（全站唯一删除出口）是**两套清单**。删除最终走 `FileTrashService.shared.moveToTrash`(:1129)，
   由 `DeletionGuard` 在出口再拦一道。请协调者确认这两层是否口径重复/冲突——本审计只核对了 04 稿↔实现的视觉与文案还原，
   未深究双层闸门的语义一致性。

---
> 硬约束自检：未执行任何 git 操作；未启动 App、未截图、未合成事件；未编辑 `tokens.css`/`screen.css`/`icons.js`/`render.sh`/`Packages/MMUI`/`Packages/MMCore`/`Sources/MacMaster`；仅新建 `docs/analysis/fidelity-disk.md`。所有像素项标 `⚠️待真机测量`，未编造数字。`MM_DISK_SCAN` 越界问题只记录、未修改，已列入「提请协调者」。

## 7. P4 追加（2026-10-01，主代理实机轮）

上面这份审计是纯静态对照（未起 App、未截图）。本轮补齐了两件它做不到的事：

1. **§4 #13 / 提请协调者 #5 的 /tmp 夹具已落地**：`Scripts/disk-fixture.sh` 造
   `/tmp/macmaster-disk-fixture`（175 MB，含 40 个小文件与一块 101 MB 的 `Library/`）。
   截图命令：
   ```zsh
   MM_DISK_SCAN=/tmp/macmaster-disk-fixture ./Scripts/p4-sweep.sh \
     /tmp/mmapp-p5/MacMaster.app /tmp/p4-disk light "" disk
   ```
   证据：`docs/verification/p4-light-dark/light-disk-fixture.jpg`。

2. **夹具当场暴露一个口径黑洞（已修）**：`du -sh` 报 175 MB，页面报 77.8 MB。
   差的 101 MB 全在 `Library/` —— `DiskScanner.protectedNames` 会**整目录跳过**它，
   而页面上没有任何地方说"这块没算"。用户看到的就是"Library 是空的"，
   而事实是"Library 我们没看"。
   修法：`ScanOutput.skippedProtected` 把被挡掉的根目录子项带出来
   （`skippedProtectedNames(rootPath:)` 只列一层，不递归），
   面包屑条挂 `🔒 未纳入 N 个受保护目录` 徽标，hover 列名字。
   判据：`DiskScannerHierarchyTests.testProtectedDirectorySkipIsReported` /
   `testNothingSkippedLeavesEmptyDisclosure`。
   **P22 把这一处口径改宽了**：那句"只列一层，不递归"当时是真的，也当时就是错的——
   扫描的跳过判定在**每一层**都做，披露却只数根目录那一层，于是 N 少报。
   现在 `skippedProtected` 是"整棵树里每一处跳过的目录，路径相对被扫的根"，
   `skippedProtectedNames(rootPath:)` 已删，记账换成 `ProtectedSkipLedger`（见 §13）。
   **没改扫描语义**：跳过 `Library` 是既定行为，删除安全另有 `DiskRemoval` + `DeletionGuard` 两道闸
   （见 `deletion-guard.md`、提请协调者 #6），这里补的只是可见性。

   披露文案为什么放徽标而不是页头副标题：`MMPageHeader` 的 subtitle 是
   `lineLimit(1) + truncationMode(.middle)`，磁盘页右侧控件多，~1100pt 宽度下副标题本来就会被吃掉一段
   （实测被吃掉的是"N 个文件"）。再往里塞一句，被挤没的就是占用和用时。
   前后两张图都在 `docs/verification/p4-light-dark/`：
   `light-disk-fixture-subtitle-before.jpg`（塞在副标题里，占用/用时被截）与
   `light-disk-fixture.jpg`（改挂徽标，副标题恢复）。

浅色档其余色面（卡片/次级/页面底）的实测与判定统一记在 `fidelity-light-dark.md` §2。

## 8. P5 追加（2026-10-01）：两块删除确认面板与回执

补上 §提请协调者 #2 里"确认删除 sheet + 撤回 toast"那格里长期只有文字、没有画的一块，
并顺带纠正一处**说错话的 UI**（不是像素偏差，是事实偏差）。

设计稿：`docs/design-system/screens/mmdisk/04b-disk-confirm.html`（三栏 artboard：
04b 回收面板 / 04c 永久删除面板 + "默认态（未勾选）"附卡 / 04d 两条回执吐司并排，
注释里点名对应的实现符号）· 渲染 `04b-disk-confirm.png`（1200×2130；先按 1000×1300
渲会把第二栏裁掉，加 04d 后 2620 又留一屏白边）。

实机截图（浅色档，无合成点击）在 `docs/verification/p5-disk-permanent/`：

| 文件 | 拍到什么 | 判定 |
|---|---|---|
| `trash.jpg` | 回收面板：`回收 58.7 MB · 清空废纸篓后卷可用 6.86 GB → 6.91 GB`、Downloads 50.3 MB / Movies 8.4 MB 两行、一行 blocked、底部 `这些项改为永久删除…` 链接；面包屑**只剩** `卷可用 X` | ✅ 与 04b 第一栏一致；箭头徽章按实测口径撤掉了 |
| `perm.jpg` | 永久删除面板：红色标题、`这一步当场生效：卷可用 6.89 GB → 6.95 GB`、不可恢复警示、未勾选的确认框、灰掉的 `永久删除 58.7 MB` | ✅ 按钮在未勾选时确实点不动 |
| `perm-acked.jpg` | 同一块面板勾上以后按钮变红亮 | ✅ 单次会话内 consent，重开归零 |
| `toast.jpg` | 回执吐司：橙色三角 + `已永久删除 50.3 MB`、`共 1 项 · 无法恢复`、倒计时 `7s`、**没有**撤回按钮 | ✅ 与 04d 右条一致；左条（绿勾 + 撤回）是同一组件传了 `onUndo` 的样子，`trash.jpg` 之后的真实那一拍没单独拍 |

截图命令（`SEL` 的顺序是踩出来的，见 `hook-ledger.md` §5 末）：

```zsh
SEL="/tmp/macmaster-disk-fixture/Downloads,/tmp/macmaster-disk-fixture/Movies,/tmp/macmaster-disk-fixture"
./Scripts/p4-sweep.sh /tmp/mm-p5-app/MacMaster.app /tmp/p5-sheet/trash light "" disk \
  "MM_DISK_SCAN=/tmp/macmaster-disk-fixture MM_DISK_SELECT=$SEL MM_SHOW_CONFIRM=1"
# perm / perm-acked 追加 MM_SHOW_PERMANENT=1|acked；toast 用 MM_SHOW_TOAST=permanent
```

未拍到的两态与原因：`.guarded` blocked 行（钩子进不去 `DeletionGuard` 的保护清单，
只有单测覆盖）、按下红色按钮之后的界面（禁止合成点击）。都记在
`hook-ledger.md` §3，不当 bug。

## 9. P6.2a 追加（2026-10-03）：标记跨重扫存续（04e）

补掉 `disktree-adoption.md` 末尾那条"仍然推迟的一项"：**重扫不再清空标记**。
改动前 `scan(rootPath:)` 落地时执行 `self.marked = [:]`，也就是「选择目录」重扫一次，
用户在图上 ⌘ 点出来的那串标记全没；而工具栏那颗「重新扫描」走的是另一条路
（`doNavigate`，只重枚举当前层），它**从来不清标记**——于是同一屏上"重扫"有两种后果，
其中一种还留着旧快照的字节。

### 9.1 两条口径，各自守各的失败模式

| 场景 | 走哪个函数 | 命中的标记 | 没命中的标记 |
|---|---|---|---|
| 整根重扫（首次扫描、`选择目录`、`MM_DISK_RESCAN`） | `DiskMarks.reattach(_:rootPath:into:)` | 换成新扫描那份节点（体积跟着新扫描走） | **丢弃**，并在面包屑上点名丢了几条 |
| 单层重新枚举（工具栏「重新扫描」、下钻未缓存的目录） | `DiskMarks.refresh(_:with:under:)` | 同上 | **scope 之外的原样留着** |

分开的理由写在这条规则上：**没扫到 ≠ 不存在**。单层重新枚举只看得见当前这一层底下的东西，
它没有资格判兄弟目录上那条标记的生死；只有整根重扫说得出"这棵树里没有它"。
两个函数都不判扫描根自己——树里存的是根的孩子，根这一层没被这次枚举观察到
（`testReattachKeepsAMarkOnTheScannedRootItself` / `testRefreshKeepsAMarkOnTheEnumeratedDirectoryItself`
把这条钉住）。

反过来，只保路径不换数字也不行：那底部「已标记 N 项 · X」就成了两个时间点之和，
正是 `disktree-adoption.md` 当初推迟这一条时点名的风险。所以命中即换节点，
数字一律以新扫描为准。

### 9.2 逐元素对照（04e ↔ 实机）

设计稿：`docs/design-system/screens/mmdisk/04e-disk-rescan.html`（两栏：① 同根重扫后标记还在
② 换根重扫后丢弃并点名）· 渲染 `04e-disk-rescan.png`（1200×1640）。
实机三张在 `docs/verification/p62-marks/`，命令 `./Scripts/p62-capture.sh <app> <目录> light`。

| 元素 | 稿 | 实机 | 判定 |
|---|---|---|---|
| ① 同根重扫后的面包屑 | `已标记 2 项 · 67.1 MB` | `02-marks-after-rescan.png` 同一条，67.1 MB | ✅ 改动前这一张会是"无标记" |
| ① 确认面板清单 | （04e 不画面板，画的是主窗） | 同一张里 sheet 列 `Downloads 50.3 MB` + `report-2026.pdf 16.8 MB` | ✅ 两条都挂回来了 |
| ① 图上 ✓ 角标 | Downloads / Documents 两块右下角 | ② 那张两块右下角各一个圆勾；① 因为钩子下钻进了 Documents，图上只有 `report-2026.pdf` 这一块带勾 | ✅ |
| ② 换根后保留的那条 | `已标记 1 项 · 16.8 MB` | `03-marks-after-root-switch.png` 同一条 | ✅ 体积取自新扫描 |
| ② 丢弃徽章 | `⚠ 重扫后 1 个标记已经不在了 · 已移除` | 同一张，橙色，位置一致 | ✅ tooltip 里逐条列路径 |
| ② 待删总量随之变小 | 67.1 → 16.8 MB | 面板与底部条都只算 16.8 MB | ✅ 少掉的 50.3 MB 是"这次没扫到"，不是"它不存在" |
| ② 受保护目录徽章消失 | 第二栏不画 `未纳入 1 个受保护目录` | 换根到 Documents 后确实没有这条 | ✅ 新根里没有受保护条目 |

夹具沿用磁盘页一直在用的 `Scripts/disk-fixture.sh`（本次不新增夹具），
两条标记刻意分在 `Documents/report-2026.pdf` 与 `Downloads` 两个顶层目录，
③ 换根重扫时正好一条挂得回去、一条挂不回去。

### 9.3 拍不到的，逐条写明

1. **"体积以新扫描为准"这一拍需要两次扫描之间磁盘真的变了**。钩子做不到（应用自己不写文件），
   所以照片上 ① 和 ② 的数字一样。这条只有单测钉住：
   `testReattachKeepsMarksAndReplacesTheirSizeWithTheNewScan`（100→40、200→900）。
2. **「重新扫描」按钮那条 `refresh` 路径需要真点击**（禁止合成点击），照片里没有。
   覆盖它的还是单测：`testRefreshDropsOnlyWithinTheEnumeratedLevelAndKeepsSiblings`
   ——一条 scope 内消失的丢弃、一条 scope 内还在的换新、一条兄弟目录上的原样留着。
   ~~以及一条"深一层的标记"~~ 当时**没有**这一条，而 P6.7 恰恰是补上它之后查出一个真 bug（见 §10）。
3. **纯前缀与按组件比较在界面上看不出区别**：原来由 `testIsUnderComparesWholePathComponents` 钉。
   P6.7 之后 `isUnder` 没有生产调用点、已删，同一条判据挪到 `isDirectChild` 上
   （`testIsDirectChildComparesWholePathComponents`，含"`/u/dev/ab/x` 不算 `/u/dev/a` 的孩子"）。

### 9.4 顺带改的一处钩子行为

`MM_DISK_SELECT` 过去每次扫描落地都重放。新增 `MM_DISK_RESCAN` 之后这会**把该丢弃的标记重新
加回来**，取证就看不出丢弃那条分支，于是它改成只重放一次（`selectionHookApplied`）——
它代表的是"用户动手标记过一次"这个动作，而不是一个常驻状态。
既有单档取证（`p4-sweep.sh … disk` 那一类）都只扫一次，行为不变。


## 10. P6.7 追加（2026-10-04）：`refresh` 的"只在单层判生死"当年没兑现

`DiskMarks.refresh` 自己的注释写着**「scope 之外的原样留着——没在这一层扫到 ≠ 不存在」**，
§9.1 也把这句话当作两条口径的分工依据。P6.7 的夹具审计照着它查代码，发现它只兑现了一半：

```swift
guard path != scope, isUnder(path, scope) else { marks[path] = old; continue }
if let fresh = find(path: path, in: items) { … } else { dropped.append(path) }
```

`isUnder` 是**任意深度**的包含判断，而 `find` 递归找的是 `items` 那几棵子树——
问题在于 `items` 来自 `DiskScanner.childrenOfDirectory`（`doNavigate` 在 `MMDisk.swift:1403`，
取孩子在 `:1401`，**只取一层**），拿到的孩子**不带孙子**。于是挂在 `scope` 下两层的标记既找不到也无处递归，
被丢进 `dropped`，UI 上据此画出「重扫后 N 个标记已经不在了 · 已移除」（`MMDisk.swift:374`）。

**这不是取证缺陷，是用户可达的假话**，路径很日常：
在 `Documents` 里标记一个文件 → 回到上一层 → 按「重新扫描」。
那 16.8 MB 没消失，它只是这次没被观察到。

### 10.1 先红后绿

补在 `testRefreshDropsOnlyWithinTheEnumeratedLevelAndKeepsSiblings` 之后：

```
testRefreshKeepsMarksDeeperThanTheEnumeratedLevel
  error: ("[\"/u/dev/a/b/c\"]") is not equal to ("[]")
  error: ("nil") is not equal to ("Optional(700)")
```

修法把"这一层观察到了什么"写成一条判据而不是靠递归碰运气：
`refresh` 现在只对 `isDirectChild(path, of: scope)` 成立的那批换体积 / 判生死，
其余（scope 本身、更深的一层、scope 外的兄弟）一律原样留着。
`isUnder` 随失去生产调用点而删除，同一条"按组件比较、同前缀不算"的判据挪到
`isDirectChild` 上（`testIsDirectChildComparesWholePathComponents`）。
`Packages/MMDisk` 全量 **62 tests / 0 failures / 1 skipped**（2026-10-04 现跑）。

### 10.2 一条刻意保留的口径不对称

更深那层的标记**留着旧体积**，与文件头"体积一律换成新扫描那一份"相反。这是两害相权：

| 做法 | 底部「已标记 N 项 · X」 | 面包屑上那句 |
| --- | --- | --- |
| 丢弃并点名 | 少了一项（用户以为清单缩了） | **"已经不在了"——假话** |
| 原样留着（现在） | 掺一个"上次量的"字节 | 不说 |

选后者的理由和 §9.1 是同一条：**"它没了"只有整根重扫（`reattach`）说得起**，
单层枚举说这句话就是撒谎；而旧体积至少还是"上一次真量到的数"，
它错在时效，不错在事实。`reattach` 那条路（整根重扫、换根）保持原样——新树是全的，
找得到就该点名找不到。

### 10.3 这一轮在取证侧改的（同一批审计带出来的）

- `MM_DISK_SELECT` / `MM_SHOW_CONFIRM` / `MM_SHOW_TOAST` / `MM_SHOW_PERMANENT` **每个生效分支各留一行日志**，
  带可核对的数：选中项的 `MMFormat.bytes`、面板里的 `marked.count`、吐司借来的那一项体积。
  动因是 P6.6 那条教训的反面——**只写失败日志的钩子，成功时在日志里和"压根没跑"同样安静**。
  2026-10-04 手工起实例跑过一轮，四行为：
  `已选中 /tmp/macmaster-disk-fixture/Documents/report-2026.pdf（16.8 MB）`、
  `已打开确认面板（2 个标记）`、`MM_SHOW_PERMANENT=acked …（勾选项 已打）`、
  `MM_SHOW_TOAST 已画出「移入废纸篓」回执条（1 项 · 16.8 MB）`。
- `p4-sweep.sh` 那行"钩子凭据"原来只 `grep` 四类钩子名（`MM_APPEARANCE|MM_WINDOW_SIZE|MM_DISK|MM_SHOW`），
  现在收全部 `MM_` 开头的行加夹具哨兵词——旧写法下磁盘页以外的钩子即便真生效，这行也是空的。
- **§10 这条缺陷仍然没有照片**：兑现它需要"回到上一层再按重新扫描"，那是真点击，
  禁止合成点击，而磁盘页没有"导航到某个祖先目录"的钩子。为一张照片加一条新钩子
  （`MM_DISK_NAVIGATE`）本轮没做——`MM_DISK_RESCAN` 走的是整根 `reattach`，覆盖不到 `refresh`。
  所以判据停在 §10.1 那两条断言上，写在这里免得下轮以为照片里有。

## 11. P6.8c 追加（2026-10-05）：§8 那四张手工照片变成可重跑脚本

§8 末尾留的是一段**手写命令**（`p4-sweep.sh` 加一串 `MM_*`），仓库里没有任何脚本会再拍一遍那四张。
本轮补 `Scripts/p68-disk-capture.sh`，照片写到新目录 `docs/verification/p68-disk/`
（4 张 png + 4 份同名 log），**`docs/verification/p5-disk-permanent/` 一字未动**。
本轮**不改源码、不新增钩子**，风格与 `p68-{dev,brew,trash}-capture.sh` 一致（`ONLY=` 重拍单档、
每份 log 开头两行归因头、只 kill 自己起的 pid、拿不到窗口 id 就报错不出空照片）。

### 11.1 怎么跑

```sh
./Scripts/make-app.sh -o /tmp/mm-app-p68disk -s /tmp/mm-scratch-p68disk
./Scripts/p68-disk-capture.sh /tmp/mm-app-p68disk/MacMaster.app docs/verification/p68-disk light
# 只重拍回执条：KEEP_FIXTURE=1 ONLY=04 ./Scripts/p68-disk-capture.sh …
```

夹具默认每次重建（`Scripts/disk-fixture.sh` 开头就 `rm -rf`，幂等）；`KEEP_FIXTURE=1` 跳过重建。
`SEL` 的顺序仍是**根写在最后**——`MM_DISK_SELECT` 按逗号逐个往下钻，把扫描根写在第一个会一路选到
`/tmp`、`selected` 变 nil，04 那档的吐司支路整条哑掉（`hook-ledger.md` §5 末那条老教训，脚本里也写了）。

### 11.2 逐档哨兵（判据是日志里那行带数的回执 + 画面上的同一个数）

| 档 | 钩子 | 日志那行可核对的断言 | 画面上必须对上的 |
|---|---|---|---|
| 01 `trash-confirm` | `MM_DISK_SCAN` + `MM_DISK_SELECT=$SEL` + `MM_SHOW_CONFIRM=1` | `MM_DISK_SELECT 已选中 …/Downloads（50.3 MB）`、`MM_SHOW_CONFIRM 已打开确认面板（3 个标记）` | 面板标题「把 **2** 项移入废纸篓？」+ 三行（Downloads 50.3 / Movies 8.4 / `macmaster-disk-fixture` 标「就是正在扫描的目录本身」）+ 底部「已标记 **2** 项 · 58.7 MB · 1 项不能删」 |
| 02 `perm-unacked` | 同上 + `MM_SHOW_PERMANENT=1` | `…（勾选项 **未打**），没有改动任何文件` | 红色永久删除面板、同意框空、按钮灰 |
| 03 `perm-acked` | 同上，`MM_SHOW_PERMANENT=acked` | `…（勾选项 **已打**）…` | 同一块面板按钮变红亮 |
| 04 `toast-permanent` | `SCAN` + `SELECT=$SEL` + `MM_SHOW_TOAST=permanent`（**不带** CONFIRM） | `MM_SHOW_TOAST=permanent 已画出「已永久删除」回执条（1 项 · 50.3 MB），没有删除任何东西` | 橙三角 + `已永久删除 50.3 MB · 共 1 项 · 无法恢复` + 倒计时、**没有撤回按钮**；右侧详情是「标记」而不是「取消标记」（这一档确实没打标记） |

`已选中 …（50.3 MB）` 与面板里 Downloads 那一行的 50.3 MB 是同一个数——**日志与照片交叉核对**，
不是各说各话。夹具大小固定（`Downloads/dmg-image.dmg` 48 MiB → 十进制 50.3 MB），
所以这一族照片的数字是可预期的；哨兵另有其一：真机上不存在
`/tmp/macmaster-disk-fixture/Downloads/dmg-image.dmg` 这条路径。

### 11.3 与旧照片不一致 / 本轮新学到的（如实记）

1. **「3 个标记」与「把 2 项移入废纸篓」不是矛盾，是同一件事的两个口径**：`marked.count` 含扫描根
   那一条，而裁决阶段把它拦下来（它就是正在扫的那层），所以面板列 3 行、可删 2 项。
   旧 §8 只写了"两行 + 一行 blocked"，没把这三位数字的关系说穿；脚本注释里那句
   "面板里应当正好有这么多行"指的是**行数**等于 `marked.count`，别读成"可删项数"。
2. **04 那一档的 `SETTLE` 不能沿用通用的 10 秒**：回执条自带 10 秒倒计时（`permanentSeconds = 10`，
   每秒减一），第一次实跑按 10 秒等，拍到的是**「1s」**——差一秒就什么都没有了。
   现在 04 单独用 `TOAST_SETTLE`（默认 5 秒），实跑拍到 **6s**，与旧照片那张的 7s 同一量级。
   这是"迭代次数≠秒数"之外另一类坑：**画面里的元素自己会走时间**。
3. **页头是 `77.8 MB · 44 个文件` 而不是夹具的 175 MB**：`Library/` 那一档被扫描层跳过
   （`disk-fixture.sh` 头注释记过），旧照片同样如此，不是回归。
4. **卷可用数字每次不同**（本轮 43.68 / 43.73 GB，旧照片 6.86 GB）：读的是真卷，属真机态。

### 11.4 依旧拍不到的（点名，别以为脚本扩了四档就都齐了）

- **「移入废纸篓」那条绿色撤回回执**（§8 表格末句"左条…真实那一拍没单独拍"）现在**仍然拍不到**，
  而且原因这轮才查清：画它的分支在 `applySelectionHook` 里排在
  `guard env["MM_SHOW_CONFIRM"] != nil else { return }` **之后**（`MMDisk.swift:1133` → `:1168`），
  也就是说要触发它就必须开确认面板，而面板是 `.sheet`（`:120`），会把吐司整个盖住。
  零点击到不了这一态，除非给它单开一条钩子——本轮不新增钩子，所以四档里没有它。
- `.guarded` blocked 行、按下红色按钮之后的界面：与 §8 末尾所记相同，前者钩子进不去
  `DeletionGuard` 的保护清单（只有单测），后者要合成点击。
- §10.3 末条那句"这条缺陷仍然没有照片"**原样成立**：`refresh` 的跨层留痕要"回到上一层再重新扫描"，
  磁盘页没有导航到祖先目录的钩子，`MM_DISK_RESCAN` 走的是整根 `reattach`，覆盖不到。

实跑核对：`ps -eo pid,command | grep "MacMaster.app/Contents/MacOS"` 本轮跑完为空
（注意 grep 无匹配时退出码非 0，别把它接在 `&&` 后面当断言）。

## 12. P8 追加（2026-10-05）：详情第四格的三种态，与一棵 20 层的树

I4 收口那一轮（§2 第 4 条 ✅）留下的不是一句"改回子项就完了"，而是把那一格的**三种态**
一次分开：不是目录、量过的目录（含"确实为空"那个真 0）、**根本没枚举过的目录**。
以前第三种显示成 0。这一节记的是取证本身。

### 12.1 为什么必须新造一棵树

`descendantsMeasured: false` 只由 `if depth >= maxDepth`（`MMDisk.swift:1947`）那一支写下，
而 `maxDepth = 20`（`MMDisk.swift:1779`）。既有夹具 `disk-fixture.sh` 最深两三层，**永远走不到那一步**——
所以这一档此前不是"没拍"，是**没有任何夹具能拍到**。新夹具
`Scripts/disk-depth-fixture.sh` 造的是一棵 20 层窄树（每层一个 64k 实心文件 + 一个子目录），
层数按扫描器口径推：`scanChildren(path: 根, depth: 0)` 枚举根的子女，扫 `根/L01…L0k` 时 depth = k，
所以 k = 20 那一层（即 L20 的子女）里的目录被封顶 → **L21 就是要拍的那个节点**，
底下再挂 L22/L23 各 1 MB，让 `deepSize(remainingDepth: 3)` 量得到字节。
于是画面上是"占用有数、子项没枚举"这一对，而不是两格都空——后者拍不出这一档的价值。

### 12.2 实跑读数（`docs/verification/p8-disk-depth/`，三档零点击）

| 档 | 选中 | 占用 | 实际占比 | 子项 | 日志里的钩子凭据 |
| --- | --- | --- | --- | --- | --- |
| 01-capped-node | `…/L20/L21` | 2.2 MB | 62.3% | **未枚举** | `MM_DISK_SELECT 已选中 …（2.2 MB）` |
| 02-measured-dir | `…/L01` | 3.5 MB | 100.0% | **2** | 同上（3.5 MB） |
| 03-file-node | `…/L01/marker.bin` | 66 KB | 1.9% | **—** | 同上（66 KB） |

三处交叉核对：① 01 的「占用 2.2 MB」与日志那行逐字相同，而 2.2 MB ≈ 64k + 1m + 1m，
说明字节确实由 `deepSize` 兜到了、**只有名字没枚举**；② 02 的「子项 2」与同一张图下面
「内部构成」那两行（L02 3.4 MB、marker.bin 66 KB）**行数一致**，这一格从此能自证口径；
③ 02 的 3.5 MB = 19×64k + 2.2 MB，与 01 的封顶体积互相咬合（L01 往下的求和把 L21 当成 2.2 MB 计入）。

### 12.3 这一轮查清的两件事（都不是文案问题）

1. **01 档的 treemap 里 L21 底下是有内容的**，别读成"未枚举被推翻了"：`MM_DISK_SELECT` 会
   `openDirectory(父层)`，父层没缓存时起 `doNavigate` **重新枚举那一层**（`:1411-1436`），
   重枚举从 depth 0 重新起算，所以 L21 在这一层视图里是正常节点；而右侧详情读的是
   **原扫描树**里那个封顶节点（`node(atPath:)` 走 `scanStore.currentChildren` 递归查找）。
   两者不是同一个节点对象，各自都诚实——"这一层没枚举过"说的是原树那趟遍历的账。
2. **窗口尺寸要脚本自己写死**：App 会恢复上次退出的 frame，第一次实跑恢复到 1000x652pt，
   详情面板被挤到窗口边缘，照片看着像"那一格没了"。现在 `SIZE=1400x900`（`MM_WINDOW_SIZE`）。
   顺带一个 zsh 陷阱记在夹具脚本头注释里：累加路径的变量**不能叫 `path`**——它与 `PATH` 绑定，
   一赋值 `seq`/`mkdir` 全 command not found（第一次实跑就是这么挂的）。

### 12.4 回归网

`Packages/MMDisk/Tests/MMDiskTests/DiskInspectorTextTests.swift` 四档各一条：文件→「—」、
量到的目录→`MMFormat.count(n)`、**量到且确实为空→真 0**（不许被"未枚举"吞掉）、
封顶→「未枚举」且字符串里**不许含 "0"**。MMDisk 包 66 个测试全绿（1 个跳过仍是
"本机没有第二块挂载卷"那条），全仓 `./Scripts/run-all-tests.sh` = **571 个测试 / 0 失败 / 1 跳过**。

### 12.5 顺带记一笔：这份文档里的行号引用在漂移

本轮为了核对第四格把 `MMDisk.swift` 通读了一遍，顺手发现**§0 和 §1 那两张表里的行号是写稿当时的快照**，
后来代码往下长，引用没跟着动。现在（2026-10-05）实测：

| 出处 | 写的 | 现在 |
| --- | --- | --- |
| §0 可用钩子表 | `MM_DISK_DEPTH` `:128` | `:159` |
| §0 可用钩子表 | `MM_DISK_FILTER` `:132` | `:163` |
| §0 可用钩子表 | `MM_DISK_SCAN` `:135` | `:179`（同一条的 /tmp 拦截回执在 `:184`） |
| §0 可用钩子表 | `MM_DISK_SELECT` `:996` / `MM_SHOW_CONFIRM` `:1009` / `MM_SHOW_TOAST` `:1025` | `:1094` / `:1141` / `:1129` |
| §1.4 | `readEntries` `:1585-1626` | `:1893` 起 |
| §1.5 | `legend` `:468-513`、说明 `:499-501` | `legend(filtered:)` `:556` 起，两句说明 `:587-589`（本轮已改） |

**判据**：§2 往后每一节的复核（`✅ 已落地（commit）` / `❌ 仍未做（复核 日期）`）带的是**复核当时的行号**，
那一部分是可信的；§0/§1 是首轮快照，**别拿它当"现在去哪一行"**。

**下一轮改稿时的处理**：这些引用一律换成**符号名**（`readEntries` / `legend(filtered:)` / `doNavigate` /
钩子名本身），行号只在"这一处只有行号能定位"时保留，并且跟着写"现 `:NNNN`"标明它是快照值。
理由就是本仓库自己那条建议——按符号名找，别按行号找。

## 13. P22 追加（2026-10-06）：徽章那句"未纳入 N 个"数的是整棵树，不再只是根目录

§5 第 2 条那次补的披露有一个当时没看见的形状：扫描的跳过判定按名字做在**每一层**
（`scanChildren` 与 `deepSize` 各有一处 `protectedNames.contains(entry.name)`），
而披露走的是 `skippedProtectedNames(rootPath:)`——**只列根目录的直接子项**。
两处读的是同一份名单，数的范围却不一样，于是 N 是少报的。

真机上最先撞上的是 `~/Pictures/Photos Library.photoslibrary`：它在第二层，
扫描整目录跳过、一个字节都不算，徽章却一个都不提。画面上 `Pictures` 那一块
根本不出现（0 体积不进 treemap：子层那一档由 `rawChildItems` 的 `.filter { $0.size > 0 }` 挡下，
顶层这一格本轮没单独查它走的是哪一行），于是它就被读成"这里真的是空的"，
而 §5 那次修的正是这一类读法——修得不完全。

**改法**：删掉 `skippedProtectedNames(rootPath:)`，换成 `ProtectedSkipLedger`
（`MMDisk.swift`，与 `HardlinkLedger` 同一条理由用 `NSLock`：记跳过在同步枚举里，
而顶层往下有三层并发），跟着遍历一路记到 `deepSize` 那一支（深度截断档同样是"整目录没看"）。
`skippedProtected` 的形态从"名字"换成"**相对被扫根**的路径"——两处同名跳过
（`Library` 和 `Documents/Work/Library`）只给名字就分不出是谁。
根目录那一层退化成名字本身，所以旧的那条判据 `XCTAssertEqual(output.skippedProtected, ["Library"])` 不用改。
浮层文案加了一道截断（`skippedDisclosure(_:)`，前 8 处 + "等 N 处"）：整盘扫描时
`/System/…/Library` 这类能到几十上百处，全列出没人读，但**数字始终是完整的**。

**判据**：`DiskScannerHierarchyTests.testNestedProtectedSkipIsDisclosed`——
夹具在第二层放 `Pictures/Photos Library.photoslibrary`、第三层放 `dir0/dir1/Library`，
断言两处的相对路径都在、且被跳过的那块字节不进父目录面积（`Pictures.size == 0`）。
**先跑过一遍失败**：改代码之前它报的是 `("[]") is not equal to ("[Pictures/Photos Library.photoslibrary, dir0/dir1/Library]")`，
也就是"两处都不报"，而不是"少报一处"——这条失败信息本身就是这一轮的病根。

**取证**（`docs/verification/p22-disk-skip/`，`./Scripts/p22-disk-skip-capture.sh`，两档零点击）：
新夹具 `Scripts/disk-protected-fixture.sh` 把受保护目录放在第 1/2/3 层各一处。
`01-skip-badge` 扫夹具根 → 徽章 `未纳入 3 个受保护目录`；
`02-skip-subroot` 换根到 `…/Documents` → `未纳入 1 个受保护目录`（只有 `Work/Library`，
上一档那两处不在这棵树里，不该跟着换根跑过来）。
**为什么这一族要新夹具**：哨兵夹具 `disk-fixture.sh` 只在根目录放了一个 `Library`，
旧口径和新口径在它上面都报"未纳入 1 个"，照片逐像素一样——这一族的 bug 用哨兵夹具拍不出来。
反过来这也是它继续当哨兵的理由：本轮它的字节数、`已选中 …（50.3 MB）`、`确认面板（3 个标记）`
那些回执**一个字都没动**（被跳过的目录本来就不进统计），所以 p68-disk / p21-disk 两族旧照片仍然可比。

**照片证不到的两处，别当成证到了**：
① 浮层里那三条相对路径是原生 tooltip，不进截图——字符串形态的证据只有那条单测；
② "改之前报 1、改之后报 3"这一对比没有旧产物的同夹具照片，凭据是上面那条单测的失败输出。

**仍然开着的**：
- 下钻（`childrenOfDirectory`）这一趟**不写披露**（`skips: nil`）。理由写在调用点的注释里：
  全盘扫描走过同一棵子树时已经把每一处记进去了，下钻再记一遍会把同一处数成两处。
  但"重新扫描之后树上多了新的受保护目录"这一档确实不进 N，本轮没改。
- `protectedNames` 里 `.Trash` / `.Spotlight-V100` / `.fseventsd` / `.TemporaryItems` / `.PKISyncStore`
  这五条**永远匹配不上**：`readEntries` 在更早的地方就把 `.` 开头的名字整条跳过（同一个函数里，
  本轮现读 `:1914`，快照值）。它们实际是被"隐藏文件"那条规则挡掉的，不是被这份名单挡掉的——
  结果一样（都不进统计），但"名单里有它"这句话对这几项起不了任何作用，
  而徽章的浮层也就永远不会列出它们。
- 真机用户目录（受保护项不止 `Library` 一个）下这枚徽章的宽度、窄窗溢出：仍未测。
  §2 I11 那一条在 P6.6 量过的是**夹具根**（面包屑里一枚「卷可用 …」药丸），
  而本轮之后同一栏可能同时挂「未纳入 30 处 …」这种长浮层入口——**徽章变多宽会不会把面包屑挤出去，
  现在没有任何一张照片知道**（夹具最多 3 处）。

## 14. P23 追加（2026-10-06）：同一族照片重拍，但新事实全在日志头里

磁盘页本轮**没有任何界面改动**（P23 一行 Swift 都没动），这一节记的是"那为什么还重拍两档"。

`docs/verification/p23-disk-skip/`（同一支 `./Scripts/p22-disk-skip-capture.sh`，同一份夹具，两档零点击）
是 §13 那两档的**重拍**。两张照片与 P22 那两张逐格对读，**只动了两处，而且两处都不是这轮的改动**：

| 画面那一格 | P22（`p22-disk-skip/`） | P23（`p23-disk-skip/`） | 归因 |
| --- | --- | --- | --- |
| 面包屑右侧「卷可用」 | 45.54 GB | **45.18 GB** | 这台机器在这两跑之间又写了 0.36 GB，与代码无关 |
| 侧栏「系统清理」 | 1.87 GB | **2.15 GB** | 同上，那一栏是真机测量值（无钩子顶替，见 `website-audit.md` 那一格） |
| 徽章 | `未纳入 3 个受保护目录` | 逐字相同 | §13 那条改动仍在 |
| 夹具四格（`75.5 MB · 3 个文件`、50.3 / 16.8 / 8.4 MB） | — | 逐字相同 | 夹具决定，不随真机变 |

**所以这一族照片的全部新事实是日志头那一行**（两份 `.log` 第三行，逐字）：

```
# digest: tree=df71638+e3b0c442 app=df71638+e3b0c442
```

它是 `release-readiness.md` §8 那条"照片与产物同源没有门禁"的还账：取证脚本现在**起跑前**比一遍编译输入的内容指纹，
不等就 exit 4、一张都不出（判据与五档否证在 `release-readiness.md` §7.14，
逐字日志 `docs/verification/p23-provenance/probe.log`）。
**对磁盘页这一族而言，这意味着"重拍的照片跑的就是当前这份源码"不再需要人声明**——
P22 那一轮靠的是三条 `stat` 现读出来的 mtime 排序，而那个形态在 `git clone` 之后必然失效。

**本轮没重拍的那一族**：`p22-disk/` 那四档（`p68-disk-capture.sh` 的删除面板回归）。
判据是"回执逐字相同"，而本轮没有编译输入变化 → 产物同一份 → 再拍一遍只会多四个目录、
不多一条证据。**这一格如果哪天被问"为什么 P23 没重跑 p68-disk"，答案就是这一句**。
它凭什么成立也能核：本轮 `git ls-files --others --exclude-standard -- Sources Packages Resources Package.swift`
现数 **0** 个未跟踪编译输入、`git diff HEAD` 对那 92 个输入**零输出**（所以指纹后半截是空输入流的哈希
`e3b0c442`），也就是"当前产物用的编译输入 == `df71638` 那一提交里的内容"。
**但别把它读成"P22 那四张照片与今天的产物指纹相同"**——P22 的产物早于 `MMSourceDigest` 这一键，
它没有指纹可比；可比的是"内容 == 那一次提交"，这一条是本轮的 `tree=` 值给的。

## 15. P26 追加（2026-10-07）：页头副标题收成三段合同，「扫描用时」出页头

判据、九屏逐屏实拍与两档修复过程都在 `docs/analysis/header-truncation-audit.md`（本轮主文档）。
这一节只记磁盘页自己那三笔账。

**① 这一屏是九屏里唯一一处"截断之后画面在说谎"**。页头副标题是
`lineLimit(1) + truncationMode(.middle)`，而这一屏的动作簇（Treemap/列表/大文件 + 筛选框 +
重新扫描 + 选择目录）是全站最宽的一档 → 1000 pt 硬最小宽度下**中段必掉**。
旧四字段的排法截出来是 `77.8 MB · 44…aster-disk-fixture`：`44` 的单位落在被吃掉的区间，
画面上是两个并排的光数。旧注释把这笔代价写成"文件数只剩个位数"，认得不够——**剩个位数不是问题，
丢了单位才是问题**。

**② 改法走了两档，第一档是错的**。只调段序（占用 · 路径 · 用时 · 文件数）之后实拍：
`77.8 MB · /tmp….1 s · 44 个文件`。单位活了，但"用时"被切成半句，真值 0.1 s 在画面上成了 1 s。
教训写成一句话留在源码注释里：**牺牲者不能是个数字**——中间截断不会整段删掉谁，
它只会把跨在边界上那一段切一半，而"切一半的数字"比"少一段"更糟。
于是页头只剩三段：`占用 · 路径 · N 个文件`（`MMDisk.swift:235-241` 取数、`:1585-1591` 定序；**P35b 现读重指**，§15 那一轮读的是 230-236 与 1555-1561），
实拍 `77.8 MB · /tmp…ture · 44 个文件` / `33.6 MB · /tmp…code · 1 个文件`，两头都是完整的话。

**③ 设计稿欠一次同步**：`docs/design-system/screens/mmdisk/04-disk.html:60` 与
`04b-disk-confirm.html:96` 的副标题样例都还写着"扫描用时"。归 **设计稿该改**（§1.2 已改判）。
顺带一笔：04 稿至今没有"最小窗口"这一档 artboard，页头在窄窗下该长什么样**稿内无处可查**——
这一条与 `fidelity-cleaner.md` §11.4 记的是同一件事（共享层"段数组 + 每段独立 Text + 优先级"
那条路），别在这里重复立案。

**回归网**：`Packages/MMDisk/Tests/MMDiskTests/DiskHeaderContractTests.swift` 四条
（尾=带单位的文件数、头=占用、整句恰好三段且不含秒数、千分位不许把单位挤散）。
它钉得住段序，钉不住"这一句在 1000 pt 放不放得下"——那只有照片，复现命令在本节 ② 引的那份文档 §7/§8。

**④ 本轮顺手撞到的一类账：表格里裸写的 `:NNN` 锚不在机器判据里**。
`Scripts/p16-citation-audit.sh:134` 那条正则要求**冒号前紧贴一个带扩展名的文件名**
（`MMDisk.swift:208-210` 它吃，`:208-210` 它一个都不吃）。**P35b 现读**：本轮重指时裸号那一半全被工具放过，
只能人工逐条补（见 §1 那一格）——这一句从"举个形式差异"变成了当期欠着的账。本表 §1.2 为了少占版面，
同一文件的后续行号全是裸写的——**于是这一类锚从头到尾没有被机器查过**。
本轮实测它的体量（自包含一条命令，冒号前不是文件名字符、冒号后是数字即计一处；
时间 `22:35`、比例 `1000:600`、URL 都不计）：

```
awk '{s=$0; while (match(s,/:[0-9]+(-[0-9]+)?/)) {p=(RSTART==1)?"":substr(s,RSTART-1,1);
     if (p !~ /[A-Za-z0-9_.\/+-]/) t++; s=substr(s,RSTART+1)} } END{print t+0}' \
    docs/analysis/fidelity-disk.md        # 现读 127（全仓最多的一页）
awk -f 同一份脚本 docs/analysis/*.md       # 现读 753（第二多的是 dev-artifact-walk-merge.md 124）
```

**这两个数在本段落下笔后又涨过一次、再还债之后回落**（本文 120→127，全仓 749→756→753）。
涨的是这一段自己裸写的那几条旧锚，回落的是把五条 P21 的裸括号改成带文件名的活坐标
（**裸改写全 = 这一类账从"没人查"变成"有人查"，所以裸数会掉**）。
一个"量锚点漂没漂"的数会被"记录它漂了"这个动作本身改变，所以它**必须在同一轮末尾重读一次**，
上面写的就是本轮最后一次重读的值。

漂了的是两处，而且**都还挂着 ✅**：§1.2 的筛选框那一格写 `:149-152`、按钮那一格写 `:155-160`/`:162-168`，
现读真实位置是 `:203-205`、`:209-214`、`:216-222`——**差 54 行**，差值正是 P26 自己在
`MMDisk.swift` 上加的那 18 行（页头取数 + 四条判据的钩子面）加上它上面那些行的累积位移。
已改。同一轮里审计**真抓到**的两处漂移是带文件名的
（`feature-roadmap.md` 第 955 行指磁盘页徽标那一处、`fidelity-monitor.md` 第 111 行指 80 pt 标签列那一处，
两条都已按现读重指），也就是说：**同一类漂移，写全文件名的有网，裸写的没网**。
这不是审计脚本的 bug，是它的判据边界，而这条边界此前没人量过。

**因此立一条规矩**：凡本轮改过某个源文件的行数，同一轮必须现读重查**指向该文件的裸锚**
（`grep -nE '[^A-Za-z0-9_.\/+-]:[0-9]+' docs/analysis/*.md` 按文件名筛），改不完就写进残余；
要么写全 `MMDisk.swift:208-210`，要么不写行号。**把裸锚收进机器判据**（核验表给"文件"列单独一格）
是共享层的事，本轮只立案不做。

**规矩管的是"裸锚没人查"，那带文件名的就查得干净吗——本轮量了，也不干净**：
门禁在还债之前只报 **2 条硬失败**，逐块对差量出来同一棵树上实漂 **88 条带文件名的引用**（还有那 26 处裸写）。
差在那四条判据问的是"存在不存在"，**没有一条问"指的是不是当初那一行"**；被抓到的那两条
是因为恰好漂到了空行上，**余下 86 条漂过去的地方挨着真代码，读起来仍然像话**。
另一件"照明细改会漏"的事：明细那一段**按锚点去重，一条锚点只打印第一个引用它的文档**，
所以改完报出来的两处再跑一遍仍是那两条、只是换了文件名——**要按锚点 `grep` 全仓，不能按明细那两行改**。
这两条的完整记账在 `docs/analysis/header-truncation-audit.md` §9 与
`docs/analysis/release-readiness.md` §1 那一格（含"总数不能当债的读数"那一句：88 条重指，唯一面只动 4）。

## 16. P35b 追加（2026-10-12）：面包屑条上那个「还有 N 卷」，与它为什么不能只靠照片

判据（三级枚举、容量配对去重、排序口径、字节对账）全在 `docs/analysis/disk-volume-enumeration.md`，
本轮实现结果与五条偏离记在那份的 §14。这一节只记**这一屏的还原度账**：画面多了什么、稿没有它、
以及"照片拍到"与"这台机器有"的差别怎么变成机械判据。

**① 新增的是一个徽标，不是页头第四段**。磁盘页面包屑条右侧：
`MMDisk.swift:367-371` 的 `MMBadge(DiskVolumeBadgeCopy.text(candidateCount: volumeRoots?.count))`，
取数：定义在 `:1553-1558`、唯一调用点在 `:1517`（跟着"清单载入"这一件事刷新）；**这两处是收口时重跑对位才落准的**——
本节初稿写的 1515-1524 其实是调用点附近那一屏，定义在它下面 36 行，两个数当时都没现读到底，声明在 `:85`
（`@State private var volumeRoots: [VolumeRoot]?`——**nil 是"没读到"，不是"0 个"**）。
为什么不写进页头副标题：`DiskHeaderContractTests` 把那句钉成**恰好三段、且不含秒数**
（`:235-241` 取数、`:1585-1591` 定序，合同本身是 §15 ② 那一轮的；**这一对行号本节初稿照抄了 §15 那一份、没有现读，P35b 收口时逐条对位重指**——
§15 那一轮读的是 230-236 与 1555-1561，本轮在它们之上分别加了 5 行与 30 行），加第四段就是违约。
§15 ① 那条教训也在这里成立——这一屏的动作簇全站最宽，多出来的要紧话不能挂在会被中间截断吃掉的位置上。
措辞四支与 caveat 集中在 `DiskVolumeBadgeCopy`（`:1603-1617`），caveat 走 `.help()`。

**② 稿侧没有这一格**（`docs/design-system/screens/mmdisk/04-disk.html` 无对应元素）。
归 **设计稿该改**：它不是还原度偏差，是实现比稿多做的一格可见状态，
而 caveat 里那五句（口径 / 去重 / 尺子 / 换卷办法 / 网络卷边界）是稿该抄的内容。

**③ 档位映射**（`MM_VOLUME_FIXTURE` 是本轮新增的合成档，读取点 `MMCore/VolumeRoots.swift` 的
`VolumeRootProbe.snapshot(env:)`；不注这一支就是读这台机器的挂载表）：

| 档 | 照片 | 画面上那句 | 这一格证明什么 |
| --- | --- | --- | --- |
| 不注（真机） | `p35b-volumes/01-disk-real-one-root.png` | **什么都不写**（候选根 1，`:1607` 那支返回 nil） | 本机今天只有一卷可分析，而"只有 1 卷"我们不写成自证 |
| `two` | `02-disk-fixture-two.png` · 暗档 `p35b-volumes-dark/02-…` | 「这台机器还有 **1** 卷可以切换分析」 | 正分支的排版放得下；N 是 `count−1`（当下这卷已经在分析，不能再卖一次） |
| `zero` | `03-disk-fixture-zero.png` | **仍然什么都不写** | 有挂载点、但没有一条能扫 —— 这一档证明它**没有**长成「还有 0 卷」，也**没有**冒充"读不到"（两个不同的事实，`DiskVolumeBadgeTests` ③ 钉的就是这条） |
| `fail` | `04-disk-fixture-fail.png` | 「未能读取卷列表，这里不猜数字」（caution 色 + `questionmark.folder`） | 读数失败那一支有话说，且不编数 |
| `two` + 窄窗 | `05-disk-fixture-two-narrow.png` | 「这台机器还有 1 卷可以切换分析」在 1000 pt 宽下 | §15 那一族的截断检查：徽标与「未纳入 N 个受保护目录」「卷可用 X」挤不挤 |
| 非法值 | `06-disk-fixture-invalid-voided.png` | 回到真机那一态（什么都不写） | 写错值整支作废 + stderr 留一行，回落 `off` = 读这台机器 |

四支措辞里**只有两支会画东西**（`two`/`fail`）；`zero` 与真机那两张画面同形是**设计如此**，
所以这一族不能靠 md5 判夹具生效与否——判据换成 stderr 那行留痕 + 日志里的 `# 页：`/`# 夹具：` 两行。

概览页那两张（`07-overview-real-count.png` / `08-overview-fixture-fail.png`）拍的不是这一屏，
是页脚那句「N 个卷」（`MainWindow.swift:277-285`），列在这里只因为同一个判据层喂两边。

**④ 01 与 07 这两张"画面上一句话都没有"的照片，单看是不可证的**。空徽标既可能是"候选根=1 所以不写"，
也可能是"这段代码根本没跑"。本轮的交叉读数是把 P35a 那支探针**当天在同一棵树上重跑**、
输出到独立目录 `docs/verification/p35b-volumes-probe/volumes.log`，它打印「候选根=1」，
头部 `# digest: 27db42a+d01abc46` 与被测产物的 `MMSourceDigest` 逐字相同
（同族多跑必须换目录，规矩出自 `f7bca94`）。**照片证明界面，探针证明数字。**

**⑤ 本轮自己造出来的两处假绿，都是被脚本的门禁抓住的**（不是人眼看照片看出来的）：
- `VolumeFixtureTier` 第一版把 `\(tier.rawValue)` 漏写成 `\tier.rawValue`：`\t` 被当制表符，
  stderr 那行"留痕"打的是 `MM_VOLUME_FIXTURE=〈TAB〉ier.rawValue 已生效`——照片照常拍到徽标、
  日志照常有一行"已生效"，**取证用的那行字没说出用的是哪一档**。现在那句是纯函数
  `appliedNote`（`VolumeRoots.swift`），由 `testAppliedNoteNamesTheTier` 钉住"档位名必须在里面、
  且不许出现未求值的插值"。
- `shot 07`/`shot 08` 第一版漏传第四个参数，两档都落在磁盘页上：07 与 06 逐字节相同，
  而概览页那两张从头到尾没拍到过概览页。修法是脚本自己断言每张的**页别**（日志里那行 `# 页：`），
  外加 06↔07 md5 **必须不同**这条兜底。P6.6 那一族的判据（同钩子两档 md5 相同 = 夹具没生效）
  在这里反过来救了一次。

**⑥ 回归网**：`VolumeRootsTests` 19 条（纯函数：三级枚举/去重/排序/口径/四档夹具/appliedNote）
+ `DiskVolumeBadgeTests` 8 条（四支措辞 + caveat 五句 + nil≠0）。
九包 `合计：764 个测试，0 个失败，1 个跳过`（`docs/verification/p35b-volumes/run-all-tests.log`，
逐包 MMCore 96 · MMUI 17 · MMFileScanner 117 · MMCleaner 25 · MMUninstaller 200 · MMDisk 85 ·
MMMonitor 57 · MMGuardian 96 · MMOptimizer 71；比 P34b 的 737 多 27 = 本轮那两个新文件）。
**那一串是 P35b 归档的快照，不是当前值**：MMMonitor 自 P37 起是 85、全套 792（见 `release-readiness.md` §7.29）——抄它当"现在"会漏掉一轮。
它钉得住措辞与判据，钉不住"这台机器有几块盘"——**合成值只证明界面会写这句话，
不证明这台机器有两块盘**，所以 caveat 与每一档日志里那行"这是合成快照"都不许删。

**⑦ 仍未做的**（写清，不含"应该没问题"）：**C 档「一键换卷重扫」没实现**，
所以徽标那句只报数、点了没反应，caveat 第一句就是"要分析别的卷，现在按「选择目录」走到那卷上的任意目录"。
照片里 `two` 档那个"还有 2 卷"在真机上永远不出现（本机候选根恒为 1），
它是**将来插第二块盘时才会活过来的那一格**——本轮只做到"它长什么样、放得下、口径说得清"。



