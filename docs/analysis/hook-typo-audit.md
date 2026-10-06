# 钩子写错值时的行为审计（P18）

> 一句话：**钩子写错不会让界面报错，只会让照片安静地停在另一档上。**
> 那张"看上去没问题"的截图随后被登记成"某一档已核对"——这是取证里最贵的一类错误，
> 因为它不是失败，是**假通过**。本轮把全仓 `MM_*` 钩子按"值写错会发生什么"分了一遍类，
> 把会换档又不说话的那一类全部收口，并留下一道实机门禁。
>
> 配套：钩子逐条属性看 `hook-ledger.md`（只读性/破坏性），本文只管**失效方式**。
> 数据来自 2026-10-06 现读：`grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' | sort -u` = **52** 个
> 独立变量名（`MM_TRASH_FIXTURE_PROBE` 是测试里探 `/tmp` 守卫的临时 key，运行时钩子 51 个）。

## 0. 结论先行

- **16 个键改前是"静默换档"**：值写错 → 回落到另一档或按未设置处理 → stderr 一行都没有。
  本轮全部改成"回落 + 写一行"，其中 13 个走 MMCore 的 `MMHookValue`（有单测），3 个是本轮收尾补的。
- **1 个是安全洞，不只是取证问题**：`MM_PURGE_FIXTURE_HOME` 的三条越界分支静默返回 nil，
  而它的回落值是 `NSHomeDirectory()`——那一屏每一行都带勾选框和删除按钮。见 §3。
- **3 个键本来就会说话，本轮只是把解析搬进 MMCore**（`MM_OPEN_MODULE`、`MM_APPEARANCE`、`MM_WINDOW_SIZE`）：
  文案一字未改（旧日志要还能对上），改的是"判据能不能被单测钉住"。
- **7 个键 13 处站点是 presence 开关（非空即生效），本轮不动**：它们不会把画面切到另一档，
  代价是**反过来**的失效——`MM_AUTO_SCAN=0` 也是开。§5 记这条边界，别把它当成已收口。
- 核验链三段：MMCore 新增 **22 条**单测（48 → 70）、全仓 **612 个测试 0 失败 1 跳过**
  （`./Scripts/run-all-tests.sh`，2026-10-06 现跑）、实机门禁 **23 档**全绿
  （`Scripts/p18-hook-typo-proof.sh` → `docs/verification/p18-hooks/`，18 张照片 + 逐档原始 stderr）。

## 1. 判据：按"值写错之后画面会变成什么"分四类

分法只看一件事——**错值会不会把画面挪到另一档，而照片上不留下"这是另一档"的痕迹**。
照片是自证不了的：它只画"当前这一屏"，不画"本来该是哪一屏"。

| 类 | 失效方式 | 照片会不会说谎 | 本轮处置 |
| --- | --- | --- | --- |
| **A** | 写错会说话：回落 + stderr 一行（改前就有） | 不会，日志能说清 | 三个键把解析搬进 MMCore，文案不变 |
| **B** | 写错会换档，且一声不响 | **会**，而且拍出来最像"通过" | **16 个键全部收口**（§2） |
| **C** | 非空即生效（presence 开关） | 不会换档，但**写 0 也是开** | 不动，边界写进 §5 |
| **D** | 有值但对不上，另有凭据可核 | 取决于那条凭据 | 逐个记录，不强行归一（§5） |

留痕文案的口径由 `MMHookValue` 统一（`Packages/MMCore/Sources/MMCore/HookValues.swift`）：

- 未设置 / 空串 = 按未设置处理，**生产路径不留痕**（否则每次真机启动都刷一行）；
- 有值但对不上 = 回落默认档 + 写一行，行里必须出现**原样的错值**（报 `sytem` 而不是报 `system`，
  核对的人要能在日志里认出自己敲的那几个字母）；
- 比较前统一 trim + 转小写，所以档位名一律小写；
- **可接受集合由档位表现算**，不写字面量——加了档忘了改文档，这条会在留痕里自己说新话。

## 2. B 类台账：改前怎么静默，改后怎么说

