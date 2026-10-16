# Uninstally 采纳分析：卸载页的三块招牌（残留 / Homebrew / Finder 右键）

> 参考源：`docs/github-references/uninstally`（gostonx/uninstally，SwiftUI + 一个 FinderSync 扩展，MIT，
> 钉在 `c01646dc…`（= tag v1.7.3，提交日 2026-07-10），取法与登记见 [reference-repos.md](reference-repos.md) 第 2 节第 53 行那一格）。
> 本文**两侧行号都是本轮（2026-10-16）对着磁盘上的树逐文件读出来的**：参考侧 84 个 `.swift` 落盘、
> `git ls-files` 140 条（差额是那 20 项被 skip-worktree 的 GIF/PNG，见 reference-repos.md §2.1）；
> MacMaster 侧行号来自同一轮现读。写文档时未改任何代码。

## 一句话结论

Uninstally 的三块招牌里，**只有"残留删除"这一块和我们的差距是真的**：它的删除链条是
"正白名单允许根 + 精确匹配的保护区 + 执行时二次校验 + 结构化留痕"四段，我们只有后两段的半截
（`DeletionGuard` 是纯黑名单，没有"只能落在这些根里"的正向闸）。
**Homebrew 管理**它靠真的执行 `brew`，我们已经用"只读 brew 自己留下的账本"覆盖了同一批问题，
而且证据强度更高（设备号同一 vs 路径前缀 `contains`）——这一块的差距不在能力而在**呈现**：
面板、反向依赖、可删体积。
**Finder 右键卸载**是它最出圈的一条，但那是**签名与授权问题不是代码问题**：
一个 `com.apple.FinderSync` 扩展要求 Developer ID + 用户在系统设置里手动启用，
我们的产物现在是 ad-hoc 签名（`Scripts/make-app.sh:138`，**P46f 现读重指**：这一轮往同一份 plist 里插了 `CFBundleURLTypes`，那一行往下走了 14 行），且**分析时**全仓没有任何 URL scheme 与打开回调
（`Sources/MacMaster/` 里 `onOpenURL` / `NSApplicationDelegate` / `handlesExternalEvents` 三个符号零命中；**P46e 已落 `onOpenURL` 那一条**，见「执行结果」§5）。
所以本轮判定：**ADOPT 四片小改动（允许根闸、插件类 bundle 与四个新根、删除后通知访达、断链别名）**；
**ADAPT 两片**（Homebrew 只读面板、URL scheme 接收端）；**BLOCKED 一片**（FinderSync 扩展本体，等 Developer ID）；
**SKIP 六处**——其中包括它自己代码里三处会被误当成"安全设计"的缺陷，见 §6。
（**P46f 现读**：上面这份判定的落点是「执行结果」那一节——四片 ADOPT 里按原样落地的只有"允许根闸"那一半，"应用目录"那一半落地了但分档没做，另外两片改判；两片 ADAPT 里 URL scheme 接收端落地了，Homebrew 面板没有。）

## MacMaster 卸载侧现状速览（本轮现读）

- 唯一删除出口：`Packages/MMCore/Sources/MMCore/FileTrashService.swift:88` `moveToTrash(paths:)`（**P47 现读重指**，本文写这一格时是 `:39`），
  每一条路径在执行处过闸（`:96` 调 `DeletionGuard.rejection(for:)`）；永久删除同一形态（`:145`、`:150`）。
  **执行时确实会重判一次**，这一点与它的 `DeletionExecutor` 同构，不是差距。
- 闸的判据：`Packages/MMCore/Sources/MMCore/DeletionGuard.swift` 是**黑名单**——
  系统根 `:25-33`、home 下整棵子树 `:44-52`、只挡目录本身的六个用户目录 `:60-62`、废纸篓自身 `:66`；
  两遍口径（字面 + `realpath`）在 `:68-76`，归一与组件边界比较在 `:183-199`、`:204-210`。
  **没有"落在这些允许根之内才放行"的正向一条**——这是本轮唯一判定为"真差距"的结构（**P46b 已补**：`isInside` `:98-108`、执行处那条 `allowedRootRejection` `:115-126`）。
- 残留引擎目录清单：`Packages/MMUninstaller/Sources/MMUninstaller/ResidualScanner.swift`
  用户域 12 条 `:219-236`，系统域 4 条 `:240-245`，红线（`/Library/Extensions`、`/usr/local/*`、
  `/private/var/db/receipts`）写在 `:184-187`；Library 根下探要绕开 Apple 目录的名单在 `:262-273`。
- 应用列举：`AppScanner.swift:27-29` 只认 `/Applications` 与 `~/Applications` 两个目录（**这一句是分析时快照，
  P46c 已改判**：现为固定三条 + 每块非启动卷一条，见 §3「落地」），`AppScanner.swift:60` 的筛子是 `entry.hasSuffix(".app")`——**其它后缀的 bundle 一律看不见**。
  监听范围与列举同源（`AppFolderWatcher.swift:116-121` 直接取 `defaultSearchDirectories`），
  注释 `:111-115` 就把"两边不等会漏报/误报"写在了脸上，所以补根只需要改一处。
- 安装来源：`AppProvenance.swift:100-160`，四档结论（`:42-48` 的 `Source`）全部来自读文件：
  Caskroom 账本 `:164-200`、staged 链接解析后的 `(st_dev, st_ino)` 同一 `:127-138`、
  MAS 收据 `:140-144`、`/var/db/receipts` 里的包标识 `:156-158`；两个 token 抢同一份 bundle 时
  **降级成 `.unknown` 并把候选留下**（`:133-137`、`:151-154`）。
- 废纸篓监听：`TrashWatcher.swift:74`（kqueue）、`:156`（`O_RDONLY` 拿 fd）、`:179`（事件源）、
  `:252`（只报"新出现的那批"）。与它的 `TrashMonitor` 同构，**不是差距**。
- 风险三档：`Packages/MMCore/Sources/MMCore/Risk.swift:9-42`，默认勾选与"是否给删除入口"都由这一档决定
  （`:38-41`），扫描器与 UI 引用同一个定义（文件头 `:3-5` 就是这个理由）。
- 删除历史上界是**条数**：`FileTrashService.swift:16` `historyLimit = 20`，`:229-230` 超限裁尾（**P47 现读重指**，此前本文写 `:15`、`:165-166`；那两个数是 **P46f 现读重指**从 153-154 换上来的——正向闸那四行插在执行处上面）。
  落盘与"读不出来就改名留档不静默覆盖"在 `TrashHistoryStore.swift:27-36`、`:52-56`。

