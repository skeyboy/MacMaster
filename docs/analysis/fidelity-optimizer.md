# 08 系统优化 · 设计稿 ↔ 实现 逐元素对照（fidelity-optimizer）

> **结论先行**：08 稿四个 tab（duplicates 重复文件 / browser 浏览器缓存 / status 系统状态 /
> devtools 开发工具缓存）与实现在**结构、文案、状态机**三层高度一致——页头副标题来源、
> 分段页签 maxWidth 340、四 tab 的空/扫描中/结果/失败态、`keepRequired` 硬约束、devtools
> "只报不执行"与 PROTECTED 分档都照设计落地。逐元素对照 **45 项**，需归属的差异很少：
> **实现该改 0 硬项**（1 项 ⚠️中 待真机测量：失败回执容器橙底）、**设计稿该改 3 低**
> （侧栏占位数字、浏览器删除按钮图标、08e 推演档标注）。受"只有 `MM_OPEN_TAB` 一个钩子"限制，
> 四 tab 内的空/失败/超大列表/PROTECTED 拒绝态暂无注入路径，逐条列在 §5。
>
> **安全口径复核（核心交付）三条结论**：
> ① 候选列表（Documents/Downloads/Desktop 内重复文件、~/Library/Caches 下浏览器缓存）
> **全部经 `FileTrashService` → `DeletionGuard` 单一闸口**，与闸门三层口径无冲突，
> 未发现"设计该拦却被放行"的漏判；
> ② PROTECTED 拒绝态**复用共享 `MMUI.MMFailurePanel`**（与 MMCleaner 的
> `MM_FAILURE_FIXTURE=protected` 同一组件），shield/caution 分档表达完全一致，达标；
> ③ **无绕过 `FileTrashService` 的直接删除路径**——全模块删除仅 2 处 `moveToTrash`
> （`MMOptimizer.swift:355`、`:583`）+ 1 处 `undo`，无任何 `FileManager.removeItem` /
> `trashItem` / `rm`；devtools tab 零删除、零 spawn（仅 `NSPasteboard` 拷贝 + stat 探测）。
> 无越界 bug。

## 0. 对照方法（先说清楚哪些是量出来的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmoptimizer/08-optimizer.html`（5 个 artboard：08 首屏未扫描 / 08b 扫描结果 / 08c 扫描中+浏览器 / 08d 系统状态+回执 / 08e 开发工具） |
| 实现 | `Packages/MMOptimizer/Sources/MMOptimizer/`：`MMOptimizer.swift`、`DevToolCacheView.swift`、`DashboardMetrics.swift`、`DevToolCacheAudit.swift` |
| 渲染 | 本环境**无头、未运行 App、未截图**，不编像素数字；几何/像素项一律标 `⚠️待真机测量`，只从代码＋HTML+tokens 推导 |
| 复用基准 | 共享组件 `MMFailurePanel`/`MMBadge`/`MMFormat` 取自 `Packages/MMUI/Sources/MMUI/MMDesign.swift`；闸门取自 `Packages/MMCore/Sources/MMCore/DeletionGuard.swift`、`FileTrashService.swift` |
| 可用钩子 | **只有 `MM_OPEN_TAB=duplicates|browser|status|devtools`**（`MMOptimizer.swift:42`）。`grep processInfo.environment Packages/MMOptimizer/` → 仅此一处；四 tab 内的空/失败/超大列表态无注入路径（见 `docs/analysis/hook-ledger.md` §4 已提"建议补 MM_OPTIMIZER_FIXTURE"） |
| 硬约束 | 全程未发合成事件、未运行 App、未截图、未改 `Packages/`/`tokens.css`/`screen.css`/`icons.js`；未做任何 git 操作；未碰 `/tmp` 之外路径。本稿只新增本文件 |

代码侧已实证的口径（来自共享文件，非本模块自造）：

