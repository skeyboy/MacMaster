# 06 隐私守护 · 设计稿 ↔ 实现 逐元素对照（fidelity-guardian）

> **结论先行**：06 稿（正常态首屏 + Mac mini 实机首屏 + TCC 降级双卡）与实现在**结构、文案、降级语义**
> 三层基本对得上——当前占用四档、TCC 四档、登录项三类异常徽章与脚注，逐条都有实现出处且文案一致。
> **本模块最关键的红线「授权表读不到 ≠ 未授权」在设计与实现两侧都守住了**：`TCCSourceOutcome`
> 把 `.readable` 与 `.unreadable` 分成两个类型，`TCCViewerState` 把 `.unreadable`（读不到·不画列表）
> 与 `.emptyRead`（查到了 0 行·明确说"查到了没有"）分成两个独立 UI 态；设计稿 06c 也用两张独立卡片
> 表达这两档，且实现 `partial` 档会正确**过滤掉读不到的那个库的行**，不会把"用户级没有"渲染成"整机没有"。
> 这一条经逐代码路径核对，**PASS，无缺陷**。
>
> 真正的缺陷集中在三处：①设计稿 06 主屏在"系统级库读不到"警示条旁边又画了一行"屏幕录制·系统级"
> （自相矛盾，实现不会这么画）；②实现多了一张设计稿没有的「系统活动」卡（产品规划文档 §4.5 有"最近活动"
> 但设计稿落后未补）；③实现独有卡「系统活动」**没有任何夹具钩子**，其空态/填充态无法无头截图核对。
> 另外全站骨架层（侧栏 footer / 侧栏宽 / 标题栏高 / 卡片底 token）沿用 `fidelity-monitor.md` 已记的差异，
> 修复归协调层，非本模块独有。
>
> 逐元素对照 **约 60 项**，其中 **16 项存在需归属的差异**（**高 0 / 中 3 / 低 13**）：
> **实现该改 4 条**（I1–I4）、**设计稿该改 9 条 + 全站 4 条口径**（S1–S11，其中 S1/S2/S3/S4 为全站 token 漂移）、
> **两边都改 0 条**。**另有 1 张实现独有卡（系统活动）完全没被设计稿覆盖**（其状态钩子已落地，见 §6.6.3）。
> **P13 更正这两句**：那张卡已在 P11c 进稿（§6.7，S12 关闭）；"两边都改"从 0 条变 **1 条**、
> 需归属的差异因此是 **17 项**（**高 0 / 中 3 / 低 14**）——新增的 **D1** 是页头副标题只列三件事、
> 而这一屏有四张卡，两边同一句文案，见 §7.1。**（D1 已在 P14 关闭，见 §8.1。）**
>
> **P6.2b 更新（2026-10-03）**：实现该改从 4 条变 6 条（新增 I5 整页分隔语言、I6 定高切字），其中 **I1/I3/I5/I6 已落地**、
> I2 归协调层；§4 里"无头拍不到"的 5 项已实拍（`docs/verification/p62b-fidelity/`），
> 系统活动卡那项也因 `MM_GUARDIAN_ACTIVITY_FIXTURE` 落地而不再无解。**本轮改动与两次否证实验集中在 §6。**
>
> **P6.2c 更新（2026-10-03）**：**I4 关掉**——占用行图标环的直径/描边/上色三条都改过（§6.6.1），
> 守护页八档另出一整套深色档（`docs/verification/p62c-dark/`，§6.6.2），
> §6.5 里"深色档没量/活动卡没拍/登录项 indeterminate 没拍"三条一并划掉。
>
> **P11 / P11c 更新（2026-10-05）**：上面第 11–13 行那三处缺陷里，**②③ 是同一张卡**（「系统活动」），
> 它先被 P11 查出三处读法错（§6.6.6），再被 P11c 整卡重定——**统一日志那一族已从界面撤下，
> 卡片改名「密钥与自启配置的改动时间」，设计稿 06 也补了这一节（S12 关闭）**。
> 撤下它的全部实测（八档谓词、三家参考项目对照）与新的文案合同在 **§6.7**；
> 顺带修掉一个真机上恒为 0 行的 `prefix(3)` 缺陷也在那一节。
>
> **P13 更新（2026-10-05）**：这一卡的**发版侧照片**补上了——`docs/verification/p13-v1/01-real-machine.png`
> 拍在 `VERSION=1.0.0 BUILD=1` 的候选产物上（§6.7 那四档是调试构建，两回事）。同一轮把本文
> §1 的**行号引用全量现读了一遍**：11 处漂了 9 处，**没有一处指错元素**——结论有效、坐标过期，
> 逐条已就地更正（§7.2 有对照表）。新增开放项 **D1**（§7.1）。
>
> **P14 更新（2026-10-05）**：**D1 关闭**（§8.1）——页头副标题改成由 `GuardianPageCopy.subtitleSegments`
> 一份清单生成，段数由 `GuardianHeaderContractTests`（4 条）钉住，并且**做过否证实验**：删掉第四段
> → `Executed 4 tests, with 2 failures`。同一轮量到一件改文案时不会报错的事：
> `MMPageHeader` 的副标题是 `.lineLimit(1)` + **中间省略**，所以加长它的后果不是换行也不是溢出，
> 而是画面上多一个 `…`、切掉的正好是句子中段。三档窗口的实机照片在 §8.2
> （`docs/verification/p14-header/`）：四段在 1000pt 地板宽度下仍完整，余量不到三个汉字宽。

## 0. 对照方法（先说清楚哪些是量出来的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmguardian/06-guardian.html`（3 个 artboard：A 正常态首屏·四档 montage / B Mac mini 实机首屏 / C TCC 降级双卡「读不到」「查到了没有」） |
| 渲染 | **P14 重渲**：`cd docs/design-system && ./render.sh screens/mmguardian/06-guardian.html 1100 2688` → `screens/mmguardian/06-guardian.png`（2200×5376，2x）。两处要记清：① 这一格从前写的是 `1160 4600`，而**那条命令从来没有产出过入库那张图**——旧文件是 2200×5200，即 1100×2600 @2x，宽度与高度都对不上（那一格自己也写着"本审计未重渲"，所以它记的是抄来的命令，不是跑过的命令）；本轮按旧图的**同一宽度 1100** 重渲，免得画板宽度变了却没人察觉。② 高度是量出来的：先按 3000 渲一版，用 PIL 逐行找最后一条非背景行（y=5320 @2x → 2660 CSS px），再按 2688 重渲，两版尾行同为 y=5320 → **没切内容**，页底留白 55 px（2x）。旧图那一版的尾行在 y=4416，画布 5200 → 稿尾挂着 ≈392 CSS px 的纯灰底，正是 `fidelity-monitor.md` 那条"猜高度的代价"的同一个形状 |
| 实机 | **P3 审计时无头**（该节判定全部来自代码 + HTML + tokens 比对）；**P6.2b 起本模块有实拍**：`docs/verification/p62b-fidelity/`（raw @2x PNG）。原记"全站像素锚点引用 monitor §0（侧栏 220pt）"已被本轮重测推翻——改前实机是 200pt，见 §6.3 |
| 可用钩子 | `MM_GUARDIAN_FIXTURE`(占用档) / `MM_TCC_FIXTURE`(TCC 档) / `MM_GUARDIAN_LOGIN_FIXTURE`(登录项档) / `MM_GUARDIAN_LOAD=hold`(首帧定格) / `MM_GUARDIAN_CARDS`(卡过滤，逗号子集 `occupancy|tcc|login|activity`)。前四个均 `com.example.*` 合成、只读、不写盘；`MM_GUARDIAN_CARDS` 是显示层过滤，不改变数据流（`grep processInfo.environment Packages/MMGuardian/` → 5 命中） |
| 硬约束 | 全程未发合成鼠标/滚轮/键盘事件；未改 `Packages/MMGuardian/` 之外文件（tokens/screen/icons/render.sh/MMCore/MMUI 均只读）；未 `git` 任何操作；未 `swift build`；未碰 `/tmp` 之外路径 |
| 测量诚实 | 没测过 ≠ 0、没看过 ≠ 干净、原因未知 ≠ 某个具体原因；像素项无真机数字，只标 `⚠️` 不编 |

> 所有"一致"判定中，**结构/语义类来自代码与设计稿逐字比对**；**像素/几何类凡未实机量过的均标 `⚠️`，不报数字**。

## 1. 逐元素对照表

严重度定义：**高** = 用户会读到错误结论（把未知当已知 / 把失败当正常）；
**中** = 视觉或语义明显跑偏，但不产生错误结论；**低** = 像素级偏差、占位数据、口径注脚。

### 1.0 全站骨架（侧栏 / 标题栏 / 卡片底）—— 非本模块独有，沿用 monitor 已记差异

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 侧栏 nav-item：概览/系统清理(2.4 GB)/应用卸载(46)/磁盘分析/系统监控/隐私守护(active)/系统优化/设置 | `MMGuardian.swift` 借壳 `MainWindow` 导航（模块 `guardian`，`moduleIcon:"lock.shield"`） | ✅ | 项与顺序一致；"隐私守护"为 active | — | — |
| 侧栏 footer = 分隔线 + 「设置」nav-item（稿 06 画法） | 实机 = 磁盘容量行（`Macintosh HD` + 红色容量条）+ 带边框「设置」按钮（`fidelity-monitor.md` §0 已量） | ❌ | 07 稿沿用 01–06 错误画法；本模块侧栏同样缺容量行+设置按钮 | **中** | 设计稿该改 S1（全站） |
| 侧栏宽 220pt（`--sidebar-w`，`tokens.css:32`） | `MainWindow.swift:18` `navigationSplitViewColumnWidth` | ✅（P6.2b 起） | **本轮重测**：改前分隔线在 x=401px@2x = **200pt**（比稿窄 20pt）；三个历史数字 200/216/220 量的其实是三种不同东西。现 `min:220`，实测 x=440px@2x = **220pt**。机制由两次否证实验确定，见 §6.3 | 低 | 实现该改 I1 → **已落地** |
| 标题栏 38pt（`--titlebar-h`） | 实机黑线 y=52（`fidelity-monitor.md` §0） | ❌ | 实现 +14pt，每页可视高度少 14pt | 低 | 实现该改 I2（全站 I10b） |
| 卡片底 = `--c-card-bg`（白） | `MMColor.cardBackground = Color(nsColor:.underPageBackgroundColor)`（`MMDesign.swift:19`） | ❌ | 稿内 `.card` token 与实现 underPage 档不同；本模块卡全走 underPage | 低 | 设计稿该改 S2（全站 S4） |
| 页面底 = `--c-content-bg`（白） | 实机 `contentBackground`=textBackgroundColor 暗档（`MMDesign.swift:17`） | ❌ | 稿"白底+灰卡"对比度高于实机"灰底+更深灰卡" | 低 | 设计稿该改 S3（全站 S3） |
| 侧栏尾数「2.4 GB」「46」 | 本模块无来源 | ❌ | 纯占位，与实机不一致 | 低 | 设计稿该改 S4（全站 S2） |

