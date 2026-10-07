# 07 系统监控 · 设计稿 ↔ 实现 逐元素对照（fidelity-monitor）

> **结论先行**：A 稿（正常态首屏）与实机在**结构、文案、几何**三层全部对得上——页头 46pt、
> 读数卡 48pt、每核行距 36pt、进度条轨道 683×6pt、MMKeyRow 行距 22pt、卡内边距 12pt、
> 滚动区边距 16pt 都是**量过实机像素**的，不是估的。
> 真正的缺陷集中在**降级语义**上：本页有 3 处把"还不知道"写成了"已知的结论"
> （公元 1 年的采样时间、把未采样说成 host_statistics64 失败、把"查到空列表"说成"读取失败"），
> 这正好踩在本项目"测量诚实"的红线上，判 **实现该改 · 高**。
> 另有 1 处**设计稿全站性错误**（侧栏footer 画错），07 稿沿用了 01–06 的错误画法。
>
> **主代理复核后的处置（2026-09-30）**：上表 3 处"把不知道写成结论"里，**I1（0001-01-01 采样时间）、
> I2（未采样归因给 host_statistics64）已改**，I6/I7（进程失败态）改了文案那一半、
> 枚举返回那一半留着。逐条处置记在 §2。审计给的行号有 7~11 行漂移，已按当前代码重新核对。
> 另：复核时我自己怀疑 `proc_listallpids` 返回的是**字节数**（那样 `for i in 0..<count` 会越界读 `pids`）——
> **本机实测否掉**：523 个进程时返回 523 而不是 2092，按 pid 个数计，现有写法安全，未改。
>
> 逐元素对照 **47 项**，其中 **16 项存在需归属的差异**（**高 2 / 中 6 / 低 8**，另有 1 项仅记录不判改）：
> **实现该改 11 条**（I1–I10b）、**设计稿该改 5 条**（S2–S6）、**两边都改 1 条**（S1 侧栏 footer，全站）。
> **另有 13 项状态因为缺钩子而完全没能真机验证**（见 §4，逐条写明缺什么）。
>
> **P6.4 追加（2026-10-04，「温度与风扇」新卡）**：上面这些计数是 **2026-09-30 那轮审计的快照**，
> 不随新卡重算；新卡带来 **1 条实现该改（I11 · 红档无迟滞，低，**同日已改**）** 与 **1 条归协调层（S7 · 图标精灵形状，低，
> 附一条"键名不可读但**判不改**"）**，逐条见 §2.13 / §3.7，取证矩阵在 §4.2。
> §1.8 那张表的实现行号仍是旧坐标（新卡把文件整体下移 ≈90 行），用前先按符号名重找。
>
> **P6.5 复核（2026-10-04，把这份清单重新读了一遍代码）**：§2 那 11 条里有 **5 条其实早就落地了**——
> I3（磁盘"待差分"caption）、I4（`card()` 改调 `MMCard`）、I5（去掉 `(wired)` 括注，触发条件消了）、
> I6+I7（进程四态）全部在 **2026-09-30 的 `e84066a` / `c74f045`** 里做完了，只有 I4 的组件档位在前一个提交。
> **这份审计文档自己就是那条"上一轮的搜索结果不是依据"的老坑**：它记的是写下那天的代码，
> 落地那轮改了代码没回写清单，于是 4 天里挂着 5 条已完成项。逐条现状与现读行号见 §2.3–§2.7。
> 本轮真做的只有一条：**I9（Swap 零值文案）已改**（§2.10，取证 §4.3）。
> **这一页自己**还开着的只剩 **I8 一条**（网络速率在页面消失，低）——它卡的是画稿决定，不是代码决定（§2.9）；
> 另有两处**半开**：I2 剩下的那一半（`host_statistics64` 真失败与 `vm_page_size` 异常仍同一句，§2.2）、
> I10a/I10b（侧栏 220pt / 标题栏 52pt，全站骨架，归协调层，§2.11–2.12）。
> 再新增一条设计稿侧：**S8**（07 稿的「联动保留(wired)」括注落后于实现，方向与 S1–S7 相反）。

## 0. 对照方法（先说清楚哪些是量出来的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmmonitor/07-monitor.html`（**5 个 artboard**：A 正常态首屏 / B 折叠线以下 / C 采样中首帧 / D 降级态合集 / **E 温度与风扇（P6.4 新增）**） |
| 渲染 | `cd docs/design-system && ./render.sh screens/mmmonitor/07-monitor.html 1160 6515` → `screens/mmmonitor/07-monitor.png`（2320×13030，2x）。**高度是量出来的不是猜的**：先按 7000 渲染，再用 PIL 逐行找最后一条非背景行（y=12974），加 28px 页底留白得 6515——上一版按 4600（D 稿加 D3a 时同理），E 稿加了 ≈1890px。**猜高度的代价是稿尾挂一段纯灰底**，看起来像"内容就这么长" |
| 实机 | 首轮：`build/MacMaster.app`（**未重新构建**），`MM_OPEN_MODULE=monitor` 启动，按 **pid** 匹配 windowid，`screencapture -o -x -l<id>` → `/tmp/mmshot/70-monitor-real.png`（1100×700 @1x，深色模式，Mac mini M4 / 10 核 / 24 GB，2026-09-30 03:16）。**P6.4 轮**：`Scripts/p64-capture.sh` → `docs/verification/p64/`（浅色 8 张）与 `docs/verification/p64-dark/`（暗色 8 张），窗口 1100pt 宽 @2x，含**不注任何夹具的实机真读数**那张 |
| 像素取证 | CoreGraphics 逐行/逐列取色（`/tmp/vscan.swift`、`/tmp/hscan.swift`、`/tmp/cropimg2.swift`），所有"实机"数字都来自这条路径。**P6.4 轮改用 PIL 直接扫 `docs/verification/p64/01-monitor-sensors-real.png`**（脚本已入库的那张，不是 /tmp 里的临时件）：温度行 8 个行中心 y=469/540/613/685/757/829/901/973 → **行距 71.5px@2x ≈ 35.75pt = 36pt**，与稿内 `.trow`（28 行高 + 8 卡内间距）对上了 |
| 可用钩子 | **`MM_OPEN_MODULE=monitor` + `MM_MONITOR_HOLD` + `MM_MONITOR_FIXTURE` + `MM_MONITOR_CARDS`**（后两个见 §4.1；`MM_MONITOR_CARDS` 是 P6.4 为「温度与风扇」补的卡过滤）。审计首轮那句"本模块没有任何内容钩子（grep 0 命中）"已过期，保留在原文里不删 |
| 硬约束 | 全程未发合成鼠标/滚轮/键盘事件；未改 `Sources/`、`Packages/`；未跑 `swift build` / `make-app.sh`；未 `pkill`，只 `kill` 自己启用的实例 |

实机测得的锚点（本表所有"一致"判定的基准）：

- 标题栏 0→52（1px 黑线在 y=52）→ **52pt**；页头 52→98（底部分隔线 y=97）→ **46pt**，页头填充 `(30,30,30)` = `controlBackground/textBackground` 暗档。
- 侧栏右边界 1px 分隔线在 **x=220**；首张卡左边缘（描边）在 **x=236** = 220+16 → 滚动区 `MMGap.lg` 边距实测成立；卡右边缘 x≈1084 → 右侧同样 16pt。
- 卡填充 `(40,40,40)`、页面底 `(43,43,44)` → **卡比页面底更暗 3 级**（`underPageBackgroundColor` vs `windowBackgroundColor`），这条直接决定了 §3 的 S3。
- 读数卡：描边 y=113/114、填充 115→162 → **整卡 48pt**（稿内按 13+2+18+2×8 复算 = 48，一致）。
- 每核进度条轨道 **x 317→1000（683pt 宽）× 6pt 高**：236(卡)+12(内边距)+56(标签列)+12(间距)=316≈317；1084-12-60(数值列)-12=1000 ✓ 与 `MMMonitor.swift:83,88` 的 56/60 硬编码列宽互相咬合，说明列宽实现正确。
- 每核行 **36pt 间距** = `rowCompact` 28 + 卡内 `MMGap.sm` 8 ✓；MMKeyRow **22pt 间距** = 15 行高 + 8 ✓。

