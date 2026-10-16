# 48 应用卸载 · 设计稿 ↔ 实现 逐元素对照（fidelity-uninstaller）

> 后续更新：原审计表是修复前的历史快照。P1 已让“仅卸载应用”与“应用加残留”都进入确认面板，并展示确切路径及包含本体的合计；只读残留不会进入最终删除根。当前原生窗口证据见 [P1 清理与卸载验收](p1-cleaner-uninstaller.md)。

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
| 实现 | `Packages/MMUninstaller/Sources/MMUninstaller/`：`MMUninstaller.swift`、`UninstallerModel.swift`、`OrphanScanner.swift`、`ResidualScanner.swift`、`ContainerScanner.swift`、`LaunchServiceScanner.swift`、`TrashWatcher.swift`、`ResidualCollector.swift`、`ResidualNameMatcher.swift`〔P43c 现读：该目录 **15 个文件**，本格只列了 9 个，缺 `AppScanner.swift`、`AppProvenance.swift`、`AppFolderWatcher.swift`、`RunningAppProbe.swift`、`SteamLauncherProbe.swift`、`UninstallFixtureHooks.swift`——都是 §8/§9/§13/§14/§15 那几轮各自新增的判层，写进清单却没回填本格〕 |
| 可用钩子 | `MM_UNINSTALL_PANE`（初始档）、`MM_ORPHAN_FIXTURE_HOME`（孤儿扫描 home + 自动勾选+开确认）、`MM_TRASH_FIXTURE_DIR`（假废纸篓）、`MM_TRASH_SCAN_HOME`（假 home）、`MM_SHOW_TRASH_CONFIRM`（自动开废纸篓清理确认）〔P43c 现读：源码里是 **10 枚**，本格只列了 5 枚。缺的 5 枚是 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME`（`MMUninstaller.swift:54`）、`MM_UNINSTALL_CONFIRM_MODE`（`:79`）、`MM_UNINSTALL_SELF_ECHO`（`:103`）、`MM_UNINSTALL_SELECT`（`:110`）、`MM_UNINSTALL_SENSITIVITY`（`UninstallerModel.swift:184`）；本文列的那 5 枚调用点在 `MMUninstaller.swift:43/164/806`（**P46f 现读**：后两枚此前写 142 与 779）+ `TrashWatcher.swift:110/123`。还有一句要钉死：**这一页没有 HOLD 钩子**——全仓带 HOLD 的键现读只有 `MM_DISK_HOLD`、`MM_MONITOR_HOLD` 两枚，所以 §5 前四行"没有冻结钩子"到本轮仍成立〕 |
| 几何来源 | 设计系统 README 明确"CSS px 与 SwiftUI pt 一一对应"，故稿内 px 与 Swift 常量可直接比对；**本环境无头、未跑 App、未截图**，凡依赖真实渲染外观（颜色、字重、勾选框外观、垂直对齐）的项标 `⚠️待真机测量`，几何类差异凭 CSS/常量推导、不再编像素〔P43c 现读：**"本环境无头、未跑 App、未截图"这一句早已过期**，但它把后面所有格的口径都带偏了——卸载页现在有一整批带窗口的实机照片，本格下面两行与 §4 都得按照片重判。现读该页证据族 **13 个目录 63 张**〔P43c 复算更正：本句初稿写作"12 个目录 54 张"，是照抄上一格漏改的分项相加——下面逐项枚举本身就是 13 项、相加 63（`p4-light-dark` 目录共 18 张，本页只计卸载页那 2 张）〕：`p1.5-trash` 2、`mmuninstaller` 2、`p7-brew` 9、`p4-light-dark` 卸载页 2（light/dark 各一张）、`p11-hardened/watch-trash-base` 1、`watch-trash-hr` 1、`p68-brew` 9、`p68-trash` 2、`p31-running` 7、`p32-steam` 9、`p32b-steam` 12、`p33b-nesting` 6＋`p32b-crosscheck` 1〕 |
| 实机图 | `docs/verification/p1.5-trash/uninstaller-no-fda-banner.jpg`、`uninstaller-trash-notice.jpg` 两图均**已入库存在**（前者对应 03c-3 无权限默认态，后者对应 03c 钩子态卡片 + 4 项残留）〔P43c 现读：两图确实都在（目录里各 1 张、无 `.log`）。但这格是 §0 里唯一还只提这两张的地方，账要补全：上面那 63 张里〔P43c 复算更正：初稿此句写"54 张"，随 §0 几何来源那格的同一个错数一路带到 §5 表尾，三处已同轮改成 63；另"34 张 + 交叉 1 张"口径已核——p33b 目录 8 份 `.log` 只有 6 张配图，`fixture-rows.log`、`ownership-review.log` 是分析日志、无照片〕，**只有 p31/p32/p32b/p33b 四族（34 张 + 交叉 1 张）的 `.log` 带 `# digest:` 源码指纹**——逐族 `grep -c digest`：p31 7/7、p32 9/9、p32b 12/12、p33b 8/8；而 `p68-brew` 0/9、`p68-trash` 0/2、`p11-hardened` 两族 0/1+0/1，`grep -l digest Scripts/*.sh` 里也没有 `p68-brew-capture.sh`/`p68-trash-capture.sh`（它们出片早于 P23b 那道门禁）。所以"照片与二进制同源"这句话对这 11 张**说不成立**，它们的归因只有 §12.5 那两行手写头（`# <脚本> <档> <时间> app= fixture=` + `# env:`）〕 |
| 硬约束 | 全程未发合成鼠标/滚轮/键盘；未改 `tokens.css/screen.css/icons.js/Packages/MMUI/Packages/MMCore/Sources/MacMaster`；未 `git` 任何操作；未动 `/var/db/receipts` 相关代码（#46 P1.8 等卸载路收工后再动，本次仅审计） |

> `03b` 与 `03c` 的图标（`i-app-x`/`i-tray-down`/`i-trash`/`i-sparkles`/`i-gauge`/`i-treemap`/`i-activity`/`i-shield-check`/`i-speed`/`i-gear`/`i-search`/`i-refresh`/`i-folder`/`i-list`/`i-box`/`i-power`/`i-lock`/`i-term`/`i-info`/`i-chev-d`）经核对**全部在 `icons.js` 中定义**，无缺图。实现侧改用 SF Symbol（`xmark.circle`/`tray.and.arrow.down.fill`/`trash`/`lock.fill` 等），与设计精灵的注释映射一致。

## 1. 逐元素对照表

严重度定义：**高** = 用户会读到错误结论（把未知当已知 / 把失败当正常）；
**中** = 视觉或语义明显跑偏、或需改共享令牌才能对齐；**低** = 像素级偏差、文案注脚、稿面缺档。

### 1.1 页头与工具栏（03 / 03b / 03c 共用）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「应用卸载」+ 副标题「N 个应用 · 合计 X · 大小已实测」 | `UninstallerView.headerSubtitle`（`MMUninstaller.swift:371-379`，用在 `:177` 的 `MMPageHeader`；**P46f 现读**：此前本文写 344-352 / 150，P46c 与 P46e 在它上方共插 27 行） | ✅ | 实现：扫描中写"已测 M · K 个测量中"，扫完才写"合计 X · 大小已实测"，稿面只画了稳态那一句，口径一致。**P16 两处更正**：本文此前把它记成 `UninstallerModel.headerSubtitle`、位置写在 `MMUninstaller.swift` 的 206 行——行号是写作当时的位置（已漂），而且**归属也错**：`headerSubtitle` 在 `UninstallerView` 里，`UninstallerModel` 是 `UninstallerModel.swift:127` 那个类，它没有这个属性。行号判据（在不在文件里、是不是空行）抓不出这种错，这一条是顺着被点名的行把周围三行一起读出来的。**P36 第五笔债再指一次**：`:326-332` 那一读也已漂，现读那一格落在 `MMUndoToast` 的 `.overlay` 上 | — | — |
| 副标题在「卸载后遗症」档仍显示"应用数/合计" | `headerSubtitle` 不随 `pane` 变 | ⚠️ 稿面取舍 | 稿 03b 同样如此，属稿面决定；语义上副标题与当前档弱相关 | 低 | 设计稿该改 S7 |
| 两枚分段控件：已装应用/卸载后遗症、严格/增强/深度 | `MMUninstaller.swift:173-188` 两枚 `Picker`，`.pickerStyle(.segmented)` 在 `:183`/`:193`〔**P46f 现读**：两枚 `.pickerStyle` 此前本文写 161 与 171（P43c 那一读），整段 **+22 行**；`MM_UNINSTALL_PANE` 那行 `@State` 在 `MMUninstaller.swift:164`〕 | ✅ | 实现用 `Picker` 分段，`MM_UNINSTALL_PANE` 决定初始档（P16 现读：本文此前记 77–95 行，是写作当时的位置） | — | — |
| 分段控件初始档由 `MM_UNINSTALL_PANE` 决定 | `:62` `Pane(hookValue:)` | ✅ | 钩子缺省回落 `.apps`，符合稿面默认 | — | — |
| 「重新载入」按钮 | `:97-102` | ✅ | 实现在 `isScanningApps` 时禁用；稿面未画禁用态 | 低 | 记录 |
| 工具栏高度 46pt | `MMMetric.toolbar = 46` | ✅ | 与稿/screen.css `.toolbar` 一致 | — | — |
| 侧栏 active = 应用卸载、尾部计数「46」 | 壳工程导航（`MMDestination`），本模块无侧栏绘制权 | ✅（壳渲染） | 侧栏由 `Sources/MacMaster` 渲染，不属本模块交付〔**P39 现读把这一格的两处不实改判**：① 本模块四份稿（03/03b/03c/03e）里**从来没有 "46" 这个尾部计数**，"46" 只出现在元素清单 `components.html:136` 的组件示例上；② 03c/03e 那两格确实画了「应用卸载」尾数，但值是 `45`，而**实机永远不给非清理行挂尾数**（`MainWindow.swift:103-110` 只对 `module.id == cleaner` 且 `.measured` 才画），所以这一格原判 ✅ 是假的——它是 P38f 翻出来的一条新账（`release-readiness.md` §7.35 第 3 项），**P39 已把那两个 `45` 删掉并重渲染两页**，「系统清理 1.3 GB」按合同留着，判据在 §7.36〕 | — | — |

### 1.2 应用列表（03 · apps 档）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 列表列宽 300pt | `appList.frame(width: MMMetric.inspector)` → **268**（`MMUninstaller.swift:213`，`MMDesign.swift:120`；**P46f 顺带修一处旧锚**：本文此前记的 186 在 HEAD 就落在 `trashRegion` 那一行，`.frame(width:)` 当时在 191，本轮再 +22） | ❌ | 稿画 300pt，实现用共享令牌 `inspector=268pt`，**差 32pt**；改令牌影响其它模块（P16 现读：本文此前记 110 行 / 89 行，两处都漂） | **中** | 两边都改·提协调者 B1 |
| 行高 52pt、图标 28pt | `AppListRow` 用 `MMMetric.rowApp=56`、图标 `iconApp=32`（`MMUninstaller.swift:1614-1690`，`MMDesign.swift:113`、`:128`） | ❌ | 稿 52/28，实现 56/32，各差 4pt | 低 | 设计稿该改 S3 |
| 行内容：图标 + 名称 + 版本·大小 + （残留计数徽标 / 系统应用徽标） | `AppListRow` `:807-819` | ✅ | 实现用真实 `NSWorkspace` 图标（稿用字母占位头像，属稿面惯例），数量徽标用 `accent` + 大小 `tertiary`，与稿一致 | — | — |
| 搜索框「搜索应用…」 | `:227` `TextField` | ✅ | 实现按名称/包名过滤（`filteredApps` `:67`） | — | — |
| 列表页脚「N 个应用 · 已测 M · K 个测量中」 | `listFooter` `:278` | ✅ | 与稿 03/03c 页脚文案一致（03c 稳态为"45 个应用 · 已测 45"） | — | — |
| 列表扫描中转（ProgressView + 扫描应用…）/ 无应用空态 | `appList` 的 `:401-410`〔**P46f 现读**：`appList` 在 `MMUninstaller.swift:388`，扫描中转在 `:401-406`、空态 `MMEmptyState` 在 `:408`；本文此前写 361 与 381（P43c 那一读），再早写 236-245；且这两档**一张照片都没有**，见 §5 第 9 行那格〕 | ⚠️ 稿缺 | 稿 03 未画扫描中/空态；实现有 `MMEmptyState`/"扫描应用…"，属实现补状态 | 低 | 设计稿该改 S6（同类） |
| 行右侧"N 项残留"徽标 | `:807-816` | ✅ | `app.residuals.isEmpty == false` 时显示；系统应用显示"系统应用"徽标 | — | — |

