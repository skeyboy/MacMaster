# 全仓钩子台账（hook-ledger）

> 配套 `docs/design-system/README.md` §2 归属矩阵。本台账逐条标注每个 `MM_*` 钩子的
> **只读性** 与 **是否可能触发破坏性流程**，供集成阶段统一落地时排查越界写操作。
> 数据来自 `grep -rn "processInfo.environment\|MM_[A-Z_]+" Packages Sources`（2026-09-30）。

## 0. 结论先行

- 全仓现存钩子 **52 个独立变量名**（`grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' | sort -u`
  于 2026-10-09（P29）重跑得 **53** 个，其中 `MM_TRASH_FIXTURE_PROBE` 只是 `TrashWatcherTests.swift:46`
  用来探 `/tmp` 守卫的临时 key，不是运行时钩子，不计入）。**P31a 用同一条命令重跑仍是 53**
  （那一轮没新增任何 `MM_*`：卸载页「正在运行」复用 P5.2 的 `MM_UNINSTALL_SELECT` 与
  P5.1 的 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME`，见下表最后一行）。**P35b 现跑同一条命令 = 55**，
  比 P31a 那一次多两个：`MM_UNINSTALL_SENSITIVITY`（**P32b 新增，当时漏回填这条计数**，所以下表
  那一行自己写着"§0 停在 53"）和本轮的 `MM_VOLUME_FIXTURE`。这一次不是"看着多了两个"，是逐字对的：
  同一条命令分别跑在三个点上——P32b 之前那一格 `fdf0f95` = 53、HEAD `27db42a`（P34b 门禁之后）= 54、
  工作区 = 55，相邻两级的差集各只有一个名字且就是上面那两个。运行时钩子 54 个
  （`MM_TRASH_FIXTURE_PROBE` 仍只是测试里的临时 key）。**这一条计数从 2026-10-04 的 52 走到 53，
  涨的那一个是 P29 的 `MM_DUMP_MENUS`**（见下表壳层那一行）——P21 到 P28 那八轮一个都没加，
  它是 §7.19/§7.20 两轮全在 CI 与测试门禁链上、P29 第一次回到界面本身的结果。
  **P37 现跑同一条命令仍是 55，一个名字都没差**：电池卡没有新增键——四档挂在既有的 `MM_MONITOR_FIXTURE` 上、
  卡名挂在 `MM_MONITOR_CARDS` 上、窄窗与换屏挂在 `MM_WINDOW_SIZE`/`MM_OPEN_MODULE` 上。
  这一轮的证法换了形状：不只比总数，而是把 HEAD 那一读与工作树这一读各自 `sort -u` 成 55 行再 `comm -3`，
  **两个方向都空**才叫"没加键"——总数相等只证明没有净增，集合相等才证明没有偷偷换过一个。
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
  **P18 没有新增钩子名**（2026-10-06 现跑同一条
  `grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' | sort -u | wc -l` = **52**，
  运行时钩子仍 51 个），但它改的是**每一个钩子失效时的表现**：16 个原本"写错值就静默停在另一档"的键
  现在一律回落默认档 **+ 写一行 stderr**（文案点名原文、可接受值、实际落在哪），
  判定逻辑下沉到 `MMCore.MMHookValue` / `MMLaunchHook` 并补了 **22 条单测**（MMCore 48→70），
  壳层那个"executable target 零测试"的洞因此第一次有了可测的判定层。
  其中一条是**安全洞**而不是取证洞：`MM_PURGE_FIXTURE_HOME` 的三条越界分支改前全部静默
  `return nil`，而 nil 回落的是 `NSHomeDirectory()`——写错一个字母就把"拍夹具"变成
  "拍用户真实项目、每行还能整片勾选去删"。现在三条各留一行并点名"扫描根将是真实 home"。
  全量分类（A/B/C/D）、逐键的"改前失效方式 / 改后回落 / 实机档号"与**故意没动**的 C 类清单
  在 `docs/analysis/hook-typo-audit.md`；门禁是 `Scripts/p18-hook-typo-proof.sh`（23 档，全绿）。
- **除 `MM_UNINSTALL_SELF_ECHO` 一条外全部只读**：那个钩子会让应用真的把**夹具里**的那个 app 移进废纸篓
  （这是 §5 那两种回声文案唯一的产生路径），所以它被两道锁钉住：夹具 home 必须是 `/tmp` 下的假 home、
  目标必须用 `MM_UNINSTALL_SELECT` 点名点到；跑完取证脚本会按 bundle 标识清掉那一条。
  其余钩子只负责"把页面定格在某个状态便于截图"，不碰真实文件。
- **破坏性流程的唯一入口是用户在 UI 里点「确认」按钮**，由 `MMCore.DeletionGuard` + `FileTrashService` 双重闸门拦截。
- 需要特别留意的"看似会动"的钩子：
  - `MM_AUTO_SCAN` / `MM_DISK_SCAN`：触发**只读扫描**（枚举文件系统、不写），不会删除。`MM_PURGE_FIXTURE_HOME` 同理——它只换扫描根，扫的仍是 `/tmp` 下的假项目；**但"钩子被忽略"不等于"扫的是假项目"**：忽略之后回落的是真实 home，所以 P18 起这一条必然留一行（这是本轮唯一的洞被补上的地方）。
  - `MM_SHOW_CONFIRM` / `MM_SHOW_TRASH_CONFIRM` / `MM_DEV_CONFIRM` / `MM_SHOW_TOAST` / `MM_SHOW_PERMANENT`：只**弹出**确认面板/吐司，**真正的删除发生在用户点面板里的「确认」**，不在钩子里。`MM_SHOW_TOAST=permanent` 摆的是"已永久删除"回执，它**没有撤回按钮**、也不会删任何东西（数字借自选中标项）；`MM_SHOW_PERMANENT` 只是把确认面板换成永久删除那块，一个字节都不动。
- `README §2` 矩阵**已过期**：漏了 `MM_GUARDIAN_LOGIN_FIXTURE`、`MM_GUARDIAN_LOAD`（代码已落地，矩阵未同步）。
  → 已在本轮补正（见文末「提请协调者」）。

## 1. 钩子台账

