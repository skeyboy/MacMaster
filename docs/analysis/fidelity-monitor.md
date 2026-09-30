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

## 0. 对照方法（先说清楚哪些是量出来的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmmonitor/07-monitor.html`（4 个 artboard：A 正常态首屏 / B 折叠线以下 / C 采样中首帧 / D 降级态合集） |
| 渲染 | `cd docs/design-system && ./render.sh screens/mmmonitor/07-monitor.html 1160 4600` → `screens/mmmonitor/07-monitor.png`（2320×9200，2x）。**上一版按 4210 渲染**；D 稿新增 D3a 一格后按 4600 重出，避免最后一格被裁 |
| 实机 | `build/MacMaster.app`（**未重新构建**），`MM_OPEN_MODULE=monitor` 启动，按 **pid** 匹配 windowid，`screencapture -o -x -l<id>` → `/tmp/mmshot/70-monitor-real.png`（1100×700 @1x，深色模式，Mac mini M4 / 10 核 / 24 GB，2026-09-30 03:16） |
| 像素取证 | CoreGraphics 逐行/逐列取色（`/tmp/vscan.swift`、`/tmp/hscan.swift`、`/tmp/cropimg2.swift`），所有"实机"数字都来自这条路径 |
| 可用钩子 | **只有 `MM_OPEN_MODULE=monitor`**（`Sources/MacMaster/MainWindow.swift`）。`grep ProcessInfo.processInfo.environment Packages/MMMonitor/` → **0 命中**，即本模块**没有任何内容/状态钩子**，滚动、骨架、失败分支都无法在实机上构造 |
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
| 标题「系统监控」 | `MMMonitor.swift:27`；模块名 `:7` | ✅ | 实机逐字一致 | — | — |
| 副标题「上次采样 2026-09-30 03:16 · 实时更新」 | `MMMonitor.swift:27` + `MMFormat.dateTime` | ✅ | 实机格式 `yyyy-MM-dd HH:mm` 一致；分钟粒度不刷新时看起来"停在旧值"是设计选择，稿内已注明 | 低 | 记录 |
| C/D 稿 frame-0 副标题「上次采样 **0001-01-01 08:05** · 实时更新」 | `MetricTypes.swift` `MetricSnapshot.empty.sampledAt = .distantPast`，经 `MMMonitor.swift:27` 渲染 | ❌ | 首帧（`enable()` 之前）把"还不知道上次采样时间"渲染成**公元 1 年的具体时刻**；`nil → "—"` 的约定只加在数值上，没加在时间上 | **高** | ~~实现该改 I1~~ **已改** |
| 右侧「菜单栏监控」+ switch，标签在左 | `MMMonitor.swift:28-32` `.toggleStyle(.switch)` | ✅ | 实机标签在左、开关在右，位置一致 | — | — |
| 关闭态（switch off） | `menuBar.disable()` → 采样循环被 cancel | ⚠️ 未画 | 关了就停采样，页面会**冻在最后一帧**而不是变空；稿内没有这一档，实机也无法验证（见 §4） | 低 | 设计稿该改 S5b |

### 1.2 顶部读数条（MMStatItem × 4）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 四个标签逐字：「CPU 总占用」「内存」「磁盘 读」「磁盘 写」 | `MMMonitor.swift:57-60` | ✅ | 实机一致（含"磁盘 读"中间那个空格） | — | — |
| 百分比 1 位小数（35.8% / 80.2%） | `MenuBarManager.percentText:169` → `MMFormat.percent` | ✅ | 0.4% 不会被压成 0% | — | — |
| 速率 `compactBytes + "/s"`（1.9 MB/s、293.3 KB/s） | `MMMonitor.swift:64-67` | ✅ | 稿内数值取自实机 | — | — |
| nil → 「—」（C 稿 CPU/磁盘四项） | `:65`、`MenuBarManager:170` | ✅ | 空值不塌成 0 | — | — |
| 卡片几何：48pt 高、6pt 圆角、`cardBackground` + separator 描边、v8/h12 内边距 | `MMDesign.swift:359-369` | ✅ | 实机 48pt（115→162）与稿内一致 | — | — |
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
| **首帧 `.ok` + 速率 nil** → 两行「—」且**没有**原因行 | `SystemMetricSampler.swift:94`（`interval` 为 nil 时不填 `diskRate`，`diskStatus` 仍 `.ok`） | ❌ | 与 `.unavailable` 在 3 米外**完全同形**（都是"读取 —／写入 —"），差别只在有没有那行灰字；用户无法区分"还没法差分"和"这台机器读不到磁盘统计" | **中** | 实现该改 I3 |