- `MMFormat.bytes(_:UInt64?)`（`MMDesign.swift:113-117`）：`nil → "测量中"`，`<1000 → "N 字节"`，否则 `byte.string`。→ 浏览器 nil 体积渲染"测量中"与 08c 一致，非"0 字节"。
- `MMFailurePanel`（`MMDesign.swift:614-674`）：恒定渲染 `MMBadge("N 项失败", tint:.caution)`（:633，无论 `summary` 是否 nil）；逐条按 `code=="PROTECTED"` 走 `exclamationmark.shield`+`MMColor.caution`（:645-647），否则 `xmark.circle.fill`+`destructive`；显示 `path + message + code`（:649-663）；`>4` 条折叠"另有 N 项失败"（:666-670）。
- `FileTrashService.moveToTrash`（`FileTrashService.swift:35-69`）：循环开头即 `DeletionGuard.rejection(for:)`（:43），PROTECTED → `TrashFailure(code:"PROTECTED")`（:44），逐条上报、不静默跳过；执行用 `trashItem`（可撤回、入台账）。
- `DeletionGuard`（`DeletionGuard.swift:25-57`）：系统域子树 / 凭证与活数据子树 / 六个用户目录"**目录本身挡、内容放**"。

---

## 1. 逐元素对照表（四 tab 全覆盖）

严重度定义：**高** = 用户会读到错误结论（把未知当已知 / 把失败当正常 / 绕过删除闸门）；
**中** = 视觉或语义明显跑偏但不产生错误结论；**低** = 像素级偏差、占位数据、口径注脚。
`⚠️` = 需真机截图才能判定，本环境未测。

### 1.1 页头 / 页签 / 侧栏（四 tab 共用）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「系统优化」 | `MMOptimizer.swift:52` | ✅ | — | — | — |
| 副标题绑定 `diagnostics.updatedAt`，默认首屏只有标题一行 | `:52` `SystemDiagnosticsModel.updatedAt` 初始 nil，仅 status `.task` 后赋值（`:218,:661`） | ✅ | 08 稿注"默认首屏无副标题，不是漏画"——代码逻辑一致；⚠️ 默认首屏是否真无副标题需真机 | 低 | ⚠️待真机测量 |
| 分段页签（重复文件/浏览器缓存/系统状态/开发工具），maxWidth 340 居中 | `:54-61` `.frame(maxWidth:340)` `.padding(.horizontal, .lg)` | ✅ | 居中几何 ⚠️ 像素级未测 | 低 | ⚠️待真机测量 |
| 默认 tab=duplicates；`MM_OPEN_TAB` 可切 | `:41-42` | ✅ | — | — | — |
| 侧栏 "系统优化" active + 其余模块项 | 壳 `MainWindow` 渲染（非本模块） | ⚠️ | 08 稿侧栏尾部写 "系统清理 2.4 GB / 应用卸载 46"，08e 已改 "1.27 GB"；占位数字全站问题 | 低 | 设计稿该改 S1 |
| 顶部「查找重复文件」按钮（magnifyingglass，bordered） | `:90-96` | ✅ | 图标 SF `magnifyingglass` 与稿一致 | — | — |

