# 应用本体有没有风险档（P51a 审计，2026-10-16）

> 缘起：`docs/analysis/uninstally-adoption.md` §6 末尾那条「还没做的」把两件事写在同一句里——
> §2 的 `.component` 风险档与 §3 的外接卷 `caution` 分档，「两条同撞在"应用本体有没有风险档"那一个决定上，进设计稿队列」。
> 本文把这个决定拆开：先现读"档"在我们这里到底长在哪一层，再逐条给建议与代价。
> **本轮只审计，代码一行未动**；下面所有 `文件:行号` 都是本轮（P51a）对着磁盘现读出来的。

## 0. 结论先行

1. **本体这一层今天没有任何档位，而且不是"少见场景才成立"**：卸载页把 45 条应用全摆出来，其中 4 条是
   `com.apple.*`（Safari、TestFlight、Transporter、Xcode），详情面板底部那两个卸载按钮对它们**照样是 enabled 的**
   （`MMUninstaller.swift:1887-1896`、确认面板内 `:761-771` 都没有 `.disabled`）。
   `isSystemOwned` 改变的只有两件事：**不扫残留**（`UninstallerModel.swift:368-372`）与**一枚徽章**
   （`MMUninstaller.swift:1689-1691`、`:1862-1868`），它不是"能不能删"的判据。
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
   这两种表达界面上都已经有了（`allowsDeletion` 决定的勾选框、`cautionNotice` 那个橙色块 `MMUninstaller.swift:780-792`），
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
- 机制一：默认勾选只来自 `.safe`（`UninstallerModel.swift:86-88`，合同句在 `:85`）。
- 机制二：不给删除入口的是 `.readOnly`（`:91-93`；执行处与行内勾选框各挡一次，`:458`、`MMUninstaller.swift:1280`、`:1936`）。
- 版式：按档分组，组序 safe → caution → readOnly（`ResidualScanner.swift:383-384`），
  每组一枚 `MMBadge(risk:)` + 一句 `groupNote`（`MMUninstaller.swift:1902-1912`），
  页脚那枚「N 项默认不勾选」是同一档的另一处表达（`:1849`）。

**这一层没有缺口。** 上一轮的插件残留之所以还没做，缺的从来不是"档"。

### 2.2 本体层：没有档，也没有档的载体

- 数据结构：`UninstallCandidate`（`UninstallerModel.swift:8-36`）字段读满是 `path / bundleID / version / size / residuals / isSystemOwned / provenance / steamLauncher`——**没有 `risk`**。
- 勾选模型只作用在残留上：`deletionPaths(appPath:items:selectedIDs:)`（`:97-102`）返回的是
  `[appPath] + 勾选残留的互不嵌套根`，**本体那一条是无条件拼进去的**；
  两个入口 `uninstallAppWithSelection`（`:492-497`）与 `uninstallAppOnly`（`:500-503`）都走它。
- 界面上本体那一行（`MMUninstaller.swift:1631-1696`）有四样"看着像档位"的东西，全部是提示，
  **没有一样改变可删性**：
  ① `sourceChip`（判定 `:1349-1355`，只有 brew 两档占这一格，注释 `:1346-1348` 写明了理由）；
  ② `runningChip` / `runningWarning`（`:1472`、`:1541`，P31a 那句"只提示不代杀"）；
  ③ `steamLauncherChip`（`:1574`）；
  ④ `isSystemOwned` 那枚「系统应用」徽章（`:1689-1691`）。
  确认面板同样只有两枚橙色提醒（`sourceWarning` `:1441` 的文案、`runningNotice`），
  键值六行是「应用 / 来源 / 包名 / 本体 / 残留 / 合计」（`:717-725`）——**「本体」那一格只报体积，不报风险**。

### 2.3 真正拦得住本体的那条闸：它按位置判，不按身份判

正向闸的根清单来自 `deletionRoots(for:)`（`UninstallerModel.swift:514-517`）= 残留清单的 Library 根 + 应用目录，
执行处两遍口径要求**字面与 `realpath` 之后都在根内**（`DeletionGuard.swift:115-126`）。于是本轮那 4 条 `com.apple.*`：

