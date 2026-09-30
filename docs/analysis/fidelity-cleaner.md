# 47 系统清理 · 设计稿 ↔ 实现 逐元素对照（fidelity-cleaner）

> **结论先行**：本模块的**语义诚实度是九个模块里做得最足的**——不可访问的路径不计入合计、
> 只读档的体积单列不混进"可释放"、安装包残留区分"签名已核实/仅按名称识别"、体积测不出写"测量中"
> 而不是 0，`MM_FAILURE_FIXTURE` 的拒绝回执内容还真的是 `DeletionGuard` 现场算出来的。这些在
> `fidelity-monitor` 里普遍踩红线的点上，cleaner 基本没踩。
>
> 真正的缺陷只有 **1 条高**，而且是把上面这套诚实性从入口漏掉的一处：**删除失败/被闸门拒绝的条目，
> 仍然会被从分类表里整行删掉**（`cleaned = Set(paths)` 用的是"尝试过的全部路径"而不是"真的搬进废纸篓的
> 那批"），于是**主表面（分类表）把失败当成了已清理**；同一个模块的 `UserFolderCleanView` 用
> `result.operation.files` 做对了，说明这是实现不一致而不是设计天花板。
>
> 其余差异集中在三类：**① 与共享组件的结构差**（只读行丢掉复选框列、行内要素顺序、
> `MMFailurePanel` 比 `05-states` 规格少统计行与页脚）、**② 02/02b 两稿互相打架的结构**
> （02 缺容器三页签、02b 把页签塞进页头同一行、过滤条第 4 项"开发" vs 实现"临时"）、
> **③ 全站骨架层继承项**（侧栏 footer、页底/卡片 token、侧栏尾数占位，与 `fidelity-monitor` 同源）。
>
> **逐元素对照 59 项**，其中 **需归属的差异 23 项**（**高 1 / 中 6 / 低 16**）：
> **实现该改 10 条**（I1–I10）、**设计稿该改 13 条**（S1–S13，其中 S2 为两边都改）。
> **本次环境（无头沙箱）未跑 App、未重新渲染设计稿、未做任何像素取色**：所有"实机像素一致"的判定
> **一律标 `⚠️待真机测量`**，本文的"一致"只指**结构/文案/语义**在代码与 HTML 层面成立。
> 实机侧唯一可引用的入库证据是 `docs/verification/p1.7-deletion-guard/cleaner-refusal-panel.jpg`
> （深色，清理页含权限横幅 + 拒绝回执面板），下文凡引用它都注明是**既有图，非本次新拍**。

## 0. 对照方法（先说清楚哪些是量出来的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmcleaner/02-cleaner.html`（1 屏：缓存清理正常态）、`02b-cleaner-installers.html`（2 个 artboard：用户文件夹+安装包残留正常态 / 确认面板） |
| 设计渲染 | 复用**已入库**的 `02-cleaner.png`、`02b-cleaner-installers.png`（浅色 2x）。**本次未重新渲染**（无头环境，不跑 `render.sh`，不产新图） |
| 实机 | **本次未启动、未截图**（硬约束：禁跑 App / 禁截图）。唯一引用的实机图是既有 `docs/verification/p1.7-deletion-guard/cleaner-refusal-panel.jpg`（深色，`MM_FAILURE_FIXTURE=protected` 预演 + 权限横幅 + 分类表），它是上一阶段入库的证据，不代表本次测量 |
| 像素取证 | **无**。本文不含任何 CoreGraphics 取色数字；凡"实机宽度/高度/颜色"一律 `⚠️待真机测量`，只给代码可推导的 token 值 |
| 可用钩子（README §2，已 `grep` 核对全部命中） | `MM_OPEN_TAB`(`CleanerContainerView.swift:32`)、`MM_CLEANER_FILTER`(`MMCleaner.swift:280`)、`MM_EXPAND_CATEGORIES`(`MMCleaner.swift:148`)、`MM_AUTO_SCAN`(`UserFolderCleanView.swift:112`/`SystemAnalysisView.swift:78`)、`MM_SHOW_CONFIRM`(`MMCleaner.swift:359`/`UserFolderCleanView.swift:116,384`/`SystemAnalysisView.swift:82`)、`MM_INSTALLER_FIXTURE_DIR`(`UserFolderCleanView.swift:120,366`)、`MM_FAILURE_FIXTURE`(`MMCleaner.swift:365`)。**七条全部存在**，故 monitor 那种"13 项完全无法构造"的困境 cleaner 没有 |
| 硬约束 | 全程未 `git`、未跑 `swift build`/`make-app.sh`、未发合成鼠标/滚轮/键盘事件、未改 `Sources/`·`Packages/`·共享层；本次只写本文档一个文件 |

代码层锚点（本文所有"结构成立"判定的依据，单位 CSS px == pt）：

- 容器两级导航：`CleanerContainerView.swift:31-61` —— 顶部 `safeAreaInset` 里 30pt 高的三页签
  segmented `Picker`（`缓存清理/用户文件夹/系统分析`），其下才是各页自己的 `MMPageHeader`。
