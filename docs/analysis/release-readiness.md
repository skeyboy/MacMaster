# MacMaster v1.0 就绪度核验（release-readiness）

> 本轮（P7b）的目的不是再加功能，而是回答一个问题：**现在这份代码能不能作为第一个稳定版本发出去，
> 以什么形态发，发之前必须先补什么。** 逐条清单不重复 `docs/analysis/fidelity-*.md`，
> 本文只给判定、阻塞项和范围建议。
>
> **文中所有数字都是 2026-10-05 现跑的**，不是从上一轮文档抄的。每条结论后面都跟着它的取数命令或代码位置。

## 0. 结论先行

- **功能面：可以发。** 九个包全绿：`581` 个测试、`0` 个失败、`1` 个跳过（跳过原因见 §1）。
  六个业务模块都有真机照片级别的取证，且本轮之前发现的"界面上说了代码库支撑不了的话"已收口（§7）。
- **分发面：现在这份产物还不能直接发给别人。** 它是 **ad-hoc 签名**、Gatekeeper 判定 `rejected`、
  没有许可证书（§2）。图标那一项 **P10 已补**（§2.2：`Resources/AppIcon.icns` + `CFBundleIconFile`）。
  剩下的都不是代码问题，是**发版动作**问题，各自都有明确的补法。
- **一句话判定**：作为 **"自己编译自己用 / 附带源码的私有分发"**——今天就能发。
  作为 **"给陌生人的 dmg"**——差 §2 的三项。§3 那条 hardened runtime 的兼容验证 **P11 已跑完**：
  本机实测七行能力**零行被打断**，所以走 §2.1 第 2 条**不需要砍功能**；
  剩下的空白是 `launchctl` 的**写侧**没测（会真改用户 launchd 状态），已如实记在 §3。
- **两个必须由人拍板、实现不代选的事项**：许可证（§2.3）与开发者身份（Apple Developer 账号，§2.1）。
- **§10 那份 checklist 的 1–3 步已经真跑过一遍**（P8 之后，2026-10-05）：571/0/1 → `VERSION=1.0.0 BUILD=1`
  的候选产物 → 三张照片把"版本号走到界面"这条链闭合（§7.2）。**判定没变**：卡在第 4 步那四项人工决定上。
  P11 之后第 1 步重跑是 **581/0/1**（多的 10 条全在 MMGuardian：活动卡那三处读法的判据，见 §3）。

## 1. 本轮实测数字

| 指标 | 值 | 怎么量的 |
| --- | --- | --- |
| 测试总数 | **581** | `./Scripts/run-all-tests.sh`（九包逐个 `swift test`，默认 debug 配置）。**P11 于 2026-10-05 重跑**：P7 落地时 566，P8 +5（MMDisk 4 + MMFileScanner 1，见 §7.1），P10 不变，P11 +10（MMGuardian 活动卡那三处读法的判据，见 §3） |
| 失败 | **0** | 同上，逐包读 `Test Suite 'All tests' passed` 后那行 |
| 跳过 | **1** | 唯一一条在 MMDisk：`DiskRemovalTests.swift:173 testMountedVolumeRootIsBlocked`，跳过理由原文 `本机没有第二块挂载卷`——**是环境不满足，不是功能没测** |
| 生产代码量 | **26,428 行** | `find Sources Packages -name '*.swift' -not -path '*/.build/*' -not -path '*/Tests/*' \| xargs wc -l`（P11 重跑；P8 时 26,310，P10 +15 是关于页那枚 `appIconArtwork`，P11 +103 是 `scanUnifiedLog` 的并行读 + 拆行 + 取尾） |
| 测试代码量 | **8,957 行** | 同一条命令换成 `-path '*/Tests/*'`（P11 重跑；P7 时 8,790，P8 时 8,846） |
| 取证钩子 | **52 个名字**（运行时 51） | `grep -rhoE 'MM_[A-Z_0-9]+' Packages Sources --include='*.swift' \| sort -u \| wc -l`；多出来的一个是 `MM_TRASH_FIXTURE_PROBE`，只在测试里探 `/tmp` 守卫。**P11 实测轮一个新增钩子都没加**（见 §3 的"零夹具"规定） |
| 子进程启动点 | **4 处** | `grep -rn "Process()" Sources Packages`（非测试）命中 4 行，见 §3 |
| 网络代码 | **0** | `grep` `URLSession`/`NWConnection`/`Socket`/`Reachability` 在非测试源码里**无命中** |

