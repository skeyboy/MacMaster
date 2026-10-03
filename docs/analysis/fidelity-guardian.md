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
>
> **P6.2b 更新（2026-10-03）**：实现该改从 4 条变 6 条（新增 I5 整页分隔语言、I6 定高切字），其中 **I1/I3/I5/I6 已落地**、
> I2 归协调层；§4 里"无头拍不到"的 5 项已实拍（`docs/verification/p62b-fidelity/`），
> 系统活动卡那项也因 `MM_GUARDIAN_ACTIVITY_FIXTURE` 落地而不再无解。**本轮改动与两次否证实验集中在 §6。**
>
> **P6.2c 更新（2026-10-03）**：**I4 关掉**——占用行图标环的直径/描边/上色三条都改过（§6.6.1），
> 守护页八档另出一整套深色档（`docs/verification/p62c-dark/`，§6.6.2），
> §6.5 里"深色档没量/活动卡没拍/登录项 indeterminate 没拍"三条一并划掉。

## 0. 对照方法（先说清楚哪些是量出来的）

| 事项 | 值 |
| --- | --- |
| 设计稿 | `docs/design-system/screens/mmguardian/06-guardian.html`（3 个 artboard：A 正常态首屏·四档 montage / B Mac mini 实机首屏 / C TCC 降级双卡「读不到」「查到了没有」） |
| 渲染 | `cd docs/design-system && ./render.sh screens/mmguardian/06-guardian.html 1160 4600` → `screens/mmguardian/06-guardian.png`（稿内已出，本审计未重渲） |
| 实机 | **P3 审计时无头**（该节判定全部来自代码 + HTML + tokens 比对）；**P6.2b 起本模块有实拍**：`docs/verification/p62b-fidelity/`（raw @2x PNG）。原记"全站像素锚点引用 monitor §0（侧栏 220pt）"已被本轮重测推翻——改前实机是 200pt，见 §6.3 |
| 可用钩子 | `MM_GUARDIAN_FIXTURE`(占用档) / `MM_TCC_FIXTURE`(TCC 档) / `MM_GUARDIAN_LOGIN_FIXTURE`(登录项档) / `MM_GUARDIAN_LOAD=hold`(首帧定格)。四个钩子均 `com.example.*` 合成、只读、不写盘（`grep processInfo.environment Packages/MMGuardian/` → 4 命中） |
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
| 副标题「摄像头与麦克风的当前占用（手动测量，非实时监听）· TCC 授权只读视图 · 登录项管理」 | `:24` | ✅ | 逐字一致（与 `guardian-device-usage.md` 复核口径"非实时监听"对齐） | — | — |
| 右侧「刷新」按钮 | `:25-27` `.buttonStyle(.bordered)` `.controlSize(.small)` | ✅ | 稿内 `<span class="btn sm">刷新</span>` 对应 | — | — |
| 稿 toolbar 内「测量于 10:24:07」（A 稿有、B 稿无，稿内自不一致） | 实现把"测量于 …"放到**当前占用卡头**（`MMGuardian.swift:84`），toolbar 不放时间 | ❌ | 采样时刻位置分歧：设计画在 toolbar，实现画在占用卡头（更贴近数据，且 B 稿本就没画时间，实现反而更一致） | 低 | 设计稿该改 S5 |
| 卡头摄像头图标恒为次级色（不表态） | `MMGuardian.swift:80` `.foregroundStyle(MMColor.secondaryLabel)` | ✅ | 与稿 cap"卡头的摄像头图标不参与表态"一致——红色只属于"正在被使用" | — | — |

