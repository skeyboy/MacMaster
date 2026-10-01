# 04 磁盘分析 · 设计稿 ↔ 实现 逐元素对照（fidelity-disk）

> **结论先行**：04 稿（`docs/design-system/screens/mmdisk/04-disk.html`）只画了**一种状态**——treemap
> 已扫描 + Xcode 选中且已标记的首屏。把这一屏逐元素拆开，结构、文案、配色三层**大体对得上**：
> 7 类分类模型与色值（`#AF52DE/#5E5CE6/#30B0C7/#28CD41/#8E8E93/#FF9500/#A2845E`）与实现
> `DiskClassify.swift:28-37` 逐字一致，分段控件、筛选框宽 132、treemap 圆角 3pt、详情面板 268pt
> 宽均对得上，副标题四个字段的顺序与 `MMFormat` 输出格式一致。
>
> 真正的缺口分两类：
> 1. **设计稿覆盖不全**（占大头）：列表视图态、大文件列表态、确认删除 sheet、撤回 toast、扫描中态、
>    空态、过滤态——这些实现里都画得出来，但 **04 稿一个 artboard 都没有**，还有一整块
>    "值得看一眼"面板实现里有、稿里没有。这正好踩在本项目"每屏 artboard 要覆盖该视图真能画出的每一种状态"的红线上，
>    判 **设计稿该改 · 中**（S1/S2）。
> 2. **一处真硬伤在钩子**：`MM_DISK_SCAN` 等扫描类钩子**没有 /tmp 越界拦截**
>    （`MMDisk.swift:135-136` 直接 `expandingTildeInPath` 后 `scan`，不判路径前缀），
>    违反本项目"扫描类钩子只认 /tmp、越界即忽略"的明线纪律（README §5），
>    一旦被设成真实用户目录会去枚举真实磁盘树，判 **实现该改 · 高**（I1）。
>
> 另外有若干像素级/措辞级偏差（header 带高度、详情图标、徽章文案、各状态栏高度等），
> 无头环境无法真机测量，凡像素项一律标 `⚠️待真机测量`，没有编造任何数字。
>
> 逐元素对照 **31 项**，其中 **18 项存在需归属的差异**（**高 1 / 中 3 / 低 14**）：
> **实现该改 12 条**（I1–I12）、**设计稿该改 6 条**（S1–S6，含 S5 全站侧栏 footer）。
> **另有 13 项状态因为缺设计 artboard / 无法真机测量而完全没能验证**（见 §4）。

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

- 页头 46pt：`MMPageHeader` `MMMetric.toolbar = 46`（`MMDesign.swift:86,267`），与 `screen.css` `.toolbar { height: 46px }`、04 稿 `.toolbar` 一致 ✓。
- 详情栏 268pt：`MMMetric.inspector = 268`（`MMDesign.swift:89`），与 `screen.css` `.inspector { width: 268px }`、04 稿 `.inspector` 一致 ✓。
- treemap 圆角 3pt：`TreemapView.swift:464` `roundedRect: rect, cornerRadius: 3`，与 04 稿 `.blk { border-radius: 3px }` 一致 ✓。
- 7 类色值：04 稿 `<div class="cap">` 配色与 `DiskClassify.color`（`DiskClassify.swift:28-37`）逐字相同 ✓。
- 徽章高 18pt：`MMBadge` `.frame(height: 18)`（`MMDesign.swift:232`），与 `tokens.css` `.badge { height: 18px }` 一致 ✓。

## 1. 逐元素对照表

严重度定义：**高** = 用户会读到错误结论 / 违反安全红线；**中** = 视觉或语义明显跑偏，或整块 UI 在稿中缺失导致无法核对；**低** = 像素级偏差、措辞口径、占位数据。