## 1. 逐元素对照表

严重度定义：**高** = 用户会读到错误结论（把未知当已知 / 把失败当正常）；
**中** = 视觉或语义明显跑偏，但不产生错误结论；**低** = 像素级偏差、占位数据、口径注脚。

### 1.1 页头（MMPageHeader）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「系统监控」 | `MMMonitor.swift:44`；模块名 `:8` | ✅ | 实机逐字一致（P16 现读：本文此前两处都记 27 行/模块名 7 行，是页头之上加了 `headerSubtitle` 之后漂的） | — | — |
| 副标题「上次采样 2026-09-30 03:16 · 实时更新」 | `MMMonitor.swift:39` + `MMFormat.dateTime` | ✅ | 实机格式 `yyyy-MM-dd HH:mm` 一致；分钟粒度不刷新时看起来"停在旧值"是设计选择，稿内已注明 | 低 | 记录 |
| C/D 稿 frame-0 副标题「上次采样 **0001-01-01 08:05** · 实时更新」 | `MetricTypes.swift` `MetricSnapshot.empty.sampledAt = .distantPast`，经 `MMMonitor.swift:37-39` 渲染 | ❌ | 首帧（`enable()` 之前）把"还不知道上次采样时间"渲染成**公元 1 年的具体时刻**；`nil → "—"` 的约定只加在数值上，没加在时间上 | **高** | ~~实现该改 I1~~ **已改**（`:38` 现读：`hasSampled` 为假时改口「尚未完成首次采样」） |
| 右侧「菜单栏监控」+ switch，标签在左 | `MMMonitor.swift:45-49` `.toggleStyle(.switch)` | ✅ | 实机标签在左、开关在右，位置一致 | — | — |
| 关闭态（switch off） | `menuBar.disable()` → 采样循环被 cancel | ⚠️ 未画 | 关了就停采样，页面会**冻在最后一帧**而不是变空；稿内没有这一档，实机也无法验证（见 §4） | 低 | 设计稿该改 S5b |

### 1.2 顶部读数条（MMStatItem × 4）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 四个标签逐字：「CPU 总占用」「内存」「磁盘 读」「磁盘 写」 | `MMMonitor.swift:57-60` | ✅ | 实机一致（含"磁盘 读"中间那个空格） | — | — |
| 百分比 1 位小数（35.8% / 80.2%） | `MenuBarManager.percentText:169` → `MMFormat.percent` | ✅ | 0.4% 不会被压成 0% | — | — |
| 速率 `compactBytes + "/s"`（1.9 MB/s、293.3 KB/s） | `MMMonitor.swift:64-67` | ✅ | 稿内数值取自实机 | — | — |
| nil → 「—」（C 稿 CPU/磁盘四项） | `:65`、`MenuBarManager:170` | ✅ | 空值不塌成 0 | — | — |
| 卡片几何：48pt 高、6pt 圆角、`cardBackground` + separator 描边、v8/h12 内边距 | `MMDesign.swift:363-373` | ✅ | 实机 48pt（115→162）与稿内一致 | — | — |
| 网络速率（`networkUp/DownBytesPerSecond`） | 快照里有（`MetricTypes.swift`），菜单栏菜单里显示（`MenuBarManager:160-164`），**页面一处都不用** | ❌ | 页面叫「系统监控」却只有磁盘 IO 没有网络；同一份数据在两个出口口径不一致 | 低 | 实现该改 I8 |

### 1.3 每核 CPU 卡

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「每核 CPU」+ SF Symbol `cpu`（16pt 次级色） | `MMMonitor.swift:72` | ✅ | 一致 | — | — |
| 「核 1」…「核 10」（1-based） | `:80` `"核 \(index + 1)"` | ✅ | 实机 10 行、从 1 开始 | — | — |
| 标签列 56pt / 数值列 60pt 右对齐 / 行高 28pt / 条高 6pt | `:83,88,90`、`CoreUsageBar:231` | ✅ | 由轨道 317→1000 反推，四个数全部对上 | — | — |
| A 稿数值 17.5/14.0/7.7/4.8/2.4/2.4/74.2/77.9/78.0/77.5% | 实机截图 | ✅ | 条宽与文字双核对：核 1 条 317→435 = 118/683 = 17.3% ≈ 17.5% ✓ | — | — |
| **空槽**（只画 `fillActive` 轨道，数值列「—」） | `CoreUsageBar:224`（`if let usage`）+ `:216` 注释 | ✅ | C 稿 10 行全空槽 = 首帧真实形态（`CPUDiff.perCoreUsage:59-61` 无上一组 → `Array(repeating: nil, count: 10)`） | — | — |
| ≥85% 红档（条与数值同时 `destructive`） | `:87`、`:226` | ⚠️ 仅 D 稿示意 | 本机峰值 78.0%，**实机未触发**；D 稿按 91.4% 画 | — | 见 §4 |
| `perCoreCPU.isEmpty` → 卡内单个居中「—」 | `:73-76` | ✅（代码分支） | 与"10 行空槽"是两种信息量，稿内分开画（D1 vs C）；实机未截到 | — | 见 §4 |

### 1.4 磁盘 IO 卡

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「磁盘 IO」+ `internaldrive` | `MMMonitor.swift:99` | ✅ | 一致 | — | — |
| 「读取」「写入」两行，`monospaced: true` | `:102-103` | ✅ | 实机等宽数字成立 | — | — |
| `.unavailable` → 两行「—」+ reason 原文整行 caption | `:104-110` | ✅ | D2 稿把 `DiskIOReader` 的四种 reason 原文照抄（`MetricReaders.swift`），含 `<machErrorString>` 占位 | — | — |
| **首帧 `.ok` + 速率 nil** → 两行「—」且**没有**原因行 | `SystemMetricSampler.swift:94`（`interval` 为 nil 时不填 `diskRate`，`diskStatus` 仍 `.ok`）+ `MMMonitor.swift:160-164` | ✅ | ~~与 `.unavailable` 在 3 米外**完全同形**~~ **I3 已改**（`e84066a`，2026-09-30，复核 2026-10-04）：`.ok` 且任一速率为 nil 时补一行 caption「等待下一次采样计算速率」，三态在图元层可分 | — | ~~实现该改 I3~~ **已改**（见 §2.3） |