## 逐维度判定

### 1. 删除闸的形态：黑名单 vs 允许根 + 黑名单

| | |
|---|---|
| Uninstally | `Services/Security/PathValidator.swift:24-33` 先把可删根列成一张正白名单（应用目录 + 用户 Library 各类根 + 临时目录，系统域仅当开关打开）；`:66-97` 五步依次是"存在 → 解析符号链接并归一（`:75`）→ 不是保护区（`:79`，**精确集合匹配**，保护区在 `:42-60`，含挂载卷枚举 `:54-58`）→ 离根不够远（`:84`，`pathComponents.count <= 2`）→ 必须**严格落在某个允许根之内且不是根本身**（`:90-95`，组件级比较在 `:102-107`）"。校验通过的**规范路径**才是执行用的路径（`PlannedDeletion.canonicalURL`，`DeletionPlan.swift:9-10`） |
| MacMaster | 只有负向一条链（`DeletionGuard.swift:68-76`+`:128-155`），正向没有（**这一格是分析时快照：P46b 已按下面的判定补上正向闸**）。好处是我们的黑名单比它厚（凭证子树、Docker/OrbStack 虚拟磁盘、`~/.Trash` 自身）；坏处是**任何上游扫描器的误判只要能绕过黑名单就能走到执行处**，而"这个路径本来就不属于卸载器该碰的位置"这一类错误，黑名单永远补不全 |
| 判定 | **ADOPT 形状，不 ADOPT 内容**——照搬它的允许根会直接废掉「用户文件夹清理」那一页（`~/Documents/report.pdf` 在它的世界里是不可删的，而我们这是正经功能，`DeletionGuard.swift:54-62` 的注释写的正是这个取舍）。所以做成**调用方自带的可选正向闸**：`FileTrashService` 增一个 `allowedRoots: [String]?` 参数，只有卸载页与孤儿清理传（残留清单的根本来就来自 `ResidualCatalog`，等于把清单升格成闸），清理页与磁盘页不传即维持现状 |
| 落地 | **（P46b 已照此落地，实测见「执行结果」§1）**① `DeletionGuard` 加纯函数 `isInside(_ path: String, roots: [String]) -> Bool`，复用现成的 `canonicalize`（`:183-199`）与组件边界比较（`:204-210`），**不要**用 `URL.standardizedFileURL`（`:176-182` 已实测它会跟着符号链接重写路径、同一类输入给两种结果）；② `FileTrashService.moveToTrash/permanentlyDelete`（`:39`、`:89`）各接一个默认 `nil` 的参数；③ 卸载页调用处把 `ResidualCatalog.libraryRoots(...)`（`ResidualScanner.swift:276-283`）+ 应用目录交进去 |
| 代价 | S（纯函数 + 单测）→ M（三个调用点接线） |

### 2. 它把"可卸载的东西"定义为六种 bundle

| | |
|---|---|
| Uninstally | `Utilities/LibraryPaths.swift:11-13` 一张后缀集合 `app / component / vst / vst3 / aaxplugin / clap`，被三处复用：`isSupportedBundle`（`:16-18`）、扩展菜单筛选（`UninstallyFinder/FinderSync.swift:65`）、废纸篓监听只报这些（`TrashMonitor.swift:90-96`）。插件目录单列一张表（`LibraryPaths.swift:50-63`：`/Library/Audio/Plug-Ins/{Components,VST,VST3,CLAP}` + `/Library/Application Support/Avid/Audio/Plug-Ins` + 用户域同名四个），并且**只列真实存在的**（`:62` 过 `fileExists`） |
| MacMaster | `AppScanner.swift:60` 只认 `.app`；`ResidualCatalog` 用户域 12 条、系统域 4 条里没有任何音频插件目录（`ResidualScanner.swift:219-245`）；`standardLibrarySubdirectoryNames` 里倒是有 `Audio`、`Components`（`:263-264`），但那是"Library 根下探要跳过它们"的名单，不是扫描根。**P46 轮未采纳这一条**（见「执行结果」§2 未落地） |
| 判定 | **ADOPT**（音频插件是"删不干净"的重灾区，且这条产品能力在我们设计稿的卸载页里没有对标物）；插件 bundle 与 `.app` 分开成**两类条目**，不要混进同一张列表——`~/Library/Audio/Plug-Ins/Components` 里的 `.component` 是内核扩展家族，风险档不该和缓存同级 |
| 落地 | ① `AppScanner` 的筛子换成"后缀 ∈ 集合"，集合公开可注入（单测传夹具目录）；② `ResidualCatalog` 增 `pluginEntries`（用户域 + 系统域各四个，逐条 `fileExists` 才生效），类别走现有 `.applicationSupport` 之外新增一档还是复用，按 `Risk.swift:3-5` 的"语义固定不可按页面重定义"来定；③ `/Library/Extensions` 仍在红线里（`ResidualScanner.swift:184-187`）——`.component` 只在 `Audio/Plug-Ins/Components` 这一条路径下收，不做全域 |
| 代价 | M（扫描根 + 风险档 + 详情页 + 单测夹具四件） |

### 3. 应用目录：`/Applications/Utilities` 与外接卷上的 `/Applications`

| | |
|---|---|
| Uninstally | `LibraryPaths.swift:21-45`：`/Applications`、`~/Applications`、`/Applications/Utilities` 三条写死，再枚举 `/Volumes`，用 `volumeIsRootFileSystem` 跳过启动卷（`:36-37`）后补 `<卷>/Applications`（`:38-41`，且必须存在） |
| MacMaster | 两条（`AppScanner.swift:27-29`，**分析时快照**：P46c 已按本行判定扩为固定三条 + 每块非启动卷一条）。`/Applications/Utilities` 在本机确实存在（本轮实测）；`/Volumes` 本机 2 项。磁盘页那一侧已经有跨卷候选根的纯函数与夹具（`Packages/MMCore/Sources/MMCore/VolumeRoots.swift:152` `candidates(from:)`，夹具卷在 `:212`），P46c 之前卸载页的应用列举**没有接它**；接上之后跨卷那一步的入口是 `nonBootVolumePaths(from:)`（`:167-169`） |
| 判定 | **ADOPT**，并且**必须同源**：监听范围 = 列举范围是 `AppFolderWatcher.swift:111-115` 已经写进注释的不变量，所以只改 `defaultSearchDirectories` 一处，装卸监听自动跟着宽 |
| 落地 | `defaultSearchDirectories(home:)` 增两个纯函数：`utilities` 常量拼接 + `/Volumes` 枚举（沿用 `VolumeRoots` 的 browsable 判定口径，别在卸载包里再实现一遍 `volumeIsRootFileSystem`）；外接卷上的应用**默认档**要不要显示，按 `Risk.swift:41` `allowsDeletion` 给 caution 起步（拔盘即失效，误删代价不对称） |
| 代价 | S |

