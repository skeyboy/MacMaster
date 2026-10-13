# MacMaster

原生 macOS 的清理 / 卸载 / 磁盘分析 / 监控 / 守护 / 优化工具。Swift + SwiftUI，
SwiftPM 多包结构，无第三方依赖，**无任何网络代码**。

- 系统要求：**macOS 14.0+**（`Package.swift` 的 `.macOS(.v14)`，产物 `Info.plist` 的 `LSMinimumSystemVersion=14.0`）
- 工具链：**构建实测下限是 Xcode 26 / Swift 6.3 这一档**，不是清单里那行版本号。`Package.swift` 第一行是
  swift-tools-version 5.9，但**5.9/5.10 那批工具链实测编不过**：CI 曾在 Xcode 15.4（Swift 5.10）镜像上跑，
  磁盘页 `Packages/MMDisk/Sources/MMDisk/MMDisk.swift:1432-1437` 的 `scanDirectory()` 报三处 `await`/MainActor 错误
  （三档读数都出自当场跑的构建日志，"为什么不改那三行"记在 `docs/analysis/release-readiness.md` §7.20 与 §8 的工具链那一档）。
  实测绿的两个档：Xcode 26.6 / Swift 6.3.3（CI 现用 `macos-latest`）与作者机 Xcode 27.0 / Swift 6.4（全部取证产物出自后一个）。
  **中间那些档（16.x–25.x）从没测过，别假设能编。** swift-tools-version 5.9 只是清单声明的下限，够不着这一条。
- 产物要求的 macOS 与构建机是哪个 macOS **无关**（上一条只讲构建）：那由 `Package.swift` 的 `.macOS(.v14)` 与 plist 的 `LSMinimumSystemVersion=14.0` 定
- 界面语言：简体中文单语（设置页那个语言选择器是**禁用状态**，因为界面文案还没接入多语言，切了不改变任何东西）
- 许可：**尚未选择**——仓库里没有 LICENSE 文件，所以本文也不声称任何许可。详见 `docs/analysis/release-readiness.md` §2.3

## 构建与运行

SPM 只产出裸可执行文件，**裸文件看不到窗口、也没有正确的 Bundle Identifier 与 TCC 归属**，
所以必须用打包脚本：

```bash
./Scripts/make-app.sh                       # → build/MacMaster.app（Release + ad-hoc 签名）
open build/MacMaster.app
```

并发验证时用 `-o/-s` 隔离，否则后构建会把别人正在跑的实例的二进制换掉，
截图就变成"看着是真的、其实来自别人的代码"的证据：

```bash
VERSION=1.0.0 BUILD=1 ./Scripts/make-app.sh -o /tmp/mm-app-x -s /tmp/mm-scratch-x
```

**版本号只有一个真源**：上面那条 `VERSION=/BUILD=`。设置页「关于」读的是 bundle 的
`Info.plist`，而那份 plist 是 `make-app.sh` 写的——不要去脚本里改字面量。

**产物自带出处**（P19 起）：`make-app.sh` 往同一份 plist 写 `MMGitCommit`（工作区不干净时后缀 `-dirty`）。
**P23 起还写 `MMSourceDigest`**——那 **99** 个编译输入（**P35b 现数：已跟踪 99 + 未跟踪 0**；
P34b 那一读是 96 + 2，因为那两个新源文件当天还没 `git add`；P35b 又加了一个 `Packages/MMCore/Sources/MMCore/VolumeRoots.swift`，
它当日就进了索引；`Sources` / 九个包的 `Sources` 与 `Package.swift` /
根 `Package.swift` / `Resources/AppIcon.icns`，**不含测试源码**）的**内容**哈希，前缀拼 HEAD 短 sha。
为什么要它：`-dirty` 只说"工作区有改动"，不说改了哪个文件哪一行，
而 P22 撞的那一次（搬动一个私有辅助函数的位置）恰好是 commit、脏净态与画面**三条线都看不见**的改动。
取证脚本起跑前先比这个指纹，**不同源就 exit 4、一张都不出**，
配方一份在 `Scripts/mm-provenance.sh`，构建侧与取证侧共用（两边各算一遍等于没门禁）。
**接了这道门禁的出片脚本现读 14 支**（**P35b 现数**：`p7-release-check`、`p17-website-capture`、`p18-hook-typo-proof`、
`p22-disk-skip-capture`、`p4-sweep`、`p68-dev-capture`、`p68-disk-capture`、`p29-settings-capture`、
`p31-running-capture`、`p32-steam-capture`、`p32b-steam-launcher-capture`、`p33b-nesting-capture`、
`p34b-prefs-capture`、`p35b-volumes-capture`；
判据是 `comm -12` 比"含 screencapture"与"含 mm_provenance_check"两份清单——**单独 `grep -l mm_provenance_check` 会多算三支**：
`mm-provenance.sh` 自己是定义处、`p23-provenance-probe.sh` 与 `p29-settings-pane-probe.sh` 是探针，都不出片），
分母是 34 支含 `screencapture` 的脚本，**其余 20 支是历史轮次的夹具，没接**（代价与理由见 §7.14 残余。
**这一格从前写的是 7 / 27 / 20**：那是 P23 那一读，P26 推到 7 / 20 之后每一轮的新出片脚本都接了门禁、
却没有人回头改这一格——**它是 §0 那条"活数要挂轮次记账"规矩的第六个副本面，本轮现读才跟上**；
分子从 7 涨到 14 而残格仍是 20，是因为涨的全是"新写的脚本自己就接了"，没有一支旧夹具被补上）。
**顺序因此是钉死的：提交 → `make-app.sh` → 出片脚本**。指纹前缀是 HEAD 短 sha，
所以一次提交本身就让提交前那份产物失配（内容没变也一样）——这不是麻烦，是它该管的那件事：
照片出自哪一格树，日志里那一行 `tree=` 会写明。
**这条顺序 P24 第一次照做**（`docs/verification/p24-v1/`，产物 `MMGitCommit=b4f9e1f` 不带 `-dirty`），
两支只验过"拒"的脚本（`p17-website-capture` / `p18-hook-typo-proof`）也各有一份**放行**日志在
`docs/verification/p24-gate-pass/`——只验一条边的门禁，另一条边要等下一轮才看得见它通不通。
**P25 第二次照做，而且是第一次带着源码改动照做**（`docs/verification/p25-v1/`）：这一遍的产物
`MMGitCommit=fc2a7b2-dirty` 而 `MMSourceDigest=fc2a7b2+e3b0c442`——**这两串量的是不同的东西**，
前者是整棵树的脏净态（本轮构建时文档正在改），后者只量 92 个编译输入；
**照片与二进制同源看的是 `# digest:` 那一行，不是 plist 上那个短 sha 后缀。**
**P26 第三次照做，而且一轮里走了四遍**（`cae60fe` → `59e653b` → `6aa897e` → `17f4371`，
照片分三批落地共 19 份日志，其中 17 份带 `# digest:` 且逐字对上自己那一份产物；那两份没有的，见下面那条边界）：
这一轮撞出来的是一条**从前只写在注释里、没人真跑过的性质**——指纹前缀是 HEAD 短 sha，
所以**一个只改 `Scripts/` 的提交**（`.sh` 不是编译输入、内容指纹后半截一个字没变）
也会让刚构建好的那份产物在门禁眼里失配。P26 正是在第三次提交之后被这一条挡了一次，
重新构建、把最终那三族照片重拍了一遍才入库。**这不是误伤**：产物身份本来就该跟着它所在的那格 commit 走，
而代价（多构建一次、多重拍一批）要如实算在"照做一遍"的成本里。
顺带这一轮也**撞见了门禁的一条边界**：给脚本补门禁只从装上那一刻起生效，
已经入库的历史证据族补不回来——`p26-dev-min/`、`p26-dev-worst/` 那两族就是加门禁之前那一版脚本拍的，
日志里没有 `# digest:`，那一版产物也早就不在了（§7.17）。
**引用门禁也有同一形状的边界，P26 把它量出来了**：`./Scripts/p16-citation-audit.sh` 那四条硬判据问的是
"文件在不在、行号越不越界、那几行空不空、同后缀歧不歧"，**没有一条问"这一行指的是不是当初指的那一行"**。
所以本轮改完两个源文件、全仓实漂 **88 条带文件名的行号引用**，门禁只报回 **2 条**——
那两条被抓到是因为恰好漂到了空行上，余下 86 条漂过去的地方挨着真代码、读起来仍然像话。
**结论不是"门禁没用"，是它管不到这一层**：改过源码行数的那一轮，必须自己现读对差把旧锚点重指一遍
（逐条对法与完整记账见 `docs/analysis/header-truncation-audit.md` §9），别等它报。
十五遍发版核验的产物版本号**从前十四遍逐字相同，第十五遍起分成两档**（现读：按 1.0.0 那一对键数仍是
**47 份 .log**，一条不多——因为本轮新那三份读的不是 1.0.0；按 1.0.1 那一对键数是 **3 份**，
逐字就是 `docs/verification/p35b-clone/` 那三份照片日志）：
`grep -rl "CFBundleShortVersionString=1.0.0 CFBundleVersion=1" docs/verification --include='*.log' | wc -l`，
**这 47 份里只有 42 份是"核验那十四遍"的产物**（§10 第 3 步那 14 个目录 × 每族三份日志；
另一把尺子 `grep -h "^# plist:" docs/verification/{v1.0.0,p12-v1,p13-v1,p14-v1,p15-v1,p19-v1,p20-clone,p21-v1,p22-v1,p23-v1,p24-v1,p25-v1,p27-clone,p30-clone,p35b-clone}/*.log` 现读 **45 行** = 15 个目录 × 3，其中 42 行读 1.0.0、3 行读 1.0.1），
多出来的 5 份分解是 `p10-icon/` 3——同一支 `p7-release-check.sh` 拍的图标核验，没算进"遍"里，
加 P28 那一次 CI 与本地打包各 1（`p28-ci/green-run.log`、`p28-package/package.log`）；
**这一格从本轮起有两个版本号，凡按那一对键数日志的命令都要先说要数哪一档**（"数没动"不再等于"没有新证据"）；
没这两键就分不出哪一份出自哪一次改动；
取证日志里的 `# repo:` 是**跑脚本的那棵树**，`# app-repo:` 才是**被测二进制那棵树**，两行不一样是常态
（改完脚本重跑旧产物时必然不一样），`# digest:` 那一行则是**内容**层面的对账（`tree=` 与 `app=`）。