### 1.3 应用详情（03 · 选中应用）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 身份头：38pt 图标 + 名称 + `包名 · 大小 · /Applications` | `AppDetailView.identityHeader` `MMUninstaller.swift:1725-1743` | ✅ | 实现 `deletingLastPathComponent` 取父目录，与稿一致（P16 现读：本文此前只写裸行号 853，是写作当时的位置） | — | — |
| 四张统计卡：应用大小/包含文件/残留大小/残留项 | `statsCards` `MMUninstaller.swift:1757` → `MMStatItem` | ⚠️ 几何 | 实现用共享 `MMStatItem`（`MMDesign.swift:390`）：圆角 `MMRadius.control`＝**6**（`:104`）、底 `MMColor.underPageSurface`（用在 `:407`，值在 `:47`）；稿 `.cards .c` 圆角 6、底 `--c-card-bg-alt`。**P16 更正两处**：本文此前把 `MMStatItem` 记在 `MMDesign.swift` 的第 350 行（漂了 36 行）、并把令牌写成 `cardBackground` 与 `control=8`——`cardBackground` 这个符号**已不存在**（改名见 `:41` 注释），`control` 也不是 8。圆角这一维现在两边都是 6，只剩底色一档之差（#E4E4E4 vs #F7F7F7） | 低 | 设计稿该改 S4 |
| 键值对：包名/版本/开发者/最低系统/可执行文件/修改时间/所在文件夹 | `infoSection` `MMUninstaller.swift:1796` → `MMKeyRow` | ✅ | 实现 `MMKeyRow("版本", "\(version) (\(build))")` 与稿"26.2 (17C4011)"一致；空值填空字符串；`MMKeyRow` 在 `MMDesign.swift:366` | — | — |
| 「将一并移除的残留」+ 徽标"N 项默认不勾选" + "按包名…匹配·不含共享文件" + 全选可删项 | `residualSection` `:902-918` | ✅ | 实现徽标 `unselectedCount` 项、文案"按包名与容器证据匹配 · 不含其他应用的共享文件"，与稿一致 | — | — |
| 残留按风险分组，每行：图标 + 路径 + 原因 + 徽标 + 勾选框 | `residualGroups` `:958` → `ResidualRow`/`MMItemRow` | ✅ | 实现 `MMItemRow`（`MMDesign.swift:807`）逐行：risk 徽标、`risk.allowsDeletion` 为假时勾选框禁用（root 属主项不可选），与稿"root 属主项勾选框直接禁用"一致 |
| 残留行高 28pt（稿 `.res`） | `MMItemRow` 用 `MMMetric.rowRegular`（=44，`MMDesign.swift:870`） | ❌ | 稿 28pt 两行文案放不下且与 03b 的 52pt 自相矛盾；实现统一 44pt 更合理 | 低 | 设计稿该改 S2 |
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
| 头部：`tray.and.arrow.down.fill` + 标题（单应用"刚拖进废纸篓：X" / 多应用 Picker + "有 N 个应用刚进废纸篓"）+ 徽标"本体已在废纸篓"(info) + 在访达中显示 + 忽略 | `trashNoticeCard` `MMUninstaller.swift:1120`〔**P46f 现读**：挂载点在 `:1103`；本文此前写 1093 与 1076（P43c 那一读），再早写 583-615；"多应用走 `Picker`"这一支至今没有照片，见 §5 第 6 行那格〕 | ✅ | 实现 `MMBadge("本体已在废纸篓", informational, "trash")`；多应用走 `Picker`；与稿一致 |
| 头部路径行：`~/.Trash/Foo.app · com.example.Foo`（等宽、中段截断） | `:617-630` 用 `trashArrival?.path`（绝对路径） | ❌ | 实现给**绝对路径**（`/Users/lee/.Trash/Foo.app`），而卡片内残留行用 `~/` 缩写（`displayPath`）——同卡两种写法；稿头部用 `~/.Trash` 缩写 | 低 | 实现该改 I1 |
| 扫描中档：ProgressView + "按包名与容器证据扫残留…" + 汇总"扫描中…" | `:632-636` + `trashNoticeSummary` `:695` | ✅ | 与 03c-2①一致 |
| 尚未扫描档："还没扫残留…" + 汇总"尚未扫描" | `MMUninstaller.swift:1193` + `:1251`〔**P46f 现读**：本文此前写 1166 与 1224（P43c 那一读），再早写 637-640 与 696〕 | ✅ | 与 03c-2②一致；**不是**"0 项 · 0 字节"〔P43c：这一档**仍 0 张**，§5 第 4 行那格〕 |
| 无匹配档："按当前敏感度没有匹配到残留文件。" + 汇总"已选 0 项 · 0 字节" | `MMUninstaller.swift:1197` + `:1251`〔**P46f 现读**：本文此前写 1170（P43c 那一读），再早写 641-644 与 696〕 | ✌ | 与 03c-2③一致；此档是"真扫过结论空"，写 0 正确〔P43c：**仍 0 张**，§5 第 5 行那格；p32b 交叉验证那张的「已选 0 项残留」是勾选为零，不是这一档〕 |
| 正常档：残留行（safe 默认勾 / caution 默认不勾 / root 勾选框禁用）+ 汇总"已选 N · 字节 · 未勾选 M" + 全选可删项 + 清理勾选的残留 | `:646-684` + `:697` | ✅ | 实现 `trashResidualBinding` 仅 `risk.allowsDeletion` 时可勾；汇总模板与稿"已选 2 项 · 6.3 MB · 未勾选 2 项"一致；按钮 `borderedProminent`+`destructive` |
| 卡片底色 info 8% | `:689` `MMColor.soft(informational, 0.08)` | ✅ | 与稿 `color-mix(info 8%)` 一致 |
| 卡片内残留行高 | `MMItemRow` `rowRegular=44` | ⚠️ 稿 03c 未单列 | 稿 03c 卡片行 `.nrow` 高 46pt，实现 44pt；差 2pt〔P43c 现读：两头都还在原值上——`MMDesign.swift:112` `rowRegular: CGFloat = 44`，`03c-uninstaller-trash.html:35` `min-height:46px`。这一格挂着"⚠️待真机测量"已经名不副实：**它是一个改哪头的决定，不是一次测量**（改稿 44 / 改实现 46 / 再拍一张量尺，三条路都要人拍板），且 `rowRegular` 是共享令牌，动它会影响其它页的行高——与 §4 B1 同一类〕 | 低 | ⚠️待真机测量 |

### 1.7 无权限降级横幅（03c-3）+ 废纸篓清理确认面板

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 横幅：`lock.fill` + 标题"读不到废纸篓" + 带错误码详情 + "打开系统设置"（深链 Privacy_AllFiles） | `trashRegion` `MMUninstaller.swift:1096-1112`（横幅构造 `:1105-1111`）→ `MMPermissionBanner`（`MMDesign.swift:483`，`lock.fill` `:496`）；深链那一档取 `MMSettingsPane.fullDiskAccess`（`SystemSettings.swift:18`），在 `settingsPane:` 参数上（`MMUninstaller.swift:1110`） | ✅ | 实现 `needsFullDiskAccess ? "读不到废纸篓" : "废纸篓现在读不了"`；详情拼 `reason + " 在系统设置里授予…重启应用才会生效"`；`reason="无法打开废纸篓目录：Operation not permitted（错误码 1）。"` 与稿逐字一致（见 `trash-watch-fda.md` 本机实测） |
| 目录不存在走另一文案且**不放授权按钮** | `TrashWatcher.start` `TrashWatcher.swift:140-148` `needsFullDiskAccess:false` → `MMPermissionBanner(settingsPane:nil)` | ✅ | 实现区分 ENOENT（目录不存在，无按钮）与 EPERM/EACCES（要授权），与 `trash-watch-fda.md` 红线 2 一致 |
| 页面其余部分不受影响（列表/卸载动作不依赖读废纸篓） | `trashRegion` 仅替换卡片区，列表/详情照常 | ✅ | 与稿"页面其余部分不受影响"一致；`uninstaller-no-fda-banner.jpg` 已证 |
| 横幅底色 warning 10% | `MMPermissionBanner` `soft(caution,0.10)` | ✅ | 与稿 `color-mix(warning 10%)` 一致 |
| 废纸篓清理确认面板（"清理 X 的 N 项残留？" + 逐路径 + 合计 + 取消/移入废纸篓） | `trashConfirmSheet` `MMUninstaller.swift:1278` | ⚠️ 稿缺 | 稿 03c **未画**此确认面板（孤儿确认 03b 有、废纸篓清理确认没有）；实现 `deletionRoots(for:)` 单点给路径、不含本体（调用 `MMUninstaller.swift:1279`，定义 `ResidualScanner.swift:413`），与红线 3 一致 | 低 | 设计稿该改 S5 |
| `MM_SHOW_TRASH_CONFIRM` 触发确认面板 | `trashConfirmHook` `MMUninstaller.swift:804-806`（需 `fixtureScanHome() != nil` 且环境变量=1） | ⚠️ 文档缺口 | 单设 `MM_SHOW_TRASH_CONFIRM=1` **不会**触发，必须同时设 `MM_TRASH_SCAN_HOME`（且限 /tmp）；稿/README 描述"自动开确认面板"未写此互锁 | **中** | 两边都改·提协调者 B2 |

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

> **复核 2026-10-04（P6.5b）：三条全部已落地**，都出自同一个提交 **`71da937`**（2026-09-30，
> `fix(uninstaller): 提示卡路径统一 ~/ 缩写、注脚补撤回口径、操作栏 note 去数字`），只改了
> `MMUninstaller.swift` 一个文件（+5/−3）。下面逐条把当时写的行号换成今天的坐标，并把
> "该不该改"的结论留着——这份清单当时判的都是低，落地没有改变判断，只是说明**它挂了一天多没被划掉**。
> 与 `fidelity-monitor.md` §2、`fidelity-cleaner.md` §2 同一轮发现：清单里的"开放"是写下那天的状态。

1. **【低】I1 · 提示卡头部路径用绝对路径，卡片内残留行用 `~/` 缩写**（`MMUninstaller.swift:644-657` 用 `trashArrival?.path`）
   头部写 `/Users/lee/.Trash/Foo.app`，下方残留行写 `~/Library/...`，同卡两种写法。建议头部也走
   `displayPath`（或统一绝对），与稿 `~/.Trash/Foo.app` 对齐。
   **✅ 已落地（`71da937`）**：头部改为 `arrivalDisplayPath`，在 `trashNoticeCard` 里算一次
   （`MMUninstaller.swift:1128`，`ResidualCollector.display(arrivalPath, home: NSHomeDirectory())`；**P46f 顺带修一处旧锚**：本文此前记的 1047 在 HEAD 就落在「应用根跳过」那一段上，这一句当时在 1101）、
   渲染于 `:1095`。同卡两种写法已收口为一种，且与残留行（`:882`）、"不在这台机器上"回执（`:1000`）
   共用同一个 `display` 函数——缩写口径不再各页自己拼。
2. **【低】I2 · 详情注脚漏"或「最近操作」中"**（`AppDetailView.confirmationNote` `:999`）
   写"可在 15 秒内撤回"，但同模块确认面板（`:502`）与 `trash-watch-fda.md` 的撤回语义都含"最近操作"。
   建议补成"可在 15 秒内或「最近操作」中撤回"，与自身确认面板口径一致。
   **✅ 已落地（`71da937`）**：`confirmationNote`（现 `MMUninstaller.swift:1934-1936`）末句现为
   「可在 15 秒内或「最近操作」中撤回。」，渲染点 `:1594`。注脚与确认面板、撤回实现三方口径一致。
