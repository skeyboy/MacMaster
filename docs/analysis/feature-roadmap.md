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

1. **P1.4 孤儿残留反向扫描**：卸载页目前只能"选 app → 清残留"，反向的"哪些残留没有主人"
   还没做，这是卸载模块真正差异化的一步。
2. **P1.6 删除历史持久化**：15 秒 toast 撤回窗口太短；`FileTrashService` 已有 operationID，
   缺的是落盘与历史页。
3. **disktree #7 键盘通路收尾**：方向键/回门/空格/Esc 已通，剩 filter 的全树口径。
4. **P3.1 麦克风/摄像头占用指示**：隐私守护现在只有登录项，"谁在用我的摄像头"还没答案。

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