### 1.5 内存卡

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「内存」+ `memorychip` | `MMMonitor.swift:179` | ✅ | 一致 | — | — |
| 五个标签逐字：「已用」「活动」「联动保留(wired)」「压缩」「Swap」 | `:181-186` | ⚠️ 稿侧过期 | **实现侧已在 `e84066a` 去掉 `(wired)` 括注**（全站纯中文惯例），这一行是 2026-09-30 那轮的快照。稿内 D/B 两稿的标签列仍写「联动保留(wired)」→ 归 §3 设计稿该改（S8） | 低 | 设计稿该改 S8 |
| 「已用」= `bytes(used) / bytes(total)` | `:181`，口径 `MemoryMetrics.usedBytes = active+wired+compressed`（`MetricTypes.swift`） | ✅ | B 稿卡头把"不含 inactive"的口径写死 | — | — |
| 「联动保留(wired)」在 80pt 标签列内**换行** | `MMDesign.swift:380` `.frame(width: 80)` | ✅（触发条件已消） | 括注去掉后本页最长标签 4 汉字，80pt 装得下（实机 `docs/verification/p65/0*` 五行行距 22pt 无折行）。**令牌没动**，5 汉字是上限、6 个就折行 → 见 §2.5 的关闭条件 | — | ~~实现该改 I5~~ **已改（`e84066a`）** |
| `memory == nil` → 「内存读数不可用（host_statistics64 失败），显示 —。」 | `MMMonitor.swift:189-197` | ❌ | 这句在**三种**不同成因下都会出现：①`.empty`（压根没采）②`host_statistics64` 真失败 ③`vm_page_size` 异常。把"还没采到"写成"系统调用失败"= 给出错误的因果结论 | **高** | ~~实现该改 I2~~ **已改**（②③仍同句，见 §2.2） |
| `swapAvailable == false` → Swap 行「—」 | `:186` → `MenuBarManager.swapText` | ✅（夹具已拍） | D 稿画了；本机 swapAvailable=true，实机拍不到 → `MM_MONITOR_FIXTURE=swapOff`，照片 `docs/verification/p65/03`（+ 暗档） | — | 见 §4 |
| `swapAvailable == true` 且读到 0 → ~~「0 字节 / 0 字节」~~「0 字节（未使用）」 | `MenuBarManager.swift:186-203`（`MMFormat.bytes` 的 <1000 特判仍在，只是不再一行用两次） | ✅ | 中文语境里读起来像坏了 → **I9 已改（2026-10-04）**；零值档实机拍不到（本机 used≈800M），夹具 `swapZero` 摆拍，照片 `p65/02` | — | ~~实现该改 I9~~ **已改**（见 §2.10） |

### 1.6 进程 TOP 10 卡

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「进程 TOP 10」+ `list.bullet` | `MMMonitor.swift:293` | ✅ | 一致 | — | — |
| 唯一动作 = 图标按钮 `arrow.clockwise`（无"结束进程"） | `:294-301` | ✅ | 只读页无写操作，稿内明确写出这一条 | — | — |
| 行内文案「CPU 时间 mm:ss」+ 右对齐 80pt 的 `MMFormat.bytes` | `:319-325` | ✅ | 未沿用旧实现的误标「CPU x%」（`:317-318` 注释即为此保留） | — | — |
| 名称回落 `pid:NNN` | `ProcessReader:428` `name.isEmpty ? "pid:\(pid)"` | ✅ | B 稿画了 `pid:4417` | — | — |
| 行 28pt + `contentBackground` 药丸 + `MMRadius.control` + 横向 12pt | `:327-329` | ✅ | — | — | — |
| `processes.isEmpty && !processLoadFailed` → **4 条 `MMSkeletonRow`** | `:302-303` | ✅（代码分支） | D5 稿按 1:1（15 方块 + 120 短条 + 56 短条，行高 44）画；实机在折叠线以下且无钩子，未截到 | — | 见 §4 |
| `processLoadFailed` → `MMEmptyState(title:"进程列表读取失败", detail:nil)` | 原 `:151`，现 `:304-306` | ✅ | ~~失败态既没有原因也没有下一步~~ **I6 已改**：`detail:` 给「无法枚举系统进程。点卡片上方的刷新按钮重试。」；`action:` 仍不加（重试按钮就在同一张卡右上角 `:294-301`） | — | ~~实现该改 I6~~ **已改**（见 §2.6） |
| `processLoadFailed = procs.isEmpty` | 原 `:184`，现 `ProcessReader.topProcesses():399-436` | ✅ | ~~"查到空"与"查失败"压成同一个 UI 态~~ **I7 已改**（`e84066a`）：返回 `ProcessLoadResult{state, processes}`，`proc_listallpids` 给 0 个 → `.failed`（`:402`），枚举有结果但详情全拿不到 → `.empty`（`:436`），UI 各走一句文案（`:304-309`） | — | ~~实现该改 I7~~ **已改**（见 §2.7） |

### 1.7 温度与风扇卡（P6.4 新增，E 稿 ↔ 实机 `docs/verification/p64/`）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「温度与风扇」+ `thermometer.medium`（16pt 次级色） | `MMMonitor.swift:197` | ✅ | 实机照片 01 逐字一致；图标形状见 S7 附注 | — | — |
| 温度行：键名列 56pt `.callout.monospaced()` 次级色 + 数值 `.callout.monospacedDigit()` 撑满右对齐 | `:214-227` | ✅ | **行距实测 36pt**（8 个行中心 y=469…973 @2x，间距 71.5±0.5px = 28 行高 + 8 卡内间距），与稿内 `.trow` 一致。稿内刻意**不复用** `.crow .num` 那个 60pt 定宽列——那是每核 CPU 的口径，本卡数值是"撑满后右对齐" | — | — |
| 只显示最高 8 行 + 一行 caption 交代总数 | `:191`、`:228-233` | ✅ | 实机脚注原文「按键值降序显示最高的 8 个，本机共 **174** 个可信温度点。」——174 与 `Scripts/smc-probe.swift` 独立测得的 `flt ` 键数**逐字相同**，这条是"页面报的数能回到探针"的双向核对 | — | — |
| 降序 + 同值按键名升序 | `Sensors.swift` `SensorTemperature: Comparable` | ✅（一致性核对） | 照片 01（2026-10-04 重拍）里两组同值都按键名升序：`TCMz / Tp0c / Tp3X` 同为 81.3 °C，`Tp0Z / Tp3P` 同为 80.0 °C。**这条不是证明**：显示只到 0.1 °C，屏上相等不等于底层相等；判定本身钉在 `SensorTests` 的 `Comparable` 用例上 | — | — |
| 键名用 SMC 原文、不编 CPU/GPU 归属 | `:216` 注释 | ✅ | 实机显示 `TCMz`/`Tp0W`/`Tp3P` 这种原始 4 字符，没有任何一处被翻译成"CPU 温度" | — | — |
| 从冷到热 ≥90 °C 转 destructive、键名列不转；已红着的要跌到 85 以下才复原（I11 迟滞） | `:206-211`、`:237-241` | ⚠️ 仅夹具 | 本机**跨不过 90**：空闲最高 54.5 °C，8 个 `yes` 循环压满 ~40 秒也只到 **89.0 °C**（`docs/verification/i11-hysteresis/`，26 帧零红）。红档取证走 `MM_MONITOR_FIXTURE=sensorsHot`（照片 06 + 暗档 06）；**过渡态没有照片**，只有单测，原因写在 §4.2 末尾 | 低 | I11 **已改**（见 §2.13） |
| `.unavailable` → 值位「—」+ reason 原文 caption | `:205-212` | ✅（夹具） | 照片 03：「IOServiceOpen(AppleSMC) 失败：kIOReturnDenied」整行照排。**这句 reason 是夹具给的**，本机 SMC 打得开，真失败态无法自然构造；七句 reason 逐句有出处（连接层 4 + 装配层 3 + 首帧 1），全列在 E 稿卡外标注 | — | — |
| `fanCount == 0` → 「无（SMC 报告本机 0 台风扇）」 | `:241-242` | ✅（夹具） | 照片 04；本机 `FNum`=1，这一档只能注入 | — | — |
| `fanCount == nil` → 「风扇 —」+「FNum 键没读到，风扇数量未知（未知不等于 0 台）。」 | `:248-255` | ✅（夹具） | 照片 05。与上一档**是两句不同的话**，这条正是本项目"测量诚实"红线在新卡上的落点 | — | — |
| 风扇行 `MMKeyRow(…, monospaced: true)`，值「1000 RPM（区间 1000–4900）」 | `:245`、`fanText:258-264` | ✅ | 实机照片 01 逐字一致，含全角括号与 en-dash；`Mn/Mx` 缺任一时代码只写「2100 RPM」（不给假区间），这一支**没有照片**——本机四键齐全，夹具也没做这一档，只由单测钉住（`SensorTests` 的风扇取值用例） | 低 | 记录 |
| 卡片排在整页最后（进程卡之后） | `:56` | ✅ | 760pt 窗口里永远在折叠线以下，取证靠 `MM_MONITOR_CARDS=sensors`；相邻与卡间距另拍一张 `=process,sensors`（照片 07） | — | — |
| 首帧前（`MetricSnapshot.empty`）→「尚未完成首次采样」 | `Sensors.swift:150` `notSampled` | ✅（代码分支） | 与 `.unavailable` 同形、不同文案；**抢拍不到**（`.onAppear` 立刻 `enable()`），与 D3a 同一处置 | — | 见 §4 #4 |