逐包分布（同一条 `run-all-tests.sh` 输出，2026-10-05 P11 重跑）：
MMCore 43 · MMUI 17 · MMFileScanner 116 · MMCleaner 18 · MMUninstaller 121 ·
MMDisk 66（含 1 跳过）· MMMonitor 53 · MMGuardian 93 · MMOptimizer 54。

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
| 启 `/usr/bin/log show` 读统一日志 | `MMGuardian.swift` `ActivityScanner.scanUnifiedLog` | runtime 需实测；受限环境会挂起，故自带 8 秒超时 | **无差**：两档各 **5 条真实事件行**、正文完整、**最新在前**（`03-activity-{base,hr}.png`，15:29 打在带流式读取 + 取尾 5 条的重建二进制上：base 五行 15:29:23.x、hr 五行 15:29:37.x，各自就是扫描那一刻）。两档不同的只有"哪 5 条最新"（相隔 14 秒拍的）。**这一格还查出了我们自己的三个 bug，见下** |
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

**同一轮还修了取证脚本自己的一个假选择器**：`p11-hardened-check.sh` 的 `ONLY=03,05` 逐档重拍
写在注释里承诺过，实现却是整块用 `ONLY=shots` 把门——点名档号会把五档全跳过。现在五档各自把关。

## 4. 隐私面（发版说明里必须写的东西）

**读**（全部在用户本机，无外发）：
- 缓存与日志根：`~/Library/Caches`、`~/Library/Logs`、`~/Library/Containers/*/Data/Library/Caches`、
  `getconf DARWIN_USER_CACHE_DIR`（`CacheScanner.swift:131-162`）、系统级 `/Library/Caches`、`/Library/Logs`
  （`SystemAnalyzer.swift:104-176`）。
- iOS 备份目录（**只读列体积，分类为只读不给删除入口**）：`~/Library/Application Support/MobileSync/Backup`
  （`SystemAnalyzer.swift:118,150`）。
- 浏览器：优化页只列**缓存目录**（`MMOptimizer.swift:615-616` 的
  `~/Library/Caches/com.apple.Safari`、`~/Library/Caches/Google/Chrome`）。
  **不读 History / Cookies / 密码库**——这条要说清，因为页面上出现了浏览器名字，用户会往那个方向理解。
- 重复文件：`DuplicateScanner.swift:238-255` 会**读文件内容**算 SHA-256（先头尾各采样，
  命中候选才整文件哈希；任何读失败都计入 `unreadablePaths`，宁可漏报不误报）。
- 统一日志 `log show`（§3 第 2 行）与 `/var/db/receipts` 安装包收据、`~/.homebrew` 账本 —— 都是只读归属证据。

**写**（用户机器上会长期留下什么）：
1. `~/Library/Preferences/com.macmaster.app`（`UserDefaults.standard`，18 个键 +
   `CleanerExclusions` 的前缀键）——P7a 那轮"改设置态"取证用的就是这里，代价见 `hook-ledger.md` §0。
2. `~/Library/Application Support/MacMaster/trash-history.json`（`TrashHistoryStore.swift:17-22`，
   原子写）——**这是唯一一份记录了用户文件路径的磁盘文件**，为的是跨启动撤回。发版说明里要写这一条。
3. 系统登录项注册/注销（`SMAppService.mainApp`，`LaunchBehavior.swift:24-37`）。
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
- 永久删除**不写台账**（`FileTrashService.swift:79-83` 的文件注释写明理由：
  没有"到哪去"就写进「最近操作」，只会多出一个点不动的撤回按钮）。
- 撤回路径**故意不经 DeletionGuard**：它写回的是台账里记的 `originalPath`，
  不是新路径。这条是设计而非漏洞，记在 `docs/analysis/deletion-guard.md`。

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
| MMGuardian（守护） | **可发布·需标注** | 83 测试。**标注内容**：TCC.db 读不到时需要用户手动授 FDA，界面对此有横幅（`guardian-tcc.md`）；统一日志那一档在非受限环境也会慢，已有超时保护 |
| MMOptimizer（优化） | **可发布·需标注** | 54 测试。开着的是**形态题**（`MMFailurePanel` 通栏条 vs 带边框卡，与 cleaner I5 同一件事，归协调层）与 `fidelity-optimizer.md` 的 #8/#10 未拍全（跨 tab 运行态、阶段枚举）。**标注内容**：重复文件删除前必须人工核对分组，PROTECTED 组永远不给删除入口 |
| 壳层 `Sources/MacMaster` | **可发布·但零测试** | 根 `Package.swift` 只有一个 `.executableTarget`（`:22`），**没有测试目标**（`ls Sources/` 只有 `MacMaster`）。九包 571 个测试**一个都不覆盖壳层**——导航、窗口、设置页绑定全靠实机照片兜。**这是 v1.0 唯一一处"能力靠肉眼而不是靠测试"的地方**。P8 动过壳层（`DashboardModel.measureReclaimable` 现读设置拼 scope），**能单测的那一半已下沉**（`CacheScanScope.selected` 在 MMFileScanner，有单测），壳里剩下的三行只能靠 `p8-dashboard-scope/` 那三张照片 |
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