### 1.2 重复文件 tab（duplicates）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 顶行口径「按文件内容比对，不看文件名。」(未扫档) | `:275` headline `guard hasScanned else` 分支 | ✅ | — | — | — |
| 范围行硬编码 Documents/Downloads/Desktop | `:256-259` `scopes`；`:281-286` `scannedScope` 拼名 | ✅ | 与稿"逐字照抄"一致 | — | — |
| 空态两档：未扫="还未开始检测" / 扫过没找到="没有发现内容完全相同的文件" | `:137-141` `MMEmptyState` 标题条件 | ✅ | 绝不混用，与稿一致 | — | — |
| 空态 detail=scannedScope（未扫不追加"本次比对 N 个候选"） | `:140` `detail: duplicates.scannedScope` | ✅ | 稿注"未扫时不追加"——代码 `scannedScope` 在 `lastReport==nil` 时只返回 base（`:284`） | — | — |
| 扫描中 headline="正在按内容比对，未完成前不会给出结果。" | `:273` | ✅ | — | — | — |
| 「停止」按钮 + 「重新扫描」置灰 | `:86-89` 停止；`:97` 重新扫描 disabled | ✅ | — | — | — |
| 进度 `MMScanProgress`：action=阶段原文、estimatedRemaining 恒 nil、fraction | `:102-110` 传 `estimatedRemaining:nil`、`progress.fraction` | ✅（结构） | 阶段枚举 `progress.stage.rawValue` 的原文（归类候选/抽样比对/逐字节校验）来自 `DuplicateScanner`，**不在本模块文件内**；"已处理 N 项" 文案在 `MMScanProgress` 内——⚠️ 待真机核对逐字 | 低 | ⚠️待真机测量 |
| 扫描中且未出分组 → 6 条骨架 | `:130-135` `ForEach(0..<6) MMSkeletonRow` | ✅ | 数量 6 与稿一致 | — | — |
| caveat 横幅「部分文件没能参与判定」+ 读失败/云端占位两档用"；"连接 | `:112-114` `MMPermissionBanner`；`:288-293` `caveatText` | ✅ | 文案拼接与稿一致 | — | — |
| 分组卡头：chevron + doc.on.doc(橙) + "N 个文件内容相同" + "size×n" + 徽章"谨慎"(caution) + 右端蓝"可释放 X" | `:431-449` `DuplicateGroupRow` | ✅ | `MMBadge(risk:.caution)`(:444)、`可释放`=`wastedSpace`(:445) | — | — |
| "可释放 X"= size×(个数−1) | `DuplicateGroup.wastedSpace`（按 `:278` 口径 `totalWaste`）；08b 858=286×3 | ✅ | 数学一致 | — | — |
| "需保留"徽章仅出现在组内唯一未勾且其余全勾项；其复选框禁用 | `:339-349` `isKeepRequired`；`:480` `.disabled(keepRequired)`；`:492` `MMBadge("需保留")` | ✅ | 硬约束与稿"一组必须留一份"一致 | — | — |
| 修改时间 RelativeDateTimeFormatter 短格式 | `:493` `MMFormat.relative` | ✅（代码分支） | 实际格式 ⚠️ 待真机 | 低 | ⚠️待真机测量 |
| 行尾 folder 图标="在访达中显示"(help) | `:500-506` `MMReveal.open`+`.help` | ✅ | — | — | — |
| 操作栏随勾选：「已选 N 项 · X」+ 提示句 | `:380-398` `MMActionBar` | ✅ | 未勾="未勾选的文件不会被改动。"，已勾="被勾选的文件会先移入废纸篓，可撤回。"(:385) | — | — |
| 「移到废纸篓」置灰(disabled) 当未勾选 | `:397` `.disabled(selection.isEmpty)` | ✅ | — | — | — |
| 撤回 toast 8s 自动消失、不传 secondsRemaining（无倒计时数字） | `:399-414` `MMUndoToast` + `Task.sleep(8)` | ✅ | 与稿"没有倒计时数字"一致 | — | — |
| 失败回执 `MMFailurePanel`（PROTECTED 分档） | `:118-122` `MMFailurePanel(summary:nil, trashFailures)` | ✅（结构） | 见 §2② 与 §3 I1（容器橙底 ⚠️） | 中(待核) | 见 §3 I1 |