### 1.8 卡片容器与全站骨架层

> **本表的实现行号是 2026-09-30 那轮审计的坐标**，P6.4 在文件里插入了「温度与风扇」一整段（≈90 行）后
> 已整体下移（例如私有 `card()` 从 `:191-213` 移到 `:333` 起）。**照抄会点到别处**，
> 用前先按符号名重找（`grep -n "private func card" MMMonitor.swift`）。§1.7 那张表的行号是 2026-10-04 现读的。
> **P6.5 复核（2026-10-04）已把本表与 §1.5/§1.6 的行号换成现读值**：`card()` 现在在 `MMMonitor.swift:349-366`。


| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 页面卡：`underPage` 底 + 12pt 内边距 + 8pt 圆角 + separator 描边 | `MMMonitor.swift:349-366`（私有 `card()`，内部是 `MMCard(padding: MMGap.md, style: .underPage)`） | ✅ | 实机卡底 (40,40,40)、描边 1px，与稿内 `.mcard` 一致 | — | — |
| ~~但 `card()` **没有复用 `MMCard`**~~ | `MMDesign.swift:902-936`（`MMCardStyle.content` / `.underPage` 两档 + `padding:` 参数） | ✅ | ~~同一 App 里两套"卡片"~~ **I4 已改**（`c74f045` 补档位、`e84066a` 本页改调组件，均 2026-09-30）：底色这一维收口进组件，内边距这一维由本页**显式选** 12pt（密度按实测量到的 22pt/36pt 行距定的，见 §2.4） | — | ~~实现该改 I4~~ **已改** |
| 块间距 16pt、滚动区内边距 16pt | `:35,42` | ✅ | 实机 98→114=16、卡间 165→180=16 | — | — |
| **无底部动作条** | 实现里确实没有 `MMActionBar` | ✅ | 只读页不加动作条，稿内注明理由 | — | — |
| 侧栏宽 216pt（`MMMetric.sidebar`） | 实机分隔线在 **x=220** | ❌ | 全站骨架 +4pt | 低 | 实现该改 I10a |
| 标题栏 38pt（`--titlebar-h`） | 实机 **52pt**（黑线 y=52） | ❌ | 全站骨架 +14pt，等于每页可视高度少 14pt（本页折叠线位置因此前移） | 低 | 实现该改 I10b |
| 页面底 = `--c-content-bg`（白） | 实机页面底 = `windowBackgroundColor`（暗档实测 43,43,44），卡才是 underPage(40,40,40) | ❌ | 稿内"白底 + 灰卡"的对比度远高于实机"灰底 + 更深灰卡"（差 3 级 vs 差 8 级） | 低 | 设计稿该改 S3 |
| 侧栏 footer = 1px 分隔线 + 「设置」nav-item | 实机 = 磁盘容量行（`Macintosh HD` + `2%` + 红色容量条）+ **带边框的「设置」按钮** | ❌ | 07 稿沿用 01–06 的错误画法；实机截图左下已核对 | **中** | 设计稿该改 S1 |
| 侧栏尾数「2.4 GB」「46」 | 本页无来源 | ❌ | 纯占位数据 | 低 | 设计稿该改 S2 |
| `tokens.css` `.card` 用 `--c-card-bg` | 本页卡是 `cardBackground` = underPage | ❌ | 稿内只能自写 `.mcard`，说明 token 层缺一个 under-page 变体 | 低 | 设计稿该改 S4 |

## 2. 实现该改（11 条 + 1 条两边都改，按严重度排序）

1. **【高】I1 · 未采样时的时间戳 —— ✅ 已改（2026-09-30）**
   `MetricSnapshot.empty.sampledAt = .distantPast` 会渲染成「上次采样 **0001-01-01 08:05** · 实时更新」
   （Asia/Shanghai 下 `timeIntervalSince1970 = -62135769600`，本机实测）。
   → 采纳第二个方案：`MetricTypes.swift:227` 新增 `MetricSnapshot.hasSampled`（`sampledAt != .distantPast`），
   `MMMonitor.swift:27-31` 页头在未采样时出「尚未完成首次采样」。没改成 `Date?`：`sampledAt` 有 6 个调用点，
   把哨兵集中成一个具名字段比铺开 Optional 波及面小，且 I2 需要的是同一个判据。
   单测：`Packages/MMMonitor/Tests/MMMonitorTests/SampledAtSentinelTests.swift`。
   实机核对：采样后页头「上次采样 2026-09-30 04:07 · 实时更新」（`/tmp/mmshot/mon-fix.jpg`）；
   未采样那一帧抢拍不到（`.onAppear` 立刻 `enable()`），按代码重绘，见 07 稿 D3a。
2. **【高】I2 · 内存不可用的归因写死 —— ✅ 已改（2026-09-30）**
   「内存读数不可用（**host_statistics64 失败**），显示 —。」在 `.empty`（压根没采）时同样出现。
   → `MMMonitor.swift:135-142` 按 `hasSampled` 分流：未采样走「尚未完成首次采样，这里还没有内存读数。」，
   真失败才点名 API。与磁盘 IO 卡（`.unavailable(reason:)`）的口径对齐了。
   仍留一半：`②host_statistics64 真失败` 与 `③vm_page_size 异常` 两种真失败在采样器里没区分，
   现在都归到同一句点名 API 的文案下——比原来准，但还没到"逐因逐句"。
   **复核 2026-10-05（P7）：这"一半"不成立，本条可以整条划掉。**
   现读 `MetricReaders.swift:140-166`：`MemoryReader.read()` 返回 nil 的路径**只有一条**
   （`:148` `kr != KERN_SUCCESS`，就是 `host_statistics64` 本身失败）；`vm_kernel_page_size`
   在 `:152` 只是参与换算，它异常会算错数而**不会**走到 nil，所以它不可能是那句文案的另一种成因。
   `sysctlbyname` 失败另有 `swapOK=false` 单独承载（`:155/:162-164`），也不借这句话。
   → `MMMonitor.swift:194` 那句「（host_statistics64 失败）」**是逐因的，不是概括的**；
   要再"逐因逐句"就得先造出第二个 nil 成因，而目前没有。**不再占欠账。**
3. **【中】I3 · 磁盘 IO「还没法差分」与「读不到」同形**（`SystemMetricSampler.swift:94` / `MMMonitor.swift:101-106`）
   首帧 `.ok` + nil 速率时两行「—」且无原因行。→ 建议：`.ok` 但 `diskRate == nil` 时补一行
   caption「需两次采样才能算出速率」，让三态（有数 / 待差分 / 不可用）在图元层可分。
   **✅ 已落地（复核 2026-10-04：`e84066a`，2026-09-30）**——本条在审计文档里挂了 4 天没人划掉，
   是因为落地那轮把它连同 I4–I7 一起写进了代码、没回写这份清单。现状：`MMMonitor.swift:160-164`
   在 `.ok` 且任一速率为 nil 时补 caption「等待下一次采样计算速率」，三态在图元层已可分
   （文案与这里的建议不同句，判据相同）。
