# 47 系统清理 · 设计稿 ↔ 实现 逐元素对照（fidelity-cleaner）

> 后续更新：原审计表是修复前的历史快照。P0 已修正失败条目回写与共享列顺序；P1 已让缓存确认与执行共用 `CleanerSelectionPlan`，并把未测体积明确保留为未知。当前验收与截图见 [P1 清理与卸载验收](p1-cleaner-uninstaller.md)。

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
> **③ 全站骨架层继承项**（侧栏 footer、页底/卡片 token、侧栏尾数占位，与 `fidelity-monitor` 同源）。〔**P38f 现读**：这一族里**侧栏 footer 与侧栏尾数占位两项都已经落地**——组件在 `tokens.css:286`、16 张稿在用（含本页 02/02b/02c 三张），尾数由同一笔 `0c61fbf` 从稿侧删掉；这一族今天只剩页底/卡片那一半（S4，等 `coordination-audit.md` §5 第 2 条）还开着。判据与残留三处见 `release-readiness.md` §7.35。〕
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
| 可用钩子（README §2，**P16 重新 `grep` 核对全部命中，并逐条现读行号；P18 再逐条现读一次**） | `MM_OPEN_TAB`(`CleanerContainerView.swift:30`)、`MM_CLEANER_FILTER`(`MMCleaner.swift:318`)、`MM_EXPAND_CATEGORIES`(`MMCleaner.swift:138`)、`MM_AUTO_SCAN`(`UserFolderCleanView.swift:112`/`SystemAnalysisView.swift:78`)、`MM_SHOW_CONFIRM`(`MMCleaner.swift:397`/`UserFolderCleanView.swift:116,384`/`SystemAnalysisView.swift:82`)、`MM_INSTALLER_FIXTURE_DIR`(`UserFolderCleanView.swift:120,366`)、`MM_FAILURE_FIXTURE`(`MMCleaner.swift:403`)。**七条全部存在**，故 monitor 那种"13 项完全无法构造"的困境 cleaner 没有。（本文此前记的 `:32`/`:280`/`:148`/`:359`/`:365` 五处都是写作当时的位置，已漂 2–36 行；P18 把 `MM_OPEN_TAB`/`MM_FAILURE_FIXTURE` 接进 `MMHookValue` 后行号又往后漂了 4–6 行；`MM_OPEN_TAB` 在磁盘页 `MMDisk.swift:38` 与优化页 `MMOptimizer.swift:41` 也各有一个同名钩子，不属于本模块这一行） |
| 硬约束 | 全程未 `git`、未跑 `swift build`/`make-app.sh`、未发合成鼠标/滚轮/键盘事件、未改 `Sources/`·`Packages/`·共享层；本次只写本文档一个文件 |

代码层锚点（本文所有"结构成立"判定的依据，单位 CSS px == pt）：

- 容器两级导航：`CleanerContainerView.swift:31-61` —— 顶部 `safeAreaInset` 里 30pt 高的三页签
  segmented `Picker`（`缓存清理/用户文件夹/系统分析`），其下才是各页自己的 `MMPageHeader`。
- 页头：`MMPageHeader`（`MMDesign.swift:238-271`）= `MMMetric.toolbar` 46pt + `contentBackground` + 底部 Divider。
- 过滤条：`MMCleaner.swift:305-325`，`CleanerFilter` 四档 `全部/缓存/日志/临时`（`:896-921`，**P25 现读重指**，旧值那一对行号漂了约四十行）。
- 分类表：`MMCleaner.swift:502-506` —— 内联卡（`background(MMColor.contentBackground)` + `MMRadius.card` 8 + separator 描边 + `MMGap.lg` 16 内边距），**没有调用 `MMCard`**。
- 表头 26pt / 分组头 30pt / 行 44pt：`MMCleaner.swift:511-526`、`:545-565`、`MMItemRow`（`MMDesign.swift:807-873`，`MMMetric.rowRegular` 44）。
- 动作栏：`MMActionBar`（`MMDesign.swift:280-317`）= `MMMetric.actionBar` 52pt + `cardBackground`。
- 风险三档真源：`MMRisk`（`Packages/MMCore/Sources/MMCore/Risk.swift:9-41`），`groupTitle/groupNote/isDefaultSelected/allowsDeletion`。
- 卡片 token 真源：`MMCard`（`MMDesign.swift:904-938`）= `MMColor.cardSurface`（`MMCardStyle.content`）+ 8pt 圆角 + 16pt 内边距；而本文页内卡用的是 `MMColor.contentBackground`（`textBackgroundColor`）→ 见 I4/S9。
- 拒绝回执预演：`CleanerView.refusalPreview()`（`MMCleaner.swift:926-934`），三条由 `DeletionGuard.rejection(for:)` 现场算出。

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
| 副标题格式「已扫描 N 类 · 可释放 X · 时间」 | `headerSubtitle` `MMCleaner.swift:881-891`，段序在 `CleanerHeaderCopy.subtitleSegments` `:970-1010` | ⚠️ 结构 | 实现多出一段「**另有 Y 只读**」（`readOnlyTotal>0` 时），类数用 `categories.count`；**P25 把段序改成「已扫描 N 类（·未完成）· 时间 · 可释放 X ·· 另有 Y 只读」**——时间从末尾挪到中段，只读那一段压到最后。理由是界面上的而不是审美的：页头副标题单行 + 中间截断，用户能拖到的最窄窗（1000 pt）先吃中段，而"另有 N 只读"被吃掉等于把代码里那条自我约束在界面上撤销，见 `release-readiness.md` §7.16 | 低 | 设计稿该改 S6 |
| 副标题数值「已扫描 **9 类** · 可释放 **2.42 GB** · **21:15**」 | 同上 | ❌ | 稿内 9/2.42/21:15 均为**占位**：1280×800 实拍副标题为「已扫描 16 类 · 10-07 21:03 · 可释放 3.76 GB · 另有 136.7 MB 只读」（`docs/verification/p25-header-wide/`）；稿内另外还自相矛盾（表里列了 5+3+2=**10** 行却写"9 类"）。**这一格 2026-09-30 那版抄的是旧段序**，P25 之后按新照片重指 | 低 | 设计稿该改 S6 |
| 过滤条 seg：`全部 / 缓存 / 日志 / **开发**` | `CleanerFilter.label` `MMCleaner.swift:904-911` = `全部/缓存/日志/**临时**` | ❌ | 第 4 项文案不一致；实现的 `temp` 映射 `CacheScope.temp`，语义是「临时」不是「开发」 | 低 | 设计稿该改 S3 |
| 「搜索类别」搜索框 | `MMCleaner.swift:315-317`，`TextField.frame(width: 140)` | ✅ | 稿 `width:150px`；宽度差 **10pt `⚠️待真机测量`** | 低 | 记录 |
| 「重新扫描」按钮 + refresh 图标 | `MMCleaner.swift:319-324` `.disabled(model.isScanning)` | ✅ | 一致（实机在扫描时禁用，稿内未画禁用态） | — | — |

### 1.3 权限降级横幅（无权限态）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 「有 N 个位置读不到…未授权的部分不计入合计，也不会显示为 0。」+「打开系统设置」 | `MMCleaner.swift:366-370` → `MMPermissionBanner`（`MMDesign.swift:483-513`，深链 `openSystemSettings(pane:)` `:519`） | ⚠️ 未画 | 02 稿**没有这一档**；实机图顶部有（琥珀锁 + 294 个位置读不到 + 打开系统设置）。文案与 `05-states.html` 权限态口径一致 | 低 | 设计稿该改 S10 |

### 1.4 分类表

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 表头列「类别 · 大小 · 风险 · **操作**」 | `tableHeader` `MMCleaner.swift:511-526` | ❌ | 实现最后一列表头是 `Text("")`（空），**没有「操作」列名**；列宽 `大小 minWidth 72 / 风险 44 / 操作 52` vs 稿 `78 / 92 / 60`（**`⚠️待真机测量`**） | 低 | 实现该改 I6 |
| 分组头「可安全清理 N 类 · X」+ 右侧说明 | `groupHeader` `MMCleaner.swift:545-565`；文案真源 `MMRisk` | ✅ | 组名「可安全清理/需谨慎/只读 · 不会修改」与右注三句**逐字一致**（`Risk.swift:22-36`）；`N 类` 与合计按实算 | — | — |
| 分组右注文字 | 同上 `.frame(maxWidth: 280, alignment: .trailing)` + `.lineLimit(1)` | ✅ | **P6.6 实测**：最长那句（谨慎档 19 个汉字）完整显示、无 "…"，实宽 ≈187pt < 280pt 封顶 | 低 | ~~I9~~ 已量，非缺陷 |
| 行结构：勾选 · 图标 · 名称/副标题 · **大小 → 风险徽章 → 操作** | `MMItemRow`（`MMDesign.swift:838-868`，P36 现读重指：原引 `:719-747` 落在 `MMFailurePanel` 的 body 里，与这个组件无关）：`勾选 → 图标 → 名称/副标题 → Spacer → 徽章 → accessory → 大小` | ❌ | **大小永远在最右**，徽章/折叠箭头/文件夹都在它左边；稿内大小在徽章**之前**。分类行与安装包行都如此 | **中** | 实现该改 I3 |
| 行内图标配色：安全档 `--c-warning`（橙）/ 谨慎档 secondary（灰）/ 只读 tertiary | `MMItemRow` 用 `risk?.color`（安全=绿 `systemGreen`、谨慎=橙、只读=secondary） | ❌ | 安全档图标实现是**绿**、稿内是**橙**；谨慎档实现是**橙**、稿内是**灰**。且稿内"安全徽章绿 + 图标橙"自身不一致 | 低 | 设计稿该改 S7 |
| 只读行：虚线禁用复选框（`.chk.off-allowed`）+ 锁图标 + 「只读」徽章 | `categoryRows` `MMCleaner.swift:522-546` 传 `isSelectable: category.risk.allowsDeletion` → 只读档 **不渲染 Toggle** | ❌ | 实现**整列删掉复选框**（`MMItemRow` 里 `if isSelectable { Toggle }`），不是画虚线禁用框；后果是只读行的图标列相对可勾选行**左移、列不对齐** | **中** | 实现该改 I2 |
| 只读行操作列 = info 图标 | `categoryRows` 仍按 `subItems` 非空给 `chevron.down/up` + `folder` | ❌ | 只读分类只要 `subItems` 非空就仍带**展开箭头**，稿内只给 info | 低 | 实现该改 I7 |
| 「沙盒容器缓存」大小占位「·」 | `MMCleaner.swift:572` `scannedSize > 0 ? bytes : "—"` | ❌ | 稿内未测用「·」，实现用「—」；且实现把"扫到 0 字节"也画成「—」（与"未测"同形） | 低 | 设计稿该改 S7 |
| 行高 44 / 表头 26 / 分组头 30 / 卡圆角 8 | `MMMetric.rowRegular` 44、`:478` 26、`:518` 30、`MMRadius.card` 8 | ✅ | 与稿内 `.crow min-height:44`、`.hdr 26`、`.gtitle 30`、`--r-md 8` **数值一致**（代码层；实机像素 `⚠️待真机测量`） | — | — |
| 底部注脚「所有删除一律先移入废纸篓…不会静默跳过。」 | `MMCleaner.swift:436-446` | ✅ | 文案逐字一致 | — | — |
| hover 才显现的文件夹按钮 | `MMRowAction`（`MMCleaner.swift:938-957`）图标**常显**，仅 hover 时出底 | ❌ | 稿内 `.crow .op{opacity:0}` 整枚按钮 hover 才现；实现图标一直在 | 低 | 设计稿该改 S7 |

