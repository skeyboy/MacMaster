# 功能演化路线图：参考开源项目 → MacMaster

> 参考源：`docs/github-references/{Pearcleaner,Mole,stats,OverSight,disktree}`、`docs/lemon-cleaner`。
> 许可：Pearcleaner / Mole / OverSight / Lemon 均为 **GPLv3**（Pearcleaner 另带 Commons Clause，禁止商业售卖）→ **只能借鉴思路自行实现，不得复制代码**；stats 与 disktree 为 **MIT**，可引用片段（需署名）。
> 表中"已复核"列指我是否亲自打开过对应 MacMaster 文件确认现状。

## 现状盘点（先说结论）

| 模块 | 现状 | 复核 |
|---|---|---|
| `Packages/MMHelper`、`MMMenuBar`、`MMWidget` | **空目录，无 Package.swift**，是死引用 | 已复核（`find` 返回 0 文件） |
| `MMFileScanner/DuplicateScanner` | 只哈希前 10MB 且用非确定性 `Swift.Hasher`；**读取失败返回 `""`，全部不可读文件会被归为同一组"重复文件"** | 已复核 `MMFileScanner.swift:211-224` |
| `MMOptimizer.runOptimization` | **空操作**：只把状态改成 `.optimized`、detail 写"已完成"，不执行任何系统动作 | 已复核 `MMOptimizer.swift:105-110` |
| `MMOptimizer.deleteSelected` | 用 `try? FileManager.default.trashItem`，**绕过 `FileTrashService`**（无撤回、无历史、错误被 `try?` 吞掉） | 已复核 `MMOptimizer.swift:318-320` |
| `MMUninstaller.findResiduals` | 只探测 11 个固定候选路径，无 Containers / Group Containers / LaunchAgents / receipts / Spotlight | 已复核（本轮重写前的实现） |
| `MMGuardian` | 有 LaunchAgents/Daemons plist 扫描；对 `/Library` 域写 `Disabled` 键在无 root 时会静默失败；**完全没有摄像头/麦克风占用监控、没有 TCC 权限视图** | 部分复核（行号来自子代理，未逐行验证） |
| `MMMonitor` | 菜单栏 CPU/内存/网络 + 阈值通知；无每核、无磁盘 IO、无电池/温度/风扇 | 部分复核 |
| `MMCleaner/CacheScanner` | 7 个静态类别，全在 `~/Library` 下 | 部分复核 |

## P0：正确性与安全（先于任何新功能）

| # | 事项 | 落点 | 代价 |
|---|---|---|---|
| 0.1 | **重写重复文件判定**：size 分桶 → 首块哈希 → **全文件哈希确认**；不可读文件跳过而不是归入 `""` 组；哈希换稳定算法（CryptoKit `Insecure.MD5` 仅用于分桶 + 最终逐字节/全量摘要确认） | `MMFileScanner` | S |
| 0.2 | **删除统一走 `FileTrashService`**：`MMOptimizer` 两处 `try? trashItem` 改为带历史与撤回的服务；失败必须可见上报，不得 `try?` 吞掉 | `MMOptimizer` | S |
| 0.3 | **删掉假动作**：`runOptimization` 要么实现真实维护任务，要么从 UI 移除该行。宁可少功能，不可报"已完成"而什么都没做 | `MMOptimizer` | S |
| 0.4 | 清理空包目录 `MMHelper`/`MMMenuBar`/`MMWidget`（或补齐 Package.swift） | 仓库 | S |
| 0.5 | 概览页接真实数据（当前 CPU 23 / 内存 45 / 磁盘 49 与"清理 2.3 GB"全是硬编码常量） | `Sources/MacMaster/MainWindow.swift:122` | S |

## P1：卸载残留引擎（价值最高的一档）