4. **【中】I4 · 私有 `card()` 复刻 `MMCard`**（`MMMonitor.swift:191-213` vs `MMDesign.swift:770-786`）
   底（underPage vs controlBackground）与内边距（12 vs 16）两套。→ 建议：`MMCard` 增加
   `background:` 参数或加一个 `MMCardStyle.underPage`，本页改为调用组件。
   **✅ 已落地（复核 2026-10-04）**：`MMCardStyle` 两档在 `MMDesign.swift:902-914`（`c74f045`，2026-09-30），
   本页 `card()` 只剩标题行 + 内容，容器是 `MMCard(padding: MMGap.md, style: .underPage)`
   （`MMMonitor.swift:349-366`）。**内边距这一档没有统一到 16**：本页仍是 `MMGap.md`(12)，
   这是选出来的而不是漏的——监控页六张卡的密度按 §0 实测的 22pt/36pt 行距定的，改到 16 会整体变长。
   组件侧的"两套底色"已收口，剩下的只是这一页主动选了另一档内边距。
5. **【中】I5 · `MMKeyRow` 80pt 标签列撑不住长标签**（`MMDesign.swift:344` + `MMMonitor.swift:122`）
   「联动保留(wired)」折行、破坏实机 22pt 行距。→ 建议：标签列改为按内容自适应（`Grid`/`alignmentGuide`）
   或把令牌提到 96pt；顺带决定「联动保留」是否保留英文括注（全站措辞惯例是纯中文，括注属例外）。
   **✅ 触发条件已消（复核 2026-10-04：`e84066a` 去掉了 `(wired)` 括注）**：本页标签现在是
   「已用/活动/联动保留/压缩/Swap」（`MMMonitor.swift:181-186`），最长 4 汉字，80pt 装得下。
   **令牌本身没动**（`MMDesign.swift:380` 仍是 `.frame(width: 80)`），所以这条的**结构风险还在**：
   5 汉字是实测上限（磁盘页的「所在文件夹」「可执行文件」正好顶格），6 个就折行。
   归"关闭 + 附条件"：下一次有页面写进 6 汉字标签时按建议改自适应，而不是等它先折行。
6. **【中】I6 · 进程失败态没有下一步 —— ✅ 已改（2026-09-30，复核 2026-10-04 收口）**
   `MMEmptyState(..., detail: nil)`（原 `:151`，2026-09-30 那轮记的是 `:164`，现 `:304-306`），而组件本身支持 `detail`/`action`。
   → 当时传 `detail: "枚举系统进程没有拿到任何结果。点卡片上方的刷新按钮重试。"`。
   **这一句在 `e84066a` 里随 I7 一起改了措辞**（因为它当时说的是"查到空"，而失败态另有其人）：
   现在 `.failed` 是「无法枚举系统进程。点卡片上方的刷新按钮重试。」（`:305-306`），
   `.empty` 是「枚举已完成，但没有取得可读取的进程详情。可刷新重试。」（`:308-309`）。
   **没有**点名 `proc_pidinfo`：那条路径根本没调它，失败点也可能是 `proc_listallpids`，
   指错原因比不说更糟。`action:` 未加——重试按钮已经在同一张卡右上角（`:294-301`），再加一个是同一个动作画两个入口。
7. **【中】I7 · 「查到空」被当成「查失败」**（原 `MMMonitor.swift:198` `processLoadFailed = procs.isEmpty`）
   → 建议：区分 `ProcessReader` 的返回（`count > 0` 失败 vs 结果为空），空结果走 `MMEmptyState(title:"没有可显示的进程")`。
   **✅ 已落地（复核 2026-10-04：`e84066a`，2026-09-30）**：`topProcesses()` 现在返回
   `ProcessLoadResult{state, processes}`（`topProcesses():399-436`、结构体 `:444`），`proc_listallpids` 返回 0 个 →
   `.failed`（`:402`），选出的进程详情全拿不到 → `.empty`（`:436`），UI 四态分支在 `:302-310`。
   当初说"仍未做的那一半"就是这条，它做完了 I6 才成立——两条文案指向的是两个不同事实。
8. **【中】S1 关联 · 侧栏 footer 与实机不符**（见 §3，实机是容量行 + 带边框设置按钮）——**这条两边都要改**：
   设计稿要重画，同时实现里侧栏 footer 的容量条/设置按钮在 01–06 六张稿里全部缺失，属全站缺口。
9. **【低】I8 · 网络速率在页面消失**：快照有 `networkUp/DownBytesPerSecond`、菜单栏有显示（`MenuBarManager.swift:320-322`）、页面一处不用。**仍未做**，是这一页唯一还开着的图元/文案项（I2 的半条是"逐因逐句"的粒度问题，I10a/b 在骨架层）。
   没顺手做的理由：顶部读数条是 `MMStatItem × 4`（一行四个，`MMDesign.swift:390`），加网络进出要变 6 个——
   要么换行（页头高度 +一行，影响 §0 量的折叠线落点），要么把磁盘读写挤成一行两项。这是**画稿决定**，不是代码决定。
10. **【低】I9 · Swap 读到 0 输出「0 字节 / 0 字节」**（`MMFormat.bytes` <1000 特判）→ 中文读起来像坏了。
    **✅ 已改（2026-10-04，P6.5）**：文案抽成 `MenuBarManager.swapText(_:compact:)`（`MenuBarManager.swift:186-203`），
    三档：**读不到 sysctl** → 「—」（原样）；**读到 0 且总量也是 0** → 「0 字节（未使用）」；
    **其余** → 「已用 / 总量」照原样对仗。页面（`MMMonitor.swift:186`）与菜单栏下拉（`MenuBarManager.swift:305`，紧凑单位）都走它，
    同一句话不再有两个人质。**只在两侧同为 0 时才省略对仗**——一侧有数就照报，不替用户下"未使用"的结论。
    `MMFormat.bytes` 本身没动：那个 <1000 特判在清理工具里是对的（几百字节的真实体积不能塌成 "0 KB"），
    错的是一行里用两次再拼斜杠，属调用方。
    **实机拍不到零值**：本机 `sysctl vm.swapusage` 是 used≈800M / total=2048M（照片 `p65/01`），
    所以新增夹具档 `swapZero`（`swapAvailable=true` + 两个 0）。顺带修掉一个夹具自身的坑：
    `populated` 底座原来也是 0/0，于是 `populated` 与 `swapZero` 在照片上同一个样，两档合成一档——
    底座改成真实形状 800 MiB / 2 GiB（`MonitorFixtureHooks.swift:171-179`）。
    取证：`Scripts/p65-swap-capture.sh` → `docs/verification/p65/` 与 `p65-dark/` 各 4 张
    （实机非零 / swapZero / swapOff / populated）。单测 6 条在 `FormatTests`，包内 **53 条全绿**。
