# MacMaster v1.0 就绪度核验（release-readiness）

> 本轮（P7b）的目的不是再加功能，而是回答一个问题：**现在这份代码能不能作为第一个稳定版本发出去，
> 以什么形态发，发之前必须先补什么。** 逐条清单不重复 `docs/analysis/fidelity-*.md`，
> 本文只给判定、阻塞项和范围建议。
>
> **文中所有数字都是 2026-10-05 现跑的**，不是从上一轮文档抄的。每条结论后面都跟着它的取数命令或代码位置。
> **P16/P17 之后这一句要分开看**：§1 的位置引用计数与 §11 的取证目录数（48）是 2026-10-06 现跑；
> 测试数 590、两份代码行数、52 个钩子名仍是 P15 那一跑——**那两轮一行代码没动**，
> 没有理由为了日期好看重跑九包测试。**但 P18（2026-10-06）动了代码，这句话到那儿为止**：
> 本轮现跑 **612 / 0 / 1**（逐包见 §1）、生产 **26,645** / 测试 **9,377** 行、
> 位置引用 **675 条次 / 580 唯一 / 硬失败 0**，取证目录 **50** 个（多了 `p18-hooks/`）；
> 52 个钩子名**没变**——P18 一个钩子都没加，改的是"写错值时会发生什么"（§7.9）。
> §11 那句"取证目录 48"在 P18 之后是 **50**（多的正是 `p18-hooks/`），本轮已就地改。
> **P19（2026-10-06，§7.10）没动一行业务源码**，所以 612 / 26,645 / 9,377 / 52 这四个数**沿用 P18 那一跑**
> （重跑过一遍确认还是 612/0/1，见 §7.10 表格第一行；但九包没有一包变数）。
> 它改的是取证工具链：候选产物现在自证 commit（`Info.plist` 的 `MMGitCommit`），
> 取证日志分清"跑脚本的那棵树"和"被测产物那棵树"。位置引用仍是 **675 / 580 / 硬失败 0**（P19 收口那一跑），
> 取证目录 **52** 个（P19 多了 `p19-v1/` 与 `p19-hooks/`）。
> **P20（2026-10-06，§7.11）同样没动业务源码**，四个数仍是 612 / 26,645 / 9,377 / 52，
> 但**取证目录这一格换了判据**：上面那句"52 个"是用 `ls -d` 数的，里面有两个空目录 git 根本不跟踪，
> 所以它在干净克隆里是 50——换成"只数入库文件"的命令之后 **P18 是 48、P19 是 50、P20 是 51**
> （多的那一个是 `p20-clone/`）。上面三格里的旧数保留原文，因为它们是当时那条命令的真结果，
> 不是笔误；**这一格从此只认 §11 里那条能重跑的命令**。
> 位置引用：克隆那一跑 **675 / 580 / 硬失败 0**，那六个数与作者树在同一个 commit（`b2b3718`）上逐位相同；
> 本轮五处文档改完之后再跑一遍是 **680 / 585 / 硬失败 0**（四个硬判据仍全 0，
> 三份读数在 `docs/verification/p20-clone/audit-{clone-without-refs,clone-with-refs,author-tree}.log`，逐条解释在 §7.11）。
> P20 多出来的一件事是：**这一遍整棵树是一次干净的 `git clone` 带出来的**——
> 代价是撞出"引用门禁在干净克隆里连报告都出不来"这个真 bug。
> **P21（2026-10-06，§7.12）动了业务源码**，所以这四个数是本轮现跑的：**621 / 26,688 / 9,513 / 52**
> （+9 条判据：`DeletionGuardTests` +3、`DiskRiskTests` 全新 6 条；钩子名仍是 52，本轮一个没加）。
> 位置引用 **697 / 595 / 硬失败 0**（收口那一跑，全部文档改完之后重跑，逐字日志
> `docs/verification/p21-disk-risk/citation-audit.log`）。
> 取证目录 **51 → 54**：本轮新开 `p21-disk/`（磁盘页四档重拍）、`p21-disk-risk/`（拍不了的那一格换成探针表 + 引用门禁日志）、
> `p21-v1/`（§10 第 3 步第八遍的三张照片）。
> 本轮改的是删除闸门的口径与磁盘页的风险标签，逐条见 §7.12。
> **P22（2026-10-06，§7.13）又动了业务源码**，四个数同样是本轮现跑的：**622 / 26,730 / 9,535 / 52**
> （+1 条判据：`testNestedProtectedSkipIsDisclosed`；钩子名仍是 52，本轮一个没加，
> 取证只是借 `MM_DISK_SCAN` 换了一个新夹具的根）。
> 位置引用 **698 条次 / 596 唯一 / 硬失败 0**（净 +1，那一个 +1 就是本轮 +42 行代码的全部锚点代价，
> 分解见 §1 那一格），取证目录 **54 → 58**（`p22-v1/`、`p22-disk/`、`p22-disk-skip/`、`p22-citations/`）。
> 这一轮真正值得记的不是这四个数：它是**第一次出现"照片与磁盘上的源码不是同一份产物"**的一轮——
> 中途一次为了少还锚点债的搬家，让归因头里的 `MMGitCommit` 与产物脱了钩，
> 所以 §7.13 里那九张照片全部重拍过。
> **P23（2026-10-06，§7.14）没动一行业务源码**，四个数仍是 **622 / 26,730 / 9,535 / 52**
> （本轮又跑了一遍 `run-all-tests.sh`，逐包与 P22 归档那一份一格不差；结论行入库在
> `docs/verification/p23-citations/run-all-tests.log`）。它动的是**取证工具链本身**：
> 新增 `Scripts/mm-provenance.sh`（77 行，编译输入的**内容**指纹 + 同源检查）与
> `Scripts/p23-provenance-probe.sh`（147 行，五档否证），六支既有脚本各加 9–13 行、**零删除**。
> 位置引用 **见 §1 那一格的 P23 收口读数**，取证目录 **58 → 62**
> （`p23-v1/`、`p23-disk-skip/`、`p23-provenance/`、`p23-citations/`）。
> 这一轮把 P22 留下的那句"照片与产物同源没有门禁"变成了**一条会当场拒拍的断言**：
> 产物 plist 多一个 `MMSourceDigest`，取证脚本起跑前先比它，不同源就 exit 4、一张都不出（§7.14）。

## 0. 结论先行

- **功能面：可以发。** 九个包全绿：`622` 个测试、`0` 个失败、`1` 个跳过（跳过原因见 §1）。
  六个业务模块都有真机照片级别的取证，且本轮之前发现的"界面上说了代码库支撑不了的话"已收口（§7）。
- **分发面：现在这份产物还不能直接发给别人。** 它是 **ad-hoc 签名**、Gatekeeper 判定 `rejected`、
  没有许可证书（§2）。图标那一项 **P10 已补**（§2.2：`Resources/AppIcon.icns` + `CFBundleIconFile`）。
  剩下的都不是代码问题，是**发版动作**问题，各自都有明确的补法。
- **一句话判定**：作为 **"自己编译自己用 / 附带源码的私有分发"**——今天就能发。
  作为 **"给陌生人的 dmg"**——差 §2 的三项。§3 那条 hardened runtime 的兼容验证 **P11 已跑完**：
  本机实测七行能力**零行被打断**，所以走 §2.1 第 2 条**不需要砍功能**；
  剩下的空白是 `launchctl` 的**写侧**没测（会真改用户 launchd 状态），已如实记在 §3；
  **读侧**自 P15 起有一条真机测试（`LaunchctlRunnerTests`，纯查询不动 launchd）。
  （**P11c 注**：那七行里的"启 `/usr/bin/log show` 读统一日志"一行，**下一轮就从界面上撤下了**，
  所以当前二进制只剩六行需要那份兼容结论——测量本身没白做，它正是撤下的依据，见 §3 末尾与 §6.7。）
- **两个必须由人拍板、实现不代选的事项**：许可证（§2.3）与开发者身份（Apple Developer 账号，§2.1）。
- **§10 那份 checklist 的 1–3 步已经真跑过十遍**（P8 之后一遍 571/0/1；**P12 在带 P11 改动的二进制上
  581/0/1**；**P13 在带 P11c 改动的二进制上 579/0/1**；**P14 在带页头合同改动的二进制上 583/0/1**；
  **P15 在带 `CommandRunner` 的二进制上 590/0/1**，这五遍都是 2026-10-05；**P19 在带 P18 改动的二进制上
  612/0/1**；**P20 在一棵 `git clone` 出来的树上 612/0/1**，这两遍都是 2026-10-06；
  **P21 在带删除闸门改动的二进制上 621/0/1**；**P22 在带跳过披露改动的二进制上 622/0/1**；
  **P23 在带取证工具链改动的二进制上还是 622/0/1**，同一日）：
  `VERSION=1.0.0 BUILD=1` 的候选产物，照片把"版本号走到界面"这条链闭合了十次
  （§7.2、§7.3、§7.4、§7.5、§7.6、§7.10、§7.11、§7.12、§7.13、§7.14）。**判定没变**：卡在第 4 步那三项人工决定上
  （许可 / `NSHumanReadableCopyright` / 签名方式——这里从前写"四项"，与 §7.5、§11 的"三项"对不上，
  现读 §10 第 4 步只有三条，已改齐）。
  P12 顺带把 §7.2 挂着的那句"含义未查"量成了事实：**那行 sandbox 警告是启动路径带来的，不是签名**（§7.3）。
  P11c 动过活动卡，**P13 就是那一遍补的账**：除了三张基础照片，还在候选产物上重拍了改名之后的
  那张卡（§7.4 表格最后一行）。P14 动的是页头副标题，所以第四遍之外另拍了一组三档宽度的排版照片（§7.5）。
  P15 动的是取数那条路，所以第五遍之外补的是**"屏幕上那句话还是不是这台机器上的真话"**两档照片，
  加一份把形状改回错误写法去做的事前否证（§7.6）。
  **P16 与 P17 没有再跑第 1–3 步**：两轮一行代码都没动（P16 改的是入库文档，P17 改的是落地页），
  跑的是 §10 的第 **3e**（引用审计）与新增的第 **3f**（落地页四张实拍）。**那时候**的判定不变，
  也不需要因为两轮文档改动而变。
  **P18 只跑了第 1 步**（`612 / 0 / 1`，2026-10-06 现读）加第 3e（引用审计）：这一轮改的是**取证钩子的
  失效表现**，不是任何一条对外主张，也没有产出新的发版候选产物——`VERSION=1.0.0` 的第 2、3 步照片
  当时还是 P15 那一遍的，**它们的结论没有被这一轮推翻**（钩子只影响截图流程，不影响应用行为）。
  这一轮的取证是另一件事：`Scripts/p18-hook-typo-proof.sh` 23 档全绿（§7.9）。
  **P19 把第 2、3 步补回来了**（第六遍，还是 612），这一遍起候选产物的 plist 自己带 `MMGitCommit`（§7.10）。
  **P20 是第七遍，也是第一遍整棵树来自 `git clone` 的**——前六遍都借用了作者工作树里 `git` 看不见的数据
  （七个参考仓库、上一轮的夹具、两个 git 不跟踪的空取证目录），这一遍一样都没有（§7.11）。
  **P21 是第八遍**，跑在带本轮删除闸门改动的候选产物上（`MMGitCommit=95866d9-dirty`），
  三张照片与签名/plist/Gatekeeper 结论在 `docs/verification/p21-v1/`（§7.12）。
  **P22 是第九遍**（`MMGitCommit=0e36f97-dirty`，证据 `docs/verification/p22-v1/`，§7.13）。
  这一遍有一个**别于前八遍的形状**：三张照片是在**改完代码之后的最终那棵树**上重拍的，
  而不是在第一次构建出来的那个产物上——本轮中途把一个新加的视图辅助函数从文件前部搬到了
  `DiskAnalyzerView` 末尾，那一次搬家让前面已经拍过的照片与磁盘上的源码**不再是同一份产物**。
  发现的方式很朴素：照片归因头写 `MMGitCommit`，而产物是搬家**之前**构建的。
  所以这一遍的三张 `p22-v1/`、四张 `p22-disk/` 与两张 `p22-disk-skip/` **全部用同一个二进制重跑过**，
  旧那一批直接作废重拍，没有靠改日志文字把它们"对上"（§7.13）。
  **P23 是第十遍**（`df71638+e3b0c442`，证据 `docs/verification/p23-v1/`，§7.14）。
  这一遍与前九遍的区别不在数字（622 没动，因为一行编译输入都没改），在**这一遍不需要人记得顺序**：
  第 3 步的取证脚本起跑前会拿产物 plist 里的源码指纹和当前工作树比，不等就 exit 4、一张都不出——
  P22 那一族的作废重拍从此是**门禁拦在前面**，而不是**人在后面补**。
- **期望值以 §1 这一格为准**：别拿 571 / 581 / 579 / 583 / 590 当基准，也别顺手拿 612 当基准——
  它是某一遍的读数，不是恒等式。621 与 622 也一样，它们同样只是 P21 / P22 那两遍的读数。

## 1. 本轮实测数字

| 指标 | 值 | 怎么量的 |
| --- | --- | --- |
| 测试总数 | **622** | `./Scripts/run-all-tests.sh`（九包逐个 `swift test`，默认 debug 配置；**P22 于 2026-10-06 现跑**，那一份输出已归档在 `docs/verification/p22-citations/run-all-tests.log`；**P21 那一跑**的日志是 `/tmp/mm-p21b-tests.log`——**它没入库，所以这一格从 P22 起换成了"结论行入库、逐包原始输出留 /tmp"**，理由见 §7.13）。**P11 于 2026-10-05 重跑**：P7 落地时 566，P8 +5（MMDisk 4 + MMFileScanner 1，见 §7.1），P10 不变，P11 +10（MMGuardian 活动卡那三处读法的判据，见 §3）。**P11c 于同日重跑：581 → 579**——删掉 10 条日志拆行判据（被测函数随那一族一起撤下）、加 8 条文案合同判据（`ActivityCardContractTests`），净 −2；**这不是覆盖率退步**，被删的那 10 条测的读法已经从界面上没了。**P14 再重跑：579 → 583**（+4，`GuardianHeaderContractTests`：页头副标题的段数合同，见 §7.5）。**P15：583 → 590**（+7：`CommandRunnerPipeTests` 5 条 >64 KB 管道的读法判据、`LaunchctlRunnerTests` 1 条真机只读、`SystemSpaceReportTests` 1 条同族；见 §7.6）。**P18：590 → 612**（+22，全在 MMCore：`HookValueTests` 钉住"写错值必须回落默认档 + 生成那一行留痕文案"，`LaunchHookTests` 钉住 `MM_APPEARANCE`/`MM_WINDOW_SIZE` 的解析；见 §7.9）。**P21：612 → 621**（+9：`DeletionGuardTests` +3 钉住 `/dev`、`/private` 与"字面问和全量问不许给两种答案"，`DiskRiskTests` 全新 6 条钉住"界面标签不许和闸门唱反调"；见 §7.12）。**P22：621 → 622**（+1：`DiskScannerHierarchyTests.testNestedProtectedSkipIsDisclosed`，钉住"跳过发生在每一层，披露就必须覆盖每一层"；见 §7.13。**这一条 +1 值得多说一句**：改动的代码是 +42 行，判据只 +1——因为这一轮的病不是"某个函数算错"，是"两处读同一份名单、数的范围不一样"，能钉住它的断言天然只有一条）。**P23 又跑了一遍：622 / 0 / 1，逐包九格与 P22 归档那一份一格不差**（本轮一行编译输入都没改，判据 **+0**；结论行入库 `docs/verification/p23-citations/run-all-tests.log`。**"没改代码所以没重跑"这种话本轮不说了**——重跑很便宜，而且它正是"这一轮的改动确实只在工具链"这条主张的证据） |
| 失败 | **0** | 同上，逐包读 `Test Suite 'All tests' passed` 后那行 |
| 跳过 | **1** | 唯一一条在 MMDisk：`DiskRemovalTests.swift` 的 `testMountedVolumeRootIsBlocked`（**P15 现读复核**：函数声明在 `:167`，XCTest 日志回的是里面那句 `try XCTSkipIf` 的 `:173`——**两个数都对，指的是两件事**，从前在这两行之间来回改过一次）。跳过理由原文 `本机没有第二块挂载卷`——**是环境不满足，不是功能没测** |
| 生产代码量 | **26,730 行** | `find Sources Packages -name '*.swift' -not -path '*/.build/*' -not -path '*/Tests/*' \| xargs wc -l`（**P22 于 2026-10-06 现跑**；**P21 时 26,688**；**P18 时 26,645**：P8 时 26,310，P10 +15 是关于页那枚 `appIconArtwork`，P11 +103 是 `scanUnifiedLog` 的并行读 + 拆行 + 取尾，**P11c −88 是那一族整批删除**，P14 +18 是 `GuardianPageCopy` 那一份清单与两条注释，P15 +95 = `CommandRunner.swift` 120 行 − 两处调用点各自删掉的旧读法 25 行；P18 新增 `Packages/MMCore/Sources/MMCore/HookValues.swift` **169 行**（取证钩子的判定层），其余十个源文件净 **+21**。**P21 +43**，四笔全在删除闸门那一条链上：新增 `Packages/MMDisk/Sources/MMDisk/DiskRisk.swift` **37 行**（从 `MMDisk.swift` 里提出来的风险标签），`DeletionGuard.swift` 165 → **180**（+15：`/dev`、`/private` 两条与 `literalRejection` 那一对入口），`MMDisk.swift` 2037 → **2026**（−11：`risk(of:)` 那 14 行换成一行委托），`Packages/MMDisk/Package.swift` +2（测试目标要依赖 MMCore）。**P22 +42，一笔**：`MMDisk.swift` 2026 → **2068**——`ProtectedSkipLedger` 那一整类（含注释 25 行）、三处调用点各加一个可选参数、`skippedDisclosure(_:)` 那 8 行浮层截断，同一次改动里删掉的只有 `skippedProtectedNames(rootPath:)` 那 6 行。**这一格从来是"当轮现跑"，不是"上一格 + 增量"**：P18 前的 HEAD 现读 26,455，与 P15 记的 26,453 差 2 行——那 2 行是 P15 之后落地的别的改动，抄表的人不会知道，所以每一轮都重跑同一条命令。**P22 现读 HEAD 那一跑是 26,688，与工作区 26,730 差 42，与上面那一笔逐文件对得上**。对照命令**必须逐 blob**：`git ls-tree -r HEAD --name-only \| xargs wc -l` 看着像在量 HEAD，其实 `wc` 打开的是工作树里那个同名文件，**它量出来会恰好等于现值 26,730，差异被抹成 0**——本轮真就这么错了一次，是那个"差 0"看着太可疑才回去重跑的。正确写法是 `while read f; do git cat-file blob "HEAD:$f"; done \| wc -l` 逐项求和。**P23 现读仍是 26,730，与 P22 那一格逐字相同**——本轮只动 `Scripts/*.sh`，而 .sh 不是编译输入；这一格之所以还要重跑，是因为"没动源码"这句话本轮是要拿来当判据用的（§7.14 那条指纹主张的前提就是"编译输入一模一样"） |
| 测试代码量 | **9,535 行** | 同一条命令换成 `-path '*/Tests/*'`（**P22 于 2026-10-06 现跑**；**P21 时 9,513**；P7 时 8,790，P8 时 8,846，P11 时 8,957，P11c 时 8,984，P14 时 9,026，P15 时 9,160 = 上一条 +134（`CommandRunnerPipeTests` 87 + `LaunchctlRunnerTests` 33 + `SystemSpaceReportTests` 那 1 条 14），P18 **+217**，两笔全在 MMCore：`HookValueTests.swift` 154 行（15 条）+ `LaunchHookTests.swift` 63 行（7 条）。**P21 +136**，两笔：`DiskRiskTests.swift` 全新 **101 行**（6 条，MMDisk）+ `DeletionGuardTests.swift` **+35**（3 条，MMCore）——**那一轮没有任何其他测试文件增删**，所以 136 = 101 + 35 这一等式本身就是"没有漏计"的自证。**P22 +22，一笔**：`DiskScannerHierarchyTests.swift` 78 → **100**（新增那 1 条判据连着它的说明注释与夹具搭建）。HEAD 逐 blob 那一跑是 **9,513**，与 P21 记的那一格逐字相同——**这一格是"上一轮的现跑值应当等于本轮的 HEAD 值"的交叉验证**，两回都对上才算抄表没抄错（本轮：生产 26,688 = P21 记录、测试 9,513 = P21 记录，两笔全对）。**P23 现读仍是 9,535**——本轮新写的 224 行（两支新脚本）加 62 行（六支既有脚本的插入）**全在 `Scripts/`**，一支测试都没加） |
| 取证钩子 | **52 个名字**（运行时 51） | `grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' \| sort -u \| wc -l`（**P22 于 2026-10-06 重跑，仍是 52**）；多出来的一个是 `MM_TRASH_FIXTURE_PROBE`，只在测试里探 `/tmp` 守卫。**P11、P11c、P14、P15、P18、P21、P22 七轮一个新增钩子都没加**（P11c 只改了既有 `MM_GUARDIAN_ACTIVITY_FIXTURE` 的 `rows` 档用词；P14 的 `p14-header-capture.sh`、P15 的 `p15-pipe-capture.sh` 都只组合已有钩子，且判据是"零夹具"；**P18 更特殊：52 个名字一个没动，动的是 16 个键"写错值时的表现"**，见 §7.9；P21 连钩子的表现都没动，它借已有钩子重拍了磁盘页四档，见 §7.12；**P22 与 P21 同形**——它用的是 `MM_DISK_SCAN` 换根那一条既有能力，新夹具只是换了根里的内容，见 §7.13；**P23 连 Swift 都没动，52 个名字现读未变**——它加的"门禁"全在 shell 侧，一个新钩子都不需要） |
| 子进程启动点 | **1 处** | `grep -rn "Process()" Sources Packages`（非测试）现读只命中 `Packages/MMCore/Sources/MMCore/CommandRunner.swift:51` 一行；**含测试目录也是 1**（本轮现读复核过）。这一格从前写 3（P11c 前是 4）：`scanUnifiedLog` 那一处随统一日志族删除（4→3），P15 把剩下的三处——`SystemSpaceReport` 的 tmutil、`LoginItemStore` 的 launchctl **读**（列表）与**写**（停用）——并进那一个文件（3→1）。**形状只有一个 owning 文件，判据在 `CommandRunnerPipeTests`**，见 §7.6 |
| 网络代码 | **0** | `grep` `URLSession`/`NWConnection`/`Socket`/`Reachability` 在非测试源码里**无命中** |
| 入库文档里的位置引用 | **700 条次 / 597 条唯一引用；硬失败 0**（作者树 **P23 收口**那一跑，全部文档改完之后重跑，逐字日志 `docs/verification/p23-citations/audit.log`；**P22 收口**那一跑是 698 / 596（逐字日志 `docs/verification/p22-citations/audit.log`），P21 收口那一跑是 697 / 595（`docs/verification/p21-disk-risk/citation-audit.log`），P20 收口那一跑是 680 / 585，同一 commit 的干净克隆上是 675 / 580，差的就是新写的锚点） | `./Scripts/p16-citation-audit.sh`（**P16 新增；P17 收口那一跑 2026-10-06**，逐字结果在 `docs/verification/p17-citations/audit.log`——P16 那一跑的日志留在 `docs/verification/p16-citations/` 不动，一轮一份。**P18 收口那一跑同日，日志写进 `docs/verification/p18-hooks/citation-audit.log`**——这一轮没有新开一个 `docs/verification/*` 目录，日志跟着那一族照片走，目录数才不会每轮 +2。**P19 收口那一跑：675 / 580 / 522 三个数一个没动，硬失败 0**，日志按脚本自己的规矩落在 `docs/verification/p19-v1/audit.log`（P18 那一份是手工改名放进去的，两个名字都要想到，见 §10 第 3e 步）。**但位置存疑那一层在 P19 走了一次 99 → 100 → 99**，值得记：本轮往 `make-app.sh` 的 plist 里插了 `MMGitCommit` 两行，把 `LSMinimumSystemVersion` 那一对键往下推了 10 行，而 `website-audit.md` 有一条引用指的正是它旧的位置——**四道硬判据一声不响**（文件在、行号在范围内、不空白、不歧义），只有"只提示、不进退出码"的符号面看见了它。这一条不是噪声：它是本轮自己造成的、能被下一轮误当成"这行代码不管用"的那种漂，所以改指到 `:95-96` 并在那一格里写明了原因。**符号面不当门是对的，但它报的东西不该一律不看。**命本仓库 **522** / 命参考仓库 57 / 命苹果 SDK 头文件 1 / 两头都不到 0；越界 0、**整段空白 0**、同后缀歧义 0；符号面（只提示）死符号 **0**、位置存疑 **99**（P17 那一跑是 101：本轮把钩子锚点重指回元素本身，两条落回正确行）。**33 份入库 .md 全部被读到**（报告里 `# docs scanned:` 自报"33 个真抽了 / 33 个入库"，两个数不等就是有文件静默没进判据——这一条 P16 真发生过一次）。**上一句在 P18 前半段是假的**：那一跑报的是 32/32，因为审计器只扫 `git ls-files`，而 `hook-typo-audit.md` 还没 `git add`——**一份没进索引的文档等于不存在，它的锚点一条都不会被抽**，写文档的人和跑门禁的人中间隔着一次 `git add`。本轮因此改成：先 `git add` 整套 P18 文件，**再**跑审计（下面这份日志就是那个顺序的产物）。**这两个总数不是常数**：P16 收口那一跑是 645/545（改前 541，见 §7.7 第 1 条）；P17 一份新文档（`website-audit.md`）+ 一条脚本行 + 一批新锚点，涨到 674/571；**P18 → 675/580**，但那**不是**"新写了一批一次性锚点"（这句话我上一版写错了，现跑核过已删）：`hook-typo-audit.md` 里一条行号引用都没有，它只写文件名与脚本名，条次贡献 0。真正的原因是**改指**——把全仓入库文档的锚点集合在 HEAD 与工作区各抽一遍对差，**新增 45 条唯一、消失 35 条**（净 +9），条次只 +1，因为绝大多数动作是把一条已有引用挪到新行，而不是多加一处引用。顺带把 `dev-artifact-continuation.md` 里那条指向 DevArtifactView 第 45 行的旧锚点改到解析点现值（它记的是 `MM_PURGE_FIXTURE_HOME` 的守卫位置，守卫在续扫改动里往下搬过；P16 的报告把这一条归在"位置存疑"那一层）——**改的时候留意 §7.7 那条写法约束**：叙述这个死锚点时如果把"文件名 + 冒号 + 行号"连成一串，抽取器会把它当成一条真引用收进去，总数当场涨一条。逐条见 §8 与 §7.7。**P20 又跑了一遍，而且那一遍整棵树是 `git clone` 出来的**：675 / 580 / 522 三个数与作者树逐位相同，代价是撞出"参考仓库不在时这条脚本连报告都不出"这个真 bug（zsh NOMATCH + `set -e` 打死那个 glob，而它自己写的降级分支从没被跑到过）；修完之后两档都实测过——缺参考仓库 exit 1（**该失败**）、`./Scripts/clone-references.sh --fetch` 取齐之后 exit 0，逐条与三档读数见 §7.11。**P20 本轮五处文档改完之后在作者树上收口的那一跑**：680 / 585 / 527 / 57 / 1，越界 0、空白 0、歧义 0、死符号 0、位置存疑 **98**、硬失败 0、exit 0。**P21 收口那一跑：697 / 595 / 537 / 57 / 1，四个硬判据仍全 0，死符号 0，位置存疑 98 → 96，硬失败 0、exit 0**（`docs/verification/p21-disk-risk/citation-audit.log`）。条次 680 → 697 这两笔要分开看：一笔是本轮**还债**还出来的——磁盘页 `risk(of:)` 从 `MMDisk.swift` 提走 11 行之后，六份分析文档加 README 里所有指向那一屏的锚点整体往下漂，逐条现读重指过一遍（`fidelity-disk.md` 五处、`hook-ledger.md` 六处、`release-readiness.md` 那一格 P12 记的五处、`disk-double-gate-review.md` 两处、`disktree-adoption.md` 一处、`deletion-guard.md` 的 §1 锚点）——**这一类漂不是笔误，是改代码的人顺手把文档的坐标也改了**，而它是"位置引用"这种债务唯一确定的还法；另一笔是本轮**新写**的锚点（§7.12 那一节自己就点了 `DeletionGuard.swift` 的两处、`DiskRisk.swift` 的两处与 `DiskRemoval.swift` 一处）。**位置存疑 98 → 96 这一格本轮不解释成因**：那一层只打印前 40 条（日志里 40 行是截断不是总数），拿截断的样本去说"少的那两条是谁"等于编故事。能说的是它**依旧只提示不当门**，而且本轮就有一条是它自己的假阳性——`deletion-guard.md:133` 指 `DiskRisk.swift:27`，那一行现读正是 `static func risk(of path: String…`，锚点对，符号面只是从上下文里抽到了 `DiskAnalyzerView` 这个名字。**这一格从此多了一条要求：报数要报是在哪棵树上报的**。**P22 收口那一跑：698 / 596 / 538 / 57 / 1，越界 0、整段空白 0、同后缀歧义 0、死符号 0、位置存疑 96（与 P21 同一格，本轮没动它）、硬失败 0、exit 0**（`docs/verification/p22-citations/audit.log`，`# repo: 0e36f97-dirty`）。**条次 +1 / 唯一 +1 这一笔是本轮最该看的那一个数，因为它量的正是"这轮改代码有没有欠下锚点债"**：把全仓入库文档的引用集合在 HEAD 与工作区各抽一遍对差（抽取正则比审计脚本自己的窄，所以只用来看**分解**不用来报总数），结果是**新增 4 条键、消失 3 条**——那三条是 `fidelity-disk.md` 里本轮还债重指的三个旧锚点（磁盘扫描器那一屏在 `MMDisk.swift` 里整体下漂，逐条现读重指），第四条 `:1914` 才是**新写**的（§8 那条"名单里五条永远匹配不上"要指到 `readEntries` 挡下 `.` 开头名字的那一行）。**净 +1 就是本轮代码改动 +42 行的全部锚点代价**——这个数字这么小是**做出来的**：新加的那个视图辅助函数被刻意放在 `DiskAnalyzerView` 末尾，放前部会牵动约 40 处锚点（§7.13 记了这次搬家的另一面）。**代价是搬家省下来的，不是审计宽容出来的**。**P23 收口那一跑：700 / 597 / 539 / 57 / 1，越界 0、整段空白 0、同后缀歧义 0、死符号 0、位置存疑 96（与 P21/P22 同一格，本轮没动它）、硬失败 0、exit 0**（`docs/verification/p23-citations/audit.log`，`# repo: df71638-dirty`，`# docs scanned: 33 个真抽了 / 33 个入库`）。**条次 +1 / 唯一 +1 这两笔本轮也对了差**（同一把更窄的抽取正则，只用来看分解、不用来报总数）：**新增 2 条唯一、消失 1 条**。消失的那条是 `website-audit.md` 里指向 make-app.sh 第 95、96 行的那一对锚点，新增的两条是它的现值（同一对键，第 104、105 行），加上 §8 那条指 `Scripts/mm-provenance.sh:22-36` 的（"已知松处"那段头注释）。**这一笔要单独记，因为同一格连着第二轮为同一个原因漂**：P19 往 plist 插 `MMGitCommit` 两行，把它推下 10 行；P23 在同一处插 `MMSourceDigest` 两行、编译之后另有 7 行算指纹，它又走了 9 行。**两轮四道硬判据都没亮**（文件在、95 到 96 与 104 到 105 都还在 137 行里、都不空白、都不歧义）——第一轮是符号面替我看见的，第二轮是我照着 P19 那条记录自己去现读对位的，**这一轮的 96 里不含这一条，因为我跑审计之前已经改指了**。所以那一格现在写的是"连着两轮都被'往 plist 里加一对键'挪动，按符号名找比按行号找可靠"。**本轮唯一一处新写的锚点在工具链自己那一节**，不像 P21 那样要拖着六份文档重指一遍——原因很直接：**本轮没动任何编译输入，源码一行没改，就没有源码行号可漂**。**但这一格在收口时自己踩了一次 §7.7 那条写法约束**：上面那句"消失的那条锚点"我起初是按"文件名 + 冒号 + 两个行号"连成一串写的，抽取器把它当成一条真引用收了进去，**699 / 597 / 539 当场变成 701 / 598 / 540**，而这条"引用"指的是一对已经改指走的旧行、四道硬判据还全绿（它落在的确实是个存在的行段）。改回"第 95、96 行"这种不带头尾的写法之后回到 **700 / 597 / 539**（那一条真引用还留着，见上一句）。逐条见 §8 与 §7.7。 |
| 发版门禁换一棵树还跑不跑得动 | **跑得动，四条命令**（P20 实测） | `git clone --no-local` 出来的树里：`make-app.sh` 直接出产物（22.48 秒、零远程依赖，全仓 `.package(url:` 零命中）、`run-all-tests.sh` 612/0/1 逐包相同、`p7-release-check.sh` 三张照片与签名结论逐字相同、`Info.plist` 的 `MMGitCommit=b2b3718` **不带 `-dirty`**（P19 只验过"脏树加后缀"那一支）。逐条与撞出来的三个问题见 §7.11 |
| 照片与二进制同源的门禁（P23 新增） | **当场拒，exit 4；否证五档全绿** | 指纹 = 当前树里那 **92 个编译输入**的内容哈希前 8 位，前面拼 HEAD 短 sha（`git diff HEAD --binary -- <路径集>` ∪ 未跟踪编译输入的内容，配方一份在 `Scripts/mm-provenance.sh`，构建侧与取证侧共用）；构建侧把它写进产物 `Info.plist` 的 `MMSourceDigest`，取证侧起跑前先比，**不等就 exit 4、一张都不出**（已接：`p7-release-check.sh`、`p68-disk-capture.sh`、`p22-disk-skip-capture.sh`、`p17-website-capture.sh`、`p18-hook-typo-proof.sh`；`grep -rl mm_provenance_check Scripts` 现读数就是这一份清单）。否证跑在 `docs/verification/p23-provenance/probe.log`：① 加一个未跟踪源文件 → 指纹变、两支脚本各 exit 4、目录里 **0 张**；② 加一个未跟踪**测试**文件 → 指纹不变（改判据不该拦截图）；③ 无 `MMSourceDigest` 键的旧产物 → 当不同源处理；④ 当前树 + 当前产物 → 放行；⑤ 同源产物上一档都不拍 → 正常 exit 0（**这条防的是"永远失败的门禁"**——只会被关掉的那种门禁就是这一档没测过的）。基准那一份指纹 `df71638+e3b0c442`，工作区没脏时后半截正是**空输入流的 sha256 前缀**（`printf '' \| shasum -a 256` 现读同一串）——配方里没有藏起来的输入 |
| 取证日志的归因覆盖面 | **255 份 .log：42 带 `# repo:`、13 带 `app-repo`、6 带 `# digest:`**（P23 收口现读；写回之前那一读是 253 / 40 / 13，多的那两份就是本行下面提到的 `p23-citations/` 自己） | `find docs/verification -name '*.log' \| wc -l` 与三条 `grep -rl`（`^# repo:`、`app-repo`、`^# digest:`；**"两侧都记了"这一条用的是不带行首锚的 `app-repo`**——那一行在部分日志里不是行首，加 `^# ` 只数得出 1 份，是个假数）。**剩下那 213 份连一行归因都没有**——它们出自 P6.x 那一族更早的轮次，那时候还没有归因头这件事。出片脚本一共 27 支（`grep -rl screencapture Scripts/*.sh`），**接了门禁的是 5 支**，就是上一行那一份清单；其余 22 支是历史轮次的夹具，本轮**刻意没接**（理由与代价见 §8 与 §7.14 残余第 ② 条）。**这一轮同一个数读了两次、两次不一样**，而且两次都对：255 这一读是在 3e 的 `audit.log` 与测试结论行落盘**之后**数的，那两份各带一行 `# repo:`、都不带产物侧。上一轮自报过"23 份带两侧"，现读 13：那个数当时就没落盘，本轮按"计数一律现读"的规矩改成现读的数。**同一族还有一条现读的更正值**：README 那句"产物版本号逐字相同"原来配的数是 **30 份**，本轮按 `grep -rl "CFBundleShortVersionString=1.0.0 CFBundleVersion=1" docs/verification --include='*.log'` 现读是 **33**，30 那一读用的是哪条命令已经复现不出来了——README 现在写的是 33 **并把判据写在同一句里**，为的就是下一轮能对账 |

