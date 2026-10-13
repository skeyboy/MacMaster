# P5.3 调研：`/Applications` 装卸事件监听

对应 `docs/analysis/feature-roadmap.md` 候选 #3（"补 P1.5 盲区"）。
本文只记录**查证过的事实**：参考仓库的行号逐条本地打开核对过（代理报告给的行号有 4 处偏移，
已按实际行号改写，见 §2 末尾）；kqueue 的事件语义在本机探针里量过（§3）。

## 1. 盲区到底是什么

P1.5 的 `TrashWatcher` 监听 `~/.Trash`，能抓住"用户把 `.app` 拖进废纸篓"这一条路径。
但应用离开这台机器的方式不止一种，而卸载页对其它方式完全沉默：

| 用户做的事 | 结果 | 卸载页现在的反应 |
| --- | --- | --- |
| 拖进废纸篓 | 本体在 `~/.Trash`，残留活着 | 提示卡 + 残留清单（P1.5） |
| 废纸篓里"立即删除" / 清空废纸篓 | 本体彻底没了，残留活着 | **没有**：`~/.Trash` 里再没有这个条目，也没有别的事件源 |
| 终端 `rm -rf /Applications/Foo.app` | 同上 | **没有** |
| 应用自己的卸载器（多数带卸载器的商业软件） | 同上 | **没有** |
| 装了新应用（拖进 `/Applications`、installer 落盘） | 列表停在旧快照 | **没有**：列表不会自己更新，孤儿判定也停在旧的主人集合上 |

前三行是同一个失利的判定："本体已经不在了，但 `~/Library` 里那堆文件没人管"。
这恰好是孤儿扫描（`scanOrphans`）最该被主动提供的时刻，现在却要用户自己想到去点"扫描残留"。
后两行是反向问题：**列表过期**本身也要如实说，不能让用户以为刚装的东西"没被检测到"。

监听目标因此是两个方向都记：**消失**（给出残留入口）与**新出现**（给出重新载入入口）。

## 2. 参考项目怎么做（全部本地核对）

| 实现 | 证据（`docs/github-references/`） | 我们采纳什么 |
| --- | --- | --- |
| Pearcleaner 常驻哨兵 | plist `PearcleanerSentinel/com.alienator88.PearcleanerSentinel.plist:9-12`（`RunAtLoad`+`KeepAlive`）；注册见 `Pearcleaner/Logic/Logic.swift:1367,1379`（`SMAppService.register`） | **不采纳常驻**（见 §4.1） |
| 它的事件源 | `PearcleanerSentinel/FileWatcher.swift:2,84-94`：FSEvents，`latency: 0`，flags `.useCFTypes`+`.fileEvents` | 采纳"改动即重扫目录再对账"的思路，机制换成我们已有的 kqueue |
| 它监听哪里 | `PearcleanerSentinel/main.swift:17`：只有 `~/.Trash` | **它也没监听 `/Applications`** —— 我们要补的正是这个 |
| 从废纸篓跳到 GUI | `PearcleanerSentinel/main.swift:58` 自定义 scheme `pear://openApp?path=…`；落地端 `Pearcleaner/Logic/DeepLink.swift:143-146` 先 `FileManager.fileExists` 再信这条路径 | 采纳"事件带来的路径要重新验证存在性"；我们不做 scheme（同进程不需要绕） |
| 自我删除保护 | `PearcleanerSentinel/main.swift:54-55` 比对 `bundleID`，哨兵不处理自己；`Pearcleaner/Views/FilesView/FilesView.swift:224-225,300-301` 卸载自己前先 `sendStopNotificationFW()` 再 `sendStartNotificationFW()` | 采纳同一类问题的解法，但我们的形态是"自己刚删的那条不报"（§5） |
| "在废纸篓"还是"没了" | `Pearcleaner/Views/FilesView/FilesView.swift:271` 用 `.Trash` 子串判定 | 采纳：同一个判据决定我们报哪一种提示 |
| "应用不见了"的答案 | `Pearcleaner/Logic/ReversePathsFetch.swift:36-47` 先把在装应用的 bundleId/应用名做成一张表（`cachedAppIdentifiers`），`:63` 枚举 `locations.reverse.paths` 那批系统目录，`:218` 用 `!isRelatedToInstalledApp(...)` 把"还在装的 app 的残留"排掉，`:230-232` 还有标识长度 `count >= 5` 的下限 | 这是**重扫对账**而非事件；我们的消失提示需要事件，因为要当场说"刚刚" |
| Mole | `docs/github-references/Mole/AGENTS.md:29` 明文禁止后台常驻与监控 | 它全程没有 watcher；`lib/clean/apps.sh:151` `cache_age_seconds=300`，靠 5 分钟过期的安装清单再列举 |