- 页头：`MMPageHeader`（`MMDesign.swift:238-271`）= `MMMetric.toolbar` 46pt + `contentBackground` + 底部 Divider。
- 过滤条：`MMCleaner.swift:305-325`，`CleanerFilter` 四档 `全部/缓存/日志/临时`（`:856-881`）。
- 分类表：`MMCleaner.swift:425-464` —— 内联卡（`background(MMColor.contentBackground)` + `MMRadius.card` 8 + separator 描边 + `MMGap.lg` 16 内边距），**没有调用 `MMCard`**。
- 表头 26pt / 分组头 30pt / 行 44pt：`MMCleaner.swift:466-481`、`:500-520`、`MMItemRow`（`MMDesign.swift:682-742`，`MMMetric.rowRegular` 44）。
- 动作栏：`MMActionBar`（`MMDesign.swift:280-313`）= `MMMetric.actionBar` 52pt + `cardBackground`。
- 风险三档真源：`MMRisk`（`Packages/MMCore/Sources/MMCore/Risk.swift:9-41`），`groupTitle/groupNote/isDefaultSelected/allowsDeletion`。
- 卡片 token 真源：`MMCard`（`MMDesign.swift:770-786`）= `MMColor.controlBackground`（`windowBackgroundColor`）+ 8pt 圆角 + 16pt 内边距；而本文页内卡用的是 `MMColor.contentBackground`（`textBackgroundColor`）→ 见 I4/S9。
- 拒绝回执预演：`CleanerView.refusalPreview()`（`MMCleaner.swift:883-894`），三条由 `DeletionGuard.rejection(for:)` 现场算出。

## 1. 逐元素对照表

严重度定义：**高** = 用户会读到错误结论（把未知当已知 / 把失败当正常）；
**中** = 视觉或语义明显跑偏，但不产生错误结论；**低** = 像素级偏差、占位数据、口径注脚。

### 1.1 容器级导航（三页签）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 02 稿工具栏：只有一条 4 项 seg（`全部/缓存/日志/开发`） | `CleanerContainerView.swift:45-61` 另有独立的 30pt 三页签行 | ❌ 结构 | **02 稿根本没画容器三页签**；实机（`cleaner-refusal-panel.jpg` 顶部）确有「缓存清理｜用户文件夹｜系统分析」一条，且位于页头**之上**、不在页头里 | **中** | 设计稿该改 S1 |
| 02b 稿工具栏：seg = `缓存清理/用户文件夹/系统分析`，与标题「用户文件夹」**同一行** | 同上 | ⚠️ 半符 | 页签本身逐字对（含 activated 态），但**位置不对**：实机页签是页头之上的独立 30pt 行，稿内画进 46pt 工具栏同一行 | **中** | 设计稿该改 S1 |
| 页签字号/高度/分段样式 | Picker `.segmented` `.fixedSize()`，行高 `frame(height: 30)`，`contentBackground` 底 + 底 Divider | ⚠️ | 稿 `.seg` 在 46pt 工具栏里、chip 高 22；实机是 30pt 独立行。**具体像素差 `⚠️待真机测量`** | 低 | 设计稿该改 S1 |

### 1.2 页头与过滤条（缓存清理页）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「系统清理」 | `MMCleaner.swift:305` | ✅ | 代码逐字一致（页签叫「缓存清理」、页头叫「系统清理」，模块名与页签名不同源，见 I8） | — | — |
| 副标题格式「已扫描 N 类 · 可释放 X · 时间」 | `headerSubtitle` `MMCleaner.swift:834-851` | ✅ 结构 | 实现多出一段「**另有 Y 只读**」（`readOnlyTotal>0` 时），且类数用 `categories.count` | 低 | 设计稿该改 S6 |
| 副标题数值「已扫描 **9 类** · 可释放 **2.42 GB** · **21:15**」 | 同上 | ❌ | 稿内 9/2.42/21:15 均为**占位**：本机实拍副标题为「已扫描 16 类 · 可释放 653.6 MB · 另有 16.3 MB 只读 · 2026-09-30 10:06」；且稿内自相矛盾（表里列了 5+3+2=**10** 行却写"9 类"） | 低 | 设计稿该改 S6 |
| 过滤条 seg：`全部 / 缓存 / 日志 / **开发**` | `CleanerFilter.label` `MMCleaner.swift:864-871` = `全部/缓存/日志/**临时**` | ❌ | 第 4 项文案不一致；实现的 `temp` 映射 `CacheScope.temp`，语义是「临时」不是「开发」 | 低 | 设计稿该改 S3 |
| 「搜索类别」搜索框 | `MMCleaner.swift:315-317`，`TextField.frame(width: 140)` | ✅ | 稿 `width:150px`；宽度差 **10pt `⚠️待真机测量`** | 低 | 记录 |
| 「重新扫描」按钮 + refresh 图标 | `MMCleaner.swift:319-324` `.disabled(model.isScanning)` | ✅ | 一致（实机在扫描时禁用，稿内未画禁用态） | — | — |