3. **【低】I3 · 操作栏 note 在 `unselectedCount>0` 时写"未勾选的 N 项不会被修改"**（`actionBar` `:316`）
   稿 03 写"未勾选项不会被修改"。实现更具体（带数字），但与稿面文案不一致；若要严格还原稿面，
   应改为不带 N 的版本，或反过来让稿面补数字——属文案注脚级，低。
   **✅ 已落地（`71da937`，取"改实现"这一支）**：`actionBar` 的 note 现为无条件常量
   `"未勾选项不会被修改"`（`MMUninstaller.swift:502`，逐字为「未勾选项不会被修改」；**P46f 顺带修一处旧锚**：本文此前记的 455 在 HEAD 就落在 `onToggleAll:` 那行，这一句当时在 475），
   带 N 的分支已删。理由当时没写，这里补一句可复核的：**note 讲的是规则，summary 讲的才是数量**
   （`summary` 里已有「已选 N 项残留 · 大小」），两个数挤在一行会互相抢注意力。

## 3. 设计稿该改（S · 7 条）

1. **【低】S2 · 残留/孤儿行高稿面自相矛盾**：03 残留行 `.res` 画 28pt（两行文案放不下）、03b 孤儿行 52pt，
   实现 `MMItemRow` 统一 44pt。建议稿面两处都改到 44pt。〔P43c 现读三个数都还在原位：`03-uninstaller.html:23` `height:28px`、`03b-uninstaller-orphans.html:12` `height:52px`、`MMDesign.swift:112` `rowRegular: CGFloat = 44`——稿面这一族至今没为这两行重渲染过，属待改稿〕
2. **【低】S3 · 应用行图标 28pt、行高 52pt 与令牌不符**：实现 `iconApp=32`/`rowApp=56`；建议稿面改到 32/56，或确认令牌要调。
3. **【低】S4 · 统计卡用了非标准令牌**：稿 03 `.cards .c` 底用 `--c-card-bg-alt`、圆角 6pt，而实现 `MMStatItem`
   用 `MMColor.underPageSurface`（`MMDesign.swift:407`，值 `:47` 浅 #E4E4E4）+ `MMRadius.control`=6（`:104`，用在 `:407`）；**圆角这一维 P16 现读已经对齐**（本文此前写的是 `cardBackground` + `control=8`，那个符号已改名、那个数值也不是当前值），只剩底色一档之差。建议稿面改用 `--c-card-bg` 一档，与全站组件对齐。
4. **【低】S5 · 03c 缺"废纸篓清理确认面板"稿面**：孤儿确认 03b 有（第二 artboard），废纸篓清理确认（
   `trashConfirmSheet`）没有，建议补一张对齐 03b 的确认稿。
5. **【低】S6 · 03b 缺空态/扫描态稿面**："还没有反查过""没有发现没有主人的残留""正在反查残留归属…"
   三档实现都有、稿未画，建议补（与 03c-2 同处理）。
6. **【低】S7 · 副标题在"卸载后遗症"档仍显示应用数/合计**：03b 如此、实现同稿；语义上弱相关，建议稿面决定。
7. **【低】S8 · 03c-3 工具栏副标题"已测 0 · 45 个测量中"是瞬时快照**：无 FDA 时应用扫描**独立进行**，
   稳态是"45 已测"；稿面易误导为"无权限时应用不扫描"，建议加一句注脚。

## 4. 两边都改 · 提请协调者（B · 2 条，均中）

1. **【中】B1 · 列表宽度 / 操作栏高度 设计硬编码数值 vs 共享令牌**：
   稿把 `applist` 画成 **300pt**、操作栏写 **46pt**；实现用共享 `MMMetric.inspector=268pt`、`MMActionBar` 高 **52pt`。〔P43c 现读：两个令牌值仍成立——`MMDesign.swift:120` `inspector: CGFloat = 268`、`:115` `actionBar: CGFloat = 52`；这一条是"稿 vs 令牌"的协调项，与照片无关，维持待人拍板〕
   改 `MMMetric.inspector` 或 `MMActionBar` 高度会影响其它模块（monitor 等多处用 `inspector`/`actionBar`）。
   **提协调者决定**：要么设计改到 268/52 与令牌一致，要么为卸载页引入屏级覆盖宽度——不要模块私下改共享令牌。
2. **【中】B2 · `MM_SHOW_TRASH_CONFIRM` 互锁未写清**：
   该钩子**单设不触发**，必须同时设 `MM_TRASH_SCAN_HOME`（且只认 /tmp）才会自动开确认面板
   （`trashConfirmHook` `MMUninstaller.swift:804-806`〔**P46f 现读**：计算属性从 `MMUninstaller.swift:803` 起、互锁那句在 `:804`、`MMHookValue.flag` 在 `:806`；本文此前写 776 与 779〕）。
   这是"终点=删除按钮、绝不能指向真实用户目录"的有意互锁，但 README §2 与 03c cap 只写"自动开确认面板"。
   **提协调者**：在 README/稿面补一句"需配合 `MM_TRASH_SCAN_HOME`（限 /tmp）"，避免验证者单设钩子误以为失效。

## 5. 没能验证到的部分（逐条写明缺什么，不写"应该没问题"）

以下状态**只在代码里读到分支**、实机一张都没截到，或本机无法构造（严格遵守"测量诚实"红线，不编结论）：

| # | 未验证项 | 为什么验不了 | 需要什么才能验 |
| --- | --- | --- | --- |
| 1 | 03b 孤儿"正在反查残留归属…"扫描态 | 切到该档即 `startOrphanScanIfNeeded` 自动扫描，本地盘几乎一帧返回；且无 HOLD 钩子 | 一个冻结扫描返回的 `MM_ORPHAN_FIXTURE_HOME` HOLD 钩子，或单测/预览快照 〔P43c 现读：**仍 0 张**，且比本格写的更糟——**03b 孤儿整档一张照片都没有**。`grep -rln "orphans\|孤儿" docs/verification` 只命中 p18/p19 的钩子拼错档、p33a/p39 的分析日志，没有一张是孤儿档画面。HOLD 那半句也复核过：全仓带 HOLD 的键只有 `MM_DISK_HOLD`、`MM_MONITOR_HOLD` 两枚，这页确实没有〕 |
| 2 | 03b"还没有反查过"空态 | 进档即触发扫描，"未扫描"只活一帧 | 同上，或允许"进档不自动扫"的调试开关 〔P43c 现读：**仍 0 张**，同上一行——要的还是那枚 HOLD 钩子〕 |
| 3 | 03c 提示卡"扫描中…"档 | 到达后立刻 `scanTrashResiduals`，转瞬即过 | 一个冻结残留扫描的钩子（现有钩子无 HOLD 语义） 〔P43c 现读：**仍 0 张**。`p68-trash` 两张拍的都是"扫完"之后的卡片态，`01` 是 4 项残留、`02` 是无权限横幅，都不含扫描中那一帧〕 |
| 4 | 03c"尚未扫描"档 | 同上，到达后即扫 | 同上 〔P43c 现读：**仍 0 张**，同上一行〕 |
| 5 | 03c"按当前敏感度没有匹配到残留文件"档 | 需一个**本体在废纸篓、但按其敏感度零残留**的夹具 app；现有夹具（`uninstaller-trash-notice.jpg`）是有残留的 | 一个零残留夹具 app + `MM_TRASH_FIXTURE_DIR`/`MM_TRASH_SCAN_HOME` 〔P43c 现读：**仍 0 张**。`Scripts/trash-fixture.sh` 只造一棵 `$STAGE/Foo.app`（第 37 行）配 4 条残留，没有"零残留"这一棵树；p32b 交叉验证那张的「已选 0 项残留 · 0 字节」是**勾选为零**，不是"没有匹配到"这一档，两者别混〕 |
| 6 | 03c 多应用 Picker（"有 N 个应用刚进废纸篓"） | 需一次拖入 2+ `.app` 并监听；本机/无头都难构造 | 一个含 2+ app 的假废纸篓 + 监听器（或批量注入 arrivals 的钩子） 〔P43c 现读：**仍 0 张**，同一支夹具脚本只放得下一个 app〕 |
| 7 | 授予完全磁盘访问后"确实能读废纸篓" | 给 ad-hoc 构建授 FDA 需人工点系统设置，不在自动化范围；`trash-watch-fda.md` 已标"未在本机验证" | 人工授权后重跑截图（Apple 文档 + Pearcleaner/Mole 共识认为可读，但本机未实证） 〔P43c 现读：**仍 0 张，正分支只有负档**——`p1.5-trash/uninstaller-no-fda-banner.jpg`、`p68-trash/02-no-fda-banner.png`、`p11-hardened/watch-trash-base` 与 `watch-trash-hr` 各 1 张，拍的全是"读不到"那一态。这一条要人工点系统设置，不在自动化范围，维持原判〕 |
| 8 | 浅色模式下的实机配色 | 现有两张实机图均深色/夹具；稿按设计系统浅色档重绘 | 浅色外观下重跑截图流程 〔P43c 现读：**已由照片收口**——`docs/verification/p4-light-dark/light-uninstaller.jpg` ↔ `dark-uninstaller.jpg`（#54 那轮 `MM_APPEARANCE` 九屏）。本格那句"现有两张实机图均深色/夹具"只对 §0 实机图那两张成立，后来的 `p68-brew` 是 light 8 张 + dark 1 张、`p68-trash` 两档 `MM_APPEARANCE=dark`。顺一笔头行的账：`07-fixture-dark` 的 `# env:` 里 **light 与 dark 两个键并存**（脚本第 60 行先写运行参数 `MM_APPEARANCE=$APPEARANCE`，档位自己的覆盖值由 `$*` 追加在行尾；`env` 同一个键后写的生效，第 4 行"已强制 dark 外观"可证），归因头自己前后矛盾，重跑这族时值得顺手改脚本〕 |
| 9 | 03 apps 扫描中 / 无应用 / 未选应用 三档的精确像素 | 可构造但未见实机图；几何凭 CSS/常量推导 | 实机截图核对（见 §1.2/§1.8） 〔P43c 现读：**仍 0 张**。§1.8 把这三档标成 ✅ 说的是"实现里有这个状态"，不是"拍过"，两个口径别串。现读 `p68-brew` 9 份 + `p31-running` 7 份 `.log`，`# env:` 行**全部带 `MM_UNINSTALL_SELECT`**（`grep -L MM_UNINSTALL_SELECT` → 0 命中），没有一张是"未选应用"的画面；"无应用"要 `/Applications` 为空、本机无从构造；"扫描中"与 #1/#3 是同一件事（缺 HOLD）〕 |

**已验证的部分**（与上表相对，避免把整页写成"没验过"）：页头/工具栏文案与分段控件、应用列表行内容与徽标逻辑、
详情四卡与键值对、残留分组与"root 属主项勾选框禁用"、孤儿反向判定口径（minNameLength/applePrefixes/UUID 剥离/派生标识）、
三类确认面板文案、废纸篓提示卡四档的**文案与汇总口径**（扫描中/尚未扫描/无匹配/正常）、
无权限横幅的**错误码与授权深链**、"nil≠0 / 没看过≠没有"三条红线的实现落地。
其中 **03c-3 无权限横幅**与 **03c 提示卡（夹具态）** 两档有实机图佐证（`uninstaller-no-fda-banner.jpg` / `uninstaller-trash-notice.jpg`）。〔P43c：上面这张表是 P1 那轮写的，此后 §8/§9/§12/§13/§14/§15 六轮各自出片、各自记账，**没有一轮回头改判这张表**——所以本表现读是 9 行里 **1 行已收口（第 8 行，浅色档）、8 行仍 0 张**。这一页的成因和监控页那种"有钩子没脚本"不同：**这里的 8 行缺的是钩子语义（HOLD / 零残留夹具 / 多 app 夹具 / 人工授权），不是缺脚本**，只有第 8 行那格属于"早就拍过、表没跟着改"。下一轮别照本表下结论，先按 §0 实机图那格的 63 张账对号〔P43c 复算：这句初稿写"54 张"，与 §0 两格同源，三处同轮已改为逐项枚举相加得到的 63〕。〕

## 6. 可注入档位映射（对照现有 5 个钩子）

| 状态 | 钩子组合 | 说明 |
| --- | --- | --- |
| 03 apps 正常 | （默认，真实数据）或 `MM_UNINSTALL_PANE=apps` | — |
| 03b 孤儿正常 + 自动确认 | `MM_ORPHAN_FIXTURE_HOME=/tmp/...` | 自动勾选全部并开确认（合成点击进不了勾选框） |
| 03c 提示卡（夹具态） | `MM_TRASH_FIXTURE_DIR=/tmp/...` `MM_TRASH_SCAN_HOME=/tmp/...` | 对应 `uninstaller-trash-notice.jpg`〔P43c：这张已有可重跑脚本的替代品 `docs/verification/p68-trash/01-trash-notice.png`＋同名 `.log`（旧图一字未动）〕 |
| 03c 清理确认自动开 | 上组 + `MM_SHOW_TRASH_CONFIRM=1` | 需 `MM_TRASH_SCAN_HOME` 同时存在（B2 互锁） |
| 03c 无权限横幅 | 钩子全关（默认无 FDA 态） | 对应 `uninstaller-no-fda-banner.jpg`〔P43c：同样有替代 `p68-trash/02-no-fda-banner.png`；这一档依赖本机 TCC 态，§12.4 已记它授权后不可重跑〕 |