### 1.1 页头（MMPageHeader）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 标题「隐私守护」 | `MMGuardian.swift:24` | ✅ | 逐字一致 | — | — |
| 副标题「摄像头与麦克风的当前占用（手动测量，非实时监听）· TCC 授权只读视图 · 登录项管理 · 密钥与自启配置的改动时间（只读 mtime）」 | `:24` 传的是 `GuardianPageCopy.subtitle`；四段清单 `subtitleSegments` 在同文件末尾（P14 起） | ✅ | **D1 已关闭**：这句从前只列三件事，而这一屏有四张卡。现在段数有判据（`GuardianHeaderContractTests` 要求 == `GuardianCard.allCases.count`，否证实验见 §8.1），加长它的排版代价（`.lineLimit(1)` + 中间省略，三档窗口照片）量在 §8.2 | — | ~~两边都改 D1（P13 新增）~~ → **P14 关闭** |
| 右侧「刷新」按钮 | `:25-27` `.buttonStyle(.bordered)` `.controlSize(.small)` | ✅ | 稿内 `<span class="btn sm">刷新</span>` 对应 | — | — |
| 稿 toolbar 内「测量于 10:24:07」（A 稿有、B 稿无，稿内自不一致） | 实现把"测量于 …"放到**当前占用卡头**（`MMGuardian.swift:88-92`，P13 现读；原记 `:84` 已漂），toolbar 不放时间 | ❌ | 采样时刻位置分歧：设计画在 toolbar，实现画在占用卡头（更贴近数据，且 B 稿本就没画时间，实现反而更一致） | 低 | 设计稿该改 S5 |
| 卡头摄像头图标恒为次级色（不表态） | `MMGuardian.swift:82-85`（`iconTint: MMColor.secondaryLabel` 在 `:85`，P13 现读；原记 `:80` 是 `occupancyCard` 声明那一行） | ✅ | 与稿 cap"卡头的摄像头图标不参与表态"一致——红色只属于"正在被使用" | — | — |

### 1.2 当前占用卡（P3.1）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「当前占用」+「只读检测 · 不申请任何权限」小字（A 稿 section 头） | `MMGuardian.swift` `occupancyCard` → `sectionHeader(caption:)`（现 `:82-87`） | ✅ | **P6.5b 复核改口径**：这句诚实披露不是 P6.2b 补的，早在 **`e3928fe`（2026-09-30）**就进了代码（当时是卡头里一个独立 `Text`，旧 `:90`；TCC 卡的"SQLite 只读查询 · 不写库不提权"同批，旧 `:131`）。P6.2b（`1d5849b`，2026-10-03）做的是**搬运**——把区块头移到卡外、两句收进 `sectionHeader(caption:)` 参数。原记"改前实现卡头**没有**这句"是反的：改前有，只是位置在卡内。实机仍见 `p62b-fidelity/03-guardian-rows.png`（那张拍的正是搬运后的排版，结论不变） | 低 | 实现该改 I3 → **已落地（`e3928fe`）**，P6.2b 只改了归属位置 |
| 档1 摄像头 live：徽章「正在被使用」(danger+warn 图标) + 备注「使用方无法确定 · 公开接口不返回进程」 | `DeviceUsageCopyTable` inUse（`DeviceUsage.swift:135-143`）+ `DeviceUsageRow:594` 红 tint + `exclamationmark.triangle.fill` | ✅ | 逐字一致；红色仅此档 | — | — |
| 档2 麦克风(内置) idle：徽章「当前空闲」(safe) + 备注「1 个纯输入设备 · 读数 0」 | `DeviceUsage.swift:144-151`（idle 备注 nil） | ❌ | 设计 idle 档有"1 个纯输入设备 · 读数 0"备注，实现 idle `note:nil`，只保留 detail"输入设备存在，本次测量未读到任何进程驱动" | 低 | 设计稿该改 S6 |
| 档3 麦克风(Studio Display) combo：徽章「无法确定」(readonly) + 备注「不等于"没有应用在用"」 | `DeviceUsage.swift:160-165` `indeterminate(.comboAmbiguity)` | ✅ | 逐字一致 | — | — |
| 档4 摄像头(USB) readFailed：徽章「无法确定」(readonly) + 备注「可点"刷新"重测」 | `DeviceUsage.swift:154-159` `indeterminate(.readFailed)` | ✅ | 逐字一致 | — | — |
| absent 档（B 稿）：「本机没有摄像头」/「无可用麦克风」，中性灰 readonly | `DeviceUsage.swift:173-180` `deviceAbsent` + `DeviceUsageRow:615` 灰 tint | ✅ | 逐字一致；灰非绿（"无法确定"绝不借绿） | — | — |
| 图标环 34pt、2px 描边、**只有 live 上色**（稿 `.urow .ring` + `.urow.live .ring`） | `DeviceUsageRow` 的 `ZStack{ Circle().stroke … }` | ✅（P6.2c 起） | 原记"实现只有纯图标、无环"是**看漏了**：环一直在，但**三处与稿不符**——外圈 30pt（frame 用的就是 `iconRow` 28）而非稿面渲染出的 38pt；描边跟着语义 tint 走，于是空闲态是一枚**绿环**，而稿里绿色只属于右侧 `badge safe`，环与图标不参与表态；live 缺那层 `--c-danger-soft` 红底。三处已按稿校正（直径走新常量 `MMMetric.iconRing`，取 36 而非稿面 34，换算见 §6.6.1） | 低 | 实现该改 I4 → **已落地** |
| 占用行 min-height 56pt（稿 `.urow`） | `DeviceUsageRow` `frame(minHeight: MMMetric.rowRegular)`（rowRegular=44，`MMDesign.swift` token `--row-h-regular:44px`） | ❌ | 设计 56pt vs 实现 44pt，行高不一致 | 低 | 设计稿该改 S7 |
| 口径脚注「空闲=设备在且测到没人驱动；无法确定≠没有应用在用；本机没有设备时如实显示…」 | `MMGuardian.swift:112-120`（文案在 `:116`，"占用时系统公开接口不返回进程名，本面板不猜使用方"；P13 现读，原记 `:99-107` 已漂） | ⚠️ | 语义一致，实现脚注略简、未展开"本机没有设备"那半句（该态已有独立徽章，冗余可接受） | 低 | 记录 |
| 首帧（deviceUsage 空）→ 2 条 `MMSkeletonRow` | `MMGuardian.swift:97-102`（P13 现读，原记 `:90-93` 已漂）；由 `MM_GUARDIAN_LOAD=hold` 定格 | ✅（代码分支） | 设计稿未绘骨架 artboard，但钩子可构造 | 低 | 设计稿该改 S8（建议补骨架态 artboard） |
| 四档 montage（A 稿把四档并排画全） | 每设备仅持一态，需用 `MM_GUARDIAN_FIXTURE` 分屏截图（camera/mic 各一态） | ⚠️ | A 稿四行不是单屏可渲染态，实现每设备一行——设计应标注"每态独立示意"避免被当成单屏 | 低 | 提协调者 G4 |

### 1.3 敏感权限授权卡（P3.2）—— 重点：授权表读不到 ≠ 未授权

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「敏感权限授权」+「SQLite 只读查询 · 不写库不提权」 | `MMGuardian.swift:153-158`（P13 现读，原记 `:122-129` 已漂） | ✅ | 逐字一致 | — | — |
| **`.unreadable`（两库都打不开）→ 不画列表，只给原因 + 引导**（C 稿左卡） | `TCCViewerState.unreadable` + `TCCProbe` `.unreadable(reason:)` 两类型隔离；`MMGuardian.swift:169-182` `MMEmptyState`，标题常量 `TCCCopyTable.unreadableTitle`（`TCCAuthorization.swift:239` = "读不到 · 需要完全磁盘访问"） | ✅ | **红线守住**：读不到态**绝不画列表**，与"明确未授权"是两套代码路径 | — | — |
| **`.emptyRead`（可读且 0 行）→ "相关服务没有授权记录"，明确"查到了没有不是没查到"**（C 稿右卡） | `TCCViewer.build` `if unreadable.isEmpty { return .emptyRead }`；`MMGuardian.swift:183-190`（原记 `:149-155`） | ✅ | **红线守住**：只有"没有任何库 unreadable"才允许出现此档；有库没读到则降 `.partial` | — | — |
| **`.partial`（一库可读一库打不开）→ 列表 + 顶部点名读不到的库** | `TCCViewer.build` partial + `MMGuardian.swift:191-195` 调 `partialStrip`（定义 `:221`；原记 `:156-158`） | ✅ | **红线守住**：partial 档**只列读到的库的行**，过滤掉读不到库（见下 F 项） | — | — |
| `.loaded`（两库可读有行）→ 列表 | `TCCViewerState.loaded` + `tccRowsList` | ✅ | — | — | — |
| 部分可读警示条原文「系统级库读不到：open 被拒：Operation not permitted（errno 1）；sqlite rc=23 authorization denied——清单可能不完整」 | `TCCFixture.partialNote`（`TCCAuthorization.swift:263-265`）+ 真实 `TCCProbe` 拼 reason | ✅ | 逐字一致 | — | — |
| auth_value 映射 0 拒绝/2 允许/3 部分允许/4 已禁用；表外值(含旧系统 1)→「未知值 (N)」 | `TCCAuthStatus.from`（`TCCAuthorization.swift:66-74`）+ `copy` `unknown(value)` | ✅ | 1 及表外值一律"未知值"，永不猜"允许" | — | — |
| 行徽章：已允许(info)/部分允许(info)/未知值(1)(readonly)/已拒绝(readonly) | `TCCCopyTable.copy` + `TCCAuthorizationRow:643` `grantsAccess? informational:secondaryLabel` | ✅ | 蓝=确实拿到权限，其余中性灰；与稿一致 | — | — |
| 路径型 client 解析失败显示原始串（/opt/example/bin/ghost） | `TCCDisplayRow.init` `appName = resolvedAppName ?? client`（`TCCAuthorization.swift:131`） | ✅ | 不编名字（法则 2） | — | — |
| foot-note「状态取自 auth_value：0 拒绝/2 允许/3 部分允许/4 已禁用；表外值如实标未知值」 | `TCCCopyTable.valueLegend`（`TCCAuthorization.swift:244`） | ❌ | 稿 foot-note 含"（含旧系统的 1）"，实现缺这半句 | 低 | 设计稿该改 S9 |
| **C 稿左卡**「用户级库读不到 ENOENT + 系统级库读不到 EPERM/rc23」两原因 + 「打开系统设置·完全磁盘访问」 | `TCCCopyTable.unreadableTitle` + `unreadableGuide` + `MMReveal.openSystemSettings(...Privacy_AllFiles)` | ✅ | 标题/引导/按钮一致 | — | — |
| **F｜设计稿 06 主屏 artboard 1 在「系统级库读不到」警示条同在时画了「屏幕录制·系统级」行（Example Recorder）** | 真实 `build()` 与 `TCCFixture` `partial` 均**只取 user 行**，系统级读不到时不可能有系统级行 | ❌ | **设计稿自相矛盾**：既说系统级库读不到、又列系统级行——正好是被本项目红线禁止的"假通过"画法；实现不会这么画 | **中** | 设计稿该改 S10 |
| TCC 行 min-height 44pt（稿 `.trow`） | `TCCAuthorizationRow` `frame(minHeight: rowRegular=44)` | ✅ | 与 token 一致 | — | — |