11. **【低】I10a · 侧栏实现 220pt vs 令牌 216pt**（实机分隔线 x=220）。
12. **【低】I10b · 标题栏实现 ≈52pt vs 令牌 38pt**（实机黑线 y=52）→ 每页可视高度少 14pt，直接影响本页折叠线落点。
13. **【低】I11 · 温度红档没有迟滞（P6.4 新卡带来，2026-10-04）**——**已改（同日）**：
    `temp.celsius >= 90` 是单点判定，而本机在截图负载下实测最高 **89.4 °C**（`p64-dark/01`），离阈值 0.6 °C。采样每 2 秒一帧，
    数值在 89.x↔90.x 之间摆动时这一行的颜色会**闪**。判低不判中：闪的是颜色，数字本身每一帧都是真读数。
    → 建议：进出双阈值（进 90 / 出 85），或者干脆不转色、改成行尾一个"偏高"徽章。
    **不要**改成"把阈值提到 95 就看不见问题了"——那是把判据挪到测量够不着的地方。

    **落地（2026-10-04）**：判定抽成 `HotBand.swift`（`HotBand` = 进/出双阈值，`HotBandTrack` = 逐帧热键集合），
    视图侧 `MonitorView.hotBand = HotBand(enter: 90, exit: 85)`，颜色读 `hotSensors.isHot(temp.key)`。
    **进阈值 90 一个字没改**，改的只是"什么时候复原"（跌回 85 以下才算不热）——审计那条反模式没踩。
    两个坑记下来：① 夹具与 `MM_MONITOR_HOLD` 是在 `.onAppear` 里同步落到 snapshot 上的，
    `.onChange` 不保证抓到这一次同周期变化，所以 onAppear 末尾补了一次播种（少了它，照片 06 会拍成白字）；
    ② 每帧整体替换热集合，这一帧没出现的键自动掉出——不需要为"读不到了"单独写退出判定。
    单测 8 条在 `HotBandTests`（含两条振荡序列：`89.4→90.1→89.8→90.2` 单点判定给「白红白红」，
    迟滞给「白红红红」）。**这一档的过渡态没有照片**，原因见 §4.2 末尾。
    **每核 CPU 那一行是同一个形状**（`usage >= 0.85` 单点，`MMMonitor.swift:129`），
    本轮**没照搬**：负载下每核是 0/100% 两端走，没测到贴着 85% 摆动，改它等于凭空加状态。

## 3. 设计稿该改（8 条）

1. **【中】S1 · 侧栏 footer 全站画错**：01–07 七张稿都画成「分隔线 + 设置 nav-item」，
   实机是 **磁盘容量行（`Macintosh HD` + `2%` + 红色容量条）+ 带边框的「设置」按钮**
   （`/tmp/mmshot/70-monitor-real.png` 左下已核对）。07 稿为保持系列一致沿用了错误画法，
   **不改是为了不制造第七种侧栏**；正确做法是在 tokens/screen 层补一个侧栏 footer 组件，七张稿一起换。
2. **【低】S2 · 侧栏尾数占位**：「系统清理 2.4 GB」「应用卸载 46」在本页无数据来源，
   应改成与实机一致的 `1.26 GB` 或留空，避免"稿子里的数字看起来像实测"。
3. **【低】S3 · `.content` 底色与实机不符**：`tokens.css:297` 用 `--c-content-bg`（白），
   实机页面底是 `windowBackgroundColor`（暗档 43,43,44），卡才是 underPage(40,40,40)。
   → 需要 `.content--window` 变体；否则所有"卡浮在页面上"的页面对比度都被画重了。
4. **【低】S4 · 缺 under-page 卡片 token**：`tokens.css` `.card` = `--c-card-bg`，本页（含 `MMStatItem`）
   实际全是 `cardBackground` → 稿内只能自写 `.mcard`/`.stat`。补 `.card--under-page` 后删掉本地样式。
5. **【低】S5 · B/D 稿不是真实视口**：两稿按"卡片完整尺寸"展开（B 含内存+进程两卡、D 是 780pt 宽的卡片合集），
   真实窗口固定 1100×700。一旦实现补上内容钩子（例如 `MM_FIXTURE_*`），这两稿必须换成实机截图。
   **S5b**：另缺「菜单栏监控 = 关」这一档（关后页面冻在最后一帧，switch 变灰），本稿未画。
6. **【低】S6 · 稿内 A 稿折叠线比实机晚 14pt**：稿的标题栏按令牌 38pt 画、实机 52pt，
   所以稿内"磁盘 IO 卡完整 + 内存卡露头一行"在实机上会少露约 14pt。稿注已写明，
   修 I10b 后自动对齐。
7. **【低】S7 · `thermometer.medium` 的精灵形状与 SF Symbol 有出入（P6.4 新卡带来）**：E 稿用
   `icons.js` 里既有的 `#i-temp`（注释就标着对应 `thermometer.medium`），16×16 自绘的球泡比系统符号粗。
   这是**全站图标精灵层的共性**（01–09 每张稿都有几条这种出入），不在本页单修，归协调层。
   顺带记一条**判不改**的：卡里的键名 `TCMz`/`Tp0W`/`Tp3P` 对普通用户完全不可读，
   看起来像 bug 输出——但**给它编一个"CPU/GPU 温度"归属比不编更糟**，苹果没公布键位对应哪块硬件。
   将来若要加解释，唯一诚实的来源是厂商键位表；在那之前，稿与实现都只说"这是 SMC 原始键名"。
8. **【低】S8 · 内存卡标签的英文括注（P6.5 复核时新发现，2026-10-04）**：07 稿 B/D 两稿的第五行标签仍写
   「联动保留(wired)」，而实现已在 `e84066a`（2026-09-30）去掉括注（全站纯中文惯例，见 §2.5）。
   **这条是稿子落后于代码**，与 S1–S7 那类"代码落后于稿"方向相反，所以单列。
   改法：B/D 两稿标签逐字换成「联动保留」，并把 I9 那三档 Swap 文案（「—」/「0 字节（未使用）」/「已用 / 总量」）
   画进 D 稿——现在 D 稿只画了第一档，而 `docs/verification/p65/` 已经有后两档的照片可照抄。
   **本轮没顺手改稿**：07 稿一次重渲染 ≈40 秒且要重量高度（§0 那条"猜高度的代价"），
   而这一页攒了两处（S8 + S5b 的"菜单栏关闭"档）才值得重画一次，避免为一条措辞重排整稿。

## 4. 没能验证到的部分（逐条写明缺什么，不写"应该没问题"）

以下状态**只在代码里读到分支**，实机一张都没截到。原因统一是：本模块只有 `MM_OPEN_MODULE` 一个入口钩子，
**没有任何内容/状态钩子**（`grep -r "ProcessInfo.processInfo.environment" Packages/MMMonitor/` → 0 命中），
而合成点击/滚轮事件属于硬禁止项。

| # | 未验证项 | 为什么验不了 | 需要什么才能验 |
| --- | --- | --- | --- |
| 1 | 内存卡真实渲染（B 稿上半） | 在 1100×700 视口的折叠线以下；不能滚 | 内容钩子（如 `MM_MONITOR_SCROLL=bottom`）或临时把窗口调高（禁止） |
| 2 | 进程 TOP 10 真实列表（B 稿下半） | 同上，且 `loadProcesses()` 结果不可控 | 同上 + 一个能注入固定进程列表的 fixture 钩子 |
| 3 | `MMSkeletonRow` × 4（D5） | `onAppear` 后 `Task.detached` 通常在同一次绘制前就返回，实机几乎抓不到骨架帧 | 钩子延迟 `ProcessReader` 返回，或单测/预览快照 |
| 4 | `MetricSnapshot.empty` 帧（C 稿注脚 + D1/D2/D3） | `enable()` 在 `onAppear` 里立刻调用，`.empty` 只活不到一帧 | 一个"禁止自动 enable"的钩子 |
| 5 | 采样首帧（C 稿本体：CPU「—」+ 10 空槽 + 磁盘「—/—」无原因行） | 首帧后立刻被第二帧覆盖，无暂停钩子 | 采样节流/暂停钩子 |
| 6 | 磁盘 IO 四种 `.unavailable` reason 的实机排版（D2） | 本机 IOKit 正常返回，无法构造；沙盒限制分支需要换宿主 | 注入 `DiskIOStatus` 的钩子，或在单测里渲染 |
| 7 | 内存 `nil` 分支那句（D3） | `host_statistics64` 本机不会失败 | 注入 `memory = nil` 的钩子 |
| 8 | `perCoreCPU.isEmpty` → 单个「—」（D1） | `host_processor_info` 本机恒返回 10 核 | 同上 |
| 9 | 每核 ≥85% 红档（D 稿第一格） | 本机采样峰值 78.0%，未越线；不能人为压 CPU 制造（会影响其他并发代理） | 注入 `perCoreCPU` 的钩子 |
| 10 | `swapAvailable == false` 的 Swap 行（D 稿） | 本机 `sysctl VM_SWAPUSAGE` 正常 | 同上 |
| 11 | 「菜单栏监控」关闭态 | 关掉即停止采样，页面会冻帧，且需要点击开关（禁止） | 键盘/点击事件之外的开关钩子 |
| 12 | 浅色模式下的实机配色 | 实机截图取自**深色模式**；稿按设计系统浅色档重绘，浅色档只做了一次交叉核对 | 在浅色模式外观下重跑一次截图流程 |
| 13 | `MMFormat.bytes` 在各 locale 的确切输出（「1.42 GB」vs「1,42 GB」等） | 只在本机默认 locale 下量过 | 用 `MMFormat` 单测矩阵覆盖，不属于设计稿能验证的范围 |