### 1.5 底部操作栏

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 左侧合计「已选 N 类 · X」+ 注脚「未勾选项不会被修改」 | `actionBar` `MMCleaner.swift:685-706`；`MMActionBar` 纵向两行 | ✅ | 结构一致（02 稿也是纵向两行） | — | — |
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
| 稿内额外的「清理后 15 秒内可一键撤回」开关 | `MMCleaner.swift:753`，仅缓存页 sheet 有 | ⚠️ | 用户文件夹页/系统分析页的 `.alert` **没有**这个开关 | 低 | 实现该改 I6b |

### 1.7 失败 / 被闸门拒绝回执（MMFailurePanel）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| PROTECTED 行：琥珀盾 + 原因 + 错误码三列 | `MMFailurePanel`（`MMDesign.swift:647-670`）：`failure.code=="PROTECTED"` → `exclamationmark.shield` 琥珀 + 原因 2 行 + 右列 `PROTECTED` | ✅ | 与 `cleaner-refusal-panel.jpg` 实拍一致：三条 PROTECTED，盾牌/原因/码齐全；文案由 `DeletionGuard.rejection` 现场算，非手写 | — | — |
| 顶部摘要「已回收 X GB」（绿） + 「N 项失败」徽章 + 忽略 | `MMCleaner.swift:337-344` 传 `"已回收 \(MMFormat.bytes(model.lastResult?.totalSize))"` | ⚠️ | 实拍图摘要显示「已回收 **测量中**」（夹具下 `lastResult==nil`）；真实删除后才会是「已回收 X GB」 | 低 | 实现该改 I10 |
| 「计划 N · 成功 N · 失败 N · 跳过 N」统计行 | 实现无此行 | ❌ | `05-states.html` 局部失败态明确画了这行；实现只给"已回收 + N 项失败" | **中** | 实现该改 I5 |
| 页脚「复制诊断信息 / 重试失败项 / 完成」 | 实现只有「忽略」 | ❌ | 缺"重试失败项"等补救入口；`05-states` 规格有 | **中** | 实现该改 I5 |
| 面板形态：带边框圆角卡（`05-states`） | 实现是**琥珀底通栏条**（`MMColor.soft(caution,0.10)` + 顶部 Divider，无圆角/边框），贴动作栏上方 | ❌ | 形态不同；影响的是共享组件 | 低 | 实现该改 I5（→ 协调者） |
| 超过 4 条折叠为「另有 N 项失败」 | `MMDesign.swift:647` `failures.prefix(4)` | ✅ | 夹具正好 3 条，全部列出 | — | — |

### 1.8 删除后状态一致性（无稿，代码走查）

| 事项 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 删除后把**失败/被拒**的条目从分类表移除 | `CleanerModel.clean()` `MMCleaner.swift:214-239`：`let cleaned = Set(paths)`（= 尝试过的**全部**路径）→ `subItems.removeAll { cleaned.contains($0.path) }` | ❌ | **失败条目也一并消失**：主表面（分类表）表现成"已清理"，与底部失败面板互相打架。对照 `UserFolderCleanView.swift:532-534` 用的是 `result.operation.files`（只删真的搬走的）→ 同模块两种口径 | **高** | 实现该改 I1 |
| 系统分析页同类问题 | `SystemAnalysisView.swift:324-334`：同样 `cleaned = Set(paths)` → `groups[i].items.removeAll` | ❌ | 同一缺陷的第二个副本 | **高** | 实现该改 I1 |

### 1.9 空 / 加载 / 取消 态（缓存清理页）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 加载态：进度一行 + skeleton，不显示 0 B | `MMCleaner.swift:431-441` → `MMScanProgress` + 5×`MMSkeletonRow` + 取消 | ✅ 结构 | 与 `05-states` 加载态一致；实现**不画「剩余约 00:14」**（`estimatedRemaining: nil`），且用「正在扫描 <类别名>」代替「第 2/5 步」 | 低 | 记录 |
| 空态：标题「没有可清理的内容」+「已检查 N 个类别…」 | `MMCleaner.swift:451-464` | ❌ | 分支条件是 `categories.isEmpty`，此分支 detail 会拼出「**已检查 0 个类别**」；而真正"扫完但都干净"的态**不进这个分支**（会显示一张 `—` 全零的表格）。也就是说空态实际只在**取消于第一类完成前**才命中，标题却断言"没有可清理的内容" | **中** | 实现该改 I4 |
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
| 侧栏 footer = 1px 线 + 平铺「设置」nav-item | 实机图左下是 **`Macintosh HD` + `7%` + 红色容量条 + 带边框「设置」按钮** | ✅（P38f 现读） | 与 `fidelity-monitor` S1 同源：02/02b 沿用了 01–06 的错误画法——**这一半由 `0c61fbf` 作废**（那一笔就把 02/02b 换成 `tokens.css:286` 的 `.sidebar-footer`，02c 新建时从一开始就在用） | **中** | 两边都改 S2 → **稿侧已落地（P38f）** |
| 侧栏尾数「系统清理 2.4 GB」「应用卸载 46」 | 无来源；实机 系统清理尾数随扫描变化（图上为 653.6 MB） | ✅（P38f 现读） | 纯占位，见 monitor S2——**这一条由 `0c61fbf` 作废**：现读 `02-cleaner.html`、`02b-cleaner-installers.html`、`02c-cleaner-dev.html` 三份稿里 `class="tail"` 出现 0 次，侧栏不挂尾数；实现也只在 `MainWindow.swift:105-110` 的 `.measured` 分支给清理那一行挂真实值 | 低 | 设计稿该改 S8 → **稿侧已落地（P38f）** |
| 页面底 / 卡片底色 | `tokens.css` 用 `--c-content-bg`（白）；实机页底 = `windowBackgroundColor`、卡 = `textBackgroundColor` | ❌ | 全站性 token 差，见 monitor S3/S4 | 低 | 设计稿该改 S9 |
| 页内卡未复用 `MMCard` | `MMCleaner.swift:503-506` 内联 `contentBackground`+8pt+描边，**不调用 `MMCard`**（后者是 `cardSurface`） | ❌ | 与 monitor I4 同类：同一 App 出现第三种"卡底 token" | **中** | 实现该改 I4（→ 协调者） |
| 侧栏宽 216 / 标题栏 52（**P38a 现读：令牌已从 38 改为 52**） | `MMMetric.sidebar` 216、`tokens --titlebar-h` 52 | ⚠️ / ✅ | 实机 monitor 实测 220 / 52（monitor I10a/I10b），cleaner 继承同一骨架；**标题栏那一半本轮关闭**（令牌与实机同源，实现侧无此常量），侧栏那一半仍是一条 `MMMetric.sidebar` 与稿面 220 的数差，没动 | 低 | 记录（见 monitor） |

## 2. 实现该改（10 条，按严重度排序）

> **P6.5b 复核（2026-10-04，逐条现读代码 + `git log -S`）**：这份清单同样中了"落地那轮没回写"的招——
> **I1 / I2 / I3 三条已经做完了**（`6d086c6` / `c74f045` / `e84066a`，全部 2026-09-30），
> **I5 / I6 / I10 各做了一半**，I4 / I7 / I8 / I9 四条确实一天没动。
> 下面每条末尾的「**复核 2026-10-04**」是现读结论，行号是今天的坐标（原文里的行号是审计当天的）。
> 与 `fidelity-monitor.md` 同一轮发现，手法同一轮做：**清单里的"开放"是写下那天的状态，不是今天的状态**。
>
> **P6.6 追加（2026-10-04）**：**I9 已量完并判为"非缺陷"**（最长那句 groupNote 实宽 ≈187pt < 280pt 封顶，
> 照片 `docs/verification/p66-layout/04-cleaner-caution-note.png`，拍法见 §2 I9）。
> 所以"一天没动"的四条现在只剩 **I4 / I7 / I8** 三条。

