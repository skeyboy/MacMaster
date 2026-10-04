# 全仓钩子台账（hook-ledger）

> 配套 `docs/design-system/README.md` §2 归属矩阵。本台账逐条标注每个 `MM_*` 钩子的
> **只读性** 与 **是否可能触发破坏性流程**，供集成阶段统一落地时排查越界写操作。
> 数据来自 `grep -rn "processInfo.environment\|MM_[A-Z_]+" Packages Sources`（2026-09-30）。

## 0. 结论先行

- 全仓现存钩子 **49 个独立变量名**（`grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' | sort -u` 得 50 个，
  其中 `MM_TRASH_FIXTURE_PROBE` 只是 `TrashWatcherTests.swift:46` 用来探 `/tmp` 守卫的临时 key，不是运行时钩子，不计入）。
  集成阶段新增 `MM_OPTIMIZER_FIXTURE`、`MM_GUARDIAN_ACTIVITY_FIXTURE`、`MM_DISK_HOLD`；
  P4 浅色档新增 `MM_APPEARANCE`、`MM_WINDOW_SIZE`（都在壳层，见下表）；并对 `MM_DISK_SCAN`/`MM_DISK_SELECT` 补 /tmp 守卫；
  磁盘永久删除路径新增 `MM_SHOW_PERMANENT`，并给 `MM_SHOW_TOAST` 加 `permanent` 取值（见下表）；
  P5.1「开发产物」页新增 `MM_PURGE_FIXTURE_HOME` + `MM_DEV_EXPAND/SELECT/SCROLL/CONFIRM` 共 5 个（见下表）；
  P5.2「安装来源」新增 `MM_UNINSTALL_SELECT`（点名要选中的那一行），并给 `MM_UNINSTALL_CONFIRM_MODE` 加 `none`
  （只拍列表与详情、不弹面板——面板会盖掉这一轮真正要拍的两块）。
  P5.3「应用装卸监听」新增 `MM_APPS_WATCH_FIXTURE_DIR`、`MM_APPS_WATCH_AUTO_SCAN`、`MM_UNINSTALL_SELF_ECHO`
  与取证用的 `MM_PROBE_WINDOW` 共 4 个。
  P6.1「开发产物截断根续扫」新增 `MM_DEV_ROOT_BUDGET_SECONDS`、`MM_DEV_CONTINUE_BUDGET_SECONDS`、
  `MM_DEV_AUTO_CONTINUE` 共 3 个：前两把预算调到极小好让首批**必然**截断，第三把续扫批自动跑掉——
  有了这三个，①含截断 / ②续扫之后 / ③同一根再截断三档全部零点击（见下表）。
  P6.2a「磁盘标记跨重扫存续」新增 `MM_DISK_RESCAN` 1 个：首扫落地后自动再扫一次（值同样只认 /tmp），
  配合"标记钩子只重放一次"才拍得到 ②同根重扫（标记还在）与 ③换根重扫（挂不回去的丢弃并点名）。
- **除 `MM_UNINSTALL_SELF_ECHO` 一条外全部只读**：那个钩子会让应用真的把**夹具里**的那个 app 移进废纸篓
  （这是 §5 那两种回声文案唯一的产生路径），所以它被两道锁钉住：夹具 home 必须是 `/tmp` 下的假 home、
  目标必须用 `MM_UNINSTALL_SELECT` 点名点到；跑完取证脚本会按 bundle 标识清掉那一条。
  其余钩子只负责"把页面定格在某个状态便于截图"，不碰真实文件。
