# 功能演化路线图：参考开源项目 → MacMaster

> 参考源：`docs/github-references/{Pearcleaner,Mole,stats,OverSight,disktree}`、`docs/lemon-cleaner`。
> 许可：本地 `Pearcleaner/LICENSE.md` 为 **Apache 2.0 + Commons Clause**（禁止销售其软件或派生产品）；Mole / OverSight / Lemon Cleaner 主模块为 **GPLv3**，Lemon Daemon 单独为 **GPLv2**；stats 与 disktree 为 **MIT**。本项目对这些仓库只借鉴技术思路并自行实现；若将来复用代码，必须逐文件核对许可与署名要求。
> 表中"已复核"列指我是否亲自打开过对应 MacMaster 文件确认现状。

## 现状盘点（历史基线）

下表是路线图最初写作时的缺口快照，不代表当前代码状态。当前模块顺序、完成项与验收结果见 [模块优先级](module-priority.md)。
"复核"列里的行号是**写作当时**的位置，会随重构漂走；本轮（P16）逐条现读了一遍，凡已失效的都补了现址。

| 模块 | 现状 | 复核 |
|---|---|---|
| `Packages/MMHelper`、`MMMenuBar`、`MMWidget` | **空目录，无 Package.swift**，是死引用 | 已复核（这三个目录现已整体不存在：`[[ -e Packages/MMHelper ]]` 等三查全 no such file；P16 现读） |
| `MMFileScanner/DuplicateScanner` | 只哈希前 10MB 且用非确定性 `Swift.Hasher`；**读取失败返回 `""`，全部不可读文件会被归为同一组"重复文件"** | 写作时复核的是当时那份 `MMFileScanner.swift` 里的 14 行——**那个位置已不存在**（重写过：本仓库那份文件只剩 168 行，不足 211）。那份实现在 2026-09-29「重复文件检测改为可验证的安全实现」中整体移出成独立文件。现址逐条现读，全在 `DuplicateScanner.swift`：SHA256 `:244`；读失败一律 `.failure` 并计入 `unreadablePaths`（`:238-240`、字段 `:55`）；采样是**首尾各 4 MB**而非前 10 MB（`sampleSize` 默认 `:100`，分支 `:246-251`）。这一行描述的三个缺陷在当前代码里都不成立，只作为缺口快照的历史保留 |
| `MMOptimizer.runOptimization` | **空操作**：只把状态改成 `.optimized`、detail 写"已完成"，不执行任何系统动作 | 写作时复核的是 `MMOptimizer.swift` 里当时的那 6 行；**该符号已不存在**（P16 现读：全仓 `grep -rn runOptimization` 零命中，那几个行号现在是失败面板的夹具赋值）。P0 §0.3 那条按"移除假动作"收口 |
| `MMOptimizer.deleteSelected` | 用 `try? FileManager.default.trashItem`，**绕过 `FileTrashService`**（无撤回、无历史、错误被 `try?` 吞掉） | 写作时复核的是 `MMOptimizer.swift` 里当时的那 3 行；**该符号已不存在**，那几个行号现在是扫描中文案。优化页删除现走 `FileTrashService`（P16 现读：`MMOptimizer.swift:434`、`:457`（撤回）、`:685`） |
| `MMUninstaller.findResiduals`（**P36 现读：该符号已不存在**，全仓 Swift 源码 0 命中；扫描拆在 `ContainerScanner`、`LaunchServiceScanner`、`OrphanScanner` 三个文件） | 只探测 11 个固定候选路径，无 Containers / Group Containers / LaunchAgents / receipts / Spotlight | 部分复核（**P29b 现读：本行五项全已落地，别再当缺口排期**——Containers 见 `ContainerScanner.swift:17`（`MCMMetadataIdentifier`）、Group Containers `:59`；LaunchAgents/Daemons 见 `LaunchServiceScanner.swift:44,98`；receipts 见 P1.8 的 `OrphanScanner.swift`；Spotlight 元数据即 `MCMMetadataIdentifier` 那条） |
| `MMGuardian` | 有 LaunchAgents/Daemons plist 扫描；对 `/Library` 域写 `Disabled` 键在无 root 时会静默失败；**完全没有摄像头/麦克风占用监控、没有 TCC 权限视图** | 部分复核（**P29b 现读：加粗那半句不成立**——`DeviceUsage.swift`/`DeviceUsageProbe.swift` 是占用检测，`TCCProbe.swift`/`TCCAuthorization.swift` 是只读授权视图，见下方「P3.1 落地」「P3.2 落地」两节；写 `Disabled` 那半句也已按 3.5 收口，`LaunchItemPolicy.swift:5` 明写"永远不尝试写"） |
| `MMMonitor` | 菜单栏 CPU/内存/网络 + 阈值通知；无每核、无磁盘 IO、无电池/温度/风扇 | 部分复核（**P29b 现读：除电池外全已落地**——每核与磁盘 IO 在 `MetricReaders.swift`（`IOBlockStorageDriver` 六处命中），温度/风扇在 `SMC.swift`+`SensorSampler.swift`+`HotBand.swift`（P6.4）；**"电池确实到现在也没有、三查 0 命中"是 P29b 那一读，本轮已作废**：**P37（2026-10-14）落地电池只读卡**，`AppleSmartBattery` 同一条口径现读 **11 处命中 / 5 个文件**（`grep -r --exclude-dir=.build`——不加这个排除会读到 20 处，多出来的九处全是 `.build` 里的编译产物，别把那条命令的结果当命中数），判定层 `BatterySnapshot`、读取层 `BatteryReader`、呈现层 `batteryCard` 全在，28 条单测 + 八档实拍。左边那一列"无电池"因此也不再是现状，见本节末 §3 的 v1.2 第一行与本文 §13） |
| `MMCleaner/CacheScanner` | 7 个静态类别，全在 `~/Library` 下 | 部分复核（**P29b 现读：不成立**——`CacheScanner.swift` 里 `/private/var/folders` 命中 7 处，4.1/4.2 那两行说的系统缓存与沙盒容器缓存都在） |

## P0：正确性与安全（先于任何新功能）

| # | 事项 | 落点 | 代价 |
|---|---|---|---|
| 0.1 | **重写重复文件判定**：size 分桶 → 首块哈希 → **全文件哈希确认**；不可读文件跳过而不是归入 `""` 组；哈希换稳定算法（CryptoKit `Insecure.MD5` 仅用于分桶 + 最终逐字节/全量摘要确认） | `MMFileScanner` | S |
| 0.2 | **删除统一走 `FileTrashService`**：`MMOptimizer` 两处 `try? trashItem` 改为带历史与撤回的服务；失败必须可见上报，不得 `try?` 吞掉 | `MMOptimizer` | S |
| 0.3 | **删掉假动作**：`runOptimization` 要么实现真实维护任务，要么从 UI 移除该行。宁可少功能，不可报"已完成"而什么都没做 | `MMOptimizer` | S |
| 0.4 | 清理空包目录 `MMHelper`/`MMMenuBar`/`MMWidget`（或补齐 Package.swift） | 仓库 | S |
| 0.5 | 概览页接真实数据（当前 CPU 23 / 内存 45 / 磁盘 49 与"清理 2.3 GB"全是硬编码常量） | `Sources/MacMaster/MainWindow.swift:123` | S |

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
| 4.5 | 白名单持久化（**P36 现读：已落地**——名单经 `CleanerExclusionStore` 持久化，`excludedEntries` 只是内存快照） | Mole `lib/manage/whitelist.sh`；现状 `MMCleaner.swift:26` | S |
| 4.6 | APFS purgeable 与 Time Machine 本地快照**只读报告**（删除需 root，不做） | Mole `cmd/status/metrics_disk.go:336-399`、`cmd/analyze/snapshots.go` | S |

### P3 / P4 落地状态（2026-09-30 逐条对着代码复核）

上面两张表写的时候是待办清单，现在有几条其实早就落地了，表里没改口，容易重复施工。
逐条核过代码后的真实状态：

| 项 | 状态 | 依据 |
|---|---|---|
| 3.1 设备占用指示 | ✅ 已落地 | `MMGuardian/DeviceUsage.swift` + `DeviceUsageProbe.swift`，见「P3.1 落地」节 |
| 3.2 TCC 授权只读视图 | ✅ 已落地 | `MMGuardian/TCCAuthorization.swift` + `TCCProbe.swift`（只读 `SQLITE_OPEN_READONLY`，半读即整库判不可读），见「P3.2 落地」节 |
| 3.3 登录项异常标注 | ✅ 已落地 | `MMGuardian/LoginItemAudit.swift`：磁盘 plist × `launchctl list` 快照交叉，三类异常徽章 + 孤儿标签脚注，见「P3.3 落地」节 |
| 3.4 菜单栏指标 | 🟡 **四项里两项从未落地，这一行的依据此前说满了** | `MMMonitor.swift:134` `perCoreCard` 每核 CPU（**P37 又顶漂一行**：电池卡那段代码插在它上面，133 成了空行——引用门禁这一跑唯一的硬失败就是它，所以这一格按"同行改写、不加行"重指。上一笔是 **P29b 重锚**：这一行从前引 `:71`，而门禁的符号面从它建立的第一跑起、26 份 `audit.log` 每一份都点名这一行——"那一行里没有 `IOBlockStorageDriver`/`AppleSmartBattery`"——提示档不进退出码，所以它喊了十几轮没人当账还，本轮换成真锚并同时改掉那两个假符号）、`MetricReaders.swift` 有 `IOBlockStorageDriver` 差分（六处命中）与 compressed 口径（`MetricTypes.swift:138-140`）。**但同一行从前还写着 `AppleSmartBattery` 与 IOReport——P29b 现读全仓 0 命中**（`battery`/`电池`/`AppleSmartBattery`/`IOReport` 四查皆空，命中的只有 `Sensors.swift:80` 一句"不做 GPU 归属推测"的注释），电池与 GPU 两张卡在 P6.4 那一节已自纠为"不存在"。**P29b 那一读这一行才是它的真实状态**；缺的两项排到 v1.2（见本节末）——**P37 兑现了其中一项**：`MMMonitor.swift` 现在有 `batteryCard`，判定层 `BatterySnapshot`、读取层 `BatteryReader` 都在，`AppleSmartBattery` 全仓现读 **11 处命中**（不再是 0），所以这一行剩下的"未落地"只有 GPU 那一项，账见本文 §13 |
| 3.5 不再写系统域 `Disabled` | ✅ 已落地 | `LaunchItemPolicy.swift:5` 明确"永远不尝试写 Disabled 键"，用户域改写走 throwing API（`LoginItemStore.swift:158-188`） |
| 4.1 非显性系统缓存 | ✅ 已落地 | `CacheScanner.swift:475-485`（metalfe / gpuarchiver），QuickLook、iconservices、GeoServices、photoanalysisd 同文件内共 13 处 |
| 4.2 沙盒容器内缓存 | ✅ 已落地 | `CacheScanner.swift:564-569` 走 `~/Library/Containers/*/Data/Library/Caches` 通配 |
| 4.3 开发工具缓存走 owner 命令 | ✅ 已落地（只报不执行） | `MMOptimizer/DevToolCacheAudit.swift` + 「开发工具」tab：位置来源/在不在/多大 + 可拷贝的 owner 命令。**刻意不执行第三方二进制**，判据见 `docs/analysis/devtool-owner-commands.md` |
| 4.4 安装包残留查找 | ✅ 已落地 | `MMFileScanner/InstallerScanner.swift` 内容嗅探（koly / xar! / EOCD 中央目录）+ `UserFolderCleanView` 区块，见「P4.4 落地」节 |
| 4.5 白名单持久化 | ✅ 已落地 | `CleanerExclusionStore`（`MMCleaner.swift:25-53`）已是唯一真源，表里那句"当前是会话级内存态"过期了 |
| 4.6 purgeable / 本地快照只读报告 | 🟡→✅ **本轮修真后才落地** | `ReadOnlySpaceReport.swift` + `SystemSpaceReport.swift`。此前快照那一块在 macOS 11+ 上**永远**显示"不可用"（解析器只认旧表头），见「P4.6 复核」节 |

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
5. ✅ **P1.8 安装收据只读归属**：孤儿反查读取 `PackageIdentifier` 作为排除误报的辅助线索；
   收据目录不进残留候选、不进入删除路径。注入 `/tmp` 假收据验证，见 `fidelity-uninstaller.md` §7。

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
"可释放 X GB" 一直在低报。修法是把 `.skipsHiddenFiles` 去掉（`SystemSampler.swift:166`），
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

**三张稿**：`docs/design-system/screens/mmmonitor/07-monitor.html`（A 正常态 / B 折叠线以下 / C 采样中首帧 /
D 降级态合集，含新增 D3a）、`08-optimizer.html`（08 首屏 / 08b 结果 / 08c 扫描中+浏览器 /
08d 系统状态+回执 / **08e 开发工具页签**）、`09-settings.html`（09a 通用 / 09b 监控 / 09c 清理+台账 /
09d 关于 / 09e 清空确认态）。逐元素对照与归属判定记在 `docs/analysis/fidelity-monitor.md`。

**审计里被判"实现该改 · 高"的三处，都是同一类错**：把"还不知道"写成一个已知结论。
① 页头在未采样时渲染成「上次采样 **0001-01-01 08:05**」（`.distantPast` 哨兵被当成真实时刻）；
② 内存卡在"压根没采过"时也说成「host_statistics64 失败」（给出错误的因果）；
③ 进程卡失败态 `detail: nil`，既没说原因也没说下一步。
修法：`MetricTypes.swift:431-433` 新增 `MetricSnapshot.hasSampled`，页头与内存卡共用这一个判据
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

## P4.6 复核：本地快照卡片在真机上从来没亮过（2026-10-01）

表里这条原本写着"✅ 已落地"。本轮为了选型去跑一次真机 `tmutil`，才发现它落地了但从没工作过：

```
$ tmutil listlocalsnapshots /
Snapshots for volume group containing disk /:      ← 本机实际表头
com.apple.os.update-5203530F8BB2…
com.apple.os.update-8847C532F7D8…
com.apple.os.update-MSUPrepareUpdate
```

- **根因**：`TimeMachineSnapshotReader.headerPrefix` 只认 `Snapshots for disk`，
  而 macOS 11 起带签名系统卷的机器输出的是 `Snapshots for volume group containing disk`。
  解析器坚持"没有表头就整块判不可用"（这条防呆本身是对的，它挡的是把报错文本当成清单），
  于是新系统上这块卡片**永远**是"本地快照：不可用"。
- **为什么单测全绿**：五条样例全按旧表头写。这是"照着想象里的输出写测试"的教科书案例——
  现在补了 `testRealMachineOutputParses`，只断言"解析得动"，不比条数（条数随机器状态变）。
- **顺带纠正的第二处口径**：条目过滤只认 `com.apple.TimeMachine.`，可这台没接 TM 的机器
  三条全是 `com.apple.os.update-*`。它们是系统更新的安全网，不是 TM 快照，
  统称"Time Machine 快照"会把用户指向错误的方向（删它影响更新回滚）。
  现在按 `timeMachine / systemUpdate / other` 分档，行上和条数后面都标来历。
- **明确不报字节**：试过用 `diskutil apfs list` 的容器差值凑——本机
  "各卷已用合计 486.7 GB"对"容器已用 488.1 GB"只差约 1.4 GB，那是元数据与预留，
  不是快照足迹。APFS 不给单个快照的独立占用，无 root 读不到，所以这块只有条数，
  并在界面上写清楚为什么没有 GB、以及第三方工具报的那个 GB 为什么不可信。
- **改名**：`TimeMachineSnapshot*` → `LocalSnapshot*`（`LocalSnapshotReader` /
  `LocalSnapshotListing`），因为列的已经不止 TM。
- **取证**：`MM_SNAPSHOT_FIXTURE` 把快照那一块换成样例文本（卷容量仍真读），
  四态照片在 `docs/verification/p6-snapshots/`：真机 / `mixed`（三档齐全）/
  `overflow`（9 条 → 列 6 + "另有 3 个"）/ `broken`（不可用 + 原始错误）。
  下方区块进不了画面这一条记在 `hook-ledger.md` §5：窗口高度被钳在约 1080pt，
  得靠 `MM_CLEANER_FILTER=废纸篓` 把表格缩短，而不是把窗拉高。

## P5.1 落地：开发产物跨目录聚合（cleaner 第四子页「开发产物」/ 稿 02c）（2026-10-01）

**参考**：`Mole/lib/clean/project.sh`（`MIN_AGE_DAYS=7`、深度 1…6、monorepo 指示器、
`CACHEDIR.TAG` 认缓存）、`purge_shared.sh:18` 的 20+ 产物名单。**我们比它窄一格**：
Mole 会 `git ls-files` 探产物里是否混了签入的源码，我们**不 spawn 任何第三方二进制**，
只用目录里看得见的证据（名单 / 邻居文件 / 清单文件 / CACHEDIR.TAG），认不出来的落 `protected`。

**落地**：`ProjectArtifactScanner`（MMFileScanner，917 行 + 42 条新单测，包内 93 条全绿）
→ `DevArtifactView`（MMCleaner 第四子页，`MM_OPEN_TAB=dev`）→ 设计稿 `02c-cleaner-dev.html`
→ 夹具 `Scripts/purge-fixture.sh` → 5 枚钩子（`hook-ledger.md` §1）。
还原度逐元素对照与"拍不到的三态"记在 `fidelity-cleaner.md` §7。

### 三件只有真机才说出来的事

1. **一个预算 bug（本轮唯一的功能缺陷，实机跑出来的）**：`rootBudgetSeconds` 被写成了
   **全局**截止时间，第一个根就把预算吃光，后面 7 个根（含 `~/Documents`）**一秒都没扫**——
   照片上"耗时 20.0 秒"正好等于预算值，这就是它的形状。修法：每根一份预算 **且** 全局封顶，
   `rootDeadline = min(now + rootBudget, started + totalBudget)`（抽成纯函数好测），
   并把 `Desktop`/`Documents` 提进显式根（**根的顺序就是预算的分配顺序**）。
   修前：20.0 秒 / 缺 7 根；修后：16.2 秒 / 缺 2 根（`~/Desktop`、`~/Documents` 仍在截断，
   页面用橙色那条点名，并写"截断范围内的项目没被扫过，不等于它们干净"）。
2. **Mole 的八个默认根在这台 Mac 上一个都不存在**（`~/dev`、`~/www`、`~/Projects`…是**压根没有**，
   不是读不动）。所以扫描器必须把"没有"和"读不动"分开报（`missingRoots` vs `unreadableRoots`），
   并且保留"home 下一级目录当容器"这条路——否则这台机器上一个项目都扫不出来。
   真机现在报 **100 个项目 · 145 处产物 · 可回收 19.37 GB**。