| 钩子 | 归属模块 | 文件:行 | 用途 | 只读? | 破坏性流程? | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| `MM_OPEN_MODULE` | 壳 `Sources/MacMaster` | `MainWindow.swift:52` | 启动后直接跳到指定模块页 | ✅ | 否 | 非法值写 stderr 并停在概览；只认 `MMDestination.rawValue`。**P18：解析下沉到 `MMCore.MMHookValue.selected`**（壳层是 executable target，本来零测试；现在这段判定由 MMCore 的 22 个新单测钉住）。**P29 现读重指：原记 `:51`**，本轮 `MainWindow.swift` 净 +1（`.onAppear` 里多挂一行 `LaunchMenuDump.dumpOnceIfEnabled()`，`MainWindow.swift:38`，它在钩子读取点上面），这一行跟着往下漂了一格 |
| `MM_SHOW_SETTINGS` | 壳 | `MainWindow.swift:47` | 启动即打开设置 sheet | ✅ | 否 | C 类（非空即生效，`!= nil`），P18 未改，见 §5。**P29 两处**：锚点原记 `:46`（`.onAppear` 多挂一行把它推了一格）；它现在走 `appState.requestSettings()` 而不是自己置 `showSettings`，**与 ⌘, 、菜单栏「设置...」三条入口汇到同一个函数**（`MacMasterApp.swift:93`）——三条路各写一遍"怎么把 sheet 打开"的话，改其中一条就会漏掉另两条，而这正是本轮要修的那个形状 |
| `MM_APPEARANCE` | 壳 | `LaunchBehavior.swift:105` | 强制本进程 `NSApp.appearance` 为 `light`/`dark`（别名 `aqua`/`darkAqua`） | ✅ | 否 | **P4 新增**。只改本进程，不动用户系统外观；值写错会沿用系统档并写 stderr 留痕。生效凭据打在启动日志里，`p4-sweep.sh` 会 grep 回控制台。**P18：判定树换成 `MMLaunchHook.resolveAppearance`（MMCore，`light|aqua|dark|darkaqua` 四写法带单测）**，留痕文案逐字未改。**P29 现读重指：原记 `:82`** ——本轮 `LaunchBehavior.swift` 净 +79 行，全落在这个读取点**上方**（`LoginItemManager` 的状态读法 +31 行那一段、`LaunchMenuDump` 一整段），所以它和下面那条 `MM_WINDOW_SIZE` 一起漂了同一距离（+23）——**同一个文件里两个锚点漂同样的行数，是"上面插了一段"的形状而不是"两处各自改过"**，这一眼能省掉一次逐条复核 |
| `MM_WINDOW_SIZE` | 壳 | `LaunchBehavior.swift:135` | `=宽x高`（如 `900x600`）改主窗口内容区尺寸 | ✅ | 否 | **P4 新增**。下限 320×200，解析失败/找不到主窗口都写 stderr；`DispatchQueue.main.async` 等窗口上屏。**凭据回读夹取后的真实窗口尺寸**（`asyncAfter 0.3s`）：窗口有 `.frame(minWidth:)` 地板，请求 900 会被夹到 1000，只回显请求值会产出"看着真、来源错"的最小窗口证据。**P18：解析换成 `MMLaunchHook.resolveWindowSize`（MMCore，带单测）**。**P29 现读重指：原记 `:112`**，漂因见上一行；`setContentSize` 那一调用点现读 `:144`（`fidelity-shell.md` §提请协调者 与 `fidelity-guardian.md` §6.6.5 各引过一次，同轮一并改指） |
| `MM_SETTINGS_TAB` | 壳 | `SettingsView.swift:13` | 设置 sheet 默认选中 tab | ✅ | 否 | 非法值回落 `.general`。**P18：改走 `MMHookValue.selected`**（此前写错值一声不出，照片停在「通用」却被登记成某一 tab 已核对）。**P29 现读重指：原记 `:11`**，本轮 `SettingsView.swift` 在它上面加了 `import MMMonitor` 与一个 `@StateObject`（通知授权状态），两行 |
| `MM_OPEN_TAB` | `MMCleaner` | `CleanerContainerView.swift:30` | cleaner 页默认 tab（cache/folders/system/**dev**） | ✅ | 否 | 非法值回落 `.cache`。**P5.1 新增 `dev`（开发产物子页）**。**P18：改走 `MMHookValue.selected`**，`accepts` 由 tab 表现算，写错必留一行 |
| `MM_CLEANER_FILTER` | `MMCleaner` | `MMCleaner.swift:318` | 搜索框初值（等价于用户手动输入） | ✅ | 否 | **P16 现读**：原记 `:280` 已漂。任意串都合法（就是搜索词），没有"写错"这一态 |
| `MM_EXPAND_CATEGORIES` | `MMCleaner` | `MMCleaner.swift:138` | 展开分类 | ✅ | 否 | **P16 现读**：原记 `:148` 已漂。C 类，P18 未改（见 §5） |
| `MM_AUTO_SCAN` | `MMCleaner` | `UserFolderCleanView.swift:112` `SystemAnalysisView.swift:78` | 进场即触发扫描 | ✅ | 否（只读扫描） | 仅枚举文件系统，不写不删。C 类，P18 未改 |
| `MM_SHOW_CONFIRM` | `MMCleaner` | `MMCleaner.swift:397` `UserFolderCleanView.swift:116,384` | 弹出删除确认面板 | ✅ | 否（弹面板，删在按钮里） | 实际删除需用户点「确认」，过 `DeletionGuard`。锚点于 2026-10-04 现读重定（原记 `:359` 已漂）；**P18 后再漂 7 行**。C 类 |
| `MM_INSTALLER_FIXTURE_DIR` | `MMCleaner` | `UserFolderCleanView.swift:120,366` | 注入安装器残留夹具目录 | ✅ | 否 | **只认 `/tmp` 之下**，越界忽略并写 stderr（守卫在 `:15`） |
| `MM_FAILURE_FIXTURE` | `MMCleaner` | `MMCleaner.swift:403` | 渲染拒绝回执（=protected） | ✅ | 否 | 仅展示，复用 `MMUI.MMFailurePanel`。**P16 现读**：原记 `:365` 已漂；`MMCleaner.swift:930` 是那段回执的注释锚（**P25 现读：`930` 已漂到 `923`**，清理页副标题整段搬家后那一屏之后整体 −7；本文表里"锚点"一列仍写 `:403`，那是渲染点，本轮没动）。**P18：改走 `MMHookValue.flag(token:"protected")`**——改前只有 `== "protected"` 一种写法能用，写成 `Protect` 就静默什么都不画 |
| `MM_SNAPSHOT_FIXTURE` | `MMCleaner` | `MMCleaner.swift:250` `applySnapshotFixture` | 把"磁盘空间只读报告"里的**快照那一块**换成样例文本（`mixed`/`overflow`/`updateonly`/`none`/`broken`） | ✅ | 否 | 只替换解析器的输入字符串，卷容量仍是真读的；不起命令、不碰盘。**P18：未知取值从"整块静默忽略"改成留一行**（`含非法取值（…），只接受 broken|mixed|none|overflow|updateonly`），五个档名逐字列出来 |
| `MM_PURGE_FIXTURE_HOME` | `MMCleaner` | `DevArtifactView.swift:69` `fixtureHome` | 把「开发产物」页的扫描根换成假 home | ✅ | 否 | **P5.1 新增。只认 `/tmp`**：`realpath` 解析后**再复核一次前缀**，越界整块忽略。这一屏的终点是删除按钮，所以钩子绝不能把用户的真项目变成可以整片勾选的夹具。配合 `Scripts/purge-fixture.sh`。**P16 现读**：原记 `:45` 已漂。**P18 补的安全洞**：改前三条失效分支（非 /tmp 前缀、`realpath` 失败、解引用后跳出 /tmp）**全是静默 return nil**，而 nil 回落的是 `NSHomeDirectory()`——写错一个字母就把"拍夹具"换成"拍用户真实项目，且每行可勾选可删"。现在三条各留一行 stderr（文案点名"扫描根将是真实 home"），且 `static var`→`static let`（`scanHome` 在 `body` 里被多帧读到，计算属性会把留痕刷成刷屏）。**这三条故意不拍照**（见 `hook-typo-audit.md` §3）：画面内容取决于回落时用户的真 home，取证不该把真 home 拍进仓库 |
| `MM_DEV_EXPAND` | `MMCleaner` | `DevArtifactView.swift:270`（首扫后）与 `:302`（续扫合并后） | 扫描回来后把所有项目分组一次性展开 | ✅ | 否 | **P5.1 新增**。非空即生效，只改内存里的 `expandedRoots`。两处是两条路径各读一次，**只改一处会让"续扫之后"那一档拍不到展开态**。**P16 现读**：原记 `:109` 已漂。C 类，P18 未改 |
| `MM_DEV_SELECT` | `MMCleaner` | `DevArtifactView.swift:273` | `=untouched` 时勾选全部"判定可回收且体积已量到"的行 | ✅ | 否 | **P5.1 新增**。只写内存 `Set<String>`；受保护、嵌套已计入、体积为 nil 的行**选不中**（`isSelectable`），所以这一拍里的勾选数就是删除按钮将来真正会数的数。**P16 现读**：原记 `:112` 已漂。**P18：改走 `MMHookValue.flag(token:"untouched")`**——改前写成 `untouch` 会静默不勾，照片上删除按钮是灰的，看上去却像"勾选态已核对" |
| `MM_DEV_SCROLL` | `MMCleaner` | `DevArtifactView.swift:735` | `=end` 时列表自滚到底 | ✅ | 否 | **P5.1 新增**。窗口高度被屏幕钳住，底部合计条和操作条在首屏外；用 `ScrollViewReader` 自滚**代替合成滚轮事件**。**P16 现读**：原记 `:428` 已漂。**P18：改走 `MMHookValue.flag(token:"end")`** |
| `MM_DEV_CONFIRM` | `MMCleaner` | `DevArtifactView.swift:437` | 弹出开发产物删除确认面板 | ✅ | 否（弹面板，删在按钮里） | **P5.1 新增**。链路同 §3 三关：确认按钮 → `DeletionGuard` → `FileTrashService`。**P6.7 复核**：锚点原记 `:236`，当时现读 `:407`；它写在 `.task` 里而 `model.scan()` 上一行没 await，所以面板先于 `report` 打开（等够就不空）。**P6.8 收口**：`Scripts/p68-dev-capture.sh` 第 04 档现在会重拍这一张（写进 `docs/verification/p68-dev/`，旧 `p7-dev/04` 未动），"有照片、无脚本"这条不成立了；详见 `fidelity-cleaner.md` §9–§10。**P18 现读**：`:437`。C 类 |
| `MM_DEV_ROOT_BUDGET_SECONDS` | `MMCleaner` | `DevArtifactView.swift:160`（读）＋ `:181-184`（写进 `rules`） | 覆盖**全量扫描**的每根预算（`ProjectArtifactRules.rootBudgetSeconds`） | ✅ | 否（只读扫描，只是提前收尾） | **P6.1 新增**。必须 `>0` 才生效，真机不设就是原口径 15 秒。同时把 `totalBudgetSeconds` 抬到 `max(总, 覆盖值)`（`:184`）——只改每根预算而总时限仍写死 60 秒的话，钩子写 120 实际拿到的是 60。点名条里"每次 X 秒"读的就是这个数（`:124` → `:614`），抄字面量会骗人。**P16 现读**：本行此前记 `:138,146`。**P18 补的洞**：改前 `Double(token)` 失败或 `<=0` 都静默回落，而 **`Double("nan")` 是能解析的、`nan > 0` 是假的**——写成 `15s`/`nan` 拍出来的"预算 15 秒"照片跟钩子一个字节关系都没有，日志也一行不留。现在走 `parseBudgetOverride`，非 `>0` 一律点名（结果存 `static let`，理由同 `fixtureHome`：这条是 `body` 可达的） |
| `MM_DEV_CONTINUE_BUDGET_SECONDS` | `MMCleaner` | `DevArtifactView.swift:161`（读）＋ `:181-184` | 覆盖**续扫批次**的每根预算 | ✅ | 否 | **P6.1 新增**。为什么必须两个键：同一个极小预算下，首批截断的根在第二批必然同样截断，「本轮扫完」（绿 chip + 「第 N 批补全」）那一档就永远拍不到。留痕逻辑与上行共用 `parseBudgetOverride(key:)`（`:163-175`） |
| `MM_DEV_AUTO_CONTINUE` | `MMCleaner` | `DevArtifactView.swift:194`（读）与 `:209`（消费） | 全量扫完之后自动再跑最多 N 批续扫 | ✅ | 否（跑的是同一套只读扫描） | **P6.1 新增**。只认 `1…3`，其余值忽略。每批之间复查 `canContinueTruncatedRoots`，试满 2 次的根自动排除，所以不会自己循环成常驻扫描。存在的理由：②「续扫之后」与③「已试过 2 次」两档都要按一次按钮才进得去，而**合成点击会逃逸到用户的其它应用**（老规矩），点击链本身不在取证范围。**P18：改走 `MMHookValue.int(bounds:1...3, fallback:0)`**，写成 `3s`/`0`/`9` 现在都会留一行并回落 0（=不自动续扫） |
| `MM_UNINSTALL_PANE` | `MMUninstaller` | `MMUninstaller.swift:142` | 卸载页默认 pane | ✅ | 否 | 非法值回落 `.apps`。**P18：改走 `MMHookValue.selected`**（`Pane` 实现了 `MMHookKeyed`，`accepts` 就是 `apps|orphans`） |
| `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` | `MMUninstaller` | `UninstallFixtureHooks.swift` | 仅加载 `/tmp` 假应用并打开卸载确认面板 | ✅ | 否 | 解析符号链接后仍须位于 `/tmp`；配合 `Scripts/uninstall-fixture.sh`，绝不自动点击删除。失效写 stderr（`忽略该钩子`），P18 保留原写法（A 类，见 §5） |
| `MM_UNINSTALL_CONFIRM_MODE` | `MMUninstaller` | `MMUninstaller.swift:79` | 夹具确认模式 `apponly` / `withresiduals` / `none` | ✅ | 否 | 仅在上行有效时读取；省略则为 `appOnly`。**P5.2 新增 `none`**：只选行不弹面板，面板会盖住列表的行内徽章与详情的来源三行。**P18 补的洞**：改前是 **case-sensitive 的 `switch` 字符串**——写成 `WithResiduals` 或 `withresidual` 都掉进 `default` 静默变 `appOnly`，拍出来的面板少一栏却被登记成"带残留档已核对"。现在经 `ConfirmHookKeyed` 三档 + `MMHookValue.selected`（先 trim+小写，写错留一行）。实机档号 23 |
| `MM_UNINSTALL_SELECT` | `MMUninstaller` | `MMUninstaller.swift:110` | 按 `bundleName` 点名要选中的那一行 | ✅ | 否 | **P5.2 新增**。只写 `selectedAppID`，不点任何按钮。点不到时写 stderr 并**什么都不选**——宁可拍出一张空态，也不悄悄换成别的应用。真机上不需要夹具目录就能用（选中态是内存里的），夹具截图下与 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 配合 |
| `MM_ORPHAN_FIXTURE_HOME` | `MMUninstaller` | `MMUninstaller.swift:42` | 注入孤儿扫描夹具 home | ✅ | 否 | **只认 `/tmp` 之下**，越界忽略并写 stderr |
| `MM_TRASH_FIXTURE_DIR` | `MMUninstaller` | `TrashWatcher.swift:106` | 注入废纸篓夹具目录 | ✅ | 否 | 同上，只认 `/tmp`。**P6.7 起被拒还会点名"改为监听真实废纸篓"**（`:110-113`） |
| `MM_TRASH_SCAN_HOME` | `MMUninstaller` | `TrashWatcher.swift:123` | 注入废纸篓扫描 home | ✅ | 否 | 同上，只认 `/tmp` |
| `MM_SHOW_TRASH_CONFIRM` | `MMUninstaller` | `MMUninstaller.swift:779` | 弹出废纸篓确认面板 | ✅ | 否（弹面板，删在按钮里） | 删除走 `FileTrashService`，过闸门。**P18：改走 `MMHookValue.flag(token:"1")`**——这一族三个 `=="1"` 开关（另两个见下两行）改前 `=0` 也算开，写 `=1 ` 之外的一切都是静默关闭 |
| `MM_APPS_WATCH_FIXTURE_DIR` | `MMUninstaller` | `AppFolderWatcher.swift:117` | 把「应用目录监听」的根换成夹具目录 | ✅ | 否 | **P5.3 新增。只认 `/tmp`**（复用 `TrashWatcher.fixtureEnvironmentValue`）。只改监听根，不写盘；配合 `Scripts/apps-watch-fixture.sh` |
| `MM_APPS_WATCH_AUTO_SCAN` | `MMUninstaller` | `MMUninstaller.swift:93` | 启动后自动走一次消失卡的「重新载入并扫描」 | ✅ | 否（扫描只读，删在按钮里） | **P5.3 新增**。**必须 `MM_APPS_WATCH_FIXTURE_DIR` 成立才生效**，否则忽略。合成点击进不了原生按钮，而这张卡的终点不跑一次就拍不到。**P18：`flag(token:"1")`** |
| `MM_UNINSTALL_SELF_ECHO` | `MMUninstaller` | `MMUninstaller.swift:103` | 自动执行一次「仅卸载应用」，用来拍自我回声文案与回声抑制 | ⚠️ 会动文件 | **是**：把夹具里那个 app 真的移进废纸篓 | **P5.3 新增**。**必须 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME`（/tmp 假 home）成立才生效**；`MM_UNINSTALL_SELECT` 点名，取不到就不动。跑完 `Scripts/apps-watch-run.sh` 会按 bundle 标识（不认名字）清掉本次进废纸篓的夹具应用。**P18：`flag(token:"1")`**——这个钩子是唯一会动文件的，把它从"非 `1` 即静默关闭"改成"非 `1` 点名 + 关闭"，等于给这条唯一的破坏性入口多加了一道会说话的门槛 |
| `MM_PROBE_WINDOW` | 壳 `Sources/MacMaster` | `WindowProbe.swift:12` | 按 0.2…16s 若干时间点把每个真实窗口的 AppKit 帧写到 stderr | ✅ | 否 | **P5.3 新增**（取证工具，不是界面钩子）。只读 `frame/bounds/contentLayoutRect/subviews`，不改任何帧；没有这个变量时 `start()` 直接返回。量的是"宿主视图有没有比窗口高"，见 `apps-watch.md` §7 |
| `MM_DUMP_MENUS` | 壳 | `LaunchBehavior.swift:182` | 启动时把**两支菜单的条目文字**打进 stderr：`NSApp.mainMenu` 递归（带 `[⌘,]` 这种键位标注）与菜单栏状态菜单（`MenuBarManager.statusMenuTitlesForDump`，`MenuBarManager.swift:59`） | ✅ | 否 | **P29 新增**（同 P5.3 那一族：取证工具，不是界面钩子）。存在的唯一理由是**菜单不点开就没有内容**，而本项目禁止合成点击（会逃逸到用户前台的别的 App）——设置页那两条新入口（⌘, 与状态菜单「设置...」）的判据是"菜单里有没有那一行"，没有这个键就只能靠"我写了这行代码"来主张。**代价写在代码里**：`MenuBarManager` 因此把"构造条目"与"挂上菜单"拆成两步（`menuWillOpen` 只做第二步），dump 走第一步；**拆开的两步之间不许有状态**，否则 dump 出来的和真挂上去的不是同一份菜单，那比没有判据更坏。C 类（非空即生效，`env["MM_DUMP_MENUS"] != nil`）——它没有"写错值停在另一档"这一态，写什么都摊平，所以 P18 那套回落+留痕不适用；生效与否的凭据就是那几十行 `MM_DUMP_MENUS` 前缀本身，一行都没有等于没开 |
| `MM_OPEN_TAB` | `MMDisk` | `MMDisk.swift:38` | disk 页默认 tab（tree/list/large） | ✅ | 否 | 非法值回落 `.treemap`。**P18：改走 `MMHookValue.selected`，写错留一行并列出 `tree|list|large`**。这一行是本轮最典型的一个坑：页面上那个 tab 的标题写着 **Treemap**，而钩子只认 **`tree`**（`hookKey` 与 `rawValue` 不同源，见 `:29-35`）——改前写 `treemap` 会静默停在 treemap 上，**照片和"钩子生效"完全同一张**，人照着界面写字必然中招。现在日志会指出"只接受 tree|list|large" |
| `MM_DISK_DEPTH` | `MMDisk` | `MMDisk.swift:157` | 展开深度 1…4 | ✅ | 否 | 越界（非 1…4）忽略。**P18：改走 `MMHookValue.int(bounds:1...4)`**——改前 `depth=abc` 与 `depth=9` 都是静默按默认，日志上分不出"钩子没写"和"钩子写错了" |
| `MM_DISK_FILTER` | `MMDisk` | `MMDisk.swift:159` | 过滤串 | ✅ | 否 | 任意串都合法（就是过滤词），没有"写错"这一态 |
| `MM_DISK_SCAN` | `MMDisk` | `MMDisk.swift:175` | 对指定根路径触发扫描 | ✅ | 否（只读扫描） | 仅枚举，不写。**本轮补 /tmp 守卫**：非 `/tmp`/`/private/tmp` 前缀写 stderr 并忽略 |
| `MM_DISK_SELECT` | `MMDisk` | `MMDisk.swift:1083`（重放闸门 `:1084`，置位 `:1099`；**P35b 现读重指**——这一段整体往下漂 16 行，裸 `:NNN` 续列不在重指工具的视野里，逐条现读改的） | 预选路径并展开 | ✅ | 否 | 仅展示选中态。**本轮补 /tmp 守卫**：任一目标非 /tmp 前缀则整体忽略。**P6.2a 起只重放一次**（`selectionHookApplied`）：它代表"用户动手标记过一次"，每次扫描都重放会把该丢弃的标记重新加回来。**P6.7 起选中成功/失败各写一行**（成功带 `MMFormat.bytes`，失败点名「这一层不在已展开的树里」）——`openDirectory` 遇未缓存的一层会起 `Task { doNavigate }`，这一路是有窗口的，不写日志就分不出「钩子没跑」与「这一层还没到」 |
| `MM_DISK_RESCAN` | `MMDisk` | `MMDisk.swift:187` | 首扫落地后**自动再扫一次**指定根（P6.2a 新增） | ✅ | 否（只读扫描） | 值同样只认 `/tmp`/`/private/tmp` 前缀，越界写 stderr 并忽略。给同一个根=拍"标记跨重扫还在"，给另一个根=拍"挂不回去的丢弃并点名" |
| `MM_DISK_HOLD` | `MMDisk` | `MMDisk.swift:164` | `=hold` 冻结在"正在分析磁盘结构"首帧，不触发扫描 | ✅ | 否 | 见 `fidelity-disk.md` §提请协调者 #4。**P18：`hold` 之外取值写 stderr 并忽略**（`:171-172`）。这一行原本是 `!raw.isEmpty` 的 C 类形态，但它是"**不扫描**"的开关——写成 `hold=1` 静默失效就等于拍一张正在扫的图却登记成"首帧已核对"，所以升格成点名 |
| `MM_SHOW_CONFIRM` | `MMDisk` | `MMDisk.swift:1133` | 弹出删除确认面板（回收/进废纸篓） | ✅ | 否（删在按钮里） | 过 `DeletionGuard`；面板里闸口拒绝项已提前为 `.guarded` blocked。**P6.7 起这行开面板时写一条带 `marked.count` 的日志**（`:1153`），找不到的目标逐个点名（旧写法悄悄跳过，面板行数就成了自报）。C 类，P18 未改 |
| `MM_SHOW_PERMANENT` | `MMDisk` | `MMDisk.swift:1157` | 把确认面板换成**永久删除**面板 | ✅ | 否（同一层交换 `showMarkConfirm=false` / `showPermanentConfirm=true`，不删） | 值 `acked` 时代码里把确认勾选打上，截图才能拍到"按钮点亮"那一态；勾选本身不落盘。**P18 现读**：原记 `:1160` 已漂 |
| `MM_SHOW_TOAST` | `MMDisk` | `MMDisk.swift:1121,1168` | 弹出回执吐司 | ✅ | 否 | `=permanent` 走"已永久删除 · 无法恢复"那一支（橙色三角、**无撤回按钮**），数字借自当前选中项，不移动任何文件。**P18 归为 D 类**（写错不会停在另一档还看不出来）：两条分支各自 `MM_SHOW_TOAST 已画出「…」回执条`（`:1129`、`:1173`）自报画的是哪一支，照片与日志互相印证 |
| `MM_UNINSTALL_SENSITIVITY` | `MMUninstaller` | `UninstallerModel.swift:184` | 残留敏感度三档 `strict\|enhanced\|deep` 的取证注入 | ✅ | 否 | **P32b 新增，但当时没回填本台账**（§0 那条钩子名计数因此停在 P31a 的 53；P35b 现跑重记，见 §0）。档位名与界面选择器 `ResidualSensitivity.allCases` 同源，写错值回落 strict 并留一行——`ResidualSensitivityTests` 里 P32b 加的 4 条钉的就是这两件事。取证 `Scripts/p32b-steam-launcher-capture.sh` 与 `Scripts/p33b-nesting-capture.sh` |
| `MM_VOLUME_FIXTURE` | `MMCore`（读取点）· 消费方是壳 `Sources/MacMaster` 与 `MMDisk` | `VolumeRoots.swift` `VolumeRootProbe.snapshot(env:)` | 把"这台机器挂了哪些卷"整块换成四档合成快照（`off\|two\|zero\|fail`），用来拍本机**永远拍不到**的那三档界面分支 | ✅ | 否 | **P35b 新增**。经 `MMHookValue.selected`，写错值整支作废 + 留一行、回落 `off`（= 读这台机器）。为什么必须有它：本机候选根恒为 1（一块内部盘、`/Volumes` 是空的），所以「这台机器还有 N 卷可以切换分析」与「未能读取卷列表，这里不猜数字」两句在真机上都不出现——`disk-volume-enumeration.md` §11.5 当时接受的是"正分支只有单测"，本轮补成照片。**代价写在这里**：合成值只证明界面会写这句话、放得下这句话，**不证明这台机器有两块盘**，所以每一档的 `.log` 里都自带一行「已生效：这是合成快照，不是这台机器的读数」。**这一行自己踩过坑，而且是本台账 §0 那一族坑的第 N 次复现**：第一版把 `\(tier.rawValue)` 手写成 `\tier.rawValue`，`\t` 被当成制表符，stderr 打出来是「=〈TAB〉ier.rawValue 已生效」——照片照常拍到徽标、日志照常有一行"已生效"，**唯一的机械判据当场变假绿**。现在那句是 `VolumeFixtureTier.appliedNote` 纯函数，由 `testAppliedNoteNamesTheTier` 钉住档位名必须出现在里面。取证 `Scripts/p35b-volumes-capture.sh`（八档：磁盘页 01~06 + 概览页 07~08） |
| `MM_GUARDIAN_FIXTURE` | `MMGuardian` | `MMGuardian.swift` `GuardianViewModel.fixtureOverrides` | 注入守护规则夹具行 | ✅ | 否 | 合成 `com.example.*`，不碰真实登录项。**这一族五个钩子的读取点全在 `GuardianViewModel` 的静态属性上**（原来是 `:410/:424/:438/:450/:461` 这种行号，P11b 一律换成符号名——它们已经漂过两次，每次改这一页都要重量） |
| `MM_TCC_FIXTURE` | `MMGuardian` | `GuardianViewModel.tccFixtureState` | 注入 TCC 授权表行 | ✅ | 否 | 支持 `rows/unreadable/empty/partial` |
| `MM_GUARDIAN_LOGIN_FIXTURE` | `MMGuardian` | `GuardianViewModel.loginFixtureStage` | 注入登录项夹具（rows/empty/indeterminate/scanerror） | ✅ | 否 | **README §2 漏列，本轮补正** |
| `MM_GUARDIAN_LOAD` | `MMGuardian` | `GuardianViewModel.holdInitialFrame` | `=hold` 时整页冻结首帧（测量中+骨架） | ✅ | 否 | **README §2 漏列，本轮补正** |
| `MM_GUARDIAN_ACTIVITY_FIXTURE` | `MMGuardian` | `GuardianViewModel.activityFixtureStage` | 活动卡（P11c 起叫「密钥与自启配置的改动时间」）注入 `empty/rows` | ✅ | 否 | 见 `fidelity-guardian.md` §5 G1（该条已标已落实）；合成条目标"夹具值"。**P6.2d 起用 `MM_GUARDIAN_CARDS=activity` 只渲染活动卡出片**（§6.6.3）。**P11b 的教训**：`rows` 档从来没证明过真实读取路径——它把待测的那条读法整条换掉了（§6.6.3 末尾）。**P11c 更新**：`rows` 档两行的用词跟着合同换了（detail 从中文说明改成绝对路径、tone 只剩 caution/neutral、不再有"系统日志事件"那一行），判据 `testFixtureRowsUseTheSameVocabularyAsRealRows`——**夹具的口径必须和真机同一套，否则无头照片在教一套真机不再产出的话** |
| `MM_GUARDIAN_CARDS` | `MMGuardian` | `MMGuardian.swift` `GuardianCardFilter`（`GuardianFixtureHooks.swift`） | 卡显示过滤，逗号子集 `occupancy\|tcc\|login\|activity` | ✅ | 否 | **P6.2d 新增**。纯显示层过滤，不改变数据流；非法值整批拒绝并写 stderr。解决活动卡排在第 4 位永远在折叠线以下的问题——07/10 两档用 `=activity` 只渲染活动卡，不再需要拉高窗口+压矮上方三卡 |
| `MM_OPEN_TAB` | `MMOptimizer` | `MMOptimizer.swift:41` | optimizer 页默认 tab（duplicates/browser/status/devtools/**preferences**） | ✅ | 否 | 非法值回落 `.duplicates`。**P18：改走 `MMHookValue.selected`**——`duplicate`（少一个 s）此前静默停在重复文件 tab，与"生效"同一张图。**P34b 加第五档 `preferences`**（偏好文件健康检查那一屏），`accepts` 由 `OptimizerTab.allCases` 现算（`MMOptimizer.swift:270`），所以台账这一格与代码那句 tab 清单是同一支出 |
| `MM_OPTIMIZER_FIXTURE` | `MMOptimizer` | `MMOptimizer.swift` | 五 tab 空/失败/PROTECTED 态统一夹具（duplicates:N/empty/scannedEmpty、**caveat:unreadable:N / caveat:dataless:N（P6.6 新增，必须与 `duplicates:N` 同给，单独给则整条作废）**、browser:rows/empty、status:allReadOnly、devtools:notInstalled/unreadable、**prefs:broken/unreadable/empty/partial（P34b 新增四档，形状见 `OptimizerFixtureHooks.swift:226` 那个 `prefsScan(tier:)`）**、protected） | ✅ | 否 | 见 `fidelity-optimizer.md` §6；纯数值/状态注入，不读 /tmp、不写盘、不 spawn。**P6.6 起有 `fixturePinned`**：给了夹具的 tab 会被钉住，随后落地的真实扫描结果整批丢弃。在此之前钩子是**半生效**的——三个 tab 的夹具被并发真实扫描覆盖，拍出来的照片挂着夹具文件名却是真实数据（见 §4 #2）。**P34b 那四档走的是同一条 `fixturePinned`**，为它新写了 2 条判据（`testPreferencesFixtureSurvivesALaterRealScan` / `testUnpinnedPreferencesModelScansNormally`），不是只加了形状 |
| `MM_MONITOR_HOLD` | `MMMonitor` | `MMMonitor.swift`（#50 新增） | `=hold` 时冻结在 `.empty` 首帧 | ✅ | 否 | 见 `docs/analysis/fidelity-monitor.md` §4 |
| `MM_MONITOR_FIXTURE` | `MMMonitor` | `MMMonitor.swift`（#50 新增，P6.4 扩档，P6.5 加 `swapZero`） | 注入确定快照（populated/memoryNil/swapOff/**swapZero**/perCoreRed/perCoreEmpty/disk-unavailable:reason/processes/menubarOff + **P6.4 五档：sensors/sensorsUnavailable/sensorsNoFan/sensorsFanUnknown/sensorsHot，以及带自定义原因的 `sensors-unavailable:reason`** + **P37 电池四档：battery/batteryNoHealth/batteryCharging/batteryUnavailable，以及带自定义原因的 `battery-unavailable:reason`**） | ✅ | 否 | 纯数值注入，不读 `/tmp`、不采样；**传感器五档连 `SMCClient` 都不碰**（整块顶替 `SensorsSnapshot`），所以"钩子会不会写 SMC"这个问题在这条上答案是结构性的不会。逗号可叠加（如 `processes,sensors` 拍相邻两卡）；**`menubarOff` 自 P6.7 起才真的被消费**（`menuBar.disable()`，此前只解析不用）。**`swapZero` 与 `swapOff` 只差 `swapAvailable` 一位**（前者"读到 0"、后者"读不到"），这一位就是 I9 那两句话的分界；`populated` 底座的 swap 从 0/0 改成真实的 800 MiB / 2 GiB，否则这两档拍出来是同一张。**P37 电池四档同一形状**：`battery` 与 `batteryNoHealth` 只差 `DesignCapacity` 一位（有健康度 / 健康度「—」），`batteryCharging` 一次拍出状态行与预计剩余两行，`batteryUnavailable` 是整卡读不出；这台开发机是 Mac mini、`BatteryInstalled=No`，所以"有电池"的四个正分支在真机上不存在，只能由这几档出片（照片 01 拍的恰是 `noBattery` 那一档） |
| `MM_MONITOR_CARDS` | `MMMonitor` | `MMMonitor.swift` `MonitorCardFilter`（`MonitorFixtureHooks.swift`） | 卡显示过滤，逗号子集 `stats\|perCore\|disk\|memory\|process\|sensors\|battery` | ✅ | 否 | **P6.4 新增**。手法照 `MM_GUARDIAN_CARDS`：「温度与风扇」排在整页最后，760pt 窗口里永远在折叠线以下，靠钩子钉死位置而不是拉高窗口碰运气。非法值整批拒绝并写 stderr（半生效夹具 = 假通过）；纯显示层过滤，不改变数据流。**P37 子集多一个 `battery`**（枚举 `Card` 跟着新卡名一起长，键名没变） |