| 键 | 改前的失效方式 | 改后回落到 | 留痕（实机档号） |
| --- | --- | --- | --- |
| `MM_SETTINGS_TAB` | `init?(hookKey:)` 返回 nil → `.general`，无话 | `.general` | 06 |
| `MM_OPEN_TAB`（清理页） | 同上 → `.cache` | `.cache` | 03 |
| `MM_OPEN_TAB`（磁盘页） | 同上 → `.treemap`；视图标题写着 Treemap，钩子只认 `tree`，**写 `treemap` 是最常见的错** | `.tree` | 04 |
| `MM_OPEN_TAB`（优化页） | 同上 → `.duplicates`；`duplicate`（少 s）静默 | `.duplicates` | 09 |
| `MM_UNINSTALL_PANE` | 同上 → `.apps`（`oran` 静默变成"已装应用"） | `.apps` | 07 |
| `MM_DISK_DEPTH` | `Int(...)` + `(1...4).contains` 一把 guard，越界与非数同样静默 | 现值（默认 3） | 08 |
| `MM_DEV_SELECT` | `== "untouched"`，写错=没勾，画面上是"一个都没选"的空合计 | 不勾 | 15 |
| `MM_DEV_SCROLL` | `== "end"`，写错=不滚，底部合计条在首屏外，拍到的是半张表 | 不滚 | 16 |
| `MM_FAILURE_FIXTURE` | `== "protected"`，写错=回执不出现 | 不出现 | 17 |
| `MM_SNAPSHOT_FIXTURE` | 查表失败整块忽略（未知档连"有哪些档"都不说） | 真实读取结果 | 18 |
| `MM_PURGE_FIXTURE_HOME` | 三条越界分支 `return nil` 无话 → 扫真实 home | 真实 home（**危险**，见 §3） | 10、11 |
| `MM_APPS_WATCH_AUTO_SCAN` | `== "1"`，写 `true` 就不跑，画面上是"从没扫过"的卡 | 不跑 | 未单列（同族文案由 15/16/17 钉住） |
| `MM_UNINSTALL_SELF_ECHO` | `== "1"`，写错=不卸 → 自我回声两张卡拍不到 | 不动文件 | 同上 |
| `MM_SHOW_TRASH_CONFIRM` | `== "1"`，写错=面板不弹 | 不弹 | 同上 |
| `MM_DEV_AUTO_CONTINUE` | `Int(raw)` + `(1...3).contains` 一把 guard；写 `3s` 与"没开"同一个样 | `0` = 不自动续扫 | 21 |
| `MM_DEV_ROOT/CONTINUE_BUDGET_SECONDS` | `Double(raw)` 能解析但 `>0` 为假时静默——**`nan` 就在这条上**（`Double("nan")` 解析成功，`nan > 0` 是假的） | 默认预算 | 22 |
| `MM_UNINSTALL_CONFIRM_MODE` | case-sensitive 的 `switch`：`WithResiduals`/`withresidual` 静默变 `appOnly`，弹出来的是另一档面板 | `apponly` | 23 |

后三条（AUTO_CONTINUE、两个预算秒数、CONFIRM_MODE）是本轮收尾时补的：前一批把"档位选择"族收干净之后，
剩的就是这三个形状不同但同样会换档的键。它们不改语义，只把"没说话"改成"说一句"。

## 3. 专项：`MM_PURGE_FIXTURE_HOME` —— 静默回落等于拿用户真项目当夹具

改前三条失败分支都 `return nil`，一行都不写：

1. 值不带 `/tmp/` 前缀（写成了 `~/purge-fixture`、或者少写斜杠）；
2. `realpath` 失败（目录不存在、名字打错）；
3. `/tmp` 下的符号链接解引用之后跳出 `/tmp`（`/tmp/link → /Users/lee`）。

`nil` 之后 `scanHome` 就是真实主目录，而「开发产物」这一屏的**每一行都有勾选框**、
底部就是删除按钮，`MM_DEV_SELECT=untouched` 还会替用户把可回收项整片勾上。
也就是说：一个拼错的夹具路径，产出的不是"一张废片"，而是"一张真实的、可删的、
看起来属于夹具的清单照片"，而它会被登记成"夹具档已核对"。

改后三条各写一行，每一行都明确说出**扫描根将是真实 home**（只说"钩子已忽略"不够：
忽略之后落在哪里才是这条留痕的全部信息量）。另外把 `static var` 改成 `static let`——
`scanHome` 在 `body` 求值里被读到多次，`var` 会让同一行留痕按帧刷屏，
而刷屏的日志和没有日志一样没法核对（同一个坑在本仓踩过第二次）。

核验：10（目录不存在）、11（指向 `/Users`）两档**不出照片**——钩子被拒之后画面就是真实主目录的
项目清单，那种图不该进仓库，而这一档要核的本来就是日志那一行。

## 4. 下沉边界：什么进了 MMCore，什么留在壳层

