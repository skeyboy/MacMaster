# MacMaster v1.0 就绪度核验（release-readiness）

> 本轮（P7b）的目的不是再加功能，而是回答一个问题：**现在这份代码能不能作为第一个稳定版本发出去，
> 以什么形态发，发之前必须先补什么。** 逐条清单不重复 `docs/analysis/fidelity-*.md`，
> 本文只给判定、阻塞项和范围建议。
>
> **文中所有数字都是 2026-10-05 现跑的**，不是从上一轮文档抄的。每条结论后面都跟着它的取数命令或代码位置。

## 0. 结论先行

- **功能面：可以发。** 九个包全绿：`579` 个测试、`0` 个失败、`1` 个跳过（跳过原因见 §1）。
  六个业务模块都有真机照片级别的取证，且本轮之前发现的"界面上说了代码库支撑不了的话"已收口（§7）。
- **分发面：现在这份产物还不能直接发给别人。** 它是 **ad-hoc 签名**、Gatekeeper 判定 `rejected`、
  没有许可证书（§2）。图标那一项 **P10 已补**（§2.2：`Resources/AppIcon.icns` + `CFBundleIconFile`）。
  剩下的都不是代码问题，是**发版动作**问题，各自都有明确的补法。
- **一句话判定**：作为 **"自己编译自己用 / 附带源码的私有分发"**——今天就能发。
  作为 **"给陌生人的 dmg"**——差 §2 的三项。§3 那条 hardened runtime 的兼容验证 **P11 已跑完**：
  本机实测七行能力**零行被打断**，所以走 §2.1 第 2 条**不需要砍功能**；
  剩下的空白是 `launchctl` 的**写侧**没测（会真改用户 launchd 状态），已如实记在 §3。
  （**P11c 注**：那七行里的"启 `/usr/bin/log show` 读统一日志"一行，**下一轮就从界面上撤下了**，
  所以当前二进制只剩六行需要那份兼容结论——测量本身没白做，它正是撤下的依据，见 §3 末尾与 §6.7。）
- **两个必须由人拍板、实现不代选的事项**：许可证（§2.3）与开发者身份（Apple Developer 账号，§2.1）。
- **§10 那份 checklist 的 1–3 步已经真跑过三遍**（P8 之后一遍 571/0/1；**P12 在带 P11 改动的二进制上
  581/0/1**；**P13 在带 P11c 改动的二进制上 579/0/1**，都是 2026-10-05）：
  `VERSION=1.0.0 BUILD=1` 的候选产物，照片把"版本号走到界面"这条链闭合了三次
  （§7.2、§7.3、§7.4）。**判定没变**：卡在第 4 步那四项人工决定上。
  P12 顺带把 §7.2 挂着的那句"含义未查"量成了事实：**那行 sandbox 警告是启动路径带来的，不是签名**（§7.3）。
  P11c 动过活动卡，**P13 就是那一遍补的账**：除了三张基础照片，还在候选产物上重拍了改名之后的
  那张卡（§7.4 表格最后一行）。**期望值以 §1 为准**，别拿 581 当基准。

## 1. 本轮实测数字