### 1.3 浏览器缓存 tab（browser）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 进页签即 `scanIfNeeded`（无"请先点扫描"空态） | `:196` `.task { await browser.scanIfNeeded() }` | ✅ | 稿"量一次不到一秒，比摆空态有用" | — | — |
| 只探测 ~/Library/Caches 下 Safari/Chrome/Firefox/Edge 四目录，存在且非空才列 | `:531-536` candidates；`:539` `fileExists`；`:544` `filter { size==nil \|\| size>0 }` | ✅ | "非空"判定=`size==nil||size>0`，排除 0 字节 | — | — |
| 顶行仅"重新扫描"（扫描中置灰），**无停止按钮** | `:162-168` 无停止；`:168` disabled | ✅ | 与稿"与重复文件页签不同，没有停止按钮"一致 | — | — |
| headline "N 个缓存目录 · 合计 X（M 个目录没读到，未计入）" | `:556-565` | ✅ | 合计只加 `measured`（`:559-560`），未量到的追"未计入" | — | — |
| 每行动作仅"位置"(访达显示)+"移到废纸篓"(小按钮红字) | `:606` `MMRevealButton`；`:614-621` 删除按钮 tint red | ✅ | 图标：稿用 `#i-box`，实现用 SF `trash`（见 S2） | 低 | 设计稿该改 S2 |
| size=nil → "测量中"，help="目录存在，但体积没能读出来；不是 0 字节。" | `:609` `MMFormat.bytes(item.size)`（nil→"测量中"，已核）；`:613` `.help(...)` | ✅ | 文案与稿逐字一致 | — | — |
| "测量中"行排末位（nil 按 0 参与排序），绝不显 0 | `:544-545` `sorted { ($0.size ?? 0) > ($1.size ?? 0) }` | ✅ | 与稿"排末位但绝不混同 0 字节"一致 | — | — |
| 不碰历史记录/密码/Cookie（空态 detail 原文） | `:178` detail 文案 | ✅ | — | — | — |
| 空列表两档："正在统计缓存体积…"(未扫) / "没有发现可清理的浏览器缓存"(扫过空) | `:174-179` 条件 | ✅ | — | — | — |
| 删除走 `FileTrashService.moveToTrash`（可撤回/入台账） | `:582-586` `clean` → `moveToTrash` | ✅ | 经闸门，见 §2③ | — | — |
| 失败回执 `MMFailurePanel(browser.failures)` | `:192-194` | ✅ | 同 §2② | 中(待核) | 见 §3 I1 |

### 1.4 系统状态 tab（status）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 进页签即 `.task refresh()`（自带检测） | `:218` `.task { await diagnostics.refresh() }` | ✅ | — | — | — |
| 检测中 checks 空 → 整页仅居中 ProgressView，无假数据 | `:213-217` `overlay` ProgressView | ✅ | — | — | — |
| 三行：内存/磁盘/废纸篓 | `:666-720` `SystemDiagnostics.measure` | ✅ | — | — | — |
| 内存 value="已用/总量"，压力>85% 转"谨慎"，否则"安全" | `:680-688`；`:685` risk | ✅ | — | — | — |
| 内存 `used==nil` → "—" + note"vm_statistics64 没读数…显示 —。" | `:671-672`；`:683` DashboardText | ✅ | 读不到≠0，与稿一致 | — | — |
| 内存 swap 失败 → note"交换空间读数不可用（sysctl vm.swapusage 失败），显示 —。" | `:677-679` | ✅ | 稿注"本稿未画第三档"——代码有第三档 | — | — |
| 磁盘读不到卷 → "—" + note"未能读取卷信息（容量键未返回），不显示 0。" | `:700-704` else 分支 | ✅ | — | — | — |
| 废纸篓用 `directoryBytes` 而非 `trashBytes`（后者把没量到折 0） | `:706-717` 注释 + `directoryBytes` | ✅ | 稿注"nil→值'—'"——代码 `map(MMFormat.bytes) ?? placeholder` | — | — |
| 废纸篓 >5GB 转"谨慎"，否则"只读"；**永无清空按钮** | `:714` risk；`:713` note"只带你过去，不代你清空" | ✅ | 与稿一致 | — | — |
| 没量到行徽章一律"只读"(灰+锁)，不给绿"安全" | `:685/:702/:714` 各 nil 分支 `risk:.readOnly`；`SystemCheckRow` `MMBadge(risk:)` | ✅ | — | — | — |
| 行动作："查看"跳 monitor/disk、"打开"访达 ~/.Trash、行尾圆形刷新 | `:742-752` destination/ revealPath/ onRefresh | ✅ | — | — | — |
| 副标题"上次检测 yyyy-MM-dd HH:mm"是唯一来源 | `:661` `updatedAt`；`:52` 绑定页头 | ✅ | — | — | — |