### 1.3 权限降级横幅（无权限态）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 「有 N 个位置读不到…未授权的部分不计入合计，也不会显示为 0。」+「打开系统设置」 | `MMCleaner.swift:327-333` → `MMPermissionBanner`（`MMDesign.swift:443-473`） | ⚠️ 未画 | 02 稿**没有这一档**；实机图顶部有（琥珀锁 + 294 个位置读不到 + 打开系统设置）。文案与 `05-states.html` 权限态口径一致 | 低 | 设计稿该改 S10 |

### 1.4 分类表

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 表头列「类别 · 大小 · 风险 · **操作**」 | `tableHeader` `MMCleaner.swift:466-481` | ❌ | 实现最后一列表头是 `Text("")`（空），**没有「操作」列名**；列宽 `大小 minWidth 72 / 风险 44 / 操作 52` vs 稿 `78 / 92 / 60`（**`⚠️待真机测量`**） | 低 | 实现该改 I6 |
| 分组头「可安全清理 N 类 · X」+ 右侧说明 | `groupHeader` `MMCleaner.swift:500-520`；文案真源 `MMRisk` | ✅ | 组名「可安全清理/需谨慎/只读 · 不会修改」与右注三句**逐字一致**（`Risk.swift:22-36`）；`N 类` 与合计按实算 | — | — |
| 分组右注文字 | 同上 `.frame(maxWidth: 280, alignment: .trailing)` + `.lineLimit(1)` | ⚠️ | 实现给右注硬封顶 280pt；最长那句「可能包含登录态或未同步数据，默认不勾选」是否真被截尾**取决于窗口宽度，`⚠️待真机测量`** | 低 | 实现该改 I9 |
| 行结构：勾选 · 图标 · 名称/副标题 · **大小 → 风险徽章 → 操作** | `MMItemRow`（`MMDesign.swift:713-741`）：`勾选 → 图标 → 名称/副标题 → Spacer → 徽章 → accessory → 大小` | ❌ | **大小永远在最右**，徽章/折叠箭头/文件夹都在它左边；稿内大小在徽章**之前**。分类行与安装包行都如此 | **中** | 实现该改 I3 |
| 行内图标配色：安全档 `--c-warning`（橙）/ 谨慎档 secondary（灰）/ 只读 tertiary | `MMItemRow` 用 `risk?.color`（安全=绿 `systemGreen`、谨慎=橙、只读=secondary） | ❌ | 安全档图标实现是**绿**、稿内是**橙**；谨慎档实现是**橙**、稿内是**灰**。且稿内"安全徽章绿 + 图标橙"自身不一致 | 低 | 设计稿该改 S7 |
| 只读行：虚线禁用复选框（`.chk.off-allowed`）+ 锁图标 + 「只读」徽章 | `categoryRows` `MMCleaner.swift:522-546` 传 `isSelectable: category.risk.allowsDeletion` → 只读档 **不渲染 Toggle** | ❌ | 实现**整列删掉复选框**（`MMItemRow` 里 `if isSelectable { Toggle }`），不是画虚线禁用框；后果是只读行的图标列相对可勾选行**左移、列不对齐** | **中** | 实现该改 I2 |
| 只读行操作列 = info 图标 | `categoryRows` 仍按 `subItems` 非空给 `chevron.down/up` + `folder` | ❌ | 只读分类只要 `subItems` 非空就仍带**展开箭头**，稿内只给 info | 低 | 实现该改 I7 |
| 「沙盒容器缓存」大小占位「·」 | `MMCleaner.swift:527` `scannedSize > 0 ? bytes : "—"` | ❌ | 稿内未测用「·」，实现用「—」；且实现把"扫到 0 字节"也画成「—」（与"未测"同形） | 低 | 设计稿该改 S7 |
| 行高 44 / 表头 26 / 分组头 30 / 卡圆角 8 | `MMMetric.rowRegular` 44、`:478` 26、`:518` 30、`MMRadius.card` 8 | ✅ | 与稿内 `.crow min-height:44`、`.hdr 26`、`.gtitle 30`、`--r-md 8` **数值一致**（代码层；实机像素 `⚠️待真机测量`） | — | — |
| 底部注脚「所有删除一律先移入废纸篓…不会静默跳过。」 | `MMCleaner.swift:436-446` | ✅ | 文案逐字一致 | — | — |
| hover 才显现的文件夹按钮 | `MMRowAction`（`MMCleaner.swift:898-917`）图标**常显**，仅 hover 时出底 | ❌ | 稿内 `.crow .op{opacity:0}` 整枚按钮 hover 才现；实现图标一直在 | 低 | 设计稿该改 S7 |

### 1.5 底部操作栏

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 左侧合计「已选 N 类 · X」+ 注脚「未勾选项不会被修改」 | `actionBar` `MMCleaner.swift:640-661`；`MMActionBar` 纵向两行 | ✅ | 结构一致（02 稿也是纵向两行） | — | — |
| 右侧「排除名单 (N)」次按钮 | `MMCleaner.swift:647-648` `.disabled(空)` | ✅ | 一致（稿内无禁用态） | — | — |
| 右侧主按钮「清理已选 N 类」= **蓝色 primary** | `MMCleaner.swift:650-659` `.tint(MMColor.destructive)`（红） | ❌ | 稿内是蓝 `btn primary lg`；实现是**红 destructive**。且 02b 稿与 `05-states` 危险确认用的都是红 | 低 | 设计稿该改 S4 |
| 动作栏高度 52 | `MMMetric.actionBar` 52 | ✅ | 02 稿 52 一致 | — | — |
| 「可释放」口径 | `measuredTotal`（只含 `risk.allowsDeletion` 的类别）`MMCleaner.swift:60-64` | ✅ | 实现不把只读体积算进可释放，符合项目红线 | — | — |

