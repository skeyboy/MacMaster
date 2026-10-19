# 应用本体有没有风险档（P51a 审计，2026-10-16）

> 缘起：`docs/analysis/uninstally-adoption.md` §6 末尾那条「还没做的」把两件事写在同一句里——
> §2 的 `.component` 风险档与 §3 的外接卷 `caution` 分档，「两条同撞在"应用本体有没有风险档"那一个决定上，进设计稿队列」。
> 本文把这个决定拆开：先现读"档"在我们这里到底长在哪一层，再逐条给建议与代价。
> **本轮只审计，代码一行未动**；下面所有 `文件:行号` 都是本轮（P51a）对着磁盘现读出来的。
>
> **P52b（同日）已按 §4 建议 1 动手，落地账见 §9。** 本文里"今天/现在"说的都是动手前那件事：
> §0 第 1 条与 §2.2 描述的本体层形态已被改动，那两节指向两个改动文件的行号在 P52b 逐条按内容重指过
> （`ResidualScanner` / `ResidualCollector` / `Risk` / `DeletionGuard` / `FileTrashService` / `AppScanner` /
> `AppFolderWatcher` 七个文件一字未动，它们的行号仍是 P51a 的读数且仍然有效）；
> §4–§6 的建议、代价与待量项保持原样，只在被落地改变的那几句后面标了「P52b」。
>
> **P53（2026-10-18）只补量，代码一行未动**：§6 第三条欠的那张跨卷实拍已经拍出来，
> 三条读数、五张照片与判据在 §10；§4 建议 2 的合同句跟着按读数改过（那里原来写着"本轮未实拍"）。

## 0. 结论先行

1. **本体这一层在 P51a 那一轮没有任何档位，而且不是"少见场景才成立"**：卸载页把 45 条应用全摆出来，其中 4 条是
   `com.apple.*`（Safari、TestFlight、Transporter、Xcode），详情面板底部那两个卸载按钮对它们**照样是 enabled 的**
   （`MMUninstaller.swift:1903-1912`、确认面板内 `:771-781` 都没有 `.disabled`）。
   `isSystemOwned` 改变的只有两件事：**不扫残留**（`UninstallerModel.swift:384-388`）与**一枚徽章**
   （`MMUninstaller.swift:1699-1701`、`:1875-1883`），它不是"能不能删"的判据。
   **P52b 已改**：那两个按钮现在整块长在 `if app.bodyDeletable` 里，只读档换成一块只读说明
   （`MMUninstaller.swift:1914-1929`）；判据、三处入口与实拍见 §9。
2. **`MMRisk` 的三档搬不到本体上，缺的不是字段是机制**：caution 在本体的载体上没有落点
   （它的机制是"默认不勾选"，`Risk.swift:7-8` 的合同 + `:39`，而本体没有勾选框）；
   **只有 `readOnly` 那一档在本体上有天然落点**——`allowsDeletion` = "不给删除入口"（`Risk.swift:41`），
   这一句对"整个应用"完全成立，只是从来没被接到本体上。
3. 因此建议把决定拆成三条，代价与依赖各不相同：**建议 1** 系统应用本体转 `readOnly`（S，不依赖设计稿）；
   **建议 2** 外接卷本体保持可删但强制带警告（S–M，需要一枚 chip 与一句文案）；
   **建议 3** `.component` 那片**不等于**"本体档"——它真正的缺口是残留清单没有音频插件根（S–M，不需要新概念），
   只有"把插件当独立条目卸载"那一半才需要本体层的新形态（M，本机零样本，全靠夹具）。
4. 一句话把 P46 那轮的判断改精确：§3 当年落不下"caution 起步"，**不是因为要先引入一个枚举字段，
   而是因为"本体"这一层的风险只能用两种表达——给不给删除入口、动手前必须读哪一句**。
   这两种表达界面上都已经有了（`allowsDeletion` 决定的勾选框、`cautionNotice` 那个橙色块 `MMUninstaller.swift:790-802`），
   只是没有一个作用在本体上。

## 1. 本机实测（每条都是本轮现读，命令见 §7）

| 量什么 | 读数 |
|---|---|
| `/Applications` 里以 `.app` 结尾的条目 | **45** 条（与 P49 照片 02 里页脚那句「45 个应用」对得上） |
| 其中 `com.apple.*` | **4** 条：`Safari.app`=`com.apple.Safari`、`TestFlight.app`=`com.apple.TestFlight`、`Transporter.app`=`com.apple.TransporterApp`、`Xcode.app`=`com.apple.dt.Xcode` |
| `Xcode.app` 体积 | `du -sh` = **3.6G**（本轮现读，属主 `lee:staff`） |
| 四条里哪条不是真目录 | `Safari.app` 是**符号链接**，指向 `../System/Cryptexes/App/System/Applications/Safari.app`，flags `restricted,hidden`；另三条是数据卷上的真目录 |
| `/Applications/Utilities` | 存在，**0 项**（§3 当年那句"本机确实存在"是存在性判断，本轮补上"里面是空的"） |
| `~/Applications` | **不存在**（`AppScanner` 靠 `contentsOfDirectory` 抛错来跳过，界面上不会有一条"扫不到"的谎） |
| `/Volumes` | 2 项：`Macintosh HD`、`Recovery`——本机没有第二块可挂载的非启动卷，外接卷那一条只能靠 `Scripts/p49-external-volume-fixture.sh` 造的镜像卷 |
| 音频插件根（Uninstally 那 9 条：系统域 5 + 用户域 4） | **5 条存在、4 条不存在；存在的 5 条全部 0 项** |

最后那一行是本文件最扫兴也最要紧的一格：**这台机器上一个音频插件也没有**。
所以 §2 那一片（`.component` / vst / vst3 / aaxplugin / clap）任何验收都只能是夹具档，
与 Steam 那一族同型（判据写在 `docs/analysis/uninstaller-steam-launcher.md` §1「本机实测：没有 Steam，所以全族靠夹具」）。
全仓现读只有一处提到 Plug-Ins：`ResidualScanner.swift:267` 的 `"Internet Plug-Ins"`，
那是"Library 根下探允许的子目录名"，与浏览器插件同名不同事——**残留清单里没有任何音频插件根**。

## 2. "档"今天长在哪一层（现读）

### 2.1 残留层：三档齐全，两条机制都能跑

- 载体：`ResidualItem.risk`（`ResidualScanner.swift:154`），一条一项。
- 定档：类别默认 `ResidualCategory.defaultRisk`（`:97-105`，13 个类别分两档，`.safe` 六个 / `.caution` 七个），
  再由 `ResidualCollector.resolvedRisk`（`ResidualCollector.swift:199-203`）跑一条**降级**：
  当前用户删不掉的一律转 `.readOnly`（判据 `isDeletableByCurrentUser`，`:206-214`：查父目录 `access(W_OK)` 加 `UF_IMMUTABLE`）。
- 机制一：默认勾选只来自 `.safe`（`UninstallerModel.swift:96-98`，合同句在 `:95`）。
- 机制二：不给删除入口的是 `.readOnly`（`:101-103`；执行处与行内勾选框各挡一次，`:474`、`MMUninstaller.swift:1290`、`:1969`）。
- 版式：按档分组，组序 safe → caution → readOnly（`ResidualScanner.swift:383-384`），
  每组一枚 `MMBadge(risk:)` + 一句 `groupNote`（`MMUninstaller.swift:1935-1945`），
  页脚那枚「N 项默认不勾选」是同一档的另一处表达（`:1859`）。

**这一层没有缺口。** 上一轮的插件残留之所以还没做，缺的从来不是"档"。
P52b 也没动这一层：上面那几个行号只是随同文件插入偏移，改完之后逐条按内容重读过，仍然指向同一件事。

### 2.2 本体层：没有档，也没有档的载体

- 数据结构：`UninstallCandidate`（`UninstallerModel.swift:8-36`）字段读满是 `path / bundleID / version / size / residuals / isSystemOwned / provenance / steamLauncher`——**没有 `risk`**。
  **P52b 补的是两态判定，不是档**：`bodyDeletable`（`UninstallerModel.swift:66-74`，= `isSystemOwned == false`），
  上面那串字段名是落地前的读数；为什么不叫 `risk`、为什么不用 `.caution`，就是 §3 与 §4 建议 4 那两段，代码注释里也引了回来。