### 1.5 内存卡

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「内存」+ `memorychip` | `MMMonitor.swift:118` | ✅ | 一致 | — | — |
| 五个标签逐字：「已用」「活动」「联动保留(wired)」「压缩」「Swap」 | `:120-127` | ✅ | 稿内未做任何润色（含中英混排的 `wired`） | — | — |
| 「已用」= `bytes(used) / bytes(total)` | `:120`，口径 `MemoryMetrics.usedBytes = active+wired+compressed`（`MetricTypes.swift`） | ✅ | B 稿卡头把"不含 inactive"的口径写死 | — | — |
| 「联动保留(wired)」在 80pt 标签列内**换行** | `MMDesign.swift:340` `.frame(width: 80)` | ❌ | 80pt 装不下 5 汉字+括号 → 实机同宽度下必然折行，22pt 行距被这一行撑破；且英文括号注法与全站"纯中文标签"惯例不一致 | **中** | 实现该改 I5（文案部分两可，见 §2） |
| `memory == nil` → 「内存读数不可用（host_statistics64 失败），显示 —。」 | `MMMonitor.swift:129` | ❌ | 这句在**三种**不同成因下都会出现：①`.empty`（压根没采）②`host_statistics64` 真失败 ③`vm_page_size` 异常。把"还没采到"写成"系统调用失败"= 给出错误的因果结论 | **高** | ~~实现该改 I2~~ **已改** |
| `swapAvailable == false` → Swap 行「—」 | `:125-127` | ✅（代码分支） | D 稿画了；本机 swapAvailable=true，**实机未触发** | — | 见 §4 |
| `swapAvailable == true` 且读到 0 → 「0 字节 / 0 字节」 | `MMFormat.bytes`（<1000 字节特判） | ⚠️ | 中文语境里读起来像坏了；稿内以注脚说明，未画 | 低 | 实现该改 I9 |

### 1.6 进程 TOP 10 卡

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「进程 TOP 10」+ `list.bullet` | `MMMonitor.swift:139` | ✅ | 一致 | — | — |
| 唯一动作 = 图标按钮 `arrow.clockwise`（无"结束进程"） | `:141-146` | ✅ | 只读页无写操作，稿内明确写出这一条 | — | — |
| 行内文案「CPU 时间 mm:ss」+ 右对齐 80pt 的 `MMFormat.bytes` | `:161-167` | ✅ | 未沿用旧实现的误标「CPU x%」（`:159-160` 注释即为此保留） | — | — |
| 名称回落 `pid:NNN` | `ProcessReader:275` `name.isEmpty ? "pid:\(pid)"` | ✅ | B 稿画了 `pid:4417` | — | — |
| 行 28pt + `contentBackground` 药丸 + `MMRadius.control` + 横向 12pt | `:169-171` | ✅ | — | — | — |
| `processes.isEmpty && !processLoadFailed` → **4 条 `MMSkeletonRow`** | `:148-149` | ✅（代码分支） | D5 稿按 1:1（15 方块 + 120 短条 + 56 短条，行高 44）画；实机在折叠线以下且无钩子，未截到 | — | 见 §4 |
| `processLoadFailed` → `MMEmptyState(title:"进程列表读取失败", detail:nil)` | `:151` | ❌ | `MMEmptyState` 支持 `detail`/`action`（`MMDesign.swift:405-438`）却都传了 nil → 失败态**既没有原因也没有下一步**（重试按钮就在同一张卡右上角，但没在文案里指向它） | **中** | 实现该改 I6 **已改一半**（见 §2.6） |
| `processLoadFailed = procs.isEmpty` | `:184` | ❌ | "枚举成功但一个进程都没有"与"`proc_listallpids` 失败"被压成同一个 UI 态；前者在本项目语义里应显示空列表，而不是"读取失败" | **中** | 实现该改 I7 |