### 1.6 确认面板

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「确认清理选中的项目？」 | `confirmSheet` `MMCleaner.swift:673-725`（缓存页）/ `.alert`（`UserFolderCleanView.swift:83-90`） | ✅ | 逐字一致 | — | — |
| 正文「共 N 项，约 X。选中的内容将移入废纸篓（可撤回），不会永久删除。」 | 同上 | ✅ | 文案一致（02b 稿与实现逐字对上） | — | — |
| 按钮「取消」/「移入废纸篓」 | `.keyboardShortcut(.cancelAction/.defaultAction)`，destructive tint | ✅ | 一致 | — | — |
| 面板承载方式 | 缓存页走 `VStack` `.sheet`（宽 420）；用户文件夹页走系统 `.alert` | ⚠️ | 02b 稿画的是**自定义 alert 版式**（400pt 圆角卡 + 44pt warn 图标）；实现用户文件夹页用的是**系统 `NSAlert`**，与稿内版式不同 | 低 | 设计稿该改 S5b |
| 稿内额外的「清理后 15 秒内可一键撤回」开关 | `MMCleaner.swift:707`，仅缓存页 sheet 有 | ⚠️ | 用户文件夹页/系统分析页的 `.alert` **没有**这个开关 | 低 | 实现该改 I6b |

### 1.7 失败 / 被闸门拒绝回执（MMFailurePanel）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| PROTECTED 行：琥珀盾 + 原因 + 错误码三列 | `MMFailurePanel`（`MMDesign.swift:641-664`）：`failure.code=="PROTECTED"` → `exclamationmark.shield` 琥珀 + 原因 2 行 + 右列 `PROTECTED` | ✅ | 与 `cleaner-refusal-panel.jpg` 实拍一致：三条 PROTECTED，盾牌/原因/码齐全；文案由 `DeletionGuard.rejection` 现场算，非手写 | — | — |
| 顶部摘要「已回收 X GB」（绿） + 「N 项失败」徽章 + 忽略 | `MMCleaner.swift:337-344` 传 `"已回收 \(MMFormat.bytes(model.lastResult?.totalSize))"` | ⚠️ | 实拍图摘要显示「已回收 **测量中**」（夹具下 `lastResult==nil`）；真实删除后才会是「已回收 X GB」 | 低 | 实现该改 I10 |
| 「计划 N · 成功 N · 失败 N · 跳过 N」统计行 | 实现无此行 | ❌ | `05-states.html` 局部失败态明确画了这行；实现只给"已回收 + N 项失败" | **中** | 实现该改 I5 |
| 页脚「复制诊断信息 / 重试失败项 / 完成」 | 实现只有「忽略」 | ❌ | 缺"重试失败项"等补救入口；`05-states` 规格有 | **中** | 实现该改 I5 |
| 面板形态：带边框圆角卡（`05-states`） | 实现是**琥珀底通栏条**（`MMColor.soft(caution,0.10)` + 顶部 Divider，无圆角/边框），贴动作栏上方 | ❌ | 形态不同；影响的是共享组件 | 低 | 实现该改 I5（→ 协调者） |
| 超过 4 条折叠为「另有 N 项失败」 | `MMDesign.swift:641` `failures.prefix(4)` | ✅ | 夹具正好 3 条，全部列出 | — | — |

### 1.8 删除后状态一致性（无稿，代码走查）

| 事项 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 删除后把**失败/被拒**的条目从分类表移除 | `CleanerModel.clean()` `MMCleaner.swift:214-239`：`let cleaned = Set(paths)`（= 尝试过的**全部**路径）→ `subItems.removeAll { cleaned.contains($0.path) }` | ❌ | **失败条目也一并消失**：主表面（分类表）表现成"已清理"，与底部失败面板互相打架。对照 `UserFolderCleanView.swift:532-534` 用的是 `result.operation.files`（只删真的搬走的）→ 同模块两种口径 | **高** | 实现该改 I1 |
| 系统分析页同类问题 | `SystemAnalysisView.swift:324-334`：同样 `cleaned = Set(paths)` → `groups[i].items.removeAll` | ❌ | 同一缺陷的第二个副本 | **高** | 实现该改 I1 |