3. **两道闸门必须说同一句话**：`DeletionGuard.protectedHomeSubtrees` 早就挡着
   `Library/CloudStorage`，而扫描器原来只看名字和邻居，会给 iCloud 目录下的 `dist` 判"可回收"
   ——UI 上就是一个**勾了也删不掉**的复选框。修法：云同步在 `verdict` 里早于名单和
   CACHEDIR.TAG 拦下，理由原样带到行上（"位于 iCloud 同步目录：删除会同步到所有设备"）。
   删除链路本身仍是双层的：`FileTrashService.moveToTrash` 对每条路径再问一次
   `DeletionGuard.rejection(for:)`（`FileTrashService.swift:43`），扫描器的判定只是前置体验。

### 数字口径（本轮定下的规矩）

- **可回收 ≠ 批量按钮挑中的数**。真机 19.37 GB 里只有 6.79 GB 被"选中 7 天未触碰的"挑走，
  差的是**判定可回收但近期在用/活动度未知**的行——它们有勾选框，用户自己决定，批量按钮不替用户挑。
  夹具上这笔账逐行对得平（103.8 − 99.6 = 4.2 MB = `stale-site` 那两行"改动过"）。
- 三种"没有数字"分开写：整页没有可选行 → "无可回收条目"；有可选行但体积没测全 → "可回收 —"；
  单行体积读不到 → "—"（**绝不折成 0 字节**）。
- 活动度探测没跑完 → `.unknown`，**不许**写成"很久没碰"；读不进产物目录 → `protected`
  （无法确认里面没有签入的源码）。

### 没能验证到的部分

- **嵌套产物"已计入上一行"** 与 **夹具外软链被丢弃** 两态在真实扫描里构造不出来
  （发现阶段命中产物就不再下钻；`lstat` 从不跟随软链），只有单测覆盖——见 `fidelity-cleaner.md` §7.3。
- **真删一次**：这一屏的删除走 `FileTrashService`，但不对用户真项目演，也不做合成点击；
  照片停在确认面板（`04-fixture-confirm-sheet.jpg`）。
- 扫描器的 `progress:` 回调没接 UI（真机 16 秒，转圈可接受），本轮明确不做。

## P5.2 落地：安装来源识别（卸载页 03d，只读 brew 账本）（2026-10-02）

候选表 #2。给「已装应用」每一行标出它是**怎么装上的**，并在删除前把后果说清楚：
brew cask 装的应用被拖进废纸篓，`brew list` 仍然说它装着。

- **事实层** `AppProvenance.swift`（248 行）+ `AppProvenanceScanner`：
  只读 `<prefix>/Caskroom/<token>/.metadata/INSTALL_RECEIPT.json` 与 bundle 自己的元数据，
  **不 spawn 任何第三方二进制**（brew / git / pkgutil / mdls 一个都不叫），不碰私有框架。
  两个前缀（`/opt/homebrew`、`/usr/local`）都探，不按 CPU 架构猜——ARM 机器上另装一份 Intel brew 很常见。
- **判据强度排序**：设备身份 `(st_dev, st_ino)`（Caskroom 里 staged 的 `.app` 链接解析后与本 bundle
  是同一个 inode）> MAS 收据 `Contents/_MASReceipt/receipt` > 只有声明的名字对上 > 包名出现在
  `/var/db/receipts` > 无。命中两个 token 就**降级并点名**，不替用户挑第一个。
  "unknown ≠ 手动安装"写进了文案：装在别的卷、换了名字、用了别的安装器都会落在这里。
- **呈现层**全部在 `MMUninstaller.swift` 的 `extension UninstallCandidate`（`sourceChip` /
  `sourceBadge` / `sourceValue` / `sourceReceipt` / `sourceCommand` / `sourceBasis` / `sourceWarning`），
  文案合同 = 设计稿 03d 第三块那张表，逐字一致。**列表行内徽章只给 brew 两档**：
  这枚标记存在的理由是"它会改变你下一步的动作"，App Store 与安装包没有这种后果就不在列表里打扰。
- **对应命令只展示，绝不代跑**：`brew uninstall --cask <token>` 只在**设备号级凭据**那一档出现；
  只有名字对上时不给命令——凭据不足就推荐一条会改动系统状态的指令，是这一页最贵的一种错。
- 来源识别排在**测体积之前**：一条 stat 一次的开销，不需要等几十秒的 `DirectoryMetrics`
  才有徽章，列表刚出来就该说得出这一行是什么。

### 真机现状（`09-real-machine.jpg`，不注入任何夹具）

44 个应用全部测完：3 个设备号级 cask 命中（highball / homebrew-app / wailbrew）、
9 个 MAS 收据、0 个安装包命中、**0 个误报**（其余全部如实落在"无法判定"）。
Highball 那一屏给的是 `/opt/homebrew/Caskroom/highball/.metadata/INSTALL_RECEIPT.json`
与 `brew uninstall --cask highball`。这一张存在的意义是：解析器不是只对着夹具写的。

### 取证这一步抓出来的两个问题（详见 `fidelity-uninstaller.md` §8.2）

1. `provenanceMap` 用 `source != .unknown` 过滤"没必要存的空结构"，把**歧义这一档的事实**
   一起丢了（歧义也是 `.unknown`）。照片第一次拍出来是一句空白的「无法判定」。
   引擎单测当时全绿——漏的是模型装配路径，回归测试因此写在 `AppProvenanceTests` 而不是引擎测试里。
2. 两种歧义可信度不同：一份是"两份账本都**声明**了这个名字"，另一份是"两份 staged 链接
   解析后**都是这一份文件**"。合同表原本只有一句，实现照抄就把已知的事实说小了。
   补 `ambiguousByDeviceIdentity`，来源行与判定依据各自分叉，设计稿补第二行。

### 没能验证到的部分

- **安装包档（`.installerPackage`）没有实机照片**：夹具运行刻意不读真机 `/var/db/receipts`
  （否则"这一档没命中"到底是没凭据还是没读系统就分不出来），真机上这台也没有 bundleID 命中的包。
  只有设计稿合同表那一行 + 单测。
- **不删任何东西**：来源识别是纯读；照片停在确认面板（`06-fixture-confirm-sheet.jpg`），
  删除链路仍是 `DeletionGuard` → `FileTrashService`，本轮没有改动。

## P5.3 落地：应用目录装卸监听（卸载页 03e，进程内 kqueue）（2026-10-02）

- **补的是 P1.5 的一个真实盲区**：只监听 `~/.Trash` 时，用户"立即删除"或 `rm` 掉一个 app，
  残留提示完全不触发。现在监听**与列举同一套目录**（`/Applications` + `~/Applications`，第一层 `.app`），
  离开的那一张卡直接送到已有的「卸载后遗症」页，新来的那一条只报"清单过期"。
- **不学 Pearcleaner 的常驻 LaunchAgent**：照 `TrashWatcher` 的"页面存活期 arm"做进程内监听，
  kqueue 已实测能收到目录增删（`apps-watch.md` §3），FSEvents 这一轮不需要。
- **不自动重扫**：列表是用户正在看的表格，自动刷新会把他选中的应用换掉。
  消失卡的动作是「重新载入并扫描残留」，**先重载再扫**——清单还挂着那个应用时，
  反查会把它自己散在 `~/Library` 的文件当成"有主人"漏掉。
- **自我回声两头都堵**（§5 of `apps-watch.md`）：我们自己移走的那条不再报"刚从应用目录消失"；
  「仅卸载应用」那张卡的主语换成第二人称「你刚卸载了 X，残留还在」+ 徽章「由 MacMaster 移入」。
- **本轮取证顺带修掉两个真缺陷**：一个 `.fixedSize` 让整页比窗口高 397pt（并因此立了
  `Scripts/window-probe-sweep.sh` 这道逐屏几何守卫，7 页 × 两尺寸全部齐平）；
  回声卡把"我们动过手"寄托在"列得动废纸篓"上，没有完全磁盘访问的机器上它永远不出现。
  两条的来龙去脉在 `apps-watch.md` §6，照片在 `docs/verification/p9-apps-watch/`（4 张，零合成点击）。

## P6.1 落地：开发产物截断根的分批续扫（02c ②③）（2026-10-03）

- **把"橙色点名"变成"能按一次的按钮"**：P5.1 真机上 `~/Desktop`、`~/Documents` 在 15 s/根预算下
  仍然截断，而截断除了被点名一次就再没有下文。现在「继续扫描这 N 个根」只重跑被截断的根，
  上一批**已经看完证据的行整行复用**，这一批的预算全花在没量完的行上。
  夹具实测：首批 76.4 MB → 续扫后 162.8 MB（`docs/verification/p61-continue/`，4 张，零合成点击）。
- **难点确实不在续扫而在合并**（调研 §4.3/§4.4 兑现）：`mergedReport` 不能把两批的行拼起来完事，
  要重算嵌套折叠（新根可能把旧行变成"已计入上一行"）、重跑 `group`、
  并保证一个根在 scanned / truncated / inaccessible / missing 四本账里**只出现一次**。
- **试满两次就改口，不做常驻**（D6/D7）：同一个根最多 2 次，之后按钮置灰（藏起来等于什么都不说，
  而"不是坏了，是不该再按"恰恰是要让读者看见的那件事），点名条换成"这是这一处的上限"+ 两条出路
  （把项目放浅一层 / 单项目模式）。预算不递加、游标不落盘、不起 daemon。
- **勾选只修剪不清空**：续扫不新增删除权限，也不该把用户上一批的勾选无端抹掉；
  抹的是那些**失去勾选框**的行（被重标成嵌套、或改判受保护）。
- **本轮从照片里抓到一个判据错误**：组头「第 N 批补全」原来按"这一组的根有没有被重跑"点亮，
  于是整行复用的组和"重测完还是读不到"的组都会亮。改成按 `rowsCompletedByBatch`
  （这一批看完证据的行 − 上一批就已看完的）点亮。细节与另外两处自相矛盾的文案在
  `fidelity-cleaner.md` §8.2 / §8.4；一处 P5.1 就在、本轮没修的不自洽（根报"已扫完"而组里挂着
  「读不到（预算用尽）」）记在 §8.6，留给 P6.2 判。

## P6.2a 落地：磁盘标记跨重扫存续（04e）（2026-10-03）

disktree 那张"仍然推迟的一项"的账，本轮收掉。推迟的理由从来不是难写，而是它有两种**互相打架**的
错法，选错任何一种都比不做更糟——所以先把口径拆开再动手。

- **一件是存续，一件是过期，两件事必须同时做对**：标记按**绝对路径**挂回新扫描的树，
  体积**一律换成新扫描那一份**。只挂路径不换体积，底部那行「已标记 N 项 · X」就成了两个时间点的和，
  谁也核对不了；只换体积不挂路径，就是改动前的行为——用户重扫一次，半天的勾选白做。
  两条都落在 `Packages/MMDisk/Sources/MMDisk/DiskMarks.swift`（纯函数，9 条单测钉住）。
- **两套丢弃口径，故意不一样**：整根重扫（`scan(rootPath:)`、「选择目录」、`MM_DISK_RESCAN`）
  有资格说"这个路径不在了"，挂不回去就丢弃并点名；单层重新枚举（工具栏「重新扫描」、下钻未缓存目录）
  只对自己那层有管辖权——**没扫到 ≠ 不存在**，scope 之外的标记原样留着。
  另一个不显眼的边界：被枚举的那个目录永远不在自己的孩子里，所以 `path == rootPath` / `path == scope`
  的标记是**保留**，不是丢弃（`testReattachKeepsAMarkOnTheScannedRootItself`、`testRefreshKeepsAMarkOnTheEnumeratedDirectoryItself`）。
- **丢弃要说出来**：面包屑条上「重扫后 N 个标记已经不在了 · 已移除」，hover 逐个列路径。
  静默丢弃和静默保留一样坏——用户需要知道总量为什么变小了。
  `DiskRemoval.plan(marks:root:)` 是唯一的裁决入口（徽章 + 两块确认面板都从它走），
  所以 `marksDroppedByRescan` 是把待删总量**诚实缩小**，而不是让一个旧字节混进面板。
- **拍得到靠一个新钩子，零合成点击**：`MM_DISK_RESCAN` 让应用自己发起第二次扫描
  （给同一个根 = 拍"标记还在、体积换新"；给另一个 /tmp 根 = 拍"挂不回去的丢弃并说出来"），
  三档照片在 `docs/verification/p62-marks/`，脚本 `Scripts/p62-capture.sh`。
  配套改了一处钩子语义：`MM_DISK_SELECT` **只在首次扫描重放**——它代表的是"用户动手标记过一次"这个动作，
  每次扫描都重放的话，第二次扫描会把本该丢弃的标记重新加回来，照片上就看不出丢弃这条分支了
  （这条记在 `hook-ledger.md` §5，是本轮唯一一处"改钩子而不是改 UI"才能取证的地方）。
- 设计稿 `docs/design-system/screens/mmdisk/04e-disk-rescan.png`（两帧窗口，逐元素对照表在
  `fidelity-disk.md` §9.2）。§9.3 记了**三处拍不到**的：体积变化那一拍要求两次扫描之间磁盘真的动过，
  `refresh` 那条路要真点击（只有单测），`isUnder` 的整组件语义同理——都写清了对应钉住它的测试，不当已验证。

## P6.2b 落地：四处还原度瑕疵收口（2026-10-03）

四处里只有两处按原样成立，另外两处的**度量本身是错的**——所以这一轮真正的产出是三条口径，不只是四个补丁。

- **守护页那一条不是"少一条分隔线"，是整页换了语言**（`fidelity-guardian.md` §6.1）：稿 06 是"卡外标题行 +
  通栏卡（`card-flush{padding:0}`）+ 卡内平铺行带底分隔线"，实现是"带内边距的卡里塞标题 + 每行刷沉底药丸"。
  判它归实现一侧的依据不是稿，而是另外两页——概览与清理的表格行早就是 `MMCard(padding:0) + Divider()`，
  守护页是全站唯一的少数派。顺带关掉 I3（"只读检测 · 不申请任何权限"那句诚实披露从没上屏），它本来就该在 section 头。
- **改分隔语言时掉出两个切字 bug**（§6.2）：系统活动行 `height: 28` 装两行文字、登录行 `height: 44/56` 装三行徽章，
  两处都是**稿写 `min-height`、实现写死 `height`**。这类错单看代码不显眼，把行刷平、留白一变干净就露出来了——
  "还原度收口"能顺手查出真 bug，不是副产品。
- **"侧栏 229↔245pt"这组数在任何一张照片里都复现不了**，照着它动手就会改错地方。两次否证实验（§6.3）：
  手写 260pt 进 SwiftUI 自己那条 `NSSplitView Subview Frames…` → 屏幕仍是 200pt，退出时还被改回 200；
  把 `ideal` 改成 240 重新构建 → 仍是 200pt。**首屏宽度只认 `min`，`ideal` 与那条持久化记录都不参与。**
  所以 220 要落地只能抬 `min`，代价是用户拖不到 200 以下（`--sidebar-w-min` 在 CSS 里声明后从未被引用，没有合同被破坏）。
- **取证脚本里删掉了一段"看起来在解决问题"的代码**：为"上一轮 P4 把侧栏夹到 200 并持久化、污染了基线"这个猜测，
  脚本写过一段删偏好键的分支；实验 A 把它否证了，分支就删了——留着只会让下一个人以为像素基线由它兜住。
  测量一律在 **raw @2x PNG** 上做：P4 那批 `sips -Z 1400` 的 `.jpg` 坐标跟着缩，拿它报 px 就是假的。
- **sparkline 那张没有加历史注入钩子**：12 格横轴等真实采样长满，代价是脚本多跑 30 秒。另一条路是给截图编一段
  假历史，最容易也最坏——照片上每一根柱子都得能回到内核计数器上，否则这张图不算证据。
- 五张照片在 `docs/verification/p62b-fidelity/`（含两张否证实验的照片），脚本 `Scripts/p62b-capture.sh`，
  全档浅色、零合成点击。**没测的**也逐条写了：暗档、侧栏拖到 280 那一端、系统活动卡两档（钩子已有、本轮没拍）、
  登录项 `indeterminate`/`scanerror` 两档（§6.5）。**这四条里除 `scanerror` 外都由 P6.2c 关掉，见下一节。**

## P6.2c 落地：图标环按稿校正 + 守护页暗档（2026-10-03）

P6.2b 留下的"没测清单"一轮收掉三条，顺带把 I4 那条我**自己写错的判据**改对。

- **I4 原判定"实现没有环"是看漏**：`DeviceUsageRow` 一直有 `Circle().stroke`。真实差异三条——
  外圈 30pt vs 稿面 38pt、描边跟语义 tint 走（空闲态因此成了**绿环**，而稿里绿色只属于右侧 `badge safe`）、
  live 缺 `--c-danger-soft` 那层红底。**同一行两处绿**是这一处真正的损失：这一屏的红/绿是稀缺信号
  （"此刻确有进程在驱动"），环和图标不参与表态，多一处上色就稀释一次判定强度。
- **稿上的 34pt 是个陷阱，抄它反而更远**：`screen.css` 没有 box-sizing reset，`.urow .ring{width:34px;
  border:2px}` 的 34 是**内容盒**，浏览器画出来外圈 38px（量稿子 PNG = 76px@2x 对上了）；
  而 SwiftUI 的 `stroke` 骑在路径中线上、向 frame 外各溢半个线宽，所以 38pt 外圈要由 **36pt frame** 承载。
  本轮第一版照稿面抄成 34，量出来 36pt——**"照稿改"里"照"的是稿面数字还是稿的渲染结果，
  这两个动作会差 2pt**，这一处是后者。换算连同原因写进 `MMDesign.swift:123` 的注释。
- **暗档那条"未知"划掉了**：八档 × 明暗两套重拍，同名两张上量同一行——浅色卡底 `(255,255,255)` →
  分隔线 `(230,230,230)`，深色 `(37,37,37)` → `(58,58,58)`，都是 2px 发丝线。
  **P6.2b 去掉行药丸底没有让暗档的行更难分辨**，这条从猜变成量过的。
