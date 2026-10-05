# 全仓钩子台账（hook-ledger）

> 配套 `docs/design-system/README.md` §2 归属矩阵。本台账逐条标注每个 `MM_*` 钩子的
> **只读性** 与 **是否可能触发破坏性流程**，供集成阶段统一落地时排查越界写操作。
> 数据来自 `grep -rn "processInfo.environment\|MM_[A-Z_]+" Packages Sources`（2026-09-30）。

## 0. 结论先行

- 全仓现存钩子 **51 个独立变量名**（`grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' | sort -u`
  于 2026-10-04 重跑得 **52** 个，其中 `MM_TRASH_FIXTURE_PROBE` 只是 `TrashWatcherTests.swift:46`
  用来探 `/tmp` 守卫的临时 key，不是运行时钩子，不计入）。
  上一版记的"49 个（grep 得 50）"是 2026-09-30 的数，**P6.2d 的 `MM_GUARDIAN_CARDS` 与本轮的
  `MM_MONITOR_CARDS` 都没回填过这条计数**——台账自己就是那条老教训（"旧文档里的数字是线索不是依据"）的对象，
  所以这里给的是重跑结果，不是 49+2。
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
  P6.4「SMC 温度/风扇」新增 `MM_MONITOR_CARDS` 1 个（卡显示过滤，手法照 `MM_GUARDIAN_CARDS`），
  并给 `MM_MONITOR_FIXTURE` 加 5 个传感器档。这两个钩子**一个字节都不写 SMC**：
  夹具档是整块顶替 `SensorsSnapshot`（连 `SMCClient` 都不碰），卡过滤是纯显示层；
  而真实读取路径本身只发 `readKeyInfo`/`readBytes`/`keyFromIndex` 三条命令，
  写命令与 `F{id}Md`、`Ftst` 在 `SMCCommand` 这个枚举里**没有对应取值**（见 `SMC.swift`）。
  **P6.5「Swap 零值文案」没有新增钩子名**（所以上面那条 52 的计数不变），只给 `MM_MONITOR_FIXTURE`
  加了 1 个档 `swapZero`，并**改了 `populated` 底座的 swap 数值**：底座原本是 0/0，
  与新的 `swapZero` 档在照片上同一个样——两档合成一档，等于夹具自己把要区分的东西抹平了。
  **P6.6 同样没有新增钩子名**（2026-10-04 重跑 grep 仍为 **52**），只给 `MM_OPTIMIZER_FIXTURE`
  加了 2 个档（`caveat:unreadable:N` / `caveat:dataless:N`）。这一轮真正的产出不在钩子层，
  而是把"钩子存在"与"钩子生效"这两件事分开查了一次：`MM_OPTIMIZER_FIXTURE` 自落地起
  **四个 tab 里有三个从未生效过**，却被文档和矩阵当作已具备的能力引用了四天。
  判据是照片自己的 md5——同一钩子的两个不同档位逐字节相同，只能是夹具被真实数据覆盖了。
  **所以台账里"✅ 只读"只回答"会不会写盘"，不回答"拍出来的算不算数"**；后者要靠
  `md5 -q *.png | sort | uniq -d`（见 §5 `p66-optimizer-capture.sh`）。
  **P6.7 也没有新增钩子名**（2026-10-04 重跑同一条 grep 仍为 **52**），但它是三轮里第一个查出
  **产品缺陷**的取证轮：`DiskMarks.refresh` 会把挂在"这次只枚举了一层"之外的标记**丢弃并在 UI 上点名"已经不在了"**
  （见 `docs/analysis/fidelity-disk.md`）。同时这一轮把 P6.6 那道"只靠 md5"的判据换成哨兵值，
  据此确认 monitor/guardian 两个夹具是真生效的（§4 #2 的提请就此收回），
  另外查出并修了两处"日志在说谎"：`menubarOff` 解析了没人消费、孤儿夹具扫描没跑也报成功（§4 #4）。
  **P6.8 与 P6.8b 都没有新增钩子名**（2026-10-04 再次重跑同一条 grep 仍为 **52**）。
  P6.8 这一轮不查钩子生不生效，查的是**证据能不能重跑**：`p7-dev`/`p7-brew`/`p1.5-trash`/`p5-disk-permanent`
  四批手工照片此前只有夹具没有脚本，本轮补 `Scripts/p68-{dev,brew,trash,disk}-capture.sh` 四个
  （照片写新目录 `docs/verification/p68-*/`，旧证据一字未动）。它顺手抓出一处**存错文件的证据**：
  `p7-brew/09-real-machine.jpg` 拍的是磁盘分析页，不是卸载页（§8.1 那一格的判定作废，见
  `fidelity-uninstaller.md` §12.3）。P6.8b 再补一刀：这些 `.log` 只记应用 stderr，
  看不出本档注入了什么——归因头两行从此由脚本自己写（见 §5 末尾）。
  **P6.8c 与 P7a 都没有新增钩子名**（2026-10-05 现跑同一条
  `grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' | sort -u | wc -l` = **52**，
  其中 `MM_TRASH_FIXTURE_PROBE` 仍是测试里探 `/tmp` 守卫的临时 key，运行时钩子 51 个）。
  **P7a 是这一族里第一条不靠钩子的取证**：清理页"四个类别开关全关"这一态由
  `defaults write com.macmaster.app` 直接改持久化设置得到，页面 `.task` 进页即扫，
  于是既没有新 `MM_*`、也没有合成点击。归因头因此多了第三行 `# defaults:`
  （见 §5 `Scripts/p7-empty-scope-capture.sh`）。**这一类手段的代价要写清**：
  它动的是用户机器上的真实域，脚本必须 `trap` 还原并且成对拍（异常档 + 还原档），
  否则下一轮所有人读到的都是一台"清理页什么都不扫"的机器。
  **P8 没有新增钩子名**（2026-10-05 现跑同一条 grep = **52**，运行时钩子仍 51 个），
  但它是第一轮**同一轮里两种注入手段并用**：概览页那一档走 `defaults`（第四种手法），
  磁盘详情那一档走 `/tmp` 深夹具 + 既有的 `MM_DISK_SCAN`/`MM_DISK_SELECT`（第一、二种）。
  新脚本 3 个（含夹具 `Scripts/disk-depth-fixture.sh`），**一个钩子都没加**——
  "要拍一个新状态"未必要新钩子，一棵形状对的树就够了（这次是一棵 20 层的窄树）。
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
| `MM_SHOW_CONFIRM` | `MMCleaner` | `MMCleaner.swift:390` `UserFolderCleanView.swift:116,384` | 弹出删除确认面板 | ✅ | 否（弹面板，删在按钮里） | 实际删除需用户点「确认」，过 `DeletionGuard`。锚点于 2026-10-04 现读重定（原记 `:359` 已漂） |
| `MM_INSTALLER_FIXTURE_DIR` | `MMCleaner` | `UserFolderCleanView.swift:120,366` | 注入安装器残留夹具目录 | ✅ | 否 | **只认 `/tmp` 之下**，越界忽略并写 stderr |
| `MM_FAILURE_FIXTURE` | `MMCleaner` | `MMCleaner.swift:365` | 渲染拒绝回执（=protected） | ✅ | 否 | 仅展示，复用 `MMUI.MMFailurePanel` |
| `MM_SNAPSHOT_FIXTURE` | `MMCleaner` | `MMCleaner.swift` `applySnapshotFixture` | 把"磁盘空间只读报告"里的**快照那一块**换成样例文本（`mixed`/`overflow`/`updateonly`/`none`/`broken`） | ✅ | 否 | 只替换解析器的输入字符串，卷容量仍是真读的；不起命令、不碰盘。未知取值整块忽略 |
| `MM_PURGE_FIXTURE_HOME` | `MMCleaner` | `DevArtifactView.swift:45` | 把「开发产物」页的扫描根换成假 home | ✅ | 否 | **P5.1 新增。只认 `/tmp`**：`realpath` 解析后**再复核一次前缀**，越界整块忽略。这一屏的终点是删除按钮，所以钩子绝不能把用户的真项目变成可以整片勾选的夹具。配合 `Scripts/purge-fixture.sh` |
| `MM_DEV_EXPAND` | `MMCleaner` | `DevArtifactView.swift:109` | 扫描回来后把所有项目分组一次性展开 | ✅ | 否 | **P5.1 新增**。非空即生效，只改内存里的 `expandedRoots` |
| `MM_DEV_SELECT` | `MMCleaner` | `DevArtifactView.swift:112` | `=untouched` 时勾选全部"判定可回收且体积已量到"的行 | ✅ | 否 | **P5.1 新增**。只写内存 `Set<String>`；受保护、嵌套已计入、体积为 nil 的行**选不中**（`isSelectable`），所以这一拍里的勾选数就是删除按钮将来真正会数的数 |
| `MM_DEV_SCROLL` | `MMCleaner` | `DevArtifactView.swift:428` | `=end` 时列表自滚到底 | ✅ | 否 | **P5.1 新增**。窗口高度被屏幕钳住，底部合计条和操作条在首屏外；用 `ScrollViewReader` 自滚**代替合成滚轮事件** |
| `MM_DEV_CONFIRM` | `MMCleaner` | `DevArtifactView.swift:407` | 弹出开发产物删除确认面板 | ✅ | 否（弹面板，删在按钮里） | **P5.1 新增**。链路同 §3 三关：确认按钮 → `DeletionGuard` → `FileTrashService`。**P6.7 复核**：锚点原记 `:236`，现读 `:407`；它写在 `.task` 里而 `model.scan()` 上一行没 await，所以面板先于 `report` 打开（等够就不空）。**P6.8 收口**：`Scripts/p68-dev-capture.sh` 第 04 档现在会重拍这一张（写进 `docs/verification/p68-dev/`，旧 `p7-dev/04` 未动），"有照片、无脚本"这条不成立了；详见 `fidelity-cleaner.md` §9–§10 |
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
| `MM_DISK_SELECT` | `MMDisk` | `MMDisk.swift:1094`（选中落在 `:1113`） | 预选路径并展开 | ✅ | 否 | 仅展示选中态。**本轮补 /tmp 守卫**：任一目标非 /tmp 前缀则整体忽略。**P6.2a 起只重放一次**（`selectionHookApplied`）：它代表"用户动手标记过一次"，每次扫描都重放会把该丢弃的标记重新加回来。**P6.7 起选中成功/失败各写一行**（成功带 `MMFormat.bytes`，失败点名「这一层不在已展开的树里」）——`openDirectory` 遇未缓存的一层会起 `Task { doNavigate }`，这一路是有窗口的，不写日志就分不出「钩子没跑」与「这一层还没到」 |
| `MM_DISK_RESCAN` | `MMDisk` | `MMDisk.swift:191` | 首扫落地后**自动再扫一次**指定根（P6.2a 新增） | ✅ | 否（只读扫描） | 值同样只认 `/tmp`/`/private/tmp` 前缀，越界写 stderr 并忽略。给同一个根=拍"标记跨重扫还在"，给另一个根=拍"挂不回去的丢弃并点名" |
| `MM_DISK_HOLD` | `MMDisk` | `MMDisk.swift`（本轮新增） | `=hold` 冻结在"正在分析磁盘结构"首帧，不触发扫描 | ✅ | 否 | 见 `fidelity-disk.md` §提请协调者 #4 |
| `MM_SHOW_CONFIRM` | `MMDisk` | `MMDisk.swift:1141` | 弹出删除确认面板（回收/进废纸篓） | ✅ | 否（删在按钮里） | 过 `DeletionGuard`；面板里闸口拒绝项已提前为 `.guarded` blocked。**P6.7 起这行开面板时写一条带 `marked.count` 的日志**，找不到的目标逐个点名（旧写法悄悄跳过，面板行数就成了自报） |
| `MM_SHOW_PERMANENT` | `MMDisk` | `MMDisk.swift:1165` | 把确认面板换成**永久删除**面板 | ✅ | 否（同一层交换 `showMarkConfirm=false` / `showPermanentConfirm=true`，不删） | 值 `acked` 时代码里把确认勾选打上，截图才能拍到"按钮点亮"那一态；勾选本身不落盘 |
| `MM_SHOW_TOAST` | `MMDisk` | `MMDisk.swift:1129,1176` | 弹出回执吐司 | ✅ | 否 | `=permanent` 走"已永久删除 · 无法恢复"那一支（橙色三角、**无撤回按钮**），数字借自当前选中项，不移动任何文件 |
| `MM_GUARDIAN_FIXTURE` | `MMGuardian` | `MMGuardian.swift:410` | 注入守护规则夹具行 | ✅ | 否 | 合成 `com.example.*`，不碰真实登录项。行号 P6.2b 起（整页骨架重排把钩子块往下推了 36 行） |
| `MM_TCC_FIXTURE` | `MMGuardian` | `MMGuardian.swift:424` | 注入 TCC 授权表行 | ✅ | 否 | 支持 `rows/unreadable/empty/partial` |
| `MM_GUARDIAN_LOGIN_FIXTURE` | `MMGuardian` | `MMGuardian.swift:438` | 注入登录项夹具（rows/empty/indeterminate/scanerror） | ✅ | 否 | **README §2 漏列，本轮补正** |
| `MM_GUARDIAN_LOAD` | `MMGuardian` | `MMGuardian.swift:450` | `=hold` 时整页冻结首帧（测量中+骨架） | ✅ | 否 | **README §2 漏列，本轮补正** |
| `MM_GUARDIAN_ACTIVITY_FIXTURE` | `MMGuardian` | `MMGuardian.swift:461` | 系统活动卡注入 `empty/rows` | ✅ | 否 | 见 `fidelity-guardian.md` §5 G1（该条已标已落实）；合成条目标"夹具值"。**P6.2d 起用 `MM_GUARDIAN_CARDS=activity` 只渲染活动卡出片**（§6.6.3） |
| `MM_GUARDIAN_CARDS` | `MMGuardian` | `MMGuardian.swift` `GuardianCardFilter`（`GuardianFixtureHooks.swift`） | 卡显示过滤，逗号子集 `occupancy\|tcc\|login\|activity` | ✅ | 否 | **P6.2d 新增**。纯显示层过滤，不改变数据流；非法值整批拒绝并写 stderr。解决活动卡排在第 4 位永远在折叠线以下的问题——07/10 两档用 `=activity` 只渲染活动卡，不再需要拉高窗口+压矮上方三卡 |
| `MM_OPEN_TAB` | `MMOptimizer` | `MMOptimizer.swift:42` | optimizer 页默认 tab（duplicates/browser/status/devtools） | ✅ | 否 | 非法值回落 `.duplicates` |
| `MM_OPTIMIZER_FIXTURE` | `MMOptimizer` | `MMOptimizer.swift` | 四 tab 空/失败/PROTECTED 态统一夹具（duplicates:N/empty/scannedEmpty、**caveat:unreadable:N / caveat:dataless:N（P6.6 新增，必须与 `duplicates:N` 同给，单独给则整条作废）**、browser:rows/empty、status:allReadOnly、devtools:notInstalled/unreadable、protected） | ✅ | 否 | 见 `fidelity-optimizer.md` §6；纯数值/状态注入，不读 /tmp、不写盘、不 spawn。**P6.6 起有 `fixturePinned`**：给了夹具的 tab 会被钉住，随后落地的真实扫描结果整批丢弃。在此之前钩子是**半生效**的——三个 tab 的夹具被并发真实扫描覆盖，拍出来的照片挂着夹具文件名却是真实数据（见 §4 #2） |
| `MM_MONITOR_HOLD` | `MMMonitor` | `MMMonitor.swift`（#50 新增） | `=hold` 时冻结在 `.empty` 首帧 | ✅ | 否 | 见 `docs/analysis/fidelity-monitor.md` §4 |
| `MM_MONITOR_FIXTURE` | `MMMonitor` | `MMMonitor.swift`（#50 新增，P6.4 扩档，P6.5 加 `swapZero`） | 注入确定快照（populated/memoryNil/swapOff/**swapZero**/perCoreRed/perCoreEmpty/disk-unavailable:reason/processes/menubarOff + **P6.4 五档：sensors/sensorsUnavailable/sensorsNoFan/sensorsFanUnknown/sensorsHot，以及带自定义原因的 `sensors-unavailable:reason`**） | ✅ | 否 | 纯数值注入，不读 `/tmp`、不采样；**传感器五档连 `SMCClient` 都不碰**（整块顶替 `SensorsSnapshot`），所以"钩子会不会写 SMC"这个问题在这条上答案是结构性的不会。逗号可叠加（如 `processes,sensors` 拍相邻两卡）；**`menubarOff` 自 P6.7 起才真的被消费**（`menuBar.disable()`，此前只解析不用）。**`swapZero` 与 `swapOff` 只差 `swapAvailable` 一位**（前者"读到 0"、后者"读不到"），这一位就是 I9 那两句话的分界；`populated` 底座的 swap 从 0/0 改成真实的 800 MiB / 2 GiB，否则这两档拍出来是同一张 |
| `MM_MONITOR_CARDS` | `MMMonitor` | `MMMonitor.swift` `MonitorCardFilter`（`MonitorFixtureHooks.swift`） | 卡显示过滤，逗号子集 `stats\|perCore\|disk\|memory\|process\|sensors` | ✅ | 否 | **P6.4 新增**。手法照 `MM_GUARDIAN_CARDS`：「温度与风扇」排在整页最后，760pt 窗口里永远在折叠线以下，靠钩子钉死位置而不是拉高窗口碰运气。非法值整批拒绝并写 stderr（半生效夹具 = 假通过）；纯显示层过滤，不改变数据流 |