- `Safari.app`：字面 `/Applications/Safari.app` 在根内，解析后是 `/System/Cryptexes/...`
  → 正向闸拒（`:121-123`），黑名单也拒（`systemRoots` 含 `/System`，`:25-33`、`:134-136`）。**两条都拒，删不掉。**
- `Xcode.app` / `TestFlight.app` / `Transporter.app`：字面与解析后都在 `/Applications` 之内，黑名单里没有 `/Applications`
  → **闸门放行**。它们今天能不能真删成取决于运行时权限（见 §6，本轮没量），
  但"卸载页把 Apple 提供的应用当成一个正经卸载候选、并且不给任何一句风险话"这件事与权限无关。

**这里要写清一句避免误读**：Safari 那条不是"我们设计了系统应用保护"，是符号链接恰好逃出了允许根。
按位置判的闸本来就答不了"这是谁的应用"——那正是 `uninstally-adoption.md` §1 那句"黑名单永远补不全"的镜像面：
**正向闸补的是"位置"，任何闸都不补"身份"**。

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
  现读**没有任何一条测试钉住今天的行为**（`grep -rn isSystemOwned Packages/MMUninstaller/Tests/` 零命中），
  所以这一改动不会撞旧合同，但也意味着**旧行为从来没被验收过**。
- 待量的前置：`isDeletableByCurrentUser` 只看父目录（`ResidualCollector.swift:206-214`，那句注释的理由是"移到废纸篓要的是父目录的写权限"）。
  这一条对**文件**够用，对**目录型 bundle** 够不够，本文不下结论——落地轮先用夹具量一次再决定是否复用
  （复用比新写一条好，同源这件事在 P21b 已经是判据）。

### 建议 2 外接卷上的应用：保持可删 + 强制一句警告（代价 S–M，要改稿）

- 做什么：本体行增一枚 chip「外接卷」（复用 `SourceChip` 那一族的版式与字号，`MMUninstaller.swift:1647-1666`），
  确认面板在键值六行下方插一块 `cautionNotice`，文案要说清**撤回会怎样**而不是只说"这是外置盘"，
  建议合同句：「这条本体在外接卷上，移入废纸篓后落点也在那块卷上；拔盘后「最近操作」里的撤回会失效（本轮未实拍，见 §6）」。
- 判据从哪来：`AppScanner.applicationDirectories(home:volumePaths:directoryExists:)`（`AppScanner.swift:43-48`）
  已经把"每条候选卷一项"和"三条固定"分开写了，本体只需带上"我来自哪一组"——
  今天这个信息在 `DiscoveredApp`（`:10-20`）里**丢了**，只有 `path`，所以这一片的最小改动是给它补一个来源标记，
  而不是在 UI 里反向解析路径前缀（`/Volumes` 字面量散进 UI 是另一种漏）。
- 为什么不是 `readOnly`：外接卷上装的正是用户自己装的应用，一刀切不给删就把 P49 那一整条能力废了；
  代价不对称这件事要说，但要说的是"撤不回"这条真的不对称，不是"这是外置盘"。
- 需要设计稿：是。chip 位与那句警告各一处，稿面在 03 系（列表行 + 确认面板），
  稿子改动要走 `docs/design-system/screens/mmuninstaller/` 与 `fidelity-uninstaller.md` 的对照，不能只改代码。

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

1. 本体行的 chip 位（第二行，`SourceChip` 同族，`MMUninstaller.swift:1647-1666`）：新增「外接卷」一枚。
   这一行今天已经有四样东西抢宽度（运行中 / brew / 启动器 / 版本号 + 体积），
   P26 那一族截断教训在这里直接适用：**新增一枚要同时定"哪一枚让步"**，不能只加不减。
2. 系统应用的本体：**没有**删除按钮，详情面板底部换成一句只读说明；列表行的「系统应用」徽章保留。
   这里要定的事是「残留」那一节怎么措辞——今天 `:1862-1868` 那句"删除不会回收空间"其实说了两件不同的事，
   改成本体只读之后，它得能说清"不扫"和"不删"是两个决定。
3. 确认面板的警告块：复用 `cautionNotice`（`:780-792`），与 `sourceWarning` / `runningNotice` 同一版式——
   这三块在同一屏里叠起来时**谁在上、要不要合并成一块**，是稿子要画的第一件事（`:730-736` 现在只允许两块）。