## 2. 各模块钩子小结

- **壳（Sources/MacMaster）**：**7 个**，纯导航/打开/取证档（`MM_APPEARANCE` `MM_WINDOW_SIZE` `MM_DUMP_MENUS`），零副作用。
  **这一格从前写 5 个，是两轮没回填攒下的**：P5.3 的 `MM_PROBE_WINDOW` 落在 `WindowProbe.swift`、
  P29 的 `MM_DUMP_MENUS` 落在 `LaunchBehavior.swift`，两个都进了上面的表却没进这一格。
  本轮现读枚举表里"模块"列写 `壳` 的行 = 7 行（`MM_OPEN_MODULE` `MM_SHOW_SETTINGS` `MM_APPEARANCE`
  `MM_WINDOW_SIZE` `MM_SETTINGS_TAB` `MM_PROBE_WINDOW` `MM_DUMP_MENUS`），**表与小结从此以行数对齐为准，
  不以"新增时记得顺手改一下"为准**——台账自己那条老教训（"旧文档里的数字是线索不是依据"）这次量到它头上。
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
- **MMOptimizer**：2 个（`MM_OPEN_TAB` + `MM_OPTIMIZER_FIXTURE`，后者 P6.6 起十档、**P34b 起十四档**——新增的 `prefs:broken/unreadable/empty/partial` 是同一支钩子上的四个取值，**钩子名总数没变**，`DevToolCacheAudit.swift:166` 那条口径也不受影响）。`DevToolCacheAudit.swift:166` 读的 `env` 是 **PATH 探测**（找可执行文件），**不是 `MM_` 夹具钩子**，与截图无关，不计入台账。
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
   挡住了；而另三个 tab 的视图级 `.task`（`MMOptimizer.swift:243`/`:265`、`DevToolCacheView.swift:84`。**P35b 现读重指**：2026-10-04 那一读是 239/261，之后被 P34b 第五 tab 与本轮各顶一次；重指工具照 HEAD 内容搬，把 239 搬到了 `MMFailurePanel` 那一行（HEAD 第 239 行确实是它），所以这一族改按 `grep -n "\.task"` 现读钉死）
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
3. **`MM_DISK_SCAN` 越界值处理**：~~当前未校验 /tmp~~ **已落地**：集成阶段对 `MM_DISK_SCAN`/`MM_DISK_SELECT` 补 `/tmp`/`/private/tmp` 前缀守卫，越界写 stderr 并忽略。**这一条原本带着一个行号（旧树的第 135 行），本轮把它去掉了**——那个坐标指的是"改前"的那棵树，改前的树已经不在，行号既不可能被门禁验（它验的是当前树），也不该由当前的行号来充数；守卫的现读坐标是 `MMDisk.swift:175-180`（选择类那一处在 `:1091-1096`）。
4. **§4 #2 那道提请已有答案，答案是"竞态没有扩散，但另一类缺陷扩散了"（P6.7，2026-10-04）**。
   换了一种判据再查一遍全仓：**不比照片 md5，而是找一个真实路径生产不出来的值去日志和照片里查它**。
   md5 只能证明"两张不一样"，证明不了"这一张是夹具"——`browser:rows` 与 `devtools:notInstalled` 从一开始就互相不同，
   它们照样都是真实数据。哨兵值反过来：监控页 `MM_MONITOR_FIXTURE=populated` 落地时
   「上次采样 2023-11-15 06:13」与温度键名 `TZZa…TZZh`（真机是 2026-10-04 与 `TCMz/Tp0c/…` 174 个点）
   都出现在画面上；守护页夹具的 `com.example.*` 与「（夹具值）」同理。**这两个钩子是真生效的**，
   `fixturePinned` 那类竞态在 monitor/guardian 上没有可复现的证据，性质与 §4 #2 猜测的不同：
   monitor 的夹具分支**刻意不调 `menuBar.enable()`**（`MMMonitor.swift:90` 那行注释就是理由——
   别让后台采样循环把夹具快照覆盖掉），所以"夹具与真实采样共用同一个赋值口"这件事根本不成立：
   注了夹具就没有采样循环。守护页的几张卡由 `MM_GUARDIAN_CARDS` 只渲染目标卡，
   喂数据的 `.task` 与夹具赋值之间没有观察到互相覆盖（`p62b` 那十档逐档不同即是证据）。
   **扩散的是另外三件事，都已修**：
   - **解析了却没人消费**（`MM_MONITOR_FIXTURE=menubarOff`）：#50 起这个 case 一直在解析，
     没有一处读 `fixture.menubarOff`，于是 `fidelity-monitor.md` §5 那行"关闭态已覆盖"是空的。
     现在它真把状态项摘掉，两档对照见 `docs/verification/p67-menubar-off/01↔02`
     （md5 `89d0fec5…` vs `2c125c01…`，除开关外全部数字逐位相同）。
   - **自报成功却不判前置条件**（卸载页孤儿夹具）：旧写法在 `scanOrphans` **静默 return**
     （`UninstallerModel.swift:574`）之后照样打一行"已自动勾选并打开确认面板"，取证脚本自己造了一条假凭据。
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
| `Scripts/p34b-prefs-capture.sh` | `MM_OPTIMIZER_FIXTURE` 的 `prefs:*` 四档 × 明暗两套 + **真机档**（不注夹具，读本机 `~/Library/Preferences`）+ 窄窗档 + 非法值守卫档，共 7 张 | **P34b 新增**。这一族的界面句子全是**计数拼出来的**（"检查过 N 个"、"其中 M 个我们没能读"、"剩下的 K 个没看"），计数错在画面上看不出来，只会长成一句假话，所以脚本末尾同样自带 `md5 -q *.png \| sort \| uniq -d`。本轮量到**一对重复是设计如此**：`01-prefs-real-gui.png` ↔ `07-prefs-fixture-invalid-voided.png`（非法值让整支钩子作废，画面就回到真机那一态），这一对记在 `fidelity-optimizer.md` §7.2，别当夹具没生效。**07 那一档的判据在 stderr 不在照片**。真机档是 P34a §11.1 那句的答案：探针（裸二进制）与界面（.app 进程）给的"M 个读不到"必须是同一个数 |
| `Scripts/p67-menubar-off-capture.sh` | 监控页「菜单栏监控」开关两档：`populated` 与 `populated,menubarOff`，其余环境变量逐字相同 | **P6.7 新增**。它存在的唯一理由是**把"开关"做成画面里唯一的变量**：底座同为 `populated`，两张照片除那枚 switch 外每一个数字都该逐位相同；一旦两张一模一样，`menubarOff` 就又变回"解析了没人消费"，一旦数字也漂了，说明夹具没钉住。零合成点击（点击会逃逸到用户其它应用），只 kill 自己起的 pid |
| `Scripts/p68-dev-capture.sh` | 「开发产物」七档：默认态 / 展开+批量勾选 / 滚到底四态徽标 / 确认面板 / 深色 / **真机** / 最小窗口 | **P6.8 新增**。把 `docs/verification/p7-dev/` 那批手工照片变成可重跑（旧目录一字未动，新照片写 `p68-dev/`）。判据是**画面上必须有真实机器生产不出的值**（`~/Documents/bulk-1…bulk-12`、「夹具值」），不是 md5 互不相同。06 是真机档：不带 `MM_PURGE_FIXTURE_HOME`、等 30 秒真实扫描 |
| `Scripts/p68-brew-capture.sh` | 「安装来源」九档：五档来源各一张 + 确认面板 + 深色 + 最小窗口 + 真机 | **P6.8 新增**。同上，旧目录 `p7-brew/` 未动。默认每次现造一棵 `provenance-fixture.sh`（`FIX=` 可复用）：staged 链接的设备号判据依赖"链接指向的就是这棵树里的这份 bundle"，拿旧目录重跑没坏，但照片里的路径会指着一次没发生过的运行。09 真机档可 `REAL_SELECT=` 点名（本机已无 Highball，本轮用的是 `WailBrew`，见 `fidelity-uninstaller.md` §12.3） |
| `Scripts/p68-trash-capture.sh` | 废纸篓监听两档：提示卡（夹具 + 脚本自己 `mv`）/ 无权限横幅（真机、无钩子） | **P6.8 新增**。01 的时序是全部取证脚本里最脆的一档：**基线必须晚于 `mv`**，否则拖进去的应用被当成"启动前就在"的历史条目、卡片根本不出现——所以脚本先轮询到窗口 id、再留 2 秒给 `startTrashWatching`，才动手 `mv`；`AFTER_MOVE` 默认 60 秒，因为残留扫描的合并计时器排在 MainActor 上、要等 41 个应用测完。跑前会验 `/tmp/mmstage/Foo.app` 还在，不满足就点名让人重跑夹具而不是拍出一张假态 |
| `Scripts/p68-disk-capture.sh` | 磁盘页删除面板四档：回收/裁决面板 → 永久删除面板（未勾选）→ 同一块（已勾选）→「已永久删除」回执条 | **P6.8c 新增**。它是这一族钩子的**顺序依赖**最容易踩空的一屏：`MM_DISK_SELECT` 把扫描根写在第一个会把 `selected` 走成 nil，`MM_SHOW_TOAST=permanent` 必须不带 `MM_SHOW_CONFIRM`（它自己 return），而绿色撤回那条回执**必须**带 `MM_SHOW_CONFIRM` 才够得着、可面板是 `.sheet` 又会盖住它——所以四档里唯独没有它（判据见 `fidelity-disk.md` §11.4）。04 档另有 `TOAST_SETTLE=5`：**吐司自己带 10 秒倒计时**，按通用 10 秒去拍正好卡在 `1s` 上 |
| `Scripts/p7-empty-scope-capture.sh` | 清理页空扫描范围两档：①四个类别开关全关 ②删回默认值作对照 | **P7a 新增**。这一档**没有对应钩子**，状态来自 `defaults write com.macmaster.app`（那四个开关本来就是持久化设置，页面 `.task` 进页即扫，所以"改设置 → 起进程"就够了，不需要合成点击）。代价是这把钥匙动的是**真实域**，所以脚本 `trap restore EXIT` 保证退出必删键，并把动过哪几个键写进归因头的第三行 `# defaults:`。**这是第四种注入手法**，与前三种（env 钩子 / 夹具目录 / 真实负载）不同：它改的是用户机器上长期留下的状态，跑挂了就一直关着——所以只有"页面自己会读设置"的这一类态能用它，且必须成对拍（异常档 + 还原档） |
| `Scripts/run-all-tests.sh` | 九包全量 `swift test`，逐包一行结论 + 总计 | **P7 新增**。它修的是**读数本身的形态错**：`swift test \| tail -4` 只剩 swift-testing 那行 `Test run with 0 tests`，于是 MMCore 的 48 个测试（P15 现读；这一格自 P7 起写的是 43）在屏幕上显示成"跑了 0 个"；而按 `with N failures` 字面顺序解析会把有跳过项的 MMDisk 解析成 **0 个测试**（那一行实为 `with 1 test skipped and 0 failures`）。两个坑都写进脚本注释了。**只认「Test Suite 'All tests' passed/failed」后面那一行**才是包级总数，中间同名格式的行是各测试类的分项 |
| `Scripts/p7-release-check.sh` | 发布候选产物的基础三照 + **签名/plist/Gatekeeper 结论**：①概览（不注钩子，真数据）②关于页（`MM_SHOW_SETTINGS=1 MM_SETTINGS_TAB=about`，判据是打包时指定的版本号必须出现在画面上）③`MM_WINDOW_SIZE=1000x600` 下限窗口概览 | **P7b 新增**。它归因头多了三行非照片证据：`# codesign:`（`flags=0x2(adhoc) Signature=adhoc TeamIdentifier=not set`）、`# plist:`（`CFBundleShortVersionString`/`CFBundleVersion` 逐键）、`# spctl:`（`rejected`）。两个用途：① **版本号链自证**——`make-app.sh` 写的 plist 与「关于」页画出来的字符串必须在同一张图里对得上，这比读代码强；② **签名状态是有照片的结论**，发版判定（`docs/analysis/release-readiness.md` §2）不用凭记忆。**P10 给 `# plist:` 又加一键** `CFBundleIconFile=${icon:-（无）}`：图标缺档不会有任何地方报错（Dock 只是变成通用白纸），所以只能把它塞进每次构建都必写的归因头里，让"这次到底带没带图标"成为一个有日志可查的事实而不是事后回忆。注意第三档：`1000x600` 就是窗口下限（`MacMasterApp.swift` 的 `minWidth/minHeight`），**再小的请求会被夹回去**，所以它测的是"下限窗口里会不会截字"，不是"能不能更小"——本轮正是这一档抓出内存卡「交换 …」那行的截断。**已跑三遍**：`v1.0.0/`（P9，571）→ `p12-v1/`（P12，581）→ `p13-v1/`（P13，579），三遍都是 `1.0.0(1)` / adhoc / `rejected`，判据见 `release-readiness.md` §7.2–§7.4 |
| `Scripts/p8-dashboard-scope-capture.sh` | 概览页「可清理跟勾选走」三档：①只勾日志 ②四个全关 ③删回默认值对照 | **P8 新增**，手段同 P7a（`defaults write` + `trap restore EXIT` + 归因头第三行 `# defaults:` 逐个键点名）。判据不是"数字变小"这种要看运气的说法，而是**结构性**的：01 那一档卡里只剩日志三类，「可立即释放 41.8 MB」正好等于两个可删类之和（应用日志 34.3 + 崩溃与诊断 7.5），只读的「系统日志 101.7 MB」不计入；03 同一格是 5.38 GB。02 是**未勾选类别**，不是「未扫描」也不是「测量失败」。两处实测代价：概览扫的是真实缓存，`SETTLE` 得给到 16 秒；窗口尺寸必须脚本自己写死（`SIZE=1400x1000`）——App 会恢复上次退出的 frame，第一次实跑恢复到 1000x652pt，要拍的那一卡直接落到折叠线以下 |
| `Scripts/p8-disk-depth-capture.sh` + `Scripts/disk-depth-fixture.sh` | 磁盘详情第四格三档：①封顶节点=**未枚举** ②正常目录=真实计数 ③文件=— | **P8 新增**。普通夹具（`disk-fixture.sh` 最深两三层）永远走不到 `depth >= maxDepth` 那一支，所以另造一棵 20 层窄树：扫 `根/L01…L20` 时 depth=20，L20 里的目录 L21 被做成 `children: []` + `deepSize` + `descendantsMeasured: false`。钩子凭据是日志那行 `MM_DISK_SELECT 已选中 …（2.2 MB）`，与画面上「占用 2.2 MB」对得上，才证明这一档拍的是"字节量到了、名字没枚举"这一对（旧代码在这里写的是 `0`）。两个坑记在这：① zsh 里累加路径的变量**不能叫 `path`**（它与 `PATH` 绑定，一赋值 `seq`/`mkdir` 就 command not found）；② 01 档会顺带触发一次单层重枚举（`openDirectory` 遇到未缓存的一层起 `doNavigate`），所以 treemap 里 L21 底下看得见内容，而右侧详情读的是原扫描树里那个封顶节点——这正是"未枚举"该有的样子：这一层没枚举过，不等于它底下是空的 |
| `Scripts/make-icon.sh` + `Scripts/make-icon.swift` | 生成 `Resources/AppIcon.icns`（十档），再**反向解一次核对**；`--check` 不重写 icns，但会现生成一份源图到 `build/AppIcon.check.iconset` 供字节比对 | **P10 新增**，这一条不是取证脚本而是**产物生成器**——图标没有钩子可注入，但它同样要"每个数字能自证"。形状取自设计系统的 `sparkles`（`docs/design-system/icons.js`），内外半径比 0.362 是从那条 path 直接量的，所以稿与产物可以逐数比对。判据刻意不用 `sips -g pixelWidth`：那只会报容器里被挑中的一档，**看不出十档是不是都在**，而少一档的后果（Dock 16pt 拿大图硬缩）在 plist、codesign、界面上都没有任何征兆。所以走 `iconutil -c iconset` 解回来数档数、比 1024 档字节数（现测 270,169 与源 PNG 一致）。**P36 补的两件事**：① 那句"比字节"在 `--check` 模式下从前恒不执行（源图目录只有生成分支才创建），现在两种模式都真跑，取不到源图就当场退非零；② 这一判的名字是**像素漂移探针**而不是字节流探针——同一张图换一种 PNG 编码，`iconutil` 归一回同一个 icns（现测 270,169 与 270,689 两个源图打出逐字相同的 icns），只有改像素才拒 |
| `Scripts/p11-hardened-check.sh` | 同一份二进制、两种签名档次（`flags=0x2(adhoc)` 与 `flags=0x10002(adhoc,runtime)`），逐能力拍七行对照照片：TCC.db / `launchctl list` / `log show` / SMC+IOKit 磁盘 / `tmutil` / 两组 kqueue 监听 | **P11 新增**。它把 `release-readiness.md` §3 那张**预测表**变成照片。两条硬规定写进脚本头：① **本轮零顶数据夹具**（`MM_*_FIXTURE` 改的正是"喂给界面的数据"，而这一轮测的是"取数那条系统调用还通不通"，带上夹具等于把待测对象换掉，照片会拍出一张漂亮的假绿）——唯一例外是监听两档的**目录**钩子，它们只把 kqueue 指到 /tmp，事件仍走真实 `DispatchSource`；② 需要点击才能触发的那条（登录项开关会真改用户 launchd 状态）**不测**，并把空白如实写回 §3。监听两档**不自己造时序**，直接调已验证的 `p68-trash-capture.sh` 与 `apps-watch-run.sh`——第一版在这里造过一次，`mv` 一个 `.txt`、等 9 秒，两档照片逐字节相同，看着像"签名不影响这一行"，其实什么都没拍到（要 `.app`、改动要晚于基线、mv 之后要等约 45–60 秒）。`ONLY=shots` / `ONLY=watch` / `ONLY=01,02,04,05` 逐档重拍（后者在 P11b 修完活动卡之后真的跑过一次，四档各自把关、没有把 03 捎上）
**P14 注**：上面能力清单里的 `log show` 那一行已随 P11c 撤下（`scanUnifiedLog` 已删），于是 **03 档不再是 hardened runtime 的判据**——它从前那句判据（"有没有出现「系统日志事件」行"）从此永远不可能满足。脚本头部注释已就地改成"只旁证这一屏在 runtime 下照样渲染"，并写明 `p11-hardened/03-activity-*.png` 里 P11c 之前那两张证明的是**当时的**判据 |
| `Scripts/p11-pipe-deadlock-repro.swift` | 不启动应用，只按同样的 API 形状跑同一条 `log show`：① 先 `waitUntilExit()` 再读 ② 读与等分占两条队列、**一超时整批丢掉** ③ 仓库实装（边读边攒、超时只杀子进程），各打印**自己的**耗时、字节数与可用事件条数；末位参数是 ③ 的轮数 | **P11 新增**。它是"这一格为什么是空的"的**独立复现件**：现测 ① 停在整 **65,536** 字节、8.01 秒到点被杀，② **0.82 秒**取回 **198,172** 字节，③ 五轮 0.83–0.90 秒正常退出、154–156 条事件行可用。有这一个文件，下一轮不必重跑整个应用、也不必信我们的叙述就能自己撞见同一个死锁 |
| `Scripts/make-app.sh` 的 `HARDENED=1` | 额外打 `--options runtime`，并在构建末尾**自己读回** `codesign -dv` 的 flags 一行 | **P11 新增档位**。它**不是任何一种发布形态**（发布要证书 + 公证），只是这一轮的量具。签名档次必须由脚本自己读回来打印——`codesign` 加了什么标志，看构建日志比看脚本可靠 |
| `Scripts/p12-sandbox-warning-probe.sh` | 同一份 bundle 原样拷进 `~/.mm-p12-probe/`（拷完 `codesign --verify --deep --strict` 自证），两个位置各起 7 秒，只比那一行 `sandbox_extension_issue_file_to_process` 出现的**次数** | **P12 新增**。它不为任何钩子服务，是为**还一笔旧账**：那行警告从 P7 起在每一份取证日志里都有，当时的解释是"ad-hoc 构建从 /tmp 起进程"——一句话捆了签名与路径两个变量，而两个都没单独测过。现测：`/tmp` **1 次**、用户目录 **0 次**，两档同为 `flags=0x2(adhoc)`、都活过 7 秒、界面都出真实读数 → **是路径不是签名**。探针目录跑完自删 |
| `Scripts/p11c-activity-capture.sh` | 四档零点击照片（真机 / 夹具 rows / 夹具 empty / 夹具 rows @1000×700），每份 `.log` 带 `# codesign:` 与 `# env:` 归因头；**真机档额外写 `# expect:` 行**——脚本用 `stat` 现读那五个路径的 mtime，与代码的 `attributesOfItem` 是两条不同的读法 | **P11c 新增**。它要闭的是照片侧那一环：卡片上那五个"X 前"必须能从 expect 行**算**出来（`.ssh` 08-20 14:23 → 照片 46 天前、`Keychains` 10-05 07:59 → 8 小时前），否则照片只是好看。两条读法对上才算数，这是 P6.7b"合成值有没有真的出现在画面上"那条判据的反向用法：**真值也要出现在照片里，并且要能从另一条路推出来**。**P13 又用了一次、只跑一档**：
`ONLY=01 ./Scripts/p11c-activity-capture.sh /tmp/mm-app-p13/MacMaster.app docs/verification/p13-v1`，
把真机那一档拍在 **`VERSION=1.0.0` 的发版候选产物**上（`p11c-activity/` 那四档是调试构建）。
`ONLY=` 这一档存在的意义就在这儿：**发版侧要的是"这份二进制"，不是"这一族状态"**，
四档重跑一遍只是把同一批夹具再点一次 |
| `Scripts/p14-header-capture.sh` | 三种窗口宽度各拍一张守护页整页（默认 1100×700 / 请求 1000×600、实际被 `minHeight` 夹成 1000×652 / 1400×900 作控制组），**零夹具**；唯一判据是"页头副标题那一行不许出现 `…`" | **P14 新增**。它管的是 D1（页头副标题补第四段，`fidelity-guardian.md` §8.1）改完之后**新引入**的风险：`MMPageHeader` 的副标题写的是 `.lineLimit(1)` + `.truncationMode(.middle)`，所以 3 段变 4 段既不换行也不报错，只会**静默切掉句子中段**，而切掉的恰好是"登录项管理"这种少看一眼也不觉得少了的词。`GuardianHeaderContractTests` 钉得住"段数对不对"，钉不住"画面上放不放得下"。三档实测四段全在；最窄档末尾距「刷新」不到三个汉字宽（照片 2× 估读，所以没写进判据）。**往后页头副标题每加一段都要重跑这一支** |
| `Scripts/p15-pipe-capture.sh` | 两档零夹具照片：`01-login`（`MM_GUARDIAN_CARDS=login` 只渲染登录项卡）+ `02-space`（清理页缓存 tab × 邮件过滤，读的是 tmutil 那一处）；每份 `.log` 带 `# codesign:` / `# env:` / `# pid:` 归因头与 `# expect:` 行 | **P15 新增**。它证的是"三处子进程调用并成一个已测执行器之后，界面这句话还是这台机器上的真话"。判据两次改过才立住：① 第一版拿登录项卡**脚注**（"launchd 里还挂着 N 个非苹果标签"）当判据，拍回来才发现 17 行列表下那条线**在折线以下**，画面里没有它——于是换成两条**一定在框内**的读法：`login-item-files=N`（对列表行数）与 `not-loaded-labels=N …`（对「已加载/未加载」那一列）。② 顺序上必须**先拍照再写 expect 行**：脚本开着 `set -e`，注解里任何一个语法错（本轮真撞过一个 `${(j:、)…}` 的 "error in flags"）会把已经起好的实例丢在屏幕上没人收，留过一个 pid 活到下一轮。两条 expect 用 `plutil`/`launchctl` 各自**独立**重算，与 `LaunchctlListParser` 是两条读法——本轮对上是 3 个孤儿标签 / 17 行 / 2 个未加载 |
| `Scripts/p17-website-capture.sh` | 落地页 §界面预览 那四张图，四档夹具实拍：清理（**dev tab**）/ 磁盘 / 监控 / 守护，全部 1280×800pt 暗档，产物直接写 `docs/website/assets/`（不是 `docs/verification/`），另落一份 `docs/verification/p17-website/capture.log` | **P17c 新增**。它与 `p68-*` 那一族的差别在**去向**：那批是验收证据，这批是要给陌生人看的宣传图，所以判据不是"这一档拍到了没"，而是**画面上不许出现只有这台机器才有的东西**。两条现读出来的覆盖面边界（都写进 `website-audit.md` §3）：① `MM_PURGE_FIXTURE_HOME` 只换「开发产物」那一页的扫描根，缓存 tab 进页即 `model.scan()` 扫真机（`MMCleaner.swift:389-392`），所以 01 只能拍 dev tab，卡片标题写「清理 · 开发产物」不是措辞选择而是被钩子决定的；② 侧栏 `volumeFooter`（`MainWindow.swift:141-166` ← `DashboardModel.swift:75`）、侧栏"系统清理"后面那格可回收体积（`MainWindow.swift:105-110`，读概览页那次真实扫描）与磁盘页 `卷可用` badge（`MMDisk.swift:379`）**没有任何钩子能碰**，整窗截图必然带上真实卷名、占用与可回收量——本轮的做法是**在页面上明说**而不是裁掉，理由同时写进了 `index.html` 那条 img 规则的注释里。零合成点击，只 kill 自己起的 pid；`ONLY` / `KEEP_FIXTURE` / `SETTLE` / `DISK_SETTLE` / `SIZE` 可改档重拍 |
| `Scripts/p18-hook-typo-proof.sh` | 23 档"把钩子写错一个字母"的实机核对：每档注入一个**故意写错**的取值，判据不是画面而是 **stderr 里必须出现那一行留痕**（`expect=` 逐档钉住文案片段），负向档（`expect=-`）反过来要求"这一档一条留痕都不许有" | **P18 新增**。这一族的判据天生不在照片上——照片对"钩子写错"毫无反应（静默停在默认档的画面与生效的画面是同一张），所以它是全仓唯一一个**以 stderr 为主证据、照片为佐证**的取证脚本。三条自己踩过的坑写进脚本头：① `ONLY` 曾写成 `1[348]` 这种字符类，zsh 里 `[[ $name == ${ONLY}* ]]` 不把它当模式读 → **一档没跑却打印"全部 0 档符合预期"并 exit 0**（绿色空跑，门禁工具最坏的失效）；现在改成逗号前缀列表 + `checked==0 → exit 2`。② `ONLY` 重跑曾把整个证据目录 `rm` 掉，剩下两份证据说不同的话；现在局部重跑写 `capture-partial.log`，一个字都不碰既有照片与既有 `capture.log`。③ 23 档要的卸载确认夹具是 `mktemp` 随机名、没法复用，脚本每次现造现删（`trap rm -rf EXIT`）。**五档（10/11/13/21/22）用 `-n` 只收日志不拍照**：它们的失效分支回落的是用户真 home 或真实扫描根，画面内容取决于机器现状，取证不该把真 home 拍进仓库（详见 `hook-typo-audit.md` §3、§6） |
| `Scripts/p31-running-capture.sh` + `Scripts/p31-running-fixture.sh` + `Scripts/running-apps-probe.swift` | 卸载页「正在运行」七档：①夹具在跑 ②确认面板里的提醒 ③同一张图上跑的/没跑的对照 ④最小窗口 ⑤只有包名对上 ⑥**窗口开好之后才启动进程** ⑦真机（WeChat）。每份 `.log` 带 `# digest:` / `# windows(pid=…)` / `# launched:` / `# snapshot(拍前/拍后):` | **P31a 新增**。这一族与全仓其它取证族的根本差别：**它的哨兵不许是合成值**。`RunningAppProbe.snapshot()` 里没有读 env 的分支、`runningAppsFactory` 只给单测注入，所以照片里那个 pid 背后是一个真的 `open -g` 起来的 /tmp 夹具应用（`p31-running-fixture.sh` 造三棵 bundle，其中 `Applications/ElsewhereFoo` 与 `Elsewhere/ElsewhereFoo` **同包名、不同位置**，专门撞"只有包名对上"那一档）。06 是唯一证明"通知驱动刷新真的通到界面"的照片：窗口先开好、进程后启动，中间没有任何重载——所以夹具必须是 Cocoa 应用（`sleep` 进程不发 `NSWorkspace` 通知）。两条本轮改出来的工具规矩：① **`main_window_id()`**——从前 `shot()` 拿 `head -1`，而 CGWindowList 前→后排序里最靠前那扇恰好是盖在主窗前的设置窗，05 第一次就拍成了设置页；现在要求"标题正好 `MacMaster` 且 `layer=0` 的窗口**正好一扇**"，挑不到就一张都不出，并把整份清单写进日志（现读：`Scripts/` 里 29 支引用 `window-ids.swift`、26 支仍在用 `head -1`，本轮只硬了这一支）。② **哨兵与画面同源**——`# real-running:` 从前由 `pgrep -f` 给出，数到 **13** 而照片上只有 **2** 个号（口径不同：快照里只有两条报出的 `bundleURL` 正好是外层 `.app`）；换成 `running-apps-probe.swift`，走与 `AppRunningState.resolve` 同一条 API、同一套比较规则，并在拍照前后各读一遍 |
| `Scripts/running-apps-tally.swift` | 现读一次本机进程快照，按 `RunningAppProbe.snapshot()` 的**同一口径**给两行统计：`total / pidNonPositive / participating / idEmpty / pathEmpty / bothEmpty`，外加 `idEmpty` 按 activationPolicy 的分桶 | **P31a 新增**。它不为任何照片服务，是给**"为什么没有照片"那句话**兜底的：`undetermined` 那一档本机拍不出来，依据只有"两样都报不出的进程是 0 条"这一个数——一个支撑"缺证据"的数如果不能被一键重算，它就只是一句印象。两个自己撞过的坑写进注释里：① 别按 `rawValue` 分桶（这个桥过来的枚举 `String(describing:)` 打出来是 `NSApplicationActivationPolicy(rawValue: 1)`，绕回数字；第一版就差点把 accessory 12 条读成 prohibited 12 条），改成逐 case 写死 + `@unknown default`；② 这些数**几十分钟就会变**（当日三次现读：参与判定 163 / 165 / 139，`idEmpty` 31 / 31 / 19），所以文档里引它必须带钟点，只有 `bothEmpty = 0` 那一条三次都稳 |
| `Scripts/p36-icon-byte-audit.sh` | 不启动应用，把 `make-icon.sh` 两道判据的各条分支**正反各撞一遍**：① `--check` 正向（现有 icns 该放行，且当场证明源图这次真的存在）② 负向（在临时树里用改过一位颜色常数的 `make-icon.swift` 打一棵 icns，再换回真源跑 `--check`，必须被字节判据拒）③ 边界（同一张图纯重编码 → icns 逐字相同 → 放行），末格自己比 `Resources/AppIcon.icns` 的 sha256，动了就退非零 | **P36 新增**，它是**给判据做判据**的一支：`--check` 那一支的字节比对从前恒不执行（源图目录只有生成分支才创建，`[[ -n "$src_bytes" ]]` 于是恒假），而成功那行打的又是被比对那一侧的数，所以日志永远读起来像"核过了"。**这类失效的通用形状是"取不到证据 = 这一判不适用"**，在门禁脚本里必须反过来：取不到证据就是失败。负向这一头值得记一个坑：第一版只改了 PNG 编码没改像素，`iconutil` 把两份输入归一回**同一个 icns**（sha 逐字相同），读数看着像"改源图也核不出来"——真改像素才撞出那句 `✗ 源 270169 / 解出 277310`。临时树走 `mktemp -d` + `trap rm -rf EXIT`，仓库里只留 `docs/verification/p36-icon-byte/audit.log`（过程见 `release-readiness.md` §7.25） |
- **钩子写错值不会让界面报错，只会让照片安静地停在另一档**（P18）：这是取证里最贵的一类错误——**假通过**。
  所以这一轮把"能不能发现写错"从人的记忆挪到两处：**判定下沉**（`MMCore.MMHookValue` / `MMLaunchHook`，
  22 条单测钉住文案，含一条 `dup`/`dup2` 到 fd 2 的"留痕真的落在 stderr"测试）与**门禁自证**
  （`p18-hook-typo-proof.sh` 的 23 档每一档都拿错值去撞，撞不出那行话就是红）。
  四类失效里只有 B 类（静默换档）需要修，本轮 16 个键全关掉；A 类本来就会说话，只统一文案；
  C 类（非空即生效的 7 键 / 13 处）**故意不动**并写清理由（见 `hook-typo-audit.md` §5）；
  D 类（`MM_SHOW_TOAST`）由自报文案背书。**判据不是"有多少钩子"，是"写错时日志里有没有一行"**。