| 指标 | 值 | 怎么量的 |
| --- | --- | --- |
| 测试总数 | **579** | `./Scripts/run-all-tests.sh`（九包逐个 `swift test`，默认 debug 配置）。**P11 于 2026-10-05 重跑**：P7 落地时 566，P8 +5（MMDisk 4 + MMFileScanner 1，见 §7.1），P10 不变，P11 +10（MMGuardian 活动卡那三处读法的判据，见 §3）。**P11c 于同日重跑：581 → 579**——删掉 10 条日志拆行判据（被测函数随那一族一起撤下）、加 8 条文案合同判据（`ActivityCardContractTests`），净 −2；**这不是覆盖率退步**，被删的那 10 条测的读法已经从界面上没了 |
| 失败 | **0** | 同上，逐包读 `Test Suite 'All tests' passed` 后那行 |
| 跳过 | **1** | 唯一一条在 MMDisk：`DiskRemovalTests.swift` 的 `testMountedVolumeRootIsBlocked`（P12 现读 `:167`；此前写 `:173`，**漂了 6 行且没人说得清是哪一轮漂的**——这一格自 P7 起没被重读过），跳过理由原文 `本机没有第二块挂载卷`——**是环境不满足，不是功能没测** |
| 生产代码量 | **26,340 行** | `find Sources Packages -name '*.swift' -not -path '*/.build/*' -not -path '*/Tests/*' \| xargs wc -l`（P11c 重跑；P8 时 26,310，P10 +15 是关于页那枚 `appIconArtwork`，P11 +103 是 `scanUnifiedLog` 的并行读 + 拆行 + 取尾，**P11c −88 是那一族整批删除**） |
| 测试代码量 | **8,984 行** | 同一条命令换成 `-path '*/Tests/*'`（P11c 重跑；P7 时 8,790，P8 时 8,846，P11 时 8,957） |
| 取证钩子 | **52 个名字**（运行时 51） | `grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' \| sort -u \| wc -l`；多出来的一个是 `MM_TRASH_FIXTURE_PROBE`，只在测试里探 `/tmp` 守卫。**P11 与 P11c 两轮一个新增钩子都没加**（P11c 只改了既有 `MM_GUARDIAN_ACTIVITY_FIXTURE` 的 `rows` 档用词） |
| 子进程启动点 | **3 处** | `grep -rn "Process()" Sources Packages`（非测试）命中 3 行（P11c 重跑；从前是 4 处，`ActivityScanner.scanUnifiedLog` 那一处随统一日志族删除）。见 §3 |
| 网络代码 | **0** | `grep` `URLSession`/`NWConnection`/`Socket`/`Reachability` 在非测试源码里**无命中** |

逐包分布（同一条 `run-all-tests.sh` 输出，2026-10-05 **P11c** 重跑）：
MMCore 43 · MMUI 17 · MMFileScanner 116 · MMCleaner 18 · MMUninstaller 121 ·
MMDisk 66（含 1 跳过）· MMMonitor 53 · MMGuardian **91** · MMOptimizer 54。

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
> `Test run with 0 tests`，会把 MMCore 的 43 个测试在屏幕上显示成"跑了 0 个"；
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
| 启 `launchctl` 停用登录项（写侧） | `LoginItemStore.swift` `runLaunchctl`（`/bin/launchctl <cmd> -w <path>`） | runtime 需实测；沙盒会拒 | **未测**。点开关会真改用户 launchd 状态，本轮不制造这种改动——这是 §3 剩下的唯一空白 |
| `launchctl list` 核对（读侧） | `LoginItemStore.swift` `launchctlSnapshot` | 同上 | **无差**：两档都是 17 项、同两行挂「没在当前会话里加载」（`02-login-{base,hr}.png` 逐字节相同） |
| 启 `/usr/bin/log show` 读统一日志 | `MMGuardian.swift` `ActivityScanner.scanUnifiedLog`（**P11c 已删**，这一行记的是 P11 那一刻的实测） | runtime 需实测；受限环境会挂起，故自带 8 秒超时 | **无差**：两档各 **5 条真实事件行**、正文完整、**最新在前**（`03-activity-{base,hr}.png`，15:29 打在带流式读取 + 取尾 5 条的重建二进制上：base 五行 15:29:23.x、hr 五行 15:29:37.x，各自就是扫描那一刻）。两档不同的只有"哪 5 条最新"（相隔 14 秒拍的）。**这一格还查出了我们自己的三个 bug，见下**。**P11c 更正这一行的用途**：它证明的是"runtime 不拦这条路"，而下一轮量完八档谓词之后**这一族从界面上撤下了**（`fidelity-guardian.md` §6.7）——所以当前二进制里已经没有这一行，兼容结论只剩六行需要它，撤下的决定本身正是用这一路的实测做的 |
| 启 `/usr/bin/tmutil` 列本地快照 | `SystemSpaceReport.swift` `tmutilPath` | 只读子命令；沙盒受阻 | **无差**：两档都出「磁盘空间只读报告」，本地快照 `0 个` + "这台 Mac 目前没有本地快照"（`05-space-*.png`） |
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
  同样的"先等再读"形状在 `SystemSpaceReport.swift` 的 tmutil 那一处**没有**发作（输出小），本轮没改它。
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
  `MMCleaner.swift:931`（清理页预检）。**两个删除出口都过它**，没有第三道口子。
