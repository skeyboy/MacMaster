# 48 应用卸载 · 设计稿 ↔ 实现 逐元素对照（fidelity-uninstaller）

> **结论先行**：03 / 03b / 03c 三屏在**结构、文案、状态机**三层高度一致——页头工具栏、应用列表、
> 详情四卡、残留分组、孤儿反向扫描、废纸篓提示卡的四档（扫描中 / 尚未扫描 / 无匹配 / 正常）、
> 无权限降级横幅，以及"nil ≠ 0 / 没看过 ≠ 没有"这三条测量诚实红线，实现都**逐条落地**，
> 且 `trashNoticeSummary`/`orphanSummary`/`headerSubtitle` 都按"未扫描写尚未、扫了才写数字"的口径写，
> 没有把"还没扫"渲染成"0 项 · 0 字节"。
> 真正的差异集中在**几何数值与设计稿不一致的共享令牌**、**几处行高稿面自相矛盾**、
> 以及**钩子互锁的文档化缺口**上，全部是低/中严重度，**没有发现高严重度缺陷**
> （本项目最看重的"把不知道写成结论"在卸载路实现侧未被触发）。
>
> 逐元素对照 **约 60 项**，其中 **12 项存在需归属的差异**（**高 0 / 中 2 / 低 10**）：
> **实现该改 3 条**（I1–I3，均为文案/路径写法小不一致）、
> **设计稿该改 7 条**（S2–S8，稿面行高/令牌/缺档）、
> **两边都改·提协调者 2 条**（B1 列表宽度/操作栏高度与共享令牌冲突、B2 `MM_SHOW_TRASH_CONFIRM` 互锁未写清）。

## 0. 对照方法（先说清楚哪些是量出来的，哪些是推导的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmuninstaller/03-uninstaller.html`（1 张：apps 正常态 + 详情）、`03b-uninstaller-orphans.html`（1 张：孤儿列表 + 确认面板）、`03c-uninstaller-trash.html`（3 个 artboard：03c 正常提示卡 / 03c-2 三档 + 横幅 / 03c-3 无权限横幅） |
| 实现 | `Packages/MMUninstaller/Sources/MMUninstaller/`：`MMUninstaller.swift`、`UninstallerModel.swift`、`OrphanScanner.swift`、`ResidualScanner.swift`、`ContainerScanner.swift`、`LaunchServiceScanner.swift`、`TrashWatcher.swift`、`ResidualCollector.swift`、`ResidualNameMatcher.swift` |
| 可用钩子 | `MM_UNINSTALL_PANE`（初始档）、`MM_ORPHAN_FIXTURE_HOME`（孤儿扫描 home + 自动勾选+开确认）、`MM_TRASH_FIXTURE_DIR`（假废纸篓）、`MM_TRASH_SCAN_HOME`（假 home）、`MM_SHOW_TRASH_CONFIRM`（自动开废纸篓清理确认） |
| 几何来源 | 设计系统 README 明确"CSS px 与 SwiftUI pt 一一对应"，故稿内 px 与 Swift 常量可直接比对；**本环境无头、未跑 App、未截图**，凡依赖真实渲染外观（颜色、字重、勾选框外观、垂直对齐）的项标 `⚠️待真机测量`，几何类差异凭 CSS/常量推导、不再编像素 |
| 实机图 | `docs/verification/p1.5-trash/uninstaller-no-fda-banner.jpg`、`uninstaller-trash-notice.jpg` 两图均**已入库存在**（前者对应 03c-3 无权限默认态，后者对应 03c 钩子态卡片 + 4 项残留） |
| 硬约束 | 全程未发合成鼠标/滚轮/键盘；未改 `tokens.css/screen.css/icons.js/Packages/MMUI/Packages/MMCore/Sources/MacMaster`；未 `git` 任何操作；未动 `/var/db/receipts` 相关代码（#46 P1.8 等卸载路收工后再动，本次仅审计） |