> **「授权表读不到 ≠ 未授权」核对结论（任务重点）**：在 `TCCProbe`→`TCCViewer`→`tccCard` 全链路逐行核对：
> 1. 读不到（`.unreadable`，含两库都打不开 / 探针零结论 `outcomes.isEmpty`）**只渲染降级横幅，永不画列表**；
> 2. 查到 0 行（`.emptyRead`，须 `unreadable.isEmpty`）才说"没有授权记录"，且文案点名"查到了没有不是没查到"；
> 3. 半读半失败（`.partial`）列表**只含读到的库**，并用警示条点名没读到的库；
> 4. 明确"已拒绝"(auth_value 0) 这类**确定结论只在 `.loaded`/`.partial` 的行里出现**，绝不出现在 `.unreadable` 档。
> 设计稿 06c 同样用两张独立卡片守住该边界。**结论：设计与实现两侧均守住，无"把读不到混成未授权"的缺陷。**
> 唯一瑕疵是 06 主屏 artboard 1 内一处自相矛盾（见上 F / S10），属设计稿文字问题、非实现问题。

### 1.4 登录项卡（P3.3）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「登录项 N 项」+「打开系统设置 · 登录项」 | `MMGuardian.swift:252-261`（P13 现读，原记 `:213-222`） | ✅ | 本机 N=17（与 hook-ledger"本机 17 项"一致） | — | — |
| 行1 改名停用：`com.codex...disabled` + 「改名停用」徽章 + 开关 | `LoginItemRow:533-559`（renamedDisabled→「改名停用」徽章；user 域→`Toggle`） | ✅ | 开关 off（enabled=false）对应稿 `.sw` | — | — |
| 行2 未加载：`com.pnuts.jenkins` +「没在当前会话里加载」(warn) + 开关 on | `LoginItemAnomalyCopy.badge(.plistNotLoaded)` + `isWritable`→`Toggle` on | ✅ | 逐字一致 | — | — |
| 行3 系统域未加载：`com.sogou...` +「没在当前会话里加载」+「只读」+「在系统设置中管理」 | `domain==.system`→`isWritable=false`→只读徽章+按钮；异常 plistNotLoaded | ✅ | 双徽章+按钮，与稿一致 | — | — |
| 行4 系统域只读：`com.docker.socket` +「只读」+「在系统设置中管理」 | 同上 | ✅ | 一致 | — | — |
| 脚注①孤儿：「launchd 里还挂着 N 个非苹果标签…com.ollama.ollama、com.postgresapp…不一定是残留」 | `LoginItemAudit.swift` + `LoginItemAnomalyCopy.orphanNote` + `auditFooter`（count+前 6 标签） | ✅ | 语义一致（标签名是样本数据，结构一致） | — | — |
| 脚注②「没在当前会话里加载≠坏了…不替你下结论」 | `LoginItemAnomalyCopy.footnote`（`LoginItemAudit.swift:202`） | ✅ | 逐字一致 | — | — |
| 不可核对脚注「这一轮没对表…没查到不会被写成没加载」 | `LoginItemAnomalyCopy.indeterminateNote` + `auditFooter` `!determinate` 分支 | ✅ | 由 `MM_GUARDIAN_LOGIN_FIXTURE=indeterminate` 可构造 | — | — |
| 读取失败横幅（顶部黄条，scanerror 档） | 调用点 `MMGuardian.swift:31-33` + 定义 `readErrorBanner`（`:60-76`，P13 现读；原记 `:31-69`）+ `vm.scanErrors`（`:423`） | ✅（代码分支） | 由 `MM_GUARDIAN_LOGIN_FIXTURE=scanerror` 注入；**设计稿无专用 artboard 描绘该横幅** | 低 | 设计稿该改 S11 |
| 写失败面板（toggle 系统域/改名文件被拒 → `MMFailurePanel`） | `MMGuardian.swift:44-50`（面板）与 `:590-598`（`toggle(_:)` 把失败 append 进 `writeFailures`；原记 `:42-48,502-510`，后一处已被 P11c 的删改挪走） | ✅（代码分支） | 交互结果态；**设计稿未绘** | 低 | 设计稿该改 S11（同条） |
| 登录行 min-height 44pt（稿 `.login`） | `LoginItemRow` `frame(minHeight:)`（P6.2b 前是 `frame(height: 44/56)` **定高**） | ❌→✅ | 原判定"✅ 与 token 一致"是**错的**：稿写 min-height，实现写死 height，带异常徽章的行有第三行文字，44/56 钉死就把徽章那行齐根切掉。改后见 `p62b-fidelity/04-guardian-fixture-rows.png`（三行徽章完整） | 低 | 实现该改 I6 → **已落地** |

### 1.5 密钥与自启配置的改动时间卡（P11c 定合同；设计稿 06 已补这一节）

> 这一节从前记的是"实现多了一张稿上没有的卡"（旧 S12）。P11c 把那张卡的口径重定之后
> **设计稿补了它**（`docs/design-system/screens/mmguardian/06-guardian.html` 登录项卡之后那一节），
> 于是三行判据从"无基准"变成"有基准可比"。撤下日志族的全部实测在 §6.7。

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 稿 06「密钥与自启配置的改动时间」卡：五行（三行密钥目录 caution 橙 + 两行 LaunchAgent 中性灰），行 = 名称 + mono 绝对路径 + 右侧相对时间，脚注一条 | `MMGuardian.swift` `activityCard` + `ActivityScanner.watchableDirectories/launchAgentFiles/activityRows` | ⚠️ | 形状与 `p11c-activity/01-real-machine.png` 一致（本机 `.gnupg` 不存在 → 照片两行目录 + 三行 agent，稿上五行是"全都有"那一档）。**稿上脚注比实现多两句**（图标配色口径、"两者不得是同一个数说两遍"），那是写给下一轮看的合同，不是界面文案 | 低 | 记录（S12 关闭） |
| 空态「本机没有 ~/.ssh、~/.gnupg、~/Library/Keychains 这三个目录，用户级 LaunchAgents 目录里也没有 .plist。」 | `ActivityCardCopy.emptyText` | ✅ | 实现与常量同源，判据 `testCardCopyScopesTheClaimToModificationTimes`；`empty` 档照片 `p11c-activity/03-fixture-empty.png`（旧 `p62b-fidelity/10-guardian-activity-empty.png` 拍的是"近 5 分钟没有可读到的活动事件"那句，已被合同换掉，旧照片不重拍、只在此注明它记录的是收口前的口径） | — | 已收口 |
| 卡片几何（icon=eye、行高 44、平铺行 + `Divider()`） | `activityCard`：行 `minHeight: rowCompact`（P6.2b），detail 换成 `.caption.monospaced()` + 中段省略 | ⚠️ | 路径比从前的中文说明长，窄窗（1000pt）下中段省略生效、不溢出（`p11c-activity/04-fixture-rows-min-window.png`）；脚注两行换行不切字 | 低 | 记录 |


## 2. 实现该改（6 条，按严重度排序；P6.2b 关掉 3 条、P6.2c 关掉 I4）

> **复核 2026-10-04（P6.5b）**：六条状态**全部属实**，这一页的账没写过——只有 **I3 的归属提交记错了**
> （见该条），和另外两处需要补一句"还剩什么"（I2、I6）。真开着的仍然只有 **I2（标题栏 52 vs 38，全站 I10b，归协调层）**。
> 这一页与 `fidelity-monitor.md`、`fidelity-uninstaller.md` 一起构成本轮的对照样本：
> **同一批审计里，"改完没回写"和"回写了但记错是谁改的"是两种不同的账，都得翻一遍。**

1. **【低】I1 · 侧栏宽度** —— **P6.2b 已落地**。本条原记"实机 220 vs 令牌 216"，两个数都不对：改前实机量到 **200pt**，令牌早已是 220。改法与两次否证实验见 §6.3。
2. **【低】I2 · 标题栏实现 ≈52pt vs 令牌 38pt**（实机黑线 y=52，全站 I10b）。同上，归协调层。
   **复核 2026-10-04：仍是四条里唯一真开着的实现项**，没动是因为动不了——`titleBar` 高度属壳工程 + 全站十张稿的公共口径，
   单页改会造出第七种标题栏。继续挂协调层，不在本轮范围内。
3. **【低】I3 · 当前占用卡头缺"只读检测 · 不申请任何权限"诚实小字** —— **已落地，但不是 P6.2b 落的（复核更正）**：
   两句诚实披露都由 **`e3928fe`（2026-09-30，`fix(guardian): 占用卡头补诚实披露小字、占用行补图标环`）**加进代码，
   当时是卡头内的独立 `Text`（旧 `:90`、TCC 卡在旧 `:131`）；P6.2b（`1d5849b`，2026-10-03）只是把它们**搬进**
   `sectionHeader(caption:)`（P13 现读：占用卡 `MMGuardian.swift:82-87`、TCC 卡 `:153-158`）。
   原句"区块头搬到卡外时**按稿补**小字"把两件事记成了一件事——搬运是真的，"补"不是。
   **对结论无影响**（这一项确实关了），但 `e3928fe` 那笔同时还动了占用行图标环，而**图标环那条（I4）的正确归属是 `45a5de5`（P6.2c）**，
   两条相邻、来源不同，记错了下次就会去 P6.2b 的 diff 里找不到东西。
4. **【低】I4 · 占用行图标环与稿不符** —— **P6.2c 已落地**。本条原判定"实现没有环"是**看漏**（`DeviceUsageRow` 一直有 `Circle().stroke`），真实差异是三处：外圈 30pt vs 稿面渲染出的 38pt（稿上写的 34 是内容盒，见 §6.6.1）、描边跟语义 tint 走（空闲态因此成了绿环，而稿里绿色只属于右侧 `badge safe`）、live 缺 `--c-danger-soft` 那层红底。改后见 §6.6。
5. **【中】I5 · 整页分隔语言与稿 06 不一致** —— **P6.2b 已落地**：稿是"卡外标题行 + 通栏卡 + 卡内平铺行带底分隔线"，改前是"带内边距的卡里塞标题 + 每行刷沉底药丸"。逐部位对照见 §6.1。
6. **【低】I6 · 三处行高写成定高，把内容切掉** —— **P6.2b 已落地**：系统活动行 `height: 28`（两行文字被切下沿）、登录行 `height: 44/56`（异常徽章那第三行被切）。稿一律写 `min-height`。详见 §6.2。
   **复核 2026-10-04 补一句还剩的**：改成 `minHeight` 只保证"不切字"，**不保证"不折行"**。
   与监控页 `MMKeyRow` 的 80pt 标签列同一族问题（`fidelity-monitor.md` §2 第 5 条给了触发条件：标签写到 6 个汉字就折行，5 个是实测上限）。
   守护页现在的标签最长是"屏幕录制"（4 汉字），所以还没顶到；**这一条按"关闭 + 附条件"记**，
   条件是：这一页出现 6 汉字标签时改自适应，而不是等它先折行。