> 所有 `/tmp` 钩子均按 `TrashWatcher.fixtureEnvironmentValue`（`TrashWatcher.swift:105`〔P43c 现读：该函数在 `TrashWatcher.swift:128`〕）口径：
> 只认 `/tmp/` 或 `/private/tmp/` 之下，越界写 stderr 并忽略——本审计未新增任何夹具文件，如需补 B1/B2 之外的夹具，
> 一律按 `GuardianFixtureHooks.swift` 的"纯展示数据、不写盘、不合规则整钩作废"口径走，否则列进 §4/提请协调者。另钉一句口径：**本表只是 §0 那 5 枚钩子的映射，不是全部可注入档位**：另 5 枚（`MM_UNINSTALL_CONFIRM_FIXTURE_HOME`、`MM_UNINSTALL_CONFIRM_MODE`、`MM_UNINSTALL_SELECT`、`MM_UNINSTALL_SENSITIVITY`、`MM_UNINSTALL_SELF_ECHO`）的档位映射分散在 §8.2、§12.2、§13 与 §14，标题那句"对照现有 5 个钩子"是写作当时的钩子数，现读源码是 10 枚。

## 7. 关于 #46 P1.8（/var/db/receipts 只读归属接孤儿扫描）

原审计时**仅审计、未改动** receipts 相关代码。后续 P1.8 已落地：`OrphanScanner`
经 `ReceiptOwnerIndex` 只读收据 plist 的 `PackageIdentifier`，把它并入归属索引，减少仍有安装收据的
缓存被误报为孤儿。`/private/var/db/receipts` 仍是**删除候选红线**：不进 `ResidualCatalog`，
不展示为残留，也不传给 `FileTrashService`。收据可能在卸载后保留，所以它只能压低误报，
不能证明应用仍已安装；读取失败时退回原判定，不捏造归属。

单测注入 `/tmp` 下的假收据目录，覆盖匹配收据、损坏 plist 和候选清单不包含收据路径；
真实运行才传 `/private/var/db/receipts`，`MM_ORPHAN_FIXTURE_HOME` 夹具运行不读真实收据。

## 8. P5.2 追加（2026-10-02）：安装来源 03d ↔ 实现

设计稿 `docs/design-system/screens/mmuninstaller/03d-uninstaller-provenance.html`（渲染图同目录 `.png`，
三块：列表+详情、确认面板、五档文案合同表），实机证据 9 张在 `docs/verification/p7-brew/`。
**零合成点击**：五档来源靠 `Scripts/provenance-fixture.sh` 造一棵假 home + 一份假 brew 账本
（`<root>/.homebrew/Caskroom`），再用 `MM_UNINSTALL_SELECT=<bundleName>` 点名选中那一行；
`MM_UNINSTALL_CONFIRM_MODE=none` 让面板不弹出来（弹了会盖掉这一轮真正要拍的列表与详情）。

### 8.1 逐元素对照

| 元素 | 设计稿 | 实机（照片编号） | 判定 |
|---|---|---|---|
| 列表行内 chip：`brew`（accent）/ `疑似 brew`（caution 橙） | `.src` / `.src.brew` / `.src.maybe`，16pt 高 | `01`（Highball `brew`）`02`（CodeEdit `疑似 brew`） | ✅ 16pt 而不是 `MMBadge` 的 18pt：行只有两行文字的空间 |
| 后三档**不给**行内 chip | 合同表"列表无徽章" | `03`（歧义）`04`（App Store）`05`（无法判定）三张里 Firefox/WeChat/MysteryApp 行都干净 | ✅ 这一条是设计决定：chip 存在的理由是"它会改变你下一步的动作"，只有 brew 两档会 |
| 详情标题旁徽章：`Homebrew cask · highball` / `疑似 Homebrew cask` / `App Store` / `安装包` | `.badge` 三档色 | `01` `02` `04` | ✅ 用 `MMBadge`（18pt），图标 `shippingbox` / `questionmark.circle` / `app.badge` / `square.and.arrow.down`；`unknown` 没有徽章——把"没查到"做成一种属性是假话 |
| 键值行「来源」 | 合同表逐档一句 | `01`「Homebrew cask · highball 0.9.39（tap homebrew/cask）」/ `02`「可能是 Homebrew cask · codeedit（只有名字对上）」/ `04`「Mac App Store」/ `05`「无法判定」 | ✅ 强档带版本与 tap，弱档把"只有名字对上"写在标题里而不是小字里 |
| 键值行「来源凭据」 | 指到那份 json | `01` `02` 指向 `<home>/.homebrew/Caskroom/<token>/.metadata/INSTALL_RECEIPT.json`；`04` `05` 整行不出现 | ✅ 只有 brew 两档有账本可指；`MMKeyRow` 不拿空串占位 |
| 键值行「对应命令」 | 只展示，不执行 | `01` `brew uninstall --cask highball`；`02` 起就没有这一行 | ✅ 弱证据不配一条会改动系统状态的命令 |
| 「判定依据」小字（info 图标 + 一句） | 合同表 `.sub` | `01`（设备号 + inode 相同）`02`（staged 链接指向别处）`03`（两份账本在抢同一份文件）`04`（收据跟着 bundle 走）`05`（不等于「手动安装」） | ✅ 五档各有自己的一句话，没有共用一条兜底文案 |
| 确认面板「来源」行 + 橙色 brew 提醒 | `.dialog .callout` | `06`（提醒点名 `path` 与 `brew uninstall --cask highball`，末尾"MacMaster 不会代你运行 brew"） | ✅ 提醒只在 brew 两档出现，其余三档面板与 P1.5 之前一致 |
| 深色档 | 同一套令牌 | `07` | ✅ chip/badge 的 soft 底色在深色下仍可读（截图里主按钮呈灰是**窗口非活动态**，不是配色漏档） |
| 最小窗口（请求 900×600 → 夹到 1000 宽） | — | `08` | ✅ 「来源凭据」折成三行、「判定依据」折成两行，都不与相邻键重叠、不截尾 |
| 真机（不注入夹具，读 `/opt/homebrew`） | — | ~~`09`：44 个应用全部测完，Highball 一行给出设备号级凭据 + 对应命令~~ **这一行的判定作废**：库里那张 `p7-brew/09-real-machine.jpg` 拍的是**磁盘分析页**，不是卸载页（见 §12.3 第 2 条）。本轮补上的 `p68-brew/09-real-machine.png` 才是这一格该拍的证据 | ✅ 判定改由新照片支撑：真机与夹具走同一套代码路径，解析器不是只对着夹具写的 |

### 8.2 取证这一步抓出来的两个真问题

1. **歧义事实被"省一次赋值"吃掉了**。`UninstallerModel.provenanceMap` 当初写的是
   `if found.source != .unknown { map[app.path] = found }`——理由是"默认值就是 unknown，
   没必要为 44 个应用各存一份空结构"。但**两个 cask 抢同一份 bundle 也是 `.unknown`，却带着事实**，
   于是 `03` 第一次拍出来是一句空白的「无法判定」，看不出 firefox 与 firefox-beta 在打架。
   判据改成"没有事实才不入表"（`source != .unknown || ambiguousCaskTokens.isEmpty == false`），
   回归测试是 `testLoadAppsKeepsAmbiguousCaskTokensOnAnUnknownSource`——它走的是模型装配路径，
   纯引擎测试（`testTwoCasksStagingTheSameBundleIsAmbiguous`）当时全绿也照样漏掉这个。
2. **两种歧义的可信度不一样，文案不能混着说**。合同表原本只有一句「两个 cask 都声明了这个名字」，
   而 `03` 的夹具是**两份 staged 链接解析后都指向同一个 inode**——这比"名字撞上"强得多，
   说成"名字"是把已知的事实说小了。于是 `AppProvenance` 记一个 `ambiguousByDeviceIdentity`，
   来源行与判定依据各自分叉，设计稿合同表补了第二行。

### 8.3 拍不到的（点名，免得下轮又去找脚本）

- **安装包档（`.installerPackage`）没有实机照片**。判定要 `bundleID ∈ /var/db/receipts`，
  而夹具运行刻意把 `provenanceReceiptsRootFactory` 置 `nil`（假 home 不该去读真机系统收据，
  否则"这一档没命中"到底是没凭据还是没读系统就分不出来）。合同文案与降级路径由
  `AppProvenancePresentationTests` 覆盖，照片只有稿子第三块。〔**P46f 现读**：这行赋值在 `MMUninstaller.swift:257`（§12.4 重述的是同一条，两处同判——到本轮仍 0 张）；`AppProvenancePresentationTests` 现读在 `Packages/MMUninstaller/Tests/MMUninstallerTests/AppProvenancePresentationTests.swift`，确有其测〕
- **"账本声明了 app、但那份 bundle 早就不在"的悬空链**只在弱档里出现（`02` 就是它），
  没有单独一屏——它的 UI 表现就是"没有徽章"，与 `05` 同框。

## 9. P5.3 追加（2026-10-02）：应用装卸监听 03e ↔ 实现

设计稿 `docs/design-system/screens/mmuninstaller/03e-uninstaller-watch.html`（三块：消失卡 /
两个方向同屏 / 过渡与降级合同表），实机证据 4 张在 `docs/verification/p9-apps-watch/`
（`notice` `scan` `echo` `skipped`，各带同名 `.log`）。
**零合成点击**：改动由 `Scripts/apps-watch-fixture.sh depart` 真的往夹具目录里增删条目
（探针已证明这类改动会送 kqueue 事件，见 `apps-watch.md` §3），
两个"替用户按下按钮"的钩子（`MM_APPS_WATCH_AUTO_SCAN`、`MM_UNINSTALL_SELF_ECHO`）
都要求 /tmp 夹具成立才生效。

### 9.1 逐元素对照

| 元素 | 设计稿 | 实机（照片编号） | 判定 |
|---|---|---|---|
| 消失卡标题「刚从应用目录消失：X」+ 徽章「本体已不在应用目录」 | `.notice` + `.badge.info` | `notice` | ✅ 图标 `xmark.app`；徽章用 `MMBadge` 而不是稿里的 16pt `.badge` |
| 路径行「最后已知位置」 | `.path` monospace | `notice`：`/tmp/mmapps/Applications/Highball.app · com.example.Highball · 最后已知位置` | ✅ 三段一条线，中间点分隔 |
| 脚注「未扫描 · 扫描会先重新载入清单」+ 两按钮 | `.foot` | `notice` | ✅ 「只重新载入清单」是普通按钮，「重新载入并扫描残留」才是 prominent |
| 新条目轻提示「应用目录里有 N 个新条目」+ 徽章「当前清单是旧快照」 | `.soft` + `<ul>` 条目名 | `notice`：1 个新条目 `Notion.app` | ✅ 没有残留清单、没有删除按钮，唯一动作是「重新载入」 |
| 两方向同屏时**消失卡在上** | 03e-2 说明文字 | `notice`（消失卡在上、新条目在下） | ✅ 稿子原本画反了（新条目在上），本轮把 HTML 调正并重渲染 |
| 列表页脚「清单是载入时的快照，未自动刷新」 | 页脚橙字 | `notice` `echo` `skipped` 三张都在 | ✅ 这一句是"不自动重扫"这个决定的可见代价，不能省 |
| 「不在这台机器上」说明卡 | 03e-3 第三档 | `skipped`：`~/Applications 不在这台机器上` + 一句"目录不存在与读不到是两种原因" | ✅ 真机拍的，不带夹具钩子——用了夹具就把监听根换成那一个目录，"跳过"这个态反而造不出来 |
| 回声卡「你刚卸载了 X，残留还在」+ 徽章「由 MacMaster 移入」 | 03e-3 最后一档 | `echo` | ✅ 本轮修完才拍得到，见 §9.2 第 2 条。路径行写的是 `~/.Trash/Highball 12-29-703.app` —— 上一轮取证留下的 `Highball.app` 还在废纸篓里，系统给这一次改了名。这一句恰好证明路径是 `FileTrashService` 回填的目的地，不是拿原名拼的 |
| 回声抑制：自己卸载后不再冒「刚从应用目录消失」 | 03e-2 说明 ② | `echo`：列表只剩 Keeper/Lumen，没有消失卡 | ✅ 与 `notice` 对照着看才有意义，单看一张证不了"没出现" |
| 终点：重新载入并扫描 → 后遗症页 + 确认面板 | 03e-3 第一档 | `scan` | ✅ 「可疑残留 2 项 · 已选 2 项」，面板明说"找不到不等于没在用" |