## 2. 各模块钩子小结

- **壳（Sources/MacMaster）**：5 个，纯导航/打开/取证档（`MM_APPEARANCE` `MM_WINDOW_SIZE`），零副作用。
- **MMCleaner**：16 个（P5.1 新增 5 个：`MM_PURGE_FIXTURE_HOME` + `MM_DEV_EXPAND/SELECT/SCROLL/CONFIRM`；P6.1 再新增 3 个预算/自动续扫钩子；含 P4.6 的 `MM_SNAPSHOT_FIXTURE`，早前列数漏计它）。含 2 个 `/tmp` 路径夹具（`MM_INSTALLER_FIXTURE_DIR`、`MM_PURGE_FIXTURE_HOME`，越界即忽略）。
- **MMUninstaller**：5 个，含 3 个 `/tmp` 路径夹具，全部越界即忽略。
  **P6.7 起两条自报改为可核对**：① `MM_ORPHAN_FIXTURE_HOME` 那趟自动扫描先把 `scanOrphans` 的静默前置
  条件（`isScanningApps || apps.isEmpty`）判一遍，不满足就点名"孤儿夹具扫描**没有执行**"并**不**开面板，
  满足则把条数写进日志（`（N 条）`，0 条照写）；② `TrashWatcher.watchTarget()` 拒绝了一个
  `MM_TRASH_FIXTURE_DIR` 却仍要监听真实 `~/.Trash` 时，会把"改为监听真实废纸篓"连同后果一起说出来。