### 1.2 当前占用卡（P3.1）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「当前占用」+「只读检测 · 不申请任何权限」小字（A 稿 section 头） | `MMGuardian.swift` `occupancyCard` → `sectionHeader(caption:)` | ✅（P6.2b 起） | 改前实现卡头**没有**这句诚实披露；P6.2b 把区块头搬到卡外时按稿补了小字（I3 关闭），实机见 `p62b-fidelity/03-guardian-rows.png` | 低 | 实现该改 I3 → **已落地** |
| 档1 摄像头 live：徽章「正在被使用」(danger+warn 图标) + 备注「使用方无法确定 · 公开接口不返回进程」 | `DeviceUsageCopyTable` inUse（`DeviceUsage.swift:135-143`）+ `DeviceUsageRow:594` 红 tint + `exclamationmark.triangle.fill` | ✅ | 逐字一致；红色仅此档 | — | — |
| 档2 麦克风(内置) idle：徽章「当前空闲」(safe) + 备注「1 个纯输入设备 · 读数 0」 | `DeviceUsage.swift:144-151`（idle 备注 nil） | ❌ | 设计 idle 档有"1 个纯输入设备 · 读数 0"备注，实现 idle `note:nil`，只保留 detail"输入设备存在，本次测量未读到任何进程驱动" | 低 | 设计稿该改 S6 |
| 档3 麦克风(Studio Display) combo：徽章「无法确定」(readonly) + 备注「不等于"没有应用在用"」 | `DeviceUsage.swift:160-165` `indeterminate(.comboAmbiguity)` | ✅ | 逐字一致 | — | — |
| 档4 摄像头(USB) readFailed：徽章「无法确定」(readonly) + 备注「可点"刷新"重测」 | `DeviceUsage.swift:154-159` `indeterminate(.readFailed)` | ✅ | 逐字一致 | — | — |
| absent 档（B 稿）：「本机没有摄像头」/「无可用麦克风」，中性灰 readonly | `DeviceUsage.swift:173-180` `deviceAbsent` + `DeviceUsageRow:615` 灰 tint | ✅ | 逐字一致；灰非绿（"无法确定"绝不借绿） | — | — |
| 图标环 34pt、2px 描边、**只有 live 上色**（稿 `.urow .ring` + `.urow.live .ring`） | `DeviceUsageRow` 的 `ZStack{ Circle().stroke … }` | ✅（P6.2c 起） | 原记"实现只有纯图标、无环"是**看漏了**：环一直在，但**三处与稿不符**——外圈 30pt（frame 用的就是 `iconRow` 28）而非稿面渲染出的 38pt；描边跟着语义 tint 走，于是空闲态是一枚**绿环**，而稿里绿色只属于右侧 `badge safe`，环与图标不参与表态；live 缺那层 `--c-danger-soft` 红底。三处已按稿校正（直径走新常量 `MMMetric.iconRing`，取 36 而非稿面 34，换算见 §6.6.1） | 低 | 实现该改 I4 → **已落地** |
| 占用行 min-height 56pt（稿 `.urow`） | `DeviceUsageRow` `frame(minHeight: MMMetric.rowRegular)`（rowRegular=44，`MMDesign.swift` token `--row-h-regular:44px`） | ❌ | 设计 56pt vs 实现 44pt，行高不一致 | 低 | 设计稿该改 S7 |
| 口径脚注「空闲=设备在且测到没人驱动；无法确定≠没有应用在用；本机没有设备时如实显示…」 | `MMGuardian.swift:99-107`（"占用时系统公开接口不返回进程名，本面板不猜使用方"） | ⚠️ | 语义一致，实现脚注略简、未展开"本机没有设备"那半句（该态已有独立徽章，冗余可接受） | 低 | 记录 |
| 首帧（deviceUsage 空）→ 2 条 `MMSkeletonRow` | `MMGuardian.swift:90-93`；由 `MM_GUARDIAN_LOAD=hold` 定格 | ✅（代码分支） | 设计稿未绘骨架 artboard，但钩子可构造 | 低 | 设计稿该改 S8（建议补骨架态 artboard） |
| 四档 montage（A 稿把四档并排画全） | 每设备仅持一态，需用 `MM_GUARDIAN_FIXTURE` 分屏截图（camera/mic 各一态） | ⚠️ | A 稿四行不是单屏可渲染态，实现每设备一行——设计应标注"每态独立示意"避免被当成单屏 | 低 | 提协调者 G4 |