- **两处采集设计缺陷：照片存在但不证明任何东西**。① 系统活动卡排在第 4 位，它上面那张 TCC 空态卡
  就有 ~600pt 高，760pt 窗口里它**永远在折叠线以下**——07/08 两档之前拍的都是页面上半，
  命名的对象一个都不在画面里。修法：窗口拉到 1100×1000（屏 1920×1080pt 的上限附近）
  + 把上方两卡换成矮夹具态，代价（那两卡不算本机状态）写在照片旁边而不是心里。
  ② 07 第一次拍到的是活动卡**空态**：`loadActivity()` 的夹具分支**先真跑一次** `ActivityScanner.scan()`
  （含 `log show` 子进程）再顶替展示数据，8 秒等待截在覆盖之前。改成 25 秒。
  **凡是"先真跑再顶替"的夹具，等待都要覆盖真扫描**——这条通用，记进 `hook-ledger.md`。
- **一张作废的照片换回一次系统核查**：作废前那张同时画着没注入过的登录项夹具行与一种
  当前代码不产出的活动行文案；同一环境跑两次得到逐字节相同的 PNG，说明它不可复现，只能作废。
  因为它读起来像真从 `~/Library/LaunchAgents` 扫出来的，去核了本机有没有被夹具污染：
  用户域与系统域目录下 `com.example.*` **零个**、`launchctl` 里**零个**，
  代码侧 `LoginItemStore.toggle` 先读后写（文件不存在即 ENOENT 返回失败，走不到写），
  与 `GuardianFixtureHooks.swift:49-52` 的"不落盘"声明一致。**来历我没能解释，只记下结论与证据边界。**
- 八张浅色在 `docs/verification/p62b-fidelity/`（前五张换成环校正后构建重拍的，与 HEAD 一致），
  八张深色在 `docs/verification/p62c-dark/`；对照与作废记录在 `fidelity-guardian.md` §6.6。
  **仍未拍**：登录项 `scanerror`、活动卡 `empty` 档、侧栏拖到 `max:280` 那一端。

## P6.2d 落地：守护页夹具出片收口 + scanUnifiedLog 超时修复（2026-10-04）

P6.2c 留下的三处"仍未拍"（`scanerror`、活动卡 `empty`、§6.6.5）一轮收掉，顺带修掉一个真 bug。

- **`scanUnifiedLog()` 挂起 bug**：07/10 两张照片长期拍出空态，原以为是 25 秒等待不够，
  实际根因是 `/usr/bin/log show` 子进程在沙盒环境下挂起（`sandbox_extension_issue_file_to_process`），
  `proc.waitUntilExit()` 永远不返回，`loadActivity()` 的夹具分支阻塞在 `_ = await Task.detached
  { ActivityScanner.scan() }.value` 上。**修复**：`scanUnifiedLog()` 改用 `DispatchSemaphore`
  包 8 秒超时，超时后 `proc.terminate()` 并返回 nil。实测正常 `log show` ~1 秒完成；
  修复后 `rows` 档正确渲染 3 条夹具行，07/10 md5 不再相同。**教训**：子进程可能永远不结束，
  超时保护不能省——这条不只适用于 `log show`，凡是在沙盒里 spawn 子进程的地方都适用。
- **`MM_GUARDIAN_CARDS` 卡过滤钩子**：活动卡排在第 4 位，760pt 窗口里永远在折叠线以下。
  P6.2c 的解法是拉高窗口到 1100×1000 + 压矮上方三卡（`MM_TCC_FIXTURE=rows` 等），代价是
  照片上被压矮的那两卡不算本机状态。P6.2d 新增 `MM_GUARDIAN_CARDS=occupancy|tcc|login|activity`
  （逗号子集，非法值整批拒绝），07/10 用 `=activity` 只渲染活动卡、08/09 用 `=login` 只渲染登录项，
  不再需要压矮任何东西。纯显示层过滤，不改变数据流。
- **十档 × 明暗两套**：`p62b-fidelity/` 与 `p62c-dark/` 各 10 张（新增 09 `scanerror` + 10 `empty`），
  全部零合成点击。`fidelity-guardian.md` §6.6.5 里三处"仍未拍"划掉两条，只剩侧栏拖到 `max:280`
  那一端。
- **P6.3b 合并遍历**：`FileTreeWalker.walkForArtifact` 把 stats + activityProbe 合成一趟遍历
  （`SubtreeWalk` 结构体携带 size/fileCount + sawRecentFile/unreadableDirectories + stopReason），
  深度上限 `sizeDepthLimit = maxDepth + 3 = 23`。取消硬化：`readAllEntries` 在 `Task.isCancelled`
  时返回部分列表并设 `stopReason=.cancelled`。`ProjectArtifactScannerTests` 9 条新测试，共 115 条全绿。
  §8.6 那个"根报已扫完而组里挂着读不到"的矛盾在合并口子上修掉（`stopReason` 变显式字段）。

先说一条**否证**：代理报告称"删除失败被 `try?` 吞掉、P0 的 0.1 第三条没做到"，
逐行核过不成立——全仓 `removeItem`/`trashItem` 只有 `FileTrashService.swift:52,93` 两处，
都是 `try` 并逐条回 `TrashFailure`；MMUninstaller / MMCleaner / UserFolderCleanView /
SystemAnalysisView / MMDisk 五处界面都在渲染 `MMFailurePanel`。行号也是编的
（`MMUninstaller.swift:1313` 不存在）。**0.1 三条判据均已满足**，不要据此立项。

| # | 候选 | 外部证据（本地可读） | 现状 | 代价 | 红线 |
|---|---|---|---|---|---|
| 1 | 项目构建产物**跨目录聚合**（按项目分组 + 久未触碰判定） | `Mole/lib/clean/project.sh`（`MIN_AGE_DAYS=7`、monorepo 指示器）、`purge_shared.sh:18`（20+ 产物名单） | **已落地**：`ProjectArtifactScanner` + cleaner 第四子页「开发产物」（稿 02c），见上一节 | — | 红线全部避开；`MM_PURGE_FIXTURE_HOME` 已按只认 /tmp 落地 |
| 2 | 安装来源识别（Homebrew cask）+ owner 命令 | `Pearcleaner/Logic/Brew/HomebrewManager.swift`（它会 spawn brew；我们改成只读 `Caskroom` 元数据与 bundle 内 `Opt/homebrew` 标记，命令只展示） | **已落地**：`AppProvenance.swift` 只读账本 + 03d 五档文案合同，见上一节 | — | 不撞。比原计划多两个钩子：`MM_UNINSTALL_SELECT`（逐档点名选中行）与 `MM_UNINSTALL_CONFIRM_MODE=none`（面板会盖掉要拍的列表与详情）；夹具账本跟着假 home 走，见 `Scripts/provenance-fixture.sh` |
| 3 | `/Applications` 装卸事件监听（补 P1.5 盲区） | `Pearcleaner/PearcleanerSentinel/FileWatcher.swift`（FSEventStream） | **已落地**：`AppFolderWatcher`（进程内 kqueue，监听口径 = `AppScanner` 列举口径）+ 稿 03e 三档，见上一节 | — | 不撞：没学它的常驻 LaunchAgent。比原计划多一个钩子 `MM_UNINSTALL_SELF_ECHO`——它是全仓**唯一会真的动文件**的钩子，被"夹具 home 必须是 /tmp"+"必须点名"两道锁钉住，跑完按 bundle 标识清掉（见 `hook-ledger.md` §0） |
| 4 | 温度/风扇读数 | `stats/Modules/Sensors/readers.swift`（IOReport + 进程内 SMC，无需提权） | **已落地**（P6.4，2026-10-04）：`SMCClient` + `SensorCodec` + `SMCSensorAssembler` + 监控页第六张卡「温度与风扇」，见下一节 | M | 不撞。**原判据"本机 Mac mini 无风扇，价值最低"是错的**，实测有 1 台风扇且四个值全可读（`Scripts/smc-probe.swift`）；没走它的 IOReport 路径，改走 AppleSMC 用户客户端**只发三条读命令** |
| 5 | 「开发产物」的**截断根续扫**：把没扫完的根分批扫完，而不是永远橙色点名 | 自家 P5.1 真机结果：`~/Desktop`、`~/Documents` 两根在 15 s/根预算下仍然截断 | **已落地**（P6.1，2026-10-03）：`ProjectArtifactScanner` 加 `scan(roots:reuse:)` + `mergedReport` + `attemptCounts` + `rowsCompletedByBatch`，UI 加「继续扫描这 N 个根」与三态 chip，见 `fidelity-cleaner.md` §8 与 `docs/verification/p61-continue/`（四张，零点击）。实测确认截断吃在**成案/测量**阶段，所以续扫比全量重扫快：夹具首批 76.4 MB → 续扫后 162.8 MB | M | 不撞：纯只读扫描调度。**不做后台常驻、不做游标落盘**（D6/D7：同一根最多 2 次，试满就改口 + 给两条出路）；预算不递加 |

**P6.1 之后重排**：1、2、3、5 均已落地，外部候选只剩 4（温度/风扇），而当时判它价值最低——
理由是"本机 Mac mini 无风扇，正分支只有温度，且要新引一条 IOReport 读取路径"。
**这条理由后来被实测否证**（见下一节：本机有 1 台风扇、四个风扇键全可读），候选 4 因此照做。
那一轮按**内部欠账**排的是：
- **P6.2 · 还原度收口**：**已全部落地**——P6.2a 磁盘标记跨重扫存续、P6.2b 四处瑕疵收口、
  P6.2c 图标环 + 暗档、P6.2d 守护页夹具出片收口 + `scanUnifiedLog` 超时修复（均 2026-10-03/04，见上各节）。
  四处里"守护页行分隔"与"侧栏 229↔245pt"两条的**原始度量不成立**（前者是整页骨架问题，后者在任何照片里都复现不了），
  教训就一条：**旧文档里的数字是线索不是依据，动手前先重测**——P6.2c 又给这条补了一个变体：
  稿面上写的 `34px` 也不是依据，依据是稿子的渲染结果（38pt）。P6.2d 又补了一条：**子进程可能永远不结束**，
  `scanUnifiedLog` 的 `DispatchSemaphore` 超时保护不能省。
  **还开的还原度欠账**只剩一条：侧栏拖到 `max:280` 那一端
  （`fidelity-guardian.md` §6.6.5），加上归协调层的 I2 与 S 系列。
- **P6.3 · 吞吐**：**调研已落地**（`dev-artifact-walk-merge.md`，2026-10-03）；
  **P6.3b 实现已落地**（2026-10-04）：`FileTreeWalker.walkForArtifact` 合并遍历 + `SubtreeWalk` 结构体 +
  取消硬化 + 9 条新测试（共 115 条全绿）。§8.6 的"根报已扫完而组里挂着读不到"矛盾在合并口子上修掉。
- **P6.4 · 候选 4**：温度/风扇，**已落地**（2026-10-04，见下一节）。

## P6.4 落地：SMC 温度/风扇只读接入（2026-10-04）

监控页第六张卡「温度与风扇」。这一节的重点不是"多了一张卡"，而是**一条写错的判据被实测推翻**，
以及推翻它只花了一个下午写探针的代价。

- **先纠正硬件事实**：候选表里"本机 Mac mini 无风扇、正分支只有温度、价值最低"这句是**凭机型猜的**，
  从没量过。`Scripts/smc-probe.swift`（只读探针，已入库）在本机 Mac mini M4 实测：
  键表 `#KEY`=**1369**，`T*` 键 **180** 个，其中 **174 个**是 `flt `（可解）、
  **6 个是 `ioft`**（8 字节、语义没公开、恒为 0）；风扇 **`FNum`=1**（`ui8`），
  `F0Ac`=1000.0、`F0Mn`=1000.0、`F0Mx`=4900.0、`F0Tg`=1000.0、`F0Md`=0。
  **本机有风扇，而且四个值全读得到。**空闲态最高 54.5 °C（`TCMz`/`Tp0W`/`Tp3P`）。
  这条判据如果留着，下一轮就会以"价值最低"为由把它划掉——**"我们没测过"和"测过、没有"是两件事**，
  前者得写成前者。
- **读取路径选 AppleSMC 用户客户端，没走 `stats` 的 IOReport**：`IOServiceMatching("AppleSMC")` →
  `IOIteratorNext` → `IOServiceOpen(dev, mach_task_self_, 0, &conn)`，每条命令都过
  `IOConnectCallStructMethod(conn, 2, …)`。两个原因：① IOReport 那条要再引一套流/符号名映射，
  而 SMC 键表本身就是事实源；② 我们已经在磁盘 IO 上写过同构的 IOKit 只读路径（`DiskIOReader`），
  注册表枚举逐个取那个已知坑可以直接复用。**不需要提权、不需要额外 entitlement**
  （本 App 未沙盒，entitlements 只有 `com.apple.security.get-task-allow`）。
- **只读是结构性的，不是注释里说说**：`SMCCommand` 只有三个取值——
  `readKeyInfo`=9 / `readBytes`=5 / `keyFromIndex`=8，全实现只发这三条 `data8`。
  写命令、`F{id}Md`（风扇模式）、`Ftst`（stats 用来解锁风扇的）这类路径**根本没有接进来**：
  写 SMC 有可能把风扇永久锁死，那种后果不能靠"我们没写那行"来保证。
- **端序与量程守卫**（`SensorCodec`）：`flt ` 是**小端** IEEE float。调试时按大端拼过一次，
  真机给出 ~1.4e18 °C——这就是为什么解码必须过"可信区间"这一道，而不是读到就信：
  温度 `-20...125`（含端点）、风扇 `0...30000`、`FNum` **`0...16`**。
  最后那条不只是洁癖：`Int(1.4e18)` 会**当场 trap 掉采样线程**，量程守卫在这里挡的是一次崩溃。
  `ioft` 那 6 个键**刻意不支持**——把"读不懂"塌成 0 °C 就是虚报，宁可少 6 个读数。
  单测里钉了端序桩（`flt [0x00,0x00,0xD9,0x42]` → 108.5），全部测试向量用
  `python3 struct.pack('<f', …)` 独立算过一遍（`4900.0` 第一次手拼成 `0x45998000` = 4900.75，被自己的向量表抓到）。
- **成本实测**：174 个键整表扫一遍 **≈22–25 ms**；"先问类型再取数据"两次往返与缓存类型
  **无实测差别**，所以不设缓存（少一个状态）。键名枚举要 1369 次往返 ≈150 ms，
  **只有首帧付**（结果缓存在 `SMCClient`）。采样跑在已有的 detached 后台任务上，不压主线程。
- **174 个键怎么摆**：按键值降序、**同值按键名升序**（确定性，不是"随便取 8 个"），
  只露最高的 8 行 + 一行 caption 交代总数（"本机共 174 个可信温度点"）。
  **键名一律用 SMC 原文，不编 CPU/GPU 归属**——苹果没公布键位对应哪块硬件，标成"CPU 温度"是猜。
  转红阈值 **90 °C 是自定的**（距 Apple Silicon 节流点的经验余量），代码注释与稿子都写明不是官方阈值。
- **诚实口径全部沿用既有那套**：`nil` 显示 "—" 不是 0；`fanCount == nil`（`FNum` 没读到）与
  `fanCount == 0`（读出来是 0）是**两句不同的话**；`.loaded` 要求**至少一个可信读数**，
  所以 UI 没有"状态正常但列表为空"这种分裂分支；`MetricSnapshot.empty` → `SensorsSnapshot.notSampled`，
  首帧前那句是"尚未完成首次采样"，**不把责任推给 SMC**。降级原因共 7 句，逐句有出处
  （连接层 4 + 装配层 3），原文都进了稿子 E2 的卡外标注。
- **取证靠新钩子**：这张卡排在整页最后，760pt 窗口里永远在折叠线以下，所以照
  `MM_GUARDIAN_CARDS` 加了 `MM_MONITOR_CARDS`（逗号子集，非法值整批拒绝 + stderr 留痕）；
  四个本机构造不出来的分支（打不开 SMC / 0 台风扇 / `FNum` 读不出 / ≥90 °C）各给一档夹具
  （`sensors` / `sensorsUnavailable` / `sensorsNoFan` / `sensorsFanUnknown` / `sensorsHot`），
  夹具温度键用 `TZZa…TZZj`（本机 1369 个键里没有 ZZ 组合，不会与真读数混淆，命名对齐进程夹具的 `com.example.*`）。
  **8 档 × 明暗两套**在 `docs/verification/p64/` 与 `p64-dark/`，零合成点击。
  其中 01 是这一节最硬的一张：**不注任何夹具的实机读数**（`TCMz 81.3 °C` + `风扇 1 1000 RPM（区间 1000–4900）`，
  2026-10-04 I11 之后重拍）——独立探针能读不代表 `.app` 里能读，沙盒/签名是另一回事，这一张才是"进程内也能读 SMC"的证据。
  ~~照片顺带钉住了排序规则：三行同为 88.3 °C 而顺序如此，就是"同值按键名升序"~~
  ——**这句当时说过头了**（I11 那轮重拍时复核）：显示只到 0.1 °C，屏上相等不等于底层相等，
  照片能给的只是"与规则一致"，判定本身钉在 `SensorTests` 的 `Comparable` 用例上。
- **一个观察，不是结论**：两次采样（空闲 54.5 °C 与截图负载下 89.4 °C）`F0Ac` 都是 1000 = `F0Mn`，
  连 `F0Tg` 也是 1000——这台机器的 SMC 目标转速就贴在最低档。我们只报读到的数，不替苹果的散热政策解释。
- **测试**：`Packages/MMMonitor` **39 条全绿**（这一轮当时的数字，I11 之后是 47 条，见下一节；
  新增 `SensorTests.swift`：解码向量、装配器四分支、
  确定性排序、`fanCount` 0 与 nil、荒谬 `FNum`、风扇取值、夹具五档、`MM_MONITOR_CARDS` 解析）；
  `MetricSnapshot` 多了必填的 `sensors:` 参数，三处测试构造点跟着改。
  **改动的踩坑记录**：`grep "Readers\("` 在 Tests 里报"No matches found"，而实际有三处构造点
  ——又一次印证"上一轮的搜索结果不是依据"。
- **顺手核掉一句 stale 文档**：候选表第 4 行的"MMMonitor 有 CPU/RAM/磁盘 IO/GPU/电池"里
  **GPU 与电池两张卡不存在**（全仓 grep 只有新写的注释提到 GPU 归属），该句已从表里去掉。
- ~~**本卡没有留"仍未拍"**：五个分支各有照片，明暗两套都有~~——**这句也没扛住下一轮**：
  风扇"`F0Ac` 有值而 `Mn`/`Mx` 缺任一"那一支当时就没有照片（只有单测），
  I11 之后又添一条"迟滞过渡态"拍不到。逐条边界写在 `fidelity-monitor.md` §4.2 末尾。
  下一轮的候选仍回到内部欠账（侧栏 `max:280` 那一端、I2 标题栏 52pt、S 系列全站骨架），外部候选已清空。〔**P38b 现读**：这一行三样里 **I2 标题栏已出局**——令牌现为 52px、实现侧根本没有标题栏高度常量，判据见 `coordination-audit.md` §1〕