**应用图标是画出来的**，不是一张来路不明的 png：`./Scripts/make-icon.sh` 跑
`Scripts/make-icon.swift` 生成十档 iconset → `iconutil` 打成 `Resources/AppIcon.icns`，
然后**反向解一次**核对十档齐全（少一档时 Dock 缩到 16pt 会拿大图硬缩，而 plist 与签名一切正常、
没有任何一处会报错，所以判据只能是档数与字节数）。`make-app.sh` 看见这个文件才写
`CFBundleIconFile`——键在而文件没了，比"没这一键"更难查。

## 测试

```bash
./Scripts/run-all-tests.sh     # 九个包逐个 swift test，逐包一行结论 + 总计
./Scripts/clone-references.sh  # 参考仓库在不在、HEAD 对不对得上钉住的 commit（只读；--fetch 才联网）
./Scripts/p16-citation-audit.sh  # 入库文档里每处 `文件:行号` 落盘验一遍（纯读，约 40 秒）
./Scripts/package-app.sh       # 把 build/MacMaster.app 打成 zip + dmg 并自验（先对 plist 的版本号）
./Scripts/p28-cpu-ticks-probe.sh  # 真机探针：host_cpu_load_info 的累计 tick 会不会给零跨度
```

现测（**2026-10-12，P35b 在作者工作树上重跑（`27db42a-dirty`、指纹 `27db42a+d01abc46`）；上一读是同日的 P34b，再上一读是同日的 P33b，再往前是 2026-10-10 的 P32b，再往前是同日的 P31a，再往前是 2026-10-09 P30 那棵 `git clone` 的树**）：
**764 个测试、0 失败、1 跳过**（P11 那遍是 581，P11c 撤下统一日志那一族时
删掉 10 条它的单测、新增 8 条活动卡文案合同单测 → 579；P14 加 4 条页头副标题合同单测 → 583；
P15 加 7 条子进程读法判据（`CommandRunnerPipeTests` 5 + `LaunchctlRunnerTests` 1 + `SystemSpaceReportTests` 1）→ 590；
**P18 加 22 条钩子判定单测**（`HookValueTests` 15 + `LaunchHookTests` 7，全在 MMCore）→ 612；
**P21 加 9 条删除闸门口径判据**（`DeletionGuardTests` +3：`/dev`、`/private`、"字面问与全量问不许给两种答案"；
`DiskRiskTests` 全新 6 条：界面标签不许和闸门唱反调）→ 621；
**P22 加 1 条跳过披露判据**（`DiskScannerHierarchyTests.testNestedProtectedSkipIsDisclosed`：
受保护目录跳过发生在每一层，披露也必须覆盖每一层）→ 622；
**P25 加 7 条清理页副标题判据**（`CleanerHeaderContractTests`：段序按优先级排、"另有 N 只读"不许被中间截断吃掉、
时间戳不带年份这一长度决定）；**P26 加 4 条磁盘页页头判据**（`DiskHeaderContractTests`：单位必须贴着数字待在尾格、
占用待在头格、副标题必须正好三段且**不许出现秒数**）→ 633；
**P29 加 8 条设置页判据**（`MMSettingsPaneTests` 4 条钉深链拼接"只许有一个 scheme"、`NotificationStatusTests` 4 条钉
通知授权状态的文案与判据，两包各 +4）→ 641——这两族钉的都是包里的纯函数，
壳层那一条都没被它们覆盖（下一句"零测试"的口径不变）。
**P31 加 27 条卸载页「正在运行」判据**（`RunningAppProbeTests` 13 条钉纯判据：`AppRunningState.resolve`
只吃快照值类型，含一条"`isUnattributable` 要**包名与位置同时缺**才算"的否证；
`RunningAppStatePresentationTests` 10 条钉四档各说哪句话，含一条否证——「两档都算『正在运行』」这句
在"两个进程、同一档"的画面上不许出现；`UninstallerRunningStateModelTests` 4 条钉"缺席 = 一个字都不说"）
→ **668**，全在 MMUninstaller 那一包。
**P32b 在同一个包里加 38 条**（`SteamLauncherProbeTests` 24 条钉判定与读取两层：两条入口按优先级试、
shebang 只收 `sh/bash/zsh/env`、动词只收 `run|rungameid|launch`、4096 字节成本闸门，含一条"名字里带路径分隔符的
`CFBundleExecutable` 直接不算"和一条"读取永远不离开 `Contents/MacOS`"；`SteamLauncherPresentationTests` 5 条
钉界面那三样元素各自的出现/不出现，其中一条禁词表把"依据那句不许说证据之外的量"钉死——`GB`、`MB`、「游戏在」
都不许出现；`ResidualCollectorSteamTests` 5 条钉那句反向提醒**只挂 `applicationSupport` 那一行、
只在直接子项里有 `steamapps` 时挂、同一条路径只挂一次**；`ResidualSensitivityTests` 6 → 10 的 +4 条钉新钩子
`MM_UNINSTALL_SENSITIVITY`：档位名必须与选择器 `allCases` 同源，写错值回落 strict 且**必须在 stderr 留痕**）
→ **706**，同样全在 MMUninstaller 那一包。
**P33b 在同一个包里加 14 条**（`ResidualOwnershipReviewTests`：残留走到默认勾选之前先看一次归属——
祖先目录被**另一个已安装应用**主张、或同层里那一个更像主人的候选不是本应用时，整条降级为「谨慎」并默认不勾选，
主人名写进证据行；两条线索各自有出现/不出现两条判据，外加一条否证 `testStrictTierHasNoContainmentHit`：
strict 档没有包含命中 ⇒ 复核一轮都不跑）→ **720**，还是全在 MMUninstaller 那一包。
**P34b 加 17 条，一格都没动别的包**（`PreferencesAuditTests` 全新 13 条：偏好文件四态判据——空文件、读不出来的 plist、
解析成功但根不是字典、以及"系统拒绝读取"这一态必须和"它坏了"分成两栏说；再加时间预算截断那两对
（`testBudgetTruncatesAndCountsTheRemaining` / `testGenerousBudgetScansEverything`）与一条文案不许过度声称
（`testCopyNeverOverclaims`）；`OptimizerFixtureHookTests` 14 → 18 的 +4 条全钉新增的 `prefs:*` 那一族——
档位名拼错要整支钩子作废、四档各有各的形状、夹具落地后真实扫描后到不许把它覆盖掉）→ **737**。
**P35b 加 27 条，两包各一笔**（`VolumeRootsTests` 全新 19 条在 MMCore：候选根那四条规则——可浏览、有总容量、
按**容量对**去重、使用率降序且读不到可用的排最后——每一条都能在单测里喂合成快照跑完，外加一条钉住夹具留痕行
必须**说出用的是哪一档**；`DiskVolumeBadgeCopy` 8 条在 MMDisk：「还有 N 卷」的 N 是**候选根数 − 1**、
1 卷与 0 卷两档必须沉默、读不到才说"这里不猜数字"、禁语表把"块硬盘""没有其他卷""只有 1 卷""0 卷"钉死）
→ **764**。
**逐包求和 = 764**（**96** / 17 / 117 / 25 / **200** / **85**（含 1 跳过）/ 57 / 96 / 71），这一条自 P11c 起每轮都当自证用。
**P25 那一跑里 MMCore 与 MMDisk 都是 73、撞过一格，P26 MMDisk 走到 77 之后撞车解开**——
**而 P29 把它们撞回来了**：MMCore 也走到 77，于是这一跑里"77"同时是 MMCore 和 MMDisk。
**P35b 换了撞车的一对**：MMCore 96 与 **MMGuardian** 96，MMDisk 走到 85 之后反而和 MMCore 解开了——
所以这条自证**要按包名读**这件事永远有效，不会哪一轮"解开"之后就再也不必念：96 出现两次，
"某个数出现过没有"这种读法这一次照样会数错总数。
**这一轮多出来的一条教训跟这 4 条判据有关**：第一档修复（只调段序）在这 4 条下是全绿的，
实拍却把"扫描用时"切成一半——真值 0.1 s 在画面上成了 1 s。**单测钉得住段序，钉不住"这一句在 1000 pt 放不放得下"**，
后者只有照片（§7.17）。
**P20 那遍是在一次干净 `git clone` 出来的树上跑的**，那一跑九个包逐包数一个不差
（70 / 17 / 117 / 18 / 121 / 66 / 53 / 96 / 54——MMCore 的 +3 与 MMDisk 的 +6 是 P21 那一跑之后才有的，
MMDisk 再 +1 是 P22 之后才有的）。
**P27 是第二份从克隆树归档的测试结论行**（`docs/verification/p27-citations/run-all-tests.log`，
九格 73 / 17 / 117 / 25 / 121 / 77 / 53 / 96 / 54，与 P26 那一份一格不差），
而它跟 P20 那一跑的区别是**这一遍带着同源门禁**：产物 plist 里的 `MMSourceDigest` 与那棵树现读的指纹
逐字相等（`fd2ec86+e3b0c442`），"照片出自哪一棵树"由日志头那一行自己说，不再靠人记得顺序（§7.18）。不要手敲 `swift test | tail -4`——
SwiftPM 的结论行有两种形态，那样会把 MMCore 的 73 个测试显示成"跑了 0 个"
（原因与解析规则写在脚本头部注释里）。