> `03b` 与 `03c` 的图标（`i-app-x`/`i-tray-down`/`i-trash`/`i-sparkles`/`i-gauge`/`i-treemap`/`i-activity`/`i-shield-check`/`i-speed`/`i-gear`/`i-search`/`i-refresh`/`i-folder`/`i-list`/`i-box`/`i-power`/`i-lock`/`i-term`/`i-info`/`i-chev-d`）经核对**全部在 `icons.js` 中定义**，无缺图。实现侧改用 SF Symbol（`xmark.circle`/`tray.and.arrow.down.fill`/`trash`/`lock.fill` 等），与设计精灵的注释映射一致。

## 1. 逐元素对照表

严重度定义：**高** = 用户会读到错误结论（把未知当已知 / 把失败当正常）；
**中** = 视觉或语义明显跑偏、或需改共享令牌才能对齐；**低** = 像素级偏差、文案注脚、稿面缺档。

### 1.1 页头与工具栏（03 / 03b / 03c 共用）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「应用卸载」+ 副标题「N 个应用 · 合计 X · 大小已实测」 | `UninstallerModel.headerSubtitle`（`MMUninstaller.swift:206`） | ✅ | 实现：扫描中写"已测 M · K 个测量中"，扫完才写"合计 X · 大小已实测"，稿面只画了稳态那一句，口径一致 | — | — |
| 副标题在「卸载后遗症」档仍显示"应用数/合计" | `headerSubtitle` 不随 `pane` 变 | ⚠️ 稿面取舍 | 稿 03b 同样如此，属稿面决定；语义上副标题与当前档弱相关 | 低 | 设计稿该改 S7 |
| 两枚分段控件：已装应用/卸载后遗症、严格/增强/深度 | `MMUninstaller.swift:77-95` `.pickerStyle(.segmented)` | ✅ | 实现用 `Picker` 分段，`MM_UNINSTALL_PANE` 决定初始档 | — | — |
| 分段控件初始档由 `MM_UNINSTALL_PANE` 决定 | `:62` `Pane(hookValue:)` | ✅ | 钩子缺省回落 `.apps`，符合稿面默认 | — | — |
| 「重新载入」按钮 | `:97-102` | ✅ | 实现在 `isScanningApps` 时禁用；稿面未画禁用态 | 低 | 记录 |
| 工具栏高度 46pt | `MMMetric.toolbar = 46` | ✅ | 与稿/screen.css `.toolbar` 一致 | — | — |
| 侧栏 active = 应用卸载、尾部计数「46」 | 壳工程导航（`MMDestination`），本模块无侧栏绘制权 | ✅（壳渲染） | 侧栏由 `Sources/MacMaster` 渲染，不属本模块交付 | — | — |

### 1.2 应用列表（03 · apps 档）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 列表列宽 300pt | `appList.frame(width: MMMetric.inspector)` → **268**（`MMUninstaller.swift:110`，`MMDesign.swift:89`） | ❌ | 稿画 300pt，实现用共享令牌 `inspector=268pt`，**差 32pt**；改令牌影响其它模块 | **中** | 两边都改·提协调者 B1 |
| 行高 52pt、图标 28pt | `AppListRow` 用 `MMMetric.rowApp=56`、图标 `iconApp=32`（`MMUninstaller.swift:778-823`，`MMDesign.swift:85,92`） | ❌ | 稿 52/28，实现 56/32，各差 4pt | 低 | 设计稿该改 S3 |
| 行内容：图标 + 名称 + 版本·大小 + （残留计数徽标 / 系统应用徽标） | `AppListRow` `:807-819` | ✅ | 实现用真实 `NSWorkspace` 图标（稿用字母占位头像，属稿面惯例），数量徽标用 `accent` + 大小 `tertiary`，与稿一致 | — | — |
| 搜索框「搜索应用…」 | `:227` `TextField` | ✅ | 实现按名称/包名过滤（`filteredApps` `:67`） | — | — |
| 列表页脚「N 个应用 · 已测 M · K 个测量中」 | `listFooter` `:278` | ✅ | 与稿 03/03c 页脚文案一致（03c 稳态为"45 个应用 · 已测 45"） | — | — |
| 列表扫描中转（ProgressView + 扫描应用…）/ 无应用空态 | `appList` `:236-245` | ⚠️ 稿缺 | 稿 03 未画扫描中/空态；实现有 `MMEmptyState`/"扫描应用…"，属实现补状态 | 低 | 设计稿该改 S6（同类） |
| 行右侧"N 项残留"徽标 | `:807-816` | ✅ | `app.residuals.isEmpty == false` 时显示；系统应用显示"系统应用"徽标 | — | — |