- **MMDisk**：9 个（新增 `MM_DISK_HOLD`；P6.2a 再新增 `MM_DISK_RESCAN`），`MM_DISK_SCAN`/`MM_DISK_SELECT`/`MM_DISK_RESCAN` 都带 `/tmp` 守卫。
  **P6.7 起 `MM_DISK_SELECT` 这一族每次生效都留痕**：选中（带 `MMFormat.bytes` 的那个数）、
  没选中（点名"这一层不在已展开的树里"）、确认面板（带 `marked.count`）、
  `MM_SHOW_PERMANENT`（带勾选态）、两条吐司（各带借来的数字与"没有删/没有移动任何东西"）。
  写这几行的动机是 §4 #4 那条：**成功路径此前一声不出**，日志里"完全生效"和"压根没跑"同样安静。
- **MMGuardian**：6 个（新增 `MM_GUARDIAN_ACTIVITY_FIXTURE`、`MM_GUARDIAN_CARDS`），全 `com.example.*` 合成，不写盘。`MM_GUARDIAN_CARDS` 是纯显示层过滤。
- **MMOptimizer**：2 个（`MM_OPEN_TAB` + `MM_OPTIMIZER_FIXTURE`，后者 P6.6 起十档）。`DevToolCacheAudit.swift:166` 读的 `env` 是 **PATH 探测**（找可执行文件），**不是 `MM_` 夹具钩子**，与截图无关，不计入台账。
  **P6.6 起这个模块多一条约定**：给了夹具的 tab 由 `fixturePinned` 钉住，随后落地的真实扫描整批丢弃。
  这是缺陷补出来的约定，不是设计选择——其余模块的夹具**有没有同样的竞态本轮没查**，见 §4 #2 提请。