- 勾选模型只作用在残留上：`deletionPaths(appPath:items:selectedIDs:)`（`:112-118`）返回的是
  `[appPath] + 勾选残留的互不嵌套根`，**本体那一条是无条件拼进去的**；
  两个入口 `uninstallAppWithSelection`（`:508-516`）与 `uninstallAppOnly`（`:519-525`）都走它。
  **P52b 已改这三处**：签名成 `deletionPaths(appPath:bodyDeletable:items:selectedIDs:)`，本体那一条要判定为真才进列表，
  两个入口各加一条 `guard app.bodyDeletable`（`:512`、`:523`）——`uninstallAppOnly` 那条尤其必要，
  因为 `MM_UNINSTALL_SELF_ECHO` 那条夹具路径根本不经过界面上的按钮。
- 界面上本体那一行（`MMUninstaller.swift:1641-1706`）有四样"看着像档位"的东西，全部是提示，
  **没有一样改变可删性**：
  ① `sourceChip`（判定 `:1359-1365`，只有 brew 两档占这一格，注释 `:1356-1358` 写明了理由）；
  ② `runningChip` / `runningWarning`（`:1482`、`:1551`，P31a 那句"只提示不代杀"）；
  ③ `steamLauncherChip`（`:1584`）；
  ④ `isSystemOwned` 那枚「系统应用」徽章（`:1699-1701`）。
  确认面板同样只有两枚橙色提醒（`sourceWarning` `:1451` 的文案、`runningNotice`），
  键值六行是「应用 / 来源 / 包名 / 本体 / 残留 / 合计」（`:727-735`）——**「本体」那一格只报体积，不报风险**。
  **P52b 一句没改这四样提示**：它们仍然只是提示；改的只有删除入口给不给，见 §9。

### 2.3 真正拦得住本体的那条闸：它按位置判，不按身份判

正向闸的根清单来自 `deletionRoots(for:)`（`UninstallerModel.swift:536-539`）= 残留清单的 Library 根 + 应用目录，
执行处两遍口径要求**字面与 `realpath` 之后都在根内**（`DeletionGuard.swift:115-126`）。于是本轮那 4 条 `com.apple.*`：

- `Safari.app`：字面 `/Applications/Safari.app` 在根内，解析后是 `/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app`
  → 正向闸拒（`:121-123`），黑名单也拒（`systemRoots` 含 `/System`，`:25-33`、`:134-136`）。**两条都拒，删不掉。**
  〔P52b 现读改判这一格的**路径写法**：`ls -ld` 看到的链接目标是 `../System/Cryptexes/App/System/Applications/Safari.app`，
  而 `realpath` 落到的最终位置是上面那条 Preboot 下的路径（`/System/Cryptexes/App` 自己也是一层链接）。
  P51a 那轮写的是前者，两个都不是允许根里的成员，所以那一格的**结论没变**，变的是抄下来的那条字符串。〕
- `Xcode.app` / `TestFlight.app` / `Transporter.app`：字面与解析后都在 `/Applications` 之内（P52b 用 `realpath` 逐条复量过，
  三条解析后都等于自身，没有逃出 `/Applications`），黑名单里没有 `/Applications`
  → **闸门放行**。它们当时能不能真删成取决于运行时权限（见 §6，本轮没量），
  但"卸载页把 Apple 提供的应用当成一个正经卸载候选、并且不给任何一句风险话"这件事与权限无关。

**这里要写清一句避免误读**：Safari 那条不是"我们设计了系统应用保护"，是符号链接恰好逃出了允许根。
按位置判的闸本来就答不了"这是谁的应用"——那正是 `uninstally-adoption.md` §1 那句"黑名单永远补不全"的镜像面：
**正向闸补的是"位置"，任何闸都不补"身份"**。

**P52b 没有改这一节说的任何一条判定**：`DeletionGuard` 与 `FileTrashService` 一字未动，那三条 `com.apple.*`
现在**仍然**过得了正向闸。落地的那一条站在闸的上游（判定 + 删除集合 + 三处入口），
所以这一族今天的行为是"路径压根不会被交给删除服务"，而不是"闸门把它们挡下来了"——
这两句话在界面上读起来一样，在往后要不要把它们移出允许根那一问上不是一个东西。
第三条证据（执行处复验）在 §9 第 4 项。

## 3. 为什么 §3 那句"外接卷按 caution 起步"当年落不了地

参考侧那份判定要的是「外接卷上的应用默认档要不要显示，按 `Risk.swift:41` `allowsDeletion` 给 caution 起步」
（原文在 `uninstally-adoption.md` 第 82 行），而 P46c 的落地记录写的是「"应用本体"这一层现在压根没有风险档
（档位在残留项上），要做就得先引入那个概念」（同文第 206-207 行）。把这两句对起来看，卡点很具体：

1. `.caution` 的两条机制在本体上都跑不起来：**默认不勾选**没有勾选框可默认，
   **不提供删除入口**是 `.readOnly` 那条而不是 caution 那条（`Risk.swift:39`、`:41`）。
   把一个只能表达"少动手"的枚举贴到一个只有"动 / 不动"两个状态的载体上，能贴上去的只有措辞。
2. 而 `Risk.swift:7-8` 的文件头合同写死了「语义固定，不可按页面重定义」。
   所以**不能**靠"在本体这一层让 caution 表示别的"绕过第 1 条——那正是那句话存在的理由（同文件 `:3-5` 给的是同一个道理）。
3. 外接卷这一条真正要传达的东西，跟"默认不勾选"不是一回事，是**「删掉之后撤回会失效」**。
   这一点有代码依据：撤回凭据是记录里的 `trashPath`（`FileTrashService.swift:205-217`），
   而"有没有得撤"按 `fileExists(trashPath)` 判（`:298`），`canUndo` 不成立时页面直接说
   「没有仍在废纸篓中、可以恢复的文件」（`:195-199`）。**盘一拔，那条凭据就自动降成一句实话**——
   代价不是删不掉，是删了撤不回，而这句话说在动手之前才有用。

结论：本体这一层需要的不是第三档，是**两个新表达**：
「给不给删除入口」（= 把现成的 `allowsDeletion` 接到本体）与
「动手前必须读哪一句」（= 把现成的 `cautionNotice` 那个橙色块接到本体的判定上）。
两者都不需要动 `MMRisk` 的语义合同，也就不需要重开 `:7-8` 那句话。

## 4. 决策单（四条，代价与依赖逐条标明）

### 建议 1 系统应用的本体转 `readOnly`（推荐先做，代价 S）

- 做什么：`UninstallCandidate` 增一个**本体级**的"可删性"判定（名字建议 `bodyDeletable`，别叫 `risk`，
  避免被读成三档），取值现在就能定：`isSystemOwned == false`；`readOnly` 时详情面板那两个按钮消失或禁用，
  改成一句「这是 Apple 提供的应用，MacMaster 不提供卸载入口」——**措辞沿用 `Risk.swift:34` 那句
  「仅供查看，MacMaster 不提供删除入口」的句式**，两处只读说同一种话。
- 为什么先做它：它修的是**已发版本上今天就踩得到的**一条能力谎话（页面把系统应用做成正经卸载候选），
  而它不引入任何新版式、不依赖 §2 那个还没定的插件形态，**也不依赖设计稿**——被删掉的是一个入口，不是新增一屏。
- 影响面：`UninstallerModel.swift`（判定 + 两个 uninstall 入口的 guard）、`MMUninstaller.swift`（按钮与只读文案）、
  新单测（`isSystemOwned` → 本体不进删除集合；否证：`deletionPaths` 收到系统应用时 `[appPath]` 那一条不出现）。
  现读**没有任何一条测试钉住当时的行为**（`grep -rn isSystemOwned Packages/MMUninstaller/Tests/` 零命中），
  所以这一改动不会撞旧合同，但也意味着**旧行为从来没被验收过**。
  **P52b 补正这一格少算的一处**：删除入口不是一个而是**三个**——详情面板底部那两个按钮、底部操作栏那两个按钮
  （`MMUninstaller.swift:515` 那一格 `trailing`），加上 `requestConfirmation`（`:702-705`）那道兜底 guard；
  建议文本里的"两个按钮"是 §2.2 那两句的口径，操作栏那一格在本轮动手前才被现读发现。
