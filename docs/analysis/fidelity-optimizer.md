# 08 系统优化 · 设计稿 ↔ 实现 逐元素对照（fidelity-optimizer）

> **结论先行**：08 稿四个 tab（duplicates 重复文件 / browser 浏览器缓存 / status 系统状态 /
> devtools 开发工具缓存）与实现在**结构、文案、状态机**三层高度一致——页头副标题来源、
> 分段页签 maxWidth 340、四 tab 的空/扫描中/结果/失败态、`keepRequired` 硬约束、devtools
> "只报不执行"与 PROTECTED 分档都照设计落地。逐元素对照 **45 项**，需归属的差异很少：
> **实现该改 0 硬项**（那 1 项 ⚠️中 待真机测量的"失败回执容器橙底"已于 **P6.5b 复核结清：缺陷从未存在**，
> 见 §3）、**设计稿该改 3 低**
> （侧栏占位数字、浏览器删除按钮图标、08e 推演档标注）。写这份审计时受"只有 `MM_OPEN_TAB` 一个钩子"限制，
> 四 tab 内的空/失败/超大列表/PROTECTED 拒绝态暂无注入路径，逐条列在 §5——
> **注入路径后来补上了**（`MM_OPTIMIZER_FIXTURE`，`969e548`，2026-09-30），但 §5 那七档
> **一张照片都还没拍**：`grep -r MM_OPTIMIZER_FIXTURE Scripts/` 无命中，`docs/verification/` 下没有 optimizer 夹具目录。
> 也就是说这一页现在是"有钩子、无取证"，缺的是跑一遍夹具脚本，不再是缺能力。
>
> **P34b 追加（2026-10-12）：这一页现在是五个 tab。** 本文件通篇（含下面的章节标题）的"四 tab"是这份审计写下当天的事实，
> 新增的是 `preferences`（偏好文件那一屏，`MMOptimizer.swift:270`）。本文件不重写历史结论，
> 第五屏的对照、取证与**实拍抓出来的一个溢出缺陷**记在新增的 **§7**；稿侧对应的是新增的 **08f** artboard。
>
> **安全口径复核（核心交付）三条结论**：
> ① 候选列表（Documents/Downloads/Desktop 内重复文件、~/Library/Caches 下浏览器缓存）
> **全部经 `FileTrashService` → `DeletionGuard` 单一闸口**，与闸门三层口径无冲突，
> 未发现"设计该拦却被放行"的漏判；
> ② PROTECTED 拒绝态**复用共享 `MMUI.MMFailurePanel`**（与 MMCleaner 的
> `MM_FAILURE_FIXTURE=protected` 同一组件），shield/caution 分档表达完全一致，达标；
> ③ **无绕过 `FileTrashService` 的直接删除路径**——全模块删除仅 2 处 `moveToTrash`
> （`MMOptimizer.swift:439`、`:690`）+ 1 处 `undo`（`:462`），无任何 `FileManager.removeItem` /
> `trashItem` / `rm`；devtools tab 零删除、零 spawn（仅 `NSPasteboard` 拷贝 + stat 探测）。
> 无越界 bug。

## 0. 对照方法（先说清楚哪些是量出来的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmoptimizer/08-optimizer.html`（审计当时 5 个 artboard：08 首屏未扫描 / 08b 扫描结果 / 08c 扫描中+浏览器 / 08d 系统状态+回执 / 08e 开发工具。**P34b 起为 6 个**：新增 **08f 偏好文件**，五个窗格——真实态整窗 + 破损/读不到两个 540 px 夹具窗 + 空态与截断态。渲染产物 `08-optimizer.png` 现为 2320x11402，审计当时那份是 2320x8020） |
| 实现 | `Packages/MMOptimizer/Sources/MMOptimizer/`：`MMOptimizer.swift`、`DevToolCacheView.swift`、`DashboardMetrics.swift`、`DevToolCacheAudit.swift`（审计当时四文件）+ **P34b 新增 `PreferencesAudit.swift`（纯判定层）与 `PreferencesView.swift`（呈现层）** |
| 渲染 | 本环境**无头、未运行 App、未截图**，不编像素数字；几何/像素项一律标 `⚠️待真机测量`，只从代码＋HTML+tokens 推导 |
| 复用基准 | 共享组件 `MMFailurePanel`/`MMBadge`/`MMFormat` 取自 `Packages/MMUI/Sources/MMUI/MMDesign.swift`；闸门取自 `Packages/MMCore/Sources/MMCore/DeletionGuard.swift`、`FileTrashService.swift` |
| 可用钩子 | 审计当时**只有 `MM_OPEN_TAB=duplicates\|browser\|status\|devtools`**（`MMOptimizer.swift:41`），故四 tab 内的空/失败/超大列表态无注入路径（§5 全部由此而来）。**复核 2026-10-04：这句在本文件提交那天就已经过期了**——`MM_OPTIMIZER_FIXTURE` 由 `969e548`（2026-09-30）落地，而它正是本文件 §6 #1 建议的那件事；两份文件都提交在 2026-09-30，`969e548` 还是 `e96c95b`（本文件入库那一笔）的**祖先提交**。所以不是"别人后来改了代码"，是**自己建议改完没回写建议**（`OptimizerFixtureHooks.swift:4-5` 的表头甚至引用了"§5 #1–7"，说明写钩子时这份审计已经在了）。入口：`Packages/MMOptimizer/Sources/MMOptimizer/OptimizerFixtureHooks.swift`，解析点 `MMOptimizer.swift:82`；档位 `duplicates:<N>`（N>0 组数）/`duplicates:empty`/`duplicates:scannedEmpty`/`browser:rows`/`browser:empty`/`status:allReadOnly`/`devtools:notInstalled`/`devtools:unreadable`/`protected`，逗号可叠加，铁律与 monitor/guardian 同口径（只顶替展示数据、不写盘不 spawn 不读 /tmp、含非法值整钩作废）。README §2 矩阵同步已到位（`docs/design-system/README.md:43`）。**但没有任何脚本用过它**（`grep -r MM_OPTIMIZER_FIXTURE Scripts/` → 0 命中），§5 的七档仍是"能力有、照片无" |
| 硬约束 | 全程未发合成事件、未运行 App、未截图、未改 `Packages/`/`tokens.css`/`screen.css`/`icons.js`；未做任何 git 操作；未碰 `/tmp` 之外路径。本稿只新增本文件 |

代码侧已实证的口径（来自共享文件，非本模块自造）：

- `MMFormat.bytes(_:UInt64?)`（`MMDesign.swift:149-153`）：`nil → "测量中"`（`:150`），`<1000 → "N 字节"`（`:151`），否则 `byte.string`（`:152`）。→ 浏览器 nil 体积渲染"测量中"与 08c 一致，非"0 字节"。**（P35b 现读重指：本行此前写 `:113-117`，那是更早的树。）**
- `MMFailurePanel`（`MMDesign.swift:672-785`）：恒定渲染 `MMBadge("N 项失败", tint:.caution)`（`:724`，无论 `summary` 是否 nil）；逐条按 `code=="PROTECTED"` 走 `exclamationmark.shield`+`MMColor.caution`（`:739`/`:741`），否则 `xmark.circle.fill`+`destructive`；显示 `path + message + code`（`:743-757`）；`>4` 条折叠"另有 N 项失败"（`:760-764`）。
  **复核 2026-10-04 的两处更正**：① 上面这一串行号取自今天的文件已不成立（**P35b 现读**：组件 `:672`，body `:716-785`）；
  ② **更要紧的是这条 bullet 本身漏判了一件事**——它把 body 截在 `:674`，于是没读到 `:676` 之后的
  `.background(MMColor.soft(MMColor.caution, 0.10))`（今天 `:783`），直接导致 §3 I1 那个"橙底缺失"疑点被立案。
  **方法教训（写进本节，供后续审计照办）：判"组件没有某个修饰符"必须读到 body 的收尾大括号，
  按估计范围截行会把"有"读成"无"。** 同一天里 `MMFormat.bytes` 那条是按整段读的，结论就站住了。