## 3. 设计稿该改（9 条模块 + 4 条全站口径，按严重度排序）

1. **【中】S1 · 侧栏 footer 全站画错**（实机容量行+带边框设置按钮，全站 S1）：06 稿沿用 01–06 错误画法，应在 tokens/screen 层补侧栏 footer 组件，七张稿一起换。
2. **【中】S10 · 06 主屏 artboard 1 系统级行与"系统级库读不到"警示条自相矛盾**：既画"系统级库读不到"警示条、又画"屏幕录制·系统级"行（Example Recorder），正是本项目红线禁止的"读不到也列系统级行"假通过。实现 `partial` 档已正确过滤掉系统级行。**改法**：删掉该行（保留警示条），或删掉警示条（改为 `.loaded` 全可读态）——二者只能留一。
3. ~~**【中】S12 · 设计稿缺「系统活动」卡**~~ → **P11c 关闭**：06-guardian.html 已补这一节，但**补的不是原来那张卡**——量完四种谓词之后日志族整族撤下，卡片重定成「密钥与自启配置的改动时间」（合同与实测见 §6.7）。产品规划文档 §4.5 那句"最近活动"到此只能算"实现比规划走得远，规划该改"，不是设计稿落后。
4. **【低】S2 · 卡片底 token 漂移**（全站 S4）：稿 `.card`=`--c-card-bg`，实现 `MMColor.cardBackground`=underPageBackgroundColor；补 `.card--under-page` 后删本地样式。
5. **【低】S3 · 页面底对比度**（全站 S3）：稿 `--c-content-bg`(白) vs 实机 textBackgroundColor 暗档；需 `.content--window` 变体。
6. **【低】S4 · 侧栏尾数占位**（全站 S2）：`2.4 GB`/`46` 无来源，应改实机值或留空。
7. **【低】S5 · 测量时间位置**：稿画在 toolbar（且 A/B 稿自不一致），实现画在当前占用卡头更合理；建议设计稿统一到卡头。
8. **【低】S6 · 占用 idle 档备注**：稿 idle 有"1 个纯输入设备 · 读数 0"，实现 `note:nil`；若要坚持该注脚，实现需从 `AudioDeviceReading` 取通道数拼注（或设计稿承认该注为示例多余信息）。
9. **【低】S7 · 占用行高 56 vs 44**：稿 `.urow{min-height:56px}` 与全站 `--row-h-regular:44px` 不一致，建议统一；⚠️ 精确行高待真机测量。
10. **【低】S9 · TCC foot-note 措辞**：稿含"（含旧系统的 1）"，实现 `valueLegend` 缺这半句——补回以明确"1 不按旧表猜成允许"。
11. **【低】S11 · 交互态未绘 artboard**：读取失败横幅（`readErrorBanner`）与写失败面板（`MMFailurePanel`）由 `MM_GUARDIAN_LOGIN_FIXTURE=scanerror`/toggle 失败触发，但设计稿无专用 artboard；建议补两张推演档。
12. **【低】S8 · 首帧骨架态未绘**：`MM_GUARDIAN_LOAD=hold` 可定格首帧（2 占用骨架 + 2 TCC 骨架），设计稿未画骨架 artboard；建议在 06 补一档。

## 4. 没能验证到的部分（逐条写明缺什么，不写"应该没问题"）

以下状态只在代码里读到分支，**本节写于 P3 无头审计**（当时环境不允许运行/截图）。P6.2b 已把其中 **1、2、3、4、6 五项实拍补齐**（`docs/verification/p62b-fidelity/`，见 §6.4），第 5 项（系统活动卡）也因 `MM_GUARDIAN_ACTIVITY_FIXTURE` 落地 + `scanUnifiedLog` 超时修复而实拍补齐（§6.6.3）——**但那一档拍的是夹具行，真实日志路径直到 P11 才第一次出内容，见 §6.6.3 末尾的 P11 更正；P11 又在这同一张卡上连着查出三处读法错与一处谓词口径缺口，收口记在 §6.6.6**。**§4 全部六项均已验证。**

| # | 未验证项 | 为什么验不了 | 需要什么才能验 |
| --- | --- | --- | --- |
| 1 | 占用四档逐态真机渲染（inUse/idle/combo/conflict/absent） | 每设备仅一态，需分屏 fixture；本环境不跑 App | `MM_GUARDIAN_FIXTURE` 分两次注入 + 按 pid 抓窗截图 |
| 2 | TCC 四档逐态真机排版（unreadable/emptyRead/partial/loaded） | 同上，且本机两库真打不开，`.loaded`/`.partial`/`.emptyRead` 只有夹具值 | `MM_TCC_FIXTURE` 四档 + 真机截图 |
| 3 | 登录项四态真机排版（rows/empty/indeterminate/scanerror） | 本机 17 项只有 plistNotLoaded 一种自然出现 | `MM_GUARDIAN_LOGIN_FIXTURE` 四档 + 真机截图 |
| 4 | 首帧骨架（hold）真机形态 | 首帧抢拍不到，靠 `MM_GUARDIAN_LOAD=hold` 定格 | 钩子 + 抓窗 |
| 5 | **系统活动卡空态 / 填充态** | **该卡无任何夹具钩子**，且 `ActivityScanner` 跑 `log show`/读敏感目录，无头不可控 | **需新增 `MM_GUARDIAN_ACTIVITY_FIXTURE`（见 §5 G1）** |
| 6 | 所有像素项（行高 44/56、环 34pt、卡片底 underPage、侧栏 220/标题栏 52） | 无实机抓取 | 按 pid 抓窗 + CoreGraphics 取色（同 monitor §0 流程） |

**已验证的部分**（结构/语义，来自代码+HTML+tokens 逐字比对，非像素）：页头标题/副标题/刷新；占用四档文案与 tint 规则；TCC 四档状态机分离与红线边界（§1.3 重点）；auth_value 映射与"未知值"；登录项三类异常徽章+双脚注；系统活动卡为实现独有（设计稿无）。

### 4.1 可注入档位映射（六个钩子逐项对照设计稿状态；P14 现读，从前写"四个"）

| 设计稿状态 | 可注入档位 | 启动方式（按 pid 抓窗） |
| --- | --- | --- |
| 当前占用·四档 montage（A 稿） | `MM_GUARDIAN_FIXTURE=camera=inuse,mic=idle` 等（每设备一态，分屏） | `MM_OPEN_MODULE=guardian` + 钩子 |
| 当前占用·Mac mini 实机（B 稿 absent） | `MM_GUARDIAN_FIXTURE=camera=absent,mic=absent` | 同上 |
| TCC·部分可读（A 稿主屏警示条+用户级行） | `MM_TCC_FIXTURE=partial` | 同上 |
| TCC·读不到（C 稿左卡） | `MM_TCC_FIXTURE=unreadable` | 同上 |
| TCC·查到了没有（C 稿右卡） | `MM_TCC_FIXTURE=empty` | 同上 |
| TCC·全可读有行（A 稿示例行） | `MM_TCC_FIXTURE=rows` | 同上 |
| 登录项·异常标注（A 稿四行+双脚注） | `MM_GUARDIAN_LOGIN_FIXTURE=rows` | 同上 |
| 登录项·空态 | `MM_GUARDIAN_LOGIN_FIXTURE=empty` | 同上 |
| 登录项·不可核对脚注 | `MM_GUARDIAN_LOGIN_FIXTURE=indeterminate` | 同上 |
| 登录项·读取失败横幅 | `MM_GUARDIAN_LOGIN_FIXTURE=scanerror` | 同上 |
| 首帧骨架（测量中） | `MM_GUARDIAN_LOAD=hold` | 同上 |
| 「密钥与自启配置的改动时间」卡·填充态（P11c 前叫「系统活动」，钩子键名未改） | `MM_GUARDIAN_CARDS=activity MM_GUARDIAN_ACTIVITY_FIXTURE=rows` | 同上（§6.6.3；**照片拍的是收口前口径**，新合同的真机档在 §8.2 与 `p11c-activity/`） |
| 「密钥与自启配置的改动时间」卡·空态 | `MM_GUARDIAN_CARDS=activity MM_GUARDIAN_ACTIVITY_FIXTURE=empty` | 同上（§6.6.3） |
| 页头副标题·三档窗口宽度（不注入任何夹具） | 无钩子——判据是"那一行不许出现 `…`" | `Scripts/p14-header-capture.sh`，见 §8.2 |

## 5. 提请协调者

1. **【重点·核对结论】"授权表读不到 ≠ 未授权"边界：设计与实现均守住，PASS。** 实现在 `TCCProbe`/`TCCViewer`/`tccCard` 把"读不到"(`.unreadable`，不画列表) 与"查到 0 行"(`.emptyRead`，明确"查到了没有") 分成两个独立 UI 态，且 `.partial` 只列读到的库；设计稿 06c 也用两张独立卡片表达。唯一瑕疵是 06 主屏 artboard 1 内"系统级库读不到"警示条旁又画了系统级行（S10，设计稿自相矛盾，实现不会这么画），请协调者让设计稿修掉该自相矛盾。
2. **【已落实·已出片（含 empty 档）】系统活动卡夹具钩子（G1）**：`MM_GUARDIAN_ACTIVITY_FIXTURE=empty|rows` 已落地（调用点是 `GuardianViewModel` 的 `activityFixtureStage` 常量——按符号名找，这一轮它随卡片改动挪过位置），合成条目标"夹具值"，本审计提出的"该卡无钩子、无法无头核对"已不成立；`rows` 档明暗两档各一张 + `empty` 档一张，见 §6.6.3。**P6.2d 新增 `MM_GUARDIAN_CARDS` 卡过滤钩子**，解决活动卡排在第 4 位永远在折叠线以下的问题——07/10 两档现在用 `MM_GUARDIAN_CARDS=activity` 只渲染活动卡，不再需要压矮上方三卡。**P11c 更新**：`rows` 档的两行已换成新合同用词（detail 是路径、tone 只剩 caution/neutral），旧 `p62b-fidelity/07、10` 两张照片记的是收口前的口径，不重拍、在 §1.5 注明。
3. ~~**【低】活动卡读敏感目录口径（G2）**~~ → **P11c 关闭，而且答案是"这句本身就不能说"**：那一行读的从来不是访问时间，是 `.modificationDate`，却写着"最近访问: X"。目录 mtime 只在**增删条目**时变，读取里面的密钥文件不动它——所以这句话正好是这个卡最不该说的那件事（三家参考项目无一这么标，见 §6.7）。现在 detail 是绝对路径、右侧是 mtime 的相对说法，卡片脚注明写"读取不会留下这里显示的那个时间"。至于"失败是否要明示"：这一族的读法只剩 `attributesOfItem`，读不到目录就是不存在，空态文案直接说出缺哪三个路径，不再有被静默跳过的 `readError`。
4. **【低】`MM_TCC_FIXTURE=unreadable` 文案格式（G3）**：夹具 detail 是单句平铺"模拟两库均读不到…"，未用真实 `TCCViewer.build` 的"用户级库读不到：…；系统级库读不到：…"逐库拼接，与设计 artboard 3 两原因排版不完全一致。建议夹具 unreadable 改为注入"用户级 ENOENT + 系统级 EPERM/rc23"两段原文以贴近设计。
5. **【低】四档 montage 非单屏态（G4）**：06 主屏 A 稿把占用四档并排画全，但每设备仅持一态，易被当成单屏。建议设计稿标注"每态独立示意，需用 `MM_GUARDIAN_FIXTURE` 分屏核对"。
6. **【记录】全站骨架 token 漂移（S1–S4 / I1–I2）**：侧栏 footer、侧栏宽 220、标题栏 52、卡片底 underPage、页面底对比度、侧栏尾数占位——修复在 `tokens.css`/`screen.css`/壳工程，归协调层统一处理（同 `fidelity-monitor.md` §3），非本模块能改。
7. **【已落实】README §2 矩阵**：`MM_GUARDIAN_LOGIN_FIXTURE`、`MM_GUARDIAN_LOAD` 已在 `hook-ledger.md` 补列（本审计沿用，未重复改）。