### 1.9 空 / 加载 / 取消 态（缓存清理页）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 加载态：进度一行 + skeleton，不显示 0 B | `MMCleaner.swift:391-412` → `MMScanProgress` + 5×`MMSkeletonRow` + 取消 | ✅ 结构 | 与 `05-states` 加载态一致；实现**不画「剩余约 00:14」**（`estimatedRemaining: nil`），且用「正在扫描 <类别名>」代替「第 2/5 步」 | 低 | 记录 |
| 空态：标题「没有可清理的内容」+「已检查 N 个类别…」 | `MMCleaner.swift:413-419` | ❌ | 分支条件是 `categories.isEmpty`，此分支 detail 会拼出「**已检查 0 个类别**」；而真正"扫完但都干净"的态**不进这个分支**（会显示一张 `—` 全零的表格）。也就是说空态实际只在**取消于第一类完成前**才命中，标题却断言"没有可清理的内容" | **中** | 实现该改 I4 |
| 取消按钮 | `MMCleaner.swift:407` `cancelScan()` 只置取消标志 | ✅ | 扫描提前结束、`isPartial=true`，副标题补「未完成」、动作栏注脚改口径——诚实 | — | — |

### 1.10 用户文件夹页 + 安装包残留（02b）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 页头「用户文件夹」+「N 个文件夹 · X · …」 | `UserFolderCleanView.swift:60-67,131-139` | ✅ 结构 | 实现副标题按"是否含无权限"追加「· M 个无访问权限」；稿内是「6 个文件夹 · 41.2 GB · 全部默认未选中」（占位） | 低 | 设计稿该改 S8 |
| 文件夹行：勾选 · 图标 · 名称/文件数 · 大小 · 展开 · 文件夹 | `UserFolderSection` `UserFolderCleanView.swift:581-644` | ✅ 结构 | 与稿一致；"默认全部未选中"、无权限档走 `MMBadge("无权限")` | — | — |
| 安装包组头「安装包残留 N 项（M 项签名已核实）」+ 右注 | `installerGroupHeader`/`installerCounter` `UserFolderCleanView.swift:275-302` | ✅ | 逐字一致（含 `尚未嗅探`/`嗅探中…` 两档） | — | — |
| 范围行「扫描范围：… · 只查这些位置本身及其一层子目录…」 | `installerScopeLine`/`installerScopeText` `UserFolderCleanView.swift:306-324` | ⚠️ | 文案口径一致（深度 1 层）；但实现**上下各画一次**（`:237`、`:263`），稿内只画一次 | 低 | 设计稿该改 S10 |
| 安装包行：勾选 · 图标 · 名称/证据 · **签名徽章 → 大小 → 文件夹** | `installerRow` `UserFolderCleanView.swift:335-355` → `MMItemRow`（accessory 放徽章+文件夹，value 最右） | ❌ | 同 I3：大小永远最右，徽章/文件夹在其左；稿内大小在徽章与文件夹**之间** | **中** | 实现该改 I3 |
| 证据两档：绿/蓝「签名已核实」 vs 橙「仅按名称识别」 | `UserFolderCleanView.swift:345-350` `MMBadge`(`informational`/`caution`) | ✅ | 逐字与配色语义一致（橙带问号，不借绿/蓝） | — | — |
| 体积「测量中」（`Whatever.dmg`） | `MMFileScanner/InstallerScanner.swift:37-38` `size: nil` → `MMFormat.bytes(nil)="测量中"` | ✅ | 一致，未测不写 0 | — | — |
| 无权限降级行「N 个位置读不到…本轮没有检查它们」 | `UserFolderCleanView.swift:265-272` | ⚠️ 未画 | 02b 稿无此档 | 低 | 设计稿该改 S10 |
| 动作栏「已选 N 项 · X」+ 红「清理选中」 | `actionBar` `UserFolderCleanView.swift:396-408` | ⚠️ | 稿 02b 把它改成 **46pt 高 + 横向一行合计**；实现是 `MMActionBar` 52pt + 纵向两行 | 低 | 设计稿该改 S5 |
| 用户文件夹页的勾选清理 | `cleanSelected`/`applyCleaned` `UserFolderCleanView.swift:518-569` | ✅ | 失败项**不被**从列表摘掉（整删的重新 `scanFolder` 统计，失败就还在）；安装包用 `moved` 集 → **这一步做对了**，反衬 I1 | — | — |

### 1.11 系统分析页（无稿）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 无设计稿 | `SystemAnalysisView.swift` 全篇；README §1 只列 02/02b 两稿 | ⚠️ | 第三页签「系统分析」**没有设计稿**，只能代码走查：页头「系统级文件分析」、只读项用眼睛图标、安全档徽章由 `SystemItemSafety` 推导 | — | 设计稿该改 S11 |
| 删除后失败项仍被移除 | `SystemAnalysisView.swift:324-334` | ❌ | 同 I1 的副本 | **高** | 实现该改 I1 |