逐包分布（同一条 `run-all-tests.sh` 输出，2026-10-06 **P22** 重跑，归档 `docs/verification/p22-citations/run-all-tests.log`）：
MMCore **73** · MMUI 17 · MMFileScanner **117** · MMCleaner 18 · MMUninstaller 121 ·
MMDisk **73**（含 1 跳过）· MMMonitor 53 · MMGuardian **96** · MMOptimizer 54。
**逐包求和 = 622**，与合计那一格一致（这一条自 P11c 起每轮都当自证用：抄来的数不会同时抄错九格）。
**这一跑里 MMCore 与 MMDisk 都是 73**——两格数字撞上了，所以"求和 = 622"这条自证比从前更该逐包按名字读，
别按"73 出现过没有"读；撞车本身没有含义，它就是两包各 73 条。
P15 只动了三包：MMCore +5（`CommandRunnerPipeTests`）、MMFileScanner +1、MMGuardian +1。
**P18 只动了一包**：MMCore 48 → **70**（+22，`HookValueTests` 15 + `LaunchHookTests` 7），其余八包一个数没变——
这一条本身就是"这轮没顺手改坏别处"的旁证（钩子接线改了七个包的源码，但判定全在 MMCore，别的包没有新增断言）。
**P21 动了两包**：MMCore 70 → **73**（+3，`DeletionGuardTests`）、MMDisk 66 → **72**（+6，`DiskRiskTests` 全新一个文件），
其余七包一个数没变。这一轮和 P18 是同一形状的反面教材：**改了磁盘页与闸门的口径，判据只加在被改的那两包**，
所以"其余七包不变"这次**不能**当"别处没被改坏"的证据——MMDisk 那 66 条里本来就有一批在跑删除路径，
它们全绿才是那件事的证据（本轮确实是全绿：0 失败）。
**P22 动了一包**：MMDisk 72 → **73**（+1，`testNestedProtectedSkipIsDisclosed`），其余八包一个数没变。
它和 P21 是同一形状，判据也一样：**"其余八包不变"不是证据，MMDisk 那 72 条旧判据全绿才是**——
本轮新加的这条改的是 `ScanOutput.skippedProtected` 的**形态**（名字 → 相对根的路径），
旧的那条 `testProtectedDirectorySkipIsReported` 断言的是 `["Library"]`，
它在根目录那一层恰好退化成了同名形态，所以它**通过**这件事本身就在检验"退化没退错"（见 §7.13）。

> **P12（2026-10-05，发版核验轮）把上表八行全部现读复核了一遍**：581/0/1（逐包分布同上，MMGuardian 93）、
> 26,428 / 8,957 行、52 个钩子名、4 处 `Process()`、网络代码零命中——**六个数一个都没漂**；
> 漂的是两处**位置引用**：MMGuardian 的 93 条没同步进 §6（那里还写 83），
> 以及这一行原本的 `DiskRemovalTests.swift:173`（现读 `:167`）。
> 唯一那条跳过仍是 `testMountedVolumeRootIsBlocked`（本机没有第二块挂载卷）。
> **教训**：加一轮只往 §1 追加一个数，不等于全文档同步；计数漂移的地方是**引用计数的句子**，不是计数表。

> **P11c（2026-10-05，活动卡文案合同轮）是这一表第一次往下减**：579/0/1、26,340 / 8,984 行、
> 子进程启动点 4 → 3。减的原因不是重构收拢，是**撤下了一族**——`fidelity-guardian.md` §6.7 量了八档谓词，
> 没有任何一档能同时做到低噪、可读、切题，于是「系统活动」卡不再读统一日志。
> **P12 那条教训在这一轮自己应验了一次**：改完之后 §6 壳层那一格、§10 checklist 第 1 步的期望值、
> §11 里"九包 581 个测试"与"581 条测试没覆盖的那一层"那两句话全都还写着 581。**引用计数的句子有三处，计数表只有一处。**
> 三处本轮已全部改成 579（`fidelity-guardian.md` §6.7 结尾也记着同一个数）。**逐包求和是这里最省事的自证**：
> 上面那行九包里只有 MMGuardian 变了（93→91），其余八包不变，求和 = 579，
> 与 `run-all-tests.sh` 的总数对上，说明没有第二个包的数被顺手动过。

> **`run-all-tests.sh` 存在的理由**：`swift test | tail -4` 只剩 swift-testing 的
> `Test run with 0 tests`，会把 MMCore 的 **70** 个测试（P18 现读；P15 时是 48——**这一格恰好随 P18 上涨，因为钩子判定下沉进了这一包**）在屏幕上显示成"跑了 0 个"；
> 而按 `with N failures` 的字面顺序解析会把有跳过项的 MMDisk 解析成 **0 个测试**
> （那一行实为 `with 1 test skipped and 0 failures`）。这两个坑都写进了脚本注释。

## 2. 分发阻塞项（按"挡住什么"排序）

### 2.1 签名与公证 —— 挡住"别人能不能打开"

现测（`/tmp/mm-app-p7b/MacMaster.app`，本轮构建）：

```
codesign -dv --verbose=4  →  Identifier=com.macmaster.app  flags=0x2(adhoc)  Signature=adhoc  TeamIdentifier=not set
spctl -a -vv -t execute   →  /tmp/mm-app-p7b/MacMaster.app: rejected
```

- `ad-hoc` 意味着**没有开发者身份**，`TeamIdentifier=not set`；
- Gatekeeper 对首次从网络下载（带 quarantine 属性）的这类产物**直接拒绝**；
- 本机自用不受影响（本仓库所有照片都是这么拍出来的），**发给别人就受影响**。

补齐路径（三选一，代价递增）：
1. **只用源码构建**：README 里写清 `./Scripts/make-app.sh`，不产出 dmg。零成本、零身份要求。
2. **Developer ID + 公证**：需要 Apple Developer Program 账号（付费身份，**这项决定不属于实现**）。
   流程是 `codesign -s "Developer ID Application: …" --options runtime` → `notarytool submit` → `staple` → 打 dmg。
   **代价面 P11 已量过**：`--options runtime` 那一位标志在本机打断了 §3 那张表里的零行，
   走这条路**不需要砍功能**（限定条件见 §3 末尾三条）。
3. **Mac App Store**：需要账号，且必须沙盒——**当前代码过不去**，见 §3。

### 2.2 图标 —— 挡住"它像个正经应用"

**P10（2026-10-05）已补这一项的前半段**：`Resources/AppIcon.icns` 入库，`make-app.sh` 把它拷进
`Contents/Resources/` 并写 `CFBundleIconFile=AppIcon`。现测（`/tmp/mm-app-p10/MacMaster.app`）：

```
plutil -p Contents/Info.plist → "CFBundleIconFile" => "AppIcon"
Contents/Resources/AppIcon.icns → 518,512 字节
./Scripts/make-icon.sh --check  → ✓ 反向解出 10 档；1024 档 270169 字节
```

图标是**画出来的**，不是一张来路不明的 png：`Scripts/make-icon.swift` 用 CoreGraphics 画十档，
形状取自设计系统自己的品牌符号 `sparkles`（`docs/design-system/icons.js` 那条 path，
也是侧边栏「✦ MacMaster」那颗），内外半径比 0.362 直接从那条 path 量出。
判据不是"看着像"：`make-icon.sh` 生成之后**用 `iconutil -c iconset` 反向解一次**，
核对十档齐全且 1024 档字节数与源 PNG 一致——少一档时 Dock 缩到 16pt 会拿大图硬缩，
而 plist 与 codesign 全都正常、没有任何一处报错，所以只能这样自证。

**如实记下的两处代价**：
1. 圆角是**普通圆角矩形**（`cornerRatio = 0.2237`）近似苹果的连续曲率 squircle。
   32pt 以下看不出差别，1024 档放大看边缘会发现没那么"鼓"。要真 squircle 得换超椭圆路径，
   这一版没做。
2. 16/32 两档**只画大星**（`size >= 48` 才画三颗）——三颗星挤在 32px 里是一团糊，糊掉不如少画。
   这是取舍，不是漏了。

关于页那一枚也一并换成图标本体（`SettingsView.swift` 的 `appIconArtwork`，
以前是 SF Symbol `macbook.and.iphone` 占位符）。取证：`docs/verification/p10-icon/02-about.png`
同一张里能看到蓝底三颗星 + 「版本 1.0.0 (1)」，设计稿 `09-settings.html` 的 09d 板用的是**同一组几何与色值**。
`swift run` 那种没有 bundle 的跑法走另一支（退回占位符），**不画一张白纸冒充图标**。

**这一项剩下的部分仍是动作不是代码**：`NSHumanReadableCopyright` 现值是裸的 `MacMaster`，
**没有年份也没有权利人**（填谁的名字是法律问题，与 §2.3 一起由人拍板）。

`find` 全仓 `*.icns` 在 P10 之前无命中；当时的 plist 完整键集是 12 个键、**没有任何图标键**
（`CFBundleIconFile`/`CFBundleIconName` 都不存在），那一份现测留在 `p7-release-build/` 的日志里。

- `CFBundleDevelopmentRegion=zh_CN`：界面目前是中文单语（§6 壳层那一行有证据），
  英文环境首次启动会拿到中文的 `CFBundleDevelopmentRegion` 提示，可接受，但要写明。

### 2.3 许可证 —— **实现不代选**

- 现测：仓库根目录**没有 LICENSE 文件**（`find . -maxdepth 3 -iname 'LICENSE*'` 只命中
  `docs/lemon-cleaner/` 下两份**第三方项目自己的**许可，而那两个目录都在 `.gitignore` 里，
  不属于本仓库分发内容）。
- 因此 `about` 那一格此前写的 `MIT License` 是一句**代码库里找不到凭据的话**。
  本轮已把界面文案改回事实：`SettingsView.swift` 现在显示「许可 尚未选择许可」，
  照片见 `docs/verification/p7-release-build/02-about.png`。
- **选哪种许可是法律决定**。本文只列出这一项没定，以及定了之后要动的地方：
  补 `LICENSE` 文件、改 `SettingsView.swift` 那一格。设计稿那一格 **P10 已跟实现同口径**
  （`09-settings.html` 的 09d 板现写「尚未选择许可」，并在板注里写明"稿子不许替项目宣称授权"），
  所以定许可之后是**两处一起改回**，不会再出现"稿说 MIT、实现说没定"那种分叉。
  现测复核（2026-10-05 P10）：`find . -maxdepth 3 -iname 'LICENSE*'` 仍只命中 `docs/lemon-cleaner/` 那两份第三方许可。

## 3. hardened runtime / 沙盒会打断什么 —— **P11 已实测（2026-10-05）**

这一节以前是**预测**：每一行指着代码说"沙盒下会被拒 / hardened runtime 需实测"，
而"需实测"挂了几天一条都没测过。预测不能当发版依据——表里若有一行其实不会断，我们就白担心一项能力；
若有一行其实会断而没发现，发出去的 dmg 上那一格就是空的。现在它是照片。

**量具**：同一份编译产物，两种签名档次，逐个能力拍对照照片。

```
./Scripts/make-app.sh            -o /tmp/mm-app-p11-base -s /tmp/mm-scratch-p11   # flags=0x2(adhoc)
HARDENED=1 ./Scripts/make-app.sh -o /tmp/mm-app-p11-hr   -s /tmp/mm-scratch-p11   # flags=0x10002(adhoc,runtime)
./Scripts/p11-hardened-check.sh /tmp/mm-app-p11-base/MacMaster.app docs/verification/p11-hardened base
./Scripts/p11-hardened-check.sh /tmp/mm-app-p11-hr/MacMaster.app   docs/verification/p11-hardened hr
```

判据不是"这一档好不好看"，而是**同一能力在两档之间有没有差**。两份 bundle 的 `codesign` cdhash 不同
（签名嵌在二进制里，这必然不同），所以另外证一次二进制同一性：
`codesign --remove-signature` 剥掉签名后两份可执行文件摘要一致，
现测（P11b 修完 `scanUnifiedLog` 之后的那一对构建）
`sha256 = 937567828cf75b9dc54dcba701aa9ecdb9601c5811a8ccdca34fea4ef21d74b6`、
`md5 = 561d24ee77b3926a36f8f2519142bd33`。
**这个数随构建变，不是常量**：本轮早先那一对（活动卡还在 `prefix(5)` 时）是
`17cc4a102682cd34d83100f08e4e8118602519db7a435005019af8e87036fce5`——顺带认错过一次摘要算法，
那串 64 位是 SHA-256 而当时写成了"md5"，现在两个都记。**要复现这一轮，重跑上面四条命令后
自己现量一次同一性**，别拿本文这串去比。

**本轮一个顶数据的夹具钩子都不带**（`MM_*_FIXTURE` 改的正是"喂给界面的数据"，而这一轮测的就是
"取数那条系统调用还通不通"）；唯一例外是监听两档的**目录**钩子，它们只把 kqueue 指到 /tmp，事件仍走真实
`DispatchSource`。零合成点击。