- `FileTrashService.moveToTrash`（`FileTrashService.swift:35-69`）：循环开头即 `DeletionGuard.rejection(for:)`（:43），PROTECTED → `TrashFailure(code:"PROTECTED")`（:44），逐条上报、不静默跳过；执行用 `trashItem`（可撤回、入台账）。
- `DeletionGuard`（`DeletionGuard.swift:25-62`）：系统域子树 / 凭证与活数据子树 / 六个用户目录"**目录本身挡、内容放**"。**P36 现读重指**：这一格此前收口在 `:57`，只圈到第三层的说明注释（54-59），没圈到那六个目录名的字面量（`protectedHomeDirectories` 在 `:60-62`）；本轮按"讲的是哪三层就收到哪一行"放宽。

---

## 1. 逐元素对照表（四 tab 全覆盖）

严重度定义：**高** = 用户会读到错误结论（把未知当已知 / 把失败当正常 / 绕过删除闸门）；
**中** = 视觉或语义明显跑偏但不产生错误结论；**低** = 像素级偏差、占位数据、口径注脚。
`⚠️` = 需真机截图才能判定，本环境未测。**P36 现读重指（2026-10-13）**：本节三张表的锚点此前整片停在 2026-10-04 那一读的坐标上，本轮对着当前树逐行重指了一遍——duplicates 视图一族 +52、browser/devtools 行 +89、status 行 +130，页头一行 +1。**为什么必须手工来一遍**：这一片的坐标绝大多数是裸写 `:NN`（上一格文件名的续写），引用门禁与漂移量尺的正则都要求冒号前紧跟文件名，所以它们对这部分**既看不见也报不出漂**；机械重指罩不住它，只能按稿内条目声称的那件事去 grep 源码、再回读目标行原文核对。

### 1.1 页头 / 页签 / 侧栏（四 tab 共用）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「系统优化」 | `MMOptimizer.swift:52` | ✅ | — | — | — |
| 副标题绑定 `diagnostics.updatedAt`，默认首屏只有标题一行 | `:52` `SystemDiagnosticsModel.updatedAt` 初始 nil，仅 status `.task` 后赋值（`:265`、`:772`） | ✅ | 08 稿注"默认首屏无副标题，不是漏画"——代码逻辑一致；⚠️ 默认首屏是否真无副标题需真机 | 低 | ⚠️待真机测量 |
| 分段页签（重复文件/浏览器缓存/系统状态/开发工具），maxWidth 340 居中 | `:54-61` `.frame(maxWidth:340)` `.padding(.horizontal, .lg)` | ✅ | 居中几何 ⚠️ 像素级未测 | 低 | ⚠️待真机测量 |
| 默认 tab=duplicates；`MM_OPEN_TAB` 可切 | `:41-42` | ✅ | — | — | — |
| 侧栏 "系统优化" active + 其余模块项 | 壳 `MainWindow` 渲染（非本模块） | ✅（P38f 现读） | 08 稿侧栏尾部写 "系统清理 2.4 GB / 应用卸载 46"，08e 已改 "1.27 GB"；占位数字全站问题——**这半句由 `0c61fbf` 作废**：现读 `08-optimizer.html` 六块 artboard 里画了侧栏的只有四块（`:162`、`:238`、`:573`、`:748`），其中侧栏尾数只剩 08e（`:576` `1.27 GB`）与 08f（`:751` `4.43 GB`）两处、都挂在清理行上，08/08b 那两块（`:165-166`、`:241-242`）压根没画尾数；"2.4 GB / 46" 这两个占位串在这份稿子里已经不存在（`2.4 GB` 只作为文件体积出现在 `:418`，`46` 只作为 `max-width:460px` 的子串出现在 `:82`）。而实现侧本来就只给清理行挂尾数、没扫过时留空（`MainWindow.swift:105-110`），所以"没画"与"画了实测值"两种画法都合法 | 低 | 设计稿该改 S1 → **稿侧已落地（P38f）**，见 `release-readiness.md` §7.35 |
| 顶部「查找重复文件」按钮（magnifyingglass，bordered） | `:137-144` | ✅ | 图标 SF `magnifyingglass` 与稿一致 | — | — |

### 1.2 重复文件 tab（duplicates）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 顶行口径「按文件内容比对，不看文件名。」(未扫档) | `:327` headline `guard hasScanned else` 分支 | ✅ | — | — | — |
| 范围行硬编码 Documents/Downloads/Desktop | `:308-311` `scopes`；`:333-338` `scannedScope` 拼名 | ✅ | 与稿"逐字照抄"一致 | — | — |
| 空态两档：未扫="还未开始检测" / 扫过没找到="没有发现内容完全相同的文件" | `:184-188` `MMEmptyState` 标题条件 | ✅ | 绝不混用，与稿一致 | — | — |
| 空态 detail=scannedScope（未扫不追加"本次比对 N 个候选"） | `:187` `detail: duplicates.scannedScope` | ✅ | 稿注"未扫时不追加"——代码 `scannedScope` 在 `lastReport==nil` 时只返回 base（`:336`） | — | — |
| 扫描中 headline="正在按内容比对，未完成前不会给出结果。" | `:325` | ✅ | — | — | — |
| 「停止」按钮 + 「重新扫描」置灰 | `:133-136` 停止；`:144` 重新扫描 disabled | ✅ | — | — | — |
| 进度 `MMScanProgress`：action=阶段原文、estimatedRemaining 恒 nil、fraction | `:149-157` 传 `estimatedRemaining:nil`、`progress.fraction` | ✅（结构） | 阶段枚举 `progress.stage.rawValue` 的原文（归类候选/抽样比对/逐字节校验）来自 `DuplicateScanner`，**不在本模块文件内**；"已处理 N 项" 文案在 `MMScanProgress` 内——⚠️ 待真机核对逐字 | 低 | ⚠️待真机测量 |
| 扫描中且未出分组 → 6 条骨架 | `:177-182` `ForEach(0..<6) MMSkeletonRow` | ✅ | 数量 6 与稿一致 | — | — |
| caveat 横幅「部分文件没能参与判定」+ 读失败/云端占位两档用"；"连接 | `:159-161` `MMPermissionBanner`；`:340-345` `caveatText` | ✅ | 文案拼接与稿一致 | — | — |
| 分组卡头：chevron + doc.on.doc(橙) + "N 个文件内容相同" + "size×n" + 徽章"谨慎"(caution) + 右端蓝"可释放 X" | `:509-544` `DuplicateGroupRow` | ✅ | `MMBadge(risk:.caution)`(:533)、`可释放`=`wastedSpace`(:534) | — | — |
| "可释放 X"= size×(个数−1) | `DuplicateGroup.wastedSpace`（按 `:330` 口径 `totalWaste`）；08b 858=286×3 | ✅ | 数学一致 | — | — |
| "需保留"徽章仅出现在组内唯一未勾且其余全勾项；其复选框禁用 | `:429-434` `isKeepRequired`；`:569` `.disabled(keepRequired)`；`:581` `MMBadge("需保留")` | ✅ | 硬约束与稿"一组必须留一份"一致 | — | — |
| 修改时间 RelativeDateTimeFormatter 短格式 | `:582` `MMFormat.relative` | ✅（代码分支） | 实际格式 ⚠️ 待真机 | 低 | ⚠️待真机测量 |
| 行尾 folder 图标="在访达中显示"(help) | `:589-595` `MMReveal.open`+`.help` | ✅ | — | — | — |
| 操作栏随勾选：「已选 N 项 · X」+ 提示句 | `:468-487` `MMActionBar` | ✅ | 未勾="未勾选的文件不会被改动。"，已勾="被勾选的文件会先移入废纸篓，可撤回。"(:474) | — | — |
| 「移到废纸篓」置灰(disabled) 当未勾选 | `:486` `.disabled(selection.isEmpty)` | ✅ | — | — | — |
| 撤回 toast 8s 自动消失、不传 secondsRemaining（无倒计时数字） | `:488-503` `MMUndoToast` + `Task.sleep(8)` | ✅ | 与稿"没有倒计时数字"一致 | — | — |
| 失败回执 `MMFailurePanel`（PROTECTED 分档） | `MMOptimizer.swift:166-168` `MMFailurePanel(summary:nil, trashFailures)`（P35b 现读重指，此前写 `:118-122`） | ✅（结构） | 见 §2②；容器橙底 **✅已核：组件自带**（`MMDesign.swift:783`） | ~~中(待核)~~ 无 | §3 I1 已关闭 |