**已验证的部分**（与上表相对，避免把整页都写成"没验过"）：页头标题/副标题格式/开关位置、
四个读数标签与格式、每核卡标题/图标/`核 N` 编号/56-60 列宽/28pt 行高/6pt 条与轨道几何、
A 稿 10 个百分比数值、磁盘 IO 两行标签与 monospace、卡片底/描边/圆角/内边距、
滚动区 16pt 边距与 16pt 块间距、页头 46pt、折叠线落点（磁盘 IO 卡后内存卡只露一行）。

## 4.1 可注入档位映射（#50 已落地 · 逐项补证据）

上面 13 项的"验不了"根因统一是：本模块只有 `MM_OPEN_MODULE` 一个入口，没有任何内容/状态钩子。
#50 已按 `MM_GUARDIAN_FIXTURE` 的写法补 `MM_MONITOR_HOLD` / `MM_MONITOR_FIXTURE`
（`MonitorFixtureHooks.swift` 纯数值注入，不读 `/tmp`、不采样、不写盘），逐项对应如下：

| §4 # | 未验证项 | 可注入档位 | 启动方式（按 pid 抓窗） |
| --- | --- | --- | --- |
| 1 | 内存卡真实渲染（B 稿上半） | `MM_MONITOR_FIXTURE=populated` | `MM_OPEN_MODULE=monitor` + 该钩子，窗口调高或滚动后 `screencapture -o -x -l<id>` |
| 2 | 进程 TOP 10 真实列表（B 稿下半） | `MM_MONITOR_FIXTURE=populated,processes` | 同上；`processes` 注入 10 条 `com.example.*` 固定列表 |
| 3 | `MMSkeletonRow` ×4（D5） | `MM_MONITOR_HOLD=hold` | 冻结 `.empty` 首帧，进程卡落在骨架态 |
| 4 | `MetricSnapshot.empty` 帧（C/D1/D2/D3） | `MM_MONITOR_HOLD=hold` | 同上，内存"尚未采样"、磁盘"尚未采样"、每核单「—」 |
| 5 | 采样首帧（C 本体） | `MM_MONITOR_HOLD=hold` | 同上 |
| 6 | 磁盘 IO 四种 `.unavailable` reason（D2） | `MM_MONITOR_FIXTURE=disk-unavailable:<reason>` | `<reason>` 为四种原文之一；正文照 `MetricReaders.swift` 拼接 |
| 7 | 内存 `nil` 分支（D3） | `MM_MONITOR_FIXTURE=memoryNil` | `hasSampled=true` 走"host_statistics64 失败"文案 |
| 8 | `perCoreCPU.isEmpty` → 单「—」（D1） | `MM_MONITOR_FIXTURE=perCoreEmpty` | 空数组 → 单「—」 |
| 9 | 每核 ≥85% 红档（D 稿第一格） | `MM_MONITOR_FIXTURE=perCoreRed` | 核 1 = 91.4%，条与数值同时 `destructive` |
| 10 | `swapAvailable == false` 的 Swap 行 | `MM_MONITOR_FIXTURE=swapOff` | Swap 行「—」（照片 `docs/verification/p65/03`，明暗两套） |
| 10b | **Swap 读到 0 那一档**（不在原 13 项里，是 §2.10 / I9 带出来的） | `MM_MONITOR_FIXTURE=swapZero` | Swap 行「0 字节（未使用）」（照片 `p65/02`）。**这一档与 `populated` 的区别只在 `swapAvailable` 一位**，而底座原本是 0/0 会让两档拍成同一张，所以 `populated` 同时改成真实的 800 MiB / 2 GiB（照片 `p65/04`） |
| 11 | 「菜单栏监控」关闭态 | `MM_MONITOR_FIXTURE=populated,menubarOff` | **P6.7 修正**：这一档自 #50 起**只被解析、从未被消费**（`grep -rn menubarOff` 只命中解析文件自己），所以本行原先写的"已覆盖"是空的。现在它真的走 `menuBar.disable()`——开关读的是 `isEnabled == (statusItem != nil)`，而壳层启动即 `enable()`，所以"不 enable"根本拍不出关态，**只有真把状态项摘掉才行**。照片 `docs/verification/p67-menubar-off/01↔02`：两张只差右上角那颗开关，其余数字逐位相同 |
| 12 | 浅色模式实机配色 | （非钩子） | 浅色外观下重跑 `render.sh` + 真机截图流程，单测矩阵不覆盖 |
| 13 | `MMFormat.bytes` 各 locale 输出 | （非钩子） | `MMFormat` 单测矩阵覆盖，不属设计稿验证范围 |

> **B/D 稿换夹具口径实测值**：`07-monitor.html` 的 B（内存卡+进程卡）与 D（降级态合集）artboard
> 现已可被上述钩子逐档构造真机态——复核时 B/D 两稿应**改用钩子注入后的实机截图**重出，
> 不再依赖"卡片完整尺寸"的稿内推演（原 S5 指出的"不是真实视口"问题随之消解）。

> **P6.7 哨兵值交叉验证（2026-10-04）**：上面这 13 行原先只被"两张照片 md5 不同"这种判据背书过，
> 而那个判据不充分（两张不同 ≠ 其中一张是夹具）。改用**真实路径生产不出来的值**逐档查一遍：
> `populated` 那张画面上是「上次采样 **2023-11-15 06:13**」，同一天不注夹具的实机帧读的是
> **2026-10-04**；温度键名 `TZZa…TZZh` 对上实机的 `TCMz/Tp0c/…`（174 个点）。两处都对上，
> 才敢说这一整批档位是真夹具。顺带一句机制上的澄清：注了夹具就**不会起后台采样循环**
> （`MMMonitor.swift:89` 那行"不 enable"就是为此），所以 §4 #2 猜的"夹具与真实采样抢同一个赋值口"
> 在本模块不成立——这条已写进 `docs/analysis/hook-ledger.md` §4 #4。

### 4.2 P6.4 新卡取证矩阵（8 档 × 明暗两套，`Scripts/p64-capture.sh`）

照片在 `docs/verification/p64/`（浅色）与 `docs/verification/p64-dark/`（暗色），同名同号。
**只有 01 与 08 是实机态**，其余六档都是夹具态——这个区分在稿子 E 段与照片旁边都写了，不留在心里。