| 能力 | 代码位置（按符号名找） | 预测 | **实测（base ↔ hr）** |
| --- | --- | --- | --- |
| 启 `launchctl` 停用登录项（写侧） | `LoginItemStore.swift` `LaunchctlRunner.disable`（`/bin/launchctl <cmd> -w <path>`；**P15 起走 `CommandRunner`，不设时限**）。⚠️ 这一格从前写的 `runLaunchctl` 在仓库里根本没有这个符号——**现读核对后改名** | runtime 需实测；沙盒会拒 | **未测**。点开关会真改用户 launchd 状态，本轮不制造这种改动——这是 §3 剩下的唯一空白 |
| `launchctl list` 核对（读侧） | 同上 `LaunchctlRunner.listSnapshot`（**P15 起走 `CommandRunner`，10 s 时限**）。⚠️ 从前写的 `launchctlSnapshot` 同样是不存在的符号 | 同上 | **无差**：两档都是 17 项、同两行挂「没在当前会话里加载」（`02-login-{base,hr}.png` 逐字节相同）。P15 在同一屏换了一条独立读法复核：`p15-pipe/01-login` 的 expect 行算出 17 行 / 2 个未加载，与照片逐字对得上 |
| 启 `/usr/bin/log show` 读统一日志 | `MMGuardian.swift` `ActivityScanner.scanUnifiedLog`（**P11c 已删**，这一行记的是 P11 那一刻的实测） | runtime 需实测；受限环境会挂起，故自带 8 秒超时 | **无差**：两档各 **5 条真实事件行**、正文完整、**最新在前**（`03-activity-{base,hr}.png`，15:29 打在带流式读取 + 取尾 5 条的重建二进制上：base 五行 15:29:23.x、hr 五行 15:29:37.x，各自就是扫描那一刻）。两档不同的只有"哪 5 条最新"（相隔 14 秒拍的）。**这一格还查出了我们自己的三个 bug，见下**。**P11c 更正这一行的用途**：它证明的是"runtime 不拦这条路"，而下一轮量完八档谓词之后**这一族从界面上撤下了**（`fidelity-guardian.md` §6.7）——所以当前二进制里已经没有这一行，兼容结论只剩六行需要它，撤下的决定本身正是用这一路的实测做的 |
| 启 `/usr/bin/tmutil` 列本地快照 | `SystemSpaceReport.swift` `tmutilPath`（读取器 `LocalSnapshotReader.run`，**P15 起走 `CommandRunner`**） | 只读子命令；沙盒受阻 | **无差**：两档都出「磁盘空间只读报告」，本地快照 `0 个` + "这台 Mac 目前没有本地快照"（`05-space-*.png`）。P15 另拍一档：`p15-pipe/02-space`，expect 行 `tmutil-bytes=21 / snapshot-lines=0` 与画面那句「本地快照 0 个」对得上 |
| IOKit 读 AppleSMC 温度/风扇 | `SMC.swift` `IOServiceMatching("AppleSMC")` | 沙盒基本读不到；runtime 需实测 | **无差**：两档都是 174 个可信温度点 + 风扇 1 实测 1001/1000 RPM（区间 1000–4900）（`04-monitor-*.png`） |
| IOKit 读磁盘统计 | `MetricReaders.swift` `IOServiceMatching("IOBlockStorageDriver")` | 同上 | **无差**：两档都是真实速率（读数随时间变，故照片 md5 不同，但两档同为"有数"） |
| kqueue 监听目录 | `TrashWatcher.watchTarget()`、`AppFolderWatcher.watchTargets()` | 沙盒需 security-scoped 书签，否则静默失效 | **无差**：两档都出回声卡——废纸篓侧「刚拖进废纸篓：示例应用」+「本体已在废纸篓」，应用目录侧「刚从应用目录消失：Highball」+「应用目录里有 1 个新条目 Notion.app」（`watch-trash-*`、`watch-apps-*`） |
| 只读打开 TCC.db | `TCCProbe.swift` `sqlite3_open_v2(..., SQLITE_OPEN_READONLY)` | 需要完全磁盘访问 | **无差**：两档同一句降级，用户库 `ENOENT (errno 2)` / `rc=14`，系统库 `EPERM (errno 1)` / `authorization denied (rc=23)`（`01-tcc-*.png` 逐字节相同） |

**实测换来的结论（替换掉原来的"先跑一遍再决定"）**：

1. **hardened runtime 在本机打断了七行里的零行。** §2.1 第 2 条（Developer ID + 公证）
   因此**不需要砍任何功能**——这一条以前是担心，现在是量过的。
2. **沙盒（第 3 条）仍是砍掉全部七行**，且这一轮没有实测沙盒：要打就得另做一轮，
   而结论 1 已经让"为了上架而沙盒"这件事显得不必要。v1.0 仍走第 1 或第 2 条。
3. **两档照片逐字节相同不等于没拍到东西。** `01`/`02` 两对就是这样——它们是真读数
   （降级横幅、17 项清单都在画面上），"相同"本身就是这一行的测量结果。
   判据是**先看画面里有没有内容，再谈相同不相同**；空对空也会相同（P6.6 的教训）。
4. **P11c 之后这张表只有六行是活的**：上面说的"七行"是**这张表落地那一刻的行数**，
   而其中"启 `/usr/bin/log show`"那一行对应的能力**已经从界面上撤下**（§3 表第 2 行有更正注）。
   两条结论都不因此改变：结论 1 说的是"runtime 不拦我们用的任何一条"，少一条只会让它更容易成立；
   结论 2 说的是"沙盒会把这一类能力全砍掉"，而**被撤下的那一族恰好就是沙盒那一档最难自证的一类**
   （它读的是系统日志，不是用户自己的文件）。**发版说明里现在写"六行"才对得上当前二进制。**

**三个必须跟着这张表一起说的限定**：
- `adhoc,runtime` **不等于** `Developer ID + --options runtime`。这一轮证的是"runtime 这一位标志会不会打断能力"，
  公证、`com.apple.security.application-groups` 之类 entitlement 交互不在其列。
- TCC 那一格**本机没有完全磁盘访问**，两档都是"读不到"。所以这一格测到的其实是
  **"打了 runtime 之后没有变得更读不到"**，不是"runtime 下 TCC.db 可读"。
  另外：两档 cdhash 不同，在一台**已经**授过 FDA 的机器上，授权是按 cdhash 记的，
  换签名档次会被当成另一个应用 → 那种机器上重跑这一轮，`01` 这一对**预期不同**，别当回归。
- 一台机器（Apple Silicon、macOS 27.0）、一种外观档（light）。

**这一轮顺带查出的三个真实缺陷（都不是签名造成的，是读法造成的）**：

- **管道死锁**：`scanUnifiedLog()` 先 `waitUntilExit()` 再 `readDataToEndOfFile()`。
  `Pipe` 的内核缓冲只有 64 KB，而这条 `log show --last 5m` 本机现测返回 **199,740 字节 / 1,511 行**
  （同时刻两次 199,740 与 200,017；命中谓词的量随这 5 分钟在写什么而变）——
  子进程卡在 `write`、父进程卡在 `wait`，8 秒超时两败俱伤返回 nil。
  于是**这个函数自落地起从未返回过内容**，界面上「系统日志事件」一行都没出现过，
  而卡片显示的是另外两个信号，看上去像"这台机器没有日志事件"。
  复现（不启动 App，同样的 API 形状跑同一条命令；末位数字是 ③ 的轮数）：
  `swift Scripts/p11-pipe-deadlock-repro.swift 5` →
  ① 旧写法停在整 **65,536** 字节、8.01 秒到点被杀；② 并行读 **198,172** 字节、**0.82 秒**返回；
  ③ 五轮 0.83–0.90 秒**正常退出**（没有触发超时），攒下 198,748–199,036 字节、**154–156 条事件行**可用。
  修法：读管道与等退出各占一条后台队列，且超时后**照常解析已经读到的部分**。
  同样的"先等再读"形状当时还留在 `SystemSpaceReport` 的 tmutil 与 `LoginItemStore` 的 launchctl 读/写两处，
  只因输出小没发作。**这一段 P15 已收口**：三处并成 `MMCore/CommandRunner.swift` 一处（现读全仓库 `Process()` 只有它），
  量出的余量是 tmutil **21–22 字节**、`launchctl list` **18,541–19,540 字节**（同日四次现读：
  18,541 / 18,825 / 18,959 / 19,540，取证那一刻是 18,959；≈ 64 KB 缓冲的三成，
  按同一次采样的 34 字节一行推算**还差约 1,400 行才填满**），
  并配五条喂 >64 KB 输出的合同测试。**否证（`p15-pipe/negative-control.log`）**：把形状改回"先等再读"，
  那两条用例报的是 `timedOut(10.0)` 而不是"数字不对"——死锁真实存在，超时只是在替它遮丑。详 §7.6。
  ⚠️ **这一条的第一版数据是量错的**：复现原先拿一个全局起点计时，② 打印的「8.90s」其实是
  "从脚本开始到现在"，把 ① 那 8 秒死锁算进了自己的账，读起来像"这条命令要 8.9 秒、超了应用侧 8 秒预算"。
  据此写进四份文档与源码注释的"实测 1.5 秒到 8.9 秒都出现过"**全部作废**，上面是逐支独立计时的重测值；
  教训本身记在 `hook-ledger.md` §5。
- **列宽吃掉正文**：修好死锁之后第一次实机照片里，5 条「系统日志事件」全是
  `日期 时间 线程 类型 Activity PID TTL` 这 7 段定宽列（占 78 个字符），
  而旧代码截的是 `line.prefix(80)`——正文一个字都没进画面；另外 `log show` 的折行续行
  被当成独立事件，卡片写着 5 条其实只有 4 条。现在按空格段拆列、续行并入上一条，
  表头行不再顶成第一条事件。判据在 `ActivityScannerLogRowTests.swift`（10 条，喂的是本机抄下来的行形状）。
- **「最近」画的是最旧的 5 条**：`log show` 是**升序**输出的（本机实测：末行时间戳与 `date` 只差一秒，
  首行就是窗口起点），而代码取的是 `prefix(5)`。15:07 那两张照片把这件事直接画出来了——
  五行全在 **15:02**，也就是**没有一行发生在最近 4 分钟内**，而每一行右侧写着「最近」。
  现在改成 `recentLogRecords(of:)`：取**末尾** 5 条、最新的一条排最前，15:29 重拍的两档
  五行时间戳就是扫描那一刻（base 15:29:23.x / hr 15:29:37.x）。判据是
  `ActivityScannerLogRowTests` 里那两条 `testRecentRecords…`（9 条升序事件必须交出 8…4，不是 0…4）。

**一个记下来、这一轮没改的现象：这张卡有一半在报它自己**。修好顺序之后重拍的两张照片里，
`03-activity-base.png` 的 5 行有 4 行是应用自身活动的回声：
`log … log run noninteractively, parent: 93499 (MacMaster), args: '/usr/bin/log' 'show' …`（就是这次扫描本身——
`log` CLI 会把整条命令行写进正文，而我们的谓词原文含 `"login" OR … "auth"`，
于是**这一行因为含有谓词文本而命中了自己的谓词**）、两行 `tccd: [com.apple.TCC:access] AUTHREQ_RESULT …`
（守护页另一条读法——TCC 探测——刚问出去的那两次授权查询）、一行 `runningboardd … RBSSStateCaptureSet`
（我们自己的进程被系统记了一次状态断言）。hr 那张同形：自己的 `log show`（parent 93561 MacMaster）+ 两行 tccd + 一行 runningboardd + 一行无关的 sharingd。
**顺序修好之前这一格是被掩盖的**：`prefix(5)` 拿的是窗口最旧那头，正好躲开了"刚刚发生的都是我们自己"这一段。
这一轮**没有**动谓词：按"我们自己的 pid / 命令行"过滤等于把探针写进产品逻辑，而 tccd、runningboardd
那两行是别的进程写的、按 pid 根本滤不掉；真正的问题是这条谓词（`contains "login" OR contains "auth"`）
当初就没有一份"这张卡该显示什么"的文案合同。收口它需要重定谓词 + 设计稿对这一屏的表态，
记成独立一项（`fidelity-guardian.md` §6.6.3 末尾）。

> **P11c 已收口这一项，而答案是"整族撤下"**（合同与八档谓词实测在 `fidelity-guardian.md` §6.7）。
> 一句话结论：**没有一档谓词能同时做到低噪、可读、切题**——现状谓词 5 分钟 139 行里 47 行是 sharingd 的
> `authTag` 子串巧合、5 行是 `log` 把我们自己的谓词回声回来；换进程白名单则 52 行全是 tccd 的内部转储
> （`SecTrustEvaluateIfNecessary`、`AUTHREQ_ATTRIBUTION: msgID=…`）；只留 loginwindow 是 0 行；
> 切到守护页真正该报的摄像头/麦克风，24 小时 0 行（授权判定被缓存，不落这条日志）。
> 于是这一卡改名「密钥与自启配置的改动时间」，只报固定路径的 mtime，
> 并**修掉一个真机上恒为 0 行的缺陷**（`files.prefix(3)` 在过滤 `.plist` **之前**截断，
> 而本机该目录 9 个条目里 6 个是 `.disabled` 且排在最前）。
> 上面那三条 bug 的判据（`ActivityScannerLogRowTests`，10 条）**随被测函数一起删除**；
> 复现件 `Scripts/p11-pipe-deadlock-repro.swift` 保留（它不依赖任何仓库函数），
> 教训留在 `hook-ledger.md` §5。**这条链的方法价值**：修到能出内容只是中间站，
> 下一问必须是"这一族命中集里第一名是谁"——第一名不是你想报的那件事，就该问该不该存在。

**同一轮还修了取证脚本自己的一个假选择器**：`p11-hardened-check.sh` 的 `ONLY=03,05` 逐档重拍
写在注释里承诺过，实现却是整块用 `ONLY=shots` 把门——点名档号会把五档全跳过。现在五档各自把关。

## 4. 隐私面（发版说明里必须写的东西）

**读**（全部在用户本机，无外发）：
- 缓存与日志根：`~/Library/Caches`、`~/Library/Logs`、`~/Library/Containers/*/Data/Library/Caches`、
  `getconf DARWIN_USER_CACHE_DIR`（`CacheScanner.swift` 的 `DarwinCachePaths.userCacheDirectory()`，
  P12 现读 `:153-160`；此前引的 `:131-162` 只盖得住这一处——四类可清理根目录其实列在同一个文件的
  类别表里，`:462-558`）、系统级 `/Library/Caches`、`/Library/Logs`
  （`SystemAnalyzer.swift:104-176`，P12 现读复核：`:104-105` 是两根，`:161-176` 是那两个类别）。
- iOS 备份目录（**只读列体积，分类为只读不给删除入口**）：`~/Library/Application Support/MobileSync/Backup`
  （`SystemAnalyzer.swift:118,150`）。
- 浏览器：优化页只列**缓存目录**（`MMOptimizer.swift:615-616` 的
  `~/Library/Caches/com.apple.Safari`、`~/Library/Caches/Google/Chrome`）。
  **不读 History / Cookies / 密码库**——这条要说清，因为页面上出现了浏览器名字，用户会往那个方向理解。
- 重复文件：`DuplicateScanner.swift:238-255` 会**读文件内容**算 SHA-256（先头尾各采样，
  命中候选才整文件哈希；任何读失败都计入 `unreadablePaths`，宁可漏报不误报）。
- `/var/db/receipts` 安装包收据、`~/.homebrew` 账本 —— 都是只读归属证据。
- **P11c 起，读列表里短了一项**：统一日志 `log show` 整个撤下（§3 第 2 行有八档谓词的测量与撤下理由），
  守护页「密钥与自启配置的改动时间」那张卡只 `stat` 用户自己的四个目录、只读目录条目名，
  **不再碰系统活动记录**。发版说明里"读什么"这一句因此可以写得更短，也更站得住。

**写**（用户机器上会长期留下什么）：
1. `~/Library/Preferences/com.macmaster.app`（`UserDefaults.standard`，18 个键 +
   `CleanerExclusions` 的前缀键）——P7a 那轮"改设置态"取证用的就是这里，代价见 `hook-ledger.md` §0。
2. `~/Library/Application Support/MacMaster/trash-history.json`（`TrashHistoryStore.swift:17-22`，
   原子写）——**这是唯一一份记录了用户文件路径的磁盘文件**，为的是跨启动撤回。发版说明里要写这一条。
3. 系统登录项注册/注销（`SMAppService.mainApp`，P11c 现读复核后改成带目录的完整路径
   `Sources/MacMaster/LaunchBehavior.swift:24-45`——本文此前写 `LaunchBehavior.swift:24-37`，
   行号起点是对的、终点停在了 `register()`（`:37`）那一行，而这一段真正的落点是 `:45`
   「一切以系统真实状态收尾，不假装成功」；`unregister()` 在 `:39`）。
4. 删除本身：`FileManager.trashItem`（`FileTrashService.swift:52`）或永久删除路径（§5）。

**不做的**：零网络代码（§1 实测），无任何遥测/统计上报；通知是唯一会弹系统授权的入口
（`MenuBarManager.swift:215`，`.alert,.sound`，且脱离 bundle 时不初始化 `UNUserNotificationCenter`）；
摄像头/麦克风只做枚举不建采集会话，不触发 TCC 弹窗（`DeviceUsageProbe.swift:164-171` 的文件注释已注明本机实测）。

## 5. 删除安全：闸门只有一道

- `DeletionGuard.rejection(for:)` 在**非测试源码里 4 个调用点**：
  `FileTrashService.swift:43`（移入废纸篓）、`:86`（永久删除）、`DiskRemoval.swift:98`（磁盘页裁决）、
  `MMCleaner.swift:938`（清理页预检）。**两个删除出口都过它**，没有第三道口子。
- **永久删除全仓只有一个入口**：`MMDisk.swift:1351` 的 `deleteMarkedPermanently` → `:1363` `permanentlyDelete`。
  UI 侧必须勾选确认（`MMDisk.swift:1233` 的 Toggle，`:1250` 的
  `.disabled(plan.isEmpty || !permanentAcknowledged)`），且每次执行后 `permanentAcknowledged` 复位
  （`:1319`、`:1355`）。照片证据：`docs/verification/p68-disk/` 四档。
- 永久删除**不写台账**（`FileTrashService.swift` 的 `permanentlyDelete` 上面那段文档注释写明理由，
  P12 现读 `:71-81`、"不写台账"那两行在 `:77-78`。此前本文写的是"`:79-83` 的**文件注释**"——
  行号漂了三行，而且那是**函数**的文档注释、不是文件头注释，两个错各属一类）。
- 撤回路径**故意不经 DeletionGuard**：它写回的是台账里记的 `originalPath`，
  不是新路径。这条是设计而非漏洞，记在 `docs/analysis/deletion-guard.md`。
- **P12 现读复核这一节的全部位置引用**：`DeletionGuard.rejection` 的非测试调用点仍是 **4 处**
  （`FileTrashService.swift:43`、`:86`、`DiskRemoval.swift:98`、`MMCleaner.swift:931`），
  永久删除那一支的五个行号（`MMDisk.swift:1382`/`:1252`/`:1269`/`:1338`/`:1374`）也全对得上；
  **漂的只有上一条那处**（`:79-83` → `:71-81`），外加它把函数注释说成了文件注释。
  这一节是本文行号最密的一处，九对一漂；别的节没这个运气（§4、§8、§9 各漂了一到两处，已改）。
- **P21 现读把这一节又量了一遍，结论比"P12 那一漂"更难看点**：上面那五个行号在 P21 之前的 HEAD 上
  逐一验过，**一个都不落在它声称的那一行** —— `:1252` 是 `Spacer()`（Toggle 在 `:1233`）、
  `:1269` 是一块面板的文档注释（`.disabled(...)` 在 `:1250`）、`:1338` 是相邻的
  `showMarkConfirm = false`（复位在 `:1319`）、`:1374` 恰好是 `permanentlyDelete` 调用本身
  （而它声称的是复位，在 `:1355`）、`:1382` 是 `permanentSeconds = …`（入口函数在 `:1351`）。
  **漂量整齐得很**：四条都差 19 行，入口那条差 31 —— 这不是笔误，是 P12 之后又有几轮在 1233 行以上
  插了代码，而没人回来重指。所以 P12 那句"九对一漂"在它自己的时代是成立的，
  它留下的这五个数后来变成了**五条"存在但不成立"的引用**，引用门禁一条都不会报：
  文件在、行号在范围内、不空白、不歧义，四条硬判据全过（§7.7 记的那个盲区，这是它最难查的形态——
  **漂过去的那一行读起来仍然像话**，`Spacer()` 挨着 Toggle、`permanentlyDelete` 挨着复位）。
  上面那份现在是逐行现读的活值。另外 `MMDisk.swift` 里 `risk(of:)` 那一段（HEAD 里从 1052 到 1065，共 14 行）
  在 P21 被提进 `DiskRisk.swift`，全文件在它之下的行**整体上移 11 行**，
  指到磁盘页旧行号的引用散在 **6 份文档**里（本文、`deletion-guard.md`、`fidelity-disk.md`、
  `hook-ledger.md`、`disktree-adoption.md`、`disk-double-gate-review.md`），本轮逐条现读重指了一遍——
  **改代码的人顺手把文档的坐标也改了**，
  这是"位置引用"这种债务唯一确定的还法。

## 6. 逐模块判定

判定档位只有三档：**可发布** / **可发布·需在说明里标注** / **不发这一屏**。
"开放项"列只列**本轮仍开着**的，逐条细节在对应 fidelity 文档里。