### 1.3 浏览器缓存 tab（browser）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 进页签即 `scanIfNeeded`（无"请先点扫描"空态） | `:243` `.task { await browser.scanIfNeeded() }` | ✅ | 稿"量一次不到一秒，比摆空态有用" | — | — |
| 只探测 ~/Library/Caches 下 Safari/Chrome/Firefox/Edge 四目录，存在且非空才列 | `:620-625` candidates；`:628` `fileExists`；`:633` `filter { size==nil \|\| size>0 }` | ✅ | "非空"判定=`size==nil||size>0`，排除 0 字节 | — | — |
| 顶行仅"重新扫描"（扫描中置灰），**无停止按钮** | `:205-216` 无停止；`:215` disabled | ✅ | 与稿"与重复文件页签不同，没有停止按钮"一致 | — | — |
| headline "N 个缓存目录 · 合计 X（M 个目录没读到，未计入）" | `:647-656` | ✅ | 合计只加 `measured`（`:650-651`），未量到的追"未计入" | — | — |
| 每行动作仅"位置"(访达显示)+"移到废纸篓"(小按钮红字) | `:713` `MMRevealButton`；`:721-728` 删除按钮 tint red | ✅ | 图标：稿用 `#i-box`，实现用 SF `trash`（见 S2） | 低 | 设计稿该改 S2 |
| size=nil → "测量中"，help="目录存在，但体积没能读出来；不是 0 字节。" | `:716` `MMFormat.bytes(item.size)`（nil→"测量中"，已核）；`:720` `.help(...)` | ✅ | 文案与稿逐字一致 | — | — |
| "测量中"行排末位（nil 按 0 参与排序），绝不显 0 | `:633-634` `sorted { ($0.size ?? 0) > ($1.size ?? 0) }` | ✅ | 与稿"排末位但绝不混同 0 字节"一致 | — | — |
| 不碰历史记录/密码/Cookie（空态 detail 原文） | `:225` detail 文案 | ✅ | — | — | — |
| 空列表两档："正在统计缓存体积…"(未扫) / "没有发现可清理的浏览器缓存"(扫过空) | `:221-226` 条件 | ✅ | — | — | — |
| 删除走 `FileTrashService.moveToTrash`（可撤回/入台账） | `:689-693` `clean` → `moveToTrash` | ✅ | 经闸门，见 §2③ | — | — |
| 失败回执 `MMFailurePanel(browser.failures)` | `MMOptimizer.swift:240`（P35b 现读重指，此前写 `:192-194`） | ✅ | 同 §2②；橙底同上一条，组件自带 | ~~中(待核)~~ 无 | §3 I1 已关闭 |

### 1.4 系统状态 tab（status）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 进页签即 `.task refresh()`（自带检测） | `:265` `.task { await diagnostics.refresh() }` | ✅ | — | — | — |
| 检测中 checks 空 → 整页仅居中 ProgressView，无假数据 | `:260-264` `overlay` ProgressView | ✅ | — | — | — |
| 三行：内存/磁盘/废纸篓 | `:797-851` `SystemDiagnostics.measure` | ✅ | — | — | — |
| 内存 value="已用/总量"，压力>85% 转"谨慎"，否则"安全" | `:811-819`；`:816` risk | ✅ | — | — | — |
| 内存 `used==nil` → "—" + note"vm_statistics64 没读数…显示 —。" | `:802-803`；`:814` DashboardText | ✅ | 读不到≠0，与稿一致 | — | — |
| 内存 swap 失败 → note"交换空间读数不可用（sysctl vm.swapusage 失败），显示 —。" | `:808-809` | ✅ | 稿注"本稿未画第三档"——代码有第三档 | — | — |
| 磁盘读不到卷 → "—" + note"未能读取卷信息（容量键未返回），不显示 0。" | `:831-835` else 分支 | ✅ | — | — | — |
| 废纸篓用 `directoryBytes` 而非 `trashBytes`（后者把没量到折 0） | `:837-848` 注释 + `directoryBytes` | ✅ | 稿注"nil→值'—'"——代码 `map(MMFormat.bytes) ?? placeholder` | — | — |
| 废纸篓 >5GB 转"谨慎"，否则"只读"；**永无清空按钮** | `:845` risk；`:844` note"只带你过去，不代你清空" | ✅ | 与稿一致 | — | — |
| 没量到行徽章一律"只读"(灰+锁)，不给绿"安全" | `:816/:833/:845` 各 nil 分支 `risk:.readOnly`；`SystemCheckRow` `MMBadge(risk:)` | ✅ | — | — | — |
| 行动作："查看"跳 monitor/disk、"打开"访达 ~/.Trash、行尾圆形刷新 | `:873-881` destination/ revealPath/ onRefresh | ✅ | — | — | — |
| 副标题"上次检测 yyyy-MM-dd HH:mm"是唯一来源 | `:772` `updatedAt`；`:52` 绑定页头 | ✅ | — | — | — |

### 1.5 开发工具 tab（devtools，P4.3）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 六行：Go模块/Go构建/Cargo/Homebrew/npm/pip | `DevToolCacheAudit.swift:116-130` specs | ✅ | — | — | — |
| 存在且非空才列、装没装在不在多大三档独立 | `:135-141` presence/size；`liveEntries` `:171-184` 仅 stat | ✅ | 三档绝不合并（见 devtool-owner-commands.md 测量诚实档） | — | — |
| 大小 nil → "—"（非 0 B） | `DevToolCacheView.swift:126` `entry.bytes.map(MMFormat.bytes) ?? "—"` | ✅ | 与稿一致 | — | — |
| 定位来源徽章两档："按 X 定位" / "按默认位置 · 未向工具求证"+问号 | `DevToolCacheView.swift:129-130` `MMBadge(rootSource.badgeText, systemImage: defaultPath?"questionmark.circle":nil)`；`Audit:21-26` badgeText | ✅ | 环境变量校验（绝对路径/不含../不含换行）`Audit:78-85` | — | — |
| 动作仅"拷贝 owner 命令"+"显示"；**pip 无拷贝按钮**(ownerCommand=nil) | `DevToolCacheView.swift:132-136` `if let command`；`Audit:128` pip command=nil | ✅ | 与稿"pip 只剩显示"一致 | — | — |
| 徽章优先级：没装 > 目录状态（"未安装"盖"位置不存在"） | `Audit:200-207` `presenceBadge` 先 `!toolInstalled` | ✅ | — | — | — |
| caveat 橙(caution) 只给"没装"与"读不动"；"目录不存在"保持灰 | `DevToolCacheView.swift:152-156` `caveatTint` | ✅ | 与稿"全橙会把六行都染成告警"一致 | — | — |
| 本屏无 MMActionBar，页脚一句 info.circle 说明 | `DevToolCacheView.swift:65-75` footnote | ✅ | — | — | — |
| **零删除入口、零 spawn**：copy 仅 `NSPasteboard`，refresh 仅 stat 探测 | `DevToolCacheView.swift:44-50` copy；`Audit:88-96` `toolPath` 仅 `isExecutableFile`；`:171-184` presence 仅 `fileExists/isReadableFile` | ✅ | 不执行第三方二进制，满足 P4.3"只报不执行" | — | — |
| "上次盘点"(DevToolCacheModel.updatedAt) 当前 UI 未展示 | `DevToolCacheView.swift:28` 赋值但 `DevToolCacheView` 不显示 | ⚠️ | 稿自注"已知未接上，不是稿子漏画"——非差异，记录 | 低 | 记录 |
| 08e 推演档（未安装/读不到两行）为代码推演非实机 | `08-optimizer.html:673` 自注 | ⚠️ | 需 owner 命令失败态 fixture 才能真机核对，见 §5/§6 | 低 | 见 §6 |