### 9.2 取证这一步抓出来的两个真问题

1. **一个 `.fixedSize` 让整页比窗口高 397pt**。窗口 `content` 760pt，宿主视图 1157pt，
   整窗内容上下溢出，看着像"整个窗口错位"。量出来后定位到 P5.3 三张提示卡正文上的
   `.fixedSize(horizontal: false, vertical: true)`——卡片直接挂在页面根 `VStack`、又在弹性区之上时，
   它抬的是**整页的理想高度**。细节与教训在 `apps-watch.md` §6.2；
   守卫脚本 `Scripts/window-probe-sweep.sh`（结论 `docs/verification/window-probe/sweep.txt`）：
   7 页 × 两个尺寸全部齐平。〔P43c 现读这句有两处对不上实物：① **`sweep.txt` 没有入库**——`docs/verification/window-probe/` 里只有 7 份 `.log`，`git log --all -- docs/verification/window-probe/sweep.txt` 一条历史都没有；脚本尾部确实会写这个文件，也就是说这批片子出片时那段还没进脚本，或写了没入库。② **"两个尺寸"在库里没有证据**——7 份 `.log` 全取自同一个尺寸、同一种外观（每份 5 行 `frame=W1100xH760`，`# MM_APPEARANCE=light` 各 1 行），`window-probe-sweep.sh` 本身也只按一个外观跑，第二个尺寸要调用方自己导出 `MM_WINDOW_SIZE` 再跑一遍。③ "齐平"这半句站得住：按脚本自己的判据复跑 7 份日志，逐页窗口帧高与 `AppKitPlatformViewHost` 高都是 760/760。补法是把 `sweep.txt` 与第二尺寸的日志一起重跑入库，别只留原始帧。〕
2. **回声卡把"我们动过手"寄托在"列得动废纸篓"上**。没有「完全磁盘访问」的机器上
   `~/.Trash` 列不动，`trashWatcher` 只能报 `.unreadable`，横幅排在卡片前面——
   卸载确实成功了、残留确实还在，界面只说"我读不到废纸篓"。改成卸载动作自己留凭据
   （`FileTrashService` 回填的目的地路径 + 卸载前读好的包标识），监听读得动时仍以监听为准。
   细节在 `apps-watch.md` §6.1。

### 9.3 拍不到的

- **03e-3「读不到目录」那一档（EPERM）没有照片**。它要求监听根存在、可 `open`、但列举被拒；
  /tmp 下的目录不会这样，真机的 `/Applications` 也不会。代码路径由
  `AppFolderWatcherTests` 覆盖（`listing(of:)` 返回 nil 时状态必须是"读不到"而不是"目录是空的"）。
- **`~/Applications` 里真的装了应用**时的两目录同报没有照片——本机那个目录压根不存在（`skipped` 拍的就是它）。
- **子目录条目**（列举根再往下一层，如 `/Applications/Utilities/<厂商>/Foo.app`）按设计**不该**进任何提示，
  所以它没有"正面照片"，只有 `AppWatchRule` 的那组单测守着监听口径 = 列举口径（P46c 把列举根扩到四个：`/Applications/Utilities` 与每块非启动卷的 `/Applications` 也算根，那条 `Foo.app` 现在在第一层里、会进清单）。


## 10. P6.7 追加（2026-10-04）：取证脚本自己造了一条假凭据

这一轮不拍新档，改的是**已有那条日志的可信度**。`MM_ORPHAN_FIXTURE_HOME` 那趟自动扫描
（`runOrphanScan`，`MMUninstaller.swift:532`）过去在 `await model.scanOrphans(home:)` 之后
**无条件**写一行「已用夹具目录 … 自动勾选并打开确认面板」。而 `scanOrphans` 在
"应用清单还在枚举"或"清单为空"时是**静默 return** 的（`UninstallerModel.swift:618` 那道 guard）。
两件事叠起来的结果：扫描根本没跑，日志照样是绿的——取证脚本替夹具作伪证。

改法两步（同一处，`Packages/MMUninstaller/Sources/MMUninstaller/MMUninstaller.swift`）：

1. **把同一个前置条件在外面先判一遍**，不满足就点名
   「孤儿夹具扫描**没有执行**：应用清单还在枚举或为空（isScanningApps=…, apps=…），未勾选、确认面板未打开」并 return。
   只在给了夹具 home 时判——真机那趟自动扫描（用户自己切到「卸载后遗症」）行为不变。
2. **成功那行带上条数**：`（N 条）`。这行从此是可核对的断言（照片里应当正好有这么多行），
   不是一句"我跑了"。0 条照写——**空面板与没扫描是两件事**，旧写法把它们混成同一句。

2026-10-04 各跑一轮实机验证：夹具 home 指 `Scripts/uninstall-fixture.sh` 造的那棵 →
`（1 条）`；指一棵空 home → `（0 条）`。两种都落到"打开了面板"，只有条数不同，
正是这条日志要区分的东西。

**没改的**：`reloadListing()` 会把 `selectedAppID` 清成 nil（`UninstallerModel.swift:237`）。
上一轮审计把它列为"`MM_APPS_WATCH_AUTO_SCAN` 会抹掉 `MM_UNINSTALL_SELECT` 的选中"，
现读之后判定它**不是缺陷**：清单重新反映了磁盘，选中项可能已经不存在，留在旧 id 上是悬空引用；
而 `MM_APPS_WATCH_AUTO_SCAN` 那条链路的终点是 `pane = .orphans`（`MMUninstaller.swift:908`），
拍的是后遗症页不是应用详情，两者不在同一屏。`runOrphanScan` 跑在
`await model.reloadListing()` **之后**（`:877`→`:878`），`reloadListing` 落回时
`apps` 已填（`UninstallerModel.swift:245`）、`isScanningApps=false`（`:265`），所以新加的那道前置判断不会在这条路上误报。

## 11. P6.7 追加：`MM_TRASH_FIXTURE_DIR` 被拒绝时现在会说清后果

`TrashWatcher.watchTarget()` 过去是一行 `?? (NSHomeDirectory() + "/.Trash")`。
钩子值不在 /tmp 之下时 `fixtureEnvironmentValue` 会点名并返回 nil——**但没说退回之后监听的是谁的废纸篓**，
而那是用户自己的删除记录：一张本该只含夹具的照片会悄悄变成真数据，且照片上看不出来源换了。
现在这条退路自己说一遍（含实际目录），空值同样触发。

## 12. P6.8 追加（2026-10-04，2026-10-05 整批重拍）：p7-brew 与 p1.5-trash 变成可重跑脚本

§8 那 9 张与 §6 那 2 张一直是手工拍的，仓库里只有夹具没有重跑脚本。这一轮补两个脚本，
照片改写到 `docs/verification/p68-brew/`（9 张）与 `docs/verification/p68-trash/`（2 张），
每张旁边留同名 `.log`（stderr）。**旧目录 `p7-brew/`、`p1.5-trash/` 一字未动**。
本轮**没有改任何源码、没有新增钩子**——§8 记的那批钩子已足够到全部档位。

**2026-10-05 这一批 11 份是加了归因头（§12.5）之后整批重拍的**，不是 10-04 那批的残留：
现读 22 份 p68 日志（brew 9 + trash 2 + dev 7 + disk 4），头两行都是
`# <脚本> <档> <时间>` + `# env: …`，时间戳全落在 2026-10-05 12:23–12:32。〔P43c 补一笔口径账：这两行头**不含 `# digest:` 源码指纹**——逐族 `grep -c digest`：brew 0/9、trash 0/2，`grep -l digest Scripts/*.sh` 也没有这两支脚本；P23b 之后那几族（p31 7/7、p32 9/9、p32b 12/12、p33b 8/8）才靠 `Scripts/mm-provenance.sh` 自证"照片与二进制同源"。所以 §12 这 11 张能证明"注入过什么变量"，证不了"跑的是哪一版源码"，两者别互相顶替。〕

### 12.1 怎么跑

```sh
./Scripts/make-app.sh -o /tmp/mm-app-p68uninst -s /tmp/mm-scratch-p68uninst   # 隔离构建，别动共享 build/
./Scripts/p68-brew-capture.sh /tmp/mm-app-p68uninst/MacMaster.app docs/verification/p68-brew light
./Scripts/trash-fixture.sh
./Scripts/p68-trash-capture.sh /tmp/mm-app-p68uninst/MacMaster.app docs/verification/p68-trash dark
```

两个脚本都支持 `ONLY=04` 前缀重拍单档（风格照 p61/p62）。brew 脚本默认每次现跑
`Scripts/provenance-fixture.sh` 造新夹具树（`FIX=` 可复用现成的）；trash 脚本会先验
`/tmp/mmstage/Foo.app` 还在、假废纸篓里没有残留条目，不满足就点名让人重跑夹具而不是拍出假态。

### 12.2 逐档哨兵（"这就算生效了"的判据，不是 md5）

夹具档的哨兵都是**真实机器生产不出来的值**：假 home 路径、`com.example.*`、假 brew 账本里的 token。

| 档 | 钩子组合 | 哨兵判据（画面上必须出现的） |
|---|---|---|
| 01 brew 强档 | `MM_UNINSTALL_CONFIRM_FIXTURE_HOME=<fix>` `MM_UNINSTALL_CONFIRM_MODE=none` `MM_UNINSTALL_SELECT=Highball` | 徽章「Homebrew cask · highball」、来源凭据 `<fix>/.homebrew/Caskroom/highball/.metadata/INSTALL_RECEIPT.json`、对应命令 `brew uninstall --cask highball` |
| 02 疑似 brew | 同上，`SELECT=CodeEdit` | 行内橙 chip「疑似 brew」+「只有名字对上」，且**没有**「对应命令」行；凭据指 `…/Caskroom/codeedit/…` |
| 03 歧义 | 同上，`SELECT=Firefox` | 无徽章，来源行点名「firefox、firefox-beta 两份账本把同一个 .app 摆到了这里」 |
| 04 App Store | 同上，`SELECT=WeChat` | 徽章「App Store」+ 判定依据点名 `Contents/_MASReceipt/receipt` |
| 05 无法判定 | 同上，`SELECT=MysteryApp` | 无徽章，「无法判定」且不写"手动安装" |
| 06 确认面板 | 夹具 + `SELECT=Highball`，**省略** `CONFIRM_MODE`（appOnly 自动弹，`MMUninstaller.swift:78`） | 面板「来源」行 + 橙色提醒点名 `<fix>/Applications/Highball.app` 与 `brew uninstall --cask highball`、"MacMaster 不会代你运行 brew" |
| 07 深色 | 同 01 + `MM_APPEARANCE=dark` | 同 01 哨兵在深色下可读 |
| 08 最小窗口 | 同 01 + `MM_WINDOW_SIZE=900x600` | 日志有夹取行「请求 900x600pt，窗口实际 1000x652pt」；长账本路径折三行不重叠 |
| 09 真机 | 不注入夹具，`MM_UNINSTALL_SELECT=$REAL_SELECT` | 真 `/opt/homebrew/Caskroom/wailbrew/.metadata/INSTALL_RECEIPT.json` + 真包名 `io.github.wickenico.wailbrew`——**这一张是真数据**，见 12.4 |
| trash-01 提示卡 | `MM_TRASH_FIXTURE_DIR=/tmp/mmtrash` `MM_TRASH_SCAN_HOME=/tmp/mmhome` + 脚本 mv | 卡片「刚拖进废纸篓：示例应用」+ 路径 `/tmp/mmtrash/Foo.app · com.example.Foo` + 残留行全在 `/private/tmp/mmhome/…` 之下；日志里**不得**出现「改为监听真实废纸篓」（出现了这张就作废，§11） |
| trash-02 横幅 | 不带任何钩子 | 「读不到废纸篓 / Operation not permitted（错误码 1）」——**真机档**，没有夹具哨兵，见 12.4 |