### 1.3 敏感权限授权卡（P3.2）—— 重点：授权表读不到 ≠ 未授权

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| 卡标题「敏感权限授权」+「SQLite 只读查询 · 不写库不提权」 | `MMGuardian.swift:122-129` | ✅ | 逐字一致 | — | — |
| **`.unreadable`（两库都打不开）→ 不画列表，只给原因 + 引导**（C 稿左卡） | `TCCViewerState.unreadable` + `TCCProbe` `.unreadable(reason:)` 两类型隔离；`MMGuardian.swift:136-148` `MMEmptyState(title:"读不到 · 需要完全磁盘访问")` | ✅ | **红线守住**：读不到态**绝不画列表**，与"明确未授权"是两套代码路径 | — | — |
| **`.emptyRead`（可读且 0 行）→ "相关服务没有授权记录"，明确"查到了没有不是没查到"**（C 稿右卡） | `TCCViewer.build` `if unreadable.isEmpty { return .emptyRead }`；`MMGuardian.swift:149-155` | ✅ | **红线守住**：只有"没有任何库 unreadable"才允许出现此档；有库没读到则降 `.partial` | — | — |
| **`.partial`（一库可读一库打不开）→ 列表 + 顶部点名读不到的库** | `TCCViewer.build` partial + `MMGuardian.swift:156-158` `partialStrip` | ✅ | **红线守住**：partial 档**只列读到的库的行**，过滤掉读不到库（见下 F 项） | — | — |
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
| 卡标题「登录项 N 项」+「打开系统设置 · 登录项」 | `MMGuardian.swift:213-222` | ✅ | 本机 N=17（与 hook-ledger"本机 17 项"一致） | — | — |
| 行1 改名停用：`com.codex...disabled` + 「改名停用」徽章 + 开关 | `LoginItemRow:533-559`（renamedDisabled→「改名停用」徽章；user 域→`Toggle`） | ✅ | 开关 off（enabled=false）对应稿 `.sw` | — | — |
| 行2 未加载：`com.pnuts.jenkins` +「没在当前会话里加载」(warn) + 开关 on | `LoginItemAnomalyCopy.badge(.plistNotLoaded)` + `isWritable`→`Toggle` on | ✅ | 逐字一致 | — | — |
| 行3 系统域未加载：`com.sogou...` +「没在当前会话里加载」+「只读」+「在系统设置中管理」 | `domain==.system`→`isWritable=false`→只读徽章+按钮；异常 plistNotLoaded | ✅ | 双徽章+按钮，与稿一致 | — | — |
| 行4 系统域只读：`com.docker.socket` +「只读」+「在系统设置中管理」 | 同上 | ✅ | 一致 | — | — |
| 脚注①孤儿：「launchd 里还挂着 N 个非苹果标签…com.ollama.ollama、com.postgresapp…不一定是残留」 | `LoginItemAudit.swift` + `LoginItemAnomalyCopy.orphanNote` + `auditFooter`（count+前 6 标签） | ✅ | 语义一致（标签名是样本数据，结构一致） | — | — |
| 脚注②「没在当前会话里加载≠坏了…不替你下结论」 | `LoginItemAnomalyCopy.footnote`（`LoginItemAudit.swift:202`） | ✅ | 逐字一致 | — | — |
| 不可核对脚注「这一轮没对表…没查到不会被写成没加载」 | `LoginItemAnomalyCopy.indeterminateNote` + `auditFooter` `!determinate` 分支 | ✅ | 由 `MM_GUARDIAN_LOGIN_FIXTURE=indeterminate` 可构造 | — | — |
| 读取失败横幅（顶部黄条，scanerror 档） | `readErrorBanner`(`MMGuardian.swift:31-69`) + `scanErrors` | ✅（代码分支） | 由 `MM_GUARDIAN_LOGIN_FIXTURE=scanerror` 注入；**设计稿无专用 artboard 描绘该横幅** | 低 | 设计稿该改 S11 |
| 写失败面板（toggle 系统域/改名文件被拒 → `MMFailurePanel`） | `MMGuardian.swift:42-48,502-510` | ✅（代码分支） | 交互结果态；**设计稿未绘** | 低 | 设计稿该改 S11（同条） |
| 登录行 min-height 44pt（稿 `.login`） | `LoginItemRow` `frame(minHeight:)`（P6.2b 前是 `frame(height: 44/56)` **定高**） | ❌→✅ | 原判定"✅ 与 token 一致"是**错的**：稿写 min-height，实现写死 height，带异常徽章的行有第三行文字，44/56 钉死就把徽章那行齐根切掉。改后见 `p62b-fidelity/04-guardian-fixture-rows.png`（三行徽章完整） | 低 | 实现该改 I6 → **已落地** |