| 模块 | 判定 | 依据与仍开放项 |
| --- | --- | --- |
| MMCore（设置/删除/台账） | **可发布** | 48 测试全绿（P15 +5：`CommandRunnerPipeTests`）；闸门与台账见 §5，全站唯一的子进程入口 `CommandRunner` 也在这里（§7.6）。无开放项 |
| MMFileScanner（扫描层） | **可发布** | 117 测试全绿，含快照解析两种表头形态与分类型（真机发现的 bug 已钉住）；P8 起 `CacheScanScope.selected(...)` 是清理页与概览页共用的那一条拼法（逐开关映射有单测）；P15 起 tmutil 那一路走 `CommandRunner`，并加了一条"喂 512 KB 也读得完"的判据。开放项都在 UI 层不在这里 |
| MMCleaner（清理） | **可发布·需标注** | 18 测试。本轮 I4/I10 已收（`fidelity-cleaner.md`）。仍开着：**I5**（`MMFailurePanel` 缺"重试失败项"等补救——组件在 `c74f045` 已补，**全仓 11 个调用点（含壳层 `MainWindow.swift:244`）无一使用新 init**，`grep -rn "onRetry\|onCopyDiagnostics" Sources Packages` 除组件定义外零命中，所以统计行与页脚现在是死代码路径）、**I6b**（撤回开关只在缓存页 sheet，另两页走系统 `.alert`）、**I7**（只读分类仍带展开箭头）、**I8**（页签叫"缓存清理"、页头叫"系统清理"，两名不同源）。**标注内容**：可释放数字是扫描瞬时值，不是承诺值 |
| MMUninstaller（卸载） | **可发布** | 121 测试（全仓最多）。开着的是 **B1**（列表宽 268 令牌 vs 稿 300，归协调层）、**B2**（`MM_SHOW_TRASH_CONFIRM` 需与 `MM_TRASH_SCAN_HOME` 同时给的互锁没写进文档）——两条都是文档/稿侧缺口，不影响功能 |
| MMDisk（磁盘分析） | **可发布·需标注** | 66 测试（1 跳过）。永久删除闸门见 §5。**标注内容**：treemap 需要真实扫描，大目录下扫描时间与内存都要在说明里提一句；**触达深度上限（`maxDepth = 20`）的目录只量字节不列名字**，界面上写的是「子项 未枚举」——这句要在发版说明里保留，否则用户会以为那一格坏了。**I4 已于 P8 收口**（标签回「子项」+ 封顶档说「未枚举」，见 §7.1 与 `fidelity-disk.md` §12），仍开着的是 **I3**（详情头部图标与稿不同）、**I6**（相对时间 vs 绝对日期），以及**稿侧** `04-disk.html:163` 仍写递归「文件数 42,180」 |
| MMMonitor（监控 + 菜单栏） | **可发布** | 53 测试。SMC/IOKit 都有失败降级并在界面上说原文原因（§3 那两行）。开着 **I8**（网络速率只在菜单栏显示、页面不用——归设计稿决定） |
| MMGuardian（守护） | **可发布·需标注** | **96 测试**（P15 现读：`/tmp/macmaster-tests/MMGuardian.log` → `Executed 96 tests, with 0 failures`；91 → 95 是页头副标题那份合同，`GuardianHeaderContractTests` 四条，判据与**否证实验**见 `fidelity-guardian.md` §8.1；95 → 96 是 `LaunchctlRunnerTests` 那条真机只读判据，§7.6）。**标注内容**：①TCC.db 读不到时需要用户手动授 FDA，界面对此有横幅（`guardian-tcc.md`）；②活动卡现在叫「密钥与自启配置的改动时间」，**只有 mtime、不报"最近访问"**，卡片底部把这句写在界面上（八档谓词测量与三条合同见 `fidelity-guardian.md` §6.7）——发版说明里不能把这一格写成"最近访问记录"；③统一日志那一档**P11c 已整族撤下**，所以这一模块不再有"起子进程读系统日志"这一项（§3 第 2 行）。从前这里挂着的那三条 `log show` 缺陷随之消失，但死锁的教训与复现件 `Scripts/p11-pipe-deadlock-repro.swift` 保留；④**页头副标题是四段清单，加长它会静默变成省略号**（`MMPageHeader` 的副标题是 `.lineLimit(1)` + 中间截断），三档窗口的排版照片在 `docs/verification/p14-header/`，判据"那一行不许出现 `…`"（§7.5）；⑤**`launchctl list` 这一路自 P15 起有 10 秒时限**，超时不会给出一个偏小的数，而是让整卡换成界面上那句现读原文「这一轮没能和 launchd 对表（原因），所以下面不标注加载状态——「没查到」不会被写成「没加载」。」（`LoginItemAnomalyCopy.indeterminateNote`）；停用那一侧（写）**不设时限**，界面上不会出现"没等到回话却说没改成" |
| MMOptimizer（优化） | **可发布·需标注** | 54 测试。开着的是**形态题**（`MMFailurePanel` 通栏条 vs 带边框卡，与 cleaner I5 同一件事，归协调层）与 `fidelity-optimizer.md` 的 #8/#10 未拍全（跨 tab 运行态、阶段枚举）。**标注内容**：重复文件删除前必须人工核对分组，PROTECTED 组永远不给删除入口 |
| 壳层 `Sources/MacMaster` | **可发布·但零测试** | 根 `Package.swift` 只有一个 `.executableTarget`（`:22`），**没有测试目标**（`ls Sources/` 只有 `MacMaster`）。九包 **612** 个测试**一个都不覆盖壳层**——导航、窗口、设置页绑定全靠实机照片兜。**这是 v1.0 唯一一处"能力靠肉眼而不是靠测试"的地方**。P8 动过壳层（`DashboardModel.measureReclaimable` 现读设置拼 scope），**能单测的那一半已下沉**（`CacheScanScope.selected` 在 MMFileScanner，有单测），壳里剩下的三行只能靠 `p8-dashboard-scope/` 那三张照片。**P11c 现读补一句**：§4 写侧第 3 项那个登录项开关（`Sources/MacMaster/LaunchBehavior.swift`）也落在这一格"零测试"里，它的对照记录在 `fidelity-shell.md`，不在任何一条自动断言里。**P18 把这一格的边界往 MMCore 那边推了一格，但没有加测试目标**：壳层里那三处钩子判定（`MM_OPEN_MODULE` 的目的地、`MM_APPEARANCE`、`MM_WINDOW_SIZE`）现在只剩"调 `MMHookValue.selected` / `MMLaunchHook.resolve*` + 把结果交给 AppKit"，**判定本身在 MMCore 的 70 条里有名字**——`HookValueTests` 15 条打的是共用的档位/数字/开关解析与"留痕必须落在 stderr"（`MM_OPEN_MODULE` 走的就是这一条），`LaunchHookTests` 7 条打的是外观别名与 `900x600` 那支尺寸解析；留在壳里的仍是那条没法单测的：窗口有没有真的被改大、sheet 有没有真的打开。**这一格判"可发布"的理由不变**（照片 + 现在多了判定层），但"零测试"这四个字**没有被 P18 消掉**，别在下一次抄表时把它写成"已补" |
| MMUI / 设计系统 | **可发布** | 17 测试。全站骨架 token 漂移（侧栏 footer S1、标题栏 52 vs 38 I10b、底色 S3/S4）仍在，归协调层，纯视觉 |
| 对外文案 `docs/website/index.html` | **不在产物里·P17 已过完一轮** | 这一页从前**从来没有跟实现对照过**：改动前 `grep -rn website docs/analysis/` 是 **0 命中**，九张 fidelity 对照表里也没有它的位置。P11c 撤下统一日志之后，页里那句"管理登录项，**监控系统活动**"当场变成假话，P14 那轮只改了被证伪的这两句、其余记成待办。**P17 把待办清完了**：逐句判定表 16 行在 `docs/analysis/website-audit.md`，三处"说不到"（一键清理、更快更流畅、两个下载死链）已换成界面上真实存在的动作与「现在还没有能下载的安装包」，四个占位框已换成四档夹具实拍（`Scripts/p17-website-capture.sh`，`docs/website/assets/`）。**发版说明仍要标注的两条**：①画面上侧栏那条卷名与占用百分比、磁盘页「卷可用」**没有夹具钩子**，是拍摄那台机器的真实状态——页面上已经明说这一点（§7.8 第 2 条）；②清理那张图是「开发产物」tab，不是缓存清单（同条第 1 条）。**待人的只剩页脚 `© 2026` 那一行**，它和 §2.3 的许可是同一批决定 |

## 7. 逐轮收口与发版核验（都是"用户可达"的那一类）

| 位置 | 之前 | 现在 | 证据 |
| --- | --- | --- | --- |
| 设置 › 关于 › 许可 | 写 `MIT License`，仓库无 LICENSE | 「尚未选择许可」 | `p7-release-build/02-about.png` |
| 设置 › 通用 › 语言 | 可用 Picker，切换什么都不改 | `.disabled(true)` + 明说"界面文案尚未接入多语言，切换不会改变界面" | `p7-settings-lang/` |
| 概览 › 内存「交换」一行 | 默认窗宽下截成「2.1…」，像数据读坏了 | `MainWindow.swift` `gaugeRow` 的 note 加 `minimumScaleFactor(0.8)` | `p7-release-build/03-dashboard-min.png`（1000×600 下限窗口，显示完整「交换 688.6 MB / 2.15 GB」） |
| 清理页 四开关全关 | 副标题仍报一个数 | 三档分开：`scopeEmpty` / `isPartial` / 扫描真失败 | `p7-empty-scope/`，`fidelity-cleaner.md` I4 |
| 落地页 `docs/website/index.html` | 「一键清理和安全撤回」「让 Mac 运行更快更流畅」+ 两枚 `href="#"` 的下载按钮 + 四个灰底占位框、全页 `<img>` 为 0 | 三处"说不到"换成界面上真实存在的动作，末屏改成「现在还没有能下载的安装包」+ 两条真跑得通的构建命令，四张夹具档实拍进 `assets/`，并在页面上明写哪些是夹具、哪些是拍摄那台机器的真实状态 | `docs/analysis/website-audit.md`（16 行判定表）、`Scripts/p17-website-capture.sh`、`docs/verification/p17-website/capture.log`，见 §7.8 |

### 7.1 P8 追加两处（2026-10-05，同一族：标签/数值口径不一致）

| 位置 | 之前 | 现在 | 证据 |
| --- | --- | --- | --- |
| 概览 › 可清理 | `scanAll()`，不看清理页四个勾选 → 同一个名字两个页面两种口径 | 与清理页共用 `CacheScanScope.selected(...)`；四开关全关时是**未勾选类别**（新档），不是"未扫描" | `p8-dashboard-scope/`（41.8 MB ↔ 5.38 GB 同一格随勾选变） |
| 磁盘 › 详情第四格 | 标签「文件数」、值 `children.count`；**触达深度上限的目录显示「文件数 0」** | 标签「子项」+ 纯函数 `DiskInspectorText.childCount`；封顶节点说**未枚举** | `p8-disk-depth/`（20 层夹具，占用 2.2 MB 与「未枚举」同屏），`fidelity-disk.md` §12 |

两处都是**先有单测再有照片**：MMDisk 新增 4 条（含"未枚举那一档不许含 0"）、MMFileScanner 新增 1 条
（四个开关逐个映射到 OptionSet 位）。全仓现测 **571/0/1**（见 §1）。

### 7.2 §10 checklist 的 1–3 步已实跑（2026-10-05，v1.0.0 候选产物）

跑法就是 §10 那三行命令，产物落在 `/tmp/mm-app-v1`，证据在 `docs/verification/v1.0.0/`
（3 张照片 + 3 份带归因头的日志）。逐条结论：

| 判据 | 量到的 | 出处 |
| --- | --- | --- |
| 版本链闭合 | plist `CFBundleShortVersionString=1.0.0 CFBundleVersion=1`，**关于页同一屏显示「版本 1.0.0 (1)」** | `v1.0.0/02-about.log` 第 4 行 + `02-about.png` |
| 签名档次（未变） | `flags=0x2(adhoc) Signature=adhoc TeamIdentifier=not set`、`spctl: … rejected` | 三份日志的 `# codesign:` / `# spctl:` 两行 |
| 最小窗口不截 | 1000×600 下「交换 688.6 MB / 2.15 GB」整行可读（P7a 那个 `minimumScaleFactor` 在候选产物上仍成立） | `v1.0.0/03-dashboard-min.png` |
| P7a 三句实话在屏 | 「尚未选择许可」/「未配置官方渠道」+「反馈问题」灰着 /「检查更新」可用但弹窗自陈只读本机 plist | `02-about.png`（前两项同屏可见） |
| 第 4 步 | **未做，也不该由实现做**：许可、`NSHumanReadableCopyright` 的年份与权利人、签名方式。（这一项原本还含"没有图标"，P10 已补，见 §2.2） | §2 |

**一条防误读的注**：这张概览上侧栏「系统清理 4.28 GB」与概览「可清理 4.28 GB」同值，
但**它不构成 §7.1 那条改动的证据**——两处读的是同一份测量（`MainWindow.swift:11` 那句注释就是
"概览的读数放在这一层：侧边栏…和概览页要用同一个测量结果"），相等是结构决定的。
§7.1 的判据只在 `p8-dashboard-scope/` 那三档"改勾选 → 同一格数字跟着变"的照片里。

**一条如实记录的观察（P12 已把它从"含义未查"变成量过的）**：六份日志（P7 的三份 + 本轮三份）都有一行
`sandbox_extension_issue_file_to_process failed for …: 1 (Operation not permitted)`。
当时写的是"来自 ad-hoc 构建从 `/tmp` 起进程"——那半句里捆了**两个变量**（签名档次、启动路径），
而这两个当时都没单独测过。P12 做了单变量对照，结论在 §7.3：**这一行是路径带来的，与签名档次无关**。

### 7.3 P12：§10 第 1–3 步在 P11 之后的二进制上重跑，顺手把 §7.2 那行警告归了因（2026-10-05）

跑法就是 §10 那三行命令；产物 `/tmp/mm-app-v1`，证据 `docs/verification/p12-v1/`
（三张照片 + 三份带归因头的日志 + 两份探针日志 + 一张"用户目录起进程"的窗口照片）。

| 判据 | 量到的 | 出处 |
| --- | --- | --- |
| 第 1 步 全量测试 | **581 / 0 / 1**，逐包分布与**当时**的 §1 一致（MMGuardian 93） | `./Scripts/run-all-tests.sh`（原始输出在 `/tmp/macmaster-tests/`，一次性的）。**P11c 之后这一行不再等于 §1**：§1 现在是 579/MMGuardian 91，这一格记的是 P12 那遍的实测，不改 |
| 第 2 步 图标自证 | `✓ 反向解出 10 档；1024 档 270,169 字节` | `./Scripts/make-icon.sh --check` |
| 第 2 步 候选产物 | plist `1.0.0` / `1` / `CFBundleIconFile=AppIcon`，签名 `flags=0x2(adhoc)` | `p12-v1/0{1,2,3}-*.log` 的 `# plist:` 与 `# codesign:` 两行 |
| 第 3 步 版本链闭合 | 关于页同一屏「版本 1.0.0 (1)」+ AppIcon 本体（蓝底三颗星）+「尚未选择许可」+「未配置官方渠道」+「反馈问题」灰着 | `02-about.png` |
| 第 3 步 最小窗口不截 | 1000×600 下「交换 688.6 MB / 2.15 GB」整行可读——P7a 那处 `minimumScaleFactor` 在**带 P11 改动的二进制**上仍成立 | `03-dashboard-min.png` |
| 第 4 步 | **仍未做**：许可、`NSHumanReadableCopyright` 的年份与权利人、签名方式选定 | §2 |

**这轮新量的一件事**（还 §7.2 那笔账）：

```
./Scripts/p12-sandbox-warning-probe.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p12-v1
```

同一份 bundle 原样拷进 `~/.mm-p12-probe/`（拷完立刻 `codesign --verify --deep --strict` 自证一次，
两份日志里的 `# 签名：` 同为 `flags=0x2(adhoc)`），两个位置各起 7 秒：
`/tmp` → 那行警告 **1 次**；用户目录 → **0 次**；两档进程都活过 7 秒，
且用户目录那一档的界面照常出真实读数（`06-home-location-window.png`：45.79 GB 可用、
CPU 8%·10 核 4+6、内存 16.05 / 25.77 GB、可释放三项 1.92 GB / 1.19 GB / 204.8 MB、最近操作四条）。

**所以：发版说明里不用提这一行。** 它是我们**把产物放在 `/tmp` 里取证**带来的，正常安装位置没有它。
**仍未查的部分要说清**：这一轮只把"签名档次 vs 启动路径"两个变量拆开，没查**路径的哪个属性**造成的
（`/tmp` 同时是 world-writable + sticky + `/private/tmp` 的别名，三者没拆）。
要拆得再换三个位置各起一次；这一行既无害、也不写进用户机器上的任何日志，P12 判为不值得再花一轮，
**但换 Developer ID 之后仍应复看一次**——那时签名这个变量真的变了。

**`06` 那张是暗色的，而且这是有意的**：它没传 `MM_APPEARANCE`（01/02/03 由脚本固定传 `light`），
所以界面跟随系统外观。两个含义：① 这一张**不能**当浅色档对照（两档对照在 `p4-light-dark/` 与 `p64-dark/`）；
② 它顺手证明了"不传钩子时界面跟随系统"这条默认路径——那是 §1–§9 之外没人单独取证过的一格。

### 7.4 P13：§10 第 1–3 步在**带 P11c 改动**的二进制上第三遍重跑（2026-10-05）

P11c 动了源码（活动卡整族撤下），所以 §0 那句"第 3 步的照片要重拍一次才算闭合"这一轮兑现了。
跑法与 §7.3 完全相同，产物 `/tmp/mm-app-p13`，证据 `docs/verification/p13-v1/`
（**四张**照片 + 四份带归因头的日志；比前两遍多一张，理由见表格最后一行）。

| 判据 | 量到的 | 出处 |
| --- | --- | --- |
| 第 1 步 全量测试 | **579 / 0 / 1**，逐包分布与 §1 那行九包逐项一致（MMGuardian 91） | `./Scripts/run-all-tests.sh`（原始输出在 `/tmp/macmaster-tests/`，一次性的） |
| 第 2 步 图标自证 | `✓ 反向解出 10 档；1024 档 270,169 字节`——与 §7.3 那一遍**同一个数** | `./Scripts/make-icon.sh --check` |
| 第 2 步 候选产物 | plist `1.0.0` / `1` / `CFBundleIconFile=AppIcon`，签名 `flags=0x2(adhoc)`、`TeamIdentifier=not set`，`spctl` 判 `rejected` | `p13-v1/0{1,2,3}-*.log` 的 `# plist:` / `# codesign:` / `# spctl:` 三行 |
| 第 3 步 版本链闭合（第三遍） | 关于页同一屏「版本 1.0.0 (1)」+ AppIcon 本体 +「尚未选择许可」+「未配置官方渠道」+「反馈问题」灰着 | `02-about.png` |
| 第 3 步 最小窗口不截 | 1000×600 下「交换 688.6 MB / 2.15 GB」整行可读——与 §7.3 同一个读数，说明 P7a 那处 `minimumScaleFactor` 到当前二进制仍成立 | `03-dashboard-min.png` |
| **本轮多拍的一张**：撤下日志族之后的活动卡在**发版候选产物**上 | 五行全在（`.ssh` 46 天前 / 钥匙串 8 小时前 / 三个 `.plist` 3·10·28 天前），mtime 与 `# expect:` 那五条 `stat` 读数逐条推得回；`.gnupg` 本机不存在所以没有那一行；脚注整句在画面上 | `01-real-machine.png` + 同名 `.log`（`ONLY=01 ./Scripts/p11c-activity-capture.sh /tmp/mm-app-p13/MacMaster.app docs/verification/p13-v1`） |

**为什么要多拍这一张**：`p11c-activity/` 那四档是在**调试构建**上拍的，而发版判定要的是
"`VERSION=1.0.0 BUILD=1` + release 配置 + adhoc"这一份二进制上，界面说的话和代码想说的是同一句。
这一张同时是 §6 MMGuardian 那一行"标注内容 ②"（只报 mtime）的**发版侧证据**——
以前这一格只有调试档的照片。

**第 4 步仍是 ⬜**：许可、`NSHumanReadableCopyright` 的年份与权利人、签名方式选定，三件都是人的决定。
**三遍重跑的差别只有一处**：571 → 581 → 579 个测试，产物三遍都是 `1.0.0(1)` / adhoc / `rejected`，
版本链三遍都闭合。**所以"功能就绪、分发未就绪"这句到 P13 为止没有被任何一轮推翻过，也没有被推进过——
推进它的那三项不在代码里。**

**P13 顺手记下的一条新的开放项（不阻塞）**：守护页页头副标题写的是
「摄像头与麦克风的当前占用（手动测量，非实时监听）· TCC 授权只读视图 · 登录项管理」——
三件事，而这一页现在有四张卡。从前那第四张叫「系统活动」，名字和"活动"这词一样含糊，所以没人发现少写了；
P11c 把它改成「密钥与自启配置的改动时间」之后，**副标题成了全站唯一一处还残留旧口径的地方**
（源码里 `log show` 零命中、测试里零命中、设计稿已同步，只有这一行是"卡改名了但页头没跟"）。
记为 `fidelity-guardian.md` 的开放项，改法是一行文案，归下一轮。

### 7.5 P14：同一套三步在**带页头合同改动**的二进制上第四遍重跑，并量了"这句话放不放得下"（2026-10-05）

§7.4 末尾那条 **D1** 在这一轮关闭（`fidelity-guardian.md` §8.1）：副标题改成由 `GuardianPageCopy.subtitleSegments`
一份清单生成，段数由 `GuardianHeaderContractTests` 钉住。跑法与前三遍相同，产物 `/tmp/mm-app-p14`，
证据 `docs/verification/p14-v1/`（三张）+ `docs/verification/p14-header/`（三张）。

| 判据 | 量到的 | 出处 |
| --- | --- | --- |
| 第 1 步 全量测试 | **583 / 0 / 1**，逐包求和 = 583（MMGuardian 91 → **95**） | `./Scripts/run-all-tests.sh` |
| 第 2 步 候选产物 | plist `1.0.0` / `1` / `CFBundleIconFile=AppIcon`，`flags=0x2(adhoc)`、`TeamIdentifier=not set`，`spctl` 判 `rejected` | `p14-v1/02-about.log` 的 `# plist:` / `# codesign:` / `# spctl:` |
| 第 3 步 版本链闭合（第四遍） | 同一屏「版本 1.0.0 (1)」+ AppIcon 本体 +「尚未选择许可」+「未配置官方渠道」+「反馈问题」灰着 | `p14-v1/02-about.png` |
| **本轮新判据**：四段副标题放不放得下 | 三档窗口（1100×700 默认 / 请求 1000×600、实际 **1000×652** 被 `minHeight` 夹 / 1400×900 控制组）**四段全在，无 `…`**；最窄档末尾距「刷新」不到三个汉字宽（照片 2× 估读） | `Scripts/p14-header-capture.sh` → `p14-header/0{1,2,3}-*.png` |
| 合同测试的**否证实验** | 把第四段从数组里删掉 → `Executed 4 tests, with 2 failures`，两条消息分别报"4 张卡 vs 3 件事"和"最后一段不是卡自己的标题" | 同 `GuardianHeaderContractTests`，跑法 `swift test --package-path Packages/MMGuardian --filter GuardianHeaderContractTests` |

**为什么要为一句副标题单开一支脚本**：`MMPageHeader` 的副标题写 `.lineLimit(1)` + `.truncationMode(.middle)`，
所以把 3 段改成 4 段**不会**换行、**不会**溢出、**不会**让任何一条测试变红——它唯一的可见后果是画面上多一个
省略号，而切掉的正好是"登录项管理"这种少看一眼也不觉得少了的词。**单测钉得住"段数对不对"，钉不住"这一句放不放得下"，
所以这两件事分别用一支测试和一组照片管**（同一条口径见 `hook-ledger.md` §5 的 P14 两条）。

**四遍重跑的差别只有一处**：571 → 581 → 579 → **583** 个测试，产物四遍都是 `1.0.0(1)` / adhoc / `rejected`，
版本链四遍都闭合。**判定仍然没变**：第 4 步那三项（许可、`NSHumanReadableCopyright`、签名方式）是人的决定，
不在代码里。改名残留这一轮扫完（`fidelity-guardian.md` §8.3 那张处置表），
顺带照出**第三个表面**——落地页从未与实现对照过，已进 §6 表格单独一行（**P17 已把它逐句对照完、并换成夹具实拍**，§7.8）。

### 7.6 P15：§10 第 1–3 步第五遍重跑，同时把"三处子进程调用"并成一处（2026-10-05）

P15 动的是**取数那条路**（`Process` + `Pipe`），不是任何一屏的画法：三处启动点并成
`MMCore/CommandRunner.swift`，`launchctl list` 那一路加上 10 秒时限，tmutil 那一路改为解析同一份输出。
所以 §10 三步照跑（产物 `/tmp/mm-app-p15`，`VERSION=1.0.0` / `BUILD=1`），判据多了一条：
**并完之后，屏幕上那句话在这台机器上还是不是真话**。证据 `docs/verification/p15-v1/`（三张）
+ `docs/verification/p15-pipe/`（两张照片 + 一份否证日志）。

| 判据 | 量到的 | 出处 |
| --- | --- | --- |
| 第 1 步 全量测试 | **590 / 0 / 1**，逐包求和 = 590（MMCore 43 → **48**、MMFileScanner 116 → **117**、MMGuardian 95 → **96**） | `./Scripts/run-all-tests.sh`，日志 `/tmp/macmaster-tests/` |
| 第 2 步 候选产物 | plist `1.0.0` / `1` / `CFBundleIconFile=AppIcon`，`Identifier=com.macmaster.app`、`flags=0x2(adhoc)`、`TeamIdentifier=not set`，`spctl` 判 `rejected` | `p15-v1/0{1,2,3}-*.log` 的 `# plist:` / `# codesign:` / `# spctl:`（三份逐字相同） |
| 第 3 步 版本链闭合（第五遍） | 同一屏「版本 1.0.0 (1)」+ AppIcon 本体 +「尚未选择许可」+「未配置官方渠道」+「反馈问题」灰着；1000×600 那一档「交换 680.2 MB / 2.15 GB」整行可读 | `p15-v1/02-about.png`、`p15-v1/03-dashboard-min.png` |
| **本轮新判据**：并完执行器之后界面还是真读数 | 登录项卡：expect 行 `launchctl-list-bytes=18959`、`login-item-files=17`、`not-loaded-labels=2 com.sogou.SogouServices com.sogou.SogouTaskManager` → 照片上**卡头 17 项**、**两条橙色「没在当前会话里加载」**，逐字对得上。快照那一屏：`tmutil-bytes=21 / snapshot-lines=0` → 画面「本地快照 0 个」+「这台 Mac 目前没有本地快照。」 | `Scripts/p15-pipe-capture.sh` → `p15-pipe/0{1,2}-*.{png,log}` |
| 合同测试的**否证实验** | 把 `CommandRunner` 改回"先 `waitUntilExit()` 再一次性读" → 两条 >64 KB 用例 `failed (10.095 / 10.017 seconds)`，报的都是 `caught error: "timedOut(10.0)"`。**报的是超时、不是"字节数不对"**——这条区分很重要，它说明死锁真实存在、只是被超时拦下来了；如果没有超时，这两条用例会永远挂着 | `p15-pipe/negative-control.log`（含还原过程与还原后的 590/0/1） |

**为什么这一轮值得单独记**：P11 那条教训（"没发作"不等于"写对了"）在 §3 挂了一整轮没闭，
因为当时只改了出事的 `scanUnifiedLog` 一处，另两处被写成"输出小所以没发作"就放下了。
P15 去量了那两个"小"到底多小（tmutil 21–22 字节 / launchctl 18,541–19,540 字节），
**然后按这两个数做了两件不同的小事**：读侧加时限（超时只会少一句结论，不会说一句假话），
写侧**不加**时限（"没等到回话"如果被写成"没改成"，就是一句会被用户当真的假话）。
这两条决定都写进了源码注释，判据在 `CommandRunnerPipeTests`（5 条）+ `LaunchctlRunnerTests`（1 条真机只读）。

**五遍重跑的差别只有一处**：571 → 581 → 579 → 583 → **590** 个测试，产物五遍都是 `1.0.0(1)` / adhoc / `rejected`，
版本链五遍都闭合。**判定仍然没变**：第 4 步那三项（许可、`NSHumanReadableCopyright`、签名方式）是人的决定，
不在代码里。

### 7.7 P16：文档里的位置引用第一次逐条落盘验过（2026-10-06）

P15 之后代码一行没动，这一轮验的是**另一类会烂的东西**：入库文档里那 545 处 `文件:行号` 引用
（收口那一跑的数；改前那一跑只认出 541——差的 3 条是抽取器静默漏掉的两份文档里的，见下面第 1 条）。
动手的理由是 §8 挂了三轮的那条账——`.gitignore` 排掉了参考仓库目录，
"别人 clone 之后那些引用是断链"——这句话一直是**散文**，没人把它变成数。
现在它是 `./Scripts/p16-citation-audit.sh` 的报告，跑一次 40 秒，退出码当门。