---

## 2. 安全口径复核（核心交付 · 三条）

### ②-① 候选列表是否与 DeletionGuard 闸门打架

- **两条删除链全部经单一闸口**：重复文件 `moveToTrash`（`MMOptimizer.swift:436-451`，删除调用 `:439` `FileTrashService.shared.moveToTrash`）；浏览器 `clean`（`BrowserCacheModel` `:689-693`，`:690` 同一入口）；撤回 `:461-462`（`:462` `FileTrashService.shared.undo`）。**P35b 现读重指，这一处不是"漂移"而是"基线就错"**：本行此前写的是 352-371/583-587 那一段，而 HEAD 上那两段是夹具 switch 与 `scanIfNeeded`，跟删除无关；全仓也没有 `BrowserCacheView` 这个类型（行视图叫 `BrowserCacheRowView`，不含删除）。重指工具按 HEAD 内容搬行号，只会把一个本来就错的锚点搬到另一个错行——工具能修位移，修不了引用起点，所以这一族只能靠 `grep moveToTrash|undo` 现读逐条钉。
- **候选来源**：重复文件候选 = `Documents/Downloads/Desktop` 内被勾选的重复**文件**（`scopes` `:308-311`，选择来自 `DuplicateGroup.files`）；浏览器候选 = `~/Library/Caches/{Google/Chrome, com.apple.Safari, Firefox, Microsoft Edge}`（`BrowserCacheProbe.collect` `:617-625`，四条候选目录逐条写在 `:621-624`）。
- **与三层口径的关系**：
  1. 系统域 `/System /usr /bin /sbin /Library /etc /var/db /var/root`（`DeletionGuard.swift:25-28`）：浏览器缓存在 `~/Library/Caches`（**用户 home 的 Library，不是 `/Library`**），不被子树挡；重复文件在用户三目录内，亦不触发。无冲突。
  2. 凭证/活数据子树（`.ssh/.gnupg/...`，`:39-47`）：客观上一层也不会出现在 optimizer 候选里；即便将来误入，闸门会拦。
  3. 六个用户目录"**目录本身挡、内容放**"（`:55-57`）：重复文件选中项是目录**内**的文件（如 `/Users/lee/Documents/工作/项目复盘.pdf`），闸门精确匹配"目录本身"不会误拦内容删除——这正是闸门设计意图，与 optimizer "组内必须留一份"的业务约束（判定 `:430-434`、勾选入口 `:424-427` 里 `:426` 那一支直接拒绝勾"保留项"，行呈现 `.disabled` `:569` + `MMBadge("需保留")` `:581`）**两层各司其职、无打架**。
- **冲突判定结论**：设计应被闸门拦的 PROTECTED 项（误把 `~/Documents` 目录本身塞进选择、或意外 `/System` 软链）按设计会被 `DeletionGuard` 拦下，实现也确实交给了闸门——**无"该拦没拦"的漏判，也无"该放被误拦"**。① **无冲突，无实现该改**。

### ②-② PROTECTED 拒绝态是否走 shield/caution 分档

- 实现两处失败回执都用共享 `MMUI.MMFailurePanel`：重复文件 `MMOptimizer.swift:166-168` 传 `summary:nil`；浏览器 `:240` 默认 `summary:nil`。（**P35b 现读重指**，本行此前写的 `:118-122`/`:192-194` 是 2026-10-04 那次读的行号，那次之后这一段就被 P34b 的第五 tab 插入顶下来了。）
- 该组件（已核 `MMDesign.swift:672-785`）：
  - 恒定渲染 `MMBadge("N 项失败", tint:.caution)`（`:724`，**不受 summary 是否 nil 影响**）→ 与 08d 画的"2 项失败"琥珀徽章一致；
  - 逐条按 `code=="PROTECTED"` 渲染 `exclamationmark.shield` + `MMColor.caution`（图标 `:739`、颜色 `:741`），非 PROTECTED（errno）走 `xmark.circle.fill`+`destructive`（红，同一行的三目）——**主动拒绝 vs 系统挡住的图标/颜色分档**与组件注释（`:737-738`）一致；
  - 每条显示 `path + message + code`（path `:743-746`、message `:747-752`、code `:755-757`），`>4` 条折叠"另有 N 项失败"（逐条只渲染 `prefix(4)` `:735`，折叠行 `:760-764`）。
- 这与 MMCleaner 借 `MM_FAILURE_FIXTURE=protected` 渲染的"琥珀色盾牌 + 原因 + 错误码"是**同一个组件、同一套分档**（`docs/analysis/deletion-guard.md §6` 已证）。
- **结论：② 达标**。optimizer 通过复用共享面板获得与 MMCleaner 一致的 shield/caution 分档表达，无分档缺失、无需单独再写。
- ~~⚠️ 唯一存疑：面板**容器橙底**在 `MMFailurePanel` body 未见显式 `.background`~~ **这条是本文件 §2 与 §3 I1 不同步留下的尾巴，P35b 现读清账**：橙底就在组件自己身上——`MMDesign.swift:783` 的 `.background(MMColor.soft(MMColor.caution, 0.10))`，自组件创建那一个提交（`e5634d3`）起就有，判据与来路见 §3 I1。**②-② 三条全部达标，本 §2 无存疑项。**

### ②-③ 有无绕过 FileTrashService 的直接删除路径

- 全模块检索（`grep removeItem|trashItem|\brm\b|moveToTrash|FileTrashService` 于 `Packages/MMOptimizer`）：
  - 产品代码删除动作仅 **2 处** `moveToTrash`（`MMOptimizer.swift:439`、`:690`）+ **1 处** `undo`（`:462`），全部走 `FileTrashService`（可撤回、入台账）。**P36 现读重指**：本行此前写 `:356`/`:584`/`:374`，那是 2026-10-04 那一读的坐标；今天这三行分别落在 `isScanning = false`、行视图的 `.foregroundStyle` 和 `func scan()` 上——**与删除无关**。本文件开头 ③ 那条（`:439`/`:690`/`:462`）与 §2 ②-① 那一行早就是对的，**这一格是同一件事在同一份文档里的两处读数不一致**，两处现在对齐。
  - **无任何** `FileManager.default.removeItem` / `trashItem` / shell `rm` 直接删除调用。
  - 唯一命中的 `removeItem` 在 `MMOptimizer/Tests/MMOptimizerTests/DashboardMetricsTests.swift:178`，仅清理该测试自己的 `/tmp` 夹具（符合 `README §4`「钩子只认 /tmp 之下」），**不是产品路径**。
- devtools tab **零删除入口**（`DevToolCacheView` 仅有"拷贝命令"= `NSPasteboard.general` 写 `MMOptimizer` 之外无第二处，`DevToolCacheView.swift:46`，按钮在 `:133`；与"显示"= 访达揭示。本行此前写 `:27-33`，那段是模型侧的 `refresh`/`refreshIfNeeded`，不含写盘也不含粘贴板）；`refresh` 经 `Task.detached` 调 `DevToolCacheAuditor.liveEntries`，其 `toolProbe` 仅 `isExecutableFile`（stat，不执行）、`presenceProbe` 仅 `fileExists`/`isReadableFile`（`DevToolCacheAudit.swift:171-184`）——**全链路零 spawn、零写盘**，满足 `docs/analysis/devtool-owner-commands.md`「只报位置和 owner 命令，不执行任何第三方二进制」。
- **结论：③ 无越界 bug**。未发现任何绕过 `FileTrashService` 闸门的直接删除路径。

---

## 3. 实现该改（0 硬项 + 1 待核 → **待核已于 P6.5b 结清：缺陷从未存在**）