**这一表的证据列在 P16 之前有三处路径写错、一处标识符不存在**（`./Scripts/p16-citation-audit.sh` 逐条落到文件里验出来的）：
DeepLink 在 `Logic/` 而不是 `Views/`；FilesView 在 `Views/FilesView/` 而不是 `Views/Files/`；
`ReversePathsFetch.swift` 不在 `Logic/ZombieScanner/` 这一层；而原文引的 `currentPaths`/`currentBundleIds`
两个标识符在整个 Pearcleaner 仓库里 grep 不到（`grep -rn currentBundleIds` → 0 命中），
`count >= 5` 那条是真的但在 `:232` 而不是 `:226`。上表按复核后的位置与写法重写，
结论一列没动—— Pearcleaner 确实是"重扫对账"，只是原来的行号说不出这件事。
另外这一表原来写裸文件名 `main.swift:58`：Pearcleaner 里**有两个 `main.swift`**
（`PearcleanerSentinel/` 与 `PearcleanerHelper/`），按后缀找文件时随便落到一个上，
本轮就落到了 Helper 那一份——而那一行恰好也是非空行，**光验"行号在不在文件里"抓不出这种错**，
所以这一族的引用现在一律带目录前缀（`PearcleanerSentinel/main.swift`）。

**结论：参考仓库里没有任何一个监听 `/Applications`。** 两条路线（Pearcleaner 重扫对账、Mole 缓存重扫）
都只在"用户主动执行清理"时回答"某个应用还在不在"，都不能在应用刚消失的那一刻说话。
所以这一条没有可移植的代码，只有可移植的**手法**：只读列举 + 差异比对 + 首帧只建基线。
`TrashWatcher` 已经是这套手法的进程内版本，照它做第二个实例，成本最低、风险也最低。

> 行号勘误（代理报告 → 实测）：`ReversePathsFetch.swift` 的 `currentPaths`/`currentBundleIds`/路径比对
> 报告写作 38/49/218，实际为 36/47/215；`count >= 5` 报告写作 227，实际 226。
> 报告里的"Mole 有 30 天年龄阈值"在 `apps.sh` 里 grep 不到（`2592000`、`MIN_AGE_DAYS` 均无命中），
> 本文不予采信，不据此立项。

## 3. 本机实测：kqueue 能不能看见目录里的增删

探针 `Scripts/apps-watch-probe.swift`（可重跑：`caffeinate -i swift Scripts/apps-watch-probe.swift`，
只在 `/tmp` 下建目录，不碰用户文件）。它在 `/tmp` 建一个空目录、`open(O_RDONLY)` 拿 fd、挂
`DispatchSource.makeFileSystemObjectSource(eventMask: [.write, .delete, .rename, .revoke])`，
然后依次**建一个 `Foo.app` 目录、删掉它、再写一个普通文件**，每条记录带相对时间。实机输出：

```
[0.00s] open ok fd=3
[0.42s] event data=2
[0.42s] created Foo.app        ← 建 Foo.app
[1.05s] event data=2
[1.05s] removed Foo.app        ← 删 Foo.app
[1.68s] event data=2
[1.68s] event data=2
[1.68s] wrote loose.txt        ← 写一个不相干的普通文件
[3.15s] cancelled
```