| 判据 | 抓什么 | 改前那一跑抓到 | 现在 |
| --- | --- | --- | --- |
| 命中面 | 引用路径按后缀能不能定位到真实文件（本仓库/参考仓库/SDK/都不到） | 都不到 **0**（上一轮已修 4 处写错目录的） | 0 |
| 唯一面 | 同一条路径在本仓库命中两个文件 = 引用不自证是哪一篇 | **0**（判据来自 Pearcleaner 那份有两件 `main.swift` 的仓库） | 0 |
| 行号面 | 区间结束行超过文件末尾 | **1**（引用写的是第 211–224 行，那份 `MMFileScanner.swift` 现 168 行）← 引于 `docs/analysis/feature-roadmap.md` 第 14 行 | 0 |
| 空白面 | 引用的那一段整段只有空白 | **11** | 0 |
| 符号面（**只提示，不进退出码**） | 那一行上到底有没有文档主张的那个成员 | 手工核对时抓出 **4 类**（`colorForSize`/`cardBackground`/`runOptimization`/`UninstallerModel.headerSubtitle` 全都不存在了） | 死符号 **0** / 位置存疑 96 |

**这一轮真正的产出不是那 12 处改对了的引用，是"0"这个数差点是假的**。三件只有跑过才知道的事：

1. **抽取器自己会漏文件**。`git ls-files` 默认 `core.quotePath=true` 把非 ASCII 路径包成
   `"docs/technical-analysis/01-\347\253\236…"`，于是那两份中文名文档既进不了索引、
   又在抽取阶段被 `[[ -f $md ]]` 静默跳过——**报告照样打"31 个入库 .md"**，实际抽了 29 个。
   代价是可量的：改完之后唯一引用从 541 条涨到 544 条，**漏的不是 2 份文档，是那 3 条从没被验过的引用**。
   暴露方式是否证原型在别处崩了 `awk: can't open file`。修法：四处调用全部加
   `-c core.quotePath=off`，并让报告自报 `# docs scanned: 31 个真抽了 / 31 个入库 .md`（两个数不等就是有文件没被读到）。
2. **符号面第一版看不见 `类型.成员`**。标识符正则 `^[A-Za-z_][A-Za-z0-9_]*$` 不接受点号，
   所以写成 `` `MMOptimizer.deleteSelected` `` 的那类主张**根本不会进判据**——而改名之后的旧写法
   恰恰最爱这么写。否证跑（`negative-control-symbols.log`）拿同两行新旧对照：旧抽取只认出 1 个符号、
   改后认出 2 个，所以改前报的"死符号 0"里有一半是**没在看**。
   顺带定了一条：末段不能拿"含大写"当筛子（`TreemapView.compute` 这种小写成员正是要查的那一种），
   改成按扩展名黑名单挡。
3. **判据会被自己的说明书喂活**。词汇表 = 全部跟踪源文件的原文 token，而这份脚本的注释按设计就要
   列举死符号；脚本一进 git，`colorForSize` 这些名字就会因为"审计脚本提到了它"重新变成活符号。
   所以词汇表构建显式排除本脚本自身，报告里 `# vocab: 7267 个 token` 自报条数。
   同类弱处还留了一条无法廉价修掉的：注释与字符串也算 token，`cardBackground` 因为
   `MMDesign.swift:41` 那句"上一版它叫 cardBackground"仍然活在词汇表里——记在脚本第 1 步①，不改判据。

**还有一条得写进所有后续文档的写法约束**：抽取器是机械匹配 `路径.ext:NN(-NN)?(,NN)*` 的，
所以**连"这个位置已经失效"这种说明文字也会被抓一次**——本轮改文档时自己踩到一次
（写了"本文此前记 MMDesign 那份的第 350 行"这种句子时，句子里带上了文件名、冒号和行号——
那正是被打回的第 2 条）。要记一个死掉的锚点，就写成散文（"记在某份的第 350 行"），
**别让文件名、冒号、行号连成一串**：抽取器不读语义，它只看形状，
一句"这个位置已经没了"在它眼里和一条真引用完全等价（这一段的上一稿自己就触发了两道判据）。

证据：`docs/verification/p16-citations/audit.log`（本轮正式跑，硬失败 0、退出码 0）
+ `negative-control.log`（四道硬判据各种一处坏引用）
+ `negative-control-symbols.log`（符号面两层 + 新旧抽取对照）。
参考仓库那一档的可达性写在新增的 `docs/analysis/reference-repos.md`：七个仓库各记 URL + 本轮钉住的
commit + `git ls-files` 条数，读的人一条 clone 就能把那 57 条引用变成可打开的（`docs/Mole` 那份是
**只有 .git 没有工作树**的空壳，tracked=0，报告里逐字自报，不混进"可补"那一档）。

### 7.8 P17：落地页第一次逐句对着实现读，然后把它变成有照片的一页（2026-10-06）

P14 照出、P16 记过账的那个**第三个表面**——`docs/website/index.html` 不在任何一张对照表里——
这一轮过了三遍：P17a 逐句判定（`docs/analysis/website-audit.md` §1 十六行判定表），
P17b 按判定表改文案与死链，P17c 把四个占位框换成夹具档实拍。代码一行没动。

| 判据 | 抓什么 | 抓到 | 现在 |
| --- | --- | --- | --- |
| 每句主张有无实现 | 落地页文案 vs 界面与源码 | **3 行说不到**（对应 4 条主张：一键清理、更快更流畅、两个下载按钮）+ 2 行需标注 | 全部改掉；判定表保留审计当时那一版 |
| 计数自证 | 判定表小结那一句的八行分布 | **"8 条真"是错的，逐行重数是 9 条**（漏了第 14 行"适用于 macOS 14.0"） | 已改成现读数 |
| 链接可达 | 页面上每一个 `href` | 末屏主 CTA `href="#"`；两个猜测的 GitHub 仓库地址 `curl` 回 **404** | hero CTA 改指 `#features`（能跳）；末屏换成「现在还没有能下载的安装包」+ 两条真跑得通的构建命令；**仓库地址留成占位，不放没验过的 URL** |
| 截图面 | 四个占位框能不能用现成照片填 | 仓库里当时 47 个 `docs/verification/` 目录全是**真机实拍**（真实卷名占用、真实登录项、真实密钥目录 mtime） | 新脚本 `Scripts/p17-website-capture.sh` 四档夹具实拍 |

**这一轮最值钱的两条是实拍时才浮出来的夹具覆盖边界**（都写进 `website-audit.md` §3，
判据与照片侧的说明见 `hook-ledger.md` §4 那一支新行）：

1. **清理屏拍不到"缓存清单的夹具态"**：`MM_PURGE_FIXTURE_HOME` 只换「开发产物」那一页的扫描根，
   第一个 tab 进页即 `model.scan()` 扫真机。所以 01 那张是 dev tab，卡片标题写「清理 · 开发产物」——
   不是文案偏好，是钩子覆盖面决定的。
2. **侧栏的卷信息条与磁盘页的「卷可用」没有任何钩子能碰**，整窗截图必然带上真实卷名与占用。
   本轮选择**在页面上明说**而不是裁掉：裁切后的截图不再是产品里那一屏，而裁掉本身就是在藏一件事。
   这条决定同时写进了 `index.html` 里那条 img 规则的注释，免得下一轮"顺手裁一下"。

顺带一条形状上的收获：`.html` **在引用审计脚本的扩展名清单里**，所以分析文档里那种
"落地页第几行"的锚点会随页面重写而漂走。P17a 判定表原本有四条这样的锚点，本轮**改成散文**
（写法约束的出处仍是 §7.7 最后那段）。**会被整段重写的文件，别用行号锚点指它。**

**未做**：不发布（`website-audit.md` §5）；页脚 `© 2026` 那行照 §4 留着——它和 §2.3 的许可、
`NSHumanReadableCopyright` 是同一批人的决定。

证据：`docs/verification/p17-website/capture.log`（四档 env 逐字记录 + 产出的宽高体积，带归因头）
+ `docs/website/assets/0{1,2,3,4}-*.png`（2560×1600，即 1280×800pt @2x）。
页面渲染态本轮用 headless Chrome 整页看过（`--window-size=1440,4200 --screenshot`）；
应用侧四张仍旧全部来自带窗口的真机进程——**这两件事不要混为一谈**。

### 7.9 P18：钩子写错值时"照片会不会说谎"——第一轮以 stderr 而不是照片为判据的取证（2026-10-06）

这一轮没有加功能，问的是另一个问题：**`docs/verification/**` 那 50 个目录里的照片，
是不是每一张都能回到它自己那一档钩子取值**。钩子写错不会让界面报错，只会让页面**安静地停在
另一档**，而那张照片看上去和"生效"完全一样——这是取证里最贵的一类错误（假通过），
而且它**不会在任何一次构建或测试里暴露**。

- **分类先于动手**（`docs/analysis/hook-typo-audit.md` §1）：按"写错之后那张照片变成什么"把 52 个名字分成四类。
  A 类本来就会说话（3 个）、**B 类静默换档（16 个，本轮全部关掉）**、
  C 类"非空即生效"（7 键 / 13 处，`MM_AUTO_SCAN=0` 也算开，**故意不改**，理由与逐处坐标在 §5）、
  D 类写错另有旁证（`MM_SHOW_TOAST` 自报画的是哪条吐司）。
- **判定下沉**：新增 `Packages/MMCore/Sources/MMCore/HookValues.swift`（169 行）——
  `MMHookValue.selected/int/flag` + `MMLaunchHook.resolveAppearance/resolveWindowSize`，
  留痕文案由**纯函数**生成，所以能单测；`emit()` 是留痕的唯一出口（stderr），
  并且有一条 `dup`/`dup2` 到 fd 2 的测试钉住"这行话真的落在 stderr"而不是落在某个字符串里。
  规则统一成四条：未设置/空 = 生产路径不留痕；有值对不上 = 回落默认档 + 一行；比较前 trim + 小写；
  **`accepts` 由档位表现算**（文档不可能和实现各说一套）。
- **一处是真安全洞，不是取证洞**：`MM_PURGE_FIXTURE_HOME` 的三条越界分支（非 /tmp 前缀、
  `realpath` 失败、解引用后跳出 /tmp）改前全部静默 `return nil`，而 nil 回落的是 `NSHomeDirectory()`。
  写错一个字母 = 把"拍夹具"换成"拍用户真实项目，且那一屏每一条都可勾选、可删"。
  现在三条各留一行并点名"扫描根将是真实 home"。
- **`static var` → `static let` 是被日志逼出来的**：`scanHome` 在 `body` 求值里被读多次，
  计算属性会把那一行留痕刷成刷屏。本轮撞过两次（`fixtureHome`、`rootBudgetSeconds`）。
- **最阴的一支是 `Double("nan")`**：预算钩子改前是 `Double(token) ?? 默认` + `>0`，
  而 `Double("nan")` **能解析**、`nan > 0` **是假的** → 静默回落。
  拍出来的"预算 15 秒"照片与钩子一个字节关系都没有，日志也一行不留（§2 末）。
- **门禁**：`Scripts/p18-hook-typo-proof.sh`，**23 档全绿**（`核对 23 档，失败 0 档`，
  `docs/verification/p18-hooks/capture.log` + 18 张带窗口实机照片 + `raw/` 原始 stderr）。
  判据在 stderr：每档注入一个**故意写错**的取值，`expect=` 逐档钉住那一行话的片段；
  负向档（`expect=-`）反过来要求"这一档一条留痕都不许多说"。
  **五档（10/11/13/21/22）只收日志不拍照**：它们的失效分支回落的是用户真 home / 真实扫描根，
  画面内容取决于机器现状——**取证不该把真 home 拍进仓库**，这一条是主动的边界，不是漏拍。
  零合成点击（原生按钮收不到合成事件，见 `AGENTS.md`），只 kill 自己起的 pid，隔离构建在 `/tmp/mm-app-p18`。
- **工具自己坏过两次，都修在脚本里**（§6）：① `ONLY='1[348]'` 在 zsh 里匹配不到任何档 →
  脚本打印"全部 **0** 档符合预期"并 **exit 0**（**绿色的空跑**，门禁工具最坏的失效：
  报错的形态和通过长得一样）。现在改成逗号前缀列表，且 `checked==0` 直接 `exit 2`。
  ② `ONLY` 重跑曾把整个证据目录 `rm` 掉，让剩下两份证据说不同的话；现在局部重跑写自己的日志文件，
  一个字不碰既有照片。
- **发版判定有没有变？没有。** 这一轮改的是**截图流程的可靠性**，不是任何一条对外主张：
  §10 的第 1 步在带 P18 改动的源码上重跑 = **612 / 0 / 1**（MMCore 48 → 70，其余八包一个数没变），
  第 2、3 步那三张候选产物照片**没有重拍**，也没有理由重拍（它们测的是版本号链与签名状态，
  钩子不参与）。仍然卡在第 4 步那三项人工决定上。
  **这一句在 P19 被改窄了**：那三张照片当轮确实不必重拍（钩子不参与版本号链），但"不必"的理由不是这个，
  是"那一轮没有新的候选产物"；§7.2 那条合同不按改动属于哪一族豁免，见 §7.10。

### 7.10 P19：§10 第 1–3 步在**带 P18 改动**的二进制上第六遍重跑，并让候选产物自己说得出是哪棵树（2026-10-06）

**为什么要跑这一遍**：P18 动了 **11 个生产源文件**（另两支是新增测试），而 §7.2 立的那条合同是
"第 3 步的照片要在**发版候选产物**上重拍一次才算闭合"——它不按"改动属于哪一族"豁免。
这一轮有了新候选产物，所以跑。

| 判据 | 量到的 | 出处 |
| --- | --- | --- |
| 第 1 步 全量测试 | **612 / 0 / 1**，MMCore 70、MMGuardian 96，逐包与 §1 那行一致（九包没有一个数变，P19 没动业务源码） | `./Scripts/run-all-tests.sh` |
| 第 2 步 图标自证 | `✓ 反向解出 10 档；1024 档 270,169 字节`——与 §7.3/§7.4 那一遍**同一个数** | `./Scripts/make-icon.sh --check` |
| 第 2 步 候选产物 | plist `1.0.0` / `1` / `CFBundleIconFile=AppIcon` / **`MMGitCommit=0dec4f7`**，签名 `flags=0x2(adhoc)`、`TeamIdentifier=not set`，`spctl` 判 `rejected` | `p19-v1/0{1,2,3}-*.log` 的 `# plist:` / `# codesign:` / `# spctl:` 三行 |
| 第 3 步 版本链闭合（第六遍） | 关于页同一屏「版本 1.0.0 (1)」+ AppIcon 本体 +「尚未选择许可」+「未配置官方渠道」+「反馈问题」灰着 | `02-about.png` |
| 第 3 步 最小窗口不截 | `MM_WINDOW_SIZE=1000x600` → 实际 `1000x652pt`（被 `.frame(minWidth:minHeight:)` 夹住），交换行整行可读 | `03-dashboard-min.png` + 同名 `.log` |
| **3g 第一次跑在发版候选产物上** | **核对 23 档，失败 0 档**；照片 18 张、逐档原始 stderr 23 份 | `p19-hooks/capture.log`（`./Scripts/p18-hook-typo-proof.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p19-hooks`） |

**本轮真正的产出不是"又绿一遍"，是发现候选产物不能自证它是哪棵树构建的。**
P12 / P13 / P15 / P19 四轮的产物版本号逐字相同（都是 `1.0.0(1)` + adhoc），
而取证日志的归因头当时只有日期与 `.app` 路径——`docs/verification/p15-v1/` 那三张照片
今天说不出自己出自哪一次改动。更麻烦的是**两棵树会分开**：
"跑取证脚本的那棵树"和"被测二进制打包时的那棵树"，在"改完脚本再拿旧产物跑一遍"时不是一回事，
而本轮第一遍正好撞上这件事（产物是 `6922058`，取证脚本的改动还没提交）。
补法三段，都在 `Scripts/`（提交 `0dec4f7`）：
- `make-app.sh` 往 `Info.plist` 写 **`MMGitCommit`**（自定义键，系统忽略；值 = `git rev-parse --short HEAD`，
  工作区不干净时后缀 `-dirty`）——产物从此自己带着自己的出处；
- `p7-release-check.sh` 把它读回来打进 `# plist:` 那一行，`p17-website-capture.sh` /
  `p18-hook-typo-proof.sh` 各加一行 `# app-repo:`，与它们新加的 `# repo:`（**跑脚本的那棵树**）并排；
- `p16-citation-audit.sh` 原有的 `# repo:` 补 `-dirty` 后缀。
三处都用 `git status --porcelain -uno`：这几支脚本自己正在往证据目录里写未跟踪的日志与照片，
算进脏活就永远 `-dirty`，那个后缀就没信息量了。
**代价立刻出现了一次**：往 `make-app.sh` 的 plist 模板里插两行，把下面 `LSMinimumSystemVersion` 那一对键
推下去 10 行，于是 `website-audit.md` 里指它的那条引用漂了——四道硬判据全绿，只有符号面 +1。
判据与改后的锚点记在 §1 那一格的"99 → 100 → 99"里（**改脚本会漂文档，这条在 §7.7 早就写过，本轮又应验一次**）。

**本轮第一遍的证据被第二遍盖掉了**，这里记一句为什么：同一轮里旧那两份多出来的信息只有一句
"它们还没有归因行"，而这句话写在本节里比留在证据目录里合适——留两份只差 8 分钟、
内容几乎逐字相同的 `p19-v1/` 与 `p19-v1-old/`，只会让下一轮多一个要猜哪个作数的目录。

**顺带量到的一条（关于照片本身）**：`p18-hooks/` 与 `p19-hooks/` 那 18 对同名照片里，
**17 对逐字节不同、只有 `07-pane-typo.png` 相同**。不同的那 17 张不是拍错了，是画面上本来就有实时值
（侧栏卷名与占用百分比、CPU 环形进度、右下角"数据更新于"）。所以
`md5 -q *.png | sort | uniq -d` 那把哨兵**只在同一批内有意义**（它查的是"两档拍到同一张图"），
跨批次相同不代表重复，跨批次不同也不代表变化——这一条以前没写在任何地方。

**第 4 步仍是 ⬜**：许可、`NSHumanReadableCopyright` 的年份与权利人、签名方式选定，三件都不是代码决定。
**六遍重跑的差别只有一处**：测试数 571 → 581 → 579 → 590 → 612 → 612，
产物六遍都是 `1.0.0(1)` / adhoc / `rejected`，版本链六遍都闭合。
"功能就绪、分发未就绪"这句到 P19 为止没有被任何一轮推翻过，也没有被推进过。

### 7.11 P20：§10 第 1–3 步**第一次整棵树上没有一样东西没进版本控制**（2026-10-06）

**为什么要跑这一遍。** P19 让产物自证出处，但"出处"还有一层没人问过：**这套门禁换一棵树还跑不跑得动**。
前六遍全跑在作者自己的工作树上，而那棵树里有一堆 `git` 看不见的数据（七个参考仓库、两个空取证目录、
上一轮的夹具）。同一棵树核验到第七遍，边际信息接近零。所以这一遍的判据不是"又一个 612"，而是
**除了 `git clone` 能带走的文件，什么都不借**。

**做法**（四条命令，全在 `/tmp/mm-p20-clone` 那棵 `git clone --no-local` 出来的树上，771 个跟踪文件）：

```bash
git clone --no-local /Users/lee/Desktop/MacMaster /tmp/mm-p20-clone
cd /tmp/mm-p20-clone
VERSION=1.0.0 BUILD=1 ./Scripts/make-app.sh -o /tmp/mm-p20-app -s /tmp/mm-p20-scratch
./Scripts/run-all-tests.sh
./Scripts/p7-release-check.sh /tmp/mm-p20-app/MacMaster.app docs/verification/p20-clone   # 实跑时 OUT 给的是绝对路径
```

| 判据 | 值 | 出处 |
| --- | --- | --- |
| 干净克隆能直接出产物 | `Build complete! (22.48秒)`，**没有任何人工准备步骤**：`Resources/AppIcon.icns` 在库里，`make-app.sh` 看见它才写 `CFBundleIconFile` | 克隆树 `make-app.sh` 输出 |
| 构建不联网 | 全仓 `Package.swift` 里 `.package(url:` **零命中**（九个包全是 `.package(path:)`）→ 没有 `Package.resolved` 也不是缺陷 | `grep` 现读 |
| `MMGitCommit` **两个方向**第一次都验到 | `Info.plist` 里 `b2b3718`，**不带 `-dirty`**。P19 只验过"脏树要加后缀"那一支，"干净时不加"这一支此前从没跑到 | plist 现读 |
| 第 1 步换树不变数 | **612 / 0 / 1**，逐包 70 / 17 / 117 / 18 / 121 / 66 / 53 / 96 / 54，与作者树**逐包相同** | `run-all-tests.sh` 在克隆里跑 |
| 第 3 步三张照片 | 关于页仍是 `版本 1.0.0 (1)` + 真 AppIcon + `尚未选择许可` + `未配置官方渠道` + 灰着的`反馈问题`；`MM_WINDOW_SIZE=1000x600` 仍被夹到 `1000x652pt` | `docs/verification/p20-clone/` 三张照片 + 三份 `.log` |
| 两棵树的归因行**第一次两边都干净** | `# repo: b2b3718 branch=main`（跑脚本的树）与 `# plist: … MMGitCommit=b2b3718`（被测产物）相等、都不带 `-dirty`。P19 那一跑两个数也相等，但那棵树刚被本轮自己改脏又提交，**"两边都干净"是第一次** | 三份 `.log` |
| 签名档次复现 | `flags=0x2(adhoc)`、`TeamIdentifier=not set`、`spctl … rejected`——与 P19 逐字相同 | 同上 |

**这一遍真正撞出来的东西：引用门禁在别人机器上连报告都出不来。**
克隆树里跑 `./Scripts/p16-citation-audit.sh`，退出前只留下一行
`no matches found: docs/github-references/*`。那三个目录都在 `.gitignore` 里，
而 **zsh 默认 NOMATCH**——glob 抽不到东西不是"空"而是**报错**，脚本又开了 `set -e`，
于是那条 `for d in docs/github-references/* docs/Mole docs/lemon-cleaner` 直接打死整条脚本，
**下一行的 `[[ -d $d ]] || continue` 根本没机会跑**。
最难受的是这脚本**早就为"参考仓库没克隆"写过降级逻辑**（报告里那一格全名就叫
"定位不到文件因而没试行号判据的（参考仓库没克隆时走这一支）"），可它一次都没被跑到过——
P16 写下这条判据、P17/P18/P19 拿它收口三轮，没人从一棵干净的树上跑过一次。
改法是给那一个 glob 加 `(N)` 限定符（只让它允许空，不动全局行为）。

**修完之后的降级实测**（克隆树、参考仓库仍缺）：675 / 580 / **命本仓库 522 一字不变**、
命参考仓库 **0**、两头都不到 **57**、定位不到文件 **57**、行号判据实际跑过 **523** 条、**exit 1**。
**它该失败**——57 条引用打不开的时候，不能签字说"文档没问题"。但失败得说清是"没取到"还是"写错了"，
所以报告里补了三行 `# ref:`，把取法指到一条命令上，而不是留一个 0 让人自己猜。

**新增 `Scripts/clone-references.sh`：判据来自文档，脚本里不另存一份 commit。**
它逐行现读 `docs/analysis/reference-repos.md` §2 那张表（第二列 URL、第三列 40 位 commit、第四列本地路径），
默认 `--check` 只报状态、`--fetch` 才联网（**默认不联网是刻意的**：往仓库树里下载第三方代码这件事该由人发起）。
表形一变（列序、格式、抽出的行数少于 6）它**大声退出**，而不是静默少抽一行。实测三档：
作者树 7 行全"对"（**这是第一次把"文档里钉的 commit"和"磁盘上的 HEAD"对起来**，七份逐字相同）；
克隆树 7 行全"缺" + exit 1 + 一句人话；`--fetch` 之后七个仓库按 sha 浅取全部到位（159 MB，
不走 `--unshallow`——我们只要那一份文件树，不要全部历史）。
**再跑引用门禁：675 / 580 / 522 / 57 / 1，两头都不到 0、越界 0、整段空白 0、死符号 0、位置存疑 99、exit 0
——与作者树逐位相同。** 发版前 checklist 第 3e 步从此在别人机器上也跑得动。