### 12.3 与旧照片不一致的地方（如实记）

1. **每一张 brew 档现在多了一条「~/Applications 不在这台机器上」横幅**。这是 P5.3 之后
   新加的应用目录监听态（本机确实没有 `~/Applications`），不是回归——旧照片拍于 P5.2，
   那时这一屏还没有监听区。
2. **旧 `p7-brew/09-real-machine.jpg` 对不上 §8 表格**。§8.1 写的是"44 个应用全部测完，
   Highball 一行给出设备号级凭据"，而库里那张 jpeg 拍的是**磁盘分析页正在扫描**——
   旧证据本身就存错了文件。本轮的 `p68-brew/09-real-machine.png` 是卸载页真机档，补上了这个缺口。
3. **Highball 已从本机卸载**（`/Applications` 里没有，只剩 Caskroom 账本——恰好是 §8.3
   说的"悬空链"态；10-05 现查 `ls -d /Applications/Highball.app` 仍不存在）。脚本默认仍点名
   Highball（`Scripts/p68-brew-capture.sh:106`，忠于旧档），落空时日志诚实写
   「MM_UNINSTALL_SELECT=Highball 没有对应的应用」、照片落"未选择应用"空态——
   **10-05 整批重拍时 09 档第一次就是这么废掉的**（头里 `REAL_SELECT` 没设，走了默认值）。
   重拍用的是 `ONLY=09 REAL_SELECT=WailBrew`：现在 09 的头里写的是 `MM_UNINSTALL_SELECT=WailBrew`、
   日志里**没有**那行落空，照片给出真凭据 `/opt/homebrew/Caskroom/wailbrew/.metadata/INSTALL_RECEIPT.json`。
   改真机目录的人记得同步这个变量。
4. **trash-01 的等待量级变了**：旧照片拍到"已测 31 · 13 个测量中"的中间态，本轮卡片要等
   41 个应用全部测完才出现（`trash-watch-fda.md` §1.4 记过：合并计时器排在 MainActor 上，
   批量测量期间排队）。脚本 `AFTER_MOVE` 默认 60 秒兜底，页头因此是"大小已实测"。
   卡片内容（4 项残留、已选 2 项 · 6.3 MB）与旧照片一致。
5. 应用总数 44→41、磁盘占用条百分比等随机器状态漂移，属真机档固有，不算不一致。

### 12.4 不可重跑的档（点名，不为了凑照片改生产语义）

- **trash-02「无权限横幅」依赖机器 TCC 态**：它要的就是"真 `~/.Trash` 列不动"。
  本机构建未授予「完全磁盘访问」，本轮拍到了；哪天授权了，这一档在这台机器上**不可重跑**
  ——不能拿假废纸篓冒充（假目录永远读得动），也不能改 `watchTarget()` 的退路语义。
  它是真数据档，没有夹具哨兵。
- **安装包档（`.installerPackage`）依旧没有照片**（§8.3 原样成立）：判定要读
  `/var/db/receipts`，夹具运行刻意把 `provenanceReceiptsRootFactory` 置 nil
  （`MMUninstaller.swift:257`〔**P46f 现读**：本文此前写 230 与 235，那句赋值本轮被 P46c 顶了 22 行〕），本轮没有为一张照片打开这个口子。合同文案仍由
  `AppProvenancePresentationTests` 守。
- 06 档的「带残留卸载」面板态（`CONFIRM_MODE=withResiduals`）钩子可达但旧照片没有这一档，
  本轮不新增档位，只留脚本参数可拍。

跑完两脚本后 `ps -eo pid,command | grep MacMaster.app/Contents/MacOS` 为空；
`/tmp/mmtrash` 里的 `Foo.app` 是本轮 mv 进去的，重跑 `Scripts/trash-fixture.sh` 即复位。

### 12.5 P6.8b 追加：`.log` 开头补两行归因头（本轮唯一的改动）

§12 交出来的 11 份 `.log` 全是绿的，但**绿得没有内容**：只有应用自己的 stderr
（`MM_APPEARANCE=… 已强制…`、`MM_WINDOW_SIZE=… 请求…实际…`），一句都没有记录
"这一档注入了哪些变量"。这正好是 P6.7 §10 判过的那第三种形状——**成功路径不说话**：
`MM_UNINSTALL_SELECT` 只在点名落空时写一行「没有对应的应用」，`MM_UNINSTALL_CONFIRM_FIXTURE_HOME`
只在被拒绝时写一行「不是 /tmp 下的真实目录」，于是 §12.3 第 3 条那句"本轮实跑用了
`REAL_SELECT=WailBrew`"只能靠人记得，照片旁边那份日志事后对不出来；夹具档也一样，
分不清"这条绿是因为夹具生效"还是"这条绿是因为压根没注入"。

改法是**脚本侧**补两行头（不碰源码，也不新增钩子——钩子的静默成功留给照片的哨兵去证）：

```
# p68-brew-capture.sh 01-fixture-homebrew-cask  2026-10-04 18:31:33 +0800  app=/tmp/…  fixture=/tmp/macmaster-provenance-fixture.WIq1Xq
# env: MM_APPEARANCE=light MM_OPEN_MODULE=uninstaller MM_UNINSTALL_CONFIRM_FIXTURE_HOME=… MM_UNINSTALL_CONFIRM_MODE=none MM_UNINSTALL_SELECT=Highball
```

两个脚本的 `shot()` 先写头再 `>>` 追加应用输出；trash 脚本两档各写自己的头，
02 那档明写「真机档：刻意不注入任何夹具钩子」——**"没有"也要说出来**，否则它与"忘了"长得一样。
`Scripts/p68-dev-capture.sh` 同步加上（三个 p68 脚本一套约定）。

2026-10-04 先重跑三档验过头与照片对得上（`ONLY=01` brew、`ONLY=02` trash、`ONLY=01` dev）；
**10-05 又把 22 档整批重拍了一遍**，所以现在库里每一张 p68 照片旁边的日志都带头，
不存在"一半带头一半带头之前的"。抽查两例对应关系：

- brew 01：头里 `fixture=/tmp/macmaster-provenance-fixture.Aw21jb`，照片里「来源凭据」
  与「所在文件夹」两行的路径尾缀正是 `Aw21jb`（夹具树每次现造，`mktemp` 的后缀跟着变，
  所以这条对应关系只有头在的时候才成立）。
- disk 01/04：头里的 `MM_DISK_SELECT` 三个路径 ↔ 日志 `已选中 …/Downloads（50.3 MB）`
  ↔ 照片上的同一个数（详见 `fidelity-disk.md` §11.2）。

两条读头时会被绊到的地方，如实写在这里：

1. **09 真机档的头里有 `fixture=`，但那一档没有注入夹具**。`$FIX` 在脚本开头就要造
   （`Scripts/p68-brew-capture.sh:38`，八档夹具档共用），头行是无条件打印它的；
   09 是否注入只看 `# env:` 那行——里面只有 `MM_UNINSTALL_SELECT=WailBrew`，
   没有 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME`。**"造了但没给这个进程"≠"注入了"**，
   以后若改成按档写 fixture 字段，这里得跟着改。
2. **07/08 的头里 `MM_APPEARANCE` 出现两次**（`MM_APPEARANCE=light … MM_APPEARANCE=dark`），
   是 `shot()` 把公共部分和逐档尾巴拼在一行的样子，不是拍错了：`env` 取后一个值，
   应用自己的那行也说 `MM_APPEARANCE=dark 已强制 dark 外观`（现读 `07-fixture-dark.log` 正文）。

**副作用，如实记**：`provenance-fixture.sh` 每次跑都留一棵 `/tmp/macmaster-provenance-fixture.XXXXXX`
不清理。10-05 现查是 **7 棵**——一次整批重拍留 1 棵，`ONLY=09` 单独重拍又留 1 棵
（09 那档根本不注入夹具，但 `$FIX` 在脚本开头无条件造，所以"只拍真机档"也要造一棵），
余下的是 10-04 及更早几轮。都在 /tmp、重启即清，不构成缺陷，但重跑取证的人别把
"上一棵"当成"本轮那棵"来复用——`FIX=` 只该指本轮新造的那一棵。

## 13. P31a 追加（2026-10-10）：v1.1 第 1 条「卸载前发现应用在跑」七档照片

这一族与 §12 那两族的根本差别：**它的哨兵不是合成值**。运行状态判的是"此刻有没有这个进程"，
喂给界面的假快照只能证明界面会写字，证明不了写的是真话，所以
`RunningAppProbe.snapshot()` 里**没有读 env 的分支**，照片里那个 pid 背后是一个
`open -g` 真的启动起来的 /tmp 夹具应用（`Scripts/p31-running-fixture.sh` 造三棵 bundle：
`Applications/RunningFoo`、`Applications/IdleFoo`、`Applications/ElsewhereFoo` + `Elsewhere/ElsewhereFoo`，
后两份**同包名、不同位置**）。

```sh
./Scripts/make-app.sh -o /tmp/mm-app-p31 -s /tmp/mm-scratch-p31
./Scripts/p31-running-capture.sh /tmp/mm-app-p31/MacMaster.app docs/verification/p31-running light
ONLY=05 ./Scripts/p31-running-capture.sh …        # 重拍单档
```

| 档 | 前置状态 | 画面上必须有的（哨兵） |
|---|---|---|
| 01 fixture-running | `Applications/RunningFoo` 在跑，`SELECT=RunningFoo` | 列表行橙 chip「运行中」+ 详情「正在运行 · 进程 `<日志里的 pid>`」，依据点名"位置就是 …/Applications/RunningFoo.app" |
| 02 confirm-sheet | 同上，省略 `CONFIRM_MODE`（自动弹面板） | 面板里那段橙色提醒 + 按钮仍是「取消 / 仅卸载应用」——**提醒不拦按钮** |
| 03 fixture-idle | 同上，`SELECT=IdleFoo`（它没跑） | 同一张图里 RunningFoo 有 chip、IdleFoo 没有；详情「未检测到运行中的进程」+ 图标是 circle **不是勾** |
| 04 min-window | 同上 + `MM_WINDOW_SIZE=900x600` | 提醒块三行折行不重叠。**窗口实际 1000×652**：900 宽被应用的硬下限夹住（P26 那条），日志的 `# windows(pid=…)` 行把实际尺寸记在案 |
| 05 identifier-only | 先结束 RunningFoo，再启动 `Elsewhere/ElsewhereFoo`，`SELECT=ElsewhereFoo` | 值「正在运行 · 进程 14810」，依据是"只有包名对上，位置是 …/Elsewhere/ElsewhereFoo.app，与这里这一份的写法不同"；提醒里点名"对上的只是包名" |
| 06 live-launch-refresh | 三个都没跑，窗口开好之后才 `open -g` `Applications/IdleFoo` | 那一行从「未检测到」变成「正在运行」，中间**没有任何重载**——只有 `NSWorkspace` 的启动通知能做到这一件事，也是夹具必须是 Cocoa 应用的由来（`sleep` 进程不发通知） |
| 07 real-machine | 不注入夹具，`MM_UNINSTALL_SELECT=WeChat` | 「正在运行 · 2 个进程（1094、1276）」＋依据里两个号都写在"位置就是 /Applications/WeChat.app"那一档；同一张图上 ADB Link、ChatGPT 两行也各自带 chip（**同一条读取路径同时给三个应用判对**，这是夹具档给不出的旁证） |

七份日志的 `# digest:` 全是 `tree=7918074+b8cf9354 app=7918074+b8cf9354`，头行时间戳
16:01:14–16:02:12、最后一张照片 16:03:43（07 的 `REAL_SETTLE=90` 就花在头行与照片之间），
**同一次跑**（§12.5 那两行归因头这一族照抄，另加 `# windows(pid=…)`、`# launched:`、
`# snapshot(拍前/拍后):`）。

**这一族是当天第二次跑出来的**，原因值得记：第一次拍完之后，本轮又改了两处**源码注释**
（`UninstallerModel.swift` 里"换选中项会重读"这句是假的、`RunningAppProbe.swift` 里
把"报不出包名"归因给 `.prohibited` 也是假的，现读 19 条里其实是 accessory 12 / prohibited 6 /
regular 1）。注释是编译输入、进指纹，于是 `+e7579651` 变成 `+b8cf9354`，取证脚本按 P23b 那道
门禁当场拒拍——重建 + 整族重跑一次，比"改注释不动照片"多花四分钟，换来的是这七张和
现在这份源码确实同源。**这一族里所有 pid 与夹具根（`vFH6Ex`）都是这一次的字面值**，
重跑必变。