进 MMCore 的判据只有一条：**这一段能不能在没有 AppKit、没有窗口的情况下判对错**。

- `MMHookValue`：三种形状（档位 `resolve`/`selected`、数字 `resolveInt`/`int`、单 token `resolveFlag`/`flag`）
  + `emit`（留痕的唯一出口，写 stderr——取证脚本都从 stderr 收日志，写别处等于没写）；
- `MMHookKeyed`：档位协议，`MMDestination`、四个 tab/pane 枚举、`ConfirmHookMode` 都 conform 它，
  手写 `init?(hookKey:)` 全部删掉（那五处各写一遍同样的回落，是"三个 tab 共用一个键名"这件事没人统一核对的根因）；
- `MMLaunchHook`：外观两档别名（`light|aqua` / `dark|darkAqua`）与 `900x600` 的解析，纯字符串；
  `NSAppearance.Name` 的映射与 `setContentSize` 留在壳层——那是唯一的 AppKit 触点。

留在壳层的：`@MainActor` 的启动时序（`onAppear` 时窗口还没上屏）、窗口过滤谓词、
`MM_WINDOW_SIZE` 那条"回读夹取后的真实尺寸"的 `asyncAfter 0.3`（内容区有 `minWidth` 地板，
就地读会拿到没夹过的 900，那正是"看着真、来源错"的最小窗口证据）。
壳层仍然没有测试 target（可执行 target 带 `@main`，SwiftPM 测不了），所以本轮的写法是
**把判据挪出壳层、把留痕文案变成纯函数**，而不是给壳层硬造一个测试目标。

## 5. 本轮没动的，以及为什么

- **C 类 7 个键 13 处站点**（2026-10-06 现读：
  `grep -rnE '(environment|env)\["MM_[A-Z_0-9]+"\] != nil' Packages Sources --include='*.swift' | grep -v Tests` 命中 15 行，
  其中 `MM_SHOW_TOAST`（D 类）与 `MM_TRASH_FIXTURE_DIR`（`fixtureEnvironmentValue` 的拒绝分支）不归 C 类，剩下 7 键 13 处；
  下面括号里的数字就是每个键的站点数）：`MM_AUTO_SCAN`（2）、`MM_SHOW_CONFIRM`（5，跨清理/系统分析/磁盘三页）、
  `MM_EXPAND_CATEGORIES`、`MM_DEV_EXPAND`（2）、`MM_DEV_CONFIRM`、`MM_SHOW_SETTINGS`、`MM_PROBE_WINDOW`，
  全是 `env[key] != nil`。它们的失效方向是"写了就当开"，`MM_AUTO_SCAN=0` 也会自动扫；
  但**画面不会假装是另一档**——面板没弹、没展开、没扫，照片上就是那个样子。
  统一成 `flag(token: "1")` 技术上可行（现仓所有脚本都只传 `1`），本轮没做，
  因为它改的是 13 处现网调用形态而收益只是"少一种可能的误写"，排在 B 类之后。
  **这条要记着**：谁动它，就顺手给 `MM_SHOW_CONFIRM` 那族加一档门禁（它是 5 处站点里最容易写错的）。
- **`MM_SHOW_TOAST`**：presence + 特殊值 `permanent`，且成功路径自己会写"画出的是哪一条回执"
  （带借来的数字与"没有删除/没有移动任何东西"），日志已经分得开"画出的是哪档"。
- **`MM_TRASH_FIXTURE_DIR` / `MM_TRASH_SCAN_HOME` / `MM_INSTALLER_FIXTURE_DIR` / `MM_ORPHAN_FIXTURE_HOME` /
  `MM_DISK_SCAN` / `MM_DISK_SELECT` / `MM_DISK_RESCAN` 的越界文案**：改前就会说话（A 类），
  措辞是各自手写的"忽略该钩子"，与 `MMHookValue` 那三句不同族。**没统一措辞**是本轮的取舍：
  统一要动四个包的共用工具函数（`TrashWatcher.fixtureEnvironmentValue`），收益是日志好 grep，
  风险是把已经跑过的取证脚本的判据改掉——门禁脚本的 `TRACE` 集合两种措辞都收了（§6）。
- **夹具表那一批**（`MM_GUARDIAN_*` / `MM_TCC_FIXTURE` / `MM_MONITOR_*` / `MM_OPTIMIZER_FIXTURE` /
  `MM_GUARDIAN_CARDS` / `MM_MONITOR_CARDS`）：形状是"逗号多档 + 键值对"，
  各自的包内已有 `parse` + `rejected` + 单测（`GuardianFixtureHookTests`、`OptimizerFixtureHookTests` 等），
  不属于 `MMHookValue` 的三种形状，硬塞会把它们那套更细的词法削平。