### 1.3 应用详情（03 · 选中应用）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 身份头：38pt 图标 + 名称 + `包名 · 大小 · /Applications` | `AppDetailView.identityHeader` `:853` | ✅ | 实现 `deletingLastPathComponent` 取父目录，与稿一致 | — | — |
| 四张统计卡：应用大小/包含文件/残留大小/残留项 | `statsCards` `:876` → `MMStatItem` | ⚠️ 几何 | 实现用共享 `MMStatItem`（`MMDesign.swift:350`）：圆角 `MMRadius.control=8`、底 `cardBackground`；稿 `.cards .c` 圆角 6、底 `--c-card-bg-alt` | 低 | 设计稿该改 S4 |
| 键值对：包名/版本/开发者/最低系统/可执行文件/修改时间/所在文件夹 | `infoSection` `:885` → `MMKeyRow` | ✅ | 实现 `MMKeyRow("版本", "\(version) (\(build))")` 与稿"26.2 (17C4011)"一致；空值填空字符串 | — | — |
| 「将一并移除的残留」+ 徽标"N 项默认不勾选" + "按包名…匹配·不含共享文件" + 全选可删项 | `residualSection` `:902-918` | ✅ | 实现徽标 `unselectedCount` 项、文案"按包名与容器证据匹配 · 不含其他应用的共享文件"，与稿一致 | — | — |
| 残留按风险分组，每行：图标 + 路径 + 原因 + 徽标 + 勾选框 | `residualGroups` `:958` → `ResidualRow`/`MMItemRow` | ✅ | 实现 `MMItemRow`（`MMDesign.swift:682`）逐行：risk 徽标、`risk.allowsDeletion` 为假时勾选框禁用（root 属主项不可选），与稿"root 属主项勾选框直接禁用"一致 |
| 残留行高 28pt（稿 `.res`） | `MMItemRow` 用 `MMMetric.rowRegular`（=44，`MMDesign.swift:738`） | ❌ | 稿 28pt 两行文案放不下且与 03b 的 52pt 自相矛盾；实现统一 44pt 更合理 | 低 | 设计稿该改 S2 |
| 说明："卸载会把 X.app 及勾选的 N 项（合计 X）移到废纸篓，可在 15 秒内撤回" | `confirmationNote` `:999` | ❌ | 实现写"可在 15 秒内撤回"，**漏了"或「最近操作」中**；而它自己的确认面板（`:502`）有完整句——实现内部口径不一致 | 低 | 实现该改 I2 |
| 两个动作按钮：卸载应用并移除勾选的残留（破坏红）/ 仅卸载应用，保留所有残留（borderless） | `:945-954` | ✅ | 实现同稿：破坏红 full-width + borderless small | — | — |

### 1.4 卸载确认面板（03）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「确认卸载」+ 应用/包名/移除/合计 四行 | `confirmSheet` `:489-500` | ✅ | 实现 `MMKeyRow` 列出四项，与稿一致 | — | — |
| 说明："全部内容移到废纸篓，可在 15 秒内或「最近操作」中撤回。标记为谨慎与只读的项不会被删除。" | `:502` | ✅ | 实现这句**完整**，与 §1.3 的 I2 形成对照（确认面板对、详情注脚漏） | — | — |
| 按钮：取消 / 卸载（破坏红） | `:509-515` | ✅ | 实现 `role:.destructive` + `borderedProminent` | — | — |
| 面板宽 420pt | `:519` `.frame(width: 420)` | ✅ | 与稿一致 | — | — |