| # | 事项 | 证据 | 代价 |
|---|---|---|---|
| 1.1 | 残留扫描升级为"多目录清单 × 归一化名称 × 敏感度三档（strict/enhanced/deep）" | Pearcleaner `AppPathsFetch.swift:323-434`、`Locations.swift:58-122` | M |
| 1.2 | 沙盒容器反查：读 `~/Library/Containers/<UUID>/.com.apple.containermanagerd.metadata.plist` 的 `MCMMetadataIdentifier` 关联 bundleID；Group Containers 用 `containerURL(forSecurityApplicationGroupIdentifier:)` | Pearcleaner `AppPathsFetch.swift:143-183` | M |
| 1.3 | 卸载时一并列出 app 关联的 LaunchAgent/Daemon plist（按 bundleID **和** `ProgramArguments` 指向 app 路径两轮匹配） | Pearcleaner `:105-120`；Mole `lib/uninstall/batch.sh:445-476` | S |
| 1.4 | 孤儿残留反向扫描（"卸载后遗症"页）：≥5 字符匹配 + skip 黑名单 + UUID 名跳过 + **全部默认不勾选** | Pearcleaner `ReversePathsFetch.swift:110-278`；Lemon `QMAppLeftScan.m` | M |
| 1.5 | 废纸篓监听 → 检测到 `.app` 被拖入即提示清理残留（`DispatchSource`/`NSFilePresenter`，不需要常驻 daemon） | Lemon `AppTrashDel.m:25-40`（launchd WatchPaths 更省资源） | S |
| 1.6 | 删除历史持久化 + 历史页按会话浏览并恢复，替代 15 秒过期 toast | Pearcleaner `UndoHistoryManager.swift`；Mole `lib/core/history.sh:24-38` | S |

**红线**：目录清单必须剔除参考项目里的越线路径（`/Library/Extensions`、`/usr/local/*`、`/private/var/db/receipts` 不进默认清单）；容器内含用户文档，**整个容器标 `cleanWithWarning`、默认只勾 `Data/Library/Caches`**；不可写的 root 属主文件显示"仅供查看"。

## P2：磁盘分析（详见 `disktree-adoption.md`）

口径与去重 → 分类着色与斜纹 → 树上标记两阶段删除 → Worth a look → 多层 treemap 与键盘导航。

## P3：监控与守护

| # | 事项 | 证据 | 代价 |
|---|---|---|---|
| 3.1 | 麦克风/摄像头占用指示：`kAudioDevicePropertyDeviceIsRunningSomewhere` + `CMIOObjectAddPropertyListenerBlock`，**只监听设备状态、不开采集会话，因此不需要 TCC 授权**；macOS 14+ 归属进程改从 unified log 提取 PID | OverSight `AVMonitor.m:774-1028`、`:223-246` | M |
| 3.2 | TCC 授权只读视图（哪些 app 持有麦克风/摄像头/屏幕录制）：`sqlite3_open_v2(..., READONLY)` 打开 `TCC.db`；打不开则降级为"需要完全磁盘访问" | Pearcleaner `TCCQueryHelper.swift:31-119` | S |
| 3.3 | 登录项完整度：`SMAppService` 状态 + 内嵌 `Contents/Library/LoginItems` + `launchctl list` 交叉运行时状态，标出"plist 在但没加载""运行中但找不到 plist"两类异常 | Pearcleaner `DaemonView.swift:354-606` | M |
| 3.4 | 菜单栏指标：每核 CPU、磁盘 IO 速率（`IOBlockStorageDriver` Statistics 差分）、内存补 compressed/swap、GPU（IOReport）、电池（`ioreg AppleSmartBattery`） | stats `Modules/CPU/readers.swift:45`、`Disk/readers.swift:243`、`RAM/readers.swift` | M |
| 3.5 | 移除对 `/Library` 域 plist 写 `Disabled` 的尝试（无权限会静默失败），改为只读展示 + 引导到系统设置 | 现状复核 | S |

## P4：清理覆盖面

