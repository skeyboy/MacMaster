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

## 测试

```bash
./Scripts/run-all-tests.sh     # 九个包逐个 swift test，逐包一行结论 + 总计
```

现测（2026-10-05）：**571 个测试、0 失败、1 跳过**。不要手敲 `swift test | tail -4`——
SwiftPM 的结论行有两种形态，那样会把 MMCore 的 43 个测试显示成"跑了 0 个"
（原因与解析规则写在脚本头部注释里）。

**壳层 `Sources/MacMaster` 没有测试目标**（根 `Package.swift` 只有一个 `.executableTarget`），
所以导航、窗口、设置页绑定这三件事目前只有实机照片兜，没有单测。

## 七个页面与九个包

| 页面 | 包 | 它实际做什么 |
| --- | --- | --- |
| 概览 | 壳层 + 各包 | 实时采样（CPU/内存/磁盘 IO/卷）、存储构成堆叠条、可释放估算。页上的「开始清理」按钮**只做跳转** |
| 系统清理 | `MMCleaner` + `MMFileScanner` | 按四个类别勾选扫缓存/日志/临时项，逐类风险分级，只读分类不给删除入口 |
| 开发产物 | `MMCleaner` | `node_modules`/`build` 这类项目产物，含"截断根分批续扫"与在用/受保护判定 |
| 应用卸载 | `MMUninstaller` | 残留扫描、安装包归属、Homebrew/MAS 来源识别、废纸篓与 `/Applications` 装卸监听 |
| 磁盘分析 | `MMDisk` | treemap 下钻 + 标记批量移除（回收 / 永久删除两条路径） |
| 系统监控 | `MMMonitor` | 菜单栏指标 + SMC 温度/风扇 + 进程列表；IOKit 读不到时界面明说读不到 |
| 隐私守护 | `MMGuardian` | 摄像头/麦克风占用、TCC 授权只读视图、登录项管理 |
| 优化 | `MMOptimizer` | 重复文件（SHA-256）、浏览器缓存、开发工具占用、系统状态 |
| 设置 | `MMCore` + 壳层 | 18 项持久化设置 + 关于页 |

包结构：`Packages/MMCore`（设置、删除闸门、台账、导航）、`MMUI`（设计令牌与共享组件）、
`MMFileScanner`（遍历与各类扫描器）是**三个共享层**，其余六个是功能模块。
**功能模块之间互不依赖**——现读全仓 `^import MM` 只有 `MMCore`/`MMUI`/`MMFileScanner` 三种命中，
六个功能模块一个也没 import 过另一个功能模块。跨页跳转因此走 `NotificationCenter`
（`Packages/MMCore/Sources/MMCore/Navigation.swift`）而不是直接调对方。

## 权限与隐私

**会读的**：`~/Library/Caches`、`~/Library/Logs`、`~/Library/Containers/*/Data/Library/Caches`、
per-user 的 `getconf DARWIN_USER_CACHE_DIR`、系统级 `/Library/Caches` 与 `/Library/Logs`、
`~/Library/Application Support/MobileSync/Backup`（只列体积，不给删除）、`/Applications`、`~/.Trash`、
`/var/db/receipts`（安装包收据）、Homebrew 账本、统一日志（`/usr/bin/log show`，只过 `login`/`auth` 关键字）。
重复文件检测会**读文件内容**算哈希（先头尾采样，命中候选才整文件读）。
浏览器那几行只读**缓存目录**，不读 History / Cookies / 密码库。

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

## 已知的坑（别再踩一遍）

- 有 5 个**空目录**git 不跟踪、`git status` 也看不见：
  `MacMaster/`、`MacMasterHelper/Sources/MacMasterHelper/`、`MacMasterWidgets/Sources/MacMasterWidgets/`、
  `docs/verification/mmguardian/`、`docs/verification/shell/`。前两个是**没落地的 helper/widget 骨架**，
  现在没有任何代码在里面。
- `docs/github-references/`、`docs/Mole/`、`docs/lemon-cleaner/` 在 `.gitignore` 里（各自带独立 `.git` 与许可）。
  多份分析文档按这些路径引了第三方源码位置，**clone 之后那些引用是断链**，需要自行 clone 对应项目。
- ~~概览页的"可清理"走 `scanAll()`，不看清理页那四个勾选~~ —— **P8（2026-10-05）已修**：
  两个页面现在共用 `CacheScanScope.selected(...)` 拼勾选、也共用同一份排除清单，
  四个类别全关时概览显示「未勾选类别」而不是一个来路不明的数。
  取证与逐档读数记在 `docs/analysis/release-readiness.md` §7.1。

## 发布状态

**功能就绪、分发未就绪**。产物是 ad-hoc 签名（`flags=0x2(adhoc)`、`TeamIdentifier=not set`），
Gatekeeper 判 `rejected`；没有图标；许可未定。自己编译自用不受影响，发给别人则要先补这三项。
逐模块判定、hardened runtime / 沙盒会打断哪七条现有能力、以及 v1.0 建议范围与
发版前 checklist：**`docs/analysis/release-readiness.md`**。

checklist 的 1–3 步（全量测试 → `VERSION=1.0.0 BUILD=1` 出候选产物 → 三张照片闭合并验证
"版本号从打包脚本走到关于页"）已在 2026-10-05 实跑，证据 `docs/verification/v1.0.0/`；
第 4 步（许可、图标、权利人、签名方式）是人的决定，实现不代拍。