1. **【高】I1 · 失败条目从分类表/系统分析表里被静默移除 —— 主表面把失败当成已清理**
   `CleanerModel.clean()`（`MMCleaner.swift:224`）用 `let cleaned = Set(paths)`（**尝试过的全部路径**）
   去 `subItems.removeAll`，`SystemAnalysisView.swift:330` 同款。被 `DeletionGuard` 拒绝（PROTECTED）
   或因 EPERM 失败的条目**仍在磁盘上，却从列表消失**，同时 `scannedSize` 被重算成更小——
   主表面一致地宣称"清掉了"。
   → 建议：改成只摘**真的搬走**的那批，口径与同模块已经做对的 `UserFolderCleanView.swift:532`
   （`Set(result.operation.files.map(\.originalPath))`）一致；失败条目留在原行（失败详情仍由
   `MMFailurePanel` 逐条报）。这是"把失败当正常"，正踩本模块自己的红线，判 **高**。
   **复核 2026-10-04：✅ 已落地（`6d086c6`，2026-09-30）**——`MMCleaner.swift:216` 与
   `SystemAnalysisView.swift:331` 两处都已是 `Set(result.operation.files.map(\.originalPath))`。
   这条是 §2 里唯一的"高"，挂着没人划掉最容易误导下一轮，所以先核它：提交信息点名了这条。
2. **【中】I2 · 只读行的复选框列被整列删掉**（`MMCleaner.swift:530` `isSelectable: category.risk.allowsDeletion`
   + `MMItemRow` 的 `if isSelectable`）
   稿内（`02-cleaner.html:103,107` 与 `05-states.html:100-103`）画的是**虚线禁用框** `.chk.off-allowed`：
   "这是勾选位、但你不能用"。实现直接不给复选框，于是只读行比可勾选行**少一格宽度、图标列左移**，
   同表两段列不齐。
   → 建议：`MMItemRow` 在 `isSelectable==false` 时**保留占位**（画禁用框或至少留 15pt 空槽）——
   这会碰到共享组件 `MMUI`，见 §5 提请协调者。
   **复核 2026-10-04：✅ 已落地（`c74f045`，2026-09-30，"只读行占位"就写在提交信息里）**——
   `MMDesign.swift:845-852` 现在给 `isSelectable == false` 一支画禁用 + `opacity(0.35)` 的空框，
   注释直接标着"I2"。共享组件那条路径走通了，§5 的对应提请可以撤。
3. **【中】I3 · 行内要素顺序：大小永远最右**（`MMItemRow` `MMDesign.swift:838-868`，P36 现读重指：原引裸写 `:720-741` 落在 `MMFailurePanel` 的 body 里）
   稿内两处行（分类行 `02-cleaner.html:67-70`、安装包行 `02b:77-79`）顺序都是
   **名称 → 大小 → 风险徽章 → 操作**；实现是 **名称 → 徽章 → 操作 → 大小**。
   → 建议：二选一——要么 `MMItemRow` 支持"数值列提前"的排布，要么把稿改成与共享行一致。
   因涉及共享组件，倾向**设计稿对齐组件**（见 §3）。
   **复核 2026-10-04：✅ 已落地（`e84066a`，2026-09-30）**——`MMDesign.swift:863-867` 的顺序现在是
   数值（`Text(value)`，`minWidth: 72` 右对齐）→ `MMBadge(risk:)` → `accessory`，即建议里的"数值列提前"那一支。
   实现与稿子在这一格上同序了。
4. **【中】I4 · 空态把"取消/未产出一类"说成"没有可清理的内容"**（`MMCleaner.swift:451-464`）
   分支条件 `model.categories.isEmpty` 只在**取消于第一类完成前**命中，detail 会拼出
   「**已检查 0 个类别**」；而真正"扫完都干净"的态**不**进这里（会显示全零表格）。
   标题却直接断言"没有可清理的内容"。
   → 建议：拆成两档——"扫描被取消/未完成"（标题写"扫描未完成，结果不完整"，给"重新扫描"）
   与"扫完确认无可清理"（给出检查范围与项数，照 `05-states` 空态的口径）；并把
   「已检查 0 个类别」改成不误导的措辞。
   **复核 2026-10-04：❌ 仍未做**（现坐标 `MMCleaner.swift:451-464`，`git blame` 全部落在 `e5634d3`（2026-09-29，
   **审计之前**），也就是说这一条一天都没人碰）。仍是**一个** `model.categories.isEmpty` 分支、
   标题仍断言「没有可清理的内容」；detail 里那句「扫描中途取消时结果不完整，请重新扫描」是原文就有的对冲，
   不是分档。**这条是 §2 现在剩下的一条"把不知道写成结论"**（与监控页 I1/I2 同性质），
   判高判中的差别只在于它出现的频率低。
   **✅ 已修（P7a，2026-10-05）**：`MMCleaner.swift:444-458` 现在按**三种成因**分档，
   而且第一档是审计当时没想到的第四种态——**四个类别开关全关**：
   `CacheScanner.scan(scope:)` 对空 scope 直接返回 `[]` 且 `isComplete` 仍为 `true`
   （`CacheScanner.swift:200/209` 只在取消时置 false），所以旧代码在这种态下走的是
   "扫完都干净"那一路，页面照样断言「没有可清理的内容」——**这一轮压根一项都没检查**。
   现在的三档（现读 `MMCleaner.swift:450-455`）：
   ①`没有勾选任何扫描类别` + 「设置 · 清理里的四个类别开关都关着，这一轮一项都没有检查。」
   ②`扫描中途取消，结果不完整` + 「第一类还没扫完就取消了…」（判据 `model.isPartial`，`:30/:135`）
   ③`没有可清理的内容` + 「已勾选的类别全部检查完，没有发现可清理的条目。」
   判据 ① 用 `model.scope(from: settings).isEmpty`（`:447`），不是"数一下类别有几个"——
   空清单既可能是没勾、也可能是勾了没扫到，只有 scope 本身分得出这两者。
   取证：`docs/verification/p7-empty-scope/{01-empty-scope,02-restored}.{png,log}`，
   脚本 `Scripts/p7-empty-scope-capture.sh`（状态走 `defaults write` 而不是环境变量，
   所以归因头多了第三行 `# defaults:`；跑完 `trap` 还原，02 就是还原后的对照档）。
   ②③ 两档**没有新照片**：②需要"扫到一半取消"、③需要真机上恰好全干净，
   两者都不是钩子能定格的；这一条的闭环只到"①不再是假话"为止。
5. **【中】I5 · `MMFailurePanel` 比 `05-states` 局部失败规格少两截**（`MMDesign.swift:620-684`）
   缺 **「计划 N · 成功 N · 失败 N · 跳过 N」统计行**，缺 **页脚「重试失败项 / 复制诊断信息」**；
   面板形态也由"带边框圆角卡"变成"琥珀底通栏条"。这是共享组件，见 §5。
   **复核 2026-10-04：⚠️ 组件侧做完了、调用侧一处没用 = 页面上仍然看不到**（`c74f045` 给组件加了
   `Stats` 结构体 + 带 `stats:`/`onRetry:`/`onCopyDiagnostics:` 的新 init（`MMDesign.swift:682-714`）、
   统计行 `:726-728`、页脚，但旧 init `:688` 原样保留，而**全仓 11 个调用点无一使用新 init**
   （**P20 现读重跑，判据换成能罩住壳层的那一条**：
   `grep -rn 'MMFailurePanel(' --include='*.swift' Packages Sources | grep -v 'struct MMFailurePanel' | wc -l` = 11，
   逐个位置是 `MMCleaner.swift:376`、`SystemAnalysisView.swift:37`、`UserFolderCleanView.swift:72`、
   `DevArtifactView.swift:423`、`MMDisk.swift:110`、`MMGuardian.swift:45`、`MMOptimizer.swift:166`、
   `MMOptimizer.swift:240`、`MMUninstaller.swift:202`、`MMUninstaller.swift:208`、
   `Sources/MacMaster/MainWindow.swift:242`。**这两处 `MMOptimizer.swift` 的锚点是 P34b 顶漂的**（那一轮在 161 这一行以上
   净插入 4 行——`@StateObject preferences`、`switch` 里那一条 `case .preferences`、夹具注入行与它的真实扫描 guard——
   整段往下推 4 行：161→165、235→239，本轮按 §0 那条"改过源码行数的那一轮自己现读重指"的规矩重指；
   P20 那一读 161/235 当时是对的，`grep -n MMFailurePanel` 现读就是这两个新数）。
   **原来这一格写的是"10 个"，少的那一个不是漏看而是命令本身罩不住**——旧命令
   `grep -n 'MMFailurePanel(' Packages/*/Sources` 的 glob 只展开 `Packages/<模块>/Sources`，
   壳层 `Sources/MacMaster` 在仓库根，永远不在它的搜索范围里。而 `release-readiness.md` §6
   那一格写的是 11（它另有一条含壳层的判据）——**同一个事实两份文档各写一个数，差的那一个恰好是"命令看不见"的那个**，
   这就是为什么判据要写成可以整条复制去跑的命令，而不是"我数了一下"）。
   另：旧列表里那十个**位置**本身也漂了（`MMCleaner` 369→376、`DevArtifactView` 393→423、
   `MMDisk` 112→106、`MMUninstaller` 197/203→202/208，P18 那轮改动搬的），
   而**引用门禁四道硬判据一条都没响**——漂到的那些行仍然在文件里、仍然非空白。
   这一条是 §7.7 那句"路径存在、说法不成立"的最新样本，也是"十一处走的全是旧的那一个"
   （**P16 现读**：`grep -rn "stats:"` 在调用侧仍零命中，所以"组件有功能没人接"这一句到 P20 仍然成立）
   所以这条从"组件缺功能"变成了
   **"组件有功能没人接"**，统计行与页脚现在是死代码路径。剩下的活是四个调用点各自决定
   `planned/succeeded/skipped` 从哪来（`TrashResult` 里有 `files` 与 `failures`，`planned` 需要调用方自己记），
   属协调层 + 本模块各一半。