- **`waitUntilExit()` 之后再读管道，是一个只在"输出够大"时才发作的死锁**（P11）：`Pipe` 的内核缓冲
  只有 64 KB，子进程写满就卡在 `write`，父进程卡在 `wait`，谁也不动。这一路的输出量取决于**本机日志量**，
  所以它在开发机上可以永远不出现——`scanUnifiedLog()` 自落地起就从未返回过内容，而界面显示的是
  **另外两个信号**，看上去完全像"这台机器近 5 分钟没有活动事件"。
  （**P11c 注**：`scanUnifiedLog()` 连同这一族已从界面撤下，见 `fidelity-guardian.md` §6.7；
  这一条教训**不随函数消失**——仓库里其余两处 `Process` + `Pipe` 仍是同一个形状。复现件
  `Scripts/p11-pipe-deadlock-repro.swift` 保留，它自带三支对照，不依赖任何仓库函数就能再撞一次这个死锁。）
  **P15 注**：这两处（`SystemSpaceReport` 的 tmutil、`LoginItemStore` 的 launchctl）连同 `CommandRunner`
  自己已并成一个执行器，现读全仓库（含测试）`Process()` 只剩 `CommandRunner.swift:51` 一处，
  且那一处读与等分占两条队列。这一条从"某处仍是同样的形状"变成"形状只有一个 owning 文件 + 五条合同测试"。两个可复用的判据：
  ① 凡是 `Process` + `Pipe`，**读和等必须分占两条队列**（P15 之前 `SystemSpaceReport` 那一处是同样的形状，
  只因 tmutil 输出小才没发作——"没发作"不等于"写对了"）；② 超时保护会**把死锁伪装成空结果**，
  所以带超时的读取要配一个能报字节数的复现件（`p11-pipe-deadlock-repro.swift`），
  否则下一次超时你只知道"没数"，不知道是"没数"还是"没读到"；
  ③ **超时之后不要把已经读到的整批丢掉**——仓库里实装的是复现件的第三支（边读边攒、超时只杀子进程、
  攒下的部分照常解析），因为"超时"和"这台机器没有事件"在界面上是同一句话，而它们不是同一件事。
  现测这一条命令 0.82–0.90 秒就跑完（**没有**触发超时），所以第三支在照片上和第二支看不出区别——
  它是给"会挂住的那种环境"买的保险，不是本轮的胜负手，别把它写成修好了什么。
  **P15 给 ③ 补一条边界**：这条判据跟的是"读到的东西怎么用"。P15 新实装的第三种执行器（`CommandRunner`）
  **故意反着来**——超时抛错、已读到的整批丢掉。因为③那条命令喂的是**事件流**（"有没有活动"，读到几条是几条，
  半批仍是证据），而 `launchctl list` / `tmutil listlocalsnapshots` 喂的是**计数**：界面上要说"N 个非苹果标签"，
  半批读出来的 N 只会**少报**，而少报的 N 长得跟真话一模一样（"只有 2 个"比"没核对成"更接近撒谎）。
  所以这里的正确形态是丢掉 + 让上层换成界面上那句原文（登录项卡是
  「这一轮没能和 launchd 对表（原因），所以下面不标注加载状态——「没查到」不会被写成「没加载」。」）。
  **往后新增子进程调用先问这一句：
  这次读法被截断会让界面少报一个数，还是只会少列几条？** 前者用超时换一句诚实的空档，后者才轮到③。