### 13.1 照片抓出来的两处假话（都不是单测能抓的）

1. **05 第一次拍的是设置窗**。`shot()` 从前拿 `head -1` 的窗口清单——CGWindowList 是前→后排序，
   最靠前那扇恰好是盖在主窗口前面的设置窗，而日志里连"这个 pid 当时有几扇窗、各是什么标题"都没留，
   事后无从判断。改成 `main_window_id()`：标题正好 `MacMaster` 且 `layer=0` 的窗口**要求正好一扇**，
   挑不到就一张都不出（与 `p29-settings-capture.sh:62-68` 同一立场），并把整份清单写进日志。
   **这是一处仓库级的潜伏缺陷**：现读 `Scripts/` 里 29 支脚本引用 `window-ids.swift`，
   其中 **26 支**在紧邻的两行内用 `head -1` 挑窗（口径=`grep -A2 window-ids.swift` 的输出里
   出现 `head -1`；p31 自己不在其列，它已改走 `main_window_id`）。本轮只修了这一支。
2. **07 交叉读出来的一句假话**：`runningBasis` 无论几档都在句尾拼「 两档都算『正在运行』」，
   而微信这一屏是**两个进程、同一档**（1276 是包内 wxplayer：包名报不出、位置报得出），
   画面里没有任何"两档"可数。改成两档同时出现才拼这句（`MMUninstaller.swift:1505-1510`），
   合同 `03f-uninstaller-running.html` 三处同步，并补一条否证测试
   `RunningAppStatePresentationTests.testBothTiersSentenceOnlyWhenBothTiersArePresent`。
   这一句在旧照片上看不见——旧 07 拍的是磁盘分析页，而那一页根本没有这一行。

### 13.2 哨兵口径必须与画面同源

`# real-running:` 那行从前由 `pgrep -f "/Applications/WeChat.app/Contents/"` 给出，
它数到 **13** 个进程（crashpad_handler、各种 Helper），而照片上只有 **2** 个号——
因为快照里只有 1094 与 1276 两条报出的 `bundleURL` 正好是外层那个 `.app`。
两种口径混用会让哨兵比画面多报，事后看着像"照片漏了 11 个"。
现在换成 `Scripts/running-apps-probe.swift`：与 `RunningAppProbe.resolve` 同一条 API、
同一套比较规则（pid>0、两样都报不出则不参与判定、小写字符串比、不做 realpath），
并在**拍照前后各读一遍**追记进日志（`# snapshot(拍前/拍后):`），
所以"照片上那几个号"与"那一刻的系统状态"是同一件事的两个读数。

### 13.3 没有照片的那一档，以及为什么不给它造一张

`undetermined`（快照里有既报不出包名也报不出位置的条目、且没有正对上的）本机拍不出来：
2026-10-10 当日两次现读，参与判定的分别 163 / 165 条（这个数几小时内就会变），
其中"两样都报不出"的**两次都是 0 条**——包名单独报不出 31 条、位置单独报不出 17 / 19 条，
但没有一条同时缺两样。它只有单测（`testUnattributableIsDefinedByBothFieldsMissing`）。
**不能为了凑一张照片去改 `snapshot()` 的语义**：那等于在这一屏唯一"看不见"的地方喂进去一条假快照。
同一次现读里还有一条 `pid = -1`（`com.apple.dt.Devices`，Xcode 的 helper bundle），
它在 LaunchServices 的账上却不是进程，读取端就剔掉——否则界面会写「正在运行 · 进程 -1」。

**这一组数现在有一支可重算的工具**：`swift Scripts/running-apps-tally.swift`，口径与
`RunningAppProbe.snapshot()` 逐条对齐（先剔 `pid <= 0`，"报不出"= nil 或空串）。
本轮 16:12 用它第三次现读：**参与判定 139 条、包名报不出 19 条、位置报不出 15 条、两样都报不出 0 条**，
`idEmpty` 按 activationPolicy 是 **accessory 12 / prohibited 6 / regular 1**——
139 与 165 相隔不到一小时，这就是上面那句"几小时内就会变"的实测形状；
而 `bothEmpty` 三次都是 0，这一条才是"本机拍不到 `undetermined`"的真正依据。
**`RunningAppProbe.swift` 注释里那句"两次现读"本轮没有跟着改成三次**：注释是编译输入、
进指纹，改一个字就要重建 + 重拍七张，而这一句的结论（`bothEmpty = 0`）一个字没变——
这是明知代价后的取舍，不是漏改；下一次真需要动那一段时，把读数一并带上就是零成本。
**顺带把"同一份源码里两个 `idEmpty`"这件事说清**：`snapshot()` 上那句记的是 **31 条**（15 点档那两次，
照片第一族之前），`bundleIdentifier` 上那句记的是 **19 条**（16 点档，与上面第三次读数同一批）。
同一个量在两个钟点上是两个数，这不是矛盾、是这一族读数的本性——两处都只写了日期没写钟点，
读的时候要按"当日某一时刻的现读"理解，要当下值就自己跑一次那支 tally。

### 13.4 本轮没能复现的那件事

旧 07 拍成了磁盘分析页。用**同一份 env**（`MM_OPEN_MODULE=uninstaller` + `MM_UNINSTALL_SELECT=WeChat`）
连跑三次都没能复现，每次都是卸载页、每次只有一扇窗。
`~/Library/Saved Application State` 在本机**不存在**，所以也不是窗口状态恢复把它带回上一页。
根因未记；现在的兜底是 `# windows(pid=…)` 那行——再落错页，日志会当场说出这个 pid 有几扇窗、
各是什么标题，不用猜。

## 14. P32b 追加（2026-10-10）：v1.1 第 2 条「认出 Steam 启动器」十一档 + 一张修复前

P32a 那八张（`docs/verification/p32-steam/`，审计文档 = `docs/analysis/uninstaller-steam-launcher.md`，
落地记录在 `feature-roadmap.md` §10）拍的是**现状**：这一族在界面上被说成"一个 593 字节的普通应用"。
这一族拍的是**实现之后**，四件事各有一档以上：详情面板「启动器」行的成立与不成立（不成立那一档
是判据，不是配角）、反向那一条（卸载 Steam 本体时 `Application Support/Steam` 有没有点名 `steamapps`）、
敏感度钩子 `MM_UNINSTALL_SENSITIVITY`（审计 §5 第 5 条与 `feature-roadmap.md` §10 都记过的取证缺口，本轮三档补齐）、钩子写错值。
夹具与 P32a 同一支脚本（`Scripts/p32-steam-fixture.sh`，本轮补了第六份 bundle `SteamTwoEntries`），两族照片可以直接对读。

```sh
./Scripts/make-app.sh -o /tmp/mm-app-p32b -s /tmp/mm-scratch-p32b
FIX=/tmp/macmaster-steam-fixture.DnwjwO \
  ./Scripts/p32b-steam-launcher-capture.sh /tmp/mm-app-p32b/MacMaster.app docs/verification/p32b-steam
ONLY=06 ./Scripts/p32b-steam-launcher-capture.sh …        # 只重拍 06
```

| 档 | env（除共用的假 home、`MM_OPEN_MODULE=uninstaller`） | 画面上必须有的（哨兵） |
|---|---|---|
| 01 steamgame-launcher-row | `SELECT=SteamGame` | 标题旁「Steam 启动器」徽章 + 列表行「启动器」chip + 键值行「Steam 生成的启动脚本 · SteamGame（appid 1091500）」+ 依据两句；同一张上「应用大小 593 字节」仍在（**它量的是启动器，这句话就是为它写的**） |
| 02 runsh-launcher-row | `SELECT=SteamRunSh` | 那一行的脚本名是 `run.sh`（appid 440），依据首句跟着写成 `Contents/MacOS/run.sh`——**名字不影响识别**；包名「—」、残留 0 项 |
| 03 plain-tool-control | `SELECT=PlainTool`（本体 8,389,057 B） | **否定档：那三样一个字都不能有**。这一张之外，其余十张的列表里 PlainTool 也一直不带 chip，是否定判据的交叉面。顺带在这张上又看见一次「版本 1.0 ()」（`CFBundleVersion` 缺失那处口径，审计 §5 第 6 条，**本轮未动**） |
| 04 noid-launcher-row | `SELECT=SteamNoId` | 没有 `CFBundleIdentifier` 仍识别（Mole 两处注释都承认真机这类 bundle 常常没包名）：徽章 + chip + 「启动器 … `SteamNoId`（appid 220）」三样都在，而同一张上「包名 —」「来源 无法判定」「残留 0 项」——**识别与残留是两条腿，一条断了另一条照走** |
| 05 two-entries-fallback | `SELECT=SteamTwoEntries` | 「可执行文件 Launcher」+「启动器 … `run.sh`（appid 570）」**同时**在画面上：第一条入口按合同不成立（两段命令），走第二条兜底——这一张证的正是"两条入口都试"那句取舍 |
| 06 steam-self-caveat | `SELECT=Steam`，`1400x1000` | 反向那一条：残留 1 项、`~/Library/Application Support/Steam` 25.2 MB、谨慎、未勾（页脚「已选 0 项残留 · 0 字节」），**行下方独立那一整句**「这一项内含 steamapps 目录，已装游戏通常在它下面；删掉这一项会连游戏一起删。」 |
| 07 enhanced-steamgame-residuals | `SELECT=SteamGame`，`enhanced` | 3 项 524 KB，**没有 `steamapps/common/SteamGame` 这一行**（那 25,165,832 B 不作为残留出现） |
| 08 deep-steamgame-residuals | 同上，`deep` | 与 07 **同一份清单**：这一族的候选全在 0 层，增强与深度对它没有差别——"三档都到不了游戏"现在有照片，不再只有层数推导 |
| 09 deep-steam-self-residuals | `SELECT=Steam`，`deep` | 4 项；谨慎组里 Steam 那一行仍带整句提醒（1400 宽），跨应用那条也在同一张上（见 §14.3 末） |
| 10 bad-hook-value-fallback | `SELECT=SteamGame`，`SENSITIVITY=enhance`（非法值） | 选择器停在「严格」；日志里 stderr 那一行「含非法取值（enhance），只接受 strict\|enhanced\|deep，已回落 strict 档」 |
| 11 steam-self-narrow-window | `SELECT=Steam`，`1000x1000` | 窗口硬最小宽度那一档：06 那一句**仍然整句可见**，卡片边框包住两行 |
| 11a narrow-window-truncation-before-fix | 同上（**修复前**） | 判据照片：提醒当时是拼在副标题里的，画面上只剩 `~/Library/Application` 与 `已装游戏通常在其下` 两段，中间连 `steamapps` 这个词都被省略号吃掉 |

十一份日志的 `# digest:` 全是 `tree=fdf0f95+71d7740f`；11a 是 `+1f91a012`，
**这两处不同源是故意的**——11a 要留的就是"改之前长什么样"，它不该跟着重拍。
`# repo:` 两边都写 `fdf0f95-dirty`（本轮改动未提交时拍的，提交后 `git status` 该族变干净）。

**未喂 `MM_WINDOW_SIZE` 的那几档（01–05、10）尺寸不是脚本给的**：两次整族重跑之间，
01–05 从 1000×652 变成 1000×1000、10 从 1400×1000 变成 1000×1000。
所以这一族的判据不挂在它们的高度上；十二张每张都单独对过一次
`# windows(pid=…)` 记的实际 bounds 与 png 的 pixel 尺寸，**当次跑内一一对上**。

### 14.1 照片抓出来的两处，都不是单测能抓的

1. **同屏自相矛盾**（06 与 01 对读出来的）：依据那一句原先收尾在"也说不出它们在哪"，
   而同一屏的残留行写着"内含 steamapps"并给着 25.2 MB。改成
   「我们只读了这份启动脚本，没有按游戏逐个认，所以说不出装了哪些、各自多大」——
   **没成立的东西一个字都不能占一格**，这一句现在也进了测试禁词表
   （`SteamLauncherPresentationTests` 里"说不出它们在哪"是禁词，它记录的是本轮真实踩过的那次越界）。