### 1.5 卸载后遗症列表与确认（03b）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 行：勾选框 + 图标 + 名称 + `displayPath · 在已装应用里找不到 owner` + 谨慎徽标 + 大小 + 在访达中显示 | `OrphanRow` `:1049` → `MMItemRow`，副标题 `:1057` | ✅ | 实现 `risk:.caution` → "谨慎"徽标；副标题模板与稿逐字一致 | — | — |
| 行高 52pt（稿 `.orow`） | `MMItemRow` `rowRegular=44` | ❌ | 稿 52，实现 44，差 8pt | 低 | 设计稿该改 S2 |
| 操作栏："可疑残留 N 项 · 已选 M 项 · 字节" / "反向判断…全部默认不勾选" + 反查残留 + 移到废纸篓(禁用) | `orphanActionBar` `:410` + `orphanSummary` `:403` | ✅ | 实现未扫描写"尚未反查 · 点右侧「反查残留」扫一遍 ~/Library"（非"0 项"）；已扫写"可疑残留 N 项 · 已选 M 项 · 字节"，与稿一致；移到废纸篓在 `selectedOrphanIDs.isEmpty` 时禁用，与稿一致 |
| 反向判定口径（≥3 段点分/每段≥2/总长≥10、`com.apple.*` 永不选、`Composer.Helper` 算主人、UUID 尾段剥掉、Containers 整条跳过、系统域不扫） | `OrphanScanner.judge` `:95`、`isOwnerShaped` `:142`、`strippingUUIDTailSegment` `:134` | ✅ | 实现逐条对应稿面 cap 说明；`minNameLength=10`、`applePrefixes=["com-apple"]`（归一后 `com.apple`）、UUID 剥离、派生标识归属，全部对齐 |
| 确认面板"把 N 项可疑残留移入废纸篓？" + 逐条**绝对路径** + 大小 + 取消/移入废纸篓 | `orphanConfirmSheet` `:436`，逐行 `Text(item.path)` | ✅ | 实现用 `item.path`（绝对路径），与稿"故意不沿用 ~/Library 缩写"一致；宽 480，与稿一致 |
| "找不到 ≠ 没在用"提示文案 | `:441` | ✅ | 实现与稿逐字一致 | — | — |
| 未反查 / 没有发现没有主人的残留 两档空态 | `orphanPane` `:363-371` | ⚠️ 稿缺 | 稿 03b 只画了已扫出列表，**未画**"还没有反查过"/"没有发现没有主人的残留"两档；实现有 `MMEmptyState`（前者标题"还没有反查过"、后者"没有发现没有主人的残留"） | 低 | 设计稿该改 S6 |
| 正在反查扫描态（ProgressView + 正在反查残留归属…） | `orphanPane` `:355-362` | ⚠️ 稿缺 | 稿未画；实现有，但切到该档即自动扫描、几乎抓不到 | 低 | 设计稿该改 S6 |

