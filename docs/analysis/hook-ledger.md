# 全仓钩子台账（hook-ledger）

> 配套 `docs/design-system/README.md` §2 归属矩阵。本台账逐条标注每个 `MM_*` 钩子的
> **只读性** 与 **是否可能触发破坏性流程**，供集成阶段统一落地时排查越界写操作。
> 数据来自 `grep -rn "processInfo.environment\|MM_[A-Z_]+" Packages Sources`（2026-09-30）。

## 0. 结论先行

- 全仓现存钩子 **35 个独立变量名**（`grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' | sort -u` 得 36 个，
  其中 `MM_TRASH_FIXTURE_PROBE` 只是 `TrashWatcherTests.swift:46` 用来探 `/tmp` 守卫的临时 key，不是运行时钩子，不计入）。
  集成阶段新增 `MM_OPTIMIZER_FIXTURE`、`MM_GUARDIAN_ACTIVITY_FIXTURE`、`MM_DISK_HOLD`；
  P4 浅色档新增 `MM_APPEARANCE`、`MM_WINDOW_SIZE`（都在壳层，见下表）；并对 `MM_DISK_SCAN`/`MM_DISK_SELECT` 补 /tmp 守卫；
  磁盘永久删除路径新增 `MM_SHOW_PERMANENT`，并给 `MM_SHOW_TOAST` 加 `permanent` 取值（见下表）。
  **全部为只读展示/状态钩子，无任何钩子会直接触发删除或写盘。**
- **破坏性流程的唯一入口是用户在 UI 里点「确认」按钮**，由 `MMCore.DeletionGuard` + `FileTrashService` 双重闸门拦截。钩子只负责"把页面定格在某个状态便于截图"，不碰真实文件。
- 需要特别留意的"看似会动"的钩子：
  - `MM_AUTO_SCAN` / `MM_DISK_SCAN`：触发**只读扫描**（枚举文件系统、不写），不会删除。
  - `MM_SHOW_CONFIRM` / `MM_SHOW_TRASH_CONFIRM` / `MM_SHOW_TOAST` / `MM_SHOW_PERMANENT`：只**弹出**确认面板/吐司，**真正的删除发生在用户点面板里的「确认」**，不在钩子里。`MM_SHOW_TOAST=permanent` 摆的是"已永久删除"回执，它**没有撤回按钮**、也不会删任何东西（数字借自选中标项）；`MM_SHOW_PERMANENT` 只是把确认面板换成永久删除那块，一个字节都不动。
- `README §2` 矩阵**已过期**：漏了 `MM_GUARDIAN_LOGIN_FIXTURE`、`MM_GUARDIAN_LOAD`（代码已落地，矩阵未同步）。
  → 已在本轮补正（见文末「提请协调者」）。

## 1. 钩子台账

