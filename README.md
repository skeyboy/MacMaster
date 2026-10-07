# MacMaster

原生 macOS 的清理 / 卸载 / 磁盘分析 / 监控 / 守护 / 优化工具。Swift + SwiftUI，
SwiftPM 多包结构，无第三方依赖，**无任何网络代码**。

- 系统要求：**macOS 14.0+**（`Package.swift` 的 `.macOS(.v14)`，产物 `Info.plist` 的 `LSMinimumSystemVersion=14.0`）
- 工具链：swift-tools-version 5.9；本仓库开发与全部取证都在 Apple Swift 6.4 / macOS 27 上完成
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
**P23 起还写 `MMSourceDigest`**——那 92 个编译输入（`Sources` / 九个包的 `Sources` 与 `Package.swift` /
根 `Package.swift` / `Resources/AppIcon.icns`，**不含测试源码**）的**内容**哈希，前缀拼 HEAD 短 sha。
为什么要它：`-dirty` 只说"工作区有改动"，不说改了哪个文件哪一行，
而 P22 撞的那一次（搬动一个私有辅助函数的位置）恰好是 commit、脏净态与画面**三条线都看不见**的改动。
取证脚本（`p7-release-check` 与那四支 capture）起跑前先比这个指纹，**不同源就 exit 4、一张都不出**，
配方一份在 `Scripts/mm-provenance.sh`，构建侧与取证侧共用（两边各算一遍等于没门禁）。
十遍发版核验的产物版本号逐字相同（**现读 33 份 .log 带 `CFBundleShortVersionString=1.0.0 CFBundleVersion=1` 这一对键，
一个写法**：`grep -rl "CFBundleShortVersionString=1.0.0 CFBundleVersion=1" docs/verification --include='*.log' | wc -l`），
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
```

现测（2026-10-06，P22 之后重跑）：**622 个测试、0 失败、1 跳过**（P11 那遍是 581，P11c 撤下统一日志那一族时
删掉 10 条它的单测、新增 8 条活动卡文案合同单测 → 579；P14 加 4 条页头副标题合同单测 → 583；
P15 加 7 条子进程读法判据（`CommandRunnerPipeTests` 5 + `LaunchctlRunnerTests` 1 + `SystemSpaceReportTests` 1）→ 590；
**P18 加 22 条钩子判定单测**（`HookValueTests` 15 + `LaunchHookTests` 7，全在 MMCore）→ 612；
**P21 加 9 条删除闸门口径判据**（`DeletionGuardTests` +3：`/dev`、`/private`、"字面问与全量问不许给两种答案"；
`DiskRiskTests` 全新 6 条：界面标签不许和闸门唱反调）→ 621；
**P22 加 1 条跳过披露判据**（`DiskScannerHierarchyTests.testNestedProtectedSkipIsDisclosed`：
受保护目录跳过发生在每一层，披露也必须覆盖每一层）→ 622）。
**逐包求和 = 622**（73 / 17 / 117 / 18 / 121 / 73 / 53 / 96 / 54），这一条自 P11c 起每轮都当自证用；
**这一跑第一包和第六包都是 73**（MMCore 与 MMDisk），读那行数字时别把两格并成一格——
按名字读，别按"73 出现过一次"读。
**P20 那遍是在一次干净 `git clone` 出来的树上跑的**，那一跑九个包逐包数一个不差
（70 / 17 / 117 / 18 / 121 / 66 / 53 / 96 / 54——MMCore 的 +3 与 MMDisk 的 +6 是 P21 那一跑之后才有的，
MMDisk 再 +1 是 P22 之后才有的）。不要手敲 `swift test | tail -4`——
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
| 应用卸载 | `MMUninstaller` | 残留扫描、安装包归属、Homebrew/MAS 来源识别、废纸篓与 `/Applications` 装卸监听 |
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

- **`MM_*` 环境变量钩子**（52 个名字，运行时 51 个）：把某一态的数据喂进页面。
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

checklist 的 1–3 步（全量测试 → `VERSION=1.0.0 BUILD=1` 出候选产物 → 三张照片闭合并验证
"版本号从打包脚本走到关于页"）**已实跑十遍**：前五遍都在 2026-10-05——P9 那遍 571/0/1（证据
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
第 4 步（许可、权利人、签名方式）是人的决定，实现不代拍。

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