6. **【低】I6 · 表头缺「操作」列名**（`MMCleaner.swift:473` `Text("").frame(width: 52)`）——
   稿内 `.hdr` 有「操作」。顺带：实现 `风险 44 / 操作 52` vs 稿 `风险 92 / 操作 60`，**`⚠️待真机测量`**。
   **I6b**：用户文件夹页/系统分析页的确认用系统 `.alert`，没有缓存页 sheet 里的
   「清理后 15 秒内可一键撤回」开关（`MMCleaner.swift:753`）。
   **复核 2026-10-04：⚠️ 主项已落地、两个顺带项没动**——表头 `MMCleaner.swift:504` 现在是
   `Text("操作").frame(width: 52)`（`e84066a`）；列宽仍是 44/52（稿 92/60，**这条的 `⚠️待真机测量` 至今没人量**）；
   I6b 的撤回开关仍只在缓存页 sheet（`:739`），另两页还是系统 `.alert`。
7. **【低】I7 · 只读分类仍带展开 chevron**（`MMCleaner.swift:578`，只要 `subItems` 非空；P36 现读重指：原引裸写 `:533-537` 落在「全选」binding 里，与 chevron 无关）——
   稿内只读行只给 info 图标。
   **复核 2026-10-04：❌ 仍未做**（现坐标 `MMCleaner.swift:578`，条件仍是 `!category.subItems.isEmpty`，
   没有 `allowsDeletion` 这一道闸）。
8. **【低】I8 · 页头标题与页签名不同源**：页签「缓存清理」而页头「系统清理」
   （`CleanerContainerView.swift:9-11` vs `MMCleaner.swift:305`）。记录，非必要改。
   **复核 2026-10-04：❌ 未做，且按原文判断**不该**做**——这一条审计自己写的就是"记录，非必要改"，
   页签说的是"这一格放什么"、页头说的是"这一页是什么"，两问本来可以不同答案。留在清单里只为下次别当成漏改。
   （现坐标：页签 `CleanerContainerView.swift:9` `case cache = "缓存清理"`，页头 `MMCleaner.swift:336`
   `MMPageHeader("系统清理", …)`，模块名同一个字符串还在 `MMCleaner.swift:8` 的 `moduleName`。）
9. **【低】I9 · 分组右注硬封顶 280pt**（`MMCleaner.swift:515`）——最长那句可能被 `.lineLimit(1)` 截尾，
   是否真截**`⚠️待真机测量`**。
   **复核 2026-10-04：❌ 仍未做**（现坐标 `MMCleaner.swift:546`，`.frame(maxWidth: 280, alignment: .trailing)`
   + `:543` 的 `.lineLimit(1)` 原样）。**`⚠️待真机测量` 这条挂了 4 天没人量**——它不需要钩子，
   分组注文案最长那句摆出来按 pid 抓一张窗就完事，下一轮顺手做掉。
   **✅ 已量，结论是"不用改"（P6.6，2026-10-04）**：`docs/verification/p66-layout/04-cleaner-caution-note.png`
   （@2x，1100pt 宽窗口）。拍法上有一步是这条的关键：**首屏那张（`03`）根本量不到它**——
   最长那句属于「需谨慎」分组，而清理页首屏只有「可安全清理」的 12 字短注，要往下滚才看得见，
   而滚动是合成事件、红线禁。用 `MM_CLEANER_FILTER=浏览器` 把列表收到只剩谨慎档那一组，
   分组头自己就顶到首屏了（`MM_CLEANER_FILTER` 早就有，是搜索框的初值，`MMCleaner.swift:318`）。
   量到的事实：那句「可能包含登录态或未同步数据，默认不勾选」**逐字完整显示，没有 "…"**，
   文字实宽 x=1766..2140 = 375px ≈ **187pt**，而封顶是 280pt——**余量 93pt**。
   所以这不是"这次窗口够宽所以没截"，而是**最长的这句本身就装得下**
   （`Risk.swift:32-34` 三句：安全档 12 个汉字、只读档 11 个汉字 + 一段拉丁字母、谨慎档这 19 个汉字。
   本轮只实机拍了谨慎档那一句，另两句按汉字数与同一字号推它更短——**这是推断，不是测量**）。
   → 关闭方式：`maxWidth: 280` 保留，`.lineLimit(1)` 保留；**要留一句防未来的话**——
   再往 `groupNote` 里加长文案时，280pt ≈ 28 个 CJK 字就是天花板，超了会被静默截尾，
   因为这一格没有 tooltip。这条从"待测量"变成"已量、非缺陷"，不再占欠账。
10. **【低】I10 · 拒绝回执摘要会拼出「已回收 测量中」**（`MMCleaner.swift:339`）——
    `lastResult==nil` 而 `failures` 非空时（夹具路径目前就是这样）。真实删除后 `lastResult` 有值，
    故只在预演里出现；建议摘要不要依赖另一个来源的 Optional，或对 nil 用"未搬动任何项"这类措辞。
    **复核 2026-10-04：⚠️ 四处里改好了两处**——`SystemAnalysisView.swift:38` 与
    `UserFolderCleanView.swift:73` 已是 `summary: lastResult.map { … }`（nil 就整段不出，
    正是建议的"不要依赖另一个来源的 Optional"）；仍漏的是 `MMCleaner.swift:370` 与
    `DevArtifactView.swift:394`，两处逐字都是 `"已回收 \(MMFormat.bytes(model.lastResult?.totalSize))"`，
    而 `MMFormat.bytes(nil)` = "测量中"（`MMDesign.swift:150`）。**同一条修了两遍、还剩两遍**，
    是"改了一处就当改完"的典型形状——剩下两处照抄已修好的那两行即可。
    **别把这一条的数量记成六处**（复核时容易数错）：`grep 已回收` 在本模块确实命中 6 行，
    但另外两处是**撤回条**（`MMUndoToast`）不是失败回执——`MMCleaner.swift:709-710` 与
    `DevArtifactView.swift:446-447`，它们的外层显示条件本身就是 `model.lastResult != nil`
    （`MMCleaner.swift:413-414`、`DevArtifactView.swift:445`），nil 时整条不出，**构不成缺陷**。
    所以 I10 的待修集是**四个回执点里的两个**，不是六个里的四个。
    **✅ 已修（P7a，2026-10-05）**：剩下两处照抄已修好的那两行——
    `MMCleaner.swift:370` 与 `DevArtifactView.swift:394` 现在都是
    `summary: model.lastResult.map { "已回收 \(MMFormat.bytes($0.totalSize))" }`，
    nil 时整段不出。四个回执点全部收口；`:703`/`:417` 那两条撤回条按原文判断本来就不在待修集里
    （外层显示条件已是 `lastResult != nil`）。这一条不再占欠账。

## 3. 设计稿该改（14 条；1–13 来自 P3 审计，14 是 P6.1 追加）

1. **【中】S1 · 容器三页签的结构在 02/02b 里对不上实现**：02 稿**没有**三页签；02b 稿把三页签
   画进 46pt 工具栏**与标题同行**。实机是**页头之上独立 30pt 一行**（`cleaner-refusal-panel.jpg` 顶部可核）。
   → 两稿都要重画：补出/挪正「缓存清理｜用户文件夹｜系统分析」这一行。
2. **【中】S2 · 侧栏 footer 全站画错**（与 `fidelity-monitor` S1 同源）：稿内是"分隔线 + 平铺设置"，
   实机是容量行 + 带边框设置按钮。**两边都改**：设计层补一个侧栏 footer 组件，01–07 一起换。〔**P38f 现读：这条作废，且出生即假**——组件在 `tokens.css:286`、02/02b 由 `0c61fbf` 那天就换了（那一笔的文件列表里就有这两张），02c 后来新建时从一开始就在用；现读 20 张里 16 张在用。这一族只剩 `components.html` 改稿前第 141-142 行 一格旧画法与磁盘 04b/04e 没画，见 `release-readiness.md` §7.35。〔**P39 收这一族**：那一格现读就是 `<div class="sidebar-footer">`（`components.html:141`），04b/04e 三块补了 footer，九张 png 重渲染，判据在 `release-readiness.md` §7.36。〕
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
   用户文件夹副标题「6 个文件夹 · 41.2 GB · 全部默认未选中」也是占位。〔**P38f 现读：这一条只剩后半句**——那两个侧栏尾数在 `0c61fbf` 就删干净了（三份稿 `class="tail"` 0 次，判据见 §1 表格那一行），而 `02b-cleaner-installers.html:66` 那句「6 个文件夹 · 41.2 GB · 全部默认未选中」**现在还在**——页头那句在实现里是拼出来的动态值（`Packages/MMCleaner/Sources/MMCleaner/UserFolderCleanView.swift:136`「`N` 个文件夹 · 体积」），所以这半句仍是设计稿侧待清洗。〕
9. **【低】S9 · 页底/卡片底色 token**（`--c-content-bg` 白 vs 实机 windowBackground）
   与"缺 content-bg / under-page 卡片 token"——全站项，见 monitor S3/S4，cleaner 稿只能自写 `.tblcard`。
10. **【低】S10 · 02/02b 未画任何降级态**：正常态之外，权限横幅、空态、加载态、失败回执都只存在于
    `mmui/05-states.html` 基线里；且安装包"范围行"实现上下各画一次、稿内只一次。
11. **【低】S11 · 第三页签「系统分析」完全无设计稿**（README §1 只有 02/02b）——需要补一稿或明确
    声明"系统分析页不纳入设计系统"。
12. **【低】S12 · 位置/字号像素项**：搜索框 150 vs 140、表头列宽 78/92/60 vs 72/44/52、
    页签行高——**全部 `⚠️待真机测量`**，本次不判改。