### 1.5 系统活动卡（实现独有，设计稿 06 无此 section）

| 稿内条目 | 实现出处 | 一致? | 量到的差异 | 严重度 | 归属 |
| --- | --- | --- | --- | --- | --- |
| （设计稿 06 完全没有「系统活动」卡） | `MMGuardian.swift:297-339` `activityCard` + `ActivityScanner`（近期 log 事件 / LaunchAgent 改动 / `~/.ssh`·`~/.gnupg`·`~/Library/Keychains` 访问时间） | ❌ | 实现多了第 4 张卡；产品规划文档 §4.5 有"最近活动"区块，但设计稿落后未补，且实现按"诚实口径"重做（不编造进程名、无「阻止」按钮） | **中** | 设计稿该改 S12 |
| 空态「近 5 分钟没有可读到的活动事件」 | `MMGuardian.swift:306-309` | ⚠️ | 实现独有，无设计稿可对照；且**无专属夹具钩子**，不能无头构造 | 中 | 提协调者 G1 |
| 卡片几何（icon=eye、行高 44、contentBackground 药丸） | `activityCard`：行改平铺 + `Divider()`，`minHeight: rowCompact`（P6.2b） | ⚠️ | 药丸底已去掉（全站只有这一页在用，与稿 06 的平铺行冲突）；但**这张稿 06 里根本没有**，所以像素项仍无基准可比 | 低 | 记录（区块归属见 S12） |

## 2. 实现该改（6 条，按严重度排序；P6.2b 关掉 3 条、P6.2c 关掉 I4）

1. **【低】I1 · 侧栏宽度** —— **P6.2b 已落地**。本条原记"实机 220 vs 令牌 216"，两个数都不对：改前实机量到 **200pt**，令牌早已是 220。改法与两次否证实验见 §6.3。
2. **【低】I2 · 标题栏实现 ≈52pt vs 令牌 38pt**（实机黑线 y=52，全站 I10b）。同上，归协调层。
3. **【低】I3 · 当前占用卡头缺"只读检测 · 不申请任何权限"诚实小字** —— **P6.2b 已落地**：区块头搬到卡外时按稿补 `sectionHeader(caption:)`，TCC 卡同步给"SQLite 只读查询 · 不写库不提权"。
4. **【低】I4 · 占用行图标环与稿不符** —— **P6.2c 已落地**。本条原判定"实现没有环"是**看漏**（`DeviceUsageRow` 一直有 `Circle().stroke`），真实差异是三处：外圈 30pt vs 稿面渲染出的 38pt（稿上写的 34 是内容盒，见 §6.6.1）、描边跟语义 tint 走（空闲态因此成了绿环，而稿里绿色只属于右侧 `badge safe`）、live 缺 `--c-danger-soft` 那层红底。改后见 §6.6。
5. **【中】I5 · 整页分隔语言与稿 06 不一致** —— **P6.2b 已落地**：稿是"卡外标题行 + 通栏卡 + 卡内平铺行带底分隔线"，改前是"带内边距的卡里塞标题 + 每行刷沉底药丸"。逐部位对照见 §6.1。
6. **【低】I6 · 三处行高写成定高，把内容切掉** —— **P6.2b 已落地**：系统活动行 `height: 28`（两行文字被切下沿）、登录行 `height: 44/56`（异常徽章那第三行被切）。稿一律写 `min-height`。详见 §6.2。

## 3. 设计稿该改（9 条模块 + 4 条全站口径，按严重度排序）