**改完下面这五处、并写完本节与 §10 之后，在作者树上重跑了同一道门**
（`docs/verification/p20-clone/audit-author-tree.log`）：**680 / 585 / 527 / 57 / 1**，、越界 **0**、整段空白 **0**、歧义 **0**、死符号 **0**、位置存疑 **98**、**硬失败 0、exit 0**。
三个数各涨 5（条次 675→680、唯一 580→585、命本仓库 522→527）而"命参考仓库 57 / 命 SDK 1"一动没动——
**这五个增量是本轮新写的锚点，不是同一处引用被数了两遍**（这是从三个增量相等推出来的，
明细里"本仓库引用漂了"那一节两边都是空的）。`# index:` 从 771 涨到 780，涨的正好是本轮新入库的
九份文件（`p20-clone/` 八份 + `clone-references.sh` 一份）。位置存疑 99→98 只记数不记因：
那一节只列前 40 条，两跑之间哪一条退出的名单没法从报告里读出来，而它是**提示面**、不是门。
**这一轮三份日志没用脚本默认的 `audit.log`**：那一跑不给参数、报告只走 stdout，而 stdout 最后一行
"`# 硬失败…: 0`"是脚本**写完文件之后**才打的——默认名那份永远不含它（P19 的 `audit.log` 就不含）。
`audit-{clone-without-refs,clone-with-refs,author-tree}.log` 三个名字一眼分得清是哪棵树、哪一档。

**顺带收掉五处"文档之间互相打架"**（都是 P20 现读出来的，不是从上一版抄的）：
1. README 写"沙盒会打断哪**七条**现有能力"，而本文 §3 结论 4 早就定了"发版说明里现在写**六行**才对得上当前二进制"。
   README 已改，并把"七行是 P11 那张表的行数、六行是当前二进制"这个区别写进正文。
2. README 写 checklist 1–3 步"已实跑**五遍**"——落后两轮（P19 第六遍、P20 第七遍），已补成七遍并逐遍列出证据目录。
3. `fidelity-disk.md` 三处（§0 的"一处真硬伤"、§2 的 I1 表行、§提请协调者第 1 条）还写着 `MM_DISK_SCAN`
   **没有** /tmp 越界拦截，而源码里守卫在 `MMDisk.swift:171-176`、`MM_DISK_SELECT` 在同文件 `:1086-1094`，
   **同一篇文档靠后那张"改前 → 改后"的改锚表里这件事已经记过一笔**。四道硬判据对这种错完全无感：
   改前那条锚点指过去的行存在、非空白、不歧义，只是那一行已经不是那件事了（§7.7 那句"路径存在、说法不成立"的最新样本）。
4. `fidelity-cleaner.md` I5 写"全仓 **10** 个调用点"、本文 §6 写 **11** 个。现读 11，
   差的那一个不是漏看而是**命令本身罩不住**：旧命令
   `grep -n 'MMFailurePanel(' Packages/*/Sources` 的 glob 只展开 `Packages/<模块>/Sources`，
   而壳层在仓库根的 `Sources/MacMaster`，永远不在搜索范围里。判据已换成能罩住壳层的那一条，
   顺带把旧列表里漂了的六个位置一并更正。
5. `module-priority.md` 那串"372 项测试"是 2026-09-30 基线的原始记录（那份文件按设计不跟着轮次改），
   P20 给它补了一句"这是快照不是台账"——**标了日期的旧数字和没标日期的，被误抄的概率差很多**。

**第 4 步仍 ⬜**：许可、权利人、签名方式三件都不是代码能决定的。
**七遍重跑的测试数序列**：571 → 581 → 579 → 590 → 612 → 612 → 612，产物七遍都是 `1.0.0(1)` / adhoc / `rejected`。
**这一遍没有推进"能不能发"，推进的是"别人能不能自己验一遍"**——这两件事在前六轮里被混着用。

### 7.12 P21：删除闸门补两条系统根，并让磁盘页的风险标签与闸门同源（2026-10-06）

这一轮改的是**同一件事的两端**：`DeletionGuard` 执行时拒不拒，和磁盘页给某一行的"标进回收清单"按钮。
判据只有一条方向：**闸门按字面路径拒绝的，界面就不许说可以标**（`DiskRisk.swift:33` 那行兜底问句）。
反方向不成立——标签比闸门严的地方留着（六个用户目录的**内容**、`/LibraryFoo` 那种前缀误伤），
**少给一个按钮不是假话，多给一个才是**。

**代码四处**（`git diff --numstat HEAD` 现读，全在这条链上）：
1. `DeletionGuard.swift:32` 的 `systemRoots` 补 `/dev`、`/private`。判据不是"看着像系统目录"，
   而是**这两个名字早就被别处对外说成了"系统树"**——磁盘页的 `DiskRemoval.systemFirstComponents` 一直这么写，
   两份清单口径不一就是这一条。
2. `DeletionGuard.swift:83` 新增 `literalRejection(for:)`：**只按字面路径判，不调 `realpath`**。
   为什么不复用现成的 `rejection(for:)`：标签是在 SwiftUI body 里**逐行**算的，
   把 `realpath` 放进那一层等于每次布局给每一行发一次系统调用。两问的判据由一条单测钉住不许分家。
3. 磁盘页的 `risk(of:)` 从 `MMDisk.swift:1052` 提出到 `Packages/MMDisk/Sources/MMDisk/DiskRisk.swift`
   （37 行）。提出来的理由不是整洁：**它此前一行测试都没有**，而它内联在视图里时也没法测。
4. `Packages/MMDisk/Package.swift` 给 `MMDiskTests` 加 MMCore 依赖——那条"标签不许和闸门唱反调"的属性测试
   要同时问两边，没有这条依赖就只能自证。

**+9 条判据**（612 → **621**）：`DeletionGuardTests` +3（`/dev`、`/private`；临时目录与 Homebrew 前缀不许误伤；
字面问与全量问一致），`DiskRiskTests` 全新 6 条（闸门拒的那批不再给按钮、新系统根显示为只读、
比闸门严的标签保持原样、正常可清理项没被误降级、31 条路径的抽样合同、注入 home 不放松闸门）。

**证据分三份，因为这一轮要拍的东西里有一格拍不了**：
- `docs/verification/p21-v1/`——§10 第 3 步**第八遍**，跑在带本轮改动的 `1.0.0(1)` 候选产物上
  （`MMGitCommit=95866d9-dirty`、adhoc、`spctl: rejected`）。关于页那张闭合的仍是版本链，本轮没动它。
- `docs/verification/p21-disk/`——磁盘页删除面板**四档重拍**（回收 / 未勾选 / 已勾选 / 回执条），
  四行带数字的回执与 `docs/verification/p68-disk/` **逐字相同**（"已选中 …/Downloads（50.3 MB）"、
  "确认面板（3 个标记）"……）。这一份要证明的不是新行为，是**改了标签判定没把删除路径改坏**：
  夹具大小固定，所以数字没变就是功能没变。
- `docs/verification/p21-disk-risk/risk-labels.log`——**这一格拍不了照**：闸门按字面路径拒的那批路径
  全在 `/tmp` 之外，而 `MM_DISK_SCAN` 只认 `/tmp`（越界整条忽略），所以界面上永远走不到那一档。
  替代物是 `Scripts/p21-disk-risk-probe.sh`：把 `Risk.swift` + `DeletionGuard.swift` + `DiskRisk.swift`
  **真源文件**编进一个合成模块（`swiftc -parse-as-library`），让表格由真函数产出而不是由人复述，
  唯一的机械改动是去掉 `DiskRisk.swift` 那行 `import MMCore`（脚本用行数检查守住：37 → 36）。
  表 34 条（固定 31 + 现场造的 3 条符号链接），**合同 1 违例 0 条**（脚本自己 `exit(1)`），
  **合同 2 残余 2 条**——这两条是本轮唯一没修的已知缺口，见下。

**残余那 2 条为什么故意留着**：它们是"标签看字面路径、闸门还会再解一次 `realpath`"的差集——
一个看着不在 `/System` 里的符号链接，字面放行、解析后落在 `/System` 里。要在界面上消掉它，
就得在 SwiftUI body 里对每一行 `realpath`（见上面第 2 条）。所以它被拦在**离删除更近的那一步**：
`DiskRemoval.plan()` 在拼"要删的清单"时问一次 `DeletionGuard.rejection(for:)`，
拒的写成 `blocked(reason: .guarded)` 摆进确认面板（`DiskRemoval.swift:98`）——
**用户看到的清单和真正会发生的事一致，就不算假承诺**。

**顺带还了两笔债**：
1. `risk(of:)` 提走 11 行，`MMDisk.swift` 那一条线以下所有行号整体 −11。六份分析文档加 README 里
   指向磁盘页的锚点**逐条现读重指**（`fidelity-disk.md` 五处、`hook-ledger.md` 六处、
   `disk-double-gate-review.md` 两处、`disktree-adoption.md` 一处、`deletion-guard.md` §1、本文那一格 P12 记的五处）。
   重指过程中发现**本文 §10 那五处 P12 时代的锚点在 HEAD 里就全是错的**（不是本轮改坏的）：
   五个数一个都没落在它声称的那行上，漂量整齐（19 行，入口那条 31 行），说明是后续某轮在上方法插入代码后没人回头改。
   **四道硬判据对这种错完全无感**——文件在、行号在范围内、不空白、不歧义，全过（"路径存在、说法不成立"的又一例）。
   这一条记进 §8。
2. `Scripts/p68-disk-capture.sh` 的日志**没有归因头**（P18/P19 立的规矩漏了这一支）：本轮那四张磁盘照片
   第一次拍出来时，日志说不出自己跑在哪棵树、产物出自哪棵树。修法是补 `# repo:` 与 `# app-repo:`
   （后者读产物 `Info.plist` 的 `MMGitCommit`），**然后重拍一遍**而不是手改日志——
   手改出来的归因头就是编的。上面那三份证据的日志都是修完之后重跑的产物。

**第 4 步仍 ⬜**，本轮没碰。八遍序列：571 → 581 → 579 → 583 → 590 → 612 → 612 → **621**，
产物八遍都是 `1.0.0(1)` / adhoc / `rejected`。**这一轮和 P19/P20 的区别要写清楚**：
那两轮一行业务源码都没动，这一轮动了四个文件、改了删除口径——所以它的"核验"含金量更高，
也正因为如此，四档重拍的回执逐字没变这一条才是本轮最该看的那个数。
> **P22 更正**：这一行从前写的是"571 → 581 → 579 → 590 → 612 → 612 → 612 → 621"——
> 它**漏了 P14 那一遍的 583，又多写了一个 612**，所以八个数其实只数到七遍。
> 上面 §0 那一格从头就是对的（它逐个点了 P14 的 583）。这不是本轮改坏的，
> 是本轮抄这一行时现读 §0 对了一遍才发现的：**同一份文档里两处数同一串序列，
> 一处逐点带名字、一处只写箭头，出错的是后者**。序列已按 §0 重排。

### 7.13 P22：磁盘页那句"未纳入 N 个受保护目录"数的范围与扫描不一致（2026-10-06）

病灶、改法、判据与照片逐条在 `fidelity-disk.md` §13，这里只记发版视角的那三件事。

**改了什么（一句话）**：扫描的"跳过受保护目录"判定在**每一层**都做，而徽章那句 N 只数根目录那一层
——两处读同一份名单、数的范围不一样，所以 N 是少报的，真机上最先漏的是第二层的
`~/Pictures/Photos Library.photoslibrary`（整目录不算面积，页面上也不提）。
记账换成贯穿遍历的 `ProtectedSkipLedger`，`skippedProtected` 的形态从"名字"变成"相对被扫根的路径"。
**没动扫描语义、没动删除口径**：跳过的字节本来就不进统计，这轮补的只是可见性。
代码 `MMDisk.swift` 2026 → **2068**（+42，一笔），判据 +1（622）。

**§10 第 1–3 步第九遍**（2026-10-06）：
- 第 1 步 **622 / 0 / 1**，逐包求和 = 622（§1）。这一遍的结论行**入库了**
  （`docs/verification/p22-citations/run-all-tests.log`）——前八遍都只把日志留在 `/tmp`，
  别人 clone 之后那一格引用的是一个不存在的路径。这是 §7.11"发版门禁只有作者机器跑得动"同一族的漏，
  本轮顺手补上，**从此每轮该归档的是结论行**（逐包原始输出仍留 `/tmp/macmaster-tests/`）。
- 第 2 步 `VERSION=1.0.0 BUILD=1` 出候选产物。
- 第 3 步三张照片在 `docs/verification/p22-v1/`：`01-dashboard` / `02-about`（"版本 1.0.0 (1)" + 真图标）/
  `03-dashboard-min`。归因头：`# repo: 0e36f97-dirty branch=main`、
  `# plist: CFBundleShortVersionString=1.0.0 CFBundleVersion=1 CFBundleIconFile=AppIcon MMGitCommit=0e36f97-dirty`、
  `# codesign: … flags=0x2(adhoc) Signature=adhoc TeamIdentifier=not set`、`# spctl: … rejected`。
  **签名与 Gatekeeper 那两行自 P19 起逐字未变**，第 4 步仍 ⬜。

**这一轮真正的收获是流程上的，不是那九张照片里的任何一张**：本轮中途把新加的视图辅助函数
`skippedDisclosure(_:)` 从 `DiskAnalyzerView` 前部搬到了末尾——**搬家是为了少还锚点债**
（放前部会让约 40 处文档锚点整体 +8，放末尾只牵动 3 处）。搬家之后重新构建、重新取证才发现：
**先前那一批照片跑的产物是搬家之前的**。归因头（`# repo:` / `MMGitCommit`）把这件事摆到了桌面上，
而它没有任何一张照片能自己看出来——画面逐像素一样，因为搬的是一个私有辅助函数的位置。
处置是**九张全部重拍**（`p22-v1/` 三张、`p22-disk/` 四张、`p22-disk-skip/` 两张），
不是改日志上的 commit 让它"对上"。留这一条账的理由：**"照片与二进制同源"这件事，
只要还靠人记得"我最后一次构建是什么时候"，它就一定会在某个只需要搬两行的轮次里破掉。**
重拍之后补了一次机械复核（三条 `stat` 现读）：产物可执行文件 mtime **12:37:41**、
最后一次源码改动 **12:34:31**、第一张照片 **12:38:51**——`源 < 产物 < 照片` 这一条排序
是"照片跑的确实是这份产物"目前**唯一能跑的命令**（§8 那一条待办要补的就是把它变成断言）。

**回归那一格**：`p68-disk-capture.sh` 在本轮二进制上重跑成 `docs/verification/p22-disk/`，
四行带数字的回执与 `p21-disk/` **逐字相同**（"已选中 …/Downloads（50.3 MB）"、"确认面板（3 个标记）"……）。
唯一的差别是日志里那行已知的 sandbox 警告中的产物路径（`/tmp/mm-app-p21` → `/tmp/mm-app-v1`），
它本轮已被 §7.3 定性为启动路径带来的、与签名无关。
新夹具 `Scripts/disk-protected-fixture.sh` 把受保护目录放在第 1/2/3 层各一处，
是因为哨兵夹具 `disk-fixture.sh` 在新旧两种口径下报的都是"未纳入 1 个"——**那一族 bug 用它拍不出来**。

**残余三格**（都进了 §8 的账）：① 下钻那一趟不写披露（`skips: nil`），
所以"外部改动之后重新扫描、树上多了新的受保护目录"这一档仍不进 N；
② `protectedNames` 里 `.Trash` / `.Spotlight-V100` / `.fseventsd` / `.TemporaryItems` / `.PKISyncStore`
五条**永远匹配不上**（`readEntries` 更早就把 `.` 开头的名字整条跳过），结果一样但归因是错的；
③ 真机用户目录下这枚徽章的宽度与窄窗溢出仍未测——它是 `fidelity-disk.md` §2 I11 那一格
（面包屑栏会不会挤）在**夹具根之外**的同一问，P6.6 量到的那 34pt 里从没挂过本轮这种长浮层入口。

### 7.14 P23：把"照片与产物同源"从一句自觉变成一条会当场拒拍的断言（2026-10-06）

**病灶是上一轮留下的那一格**（§8 划掉的那条）。P22 的归因头有两行：`# repo:` 是跑脚本的那棵树，
`MMGitCommit` 是被测产物打包时那棵树。本轮量的第一件事实是：**这两行逐字相等也证明不了照片是最终的**。
两个原因，都不是"人不够仔细"：

- 它们是 **commit 标签**。`0e36f97-dirty` 里那个 `-dirty` 只说"工作区有改动"，
  不说改了哪一个文件、改了哪几行。P22 那一次搬家（把 `skippedDisclosure(_:)` 挪到文件末尾）
  改的正是**位置**，而位置不动 commit、不动脏净态、也不动任何一屏的画面——**三条线同时瞎**。
- **事后补不回来**。当时想过一条更便宜的判据：`源 mtime < 产物 mtime < 照片 mtime`。
  它当场就被自己否掉了：`git clone` / `git checkout` 会把照片的 mtime 改成检出时刻，
  这一条排序在别人那棵树上**必然不成立**。也就是说这条门禁**只有"拍之前拒"这一种成立形态**，
  任何"拍完再核"的写法都会在第一次换树之后变成假阳性，然后被人关掉。

**改了什么**（全部在 `Scripts/`，Swift 一行没动）：

| 文件 | 行 | 做的事 |
| --- | --- | --- |
| `Scripts/mm-provenance.sh` | 新，77 行 | 三个函数：`mm_source_digest`（算 92 个编译输入的内容指纹）、`mm_provenance_check`（拿产物 plist 比它）、`mm_provenance_line`（那一行日志的**唯一**排法）。共享成一支文件是因为这个数的正确性**就等于两边算得一模一样**——各抄一遍配方，差一个 `--binary` 或一个路径，结果要么每轮都拒（然后人把它关掉），要么白装 |
| `Scripts/make-app.sh` | +10 | `swift build` **之后**算指纹、写进 `Info.plist` 的 `MMSourceDigest`，最后一行把指纹打给人看。时机在编译之后是刻意的：编译读的就是这一份内容，先算再编译等于允许"编译用的和签进去的不是同一份" |
| `p7-release-check.sh` / `p68-disk-capture.sh` / `p22-disk-skip-capture.sh` / `p17-website-capture.sh` / `p18-hook-typo-proof.sh` | +13/+10/+9/+9/+11，**零删除** | 起跑前先 `mm_provenance_check`，不等就带一句"这一族一张都不出"exit 4；放行时在归因头补一行 `# digest: tree=… app=…`。**拒的时候也要把两个数留在纸上**，不然人只能重跑一遍才知道差在哪 |
| `Scripts/p23-provenance-probe.sh` | 新，147 行 | 五档否证，见 §1 那一行的逐档结论。**只用未跟踪文件做探针**——本轮不再改源码做否证（上一轮有过一次拿 Edit 改壳层源码做探针、把一整个 `return` 插没了的事故，那条教训在 memory 里） |

**指纹的口径**（写在 `Scripts/mm-provenance.sh:22-36` 那四条"已知松处"里，这里只挑要紧的两条）：
覆盖 `Sources`（6）+ 九个包各自的 `Sources`（75）与 `Package.swift`（9）+ 根 `Package.swift`（1）
+ `Resources/AppIcon.icns`（1）= **92**（`git ls-files` 现数，加总可对上）。
**icns 在里面是故意的**：它就是关于页照片上那个图标，换掉它而产物不变，那张 `02-about` 就成了假证。
**测试源码不在里面**：改判据不改产物，为此拒拍等于逼人把门禁关掉——② 档测的就是这一条。
`git diff HEAD` 不带 `--ignore-all-space`，所以搬代码也会变指纹；同一棵树上改两次没重建就拒——
**那不是误伤，那就是本轮要拦的那件事**。

**§10 第 1–3 步第十遍**（2026-10-06）：第 1 步 **622 / 0 / 1**，逐包九格与 P22 归档那一份一格不差（判据 +0，
本轮没有新断言）；第 2 步 `VERSION=1.0.0 BUILD=1` → `/tmp/mm-app-p23/MacMaster.app`，
plist 第一次同时带 `MMGitCommit=df71638-dirty` 与 `MMSourceDigest=df71638+e3b0c442`；
第 3 步三张照片 `docs/verification/p23-v1/`，三份日志的归因头新长这样（`02-about` 逐字）：

```
# repo: df71638-dirty branch=main
# digest: tree=df71638+e3b0c442 app=df71638+e3b0c442
```

`# codesign:` / `# plist:` / `# spctl:` 三行自 P19 起逐字未变，第 4 步仍 ⬜。
**这一遍第一次不需要人记得"我最后一次构建是什么时候"**：P22 那一族的作废重拍，
在这条门禁之后会在**起跑那一秒**变成 exit 4 加两个数，而不是在第 N 张照片拍完之后被看出来。

**磁盘那一族本轮只重拍两档**（`docs/verification/p23-disk-skip/`），理由要说清楚，别让人以为漏了一族：
本轮**没动任何编译输入**，`tree` 与 `app` 两个指纹相等、产物与 P22 收口那一跑逐字节同源，
所以 `p22-disk/` 那四档与 `p22-v1/` 之外没有"重拍才有新证据"的东西。
重拍那两档测的是**新加的那一行日志**，不是新界面：徽章 `未纳入 3 个受保护目录`、
夹具数字 `75.5 MB · 3 个文件`（50.3 / 16.8 / 8.4 MB）与 P22 那两张**逐字相同**，
会动的只有真机那两格——卷可用 45.54 GB → **45.18 GB**、系统清理 1.87 GB → **2.15 GB**。
**门禁本身不改画面，这一族照片的全部新事实都在日志头里**，这是它和以往每一轮最不一样的地方。

**残余五条**（① ② ⑤ 进 §8 的账，③ ④ 是范围决定与代价）：
① 指纹量的是**编译输入**，量不到 `make-app.sh` 的构建参数（`-c debug` / `HARDENED=1` / `VERSION=`）
与签名那一步——那几样仍归 `MMGitCommit`、`# codesign:`、`# plist:` 三行管。
**同一份源码用两种构建参数出来的产物，指纹相同**。要覆盖它得把构建参数也拼进指纹，
那是下一轮的事，本轮先把最容易破的那一类（源码内容）拦下来。
② 27 支出片脚本只接了 5 支。剩下 22 支是 P4/P6.x/P8 那些历史轮次的夹具，
**它们的产物早就没了**：接上门禁之后它们一律拒拍，等于把历史证据变成不可重跑。
接不进、也不该硬接；这条账的形态是"新写的取证脚本必须接"，不是"全部接完"。
③ `p17-website-capture.sh` 与 `p18-hook-typo-proof.sh` 这两支**本轮只验了拒的那一支**
（① 档用 `p7-release-check` 与 `p22-disk-skip-capture` 跑通 exit 4；⑤ 档用 p68-disk 与 disk-skip 跑通放行）。
它们两支的**成功路径**没在归档日志里出现——p17 的照片走的是 `docs/website/assets/`（不是验收证据），
p18 那一档本轮没重跑（52 个钩子名与解析代码一行没动）。
④ 这一条不是缺口而是**代价**：门禁把"改完源码忘了重建"从"可能拍出假照片"变成"当场跑不动"，
换来的是**每一轮改完源码必须重新构建一次才能出片**。本轮①档那两次 exit 4 就是它的样子。
⑤ `# plist:` 那一行**没跟着长**：它仍然只打四键（版本号、构建号、图标键、`MMGitCommit`），
不含 `MMSourceDigest`。**信息不缺**——同一份归因头里的 `# digest: app=…` 那一半就是从 plist 读出来的，
而且它比 plist 那一行更强（两个数并排）。记这一格只是因为下一个读日志的人会发现
"五键里有一键在这行不在那行"，别让他以为产物没带指纹。

## 8. 已知不一致（不阻塞发版，但要有账）


- **磁盘页风险标签与删除闸门之间还剩一类已知的、故意不修的差集**（P21 记）：符号链接行——
  字面路径不在受保护清单里所以界面给按钮，`realpath` 之后落在 `/System` 里所以闸门拒。
  探针表实测本机夹具上是 2 条（`docs/verification/p21-disk-risk/risk-labels.log` 末尾那两行）。
  它不进 §7.12 那句"合同 1 违例 0"，因为那一问说的是字面路径；它被拦在更靠近删除的那一步
  （`DiskRemoval.swift:98` 的 `.guarded` 行）。**要在界面上消掉它，代价是每次布局给每行发一次 `realpath`**——
  这一账不是"没做完"，是"知道差在哪、且知道补它要花什么"。

- **`p16-citation-audit.sh` 的四道硬判据看不见"说法不成立"这一类错**（P21 记，账没还完）：
  本轮重指磁盘页锚点时发现本文 §10 那一格 P12 记的**五处**位置引用**在 HEAD 里就全是错的**——
  五个数一个都没落在它声称的那行上，漂量还整齐（19 行，入口那条 31 行），
  典型的"后来某轮在上方法插了代码、没人回头改文档"。
  **文件存在、行号在范围内、那一行不空白、同后缀不歧义——四条全过，硬失败 0。**
  符号面（死符号 / 位置存疑）能看见这一类，但它**只提示、不进退出码**，所以也不构成门禁。
  本轮只还了自己撞上的这一批（六份文档加 README）；**全仓还有多少这种"行在、话不对"的锚点，
  现在没有任何命令知道**。要真还掉，得给审计加一层"引用附近的文字与那一行的符号名要对得上"的弱判据——
  那是工具改动，不是文档改动，别在核验轮里顺手做。