| # | 事项 | 证据 | 代价 |
|---|---|---|---|
| 4.1 | 非显性系统缓存：`/private/var/folders/**/com.apple.metal{fe,gpuarchiver}`、QuickLook、iconservices、GeoServices 瓦片、photoanalysisd | Mole `lib/clean/system.sh:518-733`、`user.sh:890-1002` | S |
| 4.2 | 沙盒容器内缓存：`~/Library/Containers/*/Data/Library/Caches` | Mole `user.sh:1021-1279` | S |
| 4.3 | 开发工具缓存**走 owner 命令**（`go clean -modcache`、`cargo cache`、`brew autoremove` 预览优先），并在进程状态未知时拒绝执行 | Mole `lib/clean/dev.sh:72-447` + AGENTS.md 恢复契约条款 | M |
| 4.4 | 安装包残留查找（DMG/PKG/XIP + 按内容嗅探 ZIP） | Mole `bin/installer.sh:41-119` | M |
| 4.5 | 白名单持久化（当前 `excludedPaths` 是会话级内存态） | Mole `lib/manage/whitelist.sh`；现状 `MMCleaner.swift:26` | S |
| 4.6 | APFS purgeable 与 Time Machine 本地快照**只读报告**（删除需 root，不做） | Mole `cmd/status/metrics_disk.go:336-399`、`cmd/analyze/snapshots.go` | S |

### P3 / P4 落地状态（2026-09-30 逐条对着代码复核）

上面两张表写的时候是待办清单，现在有几条其实早就落地了，表里没改口，容易重复施工。
逐条核过代码后的真实状态：

| 项 | 状态 | 依据 |
|---|---|---|
| 3.1 设备占用指示 | ✅ 已落地 | `MMGuardian/DeviceUsage.swift` + `DeviceUsageProbe.swift`，见「P3.1 落地」节 |
| 3.2 TCC 授权只读视图 | 🟡 进行中 | 另一条线上正在做，结论以 `docs/analysis/guardian-tcc.md` 为准 |
| 3.3 登录项完整度 | 🟡 部分 | `LoginItemStore.swift` 已有 launchctl 交叉且非零退出码不再被 `try?` 吞掉；**"plist 在但没加载""运行中但找不到 plist" 两类异常标注仍未做**（全仓搜不到对应代码） |
| 3.4 菜单栏指标 | ✅ 已落地 | `MMMonitor.swift:71` 每核 CPU、`MetricReaders.swift` 有 `IOBlockStorageDriver` 差分 / compressed / `AppleSmartBattery` / IOReport |
| 3.5 不再写系统域 `Disabled` | ✅ 已落地 | `LaunchItemPolicy.swift:5` 明确"永远不尝试写 Disabled 键"，用户域改写走 throwing API（`LoginItemStore.swift:158-188`） |
| 4.1 非显性系统缓存 | ✅ 已落地 | `CacheScanner.swift:475-485`（metalfe / gpuarchiver），QuickLook、iconservices、GeoServices、photoanalysisd 同文件内共 13 处 |
| 4.2 沙盒容器内缓存 | ✅ 已落地 | `CacheScanner.swift:564-569` 走 `~/Library/Containers/*/Data/Library/Caches` 通配 |
| 4.3 开发工具缓存走 owner 命令 | ⬜ 未做 | 全仓搜不到 `go clean -modcache` / `cargo` / `brew autoremove`；这条是**执行第三方命令**，风险最高，动之前要先定"进程状态未知时拒绝执行"的判据 |
| 4.4 安装包残留查找 | 🟡 进行中 | 另一条线上正在做 |
| 4.5 白名单持久化 | ✅ 已落地 | `CleanerExclusionStore`（`MMCleaner.swift:25-53`）已是唯一真源，表里那句"当前是会话级内存态"过期了 |
| 4.6 purgeable / 本地快照只读报告 | ✅ 已落地 | `ReadOnlySpaceReport.swift`，读不到时整块说明原因，不显示 0 冒充事实 |

## 明确不采纳