- **破坏性流程的唯一入口是用户在 UI 里点「确认」按钮**，由 `MMCore.DeletionGuard` + `FileTrashService` 双重闸门拦截。
- 需要特别留意的"看似会动"的钩子：
  - `MM_AUTO_SCAN` / `MM_DISK_SCAN`：触发**只读扫描**（枚举文件系统、不写），不会删除。`MM_PURGE_FIXTURE_HOME` 同理——它只换扫描根，扫的仍是 `/tmp` 下的假项目。
  - `MM_SHOW_CONFIRM` / `MM_SHOW_TRASH_CONFIRM` / `MM_DEV_CONFIRM` / `MM_SHOW_TOAST` / `MM_SHOW_PERMANENT`：只**弹出**确认面板/吐司，**真正的删除发生在用户点面板里的「确认」**，不在钩子里。`MM_SHOW_TOAST=permanent` 摆的是"已永久删除"回执，它**没有撤回按钮**、也不会删任何东西（数字借自选中标项）；`MM_SHOW_PERMANENT` 只是把确认面板换成永久删除那块，一个字节都不动。
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
| `MM_OPEN_TAB` | `MMCleaner` | `CleanerContainerView.swift:34` | cleaner 页默认 tab（cache/folders/system/**dev**） | ✅ | 否 | 非法值回落 `.cache`。**P5.1 新增 `dev`（开发产物子页）** |
| `MM_CLEANER_FILTER` | `MMCleaner` | `MMCleaner.swift:280` | 搜索框初值（等价于用户手动输入） | ✅ | 否 | — |
| `MM_EXPAND_CATEGORIES` | `MMCleaner` | `MMCleaner.swift:148` | 展开分类 | ✅ | 否 | — |
| `MM_AUTO_SCAN` | `MMCleaner` | `UserFolderCleanView.swift:112` `SystemAnalysisView.swift:78` | 进场即触发扫描 | ✅ | 否（只读扫描） | 仅枚举文件系统，不写不删 |
| `MM_SHOW_CONFIRM` | `MMCleaner` | `MMCleaner.swift:359` `UserFolderCleanView.swift:116` | 弹出删除确认面板 | ✅ | 否（弹面板，删在按钮里） | 实际删除需用户点「确认」，过 `DeletionGuard` |
| `MM_INSTALLER_FIXTURE_DIR` | `MMCleaner` | `UserFolderCleanView.swift:120,366` | 注入安装器残留夹具目录 | ✅ | 否 | **只认 `/tmp` 之下**，越界忽略并写 stderr |
| `MM_FAILURE_FIXTURE` | `MMCleaner` | `MMCleaner.swift:365` | 渲染拒绝回执（=protected） | ✅ | 否 | 仅展示，复用 `MMUI.MMFailurePanel` |
| `MM_SNAPSHOT_FIXTURE` | `MMCleaner` | `MMCleaner.swift` `applySnapshotFixture` | 把"磁盘空间只读报告"里的**快照那一块**换成样例文本（`mixed`/`overflow`/`updateonly`/`none`/`broken`） | ✅ | 否 | 只替换解析器的输入字符串，卷容量仍是真读的；不起命令、不碰盘。未知取值整块忽略 |
| `MM_PURGE_FIXTURE_HOME` | `MMCleaner` | `DevArtifactView.swift:45` | 把「开发产物」页的扫描根换成假 home | ✅ | 否 | **P5.1 新增。只认 `/tmp`**：`realpath` 解析后**再复核一次前缀**，越界整块忽略。这一屏的终点是删除按钮，所以钩子绝不能把用户的真项目变成可以整片勾选的夹具。配合 `Scripts/purge-fixture.sh` |
| `MM_DEV_EXPAND` | `MMCleaner` | `DevArtifactView.swift:109` | 扫描回来后把所有项目分组一次性展开 | ✅ | 否 | **P5.1 新增**。非空即生效，只改内存里的 `expandedRoots` |
| `MM_DEV_SELECT` | `MMCleaner` | `DevArtifactView.swift:112` | `=untouched` 时勾选全部"判定可回收且体积已量到"的行 | ✅ | 否 | **P5.1 新增**。只写内存 `Set<String>`；受保护、嵌套已计入、体积为 nil 的行**选不中**（`isSelectable`），所以这一拍里的勾选数就是删除按钮将来真正会数的数 |
| `MM_DEV_SCROLL` | `MMCleaner` | `DevArtifactView.swift:428` | `=end` 时列表自滚到底 | ✅ | 否 | **P5.1 新增**。窗口高度被屏幕钳住，底部合计条和操作条在首屏外；用 `ScrollViewReader` 自滚**代替合成滚轮事件** |
| `MM_DEV_CONFIRM` | `MMCleaner` | `DevArtifactView.swift:236` | 弹出开发产物删除确认面板 | ✅ | 否（弹面板，删在按钮里） | **P5.1 新增**。链路同 §3 三关：确认按钮 → `DeletionGuard` → `FileTrashService` |
| `MM_DEV_ROOT_BUDGET_SECONDS` | `MMCleaner` | `DevArtifactView.swift:138,146` | 覆盖**全量扫描**的每根预算（`ProjectArtifactRules.rootBudgetSeconds`） | ✅ | 否（只读扫描，只是提前收尾） | **P6.1 新增**。必须 `>0` 才生效，真机不设就是原口径 15 秒。同时把 `totalBudgetSeconds` 抬到 `max(总, 覆盖值)`——只改每根预算而总时限仍写死 60 秒的话，钩子写 120 实际拿到的是 60。点名条里"每次 X 秒"读的就是这个数，抄字面量会骗人 |
| `MM_DEV_CONTINUE_BUDGET_SECONDS` | `MMCleaner` | `DevArtifactView.swift:138,146` | 覆盖**续扫批次**的每根预算 | ✅ | 否 | **P6.1 新增**。为什么必须两个键：同一个极小预算下，首批截断的根在第二批必然同样截断，「本轮扫完」（绿 chip + 「第 N 批补全」）那一档就永远拍不到 |
| `MM_DEV_AUTO_CONTINUE` | `MMCleaner` | `DevArtifactView.swift:159,175` | 全量扫完之后自动再跑最多 N 批续扫 | ✅ | 否（跑的是同一套只读扫描） | **P6.1 新增**。只认 `1…3`，其余值忽略。每批之间复查 `canContinueTruncatedRoots`，试满 2 次的根自动排除，所以不会自己循环成常驻扫描。存在的理由：②「续扫之后」与③「已试过 2 次」两档都要按一次按钮才进得去，而**合成点击会逃逸到用户的其它应用**（老规矩），点击链本身不在取证范围 |
| `MM_UNINSTALL_PANE` | `MMUninstaller` | `MMUninstaller.swift:63` | 卸载页默认 pane | ✅ | 否 | 非法值回落 `.apps` |
| `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` | `MMUninstaller` | `UninstallFixtureHooks.swift` | 仅加载 `/tmp` 假应用并打开卸载确认面板 | ✅ | 否 | 解析符号链接后仍须位于 `/tmp`；配合 `Scripts/uninstall-fixture.sh`，绝不自动点击删除 |
| `MM_UNINSTALL_CONFIRM_MODE` | `MMUninstaller` | `MMUninstaller.swift:73` | 夹具确认模式 `appOnly` / `withResiduals` / `none` | ✅ | 否 | 仅在上行有效时读取；省略则为 `appOnly`。**P5.2 新增 `none`**：只选行不弹面板，面板会盖住列表的行内徽章与详情的来源三行 |
| `MM_UNINSTALL_SELECT` | `MMUninstaller` | `MMUninstaller.swift:84` | 按 `bundleName` 点名要选中的那一行 | ✅ | 否 | **P5.2 新增**。只写 `selectedAppID`，不点任何按钮。点不到时写 stderr 并**什么都不选**——宁可拍出一张空态，也不悄悄换成别的应用。真机上不需要夹具目录就能用（选中态是内存里的），夹具截图下与 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 配合 |
| `MM_ORPHAN_FIXTURE_HOME` | `MMUninstaller` | `MMUninstaller.swift:44` | 注入孤儿扫描夹具 home | ✅ | 否 | **只认 `/tmp` 之下**，越界忽略并写 stderr |
| `MM_TRASH_FIXTURE_DIR` | `MMUninstaller` | `TrashWatcher.swift:94` | 注入废纸篓夹具目录 | ✅ | 否 | 同上，只认 `/tmp` |
| `MM_TRASH_SCAN_HOME` | `MMUninstaller` | `TrashWatcher.swift:100` | 注入废纸篓扫描 home | ✅ | 否 | 同上，只认 `/tmp` |
| `MM_SHOW_TRASH_CONFIRM` | `MMUninstaller` | `MMUninstaller.swift:535` | 弹出废纸篓确认面板 | ✅ | 否（弹面板，删在按钮里） | 删除走 `FileTrashService`，过闸门 |
| `MM_APPS_WATCH_FIXTURE_DIR` | `MMUninstaller` | `AppFolderWatcher.swift:117` | 把「应用目录监听」的根换成夹具目录 | ✅ | 否 | **P5.3 新增。只认 `/tmp`**（复用 `TrashWatcher.fixtureEnvironmentValue`）。只改监听根，不写盘；配合 `Scripts/apps-watch-fixture.sh` |
| `MM_APPS_WATCH_AUTO_SCAN` | `MMUninstaller` | `MMUninstaller.swift:84-87` | 启动后自动走一次消失卡的「重新载入并扫描」 | ✅ | 否（扫描只读，删在按钮里） | **P5.3 新增**。**必须 `MM_APPS_WATCH_FIXTURE_DIR` 成立才生效**，否则忽略。合成点击进不了原生按钮，而这张卡的终点不跑一次就拍不到 |
| `MM_UNINSTALL_SELF_ECHO` | `MMUninstaller` | `MMUninstaller.swift:95-98` | 自动执行一次「仅卸载应用」，用来拍自我回声文案与回声抑制 | ⚠️ 会动文件 | **是**：把夹具里那个 app 真的移进废纸篓 | **P5.3 新增**。**必须 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME`（/tmp 假 home）成立才生效**；`MM_UNINSTALL_SELECT` 点名，取不到就不动。跑完 `Scripts/apps-watch-run.sh` 会按 bundle 标识（不认名字）清掉本次进废纸篓的夹具应用 |
| `MM_PROBE_WINDOW` | 壳 `Sources/MacMaster` | `WindowProbe.swift:12` | 按 0.2…16s 若干时间点把每个真实窗口的 AppKit 帧写到 stderr | ✅ | 否 | **P5.3 新增**（取证工具，不是界面钩子）。只读 `frame/bounds/contentLayoutRect/subviews`，不改任何帧；没有这个变量时 `start()` 直接返回。量的是"宿主视图有没有比窗口高"，见 `apps-watch.md` §7 |
| `MM_OPEN_TAB` | `MMDisk` | `MMDisk.swift:44` | disk 页默认 tab（tree/list/large） | ✅ | 否 | 非法值回落 `.treemap` |
| `MM_DISK_DEPTH` | `MMDisk` | `MMDisk.swift:128` | 展开深度 1…4 | ✅ | 否 | 越界（非 1…4）忽略 |
| `MM_DISK_FILTER` | `MMDisk` | `MMDisk.swift:132` | 过滤串 | ✅ | 否 | — |
| `MM_DISK_SCAN` | `MMDisk` | `MMDisk.swift:135` | 对指定根路径触发扫描 | ✅ | 否（只读扫描） | 仅枚举，不写。**本轮补 /tmp 守卫**：非 `/tmp`/`/private/tmp` 前缀写 stderr 并忽略 |
| `MM_DISK_SELECT` | `MMDisk` | `MMDisk.swift:1094` | 预选路径并展开 | ✅ | 否 | 仅展示选中态。**本轮补 /tmp 守卫**：任一目标非 /tmp 前缀则整体忽略。**P6.2a 起只重放一次**（`selectionHookApplied`）：它代表"用户动手标记过一次"，每次扫描都重放会把该丢弃的标记重新加回来 |
| `MM_DISK_RESCAN` | `MMDisk` | `MMDisk.swift:191` | 首扫落地后**自动再扫一次**指定根（P6.2a 新增） | ✅ | 否（只读扫描） | 值同样只认 `/tmp`/`/private/tmp` 前缀，越界写 stderr 并忽略。给同一个根=拍"标记跨重扫还在"，给另一个根=拍"挂不回去的丢弃并点名" |
| `MM_DISK_HOLD` | `MMDisk` | `MMDisk.swift`（本轮新增） | `=hold` 冻结在"正在分析磁盘结构"首帧，不触发扫描 | ✅ | 否 | 见 `fidelity-disk.md` §提请协调者 #4 |
| `MM_SHOW_CONFIRM` | `MMDisk` | `MMDisk.swift:1094` | 弹出删除确认面板（回收/进废纸篓） | ✅ | 否（删在按钮里） | 过 `DeletionGuard`；面板里闸口拒绝项已提前为 `.guarded` blocked |
| `MM_SHOW_PERMANENT` | `MMDisk` | `MMDisk.swift:1111` | 把确认面板换成**永久删除**面板 | ✅ | 否（同一层交换 `showMarkConfirm=false` / `showPermanentConfirm=true`，不删） | 值 `acked` 时代码里把确认勾选打上，截图才能拍到"按钮点亮"那一态；勾选本身不落盘 |
| `MM_SHOW_TOAST` | `MMDisk` | `MMDisk.swift:1085,1118` | 弹出回执吐司 | ✅ | 否 | `=permanent` 走"已永久删除 · 无法恢复"那一支（橙色三角、**无撤回按钮**），数字借自当前选中项，不移动任何文件 |
| `MM_GUARDIAN_FIXTURE` | `MMGuardian` | `MMGuardian.swift:410` | 注入守护规则夹具行 | ✅ | 否 | 合成 `com.example.*`，不碰真实登录项。行号 P6.2b 起（整页骨架重排把钩子块往下推了 36 行） |
| `MM_TCC_FIXTURE` | `MMGuardian` | `MMGuardian.swift:424` | 注入 TCC 授权表行 | ✅ | 否 | 支持 `rows/unreadable/empty/partial` |
| `MM_GUARDIAN_LOGIN_FIXTURE` | `MMGuardian` | `MMGuardian.swift:438` | 注入登录项夹具（rows/empty/indeterminate/scanerror） | ✅ | 否 | **README §2 漏列，本轮补正** |
| `MM_GUARDIAN_LOAD` | `MMGuardian` | `MMGuardian.swift:450` | `=hold` 时整页冻结首帧（测量中+骨架） | ✅ | 否 | **README §2 漏列，本轮补正** |
| `MM_GUARDIAN_ACTIVITY_FIXTURE` | `MMGuardian` | `MMGuardian.swift:461` | 系统活动卡注入 `empty/rows` | ✅ | 否 | 见 `fidelity-guardian.md` §5 G1（该条已标已落实）；合成条目标"夹具值"。**P6.2d 起用 `MM_GUARDIAN_CARDS=activity` 只渲染活动卡出片**（§6.6.3） |
| `MM_GUARDIAN_CARDS` | `MMGuardian` | `MMGuardian.swift` `GuardianCardFilter`（`GuardianFixtureHooks.swift`） | 卡显示过滤，逗号子集 `occupancy\|tcc\|login\|activity` | ✅ | 否 | **P6.2d 新增**。纯显示层过滤，不改变数据流；非法值整批拒绝并写 stderr。解决活动卡排在第 4 位永远在折叠线以下的问题——07/10 两档用 `=activity` 只渲染活动卡，不再需要拉高窗口+压矮上方三卡 |
| `MM_OPEN_TAB` | `MMOptimizer` | `MMOptimizer.swift:42` | optimizer 页默认 tab（duplicates/browser/status/devtools） | ✅ | 否 | 非法值回落 `.duplicates` |
| `MM_OPTIMIZER_FIXTURE` | `MMOptimizer` | `MMOptimizer.swift`（本轮新增） | 四 tab 空/失败/PROTECTED 态统一夹具（duplicates:N/empty/scannedEmpty、browser:rows/empty、status:allReadOnly、devtools:notInstalled/unreadable、protected） | ✅ | 否 | 见 `fidelity-optimizer.md` §6；纯数值/状态注入，不读 /tmp、不写盘、不 spawn |
| `MM_MONITOR_HOLD` | `MMMonitor` | `MMMonitor.swift`（#50 新增） | `=hold` 时冻结在 `.empty` 首帧 | ✅ | 否 | 见 `docs/analysis/fidelity-monitor.md` §4 |
| `MM_MONITOR_FIXTURE` | `MMMonitor` | `MMMonitor.swift`（#50 新增） | 注入确定快照（populated/memoryNil/swapOff/perCoreRed/perCoreEmpty/disk-unavailable:reason/processes/menubarOff） | ✅ | 否 | 纯数值注入，不读 `/tmp`、不采样 |

## 2. 各模块钩子小结

- **壳（Sources/MacMaster）**：5 个，纯导航/打开/取证档（`MM_APPEARANCE` `MM_WINDOW_SIZE`），零副作用。
- **MMCleaner**：16 个（P5.1 新增 5 个：`MM_PURGE_FIXTURE_HOME` + `MM_DEV_EXPAND/SELECT/SCROLL/CONFIRM`；P6.1 再新增 3 个预算/自动续扫钩子；含 P4.6 的 `MM_SNAPSHOT_FIXTURE`，早前列数漏计它）。含 2 个 `/tmp` 路径夹具（`MM_INSTALLER_FIXTURE_DIR`、`MM_PURGE_FIXTURE_HOME`，越界即忽略）。
- **MMUninstaller**：5 个，含 3 个 `/tmp` 路径夹具，全部越界即忽略。
- **MMDisk**：9 个（新增 `MM_DISK_HOLD`；P6.2a 再新增 `MM_DISK_RESCAN`），`MM_DISK_SCAN`/`MM_DISK_SELECT`/`MM_DISK_RESCAN` 都带 `/tmp` 守卫。
- **MMGuardian**：6 个（新增 `MM_GUARDIAN_ACTIVITY_FIXTURE`、`MM_GUARDIAN_CARDS`），全 `com.example.*` 合成，不写盘。`MM_GUARDIAN_CARDS` 是纯显示层过滤。
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
| `Scripts/purge-fixture.sh` | 造 `/tmp/macmaster-purge-fixture`（108 MB，14 个项目 / 22 处产物）：覆盖 CACHEDIR.TAG、`node_modules`、`build`+`package.json`、近期在用、读不进、云同步、受保护作者内容、无体积各行 | **P5.1 新增**。`MM_PURGE_FIXTURE_HOME` 只认 /tmp，所以真机上拍不到的分支必须在这里凑齐；脚本末尾的「产物目录清点」会把 23 个目录逐个列年龄，跑一遍就能核对页面报的数对不对（含两个**不该出现**的诱饵：游离的 `node_modules` 和 `Projects/sneaky` 里指向外部的软链） |
| `Scripts/provenance-fixture.sh` | 造一棵假 home + 一份假 brew 账本（`<root>/.homebrew/Caskroom`），五档来源一次凑齐：设备号同一（Highball）、只有名字对上（CodeEdit，staged 链接指向别处）、MAS 收据（WeChat）、两份账本抢同一个 bundle（Firefox：firefox 与 firefox-beta）、什么都没有（MysteryApp） | **P5.2 新增**。真机上一台机器通常只有一两档拍得到，而这一屏的文案合同是**按档给的**（弱档不给 brew 命令、歧义档要点名两个 token），必须逐档摆拍。账本跟着假 home 走：`provenancePrefixesFactory` 指到 `<home>/.homebrew`、`provenanceReceiptsRootFactory` 给 `nil`，否则照片里"这一档没命中"到底是没凭据还是没读系统收据就分不出来了 |

| `Scripts/p62-capture.sh` | 磁盘标记跨重扫三档：① 打上标记 ② 同根重扫（标记还在）③ 换根重扫（挂不回去的丢弃并点名），一次跑完 | **P6.2a 新增**。三档共用同一份夹具与同一串标记钩子，差别只在 `MM_DISK_RESCAN` 给不给、给哪个根；写成脚本是因为 ② 与 ③ 的差别完全取决于第二次扫描的根，手工跑很容易把两档跑成同一档 |
| `Scripts/p62b-capture.sh` | 还原度收口**十档 × 明暗两套**：概览首帧/满轴（等真实采样 5s、30s）+ 守护页真机态/夹具态（`MM_TCC_FIXTURE=partial MM_GUARDIAN_LOGIN_FIXTURE=rows`）/首帧（`MM_GUARDIAN_LOAD=hold`）/**图标环 `MM_GUARDIAN_FIXTURE=camera=inuse,mic=idle`**/系统活动卡 `rows`+`empty`/登录项"未对表"档/登录项读取失败档。**07–10 用 `MM_GUARDIAN_CARDS` 只渲染目标卡**（P6.2d），不再需要拉高窗口+压矮上方三卡 | **P6.2b 新增、P6.2c 扩到八档、P6.2d 扩到十档**。sparkline 那两张**没有**加历史注入钩子：12 格横轴只能等真实采样长满（每 2 秒一格），给截图编一段假历史是最容易的做法也是最坏的做法——照片上那些柱子必须每一根都能回到内核计数器。**07 的 `scanUnifiedLog` 超时教训**记在 `fidelity-guardian.md` §6.6.3：`/usr/bin/log show` 在沙盒环境下会挂起，`DispatchSemaphore` 8 秒超时保护不能省 |
- 三个面（`cardSurface`/`recessedSurface`/`underPageSurface`）的实测值与判定见
  `docs/analysis/fidelity-light-dark.md` §2。