## 6. P6.2b 收口：整页换成稿 06 的骨架 + 侧栏宽度重测（2026-10-03）

取证脚本 `Scripts/p62b-capture.sh`，照片 `docs/verification/p62b-fidelity/`。全部零合成点击：状态一律由钩子在加载落地时推到位，只 kill 自己起的 pid。

### 6.1 这一轮改的不是"少一条分隔线"

P4 把这一条记成"守护页行分隔不明显"。逐字对照稿 06 的 CSS 之后，真实口径是**整页的分隔语言与稿不同**，改前实现是全站唯一用"药丸行"的一页：

| 部位 | 稿 06（`06-guardian.html` + `screen.css`） | 改前实现 | 改后（P6.2b） |
| --- | --- | --- | --- |
| 区块标题 | `.section-h` 在**卡外**：图标 + 标题 + 口径小字 + 右侧动作 | 塞在带内边距的卡里 | `sectionHeader(...)` 在卡外，口径小字回到标题旁 |
| 卡 | `.card.card-flush{padding:0}` | `MMCard()` 默认内边距 | `MMCard(padding: 0)` |
| 行 | 平铺 + `border-bottom`，`:last-child` 无线 | 每行刷成沉底药丸（圆角 `fillActive`） | 平铺 + `if index > 0 { Divider() }`，末行无线 |
| 脚注 | `.foot-note` 在卡内、`border-top` | 散在卡外 | 卡内 + `.overlay(alignment: .top){ Divider() }` |
| 部分可读警示条 | 通栏、压在卡顶 | 卡内带圆角的一小块 | 通栏 + 底部分隔线 |

判成"实现该改"而不是"稿该改"的依据：概览页与清理页的表格行早就是 `MMCard(padding:0) + Divider()` 这一种语言（`MainWindow.reclaimableCard`、`CleanerView.categoryRows`），**稿与另外两页站在同一边**，守护页是唯一的少数派。

### 6.2 顺带修掉的三处切字（同一轮改动暴露出来的）

| 位置 | 改前 | 后果 | 改后 |
| --- | --- | --- | --- |
| 系统活动行 | `frame(height: rowCompact=28)` | 行里是两行文字，标题下沿被齐根切掉 | `minHeight` |
| 登录项行 | `frame(height: 44/56)` 定高 | 带异常徽章的行有第三行，徽章被切 | `minHeight`（`04-guardian-fixture-rows.png` 里三行完整） |
| 占用行 | 已是 `minHeight` | — | 不动 |

三条同属一类错误：**稿写 `min-height` 时实现写死 `height`，等于把稿里"内容可以长高"的合同删掉**。定高只在"这一行永远一行"时才安全，而这三处都会因数据变高。

### 6.3 侧栏宽度：两次否证实验（这一条差点被写成假结论）

P4 的原始记录是"侧栏 229↔245pt"。**这组数在任何一张照片里都复现不了**，所以本轮先量再改：同一个"侧栏宽"在仓里三份文档被写成 200 / 216 / 220，谁也没算错，只是各自量的不是同一个东西。为确定机制做了两次实验（照片都在证据目录里）：

| # | 做法 | 结果 |
| --- | --- | --- |
| A | 往 SwiftUI 自己写的那条 `NSSplitView Subview Frames…` 里手改成 260pt 再启动（`probe-a-persisted-260.png`） | 分隔线仍在 x=401px@2x = **200pt**，退出时那条记录被改回 200 → **写了不等于被读** |
| B | 代码里 `ideal` 从 220 改成 240 重新构建（`probe-b-ideal-240.png`） | 屏幕上仍是 **200pt** → 首屏宽度取 **min**，`ideal` 不参与 |
| C | 改成 `min:220, ideal:220, max:280` 后重拍（`03`、`01` 两张独立照片） | 分隔线 x=440px@2x = **220pt**，两张同值 |

- **结论**：稿的 220pt 对得上，但只能由 `min` 承载；代价是用户能拖到的最窄处从 200 变成 220。`--sidebar-w-min: 200px` 这个令牌在 CSS 里声明后**从未被引用**（全仓仅 `tokens.css:33` 一处命中），所以没有实际合同被破坏。
- `MMMetric.sidebar = 220` **没有代码在读**，它只是给审计文档一个可对账的出处；已在常量注释写明，免得下一个人以为改它就改了布局。
- 曾怀疑"上一轮 P4 用 900x600 拍最小窗口，把侧栏夹到 200 并持久化，污染了之后的基线"——**实验 A 把它否证了**（持久化压根不被读）。取证脚本里为这个猜测写过一段删偏好键的代码，已删；留着只会让下一个人以为像素基线由它兜住。
- 测量口径：一律在 **raw @2x PNG**（2200×1520 px = 1100×760 pt）上量，`swift Scripts/pixel-probe.swift <png> scan y 760 380 480`。P4 那批 `.jpg` 是 `sips -Z 1400` 缩过的，坐标跟着缩，拿它报 px 就是假的。

### 6.4 照片清单（`docs/verification/p62b-fidelity/`）

| 文件 | 注入 | 看什么 |
| --- | --- | --- |
| `01-dashboard-first-frame.png` | `MM_OPEN_MODULE=dashboard`，等 5s（≈2 次采样） | sparkline 首帧横轴已满宽，柱子从右端往左长 |
| `02-dashboard-history-full.png` | 同上，等 30s（12 格真实采样） | 满轴 + 「全部 ›」affordance |
| `03-guardian-rows.png` | `MM_OPEN_MODULE=guardian` 真机态 | 卡外标题行、通栏卡、平铺行分隔线、卡内脚注、侧栏 220pt |
| `04-guardian-fixture-rows.png` | + `MM_TCC_FIXTURE=partial MM_GUARDIAN_LOGIN_FIXTURE=rows` | 通栏警示条、授权行分隔线、登录项三行徽章不被切 |
| `05-guardian-first-frame.png` | + `MM_GUARDIAN_LOAD=hold` | 首帧骨架在通栏卡里的留白 |
| `probe-a-persisted-260.png` / `probe-b-ideal-240.png` | §6.3 两次否证实验 | 两张的分隔线都在 x=401px = 200pt |

P6.2c 起同一目录再加三档，并把上面五张换成环校正后构建重拍的（改前那五张与 HEAD 不再一致）：

| 文件 | 注入 | 看什么 |
| --- | --- | --- |
| `06-guardian-ring-fixture.png` | `MM_GUARDIAN_FIXTURE=camera=inuse,mic=idle` | **图标环红/中性规则唯一的取证路径**：本机没有摄像头和麦克风，不注入则两行永远 `absent` |
| `07-guardian-activity-rows.png` | `MM_GUARDIAN_CARDS=activity` + `MM_GUARDIAN_ACTIVITY_FIXTURE=rows` | 第 4 张卡（实现独有）；**P6.2d 改用 `MM_GUARDIAN_CARDS` 只渲染活动卡**，不再需要压矮上方三卡（§6.6.3） |
| `08-guardian-login-indeterminate.png` | `MM_GUARDIAN_CARDS=login` + `MM_GUARDIAN_LOGIN_FIXTURE=indeterminate` | "本轮未核对"徽章 + 脚注压在卡内分隔线下 |
| `09-guardian-login-scanerror.png` | `MM_GUARDIAN_CARDS=login` + `MM_GUARDIAN_LOGIN_FIXTURE=scanerror` | 读取失败横幅（顶部黄条）+ 脚注 |
| `10-guardian-activity-empty.png` | `MM_GUARDIAN_CARDS=activity` + `MM_GUARDIAN_ACTIVITY_FIXTURE=empty` | 活动卡空态：「近 5 分钟没有可读到的活动事件」 |

**明暗两套**：`docs/verification/p62b-fidelity/` 是浅色，`docs/verification/p62c-dark/` 是同一八档的深色，
逐张同注入、只差 `MM_APPEARANCE`。§6.6.2 的分隔线对比度就是在同名的一对上量的。

### 6.5 这一轮**没有**核对的（不写"应该没问题"）

> 下面 1/5 两条由紧随其后的 P6.2c 关掉；2/3/4 由 P6.2d 关掉。结论在 §6.6。

1. ~~**深色档**~~：P6.2b 六张全是 `MM_APPEARANCE=light`，去药丸后暗档的行对比度没量过 → §6.6.2 量了。
2. **侧栏拖到两端**：只量了新的起点 220，`max:280` 那一端与"用户拖窄到 220 以下"的边界没拍。
   → **P6.5b 已拆**：窄的那端**不需要照片**（`min:220` 就是 AppKit 的下界，结构上拖不过去，见 §6.6.5 第 1 条）；
   280 那一端**确实拍不到**，且缺的是手段不是运气——已记为**取证边界**，不再当待办挂着。
3. ~~**系统活动卡**~~：钩子已存在但本轮没出片 → §6.6.3 出了 `rows` 档（明暗各一）。
4. ~~**登录项 `indeterminate`**~~：本轮只拍了 `rows` → §6.6.3 补了 `indeterminate`；
   ~~**`scanerror` 一档仍未拍**~~ → P6.2d 补了 `09-guardian-login-scanerror.png`（§6.6.5）。
5. ~~**I4 图标环**~~：本轮未动 → P6.2c 关掉，见 §6.6.1。

### 6.6 P6.2c 补记：图标环按稿校正 + 守护页暗档（2026-10-03）

#### 6.6.1 I4 的三条偏差，和一条我原本写错的判据

原记"实现只有纯图标、无环"是看漏了——环一直在，只是**三条都不对**：直径、描边归属、上色条件。
逐条按渲染 PNG 量，不按 CSS 读：