### 1.5 开发工具 tab（devtools，P4.3）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 六行：Go模块/Go构建/Cargo/Homebrew/npm/pip | `DevToolCacheAudit.swift:116-130` specs | ✅ | — | — | — |
| 存在且非空才列、装没装在不在多大三档独立 | `:135-141` presence/size；`liveEntries` `:171-184` 仅 stat | ✅ | 三档绝不合并（见 devtool-owner-commands.md 测量诚实档） | — | — |
| 大小 nil → "—"（非 0 B） | `DevToolCacheView.swift:109` `entry.bytes.map(MMFormat.bytes) ?? "—"` | ✅ | 与稿一致 | — | — |
| 定位来源徽章两档："按 X 定位" / "按默认位置 · 未向工具求证"+问号 | `DevToolCacheView.swift:112-113` `MMBadge(rootSource.badgeText, systemImage: defaultPath?"questionmark.circle":nil)`；`Audit:21-26` badgeText | ✅ | 环境变量校验（绝对路径/不含../不含换行）`Audit:78-85` | — | — |
| 动作仅"拷贝 owner 命令"+"显示"；**pip 无拷贝按钮**(ownerCommand=nil) | `DevToolCacheView.swift:115-122` `if let command`；`Audit:128` pip command=nil | ✅ | 与稿"pip 只剩显示"一致 | — | — |
| 徽章优先级：没装 > 目录状态（"未安装"盖"位置不存在"） | `Audit:200-207` `presenceBadge` 先 `!toolInstalled` | ✅ | — | — | — |
| caveat 橙(caution) 只给"没装"与"读不动"；"目录不存在"保持灰 | `DevToolCacheView.swift:135-139` `caveatTint` | ✅ | 与稿"全橙会把六行都染成告警"一致 | — | — |
| 本屏无 MMActionBar，页脚一句 info.circle 说明 | `DevToolCacheView.swift:48-58` footnote | ✅ | — | — | — |
| **零删除入口、零 spawn**：copy 仅 `NSPasteboard`，refresh 仅 stat 探测 | `DevToolCacheView.swift:27-33` copy；`Audit:88-96` `toolPath` 仅 `isExecutableFile`；`:171-184` presence 仅 `fileExists/isReadableFile` | ✅ | 不执行第三方二进制，满足 P4.3"只报不执行" | — | — |
| "上次盘点"(DevToolCacheModel.updatedAt) 当前 UI 未展示 | `DevToolCacheView.swift:24` 赋值但 `DevToolCacheView` 不显示 | ⚠️ | 稿自注"已知未接上，不是稿子漏画"——非差异，记录 | 低 | 记录 |
| 08e 推演档（未安装/读不到两行）为代码推演非实机 | `08-optimizer.html:633` 自注 | ⚠️ | 需 owner 命令失败态 fixture 才能真机核对，见 §5/§6 | 低 | 见 §6 |

---

## 2. 安全口径复核（核心交付 · 三条）

### ②-① 候选列表是否与 DeletionGuard 闸门打架

- **两条删除链全部经单一闸口**：重复文件 `moveToTrash`（`MMOptimizer.swift:351-370`，删除调用 `:355` `FileTrashService.shared.moveToTrash`）；浏览器 `clean`（`BrowserCacheView` `:582-586`，`:583` 同一入口）；撤回 `:373` `FileTrashService.shared.undo`。
- **候选来源**：重复文件候选 = `Documents/Downloads/Desktop` 内被勾选的重复**文件**（`scopes` `:256-259`，选择来自 `DuplicateGroup.files`）；浏览器候选 = `~/Library/Caches/{Google/Chrome, com.apple.Safari, Firefox, Microsoft Edge}`（`BrowserCacheProbe.collect` `:531-536`）。
- **与三层口径的关系**：
  1. 系统域 `/System /usr /bin /sbin /Library /etc /var/db /var/root`（`DeletionGuard.swift:25-28`）：浏览器缓存在 `~/Library/Caches`（**用户 home 的 Library，不是 `/Library`**），不被子树挡；重复文件在用户三目录内，亦不触发。无冲突。
  2. 凭证/活数据子树（`.ssh/.gnupg/...`，`:39-47`）：客观上一层也不会出现在 optimizer 候选里；即便将来误入，闸门会拦。
  3. 六个用户目录"**目录本身挡、内容放**"（`:55-57`）：重复文件选中项是目录**内**的文件（如 `/Users/lee/Documents/工作/项目复盘.pdf`），闸门精确匹配"目录本身"不会误拦内容删除——这正是闸门设计意图，与 optimizer "组内必须留一份"的业务约束（`:345-349`、`:480`）**两层各司其职、无打架**。