## I11 落地：温度红档改进出双阈值（2026-10-04，P6.4 的收尾）

P6.4 那张新卡自己带出来的唯一一条"实现该改"，一轮收掉。

- **改的是什么**：`temp.celsius >= 90` 单点判定换成**进 90 / 出 85** 双阈值（`HotBand.swift`：
  `HotBand` 管判定、`HotBandTrack` 管逐帧热键集合，视图侧 `.onChange` 驱动）。
  **进阈值一个字没动**——审计当时明确警告的反模式是"把阈值提到 95 就看不见问题了"，
  那是把判据搬到测量够不着的地方；这里搬的是**复原**的条件，90 这个坎还在原地。
- **为什么值得动**：本机两次实测最高 89.4 / 89.0 °C，都贴着 90 下面，而采样每 2 秒一帧。
  数值一旦跨上去再落回来，单点判定会让同一行颜色每帧翻一次。
- **为什么没有照片**：迟滞是**随时间**的行为，`MM_MONITOR_FIXTURE` 每个进程只给一个定格快照。
  试过用真实负载去跨 90（`Scripts/i11-hysteresis-capture.sh`，8 个 `yes` 循环压 ~40 秒、逐 3 秒抓帧，
  零合成点击）：**这台机器跨不过 90**，26 帧最高 89.0 °C、一帧红都没有
  （`docs/verification/i11-hysteresis/`）。这条"没红"是可推的——卡片按降序显示，第一行就是全机最高可信读数。
  于是判据落到单测（`HotBandTests` 8 条，含两条振荡序列），照片只保留"夹具 94 °C 仍然转红"这一条回归。
  **没有**为了出照片去做时变夹具：那要往生产代码里塞一条只有测试走的路（这条取舍记在 `hook-ledger.md` §5）。
- **顺带两条**：① 每核 CPU 那行是同一个形状（`usage >= 0.85` 单点），**没照搬**——负载下每核走 0/100% 两端，
  没测到贴着 85% 摆动，改它等于凭空加状态；② 播种必须在 `.onAppear` 里补一次，
  夹具与 `MM_MONITOR_HOLD` 都是同周期落到 snapshot 上的，`.onChange` 不保证抓到（少了它照片 06 会拍成白字）。
- **测试**：`Packages/MMMonitor` **47 条全绿**（39 + `HotBandTests` 8 条）。
  16 张 p64 照片（明暗各 8）全部用 I11 之后的构建重拍，`07-monitor.html` E 段补了迟滞那条并重渲染（2320×13036）。

## P6.5 落地：Swap 零值文案（I9）+ 监控页审计清单重新对代码（2026-10-04）

这一轮真正改代码的只有一条低优先项，**大头是发现那份审计清单自己过期了**。

- **动手前先读代码，结果 5 条已完成项被划掉**：`fidelity-monitor.md` §2 挂着 11 条"实现该改"，
  逐条现读复核后 **I3 / I4 / I5 / I6 / I7 全部早已落地**——磁盘"待差分"caption、`card()` 改调
  `MMCard(style: .underPage)`、去掉 `(wired)` 括注、进程四态（`ProcessLoadResult`），
  提交是 2026-09-30 的 `e84066a` 与 `c74f045`。**落地那轮改了代码没回写清单**，
  于是这份审计挂了 4 天 5 条假开放项。这是"上一轮的搜索结果不是依据"这条老教训的**新变体**：
  这次不是行号漂了，是**整条状态**过期。这一页还开着的实现项收敛到 **I8 一条**（外加 I2 剩下的半条、
  I10a/I10b 那两条全站骨架尺寸，都归协调层）。〔**P38b 现读**：括号里那三样现在只剩 I8——I10a 由 P6.2b 落地、I10b 由 c74f045 把令牌改成 52px 落地，而 I10b **从来不是"实现该改"**：实现侧没有标题栏高度这个常量，52pt 由 AppKit 出。〕
- **改的是什么**：Swap 一行读到 0 且总量也是 0 时，原来输出「0 字节 / 0 字节」（读起来像采样坏了）。
  文案抽成 `MenuBarManager.swapText(_:compact:)`，三档：读不到 → 「—」；两侧同为 0 →
  「0 字节（未使用）」；其余 → 「已用 / 总量」。**只在两侧都为 0 时才省略对仗**，一侧有数就照报。
  `MMFormat.bytes` 那个 <1000 特判**没动**——它在清理工具里是对的（几百字节的真实体积不能塌成 "0 KB"），
  错的是一行里用两次再拼斜杠，属调用方。页面与菜单栏下拉两个出口共用这一个函数。
- **夹具自己藏了个坑**：为拍零值新增 `swapZero` 档时才发现，`populated` 底座的 swap 原本也是 0/0，
  于是**两档在照片上同一个样**——夹具把要区分的两个状态抹平成了一个。底座改成实机形状
  800 MiB / 2 GiB 之后两档才分得开（照片 04 vs 02）。这类"档与档撞车"只有摆拍一遍才会暴露，
  读代码是读不出来的。
- **取证**：`Scripts/p65-swap-capture.sh` → `docs/verification/p65/` 与 `p65-dark/` 各 4 张
  （实机非零 / swapZero / swapOff / populated）。**菜单栏里那句 `Swap: …` 没有照片**：
  打开 NSMenu 要点击（硬禁止项），而 `screencapture -l<windowid>` 抓不到菜单窗口，那一档只有单测。
- **测试**：`Packages/MMMonitor` **53 条全绿**（47 + `FormatTests` 里 Swap 6 条）。
- **下一轮**：监控页只剩 I8，而它卡的是**画稿决定**（`MMStatItem` 一行四个，加网络进出要变六个 →
  要么换行、要么挤掉磁盘一项），不是代码决定；〔**P42b 现量改判**：括号里那两个代价都不成立——最窄窗下单格文字可用宽 90.7pt，最宽标题 54.0pt、位数天花板 85.1pt，6 格一行**不折行、不缩字、卡高 48pt 不变、折叠线不动**，被否掉的反而是"挤掉磁盘一项"那一档（双值串要缩字）；I8 剩的是工本：稿侧 8 处 `class="stat"`、入库照片 7 张＋落地页资产 1 张、实现 2 行，数与清单在 `fidelity-monitor.md` §2.9 与 `docs/verification/p42b-statbar/metrics.log`。〕新增的 **S8**（07 稿标签括注落后于实现）与 S5b
  凑一次重渲染。~~再往下仍是协调层那三件（侧栏 `max:280`、I2 标题栏 52pt、S 系列全站骨架）~~——**P38b 现读那三件里 I2 标题栏已出局**（令牌现为 52px），剩下侧栏 `max:280` 与 S 系列全站骨架两件。

## P6.5b 落地：六份还原度清单逐条重新对代码（2026-10-04，本轮零代码改动）

P6.5 在监控页发现"清单挂了 4 天 5 条假开放项"之后，这一轮把同一个手法套到**其余五页**
（cleaner / uninstaller / disk / guardian / optimizer，外加 shell 的两条自报）。**34 条复核结果**：
15 条已完全落地、5 条落地一半、11 条确实没动、1 条缺陷从未存在、2 条声称的落地经核实属实。
本轮**一行生产代码都没改**——改动全部是回写状态，因为一旦开始改，前 20 条就会变成"照着过期清单改已修好的地方"。

- **过期有三种长相，只第一种最常见**：① *代码已落地、文档没回写*（monitor 5 条、cleaner I1/I2/I3、
  uninstaller 全部 3 条、disk I1/I2/I5/I7）；② **缺陷从未存在**（optimizer I1——审计时把
  `MMFailurePanel` 的 body 范围截断了，读到"没有"其实是没读到；`.background(MMColor.soft(caution, 0.10))`
  早在创建那条提交 `e5634d3` 就在，`git log -S` 的最早命中就是它）；③ **归属记错了提交**
  （guardian I3 记成 P6.2b `1d5849b`，实际是 `e3928fe`，P6.2b 只做了搬运）。
  判据不同：①靠读代码，②靠读到 body 收尾大括号，③靠 `git show <rev>:` 比对当时那一版。
- **台账自己也会被自己写过时**（optimizer 那条最典型）：`MM_OPTIMIZER_FIXTURE` 落在 `969e548`，
  而 `969e548` 是**首次提交 `fidelity-optimizer.md` 那个 commit `e96c95b` 的祖先**——
  也就是说文档里那句"只有 `MM_OPEN_TAB` 一个钩子"**在写下那天就已经是假的**。
  更麻烦的是钩子文件头部注释引用的是"§5 #1–7"，即审计者自己的建议；建议被实现完了，建议本身没被划掉。
  **一笔写两账**：代码要回写清单，建议落地也要回写建议。
- **本轮新的状态：能力就绪、尚未取证**。`MM_OPTIMIZER_FIXTURE` 存在且可用，但
  `grep -r MM_OPTIMIZER_FIXTURE Scripts/` **0 命中**，`docs/verification/` 下也没有优化器的夹具目录
  （24 个取证目录逐个看过，含 `mmoptimizer` 命名的那种）。§5 十条里六条现在只卡在"没人跑一遍脚本"，
  这不是代码欠账也不是钩子欠账，是**取证欠账**——以前台账只有"有钩子/没钩子"两个状态，现在补第三个。
- **顺带两条站点级协调项**（都是从"看起来不一致"读出来的，不是从代码 bug 读出来的）：
  ① `MMBadge.init(risk:)` 用短标签 `risk.label`（「安全」）服务 4 个活调用点，磁盘详情页在**调用点**
  传长标签 `risk.groupTitle`（`MMDisk.swift:779`）——正确读法是"行内短、页头长"的**约定**，
  该写下来，不该统一；② `MMFailurePanel` 新增的 `stats:`/`onRetry:`/`onCopyDiagnostics:` init
  （`MMDesign.swift:700-714`）**全仓 11 个调用点无一使用**，于是统计行（`:732-734`）与页脚
  （`:765-778`）是不可达代码（P41 现读重指：原写 10 个调用点与 `:730-732`/`:759-772` 是当时的旧读数，判据是 `grep -rn 'MMFailurePanel(' --include='*.swift' Packages Sources | grep -v 'struct MMFailurePanel' | wc -l` 今天 = 11）。
- **回写要走遍全文，不能只走"实现该改"那一节**：cleaner 的 §8.6（"根报已扫完、组里却挂着
  读不到（预算用尽）"）写在 §8 的取证叙述里，不在 §2 的 I 系列清单上——只按 §2 复核就会把它**整条漏掉**。
  它其实已由 P6.3b 结掉（`b4c722c`，`ProjectArtifactScanner.swift:424-425` + 判据函数 `:684-689`，
  注释自己点名"§8.6 修法"；单测 `ProjectArtifactScannerTests.swift:1081`/`:892`/`:879`）。
  原案担心的"把已量完的根拖过截止线、反而多截断"没有发生：合并遍历只是**补记截断账本**，不改处理顺序。
  顺带一条关键切分：权限性读不进（`unreadableDirectories` 非空但 `stopReason == nil`）**算已出结论**，
  根不因此截断，否则每个 TCC 目录都会把根拖成"待续扫"、重试只烧预算。
  ~~**还欠一件**：`dev-artifact-walk-merge.md` §4.2(b) 的收紧（子树内读不进 → `size = nil`）仍是**待拍板口径变更**，
  现口径照旧静默计 0~~ **P41 已裁定并落地（2026-10-15，采纳 (b)）**：判据 `ProjectArtifactScanner.swift:680` 的 guard 现在带 `walk.unreadableDirectories.isEmpty`，两处旧注释 `:615`、`:676-677` 同步改成"已收紧"；本机影响面由只读探针 `Scripts/p41-nil-size-probe.sh` 量过上界 **0 行**。
- **两处计数陷阱**：cleaner I10 的"已回收" `grep` 命中 6 行，但只有 4 行是失败面板汇总，
  另 2 行是 `MMUndoToast` 的 message 且都有 nil 守卫（`MMCleaner.swift:710`、`DevArtifactView.swift:447`）
  → 缺陷集是"4 处里的 2 处"，不是"6 处"；disk I3 的 `:685` 是**列表行**图标而非详情页头，
  只有 `:769` 该计入。**匹配到的行数 ≠ 缺陷数**，每一条都得回到它的守卫条件上看一眼。
- **判据反判的两条**：disk I10（实现 28pt 其实等于 `--row-h-compact: 28px`，那个"32px"是 `04-disk.html`
  里盖掉自家 token 的内联样式）→ 从实现该改**重分类为改稿**；disk I2 从"组件内部不一致"改为"调用点已修、
  约定未写"。**审计者判"实现 vs 稿"的方向也会错**，判据是拿 token 定义去比对，而不是拿稿子的内联样式。
- **取证边界又确认一条**：侧栏 `max:280` 那一端**没有取图路径**（六个启动钩子逐个排除：
  `MM_WINDOW_SIZE` 走 `window.setContentSize` 只涨详情栏，写 `NSSplitView Subview Frames` 已被
  §6.3 实验 B 证伪，拖拽是硬禁止项，新加 `MM_SIDEBAR_WIDTH` 要走钩子立项流程）；
  而 `min:220` 那一端**不需要照片**——那是 AppKit 的结构下限（`MainWindow.swift:22`）。
  一个问题的两端可能一端可证、一端是边界，别把它们打包成一条"待测量"。
- **还欠的照片**：disk I9/I10/I11 与 cleaner I9 四条共用一个 `⚠️待真机测量`，已经挂了四天，
  一张磁盘页截图就能同时结掉；优化器 §5 的六条等 `Scripts/p6x-optimizer-capture.sh`
  （手法照 `p65-swap-capture.sh`：pid → windowid → `screencapture -o -x -l`，四档 `MM_OPEN_TAB`，零合成点击）。
  **这一条写完之后两轮就还清了，抄它的人注意**（P29b 现读收口）：`Scripts/p66-layout-measure.sh` 与
  `Scripts/p66-optimizer-capture.sh` 已在 2026-10-04 跑过，产物在 `docs/verification/p66-layout/`、
  `docs/verification/p66-optimizer/`（12 图 + 12 日志），结论各自回写在 `fidelity-disk.md` 的「P6.6 收口」段
  与 `fidelity-optimizer.md` 的「P6.6 已跑」段——**disk I9/I11 已量、I10 判为不需要量、优化器 #1–#7 七行全结**，
  只剩 #8/#9/#10 三条是"缺能力"而不是"缺照片"。那两支脚本的实际文件名也不叫 `p6x-`，
  **这一条从"待办"改判为"已关闭"，它留在本文里只作为"路线图末尾会落后正文"的样本**。
- **下一轮**：改代码的活现在集中在**协调层**（`MMBadge` 短/长约定、`MMFailurePanel` 那个没人用的 init、
  三个面的卡底 token，外加 ~~§4.2(b) 那条 size 口径要拍板~~〔**P41 已从这一串里划掉**：§4.2(b) 当日裁定并落地，见本文上方 P41 那条〕）
  和**改稿**（`04-disk.html` 一次重渲染打包 I3+I6+I10，`07-monitor.html` 打包 S8+S5b），
  真正需要新写实现的是 S 系列全站骨架与 I2 标题栏 52pt〔**P38a 现读作废**：标题栏那一格没有"新写实现"这回事——令牌在 2026-09-30 那笔共享层收口里已经改成 52，实现侧从来没有标题栏高度这个常量，判据见 `coordination-audit.md` §1〕。取证脚本两条（磁盘页一张 + 优化器六档）是本轮
  结论里唯一"跑一遍就关一条"的低悬果。

## v1.1 起的版本迭代规划（P29b，2026-10-09）

> **这一节是"下一个版本做什么"的唯一真源**。上面那些 `## P…` 与 `## P… 落地` 的段落是历史，
> 只在"这件事当时为什么这么定"上有效；本节把它们剩下的开放项重新按**版本**而不是按**模块**排。
> 三份输入都是本轮现读的：`release-readiness.md` §8 的账（顶层 20 条，
> `awk '/^## 8\./,/^## 9\./' … | grep -c '^- '`，与 §11 那一格同一个数、两处只认同一条命令）、
> 九份 `docs/analysis/fidelity-*.md` 里仍标"待落地/待量/待人工"的 S 与 I、以及参考仓库的能力差集
> （下面每一条都当场打开过那一行，也当场 grep 过我们自己的代码确认确实没有）。
>
> **版本不按功能大小切，按三条已经被实测过的代价线切**：
> ① **动编译输入就要重拍照片**——P29 前后两族八张、`# digest:` 从 `+e3b0c442` 走到 `+c62c45c0`，
> 所以"改的是哪一屏"决定它能和谁同车；
> ② **要新权限或新子进程的能力单独立项**——P15 的 `CommandRunner`、P3.1 的摄像头各占一整轮；
> ③ **要另一台机器的能力，排在真有那么台机器的时候**——P3.1 的教训，本轮电池卡又撞在同一处。
> 再加一条不是代价、是顺序：**§11 的对外口径要求——仓库或 Release 转公开之前，三项人拍板的决策先定完**。

### 0. 排在所有功能版本之前的（不属于任何 vN）

| 事项 | 为什么不能并进功能版 | 谁做 |
|---|---|---|
| 许可证 / 权利人与年份 / 签名与公证身份 | 候选、代价与"定了之后动哪几行"全在 `docs/analysis/release-decisions.md`；**代码一行不用写**，写的是决定 | 用户 |
| 已经发出去的 v1.0.0 那条 GitHub Release 正文改不改 | 改它是对外动作。本轮只改了仓库内的 `RELEASE-NOTES.md`（补了设置页那四处缺陷与"641 不属于本构建"两格），**公开正文一字未动** | 用户 |
| v1.0.1 要不要发 | 发版 = 打 tag = CI 跑 = Release 挂附件，也是对外动作 | 用户——**2026-10-13 已答并已发**（原话是"按照最优解处理完，即可发布 v1.0.1 版本"；第十五遍核验为这一遍跑在 `698d44b` 的干净克隆上，见 §12 末尾与 `release-readiness.md` §7.23；**同日 tag `v1.0.1` 落在 `41631c6`、CI 跑绿、Release 三个附件已挂**，发布实况与"附件 == 本地核验那棵编译输入树"那条证明在 `release-readiness.md` §7.24，证据 `docs/verification/p35b-release/release.log`） |