4. 建议 3-A 的插件残留行：走现成的按档分组版式，零新版式；只有类别名与 `note` 那句"为什么算它"要新写
   （对照 `ResidualCategory.note` 那张表，`ResidualScanner.swift:108-123`）。

## 6. 本轮没测的（如实记）

- **没删过任何东西**：本文全部结论来自读代码与读目录，没运行过一次卸载动作，也没有照片。
  建议 1 的"系统应用今天能被删"这句只到"闸门不拦、按钮可点"为止，**没量到 `trashItem` 的真实成败**。
- **本轮的权限读数是脏的**：`test -w /Applications/Xcode.app` 这一类 `access(W_OK)` 读数来自
  Qoder 代理的受限 shell（只能写工作区与 `/tmp`），**它测的不是 MacMaster 运行时的判据**，
  所以本文不引它作为"删得掉/删不掉"的证据。要量这一条得在应用自己那一侧走夹具（`MM_*` 钩子 + 假 home，
  机制现成：`MMUninstaller.swift:258-265`）。
- 跨卷废纸篓的真实落点（落在那块卷自己的 `.Trashes` 还是用户的 `~/.Trash`）与"拔盘后撤回长什么样"：只有代码依据
  （`FileTrashService.swift:195-217`、`:298`），**没有实拍**。建议 2 的文案要落地前必须先把这一张拍出来，
  否则那句"拔盘后撤回会失效"就是我们自己写的一句没量过的话——与 P46d 判 `noteFileSystemChanged` 不采纳时
  同一类错误（`uninstally-adoption.md` 第 216-218 行那段）。
- `isDeletableByCurrentUser` 对目录型 bundle 是否成立（§4 建议 1 那条待量前置）：未测。
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

- **三批落点**：审计本体落在 `c9e06da`（本文 §0–§7、`uninstally-adoption.md` 的三处行内指针——第 191、207、372 行，
  只在那三行里加字、没有加行——外加两份入库前的门禁 log）；这一节初稿落在 `24c1398`；
  归因那一轮与它带进来的五份 log 落在 `79cae53`。源码与测试一个字节没动。
- **引用门禁九跑**（本树），归档在 `docs/verification/` 下 `p51-citations-` 开头那九个目录里：
  v2（本文入库后、加指针前）、final（加指针后）、postcommit（第一批提交后，`# repo: c9e06da` 不带 `-dirty`）、
  symfull（同一棵树、存疑明细放开到 400 行那一跑）、close / close2 / postcommit2 / close3（这一节写出、
  入库、把下面那处措辞改回散文之前之后各跑）、postcommit3（第二批提交后，`# repo: 79cae53`，工作树干净）。
  第十个目录 `p51-citations-baseline-9e15e18` 不是本树的跑，是基线那棵树的一跑，专给下一条对账用。
  **门（硬失败）与行号越界、整段空白、死符号四层九跑全为 0，退出码九跑全 0**；
  唯一「路径+行段」1104、命本仓库 966、命参考仓库 137、位置存疑 132 九跑相同；
  `docs scanned` 47 个真抽了 / 47 个入库 .md。
  **两处动过的数要写清，别读成"九跑逐字相同"**：条次 1472 → 中间三跑 **1473** → 最后两跑又是 1472，
  那一格是这一节自己造成又自己收回去的——初稿在下面的存疑说明里把同一个代码区间按"`路径:行段`"的形状又引了一遍，
  条次算重复引用、唯一数不算，改成散文说法后回到 1472；`# index:` 1507（本文入库前）→ 1509 → 1511 → **1516**
  （这一批又补了五份 log 入库），P50 那一轮末尾留的预测「`git add` 之后下一轮读到的 index 是 1506」对上了
  （1506 + 本文 = 1507）。
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
- **下一轮从这里接**：建议 1 的实现要单独授权（`S`，不依赖设计稿，是三条里唯一现在就动得着的）；
  建议 2 与建议 3-B 先出设计稿，且建议 2 动手前必须先把"跨卷落点 / 拔盘后撤回"那张实拍补出来（§6 第二条）；
  建议 3-A 的前置是把 `isDeletableByCurrentUser` 在目录型 bundle 上的行为量出来（§6 第四条）。