- **冲突判定结论**：设计应被闸门拦的 PROTECTED 项（误把 `~/Documents` 目录本身塞进选择、或意外 `/System` 软链）按设计会被 `DeletionGuard` 拦下，实现也确实交给了闸门——**无"该拦没拦"的漏判，也无"该放被误拦"**。① **无冲突，无实现该改**。

### ②-② PROTECTED 拒绝态是否走 shield/caution 分档

- 实现两处失败回执都用共享 `MMUI.MMFailurePanel`：重复文件 `:118-122` 传 `summary:nil`；浏览器 `:192-194` 默认 `summary:nil`。
- 该组件（已核 `MMDesign.swift:614-674`）：
  - 恒定渲染 `MMBadge("N 项失败", tint:.caution)`（`:633`，**不受 summary 是否 nil 影响**）→ 与 08d 画的"2 项失败"琥珀徽章一致；
  - 逐条按 `code=="PROTECTED"` 渲染 `exclamationmark.shield` + `MMColor.caution`（`:645-647`），非 PROTECTED（errno）走 `xmark.circle.fill`+`destructive`（红）——**主动拒绝 vs 系统挡住的图标/颜色分档**与组件注释（`:643-644`）一致；
  - 每条显示 `path + message + code`（`:649-663`），`>4` 条折叠"另有 N 项失败"（`:666-670`）。
- 这与 MMCleaner 借 `MM_FAILURE_FIXTURE=protected` 渲染的"琥珀色盾牌 + 原因 + 错误码"是**同一个组件、同一套分档**（`docs/analysis/deletion-guard.md §6` 已证）。
- **结论：② 达标**。optimizer 通过复用共享面板获得与 MMCleaner 一致的 shield/caution 分档表达，无分档缺失、无需单独再写。
- ⚠️ 唯一存疑：面板**容器橙底**（`08-optimizer.html` `.failp` 用 `var(--c-warning-soft)`、`05-states` 亦橙底）在 `MMFailurePanel` body（`:625-674`）未见显式 `.background`——若橙底来自 `05-states` 的容器而非组件自身，则 optimizer 直接放置同样缺橙底。此项归 §3 I1，**待真机测量**后方可定"实现该改"。

### ②-③ 有无绕过 FileTrashService 的直接删除路径

- 全模块检索（`grep removeItem|trashItem|\brm\b|moveToTrash|FileTrashService` 于 `Packages/MMOptimizer`）：
  - 产品代码删除动作仅 **2 处** `moveToTrash`（`MMOptimizer.swift:355`、`:583`）+ **1 处** `undo`（`:373`），全部走 `FileTrashService`（可撤回、入台账）。
  - **无任何** `FileManager.default.removeItem` / `trashItem` / shell `rm` 直接删除调用。
  - 唯一命中的 `removeItem` 在 `MMOptimizer/Tests/MMOptimizerTests/DashboardMetricsTests.swift:163`，仅清理该测试自己的 `/tmp` 夹具（符合 `README §4`「钩子只认 /tmp 之下」），**不是产品路径**。
- devtools tab **零删除入口**（`DevToolCacheView` 仅有"拷贝命令"= `NSPasteboard` 写、`DevToolCacheView.swift:27-33`、与"显示"= 访达揭示）；`refresh` 经 `Task.detached` 调 `DevToolCacheAuditor.liveEntries`，其 `toolProbe` 仅 `isExecutableFile`（stat，不执行）、`presenceProbe` 仅 `fileExists`/`isReadableFile`（`DevToolCacheAudit.swift:171-184`）——**全链路零 spawn、零写盘**，满足 `docs/analysis/devtool-owner-commands.md`「只报位置和 owner 命令，不执行任何第三方二进制」。
- **结论：③ 无越界 bug**。未发现任何绕过 `FileTrashService` 闸门的直接删除路径。

---

## 3. 实现该改（0 硬项 + 1 待核中）