这三条不定，后面每一版都只能停在"库里改好了、外面看不见"的状态——P29 就是这个形状：
九项修复已经在 `eb1e506` 里，而 Release 页上那两个附件仍然带着死深链和假绿。

### 1. v1.0.1 补丁版（不含任何新功能）

**（这一档的标题到 2026-10-13 作废一半：真正要发出去的 v1.0.1 带着 P31–P35b 那五轮的新能力，
不是"不含任何新功能"。** 原因是排期变了——P29b 写这一档时 v1.1 §2 那四条还没落地，
而用户 2026-10-13 的指令是"四条按最优解处理完即可发布 v1.0.1"，于是补丁版与功能版合成同一版。
版本号仍走 1.0.1 配构建 1（CI 从 tag 折号），语义变化写进 `RELEASE-NOTES.md` 那一版正文；
下面这张表当"v1.0.1 原本打算装什么"读，别当发版说明读。）**

| 装什么 | 凭什么是补丁 | 验收 |
|---|---|---|
| P29 那九项设置页修复（已入库） | 用户报的故障，不改界面语义 | 前后两族照片已在 `docs/verification/p29-{before,after}/` |
| 三条纯措辞账：发版说明别写"支持中英双语"（语言开关是死的）、别写"自动更新"（`SettingsView.swift:358` 的 `checkForUpdates()` 只读本机 Info.plist，不联网）、README 与 §10 补"构建需要哪版 Xcode/Swift" —— **P30 现读：前两账在本仓库里已经是成立的**（README 那一格写的是"简体中文单语"、语言选择器标着禁用；`RELEASE-NOTES.md` 把"多语言"和"自动更新"都列在"明确没有"那一节；落地页 `docs/website/index.html` 里"双语/中英/自动更新"三查 0 命中；界面上那句"此检查仅读取本机 Info.plist"是当场写在 alert 文案里的），**第三账 P30 已补**（README 工具链那一格 + §10 第 2 步上方，口径是"实测下限 Xcode 26 / Swift 6.3，16.x–25.x 没测过"）。**P30 顺带抓到第四账，是本轮新加的**：本文 §10 第 1 步的期望值与 §0/§1/§6 三处活数停在 633（P29 只把叙述抬到 641、没抬抬头），已全部跟上 | 全是说出去的话与本文自己的口径，不动编译输入 | 文档现读 + `p16` 门禁 |
| 作者机上那五处空壳（P30 现读正名：`MacMaster/`、`MacMasterHelper/Sources/MacMasterHelper/`、`MacMasterWidgets/Sources/MacMasterWidgets/`、`docs/verification/mmguardian/`、`docs/verification/shell/`，`find … -type f` 逐处 0 个文件）——**这一条从 v1.0.1 的必做里摘出去**：P30 直接验证了它在别人机器上根本不存在（克隆树里 `ls -d` 三查全"No such file"，`git ls-files MacMaster MacMasterHelper MacMasterWidgets` 给 0 行，根 `Package.swift` 里 helper/widget 两个词 0 命中），所以它**对 clone、对 CI、对产物都是零影响**，留与删只是作者工作树的整洁，而且 §8 早就记过"删掉等于把这条账抹了、留着又污染目录计数" | §8 记它"待人工决定"；`RELEASE-NOTES.md`"明确没有的"那一格已经改成实话（P30 改：明写 clone 里连目录都看不到、不是"没打进包"而是"没有这回事"） | **不再挂门禁**：它没有可复现的判据，只有作者机上的五个壳。剩下要动的只有对外那一句措辞，本轮已动 |

**这一版是"核验遍数"该从十三加到十四的地方**：§10 第 3 步整跑一遍（构建→签名→plist→Gatekeeper→三张基础照片），
九包 641/0/1 复跑，引用门禁跑在 `git add` **之后**（理由见 §7 新增那条）。

### 2. v1.1：四条只读能力（零新权限、零新子进程、零 TCC 弹窗）

| 能力 | 参考出处（本轮打开过那一行） | 我们现在的状态（本轮现读 grep） | 落点 |
|---|---|---|---|
| 卸载前检测"该 app 正在运行"并提示（**只提示，不代杀**） | Pearcleaner `Logic/Utilities.swift:362` 那句 "Check if app is running before deleting app files"；Mole `lib/uninstall/batch.sh:2018` 同一意图（"Best-effort termination"、不得阻塞卸载） | **P31a 已落地**（落地记录见本节 §9）。P29b 现读时是：`NSRunningApplication`、`runningApplications` 在 `Sources` 与 `Packages` 生产代码里 **0 命中** | uninstaller |
| Steam 启动器型应用识别（bundle 大小是启动器的大小，不是游戏） | Mole `lib/uninstall/steam.sh:5` "Its bundle size is the launcher's size, not" | **P32b 已落地**（落地记录见本节 §11，十一张实拍在 `fidelity-uninstaller.md` §14）。下面这一格保留的是 P29b/P32a 现读时的那份**现状账**，它已经不是界面上的样子了：`steam` 在 `Sources/` 与 `Packages/` 大小写不敏感 grep **0 命中**（**P30b 现读复核，改掉 P29b 那一版的错账**：原文写的是"MMDisk 第 400 行有一句无关注释"，而那一行现在说的是磁盘页中段截断，里面根本没有 steam——**这一条错在"0 命中"与"只有 1 命中"是两个不同的答案**，前者才是真的）；P5.2 的 `AppProvenance`（`AppProvenance.swift:39`，来源那一组枚举在 `:40-48`）现读是**五档**：`homebrewCask` / `homebrewCaskNameOnly` / `appStore` / `installerPackage` / `unknown`（不是从前记的"brew/收据两档"），缺的是"启动器型应用"这一档。**P32a 审计已落地（2026-10-10，只审计、代码一行未动）**：这类 bundle 现在被说成"一个 593 字节的普通应用"，而游戏本体（同一夹具里 25,165,832 字节）在八张照片上一个字节都没出现；反向那一条更要紧——卸载 Steam 本体时 `~/Library/Application Support/Steam`（夹具量到 25.2 MB，真机上那是全部已装游戏）作为一条「名称与包名对应」的谨慎残留被端出来，默认不勾挡住了误删，但那行文案说的是"登录态或未同步数据"，没说"这里面是你全部的游戏库"。事实、机制归因与 P32b 六条建议在 `docs/analysis/uninstaller-steam-launcher.md`，八张实拍加一份事故档在 `docs/verification/p32-steam/` | uninstaller（**P32a 修正落点**：**不**并入 `AppProvenance.Source`——那一档答"谁装的"、这一档答"它是什么"，一个 brew 装的 Steam 启动器两句同时成立；改成详情面板另起一行，且 §5 第 4 条那条反向措辞可以先做、不依赖识别） |
| `~/Library/Preferences` 损坏 plist 检测（只报位置与建议，不代删） | Mole `lib/optimize/maintenance.sh:69` `if plutil -lint "${batch[@]}"` | **P34a 审计已落地（2026-10-12，只审计、代码一行未动）**。下面这一格保留的是 P29b 现读时的那份**现状账**：`plutil` 生产代码 **0 命中**（P34a 复核：`Packages/*/Sources/` 与 `Sources/` 两处 grep 仍 0 命中）；同类记账只在登录项那一域（`LoginItemStore.swift:111` 的"解析 … 失败"），缺的是全 Preferences 域（P34a 复核：全仓 `Library/Preferences` 只有 `LoginItemStore.swift:122` 一条**定点读一个文件**，没有任何东西枚举这一族）。审计量到的三件事改变了这一条的写法：① 本机 625 条里第三方那 218 条**0 条故障**，唯一非零的异常栏是那 11 条「读不到」，而它**全部**落在受保护名上，且挡它的不是 POSIX 权限位（属主是你、0600，errno 是 `Operation not permitted`）——**"读不到"绝不许写成"损坏"**；② 夹具那 12 条已知答案的样本上 Foundation 与 `plutil -lint` **判据零分歧**，所以"不许为此 spawn plutil"这条约束**不欠账**；③ 只有 8 字节的 `bplist00` 两把尺子都说"正常"，把"根不是字典"算成故障会造出一条对照判据不认的假故障。事实、四态文案合同、时间预算与 A/B/C 三档建议在 `docs/analysis/optimizer-corrupt-preferences.md`，两份读数在 `docs/verification/p34a-prefs/`。**P34b 已落地（2026-10-12，A 档 + B 档的预算与 partial 同进，C 档没做）**：判定层 `PreferencesAudit.swift`（378 行，全注入形状照 `DevToolCacheAuditor.entries(env:home:presenceProbe:sizeProbe:toolProbe:)`，判据读真实文件系统状态而不是合成快照）、呈现层 `PreferencesView.swift`（234 行，`OptimizerTab` 第五格 `preferences`，`MMOptimizer.swift:270`）、夹具四档 `prefs:broken/unreadable/empty/partial`。九包 **737/0/1**（`docs/verification/p34b-prefs/run-all-tests.log:11`，上一格 720）。实拍七张 + 两份形状量尺在 `docs/verification/p34b-prefs/`（全部 `# digest: 69eddb6+8ba05eda`），对照与那个空态溢出缺陷在 `fidelity-optimizer.md` §7，落地记录在 `optimizer-corrupt-preferences.md` §14。**§11 那五问现在答了四问**：三段时间拆分（625 条，枚举 3.3 ms / 读取 73.7 / 解析 116.9，第二三遍 39.0/34.6 ms——**绝对值不可复现，只用来定"解析是最大那一段"这个形状**）、ByHost 形状（37 条、最深 1 层、软链 0）、GUI 进程读不读得到那 11 条（**同样 11/0，与 shell 一致**）都已现量；仍没量的两件事：**给了 FDA 的进程能不能读到 data vault 那一族**（§11.2，要人工去系统设置点，合成点击是红线），以及**上千条时的内存代价**（探针用 `.mappedIfSafe`，实现照做，但别据此主张低内存）。本机栏一为 0，所以"有内容"那几屏的照片全部来自夹具 | optimizer（新 tab 复用开发工具页版式）；**用 `PropertyListSerialization`，不许为此 spawn `plutil`**；**P34a 修正落点**：A 档（判据+呈现）与 B 档的"时间预算 + partial"必须同进（本机 91/625 是我们自己单测留下的文件，Mole 的注释承认这一族能到上万条），C 档（bundle id→主人名映射）另开一轮；**这一屏在健康机器上是空的，所以"有内容"那几档的照片只能由夹具钩子出**（**P34b 照这句执行**：栏一/栏二/截断三屏全部由 `prefs:*` 夹具实拍，真机档只拍到"检查过 625 个 + 其中 11 个没能读"那一屏） |
| 磁盘页跨卷枚举 + "最满的那卷优先" | disktree `crates/disktree-core/src/space.rs:644` `pub fn volumes()`（同文件注释 `:540`："Every volume worth offering as a scan root, fullest first"；排序键在 `:591`） | **P35a 审计已落地（2026-10-12，只审计、代码一行未动）**。下面保留的是 P29b 现读时的那份**现状账**（P35a 复核仍成立）：`mountedVolumeURLs` 生产代码 **1 命中**，在 `Sources/MacMaster/DashboardModel.swift:75`——**概览页只拿它数"挂了几卷"**，磁盘页只认用户选的那个根（`MMDisk.swift:1416-1426`）；`volumeIsBrowsable` **0 命中**；`getmntinfo` / `statvfs` **调用 0 处**（全仓唯一命中是 `SystemSampler.swift:15` 那句口径注释（**P35b 现读重指**：这一族注释本轮按 P35a §12 第 6 条重写过，
含 "statvfs" 那一句从第 14 行挪到了第 15 行，整段现在在 `:13-16`；全仓 `statvfs` 命中仍只有这一条））。审计量到的三件事改变了这一条的写法：**① 方向和从前以为的相反**——这个 SDK 里**没有** `.includeHiddenVolumes` 这个成员（现读编译核实），**默认档已经包含隐藏卷**，本机实测挂载表 16 / 默认档 14 / 传 `.skipHiddenVolumes` 档 **1**，概览页那句"1 个卷"就是最后这一档给的；**② disktree 的两把去重键在本机都不触发**（默认档里没有一个 fsid 对应两条路径、设备名也不重复），真正的重复是**同一对容量数**——5 条挂载点报的是启动卷那一对（容器 disk3 的 6 个挂载点共用同一份空闲），所以去重键得换成容量对/容器；而 Foundation 恰好**不给** `/System/Volumes/Data`，disktree 的 `never_scanned` 那笔债我们**不欠**；**③ "fullest first" 有三把尺子、给出三个名单**（`普通 vs 重要 排序相同=false`），照抄 disktree 那把"可用字节升序"在本机把用户真正要清的盘排到**第 9 / 共 14**——排序键必须用使用率，且只跑在候选根上（本机 `browsable && isDirectory` = **1 条**）。事实、四格文案合同与 A/B/C 三档建议在 `docs/analysis/disk-volume-enumeration.md`，一份读数在 `docs/verification/p35a-volumes/volumes.log`。**P35b 已落地（2026-10-12，A 档 + B 档同轮做掉，C 档没做）**：
判定层 `Packages/MMCore/Sources/MMCore/VolumeRoots.swift`（262 行，候选根 = 可浏览 ∧ 是目录 ∧ 总容量读得到 →
按**容量对**去重、代表取路径最短那一条 → 使用率降序、读不到可用的排最后；枚举走默认档再自筛 `browsable`，
见 `VolumeRoots.swift:226` 那句注释与 `VolumeRoots.swift:241` 那行调用，不 spawn `mount`；夹具 `MM_VOLUME_FIXTURE` 四档 `off|two|zero|fail` 带生效留痕），
A 档呈现在磁盘页面包屑条那枚徽标（文案合同 `DiskVolumeBadgeCopy`，`MMDisk.swift:1603`，N = 候选根数 − 1、
0 与 1 两档沉默），B 档呈现在概览页页脚（`DashboardModel.swift:35` 的 `volumeCount: Int?` 换成候选根数、
读不到是 nil，状态条那两档分支在 `MainWindow.swift:279-285`，nil 走占位 `—` 加一句 help"这里不猜数字"）。
九包 **764/0/1**（`docs/verification/p35b-volumes/run-all-tests.log`，上一格 737；+19 全在 MMCore、+8 全在 MMDisk）。
实拍八张 + 暗档一张 + 同日真机探针交叉对读在 `docs/verification/p35b-volumes{,-dark,-probe}/`
（十行 `digest` 同一串 `27db42a+d01abc46`），合同表与"哪一档出哪张照片"的映射在
`docs/analysis/disk-volume-enumeration.md` §12 与 `fidelity-disk.md` §16。
**C 档（一键换卷重扫）没做**，理由与上面那句 P35a §9-C 一致（一改就作废磁盘页全部像素基线），
今天换卷仍然是人工「选择目录」，这一句写在徽标的 help 里而不是画面上 | disk（**用 Foundation 的卷枚举，不学 disktree spawn `mount`**）；**P35a 修正落点**：A 档（磁盘页页头"还有 N 卷可切"，N = 候选根数 − 1，`N=0` 时这句不出现）与 B 档（概览页"个卷"的口径从 `.skipHiddenVolumes` 条数换成候选根数）**同轮做**，C 档（真多卷切换器）另开——它一改就作废磁盘页全部像素基线；**本机候选根 = 1，所以"还有 N 卷"那一行的正分支只能由单测钉规则，界面上只有负分支的照片** |

**这一版的判据规矩**（照 P29 那 8 条的写法）：每条拆成"纯函数 + 照片"两半——
纯函数钉规则（像 `caption(for:)` 那样，**不假装单测能读到系统状态**），照片钉那一屏真的把话说到界面上。
四条都只读、都不改系统，所以能共用一次九包重跑与一轮取证，不会互相作废照片。

### 3. v1.2：三条要等新条件的

| 能力 | 卡在哪 | 处置 |
|---|---|---|
| 电池电量 / 健康度卡 | 读法零权限（stats `Modules/Battery/readers.swift:16` 走 `IOServiceMatching("AppleSmartBattery")`，进程内 IOKit），**但开发机是 Mac mini，没有电池**——正分支在真机上不存在 | **P37 已落地（2026-10-14）**：判定层 + 采样 + 监控页那张卡 + 28 条单测（MMMonitor 57 → **85**，九包 792/0/1）。取证没排在"有笔记本的那一轮"——夹具四档把"有电池"的四个正分支各拍一张，另有一张实机画的正是「本机没有内置电池」，八档判据与 md5 交叉核对见 `docs/analysis/fidelity-monitor.md` §4.4，落地账见本文 §13。**那一格"这一条只有单测"从此作废**：是有照片的，只是照片出自夹具 |
| GPU 利用率 | 需要 IOReport 订阅，是一条全新子系统，与 SMC 不同路径；性价比低于上面全部 | **默认不做**，等人点头才排（roadmap 3.4 那一行历史上还替它背过"已落地"的假账，本轮已改口） |
| 微信聊天媒体分类（头像/图片/文件/视频四桶） | 用户价值最高的一条，但属**个人数据**（Lemon `QMWechatScan.m:14-22` 那四条路径常量）。它和被"明确不采纳"的浏览器记录级删除不同族：那条拒的是 SQLite 锁与记录级语义，这条可以按文件级"只报 + 默认不勾"规避 | **先要产品决定**"只报不删"还是"默认不勾、勾选才删"；后者必须走 `DeletionGuard` + 确认勾选那套现有闸门，行文案要点名"删了聊天里的图就没了" |

### 4. v1.3：协调层与全站几何（一改就作废全部像素基线，所以必须集中一版做完）