### 1.6 废纸篓提示卡（03c 正常 / 03c-2 三档）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡片仅在「已装应用」档且监听器报出到达时出现 | `trashRegion` `:574`（`pane == .apps && arrivals.isEmpty == false`） | ✅ | 与稿 03c（apps 档）一致；孤儿档不显示 | — | — |
| 头部：`tray.and.arrow.down.fill` + 标题（单应用"刚拖进废纸篓：X" / 多应用 Picker + "有 N 个应用刚进废纸篓"）+ 徽标"本体已在废纸篓"(info) + 在访达中显示 + 忽略 | `trashNoticeCard` `:583-615` | ✅ | 实现 `MMBadge("本体已在废纸篓", informational, "trash")`；多应用走 `Picker`；与稿一致 |
| 头部路径行：`~/.Trash/Foo.app · com.example.Foo`（等宽、中段截断） | `:617-630` 用 `trashArrival?.path`（绝对路径） | ❌ | 实现给**绝对路径**（`/Users/lee/.Trash/Foo.app`），而卡片内残留行用 `~/` 缩写（`displayPath`）——同卡两种写法；稿头部用 `~/.Trash` 缩写 | 低 | 实现该改 I1 |
| 扫描中档：ProgressView + "按包名与容器证据扫残留…" + 汇总"扫描中…" | `:632-636` + `trashNoticeSummary` `:695` | ✅ | 与 03c-2①一致 |
| 尚未扫描档："还没扫残留…" + 汇总"尚未扫描" | `:637-640` + `:696` | ✅ | 与 03c-2②一致；**不是**"0 项 · 0 字节" |
| 无匹配档："按当前敏感度没有匹配到残留文件。" + 汇总"已选 0 项 · 0 字节" | `:641-644` + `:696` | ✌ | 与 03c-2③一致；此档是"真扫过结论空"，写 0 正确 |
| 正常档：残留行（safe 默认勾 / caution 默认不勾 / root 勾选框禁用）+ 汇总"已选 N · 字节 · 未勾选 M" + 全选可删项 + 清理勾选的残留 | `:646-684` + `:697` | ✅ | 实现 `trashResidualBinding` 仅 `risk.allowsDeletion` 时可勾；汇总模板与稿"已选 2 项 · 6.3 MB · 未勾选 2 项"一致；按钮 `borderedProminent`+`destructive` |
| 卡片底色 info 8% | `:689` `MMColor.soft(informational, 0.08)` | ✅ | 与稿 `color-mix(info 8%)` 一致 |
| 卡片内残留行高 | `MMItemRow` `rowRegular=44` | ⚠️ 稿 03c 未单列 | 稿 03c 卡片行 `.nrow` 高 46pt，实现 44pt；差 2pt | 低 | ⚠️待真机测量 |

### 1.7 无权限降级横幅（03c-3）+ 废纸篓清理确认面板

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 横幅：`lock.fill` + 标题"读不到废纸篓" + 带错误码详情 + "打开系统设置"（深链 Privacy_AllFiles） | `trashRegion` `:566-573` → `MMPermissionBanner`（`MMDesign.swift:443`）；`fullDiskAccessPane` `MMUninstaller.swift:525` | ✅ | 实现 `needsFullDiskAccess ? "读不到废纸篓" : "废纸篓现在读不了"`；详情拼 `reason + " 在系统设置里授予…重启应用才会生效"`；`reason="无法打开废纸篓目录：Operation not permitted（错误码 1）。"` 与稿逐字一致（见 `trash-watch-fda.md` 本机实测） |
| 目录不存在走另一文案且**不放授权按钮** | `TrashWatcher.start` `:120-124` `needsFullDiskAccess:false` → `MMPermissionBanner(settingsPane:nil)` | ✅ | 实现区分 ENOENT（目录不存在，无按钮）与 EPERM/EACCES（要授权），与 `trash-watch-fda.md` 红线 2 一致 |
| 页面其余部分不受影响（列表/卸载动作不依赖读废纸篓） | `trashRegion` 仅替换卡片区，列表/详情照常 | ✅ | 与稿"页面其余部分不受影响"一致；`uninstaller-no-fda-banner.jpg` 已证 |
| 横幅底色 warning 10% | `MMPermissionBanner` `soft(caution,0.10)` | ✅ | 与稿 `color-mix(warning 10%)` 一致 |
| 废纸篓清理确认面板（"清理 X 的 N 项残留？" + 逐路径 + 合计 + 取消/移入废纸篓） | `trashConfirmSheet` `:723` | ⚠️ 稿缺 | 稿 03c **未画**此确认面板（孤儿确认 03b 有、废纸篓清理确认没有）；实现 `deletionRoots(for:)` 单点给路径、不含本体（`:724,494`），与红线 3 一致 | 低 | 设计稿该改 S5 |
| `MM_SHOW_TRASH_CONFIRM` 触发确认面板 | `trashConfirmHook` `:533`（需 `fixtureScanHome() != nil` 且环境变量=1） | ⚠️ 文档缺口 | 单设 `MM_SHOW_TRASH_CONFIRM=1` **不会**触发，必须同时设 `MM_TRASH_SCAN_HOME`（且限 /tmp）；稿/README 描述"自动开确认面板"未写此互锁 | **中** | 两边都改·提协调者 B2 |