### 4. Homebrew：它执行 `brew`，我们读账本

| | |
|---|---|
| Uninstally | `Services/HomebrewService.swift:21-26` 找 `brew`（两个前缀），`:31-46` 三路 `async let` 并发取 `list --cask -1` / `leaves` / `list --versions`，`:49-53` 取反向依赖 `uses --installed`，`:63-71` **真的跑 `brew uninstall`**，并把"移除依赖"这个勾映射成 `--zap`；`:101-106` 给子进程一个最小环境（含 `HOMEBREW_NO_AUTO_UPDATE=1`、`HOMEBREW_NO_ANALYTICS=1`）；失败时把 brew 的 stderr 原样当错误文案（`:70`）。另一处 `Services/InstallationSourceDetector.swift:56-66` 是**同步** `waitUntilExit()` 再读管道、且没有 `HOMEBREW_NO_AUTO_UPDATE`，为的是在来源识别里跑 `list --cask --full-name` |
| MacMaster | 不执行任何第三方二进制（`AppProvenance.swift:6-10` 文件头把这个设计选择写明了）。**本轮实测确认只读路线够用**：本机 `Caskroom` 6 个 token、`Cellar` 120 份 formula 收据，其中 68 份写了 `runtime_dependencies`，元素形状是 `{full_name, version, revision, bottle_rebuild, pkg_version, declared_directly}`；把这批边反转就是 `brew uses --installed` 的等价读数（例：`libunistring` 被 23 个已装 formula 引用）。反向边、可回收体积（`Cellar/<name>/<version>` 实测大小）、`installed_on_request`（用户主动装的 vs 被拖进来的）全都能不落一条命令拿到 |
| 判定 | **ADAPT**（拿它的**面板形状**，不拿它的执行方式）：卸载页现在只在"某个应用是哪来的"这一格用到 brew；它证明了"brew 包列表"本身值得一个入口。我们已有的只读证据够支撑一个**不写盘**的包浏览页，删除入口一律仍走废纸篓（`FileTrashService`），不接 `brew uninstall` |
| 落地 | ① `AppProvenance` 的收据解析（`:164-200`）扩到 Cellar 侧，产出 `formulaName / version / installedOnRequest / runtimeDependencies`；② 反转一次得 `dependents`，UI 上"删了它会连带坏 N 个"就靠它；③ 明确一条**降级文案**：账本可能过期（`AppProvenance.swift:8-10` 已经为 cask 侧写了这句），所以这一页的所有数字都要带"来源文件路径"（`CaskEvidence.receiptPath`，`:17-18` 就是为此存在的） |
| 代价 | M（解析扩展 + 反转 + 一页 UI）；**不做**执行那一档，所以没有权限/签名成本 |

### 5. Finder 右键卸载：一条招牌，两块前置

| | |
|---|---|
| Uninstally | 扩展侧 `UninstallyFinder/FinderSync.swift`：`:23` 把观察目录设成 `/`（于是任何位置右键都出菜单）、`:29` 只接 `contextualMenuForItems`、`:34-36` 单/复数两种标题、`:53-56` 把选中的 bundle 拼成 `uninstally://uninstall?path=…&path=…` 后 `NSWorkspace.shared.open(url)`。扩展自己**不删任何东西**——`Config/UninstallyFinder.entitlements:7-9` 只有沙盒 + `user-selected.read-only`；主 app 反而是**非沙盒**的（`Config/Uninstally.entitlements:8-9` 明写 `app-sandbox=false`）。主 app 侧接收三条路：Info.plist 注册 scheme（`Config/Uninstally-Info.plist:51-59`）、SwiftUI `.onOpenURL`（`UninstallyApp.swift:25`）、`Uninstally/AppDelegate.swift:50-59`），三条都汇到 `SelectionReceiver.appBundleURLs`（`SelectionReceiver.swift:9-22`）再进协调器（`AppCoordinator.swift:80-83`） |
| MacMaster | **分析时三样都没有**：没有 appex target、plist 里没有 URL 类型（生成的 Info.plist 那一段当时在 `Scripts/make-app.sh:78-98`）、`Sources/MacMaster/` 里 `onOpenURL` / `NSApplicationDelegate` 零命中。**P46f 现读**：后两样里的两样已经落地——`Scripts/make-app.sh:101-111` 注册 `CFBundleURLTypes`（scheme 那一个字面量的另一处是 `Packages/MMUninstaller/Sources/MMUninstaller/OpenURL.swift:17`），接收入口是 `Sources/MacMaster/MacMasterApp.swift:50-52` 的 `.onOpenURL`；appex target 仍旧没有（那是 BLOCKED 的另一半） |
| 判定 | 扩展本体 **BLOCKED**，接收端 **ADOPT 且可以现在就做**。理由分开看：① `com.apple.FinderSync` 扩展必须由真实 Team ID 签名、随容器分发、且**首次要用户在 系统设置 → 通用 → 登录项与扩展 → 访达扩展 里手动勾选**，而我们的产物现在整包 ad-hoc 签名（`Scripts/make-app.sh:124` `--force --deep --sign - --timestamp=none`）——这道不是代码能绕的，与决策单里"签名身份"是同一笔等人项（见 [release-decisions.md](release-decisions.md) 第 2 项）；② **URL scheme 接收端不需要任何签名身份**，且它是 appex 的必要条件，先落地它还能顺手拿到"从访达拖一个 `.app` 到窗口 / 右键 → 打开方式"这条**今天就能用、今天就能拍图**的入口 |
| 落地 | 接收端一片：① `make-app.sh` 的 plist 段加 `CFBundleURLTypes`（scheme 名待定，建议 `macmaster`）；② `MacMasterApp.swift` 加 `.onOpenURL`，解析函数做成**纯函数 + 单测**（照 `SelectionReceiver.swift:9-22` 的形状：文件 URL 与非文件 URL 两条分支，`queryItems` 里同名的 `path` 全收）；③ **安全底线一条**：入站路径只是"要扫描哪个 bundle"的请求，**绝不允许**把入站路径直接喂给删除——今天所有删除仍必须由用户在页面上逐项确认后走 `FileTrashService`。这一片做完，appex 那一半就只剩一个 `menu(for:)` + 一条 `open(url)` |
| 代价 | 接收端 S；扩展本体 M + 等 Developer ID + 需要一句"如何启用访达扩展"的对外说明（这条会撞进落地页文案审） |