| 钩子 | 归属模块 | 文件:行 | 用途 | 只读? | 破坏性流程? | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| `MM_OPEN_MODULE` | 壳 `Sources/MacMaster` | `MainWindow.swift:43` | 启动后直接跳到指定模块页 | ✅ | 否 | 非法值写 stderr 并停在概览；只认 `MMDestination.rawValue` |
| `MM_SHOW_SETTINGS` | 壳 | `MainWindow.swift:40` | 启动即打开设置 sheet | ✅ | 否 | — |
| `MM_APPEARANCE` | 壳 | `LaunchBehavior.swift:81` | 强制本进程 `NSApp.appearance` 为 `light`/`dark`（别名 `aqua`/`darkAqua`） | ✅ | 否 | **P4 新增**。只改本进程，不动用户系统外观；值写错会沿用系统档并写 stderr 留痕。生效凭据打在启动日志里，`p4-sweep.sh` 会 grep 回控制台 |
| `MM_WINDOW_SIZE` | 壳 | `LaunchBehavior.swift:116` | `=宽x高`（如 `900x600`）改主窗口内容区尺寸 | ✅ | 否 | **P4 新增**。下限 320×200，解析失败/找不到主窗口都写 stderr；`DispatchQueue.main.async` 等窗口上屏。**凭据回读夹取后的真实窗口尺寸**（`asyncAfter 0.3s`）：窗口有 `.frame(minWidth:)` 地板，请求 900 会被夹到 1000，只回显请求值会产出"看着真、来源错"的最小窗口证据 |
| `MM_SETTINGS_TAB` | 壳 | `SettingsView.swift:12` | 设置 sheet 默认选中 tab | ✅ | 否 | 非法值回落 `.general` |
| `MM_OPEN_TAB` | `MMCleaner` | `CleanerContainerView.swift:32` | cleaner 页默认 tab（cache/folders/system） | ✅ | 否 | 非法值回落 `.cache` |
| `MM_CLEANER_FILTER` | `MMCleaner` | `MMCleaner.swift:280` | 搜索框初值（等价于用户手动输入） | ✅ | 否 | — |
| `MM_EXPAND_CATEGORIES` | `MMCleaner` | `MMCleaner.swift:148` | 展开分类 | ✅ | 否 | — |
| `MM_AUTO_SCAN` | `MMCleaner` | `UserFolderCleanView.swift:112` `SystemAnalysisView.swift:78` | 进场即触发扫描 | ✅ | 否（只读扫描） | 仅枚举文件系统，不写不删 |
| `MM_SHOW_CONFIRM` | `MMCleaner` | `MMCleaner.swift:359` `UserFolderCleanView.swift:116` | 弹出删除确认面板 | ✅ | 否（弹面板，删在按钮里） | 实际删除需用户点「确认」，过 `DeletionGuard` |
| `MM_INSTALLER_FIXTURE_DIR` | `MMCleaner` | `UserFolderCleanView.swift:120,366` | 注入安装器残留夹具目录 | ✅ | 否 | **只认 `/tmp` 之下**，越界忽略并写 stderr |
| `MM_FAILURE_FIXTURE` | `MMCleaner` | `MMCleaner.swift:365` | 渲染拒绝回执（=protected） | ✅ | 否 | 仅展示，复用 `MMUI.MMFailurePanel` |
| `MM_SNAPSHOT_FIXTURE` | `MMCleaner` | `MMCleaner.swift` `applySnapshotFixture` | 把"磁盘空间只读报告"里的**快照那一块**换成样例文本（`mixed`/`overflow`/`updateonly`/`none`/`broken`） | ✅ | 否 | 只替换解析器的输入字符串，卷容量仍是真读的；不起命令、不碰盘。未知取值整块忽略 |
| `MM_UNINSTALL_PANE` | `MMUninstaller` | `MMUninstaller.swift:63` | 卸载页默认 pane | ✅ | 否 | 非法值回落 `.apps` |
| `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` | `MMUninstaller` | `UninstallFixtureHooks.swift` | 仅加载 `/tmp` 假应用并打开卸载确认面板 | ✅ | 否 | 解析符号链接后仍须位于 `/tmp`；配合 `Scripts/uninstall-fixture.sh`，绝不自动点击删除 |
| `MM_UNINSTALL_CONFIRM_MODE` | `MMUninstaller` | `MMUninstaller.swift` | 夹具确认模式 `appOnly` / `withResiduals` | ✅ | 否 | 仅在上行有效时读取；省略则为 `appOnly` |
| `MM_ORPHAN_FIXTURE_HOME` | `MMUninstaller` | `MMUninstaller.swift:44` | 注入孤儿扫描夹具 home | ✅ | 否 | **只认 `/tmp` 之下**，越界忽略并写 stderr |
| `MM_TRASH_FIXTURE_DIR` | `MMUninstaller` | `TrashWatcher.swift:94` | 注入废纸篓夹具目录 | ✅ | 否 | 同上，只认 `/tmp` |
| `MM_TRASH_SCAN_HOME` | `MMUninstaller` | `TrashWatcher.swift:100` | 注入废纸篓扫描 home | ✅ | 否 | 同上，只认 `/tmp` |
| `MM_SHOW_TRASH_CONFIRM` | `MMUninstaller` | `MMUninstaller.swift:535` | 弹出废纸篓确认面板 | ✅ | 否（弹面板，删在按钮里） | 删除走 `FileTrashService`，过闸门 |
| `MM_OPEN_TAB` | `MMDisk` | `MMDisk.swift:44` | disk 页默认 tab（tree/list/large） | ✅ | 否 | 非法值回落 `.treemap` |
| `MM_DISK_DEPTH` | `MMDisk` | `MMDisk.swift:128` | 展开深度 1…4 | ✅ | 否 | 越界（非 1…4）忽略 |
| `MM_DISK_FILTER` | `MMDisk` | `MMDisk.swift:132` | 过滤串 | ✅ | 否 | — |
| `MM_DISK_SCAN` | `MMDisk` | `MMDisk.swift:135` | 对指定根路径触发扫描 | ✅ | 否（只读扫描） | 仅枚举，不写。**本轮补 /tmp 守卫**：非 `/tmp`/`/private/tmp` 前缀写 stderr 并忽略 |
| `MM_DISK_SELECT` | `MMDisk` | `MMDisk.swift:998` | 预选路径并展开 | ✅ | 否 | 仅展示选中态。**本轮补 /tmp 守卫**：任一目标非 /tmp 前缀则整体忽略 |
| `MM_DISK_HOLD` | `MMDisk` | `MMDisk.swift`（本轮新增） | `=hold` 冻结在"正在分析磁盘结构"首帧，不触发扫描 | ✅ | 否 | 见 `fidelity-disk.md` §提请协调者 #4 |
| `MM_SHOW_CONFIRM` | `MMDisk` | `MMDisk.swift:1094` | 弹出删除确认面板（回收/进废纸篓） | ✅ | 否（删在按钮里） | 过 `DeletionGuard`；面板里闸口拒绝项已提前为 `.guarded` blocked |
| `MM_SHOW_PERMANENT` | `MMDisk` | `MMDisk.swift:1111` | 把确认面板换成**永久删除**面板 | ✅ | 否（同一层交换 `showMarkConfirm=false` / `showPermanentConfirm=true`，不删） | 值 `acked` 时代码里把确认勾选打上，截图才能拍到"按钮点亮"那一态；勾选本身不落盘 |
| `MM_SHOW_TOAST` | `MMDisk` | `MMDisk.swift:1085,1118` | 弹出回执吐司 | ✅ | 否 | `=permanent` 走"已永久删除 · 无法恢复"那一支（橙色三角、**无撤回按钮**），数字借自当前选中项，不移动任何文件 |
| `MM_GUARDIAN_FIXTURE` | `MMGuardian` | `MMGuardian.swift:374` | 注入守护规则夹具行 | ✅ | 否 | 合成 `com.example.*`，不碰真实登录项 |
| `MM_TCC_FIXTURE` | `MMGuardian` | `MMGuardian.swift:388` | 注入 TCC 授权表行 | ✅ | 否 | 支持 `rows/unreadable/empty/partial` |
| `MM_GUARDIAN_LOGIN_FIXTURE` | `MMGuardian` | `MMGuardian.swift:402` | 注入登录项夹具（rows/empty/indeterminate/scanerror） | ✅ | 否 | **README §2 漏列，本轮补正** |
| `MM_GUARDIAN_LOAD` | `MMGuardian` | `MMGuardian.swift:414` | `=hold` 时整页冻结首帧（测量中+骨架） | ✅ | 否 | **README §2 漏列，本轮补正** |
| `MM_GUARDIAN_ACTIVITY_FIXTURE` | `MMGuardian` | `MMGuardian.swift`（本轮新增） | 系统活动卡注入 `empty/rows` | ✅ | 否 | 见 `fidelity-guardian.md` §5 G1；合成条目标"夹具值" |
| `MM_OPEN_TAB` | `MMOptimizer` | `MMOptimizer.swift:42` | optimizer 页默认 tab（duplicates/browser/status/devtools） | ✅ | 否 | 非法值回落 `.duplicates` |
| `MM_OPTIMIZER_FIXTURE` | `MMOptimizer` | `MMOptimizer.swift`（本轮新增） | 四 tab 空/失败/PROTECTED 态统一夹具（duplicates:N/empty/scannedEmpty、browser:rows/empty、status:allReadOnly、devtools:notInstalled/unreadable、protected） | ✅ | 否 | 见 `fidelity-optimizer.md` §6；纯数值/状态注入，不读 /tmp、不写盘、不 spawn |
| `MM_MONITOR_HOLD` | `MMMonitor` | `MMMonitor.swift`（#50 新增） | `=hold` 时冻结在 `.empty` 首帧 | ✅ | 否 | 见 `docs/analysis/fidelity-monitor.md` §4 |
| `MM_MONITOR_FIXTURE` | `MMMonitor` | `MMMonitor.swift`（#50 新增） | 注入确定快照（populated/memoryNil/swapOff/perCoreRed/perCoreEmpty/disk-unavailable:reason/processes/menubarOff） | ✅ | 否 | 纯数值注入，不读 `/tmp`、不采样 |