- **MMMonitor**：`MM_OPEN_MODULE` + #50 新增 2 个（`MM_MONITOR_HOLD` / `MM_MONITOR_FIXTURE`）
  + **P6.4 新增 1 个（`MM_MONITOR_CARDS`）**，共 3 个本模块钩子，全只读。
  本模块是 P6.4 起**唯一会读内核结构（IOKit AppleSMC 用户客户端）**的一个，
  但那条路径与截图无关、且只发三条读命令——钩子层没有任何一条能写 SMC。
  **P6.7 补上 `menubarOff` 的消费端**：这个档位自 #50 起一直被解析却没人读，
  所以它现在真的调 `menuBar.disable()`（`MacMasterApp` 启动即 `enable()`，"不 enable"这条路走不通），
  由 `docs/verification/p67-menubar-off/01↔02` 两张只差开关的照片证明生效。见 §4 #4。

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
2. **`MM_OPTIMIZER` 缺少面向无头核对的统一夹具入口**：~~目前只有 `MM_OPEN_TAB`~~ ~~钩子在但一张照片都没拍过~~ **已闭环（P6.6，2026-10-04）**：`Scripts/p66-optimizer-capture.sh` 十二档跑完，产物在 `docs/verification/p66-optimizer/`。
   这条的**真正收获不是补了照片，而是跑照片这件事本身查出一个 bug**：夹具自 `969e548` 落地以来
   **四个 tab 里有三个从未生效**（本轮 `git log -S MM_OPTIMIZER_FIXTURE` 现查，哈希与祖先关系核对无误——
   它是首次提交 `fidelity-optimizer.md` 那次 `e96c95b` 的祖先）。判据是照片自己给的：
   `browser:rows` 与 `browser:empty` 逐字节相同（md5 `aa6c478a…`）、`devtools:notInstalled` 与
   `devtools:unreadable` 相同（`13a3ac85…`）、`status:allReadOnly` 拍到的是这台机器的真实读数。
   **成因**：`applyFixtureIfNeeded()` 先 `await` 真实扫描再上夹具，重复文件那档的全文件 SHA-256 把后面所有档
   挡住了；而另三个 tab 的视图级 `.task`（`MMOptimizer.swift:239`/`:261`、`DevToolCacheView.swift:84`，2026-10-04 现读）
   本来就在并行起真实扫描。
   **修法两步，缺一不可**：① 四档夹具**先同步全部落完**，只对"没给夹具"的那档起真实扫描；
   ② 四个模型各加 `private var fixturePinned`，扫描入口与 `await` 之后**都查一次**，
   在途的真实结果整批丢弃。只做①不够——`.task` 仍会与夹具抢，最后落地的真实数据把夹具覆盖掉，
   照片挂着夹具文件名却是真实数据，正是"半生效夹具 = 假通过"那道铁律的另一种犯法。
   回归锁 `OptimizerFixtureHookTests`（11 条，补上"optimizer 是唯一没有 parse 单测的夹具"这个约定缺口）
   + `OptimizerFixturePinTests`（3 条，直接测"夹具先落、真实扫描后到"这个顺序）；
   模块 54 tests / 0 failures；重跑后 12 张图 `uniq -d` → **0 个重复**。
   **⚠️ 提请协调者**：monitor / guardian 两个夹具钩子有没有同一类 `.task` 竞态？本轮只核了优化器，没查那两个包。
   形状上最像的是**视图级 `.task` 一次性注入**那一类（guardian 的几张卡、disk 的扫描收尾），优先查它们；
   monitor 的快照由采样循环反复喂，性质不同，但"夹具与真实采样共用同一个赋值口"该不该也算竞态，需要个说法。
   另外这一条本身就是**台账自己过期**的样本：文档里"只有 `MM_OPEN_TAB` 一个钩子"在写下那天就已经是假的；
   钩子文件头部注释还引用"§5 #1–7"，也就是审计者自己的建议，建议被实现完了、建议没被划掉。