- **Mach-O 瘦身 / Lipo、语言包裁剪**（Pearcleaner `Lipo.swift`、`Logic.swift:640-796`）：修改已签名 bundle，破坏签名与公证。与本项目红线一致。
- **App Store 私有框架**（`StoreFoundation`/`CommerceKit` 内嵌头文件）：私有框架链接会阻断公证。
- **`LSSharedFileList` 变更、`dlopen` 的 `SMLoginItemSetEnabledWithURL`**（Lemon `QMLoginItemManager.m:197-272`）：10.13 起废弃，App Store 不友好；统一用 `SMAppService`。
- **`tmutil` 快照删除、sudo 清 `/private/var/folders`**（Mole `lib/clean/system.sh:927-1180`）：其 fail-closed 身份复核机制成本与收益不成比例，改为只读报告。
- **OverSight 的拦截规则**：需要 EndpointSecurity entitlement，第三方工具拿不到；只做监控 + 通知。
- **相似照片清理**（Lemon `CalculatePictureFingerprint.m`）：高 CPU + Photos 库 TCC，回收价值低。
- **浏览器历史/Cookie 记录级删除**（Lemon `LemonPrivacyClean`）：属个人数据，且浏览器运行中 SQLite 被锁；本项目只做缓存目录级。
- **`docs/github-references/SwiftFormat`**：与系统工具无关，误引入，建议从 `docs/` 移除。

## 本轮验证与评估（2026-09-30）

**方法**：无头启动 + 环境变量把界面推到目标态，按窗口 ID `screencapture` 截图核对。
全程不做任何合成点击（点击会逃逸到用户的其他应用），因此所有"确认弹窗 / 审查面板"
类状态都由 hook 预置，且 hook 一律挑最小的候选项，误触发时损失接近于零。

| 屏 | 结果 |
|---|---|
| 概览、系统清理（缓存/文件夹/系统分析）、应用卸载、磁盘（Treemap 1–4 层 / 列表 / 大文件 / 审查面板 / 撤回 toast / 空态）、系统监控、隐私守护、系统优化、设置（4 个 tab） | ✅ 已截图核对，令牌一致 |

### 只有真渲染才暴露出来的问题（均已修）

| 现象 | 根因 | 修复 |
|---|---|---|
| 8 字节的真实占用显示成"0 KB" | `ByteCountFormatter` 没开 `.useBytes` | `3daa3fe` |
| 系统分析页点"清理"直接执行，没有确认 | 该页从未接确认弹窗，与另两个清理页不一致 | `6ec3aca` |
| 大文件/列表视图在空结果时是一片空白 | 没有空态分支 | `4a0c449` |
| 审查面板里父子同时被标记，总数凭空翻倍 | 标记集合直接求和，没有裁决层 | `3c2817a` |
| `MM_OPEN_MODULE` 写错值时停在概览，截图看着像"通过" | 未知值被静默忽略 | 本轮：写 stderr 留痕 |

### P0 复核

0.1（全文件 SHA-256 分桶）、0.2（删除统一走 `FileTrashService`）、0.4（空包目录已删）、
0.5（概览真实采样）均已落地；0.3 的 `runOptimization` 假动作符号已不存在。

### 下一步（按价值/成本）

1. ✅ **P1.4 孤儿残留反向扫描**：卸载页目前只能"选 app → 清残留"，反向的"哪些残留没有主人"
   还没做，这是卸载模块真正差异化的一步。（已落地，见下节）
2. ✅ **P1.6 删除历史持久化**：15 秒 toast 撤回窗口太短；`FileTrashService` 已有 operationID，
   缺的是落盘与历史页。（已落地，见下节）
3. ✅ **disktree #7 键盘通路收尾**：方向键/回门/空格/Esc 已通，filter 也已改成全树口径（见「P1.7」节）。
4. ✅ **P3.1 麦克风/摄像头占用指示**：已落地（见「P3.1」节）。本机无摄像头/无输入设备，
   正分支（真的有人在采集）仍需在带摄像头的机器上复验。