### 1.12 全站骨架层（继承项）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 侧栏 footer = 1px 线 + 平铺「设置」nav-item | 实机图左下是 **`Macintosh HD` + `7%` + 红色容量条 + 带边框「设置」按钮** | ❌ | 与 `fidelity-monitor` S1 同源：02/02b 沿用了 01–06 的错误画法 | **中** | 两边都改 S2 |
| 侧栏尾数「系统清理 2.4 GB」「应用卸载 46」 | 无来源；实机 系统清理尾数随扫描变化（图上为 653.6 MB） | ❌ | 纯占位，见 monitor S2 | 低 | 设计稿该改 S8 |
| 页面底 / 卡片底色 | `tokens.css` 用 `--c-content-bg`（白）；实机页底 = `windowBackgroundColor`、卡 = `textBackgroundColor` | ❌ | 全站性 token 差，见 monitor S3/S4 | 低 | 设计稿该改 S9 |
| 页内卡未复用 `MMCard` | `MMCleaner.swift:458-461` 内联 `contentBackground`+8pt+描边，**不调用 `MMCard`**（后者是 `controlBackground`） | ❌ | 与 monitor I4 同类：同一 App 出现第三种"卡底 token" | **中** | 实现该改 I4（→ 协调者） |
| 侧栏宽 216 / 标题栏 38 | `MMMetric.sidebar` 216、`tokens --titlebar-h` 38 | ⚠️ | 实机 monitor 实测 220 / 52（monitor I10a/I10b），cleaner 继承同一骨架 | 低 | 记录（见 monitor） |

## 2. 实现该改（10 条，按严重度排序）

1. **【高】I1 · 失败条目从分类表/系统分析表里被静默移除 —— 主表面把失败当成已清理**
   `CleanerModel.clean()`（`MMCleaner.swift:224`）用 `let cleaned = Set(paths)`（**尝试过的全部路径**）
   去 `subItems.removeAll`，`SystemAnalysisView.swift:330` 同款。被 `DeletionGuard` 拒绝（PROTECTED）
   或因 EPERM 失败的条目**仍在磁盘上，却从列表消失**，同时 `scannedSize` 被重算成更小——
   主表面一致地宣称"清掉了"。
   → 建议：改成只摘**真的搬走**的那批，口径与同模块已经做对的 `UserFolderCleanView.swift:532`
   （`Set(result.operation.files.map(\.originalPath))`）一致；失败条目留在原行（失败详情仍由
   `MMFailurePanel` 逐条报）。这是"把失败当正常"，正踩本模块自己的红线，判 **高**。
2. **【中】I2 · 只读行的复选框列被整列删掉**（`MMCleaner.swift:530` `isSelectable: category.risk.allowsDeletion`
   + `MMItemRow` 的 `if isSelectable`）
   稿内（`02-cleaner.html:103,107` 与 `05-states.html:100-103`）画的是**虚线禁用框** `.chk.off-allowed`：
   "这是勾选位、但你不能用"。实现直接不给复选框，于是只读行比可勾选行**少一格宽度、图标列左移**，
   同表两段列不齐。
   → 建议：`MMItemRow` 在 `isSelectable==false` 时**保留占位**（画禁用框或至少留 15pt 空槽）——
   这会碰到共享组件 `MMUI`，见 §5 提请协调者。
3. **【中】I3 · 行内要素顺序：大小永远最右**（`MMItemRow` `MMDesign.swift:714-735`）
   稿内两处行（分类行 `02-cleaner.html:67-70`、安装包行 `02b:77-79`）顺序都是
   **名称 → 大小 → 风险徽章 → 操作**；实现是 **名称 → 徽章 → 操作 → 大小**。
   → 建议：二选一——要么 `MMItemRow` 支持"数值列提前"的排布，要么把稿改成与共享行一致。
   因涉及共享组件，倾向**设计稿对齐组件**（见 §3）。
4. **【中】I4 · 空态把"取消/未产出一类"说成"没有可清理的内容"**（`MMCleaner.swift:413-419`）
   分支条件 `model.categories.isEmpty` 只在**取消于第一类完成前**命中，detail 会拼出
   「**已检查 0 个类别**」；而真正"扫完都干净"的态**不**进这里（会显示全零表格）。
   标题却直接断言"没有可清理的内容"。
   → 建议：拆成两档——"扫描被取消/未完成"（标题写"扫描未完成，结果不完整"，给"重新扫描"）
   与"扫完确认无可清理"（给出检查范围与项数，照 `05-states` 空态的口径）；并把
   「已检查 0 个类别」改成不误导的措辞。
5. **【中】I5 · `MMFailurePanel` 比 `05-states` 局部失败规格少两截**（`MMDesign.swift:614-678`）
   缺 **「计划 N · 成功 N · 失败 N · 跳过 N」统计行**，缺 **页脚「重试失败项 / 复制诊断信息」**；
   面板形态也由"带边框圆角卡"变成"琥珀底通栏条"。这是共享组件，见 §5。
6. **【低】I6 · 表头缺「操作」列名**（`MMCleaner.swift:473` `Text("").frame(width: 52)`）——
   稿内 `.hdr` 有「操作」。顺带：实现 `风险 44 / 操作 52` vs 稿 `风险 92 / 操作 60`，**`⚠️待真机测量`**。
   **I6b**：用户文件夹页/系统分析页的确认用系统 `.alert`，没有缓存页 sheet 里的
   「清理后 15 秒内可一键撤回」开关（`MMCleaner.swift:707`）。
7. **【低】I7 · 只读分类仍带展开 chevron**（`MMCleaner.swift:533-537`，只要 `subItems` 非空）——
   稿内只读行只给 info 图标。
8. **【低】I8 · 页头标题与页签名不同源**：页签「缓存清理」而页头「系统清理」
   （`CleanerContainerView.swift:9-11` vs `MMCleaner.swift:305`）。记录，非必要改。