- **同一个形状会不会死锁，取决于这台机器吐多少字节**（P15）：本轮把三处调用并成 `CommandRunner` 之前，
  先量的不是"代码写得对不对"，是**余量**：`/bin/launchctl list` 同日多处现读 **18,541–19,540 字节**
  （18,541 / 18,825 / 18,959 / 19,540 各是一次现读——**这个数随作业启停浮动，所以写下来的是跨度不是单点，
  单次量到的数不能抄进下一轮**），≈ 64 KB 缓冲的三成。同一次采样里 544 行 → **34 字节一行**，
  照这个数推算**还要再多约 1,400 行才填满那 64 KB**。
  `/usr/bin/tmutil listlocalsnapshots /` 在这台机器上是 21–22 字节。这两个数说明的不是"安全"，
  而是**这两处死锁的距离是量的、不是推的**——launchctl 那处离线一千来行，tmutil 那处几乎永远不会到，
  于是"给它加不加超时"是两种不同代价的决定（读侧加 10 秒：宁可这轮说"没核对成"；写侧不加：
  宁可等，也不能把"没等到回话"说成"没改成"）。可复用的判据：**报告"这一处没发作"之前先报字节数**，
  没有数的"输出小所以没事"跟没检查过等价。
- **列宽会吃掉正文**（P11）：`log show` 不带 `--style` 时一行是 7 段定宽列 + 正文，
  旧代码 `line.prefix(80)` 恰好截在列里，于是修好死锁之后的第一张照片是"5 条事件、0 个字的内容"。
  同一批里还有两个同族错：列标题那一行被当成第 1 条事件，长消息的**折行续行**被当成独立事件
  （卡片写着 5 条其实 4 条）。判据都在 `ActivityScannerLogRowTests`，喂的是本机抄下来的行形状。