1. **【中·⚠️待真机测量】I1 · 失败回执容器橙底缺失风险**
   `MMFailurePanel`（`MMDesign.swift:625-674`）的 `body` 只做 `padding`、未显式设置 `warning-soft` 背景；设计 08d / `05-states.html` 的失败回执均为橙 10% 底。MMCleaner 的 `MM_FAILURE_FIXTURE=protected` 实机图（deletion-guard.md §6）显示"琥珀色盾牌"面板，其橙底可能来自 `05-states` 的容器而非组件自身。
   → 待真机核对：若 optimizer 直接放置 `MMFailurePanel` 缺橙底，则改 `MMFailurePanel` 补 `.background(MMColor.warningSoft)` 或在 `MMOptimizer` 两处调用外加橙底容器。**归实现该改 / 两边都改待核**，不擅自改共享组件（违反红线 3）。

> 其余对照项均为一致或设计稿侧问题，无"实现写错"硬项。

## 4. 设计稿该改（3 低）

1. **【低】S1 · 侧栏占位数字不一致**：08 稿侧栏尾部写"系统清理 2.4 GB / 应用卸载 46"，而同模块 08e 已改成"1.27 GB"，且与全站实际值不符。属 `README §2` S2 已归的全站占位问题，optimizer 稿沿用旧值，应随全站侧栏 footer 组件重画一并修正。
2. **【低】S2 · 浏览器"移到废纸篓"按钮图标**：08c 用 `#i-box`（box 占位），实现用 SF `trash`（`MMOptimizer.swift:617`）。稿图标为占位，应改为 `trash` 或注明以实现的 SF 符号为准。
3. **【低】S3 · 08e 推演档标注**：08e 下半"未安装/读不到"两行稿子自注"按代码推演，非实机照片"——这是诚实标注不是 diff；但其文案（"读不动这个位置…""PATH 里没找到 npm…"）需在真机补充 owner 命令失败态 fixture 后核对（见 §6）。

## 5. 没能验证到的部分（逐条写明缺什么，不写"应该没问题"）

以下状态**只在代码里读到分支**，本环境无头、未运行 App、未截图，且模块**只有 `MM_OPEN_TAB` 一个入口钩子**（无内容/状态注入），故全部未能真机构造：

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

**已验证的部分**（与上表相对，避免把整页写成"没验过"）：四 tab 的状态机分支、文案常量、空态两档条件、keepRequired 硬约束、`MMFormat.bytes(nil)="测量中"`、`MMFailurePanel` 的 PROTECTED shield/caution 分档与"N 项失败"徽章（代码已核）、删除全经 `FileTrashService` 闸门、devtools 零 spawn 零写盘（代码已核）。

## 6. 提请协调者

1. **补 `MM_OPTIMIZER_FIXTURE` 统一夹具入口**（呼应 `hook-ledger.md §4.2`）。当前 optimizer 只有 `MM_OPEN_TAB`，四 tab 内的空/失败/超大列表/PROTECTED 拒绝态均无注入路径。建议档位（纯数值/状态注入，不读 `/tmp`、不写盘、不 spawn，参照 `MM_MONITOR_FIXTURE`）：
   - `duplicates:<组数>`：注入确定重复分组（覆盖 08b）；
   - `duplicates:empty` / `duplicates:scannedEmpty`：两档空列表；
   - `browser:<fixture>`、`status:allReadOnly`、`devtools:<未安装|读不到>`、`protected`：覆盖 §5 #1–7。
   **本审计不擅自加钩子**（红线 3：共享层/钩子改动归协调者）。
2. **I1 容器橙底待真机裁定**：请协调者在真机截图后确认 `MMFailurePanel` 在 optimizer 两处是否缺橙底；若缺，决定改 `MMFailurePanel`（共享组件，影响全站）还是在 optimizer 调用外加容器——此改动越共享层，按红线 3 由协调者落地。
3. **S1/S2/S3 设计稿侧修正**：侧栏占位数字（随全站侧栏 footer 组件重画）、浏览器删除按钮图标（box→trash）、08e 推演档在补 fixture 后核对——均属设计稿侧，不在本模块实现范围。
4. **`README §2` 矩阵**：optimizer 行目前钩子列 `MM_OPEN_TAB` 一项，待 #1 落地后同步补 `MM_OPTIMIZER_FIXTURE`（参照 hook-ledger 对 monitor 的同类补正）。