### 6. 它代码里那几处不能照抄的东西

| 位置 | 事实 | 为什么不能抄 |
|---|---|---|
| `Models/RemovableItem.swift:40-45` | `isShared` 是一个 `switch` 完 `default: return false`、且两个可能分支也写死 `false` 的常量 | 它是三档安全分的输入之一（`SafetyScore.swift:42`、`:62`、`:128-135`），恒 `false` 意味着"共享资源"这一条**永远不会亮**。我们的对应物是 `ResidualOwnershipReview`（`ResidualScanner.swift:503` 起），默认勾选由 `Risk.swift:38-41` 决定，是活的 |
| `Services/DeletionExecutor.swift:75` | 执行时二次校验用的硬编码 `includeSystem: true`，而计划是照用户开关（`SecurityPreferences.swift:12-14`，默认也是 `true`）建的 | "再校验一次"这个动作是对的，把允许根在复校时**放宽**是错的：开关关掉时建的计划，到执行处却按打开的口径放行。我们的两遍口径在 `DeletionGuard.swift:68-76` 是同一份判据跑两遍，不存在这个问题 |
| `Services/Security/DeletionValidator.swift:60-72` | 归属判定 = 把标识符/前缀/应用名（>3 字符即可，`:68`）拿去 `contains` **整条路径** | 路径里出现一次名字就算"属于这个应用"，`/Library/Application Support/Google/Chrome` 会被任何名字含 "Chrome" 的目标收走。这正是 P33b 做归属复核要止损的那一类跨应用收集，**我们已有更严的一条，不退回去** |
| `Services/HomebrewService.swift:63-71` | 勾"移除依赖"实际下的是 `--zap` | `--zap` 是"按 cask 作者声明清理该 cask 的残留"，与"删依赖"不是同一件事；两个语义挤在一个勾上，用户按下的不是他读到的 |
| `Services/LeftoverScanner.swift:63-65`、`:113-117` | 孤儿判定只看**直接子项**一层，Apple 之外的保留名单只有四个前缀 | 一层枚举会漏掉厂商目录套应用目录的形态（我们有 `extraDescent` 与敏感度分档，`ResidualScanner.swift:202-203`、`:254-256`）；靠 4 条前缀挡系统命名空间，挡不住 `com.microsoft.*` 这类"还在机器上但没被这次扫描认领"的第三方 |
| `Services/InstallationSourceDetector.swift:13-22`、`:80-85` | 来源识别用 `appURL.path.hasPrefix("/opt/homebrew/Caskroom/\(cask)")`，包安装判定用"文件名里含小写 bundle id" | 前者方向是反的（Caskroom 里的 staged 链接**指向** `/Applications`，被卸载的那份 bundle 路径通常不以 Caskroom 开头），后者把 `.plist`/`.bom` 成对存在的账本当字符串搜索用。我们的 `(st_dev, st_ino)` 同一（`AppProvenance.swift:127-138`）与包标识精确集合成员判断（`:156-158`）是这两条的正解 |

一句都没有跳过的两条**是它的强项、我们照做**：`DeletionExecutor.swift:86-112` 每项删完立刻 `fileExists` 复验，
"仍在原地"当成失败而不是成功（`:101`、`:109`）；`DeletionLogger.swift:16-22` 把每一项的**跳过原因**单独存数组
（`:40-46` 落盘、`:59-77` 可导出文本），失败与跳过不合并计数。

## 落地顺序（本轮"执行"只跑到这里）

1. **允许根正向闸**（§1，纯函数 + 单测 + 卸载页接线）。验收：`isInside` 单测含"根本身不放行、`/ApplicationsOther` 不放行、符号链接解析后判定"三档；`./Scripts/run-all-tests.sh` 全绿。（**P46b 已落地**，三档各有对应单测，见「执行结果」§1。）
2. **`.app` 之外的五种 bundle + 四个插件根 + `/Applications/Utilities` + 外接卷根**（§2、§3，同一片代码面）。验收：夹具目录造一个 `.component` 与一个 `/Volumes/<夹具>/Applications/Foo.app`，实机截图看它出现在列表里、风险档是 caution、默认不勾选。（**P46c 只落了后半，且后半也只做了一半**：两个新目录进了清单、`.component` 那一条与"caution 档"都没落地，外接卷那一条只有单测证据没有照片。逐条见「执行结果」§2、§3。）
3. **删除后通知访达**：`DeletionExecutor.swift:156-158` 那条 `NSWorkspace.shared.noteFileSystemChanged(dir)` 值得抄——我们删完靠 `AppFolderWatcher` 事件回环，但**开着访达窗口的那一侧**并不会因此刷新。代价一行，验收方式是实机：开着 `/Applications` 窗口删一个夹具 app，看它是否当场消失。（**P46d 改判：不采纳**——这条验收当时写得太顺，它没有先解决"我们不知道不通知会不会真的不刷新"；量法与不采纳的理由见「执行结果」§3-落地顺序第 3 条。）
4. **断链别名**（`LeftoverScanner.swift:120-136`）：应用目录里的悬空 `.alias`/符号链接是一类"看得见但打不开"的真实垃圾。做成纯判定 + 夹具单测，先只读展示（`Risk.readOnly`），不给删除入口。（**P46d 改判：设计稿先行**，不在本轮——理由与要定的那一件事见「执行结果」§4-落地顺序第 4 条。）
5. **URL scheme 接收端**（§5 的②，独立一片）。验收：`open -a` 一条命令送进一个 `.app` 路径，页面切到该项的残留清单；**并附一条否证**：同一个 URL 里塞 `/System/Library`，断言它进不了删除计划的入参。（**P46e 已落地，否证两半都有**，另外为这一片改了一处壳层场景，见「执行结果」§5。）
6. 之后进路线图、不在本轮：Homebrew 只读面板（§4，M）、FinderSync 扩展（§5，BLOCKED + 等 Developer ID）、历史时长保留（它的 `HistoryRetention.swift:4-40` 四档 + `prune`，对上我们 `FileTrashService.swift:16` 的条数上界，P47 重指，此前 `:15`）。

## 这一片改了哪些文档面