1. ~~**【中·⚠️待真机测量】I1 · 失败回执容器橙底缺失风险**~~ **✅ 已关闭（复核 2026-10-04）——实现没有这个缺陷，本条从未成立**
   `MMFailurePanel`（当时记作 `MMDesign` 第 631-680 行，旧树坐标）的 `body` 只做 `padding`、未显式设置 `warning-soft` 背景；设计 08d / `05-states.html` 的失败回执均为橙 10% 底。MMCleaner 的 `MM_FAILURE_FIXTURE=protected` 实机图（deletion-guard.md §6）显示"琥珀色盾牌"面板，其橙底可能来自 `05-states` 的容器而非组件自身。
   → 待真机核对：若 optimizer 直接放置 `MMFailurePanel` 缺橙底，则改 `MMFailurePanel` 补 `.background(MMColor.warningSoft)` 或在 `MMOptimizer` 两处调用外加橙底容器。**归实现该改 / 两边都改待核**，不擅自改共享组件（违反红线 3）。
   **核对结果（不用截图也能定，因为它是个读漏）**：`MMFailurePanel` 的 body 一直自带橙底——
   `.background(MMColor.soft(MMColor.caution, 0.10))` 在 **`MMDesign.swift:783`**（**P35b 现读重指**：组件结构体 `MMDesign.swift:672`，body `:716-785`，
   下一个结构体 `MMItemRow` 从 `:807` 起；本行此前记 670/714-783/801，是 2026-10-04 那一次的读，之后被后续轮次顶漂）。`git log -S'soft(MMColor.caution, 0.10)' -- MMDesign.swift` 的最早一条是
   **`e5634d3`（2026-09-29，`feat(cleaner): 清理页改为风险分组表…`）——即创建这个组件的那一个提交**，
   所以它不是"后来补上的"，是**生下来就有**。本条之所以立案，是因为对照时把 body 的行范围截在 `:674`
   （组件当时的真实末尾在 :678 之后），`.background`  modifier 正好落在截断处外面。**教训写进 §0 的方法栏**：
   判"组件缺某个修饰符"必须读到 body 的收尾大括号，不能按估计范围截。
   **顺带结掉 §5 #5 里挂着的那半句**：PROTECTED 分档的实机排版仍未拍照（需要跑 `MM_OPTIMIZER_FIXTURE=protected`），
   但"橙底会不会缺"这个疑问已经不需要真机裁定了。
   **一处仍然成立、但要换个归属**：这个面板是**通栏条**形态（`.frame(maxWidth:.infinity, alignment:.leading)` +
   `.overlay(alignment:.top){Divider()}`，`MMDesign.swift:782-784`），而 `05-states` 画的是**带边框圆角卡**。
   这与 `fidelity-cleaner.md` §2 I5 是同一件事（共享组件形态），归协调层，不属 optimizer。

> 其余对照项均为一致或设计稿侧问题，无"实现写错"硬项。

## 4. 设计稿该改（3 低）

1. **【低】S1 · 侧栏占位数字不一致**：08 稿侧栏尾部写"系统清理 2.4 GB / 应用卸载 46"，而同模块 08e 已改成"1.27 GB"，且与全站实际值不符。属 `README §2` S2 已归的全站占位问题，optimizer 稿沿用旧值，应随全站侧栏 footer 组件重画一并修正。〔**P38f 现读：这条作废**——占位串在 `0c61fbf` 那一轮就没了，判据与逐行号见 §1 表格「侧栏 '系统优化' active + 其余模块项」那一行；同一轮还把侧栏 footer 组件（`tokens.css:286`）装进了本稿的两块 artboard（`:171`、`:247`）。本条剩下来的只有"08e/08f 那两处尾数是哪一天扫出来的"这种溯源问题，不再是画法缺陷。〕
2. **【低】S2 · 浏览器"移到废纸篓"按钮图标**：08c 用 `#i-box`（box 占位），实现用 SF `trash`（`MMOptimizer.swift:724`）。稿图标为占位，应改为 `trash` 或注明以实现的 SF 符号为准。
3. **【低】S3 · 08e 推演档标注**：08e 下半"未安装/读不到"两行稿子自注"按代码推演，非实机照片"——这是诚实标注不是 diff；但其文案（"读不动这个位置…""PATH 里没找到 npm…"）需在真机补充 owner 命令失败态 fixture 后核对（见 §6）。

## 5. 没能验证到的部分（逐条写明缺什么，不写"应该没问题"）

以下状态**只在代码里读到分支**，本环境无头、未运行 App、未截图，且模块**只有 `MM_OPEN_TAB` 一个入口钩子**（无内容/状态注入），故全部未能真机构造：

> **复核 2026-10-04 对本表的读法提示**：括号里那句"只有 `MM_OPEN_TAB`"是**写下当天的事实**，今天已不成立
> （`MM_OPTIMIZER_FIXTURE` @`969e548`）。所以 #1、#3、#4、#5、#6、#7 的"需要什么才能验"那一列**已经具备**，
> 这六行现在的正确状态是「**能力就绪、尚未取证**」——下一次跑一个 `p6x-optimizer-capture.sh` 就能一次结掉六行。
> 仍缺能力的是 **#2**（扫描中态要 HOLD 语义，`MM_MONITOR_HOLD` 那套还没有 optimizer 版本）和
> **#8/#9/#10**（跨 tab 运行态、纯像素项、阶段枚举在 `DuplicateScanner`）。**不要把整表当"验不了"重读一遍。**
>
> **P6.6 已跑（2026-10-04，本轮）**：`Scripts/p66-optimizer-capture.sh` → `docs/verification/p66-optimizer/`
> 12 张图 + 12 份日志。**#1/#3/#4/#5/#6/#7 六行全部结掉**，且 **#2 不需要 HOLD 钩子也拍到了**
> （真实 SHA-256 扫描本身就慢，3 秒即定格在骨架态），所以"仍缺能力"那句现在只剩 #8/#9/#10。
> ⚠️ 这一轮真正的产出不是那六张图，而是**跑图跑出来的一个缺陷**：夹具在四个 tab 里有三个从未生效过，
> 详见 §6 #5 的"跑一遍才知道"那段。


| # | 未验证项 | 为什么验不了 | 需要什么才能验 |
| --- | --- | --- | --- |
| 1 | 重复文件扫描结果态（08b：分组卡 / caveat 横幅 / 需保留禁用） | 依赖真实 SHA-256 全文件比对结果，不可控且无 fixture | `MM_OPTIMIZER_FIXTURE=duplicates:<组数>` 注入确定分组 |
| 2 | 重复文件扫描中态（08c 左：进度条百分比/不确定型、6 骨架、停止按钮） | `onAppear` 后 `Task` 通常瞬间返回 | 延迟/冻结扫描的钩子（参照 `MM_MONITOR_HOLD`） |
| 3 | 浏览器缓存真实列表（08c 右：四浏览器 + "测量中"末位） | `BrowserCacheProbe.collect` 结果依赖本机目录，无注入 | `MM_OPTIMIZER_FIXTURE=browser:<fixture>` |
| 4 | 浏览器空列表两档（"正在统计…"/"没有发现…"） | 同 3，且空列表触发条件不可控 | 同上 |
| 5 | 失败回执 PROTECTED 分档实机排版（08d 底部 + I1 容器橙底） | 需真实删除触发 `DeletionGuard` 拒绝，而合成点击被红线禁止 | 复用 `MM_FAILURE_FIXTURE=protected` 思路，或 `MM_OPTIMIZER_FIXTURE=protected` 注入 `TrashFailure(code:"PROTECTED")` |
| 6 | 系统状态"全只读"三行态（08d 右） | 需 `host_statistics64`/卷读取/废纸篓同时失败，本机不会 | `MM_OPTIMIZER_FIXTURE=status:allReadOnly` |
| 7 | devtools "未安装/读不到"两档（08e 推演档） | 本机只出现"位置不存在/在用"，owner 命令失败态不可构造 | `MM_OPTIMIZER_FIXTURE=devtools:<未安装\|读不到>` |
| 8 | 页头副标题"上次检测 …"是否真在默认首屏缺失、在 status 后补出 | 跨 tab 状态依赖运行 | 按 pid 抓窗逐 tab 核对（禁止合成事件） |
| 9 | 分段页签居中几何、各卡 44pt 行高、徽章像素 | 纯像素项，本环境无截图 | 真机截图 + 像素取证（参照 fidelity-monitor §0） |
| 10 | `MMScanProgress` 阶段原文与"已处理 N 项"逐字 | 阶段枚举在 `DuplicateScanner`（不在本模块四文件） | 读 `DuplicateScanner.stage` rawValue 或真机截图 |