## 2. 各模块钩子小结

- **壳（Sources/MacMaster）**：5 个，纯导航/打开/取证档（`MM_APPEARANCE` `MM_WINDOW_SIZE`），零副作用。
- **MMCleaner**：7 个，含 1 个 `/tmp` 路径夹具（`MM_INSTALLER_FIXTURE_DIR`，越界即忽略）。
- **MMUninstaller**：5 个，含 3 个 `/tmp` 路径夹具，全部越界即忽略。
- **MMDisk**：8 个（新增 `MM_DISK_HOLD`），`MM_DISK_SCAN`/`MM_DISK_SELECT` 本轮补 `/tmp` 守卫。
- **MMGuardian**：5 个（新增 `MM_GUARDIAN_ACTIVITY_FIXTURE`），全 `com.example.*` 合成，不写盘。
- **MMOptimizer**：2 个（新增 `MM_OPTIMIZER_FIXTURE`）。`DevToolCacheAudit.swift:166` 读的 `env` 是 **PATH 探测**（找可执行文件），**不是 `MM_` 夹具钩子**，与截图无关，不计入台账。
- **MMMonitor**：`MM_OPEN_MODULE` + #50 新增 2 个（`MM_MONITOR_HOLD` / `MM_MONITOR_FIXTURE`），全只读。