2. **窄窗截断**（11a → 11）：行内提醒最初是拼进 `MMItemRow` 副标题的，
   而副标题固定 `.lineLimit(1)` + 中间省略（`MMDesign.swift:858-860`），
   光路径 `~/Library/Application Support/Steam` 就有 **35 个字符**（`printf '%s' … | wc -c` 现读），
   接在"路径 · 证据"后面等于没写。改法是给 `ResidualItem` 加一个独立字段
   `caveat`（`ResidualScanner.swift:159`），由 `ResidualRow` 画在行下方
   （`MMUninstaller.swift:1956-1991`，`.fixedSize(horizontal: false, vertical: true)`）。
   **顺带把另一处截断分了性质**：1000 宽时身份头那行也是中间省略
   （`com.valvesoftware.Steam_re…/DnwjwO/Applications`），但它复述的包名与文件夹
   在下面各有一行完整的，所以那一处不藏判据——与 11a 不同性质，本轮不动它。

### 14.2 提醒只挂在它该挂的那一行

`ResidualCollector.add` 是三条扫描路的唯一收口点，命中判定放在新建候选那一刻
（`ResidualCollector.swift:121` 与 `:222-226`）：只认 `Application Support` 这一类、
只看**直接子项**里有没有 `steamapps`、不递归不数大小。
五条单测钉住它（`ResidualCollectorSteamTests`，含"同一个路径命中两次不许接两遍"与
"目录读不到时保留原句、不因异常丢行"）。08 那张是这条边界的照片侧对照：
`~/Library/Application Support/SteamGame` 也是一条 `Application Support` 候选（1 MB、谨慎），
它下面直接就是 Preferences 那一行，**一个字提醒都没加**——命中条件不是"凡是 Application Support 都提醒"。

**为什么 25.2 MB 那个数值得单独一句**：`du -sk` 现读，夹具里
`Application Support/Steam` 24,592 KB、其下 `steamapps/common/SteamGame` 24,580 KB——
**那一行的体积 99.95% 是游戏**。分组那句"可能包含登录态或未同步数据"讲的是账号，
而画面右侧那个数是游戏库，这就是提醒必须由这一行自己说的理由。

### 14.3 这一族没验到的，写在明处

- **真机上的 `Steam.app` 长什么样，本机无从验**（没装 Steam，`/Applications/Steam.app` 与
  `~/Library/Application Support/Steam` 两条都现读不存在）。所以照片里 Steam 本体自己也挂着
  「Steam 启动器」徽章、appid 0——那是**夹具的构造**（`make_launcher Applications Steam Steam com.valvesoftware.Steam 0`
  给它写了同样的启动脚本），不是对 Valve 那份 bundle 的主张。
  合同只说"满足这套判据的 bundle 会被这样标"，**不能拿这十一张断言真机不会挂、也不能断言它会挂**。
- **`steamapps` 之下到底几层能到，仍然只有推导**：07/08 证到的是"增强与深度两档，
  游戏目录都不作为残留行出现"，至于要放宽到哪一档才够到，本轮没有去改层数试（那是审计 §5 第 4 条里"改清单"那一档，待人拍板）。
- **09 顺出来的那条已在同日落地**：深度档"名称包含应用名"会跨应用收残留，
  且 `Caches/com.example.steamgame` 归到 Steam 名下**默认勾选**（页脚「已选 1 项残留 · 524 KB」）。
  P33a 审计（任务 #161，`docs/analysis/uninstaller-deep-residual-scope.md`）量完 → P33b（任务 #162）按 §5 的
  B + A 实现，落地记录是那份的 §8，取证是本文 §15。**09 那一张本轮重拍过，翻成了未勾选/谨慎。**
- **测试**：九包 **706 / 0 失败 / 1 跳过**（`Scripts/run-all-tests.sh`，本轮在最终树上跑过两次，
  两份输出 `diff` 为空），其中 MMUninstaller 148 → **186**（+38，其余八格与
  `docs/verification/p31-citations/run-all-tests.log` 那份逐字相同——这一句是 `diff` 出来的，不是推的）：
  Steam 这一族三个新文件共 **34** 条
  （`SteamLauncherProbeTests` 24 + `SteamLauncherPresentationTests` 5 + `ResidualCollectorSteamTests` 5），
  余下 4 条在改过的那份 `ResidualSensitivityTests` 里（6 → 10，+36 行；两头现读：
  `git show HEAD:` 那一份数 `func test` 得 6，跑出来的日志数该 suite 得 20 行 = 10 条 × started/passed）。
  结论行入库 `docs/verification/p32b-steam-citations/run-all-tests.log`，
  **那一格的头部还记着一件与本轮无关、但下一个人一定会撞上的事**：
  `git add` 之后 `mm_source_digest` 的后半截从 `71d7740f` 变成 `c6baaaa5`，
  而内容一个字节都没改——配方里已跟踪的走 `git diff HEAD`（带头）、未跟踪的走 `cat`（不带），
  `SteamLauncherProbe.swift` 搬过这条线就换了一次算法。复算对不上的人不必翻二进制。
- **整族重拍的代价，本轮付了两次**：第二次的原因是只改了一句**源码注释**
  （`SteamLauncherProbe.swift:191` 里那句引号中的文案已经不是我实现的那句了）。
  注释是编译输入、进指纹，于是 `+1f91a012` → `+71d7740f`，门禁当场拒拍。
  与 §13 那一次同一笔账：多花四分钟重建重跑，换来这十一张与现在这份源码确实同源。

## 15. P33b 追加（2026-10-12）：残留归属复核六档 + 一张交叉验证

判据本体不在本文复述——它在 `docs/analysis/uninstaller-deep-residual-scope.md` §8（两条线索、
按远近问、弱对弱不算主人、`foreignApps=[]` 就是旧行为）。本文只管**这一族的画面侧**：
`Scripts/p33b-nesting-fixture.sh`（一棵三份本体、六条残留的夹具树）+
`Scripts/p33b-nesting-capture.sh`（六张 + 一张交叉），证据目录
`docs/verification/p33b-nesting/`，七份日志头部都是
`# digest: tree=f7bca94+6bb866e9 app=f7bca94+6bb866e9`（**照片、二进制、跑测的输入同源，这一句是现读对出来的**，
见 `docs/verification/p33b-citations/run-all-tests.log` 那段）。

### 15.1 逐张：每一张钉哪一句

| 张 | 画面 | 它钉住的东西 |
|---|---|---|
| 01-fork-nested-downgraded | Fork / enhanced / 1400×1050 | 残留项 4，chip「2 项默认不勾选」，页脚「已选 2 项残留 · 3.1 MB」。**两条线索各占一行**：`Caches/IDEFoo/AssetsFork` 说「这一项本身归 AssetsFork（名称与包名对应）」，`Caches/IDEFoo/ts-go-fork-embedded` 说「上层目录归 IDEFoo」；同屏两条仍默认勾选的（`Caches/Fork` 硬证据、`Caches/ForkExtras` 包含匹配但两条线索都不成立）证明降级不是一刀切 |
| 02-fork-narrow-window | 同一画面 / 1000×1050 | 提醒整句折成两行显示完，**一个省略号都没有**——这一条是"主人写 `caveat` 不写 `reason`"那个决定的实物（副标题是中间截断那一族，`MMUninstaller.swift:1965` + `MMDesign.swift:859-860`；提醒是 `fixedSize(vertical)`，`MMUninstaller.swift:1987`。**P46f 现读重指**：调用点此前本文写 1938、提醒写 1956——1938 是 P46e 那 27 行把它顶下去的旧值，而 1956 **在 HEAD 上就已经指偏**（那行是 `if let caveat`，`fixedSize` 在它下面第五行），这次一并改到 modifier 那一行） |
| 03-owner-app-unchanged | 选 IDEFoo | 主人自己名下两行一字不变：复核不许把别人的正确结论改坏 |
| 04-assetsfork-hard-evidence | 选 AssetsFork | 那一条本来就走硬证据（「名称与包名对应（位于 IDEFoo 内）」），仍在安全组、仍默认勾选 |
| 05-fork-strict-control | Fork / strict | 严格档只有 1 行：包含匹配按构造到不了这一档（单测 `testStrictTierHasNoContainmentHit` 是同一件事的另一侧） |
| 06-fork-deep-tier | Fork / deep | 与 01 同——这一族在增强与深度两档行为一致 |
| p32b-crosscheck/09 | Steam / deep（P32b 那棵旧夹具） | **改动前后唯一对得上的实物**：同一条 `com.example.steamgame` 从勾选/安全翻成未勾选/谨慎，页脚「已选 0 项残留 · 0 字节」。本文 §14.3 那条"09 顺出来的"就靠这一张收口 |

逐行的应然读数不靠我看照片：`fixture-rows.log` 由**同一棵夹具树上的真扫描**在开拍前现跑生成
（`Caches/IDEFoo/AssetsFork` = 3145728 B、`ts-go-fork-embedded` = 1048576 B、`ForkExtras` = 1048576 B、
`Fork` = 2097152 B，都是 `dd` 出来的真字节，不是 `st_blocks` 的估），
六份 `.log` 的"预期行"那一格直接指向它的对应小节；复用前还验一句 `# 夹具模式：home=$FIX`，
防止拿上一棵树的读数当这一棵的期望。

### 15.2 屏幕给的高度决定照片里有几条（这一族一度有四条）

`MM_WINDOW_SIZE=1400x1250` 会被系统夹回 **1400×1050**（请求 1050 那一档才会原样生效，
01 的日志第 15 行就写着"请求 1400x1050pt，窗口实际 1400x1050pt"；夹没夹用 `sips` 量像素确认过，
不看日志自己怎么说）。卸载页详情区上部（四张统计卡 + 运行状态卡 + 八行基本信息）吃掉约 700 pt，
带提醒的降级行只放得下两条。我一度按"四条都在画面里"写了 capture 的头部说明，**照片自己把它驳回了**——
这是本轮唯一一次被实物反驳的期望值。改法是减夹具而不是加窗口高度：被删掉的两个形状
一个进了上面那张交叉验证照片，一个进了单测，脚本头里写明去哪找。

### 15.3 本轮三笔账

- **注释是编译输入，第三次**：改一句源码注释（`ResidualCollector.swift` 里那句"主人写进提醒、不写进副标题"
  的原文已经不是我实现的那句）→ `f7bca94+a18f4eb8` → `f7bca94+6bb866e9` → 门禁拒拍已出的六张 → 整族重拍。
  §13 一次、§14 一次、本轮一次，三个实例同一笔账。
- **锚点债**：`Scripts/p29-anchor-drift-audit.sh` 本轮量出四处源码改动把 **13 条**入库锚点顶漂
  （`ResidualCollector` +102、`ResidualScanner` +34、`UninstallerModel` +12/+13/+14 三档），
  已在五份文档里逐条重指。**同一轮的新教训是关于工具本身的**：p29 的"可照抄新锚点"回答的是
  "HEAD 那一行的文字搬去哪儿了"，它**不问这条引用当初指对没有**——本轮有 **6 条**在 `f7bca94` 就已经
  指着别的块（`apps-watch.md:132/140/176/206`、本文 `:118` 的 `deletionRoots`、`uninstaller-steam-launcher.md:99`
  的 descend 注释），照抄只会把错锚再搬一次家。所以九条"可照抄"只直接用了能对上句意的那几条，
  其余按句意现读代码重新定位，每条都读过落点原文。另外 p29 只认**带文件名**的引用，
  文档里裸写的相对行号（本轮那处 `:237`→`:265`）对它完全不可见。
- **顺手修了量尺自己**：`p29-anchor-drift-audit.sh:44` 补 `|| true`——"本轮只改测试文件"时那行
  `grep -v` 不吐行并以 1 退出，`set -e` 让量尺在打印任何一行之前死掉。

**测试**：九包 **720 / 0 失败 / 1 跳过**，其中 MMUninstaller 186 → **200**（+14，全部来自新增的
`ResidualOwnershipReviewTests`；逐包求和 = 720 与合计那一格一致，这一格自 P11c 起每轮自证）。
新增那一族的实跑计数是单独核的：`grep "Test Case" … | grep -c "ResidualOwnershipReviewTests.*' passed"` → 14。
结论行入库 `docs/verification/p33b-citations/run-all-tests.log`，那份头部还记了一件本轮的自查：
实现过程中我自己的中间笔记把这一格写成过 196/716，那是没跑出来过的读数——**上轮自报与自己本轮的草稿都要现读复核**。