- **`protectedNames` 里有五条永远匹配不上的名字**（P22 记）：`.Trash` / `.Spotlight-V100` / `.fseventsd` /
  `.TemporaryItems` / `.PKISyncStore` 都以 `.` 开头，而 `readEntries` 在问这份名单**之前**就把 `.` 开头的
  条目整条跳过了（`MMDisk.swift:1914`）。**可观察结果一样**（那些目录都不进统计），所以这不是 bug，
  是**归因错**：注释与徽章浮层说的"这些目录被受保护名单挡掉了"，对那五条不成立——
  是"隐藏文件"那条规则挡的。代价有两头：① 照着名单读代码的人会以为删掉这五条行为会变，
  实际不会；② 真要把 `.` 开头的目录纳入统计（比如哪天想显示 `.Trash` 占了多少），
  改名单那一行会完全没效果，得先动 `readEntries`。**本轮没改**：动它就不是"补可见性"了，
  是改扫描语义，那是另一轮的事（§7.13 残余第 ② 条）。
- **徽章那个 N 的口径是"这一趟扫过的树"，不是"你现在看到的这棵树"**（P22 记）：
  下钻那一趟刻意**不写披露**（`childrenOfDirectory` 传 `skips: nil`），因为全盘扫描已经把每一处记过了，
  下钻再记一遍会把同一处数成两处。留这一格的后果是一条具体的、本轮没修的偏差：
  **外部改动之后点「重新扫描」，如果新的受保护目录只出现在下钻过的那一层**，它不进 N。
  这一条与 §7.13 残余第 ① 条是同一格，写在这里是为了让下一个人知道 N 该在什么时候重算。
- ~~**照片与产物同源这件事目前没有门禁**（P22 记，§7.13）~~ —— **P23 已关（2026-10-06，§7.14）**：
  本轮中途搬动过一个私有辅助函数的位置，搬完之后**先前那一批照片的产物是搬家之前构建的**，
  画面逐像素一样、日志一字不差，只有归因头里的 `MMGitCommit` 与 `# repo:` 对得上才看得见。
  那一轮的处置是全部重拍。当时写下的话是"**这不是本轮的疏忽，是这一族证据的结构性缺口**：
  取证脚本只**记录**跑在哪棵树，不**校验**产物是不是那棵树构建的"，
  并且给了一个当时认为够用的补法（"产物 plist 的 `MMGitCommit` 必须等于当前 `git status --porcelain`
  所暗示的脏/净态"）——**P23 现读把那个补法否掉了**：脏树两边都带 `-dirty`，
  而 P22 那一次改的正是代码**位置**，它不动 commit、不动脏净态、不动画面，**三条线同时瞎**，
  那条判据对它恰好无效。真正的补法是换成**内容**指纹（92 个编译输入的内容哈希进 plist，
  取证脚本起跑前比，不等 exit 4 一张都不出），逐条见 §7.14 与 §1 那两行新表。
  **留这一格是因为它还留下一条没还的账**：指纹量不到构建参数与签名（§7.14 残余 ①），
  而 27 支出片脚本只接了 5 支（残余 ②，接法见 §10 第 3 步那条注释）。
- **构建参数与签名不在同源指纹里**（P23 记，§7.14 残余 ①）：同一份源码，
  `VERSION=1.0.0` 与 `VERSION=1.0.1`、`HARDENED=1` 与不带，出来的 `MMSourceDigest` **相同**。
  所以"照片与产物同源"这句话目前的准确范围是**编译进 bundle 的那一份输入同源**。
  构建参数那一侧仍由 `# plist:`（含 `CFBundleShortVersionString` / `CFBundleVersion` / `MMGitCommit`）
  与 `# codesign:` 两行管——它们不是断言，是记录。要变成断言得把参数拼进指纹，本轮没做。
- **门禁只接了 5 支出片脚本，另外 22 支没接**（P23 记，§7.14 残余 ②）：
  `grep -rl screencapture Scripts/*.sh` 现数 27 支，接了检查的是
  `p7-release-check`、`p68-disk-capture`、`p22-disk-skip-capture`、`p17-website-capture`、`p18-hook-typo-proof`。
  那 22 支是 P4 / P6.x / P8 那些历史轮次的夹具，**它们当年的产物早就不在了**，
  接上门禁只会让它们一律拒拍、把"可重跑的历史脚本"变成"不可重跑"。
  这一条的规矩因此写成**将来新写的取证脚本必须接**（§10 第 3 步注释里那句"脚本头 source 一支、起跑处 check 一次"），
  而不是"全部接完"。**这不是遗漏，是选了"能重跑"而不是"计数好看"**。
- **上一轮自报的那"23 份两侧都有的归因行"是错的，现读 13**（P23 记）：
  P23a 那一轮在对话里报过"247 份日志 / 34 份带 `# repo:` / 23 份两侧都有"，**没落盘就没人能对账**。
  本轮现读：**253 / 40 / 13**（写回之后又读了一遍，是 **255 / 42 / 13**——多的两份是 `p23-citations/` 的
  `audit.log` 与测试结论行，两份都只带作者树那一侧；前两个数在同一轮里动了两次，
  **动的理由是本轮自己多产了日志，不是量法变了**，对账用的还是下面这条加法）。
  前两个数**能对上**——差的 6 份正是本轮新写的日志
  （`p23-v1/` 三份、`p23-disk-skip/` 两份、`p23-provenance/probe.log` 一份，六份都带 `# repo:`），
  说明那一跑的这两个数是真的。第三个数**对不上**：现读带 `app-repo` 的只有 13 份，
  而本轮一份日志都没删过（`git status` 只有新增），所以那个 23 **要么当时量的不是"份"、要么当时就数错了**，
  两种都查不回来了——**这一格只认现读数**。留它的理由是把 memory 里那条"上轮自报的数也要现读复核"
  落成一个有具体数字的例子：**能对账的数才有资格进文档，对不上账的数要当成错数重写**。
  **本轮又添了一个同族例子，而且这次是自己的**：README 那句"产物版本号逐字相同"上一版配的是"30 份归因日志现读"，
  这一轮按写在同一句里的那条 `grep` 现读是 **33**，**30 是用哪条命令数出来的已经复现不出来了**——
  这一次不追究"当时数错了"，追究的是**当时没把命令一起写下来**。
  所以 §1 那一格与 README 现在都把判据和数并排写：判据在，下一轮就能对账；判据不在，那个数只是一句口气。



- ~~**概览页的"可清理"不看清理页那四个开关**~~ —— **P8 已修（2026-10-05），走"按 scope 扫"这一支**：
  拼法收敛到 `CacheScanScope.selected(systemCache:appCache:logs:temp:)`（`CacheScanner.swift`），
  清理页 `MMCleaner.swift` 的 `scope(from:)` 与概览 `DashboardModel.measureReclaimable()` 共用它，
  排除清单也按清理页口径合并（设置页永久排除 + 清理页逐条排除）。
  四个全关时不再显示"未扫描"，而是新增一档 `ReclaimMeasureState.noCategorySelected`
  →「未勾选类别」+ 一句"勾上任一个再点「重新测量」"（等下去也不会有数，这不是失败也不是没扫）。
  取证：`docs/verification/p8-dashboard-scope/` 三档（只勾日志 **41.8 MB**，且它正好等于卡里
  两个可删类之和 34.3 + 7.5，只读的「系统日志 101.7 MB」不计入 / 全关「未勾选类别」/ 还原全开 **5.38 GB**）。
  **仍然成立的边界**：概览那张按钮只做跳转（`MainWindow.swift:644`），不在概览页删任何东西。
- **"检查更新"不是死开关，但它不联网**：`SettingsView.swift` 的 `checkForUpdates()`（P12 现读 `:319-323`；
  本文此前写 `:304-310`，那是 P7 时的行号，已经漂了）只读本机 Info.plist，
  并在弹窗文案里明说"当前构建未配置更新服务器"。发版说明别写"自动更新"。
- **"反馈问题"按钮是 disabled**：`SettingsView.swift` 那一段（P12 现读 `:293-301`，此前写的 `:280-288` 同样漂了），
  旁边一句"未找到官方反馈渠道地址，不做虚构链接"。有了仓库地址再放开。
- **5 处空骨架**（P12 现读复核，五处都还在）：`MacMaster/`、`MacMasterHelper/Sources/MacMasterHelper/`、
  `MacMasterWidgets/Sources/MacMasterWidgets/`、`docs/verification/mmguardian/`、`docs/verification/shell/`。
  说它们"空"是指**零个文件**——`find MacMaster -type f` 返回 0，而 `MacMaster/` 这个目录本身不是空的，
  里面套着 `MacMaster/Sources/MacMaster` 这一层空路径（git 不跟踪空目录，所以 `git status` 里看不见）。
  前两处像是没落地的 helper/widget 骨架。要么补内容要么删掉，别让下一个人以为有个 helper 靶子。
  **P20 现读：五处都还在，但"五处"这个数只在作者树里成立**——空目录 git 不跟踪，
  所以那五处在一次干净克隆里**一个都不存在**（P20 撞到的正是这一点：`docs/verification/` 的目录数
  在作者树 52、在克隆 50，差的就是其中那两处空壳；§11 的判据因此换成了只数入库文件的那条命令）。
  也就是说这一条待办**没法用命令在别人机器上复现**，只能靠作者树里这几个壳还留着——
  删掉它们等于把这条账抹了，留着它们又污染计数，**所以判据要数文件而不是数目录**。
- ~~**`.gitignore` 把参考仓库排除了**（`docs/github-references/`、`docs/Mole/`、`docs/lemon-cleaner/`），
  而多份分析文档正文按那些路径引了源码位置——**别人 clone 之后那些引用是断链**~~
  —— **P16 已把这句话变成数并收口（2026-10-06）**：`./Scripts/p16-citation-audit.sh` 把每一处引用
  逐条落盘验过（总数与分档只记 §1 那一格与 `docs/verification/p16-citations/audit.log`，这里不重抄）：
  命参考仓库 **57** / 命苹果 SDK 头文件 **1** / **两头都不到 0**。
  两条决定：① 断链按代价分档，不混成一个数——引**本仓库**的漂了就是错（改文档，本轮改了 12 处）；
  引**参考仓库**的 clone 后一律不到，但**可补**（URL + 钉住的 commit 进 `docs/analysis/reference-repos.md`，
  读的人一条命令把那 57 条变成可打开的）。② 不为了"引用都指入库文件"而把参考仓库纳入版本——
  它们是 GPL / Apache-2.0+Commons Clause 的第三方仓库，只读不转发，纳入版本就把许可问题变成真问题。
  SDK 那一类单列一档（1 条 `AVCaptureDevice.h:323`）：本机可验，别人 clone 一样打不开，
  报告里自报 SDK 版本 27.0，换 Xcode 要重跑。README 那一行指针也补了（§10 第 3e 步）。
  **P20 把"读的人一条命令"这一句从愿望变成事实**：那条命令此前**不存在**（文档 §2 给的是一段要人手工
  换七次 URL 与 commit 的样板），而且更糟——引用门禁本身在干净克隆里跑不起来（参考仓库那个 glob 抽不到东西
  就让 zsh 直接打死脚本）。现在有了 `./Scripts/clone-references.sh`（现读那张表、默认只查不下载），
  门禁也实测过"缺参考仓库 → exit 1 且报告里明写是没取到"与"取齐 → 六个数与作者树逐位相同、exit 0"两档。
  逐条见 §7.11。

## 9. 建议的 v1.0 范围与版本号

**发**：§6 表中所有"可发布"档，即九屏全部功能；`LSMinimumSystemVersion 14.0`
（P12 现读：`Scripts/make-app.sh` 写 plist 的那一段，`<key>LSMinimumSystemVersion</key>` + `<string>14.0</string>`）。
**在发版说明里明确标注**：§6 表里那四条"可发布·需标注"（判定列逐行数，别拿 `grep -c 需标注` 当计数——
本文自己这段话里就含一次"需标注"）、§4 的写盘三项。（§8 那条"概览口径"已于 P8 收口，
不再需要标注——现在概览与清理页是同一个数。）
**不发**：Mac App Store（§3 那张表里**已测的七行全部会被沙盒砍掉**，§3 结论 2）；
多语言（语言开关本轮已禁用，没有 UI 消费点）；
自动更新（没有更新服务器）；helper/widget 两个空壳（§8）。

**版本号建议**：`CFBundleShortVersionString=1.0.0`、`CFBundleVersion=1`。
版本号只有一个来源——`Scripts/make-app.sh` 里 `VERSION=${VERSION:-1.0.0}` 与 `BUILD=${BUILD:-1}`
那两行（P12 现读 `:39-40`；此前写 `:38-39`，P10 加图标注释时往下漂了一行），所以**发版命令就是**：

```
VERSION=1.0.0 BUILD=1 ./Scripts/make-app.sh
```

P7 那轮的 `1.0.0-rc1 (1)` 是**取证用的构建**，界面显示的字符串与 plist 一致；
P8 之后按 §10 出的 **v1.0.0 候选产物**也已闭合同一条链（§7.2 第一行：plist `1.0.0`/`1` ↔ 关于页
「版本 1.0.0 (1)」，同一张照片里）。不要 `rc` 进正式版：`make-app.sh` 不解析版本号，
`rc` 会原样进 plist，`about` 页会跟着显示。

## 10. 发版前 checklist（可直接执行）