- **取"前 N 条"之前先量一遍子进程的输出顺序**（P11）：`log show` 是**升序**的（实测末行就是"刚刚那一秒"），
  而 `scanUnifiedLog()` 取 `prefix(5)` 再配一句写死的 `time: "最近"`——于是卡片画的永远是这 5 分钟窗口
  **最旧**的那头，15:07 拍的照片里五行时间戳全在 15:02。这一条**死锁修好之后才看得见**：
  死锁时这一格根本没有行，顺序错了也没人能看到；而先看到的那两个错（列宽、续行）又恰好都在
  "内容有没有活下来"这一侧，没人去问"这 5 条凭什么是这 5 条"。判据：`testRecentRecordsTakeTheNewestEndNotTheOldest`
  喂 9 条升序事件，必须交出 8…4 而不是 0…4。**照片上的时间戳本身就是判据**，读照片时别只读文案。
- **复现件里的计时必须逐支独立起点，不能共享一个全局起点**（P11，本轮自己量错自己的数）：
  `p11-pipe-deadlock-repro.swift` 第一版用 `stamp()` 打印"从脚本开始到现在"，于是 ② 那一行报的
  「8.90s」里含着 ① 的 8 秒死锁，读起来像"这条命令要 8.9 秒、超了应用侧 8 秒预算"——**而它自己只跑了 0.82 秒**。
  这个伪结论被抄进了源码注释与三份文档才被发现（发现契机是 ③ 打印「9.73s 正常退出」，
  一个不该出现的数：既然 8 秒就超时，正常退出怎么会花 9.73 秒）。两处可复用：
  ① 多段对照的脚本，**每一段自己记 `t0`**；② 打印耗时的地方要顺手打印"这一支是否触发了它自己的超时"，
  让"耗时 > 预算"这种组合自己暴露出来，而不是靠人回头看。