- `docs/analysis/reference-repos.md` 第 2 节新增第 53 行那一格（Uninstally / 钉 `c01646dc…` / `docs/github-references/uninstally` / MIT），
  §2.1 记录本机取它时踩到的网络问题与 blob 过滤取法；`docs/analysis/release-decisions.md` 的 MIT 计数从三份改四份、
  两处上游行段随文件行长重指；`README.md` 已知坑那一条从"七个仓库"改八个，并把写死的引用条数换成"由脚本每轮重算"。
- 本文是**分析文档**，不是实现记录。§1–§6 的每一处落地都在实现那一轮回来时在这里补"已落地：提交号 + 取证目录"。
- **P46f（落地轮）重指的那一批文档面**：这一轮往 `MMUninstaller.swift`、`UninstallerModel.swift`、`AppScanner.swift`、
  `FileTrashService.swift`、`DeletionGuard.swift`、`VolumeRoots.swift`、`MacMasterApp.swift`、`Scripts/make-app.sh` 里都插了行，
  全仓 `文件:行号` 引用跟着漂，所以在同一轮里逐份现读重指，动过的入库 `.md` **21 份**（README + 20 份 `docs/analysis`，
  含本文；其中 `reference-repos.md`、`release-decisions.md` 与本文是登记面，其余是重指面）、取证/夹具脚本 **8 个**
  （`fidelity-uninstaller.md` 一处面就 26 格），并把**五处**"HEAD 上本来就错"的旧锚就地改对——
  **机械位移只能保证不越界，不能保证指对**，这五条都是靠把那一行打开重读才看出来的。

## 执行结果（P46b–P46f，2026-10-16 落地轮）

### 0. 这一轮的账

三片代码（§1 正向闸、§3 应用目录、§5② 接收端）、两片改判（§2 插件 bundle 不动、落地顺序第 3 条不采纳）、
一片半（§3 落地顺序第 2 条只走了后半）。

- `./Scripts/run-all-tests.sh` 九包 **827 条 / 0 失败 / 1 跳过**（MMCore 107、MMUI 17、MMFileScanner 117、MMCleaner 25、
  MMUninstaller 217、MMDisk 85、MMMonitor 92、MMGuardian 96、MMOptimizer 71）。净增 28 条是数出来的不是推的：
  测试**声明**条数 HEAD 799 → 工作树 827，且 `git diff -U0 -- Packages/*/Tests` 里以 `-` 开头的 `func test` 是 0 行。
- `./Scripts/p16-citation-audit.sh` 末跑 **rc 0**：条次 1427 / 唯一「路径+行段」1071 / 命本仓库 933 / 命参考仓库 137 /
  行号越界 0 / **整段空白 0** / 同一条路径命中两个文件 0 / 两头都不到 0 → **硬失败 0**；符号面死符号 0、位置存疑 121（只提示不当门）。
  **第一跑是红的（rc 1、硬失败 2）**：两条都是本轮插行顶下去、又恰好落到空行上的旧锚（卸载页那条副标题引用、
  发版台账里那条 `.fullDiskAccess` 调用点）。修的时候顺手把同句里**没落空但指偏**的三处按现读改对：
  裸写的第二处调用点、`fixedSize` 那一行（HEAD 上就指着 `if let caveat`，差五行）、以及 `AppScanner` 那笔锚点债
  （字面量清单 P46c 之后在 `Packages/MMUninstaller/Sources/MMUninstaller/AppScanner.swift:45-46`，此前本文记的那一格是它搬家前的位置）。
  **这一条就是上面那句「机械位移修不了引用起点」的实物**：门禁只兜得住"落到空行/越界"那两种，指偏的必须打开那一行重读。
  三份报告都归档在 `docs/verification/p46-url/audit-first-red.log`、`audit-final.log`、`audit-postcommit.log`——
  红的这一跑也留着，只留绿的那份等于把这一轮最难看的一步藏起来。
- 候选产物 `/tmp/mm-app-p46/MacMaster.app`，`# digest` 两侧同 `0806189+440da29a`。
- **提交号回填（同轮末尾，提交之后现读）**：本批落地在 `4b55495`。提交让 `mm_source_digest` 读成
  `4b55495+e3b0c442`——后半截落到空流前缀是配方的既定行为（与 P25/P28/P30/P35b 那几份 `+e3b0c442` 同一支），
  **不是照片失效**：`git diff 0806189 4b55495 --binary -- Sources Packages Resources Package.swift ':(exclude)Packages/*/Tests/**'`
  现算仍是 `440da29a`，与那八张照片日志里 `# digest` 的后半截逐字相同，说的就是同一批编译输入。
  下一轮取证前须先 `./Scripts/make-app.sh` 重建，否则同源门会当场拒拍。

### 1. §1 正向闸 —— 已落地（P46b）

判据两段在 `Packages/MMCore/Sources/MMCore/DeletionGuard.swift:98-108`（纯字面 `isInside`）与 `:115-126`
（执行处那一遍：字面与 `realpath` 之后**各判一次**，解析失败退回按字面判而不是"读不到就当安全"）。
出口在 `Packages/MMCore/Sources/MMCore/FileTrashService.swift:88` 与 `:145`（P47 现读重指，此前本文写 `:39` 与 `:89`），各接一个默认 `nil` 的 `allowedRoots`，
被挡下按 `OUT_OF_SCOPE` 逐条进 failures（`:100`、`:154`，此前 `:51`、`:98`）——判定里那句"被挡下要当成失败逐条上报，不能静默跳过"照此实现。
接线一份口径三处共用：`Packages/MMUninstaller/Sources/MMUninstaller/UninstallerModel.swift:514-517`
（= 残留清单那几个 Library 根 + 应用目录，两边都来自页面工厂闭包，所以夹具把 home 换成 `/tmp` 时这道闸跟着换），
调用点是 `:519-521`（卸载）、`:642`（孤儿）、`:748-751`（废纸篓残留）。

验收那三档的对应单测：根本身不放行 = `testIsInsideExcludesTheRootItself`、`/ApplicationsOther` =
`testIsInsideRespectsPathComponentBoundary`、符号链接解析后判定 = `testAllowedRootRejectsSymlinkThatEscapesTheRoot`。
**撞出来一条不在验收里的**：空串根归一之后是 `/`，拿它当前缀等于放行整台机器，所以 `:105` 有一条 guard，
`testMeaninglessRootsGrantNothing` 钉住它；`testAllowedRootAgreesAcrossPrivatePrefix` 钉的是 `/tmp` 与 `/private/tmp`
这一对别名在**正向**闸里也得是同一句话（黑名单本来有这一档，新写一条最容易漏的就是它）。
数：MMCore 11 条 + `Packages/MMUninstaller/Tests/MMUninstallerTests/UninstallerDeletionRootsTests.swift` 4 条。