- **永久删除全仓只有一个入口**：`MMDisk.swift:1382` → `permanentlyDelete`。
  UI 侧必须勾选确认（`MMDisk.swift:1252` 的 Toggle，`:1269` 的
  `.disabled(plan.isEmpty || !permanentAcknowledged)`），且每次执行后 `permanentAcknowledged` 复位
  （`:1338`、`:1374`）。照片证据：`docs/verification/p68-disk/` 四档。
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

## 6. 逐模块判定

判定档位只有三档：**可发布** / **可发布·需在说明里标注** / **不发这一屏**。
"开放项"列只列**本轮仍开着**的，逐条细节在对应 fidelity 文档里。

| 模块 | 判定 | 依据与仍开放项 |
| --- | --- | --- |
| MMCore（设置/删除/台账） | **可发布** | 43 测试全绿；闸门与台账见 §5。无开放项 |
| MMFileScanner（扫描层） | **可发布** | 116 测试全绿，含快照解析两种表头形态与分类型（真机发现的 bug 已钉住）；P8 起 `CacheScanScope.selected(...)` 是清理页与概览页共用的那一条拼法（逐开关映射有单测）。开放项都在 UI 层不在这里 |
| MMCleaner（清理） | **可发布·需标注** | 18 测试。本轮 I4/I10 已收（`fidelity-cleaner.md`）。仍开着：**I5**（`MMFailurePanel` 缺"重试失败项"等补救——组件在 `c74f045` 已补，**全仓 11 个调用点（含壳层 `MainWindow.swift:244`）无一使用新 init**，`grep -rn "onRetry\|onCopyDiagnostics" Sources Packages` 除组件定义外零命中，所以统计行与页脚现在是死代码路径）、**I6b**（撤回开关只在缓存页 sheet，另两页走系统 `.alert`）、**I7**（只读分类仍带展开箭头）、**I8**（页签叫"缓存清理"、页头叫"系统清理"，两名不同源）。**标注内容**：可释放数字是扫描瞬时值，不是承诺值 |
| MMUninstaller（卸载） | **可发布** | 121 测试（全仓最多）。开着的是 **B1**（列表宽 268 令牌 vs 稿 300，归协调层）、**B2**（`MM_SHOW_TRASH_CONFIRM` 需与 `MM_TRASH_SCAN_HOME` 同时给的互锁没写进文档）——两条都是文档/稿侧缺口，不影响功能 |
| MMDisk（磁盘分析） | **可发布·需标注** | 66 测试（1 跳过）。永久删除闸门见 §5。**标注内容**：treemap 需要真实扫描，大目录下扫描时间与内存都要在说明里提一句；**触达深度上限（`maxDepth = 20`）的目录只量字节不列名字**，界面上写的是「子项 未枚举」——这句要在发版说明里保留，否则用户会以为那一格坏了。**I4 已于 P8 收口**（标签回「子项」+ 封顶档说「未枚举」，见 §7.1 与 `fidelity-disk.md` §12），仍开着的是 **I3**（详情头部图标与稿不同）、**I6**（相对时间 vs 绝对日期），以及**稿侧** `04-disk.html:163` 仍写递归「文件数 42,180」 |
| MMMonitor（监控 + 菜单栏） | **可发布** | 53 测试。SMC/IOKit 都有失败降级并在界面上说原文原因（§3 那两行）。开着 **I8**（网络速率只在菜单栏显示、页面不用——归设计稿决定） |
| MMGuardian（守护） | **可发布·需标注** | **91 测试**（P11c 现读：`swift test --package-path Packages/MMGuardian` → `Executed 91 tests, with 0 failures`。这一格从 93 变 91：撤下日志族删掉 10 条日志单测、活动卡文案合同新增 8 条，一减一增之后就是这个数）。**标注内容**：①TCC.db 读不到时需要用户手动授 FDA，界面对此有横幅（`guardian-tcc.md`）；②活动卡现在叫「密钥与自启配置的改动时间」，**只有 mtime、不报"最近访问"**，卡片底部把这句写在界面上（八档谓词测量与三条合同见 `fidelity-guardian.md` §6.7）——发版说明里不能把这一格写成"最近访问记录"；③统一日志那一档**P11c 已整族撤下**，所以这一模块不再有"起子进程读系统日志"这一项（§3 第 2 行）。从前这里挂着的那三条 `log show` 缺陷随之消失，但死锁的教训与复现件 `Scripts/p11-pipe-deadlock-repro.swift` 保留 |
| MMOptimizer（优化） | **可发布·需标注** | 54 测试。开着的是**形态题**（`MMFailurePanel` 通栏条 vs 带边框卡，与 cleaner I5 同一件事，归协调层）与 `fidelity-optimizer.md` 的 #8/#10 未拍全（跨 tab 运行态、阶段枚举）。**标注内容**：重复文件删除前必须人工核对分组，PROTECTED 组永远不给删除入口 |
| 壳层 `Sources/MacMaster` | **可发布·但零测试** | 根 `Package.swift` 只有一个 `.executableTarget`（`:22`），**没有测试目标**（`ls Sources/` 只有 `MacMaster`）。九包 579 个测试**一个都不覆盖壳层**——导航、窗口、设置页绑定全靠实机照片兜。**这是 v1.0 唯一一处"能力靠肉眼而不是靠测试"的地方**。P8 动过壳层（`DashboardModel.measureReclaimable` 现读设置拼 scope），**能单测的那一半已下沉**（`CacheScanScope.selected` 在 MMFileScanner，有单测），壳里剩下的三行只能靠 `p8-dashboard-scope/` 那三张照片。**P11c 现读补一句**：§4 写侧第 3 项那个登录项开关（`Sources/MacMaster/LaunchBehavior.swift`）也落在这一格"零测试"里，它的对照记录在 `fidelity-shell.md`，不在任何一条自动断言里 |
| MMUI / 设计系统 | **可发布** | 17 测试。全站骨架 token 漂移（侧栏 footer S1、标题栏 52 vs 38 I10b、底色 S3/S4）仍在，归协调层，纯视觉 |