- 待量的前置：**已量，P52b**。`isDeletableByCurrentUser` 只看父目录（`ResidualCollector.swift:206-214`，那句注释的理由是"移到废纸篓要的是父目录的写权限"）
  这一条对**目录型 bundle 同样成立**，四条夹具单测钉在 `BodyDeletableProbeTests`，读数与"为什么不并进来"见 §9 第 2 项。

### 建议 2 外接卷上的应用：保持可删 + 强制一句警告（代价 S–M，要改稿）

- 做什么：本体行增一枚 chip「外接卷」（复用 `SourceChip` 那一族的版式与字号，`MMUninstaller.swift:1612-1627`；
  行内那一排的排布在 `:1657-1676`），
  确认面板在键值六行下方插一块 `cautionNotice`，文案要说清**撤回会怎样**而不是只说"这是外置盘"。
  合同句（三条读数 P53 已实拍，见 §10；原来那句括号里的"本轮未实拍"就是这么来的）：
  「这条应用装在外接卷上（挂载点 <该卷挂载点>），移到废纸篓后它落在那块卷自己的 `.Trashes` 里，不在你的废纸篓里；
  拔掉这块盘，「最近操作」里那一行就撤不回来，「撤回」按钮跟着消失，把盘重新挂上才回来」。
  **P54 改判（稿面那轮）**：这一句原来在"撤不回来"后面钉着徽章字面「会显示成「废纸篓已清空」」，
  那是把**另一屏的措辞**写进了本屏的合同——那一格属 01 系与 `fidelity-shell.md` 的账，
  本轮建议把它改判成「盘已取下」（§10 第 2 项那四个字是假话那条），照原写法那条一改这句就得跟着改。**P55 补**：那一格已在稿面改判落地，而且判据是实测的（同一支探针在挂载／拔盘两档各问一遍，读数 `docs/verification/p55-undo-badge-criterion/00-criterion-reading.log`）；本屏这句合同句仍不引用徽标字面，所以两屏各自独立，改判不回头动这一句。
  现在这句只说事实（撤不回来、按钮消失、挂回来才恢复），不引用字面；稿面已按这一版落在
  `docs/design-system/screens/mmuninstaller/03h-uninstaller-external-volume.html`（画板 2 与画板 4 的三档文案表）。
  **这一句里不许出现的东西**：残留那一半。本轮台账那条 `moved=1` 只有本体一项，残留压根没进删除集合。
  它在磁盘上确实与本体同卷（P53 当场 `ls` 过：卷根那条在、真 home 同名那条不存在），
  但"删它落到哪"仍然没量过，所以同卷也只是位置读数不是落点读数（§10 第 4 项）。
- 判据从哪来：`AppScanner.applicationDirectories(home:volumePaths:directoryExists:)`（`AppScanner.swift:43-48`）
  已经把"每条候选卷一项"和"三条固定"分开写了，本体只需带上"我来自哪一组"——
  今天这个信息在 `DiscoveredApp`（`:10-20`）里**丢了**，只有 `path`，所以这一片的最小改动是给它补一个来源标记，
  而不是在 UI 里反向解析路径前缀（`/Volumes` 字面量散进 UI 是另一种漏）。
- 为什么不是 `readOnly`：外接卷上装的正是用户自己装的应用，一刀切不给删就把 P49 那一整条能力废了；
  代价不对称这件事要说，但要说的是"撤不回"这条真的不对称，不是"这是外置盘"。
- 需要设计稿：是。chip 位与那句警告各一处，稿面在 03 系（列表行 + 确认面板），
  稿子改动要走 `docs/design-system/screens/mmuninstaller/` 与 `fidelity-uninstaller.md` 的对照，不能只改代码。
  **P54 已出稿**：`03h-uninstaller-external-volume.html` 五块画板（列表行 + 详情面板 / 确认面板那块 notice 与两块叠起 /
  概览那一行的三态 / 三档文案合同表 / 后端配合清单），回写在 `fidelity-uninstaller.md` §18。
  稿面那一轮量出来一条**实现前就得知道的**结论：268pt 那一列第二行可用 138px，两枚 chip 占 70~76、
  「 · 大小」占 ~40，留给版本号只剩 4.21 / 9.93px（要 18 / 24px）——**挤不下是量出来的结论，不是待观察项**，
  所以稿定的让步顺序是 **chip ＞ 大小 ＞ 版本号**，两枚 chip 并存时版本号直接不画（详情面板那一行一直在）。
  本轮**没有实机对应物**：代码一行未动（落地要单独授权），所以 §18 不做稿↔实机对照，只登记稿面决定与缺口。

### 建议 3 `.component` 那一片拆成两半，先做不需要本体档的那一半（代价 S–M / M）

- **3-A 插件作为残留根**（推荐先做，S–M）：卸载一个音频类应用时，它装在
  `/Library/Audio/Plug-Ins/Components` 等位置的名下条目**现在是漏的**——`ResidualCatalog` 里没有这些根
  （全仓只有 `ResidualScanner.swift:267` 那个同名的浏览器插件目录名）。
  这一片走的是**残留层**，三档、默认不勾选、只读降级、按档分组全都能直接复用（§2.1），
  不需要本文前面那个"本体档"的决定。要新写的只有：类别（一档 `audioPlugin` 或复用 `.applicationSupport`，
  按 `Risk.swift:3-5` 的"语义固定"来定，倾向前者）、`ResidualCatalog` 增根（逐条 `fileExists`，与 Uninstally 同法），
  以及一条别踩的线：`/Library/Extensions` 仍在红线里（`ResidualScanner.swift:184-187`），
  `.component` 只在 `Audio/Plug-Ins/Components` 这一条路径下收，**不做全域**。
- **3-B 插件作为可独立卸载的条目**（M，本机零样本）：这才撞上"本体档"，
  而且撞的不止一档——列表要分区（`uninstally-adoption.md` 第 71 行已经判定"插件 bundle 与 `.app` 分开成两类条目"）、
  监听与列举必须同源（`AppFolderWatcher.swift:111-115` 那条不变量；后缀集合一旦只喂扫描侧就会造出
  "列表里看得见、装卸事件不报"的第四种不一致）、风险档要重开（内核扩展家族的 `.component` 不该和缓存同级）。
  本机一个插件也没有（§1），所以这一半的每一分进展都得靠夹具目录拍出来，
  建议排在建议 1、建议 2、3-A 之后，且**先出设计稿**（哪一屏、哪一类清单、详情面板给不给「来源」那一格——
  这三问 P46 那轮已经问过，本轮仍然没有答案）。

### 建议 4 明确不做：不把 `.caution` 接到本体上

理由是 §3 第 1、2 条：`.caution` 在载体上没有机制，硬接等于按页面重定义枚举，撞 `Risk.swift:7-8` 那句合同。
如果将来确实要第三态，正确做法是给本体那一层写**自己的**两态判定（建议 1 的 `bodyDeletable`）
加一个"必须读一句警告"的字段，而不是让 `MMRisk` 变成双语义。
这一条写成"不做"，是为了让下一轮不必再把同一个问题想一遍。

## 5. 如果这三条要落地，界面上一共新增长什么样（供设计稿用）

1. 本体行的 chip 位（第二行，`SourceChip` 同族，`MMUninstaller.swift:1657-1676`）：新增「外接卷」一枚。
   这一行今天已经有四样东西抢宽度（运行中 / brew / 启动器 / 版本号 + 体积），
   P26 那一族截断教训在这里直接适用：**新增一枚要同时定"哪一枚让步"**，不能只加不减。
   **P54 已定（03h 画板 1）**：让步顺序 chip ＞ 大小 ＞ 版本号，两枚 chip 并存时版本号不画；
   稿面量出的余量见 §4 建议 2 那一段（138px 可用 / 版本只剩 4.21 与 9.93px）。
   中性色那一档（`--c-neutral-soft` + 次级文字，即 `.badge.readonly` 那一档）也是这一轮定的——
   橙已经是"这件事有代价"的专用色（运行中、疑似 brew 都占它）。