13. **【低】S13 · 稿内文案与实现的口径注脚**：如注脚行、无权限行措辞已基本对齐，剩余差异为占位与上列各条。
14. **【低】S14 · 02c ② 档把「继续扫描这 N 个根」画在扫描范围条里**，实现放在页头 `actions`
    （与「重新扫描」并排，全站四页一致）。**改稿不改实现**，理由见 §8.3；同时 ② 那一帧画的是
    "续扫后仍有 1 个根截断"，实机 `02` 拍到的是"续扫后全部扫完、按钮消失"——两个都是真分支，
    稿子应补一句说明这一档只是其中一种。

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
| 5 | **被闸门拒绝（`MM_FAILURE_FIXTURE=protected`）** | `MMCleaner.swift:403` | 无头 | 已有入库图 `p1.7-deletion-guard/cleaner-refusal-panel.jpg`；但它覆盖的是**回执排版**，**不覆盖"点击→拒绝→回执"交互链**（那条需要合成点击，本项目禁止） |
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
3. **卡片 token 第三套**（I4/S9）：`MMCard` = `cardSurface`，而本页内联卡 = `contentBackground`，
   monitor 私有卡 = `underPage`。期望：`MMCard` 增加 `background:` 参数或补 `MMCardStyle`
   （`underPage` / `content`），cleaner 与 monitor 一起收口；顺带评估 `tokens.css` 是否补
   content-bg / under-page 两种卡 token（monitor S4 同问）。
4. **容器三页签 vs 页头过滤条的层级**（S1）：两稿都画错位置。期望：协调者定稿"模块内二级导航"
   的统一画法（页签在页头之上独立一行），02/02b 一起重出。
5. **侧栏 footer / 侧栏尾数（全站）**：与 monitor S1/S2 同一处，需 tokens/screen 层统一补组件，
   七张稿一起换，cleaner 的 02/02b 随批。〔**P38f 现读：这一整条已经做完，提请作废**——组件在 `tokens.css:286`，"随批"这件事 `0c61fbf` 当天就带了 02/02b，尾数也在同一笔里清掉；现读 16 张稿在用，cleaner 侧 02/02b/02c 三张都有。全站剩的只有 `components.html` 那一格与磁盘 04b/04e 没画，不属于本模块。〔**P39 那两处也清了**（`components.html:141` 现读是组件本身、04b/04e 补画并重渲染），见 `release-readiness.md` §7.36。〕
6. **要不要补"扫描完成但无可清理"的空态规格**（I4）：需要产品/设计定义"真干净"与"扫描未完成"
   两种空态各自的文案与图标（现在实现把两者混在 `categories.isEmpty` 一个分支里）。
7. **缺失的定格 / 空结果钩子**：cleaner 现有 7 个钩子覆盖了展开态、确认态、安装包夹具、拒绝预演，
   但**没有**"冻结首帧"（骨架）与"扫完为空"两个夹具档。本轮**优先不新增夹具**（照硬约束 4），
   先把需要列出来：若要补，建议照 `GuardianFixtureHooks.swift` 口径写纯粹的展示闸门，
   路径继续硬性只认 `/tmp`。
8. **"真按下删除 → 拿到 PROTECTED"的实机照片仍缺**（`deletion-guard.md` §6 已承认）：要到这一步
   需要合成点击，本项目红线禁止。现有 `cleaner-refusal-panel.jpg` 只覆盖回执排版与文案来源，
   **不覆盖交互链**——这一条按"已知缺口"留档，不试图绕过。

## 6. P6 追加（2026-10-01）：只读空间报告的快照块从没在真机上亮过

§4 里"没能验证到的部分"有一条始终没闭环：这块卡片要 `tmutil` 起子进程，
截图轮从没拍到过它。本轮补拍，当场发现它**在 macOS 11+ 上永远显示"不可用"**
（解析器只认旧表头 `Snapshots for disk`，真机写的是
`Snapshots for volume group containing disk`）。根因、修法与"为什么不报字节"记在
`feature-roadmap.md` 的「P4.6 复核」，这里只留还原度结论。

| 截图（浅色档，无合成点击） | 拍到什么 | 判定 |
|---|---|---|
| `p6-snapshots/real.jpg` | 真机：`本地快照 3 个`，三行全标"系统更新"，卷 `/` | ✅ 修复前这块是"本地快照：不可用" |
| `p6-snapshots/mixed.jpg` | `5 个（Time Machine 2 · 系统更新 2 · 其他 1）`，行上分别带时钟/货箱图标 | ✅ 分档标签与计数同时出现，未撑破行宽 |
| `p6-snapshots/overflow.jpg` | `9 个`，列 6 行 + `另有 3 个快照` | ✅ 溢出分支正常 |
| `p6-snapshots/broken.jpg` | `本地快照：不可用 · 无法解析 tmutil 输出：tmutil: Error: … error: 70` | ✅ 降级态把原始错误带出来，不显示 0 冒充事实 |

两块**新写的文案**在真机宽度下没有截断：条目数后的来历拆分（只有一类时不显示括号）、
以及"只报条数：APFS 不给单个快照的独立占用……别照着它判断要不要删"那段两行说明。

取证手法两条坑记在 `hook-ledger.md` §5（窗口高度钳在约 1080pt，要靠
`MM_CLEANER_FILTER` 缩短上方表格才能让这块进画面；夹具文本自身要有测试）。

**仍未覆盖**：`刷新` 按钮的真实点击链（禁止合成点击）——四张图都靠钩子把状态预置到位，
"点刷新 → actor 重读 → 时间戳更新"这一环只有代码路径，没有照片。

## 7. P5.1 追加（2026-10-01）：开发产物页 02c ↔ 实现

第四个 cleaner 子页（`MM_OPEN_TAB=dev`）。设计稿 `docs/design-system/screens/mmcleaner/02c-cleaner-dev.html`
（渲染图同目录 `.png`），实机证据 7 张在 `docs/verification/p7-dev/`。
**全程零合成输入**：展开、勾选、滚到底、弹确认面板分别由 `MM_DEV_EXPAND` / `MM_DEV_SELECT` /
`MM_DEV_SCROLL` / `MM_DEV_CONFIRM` 四个钩子定格，数据来自 `Scripts/purge-fixture.sh` 造的
`/tmp/macmaster-purge-fixture`（14 项目 / 22 处产物 / 108 MB，**按分支造而不是按体积造**）。

### 7.1 逐元素对照

| 元素 | 设计稿 | 实机（照片编号） | 判定 |
|---|---|---|---|
| 三页签 + 第四枚「开发产物」 | segmented 四档 | `01` | ✅ |
| 页头副标题「N 个项目 · M 处产物 · 扫描于 … · 耗时 … · K 个根没扫完」 | 同结构 | `01`（0.0 秒）/ `06`（16.2 秒 · 2 个根没扫完） | ✅ 尾部字段按可得性长出来，没扫完时不装作扫完 |
| 扫描根 chips + 「另有 N 个」 | `.scopebar` | `01`（7 枚 + 另有 1 个）/ `06`（7 枚 + 另有 12 个） | ✅ 窄窗下 chip 内部省略号截断，「另有 N 个」不丢（`07`） |
| 只读声明 + 缺失根说明 + 截断根警告 | 三条 `.note` | `06` 三条齐（橙色那条点名 `~/Desktop`、`~/Documents`） | ✅ 「截断范围内的项目没被扫过，不等于它们干净」原样落地 |
| 汇总条「N 个项目 · M 处产物 · 可回收 X」 | 可回收 17.1 GB | `02` 103.8 MB / `06` 19.37 GB | ✅ 无可选行时写「无可回收条目」，有可选行但体积没测全写「可回收 —」 |
| 批量按钮「选中 7 天未触碰的」「取消全选」 | 同文案 | `01`（取消全选 disabled）/ `02`（两枚都亮） | ✅ |
| 分组头：chevron + 项目名 + 项目根路径 + 右侧「体积 · N 处」 | 同结构 | `02` | ✅ 整组没有可选行时右侧退化成「无可回收 · N 处」而不是 0 字节 |
| 分组头来历 chip（`pnpm-workspace.yaml`）/ iCloud chip | `.chip` | `02`（`iCloud 同步` 橙色 chip）/ `03`（`pnpm-workspace.yaml` 蓝 chip） | ✅ |
| 行：勾选框 + 名称/相对路径 + 证据小字 + 体积 + 状态徽标 + 访达图标 | `.crow` 四列 | `02` `03` | ✅ 列宽 `22 / 1fr / 84 / 132` 与稿子一致；访达图标稿子里本来就有（`#i-folder`），不算实现自己加的 |
| 徽标四态：`n 天未触碰`(safe) / `目录自述为缓存`(info) / `今天改动过`(warn) / `受保护`(readonly) | 四态 | `02` 见 safe+readonly、`03` 四态同框（60 天 / 自述为缓存 / 3 天前改动过 / 受保护） | ✅ |
| 最强证据行：accent 左描边 + 加粗 + accent-soft 底 | `.crow.strong` | `03`（`toolcache/.gradle`，CACHEDIR.TAG） | ✅ 明暗两档都对（`05`） |
| 不可选行：勾选框置灰占位、名称转 secondary | `.chk.off-allowed` / `.crow.dis` | `03`（`locked/build` 体积 `—`、`stale-site` 两行） | ✅ 占位保列对齐，没有让受保护行整行错位 |
| 底部说明「删除一律移入废纸篓…不执行 git、cargo 这类第三方二进制」 | `.note` | `03` | ✅ |
| 操作条：`已选 N 处 · X` + note + 主按钮 | 已选 4 处 · 12.9 GB / `移入废纸篓` | `01`（已选 0 处，按钮禁用）/ `02`（已选 13 处 · 99.6 MB）/ `06`（已选 45 处 · 6.79 GB + 「扫描未完成，数字只包含已扫到的部分」） | ✅ **本轮改过**：按钮一度写成「移 0 处产物入废纸篓」，与稿子不符（稿子只有 `移入废纸篓`），且禁用态报 0 像算错了数、长标题在最小窗会被截尾 |
| 确认面板：标题带数量 + 一句代价 + 逐行清单 + `另有 N 处` + 取消/移入废纸篓 | `.more` | `04`（13 处，列 12 行 + 「另有 1 处（清单在扫描页里逐行可见）」） | ✅ 清单**不用 ScrollView**（sheet 里会被压成零高，这条是清理主页的老教训） |

### 7.2 两个数字对不上是设计如此，不是漏勾