量到的四件事，直接决定了实现形态：

1. **目录内的创建与删除都会触发 `NOTE_WRITE`（rawValue 2）**，空目录也能打开并监听（上面就是
   对着一个刚建好的空目录开的 fd）。删除是 rename，拖进废纸篓也是 rename —— 我们要的信号确实会来。
2. **事件不带信息**：只有"这个目录变了"，没有"哪个条目变了"。所以必须重扫目录再和基线对账，
   不能指望事件体。（`TrashWatcher.rescan()` 已经是这个形状。）
3. **三次改动收到四条事件**，而且带时间戳也**分不出**哪条对应哪次改动（0.42/1.05 各一条，
   1.68 一次来两条）。所以合并窗口是必需而非优化（沿用 `TrashWatcher.coalescingInterval = 400ms`），
   重扫必须幂等 —— 结论只能来自"目录清单的差异"，永远不能来自事件本身。
4. **未被打断时送达很快**（同一百分之一秒内就到）。但这条要打上问号：见下面的方法教训。

> 方法教训：这份输出是**重跑到第五次**才可信的。前面几次（含写这份文档之前跑的那一轮）
> 的"事件顺序"全是假象 —— 打印时间戳显示进程在 `open ok` 之后 8 分钟才产生下一行，
> 四个定时动作（0.4/1.0/1.6/2.4 s）在恢复的瞬间一次性倾倒，主 runloop 只在末尾转了一圈：
> 看起来像"删除产生两条事件、延迟两秒"，其实时序根本没拉开。
> 原因只能确认到"进程被整段挂起 8 分钟，然后一口气跑完"这一步
> （一条本该 5 秒结束的命令在后台计时里走了 24 分钟）；挂起是暂停、休眠还是调度造成的，
> 探针里没有证据，不做断言。加相对时间戳 + 后台运行（`caffeinate -i` 挡休眠）之后
> 才拿到上面这份。**时序即结论的实验，不打印时间戳就是自欺；被挂起过的运行不能当证据。**

另外两条由代码与既有验证确定：

- `/Applications` 是世界可读的（`AppScanner.applications(in:)` 一直列举得动，真机 44 个应用），
  不像 `~/.Trash` 需要完全磁盘访问。**所以这一路不该出现授权横幅**；
  只有 EPERM/EACCES 才说"读不到"，目录不存在要说"这台机器没有这个目录"。
- 监听范围必须**等于列举范围**：`AppScanner.defaultSearchDirectories` 只看 `/Applications`
  与 `~/Applications` 的**第一层** `.app`（`AppScanner.swift:27-54`）。
  `/Applications/Utilities/Foo.app` 从来就不在清单里，它的消失不能报 —— 报了就是凭空造一次"卸载"。

## 4. 设计决定

### 4.1 进程内、页面存活期监听，不做 LaunchAgent

学的是 `PearcleanerSentinel` 要解决的问题，不是它的部署形态。常驻代理意味着：
安装时写 LaunchAgent、崩溃后要有人重启、退出后仍在监听用户目录 —— 这三件事我们都不欠用户。
照 `TrashWatcher` 的形态做：`AppFolderWatcher` 在卸载页 `.onAppear`（P36 现读：落地在 `.onAppear`，不是 `.task`）里 `start()`、
`onDisappear` 里 `stop()`（`MMUninstaller.swift:222-227` 起监听、`:255-257` 停；`:223-224` 那条注释写的正是这条约束：监听不能排在
耗时的 `loadApps()` 之后，否则这段时间里的变化会漏掉）。

### 4.2 基线记的不只是名字，是身份

`.app` 一旦被删走，`Info.plist` 就读不到了 —— 这时候才知道"消失的是 bundleID 为 X 的应用"毫无办法。
所以基线在 `start()` 时就为每个 `.app` 条目记下 `(bundleID, displayName)`；
消失判定用**条目名对账**，身份从**基线**取。这与 `TrashArrival` 用 `entry` 而非 path 判断
"还在不在废纸篓"是同一个道理（`TrashWatcher.swift` 的 `arrivals.filter { present.contains($0.entry) }`）。