## 6. 核验链

1. **纯函数单测**：`Packages/MMCore/Tests/MMCoreTests/HookValueTests.swift`（15 条）+
   `LaunchHookTests.swift`（7 条）。其中一条是 `testSelectedWritesTheNoteToStderr`：
   用 `dup`/`dup2` 把 fd 2 临时换成临时文件，跑一次 `MMHookValue.selected`，再读那个文件——
   钉的是"文案生成对了"**并且**"真的落到 stderr"。只看前者，`emit` 被改成 `print` 到 stdout 也测不出来。
2. **全仓测试**：`./Scripts/run-all-tests.sh` → 612 个测试，0 失败，1 跳过；MMCore 48 → 70。
3. **实机门禁**：`Scripts/p18-hook-typo-proof.sh <app>`，23 档逐条"故意写错"，
   判据是 stderr 那一行（不是画面），退出码非 0 即门禁红。证据在 `docs/verification/p18-hooks/`：
   `capture.log`（归因头 + 每档 env/expect/windowid/result）、`raw/<档名>.log`（逐档原始 stderr）、
   18 张照片。**照片里带真机侧栏的卷名与剩余百分比**（这台机器改不掉，见 `website-audit.md` §3 同条口径），
   而 10/11/13/21/22 五档被显式标了 `-n`：钩子被拒之后回落的是真实目录，那种画面不入仓库。
   **P19 又在发版候选产物上重跑了一遍**（`docs/verification/p19-hooks/`，同样 23 档全绿 / 18 张），
   归因头从此分两行：`# repo:` 是跑脚本的那棵树，`# app-repo:` 是被测二进制打包时的那棵树
   （读 `Info.plist` 的 `MMGitCommit`，由 `make-app.sh` 写入）。P18 这一跑的产物是 `83aaf86-dirty`，
   而当时那两行都还不存在——这正是 P19 补它的原因（`release-readiness.md` §7.10）。
4. **脚本自己的两处教训**（都写进了脚本文本）：
   - `ONLY=1[348]` 看着能匹配三档，实际一档都不匹配，而"不匹配"是**静默**的——脚本照样退出 0，
     只是核对了 0 档。改成显式逗号列表 + `checked == 0` 直接失败：门禁工具最坏的失效是
     "报错的形态和通过一样"。
   - `ONLY` 局部重跑以前会先 `rm` 掉整个证据目录的照片与原始日志，等于为了补一档把
     其余各档的证据删了。现在局部重跑写自己的 `capture-partial.log`，一个字不碰既有证据。

## 7. 复发判据（以后加钩子的人过这三条）

1. **档位选择**：枚举 conform `MMHookKeyed`，读值只用 `MMHookValue.selected`。
   不要写 `switch raw { ... default: fallback }`——`default` 就是那条静默的缝。
2. **数字 / token**：`resolveInt`（有上下界）或 `flag`（单 token）。
   无上界的（秒数、字节阈值）保留原解析，但**必须**补一行 `MMHookValue.emit`，
   并说清回落后实际生效的是哪个默认值（§2 倒数第二行那两个键就是这条）。
3. **新增或改动任何留痕文案**：`Scripts/p18-hook-typo-proof.sh` 加一档，期望子串写
   **"回落后那一档"的完整句子**，跑一遍；然后把这条命令当作发版门禁的一部分
   （它和 `p16-citation-audit.sh` 一样是退出码型工具）。

判据不回到照片上。`P6.6` 那轮的结论在这里同样成立：**"钩子存在"和"钩子生效"是两件事，
"钩子生效"和"钩子说它生效了"还是两件事**——这一族只补第三件事，前两件事归 `hook-ledger.md` 与
各档 fidelity 文档的哨兵值核对（`md5 -q *.png | sort | uniq -d`）。
**那把哨兵只在同一批内有意义**（它查的是"两档拍到同一张图"）：P19 现量，`p18-hooks/` 与 `p19-hooks/`
那 18 对同名照片里 **17 对逐字节不同、只有 `07-pane-typo.png` 相同**，因为侧栏卷名与占用、CPU 环形进度、
右下角"数据更新于"本来每跑必变——跨批次不同不代表变化，跨批次相同也不代表重复。
