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
| 3.2 TCC 授权只读视图 | ✅ 已落地 | `MMGuardian/TCCAuthorization.swift` + `TCCProbe.swift`（只读 `SQLITE_OPEN_READONLY`，半读即整库判不可读），见「P3.2 落地」节 |
| 3.3 登录项异常标注 | ✅ 已落地 | `MMGuardian/LoginItemAudit.swift`：磁盘 plist × `launchctl list` 快照交叉，三类异常徽章 + 孤儿标签脚注，见「P3.3 落地」节 |
| 3.4 菜单栏指标 | ✅ 已落地 | `MMMonitor.swift:71` 每核 CPU、`MetricReaders.swift` 有 `IOBlockStorageDriver` 差分 / compressed / `AppleSmartBattery` / IOReport |
| 3.5 不再写系统域 `Disabled` | ✅ 已落地 | `LaunchItemPolicy.swift:5` 明确"永远不尝试写 Disabled 键"，用户域改写走 throwing API（`LoginItemStore.swift:158-188`） |
| 4.1 非显性系统缓存 | ✅ 已落地 | `CacheScanner.swift:475-485`（metalfe / gpuarchiver），QuickLook、iconservices、GeoServices、photoanalysisd 同文件内共 13 处 |
| 4.2 沙盒容器内缓存 | ✅ 已落地 | `CacheScanner.swift:564-569` 走 `~/Library/Containers/*/Data/Library/Caches` 通配 |
| 4.3 开发工具缓存走 owner 命令 | ✅ 已落地（只报不执行） | `MMOptimizer/DevToolCacheAudit.swift` + 「开发工具」tab：位置来源/在不在/多大 + 可拷贝的 owner 命令。**刻意不执行第三方二进制**，判据见 `docs/analysis/devtool-owner-commands.md` |
| 4.4 安装包残留查找 | ✅ 已落地 | `MMFileScanner/InstallerScanner.swift` 内容嗅探（koly / xar! / EOCD 中央目录）+ `UserFolderCleanView` 区块，见「P4.4 落地」节 |
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

## P3.2 落地：敏感权限授权只读视图（TCC）

**做了什么**：`MMGuardian/TCCAuthorization.swift`（纯判定 + 文案 + 夹具解析）、
`TCCProbe.swift`（唯一碰系统调用的一层）、`MMGuardian.swift` 的 `tccCard`。
只读打开两个 `TCC.db`（`SQLITE_OPEN_READONLY`，无 `CREATE`/`READWRITE`），
`SELECT service, client, client_type, auth_value, last_modified FROM access WHERE service IN (五个 tracked 服务)`，
绝不写库、绝不 sudo、不提权。

**本机实测（复核过，不是转述）**：
- 用户级 `~/Library/Application Support/com.apple.TCC/` → `ls` 直接 `No such file or directory`，
  `sqlite3` 报 `unable to open database file`；
- 系统级 `/Library/Application Support/com.apple.TCC/TCC.db` → `authorization denied`。
所以"读不到"是这台机器的常态档，状态机把它当第一等公民设计，而不是边角分支。

**口径**（`TCCViewerState` 四档 + 测量中）：
- `.unreadable` 逐库带 errno/strerror 与 sqlite 原文；ENOENT 单独措辞成"不存在或被系统对无
  「完全磁盘访问」的进程隐藏"——无 FDA 时目录是被隐形的，谎报成"没有这个库"就是假话。
- `.emptyRead`（"没有授权记录"）只有在没有任何一个库处于 unreadable 时才允许出现；
  有库没读到就降成 `.partial(rows:[], unreadableNote:)`，并点名是哪个库。
- `auth_value` 只映射 0/2/3/4；`1` 和一切表外值都是"未知值 (N)"，永不猜成"允许"。
- 探针层不做单元测试：拿夹具 db 测它只能证明 sqlite 能用，证明不了真 TCC 库的可读性。

**新增验证钩子**：`MM_TCC_FIXTURE=rows|unreadable|empty`。`rows` 档注入的全是 `com.example.*`
合成行，与真实数据一眼可分。

### 没能验证到的部分

"授 FDA 之后能读到"这条没验证——无头环境里没法替用户点系统设置那个开关。
所以 `.loaded` / `.partial` 两档只在合成夹具下渲染过，真机两库都打不开。
`emptyRead` 同理：这台机器上从没真的读到过 0 行。