## 7. 本轮收口的四处（都是"用户可达"的那一类）

| 位置 | 之前 | 现在 | 证据 |
| --- | --- | --- | --- |
| 设置 › 关于 › 许可 | 写 `MIT License`，仓库无 LICENSE | 「尚未选择许可」 | `p7-release-build/02-about.png` |
| 设置 › 通用 › 语言 | 可用 Picker，切换什么都不改 | `.disabled(true)` + 明说"界面文案尚未接入多语言，切换不会改变界面" | `p7-settings-lang/` |
| 概览 › 内存「交换」一行 | 默认窗宽下截成「2.1…」，像数据读坏了 | `MainWindow.swift` `gaugeRow` 的 note 加 `minimumScaleFactor(0.8)` | `p7-release-build/03-dashboard-min.png`（1000×600 下限窗口，显示完整「交换 688.6 MB / 2.15 GB」） |
| 清理页 四开关全关 | 副标题仍报一个数 | 三档分开：`scopeEmpty` / `isPartial` / 扫描真失败 | `p7-empty-scope/`，`fidelity-cleaner.md` I4 |

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

## 8. 已知不一致（不阻塞发版，但要有账）
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
- **`.gitignore` 把参考仓库排除了**（`docs/github-references/`、`docs/Mole/`、`docs/lemon-cleaner/`），
  而多份分析文档正文按那些路径引了源码位置。**别人 clone 之后那些引用是断链**。
  发版文档要么把引用改成"项目名 + 文件路径"这种可自证的写法，要么在 README 里说明这些目录需自行 clone。

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
# 1. 全量测试（期望 579/0/1、MMGuardian 91；数字变了要回写本文 §1）
./Scripts/run-all-tests.sh

# 2. 构建候选产物（版本单一来源；图标随仓库带着，构建前先自证一次）
./Scripts/make-icon.sh --check          # 反向解一次 icns，核十档齐全
VERSION=1.0.0 BUILD=1 ./Scripts/make-app.sh -o /tmp/mm-app-v1 -s /tmp/mm-scratch-v1