**壳层 `Sources/MacMaster` 没有测试目标**（根 `Package.swift` 只有一个 `.executableTarget`），
所以导航、窗口、设置页绑定这三件事目前只有实机照片兜，没有单测。
**P18 补的是这一格的另一半**：钩子取值"写错了算哪一档"这类判定本来也住在壳里（`MM_OPEN_MODULE`
的目的地、`MM_APPEARANCE`、`MM_WINDOW_SIZE`），现在解析与留痕文案全在 `Packages/MMCore`
（`HookValues.swift`，`HookValueTests` + `LaunchHookTests` 共 22 条），壳层只剩"把结果交给 AppKit"。
**能单测的那一半下沉了，"零测试目标"这四个字没变**——窗口有没有真被改大，仍然只有照片知道。

## 七个页面与九个包

| 页面 | 包 | 它实际做什么 |
| --- | --- | --- |
| 概览 | 壳层 + 各包 | 实时采样（CPU/内存/磁盘 IO/卷）、存储构成堆叠条、可释放估算。页上的「开始清理」按钮**只做跳转** |
| 系统清理 | `MMCleaner` + `MMFileScanner` | 按四个类别勾选扫缓存/日志/临时项，逐类风险分级，只读分类不给删除入口 |
| 开发产物 | `MMCleaner` | `node_modules`/`build` 这类项目产物，含"截断根分批续扫"与在用/受保护判定 |
| 应用卸载 | `MMUninstaller` | 残留扫描、安装包归属、Homebrew/MAS 来源识别、废纸篓与 `/Applications` 装卸监听、卸载前发现"该应用正在运行"（只提示，不代你退出或结束进程） |
| 磁盘分析 | `MMDisk` | treemap 下钻 + 标记批量移除（回收 / 永久删除两条路径） |
| 系统监控 | `MMMonitor` | 菜单栏指标 + SMC 温度/风扇 + 进程列表；IOKit 读不到时界面明说读不到 |
| 隐私守护 | `MMGuardian` | 摄像头/麦克风占用、TCC 授权只读视图、登录项管理、密钥与自启配置的改动时间（只读 mtime） |
| 优化 | `MMOptimizer` | 重复文件（SHA-256）、浏览器缓存、开发工具占用、系统状态 |
| 设置 | `MMCore` + 壳层 | 18 项持久化设置 + 关于页 |