## P4.4 落地：安装包残留查找（DMG / PKG / MPKG / XIP + 按内容嗅探的 ZIP）

**做了什么**：`MMFileScanner/InstallerScanner.swift`（actor，512 行，纯只读）+
`UserFolderCleanView` 的「安装包残留」区块。口径来自 Mole `bin/installer.sh:41-119`，
但实现换成内容嗅探：只读文件头/尾的 magic bytes 与 ZIP 中央目录的条目名，
**不解压、不写文件、不执行被扫描对象**（Mole 那边是 `unzip -l`，会 spawn 第三方进程）。

**证据分两档，绝不合并**：
- `.verified`：UDIF 尾块 `koly`（版本 1-8 + headerSize=512，大端）、`xar!` 头、
  XIP 签名信封 `AB C1 AD FE`、或 ZIP 中央目录里出现顶层 `<Name>.app/`；
- `.nameOnly`：只有扩展名对得上、内容没能核实（读不动 / 太小 / 不认识的变体）。
  UI 上是橙色问号徽章「仅按名称识别」，绝不借用绿/蓝。
- `.zip` 是唯一"判不了就不列"的例外：普通 zip 太常见，宁可漏报不错报。

**接入既有安全管线**：与用户文件夹清理共用 `FileTrashService`（移入废纸篓、可撤回），
默认全部不勾选；`size == nil` 渲染"测量中"。

**新增验证钩子**：`MM_INSTALLER_FIXTURE_DIR`，只接受 `/tmp` 或 `/private/tmp` 前缀
（非法值写 stderr 后忽略），且必须同时给 `MM_SHOW_CONFIRM` 才会自动勾选并弹确认面板。
这一屏的删除按钮是真删文件，钩子的防护必须比别屏更严。

### 复核时改出来的两件事

1. **深度上限必须写在页面上**。`maxDepth=2` 意味着"根目录 + 一层子目录"，更深处根本没看。
   空结果最容易骗人的地方就是"没看过"被读成"没有"——所以区块里加了一条常驻范围声明：
   「扫描范围：~/Desktop、~/Downloads、~/Documents、~/Public · 只查这些位置本身及其一层子目录，
   更深的目录本轮没有查看」。这条按 `report.scannedRoots` 实际值渲染，夹具模式下不会谎称扫了家目录。
2. `~` 缩写写成 `"~" + path.dropFirst(home.count)` 会产出 `~/Desktop`（双波浪）。
   正确是 `~/" + dropFirst(home.count + 1)`。真机截图放大才看得出来，肉眼在小字上会漏。

### 没能验证到的部分

`.xip` 的 `AB C1 AD FE` 魔数按公开格式资料实现，本机没有 .xip 样本实证；对不上只会降级成
`nameOnly`（安全方向的误差）。`installerInaccessibleRoots` 的真机渲染没截到——
那四个家目录子项在 TCC 保护下都能枚举，模拟"读不到"要指真实目录，风险大于收益。

## P3.3 落地：登录项异常标注（磁盘 plist × launchd 快照）

**做了什么**：`MMGuardian/LoginItemAudit.swift`（纯逻辑，无 IO）+ `LoginItemStore` 的
只读 `LaunchctlRunner.listSnapshot()` + `LoginItemRow` 的徽章行 + 卡片脚注。
把原来"列表里有个开关"升级成"两处记录对不上时点名"。

**三类判定，全部只报不一致、不报坏了**：
- `plistNotLoaded`：plist 在磁盘上且没写 `Disabled`，但当前 GUI 会话的 `launchctl list` 里没有它；
- `disabledButLoaded`：写着 `Disabled=true` 却仍在加载；
- `orphanLoaded`：launchd 里有标签，五个已知 LaunchAgents/Daemons 目录都找不到 plist。

**判据边界（写进代码注释，也写进文案）**：
- `LaunchDaemons` 不参与交叉——GUI 域的 `launchctl list` 本来就看不见它们，
  否则每个守护进程都会被误标成"没加载"。
- `.disabled` 改名的文件由文件名管，不再叠一枚"没加载"（launchd 根本不读它，
  两枚徽章只会互相解释不掉）；同时 `toggle` 对这类文件直接拒绝写入并回
  `RENAME-MANAGED`，不做任何文件写尝试。