| 判据 | 稿 06（`06-guardian.png` 实测） | 实现·改前（HEAD `p62b-fidelity/03`） | 实现·本轮第一版（照稿面抄 34） | 实现·终态 |
| --- | --- | --- | --- | --- |
| 环外圈直径 | **76 px@2x = 38pt** | 60 px = 30pt（frame 用 `iconRow` 28） | 72 px = 36pt | **76 px = 38pt** ✅ |
| 描边宽度 | 4 px = 2pt | 4 px = 2pt ✅ | 4 px = 2pt ✅ | 4 px = 2pt ✅ |
| 上色条件 | 只有 `.urow.live` 上色（红环 + 红底），其余态中性描边 | 环跟着语义 tint 走 → 空闲态是**绿环** | 已改成只有 `.inUse` | ✅ |

**为什么稿上的 34pt 不能直接抄成 34**（本轮第一版就抄错了这一档）：`screen.css` 里**没有 box-sizing reset**
（全文件 grep `box-sizing` 零命中），所以 `.urow .ring{width:34px;border:2px}` 的 34px 是**内容盒**，
浏览器画出来的外圈是 34+2+2 = 38px——量稿子 PNG 得 76px@2x，正是 38pt。
而 SwiftUI 的 `Circle().stroke(lineWidth: 2)` 骑在路径中线上、向 frame 外各溢 1pt，
所以 38pt 外圈要由 **36pt 的 frame** 承载。常量因此取 36 而不是稿面写的 34，
这条换算写在 `MMDesign.swift:123` 的注释里，免得下一个人"照稿改回 34"。

**绿色只属于徽章**这一条是这一处真正的收获：改前空闲态是绿环 + 右侧绿色 `当前空闲` 徽章，
同一行两处绿，稿里只有一处。这一屏的红/绿是稀缺信号（"此刻确有进程在驱动"），
环和图标不参与表态，多一处上色就稀释一次判定强度。

#### 6.6.2 暗档：去掉药丸底之后行还分不分得开

`MM_APPEARANCE` 是进程级覆盖（不写系统设置），八档各重拍一遍，落
`docs/verification/p62c-dark/`（浅色那套同步换成 P6.2c 构建重拍的，
`p62b-fidelity/` 里现在是**与 HEAD 一致**的八张）。
P6.2b 去掉行药丸底，唯一没核的就是暗档——量同一行像素：

| | 卡底 | 行分隔线 | 线宽 |
| --- | --- | --- | --- |
| 浅色 | `(255,255,255)` | `(230,230,230)` | 2 px |
| 深色 | `(37,37,37)` | `(58,58,58)` | 2 px |

两档都是 2px 发丝线，暗档的相对差甚至更大。
**结论：去药丸没有让暗档的行更难分辨**，这条从"未知"划掉。

#### 6.6.3 两处采集设计缺陷（照片存在，但不证明任何东西）

- **07/08 拍的不是它们命名的东西**：系统活动卡排在第 4 位，它上面那张"读不到"TCC 空态卡
  就有 ~600pt 高，再叠真机 17 条登录项——760pt 窗口里第 4 张卡**永远在折叠线以下**。
  修法（P6.2d）：新增 `MM_GUARDIAN_CARDS` 卡过滤钩子（`GuardianCardFilter` 解析逗号子集，
  非法值整批拒绝并写 stderr），07/10 两档现在用 `MM_GUARDIAN_CARDS=activity` 只渲染活动卡，
  不再需要拉高窗口 + 压矮上方三卡。**代价**：照片上只有一张卡，看不到它在整页里的位置。
- **`ActivityScanner.scan()` 在沙盒环境下会挂起**：07 第一次拍到的是活动卡**空态**而非 `rows`
  夹具——根因不是等待不够，而是 `scanUnifiedLog()` 调用的 `/usr/bin/log show` 子进程在沙盒
  环境下挂起（`sandbox_extension_issue_file_to_process`），`proc.waitUntilExit()` 永远不返回，
  于是 `_ = await Task.detached { ActivityScanner.scan() }.value` 阻塞到超时。
  **P6.2d 修复**：`scanUnifiedLog()` 改用 `DispatchSemaphore` 包 8 秒超时，超时后 `proc.terminate()`
  并返回 nil（降级为空列表）。实测正常 `log show` 约 1 秒完成，8 秒足够；修复后 `rows` 档
  正确渲染 3 条夹具行。**凡是"先真跑再顶替"的夹具，等待必须覆盖真扫描**——这条通用规则
  记进 `hook-ledger.md`，但本例的真正教训是：**子进程可能永远不结束，超时保护不能省**。
  **P11（2026-10-05）把这一条往前推了一步，并且改写了它的结论**：超时保护确实止住了挂起，
  但**真实日志路径此后在本机一次都没返回过内容**——因为 `scanUnifiedLog()` 先 `waitUntilExit()`
  再读管道，而 `Pipe` 只有 64 KB 缓冲、这条命令本机现测返回 **199,740 字节 / 1,511 行**，
  父子互卡到 8 秒双双失败（复现件里 ① 停在整 65,536 字节）。
  也就是说上面那句"超时保护不能省"只讲了一半，另一半是：**超时保护会把死锁伪装成空结果**。
  而 `rows` 档"正确渲染 3 条夹具行"从来没证明过真实路径——夹具把待测的那条读法整条换掉了。
  现在两档签名各有 5 条真实事件的实拍照片（`docs/verification/p11-hardened/03-activity-*.png`），
  复现件与两处读法修正见 `release-readiness.md` §3 末尾。

#### 6.6.4 一张被作废的照片，和为它做的一次系统核查

作废前有一张 light-07 同时画着**登录项夹具行**与一组来源为"登录项/计划任务"的活动行——
前者没注入过，后者的文案格式既不是 `ActivityScanner.scan()` 的输出（它写的是
"LaunchAgent 最近修改"），也不是 `GuardianActivityFixture.items()`（三条都带"（夹具值）"）。
当前构建用同一份环境跑两次得到**逐字节相同**的 PNG，说明那条状态不可复现，照片不作依据、已删。

因为活动行里"用户 LaunchAgent（启用）· 今天 15:24"读起来像是真从 `~/Library/LaunchAgents`
扫出来的，去核了本机有没有被夹具污染：

- `~/Library/LaunchAgents` 与 `/Library/LaunchAgents` 下 `com.example.*` **零个**；
- `launchctl list` / `launchctl print gui/501` 里 `com.example` **零个**；
- 代码侧对得上：`LoginItemStore.toggle` 先 `POSIXFileIO.read(url)`，文件不存在即 ENOENT 返回失败，
  写入一步根本走不到（`LoginItemStore.swift:216`）。

也就是说 `GuardianFixtureHooks.swift:49-52` 那句"任何写尝试都会在读取一步以 ENOENT 失败、不会落盘"
在本机是成立的；那张照片的来历我没能解释，只能作废。

#### 6.6.5 这一轮仍然没核的

1. **侧栏拖到 `max:280` 那一端**、以及用户拖窄到 220 以下的边界（§6.5 第 2 条）。
   **P6.5b 复核：这一条要拆成两半，两半的处置完全不同**——
   - **"拖窄到 220 以下"这半可以现在关掉，不需要照片**。它不是"没量到"，是**结构上不可能发生**：
     `.navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 280)`（`MainWindow.swift:22`）里 `min`
     同时就是 AppKit 给分隔线的下界，拖不过去。§6.3 实验 C 正是靠这一点量到 x=440px@2x = 220pt
     （首屏取 `min`）。**副作用当时已经写在注释里**（`MainWindow.swift:21`：
     "用户能拖到的最窄处从 200 变成 220"）——这条副作用是真的，但它把另一个方向也一起封住了，
     所以"最窄能到多少"这个问题在代码层就有答案，拍它等于拍一个已知量。
   - **`max:280` 那一端仍是缺口，而且缺的是取证手段，不是缺一次截图**。逐一排除了：
     ① 壳层现有的启动钩子全集是 `MM_OPEN_MODULE`（`MainWindow.swift:49`）/ `MM_SHOW_SETTINGS`（`:46`）/
     `MM_SETTINGS_TAB`（`SettingsView.swift:12`）/ `MM_WINDOW_SIZE`（`LaunchBehavior.swift:116`）/
     `MM_APPEARANCE`（`:81`）/ `MM_PROBE_WINDOW`（`WindowProbe.swift:12`），
     **没有一个能移动分隔线**；② `MM_WINDOW_SIZE` 走 `window.setContentSize`（`LaunchBehavior.swift:126`），
     改的是**整窗**尺寸，加宽的部分归 detail 面板，侧栏仍停在 `min`；
     ③ 往 `NSSplitView Subview Frames…` 写值这条路已经被 §6.3 实验 B 否证（应用不读、退出时改回）；
     ④ 代码里没有任何 `setPosition`/`resizeSubview` 可调；⑤ **拖分隔线属合成操作，红线禁止**
     （与"禁止用合成点击验证原生 UI"同条）。
     → 结论：**这一半记为"取证边界"，不是"待办"**。要真量 280 那一端，得先加一个启动时设列宽的钩子
     （例如 `MM_SIDEBAR_WIDTH`，走 `NSSplitViewItem`/`setDraggingEnabled` 之外的公开 API），
     那是新增钩子、要走 `hook-ledger.md` 的立项流程，本轮不擅自加——加了还得同步 README §2 矩阵与账本计数。
     **它挡住的问题也只有一个是实质性的**：280pt 时侧栏内容（页签 + 容量行 + 设置按钮，S1 那条全站缺口）会不会撑破。
     容量行现在没画在稿上、实现有，所以那半本来就是开放项，不缺这一张照片。
2. ~~**登录项 `scanerror` 档**~~ → P6.2d 补了 `09-guardian-login-scanerror.png`（`MM_GUARDIAN_CARDS=login` + `MM_GUARDIAN_LOGIN_FIXTURE=scanerror`）。
3. ~~**活动卡 `empty` 档**~~ → P6.2d 补了 `10-guardian-activity-empty.png`（`MM_GUARDIAN_CARDS=activity` + `MM_GUARDIAN_ACTIVITY_FIXTURE=empty`）。
4. **稿 06 的 S 系列**（S1–S4 全站 token 漂移、S10 警示条旁多画系统级行）仍归协调层，本轮没动设计稿。

#### 6.6.6 P11 收口：这张活动卡连着三处读法错，外加一处谓词口径缺口（2026-10-05）

hardened runtime 那一轮（`release-readiness.md` §3）本来只想回答"打了 runtime 这七行能力还在不在"，
结果**唯一一行"看起来什么都没发生"的格子**（系统活动）把三条缺陷全带出来了。三条都已修，
判据都在 `ActivityScannerLogRowTests`（10 条）：

1. **管道死锁**——`waitUntilExit()` 在先、读管道在后，`Pipe` 只有 64 KB 缓冲，
   这条命令本机现测 199,740 字节 / 1,511 行，父子互卡到 8 秒双双返回 nil。
   **这个函数自落地起从未返回过内容**（§6.6.3 那条"超时保护不能省"只讲了一半）。