2. 系统应用的本体：**没有**删除按钮，详情面板底部换成一句只读说明；列表行的「系统应用」徽章保留。
   这里要定的事是「残留」那一节怎么措辞——落地前 `MMUninstaller.swift:1875-1883` 那句"删除不会回收空间"
   其实说了两件不同的事，改成本体只读之后，它得能说清"不扫"和"不删"是两个决定。
   **P52b 已落这一条**：那一节现在只说"不扫"（「…它的容器与偏好由系统管理，清掉也不会回收空间」，
   `MMUninstaller.swift:1878`），"不删"由只读说明那块说（`:1914-1929`），标题也跟着分成两话
   （`残留 · 不会修改` / `将一并移除的残留`，`:1857`）。稿面（03 系）没动，账记在
   `docs/analysis/fidelity-uninstaller.md` 的 P52 那一节。
3. 确认面板的警告块：复用 `cautionNotice`（`:790-802`），与 `sourceWarning` / `runningNotice` 同一版式——
   这三块在同一屏里叠起来时**谁在上、要不要合并成一块**，是稿子要画的第一件事（`:740-746` 现在只允许两块）。
   **P52b 没动这一条**：建议 1 走的是"收起入口"而不是"加一句警告"，本体那一层的"必须读哪一句"仍属建议 2。
   **P54 已定（03h 画板 2）**：三块叠起时**不合并**（三句主语各说一事，合并要在同一句里换三个主语），
   顺序按补救代价从重到轻 **外接卷 → 运行中 → brew**（今天 `:740-746` 是来源在前、运行在后，这一轮要重排）；
   面板宽 420pt 不变，第三块加进来会不会顶到窗口下沿**稿面没量**，落地那轮实拍。
4. 建议 3-A 的插件残留行：走现成的按档分组版式，零新版式；只有类别名与 `note` 那句"为什么算它"要新写
   （对照 `ResidualCategory.note` 那张表，`ResidualScanner.swift:108-123`）。

## 6. 本轮没测的（如实记）

- **删过东西了，但不是系统应用**：P51a 写这一条时"全部结论来自读代码与读目录，没运行过一次卸载动作，也没有照片"，
  这句到 P53 不再成立——那一轮在跨卷夹具上真删了一次应用，`FileManager.trashItem` 成功、落点与照片见 §10。
  仍然成立的是它的后半句：**"系统应用当时能被删"到今天还是只到"闸门不拦、按钮可点"为止**，
  没有对哪一条 `com.apple.*` 按过一次删除（P52b 落的正是"不给入口"，之后这一量连入口都没了，见 §9 第 3 项末尾）。
  所以"删得掉/删不掉"分成了两格：**外接卷上的普通应用**那一格已经量过（§10），**系统应用本体**那一格仍然只有代码依据。
- **本轮的权限读数是脏的**：`test -w /Applications/Xcode.app` 这一类 `access(W_OK)` 读数来自
  Qoder 代理的受限 shell（只能写工作区与 `/tmp`），**它测的不是 MacMaster 运行时的判据**，
  所以本文不引它作为"删得掉/删不掉"的证据。要量这一条得在应用自己那一侧走夹具（`MM_*` 钩子 + 假 home，
  机制现成：`MMUninstaller.swift:258-265`）。
  **P52b 照这句话量的**：`BodyDeletableProbeTests` 跑在 `swift test` 里、夹具在 `NSTemporaryDirectory()` 下，
  截图走 `MM_*` 钩子 + 假 Applications 根（`Scripts/p52-system-app-fixture.sh`），没有一处引用受限 shell 的 `W_OK`。
- 跨卷废纸篓的真实落点（落在那块卷自己的 `.Trashes` 还是用户的 `~/.Trash`）与"拔盘后撤回长什么样"：
  **P53 已量，三条读数、五张照片与判据见 §10**。答案：落点是那块卷自己的 `.Trashes/<uid>/`，
  不是用户的 `~/.Trash`；拔盘之后「最近操作」那一行的「撤回」按钮换成「废纸篓已清空」徽标，重新挂上又变回按钮，
  全程没人倒过废纸篓。这一条原来写的是"只有代码依据、**没有实拍**"，而那句自我批评的对象
  （`uninstally-adoption.md` 第 216-218 行判 `noteFileSystemChanged` 不采纳时同一类错误）现在有了实拍可以对。
  **仍然没量的邻居**：勾选残留一起删时那一条台账里有几项、各自的落点分别在哪块卷上（本轮 `moved=1`，只有本体），
  以及拔掉盘之后真按一次撤回会拿到什么错误（本轮没有合成点击，只量到按钮消失；
  代码那侧 `FileTrashService.swift:195-199` 的 guard 会回一句「没有仍在废纸篓中、可以恢复的文件」，这仍是代码依据）。
- `isDeletableByCurrentUser` 对目录型 bundle 是否成立（§4 建议 1 那条待量前置）：**P52b 已量，成立、且同形**；
  四条读数与"为什么仍然没有把它并进 `bodyDeletable`"见 §9 第 2 项。
- 音频插件的价值大小：本机 0 样本（§1），**"重灾区"这句话目前只有参考项目那侧的依据**，我们这侧没有证据；
  3-A 值不值得做，取决于是否愿意靠夹具与真机用户反馈定，而不是靠本机读数。

## 7. 复现

```sh
# §1 那八行读数
ls -1 /Applications | grep '\.app$' > /tmp/p51-apps.txt && wc -l < /tmp/p51-apps.txt   # 45
n=0; while read -r e; do id=$(defaults read "/Applications/$e/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)
  case "$id" in com.apple.*) n=$((n+1)); echo "$e = $id";; esac
  done < /tmp/p51-apps.txt; echo "com.apple.* = $n"                                     # 4 条
ls -ldO /Applications/Safari.app                                  # 符号链接 + restricted,hidden
du -sh /Applications/Xcode.app                                    # 3.6G
ls -d /Applications/Utilities ~/Applications 2>&1                 # 前者存在、后者不存在
ls -1 /Volumes                                                    # Macintosh HD / Recovery
for d in /Library/Audio/Plug-Ins/{Components,VST,VST3,CLAP} \
         "/Library/Application Support/Avid/Audio/Plug-Ins" \
         ~/Library/Audio/Plug-Ins/{Components,VST,VST3,CLAP}; do
  [ -d "$d" ] && printf '%s\tEXISTS\t%s\n' "$d" "$(ls -1 "$d" | wc -l | tr -d ' ')" \
              || printf '%s\tABSENT\t-\n' "$d"; done              # 5 存在 / 4 不存在，存在的全 0
```

## 8. 收口账（2026-10-16，docs-only 一轮）

- **落点分四批**：审计本体落在 `c9e06da`（本文 §0–§7、`uninstally-adoption.md` 的三处行内指针——第 191、207、372 行，
  只在那三行里加字、没有加行——外加两份入库前的门禁 log）；这一节初稿落在 `24c1398`；
  归因那一轮与它带进来的五份 log 落在 `79cae53`；postcommit3 那份 log 与上面这段计数落在 `91eb28b`。
  源码与测试一个字节没动。
- **引用门禁十跑**（本树），归档在 `docs/verification/` 下 `p51-citations-` 开头那十个目录里：
  v2（本文入库后、加指针前）、final（加指针后）、postcommit（第一批提交后，`# repo: c9e06da` 不带 `-dirty`）、
  symfull（同一棵树、存疑明细放开到 400 行那一跑）、close / close2 / postcommit2 / close3（这一节写出、
  入库、把下面那处措辞改回散文之前之后各跑）、postcommit3（第二批提交后，`# repo: 79cae53`）、
  tail（第三节入库后那一跑，`# repo: 91eb28b`、index 1517，工作树干净）。
  第十一个目录 `p51-citations-baseline-9e15e18` 不是本树的跑，是基线那棵树的一跑，专给下一条对账用。
  **门（硬失败）与行号越界、整段空白、死符号四层十跑全为 0，退出码十跑全 0**；
  唯一「路径+行段」1104、命本仓库 966、命参考仓库 137、位置存疑 132 十跑相同；
  `docs scanned` 47 个真抽了 / 47 个入库 .md。
  **两处动过的数要写清，别读成"十跑逐字相同"**：条次 1472 → 中间三跑 **1473** → 最后三跑又是 1472，
  那一格是这一节自己造成又自己收回去的——初稿在下面的存疑说明里把同一个代码区间按"`路径:行段`"的形状又引了一遍，
  条次算重复引用、唯一数不算，改成散文说法后回到 1472；`# index:` 1507（本文入库前）→ 1509 → 1511 → 1516 → 1517
  （每提交一份 log 就 +1，这一段自己也是这样），
  P50 那一轮末尾留的预测「`git add` 之后下一轮读到的 index 是 1506」对上了（1506 + 本文 = 1507）。