- `userPreferences`（旧 `loginitems.plist` 兼容条目）不判。
- 解析器一个标签都没解析出来时返回 `.unavailable` 而不是空集合——
  空集合会让"所有 plist 都没加载"成为下一帧的"事实"。

**真机数字（本机 17 项，readErrors=0）**：异常 3 条，全是 `plistNotLoaded`
（`/Library/LaunchAgents/com.sogou.SogouServices.plist`、`com.sogou.SogouTaskManager.plist`、
`~/Library/LaunchAgents/com.pnuts.jenkins.plist`）。孤儿标签**候选 101 个，其中 99 个是
`com.apple.*`**——不排除苹果标签等于把 2 条真正该看的埋进 99 条噪音里，
所以只列非苹果自家的 2 条（`com.ollama.ollama`、`com.postgresapp.Postgres2LoginHelper`），
并在旁边写明"SMAppService 注册的登录项本来就不落这些目录，不一定是残留"。

**还原度**：设计稿 `06-guardian.html` 的登录项区块同步补上「改名停用」「没在当前会话里加载」
两枚徽章与脚注，`render.sh` 重渲染后与实机截图逐行对齐（徽章文案、颜色档位、脚注两段一致）。

### 没能验证到的部分

`disabledButLoaded` 与 `orphanLoaded` 两类徽章**没有真机渲染截图**——本机没有制造这两种状态
而不写真实 LaunchAgents 的办法，只有单元测试覆盖判定逻辑。
`launchctl list` 失败/超时导致的 `.indeterminate` 脚注同样只在测试里走过。
截图窗口锁在 1100×700（`.defaultSize` 与自动保存帧都不受控），登录项卡整卡高于视口，
所以脚注是靠"临时把该卡提到首位 + 脚注单独成卡"截到的；两处补丁均为 `TEMP-CAPTURE`，
提交前已全部回退并复查过（全仓 `grep TEMP-CAPTURE` 无命中）。

## P4.3 落地：开发工具缓存只报位置和 owner 命令，不代跑

判据与取舍全部写在 `docs/analysis/devtool-owner-commands.md`，这里只记结果。

**做了什么**：`MMOptimizer/DevToolCacheAudit.swift`（纯函数，环境字典 + 探针全注入，可完整单测）
+ 「系统优化 → 开发工具」新 tab。六条缓存（Go 模块 / Go 构建 / Cargo registry / Homebrew /
npm / pip），每条报三件独立事实：**装没装**（PATH 里 stat，不执行）、**在不在**、**多大**，
外加一条只能拷贝的命令和"为什么不该 rm 这个目录"。这一屏没有删除按钮。

**为什么不执行**：跑 `go clean -modcache` 就是信任用户机器上任意版本的 go。参考实现为了安全
执行，在最后一跳还要复查符号链接位、做词法/物理双路径身份快照、探进程状态、加超时
（Mole `dev.sh:845-905`）。不执行就把这整层风险面消掉了，也就不需要"进程状态未知时拒绝执行"
这条判据——没有执行，就没有需要拒绝的执行。代价是这一屏回收不了空间。

**顺手改口的一条**：`brew autoremove` 从 4.3 里拿掉。它卸载的是 formula 本身，不是缓存，
清理工具不该给"卸掉你正在用的软件"入口。有单测钉住整屏不出现这条命令。

### 顺着这一屏查出来的测量错误（影响全仓）

`SystemSampler.directoryBytes` 带着 `options: [.skipsHiddenFiles]`。这个选项不只是省掉
`.DS_Store`——它会把**以点开头的目录整个剪掉**，而 cargo 的 registry 体积几乎全在
`index.crates.io-*/.cache/` 底下。本机因此被报成 **12 KB，实测 75 MB**，错了三个数量级。

这条函数是缓存分类体积、废纸篓占用、撤回台账号径的共同底层，也就是说清理页上
"可释放 X GB" 一直在低报。修法是把 `.skipsHiddenFiles` 去掉（`SystemSampler.swift:164`），
并在 `MMCore/SystemSamplerSizeTests` 里钉住"隐藏子目录里的文件必须算"这条回归。

修完的真机对照：Cargo 包缓存 12 KB → **78.6 MB**（截图核对）。

### 没能验证到的部分

- 六条里只有 Cargo 一条落在"在用 + 有体积"档，其余五条本机目录都不存在，
  所以"存在且读不动"（`.unreadable`）这一档只有单测，没有真机渲染。