```
# 0.（P20 起，发版那一遍要求从这棵树上跑）干净克隆，别借作者工作树里任何一样没入库的东西
git clone --no-local <本仓库> /tmp/mm-clone && cd /tmp/mm-clone
./Scripts/clone-references.sh --check   # 只读；报"缺 7 项"是**正常的**——参考仓库本来不入库
#     为什么要有第 0 步：前六遍核验全跑在作者自己的工作树上，那棵树里有 .gitignore 排掉的参考仓库、
#     有空目录、有上一轮的夹具。P20 正是从一棵干净树上跑才撞出"引用门禁在别人的机器上跑不动"（§7.11）。

# 1. 全量测试（期望 622/0/1、MMGuardian 96、MMCore 73、MMDisk 73；数字变了要回写本文 §1）
#     P22 起把**结论行**归档一份进本轮的证据目录（`> docs/verification/pNN-citations/run-all-tests.log`），
#     前八遍只留在 /tmp——那一格引用的是一个别人 clone 之后不存在的路径（§7.13）。
./Scripts/run-all-tests.sh

# 2. 构建候选产物（版本单一来源；图标随仓库带着，构建前先自证一次）
./Scripts/make-icon.sh --check          # 反向解一次 icns，核十档齐全
VERSION=1.0.0 BUILD=1 ./Scripts/make-app.sh -o /tmp/mm-app-v1 -s /tmp/mm-scratch-v1
#     产物从此自带出处：plist 里多一个 MMGitCommit（P19 起），跑第 3 步时它会被读回归因头。
#     P23 起还多一个 **MMSourceDigest**（92 个编译输入的内容指纹，`Scripts/mm-provenance.sh`）——
#     这一键不是给人看的，是给第 3 步比对用的；`make-app.sh` 最后一行会把它打出来。
#     发版判定要看的就是这一行——十遍核验的产物版本号逐字相同（都是 1.0.0(1)，
#     `grep -h "^# plist:" docs/verification/{v1.0.0,p12-v1,p13-v1,p14-v1,p15-v1,p19-v1,p20-clone,p21-v1,p22-v1,p23-v1}/*.log`
#     现读一遍即可；唯一不是它的是 `p7-release-build/`，那一份是 P7b 的 `1.0.0-rc1`，不在这十遍里），
#     没这一键就分不出哪一份是哪一轮。

# 3. 三张基础照片 + 把签名/plist（含 CFBundleIconFile）/gatekeeper 结论写进日志归因头
#    重跑要换输出目录：这一条写进 /tmp 的那份日志归因头会**盖掉上一轮的证据**。
#    P9 第一遍写的是 docs/verification/v1.0.0/，P12 第二遍写 docs/verification/p12-v1/，
#    P13 第三遍写 docs/verification/p13-v1/，P14 第四遍写 docs/verification/p14-v1/，
#    P15 第五遍写 docs/verification/p15-v1/，P19 第六遍写 docs/verification/p19-v1/，
#    P20 第七遍写 docs/verification/p20-clone/（那一遍整棵树是 git clone 出来的，见 §7.11），
#    P21 第八遍写 docs/verification/p21-v1/，P22 第九遍写 docs/verification/p22-v1/，
#    P23 第十遍写 docs/verification/p23-v1/。
#    **产物与当前源码不同源时这一条会 exit 4、一张都不出**（P23 起）：它起跑前先拿
#    `Scripts/mm-provenance.sh` 比一遍"当前树那 92 个编译输入的内容指纹"和产物 plist 里的
#    `MMSourceDigest`，不等就拒。这一条替代了 P22 那句"跑之前先确认产物是最新那棵树构建的"——
#    那句话依赖人记得，而 P22 撞的那一次（中途搬动一个私有辅助函数的位置，画面逐像素一样）
#    恰好是 commit 标签与脏净态**都看不见**的一种改动，靠人记得记不住（§7.13、§7.14）。
#    放行时归因头会多一行 `# digest: tree=… app=…`；**拒时它也会把两个数写进日志**，
#    不然只能重跑一遍才知道差在哪。新写一支出片脚本的规矩：头上一行 `source`、
#    参数解析之后起跑之前一次 `mm_provenance_check`，别只 `# repo:` 记录（§8 那格记了现有覆盖面）。
./Scripts/p7-release-check.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p19-v1

# 3b.（可选，一次性的归因探针）那行 sandbox_extension 警告是路径带来的还是签名带来的（§7.3）
./Scripts/p12-sandbox-warning-probe.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p12-v1

# 3c.（可选，只在动过任何一处 MMPageHeader 副标题时跑）页头副标题三档宽度不出现省略号（§7.5）
#     副标题是 .lineLimit(1) + 中间截断：加长它不会报错、不会换行，只会静默切掉句子中段。
./Scripts/p14-header-capture.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p14-header

# 3d.（可选，只在动过任何一处子进程调用时跑）launchctl / tmutil 两屏的真读数与照片逐字对得上（§7.6）
#     零夹具、零合成点击；expect 行是另一条独立读法（plutil + launchctl），不与被测代码共用解析。
./Scripts/p15-pipe-capture.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p15-pipe

# 3e.（每轮都跑，改过任何一份 docs/ 里的 .md 之后必跑）入库文档的位置引用逐条落盘验一遍（§7.7）
#     四道硬判据（命中面/唯一面/行号面/空白面）不过就 exit 1；第五道符号面只提示、不进退出码。
#     报告里的三个自报数不等就是判据没跑全：docs scanned 两个数、行号判据实跑条数、vocab 条数。
#     输出目录**一轮一份**（P16 写 p16-citations、P17 写 p17-citations、P19 写 p19-v1）：这一条会盖掉同名 audit.log，
#     而 §1 那一格引用的就是最新一份，旧轮次的日志要留着才能对上前文写的数。
#     脚本自己写的文件名固定是 audit.log；P18 那一份是手工拷进 p18-hooks/citation-audit.log 的（跟着那一族照片走，
#     没另开目录），所以那一轮的日志名与别处不同——找的时候两个名字都要想到。
#     **还有一条 P18 踩过的**：这一道门只扫 `git ls-files`，新写的 .md 没 `git add` 就等于不存在，
#     而报告里的两个 docs scanned 数会一起变小、不会警告。先 add 再跑。
#     **P20 又添一条，而且这一条是"在别人机器上"的**：那 57 条指向参考仓库的引用在 .gitignore 排掉的目录里，
#     干净克隆里跑这道门会 exit 1（57 条落进"两头都不到"）。这是**对的**——取不到参考仓库时不该签字说文档没问题，
#     但要先 `./Scripts/clone-references.sh --fetch` 再跑，才会得到 §1 那一格的 675/580/522/57/1。
#     P20 之前的行为更糟：连报告都没有，脚本在参考仓库那个 glob 上撞死（zsh NOMATCH + set -e），
#     而它自己写的"参考仓库没克隆时走这一支"降级逻辑从没被跑到过（§7.11）。
./Scripts/p16-citation-audit.sh docs/verification/p19-v1   # 期望：硬失败 0、退出码 0

# 3g.（可选，只在动过任何一处 MM_* 钩子的解析/回落时跑）写错值必须留一行 stderr，23 档（§7.9）
#     这一族是全仓唯一**判据在日志里而不在画面里**的门禁：照片对"钩子写错"毫无反应，
#     所以它测的不是界面，是"下一轮那批照片能不能各自回到自己的档"。
#     需要带窗口的实机进程：先跑第 2 步产出 /tmp/mm-app-v1/MacMaster.app，再：
./Scripts/p18-hook-typo-proof.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p19-hooks   # 期望：核对 23 档，失败 0 档
#     第二个参数是证据目录（默认 docs/verification/p18-hooks）——**重跑一定要指到别处**，
#     否则会盖掉上一轮那 18 张照片与 23 份原始 stderr。P19 起归因头有两行出处：
#     `# repo:` 是跑这条脚本的那棵树，`# app-repo:` 是被测那份二进制打包时的那棵树（读 plist 的 MMGitCommit）。
#     改某一档重拍用 ONLY=08（逗号前缀列表，**不要用字符类**：`ONLY='1[348]'` 在 zsh 里匹配不到任何档，
#     旧版本因此打印过"全部 0 档符合预期"并 exit 0 —— 现在 checked==0 会直接 exit 2）。

# 3h.（可选，只在动过 make-app.sh、mm-provenance.sh 或任何一支接了门禁的取证脚本时跑）
#     同源门禁本身的五档否证：① 多一个未跟踪源文件必须拒、② 多一个未跟踪测试文件不许拒、
#     ③ 无 MMSourceDigest 键的旧产物必须当不同源、④ 当前树+当前产物必须放行、
#     ⑤ 同源产物上一档都不拍也要正常 exit 0（这一档防的是"永远失败的门禁"——那种门禁只会被关掉）。
#     它只造**未跟踪文件**做探针（`Sources/MacMaster/P23Probe.swift` 与一份测试文件），
#     跑完 trap 清掉，一动不动已提交的源码（§7.14）。第二个参数是"无指纹键的那一份旧产物"，
#     不给就跳过 ③ 档；临时输出在 /tmp/mm-p23-probe-out，不用归档（归档的是重定向出来的结论行）。
./Scripts/p23-provenance-probe.sh /tmp/mm-app-v1/MacMaster.app \
    > docs/verification/p23-provenance/probe.log   # 期望：末行"五档全部符合预期（✗ 计数 0）"、exit 0

# 3f.（可选，只在动过 docs/website/index.html 或任何一屏的夹具钩子时跑）落地页那四张图重拍（§7.8）
#     四档全走夹具钩子、零合成点击。**两条必看的后果**：
#     ① 照片直接写 docs/website/assets/（覆盖宣传图本身），归因日志默认覆盖 p17-website/capture.log——
#        想留旧的那份就先 `EVIDENCE=docs/verification/p17-website-2` 指到别处；
#     ② 画面上侧栏的卷名与占用百分比、磁盘页的「卷可用」**没有钩子能顶替**，是这台机器的真实状态，
#        所以重拍之后要核对页面上那句披露还不成不成立（换机器拍，那句话就可能反过来变成假话）。
./Scripts/p17-website-capture.sh /tmp/mm-app-v1/MacMaster.app docs/website/assets dark 1280x800

# 4. 人工确认：许可已定（补 LICENSE 文件 + 改回两处那一格）/
#    NSHumanReadableCopyright 有年份和权利人 / 签名方式选定（§2.1 三选一）

# 5. 只有选了 §2.1 第 2 条（Developer ID + 公证）才要跑：同一份二进制打两种签名，
#    逐能力拍对照照片，看 `--options runtime` 那一位标志有没有打断什么（§3 已跑过一轮）。
#    换证书之后要重跑一次——那一轮证的是 ad-hoc+runtime，不是 Developer ID+runtime。
./Scripts/make-app.sh            -o /tmp/mm-app-p11-base -s /tmp/mm-scratch-p11
HARDENED=1 ./Scripts/make-app.sh -o /tmp/mm-app-p11-hr   -s /tmp/mm-scratch-p11
./Scripts/p11-hardened-check.sh /tmp/mm-app-p11-base/MacMaster.app docs/verification/p11-hardened base
./Scripts/p11-hardened-check.sh /tmp/mm-app-p11-hr/MacMaster.app   docs/verification/p11-hardened hr
```

第 4 步全过之前，本文的判定停留在"功能就绪、分发未就绪"。

**2026-10-05 实跑状态**：第 1 步 571/0/1 ✅；第 2 步产物 `/tmp/mm-app-v1/MacMaster.app`（release 配置，
`VERSION=1.0.0 BUILD=1`，隔离 scratch `/tmp/mm-scratch-v1`）✅；第 3 步
`docs/verification/v1.0.0/`（三张照片 + 三份日志，判据逐条见 §7.2）✅；第 4 步 ⬜ 待人拍板。
第 2、3 步的产物与临时目录是**一次性的**，跑完已清掉，只有 `docs/verification/v1.0.0/` 入库。

**P11 之后（2026-10-05）第 1 步重跑 581/0/1** ✅；**第 5 步也真跑了一遍**（在选定签名方式之前先把它量清）：
`docs/verification/p11-hardened/` 两档各 5 张照片 + 2 组监听取证，判据与三条限定都在 §3。

**P13（2026-10-05，P11c 之后）第 1–3 步第三遍重跑 579/0/1** ✅：产物 `/tmp/mm-app-p13`，
证据 `docs/verification/p13-v1/`（四张照片 + 四份日志），逐判据见 §7.4。第 4 步仍 ⬜。

**P14（2026-10-05，页头合同之后）第 1–3 步第四遍重跑 583/0/1** ✅：`make-icon.sh --check` 仍是
`✓ 反向解出 10 档；1024 档 270169 字节`（与 P13 同一个数，图标这一轮没动）→ 产物 `/tmp/mm-app-p14` →
证据 `docs/verification/p14-v1/`（三张照片 + 三份归因日志）；**另加 3c 那一档**：
`docs/verification/p14-header/`（三档窗口宽度 × 三张照片 + 三份日志，判据"副标题那一行不许出现 `…`"）。
逐判据与否证实验见 §7.5。第 4 步仍 ⬜，第 5 步不需要重跑（P14 没动签名相关的任何东西）。

**P15（2026-10-05，子进程调用并口之后）第 1–3 步第五遍重跑 590/0/1** ✅：`make-icon.sh --check` 仍是
`✓ 反向解出 10 档；1024 档 270169 字节`（与 P13/P14 同一个数，图标这一轮没动）→ 产物 `/tmp/mm-app-p15` →
证据 `docs/verification/p15-v1/`（三张照片 + 三份归因日志，`# plist:` / `# codesign:` / `# spctl:` 三行与 P14 逐字相同）；
**另加 3d 那一档**：`docs/verification/p15-pipe/`（两档零夹具照片 + 两份 expect 日志 + 一份否证日志）。
第 4 步仍 ⬜，第 5 步不需要重跑（P15 没动签名，`launchctl`/`tmutil` 两行是**只读**路径，
写侧照旧不在测试里真动 launchd）。第 2、3、3d 步的产物与临时目录是一次性的，跑完已清掉。

**P12（2026-10-05，同一天的第二遍）第 1–3 步在带 P11 改动的二进制上重跑** ✅✅✅：
581/0/1 → `make-icon.sh --check` 过 → `/tmp/mm-app-v1`（`VERSION=1.0.0 BUILD=1`）→
`docs/verification/p12-v1/`（三张照片 + 三份归因日志 + 两份探针日志 + 一张用户目录窗口照片），
逐条判据见 §7.3；第 4 步 ⬜ 仍待人拍板；第 5 步不需要重跑（P11 那一份代码没再动过签名相关的东西，
而 §3 的三条限定仍然成立）。第 2、3 与 3b 步的产物与探针目录都是**一次性的**，跑完已清掉。

**P19（2026-10-06，P18 之后）第 1–3 步第六遍重跑 612/0/1** ✅：`make-icon.sh --check` 仍是
`✓ 反向解出 10 档；1024 档 270169 字节`（与 P13/P14/P15 同一个数）→ 产物 `/tmp/mm-app-v1`
（`VERSION=1.0.0 BUILD=1`，plist 第一次带 `MMGitCommit`）→ 证据 `docs/verification/p19-v1/`
（三张照片 + 三份归因日志，`# codesign:` / `# spctl:` 两行与 P15 逐字相同）；
**另加 3g 那一档跑在发版候选产物上**：`docs/verification/p19-hooks/`（23 档 / 18 张照片 / 23 份原始 stderr）。
本轮的增量不在"又绿一遍"，在**取证工具链从此能说出自己的出处**（`MMGitCommit` + `# repo:` + `# app-repo:`），
判据、覆盖旧证据的理由与那把 md5 哨兵的适用边界都在 §7.10。第 4 步仍 ⬜，第 5 步不需要重跑（P19 没动签名）。

**P20（2026-10-06，P19 之后）第 1–3 步第七遍重跑，跑在一棵 `git clone` 出来的树上** ✅：
`make-app.sh` 22.48s（零远程依赖，图标在，plist 里 `MMGitCommit=b2b3718` **不带 `-dirty`**——克隆树里没有
未提交的跟踪改动）→ `run-all-tests.sh` **612/0/1**，逐包 70 / 17 / 117 / 18 / 121 / 66 / 53 / 96 / 54
与作者树**一个不差** → `p7-release-check.sh` → 证据 `docs/verification/p20-clone/`
（三张照片，`# repo: b2b3718 branch=main`，签名/plist/Gatekeeper 三行与 P19 逐字相同）。
**引用门禁这一遍撞了三次**：第一次在克隆里**一行报告都没出**，报的是 `no matches found: docs/github-references/*`
（zsh NOMATCH 在 `set -e` 下是致命错，脚本走不到它自己写好的降级分支）；修成 `(N)` 之后走降级分支——
exit 1、硬失败 57、`# ref:` 三行把"为什么这 57 条不是断链"说清楚；再 `./Scripts/clone-references.sh --fetch`
把 5471 个参考文件取下来，那一跑才是 675 / 580 / 522 / 57 / 1、位置存疑 99、**硬失败 0、exit 0**，
与作者树逐位相同。**这一跑的 `# repo:` 带 `-dirty`，dirty 来自正在被修的那两个脚本本身**，
不是 borrowed 的未跟踪文件——`-uno` 就是为了把后者排除掉才加的。
本轮的增量不在"又绿一遍"，在**这套门禁第一次不是只在作者这一棵树上成立**；
判据、四条命令与那五处文档矛盾都在 §7.11。第 3g 步（钩子门禁）**本轮没重跑**，第 4 步仍 ⬜，
第 5 步不需要重跑（P20 没动签名）。

**P21（2026-10-06，P20 之后）第 1–3 步第八遍重跑 621/0/1，跑在带删除闸门改动的二进制上** ✅：
`run-all-tests.sh` **621/0/1**，逐包 73 / 17 / 117 / 18 / 121 / 72 / 53 / 96 / 54 →
产物 `/tmp/mm-app-p21/MacMaster.app`（`VERSION=1.0.0 BUILD=1`，plist `MMGitCommit=95866d9-dirty`
——**这一轮的 `-dirty` 是真的**：被测的正是那四个未提交的源文件，发版那一遍必须是干净的树）→
`p7-release-check.sh` → 证据 `docs/verification/p21-v1/`（三张照片，签名/plist/Gatekeeper 三行与 P19/P20 逐字相同）。
**这一遍和第 1 步之间还夹了一次回归**：`docs/verification/p21-disk/` 那四档重拍的回执与 `p68-disk/` 逐字相同，
它才是"改了删除口径没改坏删除路径"的证据；`docs/verification/p21-disk-risk/risk-labels.log` 顶掉了那一格拍不了的照片。
第 3g 步（钩子门禁）**本轮没重跑**（P21 一个钩子都没加也没改行为，52 个名字现读未变），
第 4 步仍 ⬜，第 5 步不需要重跑（P21 没动签名）。判据、那 2 条残余差集与锚点重指账都在 §7.12。

**P22（2026-10-06，P21 之后）第 1–3 步第九遍重跑 622/0/1，跑在带跳过披露改动的二进制上** ✅：
`run-all-tests.sh` **622/0/1**，逐包 73 / 17 / 117 / 18 / 121 / **73** / 53 / 96 / 54 →
产物 `/tmp/mm-app-v1/MacMaster.app`（`VERSION=1.0.0 BUILD=1`，plist `MMGitCommit=0e36f97-dirty`，
`-dirty` 同样是真的：被测的是那两个未提交的源文件）→
`p7-release-check.sh` → 证据 `docs/verification/p22-v1/`（三张照片，签名/plist/Gatekeeper 三行与 P19/P20/P21 逐字相同）。
**这一遍的第 1 步跑在最后一次源码改动之后**（结论行完成 12:40:11 > 源码 12:34:31），
第 3 步的产物 mtime 12:37:41 夹在两者之间——**这一遍的顺序是本轮唯一一次被当成判据写下来的**，
理由见 §7.13 那格"照片与产物同源没有门禁"。
第 3e 步（引用门禁）跑了，`docs/verification/p22-citations/audit.log`，**硬失败 0、exit 0**（§1 那一格）；
第 3g 步（钩子门禁）**本轮没重跑**（52 个名字现读未变，钩子解析与回落一行代码都没动，P19 那 23 档结论仍成立）；
第 4 步仍 ⬜，第 5 步不需要重跑（P22 没动签名）。

**P23（2026-10-06，P22 之后）第 1–3 步第十遍重跑 622/0/1，跑在带取证工具链改动的二进制上** ✅：
`run-all-tests.sh` **622 / 0 / 1**，逐包 73 / 17 / 117 / 18 / 121 / 73 / 53 / 96 / 54（与 P22 归档那一份
**一格不差**，本轮判据 +0）→ 产物 `/tmp/mm-app-p23/MacMaster.app`（`VERSION=1.0.0 BUILD=1`，
plist `MMGitCommit=df71638-dirty` **+ 第一次带 `MMSourceDigest=df71638+e3b0c442`**；
`-dirty` 仍是真的，脏的是本轮那六支脚本与两份新脚本）→ `p7-release-check.sh` →
证据 `docs/verification/p23-v1/`（三张照片，签名/plist/Gatekeeper 三行与 P19–P22 逐字相同，
归因头**多一行 `# digest:`**）。**这一遍是十遍里第一次"顺序由门禁保证"的一遍**：
第 3 步起跑就比过一次指纹，不同源到不了照片那一步。
**另加 3h 那一档**：`docs/verification/p23-provenance/probe.log`（五档否证全绿、✗ 计数 0，
16:25 那一跑带旧产物路径名）。磁盘那一族只重拍了 `docs/verification/p23-disk-skip/` 两档，
理由写在 §7.14 那一节末尾（**没动编译输入，`p22-disk/` 那四档没有"重拍才有新证据"的东西**）。
第 3e 步（引用门禁）跑了，`docs/verification/p23-citations/audit.log`，**700 / 597 / 539，硬失败 0、exit 0**（§1 那一格）；
第 3g 步（钩子门禁）**本轮没重跑**——52 个钩子名现读未变、钩子解析与回落一行 Swift 都没动，
P19 那 23 档结论仍成立；第 4 步仍 ⬜，第 5 步不需要重跑（P23 没动签名，
且**构建参数与签名恰好是指纹量不到的那两样**，见 §8）。
**但这两份日志的日期头是 2026-10-07，不是上面那一行的 2026-10-06**：3e 与第 1 步的结论行入库都发生在
文档回写全部落定之后（结论行完成时刻 19:43；引用门禁当天读了三遍，19:41 是文档初稿、
第二读报 701 / 598 / 540（就是 §1 那一格记的那次"叙述被抽取器当成引用"）、第三读是改回来之后**入库的那一份**——
它自己的 `# date:` 就是那一跑的时刻，本文不跟着抄一遍分钟），本轮跨了一天。
**这一天不改变这两份证据归谁**：`mm_source_digest` 现读仍是 `df71638+e3b0c442`，与 16:25 那个产物、
与 `p23-v1/` 那三张照片的 `# digest:` 是同一个值——中间落的只有文档。
**这正是 P23 之后归因和以前不一样的地方**：换在 P22 之前，读者只能靠"日期挨得近"来相信 19:41 那份审计报告
量的还是这一轮；现在他可以现读一个指纹，而这个指纹不依赖任何人的记性或时间戳。

## 11. 「能不能发第一个稳定版本」——P15 的正面回答（P12 起笔，P13/P14/P15 各补一遍核验）

问的不是"还有什么没做"，而是**今天把这份代码发出去，会不会说到做不到**。分三层答：

1. **作为"自己编译自己用 / 带源码的私有分发"：能发，今天就能。** §10 第 1–3 步跑过**十遍**（P23 是最新一遍，
   在带取证工具链改动的二进制上；P15/P19/P20 各补过一遍时这一格也跟着改过口），
   §6 那十行判定（不含 P14 新加的对外文案那一格）全落在"可发布"或"可发布·需标注"两档
   （**没有一行是"不发这一屏"**）、
   §5 那道闸门两个删除出口都过、§4 零网络代码。
   需要写的只有 §9 那四条标注 + §4 的写盘三项（其中 `trash-history.json` 会记用户文件路径，必须写）。
   （§6 最后一行是 P14 新加的**对外文案**那一格，它不在产物里，判档是"本轮起才进表"——
   它不影响这一条判定，但影响下面第 3 条那句"能测的都测了"。）
2. **作为"给陌生人的 dmg"：还差三项，且三项都不是代码。** §2.1 的签名与公证（要账号）、
   §2.3 的许可（要拍板）、`NSHumanReadableCopyright` 的年份与权利人（要填名字）。
   **代价面 P11 已经量过**：走 Developer ID + 公证**不需要砍任何功能**（§3 结论 1，七行零打断）。
   所以这三项是**决定**，不是工作量。
3. **发之前不必再补的技术项**：本轮把 §3 的空白（`launchctl` 写侧）之外能测的都测了；
   §8 那**十三条**是账、不是门（**P23 现读复核**：顶层十三条，其中三条已划掉收口——概览 scope 由 P8 修、
   参考仓库断链由 P16/P20 变成数、**"照片与产物同源没有门禁"由 P23 变成一条会 exit 4 的断言**；
   这一格从前写"那五条"、又写"九条"，都是当时数错了：**P22 那一版的 Edit 吃掉了"概览 scope"那条的表头行**，
   所以它数出来的顶层条数少一条，本轮 `awk` 现读才发现（同一轮还顺手发现 §1 那格 P23a 自报的 23 对不上账）。
   **教训与 §7.12 那条是同一族：计数必须当轮现跑，抄上一格连抄带错**）。
   （两处行号漂移本轮已改，两处死开关已明说，五处空骨架待人工决定，
   `.gitignore` 那条断链 **P16 已变成数并收口**——每一处引用都逐条落盘验过（总数只记在 §1 那一格，
   不在这里重抄第二遍），两头都不到 0，
   参考仓库那 57 条的取法写进了 `docs/analysis/reference-repos.md`）。
   **P14 起这一条要加一句限定**：`docs/website/index.html` 那一页**不在"能测的都测了"里**——
   它从来没有跟实现对照过（§6 那一格），只是它不进产物，所以不改变"能不能发"的判定。
   **P17 这句限定已经过期**：那一页逐句过了审计并换成夹具实拍（§7.8），但它**仍然不进产物**，
   所以对"能不能发"的判定仍旧没有影响——影响的是"发的时候挂出去的那段话是不是真话"。

**唯一一处"能力靠肉眼而不是靠测试"**：壳层零测试目标（§6「壳层 `Sources/MacMaster`」那一格）。这一条**不阻塞发版**，
但发版说明里不该假装九屏都有回归保护——九屏的壳层部分是 622 条测试**没覆盖**的那一层
（**P18 现读更正**：这一格从前写"590 条测试没覆盖的那一层"，而 P18 之后 MMCore 从 48 涨到 70，
涨的正是钩子判定那一段——所以准确说法是"**剩下的** 612 条仍然一条都不落在壳层里"，
判定层下沉了、`Sources/MacMaster` 本身依然没有测试目标。**P21 只是把总数从 612 抬到 621、
P22 抬到 622**，新增的判据一条在磁盘页的跳过披露、九条在删除闸门与磁盘页标签，
壳层这一格该说的话一个字没变），
它靠的是 `docs/verification/` 下那 **62 个入库取证目录**（**P20 把这一格的判据换掉了**：从前写
`ls -d docs/verification/*/ | wc -l`，P19 读出 52。那个数**依赖工作树里有没有没删干净的壳**——
`mmguardian/` 与 `shell/` 两个空目录 git 不跟踪，所以在作者的树上是 52、在干净克隆里是 50，
而"52 个目录"被写成了一句听起来像事实的话。换成 `git ls-files docs/verification | cut -d/ -f3 | sort -u | wc -l`
之后两边都是 50，P20 加进 `p20-clone/` 才变 51，**这一格从此只在能重跑的那条命令上成立**）：
P14 那一遍读到 44，P15 那轮新增 `p15-pipe/` 与 `p15-v1/` 两个，P16 新增 `p16-citations/` 一个，
P17 新增 `p17-website/` 一个，P18 新增 `p18-hooks/` 一个（引用审计日志跟着那一族照片走，没另开目录），
P19 新增 `p19-v1/` 与 `p19-hooks/` 两个（**核验轮每轮 +2 是有意的**：这一轮重跑的是两道不同的门禁，
而上一轮那两份证据的归因头写的是另一个 commit，盖掉就等于把"哪棵树产的照片"这条信息抹了），
**P20 新增 `p20-clone/` 一个**（这一遍只多一个目录，而且**第 3g 步钩子门禁本轮没重跑**——
被测的是同一个 commit 里同一份钩子实现，P19 那 23 档结论仍然成立，
本轮的新事实是"这一遍整棵树上没有一样东西没进版本控制"，不是钩子行为变了；
**多一个目录要有新事实才配多，少跑一步也要照写**）——
**P21 新增三个**：`p21-v1/`（§10 第 3 步第八遍，跑在带闸门改动的 1.0.0(1) 候选产物上）、
`p21-disk/`（磁盘页删除面板四档重拍，回执与 `p68-disk/` 逐字相同——这一份是"改了标签没改坏删除路径"的回归证据）、
`p21-disk-risk/`（**这一格拍不了照**：闸门按字面路径拒绝的那批路径全在 `/tmp` 之外，钩子根本不收，
所以换成一份能重跑的探针表 `risk-labels.log` 加本轮引用门禁日志，理由见 §7.12）；
**P22 新增四个**：`p22-v1/`（§10 第 3 步第九遍）、`p22-disk/`（`p68-disk-capture.sh` 在本轮二进制上的
四档重拍，回执与 `p21-disk/` 逐字相同——**同一支脚本连着两轮各重拍一份**，是因为它的判据就是"数字没变"，
盖掉上一轮那份就没有"没变"可对了）、`p22-disk-skip/`（新夹具两档：徽章在 1/2/3 层都有跳过时报几）、
`p22-citations/`（本轮引用门禁日志 + **第一次入库的全量测试结论行**，见 §7.13）。
**P23 新增四个**：`p23-v1/`（§10 第 3 步第十遍，三份归因头带 `# digest:` 的照片）、
`p23-disk-skip/`（磁盘跳过徽章两档，**只在新加的那一行日志上有新事实**，画面只有真机那两格动了，
理由见 §7.14 末尾）、`p23-provenance/`（同源门禁的五档否证 `probe.log`）、
`p23-citations/`（引用门禁日志 + 本轮测试结论行）。
`git ls-files docs/verification | cut -d/ -f3 | sort -u | wc -l` 现读 **62**。
**注意上面 P17 那一格里那四张照片不在 `docs/verification/`**，它们的去向是
`docs/website/assets/`（宣传图不是验收证据），所以 `p17-website/` 只有 `capture.log`。本文更早的版本写的是
"37 个（P12 之后 38）"——那个数从 P10/P11 起就没跟着涨，是本文**唯一一个自己没被计数脚本罩住的数**，
现已改成现读）。

**P12 留下的那条待办已由 P11c 关掉（2026-10-05）**：活动卡的文案合同（`fidelity-guardian.md` §6.6.6、§6.7，
任务 #107）。P12 那一段的原话是"这一格要不要发，取决于第 2 层的三项什么时候定；定了走 Developer ID，
那张卡的谓词得先重定，否则用户看到的'系统活动'其实是'我们自己在扫描'"——
**答案是整族撤下**：八档谓词实测下来没有一档同时满足"低噪声 + 可读 + 说的是这件事"（§3 第 2 行、
`fidelity-guardian.md` §6.7 的量表），所以这一卡现在只报**密钥目录与用户 LaunchAgent 的 mtime**，
名也改成了「密钥与自启配置的改动时间」。它不再依赖签名档次，也不再依赖 Developer ID 什么时候定——
**这一格和发版那三项决定脱钩了**。

**P14（2026-10-05）把 P13 挂着的那条 D1 关掉，同时照出一个新缺口**：页头副标题从前只列三件事、
这一屏有四张卡，现在它由 `GuardianPageCopy.subtitleSegments` 一份清单生成，段数有测试钉住、
排得下与否有照片钉住（§7.5）。**新缺口不在代码里，在对照表之外**：这一轮为了扫改名残留而
`grep` 全站，才发现 `docs/website/index.html` 那句"监控系统活动"从 P11c 起就是假话，
而这份落地页**从来没有进过任何一张 fidelity 对照表**（改动前 `grep -rn website docs/analysis/` = 0 命中）。
逐元素对照表能测"稿与实现像不像"，测不出"还有第三个表面没被看过"。已进 §6 表格单列一行，
判档"不在产物里·本轮起才进表"，**不阻塞发版**，但发版若要用这一页就得先单开一轮把它过完。

**P15（2026-10-05）没有关掉任何一条待办，它关掉的是 P11 留的那笔"同类形状还在别处"的账**：
三处子进程启动点并成 `MMCore/CommandRunner.swift` 一处（§1 那一格从 3 变 1），
读侧第一次有了时限、写侧明确不设时限，五条 >64 KB 的合同测试加一份事前否证（§7.6）。
**这一轮对"能不能发"的判定没有影响**——它改的是取数路径的可靠性，不是任何一屏的画法，
五遍核验的版本链、签名档次、Gatekeeper 结论逐字相同。它影响的是另一件事：
**下一轮再加系统命令时，只有一个人人可用的入口、和一个"报字节数而不是报安心"的口径**（`hook-ledger.md` §5）。
§3 那条空白（`launchctl` 写侧）仍然没测，P15 特意**没有**为了好看去测它——真点一下就会改这台机器的自启状态。

**P16（2026-10-06）对"能不能发"的判定同样没有影响，它改的是"这话有没有人验过"**：
代码一行没动，动的是 31 份入库文档里的每一处位置引用（总数只记 §1 那一格，见 §7.7）。
它给发版前 checklist 加了第 **3e** 步，从此"文档里的行号还是不是那一行"是一条**跑得出退出码**的判据，
而不是某一轮手工核对时顺带看一眼。
**这一轮最值得留下的不是那 12 处改对的引用，是那三个"0 差点是假的"**：抽取器静默漏掉两份中文名文档、
符号面看不见 `类型.成员`、判据会被脚本自己的注释喂活——三条都是否证跑出来的，
和 P11 那条"没发作不等于写对了"是同一族：**一个数的 0，只有在其判据被证明能亮的时候才是结论**。
文档层的空白也照出来了：`docs/website/index.html` 当时仍没进过任何对照表（§6 那一格、§11 第 3 条那句限定），
P16 的脚本只看 `路径:行号` 这种锚点，**量不出"这句话对着实现是不是真的"**。

**P17（2026-10-06）补的就是 P16 量不出来的那一层**：那一页逐句对着实现读了 16 行判定表，
三处"说不到"（4 条主张）改掉、两个死链换成能兑现的获取路径、四个占位框换成四档夹具实拍（§7.8）。
对"能不能发"的判定**仍旧没有影响**——它不进产物。它影响的是发版说明与（将来的）官网那句话的可信度：
一页没人核过的宣传文案，和一句写进界面的"监控系统活动"是同一类错误，只是受众更宽。
**这一轮留下的可复用判据有两条**：① 落地页这类会被整段重写的文件，文档里**别用行号锚点指它**
（`.html` 在引用审计的扩展名清单里，锚点会随重写漂走）；② 宣传图走夹具档之前要先查**钩子覆盖面**——
本轮两条边界（清理屏只能拍 dev tab、侧栏卷信息条无钩子）都是拍完看照片才发现的，
而发现之后的处理方式是**在页面上明说**，不是裁掉。

**P23（2026-10-06）关的是 P22 留的那格"没有门禁"，对"能不能发"的判定仍然没有影响**：
一行编译输入都没动（622 / 26,730 / 9,535 / 52 四个数现读与 P22 逐字相同），
产物、签名档次、Gatekeeper 结论也逐字相同。它影响的是**下一批照片的可信度**：
"照片跑的是最终那份产物"这句话从 P23 起不再依赖人记得构建顺序，
取证脚本会在起跑那一秒用内容指纹比一遍，不等就 exit 4、一张都不出（§7.14）。
**这一轮留下的可复用判据有三条**：① **commit 标签证明不了内容同源**——`-dirty` 只说"有改动"，
不说改了哪个文件哪一行，而 P22 那一次改的正是"位置"；要量内容就得算内容哈希。
② **"拍完再核"的形态一律不成立**：mtime 排序在 `git checkout` 之后必然破，
所以这类判据只有"当场拒"一种写法——写成事后审计等于写了一条会在别人机器上假阳性的规则。
③ **门禁必须自带"它会不会永远失败"那一档**（probe 的 ⑤）：
一条只会拒的门禁活不过下一轮，人会把它注释掉；⑤ 测的正是"同源时它必须放行"。
第 4 步仍 ⬜：本轮的照片（`docs/verification/p23-v1/02-about.png`）把那句人拍板的话
原样摆在关于页上——许可「尚未选择许可」、反馈「未配置官方渠道」。