## P1.4 落地：卸载后遗症（孤儿残留反向扫描）

正向扫描问"这个应用的文件在哪"，反向扫描问"这些文件是谁的"。逆问题的难点不在遍历，
而在**什么才算没有主人**，所以判定口径全部偏保守——宁可漏报，不可错报：

| 规则 | 为什么 |
|---|---|
| 只认反向域名形态（≥3 段点分、每段 ≥2 字符、总长 ≥10） | `Caches`、`Google` 这种单词目录不可能是归属线索，撞车概率太高 |
| `com-apple*` 一律不报 | 系统组件的缓存和偏好看起来全都"没有对应的已装应用"，因为应用在 /System 里 |
| 派生标识算有主人（`com.foo.Bar.Updater` / `.Helper`） | 只从前往后截短比对，厂商前缀本身不是包名就不吞掉同厂商其他应用 |
| 末段是 UUID 先剥掉再判形态 | `MMCleaner.ExclusionStoreTests.<uuid>` 是每次运行换一个的实例产物，不是应用标识 |
| `Containers` / `Group Containers` 整条清单跳过 | 目录名是随机标识，正向要靠 `MCMMetadataIdentifier` 反查，反向没有名称可判 |
| 系统域默认不扫 | `/Library` 要 root 才读得动，列出来只会灌一屏删不掉的项 |
| 结果**永远默认不勾选** | 反向结论只是"高度可疑"，装在别的卷、包名与磁盘名不同形都会被判成可疑 |

UI 侧新增「已装应用 / 卸载后遗症」分段切换，切过去自动反查一次；操作栏合计沿用
"没量到就不给数"的口径（`测量中` / `尚未反查`，不写 `0 项` 冒充"这里干净"）。
确认面板逐条列路径与大小，动词按实际操作走：只清残留时撤回提示说"已卸载"是假话，
因此 toast 文案由 `lastOperationTrashedApps` 决定。

**两套路径，不是笔误**：列表行用 `displayPath`（`~/Library/Caches/…`，home 缩写），
确认面板用 `path`（绝对路径）。列表要扫读，被缩掉的那段是每个人都不需要看的用户名；
确认面板要回答的是"到底删哪一条"，绝对路径才能直接粘进终端核对。
`OrphanCandidate` 因此同时带这两个字段，`judge` 多收一个 `home:`。

**新增验证钩子**：`MM_UNINSTALL_PANE=apps|orphans` 选分段，
`MM_ORPHAN_FIXTURE_HOME=/tmp/...` 把反查的 home 换成夹具目录并自动全选 + 打开确认面板。
后者硬性只接受 `/tmp` 前缀，否则写 stderr 并忽略——验证钩子指向真实主目录的话，
自动勾选 + 确认面板再被误按一次回车就是真删用户文件。

### 真机数据才暴露出来的两件事

1. **单测往真实 `~/Library/Preferences` 落了 10 个 plist**。`UserDefaults(suiteName:)`
   的隔离 suite 名是 `MMCleaner.ExclusionStoreTests`，`removePersistentDomain` 能把内容
   清空（42 字节的空域），但 cfprefsd 为每次 XCTest 运行留的 `<suite>.<uuid>.plist`
   删不掉。修法不是去用户主目录里删文件，而是把这类"末段 UUID"从判定里剔出去（见上表），
   并把测试文件里那句"绝不写真实域"的注释改成实话。真机候选数 94 → 85。
2. **反查必须等应用列表枚举完**。归属清单就是判定依据，枚举到一半开扫，
   没来得及入表的应用全部会被判成孤儿。`scanOrphans` 现在在
   `isScanningApps` 或 `apps.isEmpty` 时直接不响应，视图在枚举结束后补一次。

## P1.6 落地：删除历史持久化 + 跨启动撤回