### 4.3 消失 → 走已有的「卸载后遗症」页；新出现 → 重新载入

**消失卡上没有删除按钮，也不内嵌残留清单。** 这不是省事，是两条实打实的理由：

1. 删除通路已经有一条测透的 —— 卸载后遗症页（`scanOrphans` + 逐条勾选 + 撤回）。
   再造一条能删文件的平行状态，就是再造一批要防的错（P1.5 那条通路的注释里
   就写着"绝不能走 `deletionPaths`，它会把本体一起加上"这类坑）。
2. **孤儿判定的依据正是"本机已装应用清单"**（`UninstallerModel.swift:577` 把 `apps`
   映射成 `InstalledAppIdentity` 交给 `OrphanScanner`）。而消失发生的那一刻，
   清单**还是旧的、里面仍有那个应用** —— 直接扫会把它自己的残留判成"有主人"，
   **恰好漏掉我们正要提示的那几项**。所以动作必须是**先刷新归属清单、再扫**，
   而不是"扫一下看看"。

因此卡片的唯一动作是「重新载入并扫描」：`loadApps()` → `scanOrphans()` → 切到后遗症页。
清单刷新要**只等枚举、不等体积测量**：`loadApps()` 在 `apps` 就位后就把 `isScanningApps` 置回
`false`，慢的 `enrich` 在后面（`UninstallerModel.swift:212-217`），
所以拆一个"只重举清单"的入口出来即可，不用为这一路等几十秒的体积测量。
说明行要把这个因果写在脸上，不能让用户以为刷新和扫描是两步无关的操作。

**新出现**：不自动重扫。列表是用户正在看的表格，自动刷新会把选中的应用换掉。
只给"应用目录里有 N 个新条目"的轻提示 + "重新载入"按钮，让用户决定。
新条目只列目录名：包标识读不出来（替身、缺 `Info.plist`）也照样算"多了个条目"，
因为这里报的是**清单过期**这个事实，不是"这是个可卸载应用"。

### 4.4 消失提示要让位于废纸篓提示

同一个 `.app` 拖进废纸篓会**同时**触发两个监听：`~/.Trash` 出现一条、`/Applications` 少一条。
这时候两条卡都在说同一个应用，而废纸篓那条更强（本体还能还原）。
规则：消失条目若 bundleID 命中 `TrashWatcher.arrivals`，**不报**。
"立即删除/清空废纸篓"仍会报 —— 那一刻 `arrivals` 里的它已经被 `rescan()` 过滤掉了。

### 4.5 文案：只说观察到的事

| 说 | 不说 | 为什么 |
| --- | --- | --- |
| "刚从 `/Applications` 消失：Highball" | ~~"已卸载 Highball"~~ | 我们只看见它离开了目录。谁做的、有没有留凭据，都不知道 |
| "残留还没扫描" | ~~"没有残留"~~ | 与 P1.5 的 `hasScannedTrashResiduals` 同一条纪律：没看过不等于干净 |
| "这台机器没有 `~/Applications`" | ~~"无法读取，需要授权"~~ | 不存在与读不到是两件事（`TrashWatcher` 里 `needsFullDiskAccess` 只在 EPERM/EACCES 为真，同一原则） |
| "应用列表里没有它" | ~~"安装未被检测到"~~ | 我们只监听两个目录的第一层，装在别处本来就不在范围内 |

### 4.6 钩子与夹具

`MM_APPS_WATCH_FIXTURE_DIR`（`/tmp` 或 `/private/tmp` 前缀以外一律拒绝，
照 `TrashWatcher.fixtureEnvironmentValue(key:)` 实现）+ 复用 `MM_TRASH_SCAN_HOME` 指假 home。
夹具脚本 `Scripts/apps-watch-fixture.sh` 造一个 `/Applications` 替身目录，
监听建立后**由脚本自己增删条目**：探针证明这类改动确实产生事件，所以这是"观察外部变化"，
不是合成点击，不违反"禁止用合成点击验证原生 UI"。