`06`：可回收 **19.37 GB**，批量按钮按完只剩 **6.79 GB**。差的那 12.58 GB 是
**判定可回收、但活动度不是「7 天以上没碰过」**的行（近期在用 / 活动度探测未知）——
它们**有勾选框**，用户可以自己勾，只是批量按钮不替用户挑。夹具上这笔账能逐行对上：
`02` 可回收 103.8 MB − 已选 99.6 MB = 4.2 MB = `stale-site` 的 `build` 2.1 MB + `node_modules` 2.1 MB，
正是那两行橙色「改动过」。汇总条下方那句「批量按钮只会挑『证据成立且 7 天以上没碰过』的行」
就是为这个差值写的。

### 7.3 拍不到的三态（只有单测，别在照片里找）

| 状态 | 为什么拍不到 | 覆盖在哪 |
|---|---|---|
| 嵌套产物「已计入上一行」 | 发现阶段命中一个产物目录后**就不再往里下钻**，所以真扫里不可能出现"父子都是候选"。它是防御态 | `ProjectArtifactScannerTests`（行折叠 + 嵌套行不单独量体积） |
| 夹具外软链被丢弃 | 发现走 `lstat`，**从不跟随软链**，所以 `outOfSearchRootCandidateCount` 恒为 0；`Projects/sneaky/node_modules → /tmp/macmaster-purge-outside` 这个诱饵压根进不了候选集 | 同上（软链不入列的断言），夹具脚本清点时会显式列出它 |
| 真机上的 iCloud 行 | 本机 `~/Library/CloudStorage` 下没有可判定的产物目录 | 夹具 `DesignWork`（`02` 里那条「位于 iCloud 同步目录：删除会同步到所有设备」）+ 单测 3 条 |

### 7.4 最小窗口（1000×700，`07`）

操作条、批量按钮、主按钮标题全部完整；被压缩的是扫描根 chip 的内部文本（省略号）和
页头副标题（换行）。**没有**出现截主操作按钮标题的情况——那正是把窗口下限从 900 抬到 1000 的理由。

### 7.5 还原度结论

02c 的**结构、文案、四列网格、四态徽标、strong 行、chip、确认面板**在实机上逐条对上了，
唯一发现的偏离（按钮标题带数字）已改回与稿子一致。**没有需要回改设计稿的条目**。
未覆盖项集中在 §7.3 那三个防御态，以及「重新扫描」按钮的真实点击链（同 §6 的老口子：禁合成点击）。

## 8. P6.1 追加（2026-10-03）：截断根分批续扫 02c ②③ ↔ 实现

roadmap 候选 #5 落地。四张实机照片在 `docs/verification/p61-continue/`，由
`Scripts/p61-capture.sh` 一次跑完：**全程零合成点击**——「续扫之后」与「同一根再截断」
两档原本要按一次按钮才进得去，现在由 `MM_DEV_AUTO_CONTINUE` 在首批扫完后自动接一批。
夹具为此加了 12 个 bulky 项目（`Scripts/purge-fixture.sh` §11 的 `Documents/bulk-$i`，
每个 `node_modules` 40 天未碰、4.9 MB），**让截断落在根的内部而不是根的边界**——
否则首批要么整根扫完、要么整根没扫到，②那一档的"复用 + 新测"混合态就拍不出来。

### 8.1 逐元素对照

| 元素 | 设计稿 | 实机（照片编号） | 判定 |
|---|---|---|---|
| 页头「继续扫描这 N 个根」（`play.circle` + prominent） | `.btn.primary` 画在 scopebar 的 `.rowbtns` 里 | `01`（5 个根，亮）/ `03`（5 个根，**置灰**） | ⚠️ 文案与三态一致，**位置有意偏离**，见 §8.3 |
| 副标题「本清单由 N 批拼成 · 最近一批扫于 … · 累计耗时 … · K 个根没扫完」 | 「本清单由 2 批拼成」 | `02`（26 项目 · 34 产物 · 2 批拼成 · 累计耗时 不足 0.1 秒）/ `03`（尾部多「5 个根没扫完」） | ✅ 单批时仍写「扫描于 … · 耗时 …」（`01`），字段按可得性切换 |
| 扫描根 chip 三态：无色 = 之前几批扫完 / 绿底「✓ 本轮」/ 橙底 = 仍在截断 | `.chip.new`（绿）+ `.chip.bad`（橙） | `01` 三枚橙 + 另有 2 个 / `02` 三枚绿「✓ 本轮」 | ✅ 「本轮」只点在**这一批真正扫完**的根上：跑了但再次截断的根仍是橙色 |
| 点名条（可续扫那一支）「有 N 个根扫到一半就超时，本轮不报数：…其余 K 个根已扫完。」 | 同文案 | `01` | ✅ 逐字一致 |
| 点名条（试满那一支）「有 N 个根各扫过 2 次，每次 X 秒的预算都没扫完：…。这里的产物本轮不报数——"扫不完"是这一处的结论，不是"里面很干净"。」 | 同文案 | `03` | ✅ 逐字一致；钩子下的"每次"见 §8.5 |
| 「两条出路」note（放浅一层 / 单项目模式 + 不做后台常驻） | `.note` | `03` | ✅ 只在有根试满 2 次后才出现，`01` `02` 里没有它 |
| 「第 N 批用了 X 秒：上一批已经量到的行直接复用，这一批的预算全花在没测完的行上。」 | 同文案 | `02` `02b` `03` | ✅ 首批（`01`）不出现这句话——它没有"上一批" |
| 汇总条「续扫不替你勾选：新一批扫出来的行全部未选中，只有失去勾选框的行会自动退出勾选。」 | 同文案 | `02` `02b` `03` | ✅ 算术对得上：`02` 可回收 162.8 MB，已选 **13 处 · 71.5 MB**——首批勾上的行活下来了（没被清空），而 13 处仍然只是 34 行里的一小截，新一批报出来的行一枚都没被自动勾上 |
| 组头「第 N 批补全」蓝徽章 | `.chip.info` | `02b`（`toolcache` / `monorepo-app` / `stale-site` 三组亮，`demo-app` / `macmaster-web` / `bulk-1` 不亮） | ✅ **本轮改过判据**，见 §8.2 |
| 操作条「扫描未完成，数字只包含已扫到的部分」 | 同文案 | `01` `03` | ✅ `02`/`02b` 全扫完后换成「未勾选项不会被修改；受保护的行没有勾选框」 |

### 8.2 「第 N 批补全」原来点在错误的东西上

`02` 头一版照片里，`api` 组带着「第 2 批补全」徽章，可它那一行是**读不到**；
`bulk-1` 也带徽章，可它那一行是整行复用的。两个都是错的，而且同一个原因：
旧判据问的是"这一组的**根**有没有在最近一批扫完"，而徽章说的是"这一组**补上了**东西"。
根被重跑过 ≠ 组里多了任何观测。

改成 `ProjectArtifactScanner.rowsCompletedByBatch(base:merged:)`：
**这一批看完证据的行**（体积量到 + 活动度探到）减去**上一批就已看完证据的行**。
于是三种情况各归其位——新报且已量完 → 亮；重测后补上证据 → 亮；整行复用、
或重测完还是读不到 → 不亮。单测 `testRowsCompletedByBatchMarksTheBadgeInsteadOfTheRootRerun`
把这四种行摆在一起钉住。`02b` 里亮徽章的三组恰好都是首批**根本没报到**的组
（`~/Repos`、`~/dev`、`~/www` 都在首批被截断），这正是这句话该指的事。

### 8.3 一处有意的偏离：按钮在页头，不在扫描范围条

02c 把「继续扫描」和「重新扫描」画在 scopebar 右侧的 `.rowbtns` 里，实现把两枚都放在
`MMPageHeader` 的 `actions`。理由有两条：① 全站四页的刷新/主操作都在页头右端，
这一屏没有理由例外；② scopebar 那一行在最小窗要被 chips 挤（§7.4 记的就是这个），
再塞一枚 prominent 按钮会把「另有 N 个」挤出可视区，而那半句恰恰是"根没漏"的凭据。
**该改的是稿子**（已记为 §3 的 S14，本轮没动稿）。

### 8.4 两处文案是自己跟自己打架改出来的

- **「耗时」→「累计耗时」**（多批时）：合并报告的 `duration` 是各批之和
  （`ProjectArtifactScanner.swift:996`），而点名条写的是「第 2 批用了 X 秒」。
  同一屏两个都叫"耗时"、差的是一批与全部，读者只会认为其中一个算错了。
- **「0.0 秒」→「不足 0.1 秒」**：小于 0.05 秒统一写"不足 0.1"。0.0 秒读起来像按钮没生效，
  而这一档要区分的恰恰是"这一批量完了 9 个候选"和"这一批什么都没干"——点名条靠它判断
  有没有在白费预算，写成同一个数就废了。

### 8.5 只有取证钩子会露出来的两处不精确

- `03` 那句「每次 0.02 秒的预算都没扫完」里的数字取的是**全量批**的预算。真机不设钩子时
  两批同为 15 秒，"每次"严格成立；取证时全量批 0.02、续扫批 0.002，这句话在照片那一格里
  只对了前一半。**不为钩子改文案**——为它加一个"两次预算不同"的分支，是给没人会走的路修路。
- ③ 的续扫预算必须**比首批更小**，不能同值。同值 0.02 实测拍不出"扫过 2 次仍截断"：
  第二批要处理的候选比第一批少得多（能复用的整行不再成案），0.02 秒反而够它扫完，
  于是 ③ 落回"全部扫完、按钮消失"那一档。2 毫秒是刻意让它一定在第一个候选的预算检查上收尾。
  这条写在 `Scripts/p61-capture.sh` 顶部，改预算的人必须同时看见。

### 8.6 一个 P5.1 就存在、本轮没修的不自洽