设计稿 `05-states.html` 早就写了口径：**toast 是事后兜底，不是唯一入口——撤回必须在
「最近操作」里长期可用，15 秒过期不等于不可撤回**。而 `FileTrashService.trashHistory`
一直只活在内存里，重启之后那句"可在「最近操作」中撤回"就变成空头支票。

- 新增 `TrashHistoryStore`（`~/Library/Application Support/MacMaster/trash-history.json`）：
  原子写；读不出来时把坏文件改名成 `*.corrupt-<时间戳>` 留档，而不是静默覆盖。
- `FileTrashService` 的内存与磁盘只通过一个出口 `record(_:)` 改动，两边不会各说各话；
  上限 `historyLimit = 20` 也只有一个来源。store 可注入，单测因此绝不写真实
  Application Support，也绝不往用户的 `~/.Trash` 里放东西（`trashPath` 由临时目录冒充）。
- `TrashOperation.canUndo`：记录还在、但废纸篓里那个文件已经不在了（用户倒过垃圾），
  这不是失败而是事实。撤回按钮据此消失，换成"废纸篓已清空"，而不是等用户按下去才拿到错误。
- 台账不做过滤：不可撤回的那条照样列出来，抹掉它等于宣称"这次清理没发生过"。

**只有真渲染才暴露的问题**：「最近操作」卡片只有 ~330pt 宽，副标题
"N 个文件 · M 项失败" 在窄栏里被截成"1 项…"，而失败数恰恰是最不该看不见的一段 →
计数词统一收成"项"。

**已收掉的尾巴**：历史里存的是绝对路径，属于用户数据，所以设置页 · 清理现在有一节「删除历史」：
条目数（`N / 20`，20 这个数来自 `FileTrashService.historyLimit`，界面上不另抄一份）、
台账文件在哪 + 「在访达中显示台账文件」、以及「清空删除历史」。
清空走 `FileTrashService.clearHistory()`，它和另外两种改动共用同一个 `record(_:)` 出口，
所以内存与磁盘不会一边清了一边没清——`testClearHistoryEmptiesMemoryAndDiskTogether` 盯的就是这条。
确认文案写死了代价：**只删记录，不碰废纸篓里的文件**，而撤回入口随记录一起消失。

## P1.7 落地：磁盘分析的全树名称过滤（disktree #7 收尾）

原来的筛选框只过滤**当前这一层**：输入 `swift`，看到的是"这一层谁叫这个名字"，
而用户真正在问的是"这棵子里谁跟 swift 有关"。新口径由 `DiskTreeFilter`（`Packages/MMDisk/Sources/MMDisk/`）
一处算清，面包屑、treemap、列表共用同一份结果：

| 规则 | 为什么 |
|---|---|
| 后代命中 → 祖先以**命中体积**出现，且只保留含命中的分支 | 祖先块若按自身总占用画，用户会以为"这一大块都是我要的"，面积必须回答"这里面命中了多少" |
| 目录名**自身**命中 → 全量计入、子树原样展示 | 用户找的就是这个目录整体，不该在里面继续按名字剪枝 |
| 超出扫描深度、没逐层枚举过的目录 → 单独计 `indeterminateCount/Bytes` | "量过、确实没命中"和"没扫到、判不了"是两回事，折叠成零命中就是假清白；它也不参与布局（面积无从编起） |
| 命中项保色、含命中的祖先退色（两级），hover 回全亮 | 色相回答"这是什么"，保色/退色回答"它是不是命中本身"，两个维度不能互相污染 |
| 过滤为空 → `apply` 返回 nil，视图直接走原始布局 | 残状态在结构上就不存在，不靠"记得清缓存" |

**顺带修掉一个面积守恒 bug**：`TreemapLayout` 计算"其余"合并块时用 `maxChildren`（depth 0 的窗口）
作基准，而本层实际绘制的是 `childCap(at: depth)`（深层只有 24/6/4）。cap 与 maxChildren 之间的块
被静默丢掉，"其余"块也没把它们的面积计进去。不修它，全树过滤按命中体积重排后祖先块会偏小，
"命中占了多少"这个数就是错的。