- **行数守恒现读**：`release-readiness.md` 4870、`fidelity-disk.md` 1062、`uninstally-adoption.md` 374、
  `disk-volume-enumeration.md` 460、`hook-ledger.md` 514、`feature-roadmap.md` 1530，六格一字未动。
  本文不在守恒清单里（新建，且没有别的文档按行号引它）。
- **位置存疑从 133 走到 132：因已经归上了，方法是把两棵树的明细都放开跑一遍再 diff**。
  默认只列 40 行，差的那几行排在 cap 之后，光看已入库的 log 认不出是谁走的；所以做两件事：
  ① `P16_SYM_DETAIL=400` 在本树跑一跑，把全量 132 行清单入库 `docs/verification/p51-citations-symfull/audit.log`；
  ② 用 `git worktree add --detach /tmp/p51-baseline 9e15e18`（上一轮那棵树，本文还不存在）在同一支脚本上
  跑出 133 行的清单，逐行 diff 完立刻 `git worktree remove`。结果：**少 2 行、多 1 行**，两行都属同一个机制——
  这一层的计数是**每个代码区间一行**，"点名"哪些成员名取自扫描顺序里**第一条**撞上该区间的文档行，
  所以新增一篇文档能让既有区间的判定**换人**：`Risk.swift` 那三行的引用归属从 `uninstally-adoption.md` 第 72 行
  换成了本文第 154 行（仍然存疑，只是换了点名的人），`AppFolderWatcher.swift` 第 111 行起那五行的那一格则因为本文
  第 159 行同侧写的那两个名字对得上而**整条离开这一层**。基线那一跑的文件在
  `docs/verification/p51-citations-baseline-9e15e18/audit.log`，**只有存疑明细层用来对账**：
  那棵树里没有 .gitignore 排掉的参考仓库克隆，所以它自己报的 `命参考仓库 0`、`两头都不到 137`、`硬失败 137`
  与退出码 1 全是环境的产物，不是那一轮的门禁读数。
  下一轮不必再猜：同一条 `P16_SYM_DETAIL=400` 跑一遍，跟这份 132 行的清单 diff 就知道动了谁。
  本文自己在这 132 行里占 1 条（第 154 行把代码区间与同一行上的两个成员名写在了一起，锚点本身对得上，
  那是文件头"语义固定"的理由那三行），属这一层的正常噪声，不当门。
- **下一轮从这里接**（这一格在 P52b 之后重读过，原文照抄在下面第一条的引号里，只有状态变了）：
  建议 1 的实现要单独授权——**已授权并已落地，见 §9**（`S`，不依赖设计稿，是三条里唯一当时就动得着的）；
  建议 2 与建议 3-B 先出设计稿，且建议 2 动手前必须先把"跨卷落点 / 拔盘后撤回"那张实拍补出来（§6 第二条）——
  **这一张 P53 已补，见 §10**，合同句也跟着按读数定稿了（§4 建议 2 那一格）；
  建议 3-A 的前置是把 `isDeletableByCurrentUser` 在目录型 bundle 上的行为量出来——**这一条 P52b 顺手量了**（§9 第 2 项）。
  所以今天还欠的只剩一样：建议 2 / 3-B 的设计稿（建议 2 的前置实拍已经不再是欠项）；建议 3-A 已经**没有前置**了。

## 9. 建议 1 落地收口（P52b，2026-10-16）

授权口径两则，都是本轮开工前问定的：**先量前置再实现**（§4 建议 1 那条待量前置跑完才动代码），
**代码先落地、稿账记在 fidelity 文档**（03 系设计稿这轮一字未动，差额记在
`docs/analysis/fidelity-uninstaller.md` §17，与建议 2 的改稿捆在一起走）。

### 1. 落了什么：判定在上游，三处入口各拦一次

- 判定：`UninstallCandidate.bodyDeletable`（`UninstallerModel.swift:66-74`，两态、注释里写明为什么不叫 `risk`），
  取值就是 `isSystemOwned == false`，只由归属判定、不掺父目录写权限（理由见下面第 2 项）。
- 删除集合：`UninstallSelection.deletionPaths` 多了一个 `bodyDeletable` 形参（`UninstallerModel.swift:112-118`，
  默认 `true` 所以旧调用口径不变），`false` 时 `[appPath] + roots` 只剩 `roots` —— 本体那一格压根不进那串路径。
- 三处入口（§4 建议 1 那格补正过的"不是一个而是三个"）：
  详情面板两个按钮 `MMUninstaller.swift:1895`（`if app.bodyDeletable`，`else` 走 `:1914-1929` 那块只读说明）、
  底部操作栏两个按钮 `:515`（`if model.selectedApp?.bodyDeletable != false`）、
  `requestConfirmation` `:702-705` 那道 guard（它要单独拦，因为 `MM_UNINSTALL_CONFIRM_MODE` 那条自动开面板的
  夹具路径不经过按钮）。模型侧再加两道：`uninstallAppWithSelection` `UninstallerModel.swift:512`、
  `uninstallAppOnly` `:523`——后者是这一族唯一能拦住 `MM_UNINSTALL_SELF_ECHO` 那条同路的地方。
- 措辞沿用 `Risk.swift:34` 那句只读话的句式（`MMUninstaller.swift:1919`「这是 Apple 提供的应用，仅供查看，
  MacMaster 不提供删除入口。」+ 同一块里一枚 `MMBadge(risk: .readOnly)`），残留那一节的标题跟着分两话
  （`:1857`：`将一并移除的残留` / `残留 · 不会修改`）。
- **没动的**：`DeletionGuard`、`FileTrashService`、`MMRisk`、四类提示（`sourceWarning` / `runningNotice` /
  确认面板两枚橙色提醒 / 「本体」那一格只报体积）、03 系设计稿。

### 2. 前置量的读数：那把尺同形，但故意没并进来

`BodyDeletableProbeTests`（`Packages/MMUninstaller/Tests/MMUninstallerTests/BodyDeletableProbeTests.swift`，4 条）
跑在 `swift test` 里、夹具在 `NSTemporaryDirectory()` 下——所以 `access(W_OK)` 说的是真的，
不引 §6 第二条那种受限 shell 的脏读数。四条读数：

1. 父目录可写 ⇒ 目录型 bundle 判可删，**哪怕把 bundle 内部的 `Contents` 锁成只读**；
   同一把尺量 `Contents/Info.plist` 就判不可删。移的是顶层那一项、走 rename，子树权限不参与——
   `ResidualCollector.swift:206-214` 那句"要的是父目录的写权限"对目录同样成立。
2. 父目录不可写 ⇒ bundle 与普通文件同形降级，两条断言一起过。
3. `UF_IMMUTABLE` 挂在 bundle 目录本身上 ⇒ 判不可删，清掉标志要能回到可删（否则上一条测的是残留状态）。
4. 路径没有父目录（`/`）⇒ 判不可删，不被 `deletingLastPathComponent` 走到根时误判成可删。

**为什么不并进 `bodyDeletable`**：并进来这一屏的残留勾选会变成点不动的控件（父目录只读时连"清它的缓存"都按不动），
而"那一屏该长什么样"是建议 2 的稿面问题，不该由一次归属判定顺手定掉。
这一条写在 `UninstallerModel.swift:71-73` 的注释里，测试文件头也钉了一句。

### 3. 实拍：`docs/verification/p52-system-app/`，5 张 5 log，判据 8 ✓