包结构：`Packages/MMCore`（设置、删除闸门、台账、导航、**全站唯一的系统命令入口 `CommandRunner`**）、`MMUI`（设计令牌与共享组件）、
`MMFileScanner`（遍历与各类扫描器）是**三个共享层**，其余六个是功能模块。
**功能模块之间互不依赖**——现读全仓 `^import MM` 只有 `MMCore`/`MMUI`/`MMFileScanner` 三种命中，
六个功能模块一个也没 import 过另一个功能模块。跨页跳转因此走 `NotificationCenter`
（`Packages/MMCore/Sources/MMCore/Navigation.swift`）而不是直接调对方。

## 权限与隐私

**会读的**：`~/Library/Caches`、`~/Library/Logs`、`~/Library/Containers/*/Data/Library/Caches`、
per-user 的 `getconf DARWIN_USER_CACHE_DIR`、系统级 `/Library/Caches` 与 `/Library/Logs`、
`~/Library/Application Support/MobileSync/Backup`（只列体积，不给删除）、`/Applications`、`~/.Trash`、
`/var/db/receipts`（安装包收据）、Homebrew 账本。
重复文件检测会**读文件内容**算哈希（先头尾采样，命中候选才整文件读）。
浏览器那几行只读**缓存目录**，不读 History / Cookies / 密码库。
守护页那张「密钥与自启配置的改动时间」只对 `~/.ssh`、`~/.gnupg`、`~/Library/Keychains` 三个目录
和用户 `~/Library/LaunchAgents` 里的 `.plist` 问一次 **mtime**（`attributesOfItem` + 列目录名），
**不读这些目录里的任何文件内容**，也不读系统统一日志。

**不再读的**（P11c，2026-10-05）：这一版**不执行 `/usr/bin/log show`**。从前守护页有一族"最近活动"
是拿 `eventMessage contains "login" OR contains "auth"` 去过滤统一日志的，实测八档谓词没有一档能同时做到
低噪、可读、切题（命中的头名常是别的过程的日志正文），所以整族撤下——判据与量表见
`docs/analysis/fidelity-guardian.md` §6.7。**这也意味着发版说明里可以少写一项读取来源。**

**会写的**（一共四类）：
1. `~/Library/Preferences/com.macmaster.app` —— 设置项与清理页排除名单。
2. `~/Library/Application Support/MacMaster/trash-history.json` —— 删除台账，**唯一一份记录了用户文件路径的磁盘文件**，存在的意义就是跨启动撤回。
3. 系统登录项注册/注销（`SMAppService.mainApp`）。
4. 删除本身：默认 `FileManager.trashItem` 移入废纸篓；永久删除只在磁盘页，且必须勾选确认。

**不会做的**：不联网、不遥测、不上传任何数据。全仓 `URLSession` / `NWConnection` /
`Socket` / `Reachability` **零命中**（本文每条数字都可以现跑复核，见 `docs/analysis/release-readiness.md` §1）。
系统授权弹窗只有一个：菜单栏监控的通知权限（`UNUserNotificationCenter`，`.alert,.sound`）。
摄像头/麦克风只做设备枚举、不建采集会话，因此不触发 TCC 弹窗。

**要你手动给的**：隐私守护页读 `TCC.db`（**只读**，`SQLITE_OPEN_READONLY`）来判断
"哪些 app 拿过麦克风/摄像头"。没有完全磁盘访问就**读不到**，界面会直接说需要 FDA 并给「打开系统设置」，
不会把"读不到"伪装成"没有应用持有权限"。

## 取证体系（这套仓库为什么长这样）

界面能不能信，靠照片而不是靠肉眼读代码。三种注入手法 + 一条硬红线：

- **`MM_*` 环境变量钩子**（**55** 个名字，运行时 54 个；**P35b 现数**，逐名台账见 `docs/analysis/hook-ledger.md` §0——
  多出来的那一个是 `MM_TRASH_FIXTURE_PROBE`，它只在测试里探 `/tmp` 守卫，不是运行时钩子。
  从 52 走到 55 的三笔是 `MM_DUMP_MENUS`（P29）、`MM_UNINSTALL_SENSITIVITY`（P32b，当时漏登记、P35b 补）、
  `MM_VOLUME_FIXTURE`（P35b）。
  记账规矩：**这一格每加一个键都要回来改**，它是 §0 那条"活数"系列的又一个副本面）：把某一态的数据喂进页面。
  逐条只读性与是否可能触发破坏流程，记在 `docs/analysis/hook-ledger.md`。
- **`/tmp` 夹具目录**：钩子只认 `/tmp` 之下的路径，越界直接忽略并写 stderr——
  所以夹具脚本（`Scripts/*-fixture.sh`）造的东西永远碰不到真实用户文件。
- **`defaults write com.macmaster.app`**：改的是**真实持久化设置**，用于"页面自己会读设置"的那一类态
  （比如把清理页四个开关全关）。代价是这条手段会在你机器上留下状态，所以取证脚本一律 `trap restore EXIT`。
- **真实负载**：压 CPU、装满废纸篓这类只能等真数的态。
- **硬红线：不发合成鼠标/键盘事件。** 原生 UI 的合成点击会逃逸到你的其它应用。
  截图一律 `按 pid 找自己窗口 → screencapture -o -x -l<windowid>`（`Scripts/window-ids.swift`）。

照片与逐屏还原度判定在 `docs/verification/`（按轮次分目录）与 `docs/analysis/fidelity-*.md`。
设计稿在 `docs/design-system/screens/`，令牌在 `docs/design-system/`。
对外文案在 `docs/website/`：它**不进产物**，但每一句主张都对着实现核过一遍（判定表 `docs/analysis/website-audit.md`），
那四张图是 `Scripts/p17-website-capture.sh` 的夹具档实拍——**画面上侧栏那条卷名与占用百分比、
磁盘页的「卷可用」不在夹具覆盖范围内**，是拍摄那台机器的真实状态，页面上把这句明写了。

## 已知的坑（别再踩一遍）

- 有 5 个**空目录**git 不跟踪、`git status` 也看不见：
  `MacMaster/`、`MacMasterHelper/Sources/MacMasterHelper/`、`MacMasterWidgets/Sources/MacMasterWidgets/`、
  `docs/verification/mmguardian/`、`docs/verification/shell/`。前两个是**没落地的 helper/widget 骨架**，
  现在没有任何代码在里面。