### 1.8 状态覆盖核对

| 状态 | 设计稿是否画 | 实现是否有 | 可达路径 | 一致性 |
| --- | --- | --- | --- | --- |
| 03 apps 正常（选中应用有残留） | ✅ | ✅ | 真实数据 | 一致 |
| 03 apps 未选应用（空态） | ✅（03c 借用） | ✅ `MMEmptyState("未选择应用")` | 真实 | 一致 |
| 03 apps 扫描中 / 测量中 | ❌ | ✅ | 真实 | 实现补档 |
| 03 apps 无应用 | ❌ | ✅ | 真实（/Applications 空） | 实现补档 |
| 03b 孤儿正常 | ✅ | ✅（含 `MM_ORPHAN_FIXTURE_HOME` 自动勾选+确认） | 真实 ~/Library 或夹具 | 一致 |
| 03b 孤儿扫描中 | ❌ | ✅（转瞬） | 真实 | 稿缺 |
| 03b 孤儿未反查 / 无主人 | ❌ | ✅ | 真实 | 稿缺 |
| 03c 提示卡正常（有残留） | ✅ | ✅（`MM_TRASH_FIXTURE_DIR`+`MM_TRASH_SCAN_HOME`） | 夹具 | 一致，实机图已存 |
| 03c 扫描中 | ✅（03c-2①） | ✅（转瞬） | 夹具 | 一致 |
| 03c 尚未扫描 | ✅（03c-2②） | ✅（转瞬） | 夹具 | 一致 |
| 03c 无匹配 | ✅（03c-2③） | ✅ | 需无残留的夹具 app | 一致 |
| 03c 多应用 Picker | ✅（03c cap） | ✅（转瞬） | 需 2+ 到达 | 一致 |
| 03c 无权限横幅 | ✅（03c-3） | ✅ | 真实无 FDA（默认态） | 一致，实机图已存 |
| 03c 废纸篓清理确认 | ❌ | ✅ | `MM_TRASH_SCAN_HOME`+`MM_SHOW_TRASH_CONFIRM` | 稿缺 |

## 2. 实现该改（I · 3 条，均低）

1. **【低】I1 · 提示卡头部路径用绝对路径，卡片内残留行用 `~/` 缩写**（`MMUninstaller.swift:617-630` 用 `trashArrival?.path`）
   头部写 `/Users/lee/.Trash/Foo.app`，下方残留行写 `~/Library/...`，同卡两种写法。建议头部也走
   `displayPath`（或统一绝对），与稿 `~/.Trash/Foo.app` 对齐。
2. **【低】I2 · 详情注脚漏"或「最近操作」中"**（`AppDetailView.confirmationNote` `:999`）
   写"可在 15 秒内撤回"，但同模块确认面板（`:502`）与 `trash-watch-fda.md` 的撤回语义都含"最近操作"。
   建议补成"可在 15 秒内或「最近操作」中撤回"，与自身确认面板口径一致。
3. **【低】I3 · 操作栏 note 在 `unselectedCount>0` 时写"未勾选的 N 项不会被修改"**（`actionBar` `:316`）
   稿 03 写"未勾选项不会被修改"。实现更具体（带数字），但与稿面文案不一致；若要严格还原稿面，
   应改为不带 N 的版本，或反过来让稿面补数字——属文案注脚级，低。

## 3. 设计稿该改（S · 7 条）

1. **【低】S2 · 残留/孤儿行高稿面自相矛盾**：03 残留行 `.res` 画 28pt（两行文案放不下）、03b 孤儿行 52pt，
   实现 `MMItemRow` 统一 44pt。建议稿面两处都改到 44pt。