- **一句解释里不许捆两个变量**（P12）：`sandbox_extension_issue_file_to_process` 那行从 P7 起在
  每一份取证日志里都有，当时的写法是"来自 **ad-hoc 构建从 /tmp** 起进程"——签名档次与启动路径被一句话
  捆在一起，于是后面三轮都拿它当"签名档次的产物"记着，还留了一句"换 Developer ID 之后再复看"。
  拆成单变量只花了一次拷贝 + 两次 7 秒启动：`/tmp` 1 次、用户目录 0 次，两档签名同为 `adhoc`。
  **是路径，从来不是签名。** 可复用的判据：凡是"这行日志来自 X"的句子，先问 X 有几个自由度；
  自由度 ≥ 2 就把它记成**未归因**，别记成结论（本轮之前它就挂在 `release-readiness.md` §7.2 的"含义未查"上，
  而"未查"和"已归因"在文档里读起来几乎一样，这是最容易被抄走的一种错）。
- **取证脚本里 `local` 一行只认外层变量**（P12，本轮自己把证据写丢过一次）：
  `local name=$1 app=$2 log="$OUT/$name.log"` 在 zsh 里那个 `$name` 取的是**声明生效之前**的同名变量（外层没有 → 空），
  于是两档日志一起写进 `$OUT/.log`，屏幕上打印的计数却还是对的（各自 grep 同一个文件、顺序跑）。
  第一次跑完 `ls` 才发现 04/05 两个文件名下面躺着的是**手抄的旧内容**。判据：
  **多变量声明一律分行**；脚本跑完要 `ls` 输出目录核对文件名，而不是只看它打印的那两行。