9. **【低】I9 · 分组右注硬封顶 280pt**（`MMCleaner.swift:515`）——最长那句可能被 `.lineLimit(1)` 截尾，
   是否真截**`⚠️待真机测量`**。
10. **【低】I10 · 拒绝回执摘要会拼出「已回收 测量中」**（`MMCleaner.swift:339`）——
    `lastResult==nil` 而 `failures` 非空时（夹具路径目前就是这样）。真实删除后 `lastResult` 有值，
    故只在预演里出现；建议摘要不要依赖另一个来源的 Optional，或对 nil 用"未搬动任何项"这类措辞。

## 3. 设计稿该改（13 条）

1. **【中】S1 · 容器三页签的结构在 02/02b 里对不上实现**：02 稿**没有**三页签；02b 稿把三页签
   画进 46pt 工具栏**与标题同行**。实机是**页头之上独立 30pt 一行**（`cleaner-refusal-panel.jpg` 顶部可核）。
   → 两稿都要重画：补出/挪正「缓存清理｜用户文件夹｜系统分析」这一行。
2. **【中】S2 · 侧栏 footer 全站画错**（与 `fidelity-monitor` S1 同源）：稿内是"分隔线 + 平铺设置"，
   实机是容量行 + 带边框设置按钮。**两边都改**：设计层补一个侧栏 footer 组件，01–07 一起换。
3. **【低】S3 · 过滤条第 4 项「开发」应改「临时」**：实现 `CleanerFilter.temp` 映射 `CacheScope.temp`，
   "开发"在这里没有对应扫描范围。
4. **【低】S4 · 02 稿动作栏主按钮用蓝色 primary 应改 destructive 红**：与 02b、`05-states` 危险确认
   自相矛盾；删除是 destructive 动作。
5. **【低】S5 · 02b 动作栏 46pt + 横向合计应改回 52pt + 纵向两行**：与 `MMActionBar` 一致。
   **S5b**：确认面板 02b 画的是自定义 400pt alert 卡，实机用户文件夹页是系统 `NSAlert`；要么稿改成
   系统 alert 的观感，要么实现改用自定义面板（后者见 §2 I6b）。
6. **【低】S6 · 副标题口径要补只读与类数**：现稿「已扫描 9 类 · 可释放 2.42 GB · 21:15」既与自身
   表格行数（10 行）矛盾，也缺实现已有的「另有 X 只读」。
7. **【低】S7 · 行内图标配色与占位符自相矛盾**：安全档"徽章绿/图标橙"、谨慎档"徽章橙/图标灰"；
   未测占位用「·」。建议统一为"图标跟随风险档色"、未测统一「—」/「测量中」。
8. **【低】S8 · 侧栏尾数占位**（2.4 GB / 46）应改成实机同源的动态值或留空（monitor S2 同源）；
   用户文件夹副标题「6 个文件夹 · 41.2 GB · 全部默认未选中」也是占位。
9. **【低】S9 · 页底/卡片底色 token**（`--c-content-bg` 白 vs 实机 windowBackground）
   与"缺 content-bg / under-page 卡片 token"——全站项，见 monitor S3/S4，cleaner 稿只能自写 `.tblcard`。
10. **【低】S10 · 02/02b 未画任何降级态**：正常态之外，权限横幅、空态、加载态、失败回执都只存在于
    `mmui/05-states.html` 基线里；且安装包"范围行"实现上下各画一次、稿内只一次。
11. **【低】S11 · 第三页签「系统分析」完全无设计稿**（README §1 只有 02/02b）——需要补一稿或明确
    声明"系统分析页不纳入设计系统"。
12. **【低】S12 · 位置/字号像素项**：搜索框 150 vs 140、表头列宽 78/92/60 vs 72/44/52、
    页签行高——**全部 `⚠️待真机测量`**，本次不判改。
13. **【低】S13 · 稿内文案与实现的口径注脚**：如注脚行、无权限行措辞已基本对齐，剩余差异为占位与上列各条。

## 4. 没能验证到的部分（逐条写明缺什么）

**本次环境无头**：不跑 App、不截图、不合成事件、不取色。因此**上面"一致"全部只到代码/HTML 层面的
结构、文案、语义**，没有任何一条像素级结论。下列状态**有钩子可达，但本次一张都没拍**——
不是"验不了"，是"本轮没验"（与 monitor 那种"根本没有钩子"性质不同）：