2. **列宽吃掉正文**——修好死锁后第一次真有 5 行，可 5 行全是 7 段定宽列（78 个字符），
   旧代码 `line.prefix(80)` 让正文一个字都没进画面；折行续行还被顶成第 6 条事件。
3. **「最近」画的是最旧的 5 条**——`log show` 是**升序**输出（实测末行就是"刚刚那一秒"），
   而代码取 `prefix(5)` + 写死的 `time: "最近"`。15:07 那两张照片里五行时间戳全在 15:02，
   也就是**没有一行发生在最近 4 分钟内**。现在 `recentLogRecords(of:)` 取末尾 5 条、最新在前，
   15:29 重拍的两档五行就是扫描那一刻（base 15:29:23.x / hr 15:29:37.x）。

**顺序这一条是前两条修完才看得见的**：死锁时这张卡一行都没有，列宽错时 5 行全是没内容的列，
两种情况下"凭什么是这 5 条"都无从问起。**读照片要读到时间戳那一层**，
只读文案会连着放过三条错——这是本轮最值钱的一条方法。

**留下的缺口（这一轮没动，因为动它等于重定产品口径）**：修好顺序之后重拍的两张照片里，
base 那 5 行有 4 行是**应用自己的回声**——`log … log run noninteractively, parent: 93499 (MacMaster)`
（这次扫描本身：`log` CLI 把整条命令行写进正文，而我们的谓词原文含 `"login" OR … "auth"`，
于是这一行命中了自己的谓词）、两行 `tccd: [com.apple.TCC:access] AUTHREQ_RESULT`
（同一页的 TCC 探测刚问出去的两次授权查询）、一行 `runningboardd … RBSSStateCaptureSet`。
hr 那张同形（parent 93561）。**根因是谓词本身**：`eventMessage contains "login" OR contains "auth"`
当初就没有一份"这张卡该显示什么"的文案合同，它同时命中了登录/授权类事件与**我们自己发起的授权查询**。
按 pid 或命令行过滤治不了（tccd、runningboardd 是别的进程写的），所以这一条记为
**§1.5 那张卡缺文案合同**（与 S12「设计稿没有这张卡」是同一个归属），要收口得先定"系统活动"四个字的口径。

### 6.7 P11c 收口：这一卡的文案合同，日志族整族撤下（2026-10-05）

§6.6.6 留的那句"要先定『系统活动』四个字的口径"，这一轮就是那份合同。**合同的内容是：这一卡不再报活动。**
它只报一件事——几个固定路径的修改时间。理由不是"日志太吵所以少显示几行"，是量完之后
**没有任何一档谓词能同时做到低噪、可读、切题**（下面每一行都是本机现测，`log show --style json` 读回，
不靠肉眼数照片；列数不定的 compact 格式数进程会数成正文片段，本轮在这里错过一次，见 `hook-ledger.md` §5）：

| 档 | 谓词 | 窗口 | 行数 | 量到的东西 |
| --- | --- | --- | --- | --- |
| 现状 | `eventMessage contains "login" OR contains "auth"` | 5m | **139** | 47 行（34%）是 sharingd 的 `### Unable to decrypt activity level with authTag`，每 7 秒一枚；另有 **5 行是 `log` 把我们自己的谓词原文回声回来**（`args: '/usr/bin/log' 'show' … 'eventMessage contains "login" OR …'`）。这一档量到的是"正文里含这几个字母组合"，不是"系统活动" |
| 窄白名单 | `processImagePath ENDSWITH "/loginwindow" OR "/authd" OR "/authorizationhost" OR "/tccd"` | 5m | **52** | 全部来自 tccd 一家。正文形状：`AUTHREQ_ATTRIBUTION: msgID=410.180710, attribution={accessing={TCCDProcess: identifier=com.apple.spotlightknow…`、`SecTrustEvaluateIfNecessary`、`Kernel: kauth_membership_check`；中位 69 字符，2 行含 `<private>`（苹果自己把正文涂掉了）。**没有一行是用户读得懂的** |
| 只留登录 | `processImagePath ENDSWITH "/loginwindow"` | 5m | **0** | 这台机器 5 分钟内没人登录。空是真的，但一张常年为空的卡不叫信息 |
| 切题 A：摄像头/麦克风 | `tccd AND (Camera OR Microphone)` | 24h | **0** | 授权判定被缓存，不落这条日志。守护页真正想报的"谁用了摄像头"在这条路上一个字都没有 |
| 切题 B：音频/摄像守护 | `camerad OR coreaudiod` | 24h | **437** | 全是 coreaudiod，正文 `UserActivityLevel: 80, Capabilities 31, DidChange: 0, OldState: FullWake, NewState: FullWake`、`IsHidden: 1` |
| 切题 C：Gatekeeper | `processImagePath ENDSWITH "/syspolicyd"` | 30m | **20,741** | `Unable to initialize qtn_proc: 3` / `dispatch_mig_server returned 268435459` 成对刷屏 |
| 切题 D：登录族全量 | `loginwindow OR authd OR authorizationhost OR ManagedClient OR opendirectoryd` | 60m | **3,249** | loginwindow 一家 2,763 行 = 每分钟 46 行的空闲/时间检查噪声 |
| 对照：subsystem 等值 | `subsystem == "com.apple.loginwindow.logging" OR "com.apple.TCC.access" OR "com.apple.AuthenticationServicesCore"` | 5m | **0** | 抄 OverSight 的写法。等值匹配在这台机器上直接落空——**苹果自家 subsystem 名不是照着猜的那套**，白名单路线连门都要先摸对名字 |

**三家参考项目都没有这一卡**（`docs/github-references/`、`docs/Mole/`、`docs/lemon-cleaner/` 现查）：
Mole 的 LaunchAgents 只作为清理对象与保护规则出现（`lib/clean/apps.sh:773` "NEVER add LaunchAgents…"），
Lemon 扫 LaunchAgents 只为找卸载残留（`QMCoreFunction/…/McSoftwareFileScanner.m:334-337`），
Pearcleaner 只展示 `kMDItemLastUsedDate` 且文案就是 "Last Used Date"（`FilesSidebarView.swift:153`）。
唯一真消费统一日志的是 OverSight，走 Apple Log API 实时流 + 苹果自家 subsystem 白名单
（`AVMonitor.m:232` `subsystem=='com.apple.cmio' OR …`），**没有一家用 `eventMessage contains` 自由文本**，
它排除自身回声的方式是结构性的：只订苹果自家 subsystem，自家日志天然不在流里。
**把 mtime 叫"最近访问"的也只有我们自己**：Mole 用的是真 atime（`cmd/analyze/scanner.go:1214-1219`
`stat.Atimespec`）且文案保守到只在 >90 天时显示 `>3mo`/`>1yr`（`format.go:247-268`），从不写"X 天前访问"。

于是合同三条，全部写进 `ActivityCardCopy`（文案常量集中一处，判据在 `ActivityCardContractTests` 8 条）：

1. **日志族整族撤下**——`scanUnifiedLog()` 连同四个拆行/取尾辅助函数一并删除。
   §6.6.6 那三条修复（死锁、列宽、取尾）不是白做的：它们把"这一路能不能用"量清楚了，
   结论是**这一路能给用户的东西没有**；复现件 `Scripts/p11-pipe-deadlock-repro.swift` 留在仓库里，
   因为 `SystemSpaceReport` 那处 `Process` + `Pipe` 是同一个形状（只因 tmutil 输出小才没发作）。
2. **`detail` 一律是绝对路径、`time` 一律是那个 mtime 的相对说法**——从前敏感目录那行写
   「最近访问: 刚刚」而右侧时间列又写一遍「刚刚」：同一个数说两遍，而且说得不对
   （读的是 `.modificationDate`；mtime 只在目录**增删条目**时变，读取里面的密钥文件不动它）。
   卡片脚注把这句说明白：*这一格能看出密钥目录最近有没有被写过，不能用来判断有没有人访问过你的密钥*。
3. **标题跟着口径改**：「系统活动」→「密钥与自启配置的改动时间」；空态从前写
   「近 5 分钟没有可读到的活动事件」，可剩下的两族**根本没有 5 分钟窗口**（目录存在就出列，mtime 可以是几年前），
   现在空态说的是真缺的东西：三个目录都没有 + 用户级 LaunchAgents 里没有 `.plist`。
   tone 也收口：`ActivityTone` 从四支剩两支（caution / neutral），密钥目录橙、LaunchAgent 中性灰——
   从前那三行是 `.destructive` 红，等于天天在喊"你的密钥出事了"，而它报的只是一个 mtime。

**顺带修掉一个真机恒为 0 行的缺陷**（这是量出来的第二个意外）：LaunchAgent 那一族从前写的是
`for file in files.prefix(3) where file.hasSuffix(".plist")`——**截断发生在过滤之前**。
本机 `~/Library/LaunchAgents` 有 9 个条目，其中 6 个是改名停用的 `.disabled`，而 `contentsOfDirectory`
把它们排在了最前，于是这一族在真机上一行都不产出，尽管磁盘上确实躺着 3 个 `.plist`。
现在先过滤、再按 mtime 倒序、再取 3。判据 `testDisabledAgentsDoNotCrowdOutTheRealPlists`
喂的就是本机那 9 个条目的真实顺序；照片侧 `p11c-activity/01-real-machine.png` 三行 `.plist` 全在。

**照片与交叉验证**（`docs/verification/p11c-activity/`，脚本 `Scripts/p11c-activity-capture.sh`，四档）：
01 真机 / 02 夹具 rows / 03 夹具 empty / 04 夹具 rows @1000×700。01 那份 `.log` 里带 `# expect:` 行——
脚本用 `stat` 现读这五个路径的 mtime（**与代码不同的读法**），照片上那五个"X 前"必须能从 expect 行推出来：
`.ssh` 2026-08-20 14:23 → 照片 46 天前、`Keychains` 10-05 07:59 → 8 小时前、
`com.tencent.Lemon.trash.plist` 10-01 20:45 → 3 天前、`sh.brew.jenkins-lts.plist` 09-25 11:12 → 10 天前、
`com.pnuts.jenkins.plist` 09-07 10:36 → 28 天前。`.gnupg` 本机不存在 → 照片上确实没有那一行。
04 那一档看的是绝对路径在窄窗下不溢出、脚注换行两行不切字。

**这一轮的账**（现读，全部重量）：MMGuardian 测试 93 → **91**（删 10 条日志拆行判据、加 8 条合同判据），
全仓 581 → **579**、0 失败、1 跳过（仍是 MMDisk 那条没有第二块挂载卷的）；
生产代码 26,428 → **26,340** 行（−88），测试代码 8,957 → **8,984** 行；
非测试源码里的 `Process()` 启动点 4 → **3** 处；取证钩子名仍是 **52** 个（本轮一个新钩子都没加，
`MM_GUARDIAN_ACTIVITY_FIXTURE` 是既有的，只改了它的 rows 档用词）。

## 7. P13：候选产物上重拍 + 本文行号引用现读复核（2026-10-05）

`release-readiness.md` §7.4 记的是发版侧那一遍；这一节只记**本文档自己**被重读出来的东西。