- `docs/github-references/`、`docs/Mole/`、`docs/lemon-cleaner/` 在 `.gitignore` 里（各自带独立 `.git` 与许可）。
  多份分析文档按这些路径引了第三方源码位置，**clone 之后那些引用是断链**。
  取法写在 `docs/analysis/reference-repos.md`（七个仓库的 URL + 本轮钉住的 commit + 各自 `git ls-files` 条数），
  照它 clone 一次，那 57 条引用就都能打开。为什么这些目录**故意不入库**：它们是 GPL /
  Apache-2.0+Commons Clause 的第三方仓库，本项目只读、不转发。
- 入库文档里每一处 `文件:行号` 引用由 `./Scripts/p16-citation-audit.sh` 逐条落盘验一遍
  （四道硬判据不过就 exit 1；第五道"符号面"只提示不当门）。跑一次约 40 秒，纯读，不改任何东西。
  改过 `docs/` 下任何 .md 之后请跑一次——引用会像代码一样漂，而且不报错。
  **但它只扫 `git ls-files`**：一份还没 `git add` 的新文档在这道门上等于不存在，报告里的
  `# docs scanned:` 两个数会一起变小，而不是打Warning（P18 前半段就是这样跑过一整轮 32/32，
  而实际入库文档已是 33 份）。所以顺序是**先 add 再跑**。
- **这道门在干净克隆里跑不过，而且不该跑得过**（P20，2026-10-06）：那 57 条指向参考仓库的引用
  在 `.gitignore` 排掉的目录里，clone 之后它们不存在，脚本判"两头都不到"→ exit 1。
  取回它们一条命令：`./Scripts/clone-references.sh --fetch`（默认不带 `--fetch` 只报状态，联网才发生）。
  这一支脚本**不另存一份 commit 清单**，它逐行现读 `docs/analysis/reference-repos.md` §2 那张表——
  钉住的 commit 一旦有两份，就会有一份先漂。P20 之前更糟：干净克隆里它连报告都没有，
  直接在 `for d in docs/github-references/*` 上撞死（zsh 默认 glob 抽不到东西是**报错**而不是空，
  而 `set -e` 让整条脚本当场退出）——**"参考仓库没克隆时走这一支"那段降级逻辑因此从没被跑到过**。
  修好之后降级路径实测有效：命参考仓库 0、定位不到 57、报告里明写"那是没取到，不是文档没引"。
- 同一条脚本的扩展名清单里**有 `.html`**，所以分析文档里那种"落地页第几行"的锚点也会被验。
  落地页是要整段重写的文件，**别用行号指它**（写成散文）：P17a 的判定表原本有四个这种锚点，
  改完页面它们全都漂到了别的句子身上。
- **钩子写错值不会让界面报错，只会让照片停在另一档**（P18，2026-10-06）：这是取证里最贵的一类错误，
  因为那张"看上去没问题"的截图会被登记成"某一档已核对"。现在 19 个键的判定住在
  `Packages/MMCore/Sources/MMCore/HookValues.swift`（写错 = 回落默认档 + **stderr 一行**，
  文案点名原文、可接受值、实际落在哪），`Scripts/p18-hook-typo-proof.sh` 拿 23 档错值去撞它、
  以 stderr 为判据。**新增钩子时照它走**：不要手写 `env["X"].map { ... }` 那套 guard-else-静默，
  用 `MMHookValue.selected/int/flag`；`accepts` 由档位表现算，所以文档不可能和实现各说一套。
  两条附带教训：**留痕的读取点要是 `static let`**（`body` 每帧都会读，计算属性能把一行话刷成刷屏），
  以及 **`Double("nan")` 是能解析的而 `nan > 0` 是假的**（预算钩子曾在这一支静默回落，
  拍出的照片与钩子毫无关系而日志一行不留）。分类台账见 `docs/analysis/hook-typo-audit.md`。
- ~~概览页的"可清理"走 `scanAll()`，不看清理页那四个勾选~~ —— **P8（2026-10-05）已修**：
  两个页面现在共用 `CacheScanScope.selected(...)` 拼勾选、也共用同一份排除清单，
  四个类别全关时概览显示「未勾选类别」而不是一个来路不明的数。
  取证与逐档读数记在 `docs/analysis/release-readiness.md` §7.1。

## 发布状态

**功能就绪、分发未就绪**。产物是 ad-hoc 签名（`flags=0x2(adhoc)`、`TeamIdentifier=not set`），
Gatekeeper 判 `rejected`；许可未定。自己编译自用不受影响，发给别人则要先补这两项。
图标已补（`Resources/AppIcon.icns` + `CFBundleIconFile`，来历与取舍见
`docs/analysis/release-readiness.md` §2.2）。
逐模块判定、hardened runtime / 沙盒会打断哪几条现有能力（**当前二进制是六条**——P11 实测那一张表
是七行，第七行那一族 P11c 已从界面撤下，§3 结论 4 明确写了"发版说明里现在写六行才对得上当前二进制"，
README 从前写的是七条，P20 改过来）、以及 v1.0 建议范围与
发版前 checklist：**`docs/analysis/release-readiness.md`**。

**hardened runtime 那一栏 P11 已经从"预测"变成"实测"**（2026-10-05，§3）：同一份二进制打两种签名
（`adhoc` / `adhoc,runtime`），七行能力逐个拍对照照片，**本机零行被打断**——所以"走 Developer ID + 公证
要不要先砍功能"这个问题现在有答案了：不用砍。沙盒那一档仍是要把那张表整排砍掉才能上
（**那张表七行、当前二进制六行**，理由同上一段），且这一轮**没有**实测沙盒。
复跑：

```bash
./Scripts/make-app.sh            -o /tmp/mm-app-p11-base -s /tmp/mm-scratch-p11
HARDENED=1 ./Scripts/make-app.sh -o /tmp/mm-app-p11-hr   -s /tmp/mm-scratch-p11
./Scripts/p11-hardened-check.sh /tmp/mm-app-p11-base/MacMaster.app docs/verification/p11-hardened base
./Scripts/p11-hardened-check.sh /tmp/mm-app-p11-hr/MacMaster.app   docs/verification/p11-hardened hr
```

这一轮顺带查出并修了三个**与签名无关**的真实缺陷（`log show` 那条读法里的管道死锁、
列宽把事件正文吃干净、以及 `prefix(5)` 在升序输出上取到的是**最旧**的 5 条却标着「最近」）——
细节与判据在 §3 末尾与 `hook-ledger.md` §5，方法教训在 `fidelity-guardian.md` §6.6.6。
**P11c 把这三个缺陷所在的那一族整个撤下了**（同一篇 §6.7）：修完之后重测谓词，命中的头名不是要报的东西，
所以界面上不再有"最近活动"，那张卡改叫「密钥与自启配置的改动时间」。教训留在文档和
`Scripts/p11-pipe-deadlock-repro.swift` 里，代码里那一族已无残留。