- 根位置一律走"环境变量 → 默认值"，没有向工具求证（那要 spawn `go env` / `npm config get cache`）。
  界面每条都标了「按默认位置 · 未向工具求证」，但**如果用户用 `mise` 之类二次重定位过，
  这一屏会指错地方**——Mole 为这个场景写过 issue #1378 的专门回归，我们没做。
- 「拷贝命令」按钮的点击效果没有真机验证（禁止合成点击），只验证了按钮渲染与文案。

## 本轮收口：07 / 08 / 09 三张设计稿 + 监控页降级语义修正

**三张稿**：`docs/design-system/screens/07-monitor.html`（A 正常态 / B 折叠线以下 / C 采样中首帧 /
D 降级态合集，含新增 D3a）、`08-optimizer.html`（08 首屏 / 08b 结果 / 08c 扫描中+浏览器 /
08d 系统状态+回执 / **08e 开发工具页签**）、`09-settings.html`（09a 通用 / 09b 监控 / 09c 清理+台账 /
09d 关于 / 09e 清空确认态）。逐元素对照与归属判定记在 `docs/analysis/fidelity-monitor.md`。

**审计里被判"实现该改 · 高"的三处，都是同一类错**：把"还不知道"写成一个已知结论。
① 页头在未采样时渲染成「上次采样 **0001-01-01 08:05**」（`.distantPast` 哨兵被当成真实时刻）；
② 内存卡在"压根没采过"时也说成「host_statistics64 失败」（给出错误的因果）；
③ 进程卡失败态 `detail: nil`，既没说原因也没说下一步。
修法：`MetricTypes.swift:227` 新增 `MetricSnapshot.hasSampled`，页头与内存卡共用这一个判据
（没改成 `Date?`：`sampledAt` 有 6 个调用点，把哨兵集中成具名字段波及面小得多，且②需要的正是同一个判据）；
进程卡补一句不带猜测的文案——失败点可能是 `proc_listallpids` 也可能是逐个 `proc_pidinfo`，
代码没区分，所以文案只说"没拿到任何结果"，指错原因比不说更糟。
`SampledAtSentinelTests` 钉住哨兵（3 例，MMMonitor 包 20 例全绿）。

**稿子反过来被实机纠正的一处**：09b 早期版本给三个菜单栏指标开关配了 cpu/mem/net 行首图标，
实机是裸 `Toggle("显示 CPU 使用率", …)`，`.grouped` Form 不会自己插符号。已按实机去掉，
并在 09b 说明里写明"本页所有开关行都没有行首图标"。

**顺手补的两个小口子**：`MM_CLEANER_FILTER` 环境变量给清理页搜索框一个初值，
用来把折叠线以下的分类截进视口——**不用合成键盘输入**，那会逃逸到用户的其他 app；
`CacheScanner` 的 `dev_cache` 副标题改成点名"另有工具自带的清理命令"，把这一类和
「开发工具」tab 交叉引上（`MMItemRow` 的副标题是中间截断，所以这句必须短）。

### 没能验证到的部分

- 未采样那一帧（页头「尚未完成首次采样」+ D3a 内存卡）**抢拍不到**：`MonitorView.onAppear`
  立刻 `enable()`，这一帧只存在于进程启动后的第一个 runloop tick。判据有单测，形态按代码重绘，
  稿内已标注"不是实机照片"。
- 进程失败态在本机从未发生（`topProcesses()` 一直有结果），也没有让它失败的钩子，同样只有重绘。
- 08e 的「未安装」「读不到」两档本机没跑出来，画在稿子的"推演档"那一块，实机截图只覆盖
  "位置不存在"和"在用"。
- 复核时怀疑 `proc_listallpids` 返回字节数会导致越界读 `pids`：**本机实测否掉**（523 进程时返回 523），
  现有写法安全，未改。

## P1.5 落地：废纸篓拖入 `.app` → 提示清理残留（2026-09-30）

`TrashWatcher`（kqueue，非 launchd、非常驻）+ 应用卸载页顶部的提示卡。
权限侧的实测结论单独成文：**[trash-watch-fda.md](trash-watch-fda.md)**，这里只记产品判断。

- **常态就是降级态。** 本机 `~/.Trash` 是 `stat` 放行、`open` EPERM(1)，所以首次进这一页
  看到的就是"读不到废纸篓"横幅（稿 `03c-3`）。这条不是错误分支，是默认画面，
  因此横幅里带真实错误码，并说清"重新进入这一页或重启应用才会生效"。