2. **【低】S3 · 应用行图标 28pt、行高 52pt 与令牌不符**：实现 `iconApp=32`/`rowApp=56`；建议稿面改到 32/56，或确认令牌要调。
3. **【低】S4 · 统计卡用了非标准令牌**：稿 03 `.cards .c` 底用 `--c-card-bg-alt`、圆角 6pt，而实现 `MMStatItem`
   用 `cardBackground` + `MMRadius.control=8`；建议稿面改用 `--c-card-bg` 与圆角 8，与全站组件对齐。
4. **【低】S5 · 03c 缺"废纸篓清理确认面板"稿面**：孤儿确认 03b 有（第二 artboard），废纸篓清理确认（
   `trashConfirmSheet`）没有，建议补一张对齐 03b 的确认稿。
5. **【低】S6 · 03b 缺空态/扫描态稿面**："还没有反查过""没有发现没有主人的残留""正在反查残留归属…"
   三档实现都有、稿未画，建议补（与 03c-2 同处理）。
6. **【低】S7 · 副标题在"卸载后遗症"档仍显示应用数/合计**：03b 如此、实现同稿；语义上弱相关，建议稿面决定。
7. **【低】S8 · 03c-3 工具栏副标题"已测 0 · 45 个测量中"是瞬时快照**：无 FDA 时应用扫描**独立进行**，
   稳态是"45 已测"；稿面易误导为"无权限时应用不扫描"，建议加一句注脚。

## 4. 两边都改 · 提请协调者（B · 2 条，均中）