脚本 `Scripts/p52-system-app-capture.sh`（270 行）+ 夹具 `Scripts/p52-system-app-fixture.sh`（38 行，两行应用只差包标识前缀：
`ApplePages` = `com.apple.FixturePages` / `PlainTool` = `com.example.PlainTool`，两边各放 8 B 名下残留——
系统应用那一档"连扫都不扫"这件事，只有夹具里真放着它名下的文件才拍得出来）。
钩子组合：`MM_UNINSTALL_CONFIRM_FIXTURE_HOME` + `MM_UNINSTALL_SELECT` + `MM_UNINSTALL_CONFIRM_MODE` +
`MM_APPEARANCE=light` + `MM_WINDOW_SIZE`。归因头五份都是 `# repo: d827d33-dirty`、
`# digest: tree=d827d33+638fe6c9 app=d827d33+638fe6c9`（照片与二进制同源那道门禁当场算的）。

判据一共 8 条，全过：**5 ✓ 点名**（每张 log 里都要有 `MM_UNINSTALL_SELECT=<app> 已点名到 …/Applications/<app>.app` 这一行，
缺一张就整族失败）+ **3 ✓ 像素**（`Scripts/p52-photo-diff.py`，脚本自己那套口径：
`ImageChops.difference` → 按通道取最大 → 直方图 → 数 `≥9/255` 的像素，内容区 = `x ≥ 218`）：

| 对照 | 判 | 全帧 | 内容区 | 最大幅度 | 这一格说明什么 |
| --- | --- | --- | --- | --- | --- |
| 01 ↔ 03 | `same` | 215 | **0** | 167 | 01 是"请求自动开确认面板"（`CONFIRM_MODE` 未给，默认 `appOnly`）、03 是"明确请求 none"。两帧内容区**逐像素相同** ⟹ 那道 guard 让面板一次也没弹出来。215 个像素全在侧栏（`Macintosh HD 4%`/`3%`、系统清理那一行的体积数在两次跑之间自己变了），不在页面里 |
| 02 ↔ 04 | `diff` | 1 295 221 | 1 078 429 | 217 | 同一个 `PlainTool`，只改 `CONFIRM_MODE`：默认档弹出确认面板、`none` 档不弹 ⟹ 这一族钩子是活的，01↔03 那个"相同"不是脚本没生效 |
| 01 ↔ 04 | `diff` | 66 815 | 66 596 | 218 | 两帧都没有面板，差别全在详情面板与底部操作栏：`ApplePages` 那块是只读说明，`PlainTool` 那侧是「将一并移除的残留」+ 两个删除按钮 + 操作栏两枚按钮 |

出片之后脚本还追一句 `# post-shot: 两行应用仍在磁盘` —— 这一族**没有任何删除动作**，
验的是入口给不给，不是删完之后（§6 第一条那句"没量到 `trashItem` 的真实成败"在**系统应用**那一档到今天仍然成立；
外接卷上那条普通应用的删除动作是 P53 量的，见 §10）。

人读（01 与 04 两张对着读）：01 的页头「应用卸载 / 2 个应用 · 合计 991 字节 · 大小已实测」、
列表两行（ApplePages 带「系统应用」徽章、PlainTool 带「1 项残留 8 字节」）、详情四卡里「残留大小 0 字节 / 残留项 0」、
标题「残留 · 不会修改」+ 那句「系统自带应用不提供残留扫描：它的容器与偏好由系统管理，清掉也不会回收空间。」、
只读卡「只读 · 这是 Apple 提供的应用，仅供查看，MacMaster 不提供删除入口。」、
底部操作栏只剩「已选 0 项残留 · 0 字节 / 未勾选项不会被修改」而**右侧两枚按钮整块不在**；
04 的同一位置是「卸载应用并移除勾选的残留」+「仅卸载应用，保留所有残留」两枚 + 操作栏「仅卸载应用」「移到废纸篓」，
「全选可删项」也在。两帧各带两条与本轮无关的横幅（`~/Applications 不在这台机器上`、`读不到废纸篓`），
那是本机没有完全磁盘访问的常态，不是这一族引入的。

### 4. 第三条证据：执行处那一层拦不住它们，从来没拦住过

`UninstallBodyReadOnlyTests.testThePositiveGateJudgesPositionNotOwnership`（第 5 条，纯字面判定、不碰盘）钉住三行读数：
卸载页允许根里应用目录那半是固定三条 `["/Applications", "/Applications/Utilities", "<home>/Applications"]`
（`AppScanner.swift:43-48`），`/Applications/Notes.app` **在根内**、`/System/Applications/Notes.app` 不在。
配套两条 `realpath` 实测（本轮现量，写进 §2.3 那两格）：`/Applications` 与
`/Applications/{Xcode,TestFlight,Transporter}.app` 解析后都等于自身 ⟹ 正向闸放行；
`/Applications/Safari.app` 是条链接，`realpath` 落到 `/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app`
⟹ 正向闸拒。执行处两遍口径里黑名单先跑、允许根那一遍才报 `OUT_OF_SCOPE`，两个动作各一份：
移入废纸篓 `FileTrashService.swift:96-101`、永久删除 `:150-155`，
所以 `/System/Applications/*` 那种路径拿到的是 `PROTECTED` 而不是 `OUT_OF_SCOPE`。

结论要说得跟§2.3 同一口径：**这一层按位置判，Apple 的应用在 `/Applications` 里就在闸内**，
P52b 之前没有任何一层拦住那三条，今天拦住它们的是上面那一层归属判定。
哪天有人把 `/Applications` 从允许根里挪走，这条测试会先响。

### 5. 账

- 测试：新增两份文件、**9 条**（`UninstallBodyReadOnlyTests` 5 + `BodyDeletableProbeTests` 4），
  全绿。全量九包与合计那一行以 `docs/verification/p52-tests/run-all-tests.log` 为准（本文不抄总数，
  规矩是 P50 那轮定的"活数与史账分家"；那一跑是 `d827d33-dirty`、指纹 `d827d33+638fe6c9`，
  与 P50 归档逐格 `diff` **只有 MMUninstaller 那一行不同**，其余八格逐字相同）。
- 引用门禁：`Scripts/p16-citation-audit.sh` 跑在本文与 `fidelity-uninstaller.md` 改完之后，
  归档 `docs/verification/p52-citations/audit.log`（222 行，`# repo: d827d33-dirty`、index 1518）。
  四个读数：**硬失败 0**、退出码 0、引用条次 **1490**、唯一「路径+行段」**1116**、位置存疑 **132**。
  与 P51a 尾跑那份（`docs/verification/p51-citations-tail/audit.log`，1472 / 1104 / 132 / 0）对差是
  **条次 +18、唯一 +12、存疑一字未动**——本轮确实往正文里新增了真引用（§9 那些锚点与 §17 的表格），
  所以这两个数上涨是应当的，而"存疑没涨"是本轮改锚点改对了的证据。**这一轮新增的引用不是零风险形状**：
  本文 §9 写的锚点带冒号，会被门禁逐条量；写"第 N 行/§N"那种裸写不进量尺面（口径见 §7.7）。
- **提交后的另一半**（补账笔，同 P47c/§1 那两次的「下一笔补」手法）：本批落在 `a1f7120`（父提交 `d827d33`，
  正是上面「归因」那条里预先写死的那一串，这次它对上了），提交后工作树干净，同一脚本再跑一遍，
  归档 `docs/verification/p52-citations-postcommit/audit.log`（同样 222 行）。那一跑的
  `# repo: a1f7120 branch=main` **不带 `-dirty`**、index **1536**（= 入库前的 1518 + 本批新增 18 个跟踪文件：
  2 条测试 + 4 份脚本 + 5 组照片与 log + 2 份归档），四个读数**硬失败 0 / 条次 1490 / 唯一 1116 / 位置存疑 132
  与入库前那一跑逐字相同**——入库这一步没挪动任何一处引用，涨引用那笔账是落地那一跑涨的（+18 / +12 / 0，见上一条）；
  下一轮读到 index 会是 **1537**，因为这份归档自己这时才进跟踪面。补账笔的散文改完后再跑一遍
  （`# repo: a1f7120-dirty`、index 仍是 1536），四个数第二次一字未动——本批新增的都是裸写形状，进不了量尺面。
  同轮现读 `mm_source_digest`：`d827d33+638fe6c9` → **`a1f7120+e3b0c442`**。后半换成空流前缀不是改动丢了，
  而是工作树再无 diff——这两串是**同一棵树的两种写法**（前者由未提交的 diff 带出内容，后者由 HEAD 带出）。
  所以 `docs/verification/p52-tests/run-all-tests.log` 抬头那条「这一串不是空流前缀，因此它带得出源文件内容」
  的判据只在提交前成立；提交后再拿指纹比日志，比的是"树等于 HEAD"，不是"内容相同"。