`01`/`03` 里 `demo-app` 这类组：它的根被报成「已扫完」，可组里还挂着一行「读不到（预算用尽）」。
原因是截止点可能正好落在**最后一个候选的测量中间**——根这一侧算扫完了（没有待办候选了），
那一行却没量到。数字上无害：读不到的行不计入合计、不给勾选框，所以"已扫完"不会把漏报的
体积混进「可回收」。但"已扫完"和"这行没测到"同屏，读起来就是矛盾。
真要修得改收尾口径（**根扫完 = 每个候选都出了结论**），代价是把已经量完的根也拖过截止线，
反而多截断几个根。这与 `dev-artifact-continuation.md` §3.5 记的是同一片地（那节讲的是
**总预算饿死排在最后的根**，这节讲的是**根内最后一个候选没量完**），记在这里，留给 P6.2 一起判。

> **复核 2026-10-04：✅ 已落地（`b4c722c`，P6.3b 合并遍历那一轮）**，不是留给 P6.2、是 P6.3b 顺手结掉的。
> 修法比原案想的最省：合并后 `FileTreeWalker.SubtreeWalk.stopReason` 成了显式字段，
> 于是"这一行有没有因预算没出结论"不必再靠 reason 字符串猜——`ProjectArtifactScanner.swift:424-425`
> 在成案循环里就地 `if processed.budgetIncomplete { complete = false }`，判据函数在 `:684-689`
> （注释直接点名"§8.6 修法"）。原案担心的"把已量完的根也拖过截止线"没有发生，因为它**只补记截断账本**、
> 不改变候选的处理顺序。
> **一条关键切分**（`:422-423`、`:685-686`）：权限性读不进（`unreadableDirectories` 非空但 `stopReason == nil`）
> **算已出结论**，根不因此截断——否则每个 TCC 目录都会把根拖成"待续扫"，而重试只会烧预算。
> 这条切分与 §4.2 的"`fail-closed` 的「读不到/protected」是结论不是欠账"同向。
> **判据**：`ProjectArtifactScannerTests.swift:1081` `testScannedRootNeverCarriesBudgetUnfinishedRows`
> （3200 条目 + 0.05 s 根预算，专门把截止线咬在成案中途——旧的出事位置）、
> `:892` `testWalkDerivationUnreadableIsAConclusionNotATruncation`（切分那条）、
> `:879` 超时与取消并成一个结论。
> **还剩一件没结**：`dev-artifact-walk-merge.md` §4.2(b) 的收紧（子树内部读不进 → `size = nil`）
> **仍是待拍板**，现口径照旧静默计 0（`ProjectArtifactScanner.swift:615`、`:676-677` 两处注释都写着
> "§4.2(b) 待拍板，本轮不做"）。所以本节的"已扫完 vs 读不到"矛盾消除了，
> 但"量到了其实没量全"那一条**依然在**，它是口径变更、归协调者拍板，不是这页能自己改的。

### 8.7 还原度结论

02c ②③ 两档的结构与文案逐条对上，唯一偏离是按钮位置（§8.3，有意保留、待改稿）。
本轮从照片里发现并改掉的是 §8.2 那个徽章判据——它不在稿子的对照表里，
是"分批"这个新维度自己带出来的语义：**稿子画的是徽章长什么样，照片才暴露它该在哪些组上**。
另外两档按钮（继续扫描 / 重新扫描）的真实点击链依旧没拍，禁合成点击这条老规矩下，
`MM_DEV_AUTO_CONTINUE` 是它们的替身。

## 9. P6.7 追加（2026-10-04）：开发产物页四个钩子复查（结论：不改）

`hook-ledger.md` §4 #4 那条"其余模块有没有同类竞态"的提请扫到本页时，
逐个查了 `MM_DEV_EXPAND` / `MM_DEV_SELECT` / `MM_DEV_SCROLL` / `MM_DEV_CONFIRM`，三条结论：

1. **`MM_DEV_SELECT=untouched` 没有 P6.6 那种竞态**：它的落点在扫描结果落地的那段收尾里
   （`DevArtifactView.swift:254-274`，在 `report`/`batchCount` 等一次性赋完值之后），
   不是"先 `await` 真实扫描再上夹具"那个形状；续扫那趟走 `applyMerged`（`:248`），
   它**不清空也不重放**勾选（`survivingSelection`，`:265`）——这是设计，不是漏：
   续扫只让已有行改结论，上一批的勾选必须跟着修剪而不是全撤。
   **代价记在这里**：`clean()`/`undo()` 之后不会自动重放这个钩子，
   所以"删完再拍一次 untouched 选中态"这一档拍不到，需要重跑一次扫描。
2. **`MM_DEV_SCROLL=end` 那 400 ms 是等布局，不是等数据**（`DevArtifactView.swift:707`）：
   `.task(id: model.groups.count)` 已经在数据上，剩下赌的是 `LazyVStack` 排完版。
   判据不在日志而在照片——`p5-dev-*` 那批里 footnote 是否进画面。
   本轮不改：把它换成"轮询到行真的可见"需要一个查询滚动位置的 API，
   而那要么引入合成事件（禁止项），要么往页面里塞一条只有测试走的路。
3. **`MM_DEV_EXPAND` 是同步赋值**（`:240`，紧跟在 `report` 那批赋值后面），没有窗口。
   **`MM_DEV_CONFIRM` 有窗口，但不是 P6.6 那种**：它写在 `.task`（`:405`）里，而 `model.scan()`
   在上一行 `:406` **没被 await**——所以面板是在 `report` 还是 nil 的时候打开的。
   它抢的不是数据而是时间：面板内容跟着 `model.report` 落地自己重算，所以只要等够
   （`p61-capture.sh` 的 `SETTLE` 默认 8 秒）就是带行的那一态；把等待调短会拍到一张
   **空白的确认面板**，而它看起来仍然像"确认面板拍过了"。
   **更要紧的一条**：这一档**有照片、没脚本**。`docs/verification/p7-dev/04-fixture-confirm-sheet.jpg`
   在（P5.1d 那轮手工跑的），但 `grep -rn MM_DEV_CONFIRM Scripts/` 于 2026-10-04 现跑是 **0 命中**——
   没有任何脚本会把它再拍一遍。这正是 P6.5b 那条"能力就绪、尚未取证"的镜像形态：
   **照片是真的，只是不可重跑**。改动这块面板的人拿不到回归对照，只能重新手跑一次。
   补 `p7-dev` 那批脚本仍欠着，记在这里。

这一节没有代码改动，写下来是为了让下一轮不必把这四个钩子再查一遍。

## 10. P6.8 追加（2026-10-04）：把 p7-dev 那 7 档变成可重跑

§9 那条"有照片、没脚本"的欠账，这一轮结掉了。`Scripts/p68-dev-capture.sh` 一次跑完
`docs/verification/p7-dev/` 那 7 张（P5.1d 手工产物）对应的钩子组合，**全程零合成点击**，
新照片落在 `docs/verification/p68-dev/`（**没有覆盖 p7-dev 里任何一张旧图**——那是已提交证据）。

跑法（照 `p61-capture.sh` 的入参口径，先隔离构建、别动共享的 `build/MacMaster.app`）：

```
./Scripts/make-app.sh -o /tmp/mm-app-p68dev -s /tmp/mm-scratch-p68dev
./Scripts/purge-fixture.sh                       # 现成夹具，本轮不新造
./Scripts/p68-dev-capture.sh /tmp/mm-app-p68dev/MacMaster.app docs/verification/p68-dev
ONLY=04 ./Scripts/p68-dev-capture.sh …           # 只重拍 04 那一档
```

脚本现跑后 `grep -rn MM_DEV_CONFIRM Scripts/` 从 §9 记的 **0 命中** 变成 **3 命中**（都在这一支脚本里）。

### 10.1 七档的钩子组合与"这就算生效了"的哨兵判据

哨兵不是"两张 md5 不同"，而是**画面上某个真机生产不出来的值**。夹具档的凭据是
`~/Documents/bulk-1 … bulk-12` 这 12 枚项目组——它们是 `purge-fixture.sh` §11 为 P6.1 造的
胖根（每个带一枚 40 天旧的 `node_modules`），真机 `~/Documents` 不会平白长出 12 个同名同旧的项目。
（`MM_PURGE_FIXTURE_HOME` 的守卫命中 `/tmp` 时**不往 stderr 打任何东西**，所以夹具是否真生效只能看画面，
不能只看 `.log`；`.log` 里能证明的是 `MM_APPEARANCE` / `MM_WINDOW_SIZE` 这两支钩子——它们各打一行回执。）

| 档 | 钩子组合 | 旧照片（p7-dev） | 新照片（p68-dev）哨兵判据 |
|---|---|---|---|
| 01 default | 仅 `MM_PURGE_FIXTURE_HOME`（不展开不勾选） | 折叠 14 组、已选 0 处、取消全选禁用 | 折叠列表里出现 `bulk-1…bulk-12` 组头 + 已选 0 处、主按钮禁用 |
| 02 expanded-selected | `+ MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched` | 展开、已选 13 处 · 99.6 MB | 展开后 `bulk-N/node_modules` 带勾选框且被批量勾上（untouched 命中） |
| 03 bottom-states | `+ MM_DEV_SCROLL=end` | 四态徽标同框 | 滚到底：`toolcache/.gradle`「目录自述为缓存」accent 左描边 + `locked/build` 体积「—」+ stale-site 两支 warn「改动过」 |
| 04 confirm-sheet | `+ MM_DEV_CONFIRM=1` | sheet「移除 13 处」列 12 + 另有 1 | sheet 标题「移除 25 处」且清单里逐行是 `~/Documents/bulk-N/node_modules` |
| 05 dark | 同 03，`MM_APPEARANCE=dark` | 深色最强证据行 | 深色下 accent 左描边/四态徽标仍成立（`.log` 有 `MM_APPEARANCE=dark` 回执） |
| 06 real-machine | **不注入夹具**，`MM_DEV_EXPAND=1 MM_DEV_SELECT=untouched` | 真机 100 项目 · 19.37 GB | **反向哨兵**：画面**不含** `bulk-N`、扫的是 `~/Desktop/MacMaster` 等真路径——证明没被夹具污染 |
| 07 min-window | 同 02，`MM_WINDOW_SIZE=1000x700` | 窄窗 chip 省略号 | 1000×700 下 chip 内部省略号截断、"另有 N 个"不丢、主按钮标题不被截尾；`bulk-1` 仍可见 |