### 1.7 卡片容器与全站骨架层

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 页面卡：`underPage` 底 + 12pt 内边距 + 8pt 圆角 + separator 描边 | `MMMonitor.swift:191-213`（私有 `card()`） | ✅ | 实机卡底 (40,40,40)、描边 1px，与稿内 `.mcard` 一致 | — | — |
| 但 `card()` **没有复用 `MMCard`** | `MMDesign.swift:766-782`（`controlBackground` + `MMGap.lg` 16pt） | ❌ | 同一 App 里两套"卡片"：本页 underPage/12，其他页 controlBackground/16 → 令牌漂移，正是设计系统要防的事 | **中** | 实现该改 I4 |
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
3. **【中】I3 · 磁盘 IO「还没法差分」与「读不到」同形**（`SystemMetricSampler.swift:94` / `MMMonitor.swift:101-106`）
   首帧 `.ok` + nil 速率时两行「—」且无原因行。→ 建议：`.ok` 但 `diskRate == nil` 时补一行
   caption「需两次采样才能算出速率」，让三态（有数 / 待差分 / 不可用）在图元层可分。
4. **【中】I4 · 私有 `card()` 复刻 `MMCard`**（`MMMonitor.swift:191-213` vs `MMDesign.swift:766-782`）
   底（underPage vs controlBackground）与内边距（12 vs 16）两套。→ 建议：`MMCard` 增加
   `background:` 参数或加一个 `MMCardStyle.underPage`，本页改为调用组件。
5. **【中】I5 · `MMKeyRow` 80pt 标签列撑不住长标签**（`MMDesign.swift:340` + `MMMonitor.swift:122`）
   「联动保留(wired)」折行、破坏实机 22pt 行距。→ 建议：标签列改为按内容自适应（`Grid`/`alignmentGuide`）
   或把令牌提到 96pt；顺带决定「联动保留」是否保留英文括注（全站措辞惯例是纯中文，括注属例外）。
6. **【中】I6 · 进程失败态没有下一步 —— ✅ 已改一半（2026-09-30）**
   `MMEmptyState(..., detail: nil)`（原 `:151`，现 `MMMonitor.swift:164`），而组件本身支持 `detail`/`action`。
   → 现在传 `detail: "枚举系统进程没有拿到任何结果。点卡片上方的刷新按钮重试。"`。
   **没有**照建议写「proc_pidinfo 未返回任何进程」：那条路径根本没调 `proc_pidinfo`，
   失败点也可能是 `proc_listallpids`，指错原因比不说更糟。`action:` 未加——重试按钮已经在同一张卡
   右上角（`MMMonitor.swift:148-153`），再加一个是同一个动作画两个入口。
7. **【中】I7 · 「查到空」被当成「查失败」**（`MMMonitor.swift:198` `processLoadFailed = procs.isEmpty`）
   → 建议：区分 `ProcessReader` 的返回（`count > 0` 失败 vs 结果为空），空结果走 `MMEmptyState(title:"没有可显示的进程")`。
   仍未做，是 I6 剩下的那一半：要把 `topProcesses()` 从 `[MonitorProcess]` 改成结果枚举，
   顺带才能把"哪一步失败"写进文案。
8. **【中】S1 关联 · 侧栏 footer 与实机不符**（见 §3，实机是容量行 + 带边框设置按钮）——**这条两边都要改**：
   设计稿要重画，同时实现里侧栏 footer 的容量条/设置按钮在 01–06 六张稿里全部缺失，属全站缺口。
9. **【低】I8 · 网络速率在页面消失**：快照有 `networkUp/DownBytesPerSecond`、菜单栏有显示、页面一处不用。
10. **【低】I9 · Swap 读到 0 输出「0 字节 / 0 字节」**（`MMFormat.bytes` <1000 特判）→ 中文读起来像坏了。
11. **【低】I10a · 侧栏实现 220pt vs 令牌 216pt**（实机分隔线 x=220）。
12. **【低】I10b · 标题栏实现 ≈52pt vs 令牌 38pt**（实机黑线 y=52）→ 每页可视高度少 14pt，直接影响本页折叠线落点。

## 3. 设计稿该改（6 条）

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