### 2. §2 六种 bundle（音频插件）—— 本轮不动

现读：`Packages/MMUninstaller/Sources/MMUninstaller/AppScanner.swift:60` 仍旧是 `entry.hasSuffix(".app")`，
`ResidualCatalog` 那两张表（`ResidualScanner.swift` 起）一条插件根都没加。
不顺手做的理由不是代价：**判据一行就够，缺的是"`.component` 该算哪一档"**。风险档的语义在
`Packages/MMCore/Sources/MMCore/Risk.swift:9-42` 是固定的一套，音频插件既不属于 `.applicationSupport` 那一类，
也不该和缓存同级；而页面上没有它的对标物（哪一屏、哪一类清单、详情页给不给"来源"那一格）。所以这一片进设计稿队列，
稿子出来再谈代码。
一条别忘的：它那个后缀集合是**三处复用**（`Utilities/LibraryPaths.swift:11-13` 起，扫描 / 扩展菜单 / 废纸篓监听），
我们若只做扫描侧、不做监听侧，就会造出"列表里看得见、装卸事件不报"的第四种不一致——监听与列举同源那条不变量在
`Packages/MMUninstaller/Sources/MMUninstaller/AppFolderWatcher.swift:111-115` 已经写进注释了。

### 3. §3 应用目录 —— 范围落地了，分档没有（P46c）

`AppScanner.swift:32-36`（默认档）+ `:43-48`（纯的那一半，`:45` 是三条字面量），外接卷那一条不新写枚举、
走 `Packages/MMCore/Sources/MMCore/VolumeRoots.swift:167-169`。判定里那句"只改一处，装卸监听自动跟着宽"兑现了：
`AppFolderWatcher.swift:116-121` 一行没动。
为什么不看 `browsable` 而要用 `candidates(from:)`（`:152`）去重：本轮实测 `mountedVolumeURLs(options: [])` 14 条，
`/Volumes/Recovery` 与 `/` 报**同一对容量数**，不去重就会给同一个 `/Applications` 开两个 kqueue——
装卸事件成双出现，那是监听侧的假话。这条由 `testNonBootPathsDropTheBootVolumeAndItsAliasMounts` 钉住。

两件没做的，都写清楚：①判定里"外接卷条目按 caution 起步"**没落地**——"应用本体"这一层现在压根没有风险档
（档位在残留项上），要做就得先引入那个概念，不是加一行 `Risk`；②验收那句"实机截图看它出现在列表里"**没跑成**，
本机没有第二块可挂载的非启动卷，外接卷进清单目前只有单测证据（夹具档 `VolumeFixtureTier.two`）。

### 4. 落地顺序第 3 条 `noteFileSystemChanged` —— 改判：不采纳

参考侧现读是 `Uninstally/Services/DeletionExecutor.swift:155-158`：删完对"每条被移走项的父目录"去重，
在 `MainActor` 上各调一次 `NSWorkspace.shared.noteFileSystemChanged(dir)`。一行确实便宜，
但**我们不知道不通知会不会真的不刷新**——那句注释讲的是它的假设，不是实测；
我们这侧已证的只有自己那一圈（`AppFolderWatcher` 事件回环 + 回声集合消化掉自己那次动作 → 卸载页清单会掉那条），
访达那一侧一张照片都没有。一条没量过收益的改动，写完只会多一句"应该有用"。

量法（谁要做就照这个跑，它不需要新代码）：
① 夹具用 `Scripts/p46-url-fixture.sh` 那棵假 home，绝不拿真 `/Applications` 做实验；
② `open -R <夹具里的一个 app>` 起一扇**新**访达窗口（不复用用户已开的那几扇），再用 `Scripts/window-ids.swift --pid` 按 Finder pid 数出 windowid；
③ A/B 两档同一份产物、同一条删除：A=现状，B=多那一句通知（挂一个 `MM_*` 开关最省）；
④ 判据沿用下面 §5 立的那条——**可辨差异像素数**，不是 md5。A 档照片里条目还在原地 = 收益是真的；
A 与 B 都是 0 = 收益不存在，那"不采纳"这句话就从判断变成有证据的结论。
⑤ 副作用两条先想清：这一跑必然真删一个夹具 app（`/tmp` 下，可接受），而且完全可能访达自己就刷新——那这一片永远不该做。

### 5. §5② URL scheme 接收端 —— 已落地，否证两半都有（P46e）

- 解析层 `Packages/MMUninstaller/Sources/MMUninstaller/OpenURL.swift:33-43`（`scheme` 与 `host` 都收死；同名 `path=` 全收、保序、去重）
  + `:52-61`（`path=/…` 与 `path=file:///…` 两种形态归成一条路径，**只收绝对路径**；参考侧
  `Services/SelectionReceiver.swift:9-22` 这两步都没有）。scheme 那个字面量两处同源：`OpenURL.swift:17` 与
  `Scripts/make-app.sh:101-111`。
- 投递层 `Sources/MacMaster/MacMasterApp.swift:50-52` → `:118-127`，**先入队再跳转**（顺序反了，卸载页 `.task`
  消费时队里还是空的，这次点名只能等下一条 URL）。
- 队列为什么要进程级：`OpenURL.swift:73-93`。URL 到得比视图建起来早（冷启动、还停在别的页），
  只订阅视图的 `onChange` 会漏掉那一种，而漏掉的表象是"窗口亮了一切没发生"。取走即清（`:88-92`），
  留着的话用户手动选了别的应用之后还会被旧点名抢回去。
- 消费层 `Packages/MMUninstaller/Sources/MMUninstaller/MMUninstaller.swift:129-139`（清单没就绪**不消费**）
  + `UninstallerModel.swift:445-455`（精确匹配优先、大小写兜底、一个都没点中则**保留原选中项**）。
- 本轮唯一一处"不改壳层功能就不成立"的改动：`MacMasterApp.swift:34` 把场景从 `WindowGroup` 换成单例
  `Window(id: "main")`。`WindowGroup` 把"外部送进来一个 URL"当成"再开一个窗口"：pid 不变、
  主窗口从 1 扇变 2 扇，而两扇各有自己的 `@StateObject`、点名队列却是进程级的，谁先 `onChange` 谁吃掉——
  用户会看见两扇窗口对同一条 URL 给出相反的答案。每一档都数一遍窗口数，就是这个改动的正面证据。