- 旧锚点重指：本轮改过的两份源码让本文里 24 对 `File.swift:NNN` 引用整体位移，
  用 `Scripts/p52-ref-verify.py` 按**逐行内容相等**一一对过（不是按位移量算），
  其中 23 对对得上、1 对（`:1862-1868`）因为那块自己长了两行而改成 `:1875-1883`。
  这一跑顺带抓出上一轮自己埋的一处错：本文第 12 行那条 `MMUninstaller.swift:1920-1929` 当时按 +33 位移算的，
  正确值是 +16，现读已改成 `:1903-1912`。
- **还欠**：03 系稿面（列表行「系统应用」那一行与详情面板只读卡）——记在 `fidelity-uninstaller.md` §17；
  建议 2 / 3-B 的设计稿。建议 2 的跨卷实拍**不再欠**（P53 补的，见 §10）。建议 3-A 无前置，随时可接。

## 10. 前置量：跨卷删除落点与拔盘后撤回（P53，2026-10-18）

这一节补的是 §6 第三条原来欠的那张实拍。**本轮代码一行未动**，产出的全部是夹具、脚本与照片；
它把 §4 建议 2 那句合同句从"写下来的一句没量过的话"变成有读数的话，仅此而已——落地仍要单独授权。

### 1. 三条读数

1. **落点在那块卷自己的 `.Trashes`，不是用户的 `~/.Trash`**。台账（`~/Library/Application Support/MacMaster/trash-history.json`）
   头一条那两行是当场读出来的：`originalPath=/private/tmp/mm-p53-mnt/Applications/AaaP53CrossVolume.app` →
   `trashPath=/private/tmp/mm-p53-mnt/.Trashes/501/AaaP53CrossVolume.app`，`size=8192`、`moved=1`、`failures=0`；
   主目录卷 `/dev/disk3s1` 与挂载卷 `/dev/disk13s1` 不同名 ⟹ 跨卷成立。落点目录 `ls -ldn` 给
   `drwxr-xr-x 3 501 20`、`du -sk` 给 8 KB，与台账那个 8192 对得上。
   机制那侧就是 `FileTrashService.swift:45` 那一句：落点由 `FileManager.trashItem(at:resultingItemURL:)` 自己定，
   我们只是把 `resultingItemURL` 写进台账——**所以"落在哪"从来不是我们的决定，是那块卷的决定**。
2. **拔盘之后那一行说"废纸篓已清空"，而谁也没倒过垃圾**。`canUndo`（`FileTrashService.swift:294-300`）
   只看 `fileExists(atPath: trashPath)`（`:298`），不看废纸篓有没有被倒空：盘一拔，那个路径读不到 ⟹
   `MainWindow.swift:679` 那枚「撤回」按钮换成 `:684` 的 `MMBadge("废纸篓已清空")`。
   照片 03（挂载中，按钮在）→ 04（拔盘，徽标）→ 05（重挂，按钮回来）三态同一行，`test -e` 那一句在
   `00-landing-reading.log` 里跟着翻两次面（真 → 假 → 真），与 `:298` 同口径。
   **徽标那四个字是假话**：它断言的是"垃圾被倒掉了"，实测发生的是"盘被拔掉了"。〔**P55 收口**：这一条的改判已经落成两面——判据由 `Scripts/p55-undo-badge-criterion.sh` 在同一支夹具的挂载／拔盘两档各跑一遍同一支探针量出来（`docs/verification/p55-undo-badge-criterion/00-criterion-reading.log`：挂上时枚举 15 条含落点那块卷、拔掉后 14 条且那条路径 `resourceValues` 直接抛错），稿面新起 `docs/design-system/screens/shell/01b-dashboard-undo-states.html`；源码 `MainWindow.swift:684` 那四个字**本轮没动**，记为 I16 等单独授权，账在 `fidelity-shell.md` §1.4 与 §6。〕
3. **卸载页自己会把那个落点印给用户看**。照片 02 的回声卡第二行是
   `/private/tmp/mm-p53-mnt/.Trashes/501/AaaP53CrossVolume.app · local.mmvolume.aaap53crossvolume.p53`，
   底部 toast「已卸载 1 项 8 KB ｜ 撤回 ｜ 打开废纸篓 ｜ 12s」——也就是说建议 2 那句警告要说的信息，
   有一半界面已经在说了，缺的是"这块盘拔掉之后会怎样"那一句。

### 2. 夹具与脚本（为什么挂载点在 `/tmp` 之下）

- `Scripts/p53-cross-volume-fixture.sh`（`create` / `mount` / `detach` / `probe` / `clean`）：
  卷造在 `/tmp/mm-p53-volume/MMVolumeP53.dmg`，**挂载点 `/tmp/mm-p53-mnt`（realpath `/private/tmp/mm-p53-mnt`）**。
  没有复用 P49 那支（它挂 `/Volumes/$VOL`）是因为 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 那道钩子
  （`UninstallFixtureHooks.canonicalHome`）只认 `/tmp` 之下的真实目录，而它先查前缀再 `realpath` 再查一次前缀——
  用符号链接把 `/Volumes/…` 引到 `/tmp` 下过不了第二道。**代价**：这一族量到的是"源文件在第二块卷上"这一条，
  路径字面不是 `/Volumes/…`（那一条归 P49）。`FileManager.trashItem` 决定落点看 URL 属于哪块卷，
  不看它挂在哪个目录名底下，所以落点这一族读数不受影响。
- `Scripts/p53-cross-volume-capture.sh`（477 行，五档：01/02 卸载页 + 03/04/05 概览同一张卡）：
  钩子组合 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` + `MM_UNINSTALL_SELECT` + `MM_UNINSTALL_CONFIRM_MODE=none` +
  `MM_UNINSTALL_SELF_ECHO=1`，`MM_APPEARANCE=light`，概览页 `MM_WINDOW_SIZE=1400x1100`。
  （这一族收口时又补了一笔：脚本里"产物不同源时怎么重建"那句提示的 scratch 目录名是从 P52 那支抄来的，
  照它跑会和上一族撞名——实跑用的是 `/tmp/mm-scratch-p53`。所以本批不止一个提交。）
- **这一族会往用户真实的删除历史台账里写一条**，躲不掉：原本想用 `HOME=/tmp/…` 把进程隔到假 home，
  实测**无效**——Foundation 在 `.userDomainMask` 这一路不认 `HOME`（`env HOME=… swift` 探出来仍是
  `NSHomeDirectory=/Users/lee`）。代价压成两条：跑前 `pgrep -x MacMaster` 有别的实例就整族不跑
  （台账是整文件 `.atomic` 覆写，`TrashHistoryStore.swift:38-50`，两个实例各写各的会互相盖掉），
  跑前备份 + 记 sha、跑完（含中途失败，走 EXIT trap）恢复并复算。本轮前后逐字相同：
  **sha `32184eb08adce992`、13 条、6991 字节**；跑的那两分钟里是 14 条 / 7307 字节。
  备份 `/tmp/mm-p53-ledger-backup.json` 里是用户删过的绝对路径，**只留 /tmp，不入库**。

### 3. 判据：`docs/verification/p53-cross-volume-trash/`，5 张 5 log + 2 份读数列

归因头五份都是 `# repo: f7bad50-dirty`、`# digest: tree=f7bad50+9a0d5ed8 app=f7bad50+9a0d5ed8`
（照片与二进制同源那道门禁当场算的；`-dirty` 是工作树里另有一族未提交的 QuickLook 改动，与本轮无关）。
判据 6 条全过：**2 ✓ 点名**（01/02 两张 log 各要有一行 `已点名到 /private/tmp/mm-p53-mnt/Applications/AaaP53CrossVolume.app`）+
**2 ✓ 落点翻面**（拔盘后 `test -e` 假、重挂后真）+ **2 ✓ 像素**（同一套口径：`≥9/255`、内容区 `x ≥ 218`）：