## 5. 顺带查出来的 P1.5 缺陷：自我回声

`uninstallAppOnly()` / `uninstallAppWithSelection()` 都走 `FileTrashService.moveToTrash`
（`UninstallerModel.swift:465-481`，两条都汇到 `move(to:)` 那一次 `moveToTrash`），本体是真的进了 `~/.Trash`。于是我们自己的卸载动作
会触发自己的监听，弹出一张写着「**刚拖进废纸篓**：X」的卡（`MMUninstaller.swift:657-668`
的 `syncTrashNotice` 不看这条是谁造成的）。

两件事都不成立：

1. **主语是假的**：用户没拖，是我们的按钮把它移走的。
2. **时机是重复的**：`withResiduals` 模式下，用户刚在确认面板里逐项勾选过残留，
   紧接着又收到一张"清理勾选的残留"。

这一条与 P5.3 是同一个机制的两面 —— 都需要"我自己刚动过的那条不报"。
所以一并解决：模型记住**本次会话里自己移走过的 bundleID**（`move()` 成功时写入），
`syncTrashNotice` 与应用目录监听都按这个集合抑制。
`.appOnly` 模式下这张卡本该有价值（用户确实只带走了本体、残留还活着），
但它该说"你刚卸载了 X，残留还在"而不是"刚拖进废纸篓" —— 属于文案分档，不是新增功能。

## 6. 取证时查出来的两处缺陷（本轮修掉）

### 6.1 回声卡把"我们动过手"寄托在"列得动目录"上

§5 那张「你刚卸载了 X，残留还在」在**没有「完全磁盘访问」的机器上永远不出现**。
原因不在文案，在数据来源：卡片读的是 `trashWatcher.arrivals`，而 arrivals 来自
`contentsOfDirectory(~/.Trash)` —— 本机实测这一步是 `NSCocoaErrorDomain 257`
（见 `trash-watch-fda.md`）。于是监听那一支只能报 `.unreadable`，`trashRegion` 把横幅排在
卡片前面，卸载确实成功了、残留确实还在，界面却只说"我读不到废纸篓"。

这是**产品缺陷**，不只是取证障碍：这张卡讲的是我们自己的按钮刚做过的事，
凭据本该来自卸载动作本身。`FileTrashService` 在移动时就回填了目的地
（`TrashRecord.trashPath`），包标识与显示名卸载前已经读好——一个字节都不必再读废纸篓。

改法（`UninstallerModel.swift:483-498` / `TrashArrival(selfMovedPath:)`）：

- 「仅卸载应用」成功时，模型记下 `selfEchoArrival`（目的地路径 + 名字 + 包标识，不读盘）。
- 视图只在**监听读不动废纸篓**时拿它兜底（`syncTrashNotice` 里的 `echoFallback`）。
  监听看得见时一切照旧以它为准——用户在访达里还原或清空废纸篓，条目从清单里消失，卡就跟着消失；
  兜底那条没有这个能力，所以绝不能让它盖在权威来源上面。
- 「忽略」清的是来源本身（`dismissSelfEchoArrival`），只清选中项的话下一次同步又把它选回来。
- 撤回（`undoLast`）把本体放回应用目录，回声随之作废。
- 卡片标题改读 `model.trashArrival ?? arrivals.last`：原来写的是 `arrivals[0].name`，
  兜底路径下 arrivals 是空的，那是一句会越界的假话。

路径必须用 `FileTrashService` 回填的那一条，不能拿 `~/.Trash/<原目录名>.app` 自己拼：
取证时废纸篓里已经躺着上一轮的 `Highball.app`，系统把这一次改名叫
`Highball 12-29-703.app`（`echo.jpg` 拍到的就是它）。拼出来的那条既不是删除历史里的目的地，
也不是撤回时要找回的位置。