**取证结果（P6.6，2026-10-04，`docs/verification/p66-optimizer/`）**

| # | 结论 | 照片 | 图上读到什么 |
| --- | --- | --- | --- |
| 1 | ✅ 已验 | `02-optimizer-duplicates-groups` | 「4 组 · 12 个文件内容完全相同 · 每组保留一份后可释放 21 MB」+ 每行「谨慎」徽章 + 底栏「已选 0 项」 |
| 2 | ✅ 已验，**且不需要 HOLD 钩子** | `01-optimizer-duplicates-scanning` | 无夹具启动 3 秒即定格：「正在按内容比对，未完成前不会给出结果。」+「停止」+ 6 条骨架。真实扫描本身就够慢 |
| 3 | ✅ 已验 | `07-optimizer-browser-rows` | 三行 `/tmp/mm-optimizer-fixture/{Safari,Chrome,Unknown}`，末位 size=nil 那行显示「测量中」，抬头「3 个缓存目录 · 合计 224 MB (1 个目录没读到，未计入)」 |
| 4 | ✅ 已验（两档都拍到） | `07` / `08-optimizer-browser-empty` | 有列表态与「没有发现可清理的浏览器缓存」空态，两张不同图 |
| 5 | ✅ 已验 | `04-optimizer-duplicates-protected` | 底部通栏「1 项失败 / `/Users/example/Documents（夹具值）` / 位于系统目录之下，本应用不删系统域内容。/ PROTECTED / 忽略」；`MM_WINDOW_SIZE=1320x1000` 下不用滚动 |
| 6 | ✅ 已验 | `09-optimizer-status-all-readonly` | 三行全部「—」+「只读」，各带自己的降级理由（`vm_statistics64 没读数`／`容量键未返回，不显示 0`／`清空废纸篓会同时丢掉撤回入口`） |
| 7 | ✅ 已验（两档） | `10-…-not-installed` / `11-…-unreadable` | 「Go 模块缓存（夹具值） 未安装 / PATH 里没找到 go…」与「npm 缓存（夹具值） 读不到 / 读不动这个位置，所以大小和状态都不知道」，两档 size 都是「—」 |
| 8 | ❌ 仍未验 | — | 跨 tab 运行态，本轮每张图只开一个 tab，页头副标题只在 optimizer 首屏出现过 |
| 9 | ⏳ 部分 | — | 本轮只量了磁盘页的像素项（见 `fidelity-disk.md` §2 I9/I11）；optimizer 的分段页签居中与各卡 44pt 行高仍未量 |
| 10 | ❌ 仍未验 | — | 阶段枚举在 `DuplicateScanner`，`01` 那张只拍到"未完成前不给结果"这一句 |

外加两张不是"状态"的图：`03-optimizer-duplicates-caveat`（新档位 `caveat:unreadable:N` / `caveat:dataless:N`，横幅原文「部分文件没能参与判定 / 2 个文件读取失败，未参与判定；1 个仅有云端占位的文件已跳过。」）、
`12-optimizer-fixture-invalid-voided`（守卫档：喂 `devtools:notinstal` 少一个 l，日志里是
「MM_OPTIMIZER_FIXTURE 含非法取值（devtools:notinstal），整个钩子已忽略」，照片退回真实态而不是半套夹具）。

**已验证的部分**（与上表相对，避免把整页写成"没验过"）：四 tab 的状态机分支、文案常量、空态两档条件、keepRequired 硬约束、`MMFormat.bytes(nil)="测量中"`、`MMFailurePanel` 的 PROTECTED shield/caution 分档与"N 项失败"徽章（代码已核）、删除全经 `FileTrashService` 闸门、devtools 零 spawn 零写盘（代码已核）。**P6.6 之后这一句要升级**：上表 ✅ 的七行不再只是"代码里读到分支"，而是有实机照片的；仍未验的只有 #8/#10 与 #9 的一半。

## 6. 提请协调者

> **复核 2026-10-04**：四条里 **#1、#2、#4 已经结清**（分别是钩子已落地、疑点经代码核对不存在、矩阵已同步），
> 只剩 **#3 的稿侧三小改** 和 **新升出来的一条 #5（取证照跑）**。原文照留，结论追加在每条后面。
> **P6.6 之后**：#5 已结（并且顺带修了一个"夹具从未生效"的缺陷，见该条），#3 里的 08e 核对已结，
> #4 因为新增档位**又开了一次**（矩阵刚同步完就漂了）。这一节现在真正剩下的只有稿侧两小改（S1 侧栏占位数字、S2 图标）
> 和 #2 遗留的那个形态题（通栏条 vs 带边框卡，归协调层）。〔**P38f**：两小改里只剩 **S2 图标**那一条——`08-optimizer.html:419/425/431/438` 现在仍是 `#i-box`，实现是 SF `trash`；S1 侧栏占位数字由 `0c61fbf` 作废，判据见 §4 第 1 条。〕

1. **补 `MM_OPTIMIZER_FIXTURE` 统一夹具入口**（呼应 `hook-ledger.md §4.2`）。当前 optimizer 只有 `MM_OPEN_TAB`，四 tab 内的空/失败/超大列表/PROTECTED 拒绝态均无注入路径。建议档位（纯数值/状态注入，不读 `/tmp`、不写盘、不 spawn，参照 `MM_MONITOR_FIXTURE`）：
   - `duplicates:<组数>`：注入确定重复分组（覆盖 08b）；
   - `duplicates:empty` / `duplicates:scannedEmpty`：两档空列表；
   - `browser:<fixture>`、`status:allReadOnly`、`devtools:<未安装|读不到>`、`protected`：覆盖 §5 #1–7。
   **本审计不擅自加钩子**（红线 3：共享层/钩子改动归协调者）。
   **✅ 已落地（`969e548`，2026-09-30）**：`Packages/MMOptimizer/Sources/MMOptimizer/OptimizerFixtureHooks.swift`
   就是这个建议的成品，档位与建议**逐条对得上**（`browser:` 落成 `rows`/`empty` 两档；建议里的"超大列表"由
   `duplicates:<N>` 的 N 承担）。合成组走真实 `DuplicateGroup` 构造器、路径是 `/tmp/mm-optimizer-fixture/dup-i/copy-j.bin`，
   一眼可辨是夹具（`:166-176`）。**P36 现读重指**：这一格此前写"是 `/tmp` 下 `com.example` 命名"并钉 `:106-110`——**措辞与坐标一起错**：`com.example.*` 是**别的模块**夹具的命名规矩（`MonitorFixtureHooks.swift:271`、`TCCAuthorization.swift:251` 都用它），优化器这一族用的是 `/tmp/mm-optimizer-fixture/…`（`:172` 那一行），照别的模块的规矩写这一页就写成了假话。**§5 #2 是唯一没被它覆盖的**，代码注释里也留了话
   （`:21-23`：「#2（扫描中态）**不需要钩子**：真实 SHA-256 比对本来就慢……所以这里没有 HOLD 档位——别照着旧注释再补一个」）。
   **P6.6 追加（2026-10-04）**：档位又多了一组 `caveat:unreadable:N` / `caveat:dataless:N`（§5 表下第 03 档照片要的就是它），
   并加了一条不变量——**`caveat` 必须与 `duplicates:<N>` 同给**，否则整个钩子作废：
   给一张"没有结果"的列表配一句"有些文件没参与判定"，照片本身自相矛盾。
   那句"扫描中态 #2 需要 HOLD"的注释**已按实测改掉**（P6.6 第 01 档证明不需要），别照旧注释补 HOLD 档。
2. **I1 容器橙底待真机裁定**：请协调者在真机截图后确认 `MMFailurePanel` 在 optimizer 两处是否缺橙底；若缺，决定改 `MMFailurePanel`（共享组件，影响全站）还是在 optimizer 调用外加容器——此改动越共享层，按红线 3 由协调者落地。
   **✅ 已裁定，不需要截图**：橙底一直在组件里（`MMDesign.swift:783`，自 `e5634d3` 创建该组件起），见 §3 I1。
   **这一条剩下的部分换个名字继续开着**：面板形态是通栏条还是带边框卡（与 `fidelity-cleaner.md` §2 I5 同一件事），
   那是形态题，不是缺不缺底色。