**P11c（2026-10-05）对发版说明的三处影响**：①"读什么"少一项（不再执行 `log show`，见上面《权限与隐私》）；
②守护页那一卡只报 mtime，**界面上就写着这句**，所以说明里不能写成"最近访问记录"；
③`full` 测试数从 581 变 579，§10 checklist 第 1 步的期望值随之改。发版判定本身没变：
**功能就绪、分发未就绪**，卡的还是许可、权利人、签名方式那三项人的决定。

checklist 的 1–3 步（全量测试 → `VERSION=<这一版要发的号> BUILD=1` 出候选产物 → 三张照片闭合并验证
"版本号从打包脚本走到关于页"）**已实跑十五遍**：前五遍都在 2026-10-05——P9 那遍 571/0/1（证据
`docs/verification/v1.0.0/`），P12 那遍在带 P11 改动的二进制上重跑 581/0/1（证据
`docs/verification/p12-v1/`），**P13 那遍在带 P11c 改动的二进制上重跑 579/0/1**（证据
`docs/verification/p13-v1/`，判据逐条见 §7.4；这一遍还多拍一张——改名之后的活动卡，
拍在**发版候选产物**上而不是调试构建上），**P14 那遍在带页头合同的二进制上重跑 583/0/1**（证据
`docs/verification/p14-v1/`，见 §7.5），**P15 那遍在带 `CommandRunner` 的二进制上重跑 590/0/1**（证据
`docs/verification/p15-v1/` + `docs/verification/p15-pipe/`，见 §7.6）；
后五遍在 2026-10-06：**P19 那遍 612/0/1**，跑在带 P18 钩子留痕改动的候选产物上，
同一份产物再过一次钩子门禁（证据 `docs/verification/p19-v1/` + `docs/verification/p19-hooks/`，见 §7.10）；
**P20 那遍 612/0/1，但整遍是在一次干净的 `git clone` 出来的树上跑的**——不借作者工作树里任何一样
没进版本控制的东西，证据 `docs/verification/p20-clone/`（见 §7.11）。这一遍的意义不在又一个 612，
而在它把"发版前门禁只有作者机器跑得动"这一类问题逐个撞了出来，详见 §7.11；
**P21 那遍 621/0/1**，跑在带删除闸门改动的候选产物上（证据 `docs/verification/p21-v1/`，见 §7.12）——
这一遍和上一遍不一样，**它动了业务源码**，所以同一轮还重拍了磁盘页删除面板四档当回归
（`docs/verification/p21-disk/`，四行回执与 `p68-disk/` 逐字相同）。
**P22 那遍 622/0/1**，跑在带"受保护目录跳过披露覆盖全深度"改动的候选产物上
（证据 `docs/verification/p22-v1/`，见 §7.13）；它同样动了业务源码，所以也带了一组回归——
`p68-disk-capture.sh` 在 P22 的二进制上重跑成 `docs/verification/p22-disk/`，
**四行回执与 `p21-disk/` 逐字相同**（改的只是"没算进去的那些"怎么披露，被跳过的字节本来就不进统计）。
**P23 那遍还是 622/0/1**，因为这一轮**一行编译输入都没动**——它改的是取证工具链：
产物从此带一份**内容**指纹（`MMSourceDigest`），取证脚本起跑前先比一遍，
**照片跑的若不是当前那棵树构建的产物就 exit 4、一张都不出**（证据 `docs/verification/p23-v1/`，
否证五档 `docs/verification/p23-provenance/probe.log`，见 §7.14）。
磁盘那一族本轮只重拍两档（`p23-disk-skip/`），画面里会动的只有真机那两格
（卷可用 45.54 → 45.18 GB、可清理 1.87 → 2.15 GB），新事实全在日志头那一行 `# digest:`。
**第十一遍在 2026-10-07，P24，还是 622/0/1**：这一遍是上面那条顺序规矩（**先提交、再构建、再出片**）
立起来之后**第一次照做**的一遍——产物构建在已经提交的那棵干净树上，所以日志头 `# digest:` 的
`tree=` 与 `app=` 两边相等，`MMGitCommit` 也**不带 `-dirty`**（作者工作树这一侧的第一份；P20 那一遍同样干净，
但那一遍干净的是克隆树）。本轮动的是两支取证脚本，于是那两支的**放行路径**第一次归档了
（`docs/verification/p24-gate-pass/`）——P23 只验过它们"拒"的那一支，而一条只验过拒的门禁，
通不通没人知道。
**第十二遍在 2026-10-07，P25，629/0/1**：这一遍改的是业务源码一处——清理页页头那句副标题在 1000 pt 硬最小宽度下
被中间截断吃掉了"另有 N 只读"（一句话在宽窗说、在窄窗不说，等于不说）。
段序按优先级重排 + 时间戳去掉年份，判据 +7 全在 MMCleaner（18 → 25）。
**这条顺序第二次照做，也是第一次带着源码改动照做**：三个提交在前、构建在中、出片在后，
同一屏留下三档实拍（`p25-header-yeardate/` 是改去年份之前那一版二进制拍的窄窗档，
它的 `# digest:` 跟着它自己的 commit 走，**故意不等于最终产物**；`p25-header-wide/` 是 1280×800；
`p25-header-narrow/` 是最终产物的验收档）。残余没清零：那一屏在 minWidth 下仍差约 5 个字符宽度，
账在 `docs/analysis/release-readiness.md` §8。
**P26 在 2026-10-07，633/0/1，但它不是一遍完整的发版核验**——只重跑了 §10 的第 1 步（九包全量），
第 2、3 步（构建 1.0.0 候选产物 + 三张基础照片 + 签名/plist/Gatekeeper）**没跑**，
所以那一遍没让"十二遍"变成十三遍，而签名那一侧的结论**当时**的有效期只到 P25 那一份产物
（这笔账 P27 还掉了，见下面那一段）。理由与"下一轮要补"写在 §7.17 末尾。这一轮答的是 P25 留的那句问：**那条截断合同对九屏都成立吗**。
逐屏实拍的答案是"**两屏被截、七屏整句**"，而被截的正是清理页与磁盘页；机制不是"窗口窄"，
是 **预算 = 窗口宽 − 侧栏 − 这一屏动作簇的宽**（守护页 63 字符放得下，清理页 50 字符放不下），
所以 §7.16 那个"≈48 字符预算"是清理页专属、不是一条常数。
磁盘页那一句截出来是**假话**：`77.8 MB · 44…aster-disk-fixture` 里 `44` 的单位被连带吃掉，
画面上成了两个并排的光数。修了两处——共享层副标题挂 `.help`（九屏同时受益，兜底不是免罪），
磁盘页页头收成三段、"扫描用时"整段出页头。**第一档只调段序，被照片否掉了**，
最终那一句是 `77.8 MB · /tmp…ture · 44 个文件`。全过程与逐屏读数在
`docs/analysis/header-truncation-audit.md`。
第 4 步（许可、权利人、签名方式）是人的决定，实现不代拍。