顺带定下的次序：有可讲的卡片时**卡片排在横幅前面**。横幅讲的是"我们看不见废纸篓"，
卡片讲的是"我们刚亲手做过一件事"，后者才是用户此刻要的答案。

### 6.2 一个 `.fixedSize` 让整页比窗口高 397pt

现象：卸载页整窗内容上下溢出，照片看着像"窗口错位"，别的页正常。
量出来的凭据（`MM_PROBE_WINDOW=1`，见下节）：窗口 `content` 是 760pt，
而 `AppKitPlatformViewHost<…NavigationSplitRepresentable…>` 是 **1157pt**——
SwiftUI 按页面的**理想高度**给了宿主视图尺寸，窗口只是把它裁了。

成因是 P5.3 三张提示卡正文上的 `.fixedSize(horizontal: false, vertical: true)`。
这个修饰符要的是"按内容要多高就多高"，落在**直接挂在页面根 `VStack` 上、
且位于弹性区（`HStack{…}.frame(maxHeight: .infinity)`）之上**的卡片里，
就会把整页的理想高度抬到超过窗口高度，弹性区跟着被顶出去。
去掉这三处（`MMUninstaller.swift` 的 `appsDepartureCard` / `appsArrivalStrip` / `appsSkippedNote`）
后宿主回到 760pt，段落照样换行——宽度由 `frame(maxWidth: .infinity)` + `Spacer(minLength:)`
约束，本来就不靠 vertical fixedSize 撑开。

`AppDetailView` 里那两处同名修饰符**没动**：它们在滚动视图内部，HEAD 版本一直如此且量出来是齐平的。
教训不是"别用 fixedSize"，是**同一句文案，放在滚动区和放在根 VStack 上是两种几何**。

## 7. 逐屏几何守卫：`Scripts/window-probe-sweep.sh`

上面那个 bug 的麻烦在于它不像"某一页坏了"，而像"整个窗口坏了"——侧边栏也跟着位移。
所以补了一个便宜的守卫：每页起一个实例，量窗口帧与宿主帧，不相等就是溢出。

```
./Scripts/window-probe-sweep.sh light                          # 默认 1100x760
MM_WINDOW_SIZE=1000x620 ./Scripts/window-probe-sweep.sh light  # 夹取后的实际最小档
```

本轮结论（`docs/verification/window-probe/sweep.txt`）：7 页在两个尺寸下**全部齐平**。
探针本身（`Sources/MacMaster/WindowProbe.swift`）只在 `MM_PROBE_WINDOW` 存在时工作，
只读帧不改帧，产物里等于不存在——留着是因为它是这一类 bug 唯一的量化工具，
而照片看不出"差 397pt"这种数。

## 8. 下一轮

本轮已按 §6 之前的落地顺序走完：设计稿 `03e-uninstaller-watch.html`（三档：消失提示 / 新出现提示 / 读不到）
→ `AppFolderWatcher` + 单测（纯函数判据先立，照 `TrashWatchRule` 的形状）
→ UI 卡片与 §5 的抑制集合 → `Scripts/apps-watch-fixture.sh` + 实机窗口截图取证（三档，零合成点击）。

留到下轮的：

- **消失卡与回声卡的"过期"没有统一口径**。监听读得动废纸篓时靠目录清单掉出来；
  读不动时那条兜底只能等撤回或「忽略」。没有授权就没有"它还在不在"的可靠问法——
  `lstat` 一个已知路径在本机能不能成功没实测过，不拿它当结论。
- **应用目录监听只覆盖第一层 `.app`**，装在自定义目录里的应用看不见（卡片正文已写明）。
- **`~/Applications` 不存在是常态**，所以它不占横幅；只有所有目标都读不到才升级。

明确不做：常驻代理、FSEvents（kqueue 够用且已验证）、自定义 URL scheme、
`NSWorkspace` 通知（它只报前台激活与启动，报不了"某个 bundle 不见了"）、
监听 `/Applications` 的子孙目录（列举范围只到第一层，监听范围不能更宽）。