### 1.1 标题栏与侧栏（shell / 共享层）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题栏 traffic + "MacMaster"（sparkles 图标） | shell `Sources/MacMaster`（非本模块） | ✅（代码外推） | 04 稿画法与全站壳一致；本模块不拥有标题栏 | — | — |
| 侧栏 7 个 nav-item（概览/系统清理/应用卸载/磁盘分析/系统监控/隐私守护/系统优化） | shell 导航 | ✅ | 图标与 04 稿逐一对得上（`i-gauge/sparkles/app-x/treemap/activity/shield-check/speed`） | — | — |
| 侧栏「磁盘分析」为 active（treemap 图标 + accent） | `MM_OPEN_MODULE=disk` 高亮 | ✅ | 由壳工程导航真源决定 | — | — |
| 侧栏尾数占位「系统清理 2.4 GB」「应用卸载 46」 | 壳层渲染其他模块数据 | ❌ | 纯占位（与 07 稿同源错误）；本机数字应另行回填 | 低 | 设计稿该改 S6 |
| **侧栏 footer** | 实机 = 卷容量行（`Macintosh HD` + 红色容量条）+ 带边框「设置」按钮 | ❌ | 04 稿（与 01–07 一致）画成「分隔线 + 设置 nav-item」，缺容量行。属全站缺口 | **中** | 设计稿该改 S5（全站） |

### 1.2 工具栏（页头 / MMPageHeader）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「磁盘分析」 | `MMDisk.swift:141` `MMPageHeader("磁盘分析")` | ✅ | 逐字一致 | — | — |
| 副标题「~/Library · 695,682 个文件 · 271.4 GB · 扫描用时 7.6 s」 | `:173-179` `headerSubtitle` | ✅（格式） | 字段顺序与 `MMFormat.count/bytes` + `String(format: "%.1f")` 一致；`695,682` 的千分位来自 `MMFormat.count`（`:141` grouping）。路径是真实扫描根，非稿内固定 `~/Library`——属稿内示意 | 低 | 记录 |
| 分段控件「Treemap / 列表」 | `:21-41` `ViewMode` rawValue | ⚠️ 部分 | **实现有 3 段**：Treemap/列表/大文件；04 稿只画 2 段，缺「大文件」段（但 README §2 钩子列 `MM_OPEN_TAB(large)`、产品规划 2.1 也列大文件，故属稿缺） | 低 | 设计稿该改 S3 |
| 筛选框「筛选名称」宽 132 + 搜索图标 | `:149-152` `TextField.frame(width: 132)` | ✅ | 宽 132 与稿一致；系统 `roundedBorder` 是否带搜索图标 ⚠️待真机测量 | — | — |
| 按钮「重新扫描」（refresh 图标） | `:155-160`（重新扫描）/ `:162-168`（选择目录） | ⚠️ 部分 | 实现有**两个**按钮：重新扫描（重枚举当前层）+ 选择目录（borderedProminent）；稿只画 1 个「重新扫描」。稿内单按钮语义≈重扫全根，实现"重新扫描"= 重枚举当前导航层 | 低 | 实现该改 I‑（见 §2 记一笔） |

### 1.3 面包屑栏（breadcrumbBar）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 「Macintosh HD › lee › Library › Developer」（末项加粗） | `:382-388` `BreadcrumbView` | ⚠️ 部分 | 实现面包屑从**扫描根**起（`navigationStack`），不前缀卷名；若扫 `~/Library` 则首项是 `Library` 而非 `Macintosh HD`。稿假定从卷根扫到 Developer | 低 | 设计稿该改（稿内示意 vs 实现通用） |
| 行首「‹」返回箭头 | 无对应元素 | ❌ | 实现面包屑项本身可点击上跳，无独立返回 chevron；键盘 Esc / 手势 onBack 负责返回 | 低 | 实现该改 I‑（低，见 §2） |
| 右侧徽章「已标记 3 项 · 48.6 GB」 | `:272-280` marked 时 `MMBadge("已标记 N 项 · X")` | ✅（结构） | 文案与触发条件一致；但**稿内写 3 项、treemap 内仅 1 个勾标**——稿内自相矛盾（见 S4） | 低 | 设计稿该改 S4 |
| 面包屑栏高 26px | `:290-293` `.frame(height: 34)` | ❌ | 稿 26pt vs 实现 34pt ⚠️待真机测量（代码 34） | 低 | 实现该改 I11 |
| 「判不了 N 个目录」徽章（过滤深层未测） | `:266-270` | ✅（代码分支） | 实现独有；稿无对应态（过滤态缺 artboard） | 低 | 设计稿该改 S2 |