- **计数漂移不在计数表里，在"引用计数的句子"里**（P12）：`release-readiness.md` §1 那张表 P11 已经改成
  581/MMGuardian 93，而 §6 的模块判定表还写"MMGuardian 83 测试"、壳层那格还写"九包 571 个测试"——
  同一份文档里两个数并存，且**错的那两个都是被人当结论抄走的那两处**。加一轮只追加 §1 的数，
  不等于全文同步；可复用的动作是 `grep -n "个测试\|测试全绿\|测试。" docs/analysis/*.md` 把**引用**计数的句子
  也过一遍，而不是只看计数表那一格。
- **一条读法修到能出内容之后，下一问不是"还能修什么"，是"这一族该不该在这张卡上"**（P11c）：
  P11 把 `log show` 那一路的三处读法错全修好了，P11c 去定文案合同时量的却是**谓词命中了什么**——
  按进程分布一摆，139 行里第一名是 sharingd 的 `authTag`（34%），第二名往后是 opendirectoryd、cloudd、
  remotepairingd，**没有一行是"系统活动"这个词在界面上暗示的东西**。接着量了八档（窄白名单 52 行全是
  tccd 内部转储、只留 loginwindow 0 行、切到摄像头/麦克风 24h 0 行、syspolicyd 30m 20,741 行……），
  结论是**没有任何一档同时做到低噪、可读、切题**，于是整族撤下。可复用判据两条：
  ① 界面上任何一族来自"外部命令的自由文本匹配"，先按**进程/来源分布**量一次它的命中集，
  第一名不是你想报的那件事，这一族的口径就已经错了（不是"再修一轮解析"能好的）；
  ② 撤下一族常常比修好它更省——这一族带着三处修好的缺陷活了若干轮而没人问过它该不该存在。
- **数子进程的输出要选列数固定的格式**（P11c，本轮同一件事失败两次）：`log show` 默认的 compact 格式
  **列数不定**（折行续行、`Activity` 类型行的列数与事件行不同），`awk '{print $8}'` 和按 7 段前缀的
  `sed -nE` 都把正文片段数成了进程名，于是那份"分布"看起来是个数、其实是垃圾。
  换 `--style json` 一次就对了，但注意**字段名两边不一样**：compact 里那列叫 `process`，
  JSON 里根本没有这个键，得读 `processImagePath`。判据：**同一批数据用两种格式各读一次，
  量到的东西要能互相对上**，对不上就是有一侧在猜列。
- **`prefix(n)` 之后再过滤，是"恒为空"的另一种写法**（P11c）：
  `for file in files.prefix(3) where file.hasSuffix(".plist")` 读起来像"取最近三个 LaunchAgent"，
  实际是"取目录枚举的前三项，再看其中哪几个是 plist"。本机 `~/Library/LaunchAgents` 九项里六项是
  改名停用的 `.disabled` 且排在最前 → 这一族在真机上**一行都没有**，而磁盘上确实有 3 个 `.plist`。
  它和 §5 那条"超时把死锁伪装成空结果"是同一族错：**空可以是逻辑顺序造成的，不是环境造成的**。
  判据要喂目录枚举的真实顺序（`testDisabledAgentsDoNotCrowdOutTheRealPlists`），
  只喂"三个 plist"那种干净输入永远测不出它。
- **界面上两个字段说同一个数，是一个信号**（P11c）：敏感目录那行从前是
  `detail: "最近访问: 刚刚"` 配 `time: "刚刚"`——同一个数说两遍。这类重复通常说明其中一个字段
  不知道该放什么，而这次它顺带藏着一个口径错：读的是 `.modificationDate`，写的是"访问"。
  收口手法也一样：detail 换成路径（真的新信息）、time 留 mtime 的相对说法，两格各说一件事。
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
- **行号是最先过期、又最不会报错的引用**（P13）：P11c 之后按规则把 `fidelity-guardian.md` §1 的
  指向 `MMGuardian.swift` 的行号全量重读了一遍，**11 处里 9 处漂**（+9 到 +41，不是同一个常数，
  所以不是"整段位移"，是多轮在不同位置增行累积出来的）。关键是**没有一处指错元素**：
  按新行号读回去，说的还是同一件事。所以行号漂移**不会让文档变错，只会让文档变得无法核对**——
  而下一个人以为它还能核对。两条规矩：① 新增引用优先写**符号名 + 一句语义**，行号只当辅助坐标；
  ② 只要动了某个文件，**引用它的那份文档的行号必须重读**，别指望"我这轮没改那一块"。
- **"两边一致"不等于"两边都对"**（P13 新增 D1）：守护页页头副标题在源码与设计稿里逐字相同，
  所以对照表给了 ✅，这一状态保持了十几轮。它缺的是**第四张卡的名字**——而从前那张卡叫「系统活动」，
  名字含糊到没人拿它去数副标题列了几项。P11c 把它改成「密钥与自启配置的改动时间」之后，
  它和另外三项成了同一类东西，缺口才看得见。**教训**：逐元素对照表测的是"两边像不像"，
  它测不出"两边一起漏了第三方"；**改名会让别的旧账变成可见的缺陷**，所以每改一次名，
  要把引用这个名字的每一处（页头、副标题、设计稿、README、发版说明）一起过一遍。
- **改完文案要问的第二句是"画面上放得下吗"**（P14）：D1 的修法是给副标题补第四段，而 `MMPageHeader`
  的副标题写的是 `.lineLimit(1)` + `.truncationMode(.middle)`——**加长它的后果不是换行、不是溢出、
  不是任何一条测试会红，而是画面上多一个省略号，切掉的正好是句子中段**。单测能钉"段数 == 卡数"，
  钉不住"这一句在最小窗口里还剩多少宽"。所以这一轮两件事都做：① 判据落在结构上
  （`GuardianHeaderContractTests`，并且**跑过否证实验**：删掉第四段 → 4 条里 2 条失败，
  没跑过否证的合同测试和没有合同测试是一回事）；② 排版代价交给照片
  （`Scripts/p14-header-capture.sh`，三档宽度、零夹具，判据只有一句"不许出现 `…`"）。
  量到的余量：**不到三个汉字宽**（1000pt 地板宽度下，照片 2× 估读）——所以"加一段就重跑这一支"是硬规矩，
  不是"反正还放得下"。
- **对照表之外还有第三个表面**（P14）：逐元素对照表量的是"设计稿 ↔ 实现"，而 `docs/website/index.html`
  这类对外文案既不在稿里也不在代码里，**没有任何一张表会替它把关**。P11c 撤下统一日志之后，
  落地页那句"管理登录项，监控系统活动"当场变成假话，而它在改动前 `grep -rn website docs/analysis/` 是
  **0 命中**——从来没被核过。本轮只改了被证伪的两句，其余口号与四个仍是 placeholder 的截图位
  记成待办（`release-readiness.md` §6）。**教训**：撤一项能力或改一个名字时，先问"这句话还在哪些
  我们不比对的地方活着"，把那些地方一次性列进表里，比一处处撞见要便宜。