### 7.1 页头副标题少列一张卡 —— 新增 **D1（两边都改）**

`MMGuardian.swift:24` 与稿 `06-guardian.html:93`、`:305` 三处的副标题逐字相同，
所以 §1.1 那一行从前是 ✅——**"两边一致"是真的，"两边都对"不是**：这句只列了三件事
（占用 / TCC / 登录项），而这一屏有四张卡（第四张就是 §6.7 改名之后的「密钥与自启配置的改动时间」，
`MMGuardian.swift:39` 的 `if shows(.activity) { activityCard }`）。

**为什么现在才看得见**：从前那第四张叫「系统活动」，"活动"这词宽到没人拿它去数副标题列了几项；
P11c 把它改成一个具体到路径种类的名字之后，**它和那三项就是同一类东西**，缺一项才成了缺口。
这是一条**改名把另一处的旧账照出来了**的记录——改文案的收尾不是改那一处，是把引用它的每一处都过一遍。

**归属**：实现 + 设计稿同一句文案，改哪边都要动两边（源码一行、稿两行），所以记为**两边都改 D1**，
本文的"两边都改"从 **0 条变 1 条**。严重度**低**：副标题不是承诺，页面上四张卡都在，
没有一处说了代码支撑不了的话——它只是少说了一件已经存在的事。**不阻塞发版。**

### 7.2 本文 §1 的行号引用：一次全量现读，漂了 9 处

P11c 删了 `ActivityScanner` 那一段之后，本文所有指向 `MMGuardian.swift` 的行号都被规则要求重读了一遍。
结论：**§1.2–§1.4 的九处引用全漂**，漂幅 +9 到 +41 不等（不是同一个常数，所以不是"整段位移"，
是 P6.2b/P6.2c/P11 三轮在文件不同位置增行累积出来的）。逐条已就地改成现读数并各自标注"P13 现读"：

| 元素 | 原记 | 现读 |
| --- | --- | --- |
| 占用卡"测量于 …"在卡头 | `:84` | `:88-92` |
| 占用卡头图标 `iconTint` | `:80` | `:82-85`（原记那一行是 `occupancyCard` 声明） |
| 占用卡口径脚注 | `:99-107` | `:112-120`（文案在 `:116`） |
| 占用卡首帧骨架 | `:90-93` | `:97-102` |
| TCC 卡标题 + caption | `:122-129` | `:153-158` |
| `.unreadable` 态不画列表 | `:136-148` | `:169-182`（标题常量在 `TCCAuthorization.swift:239`，不在本文件） |
| `.emptyRead` 态 | `:149-155` | `:183-190` |
| `.partial` 态警示条 | `:156-158` | `:191-195`（`partialStrip` 定义在 `:221`） |
| 登录项卡标题 + 按钮 | `:213-222` | `:252-261` |
| 读取失败横幅 | `:31-69` | 调用 `:31-33`、定义 `:60-76` |
| 写失败面板 | `:42-48,502-510` | `:44-50` 与 `:590-598` |

**没有一处是"引用指错了元素"**——每一条按新行号读回去，说的还是同一件事。
所以这一批的正确读法是：**结论全部有效，坐标全部过期**。这也正是 `release-readiness.md` §5
那句"本文行号最密的一处"反复撞的同一面墙：**行号是最先过期、又最不会报错的引用**。
本文往后新增引用时优先写**符号名 + 一句语义**（如 `partialStrip` 定义 `:221`），
行号只当辅助坐标，理由就记在这里。

**P13 重跑复核的数**（全部现读，与 §6.7 结尾那一段对照）：全量测试 **579 / 0 / 1**（MMGuardian 91，
逐包求和 = 579）；生产代码 **26,340** 行、测试代码 **8,984** 行——**这两个数没漂**，
说明 P11c 之后没有别的轮动过源码。候选产物上的照片在 `docs/verification/p13-v1/01-real-machine.png`
（`# expect:` 五条 `stat` 读数与画面上的"46 天前 / 8 小时前 / 3·10·28 天前"逐条推得回，`.gnupg` 仍无行）。

## 8. P14：D1 收口，以及"副标题加长"这件事只有照片能看出来（2026-10-05）

### 8.1 D1 关闭：一句副标题现在由一份清单生成

§7.1 那条 **两边都改 D1** 已关闭，两边都改的是同一份来源：

| 位置 | 改法 |
| --- | --- |
| 实现 | `MMGuardian.swift` 页头改成 `MMPageHeader("隐私守护", subtitle: GuardianPageCopy.subtitle)`；`enum GuardianPageCopy` 把四段写成 `subtitleSegments` 数组，`subtitle` 只是它的 `" · "` 拼接 |
| 设计稿 | `06-guardian.html` 两处 title-block（`:93` 浅色、`:305` 暗色）逐字换成四段 |
| 判据 | `GuardianHeaderContractTests`（4 条）：段数 == `GuardianCard.allCases.count`、段段非空且互不重复、最后一段必须以 `ActivityCardCopy.title` 开头、第一段仍含"非实时监听" |

**否证实验做过**（这是它和"顺手改个文案"的区别）：把第四段从数组里删掉、只跑这一支测试 →
`Executed 4 tests, with 2 failures`，两条失败消息分别把缺口和后果说了出来：
`这一屏有 4 张卡，副标题却列了 3 件事`（XCTAssertEqual 3≠4）与
`副标题最后一段是「登录项管理」，而卡片自己的标题是「密钥与自启配置的改动时间」——同一个东西不许有两个说法`。
所以这条判据不是"看着像能红"，是在 D1 当时的真实状态下量过会红。

第四段刻意写成 `ActivityCardCopy.title + "（只读 mtime）"` 而不是另起一句中文说明：
卡自己的标题改了，页头就得跟着改，否则两边又变成两个说法（`testActivityCardSegmentUsesTheCardsOwnTitle` 钉的就是这一条）。

### 8.2 加长的代价不是换行，是省略号——所以必须有照片

`MMPageHeader.body`（`Packages/MMUI/Sources/MMUI/MMDesign.swift`，按符号名找）给副标题写的是
`.lineLimit(1)` + `.truncationMode(.middle)`，注释里说明这是为"副标题常带完整路径"准备的。
于是 3 段变 4 段这件事**不会**报错、**不会**换行、**也不会**把卡片挤下去：
它唯一的可见后果是画面上多一个 `…`，而切掉的正好是句子中段——也就是"登录项管理"这种一眼扫过去最不像缺了的词。
单测全绿、代码 review 看不出问题，**这一条只能靠实机窗口照片判**。

`Scripts/p14-header-capture.sh`（本轮新增，三档、零夹具、零合成点击）：

| 档 | 窗口 | 生效尺寸（`.log` 里应用自己回读的那一行） | 副标题 |
| --- | --- | --- | --- |
| `01-default` | 不给 `MM_WINDOW_SIZE`，走 `.defaultSize` | 1100×700 | 四段全在，无 `…` |
| `02-min-window` | 请求 1000×600 | **1000×652**（被 `.frame(minHeight:)` 夹，宽度这一维是真实的） | 四段全在，无 `…` |
| `03-wide` | 请求 1400×900 | 1400×900（未被夹） | 四段全在，无 `…` |

照片在 `docs/verification/p14-header/`。**最窄档的余量不大**：副标题末尾与「刷新」按钮之间
按照片 2× 比例估约 28pt，也就是**不到三个汉字的宽度**（估读，不是量出来的数，所以不写进判据）。
这条余量就是往后真正要守的东西：**页头副标题每加一段，必须重跑这一支脚本**——
它不是"反正会换行"的那类文案，加到第 3 个汉字宽以上就会静默变成省略号。

**设计稿在这一判据上帮不上忙**：稿是一张固定 1100 CSS px 宽的画板（§0「渲染」那一行），
它只能表达"某一个宽度下的样子"，而这一句的风险全在**宽度往下走**的那一侧。
所以页头副标题这一项，除了 §1.1 那句"逐字一致"还要加一句：**放不放得下由照片管，不由稿管**。

### 8.3 改名残留扫尾：活引用改四处，历史引用一处不动

P11c 把「系统活动」改成「密钥与自启配置的改动时间」之后，本轮把仍写着旧词的**活引用**过完：

| 引用 | 处置 |
| --- | --- |
| `MMGuardian.swift` 里 `activityFixtureStage` 的注释 | 改成新卡名，并写明键名 `ACTIVITY` 为什么保留（改键名会让已归档照片与脚本失配） |
| `MMGuardian.swift` 里 `loadAll()` 排序理由 | 原文"不该排在 `log show` 这类秒级子进程扫描之后"——`scanUnifiedLog` 已在 P11c 删除，改成仍然真实存在的 `launchctl list`（`LoginItemStore` 的只读快照） |
| `docs/design-system/README.md` 钩子表 | `(empty/rows，系统活动卡)` → 新卡名 + "P11c 之前叫「系统活动」" |
| `Scripts/p11-hardened-check.sh` 03 档 | **判据本身已经不成立**：那一档从前测的是 `/usr/bin/log show` 子进程在两种签名下通不通，日志族撤下后它永远拍不到"系统日志事件"行。改成写明"不再是 hardened runtime 的判据，只旁证这一屏在 runtime 下照样渲染"，并注明 P11c 之前那两张 `03-activity-*.png` 证明的是当时的判据 |
| `docs/website/index.html` 两句"监控系统活动" | 见 §8.4 |
| 稿的渲染图 `06-guardian.png` | HTML 改了、**入库那张 PNG 还是 9-30 渲的**（P11c 补的那一节与这次的第四段都不在图上）→ 按旧图同一宽度 1100 重渲，高度量出来（顺带修掉 §0「渲染」那一行：从前记的 `1160 4600` 与旧图尺寸 2200×5200 根本对不上，那条命令没跑过） |
| 本文 §4/§6 与 `feature-roadmap.md`、`coordination-gantt.html` 里的旧卡名 | **不动**：那些是当时的记录（哪一轮拍了什么、缺什么），改成新词等于把历史改掉 |

### 8.4 第三处表面：落地页

`docs/website/index.html` 的隐私守护卡片从前写"管理登录项，**监控系统活动**……"。
这一句既不是设计稿也不是实现，是**第三个表面**，而 P11c 之后它成了假话（我们不再读统一日志，
占用那一格也明写"非实时监听"）。本轮只改了被 P11c 证伪的这两句（卡片正文 + 截图位说明）。

顺带记一条**没做的**：`grep -rn "website" docs/analysis/` 在改动前是 **0 命中**——
这份落地页从来没有跟实现对照过。页里其余口号（"一键清理"、"智能扫描系统缓存、日志、临时文件"、
"实时监控 CPU…"）与截图位（四张 `screenshot-placeholder`，一张真图都没有）都还没核过，
发版若要用这一页，得单开一轮。截图位是四个 `screenshot-placeholder` 的 div、
全页 `<img>` 标签为 0（现读：`grep -c screenshot-placeholder` = 5，其中一处是 CSS 规则本身），
也就是说这一页从来没有放过真图。已写进 `release-readiness.md` §6 的待办。