### 1.4 Treemap 主体（正常态 / 选中态 / 标记态）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 7 类色块：开发者/应用数据/媒体/文档/缓存/日志/其他 | `DiskClassify.swift:12-39` + `TreemapView` 布局 | ✅ | 色相与顺序逐字一致 | — | — |
| 面积 = 实际占用（st_blocks×512） | `MMDisk.swift:1585-1626` `readEntries` 取 `st_blocks*512` | ✅（数据口径） | 实现确用分配大小；但见 I7 图例文案漏注 | 低 | 实现该改 I7 |
| 选中块：2px accent 描边 | `TreemapView.swift:527-528` `stroke(accent, lineWidth: 2)` | ✅ | 与稿 `.sel { outline: 2px #0A84FF }` 一致 | — | — |
| 标记块：斜纹 + 右下勾标 | `TreemapView.swift:478-525` 白纹 + 勾标 | ⚠️ 部分 | 稿对 Xcode 同时画 **暗纹(reclaimable) + 勾标(marked)**；实现**标记后暗纹让位给白纹**。取舍不同，视觉略异 | 低 | 实现该改 I12 |
| 可清理斜纹（hatch） | `TreemapView.swift:472-475` 暗纹 0.20 | ✅（语义） | 与稿斜纹语义一致（色相=种类、斜纹=可清） | — | — |
| 退色块 `dim`（如 Other 8.3 GB、iCloud 只读子块） | 无对应实现 | ⚠️ | 稿 `.dim` 语义未定义（只读？非首要？），实现用**深度提亮**(`TreemapPalette.shade`) 表达层级，无显式 dim 态 | 低 | 设计稿该改（dim 语义请定） |
| header 带（目录名带）默认高 20px | `TreemapLayoutOptions.headerHeight = 14`（`TreemapView.swift:116`） | ❌ | 稿 `.cap` 默认 20px、子块 inline `--cap:16px`；实现统一 14pt ⚠️待真机测量 | 低 | 实现该改 I9 |
| 块内标签阈值（≥40pt 才画） | `TreemapView.swift:500-516` 宽≥68高≥30 / 宽≥34高≥16 | ⚠️ | 稿未给阈值；代码阈值与稿示意块大小能否容下文字需 ⚠️待真机测量 | 低 | ⚠️ |
| treemap 背景 = under-page | 容器背景 | ⚠️ | 稿 `.treemap { background: var(--c-under-page) }`；实现 treemap 由 Canvas 绘制，块间空隙透出 content 背景，是否填 under-page ⚠️待真机测量 | 低 | ⚠️ |
| 「其余 N 项」合并块 | `TreemapLayout.compute` `others:`（`TreemapView.swift:151-161`） | ✅（代码分支） | 面积守恒合并，稿未显式画；属 disktree 采纳项，稿未覆盖 | 低 | 设计稿该改 S2 |

### 1.5 图例

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 7 色块 + 「可清理（斜纹）」+ 说明 | `MMDisk.swift:468-513` `legend` | ✅（结构） | 色块顺序一致 | — | — |
| 说明「面积 = 实际磁盘占用（st_blocks × 512）· 双击下钻 · ⌘ 点击标记」 | `:499-501` | ❌ | 实现说明**省略了 `(st_blocks × 512)`** 注脚，写「面积 = 实际磁盘占用 · 双击下钻 · ⌘ 点击标记」。数据确为 st_blocks，但文案精度低于稿 | 低 | 实现该改 I7 |
| 深度分段控件（1–4 层） | `:482-495` `Picker("深度")` | ⚠️ 部分 | 稿无此控件（对应 `MM_DISK_DEPTH` 钩子）；实现独有，稿缺 artboard | 低 | 设计稿该改 S2/S3 |