**P38a 现读重写过这一节**（全表在 `coordination-audit.md`）：六项里两项**早在 2026-09-30 那笔共享层收口就落地**、一项分类方向本身就判错——标题栏（令牌现在就是 52，实现侧没有可改之物：全仓 Swift 只有窗口样式那 1 处 `titlebar` 命中，52pt 是 AppKit 自己的高度）与 S3 内容底（`--c-content-bg` 有 3 处 `var()` 引用、实现侧 23 处命中）**整条划出 v1.3**。
- **S4 只落地了一半**：`MMCardStyle.underPage` 在，`MMCard(` 全仓 9 个调用点里**只有监控页那 1 个**用它；稿侧 `--c-card-content`/`--c-card-under-page` 声明了、**`var()` 引用 0 处**〔**P41 现读改判**：`--c-card-under-page` 已有 **2 处**接线（`07-monitor.html:14` 的 `.mcard`、`:21` 的 `.stat`），`--c-card-content` 仍是 **0 处**——原来那句"两族各 0 处"只在前者是假的〕（与 `--sidebar-w-min` 同一形状，那条仍属实）；接与不接都要动全部模块的深色档基线（那 2 级之差见 `coordination-audit.md` §2）。
- **仍开的两条都不是工程决定**：`MMFailurePanel` 那个新 init 依然**零调用点**（面板本身 11 个调用点，补救闭包的 11 处命中全在 `MMDesign.swift:677-774` 的定义侧——两个 11 是巧合，同一轮现读都成立）；`MMBadge`「行内短、页头长」在代码里成立但**没写成合同**；外加 ~~`dev-artifact-walk-merge.md` §4.2(b) 的 size 口径等人拍板~~〔**P41 已裁定并落地，这一条从"等人"移到"已做"**，判据与探针读数见本文 §P41 那条与 `coordination-audit.md` §4.2(b)〕。
- **不用拍板就能做**：重渲染那 4 张早于令牌修正的稿图（现读 mtime 全在 2026-09-29，另 16 张在之后）——它们画的还是旧骨架，而 §8 记过这类风险：**下一轮会拿旧稿当规格**。〔**P38b 后半已做完，且这一条本身有两处要更正**：① 只 3 张该重渲染，`mmui/components.png` 那一张重渲染后与 HEAD **字节相同**（那一页没有标题栏层）；② "另 16 张在 09-30 之后"是 mtime 口径，不代表它们与令牌同源——这一条真正的判据是像素，实测内容白区起点 OLD 158 → NEW 186（28 设备像素 = 38→52 之差），量法与两条坑见 `coordination-audit.md` §4③，脚本 `Scripts/p38b-mockup-render-check.sh`〕〔**P38c 补一行，那条"动手前先量"已经量完**：门外那批坐标进门**一条不可达都不报**（越界 0、空白 0），当场变红的只有一条**裸写文件名的测试日志坐标**撞上全仓 16 份同后缀日志——是"不自证是哪一篇"，不是"指不到"；已就地补全路径，补完的成对终跑 ext 落回 1142 / 912 / 805 且 exit 0（base 那一份 1109 / 894 / 787 一字没动）。所以补白名单这件事现在剩两道小活儿（先全站扫一遍裸写日志坐标、再单独一轮改口径），都不需谁点头，但**它们排在 v1.3 那三条决定之外**：那是尺子，不是功能。量法与两跑四个总数在 `release-readiness.md` §7.32 末段。〕〔**P38d：那两道小活儿都做完了，这一笔债（roadmap 里编号"债 6"）已收口，且它不是功能版的一行**——白名单补了 `css|log`（抽取那一步现在在脚本第 134 行，原 130），符号面对这两族跳过、命中/行号/空白三关照旧跑；全站裸写 css/log 坐标现读 25 处 / 唯一 14，**全落在单副本族**，那一族 16 份的测试日志裸写 0 处——危险判据是"裸写 + 同后缀多副本"，不是"裸写"。**基线从此是 1142 / 912 / 805（位置存疑 88、硬失败 0、exit 0，逐字日志 `docs/verification/p38d-citations/audit.log`），下一轮看到 +N 先分清是坐标涨了还是尺子换了。**v1.3 那三条决定一条没动，也不该被这一改顶掉：那是功能面的，尺子这一改不替谁做决定。全文在 §7.33。〕〔**P38e 把那句"下一轮看到 +N 先分清"兑现了一次**：改稿那一版把三个总数顶到 **1165 / 929 / 822**（位置存疑 89、越界/空白/歧义/死符号/硬失败全 0、exit 0），而**尺子一个字没改**——涨的全是这一轮写进 `.md` 的、指向设计稿的坐标。同时本节第 5 条那条约定跨轮第二次被实测到：第一次跑门禁就因一句记账里的旧坐标报了 **1 条硬失败**（改稿后那一行是空白行），本轮共把三处叙述型坐标改成散文。逐条读法在 `release-readiness.md` §7.34，台账四数在同文档 §11。〕
**这一版不写新功能**——它改的是所有版本共用的量尺，混进功能版就等于让那一版的照片同时背着两笔变化。〔**P38b 前半已做掉一件纯文档的**：副本面清单里标题栏那 17 处假判定全部就地改判（行数守恒、量尺 113/0/0），under-page 那格顺手翻掉 5 处、**剩 16 处仍等上面第 2 条**；v1.3 的体量因此是"三条决定 + 16 处回写"（"一次重渲染"那一件已随 P38b 后半做完），判据与账在 `coordination-audit.md` §3–§4〕

### 5. v1.4：改稿版

九份 fidelity 的 S 系列（全站 footer、稿内占位数字、content 底色、under-page 变体）
+ ~~`09-settings.html` 落后实现的那六条（含两句实现已经改掉的假脚注——§8 记过它的风险不是"稿不好看"，
而是**下一轮还会拿旧稿当规格**，照稿施工会把假话改回代码里）。**09 那六条 P38e 已改完（2026-10-14，
见 `release-readiness.md` §7.34）：五块 artboard 变九块、PNG 按全高重渲染，09 那一批像素基线已作废。~~ **这一格现在只剩 S 系列**，按 #53 的约定排到集成阶段。**它不与 v1.3 合并**：一次作废两批基线，出差异时分不清是谁改的。〔**P38f 现读：这一格里前两项已经落地，S 系列因此缩成四条侧栏面 + 两项令牌决定**——footer 组件在 `docs/design-system/tokens.css:287`（`.sidebar-footer` + `.vol-line`/`.pct`/`.vol-bar.low`/`.foot-btn`），现读 20 份稿里 19 份在用、25 处实例（**P41f 现读**，旧记 16 份 / 21 处），动作是 `0c61fbf`（2026-09-30「十张稿统一侧栏footer组件+清洗占位数字」），稿内占位尾数是同一笔删的；今天还开的是 `components.html` 改稿前第 141-142 行 那格旧画法、磁盘 `04b`/`04e` 三块整段没画 footer、卸载 `03c`/`03e` 两格给"应用卸载"挂了实机永远不画的尾数、`07-monitor.html` 那段自己已过期的 cap，加上 content 底色缺 `.content--window` 变体与 under-page 接线两项待裁定；判据、代价与重渲染排口见 `release-readiness.md` §7.35（本轮那 43 行判定与副本面清单在 `coordination-audit.md` §3 末段）。〔**P39 v1.4 第二刀：那四条侧栏面全部落地**——六份 `.html` 改稿 + 九张 png 重渲染，S 系列这一格今天只剩"content 底色缺 `.content--window` 变体"与 under-page 接线两项待裁定；判据、四张 STALE 的来路与两条读数边界在 `release-readiness.md` §7.36。〕

### 6. 不排期（写在这里是为了下一轮别把它当新候选再提一次）

- 上面「明确不采纳」那七条照旧。
- **本轮新增两条不做**：treemap 捏合/手势缩放（disktree `crates/disktree-app/src/views.rs:92` 的 `zoom_interface`；
  我们的验证体系禁止合成 UI 事件，**这条等于永远只有单测**，没有照片就不算落地）；
  应用更新检查（Pearcleaner `Logic/AppsUpdater/` 整个目录，**违反零网络**，且依赖的私有框架那部分本就在拒绝清单里）。
- **有意不修两条**：磁盘风险标签与删除闸门在 symlink 上给的口径不同（`realpath` 后落 `/System` 才被拦，
  代价=每行一次 realpath，§8 论证过不改）；`protectedNames` 里那五条以点开头的名单永远匹配不上
  （`.` 开头被 `readEntries` 先跳过，是归因错不是 bug，改它=改扫描语义）。

### 7. 每一版共用的验收不变量（本轮新增两条）

1. 九包重跑 + 结论行入库；动编译输入 → 前后两族照片 + `# digest:` 当场同源（P23b 那道门禁）。
2. §10 第 3 步**真跑了**遍数才加一——拍了多少张照片都不算（P29 实拍八张、前后两族各四，遍数仍是十三）。
3. 引用门禁 `Scripts/p16-citation-audit.sh` 每版跑一次并归档。**P30 起归档那一份自己带结论行**
   （从前 `# 硬失败…` 只在 stdout 与退出码里，入库那份 `audit.log` 不含它，所以"0 硬失败"这一句
   在旧日志里只能靠把四道判据相加复核——P20 就记过一次这个坑，P30 把脚本改了）。
4. **新增**：门禁跑在 `git add` **之后**。P29 实测：它的索引取自 `git ls-files`，
   两个本轮新文件在入库前被判成"不可达"，那一跑报 7 条硬失败、入库后 0 条——**顺序反了就会记一笔假账**。
5. **新增**：记"某处行号漂了"的那句话，自己不许写成 文件名 + 冒号 + 行号 的成对形态。
   P29 实测：同一段记账的话触发了第二次硬失败（0 → 1），因为门禁不分"使用一处引用"和"谈到一处引用"。
6. **版本边界 = 照片边界**：一版里尽量只让改动落在同一批屏上；跨屏几何与改稿各走各的版（见 §4、§5）。

### 8. 本轮没能确认的（下一轮先问这几句）

- **有没有第二台带电池的设备**——决定 v1.2 那三条里的第一条能不能收尾。
- **个人数据的删除边界**（微信那一类）——这是产品决定，不是工程决定。
- **`§8` 里那三档"本机拿不到"的状态**（CPU 是否真存在 0.25s 零跨度、登录项 `.requiresApproval`/`.notFound`、
  通知 `.notDetermined`/`.authorized`）——要么换机器，要么由用户手动改系统授权档位再拍，
  本轮**没有**为了拍照去动用户的系统设置。
- 五份 fidelity 的"待量"里，本轮只交叉核对了 disk/cleaner/optimizer 三份的现读收口，
  monitor/guardian/uninstaller 三份的"待量/无 HOLD 钩子"以各文档自记文本为准，**没有逐张照片目录扫过**。〔P43a/P43b/P43c（本轮）已把这笔债翻掉：三份文档逐条对着 `docs/verification/` 的照片目录扫过并就地改判。结论形状三份不一样——**monitor §4 那张 13 行表：6 行已由照片收口、7 行仍 0 张**，成因是"有钩子但只有一批脚本用了其中一部分"（`MM_MONITOR_HOLD` 落地至今没有一支脚本调用过）；**guardian 的钩子口径成立**，卡点是"真实摄像头/占用"这一态只能靠夹具、需要第二台设备；**uninstaller §5 那张 9 行表：1 行已收口（浅色档）、8 行仍 0 张**，且这 8 行缺的是钩子语义（HOLD / 零残留夹具 / 多 app 夹具 / 人工授权）而不是缺脚本。三份共同的另一笔账：出片早于 P23b 的那些族（monitor 26 张、guardian 22 张、uninstaller 的 p68 11 张）`.log` 里都没有 `# digest:` 源码指纹，"照片与二进制同源"对它们说不成立。另查 `release-readiness.md`：`grep -n "待量\|无 HOLD\|逐张照片"` → 0 命中，这一族结论只在这三份文档里。〕〔**P44 把这一句里 monitor 那半笔翻掉**（2026-10-15）：「7 行仍 0 张」今天清零——`Scripts/p69-monitor-frames-capture.sh` 出 17 档 × 明暗两套共 34 张（`docs/verification/p69-monitor-frames{,-dark}/`，每目录 17 对 `.png`/`.log`，digest 一律 `1d530d8+52db0ea7`），monitor 那张 13 行表现在读作 **#1–#12 有照片、只剩 #13（非照片项，归 `FormatTests`）**；「`MM_MONITOR_HOLD` 落地至今没有一支脚本调用过」也随之翻掉，它第一次被调用，而且出片前先补了它的生效留痕＋5 条单测（没有留痕时 HOLD 帧与真机首帧同形、照片自证不了钩子被消费）。这一轮实拍还当场抓出一个真缺陷：`MM_MONITOR_CARDS` 旧比对 `MonitorCard(rawValue: token.lowercased())` 让唯一的驼峰格 **`perCore` 永远选不中**，配上"整批作废"就连坐（第一遍 01 的 `.log` 是铁证，那张已删重拍），修法是 `CaseIterable`＋整表双向小写比对＋两条新单测。guardian/uninstaller 两半本轮未动，仍按 P43b/P43c 的结论；那句"出片早于 P23b 的族没有 `# digest:`"也不变（monitor 那 31 张旧照依旧没有，本轮 34 张逐张有）。〕

### 9. v1.1 第 1 条的落地记录（P31a，2026-10-10）

**状态：已落地，两半都齐**（纯函数 + 照片）。§2 表格第一行那句"0 命中"从现在起是历史。

- **事实层**：`Packages/MMUninstaller/Sources/MMUninstaller/RunningAppProbe.swift`——
  `RunningAppInfo` / `RunningAppEvidence` / `AppRunningState`（四档：running / notRunning /
  undetermined / 以及按证据分两档的匹配）+ 纯函数 `resolve(bundleID:bundlePath:running:)`
  （小写字符串比、**不解析符号链接**、`pid <= 0` 在读取端就剔）。
  这一层**没有一句用户可见文案，也没有读 env 的假快照钩子**——运行状态是系统状态，
  喂给界面的合成值只能证明界面会写字，证明不了写的是真话。
- **呈现层**：`MMUninstaller.swift` 的 `extension UninstallCandidate`
  （`runningChip` / `runningValue` / `runningBasis` / `runningWarning` / `runningEmphasis`），
  文案合同是 `docs/design-system/screens/mmuninstaller/03f-uninstaller-running.html`（本轮首渲染，
  高度按 PIL 逐行量出来的 2069pt，不是猜的）。
- **状态从哪来**：`UninstallerModel.runningAppsFactory`（默认真读 `NSWorkspace`，单测注入假快照）+
  `runningStates` 字典（**缺席 = 还没读过，界面这时一个字都不说**，`.notRunning` 是一种主张不是默认值）。
  更新时点只有三个：载入清单、按下卸载/移到废纸篓打开确认面板、进程启动与退出的两条通知；
  **换选中项不重读**，也**没有定时器、不轮询**。
- **单测**：三个新文件 27 条（`RunningAppProbeTests` 13 / `RunningAppStatePresentationTests` 10 /
  `UninstallerRunningStateModelTests` 4），MMUninstaller 121 → **148**，全仓 641 → **668**
  （现读，结论行在 `docs/verification/p31-citations/run-all-tests.log`）。
- **照片**：`docs/verification/p31-running/` 七张，一次跑完（七份日志 `# digest:` 全是
  `tree=7918074+b8cf9354 app=7918074+b8cf9354`）。**当日跑了两轮**：第一轮拍完之后本轮又改了两处
  **源码注释**（见下条），注释是编译输入、进指纹，取证脚本按 P23b 那道门禁当场拒拍，于是重建 +
  整族重跑一次——七张照片与这份源码同源这一条是门禁给的，不是"只改了注释所以没关系"给的。
  逐档哨兵、以及照片当场抓出来的**两处假话**，
  记在 `fidelity-uninstaller.md` §13.1：05 第一次拍到的是设置窗（`head -1` 挑窗的仓库级潜伏缺陷，
  现读 29 支引用 `window-ids.swift` 的脚本里有 26 支这么挑），07 交叉读出
  `runningBasis` 句尾那句「两档都算『正在运行』」在"两个进程同一档"的画面上是假话。
- **本轮第三处假话在源码注释里，不在画面上**：`UninstallerModel.swift` 写着"换选中项"是一个刷新时点
  （现读 `select()` 并不重读）、`RunningAppProbe.swift` 把"报不出包名"归因给 `.prohibited`
  （现读 19 条里 accessory 12 / prohibited 6 / **regular 1**）。两句都是本轮自己写的，
  靠"逐句回到代码与系统现读"抓出来，改完就是上面那次重跑。**注释进指纹不是形式主义**：
  这一轮就是它把两处没被任何断言覆盖的假话变成了必须修的事。
- **引用门禁当日十二跑，六跑入库、六跑只活在 `/tmp`**（提交前 `docs/verification/p31-citations/audit.log`，
  892 条引用、唯一「路径+行段」738、命本仓库 664，**硬失败 0、exit 0**；
  提交后 `…/audit-postcommit.log`，同一棵干净树 `# repo: f43a766`，两份 `diff` 出来
  **只差 `# date:` 与 `# repo:` 两行**——三个总数、四道硬判据、只提示那两层（死符号 0、位置存疑 116）
  逐字相同。**P24 立的那句"提交换出处、不换判据"又实测到一次**——本轮不再给它数序，
  因为同一句在 §1 那一格里 P25 数成"第二次"、P26 数成"第四次"，两个序数本来就对不上，
  再加一个只会多一个没人能复核的数。时间戳在那两份日志的第 2 行，不在这里复述，
  免得文档里那个数和归档文件自己那个数长成人手抄的两个版本）。
  **这一版到这里为止写错过一处机制**：上一稿说"同一个 `audit.log` 本轮被就地写了六回"，
  把**没入库**写成了**被盖掉**——真跑的时候每一跑都有自己的 `/tmp` 名（`p31-audit.log` 加 `2` 到 `12`），
  谁也没盖谁；真正的损失是**中间那六跑只存在 `/tmp`，而 `/tmp` 收口时要清空**，
  于是文档里凡是引用那几跑读数的句子会变成无人能对上的话。现在那十二跑的九个读数逐行进了
  `docs/verification/p31-citations/audit-ledger.md`（那份台账的九格是命令从日志里现取再反比对的，不是手抄；
  台账末尾还写着删掉 `/tmp` 之后哪些跑还能独立复核、哪些只剩这张表里的抄本）。
  所以 §10 第 3 步那条"重跑要换输出目录"**本轮按字面做到了，但字面不够**：名字换了、副本没入库——
  **换了名字不等于留了档**。三份红读的名字与读数（`audit-red1-drift.log` 876/727、
  `audit-red2-offbyone.log` 885/736、`audit-red3-selfcitation.log` 895/741）是这一轮在清 `/tmp` 之前
  拿到仓库名字的三跑过程读，加进仓库的还有终态那三份绿读。
  P24 到 P28b 四轮里那条规则被犯了四次，每一次盖掉的恰好是唯一有信息量的那一读。
  **还有第 12 跑这件事本身**：台账和这两份文档改完之后复跑，三个总数变成 **893 / 739 / 665**，
  多的那一条正是台账里指向那支门禁脚本落盘行的锚——**写文档的人在数自己的时候把自己也算进去了**，
  四道硬判据依旧全 0，所以这一格顶上那句 892 / 738 / 664 指的是第 9 到 11 跑那一份语料、
  而不是这一次提交的树；两个数各指哪一跑，现在都写在旁边。
  五处红判据**全是本轮自己造的**，没有一处旧账：
  红一那三条是**位移**——往 `UninstallerModel.swift` 插注释把文档引的 `:202` 顶成了空行
  （现在 `selectedAppID = nil` 在 `:216`）、往 `mm-provenance.sh` 的"已知松处"补两行把路径清单从 `:39`
  顶到 `:41`、`MMUninstaller.swift` 的 525 行同理落成空白。**改注释要还的债不止指纹，还有锚点。**
  红二那条是**我自己数错了行**：`sed -n '232,238p'` 打出来的第一行看着就是 232，实际 232 是空行、
  `apps = …` 在 233——取行号得让命令自己带行号打，不能按打印顺序数。
  红三那条性质又不同：它抓的是**本轮刚写的一句话**，散文里"某某文件某行号"只要写成 `路径:行` 的形态，
  就照样被抽成一条引用送去判据（P30 那一轮抓到的是同族的另一种：新写的引用把包名记错了）。
  同一张表（`fidelity-uninstaller.md` §1.7）里还有六处行号是"有效但早就指错了"——
  `trashRegion`、`TrashWatcher.start`、`MMDesign.swift` 的 `MMPermissionBanner`、`trashConfirmSheet`、
  `trashConfirmHook`、`reloadListing` 落回那两行——**门禁对它们一个字都没说**：
  它只匹配 `路径:行`，表里那些写裸 `:566-573` 的行它根本不去读。这一轮按"表既然动就整表现读"重指了，
  顺带纠正一处符号名：`fullDiskAccessPane` 从来不存在，真实取用的是 `MMSettingsPane.fullDiskAccess`
  （定义 `SystemSettings.swift:18`，横幅取用 `MMUninstaller.swift:1083`，深链拼接 `MMDesign.swift:519`）。
  **同一个符号名在别的文档面还有副本**：`trash-watch-fda.md` 第 52 行与 `fidelity-cleaner.md` 第 79 行
  （后者引 `MMDesign.swift:447-477` 指 `MMPermissionBanner`，现读那一段是 `MMEmptyState`，banner 在 `483-513`），
  两处同轮改掉；剩下 116 条"位置存疑"本轮没有逐条收，那是另一轮的活。