3. **S1/S2/S3 设计稿侧修正**：侧栏占位数字（随全站侧栏 footer 组件重画）、浏览器删除按钮图标（box→trash）、08e 推演档在补 fixture 后核对——均属设计稿侧，不在本模块实现范围。
   **仍开着（复核 2026-10-04）**。其中"08e 推演档核对"的前置条件已具备（`devtools:notInstalled|unreadable` 两档就是为它加的），
   可与 §5 #3/#4/#6/#7 并成同一次截图跑。侧栏占位数字属 `0c61fbf`（十张稿统一侧栏 footer 组件）那一轮，optimizer 稿是否已换需要稿侧目视确认一次。**P38f 已现读确认：换了**——不必目视，`08-optimizer.html:171` 与 `:247` 两块 artboard 用的就是 `tokens.css:286` 的 `.sidebar-footer`，占位尾数也不在了（判据见 §1 表格与 §4 第 1 条）。
   **P6.6：08e 那一半已结**（`10`/`11` 两张真机图，两档文案与稿子推演一致：`未安装` 档说"PATH 里没找到 go，位置是按默认规则算出来的"，
   `读不到` 档说"读不动这个位置，所以大小和状态都不知道"，两档 size 都是「—」而不是 0）。
   S1（侧栏占位数字）与 S2（图标）仍在稿侧，本轮没碰设计稿。〔**P38f 更正这一句**：两条里只剩 **S2（图标）**——S1 由 `0c61fbf` 落地，本稿那两块侧栏就是那一轮换的。〕
4. **`README §2` 矩阵**：optimizer 行目前钩子列 `MM_OPEN_TAB` 一项，待 #1 落地后同步补 `MM_OPTIMIZER_FIXTURE`（参照 hook-ledger 对 monitor 的同类补正）。
   **✅ 已同步**：`docs/design-system/README.md:43` 的 mmoptimizer 行列了 `MM_OPEN_TAB` 与
   `MM_OPTIMIZER_FIXTURE`（含九个档位名），与实现的 `OptimizerFixture.parse` 一致。
   **P6.6 又漂了一次**：新增 `caveat:unreadable:N` / `caveat:dataless:N` 两个档位（外加"`caveat` 必须与
   `duplicates:<N>` 同给"这条约束），矩阵里的"九个"已按实现改成十个——**这条本身就是"矩阵会随档位漂移"的第二次实例**，
   第一次是 hook-ledger §4.2 记的 monitor。
5. **（P6.5b 新增）optimizer 夹具一次取证都没跑**：`grep -r MM_OPTIMIZER_FIXTURE Scripts/` → 0 命中，
   `docs/verification/` 下也没有 optimizer 夹具目录（只有 `p4-light-dark/light-optimizer.jpg`、
   `dark-optimizer.jpg` 与 `p4-min-window/*-optimizer.jpg` 三张非夹具图）。
   → 建议下一轮补 `Scripts/p6x-optimizer-capture.sh`（照 `p65-swap-capture.sh` 的形状：
   pid→windowid→`screencapture -o -x -l`，按 `MM_OPEN_TAB` 分四档，一次跑完 §5 #1/#3/#4/#5/#6/#7），
   **不要**为"扫描中态"临时造合成点击——红线禁的正是那个。
   **✅ 已跑完（P6.6，2026-10-04）**：`Scripts/p66-optimizer-capture.sh` 十二档 → `docs/verification/p66-optimizer/`。
   这一条的真正价值不在那十二张图，而在**跑图跑出来的缺陷**：
   - **第一次跑出来的照片是假的**。`browser:rows` 与 `browser:empty` 两张**逐字节相同**（md5 `aa6c478a…`），
     `devtools:notInstalled` 与 `devtools:unreadable` 也相同（`13a3ac85…`），`status:allReadOnly` 拍到的是
     真实读数（16.41 GB / 25.77 GB + 「安全」徽章）。也就是说 `MM_OPTIMIZER_FIXTURE` 自 `969e548` 落地以来，
     **四个 tab 里有三个从未生效过**，而它一直在"已具备能力"那一栏里被引用。
   - **成因**：`applyFixtureIfNeeded()` 先 `await` 每个模型的真实扫描再上夹具，而重复文件那档要做全文件
     SHA-256，慢的时候把后面所有档的注入全挡住了；另外三个 tab 的视图级 `.task`
     （`MMOptimizer.swift:243` 浏览器、`:265` 系统状态、`DevToolCacheView.swift:84` 开发工具——**P35b 现读重指**：2026-10-04 那一读记的是 239/261，当时是对的，之后被 P34b 的第五 tab 插入顶漂；本轮的重指工具只会照 HEAD 那一行的内容往下搬，而它搬的是"这一轮改过的位移"，罩不住"上一轮就漂了的 3 行"，所以这一族改按 `grep -n "\.task"` 现读钉死）本来就在并行起真实扫描。
   - **修法（两步，缺一不可）**：① 四档夹具**先同步落完**，再只对"没给夹具"的那档起真实扫描；
     ② 四个模型各加 `private var fixturePinned`，在扫描入口**和 `await` 之后**都检查，
     在途的真实结果整批丢弃。只做①不够——`.task` 仍会与夹具抢，最后落地的真实数据会把夹具覆盖掉，
     照片看着像夹具、其实是真实数据，正是"半生效夹具 = 假通过"那道铁律的另一种犯法。
   - **回归锁**：`OptimizerFixtureHookTests.swift`（11 条 parse/形状，补上"optimizer 是唯一没有 parse 单测的夹具"这个
     约定缺口）+ `OptimizerFixturePinTests`（3 条，直接测"夹具先落、真实扫描后到"这个顺序）。
     `swift test --package-path Packages/MMOptimizer` → 54 tests / 0 failures。
   - **重跑后**：12 张图 `md5 -q *.png | sort | uniq -d` → **0 个重复**。
   → 协调层可复核的一点：`fixturePinned` 这套"夹具优先、真实结果丢弃"的写法，
     monitor / guardian 两个夹具钩子有没有同样的竞态（它们的视图级 `.task` 形状类似）。本轮没查那两个包。

---

## 7. P34b 追加：第五个 tab `preferences`（稿 ↔ 实现 ↔ 实拍）

> 判定侧的规格与量尺在 `docs/analysis/optimizer-corrupt-preferences.md`（P34a 审计 + §14 落地记录），
> 本节只做**设计稿 ↔ 实现 ↔ 照片**三层对照，不重述判据。
> 证据族：`docs/verification/p34b-prefs/`（7 张照片 + 7 份同名日志 + 2 份形状量尺 + 4 份排障探针 + 九包结论）。
> 脚本：`Scripts/p34b-prefs-capture.sh`（实拍）、`Scripts/p34b-prefs-scan-probe.sh`（判据形状与截断形状）。

### 7.1 结构与文案对照（08f ↔ 实现）