### 1.6 详情面板（inspector，选中 Xcode 时）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 头部图标 cube.box 紫（`i-box` + `--c-purple`） | `MMDisk.swift:678-679` `folder.fill/doc.fill` 按 `risk.color` | ❌ | 稿用 `i-box` 紫色图标；实现用 folder/doc 图标按风险色（safe=绿）。形状与颜色都不同 | 低 | 实现该改 I3 |
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
| 底部栏高 28px（状态栏） | `MMDesign.swift:309` `MMActionBar` `MMMetric.actionBar = 52` | ❌ | 稿 28pt 状态栏 vs 实现 52pt 动作栏；**内容一致**（未标记时），容器样式/高度不同 ⚠️待真机测量 | 低 | 实现该改 I8 |

### 1.8 「值得看一眼」面板（实现独有）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| （稿中无此面板） | `MMDisk.swift:298-362` `findingsPanel` | ❌ | 实现在面包屑下插入整块「值得看一眼 · N 项 · 合计 X」面板（disktree #4 采纳）；**04 稿完全没画**，无法核对排版/文案 | **中** | 设计稿该改 S1 |

### 1.9 状态：选中 / 标记 / 确认删除 / 撤回 toast

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 选中 + 标记态（Xcode 勾标 + 描边） | `:996-1030` `applySelectionHook` + `TreemapView` 选中/标记绘法 | ⚠️ | 代码可构造；稿仅静态画了这一态，无独立 artboard；视觉 ⚠️待真机测量 | 低 | ⚠️ |
| 确认删除 sheet「把 N 项移入废纸篓？」+ 可回收/被拦分列 | `:1034-1114` `markConfirmSheet` | ❌ | **稿无确认 sheet artboard**；实现面板含 targets / blocked（lock 图标 + 原因）/ absorbed 提示，文案较稿丰富 | **中** | 设计稿该改 S2 |
| 撤回 toast「已移入废纸篓 X · 共 N 项 · 撤回」 | `:107-118` `MMUndoToast` | ❌ | **稿无 toast artboard**；`MM_SHOW_TOAST` 仅借用选中项数字摆一拍（`:1025-1029`），属合成态 | 低 | 设计稿该改 S2 |
| `MM_DISK_SCAN` 只认 /tmp，越界忽略 | 缺失 | ❌ | `MMDisk.swift:135-136` 未判路径前缀即 `scan`；违反 README §5 钩子红线 | **高** | 实现该改 I1 |

### 1.10 状态：列表视图 / 大文件列表 / 扫描中 / 空态 / 过滤

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 列表视图（名称/占比条/大小行） | `:522-588` `listView` + `:592-634` `nodeRow` | ❌ | **稿无列表视图 artboard**；实现有完整列表+占比条+过滤态 | **中** | 设计稿该改 S2 |
| 大文件列表态（MM_OPEN_TAB=large） | `:647-670` `largeFilesList` | ❌ | **稿无大文件列表 artboard**；实现有，且分段控件还多一段「大文件」 | **中** | 设计稿该改 S2/S3 |
| 扫描中态（indeterminate ProgressView） | `:199-250` `scanningView` | ❌ | **稿无扫描中 artboard** | 低 | 设计稿该改 S2 |
| 空态（未扫描 / 层为空 / 过滤无命中） | `:181-194` `placeholder`、`:526`、`:566`、`:441` | ❌ | **稿无空态 artboard** | 低 | 设计稿该改 S2 |
| 过滤态（命中保色 / 祖先退色 / 判不了徽标） | `:456-463`、`DiskTreeFilter.swift` | ❌ | **稿无过滤态 artboard**；实现两级 tier（`TreemapView.swift:7-12,428-434`）对应 disktree 口径 | 中 | 设计稿该改 S2 |