## 3. 破坏性流程边界（重要）

- 任何钩子都**不会**直接调用 `FileTrashService.trash()` / `DeletionGuard` 的放行分支。
- 钩子能到达的最"危险"状态只是"弹出确认面板"（如 `MM_SHOW_CONFIRM`）。从面板到真实删除还需：
  1. 用户点击「确认」；
  2. `DeletionGuard` 闸门判定（PROTECTED → 拒绝，走 shield/caution 分档）；
  3. `FileTrashService` 执行移入废纸篓（**不是**直接 `rm`，可撤回）。
- 因此：钩子台账里**没有任何一条**需要标"可能触发破坏性流程 = 是"。集成阶段若发现某钩子绕过了上述链路（例如直接调用删除而非走确认面板），属于越界 bug，应退回模块路由修。
- 永久删除路径同构，且更窄：`MM_SHOW_PERMANENT` 只把 `showMarkConfirm` 关掉、
  `showPermanentConfirm` 打开（一次事务里交换两个 `@State`，SwiftUI 能正常叠出第二块面板，
  截图已证）。真正 `removeItem` 的只有 `permanentConfirmSheet` 那颗按钮，而它要求
  **本次打开面板内**勾过 `permanentAcknowledged`（`@State`，不持久化，关窗归零），
  且刻意没挂 `.keyboardShortcut(.defaultAction)`——回车点不亮它。
- **一条拍不到的状态**：`.guarded` blocked 行。`MM_DISK_SELECT` 只接受 /tmp 前缀路径，
  而 `DeletionGuard` 的保护清单里没有任何 /tmp 路径，两者没有交集，所以这一行在磁盘页
  无法用截图取证。它的判定由 `DiskRemovalTests`
  （`testGuardedPathIsBlockedUpFrontWithItsReason` / `testGuardedIsReportedBeforeVanished`）
  和 `PermanentDeleteTests.testProtectedPathIsRefusedAndUntouched` 覆盖。
  这不是 bug，是取证手法的边界，记在这里免得下轮又去找脚本。
- 同样**没拍**的还有"按下永久删除按钮那一瞬间之后"的界面——不允许对原生 UI 合成点击。
  `docs/verification/p5-disk-permanent/toast.jpg` 拍的是回执吐司本身
  （`MM_SHOW_TOAST=permanent` 摆数字，不删文件），不等于删除动作的产物。

## 4. 提请协调者