1. **【中】B1 · 列表宽度 / 操作栏高度 设计硬编码数值 vs 共享令牌**：
   稿把 `applist` 画成 **300pt**、操作栏写 **46pt**；实现用共享 `MMMetric.inspector=268pt`、`MMActionBar` 高 **52pt`。
   改 `MMMetric.inspector` 或 `MMActionBar` 高度会影响其它模块（monitor 等多处用 `inspector`/`actionBar`）。
   **提协调者决定**：要么设计改到 268/52 与令牌一致，要么为卸载页引入屏级覆盖宽度——不要模块私下改共享令牌。
2. **【中】B2 · `MM_SHOW_TRASH_CONFIRM` 互锁未写清**：
   该钩子**单设不触发**，必须同时设 `MM_TRASH_SCAN_HOME`（且只认 /tmp）才会自动开确认面板
   （`trashConfirmHook` `MMUninstaller.swift:533`）。
   这是"终点=删除按钮、绝不能指向真实用户目录"的有意互锁，但 README §2 与 03c cap 只写"自动开确认面板"。
   **提协调者**：在 README/稿面补一句"需配合 `MM_TRASH_SCAN_HOME`（限 /tmp）"，避免验证者单设钩子误以为失效。

## 5. 没能验证到的部分（逐条写明缺什么，不写"应该没问题"）

以下状态**只在代码里读到分支**、实机一张都没截到，或本机无法构造（严格遵守"测量诚实"红线，不编结论）：

| # | 未验证项 | 为什么验不了 | 需要什么才能验 |
| --- | --- | --- | --- |
| 1 | 03b 孤儿"正在反查残留归属…"扫描态 | 切到该档即 `startOrphanScanIfNeeded` 自动扫描，本地盘几乎一帧返回；且无 HOLD 钩子 | 一个冻结扫描返回的 `MM_ORPHAN_FIXTURE_HOME` HOLD 钩子，或单测/预览快照 |
| 2 | 03b"还没有反查过"空态 | 进档即触发扫描，"未扫描"只活一帧 | 同上，或允许"进档不自动扫"的调试开关 |
| 3 | 03c 提示卡"扫描中…"档 | 到达后立刻 `scanTrashResiduals`，转瞬即过 | 一个冻结残留扫描的钩子（现有钩子无 HOLD 语义） |
| 4 | 03c"尚未扫描"档 | 同上，到达后即扫 | 同上 |
| 5 | 03c"按当前敏感度没有匹配到残留文件"档 | 需一个**本体在废纸篓、但按其敏感度零残留**的夹具 app；现有夹具（`uninstaller-trash-notice.jpg`）是有残留的 | 一个零残留夹具 app + `MM_TRASH_FIXTURE_DIR`/`MM_TRASH_SCAN_HOME` |
| 6 | 03c 多应用 Picker（"有 N 个应用刚进废纸篓"） | 需一次拖入 2+ `.app` 并监听；本机/无头都难构造 | 一个含 2+ app 的假废纸篓 + 监听器（或批量注入 arrivals 的钩子） |
| 7 | 授予完全磁盘访问后"确实能读废纸篓" | 给 ad-hoc 构建授 FDA 需人工点系统设置，不在自动化范围；`trash-watch-fda.md` 已标"未在本机验证" | 人工授权后重跑截图（Apple 文档 + Pearcleaner/Mole 共识认为可读，但本机未实证） |
| 8 | 浅色模式下的实机配色 | 现有两张实机图均深色/夹具；稿按设计系统浅色档重绘 | 浅色外观下重跑截图流程 |
| 9 | 03 apps 扫描中 / 无应用 / 未选应用 三档的精确像素 | 可构造但未见实机图；几何凭 CSS/常量推导 | 实机截图核对（见 §1.2/§1.8） |

**已验证的部分**（与上表相对，避免把整页写成"没验过"）：页头/工具栏文案与分段控件、应用列表行内容与徽标逻辑、
详情四卡与键值对、残留分组与"root 属主项勾选框禁用"、孤儿反向判定口径（minNameLength/applePrefixes/UUID 剥离/派生标识）、
三类确认面板文案、废纸篓提示卡四档的**文案与汇总口径**（扫描中/尚未扫描/无匹配/正常）、
无权限横幅的**错误码与授权深链**、"nil≠0 / 没看过≠没有"三条红线的实现落地。
其中 **03c-3 无权限横幅**与 **03c 提示卡（夹具态）** 两档有实机图佐证（`uninstaller-no-fda-banner.jpg` / `uninstaller-trash-notice.jpg`）。

## 6. 可注入档位映射（对照现有 5 个钩子）

| 状态 | 钩子组合 | 说明 |
| --- | --- | --- |
| 03 apps 正常 | （默认，真实数据）或 `MM_UNINSTALL_PANE=apps` | — |
| 03b 孤儿正常 + 自动确认 | `MM_ORPHAN_FIXTURE_HOME=/tmp/...` | 自动勾选全部并开确认（合成点击进不了勾选框） |
| 03c 提示卡（夹具态） | `MM_TRASH_FIXTURE_DIR=/tmp/...` `MM_TRASH_SCAN_HOME=/tmp/...` | 对应 `uninstaller-trash-notice.jpg` |
| 03c 清理确认自动开 | 上组 + `MM_SHOW_TRASH_CONFIRM=1` | 需 `MM_TRASH_SCAN_HOME` 同时存在（B2 互锁） |
| 03c 无权限横幅 | 钩子全关（默认无 FDA 态） | 对应 `uninstaller-no-fda-banner.jpg` |

> 所有 `/tmp` 钩子均按 `TrashWatcher.fixtureEnvironmentValue`（`TrashWatcher.swift:105`）口径：
> 只认 `/tmp/` 或 `/private/tmp/` 之下，越界写 stderr 并忽略——本审计未新增任何夹具文件，如需补 B1/B2 之外的夹具，
> 一律按 `GuardianFixtureHooks.swift` 的"纯展示数据、不写盘、不合规则整钩作废"口径走，否则列进 §4/提请协调者。

## 7. 关于 #46 P1.8（/var/db/receipts 只读归属接孤儿扫描）

本次**仅审计、未改动**任何 receipts 相关代码（按协调计划等卸载路收工）。现状已核对：
`ResidualCatalog` 把 `/private/var/db/receipts`（安装包账本）列为**红线条目、不进默认清单**
（`ResidualScanner.swift:171-173` 注释），即 receipts 目录**当前不被读取/不被当残留**，
与 P1.8"只读归属"方向一致；但"receipts 归属接入孤儿扫描"本身尚未落地，不属本审计范围，留待 P1.8。