## 2. 实现该改（12 条，按严重度排序）

1. **【高】I1 · `MM_DISK_SCAN` / `MM_DISK_SELECT` 缺 /tmp 越界拦截**
   `MMDisk.swift:135-136` 直接 `guard ... let root = env["MM_DISK_SCAN"] ... await scan(rootPath: (root as NSString).expandingTildeInPath)`，
   不检查路径是否落在 `/tmp` 之下。`MM_DISK_SELECT`(:998) 同样不限前缀，只靠"先扫过才有节点"间接约束。
   按 README §5 红线——"钩子一律只认 /tmp 之下的夹具路径，越界就写 stderr 并忽略"——这是本模块对那条红线的
   **唯一破口**：一旦被设成真实目录（如 `MM_DISK_SCAN=~` 或 `/`），`scan()` 会去 `lstat`/`readdir` 真实磁盘树，
   即使扫描本身只读，也会触碰真实用户文件、且深度 20 的整树枚举极重。
   → 建议：在 `MMDisk.swift` 的扫描钩子入口加 `root.hasPrefix("/tmp")` 判定，否则 `stderr` 写"MM_DISK_SCAN 仅接受 /tmp 之下路径"并 `return`。
   **本环境未修改**（硬约束 #4 优先"提请协调者"），见 §提请协调者。
2. **【低】I2 · 详情徽章文案「安全」≠ 稿「可安全清理」**
   `MMBadge(risk:)`(`MMDesign.swift:219-221`) 取 `risk.label`（`Risk.swift:14`="安全"），稿 `.badge.safe` 文本为「可安全清理」（= `risk.groupTitle`）。
   → 建议：徽章改取 `risk.groupTitle`，或 04 稿改文案为「安全」。两者择一。
3. **【低】I3 · 详情头部图标不符稿**
   稿用 `i-box`（cube.box）紫色；实现 `MMDisk.swift:678` 用 `folder.fill`/`doc.fill` 按 `risk.color`。形状与颜色都不同。
   → 建议：统一为稿的 cube.box 紫，或更新稿说明图标随风险色变化。
4. **【低】I4 · 详情「子项」≠ 稿「文件数」**
   `MMDisk.swift:704` 显示 `children.count`（直接子节点数）；稿写「文件数 42,180」（递归文件数）。两者量的是不同东西。
   → 建议：若需"文件数"，应递归累加 `collect` 得到的 `fileCount`；或稿改文案为「子项」。`disktree-adoption` 里 `fileCount` 已统计（`:1466`），可直接喂给详情。
5. **【低】I5 · 「占当前层」vs 稿「实际占比」**
   `MMDisk.swift:703` 分母 `levelTotal` 随导航层变化；稿「实际占比」暗示占总扫描量。措辞/口径不一致。
   → 建议：稿明确"占当前层"，或实现在根层用 `scannedSize` 作分母并改标签。
6. **【低】I6 · 修改时间绝对 vs 相对**
   `MMDisk.swift:707` `MMFormat.relative`；稿绝对日期。实现注释已说明绝对时间戳在 268pt 内会被截。属有意取舍，两可。
   → 建议：保留相对，但稿应改为相对时间示例，避免"稿画绝对、实现相对"的落差。
7. **【低】I7 · 图例漏注 `(st_blocks × 512)`**
   数据确用分配大小（`MMDisk.swift:1612`），但 `MMDisk.swift:499-501` 图例写「面积 = 实际磁盘占用」而稿写「面积 = 实际占用（st_blocks × 512）」。
   → 建议：图例补回 `(st_blocks × 512)` 注脚，与稿对齐，也兑现 disktree 采纳的口径承诺。
8. **【低】I8 · 底部栏 52pt 动作栏 vs 稿 28pt 状态栏**
   未标记态内容一致（卷可用 / 统计不含…），但容器是 `MMActionBar`(52pt,`MMDesign.swift:309`) 而非稿的 28pt 状态栏；"标记后预计"也被挪到面包屑。
   → 建议：标记后底部栏出现动作按钮是合理的，但稿需补画"标记后动作栏"artboard；未标记态可考虑降级为更薄的状态条以贴合稿。