**一条如实记录的观察**：六份日志（P7 的三份 + 本轮三份）都有一行
`sandbox_extension_issue_file_to_process failed for …: 1 (Operation not permitted)`，
来自 ad-hoc 构建从 `/tmp` 起进程。含义未查，两轮都有、非本轮引入，界面与功能不受影响；
换成 Developer ID 签名 + 正常安装位置之后应复看一次再决定要不要当问题。


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
- **"检查更新"不是死开关，但它不联网**：`SettingsView.swift:304-310` 只读本机 Info.plist，
  并在弹窗文案里明说"当前构建未配置更新服务器"。发版说明别写"自动更新"。
- **"反馈问题"按钮是 disabled**：`SettingsView.swift:280-288`，旁边一句"未找到官方反馈渠道地址，不做虚构链接"。
  有了仓库地址再放开。
- **5 个空目录**：`MacMaster/`、`MacMasterHelper/Sources/MacMasterHelper/`、
  `MacMasterWidgets/Sources/MacMasterWidgets/`、`docs/verification/mmguardian/`、`docs/verification/shell/`
  （git 不跟踪空目录，所以 `git status` 里看不见；前两处像是没落地的 helper/widget 骨架）。
  要么补内容要么删掉，别让下一个人以为有个 helper 靶子。
- **`.gitignore` 把参考仓库排除了**（`docs/github-references/`、`docs/Mole/`、`docs/lemon-cleaner/`），
  而多份分析文档正文按那些路径引了源码位置。**别人 clone 之后那些引用是断链**。
  发版文档要么把引用改成"项目名 + 文件路径"这种可自证的写法，要么在 README 里说明这些目录需自行 clone。

## 9. 建议的 v1.0 范围与版本号

**发**：§6 表中所有"可发布"档，即九屏全部功能；`LSMinimumSystemVersion 14.0`。
**在发版说明里明确标注**：§6 表里那四条"可发布·需标注"（判定列逐行数，别拿 `grep -c 需标注` 当计数——
本文自己这段话里就含一次"需标注"）、§4 的写盘三项。（§8 那条"概览口径"已于 P8 收口，
不再需要标注——现在概览与清理页是同一个数。）
**不发**：Mac App Store（§3 的六行砍得太狠）；多语言（语言开关本轮已禁用，没有 UI 消费点）；
自动更新（没有更新服务器）；helper/widget 两个空壳（§8）。

**版本号建议**：`CFBundleShortVersionString=1.0.0`、`CFBundleVersion=1`。
版本号只有一个来源——`Scripts/make-app.sh` 里 `VERSION=${VERSION:-1.0.0}` 与 `BUILD=${BUILD:-1}`
那两行（现 `:38-39`），所以**发版命令就是**：

```
VERSION=1.0.0 BUILD=1 ./Scripts/make-app.sh
```

P7 那轮的 `1.0.0-rc1 (1)` 是**取证用的构建**，界面显示的字符串与 plist 一致；
P8 之后按 §10 出的 **v1.0.0 候选产物**也已闭合同一条链（§7.2 第一行：plist `1.0.0`/`1` ↔ 关于页
「版本 1.0.0 (1)」，同一张照片里）。不要 `rc` 进正式版：`make-app.sh` 不解析版本号，
`rc` 会原样进 plist，`about` 页会跟着显示。

## 10. 发版前 checklist（可直接执行）

```
# 1. 全量测试（期望 581/0/1；数字变了要回写本文 §1）
./Scripts/run-all-tests.sh

# 2. 构建候选产物（版本单一来源；图标随仓库带着，构建前先自证一次）
./Scripts/make-icon.sh --check          # 反向解一次 icns，核十档齐全
VERSION=1.0.0 BUILD=1 ./Scripts/make-app.sh -o /tmp/mm-app-v1 -s /tmp/mm-scratch-v1

# 3. 三张基础照片 + 把签名/plist（含 CFBundleIconFile）/gatekeeper 结论写进日志归因头
./Scripts/p7-release-check.sh /tmp/mm-app-v1/MacMaster.app docs/verification/v1.0.0

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