| # | 照片 | 启动钩子 | 这张要证明的判据 | 实机/夹具 |
| --- | --- | --- | --- | --- |
| 01 | `01-monitor-sensors-real` | `MM_MONITOR_CARDS=stats,sensors` | **`.app` 进程内能读 SMC**（真读数：`TCMz 81.3 °C` + `风扇 1 1000 RPM（区间 1000–4900）` + 脚注 174）；顺带核对同值按键名升序 | 实机 |
| 02 | `02-monitor-sensors-loaded` | `=sensors` + `MM_MONITOR_FIXTURE=sensors` | loaded 形态可复现（8 行 + 脚注 + 风扇行），键名 `TZZ*` 一眼是夹具 | 夹具 |
| 03 | `03-monitor-sensors-unavailable` | `=sensors` + `sensors-unavailable:…` | 不静默、不塌成空列表：值位「—」+ reason 原文整行 | 夹具 |
| 04 | `04-monitor-sensors-nofan` | `=sensors` + `sensorsNoFan` | 「无（SMC 报告本机 0 台风扇）」——**读出来的 0** | 夹具 |
| 05 | `05-monitor-sensors-fanunknown` | `=sensors` + `sensorsFanUnknown` | 「风扇 —」+「未知不等于 0 台」——与 04 是两句话 | 夹具 |
| 06 | `06-monitor-sensors-hot` | `=sensors` + `sensorsHot` | 从冷到热 ≥90 °C（夹具给 94.0）只有数值转红，键名列不转（暗档 06 同判据）。**I11 之后这一档还多担一条**：它是"迟滞没把红档弄坏"的回归——`onAppear` 里少那次播种，拍出来就是白字 | 夹具 |
| 07 | `07-monitor-sensors-after-process` | `=process,sensors` + `processes,sensors` | 新卡排在进程卡之后的**卡间距与页底留白**（单独渲染看不出这条） | 夹具 |
| 08 | `08-monitor-cards-illegal-token` | `MM_MONITOR_CARDS=sensors,typo` | 非法值整批作废：判据在 stderr（`grep 含非法取值` = 1 命中，明暗各一次），照片只是佐证（六卡回到真实顺序） | 实机 |

**这套钩子解决的是"最后一张卡永远拍不到"**：`MM_MONITOR_CARDS` 把渲染范围钉成子集，位置由钩子决定，
不靠拉高窗口碰运气（屏高 1080pt，`MM_WINDOW_SIZE=1400x…` 会被 AppKit 夹到 ≈1050，
这条坑 P6.2c 已经踩过一次）。代价写在稿子里：`=sensors` 单卡那张**不证明卡片顺序**，
顺序与间距是 07 那张的事。

**没有拍的一档**：风扇 `F0Ac` 有值而 `F0Mn`/`F0Mx` 缺任一 → 只写「2100 RPM」不给区间。
本机四键齐全、夹具也没做这一档，所以它只有单测（`SensorTests`）没有照片——记在这里免得下轮以为漏了。

**I11 迟滞的过渡态也拍不到（2026-10-04，试过一次并留下证据）**：迟滞是**随时间**的行为，
而 `MM_MONITOR_FIXTURE` 每个进程只给一个定格快照——夹具能拍"94 °C 是红的"，拍不到"红过之后落回 87 °C 还红着"。
唯一真办法是让本机自己热过 90 再冷下来：`Scripts/i11-hysteresis-capture.sh`（8 个 `yes` 循环 × ~40 秒，
逐 3 秒抓一帧，零合成点击）。**结果是这台机器跨不过 90**：26 帧里最高 **89.0 °C**，一帧红都没有
（`docs/verification/i11-hysteresis/peak-load-8core.png` + `run.log`）。这条"没红"是可推的而不是看的——
卡片按降序显示，第一行就是全机最高可信读数，所以"第一行没红"⟺"没有任何键到过 90"。
风扇全程 `F0Ac`=1000=`F0Mn`（P6.4 那条"目标转速贴在最低档"的观察在这里第三次复现），
机器只能靠温度自己顶住。所以判据改成这样写：**红档与迟滞都由单测钉住，照片只钉"夹具 94 °C 仍然转红"这一条回归**
（照片 06，浅+暗）。**不要**为了出一张照片去做"随时间变化的夹具档"——那会往生产代码里塞一条只有测试走的路。

顺带一条采集纪律（本轮自己踩的）：热实验期间不要同时跑别的重活。冷却段本该单调下降，
实测却是 66.0 → 81.5 → 86.2，因为我同时在渲染设计稿（Chrome headless）。
所以入库的只有负载段那一帧；**撤掉负载之后（帧 11 起）的数全部作废**，别拿它们说事。

**验证命令骨架**（§4.1 那 13 项用；§4.2 的八档已经固化成 `Scripts/p64-capture.sh`，不必再手敲。
全程零合成事件、`--pid` 抓窗）：

```bash
# 重建（隔离，不碰现有 build）
swift build -o /tmp/mm-build --scratch-path /tmp/mm-scratch 2>/dev/null || \
  ./make-app.sh -o /tmp/mm-out -s /tmp/mm-scratch

# 逐档：起实例 → 按 pid 抓窗 → 杀自己记下的 pid
MM_OPEN_MODULE=monitor MM_MONITOR_FIXTURE=perCoreRed /path/to/MacMaster.app/Contents/MacOS/MacMaster &
APP_PID=$!
WIN=$(swift Scripts/window-ids.swift --pid "$APP_PID")
screencapture -o -x -l"$WIN" /tmp/mmshot/monitor-percore-red.png
kill "$APP_PID"   # 只 kill 自己记下的 pid
```

> 注意：上面的 `swift build`/`make-app.sh` 产物路径与隔离参数（`-o`/`-s` + `--scratch-path`）是
> 按 README §5 红线写的**约定骨架**，具体入口以仓库 `Package.swift`/`make-app.sh` 实际参数为准；
> 本环境无运行实例，未实际执行。

### 4.3 P6.5 内存卡 Swap 三档取证（4 档 × 明暗两套，`Scripts/p65-swap-capture.sh`）

照片在 `docs/verification/p65/`（浅色）与 `docs/verification/p65-dark/`（暗色），同名同号。
渲染范围钉成 `MM_MONITOR_CARDS=memory`（单卡），手法与 §4.2 同一套。

| # | 照片 | 启动钩子 | 这张要证明的判据 | 实机/夹具 |
| --- | --- | --- | --- | --- |
| 01 | `01-monitor-memory-real` | 只有 `MM_MONITOR_CARDS=memory` | **非零路径没被改坏**：Swap 行仍是「747.3 MB / 2.15 GB」的对仗，数字每一帧能回到 `sysctl vm.swapusage` | 实机 |
| 02 | `02-monitor-memory-swapzero` | `+ MM_MONITOR_FIXTURE=swapZero` | I9 的新句子「0 字节（未使用）」——这是本轮真正要拍的那一帧 | 夹具 |
| 03 | `03-monitor-memory-swapoff` | `+ MM_MONITOR_FIXTURE=swapOff` | 「读不到」仍是「—」，与 02 是两句话（这条区分是 I9 改动的边界，改坏了就是一句话） | 夹具 |
| 04 | `04-monitor-memory-populated` | `+ MM_MONITOR_FIXTURE=populated` | 底座改成真实形状后与 02 确实分得开（「838.9 MB / 2.15 GB」vs「0 字节（未使用）」） | 夹具 |

**这一档为什么必须靠夹具**：本机 swap 一直非零（2026-10-04 两次量到 used 747 MB / 800 MB 上下、
total 恒为 2 GiB），零值不是"再等等就能拍到"的状态。与 §4.2 那条"跨不过 90"同性质——
**拍不到的原因写清，比编一个假数据凑一张照片值钱**；区别在于这一档是**定格的数值**，
夹具能精确构造（`swapAvailable=true` + 两个 0），所以它拍得到，只是不在真机上拍。

**没有拍的一档**：菜单栏下拉里那句 `Swap: …`（`MenuBarManager.swift:305`）。它与页面共用同一个
`swapText`，但打开菜单需要点击状态栏图标——合成点击是硬禁止项，`screencapture -l<windowid>` 也抓不到
NSMenu（它不属于应用窗口）。所以这一档只有单测（`FormatTests.testSwapCompactUsesMenuBarUnits`）没有照片。