9. **【低】I9 · treemap header 带 14pt vs 稿 20pt**
   `TreemapLayoutOptions.headerHeight = 14`(`TreemapView.swift:116`)；稿 `.cap` 默认 20px（子块 16px）。⚠️待真机测量确认视觉落差。
   → 建议：若真机看 header 带过窄，提到 18–20pt；或稿改 14pt。
10. **【低】I10 · 内部构成行高 28pt vs 稿 32px**
    `MMMetric.rowCompact = 28`(`MMDesign.swift:83`)；稿 `.rrow` 32px。⚠️待真机测量。
11. **【低】I11 · 面包屑栏 34pt vs 稿 26px**
    `MMDisk.swift:291` `.frame(height: 34)`；稿 `.crumbs` 26px。⚠️待真机测量。
12. **【低】I12 · 标记后暗纹让位白纹**
    稿对 Xcode 同时画 reclaimable 暗纹 + marked 勾标；实现 `TreemapView.swift:472-481` 标记后暗纹被白纹覆盖，只看到白纹+勾标。
    → 建议：标记态是否保留一层暗纹底以同时表达"可清+已标"，与稿作者确认；属视觉取舍，非错误。

> 另外两笔不在差异计数内、但记于此：① 工具栏"重新扫描"语义（重枚举当前层 vs 稿的重扫全根）与多出的"选择目录"按钮（§1.2）；
> ② 面包屑行首缺独立返回箭头（§1.3）。均无真机落差风险，列为低优先，随 1.2/1.3 一并处理。

## 3. 设计稿该改（6 条）

1. **【中】S1 · 04 稿缺「值得看一眼」面板**
   实现 `MMDisk.swift:298-362` 在面包屑下插入整块发现面板（disktree #4 已采纳），稿完全没画。该面板是模块核心信息区，
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
   实现侧属 shell 共享层（非 mmdisk 能改），故记此待协调者统筹。
6. **【低】S6 · 侧栏尾数占位**（沿用 `fidelity-monitor.md` S2）
   「系统清理 2.4 GB」「应用卸载 46」在 04 稿无数据来源，应改成与实机一致的数值或留空，避免"稿子数字像实测"。

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
| 8 | treemap 全部像素几何（块位置、header 带 14pt、斜纹密度、标签阈值、背景 under-page） | 无头、Canvas 绘制 | `MM_DISK_SCAN=/tmp/夹具` 起实例 → 按 pid 抓窗 → CoreGraphics 取色 |
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

1. **`MM_DISK_SCAN` / `MM_DISK_SELECT` 越界红线的修复归属**（对应 I1，高）
   本模块是唯一破了"扫描类钩子只认 /tmp"红线的地方（`MMDisk.swift:135-136`、`:998` 无前缀校验）。
   按硬约束 #4「优先提请协调者」，请协调者确认：是否在 `MMDisk/Sources` 内照 `GuardianFixtureHooks.swift` 口径
   补 `/tmp` 守卫（越界写 stderr 并 `return`），并把 `MM_DISK_SCAN` 的 `expandingTildeInPath` 结果做 `hasPrefix("/tmp")` 判定。
   **本审计未改此代码**，等协调者拍板。
2. **04 稿 artboard 补全的统筹**（对应 S1/S2/S3，中）
   列表视图、大文件列表、确认删除 sheet、撤回 toast、扫描中、空态、过滤态、值得看一眼面板、大文件分段——
   共需新增约 9 个 artboard。建议由设计稿 owner 统一补，避免各模块自行脑补。
3. **侧栏 footer 全站组件**（对应 S5，中，沿用 monitor S1）
   属 shell 共享层（tokens/screen.css + `Sources/MacMaster`），非 mmdisk 可改；请协调者统筹八张稿一起换。
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