- 否证两半：**代码半** `Packages/MMUninstaller/Tests/MMUninstallerTests/UninstallerOpenURLTests.swift:138`
  （`testSystemPathFromAUrlCannotBecomeADeletionInput`，入站路径变不成删除入参）；
  **画面半** `docs/verification/p46-url/06-url-system-path-refused.png`（送 `/System/Library/CoreServices/Finder.app`）
  与 01 基线**可辨差异 0 个像素**（最大幅度 1，就是那条半透明横幅的抖动），stderr 留痕
  「入站点名的 bundle 不在应用清单里」逐字在 `.log` 里。07 那档（一个 `path=` 都没有）同理，是另一条留痕。
- 八档取证重跑过一遍以证可重跑；`docs/verification/p46-url/00-run.log` 是这一族的核对报告本体：窗口数 8/8 正好一扇、
  留痕 8/8 对得上、像素四对"该不同"最小 66 229（最大 94 076）、两对"该相同"全是 0；
  05 那档与 02 零可辨差异 = URL 盖过了 `MM_UNINSTALL_SELECT` 钩子；08 送前/送后各一扇 = 投进了热实例。
- **教训一条**（写进脚本头，也记在这里）：这一族第一版拿 md5 当"被拒的 URL 没动画面"的判据，两头都错——
  会假红（横幅材质 ±1/255，功能全对的一跑把 06 判红），也会假绿（"md5 不同"只保证至少一个像素不一样，
  差的全是抖动时那四条"该不同"照样过）。换成"单通道差 >8/255 的像素个数"两类分得极开，判据取 0 / >0，门槛 8 留一个数量级余量。
- 没做到的：访达右键 →「打开方式」那一段真实时序没法在没有合成点击的前提下测；08 那档 `open -g -u` 等价于
  LaunchServices 那一段，不等价于访达那一段。

### 6. 一处机制盲区（本轮才看清）

`Scripts/` 不在产物源码指纹的路径集合里（`Scripts/mm-provenance.sh:47` 的 `MM_SOURCE_PATHS` 只有
Sources / Packages / Resources / Package.swift），所以"往 Info.plist 里注册 URL scheme"这类改动**不改变指纹**：
`# digest: tree=X app=X` 那句话盖不到打包脚本，一份产物完全可能带着一个树里没有的 plist 键。
本轮的补救写在取证脚本里——它不抄 scheme 字面量，而是从**产物 plist** 读回 `CFBundleURLTypes`，读不到就一张都不出（exit 4）。
要不要把 `Scripts/` 纳入指纹是另一个决定，先记在这儿。

## 执行结果（P47，2026-10-16 复验轮）

### 0. 这一轮的账

- 只落 §6 收尾那两句里的一条（删完复验），另一条现读之后判成"本来就有、但不完全等价"（见 §2）；
  外加一处待办处置（§4）与一轮锚点重指（§5）。
- 代码面 `Packages/MMCore/Sources/MMCore/FileTrashService.swift` 现读 390 行（`git diff --numstat` 对 HEAD 是 +68/−4）；
  测试面一个新文件 `Packages/MMCore/Tests/MMCoreTests/FileTrashServiceReverifyTests.swift` 167 行、7 个 `func test`、无 swift-testing、无跳过。
- 全量单测 **834 个测试 / 0 失败 / 1 跳过**；上一份归档 827 → 834，+7 全部来自那个新文件，其余八包一字不动。
  结论表与取数口径：`docs/verification/p47-reverify/run-all-tests.log`。
- 产物 `./Scripts/make-app.sh -o /tmp/mm-app-p47 -s /tmp/mm-scratch-p47` 建成（adhoc、HARDENED=0），
  现读 `# digest: tree=0a01952+5f95fc05 app=0a01952+5f95fc05`，`mm_provenance_check` 返回 0。

### 1. 「每项删完立刻复验，仍在原地当失败」—— 已落地，三处刻意不照抄

合同原话在本文 §6 末尾：`DeletionExecutor.swift:86-112` 每项删完立刻 `fileExists` 复验，
"仍在原地"当成失败而不是成功（`:101`、`:109`）。

先动结构：真会动盘那一步从函数体里提出来，做成两个可注入属性 `trashStep`（`:40`）/ `eraseStep`（`:41`），
默认实现 `moveToFinderTrash`（`:43`，`trashItem` 落在 `:45`）与 `eraseFromDisk`（`:49`，`removeItem` 落在 `:50`）。
**全仓真删盘的仍旧只有那两处**——`feature-roadmap.md` 那一格这句话今天仍然成立，只是两个名字换了房间。
提出的唯一理由是：单测不能把东西真送进用户废纸篓（本机 `~/.Trash` 读不到、落点回不来、现场清不掉），
而"调用没抛错、项还在原地"这一档在真机上根本造不出来，复验要防的正是这一档。

复验不按 `fileExists` 按，按 `(st_dev, st_ino)` 认条：执行前取证 `entryIdentity(of:)`（`:68`，调用点 `:107`、`:160`），
执行后由 `aftermath(atPath:movedFrom:)`（`:78`）判四档（`Aftermath`，`:56`），
只有 `.sameEntry` 记失败、归 `STILL_PRESENT`（`:114`、`:166`）。三处与参考的做法不同，每一条都是刻意的：

1. **不用 `fileExists`**：它把三件事读成同一件。悬空符号链接与断掉的别名在它那里读"不存在"，而盘上实实在在还占着一个目录项——
   照 `fileExists` 复验，这一档会一路绿灯成假成功，而假成功正是复验存在的唯一理由。`lstat` 一次过整条链才拦得住
   （`testDanglingSymlinkIsCaughtByTheWholeChain`）。
2. **`.unverifiable` 不判失败**（`:79` 只有 `ENOENT` 算 `.gone`）：`EACCES` 一类是"这次核不了"，不等于"还在原地"。
   把 API 已报成功的一档改成失败是另一种谎——用户会对着一个已经进了废纸篓的条目再按一次删除。
3. **`.replacedEntry` 不判失败**：跑着的应用把它刚被移走的缓存文件立刻按同名写回，老那条确实走了。
   参考那条只看"路径在不在"，这一档在它那里是假失败；报成失败等于把一次真删除说成没发生，
   而界面会因此把释放量少算、把同一个名字再摆给用户（`testReplacedEntryIsNotReportedAsAFailure`：体积按移走前那条算，新写回来的不算我们的账）。