1. **README §2 矩阵已过期**：补列 `MM_GUARDIAN_LOGIN_FIXTURE`、`MM_GUARDIAN_LOAD`（见本文件文末「已落地修正」）；同步把 `mmmonitor` 行从"无内容钩子"更新为已含 `MM_MONITOR_HOLD` / `MM_MONITOR_FIXTURE`。本轮已直接改 `docs/design-system/README.md`。
2. **`MM_OPTIMIZER` 缺少面向无头核对的统一夹具入口**：~~目前只有 `MM_OPEN_TAB`~~ **已落地**：集成阶段新增 `MM_OPTIMIZER_FIXTURE`（duplicates:N/empty/scannedEmpty、browser:rows/empty、status:allReadOnly、devtools:notInstalled/unreadable、protected），见 `OptimizerFixtureHooks.swift`。
3. **`MM_DISK_SCAN` 越界值处理**：~~当前 `MMDisk.swift:135` 未校验 /tmp~~ **已落地**：集成阶段对 `MM_DISK_SCAN`/`MM_DISK_SELECT` 补 `/tmp`/`/private/tmp` 前缀守卫，越界写 stderr 并忽略。

## 5. 取证工具链（P4 浅色档）

| 脚本 | 干什么 | 为什么在仓库里 |
| --- | --- | --- |
| `Scripts/p4-sweep.sh` | 逐屏起实例 → 按 pid 抓自己窗口 → 抓完即杀；支持明暗档、窗口尺寸、只跑指定屏 | 手动敲这串命令容易抓到别的实例的窗口，脚本把 `--pid` 这条红线固化下来 |
| `Scripts/pixel-probe.swift` | 从 PNG 定点取色 / 沿一条线打色带 | 肉眼看截图会把"整体偏亮"当成"浅色档生效"，局部混档只有逐点量才看得见 |
| `Scripts/disk-fixture.sh` | 造 `/tmp/macmaster-disk-fixture`（175 MB，含一块会被扫描层跳过的 `Library/`） | `MM_DISK_SCAN` 只认 /tmp；夹具固定大小才能核对"页面报的数对不对" |
| `Scripts/window-ids.swift` | 按 pid 列窗口 id | 见 `docs/design-system/README.md` §5 红线：`--pid` 不是可选项 |
| `Scripts/trash-space-measure.swift` | 写 200 MiB → `trashItem` → 从废纸篓删掉，三步各读一次卷可用 | "移入废纸篓就回收了 X"是本模块差点写进 UI 的假话；只有实测能把它证伪。读的是应用自己用的那两个 `URLResourceKey`，所以差值就是页面上会显示的口径 |

- 三个面（`cardSurface`/`recessedSurface`/`underPageSurface`）的实测值与判定见
  `docs/analysis/fidelity-light-dark.md` §2。
- **同一批钩子的取值顺序会互相牵制**（本轮踩到）：`MM_DISK_SELECT` 是按逗号顺序逐个
  `node(atPath:)` 往下钻的，把扫描根本身写在第一个，钩子就会一路向上选到 `/tmp`，
  既暴露了无关目录又让 `selected == nil`，于是"借选中项数字摆一拍"的吐司支路整条哑掉。
  截图用的正确顺序是 `Downloads,Movies,<root>`。另外 `MM_SHOW_TOAST=permanent` 那一支
  必须写在 `guard env["MM_SHOW_CONFIRM"] != nil` **之前**并自己 return，否则确认面板
  盖住吐司，拍到的还是面板。
- **页面下方的区块靠"缩短上方内容"顶进画面，不靠滚窗**：4K 屏上窗口高度仍被钳在约 1080pt，
  `MM_WINDOW_SIZE=1400x1900` 拿到的还是 1050pt 高的窗（照片看着像生效、其实没变）。
  要看系统清理页底部的"磁盘空间只读报告"，正确做法是给 `MM_CLEANER_FILTER` 一个只命中
  一类的词（`废纸篓`），表格缩到一行，区块自己就进画面了。
- **夹具文本也要有测试**：Swift 多行字面量的收尾**不带换行**，
  `"..." + join(...)` 拼出来的夹具会把第一条快照粘在表头行上被解析器吃掉——
  照片上"另有 2 个快照"看着挺像溢出态，其实少了一条。判据在 `SnapshotFixtureTests`。
- **不要写脚本用 NSColor 查语义色的值**：脱离真实绘制上下文解析动态色，明暗两档会给出同一个（错的）值。
  这条坑记在 `pixel-probe.swift` 文件头。