**新增验证钩子**：`MM_DISK_FILTER=<关键词>` 把名称过滤预置进输入框（键盘事件无法在无头验证里
聚焦 NSTextField，见下）。

### 没能验证到的部分

- "清空筛选框回到原始布局"只有单测与结构保证（`apply` 返回 nil 这条路径），**没有真机截图**：
  无头验证里 CGEvent 键事件打不进筛选框（应用未激活时全窗口拿不到 first responder），
  按项目法则也不允许用合成点击兜底。同理，treemap 键盘导航那句 `.help("Tab 聚焦后…")`
  在系统设置"全键盘访问"关闭时是否成立，也还没实测过——这是下一条待办。
- `indeterminate` 徽章需要一台真有 20 层深目录的机器才会出现在截图里，本机没有。

## P3.1 落地：谁在用我的摄像头 / 麦克风

隐私守护原来只有登录项管理，"此刻有没有人在采集我"这一问完全没答案。
选型、本机验证矩阵与被否决的路径都在 `docs/analysis/guardian-device-usage.md`，结论：

- 麦克风：CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`，进程内只读、微秒级、不弹权限。
- 摄像头：CoreMediaIO 的 `'gone'` 读数 + `AVCaptureDevice.DiscoverySession` 只做存在性交叉核对
  （只枚举、不建 session，因此不触发 TCC 弹窗）。
- **不做进程归属**。公开接口只给是/否；`lsof` 看不见 mach IPC 结构的占用，tccd 日志是"签入时刻"
  语义且 `<private>` 脱敏。所以占用那一行如实写"使用方无法确定 · 公开接口不返回进程"，
  留白会被读成"查了但没写"。

四档状态各有各的承诺，不能互相顶替：

| 状态 | 依据 | 界面上绝不写成 |
|---|---|---|
| 正在被使用 | 纯输入/采集设备读到 1 | — |
| 当前空闲 | 设备在，且这次**测到了** 0 | "没有应用在偷用"（读数会过期） |
| 无法确定 | 读取失败 / 组合设备播放歧义 / 两个枚举器互相矛盾 | 绿色"空闲"——灰才对应"我们不知道" |
| 本机没有该设备 | 枚举成功且确认 0 通道，两个枚举器互相印证 | "无法确定"（硬件事实信息量更大） |

**复核时改掉的三处口径**：

1. `channelCount` 读失败原本 `return 0`，于是"属性没读到"会被判成"本机没有麦克风"这条硬件事实。
   现在返回 `Int?`：实测无输入设备的读取是**成功**的（`size=8`、`mNumberBuffers=0`），
   所以 0 走"没有设备"，读失败走"无法确定"。
2. 组合设备（麦+扬声器一体）读到 1 时，输出通道数读不到也不能算 `inUse`——分不清是哪一侧在跑。
3. 页头副标题原本写"实时占用"，而卡头同时标"测量于 02:26"：这一屏是点刷新时测一次，
   不是常驻监听，两处口径必须一致 → 改成"当前占用（手动测量，非实时监听）"。
   卡头的摄像头图标也不再常驻红色：本屏的红色只属于"正在被使用"。

**新增验证钩子**：`MM_GUARDIAN_FIXTURE=camera|mic=inuse|idle|unknown|absent`（逗号分隔）。
含任何非法取值时整个钩子作废并写 stderr——半生效的夹具会让截图把"半真半假"当成"全按夹具渲染"。

### 没能验证到的部分

本机是 Mac mini：没有摄像头，也没有任何带输入通道的设备。所以
**"正在被使用"这一档只在夹具里渲染过，没有真机正分支**；摄像头分支的 `running==1`
按头文件语义实现，需要在带摄像头的机器上复验。组合设备歧义同理（本机那台
"Mac mini扬声器"读到的是 0，触发不了）。