**第十三遍在 2026-10-08，P27，633/0/1，跑在一棵 `git clone` 出来的树上**：这一遍没有新代码，
做的就是把 P26 欠的第 2、3 步**换一棵树**补完——`git clone --no-local` → `VERSION=1.0.0 BUILD=1 make-app.sh`
（25.91 秒、零远程依赖）→ `p7-release-check.sh` 三张照片（`docs/verification/p27-clone/`）→ 同一棵树上跑九包全量。
**三项同时成立是前十二遍没有过的形状**：树来自克隆、`# digest:` 里 `tree=` 与 `app=` 逐字相等、
`# plist:` 那行不带 `-dirty`（P24 有后两项、树是作者工作树；P20 有第一项，那一遍同源门禁还没立起来，
照片里没有 `# digest:` 行——**所以"别人 clone 出来也能构建、并且当场自证照片与二进制同源"这条链是第一次跑通**）。
**三行对外结论与 P25 同**：codesign 一字不差、spctl 只差产物路径前缀、plist 只差 `MMGitCommit` 那一个 token；
顺着这条对法**在 P27 那一遍**现读全仓，**15 份 `02-about.log` 里的 `# codesign:` 只有一种写法**——这一条同时是
"判定没变"最硬的证据与"分发这一头一次都没往前走"最硬的证据。
还有一件事值得单独记：P26 末尾写着"第 2、3 步在带 P26 改动的树上重跑会是一次纯重复"，本轮真跑了，
**那个推断第一次被实测对上**——所以"必然是重复"不能当成下一轮不跑的理由。
并发也如实记：三张照片（00:08:01/08/14）与跑测重叠约二分半（结论行 00:10:27），
所以 `03-dashboard-min.png` 上 CPU 15% / 内存 12.34 GB / 磁盘写 60.9 KB/s 是**跑测进行中**的时刻，不是 idle 基线。
过程与那三行逐字对法在 §7.18。

**第十四遍在 2026-10-09，P30，641/0/1，又跑在一棵 `git clone` 出来的树上**（`/tmp/mm-clone-p30`，HEAD `54ca105`，
`# digest: tree=54ca105+e3b0c442 app=54ca105+e3b0c442`）：这一遍分两半，P30a 先提交三处对外措辞账加一处门禁改动
（结论行搬进 `report()`，让入库那份 `audit.log` 自己带着判定），P30b 才是 §10 的第 0–3 步。
**P30 一行编译输入都没动**，所以九格与 P29 那份**逐字相同**——`diff` 出来的，不是从"没改代码"推的。
三项自证条件第二次同时成立（第一次 P27）：树来自克隆、`tree=` 与 `app=` 逐字相等、`# plist:` 那行不带 `-dirty`。
与 P27 那一遍有两处实测差别：①本轮第 1 步与第 3 步**没有时间重叠**（最后一包 MMOptimizer 结束于 12:56:30，
三张照片落在 12:57:48 / 12:57:56 / 12:58:02），所以 `03-dashboard-min.png` 上那几格运行时数字拍的是
"跑测已经结束"的机器，而 P27 那一遍拍的是"跑测进行中"；②三行对外结论照旧——codesign 一字不差、
`spctl` 判 `rejected`、plist 只差 `MMGitCommit` 那一个 token，**分发那一头第十四遍仍然一步没走**；
上一遍那句"15 份 `02-about.log` 只有一种 codesign 写法"本轮按同一条命令重数：`grep -h "^# codesign:" docs/verification/*/02-about.log | sort -u`
**16 份、仍只出一行**。
P28 与 P29 为什么没让遍数加一，一并写清：P28 是 CI 与本地打包那一头（`p28-ci/`、`p28-package/`），
不是 §10 的 1–3 步；P29 改了设置页九项、真重跑了九包全量（641 那一格从它起），但**没重跑第 3 步**，
所以那一遍没加——这笔账和 P26 欠 P27 的是同一个形状，本轮补齐。
**P31 同理不加**（写在 P30 这一段里，因为它是这一遍之后发生的）：它改了卸载页、+27 条判据、真重跑了九包全量
（→ 668），也拍了七张实机照片，但 §10 的第 2、3 步没跑在带 P31 的产物上——**照片多少不算遍数，
跑了第 3 步才算**，这一条与 §0 那句"验收不变量"是同一件事。
证据 `docs/verification/p30-clone/`（三张照片 + 三份归因日志）与
`docs/verification/p30-citations/run-all-tests.log`（**第三份从克隆树归档的测试结论行**，也是第二份带同源门禁的：
P20 那一遍归档规矩还没立起来，P27 是第一份）。过程在 §7.22，四条可复用判据在 §11 末尾。
本轮门禁跑三跑、入库的是最后一跑（13:27:42，索引 991，位置存疑 114，**硬失败 0、exit 0**），
中间那一跑是唯一的 exit 1，而它抓的是**本轮自己新写的一条引用**（把 `AppProvenance.swift` 记到了 MMDisk 包下）；
顺着重读那一行还揪出 P29b 留的一笔旧错账——"`steam` 生产代码只有一句无关注释"其实是 **0 命中**，
而 `AppProvenance` 的来源现读是**五档**，不是从前记的两档。**旧引用不会被硬判据抓，只会被软层提示**，
所以那两句得由人现读复核（判据 ③）。