1. **【中】S1 · 侧栏 footer 全站画错**（实机容量行+带边框设置按钮，全站 S1）：06 稿沿用 01–06 错误画法，应在 tokens/screen 层补侧栏 footer 组件，七张稿一起换。
2. **【中】S10 · 06 主屏 artboard 1 系统级行与"系统级库读不到"警示条自相矛盾**：既画"系统级库读不到"警示条、又画"屏幕录制·系统级"行（Example Recorder），正是本项目红线禁止的"读不到也列系统级行"假通过。实现 `partial` 档已正确过滤掉系统级行。**改法**：删掉该行（保留警示条），或删掉警示条（改为 `.loaded` 全可读态）——二者只能留一。
3. **【中】S12 · 设计稿缺「系统活动」卡**：实现按产品规划文档 §4.5"最近活动"落地了诚实版「系统活动」卡，但 06-guardian.html 未补。建议设计稿加该区块并明确范围（不编进程名、无「阻止」按钮、空态文案）。
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

以下状态只在代码里读到分支，**本节写于 P3 无头审计**（当时环境不允许运行/截图）。P6.2b 已把其中 **1、2、3、4、6 五项实拍补齐**（`docs/verification/p62b-fidelity/`，见 §6.4），仍只有第 5 项（系统活动卡）没拍——钩子 `MM_GUARDIAN_ACTIVITY_FIXTURE` 后来已落地，本轮未用它出片。

| # | 未验证项 | 为什么验不了 | 需要什么才能验 |
| --- | --- | --- | --- |
| 1 | 占用四档逐态真机渲染（inUse/idle/combo/conflict/absent） | 每设备仅一态，需分屏 fixture；本环境不跑 App | `MM_GUARDIAN_FIXTURE` 分两次注入 + 按 pid 抓窗截图 |
| 2 | TCC 四档逐态真机排版（unreadable/emptyRead/partial/loaded） | 同上，且本机两库真打不开，`.loaded`/`.partial`/`.emptyRead` 只有夹具值 | `MM_TCC_FIXTURE` 四档 + 真机截图 |
| 3 | 登录项四态真机排版（rows/empty/indeterminate/scanerror） | 本机 17 项只有 plistNotLoaded 一种自然出现 | `MM_GUARDIAN_LOGIN_FIXTURE` 四档 + 真机截图 |
| 4 | 首帧骨架（hold）真机形态 | 首帧抢拍不到，靠 `MM_GUARDIAN_LOAD=hold` 定格 | 钩子 + 抓窗 |
| 5 | **系统活动卡空态 / 填充态** | **该卡无任何夹具钩子**，且 `ActivityScanner` 跑 `log show`/读敏感目录，无头不可控 | **需新增 `MM_GUARDIAN_ACTIVITY_FIXTURE`（见 §5 G1）** |
| 6 | 所有像素项（行高 44/56、环 34pt、卡片底 underPage、侧栏 220/标题栏 52） | 无实机抓取 | 按 pid 抓窗 + CoreGraphics 取色（同 monitor §0 流程） |

**已验证的部分**（结构/语义，来自代码+HTML+tokens 逐字比对，非像素）：页头标题/副标题/刷新；占用四档文案与 tint 规则；TCC 四档状态机分离与红线边界（§1.3 重点）；auth_value 映射与"未知值"；登录项三类异常徽章+双脚注；系统活动卡为实现独有（设计稿无）。

### 4.1 可注入档位映射（四个钩子逐项对照设计稿状态）

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
| **系统活动卡·空态/填充态** | **无钩子** | **见 §5 G1** |

## 5. 提请协调者