三档读法各有一条单测把它们点名分开（`testAftermathNamesTheThreeReadingsApart`）。那一格在 root 下造不出 `unverifiable`，
用 `XCTSkip` 挡而不是放宽断言——**跳过要让人看见，假绿不行**。

验收对上了什么（7 条，按正面/否证分）：

- 否证——假成功必须变失败：`testPhantomTrashIsReportedAsFailureWithNoUndoCredential`（不进台账、不发撤回凭据）、
  `testPhantomPermanentDeleteIsNotCountedAsDeleted`（`totalSize == 0`：没删掉的字节不计进释放量）。
- 正向——真删除行为不变：`testRealRemovalPassesTheReverifyUnchanged`。
- 批量——一条假成功不拖累其它条、也不静默吞掉：`testPhantomInABatchStaysSeparate`。
- 读法——三档点名：另三条（上两段各引一次）。

### 2. 「跳过原因单独存、失败与跳过不合并计数」—— 本来就有，但落盘那半截没有

现读确认（没为这一条写新代码）：`TrashFailure` 一条一项、带 `code`（`:326`、`:331`），
错误文本优先取 POSIX 名（`:339`-`:355`：顺着 `NSUnderlyingErrorKey` 找 `NSPOSIXErrorDomain` 再 `strerror`，取不到退回 `Cocoa <code>`）；
成功与失败分两个数组返回（`:283`、`:375`、`:383`），两个计数各读自己那个数组（`:361`、`:377`）——**没有合并计数的那一格**，
这一句与参考同构。拒绝原因现在四档：`PROTECTED`（`:97`、`:151`）、`OUT_OF_SCOPE`（`:101`、`:155`）、
`STILL_PRESENT`（`:114`、`:166`）、POSIX/Cocoa 原文（`:120`、`:172`）。

**差距一条，记成差距**：参考把每一项的跳过/失败原因落盘且可导出文本（`DeletionLogger.swift:16-22`、`:40-46`、`:59-77`），
我们的 failures 只在一次操作的结果对象里，重启即不见——台账只存成功项的撤回凭据（`:238` `store?.save(trashHistory)`）。
要不要把失败也落盘是另一个决定（要设计：写多深、留多久、里面全是用户路径的隐私面），
与本文 §「落地顺序」第 6 条同一批处理，不在本轮。

### 3. 这一轮为什么没有照片

不是漏拍。新增的那一档要的是"删除调用报了成功、而原路径上还是同一个目录项"，
任何一次真的 `trashItem` / `removeItem` 都不长成这样；全仓没有一个 `MM_*` 钩子会做真删除（钩子只渲染状态），
而单测一律把动盘那一步注入成假动作。带窗实机截图在这一片只能拍到"一切正常"那一档，拍不到要防的那一档——
按"视觉/运行时验证必须实机截图"的规矩，这一轮的证据就不该是照片，而是 7 条单测 + 那张结论表；
把这句话写在这里，比补一张证明不了任何事的图诚实。同一条判断也挡掉了 §1 里那个"给复验加钩子档"的省事做法：
钩子档只能渲染，造不出假成功。

### 4. 待办处置（P47a）：`docs/verification/p41-tests/` 那一族

五个文件不删（台账四数连着五轮的算术都要减两道：`build/` 与"有意不入库那一族"，删了就断），
改判为**有意不入库**并写进 `.gitignore` 第 27 行；`git check-ignore -v` 现读命中这一条。
`comm -13` 那三行差不受影响（它比的是 `git ls-files`，这一族本来就没在里面）。
顺手清一条每轮构建都在响的编译器告警：`FileTrashServiceGuardTests.swift:131` 在非 throwing 的 `createFile` 前多一个 `try`（P46b 带进来的，行数未变）。

### 5. 锚点重指（P47c）：一次插入，动了 15 个落点

本轮的插入让 `FileTrashService.swift` 整体下移，另有两条是搬家而不是位移。旧→新（全部现读复核）：
`15→16`、`39→88`、`43→92`、`47→96`、`48→97`、`51→100`、`54→103`、`86→149`、`89→145`、`94→150`、`98→154`、
`39-77→88-133`、`165-166→229-230`，以及**反方向的** `60→45`、`105→50`。
副本面六份、共 11 行：`dev-artifact-continuation.md` 2、`disk-double-gate-review.md` 1、`feature-roadmap.md` 2、
`fidelity-optimizer.md` 1、`release-readiness.md` 5、本文 4。十一行全部行内追加，重指这件事本身零新行：
五份被指的文档现读 `wc -l` 与 `git show HEAD:` 逐份相等（333 / 50 / 1530 / 394 / 4870）。
本文不在这一列里，它自己涨了——本节（执行结果）整段是新写的：`git show HEAD:` 那一份 263 行，现读 364 行。
它那 4 处重指仍是行内、零新行；写这一句时先填过 361，改完这句才定在 364（这一格行内换行、行数不变，所以数字到此为止）。
按"落点写自己刚改过的行"这条老账的规矩，这里只报现读的两个数，不报推出来的数。

- **一条不是本轮造成的**：旧 `:86` 在改动之前就已指偏——`git show HEAD` 那一版的第 86 行是永久删除 doc 注释里的一句
  （"这里没有'到哪去'……"），作者意图是循环开头。本轮按意图重指到 `:149`，并把"此前已指偏"写在 `dev-artifact-continuation.md` 那一格。
- `release-readiness.md` 里 P12 那格是当时的现读快照，**原数不动**，只在同一行后面补今天的读数与一句"为什么漂了两次"。
- 门禁只保证路径存在 / 行号在界内 / 区间不整段空白；**机械位移能保证不越界，保证不了指对**。
  这一轮 15 个落点里有 2 个方向相反（`60→45`、`105→50`），只有开进源码看才知道那是搬家——所以上面那张表是逐条开进去对出来的，不是按偏移量算出来的。

### 6. 还没做的（沿用本文，不改判）

§2 六种 bundle 与 `.component` 风险档、§3 外接卷 `caution` 分档（两条同撞在"应用本体有没有风险档"那一个决定上，进设计稿队列）、
§4 Homebrew 只读面板（M）、§5 appex 那一半（BLOCKED + 等 Developer ID）、落地顺序第 4 条断链别名（设计稿先行）、
第 6 条历史时长保留，加上本轮新记的那一条：**失败原因落盘**。