**第十五遍在 2026-10-13，P35b，764/0/1，还是跑在一棵 `git clone` 出来的树上**（`/tmp/mm-clone-15`，HEAD `698d44b`，
`# digest: tree=698d44b+e3b0c442 app=698d44b+e3b0c442`）：这一遍有**两个前十四遍没有的形状**，
两条都会改变下一轮读这一格的方式。① **它是带着编译输入跑的一遍**——P27 与 P30 那两遍的九格"与上一遍逐字相同"
正是它们要证明的事，本轮不是：641 → 764，五笔累计 +123（P31a +27、P32b +38、P33b +14、P34b +17、P35b +27），
**所以"数字变了"在这一遍里是判据而不是疑点**（如果还和 P30 相同，那才说明克隆树没带上本轮的提交）。
② **产物版本号第一次不是 1.0.0(1)**：这一遍打的是 `VERSION=1.0.1 BUILD=1`，因为它是 v1.0.1 发版前最后一遍，
而 CI 那一头的版本号从 tag 折出来（`v1.0.1` → 1.0.1 配构建 1），本地必须用同一个号才对得上；
代价是全仓那两把按版本号数日志的尺子**从这一遍起要分档**——按 1.0.0 那一对键数仍是 47 份（一个没动，
因为新增那三份读的是另一档），按 `# plist:` 行数则是 45（15 个目录 × 3），其中 42 行 1.0.0、3 行 1.0.1。
"干净克隆 + `tree=` 与 `app=` 逐字相等 + `# plist:` 不带 `-dirty`"三项同时成立是**第三次**（P27、P30、本轮）；
第 3e 步引用门禁也在同一棵克隆上跑（先 `clone-references.sh --fetch`，七份参考仓库全部取到），
三个总数与四道硬判据与作者树**一位没动**（1083 / 886 / 779、硬失败 0）。
**但这一族的门禁跑到收口一共读了六遍，只有最后一遍是与这一次提交内容同读的那一遍**：发版说明改成 1.0.1 那一页时，
`feature-roadmap.md` 一次加了 6 行，把 11 条指向它行号的引用整体顶漂 6 行——门禁只抓到其中 2 条（被顶进空行的那两条），
其余 9 条落在还有字的行上、四道硬判据一声不响（`Scripts/p29-anchor-drift-audit.sh` 也看不见，它的文件集当时只有非测试 `.swift`——**P36 把被改的 `.md` 与 `.sh` 补进了同一支量尺，并加了第二个参数 `BASE` 让提交之后还问得出上一轮，见 `docs/analysis/release-readiness.md` §7.26**）。
10 条活锚点逐条现读 +6 重指、1 处漂移的历史坐标改成裸写（连同另外 3 处没漂的历史坐标，这一遍全仓共 4 处裸写），
之后**硬失败归 0**，定稿那一读
（`docs/verification/p35b-final-citations/audit.log`，跑在 `git add` 之后；其后又复读三份
`docs/verification/p35b-postwrite-citations/`、`docs/verification/p35b-commit-citations/`、
`docs/verification/p35b-precommit-citations/`，
三个总数逐字相同、`# index:` 1211 → 1212 → 1213 → 1214，每多归档一份就多一个跟踪文件）走到
**1077 / 884 / 777**、死符号 2、存疑 133、`# index:` 从 **1211** 一路涨到 **1214**——三个总数**比 1083 / 886 / 779 少的正是那四处裸写**，
两次失败与归零的归档（`p35b-releasenotes-citations/`、`p35b-anchorfix-citations/`）与逐条处置在
`docs/analysis/release-readiness.md` §7.23。
**本轮还抓到一件新的**：`make-icon.sh --check` 只跑了自己头部那两道判据里的"十档齐全"一道，
字节比对因为在 `--check` 分支里拿不到只有生成才会创建的中间目录而被整条跳过——**作者树与克隆树都一样**；
本轮没动它（它管的 `Resources/AppIcon.icns` 是编译输入，而核验途中不改量尺），改法与三条理由记在
`docs/analysis/release-readiness.md` §7.23 与 §10 第 2 步那一格，账登记给下一轮。
**这一笔已在 P36 收口**：`--check` 现在自己现生成一份源图（不重写 icns），两头各撞过一遍——
正向 `1024 档 270169 字节` 放行，把 `make-icon.swift` 里一个颜色常数改一位就报
`✗ 1024 档字节数不一致：源 270169 / 解出 277310` 并退非零； icns 跑前跑后 sha256 相同、
编译输入指纹段仍是 `e3b0c442`，所以 v1.0.1 那个产物与这条改动无关。量尺 `Scripts/p36-icon-byte-audit.sh`，
读数 `docs/verification/p36-icon-byte/audit.log`，过程 `docs/analysis/release-readiness.md` §7.25。
证据 `docs/verification/p35b-clone/`（三张照片 + 三份日志 + 一份测试结论行）与
`docs/verification/p35b-clone-citations/audit.log`，过程在 §7.23。
**v1.0.1 的发版决定这一问本轮由用户答了**（"按最优解处理完即可发布"），**同日已发**：
tag `v1.0.1` 落在 `41631c6`（附注 tag，tag 正文那句就是"第十五遍发版核验通过：764/0/1，干净克隆可复现"），
CI run `38348525288` 4 分 43 秒跑绿，Release 挂了三个附件（zip 3,324,846 / dmg 3,944,864 / SHA256SUMS 176 字节），
正文与仓库里那一版 `RELEASE-NOTES.md` **逐字相等**（7990 字符）。
**"网页上那个附件就是本地核验过的那棵编译输入树"这一句不是推的**：`Scripts/p35b-release-verify.sh v1.0.1`
把附件下载回本地，逐条量正文、三个 sha256（本地实算 / API digest / 清单文件三线对齐）、
产物 plist（`1.0.1(1)`、`MMGitCommit=41631c6` 不带 `-dirty`）与编译输入指纹段（产物 `e3b0c442` ==
本地工作树现读 `41631c6+e3b0c442` 的前半段），四道全过才写那句结论；
日志 `docs/verification/p35b-release/release.log`，过程与那一跑第一版用 BSD `sed` 撑出来的**假红**
（报摘要不符，错的是量尺不是产物）记在 `docs/analysis/release-readiness.md` §7.24。
签名身份、许可与权利人两条照旧等人（同一份日志里 `codesign` 仍 `adhoc`、`spctl` 仍 `rejected`）。
**发布之后门禁又读了三遍**（这三遍量的是下一笔提交，与上面那六遍不同一遍）：第一跑抓到上一笔提交自己写的一句
例子把 `docs/design-system/README.md` 那一行写成了冒号形态，**引用条次因此从 1077 走到 1078 而唯一数与命本仓库数不动**
（三条冒号形态共用同一个"路径+行段"键），按 §7.7 改回裸写后第二、第三跑都是 **1077 / 884 / 777、硬失败 0**——
三份归档都在 `docs/verification/p35b-release-citations/` 与同名的 `-v2`、`-v3` 那两份。

**P14（2026-10-05）改的是守护页页头那一句副标题**：它从前只列三件事，而那一屏有四张卡
（P11c 给第四张卡改名之后这个缺口才看得见）。现在副标题由一份四段清单生成，段数有单测钉住，
并且**跑过否证实验**（删掉一段 → 4 条里 2 条失败）。同一轮量到一件只有照片能发现的事：
页头副标题是**单行 + 中间截断**，所以加长它不会换行、不会报错，只会静默多一个省略号——
三档窗口宽度的照片在 `docs/verification/p14-header/`，判据是"那一行不许出现 `…`"，
复跑 `./Scripts/p14-header-capture.sh`。发版判定没变。

P12 顺手还掉了 §7.2 那笔挂着账：取证日志里那行 `sandbox_extension_issue_file_to_process …`
**是启动路径带来的，不是签名档次**（同一份 bundle 拷到用户目录起进程，两档签名同为 `adhoc`，
`/tmp` 1 次、用户目录 0 次，界面照常出真实读数）。复跑 `./Scripts/p12-sandbox-warning-probe.sh`。
含义：发版说明里不用写这一行。

**P15（2026-10-05）收的是 P11 留的那笔"同类形状还在别处"**：全站起系统命令的地方从前有三处，
每一处都自己写一遍"起进程 → 等退出 → 读管道"，而 **`Pipe` 的内核缓冲只有 64 KB**——先等再读的写法
对不对，取决于这台机器上那条命令当时吐多少字节（现测 `launchctl list` 18.5–19.5 KB、`tmutil` 21 字节，
所以它在开发机上**可以永远不出现**）。现在三处并成 `Packages/MMCore/Sources/MMCore/CommandRunner.swift`
一处（全仓 `Process()` 现读只剩这一行），读与等分占两条队列，配 5 条喂 >64 KB 输出的合同测试，
**并且做过事前否证**：把形状改回"先等再读"，那两条用例报的是 `timedOut(10.0)` 而不是"数字不对"
（`docs/verification/p15-pipe/negative-control.log`）。两处按量到的余量做了两件不同的事：
`launchctl list` 读侧加 10 秒时限（超时只少一句结论），停用登录项的写侧**不加**（"没等到回话"不能被写成"没改成"）。
复跑 `./Scripts/p15-pipe-capture.sh <候选产物> docs/verification/p15-pipe`。发版判定没变。