| 对照 | 判 | 内容区 | 最大幅度 | 这一格说明什么 |
| --- | --- | --- | --- | --- |
| 01 ↔ 02 | `diff` | 1 195 908 | 251 | 删除前列表里那一行在、两个删除入口在；删除后列表空、回声卡与 toast 出现 ⟹ 删除动作真走到了界面 |
| 03 ↔ 04 | `diff` | 37 651 | 216 | 同一张卡同一行：「撤回」按钮 → 「废纸篓已清空」徽标。**不要求"只有那一行变了"**——概览页是活数页 |

`03↔04` 这条像素判据只在"落点在这块卷上"那一支才成立；如果哪天量到落点是用户的 `~/.Trash`，
拔盘不会让那一行翻面，脚本会走 `else` 分支只记录不作判据（这一段写在脚本头部）。
`05`（重挂）与 `03` 不作像素对照：隔了一分钟，活数必然不同，那一档靠"落点又读得到 + 人眼读照片"两件事。
`00-family-run.log` 是整族 stdout 的归档（`… | tee` 那条），`00-landing-reading.log` 是落点、卷内 `.Trashes`
与拔/挂三次读数的归档。

### 4. 没量到的（下一轮别把这几句当已经量过的）

- **勾选残留一起删**那一档：本轮台账 `moved=1`，只有本体。照片 01 那一行
  「`~/Library/Caches/local.mmvolume.aaap53crossvolume.p53` · 9 字节」**读成"用户主目录"就错了**：那个 `~` 是
  `ResidualCollector.display(_:home:)`（`ResidualCollector.swift:262-267`）按**扫描根 home** 缩写的，
  而本轮 `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 把扫描根设成了卷根（`MMUninstaller.swift:258-260` 那一档
  `ResidualScanOptions(home:)`）。当场核对过两侧：`/private/tmp/mm-p53-mnt/Library/Caches/local.mmvolume.aaap53crossvolume.p53`
  在（9 字节，与那一行对得上），`/Users/lee/Library/Caches/` 下同名那条不存在。
  ⟹ 这条残留与本体**同卷**，可"删它落点在哪"仍然**没量**（同卷 ⟹ 大概率同一处，那是推论不是读数）；
  而"一条台账里两项分属两块卷"这一档**在这套钩子下造不出来**——`UninstallFixtureHooks.canonicalHome` 只认 `/tmp` 之下的目录，
  扫描根永远不可能是真 home，所以那一档只能等真机用户样本，别把它排进下一轮的前置量。
  所以 §4 建议 2 那句合同句里只写本体。
  （补一句免得下一轮把它当 bug：真机上扫描根就是真 home，那个 `~` 不是说谎，只在夹具档里指到别处。）
- **拔掉盘之后真按一次撤回**：本轮没有合成点击（原生 UI 不用合成点击这条纪律），只量到按钮消失。
  按下去会拿到什么，代码那侧是 `:195-199` 那句「没有仍在废纸篓中、可以恢复的文件」，仍是代码依据。
- **`/Volumes/<真盘>` 那一档**：见上一条夹具说明里的"代价"。
- 概览页那行右侧的「打开废纸篓」（照片 02 的 toast 与卸载页顶部那条「读不到废纸篓」横幅）在本机没有完全磁盘访问时
  对跨卷落点能不能用：**没量**，本机那一格本来就是 `Operation not permitted (错误码 1)` 的常态。

### 5. 门禁：`p16-citation-audit.sh` 两跑，硬失败 2 条，其中一条的引用面里有本文

归档 `docs/verification/p53-citations/audit.log`（默认档：存疑明细只列 40 条）与
`docs/verification/p53-citations-symfull/audit.log`（同一条命令 `P16_SYM_DETAIL=400`，存疑全清单，用来对账）。
两跑 `# repo: f7bad50-dirty`、index **1539**，四个读数相同：**条次 1505 / 唯一「路径+行段」1121 / 位置存疑 137 / 硬失败 2**、退出码 1。
**这两份是本节改完之后重跑的**：更早两跑落在 1494 / 1119 / 136 与 1501 / 1121 / 137，差的那十几条全在本文里——
"写账的那一段自己也在被量的面上"这一族自指本轮中了两次，所以只有最后一跑的数才是这份文档的数。

- **与 P52b 收口那一跑（`p52-citations-postcommit`，1490 / 1116 / 132 / 0）对差**：条次 **+15**、唯一 **+5**、存疑 **+5**、硬失败 **+2**。
  本文这一篇按门禁同一套正则现读：**条次 50 → 65、唯一 41 → 48**（新增 8 条唯一、去掉 1 条：
  P51a 写下的旧坐标 `FileTrashService.swift` 第 195–217 行，本轮按现读改成 `:195-199`——注意这一句故意把旧坐标
  写成"第 195–217 行"这种裸形状，写成带冒号的形式就等于把它又引了一遍，上面那两跑的数差里就有这么来的）。
  新增那 8 条逐条点名：`FileTrashService.swift:45`、`:195-199`、`:294-300`、`MainWindow.swift:679`、
  `TrashHistoryStore.swift:38-50`、`ResidualCollector.swift:262-267`、`MMUninstaller.swift:258-260`、
  以及下面第 3 条要说的那条不属于本轮读数的 `SettingsView.swift:169`。
  全仓唯一只涨 5 而不是 8：有 3 条的"路径+行段"在别的文档里已经引过。
- **存疑那 +5**：4 条在 `Sources/MacMaster/SettingsView.swift` 那一面（对差里它是从 1 条变 5 条，
  且这 5 条指向的全是别的文档），来自工作树里另一族未提交的改动；1 条是本轮新增的
  `MMUninstaller.swift:258-260`——门禁把句子里那枚环境变量名当成了要点名的成员，
  而那三行写的确实是"把 `optionsFactory` 换成 `ResidualScanOptions(home:)`"，**坐标没漂，是点名抽错了**，
  存疑面本来就只提示不进退出码（口径见脚本头部第五道判据）。另有一条 P51a 就在的
  `Risk.swift:3-5`，只是"引于本文第 154 行"跟着本文长行变成了 189。
- **两条硬失败形状相同**：都是「整段空白的引用」，`SettingsView.swift:169` 与 `:358`（413 行的那一版里这两行是空行）。
  根因现读：另一族未提交的改动把 `SettingsView.swift` 从 385 行抬到 413 行，而 HEAD 那两行分别写着
  `.task { await notifications.refresh() }` 与 `private func checkForUpdates() {`。
  但**"不是本轮的"这句今天要说得更准**：`:169` 这一条现在有三个引用面
  （`fidelity-shell.md` 第 102 行、`feature-roadmap.md` 第 1033 行、以及本文本节上面那一行列举），
  本文自己成了要重指的对象之一。
  **本轮不改这两处**：它们的正确坐标要对着那一族提交之后的树量，现在改就是替别人猜一个数。
  这一跑的红不是 P53 的红，但 P53 也不能拿它当"门禁绿了"报——下一轮读到这两条时，
  先确认那一族是否已经提交，再按 `git show <新 HEAD>:…` 那棵树重指，三个面一起改。
- **提交后的另一半**（补账笔，同 P49/P52b 那两次的写法）：本批 19 个文件落在 `9591bb9`（父提交 `f7bad50`，
  正是上面归因头里预先写死的那一串），其中 16 个是新增跟踪文件；同一脚本再跑一遍，归档
  `docs/verification/p53-citations-postcommit/audit.log`（224 行）。那一跑 `# repo: 9591bb9-dirty`
  （工作树里那另一族未提交的改动还在，所以仍带 `-dirty`）、index **1555** = 入库前那个 1539 + 本批 16 个，
  四个读数 **1505 / 1121 / 137 / 2 与入库前那一跑逐字相同**——入库这一步没挪动任何一处引用，
  那两条硬失败也一条没少、一条没多。下一轮读到的 index 会是 **1556**，因为这份提交后归档自己这时才进跟踪面。