3. **`MM_DISK_SCAN` 越界值处理**：~~当前 `MMDisk.swift:135` 未校验 /tmp~~ **已落地**：集成阶段对 `MM_DISK_SCAN`/`MM_DISK_SELECT` 补 `/tmp`/`/private/tmp` 前缀守卫，越界写 stderr 并忽略。
4. **§4 #2 那道提请已有答案，答案是"竞态没有扩散，但另一类缺陷扩散了"（P6.7，2026-10-04）**。
   换了一种判据再查一遍全仓：**不比照片 md5，而是找一个真实路径生产不出来的值去日志和照片里查它**。
   md5 只能证明"两张不一样"，证明不了"这一张是夹具"——`browser:rows` 与 `devtools:notInstalled` 从一开始就互相不同，
   它们照样都是真实数据。哨兵值反过来：监控页 `MM_MONITOR_FIXTURE=populated` 落地时
   「上次采样 2023-11-15 06:13」与温度键名 `TZZa…TZZh`（真机是 2026-10-04 与 `TCMz/Tp0c/…` 174 个点）
   都出现在画面上；守护页夹具的 `com.example.*` 与「（夹具值）」同理。**这两个钩子是真生效的**，
   `fixturePinned` 那类竞态在 monitor/guardian 上没有可复现的证据，性质与 §4 #2 猜测的不同：
   monitor 的夹具分支**刻意不调 `menuBar.enable()`**（`MMMonitor.swift:89` 那行注释就是理由——
   别让后台采样循环把夹具快照覆盖掉），所以"夹具与真实采样共用同一个赋值口"这件事根本不成立：
   注了夹具就没有采样循环。守护页的几张卡由 `MM_GUARDIAN_CARDS` 只渲染目标卡，
   喂数据的 `.task` 与夹具赋值之间没有观察到互相覆盖（`p62b` 那十档逐档不同即是证据）。
   **扩散的是另外三件事，都已修**：
   - **解析了却没人消费**（`MM_MONITOR_FIXTURE=menubarOff`）：#50 起这个 case 一直在解析，
     没有一处读 `fixture.menubarOff`，于是 `fidelity-monitor.md` §5 那行"关闭态已覆盖"是空的。
     现在它真把状态项摘掉，两档对照见 `docs/verification/p67-menubar-off/01↔02`
     （md5 `89d0fec5…` vs `2c125c01…`，除开关外全部数字逐位相同）。
   - **自报成功却不判前置条件**（卸载页孤儿夹具）：旧写法在 `scanOrphans` **静默 return**
     （`UninstallerModel.swift:490`）之后照样打一行"已自动勾选并打开确认面板"，取证脚本自己造了一条假凭据。
     现在先判同一个前置条件，不过就点名"没有执行"；过了则写条数（实机新跑一轮读到「（1 条）」「（0 条）」两种，
     0 条与没扫描从此在日志里是两件事）。
   - **成功路径一声不出**（磁盘页 `MM_DISK_SELECT`/`MM_SHOW_*` 全族 + `p4-sweep.sh` 那行"钩子凭据"）：
     台账里那条凭据历来只 `grep` 四类钩子名，monitor/guardian/optimizer/dev/watch 十几个钩子即便真生效，
     这行也是空的，读起来跟"没生效"一模一样。改成收所有 `MM_` 开头的行 + 夹具哨兵词，
     并给磁盘页每个生效分支各留一行可核对的数（2026-10-04 手工起实例各跑一轮：
     选中 16.8 MB / 面板 2 个标记 / 勾选已打 / 吐司 16.8 MB，四行全部落地）。
   **顺带查出的一个用户可达缺陷（不是取证缺陷）**：`DiskMarks.refresh` 号称"scope 之外不动"，
   实际只对**单层**成立的标记生效——下钻走 `DiskScanner.childrenOfDirectory`（只取一层），
   拿到的孩子不带孙子，于是挂在更深处的标记会被找不着、**丢弃并在面包屑上点名"已经不在了"**。
   可达路径很日常：在 `Documents` 里标记一个文件 → 回到上一层 → 按「重新扫描」。
   单测 `testRefreshKeepsMarksDeeperThanTheEnumeratedLevel` 先红（`dropped=["/u/dev/a/b/c"]`）后绿，
   `refresh` 从此只在"直接孩子那一层"判生死；`isUnder` 随之没有生产调用点，已删，
   换成同样按组件比的 `isDirectChild`。详见 `docs/analysis/fidelity-disk.md`。

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
| `Scripts/smc-probe.swift` | 只读探一次本机 AppleSMC：键表规模、`T*` 类型分布、风扇四键实测值、稳态扫描耗时 | **P6.4 新增**。立项前把"本机有没有风扇"这种凭机型猜的判据换成量出来的数；它同时是 `SMCParamBlock` 结构体布局的回归工具（布局漂了，`IOConnectCallStructMethod` 只会回 `kIOReturnBadArgument`，没有这个脚本就得重新猜）。**只读**：不碰 `F{id}Md`、不发 `Ftst` |
| `Scripts/p64-capture.sh` | 「温度与风扇」八档 × 明暗两套：①实机真读数（不注夹具）②loaded ③unavailable ④0 台风扇 ⑤风扇数未知 ⑥≥90 °C 红档 ⑦与进程卡相邻 ⑧非法值整批拒绝 | **P6.4 新增**。01 那张是"进程内也能读 SMC"的唯一证据；08 的判据在 stderr（`grep 含非法取值`），照片只是佐证。全部零合成点击，只 kill 自己起的 pid |
| `Scripts/p65-swap-capture.sh` | 内存卡 Swap 一行四档 × 明暗两套：①实机非零对仗（不注夹具）②`swapZero`「0 字节（未使用）」③`swapOff`「—」④`populated` 底座 | **P6.5 新增**。渲染范围钉成 `MM_MONITOR_CARDS=memory`（单卡）。01 那张是"改文案没把非零路径改坏"的回归证据；02/03 证明"读到 0"和"读不到"仍是两句话（I9 的改动边界就在这位上）。**菜单栏里那句 `Swap: …` 没有照片**：它要点开 NSMenu，而合成点击是硬禁止项、`screencapture -l<windowid>` 又抓不到菜单窗口，所以那一档只有单测 |
| `Scripts/i11-hysteresis-capture.sh` | 真实负载下逐帧抓监控页温度卡：起 8 个 `yes` 循环压 ~40 秒再撤掉，每 3 秒按 pid 抓一帧 | **I11 新增**。迟滞（进 90 / 出 85）是**随时间**的行为，而 `MM_MONITOR_FIXTURE` 每个进程只给一个定格快照——拍不到"红过之后落回 87 °C 还红着"。这台机器跨不过 90（26 帧最高 **89.0 °C**、零红），所以过渡态最终只有单测；脚本与负载段那一帧留在 `docs/verification/i11-hysteresis/`，免得下轮又去试一遍。**跑这类热实验时别同时干别的重活**：本轮同时在渲染设计稿，冷却曲线被画成 66→81.5→86.2，撤负载之后的帧全部作废 |
| `Scripts/p66-optimizer-capture.sh` | `MM_OPTIMIZER_FIXTURE` 十二档 × 明暗两套：重复文件（扫描中/有组/带告警/PROTECTED/从未扫描/扫完为空）+ 浏览器（rows/empty）+ 系统状态（allReadOnly）+ 开发工具（未装/读不进）+ 非法值整批拒绝 | **P6.6 新增**。它是"钩子写了不等于钩子生效"的唯一反证工具：第一次跑出来 `browser:rows` 与 `browser:empty` **逐字节相同**，据此查出一个从未生效的夹具（见 §4 #2）。所以脚本末尾**必须**跑 `md5 -q *.png \| sort \| uniq -d`，重复就是夹具没生效，不是"这两档长得一样"。第 01 档（扫描中）**没有 HOLD 钩子**：真实 SHA-256 本来就慢，起进程 3 秒后截图就停在骨架 |
| `Scripts/p66-layout-measure.sh` | 四档定态截图，专供量磁盘页面包屑条高 / treemap header 高 / cleaner 分组右注长度 | **P6.6 新增**。它拍的是**待测量的载体**而不是结论，所以每档都自带 `MM_DISK_SCAN`/`MM_DISK_SELECT`/`MM_CLEANER_FILTER` 的取值说明。两个坑记在脚本头里：① `MM_DISK_SELECT` 只认绝对 /tmp 路径，写相对段名会被越界 guard 整条忽略（拍出一张根图却以为是下钻图）；② 04 档用 `MM_CLEANER_FILTER=浏览器` 把表**收短**，让最长的分组右注自己升进首屏——禁合成点击，也禁滚动 |
| `Scripts/p67-menubar-off-capture.sh` | 监控页「菜单栏监控」开关两档：`populated` 与 `populated,menubarOff`，其余环境变量逐字相同 | **P6.7 新增**。它存在的唯一理由是**把"开关"做成画面里唯一的变量**：底座同为 `populated`，两张照片除那枚 switch 外每一个数字都该逐位相同；一旦两张一模一样，`menubarOff` 就又变回"解析了没人消费"，一旦数字也漂了，说明夹具没钉住。零合成点击（点击会逃逸到用户其它应用），只 kill 自己起的 pid |
| `Scripts/p68-dev-capture.sh` | 「开发产物」七档：默认态 / 展开+批量勾选 / 滚到底四态徽标 / 确认面板 / 深色 / **真机** / 最小窗口 | **P6.8 新增**。把 `docs/verification/p7-dev/` 那批手工照片变成可重跑（旧目录一字未动，新照片写 `p68-dev/`）。判据是**画面上必须有真实机器生产不出的值**（`~/Documents/bulk-1…bulk-12`、「夹具值」），不是 md5 互不相同。06 是真机档：不带 `MM_PURGE_FIXTURE_HOME`、等 30 秒真实扫描 |
| `Scripts/p68-brew-capture.sh` | 「安装来源」九档：五档来源各一张 + 确认面板 + 深色 + 最小窗口 + 真机 | **P6.8 新增**。同上，旧目录 `p7-brew/` 未动。默认每次现造一棵 `provenance-fixture.sh`（`FIX=` 可复用）：staged 链接的设备号判据依赖"链接指向的就是这棵树里的这份 bundle"，拿旧目录重跑没坏，但照片里的路径会指着一次没发生过的运行。09 真机档可 `REAL_SELECT=` 点名（本机已无 Highball，本轮用的是 `WailBrew`，见 `fidelity-uninstaller.md` §12.3） |
| `Scripts/p68-trash-capture.sh` | 废纸篓监听两档：提示卡（夹具 + 脚本自己 `mv`）/ 无权限横幅（真机、无钩子） | **P6.8 新增**。01 的时序是全部取证脚本里最脆的一档：**基线必须晚于 `mv`**，否则拖进去的应用被当成"启动前就在"的历史条目、卡片根本不出现——所以脚本先轮询到窗口 id、再留 2 秒给 `startTrashWatching`，才动手 `mv`；`AFTER_MOVE` 默认 60 秒，因为残留扫描的合并计时器排在 MainActor 上、要等 41 个应用测完。跑前会验 `/tmp/mmstage/Foo.app` 还在，不满足就点名让人重跑夹具而不是拍出一张假态 |
| `Scripts/p68-disk-capture.sh` | 磁盘页删除面板四档：回收/裁决面板 → 永久删除面板（未勾选）→ 同一块（已勾选）→「已永久删除」回执条 | **P6.8c 新增**。它是这一族钩子的**顺序依赖**最容易踩空的一屏：`MM_DISK_SELECT` 把扫描根写在第一个会把 `selected` 走成 nil，`MM_SHOW_TOAST=permanent` 必须不带 `MM_SHOW_CONFIRM`（它自己 return），而绿色撤回那条回执**必须**带 `MM_SHOW_CONFIRM` 才够得着、可面板是 `.sheet` 又会盖住它——所以四档里唯独没有它（判据见 `fidelity-disk.md` §11.4）。04 档另有 `TOAST_SETTLE=5`：**吐司自己带 10 秒倒计时**，按通用 10 秒去拍正好卡在 `1s` 上 |
| `Scripts/p7-empty-scope-capture.sh` | 清理页空扫描范围两档：①四个类别开关全关 ②删回默认值作对照 | **P7a 新增**。这一档**没有对应钩子**，状态来自 `defaults write com.macmaster.app`（那四个开关本来就是持久化设置，页面 `.task` 进页即扫，所以"改设置 → 起进程"就够了，不需要合成点击）。代价是这把钥匙动的是**真实域**，所以脚本 `trap restore EXIT` 保证退出必删键，并把动过哪几个键写进归因头的第三行 `# defaults:`。**这是第四种注入手法**，与前三种（env 钩子 / 夹具目录 / 真实负载）不同：它改的是用户机器上长期留下的状态，跑挂了就一直关着——所以只有"页面自己会读设置"的这一类态能用它，且必须成对拍（异常档 + 还原档） |
| `Scripts/run-all-tests.sh` | 九包全量 `swift test`，逐包一行结论 + 总计 | **P7 新增**。它修的是**读数本身的形态错**：`swift test \| tail -4` 只剩 swift-testing 那行 `Test run with 0 tests`，于是 MMCore 的 43 个测试在屏幕上显示成"跑了 0 个"；而按 `with N failures` 字面顺序解析会把有跳过项的 MMDisk 解析成 **0 个测试**（那一行实为 `with 1 test skipped and 0 failures`）。两个坑都写进脚本注释了。**只认「Test Suite 'All tests' passed/failed」后面那一行**才是包级总数，中间同名格式的行是各测试类的分项 |
| `Scripts/p7-release-check.sh` | 发布候选产物的基础三照 + **签名/plist/Gatekeeper 结论**：①概览（不注钩子，真数据）②关于页（`MM_SHOW_SETTINGS=1 MM_SETTINGS_TAB=about`，判据是打包时指定的版本号必须出现在画面上）③`MM_WINDOW_SIZE=1000x600` 下限窗口概览 | **P7b 新增**。它归因头多了三行非照片证据：`# codesign:`（`flags=0x2(adhoc) Signature=adhoc TeamIdentifier=not set`）、`# plist:`（`CFBundleShortVersionString`/`CFBundleVersion` 逐键）、`# spctl:`（`rejected`）。两个用途：① **版本号链自证**——`make-app.sh` 写的 plist 与「关于」页画出来的字符串必须在同一张图里对得上，这比读代码强；② **签名状态是有照片的结论**，发版判定（`docs/analysis/release-readiness.md` §2）不用凭记忆。**P10 给 `# plist:` 又加一键** `CFBundleIconFile=${icon:-（无）}`：图标缺档不会有任何地方报错（Dock 只是变成通用白纸），所以只能把它塞进每次构建都必写的归因头里，让"这次到底带没带图标"成为一个有日志可查的事实而不是事后回忆。注意第三档：`1000x600` 就是窗口下限（`MacMasterApp.swift` 的 `minWidth/minHeight`），**再小的请求会被夹回去**，所以它测的是"下限窗口里会不会截字"，不是"能不能更小"——本轮正是这一档抓出内存卡「交换 …」那行的截断 |
| `Scripts/p8-dashboard-scope-capture.sh` | 概览页「可清理跟勾选走」三档：①只勾日志 ②四个全关 ③删回默认值对照 | **P8 新增**，手段同 P7a（`defaults write` + `trap restore EXIT` + 归因头第三行 `# defaults:` 逐个键点名）。判据不是"数字变小"这种要看运气的说法，而是**结构性**的：01 那一档卡里只剩日志三类，「可立即释放 41.8 MB」正好等于两个可删类之和（应用日志 34.3 + 崩溃与诊断 7.5），只读的「系统日志 101.7 MB」不计入；03 同一格是 5.38 GB。02 是**未勾选类别**，不是「未扫描」也不是「测量失败」。两处实测代价：概览扫的是真实缓存，`SETTLE` 得给到 16 秒；窗口尺寸必须脚本自己写死（`SIZE=1400x1000`）——App 会恢复上次退出的 frame，第一次实跑恢复到 1000x652pt，要拍的那一卡直接落到折叠线以下 |
| `Scripts/p8-disk-depth-capture.sh` + `Scripts/disk-depth-fixture.sh` | 磁盘详情第四格三档：①封顶节点=**未枚举** ②正常目录=真实计数 ③文件=— | **P8 新增**。普通夹具（`disk-fixture.sh` 最深两三层）永远走不到 `depth >= maxDepth` 那一支，所以另造一棵 20 层窄树：扫 `根/L01…L20` 时 depth=20，L20 里的目录 L21 被做成 `children: []` + `deepSize` + `descendantsMeasured: false`。钩子凭据是日志那行 `MM_DISK_SELECT 已选中 …（2.2 MB）`，与画面上「占用 2.2 MB」对得上，才证明这一档拍的是"字节量到了、名字没枚举"这一对（旧代码在这里写的是 `0`）。两个坑记在这：① zsh 里累加路径的变量**不能叫 `path`**（它与 `PATH` 绑定，一赋值 `seq`/`mkdir` 就 command not found）；② 01 档会顺带触发一次单层重枚举（`openDirectory` 遇到未缓存的一层起 `doNavigate`），所以 treemap 里 L21 底下看得见内容，而右侧详情读的是原扫描树里那个封顶节点——这正是"未枚举"该有的样子：这一层没枚举过，不等于它底下是空的 |
| `Scripts/make-icon.sh` + `Scripts/make-icon.swift` | 生成 `Resources/AppIcon.icns`（十档），再**反向解一次核对**；`--check` 只核对不重生成 | **P10 新增**，这一条不是取证脚本而是**产物生成器**——图标没有钩子可注入，但它同样要"每个数字能自证"。形状取自设计系统的 `sparkles`（`docs/design-system/icons.js`），内外半径比 0.362 是从那条 path 直接量的，所以稿与产物可以逐数比对。判据刻意不用 `sips -g pixelWidth`：那只会报容器里被挑中的一档，**看不出十档是不是都在**，而少一档的后果（Dock 16pt 拿大图硬缩）在 plist、codesign、界面上都没有任何征兆。所以走 `iconutil -c iconset` 解回来数档数、比 1024 档字节数（现测 270,169 与源 PNG 一致） |
- **每份 `.log` 开头两行归因头**（P6.8b）：三个 p68 脚本的日志先写
  `# <脚本> <档> <时间> app=… fixture=…` 与 `# env: <本档全部注入变量>`，再接应用 stderr。
  原因是**钩子的成功路径大多不说话**（`MM_UNINSTALL_SELECT` 只在落空时写一行、
  `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 只在被拒绝时写一行），于是"这条绿"既可能是夹具生效
  也可能是压根没注入，真机档更是事后完全对不出点名了谁。**"没注入"也要写出来**——
  trash 02 那档的头里明写「真机档：刻意不注入任何夹具钩子」，否则它与"忘了"长得一样。
  改的是脚本，没有为此新增钩子。
- **查夹具生效，哨兵值优先于 md5**（P6.7）：`md5 -q *.png | sort | uniq -d` 是**必要不充分**的——
  它只能证明两张不同，不能证明手上这张是夹具。`p66-optimizer` 那对重复恰恰是运气：
  `browser:rows` 与 `devtools:notInstalled` 从第一次跑起就互相不同，而它们全是真实数据。
  充分条件是去找一个**真实路径生产不出来的值**：监控页的「上次采样 2023-11-15 06:13」与温度键名
  `TZZa…TZZh`（真机同日读到 2026-10-04 与 `TCMz/Tp0c/…` 共 174 个点）、守护页的 `com.example.*` 与「（夹具值）」。
  它在日志里、也在照片里出现，才算"这一档是夹具"。反过来，**生效分支也要留痕**：
  只写失败日志的钩子，成功时在日志里和"压根没跑"同样安静（磁盘页那一族四条成功路径就是为此补的）。
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
- **拍不到的时序状态就写清边界，别为出一张照片去造"随时间变化的夹具"**（I11）：迟滞、动画、
  跨帧判定这类行为，`MM_*_FIXTURE` 一次只给一个定格快照，天生拍不到过渡。两条路里选前者——
  ① 单测钉住判定 + 文档写明"这一档没有照片"（`fidelity-monitor.md` §4.2 末尾）；
  ② 加一条时变夹具，代价是往生产代码里塞一条只有测试走的路。本轮走 ①，并顺手把
  "本机压满 CPU 也只到 89.0 °C"这条实测边界留在 `Scripts/i11-hysteresis-capture.sh` 旁边。
- **不要写脚本用 NSColor 查语义色的值**：脱离真实绘制上下文解析动态色，明暗两档会给出同一个（错的）值。
  这条坑记在 `pixel-probe.swift` 文件头。
- **独立探针能读，不等于 `.app` 里能读**（P6.4）：`smc-probe.swift` 用 `swift` 解释器跑通了 AppleSMC，
  换成打包后的 `MacMaster.app` 就是另一件事——签名、entitlements、沙盒都可能把 `IOServiceOpen` 挡回来。
  所以取证脚本的第一档（01）**不注入任何夹具**，拍的就是"应用本体自己读出来的数"；
  这一档如果失败，照片本身就是证据（原因行是 IOKit 原文），而不是改去注夹具把画面凑对。
- **"不许写"要落到类型上，不要落到注释上**（P6.4）：`SMCCommand` 只有 `readBytes=5` /
  `keyFromIndex=8` / `readKeyInfo=9` 三个取值，写命令与解锁风扇的 `F{id}Md`/`Ftst`
  在这个枚举里**没有对应的 case**。光在文件头写"本实现只读"，下一个人加一条命令就破功了。
- **钩子台账要有第三个状态：能力就绪、尚未取证**（P6.5b）：这份台账历来只记"有没有这个钩子"，
  于是 `MM_OPTIMIZER_FIXTURE` 一记"已落地"就翻篇了，实际上**它一次都没被脚本用过**
  （`grep -r MM_OPTIMIZER_FIXTURE Scripts/` 0 命中，`docs/verification/` 24 个目录里没有优化器那一档）。
  一条没跑过的钩子和没有钩子，对下一轮取证来说**是同一件事**，但对"要不要再写一个钩子"来说是完全不同的两件事——
  所以判"这一档拍不到"之前，先 `grep Scripts/` 确认是缺钩子还是缺人跑。
  反过来也成立：**已拍过的档要在表里带上照片目录名**（`p64` / `p65` / `p62b-fidelity` 那种），
  否则下轮只能重跑一遍才知道拍过。