- **监听只在页面存活期 arm。** `.onAppear` 起、`.onDisappear` 停，设置页那行文案照实写"不是后台常驻"。
  一开始把 `start()` 排在 `.task` 里 `await model.loadApps()` 之后，是个真 bug：
  应用列表要测几十秒，这段时间里拖东西进废纸篓是没反应的。
- **本体永不进删除列表。** 卡片前提就是"本体已在废纸篓"，删除路径只由
  `report.deletionRoots(for:)` 给出；`TrashResidualNoticeFlowTests` 同时锁住
  "所有根都在注入的 home 之下"。测试全程只碰 `/tmp` 夹具。
- **还原即消失。** 用户把 app 从废纸篓拖回去，提示必须撤掉——那时候残留是活的，
  再挂着"清理残留"入口是害人的。这条也锁在单测里。
- **合并窗口是"最少等多久"。** 400ms 的 debounce 续体排在 MainActor 上，页面批量测量时会推迟出现；
  宁可晚出现，也不在测量中途插一整块列表刷新。移除调试打点后复测：列表还在测 13 个应用时，
  卡片约 8 秒内出现——之前"几十秒不恢复"主要是调试打点自己拖住主线程，不是架构问题。
- **实机两张图**：`docs/verification/p1.5-trash/uninstaller-no-fda-banner.jpg`（钩子全关 = 常态降级横幅）、
  `docs/verification/p1.5-trash/uninstaller-trash-notice.jpg`（夹具态 = 卡片 + 4 项残留 + 已选 2 项 · 6.3 MB）。
  夹具与抓图工具入库：`Scripts/trash-fixture.sh`、`Scripts/window-ids.swift`。

## P1.7 落地：删除闸门 `DeletionGuard`（2026-09-30）

所有删除动作的唯一闸口，接在 `FileTrashService.moveToTrash` 的循环开头。
判据、清单口径与实测依据单独成文：**[deletion-guard.md](deletion-guard.md)**，这里只记产品判断。

- **以前只有标签，没有闸门。** `MMDisk` 那份 `protectedRoots` 是给 treemap 上色的风险标注，
  标成"只读"的路径照样能被交给删除。现在标签留在原处（上色要粒度），拒绝执行另起一处。
- **拒绝要像失败一样被逐条上报。** 被挡的路径生成 `TrashFailure(code: "PROTECTED")`，
  走同一个回执面板、写进同一份删除台账。静默跳过会让界面报"移走 3 项"而实际挡了 1 项。
- **保护清单被已有功能逼出第三层口径。** 「用户文件夹清理」页正常目标就是
  桌面/文稿/下载/图片/影片/音乐，子树全挡等于废掉这一页；于是这六个目录改成
  **只挡目录本身**（那一页的文件夹行本身是可勾选的，整层桌面进废纸篓不可接受），内容照常放行。
  同理 `Data/vms`（虚拟磁盘镜像）挡、`Data/Library/Caches`（容器缓存类别）放。
- **一处清单在骗人，顺手改掉**：缓存类别 `mail_cache` 以前把 `~/Library/Mail` 当缓存列出来，
  那里面是邮件正文与附件。摘掉，只留 `~/Library/Caches/com.apple.mail`，类别改名"邮件缓存"。
- **回执面板区分两种红**：errno 用红色叉，主动拒绝用琥珀色盾牌，拒绝的理由给两行
  （一行截断正好切掉"逐项选择里面的内容"这半句可操作信息）。设计稿 `05-states` 的假想码
  `KEPT` 同步换成真实的 `PROTECTED`。
- **验证**：`DeletionGuardTests` 15 条判据 + `FileTrashServiceGuardTests` 6 条出口，
  出口测试全程只喂不存在的路径（闸门失效时 `trashItem` 会以 ENOENT 报红，真实文件一个不碰）。
  实机图 `docs/verification/p1.7-deletion-guard/cleaner-refusal-panel.jpg` 来自
  `MM_FAILURE_FIXTURE=protected` 预演钩子，文案由 `DeletionGuard` 现场算出。
  **缺**："点击删除 → 被拒 → 回执"这条交互链没有实机照片，走完它需要合成点击（项目红线禁止）。