1. **【重点·核对结论】"授权表读不到 ≠ 未授权"边界：设计与实现均守住，PASS。** 实现在 `TCCProbe`/`TCCViewer`/`tccCard` 把"读不到"(`.unreadable`，不画列表) 与"查到 0 行"(`.emptyRead`，明确"查到了没有") 分成两个独立 UI 态，且 `.partial` 只列读到的库；设计稿 06c 也用两张独立卡片表达。唯一瑕疵是 06 主屏 artboard 1 内"系统级库读不到"警示条旁又画了系统级行（S10，设计稿自相矛盾，实现不会这么画），请协调者让设计稿修掉该自相矛盾。
2. **【已落实·已出片】系统活动卡夹具钩子（G1）**：`MM_GUARDIAN_ACTIVITY_FIXTURE=empty|rows` 已在 `MMGuardian.swift:461` 落地（合成条目标"夹具值"），本审计提出的"该卡无钩子、无法无头核对"已不成立；`rows` 档明暗两档各一张，见 §6.6.3（要压矮上面两张卡才进得了画面，`empty` 档仍未单独出片）。
3. **【低】活动卡读敏感目录口径（G2）**：`ActivityScanner.scanRecentEvents` 读 `~/.ssh`/`~/.gnupg`/`~/Library/Keychains` 最近访问时间并展示为"最近访问: X"——守护模块自身把敏感目录访问时间摆上界面，可能自我矛盾，且 `readError` 失败被静默跳过。请产品/协调者确认该卡范围（是否应只报"最近改动"而非"最近访问"，以及失败是否要明示）。
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
| `07-guardian-activity-rows.png` | `MM_WINDOW_SIZE=1100x1000` + `MM_TCC_FIXTURE=rows` + `MM_GUARDIAN_LOGIN_FIXTURE=empty` + `MM_GUARDIAN_ACTIVITY_FIXTURE=rows`，等 25s | 第 4 张卡（实现独有）；**同屏 TCC/登录项两卡是压矮用的夹具态，不作依据**（§6.6.3） |
| `08-guardian-login-indeterminate.png` | `MM_WINDOW_SIZE=1100x1000` + `MM_TCC_FIXTURE=rows` + `MM_GUARDIAN_LOGIN_FIXTURE=indeterminate` | "本轮未核对"徽章 + 脚注压在卡内分隔线下 |

**明暗两套**：`docs/verification/p62b-fidelity/` 是浅色，`docs/verification/p62c-dark/` 是同一八档的深色，
逐张同注入、只差 `MM_APPEARANCE`。§6.6.2 的分隔线对比度就是在同名的一对上量的。

### 6.5 这一轮**没有**核对的（不写"应该没问题"）

> 下面 1/3/4/5 四条由紧随其后的 P6.2c 关掉，结论在 §6.6；只有第 2 条（侧栏拖到两端）还开着。

1. ~~**深色档**~~：P6.2b 六张全是 `MM_APPEARANCE=light`，去药丸后暗档的行对比度没量过 → §6.6.2 量了。
2. **侧栏拖到两端**：只量了新的起点 220，`max:280` 那一端与"用户拖窄到 220 以下"的边界没拍。
3. ~~**系统活动卡**~~：钩子已存在但本轮没出片 → §6.6.3 出了 `rows` 档（明暗各一）。
4. ~~**登录项 `indeterminate`**~~：本轮只拍了 `rows` → §6.6.3 补了 `indeterminate`；
   **`scanerror` 一档仍未拍**（它只多一条脚注，要再压一次版面）。
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
  修法：窗口拉高到 `MM_WINDOW_SIZE=1100x1000`（屏 1920×1080pt，再高会被裁），
  并把上面两张卡换成矮夹具态（`MM_TCC_FIXTURE=rows`、07 另加 `MM_GUARDIAN_LOGIN_FIXTURE=empty`）。
  **代价写在脚本里**：这两张照上的 TCC 行与"登录项为空"都不是本机状态，它们只负责把要拍的卡顶进画面。
- **夹具落地比真扫描慢**：07 第一次拍到的是活动卡**空态**——`loadActivity()` 的夹具分支
  先真跑一次 `ActivityScanner.scan()`（含 `log show` 子进程，秒级）再顶替展示数据，
  8 秒等待截在了覆盖之前。这一档的等待改成 25 秒，原因写在 `Scripts/p62b-capture.sh` 的 07 注释里。
  这不是保守值而是这条分支的最低要求：**凡是"先真跑再顶替"的夹具，等待必须覆盖真扫描**。

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
2. **登录项 `scanerror` 档**（只多一条脚注，未再压一次版面）。
3. **活动卡 `empty` 档**：07 拍的是 `rows`，空态那一行在通栏卡里的留白没单独出片。
4. **稿 06 的 S 系列**（S1–S4 全站 token 漂移、S10 警示条旁多画系统级行）仍归协调层，本轮没动设计稿。