- **与参考项目的边界差，写在明处**：Pearcleaner 的 `killApp`、Mole 的 best-effort termination
  都在动手前**替用户退出应用**，这一版只做到"看见并说出来"——不代退出、不代结束、
  也不因为"它在跑"而拦住卸载按钮（macOS 允许删掉正在运行的应用包，那句后果必须说，
  但拦按钮是一种我们没有主张的权力）。**"结束进程"这项能力本就不在 v1.1 这一条的范围里**，
  所以界面上也不出现任何"杀不动怎么办"的话。

留给后面的三条，本轮没做：

1. **`undetermined` 那一档没有照片**，本机现读两次（参与判定 163 / 165 条）里"包名与位置都报不出"
   的都是 0 条。要拍它只能改 `snapshot()` 的语义喂一条假快照，那等于在这一屏唯一"看不见"的地方
   造假——**不为一张照片改生产语义**，这条与 §6 里"treemap 手势永远只有单测"同一处理。
   这一句的依据现在有一支可重算的工具兜底：`swift Scripts/running-apps-tally.swift`
   （本轮 16:12 第三次现读：参与判定 139、`idEmpty` 19、`pathEmpty` 15、**`bothEmpty` 仍是 0**）。
2. **旧 07 曾拍成磁盘分析页，三次同 env 重跑都没复现**，`~/Library/Saved Application State`
   在本机不存在（所以也不是状态恢复）。根因未记，现在的兜底是日志里那行 `# windows(pid=…)`。
3. **v1.1 第 2 条（Steam 启动器型识别）**：P32a 审计与 P32b 实现都在 2026-10-10 落地（审计见下面的 §10，
   实现与十一张实拍见 §11）。

### 10. v1.1 第 2 条的审计记录（P32a，2026-10-10）

**状态：审计完成，代码一行未动。** 产物是 `docs/analysis/uninstaller-steam-launcher.md`（结论、实拍事实表、
参考项目识别合同、机制归因表、P32b 六条建议、没测的清单、复现），加 `docs/verification/p32-steam/`
里八张照片与八份日志（另有一份事故档 `incident-04-panel-opened-then-confirmed.png/.log`，见本节末）。
本轮**没有新的编译输入改动**，所以 §9 那笔测试总数不动；八份日志里的
`# digest:` 全是 `tree=2d49642+e3b0c442 app=2d49642+e3b0c442`，与当轮干净树同源（指纹门禁在拍之前判过一次正向）。

- **量到的两个数**：夹具里 `SteamGame.app` 本体 **593 字节 / 2 个文件**，而游戏本体（放在参考项目同一个位置
  `Library/Application Support/Steam/steamapps/common/SteamGame/`）**25,165,832 字节**。
  界面上出现的是前者：列表行「SteamGame 1.0 593 字节」、详情「本体 593 字节 · 包含文件 2 ·
  残留大小 524 KB · 残留项 3」、确认面板「合计 525 KB」。**后者八张照片一次都没出现**（日志里那条
  `# sentinel:` 就是专门用来钉这件事的：照片的「残留」「合计」里不该出现这个量级）。
  对照档 `PlainTool.app`（8,389,057 字节真实负载、残留 0 项）证明这不是"小 bundle 都不显示"，
  而是这一族没有那句话可说。
- **本轮真正的收获是反向那一条**，它不在计划里、是拍 08 时撞出来的：卸载 **Steam 本体自己**时，
  `~/Library/Application Support/Steam` 会以「名称与包名对应」的身份出现在残留清单里，
  夹具量到 **25.2 MB**，风险档是谨慎、默认不勾（页脚「已选 0 项残留 · 0 字节」）。
  真机上那一个目录装着**全部已装游戏**。默认不勾这一道挡住了误删，但那行的说明文字讲的是
  "登录态或未同步数据"——**说的是账号，不是"这里面是你的游戏库"**。
  所以 P32b 的第一条不是"认出启动器"，而是这一行措辞（审计文档 §5 第 4 条，它不依赖识别能力就能成立）。
- **为什么正好错过它，是代码推导而不是猜测**：`Application Support` 那条 catalog entry 的
  `extraDescent` 为 0，下探层数 = 敏感度秩 + 0 ⇒ 严格 0 层 / 增强 1 层 / 深度 2 层，
  而 `Steam/steamapps/common/SteamGame` 在第三层（审计文档 §4 那张表逐行带出处）。
  同一条层数既保证了我们**不会**误删游戏，也保证了我们**说不出**游戏在哪——一句话缝两面。
  这里要提防一句现成的注释：`ResidualScanner.swift` 里那段"下探厂商目录（`~/Library/Application Support/Google/Chrome` 这种形态）"
  并没有覆盖 `Steam/steamapps/common`，**P32b 不能把这层运气当合同用**。
- **增强 / 深度两档只有推导、没有照片**：`MM_UNINSTALL_*` 那五个钩子里没有敏感度钩子，
  本轮只拍到了严格档。这条缺口写进了建议第 5 条——P32b 只要动审计文档 §4 那张表任何一行，就得先把钩子做出来，
  否则又是"用推导冒充实拍"。同理，本机**没有装 Steam**（`/Applications/Steam.app` 与
  `~/Library/Application Support/Steam` 两条都现读不存在），所以这一族八张全部来自 `/tmp` 假 home，
  没有 P31 那种"点名本机真在跑的应用"的对照档。
- **两处参考项目的不共识，本轮按分歧做夹具而不是选一边**：那个启动脚本叫什么，Mole 走
  `CFBundleExecutable`（取不到退回 bundle 文件名），Pearcleaner 写死 `Contents/MacOS/run.sh`——
  于是 `SteamGame.app`（同名）与 `SteamRunSh.app`（run.sh）各一张；
  包标识那一维也一样，Mole 的 bats 夹具用 `com.example.steamgame`，而它自己的两处注释都承认
  真机这类 bundle 常常没有 `CFBundleIdentifier`——于是 `SteamNoId.app`，画面上「包名 —」、
  「来源 无法判定」、残留 **0 项**（残留只剩名字一条腿，而 `Application Support/Steam` 与它名字不同）。
- **落点从"来源徽章加一档"改掉了**（§2 那一格的第三列现在写的是新落点）：`AppProvenance.Source` 答的是
  "谁装的"，启动器这一档答的是"它是什么"，两个维度正交——一个 brew 装的 Steam 启动器两句同时成立。
  这条判断要写在实现之前，否则下一轮一定有人往那个枚举里加 case。
- **本轮的错不在计数上，在夹具里**：`Scripts/p32-steam-fixture.sh` 第一次实跑折在
  `plutil -create xml1` 那一步——它只建文件、不建父目录，而 `Library/Preferences` 在假 home 里本来就不存在，
  于是整支脚本在 Preferences 那一行停下、留下半个夹具（那次半成品目录已删）。修法是那一行前面自己 `mkdir -p`，
  原因写在脚本注释里。**教训是"每支新夹具脚本都得实跑一次才敢进仓库"**：这支脚本写的时候看着无懈可击，
  第一次跑就断在第 150 行前后的一处目录假设上。
  编辑路线这一轮刻意是"原地替换单行 + 只在文件末尾追加"，为的是不重演 P31 那种"加两行注释把别人引的行号顶掉"的
  位移债（§9 那格记过红一那三条）。全仓文档引用本轮**只增不改**，新增的引用只有
  `docs/analysis/uninstaller-steam-launcher.md` 与 `docs/verification/p32-steam/` 两个路径（不带行号）。
- **事故档要留在仓库里**：04 那一档第一次拍到的其实是**删除之后**的画面（列表少一行、
  「已卸载 2 项 · 532 KB」的 toast，夹具里的 `SteamGame.app` 当场没了）。代码上能走到删除的只有确认面板
  那个 prominent 按钮；脚本不发合成事件（老规矩），所以最可能是那十秒里一次真实按键落在我们自己的窗口上——
  **钩子自动把面板弹出来，而面板的默认按钮是破坏性的**。同一档重拍时 05 的面板好好地开着，所以它不是每次都发生，
  而是"发生过一次，而当时的脚本没有能力发现自己看见了删除之后的画面"。
  处置在取证侧：脚本每档拍完查一次夹具目录、写 `# post-shot:`，本体消失就判这一档不作数。
  **产品侧不改**——一次回车确认删除是正常 macOS 交互，要收的是脚本自己"弹面板 + 等十秒"这个跑法。
- **引用门禁本轮五跑入库**（`docs/verification/p32-steam-citations/`，全部跑在 `git add` 之后，
  每跑一跑换一个文件名——§9 那条台账立的规矩）：`audit.log`（17:38）与 `audit-precommit.log`（17:39）
  是对同一棵未提交树的重跑，两份 `diff` 出来**只差 `# date:` 一行**（三个总数、四道硬判据、
  只提示那一层逐字相同）；`audit-final.log` 是审计文档 §4 补了 Library 根那条 entry 之后那一棵；
  `audit-final2.log` 是本节定稿之后那一棵；`audit-postcommit.log` 是提交之后的干净树——它对的是
  P32a 那一次提交，本节这几行字要下一次提交才动，别拿这份日志去对这一次的文字。
  提交后那一跑 `# repo:` 从 `2d49642-dirty` 变成干净的新提交，索引也从 1044 涨到 1048 个跟踪文件
  （本族那四份门禁日志进了跟踪集），**而三个总数与四道硬判据一位没动**——
  "提交换出处、不换判据"这句又实测到一次，序数照旧不数（理由见 §9）。
  **定稿这两跑的读数是 引用条次 926 / 唯一「路径+行段」769 / 命本仓库 677，硬失败 0、exit 0**，
  比 P31 终态那一份（892 / 738 / 664）多的 34 / 31 / 13 条全部来自本族新文档与这两处回写。
  其中"条次多一条、唯一面没多"这一格是**本轮自己造的重复引用**：审计文档 §4 那一格现在把
  `ResidualScanner` 的 208 行写了两次（正文一次、出处列一次）——P31 记过的那个"写文档的人数自己也算一条"
  又出现了一次，只是这次它只影响条次，不影响任何判据。
  **一句诚实的边界**：符号面"位置存疑"从 116 涨到 122，而日志按设计只印前 40 条，
  所以"本族那 13 条新引用没落在软层里"这一句**从归档文件里读不出来**；
  本族的行号是靠"写完逐条回到源码打开对一次"兜的（§4 那张表的出处列就是这次对的结果），
  硬判据那一层则由门禁兜——**这两层谁也没替谁干过活**。

### 11. v1.1 第 2 条的落地记录（P32b，2026-10-10）

**状态：实现完成，v1.1 四条里第二条收口。** 审计那六条建议，**五条照原样落地、一条按人未拍板的那档停在半路**：

| 审计建议 | 落地成什么 | 钉住它的东西 |
|---|---|---|
| ① 事实层 `SteamLauncherProbe` | 新文件 `Packages/MMUninstaller/Sources/MMUninstaller/SteamLauncherProbe.swift`：纯判定吃快照值 + 一个只读读取器，本文件零用户可见字符串；两条入口（`CFBundleExecutable` → `run.sh` 兜底） | `SteamLauncherProbeTests` 24 条；照片 01/02/04 走第一条、05 走第二条 |
| ② 不塞进 `AppProvenance.Source` | 那个枚举**一个字未动**（仍五档）；界面上是 `MMKeyRow("启动器", …)` + 标题徽章 + 列表行 chip | `SteamLauncherPresentationTests` 5 条（含禁词表）；照片 01–05、09 |
| ③ 措辞合同 | 依据两句：凭据 + "量的就是启动器本身"；收尾从"也说不出它们在哪"改成"只读了这份启动脚本、没按游戏逐个认" | 禁词表新增"说不出它们在哪"（本轮真实越界那一句）；照片 01 与 06 对读 |
| ④ 反向那一条（**只取"改措辞"档**） | `ResidualItem.caveat` 独立字段 + `ResidualCollector.add` 唯一收口点判定 + `ResidualRow` 行下方独立一行 | `ResidualCollectorSteamTests` 5 条；照片 06（1400 宽）、08（同屏另一条候选不加字）、11（1000 宽整句）、**11a（修复前被省略号吃掉的判据档）** |
| ⑤ 敏感度钩子 | `MM_UNINSTALL_SENSITIVITY`（`UninstallerModel.swift:184`），档位名与界面选择器同源；非法值回落 strict + stderr 留痕 | `ResidualSensitivityTests`；照片 07/08/09/10 |
| ⑥ `1.0 ()` 版本口径 | **未动**（与本族无关，另开一格） | 本轮**又在这族照片上看见它一次**：`03-plain-tool-control.png` 的 PlainTool 就是「版本 1.0 ()」，而同一张上五份 Steam 夹具是 `1.0 (1)`——同一缺陷两档并存，一个字没改 |

**没做的那半条，是人还没拍板而不是漏了**：§5 第 4 条给了两档，本轮只走"改措辞"（呈现层）。
"改 `ResidualCatalog` 清单"那一档（要不要给厂商总目录一条排除/降级规则、别的厂商同不同规则）
**仍待决定**，本轮一个字没碰 `ResidualCatalog` 的条目与层数。

**照片侧抓出来的两处，都不是单测能抓的**（详版在 `fidelity-uninstaller.md` §14.1）：
同屏自相矛盾（依据说"说不出它们在哪"、残留行说"内含 steamapps"还给着 25.2 MB），
以及行内提醒拼进副标题后在窗口硬最小宽度下被中间省略吃掉（`MMItemRow` 副标题固定
`.lineLimit(1)` + `.truncationMode(.middle)`，`MMDesign.swift:858-860`；光路径 35 个字符）。
第二处的代价是**整族重拍一次**：判据档 11a 留在仓库里当"改之前长什么样"，
它的 `# digest:`（`fdf0f95+1f91a012`）与其余十一张（`+71d7740f`）**故意不同源**。

**产物清单**：源码 4 改 1 新（`MMUninstaller.swift`、`ResidualCollector.swift`、`ResidualScanner.swift`、
`UninstallerModel.swift` + `SteamLauncherProbe.swift`）、测试 3 新 1 改（共 34 条 Steam 相关，
另 `ResidualSensitivityTests` 加 36 行钩子档、净 +4 条判据：6 → 10，
`git show HEAD:… | grep -c 'func test'` 与跑出来的日志两头现读对过）、
取证脚本 1 新（`Scripts/p32b-steam-launcher-capture.sh`，十一档）+ 夹具脚本 1 改
（`p32-steam-fixture.sh` 补第六份 bundle `SteamTwoEntries`，`p32-steam-capture.sh` 那行"清单应含几行"的判据跟着改），
设计稿 1 新（`docs/design-system/screens/mmuninstaller/03g-uninstaller-steam-launcher.html` + 渲染图）、
`docs/design-system/icons.js` 新增 `game` 一条（对应 SF Symbol `gamecontroller`，**本轮动了共享层**：
只在表尾追加，既有那一条仅多一个行尾逗号，没有改任何已有键）、
实拍 12 张 + 12 份日志（`docs/verification/p32b-steam/`）。

**测试**：九包 **706 / 0 失败 / 1 跳过**（`Scripts/run-all-tests.sh` 在最终树上跑过两次，
两次那 768 字节的输出 `diff` 为空），其中 MMUninstaller 148 → 186（+38 = 34 + 4，
其余八格与 P31a 归档那份 `diff` 只此一行不同）；结论行入库
`docs/verification/p32b-steam-citations/run-all-tests.log`。