| # | 状态 | 可达钩子（已核对存在） | 本次为何没验 | 需要什么才算验过 |
| --- | --- | --- | --- | --- |
| 1 | 缓存页正常态（分组表 + 徽章 + 合计） | 默认启动 + `MM_OPEN_TAB=cache` | 无头 | 按 pid 抓窗截图（`./Scripts/window-ids.swift --pid` → `screencapture -l`） |
| 2 | 空态 | `MM_AUTO_SCAN` 触发后取消 / 或在第一类前取消 | 无头；且取消点不可控 | 一个"扫完返回空"的夹具，或"取消在第一类前"的定格钩子（当前无） |
| 3 | 加载态（skeleton × 5 + 取消） | 扫描瞬间 | 骨架帧易被覆盖 | 定格首帧钩子（当前无，类似 `MM_GUARDIAN_LOAD=hold`） |
| 4 | 无权限降级横幅 | 真实 TCC 未授权即出现（图上已有 294 位置） | 无头 | 复用既有 `cleaner-refusal-panel.jpg` 已覆盖；如需单屏再拍 |
| 5 | **被闸门拒绝（`MM_FAILURE_FIXTURE=protected`）** | `MMCleaner.swift:365` | 无头 | 已有入库图 `p1.7-deletion-guard/cleaner-refusal-panel.jpg`；但它覆盖的是**回执排版**，**不覆盖"点击→拒绝→回执"交互链**（那条需要合成点击，本项目禁止） |
| 6 | 分组展开明细 / 子项展开 | `MM_EXPAND_CATEGORIES`；子项点 chevron | 无头 | 内容钩子已够，重跑截图即可 |
| 7 | 确认面板（缓存页 sheet / 文件夹页 alert） | `MM_SHOW_CONFIRM` | 无头 | 同上 |
| 8 | 安装包残留夹具态 | `MM_INSTALLER_FIXTURE_DIR=/tmp/...`（硬性只认 `/tmp`） | 无头；且本次不造 `/tmp` 夹具 | 造一个 `/tmp` 夹具目录 + 钩子，再抓窗 |
| 9 | 系统分析页任意态 | `MM_AUTO_SCAN` + `MM_OPEN_TAB=system` | 无头；**且无设计稿可对照** | 先补设计稿（S11） |
| 10 | 浅色模式实机配色 | — | 无头；既有图为深色 | 浅色外观下重跑抓窗流程 |
| 11 | 各 locale 下 `MMFormat.bytes` 输出 | — | 不属设计稿范围 | `MMFormat` 单测矩阵 |

**已验证（代码/HTML 层面，非像素）**：模块三页签结构与钩子、页头 46pt / 动作栏 52pt / 行 44pt /
表头 26pt / 分组头 30pt / 卡圆角 8pt 的 token 值、风险三档组名与右注逐字、确认面板文案逐字、
安装包证据两档与"测量中"口径、拒绝回执三列由 `DeletionGuard` 现场生成、钩子七条全部存在且
`MM_INSTALLER_FIXTURE_DIR` 的 `/tmp` 硬约束（`UserFolderCleanView.swift:10-20`）。

## 5. 提请协调者（都是共享层，照 README §3：不要自己动手）

1. **`MMFailurePanel` 排版不够**（README §3 点名的例子）：缺 `05-states` 规格里的
   「计划/成功/失败/跳过」统计行与「重试失败项 / 复制诊断信息」页脚；形态是琥珀通栏条而非带边框卡。
   影响 cleaner 三页 + 其它模块。期望：给出统一的失败回执规格并落到 `MMUI`。
2. **`MMItemRow` 只读行丢列**（I2）：`isSelectable==false` 时整列复选框消失导致列不齐。
   期望：`MMItemRow` 保留禁用框占位（对齐 `05-states` 的 `.chk.off-allowed`），这是跨模块的列对齐地基。
3. **卡片 token 第三套**（I4/S9）：`MMCard` = `controlBackground`，而本页内联卡 = `contentBackground`，
   monitor 私有卡 = `underPage`。期望：`MMCard` 增加 `background:` 参数或补 `MMCardStyle`
   （`underPage` / `content`），cleaner 与 monitor 一起收口；顺带评估 `tokens.css` 是否补
   content-bg / under-page 两种卡 token（monitor S4 同问）。
4. **容器三页签 vs 页头过滤条的层级**（S1）：两稿都画错位置。期望：协调者定稿"模块内二级导航"
   的统一画法（页签在页头之上独立一行），02/02b 一起重出。
5. **侧栏 footer / 侧栏尾数（全站）**：与 monitor S1/S2 同一处，需 tokens/screen 层统一补组件，
   七张稿一起换，cleaner 的 02/02b 随批。
6. **要不要补"扫描完成但无可清理"的空态规格**（I4）：需要产品/设计定义"真干净"与"扫描未完成"
   两种空态各自的文案与图标（现在实现把两者混在 `categories.isEmpty` 一个分支里）。
7. **缺失的定格 / 空结果钩子**：cleaner 现有 7 个钩子覆盖了展开态、确认态、安装包夹具、拒绝预演，
   但**没有**"冻结首帧"（骨架）与"扫完为空"两个夹具档。本轮**优先不新增夹具**（照硬约束 4），
   先把需要列出来：若要补，建议照 `GuardianFixtureHooks.swift` 口径写纯粹的展示闸门，
   路径继续硬性只认 `/tmp`。
8. **"真按下删除 → 拿到 PROTECTED"的实机照片仍缺**（`deletion-guard.md` §6 已承认）：要到这一步
   需要合成点击，本项目红线禁止。现有 `cleaner-refusal-panel.jpg` 只覆盖回执排版与文案来源，
   **不覆盖交互链**——这一条按"已知缺口"留档，不试图绕过。