### 10.2 哪些档重跑出来与旧照片不一致（如实记）

**6 个夹具档（01/02/03/04/05/07）的画面数字全都变了**，但**不是面板语义变了**，是两件事：

1. **夹具长大了**：`purge-fixture.sh` 在 P6.1（2026-10-03）加了 §11 的 12 个 bulky 项目，
   晚于 P5.1d 拍 p7-dev（2026-10-01）。于是同一批钩子现在扫到 **26 项目 · 34 处产物 · 可回收 162.8 MB**
   （旧照片是 14 · 22 · 103.8 MB），`MM_DEV_SELECT=untouched` 勾上 **25 处 · 158.6 MB**（旧 13 · 99.6 MB），
   确认面板从"移除 13 处（列 12 + 另有 1）"变成"移除 25 处（列 12 + 另有 13）"。
2. **耗时文案改过口径**：§8.4 把 `<0.05 秒` 从"0.0 秒"统一改成"不足 0.1 秒"，所以旧照片副标题里
   那个"耗时 0.0 秒"这一轮**再也拍不出来**，新照片写"耗时 不足 0.1 秒"。

**旧照片要示范的每一支状态都还在、也都还拍得到**（四态徽标、CACHEDIR.TAG 最强证据行、
读不到的 `locked/build`「—」、受保护行、iCloud chip、pnpm-workspace chip、底部说明、窄窗省略号），
本轮没有丢任何一条覆盖。变的只是"多了 12 行 bulk"和"耗时那三个字"。

### 10.3 有没有"这一档不可重跑"

**七档全部零点击重跑成功**，没有一档因"缺钩子到不了"而拍不出。§9 记的那条
`MM_DEV_SELECT` 在 `clean()`/`undo()` 之后不重放的缺口，**卡不到这七档里的任何一张**——
它们全是删除前的扫描态（`apply()` 首批收尾会重放 SELECT/EXPAND），不是"删完再拍"那一态。
真要拍"删完之后的态"依旧拍不到（`clean()` 会 `scan()` 重扫、把清单换成删后新账，
且"按下删除"这一步要合成点击、红线禁），但 p7-dev 那批本来也没有这一张，本轮不新增。

### 10.4 本轮有没有加钩子

**没有。** 结论就是默认答案"不改源码"：七档所需的定格能力四个既有钩子
（`MM_DEV_EXPAND` `:240/:272`、`MM_DEV_SELECT` `:243`、`MM_DEV_SCROLL` `:705`、`MM_DEV_CONFIRM` `:407`）
加 `MM_PURGE_FIXTURE_HOME` `:65` 已全部覆盖，`Packages/MMCleaner/**` 一行未动，
`swift test` 无需跑（无源码改动）。这一节补的只是脚本 + 照片 + 这段说明。

### 10.5 P6.8b 追加：`.log` 开头补两行归因头

§10 那七份 `.log` 与卸载页那 11 份同一种毛病：**只有应用 stderr，没有一句记录本档注入了什么**，
"这条绿"既可能是夹具生效也可能是压根没注入。脚本侧统一补了两行头
（`# <脚本> <档> <时间> app=…` + `# env: …`），判据与实测对应关系记在
`fidelity-uninstaller.md` §12.5。本轮仍**未动 `Packages/MMCleaner/**`**；
`ONLY=01` 重跑一份验证过头与照片对得上：头里的时间 `18:34:54`，页头那句「扫描于 2026-10-04 18:34」
正是同一次运行；夹具 home 在照片里是以 `~` 显示的（`~/Documents/bulk-1…bulk-12` 这 12 行是真机上
不存在的哨兵），所以**这一档的对应关系靠时间戳成立，不靠字面路径**——写日志的人别把
`MM_PURGE_FIXTURE_HOME=/tmp/…` 当成"照片里应当看得见 /tmp"。

## 11. P25 追加（2026-10-07）：页头副标题的**截断合同**，以及单测钉不住的那一半

这一节对应的改动是本轮唯一一处业务源码（`release-readiness.md` §7.16 是主记录，§8 那一格从本轮起划掉）。
它由 P24 那张窄窗照片照出来，所以第一句该说的是**这张照片是怎么拍到的**：
`MM_WINDOW_SIZE` 注入 + `ONLY=02` 只跑清理页那一档，命令可重跑 ——
`SIZE=1000x652 ONLY=02 KEEP_FIXTURE=1 ./Scripts/p18-hook-typo-proof.sh <app> docs/verification/p25-header-narrow`。
`<app>` 必须是**当前树构建**的那一份，否则门禁 exit 4、一张都不出（这是 P23 立的规矩，本轮第二次照做）。

### 11.1 病不在字号，在段序

`MMPageHeader` 的副标题是一条单行文本 + `.lineLimit(1)` + 中间截断，**段序决定谁被吃、长度决定有没有人被吃**。
旧段序把「可释放 X」放中间、「另有 Y 只读」放最后？不是——旧段序是「已扫描 N 类 · 可释放 X · 时间 · 另有 Y 只读」，
1000 pt 下画面读作「已扫描 16 类 · 可释放 3.74 GB…MB 只读」：**被吃掉的正好是只读那一段的数字**。
这一句在界面上的意义是「上面那个可释放数不含只读档」，它在窄窗消失，等于代码里那条自我约束被界面撤销了
（`MMCleaner.swift` 里那句注释写的就是这件事）。

改法两步，都不涉及颜色/间距这类令牌：① 段序按"用户会当成能删多少"的两段压到尾部的原则重排；
② 时间戳从 `yyyy-MM-dd HH:mm` 换成不带年份的 `MM-dd HH:mm`。
第二步单独说：整句原本 53 个字符宽度，而 1000 pt 那一档的预算约 48 —— **去年份不是审美决定，是长度决定**，
它换来的是"尾部那两段能整段读全"。

### 11.2 三档照片，中间那一档故意不同源

| 档 | 目录 | 窗宽 | `# digest:` | 用途 |
| --- | --- | --- | --- | --- |
| 带年份那一版 | `docs/verification/p25-header-yeardate/` | 1000×652 | `7ec32c9+e3b0c442` | 改去年份**之前**的窄窗实拍，证明"重排够了/还差多少"这一步真的被看过 |
| 宽窗 | `docs/verification/p25-header-wide/` | 1280×800 | `fc2a7b2+e3b0c442` | 新段序在默认窗下的读数（§1.2 那一格现值抄自这一张） |
| 验收 | `docs/verification/p25-header-narrow/` | 1000×652 | `fc2a7b2+e3b0c442` | 最终产物在硬最小宽度下的验收档 |

**中间那一档的指纹不等于最终产物，这是有意的**：照片的出处由 `# digest:` 自己说，
统一重拍成同源的那一份，就只剩结论、没有过程了（与 `p23-provenance/` 那五档否证同族做法）。

### 11.3 单测钉住了什么、钉不住什么

`Packages/MMCleaner/Tests/MMCleanerTests/CleanerHeaderContractTests.swift`（92 行 7 条，本轮判据 +7 全在这一包）
钉四件事：① 会被当成"能删多少"的两段必须在尾部；② 时间戳不许占尾部；③ 只读档为零时整段不出现
（不许写"另有 0 字节 只读"）；④ 时间戳用不带年份的短格式。
**钉不住的是"这一句在 1000 pt 放不放得下"**——那要实机照片，所以这一节的三张图和那支脚本才是判据的另一半。
顺带一条旧账：本轮之前 MMCleaner 那 18 条判据里**没有一条**断言过副标题的段序，
这就是"屏上有句话、代码里有注释、测试里没有判据"那种缺口的形状。

### 11.4 残余（没清零，如实记）

1000 pt 那一档改完之后整句仍超预算约 **5 个字符宽度**，现在被吃掉的只剩「可释放」那三个字的标签
（数字本身读得到）。两条真正的解法——副标题换两行、或让页头按窗宽丢段——**都要动 `MMDesign.swift` 那个共享页头**，
它罩着全部九屏，不该在这一轮为一屏改，因此记在 `release-readiness.md` §8 并绑到 P4 那一轮的最小窗口账上。

**P26 复核（2026-10-07，逐屏截断审计）**：这一格**没清零，仍在**——`docs/verification/p26-fix/cleaner.png`
读到 `已扫描 16 类 · 10-07 22:15 · …放 4.51 GB · 另有 141 MB 只读`，被吃的还是「可释」那两个字的标签。
两处新信息进这一笔账：① 共享层已经挂上 `.help(subtitle)`（`MMDesign.swift:299`），
所以这一格从"看不见"降成"悬停才看得见"——**兜底，不是清零**；
② 审计量出的机制是"**预算 = 窗口宽 − 侧栏 − 这一屏动作簇**"，不是窗口宽的函数：
九屏里被截的正是动作簇最宽的两屏（清理页、磁盘页），守护页只有一个按钮，63 字符整句放得下。
所以"按窗宽丢段"那条解法要按**这一屏还剩多少**算，不能按窗口宽度做常数表。
判据、九屏逐屏读数与磁盘页那两档修复见 `docs/analysis/header-truncation-audit.md`。

### 11.5 锚点代价

本轮动了编译输入，`MMCleaner.swift` 副标题那一屏之上整体 **−7 行**（新代码加在文件末尾）。
本文被牵动而现读重指的格子共 **五处**：副标题那格（`:881-891` + 新增的 `:970-1010`）、过滤条总览那格、
`refusalPreview` 那格、`MMRowAction` 那格、过滤条 seg 的 `label` 那格
（另有一格只是副标题的实拍文案串，不带行号所以不进这笔账）——
**这五处的旧值在本轮之前就已经漂了四十到五十行**，P25 只是让这件事不得不被看见；
逐条成因、P24 那一版记的五个旧值与对应符号在 P24 HEAD 上的现值，都在 `release-readiness.md` §7.16 末尾那段。