**引用门禁八跑入库**（`docs/verification/p32b-steam-citations/`，同一支脚本、八个文件名，§9 那条台账立的规矩）：
`audit.log` 是提交前那一棵（`# repo: fdf0f95-dirty`），`audit-postcommit.log` 是提交之后的干净树
（`# repo: 9da45fa`），`audit-docfix.log` 与 `audit-docfix2.log` 是本节这段字的两版之后各一跑
（`# repo: 9da45fa-dirty`），`audit-docsweep.log` 是**活数回写扫尾那一改之后**的一跑
（`# repo: 0e88f09-dirty`，改的是 README、`RELEASE-NOTES.md`、§0/§1/§6/§10 与 CI 那格描述），
**`audit-anchorfail.log` 是本族第一份非零退出码**（`# 硬失败 1`，下面单写），`audit-anchorfix.log` 是把它改回去那一跑，
`audit-final.log` 是**写完下面那段漂的记账之后**的定稿跑（同一段定稿文本连跑两次：前一份读数是 937，
比入库这份少两处出现；入库的是紧随其后那一份，**它与提交出去的文本逐字同源**，两次除了 `# date:` 一行之外逐字相同。
被取代的那份没有入库——本族从前没有过"盖掉刚写的日志"这一档，这里记明，别把它读成 §9 那条规矩的例外）。
**前七份里除 `anchorfail` 外六份的六个读数逐字相同**：引用条次 **934** / 唯一「路径+行段」**775** / 命本仓库 **683** /
死符号 **0** / 位置存疑 **124** / **硬失败 0、exit 0**，`docs scanned` 八份都是 38 抽 38。
**第八份的三个总数走到 939 / 777 / 685**，多的 **+5 条次 / +2 唯一 / +2 命本仓库**全部来自本轮为那段漂新写的两处锚点、五处出现
（引向 `release-readiness.md` 第 723 行的那三处、指向 `Scripts/p29-anchor-drift-audit.sh` 那句 `|| true` 注释的两次——后者按 §7.7 裸写，P36 改那支脚本的头部后它的行号搬了家），**硬失败仍然 0**——
**记账本身也在加引用，这一族的数不是只降不升的**；位置存疑那一层八份都是 124，这段新字一条没进软层。
`anchorfail` 那一份与它前一份的 `diff` **只有四行**：`# date:`、`整段空白的引用: 0 → 1`、那一行的明细、
`硬失败 0 → 1`——**三个总数与另两道判据一位没动**。
头两份 `diff` 出来只有三行不同——`# date:`、`# repo:`，以及索引那一行从 **1081 涨到 1082 个跟踪文件**，
多的那一个正是 `audit.log` 自己（它在前一跑抽数时还没进跟踪集）；**第五份与第四份的 `diff` 也只有这三行**
（索引 1084 → 1085，多的那一个是 `audit-docfix2.log` 自己）。
**活数回写那一改不动总数，这一件比"硬失败 0"更值得说**：那几处新写的叙述里没有一处 `路径:行`，
所以它进抽取器的条数是零（前七份都是 934）——"加了一段文档而门禁数字不动"是量出来的，不是推出来的；
**第八份会动，是因为下面那段记账自己引了两处新锚点**，两件事别混着读。
**而最后这几份是这一族第一次抽到活数回写那两处新字**：README 那一笔与 `RELEASE-NOTES.md` 那两格
在头四份里还不存在，所以拿头四份去对这两处对不出任何东西（本节这几行自己也是改一版重跑一次，
`docfix` / `docfix2` 各对一版）——**这一句自己也躲不过这个循环**，写得越细的门禁叙述越是这样，认了。
**顺带一处工具的分工，别说反**：这一族能扫到 README 与 `RELEASE-NOTES.md`（它们是入库 `.md`），
但它只抽 `路径:行`，不抽裸数字；§0 那条对账命令正好相反，它抽裸数字、只盯 `release-readiness.md` 一个文件。
**所以本轮那两处"grep 历来看不见"的面，两支工具一支都没抓到**——兜住它们的仍然是逐格现读，
这条不是工具能替的（能替的是"改完之后有没有留下一个不挂轮的数"，那一件仍然归 §0 那条命令）。
**"提交换出处、不换判据"这一句又实测到一次**，序数照旧不数（理由见 §9）。
位置存疑那一层本轮从 P32a 的 122 走到 124（P31 是 116，三份归档对得出来），
而日志按设计只印前 40 条，所以"本族那几条新引用没落在软层里"这一句**从归档文件里读不出来**，
兜它的仍然是硬失败那一层。

**`anchorfail` 那一抓：门禁第一次抓到"文档自己引自己"的漂**（本轮真正的收获）：
活数回写在 `release-readiness.md` §0 那一格里加了行，于是同一篇 §7.21 里那句自引
当时写作 `release-readiness.md` 第 723 行的那一格（第十五遍起裸写，理由见 `release-readiness.md` §7.7），从"落在一段真实文字上"被挪成"落进一个空行"，**空白面判据当场抓住、退出码 1**（本族头一份非零）。
现读该指的位置是 `:827`——**这个号本轮被改过两次**：先按第一次现读改成 826，写下面这段说明时 §0 又加了一行，
再读就是 827。**一个自引锚点在一轮里漂两次，这件事本身就是它最合适的记账。**
**而这条引用在被挪之前就已经错了 73 行**：`git show HEAD` 那一棵里 `:723` 是「最近画的是最旧的 5 条」那一条 bullet，
跟它要指的那句不是同一件事，**头五份归档却逐份放行了它**（每份都是硬失败 0、exit 0）。
**这不是新发现，是 §7.21 那条账的又一次命中**：那里已经写明"p16 那四条硬判据没有一条问它指的是不是当初那一行"
（§7.17 量过一次：门禁报 2、实漂 88）。**本轮多出来的是覆盖面的一格**：补这一问的量尺
`Scripts/p29-anchor-drift-audit.sh` 当时取的扫描面是"本轮被改过的非测试 `.swift`"（`Scripts/p29-anchor-drift-audit.sh:46`；**这一格 P36 闭合**：第二族目标补上了，见下面第 4 条末尾与 `release-readiness.md` §7.26），
**文档引文档的锚点根本不在它的文件集里**——所以那条自引既过得了 p16 的四问、也进不了 p29 的扫描面，
它现形纯粹靠撞上空行。
**顺带一条同族的坑，本轮实测到、没有修**：在这一棵只改了文档的树上跑 `./Scripts/p29-anchor-drift-audit.sh`，
**零输出、退出码 1**——第 30 行那条 `grep -v` 在没有源码改动时无命中、非零退出，`set -e` 让它在打印表头之前就中止
（与 P28d 修的"单数 failure 漏读"同一族形状：**量尺崩了和量尺报 0，从输出上看不出区别**）。
记在这儿，下一轮再收（修法就是给那一行补 `|| true`，让它照常出表头并照实报"本轮没有源码改动"）。
**本轮照做的缓解**：自引按句定位、号只当现读快照（"本文此前写"全篇唯一，`grep -n 本文此前写` 一条命令就能重指），
并且每次给前段加行之后重跑门禁**看退出码、不只看三个总数**——`anchorfail` 那一份里三个总数一位没动，
**只核对总数会把这一抓读成"什么都没变"**。

**留给下一轮的一条**（本轮照片顺出来、一个字未动）：09 那张里深度档
`~/Library/Caches/com.example.steamgame · 名称包含应用名` **归到了 Steam 名下且默认勾选**
（页脚「已选 1 项残留 · 524 KB」）——"名称包含应用名"这条证据会跨应用收残留。
另立 P33a 审计（任务 #161），**它不在 v1.1 这四条里**，排期在四条之后。

### 12. 那条留项的落地记录（P33b，2026-10-12）

**状态：已落地，采纳审计推荐的 B + A**（`docs/analysis/uninstaller-deep-residual-scope.md` §5 那一档），
判据与单测在 §8、照片与还原度在 `docs/analysis/fidelity-uninstaller.md` §15，这里只记路线上的三件事。

1. **它不在 v1.1 四条里，也没有挤掉任何一条**：四条的第 1、2 条已收口（§9、§11），
   第 3 条（`~/Library/Preferences` 损坏 plist）与第 4 条（磁盘页跨卷枚举）仍是下两轮。
   **（这一句写的是 P33b 那一轮的排期，别把它当新规格读：四条现在**全部落地**，判据侧与实现侧都收口了——
   第 3 条的审计侧见 §2 那一格的 P34a、实现侧 **P34b 已于 2026-10-12 收口**（第五 tab + 九包 737，
   见那一格末尾）；第 4 条的审计侧见同一格的 P35a、实现侧 **P35b 同样在 2026-10-12 收口**
   （磁盘页跨卷枚举 + 九包 764，见 §2 那一格末尾与 `fidelity-disk.md` §16）。
   按顺序排在两者之后的是**第十五遍发版核验——已于 2026-10-13 收口**（两轮都动了编译输入，核验放在最后才不白跑；
   764 / 0 / 1 跑在 `698d44b` 的一棵干净克隆上，候选产物第一次打 `1.0.1(1)`，
   判据与照片在 `release-readiness.md` §7.23，证据 `docs/verification/p35b-clone/`；**同一轮的文档回写
   自己把 11 条指向本文行号的引用顶漂了 6 行**（本文 §1 那张表上方加 6 行的代价），10 条活锚点逐条现读 +6 重指、
   1 处历史坐标按 §7.7 改裸写，定稿门禁走到 1077 / 884 / 777、硬失败 0，逐条处置在 §7.23 倒数第二段）。**核验之后同日就发了**：tag `v1.0.1` 落在 `41631c6`、CI `38348525288` 4 分 43 秒跑绿、Release 三个附件已挂，正文与仓库里那一版发版说明逐字相等，"附件与本地核验的是同一棵编译输入树"由 `Scripts/p35b-release-verify.sh` 当场量出（四道缝的读数在 `release-readiness.md` §7.24，日志 `docs/verification/p35b-release/release.log`）。
   **同一遍抓到一笔新的工具链债，登记在这里**：`make-icon.sh --check` 只跑了自己头部两道判据里的"十档齐全"，
   字节比对那一支在 `--check` 模式下永远取不到源图（那个中间目录只有生成才会创建），于是整条被 `-n` 判断跳过——
   改法两条候选（现生成一份源图再比 / 在日志里明写"字节比对已跳过"并把头部那句判据改成与两种模式各自相符），
   本轮按"核验途中不改量尺"没动它，详见 §7.23 与 §10 第 2 步那一格。）** **（P36 已按第一候选收口，这一格到此闭合）**：`--check` 现生成源图再比，正反两头各撞一遍——正向 `1024 档 270169 字节` 放行，把颜色常数改一位则 `✗ 源 270169 / 解出 277310` 退非零；量尺 `Scripts/p36-icon-byte-audit.sh`，读数 `docs/verification/p36-icon-byte/audit.log`，过程 `release-readiness.md` §7.25（icns 全程未变，编译输入指纹段仍是 `e3b0c442`，所以不必跑第十六遍核验）。
   本轮走的是 §11 末尾那条"留给下一轮"，排期照 §7 原本写的"排在四条之后"提前了——
   提前的理由是它对症的风险是**默认勾选会拿走别人的东西**，不是召回缺口。
2. **B 档落地时补了 B′**：审计只写了"看祖先归属"这一条线索，实现发现同层里还有一个更像主人的候选
   （`Caches/IDEFoo/ts-go-fork-embedded` 那种形态），两条线索合起来才是同一条判据，
   **不是新加的一档授权**；措辞（A 档）落在那一句"名称包含应用名（非包名对应）"
   （`ResidualNameMatcher.swift:90`），主人名进 `caveat` 而不是 `reason`——后者是 `.lineLimit(1)` 那一族，
   会截，前者换行不截（渲染合同的现读在 §15.1）。
   **C 档（改 `ResidualCatalog` 清单）仍然没动，那是在人手里的一项**。
3. **召回没有降，这一句是量出来的**：真机本机 A/B 两趟（`docs/verification/p33b-nesting/ownership-review.log`，
   digest `f7bca94+6bb866e9`）——增强档包含命中 48 条、降级 0 条、默认勾选 48→48、两遍集合相同；
   深度档 356 / **2** / 51→49 / 集合相同。全仓只有那两条 Fork 的 `JetBrains/*/ts-go-fork-embedded` 被降级。
4. **还了上一轮记下的两笔债**：`Scripts/p29-anchor-drift-audit.sh` 那句 `|| true`（§11 倒数第二段
   "记在这儿，下一轮再收"的那一支）本轮补了；它量出来的 13 条顶漂锚点全部重指，
   并且**新学到一类它结构上看不见的错**——同一轮现读出 **6 条**引用在 `f7bca94` 就已经指着别的块
   （逐条名单与"照抄会把错锚再搬一次家"的那段在 §8.3）。**P36 把这一半收掉了**：量尺补了第二族目标（被改的 `.md` 与 `.sh` 现在也在扫描面内）与第二个参数 `BASE`（默认 `HEAD`，提交后写 `HEAD~1` 还问得出上一轮顶漂没有）；本轮它自己头部净加的 13 行顶漂的 **5 条**锚点由它抓出并全部重指，受控注入（在本文顶部插两行）当场报出 **13 条**指向本文的活锚点，过程与读数在 `release-readiness.md` §7.26。
5. **判据 +14**：九包 **720 / 0 / 1**，MMUninstaller 186 → **200**，
   结论行入库 `docs/verification/p33b-citations/run-all-tests.log`。本轮只跑 §10 第 1 步，**不是发版核验的一遍**，遍数不加。
6. **p16 引用门禁这一轮新量到两条自己的性质**（全文在 `uninstaller-deep-residual-scope.md` 的 §8.5，这里只提一句因为它会咬下一个新人）：
   它的文件索引来自 `git ls-files`，**所以引用本轮还没 `git add` 的脚本，提交前那一跑会判成「两头都不到」、硬失败 1**——
   红的是状态不是错，照着它改文档就把对的引用改错了；另一条是唯一面**按写下来的那串字符去重**，
   同一条文件同一行带目录写与不带目录写算两条，所以那层的"唯一 N"比的是写法数，不是位置数。

### 13. P37 落地记录（v1.2 第 1 条：电池电量 / 健康度只读卡，2026-10-14）

**为什么现在做这一条**：§2 那四个 v1.1 项已随 **v1.0.1** 发出（tag `v1.0.1` → `41631c6`，CI 绿），
"按 roadmap 起下一版"因此落在 §3 的第一行。那一行原本写着"取证排在有笔记本的那一轮"——
**这一轮把它改了**，理由在下面第三条：夹具拍得到的东西不该等硬件。

**1. 三层各在哪**：判定层是 `BatterySnapshot`（`MetricTypes.swift`，`assemble(from:)` 是唯一入口，
raw 对（mAh）优先于 percent 对，分母为 0 或分子大于分母一律 nil）；读取层是 `BatteryReader`
（`MetricReaders.swift`，进程内 IOKit `IOServiceMatching("AppleSmartBattery")`，零权限、零写盘）；
呈现层是监控页那张「电池」卡（`MMMonitor.swift`，三句文案抽成 `MonitorView` 上的静态函数，
**抽出来就是为了能被单测钉住**，同 §11 那个手法）。采样挂在 `SystemMetricSampler` 的既有那一趟里，
没有新起定时器。

**2. nil-not-zero 在这张卡上落成五档可数的形状**：
「不知道」与「没有」是两句话——`noBattery`（本机没电池）≠ `unavailable(reason)`（读不出来）≠
字段级 nil（整卡可读但这一格读不出，画「—」）。**三处不许塌**：越界比例不 clamp 到 100%
（钳过去就是把"口径错了"报成"电满了"）、缺 `DesignCapacity` 不出健康度、
两个电源键互相矛盾（没接外接却在充电）时状态行报「—」而不编一句话。
`cycleCount == 0` 是**真 0**，不是缺值——这一条和 I9 的 `swapZero`/`swapOff` 是同一个规矩。

**3. 取证：这一族为什么不等笔记本**：本机是 Mac mini，`BatteryInstalled=No`（探针
`Scripts/p37-battery-probe.swift`，2026-10-13 实跑），"有电池"的四个正分支**在这台机器上不存在**，
不是"再等等就能拍到"。但这些形态是**结构**而不是数值，夹具能精确构造——
`MonitorFixtureHooks.loadedBattery` 喂进去的是同一份字典、走的是同一条 `assemble(from:)`，
所以照片画的换算路径与真机同一条。八档判据与四条 md5 交叉核对写在 `docs/analysis/fidelity-monitor.md` §4.4，
照片与日志在 `docs/verification/p37-battery/`；01 那张实机画的正是「本机没有内置电池」，
它是这一族里唯一的真读数，也是"夹具没有悄悄落回真值"的反向核对之一。
**三档明确没拍**（缺什么逐条写在那份文档末尾，不写"应该没问题"）：`cycleCount == 0`、
电源行余下三档话术（`loadedBattery` 两头都给确定值，构造不出半读数）、`BatteryReader` 的三条 IOKit 失败路径。

**4. 判据 +28**：`BatteryTests.swift` 全新 28 条（键的读法 7 / 纯函数与可信范围 12 / 文案 3 / 夹具档位 6），
MMMonitor 57 → **85**，九包 **792 / 0 / 1**，结论行入库 `docs/verification/p37-battery/run-all-tests.log`。
另两支测试文件只给既有夹具补 battery 入参、两条断言从旧方法搬家，**方法数没动**。
本轮只跑 §10 第 1 步，**不是发版核验的一遍**，遍数不加。

**5. 钩子：一个新键都没加**，`MM_*` 名字总数仍是 **55**（运行时 54），证法从"数总数"换成"比集合"
（HEAD 与工作树两份 55 行 `comm -3` 两个方向都空）。出片脚本接门禁的读到 **15 / 35 / 残 20**：
分子分母各 +1，残格不动。产物指纹 `tree=60f4711+74012c66 app=60f4711+74012c66`，
后半截不是空流前缀，因为编译输入里有 5 个未提交的 `Packages/MMMonitor/Sources/**`。

**6. 默认分支与已发版本从这一轮起分家**：`RELEASE-NOTES.md` 里那两处 764 属于 `v1.0.1` 的范围、
**不是漏改**；文档里的"当前值"从此是 792，两个口径都要写（判据与理由在 `release-readiness.md` §7.29）。
**下一轮看到 792 与 764 并存时先按这一条判它是分家还是漏改，别直接改数字。**

**7. 本轮踩到的两条口径坑**（都改回来了，形状记在这里）：
① `git diff --stat` 中间那列是**增删之和**，`--numstat` 才是 +a/−b——拿 11 和 2 当净增会把 +304 算成 +312。
② **归档的说明行不能含取数行用的键**：比对段里照抄了一遍取数字面串，下一轮同一条命令抽出 11 行而不是 9 行——
文档把网撒进了自己的分母，与"取数值的命令要单独调用"是相邻的第二种坑。

**8. 这一版余下的两条仍在等人**：GPU 利用率（§3 那格写的是**默认不做**，且历史上 roadmap 替它背过
"已落地"的假账）与微信聊天媒体分类（要产品先定"只报不删"还是"默认不勾、勾选才删"）。
本文 §3 那三行现在是一行已落地、两行等人——**§3 的标题"三条要等新条件的"因此对第一行不再成立**，
它的"新条件"由夹具顶掉了；改标题会动 §3 那一带的行号，而**本文是被别处按行号引用的**
（上一次引用门禁的归档 `docs/verification/p36-debt5-citations-v2/audit.log` 里就列了 10 条指向本文的活锚），
所以只在这里说明，不动标题。本轮 §13 是**在文件末尾追加**，同样为了不移动任何既有行。