# 3. 三张基础照片 + 把签名/plist（含 CFBundleIconFile）/gatekeeper 结论写进日志归因头
#    重跑要换输出目录：这一条写进 /tmp 的那份日志归因头会**盖掉上一轮的证据**。
#    P9 第一遍写的是 docs/verification/v1.0.0/，P12 第二遍写 docs/verification/p12-v1/，
#    P13 第三遍写 docs/verification/p13-v1/。
./Scripts/p7-release-check.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p13-v1

# 3b.（可选，一次性的归因探针）那行 sandbox_extension 警告是路径带来的还是签名带来的（§7.3）
./Scripts/p12-sandbox-warning-probe.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p12-v1

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

**P12（2026-10-05，同一天的第二遍）第 1–3 步在带 P11 改动的二进制上重跑** ✅✅✅：
581/0/1 → `make-icon.sh --check` 过 → `/tmp/mm-app-v1`（`VERSION=1.0.0 BUILD=1`）→
`docs/verification/p12-v1/`（三张照片 + 三份归因日志 + 两份探针日志 + 一张用户目录窗口照片），
逐条判据见 §7.3；第 4 步 ⬜ 仍待人拍板；第 5 步不需要重跑（P11 那一份代码没再动过签名相关的东西，
而 §3 的三条限定仍然成立）。第 2、3 与 3b 步的产物与探针目录都是**一次性的**，跑完已清掉。

## 11. 「能不能发第一个稳定版本」——P12 的正面回答

问的不是"还有什么没做"，而是**今天把这份代码发出去，会不会说到做不到**。分三层答：

1. **作为"自己编译自己用 / 带源码的私有分发"：能发，今天就能。** §10 第 1–3 步跑过三遍（P13 是最新一遍，
   在带 P11c 改动的二进制上），
   §6 那十行判定全落在"可发布"或"可发布·需标注"两档（**没有一行是"不发这一屏"**）、
   §5 那道闸门两个删除出口都过、§4 零网络代码。
   需要写的只有 §9 那四条标注 + §4 的写盘三项（其中 `trash-history.json` 会记用户文件路径，必须写）。
2. **作为"给陌生人的 dmg"：还差三项，且三项都不是代码。** §2.1 的签名与公证（要账号）、
   §2.3 的许可（要拍板）、`NSHumanReadableCopyright` 的年份与权利人（要填名字）。
   **代价面 P11 已经量过**：走 Developer ID + 公证**不需要砍任何功能**（§3 结论 1，七行零打断）。
   所以这三项是**决定**，不是工作量。
3. **发之前不必再补的技术项**：本轮把 §3 的空白（`launchctl` 写侧）之外能测的都测了；
   §8 那五条是账、不是门（两处行号漂移本轮已改，两处死开关已明说，五处空骨架待人工决定，
   `.gitignore` 那条断链要在 README 里说明）。

**唯一一处"能力靠肉眼而不是靠测试"**：壳层零测试目标（§6 最后一行）。这一条**不阻塞发版**，
但发版说明里不该假装九屏都有回归保护——九屏的壳层部分是 579 条测试**没覆盖**的那一层，
它靠的是 `docs/verification/` 下那 **42 个目录**（P13 现读 `ls -d docs/verification/*/ | wc -l`：
40 个在 P11c 之前已入库，`p11c-activity/` 与 `p13-v1/` 是这两轮各新增一个。本文上一版写的是
"37 个（P12 之后 38）"——那个数从 P10/P11 起就没跟着涨，是本文**唯一一个自己没被计数脚本罩住的数**，
现已改成现读）。

**P12 留下的那条待办已由 P11c 关掉（2026-10-05）**：活动卡的文案合同（`fidelity-guardian.md` §6.6.6、§6.7，
任务 #107）。P12 那一段的原话是"这一格要不要发，取决于第 2 层的三项什么时候定；定了走 Developer ID，
那张卡的谓词得先重定，否则用户看到的'系统活动'其实是'我们自己在扫描'"——
**答案是整族撤下**：八档谓词实测下来没有一档同时满足"低噪声 + 可读 + 说的是这件事"（§3 第 2 行、
`fidelity-guardian.md` §6.7 的量表），所以这一卡现在只报**密钥目录与用户 LaunchAgent 的 mtime**，
名也改成了「密钥与自启配置的改动时间」。它不再依赖签名档次，也不再依赖 Developer ID 什么时候定——
**这一格和发版那三项决定脱钩了**。