| 稿内条目 | 实现出处 | 一致? | 备注 |
| --- | --- | --- | --- |
| 第五个分段页签 `preferences` | `MMOptimizer.swift:270`（`case duplicates, browser, status, devtools, preferences`）、`:41`（`MM_OPEN_TAB`） | ✅ | 稿侧页签条改了一处 CSS：`.seg` 的 340 px 是 SwiftUI `.frame(maxWidth:340)` 的**上限**而非定宽，五 tab 时按内容收缩（实测 334 pt），原先写死 `width:100%` 会让每个标签折成两行 |
| 页头一句「检查过 N 个偏好文件…」 | `PreferencesAudit.swift:355-364`（`headline`），视图 `PreferencesView.swift:53`/`:85-87` | ✅ | **N 的口径是"检查过"不是"找到了"**：`inspectedCount = rows.count`（`PreferencesAudit.swift:125`）。截断态那句接「就到了时间预算，剩下的 K 个没看」，K 由 `notInspectedCount = max(0, foundFiles - rows.count)`（`PreferencesAudit.swift:135`）给，而 `PreferencesAudit.swift:258` 的预算检查在**每个文件之前**，所以 K 里不含读到一半的那个。**P36 现读复核对齐**：这三处原先是裸写 `:125`/`:135`/`:258`，按本表"裸写续写上一格文件名"的规矩会读成 `PreferencesView.swift`——**内容在 Audit 不在 View**（View 的那三行是 `}`、`ForEach`、空位），坐标数字恰好撞对了，指的文件是错的，所以这里把文件名写全。 |
| 栏一「读不出来或空的那些」+ `exclamationmark.triangle` + caution | `PreferencesCopy.badSection`（`PreferencesAudit.swift:330`）、`PreferencesView.swift:120-121` | ✅ | |
| 栏二「这一族我们没看到」+ `eye.slash` + 中性色，**独立成栏** | `PreferencesAudit.swift:331`、`PreferencesView.swift:129-130`、行图标 `:228` | ✅ | 这条是 P34a §9 A 档写死的判据（"读不到"不许与"损坏"共用图标），实拍与稿都分开 |
| 栏二那句说明 | `unreadableNote(n)`（`PreferencesAudit.swift:335-337`）「系统对 n 个文件拒绝读取。这不代表它们坏了，也不代表它们没坏。」 | ✅ | **没把权限位写进文案**：P34a 在本机量到"属主是你、mode 0600 却仍被拒"，把它写成每台都成立的断言就是假话 |
| 每行：文件名 / 路径 / 体积 / 修改时间 / 「显示」 | `PreferenceFileRow`（`PreferencesView.swift:180`，「显示」`:217`） | ✅ | `bytes == nil`（连体积都读不到）渲染「—」而不是 0，档 03 有一行专门拍这个 |
| 建议进 `caveat` 而非单行 `reason` | `PreferencesCopy.advice`（`PreferencesAudit.swift:341-352`） | ✅ | 口径同 `DevToolCacheAudit`：`reason` 会被截断，`advice` 换行不截 |
| 脚注「这一屏不删、不改…」 | `PreferencesCopy.footnote`（`:366-367`），空态挂在 `.overlay` 里（见 §7.3） | ✅ | |
| 「根不是字典」不列行、只在脚注提一句 | `nonDictRootNote(c)`（`:370-372`） | ✅ | 档 02 有一行 `.parsed(root:"array")` 专门拍这句话出现 |
| 整根读不到时的横幅 | `skippedRootsNote`（`:375-377`）+ `MMPermissionBanner` | ⚠️ | **本机这一栏从未非空，所以一张照片都没拍到**。它是"不许把没看渲染成干净"的唯一出口，下一轮若要拍得造钩子或造文件系统状态 |

### 7.2 七张实拍（`MM_OPEN_TAB=preferences`，全部 1400x900 除注明）

| # | 档 | 文件 | 图上读到什么 |
| --- | --- | --- | --- |
| 01 | 真实态 | `01-prefs-real-gui` | 页头「检查过 625 个偏好文件；其中 11 个我们没能读。」+ 栏二 11 行（第 10–11 行在折下，稿侧不替它们编数字）；栏一为空，整屏没有"损坏"行 |
| 02 | `prefs:broken` | `02-prefs-fixture-broken` | 栏一两行（0 字节 / ByHost 里那份 282 字节读不成）+ 底部脚注出现「另有 1 个文件解析成功但根不是字典…」 |
| 03 | `prefs:unreadable` | `03-prefs-fixture-unreadable` | 栏二两行 + 说明句，其中一行体积是「—」（`bytes: nil`） |
| 04 | `prefs:empty` | `04-prefs-fixture-empty` | 空态「没有发现读不出来的偏好文件」+ 底部脚注（这一档是 §7.3 那个缺陷的现场） |
| 05 | `prefs:partial` | `05-prefs-fixture-partial` | 页头「检查过 2 个偏好文件就到了时间预算，剩下的 10416 个没看。」+ 空态那句换成**「时间预算内没有发现」**——截断那一趟没资格说"没有" |
| 06 | 真实态窄窗 | `06-prefs-narrow-window`（1000x760） | 五 tab 页签不折行、页头不断句、两栏行不重叠 |
| 07 | 非法值作废 | `07-prefs-fixture-invalid-voided` | 日志里只有一句判据：`MM_OPTIMIZER_FIXTURE 含非法取值（prefs:brokenn），整个钩子已忽略`；照片回到真实态（与 01 **逐字节相同**，这是设计如此，不是夹具没生效） |

同源核对：7 份日志的 `# digest:` 都是 `tree=69eddb6+8ba05eda app=69eddb6+8ba05eda`（照片与工作树、与产物 plist 三者当场同源）；
两份形状量尺（`scan-shape.log`、`scale-shape.log`）同一把哈希。
`md5 -q *.png | sort | uniq -c` → **只有一对重复**（01↔07，判据如上），其余五张两两不同。
九包：`docs/verification/p34b-prefs/run-all-tests.log:11`「合计：737 个测试，0 个失败，1 个跳过」（P38c 前此处只写了文件名、没带目录，而门禁口径下这一族有 16 份同后缀日志，裸写不自证是哪一篇）。

### 7.3 实拍抓出来的一个缺陷（只有真机截图能抓到）

空态那一屏在 1400x900 下**页头和页脚同时被裁出画面**。探针（`MM_PROBE_WINDOW=1`，零重编译）量到
`AppKitPlatformViewHost` 高 **1183 pt @Y-115**，而窗口 content 高是 900：
`MMEmptyState` 自带 `.frame(maxWidth:.infinity, maxHeight:.infinity)`（`MMDesign.swift:476`），
它的"居中"就是靠把自己撑满实现的；把那句 `fixedSize(horizontal:false, vertical:true)` 的长脚注当**同一个 VStack 的兄弟**挂上去，
SwiftUI 算整组理想尺寸时按极窄宽度折行，高度炸到 1183。

修法：脚注改挂 `.overlay(alignment: .bottom)`（`PreferencesView.swift:107-113`）——overlay 不参与基准视图的理想尺寸。
对照证据是同一张空态的**没有兄弟**那版（浏览器缓存页）探针读 `900@Y0`，见
`00-probe-prefs-empty-before-fix.log`（炸）↔ `00-probe-browser-empty-control.log`（对照）↔ `00-probe-prefs-empty-after-fix.log`（修后 900@Y0）。

**这条要进验收口径**：本站"空态 + 底部脚注"这个形状以后别再用 VStack 兄弟挂，
而且**它不可能被单测发现**——单测跑的是判据与文案，画面上少半屏只有照片知道。

### 7.4 这一屏的"拍不到"验收项（P34a §9 那句在这里落地）

真机上栏一**是空的**（本机 625 个里 0 个坏，`scan-shape.log:36`「解析成功 614 / 读不到 11 / 坏的那一栏 0 / 根不是字典 0」）。
所以：

- **"有内容"那几屏只能由夹具出**（档 02/03/05），真机档永远拍不到栏一；
- 真机档能拍的只有「检查过 625 个 + 其中 11 个没能读」这一屏，它同时是**唯一非零的异常栏**；
- 反过来，档 04 那张"空"必须是**夹具造的空**（2 个健康文件），不是真机首屏的另一种写法——
  两者在照片上应该长一样，这正是要分开拍的原因。

### 7.5 第五屏仍未验的

1. `skippedRoots` 横幅（§7.1 最后一行）——本机整根始终可读，从未非空，无照片。
2. 栏一在**真机**上的排版——需要一台真有损坏偏好文件的机器（当前只有一台 Mac mini，P34a §11.5）。
3. 「读不到」这一栏的语义到底是"系统不给看"还是"我们可以选择不去看"（P34a §11.2）——
   给了 FDA 的进程能不能读到那些文件，本轮仍未量，因为它要手动在系统设置里点，而合成点击是红线。
4. 主人名映射（C 档）未做，所以每行只有文件名与路径，没有"这条属于哪个 app"。