- **同一批钩子的取值顺序会互相牵制**（本轮踩到）：`MM_DISK_SELECT` 是按逗号顺序逐个
  `node(atPath:)` 往下钻的，把扫描根本身写在第一个，钩子就会一路向上选到 `/tmp`，
  既暴露了无关目录又让 `selected == nil`，于是"借选中项数字摆一拍"的吐司支路整条哑掉。
  截图用的正确顺序是 `Downloads,Movies,<root>`。另外 `MM_SHOW_TOAST=permanent` 那一支
  必须写在 `guard env["MM_SHOW_CONFIRM"] != nil` **之前**并自己 return，否则确认面板
  盖住吐司，拍到的还是面板。
- **"代表用户动手"的钩子必须只重放一次**（P6.2a 踩到）：`MM_DISK_SELECT` 过去挂在每次扫描
  落地的收尾上。单拍一屏时看不出来，一旦加上 `MM_DISK_RESCAN` 让页面自己扫第二次，
  它就会把第二次扫描**本该丢弃**的标记原地重新打上——③ 那一档拍出来永远像"标记都挂回来了"，
  丢弃那条分支在照片里消失。现在它由 `selectionHookApplied` 钉成一次性动作，
  语义也就和"用户手工标记过一次"对齐了。
- **页面下方的区块靠"缩短上方内容"顶进画面，不靠滚窗**：4K 屏上窗口高度仍被钳在约 1080pt，
  `MM_WINDOW_SIZE=1400x1900` 拿到的还是 1050pt 高的窗（照片看着像生效、其实没变）。
  要看系统清理页底部的"磁盘空间只读报告"，正确做法是给 `MM_CLEANER_FILTER` 一个只命中
  一类的词（`废纸篓`），表格缩到一行，区块自己就进画面了。
- **缩不了的时候让页面自己滚，别去滚窗口**：上一条对「开发产物」页不成立——那里底部是
  一张 144 行的列表和永远要可见的操作条，没有"缩短上方内容"这回事。于是加
  `MM_DEV_SCROLL=end`，用 `ScrollViewReader.scrollTo(末行, .bottom)` 在扫描回来后自滚一次。
  这仍然是**应用自己在正常渲染里走一步**，不是往原生 UI 里塞合成滚轮/点击事件。
- **夹具文本也要有测试**：Swift 多行字面量的收尾**不带换行**，
  `"..." + join(...)` 拼出来的夹具会把第一条快照粘在表头行上被解析器吃掉——
  照片上"另有 2 个快照"看着挺像溢出态，其实少了一条。判据在 `SnapshotFixtureTests`。
- **不要写脚本用 NSColor 查语义色的值**：脱离真实绘制上下文解析动态色，明暗两档会给出同一个（错的）值。
  这条坑记在 `pixel-probe.swift` 文件头。
