# 开发产物「截断根续扫」调研（P6.1a）

> **已落地**（P6.1，2026-10-03）：D1–D7 全部按这一篇实现，实机取证与两处事后修正
> （「第 N 批补全」的判据、"耗时/累计耗时"的口径）在 `fidelity-cleaner.md` §8。
> 下面 §9「拍不到的」已被三个预算/自动续扫钩子解决（§7.3 当时提的口子），见 `hook-ledger.md` 的
> `MM_DEV_ROOT_BUDGET_SECONDS` / `MM_DEV_CONTINUE_BUDGET_SECONDS` / `MM_DEV_AUTO_CONTINUE`。

> 任务：路线候选 #5（`feature-roadmap.md:665`）。P5.1 真机把 `~/Desktop`、`~/Documents`
> 两根留在了橙色点名状态（修预算后 **16.2 秒 / 缺 2 根**，见 `feature-roadmap.md` P5.1 §三件事 1），
> 页面只做到"如实报截断"。用户想把剩下的扫完，目前唯一的办法是再按「重新扫描」——
> 而那是**全量重扫**：把已经扫完的那些根再花一遍预算，被截断的根仍然排在后面等预算。
>
> 这一篇定四件事：**续扫的单位是什么、旧结论还算不算数、合并为什么要重算嵌套、
> 为什么不能做成后台常驻**。纯调研，不动代码。

## 0. 结论先行

| # | 决定 | 理由（详见对应小节） |
|---|---|---|
| D1 | 续扫的最小单位是**搜索根**，不是目录游标 | 枚举顺序无保证、遍历有并行分叉、中间态落盘等于自建索引器（§3） |
| D2 | 续扫批次**只跑被截断的根**，跳过 home 容器探测 | 根集合已经是真路径；重探一次会改变"哪些根要重试"的答案（§3.4） |
| D3 | 一批的预算**不变**（15 s/根、60 s/总），靠"复用完整观测的行"省钱，不靠加时限 | 加时限是把 15 秒的白屏换成 60 秒的白屏；截断发生在测量阶段而不是遍历阶段（§2、§4.2） |
| D4 | 合并必须在**并集**上重跑 `nestedFlags` 和 `group`，不能拼接两张报表 | 否则跨批次双重计体积、同一项目裂成两组（§4.3、§4.4） |
| D5 | 被续扫的根**整区替换**，其余根的行原样保留；复用条件是"这一行上次量到了" | 需要给 `ProjectArtifact` 补 `sourceRoot`（扫描时本来就算出来了，生成报表时丢掉）（§4.1、§4.2） |
| D6 | 续扫**不清空勾选**，只剪掉合并后不再 `isSelectable` 的行；全量重扫仍按老规矩清空 | 用户点「继续」不是来重选一遍的；而嵌套重标会让一行失去勾选框，不剪就是虚报「已选 X GB」（§5.1） |
| D7 | 不做后台常驻，不做自动循环；同一个根第二次还截断就把文案改成"这个根扫不完"+ 出路 | 按按钮的人在场，才是这份清单的意义（§6） |

落地切口与单测清单在 §7，本轮明确不做的事在 §8。

## 1. 现有截断实现（读过代码，行号自查过）

`Packages/MMFileScanner/Sources/MMFileScanner/ProjectArtifactScanner.swift`：

- `ProjectArtifactRules`（:53）把预算做成可注入字段：`rootBudgetSeconds`、
  `totalBudgetSeconds`（默认 15 / 60，`default(home:)` :136）。注释里已经写明
  **根的先后顺序就是预算的分配顺序**（:113-115）。
- `rootDeadline(now:started:rules:)`（:623，纯函数）= `min(now + 每根预算, started + 总预算)`。
  这就是"一批"的形状：**批与批之间天然隔离**，因为 `started` 是每批自己的起点。
- `scan(progress:)`（:301）每根一份 deadline（:328），`DiscoveryOutcome` 三态
  （`.root` / `.truncated` / `.inaccessible`，:442）。三个关键事实：
  1. **被截断的根，它已经发现的候选是保留的**——`.truncated(hits)` 分支照样
     `found.append(contentsOf:)`（:333-336），只是这个根不进 `scannedRoots`。
     所以今天的报表不是"截断根什么都没有"，而是"截断根给了一批**没测完**的行"。
  2. 第二遍成案循环里，`Date() >= info.deadline` 也会把根记进 `truncated`
     （:363）——**发现走完了但成案/测量没跑完，同样算截断**。
  3. 收尾有不变式：`honestScanned = Set(walked) - (truncated ∪ inaccessible)`
     （:383）——同一个根不许既出现在"已扫描"又出现在"被截断"。
     这条不变式本来就是**按根**成立的，续扫只需要沿用它，不用新造口径。

`FileTreeWalker.swift`：`readEntries`（:48）用 `contentsOfDirectory` 取名字、逐项
`lstat`、跳过点目录、不跟随符号链接；`stats`（:73）在 `depth < 3` 时用任务组并行；
`largeFiles`（:155）在 `depth < 2` 时并行。**没有任何一处对外暴露"下次从哪儿接着走"。**

`DevArtifactView.swift`：`scan()`（:87）先 `scanTask?.cancel()` 再发全量重扫；
`apply(_:)`（:101）把 `selectedPaths` 清空；`clean()`（:147）删完直接 `scan()`；
橙色那条点名在 `scopeBar`（:306-316），文案是"有 N 个根扫到一半就超时，本轮不报数"。

删除链路：`FileTrashService.swift:43`/`:86` 在真正移动每条路径之前再问一次
`DeletionGuard.rejection(for:)`。**闸门在删除现场，不在扫描现场。**

> 行号约定：本节之后不带文件名的 `:NN` 一律指 `ProjectArtifactScanner.swift`；
> 指页面文件时写成 `DevArtifactView.swift:NN`。

## 2. 真机为什么截断（本轮实测）

在开发机（macOS 27.0 / arm64，`~/Desktop` 34 个顶层条目、`~/Documents` 20 个）上量的四个数：

| 量的是什么 | 结果 |
|---|---|
| `find ~/Desktop -maxdepth 3 -type d`（整根浅层遍历） | **0.06 s / 406 个目录** |
| `find ~/Documents -maxdepth 3 -type d` | **0.07 s / 1412 个目录** |
| 单个 `node_modules` 子树（`Desktop/artisan_heir/node_modules`） | **40,396 个条目 / `find` 一遍 0.38 s** |
| 两根里名字像产物的目录（`node_modules`/`.build`/`target`/`dist`/`build`/`.venv`/`__pycache__`/`DerivedData`，深度 ≤6，**不 prune**） | **9,321 个 / 10.4 s** |

结论很直接：**发现遍历不是瓶颈**（两根的浅层遍历加起来不到 0.15 秒），
预算是被**成案阶段**吃掉的。`process(path:...)`（:495）对每个候选要做：

1. `listAllEntries(parent)` + `resolveProjectRoot`（向上最多 `projectRootMaxUp`=8 层，每层一次目录列举）；
2. `canEnumerate(candidate)` + 候选目录自身列举（判 `verdict` 要看 ownChildren）；
3. `activityProbe(in:deadline:)`（:580）——**把候选整棵子树走一遍**，只在撞到近期文件时早退；
4. `FileTreeWalker.stats(path:)`（:552-567，受同一个 deadline 约束）——**把同一棵子树再走一遍**。

一个 4 万条目的 `node_modules`，第 3、4 步就是两趟全子树遍历。真机上被截断的
恰恰是**项目最密集的 `~/Desktop`、`~/Documents`**——候选多、每个候选大。

**这条实测决定了 D3 和 D5**：截断根的"剩余工作"几乎全在"没测完的那几行"上，
不在"没走到的那些目录"上。所以续扫要复用的是**行**，不是游标。

## 3. 为什么单位是根，不是目录游标

### 3.1 枚举顺序没有保证

`readEntries` 的来源是 `FileManager.contentsOfDirectory(atPath:)`，Apple 明确写着
**返回顺序未定义**；底层 `readdir` 在这类目录里也不保证跨调用稳定。游标的语义是
"这个目录我已经处理过前 k 个名字"，一旦顺序变了，k 之后的名字会被跳过或者重做，
而跳过就是**漏报**——漏报在这一屏会以"你的磁盘很干净"的形状出现。

### 3.2 遍历没有单一挂起点

`discoverCandidates`（:451）是逐层的广度优先：每层把非候选目录收进 `directories`
再整体换成 `next`。深度大时"走到第几层的第几个目录"能勉强表达，但真正的成本在
`process()`——它对每个候选独立跑两趟子树遍历，而这趟遍历内部还有任务组并行
（`stats` 在 `depth < 3` 时并行；这条链路只用 `stats`，`largeFiles` 是磁盘页的）。并行的树没有
"接着上次那条指令"的位置；要表达只能退化成"哪些目录已经量过"的集合，那就是 §4.2
的**按行复用**，比游标更粗也更有意义。

### 3.3 游标要落盘，落盘就是索引器

一个能跨启动续扫的游标必须持久化"未完成的目录栈"。这既超出 P5.1 的"纯只读、按页扫"
定位，又正好撞上路线里已经排除的后台常驻（`feature-roadmap.md:665` 备注那一栏）。

### 3.4 根级续扫够便宜

续扫一批只传 `truncatedRoots` 里的真路径，**不再跑 `expandedSearchRoots()`**（:400）。
两个原因：一是容器探测依赖当时的 home 状态，重探可能给出一批新的根，"重试哪些根"
就有了两个互相矛盾的答案；二是探测本身要遍历 home 一层，没必要为一批只跑两根的
扫描付这个钱。代价是：新出现的顶层项目目录这一批不进清单——它属于"重新扫描"的语义，
不属于"续扫"。UI 上这两条要分开写（§7.2）。

### 3.5 一个已存在的小坑，续扫会放大它

`rootDeadline` 用的是 `Date()` 起点，而**每个根的预算和总预算在同一批里共享**：
一批里排最后的根仍然可能被总预算饿死。续扫批次通常只有 1–2 个根，饿死概率远低于全量，
但合并后的报表口径必须说清"这一批谁没轮到"——不能让它冒充"扫完了"。这也是 D1
坚持"根是可信度的单位"的另一半理由。

## 4. 合并语义（真正的难点）

续扫产出的是**第二张 `ProjectArtifactReport`**，必须和第一张合成一张给用户看。
下面六条不是风格选择，是错一条报表就假的地方。

### 4.1 按根分区，续扫的根整区替换

新报表 = 未续扫根的全部行 + 续扫根的全部行（新）。判断"某一行属于被续扫的根"
需要行的归属信息——`scan()` 内部本来就把 `(path, root, deadline)` 记在一起
（:310），但 `ProjectArtifact`（:183）没有 `sourceRoot` 字段，生成报表时丢了。
**建议补这个字段**：它同时让 UI 能说"这一行是第几批扫到的"，也是 §6 的
"同一根第二次截断"判定的依据。

不要改成"新行覆盖同 path 的旧行"这种按路径合并：那会把一个根的旧证据
（发现于第一批、当时预算耗尽）和另一个根的新证据混在一个区里，`truncatedRoots`
与行的对应关系就再也说不清了。

### 4.2 复用"上次已经量完"的行

续扫批次对**已经落在已知清单里的候选路径**直接复用旧行，不再跑 `process()`。
"已知"的判定必须严格（缺一即视为未知、要重测）：

- `size != nil`（体积真量到了）；
- `activity` 不是 `.unknown`（活动探测**完整跑完**过——`activityProbe` 只有
  走完才给 `.noRecentFile`，超时/读不动一律 `.incomplete`，见 :577-601 的注释）；
- `verdict` 不是"读不进产物目录"那条兜底 `protected`（:534，那是没看完证据的保守，不是结论）。

这样省钱的方向和 §2 的实测对得上：第二批的预算花在第一批没量完的行上。
**为什么不复用 `.unknown` 的行**：一个 `activity == .unknown` 的行没有勾选框吗？
不是——`.unknown` 的行按 `selectUntouched()` 的口径不会被自动选中（`DevArtifactView.swift:136-141` 只挑
`.untouchedForDays`），但它可能有勾选框、可能显示"—"。复用等于把"上次没看完"
永久冻结，续扫就永远叫不停。

### 4.3 `nestedFlags` 必须在并集上重算

`nestedFlags(paths:)`（:842）的语义是"祖先里也有候选的子候选只标不量"，
它只看**候选全集**。第一批在 `~/Documents` 里量完了 `X/dist`（2 GB），
第二批才在同一根里发现 `X/dist/node_modules`——拼接两张报表的话这一对会同时带体积，
`reclaimableSize` 就重复计数（`group` 是靠 `isNestedInAnotherArtifact` 跳过的，:755）。
反过来的情形也存在：第一批把 `X/dist/node_modules` 当成独立行量了（因为当时
`X/dist` 还没被发现），并集重算后要改标"已计入上一行"。

实现上的摩擦：`isNestedInAnotherArtifact` 是 `let`（:202），`ProjectArtifact` 全字段
除 `size` 都是 `let`。合并要么加一个 `withNestedFlag(_:)` 副本方法，要么用 public init
重建。倾向**加副本方法**——重建会把"哪些字段是观测、哪些是标注"这件事藏进调用点。

### 4.4 `group` 也重跑，因为 monorepo 边界可能第二批才发现

`group(artifacts:home:)`（:747）按 `projectRoot` 分桶、取桶内第一个非 nil
`monorepoIndicator`。第一批只见 `A/packages/x/node_modules`（普通项目根），
第二批才发现 `A/pnpm-workspace.yaml`，整个 workspace 该归一组——重跑 `group`
是把两批的裂组缝回来的唯一办法。注意 `group` 只消费行上已有的 `projectRoot`
字符串，所以两批里同一个 workspace 的 `projectRoot` 必须解析成同一个路径
（同一套 rules、同一个 `projectRootMaxUp`，成立）。

### 4.5 根账本：并集 + 守恒

- `scannedRoots` = 老批的已扫根 ∪ 新批里这轮走完的截断根；
- `truncatedRoots` = 还没走完的（新批里再次截断的 + 这轮没轮到的）；
- `inaccessibleRoots`、`missingRoots`：新批不该重碰已判"读不动"的根（读不动是权限事实，
  重试只烧预算），把它们带进新报表的账本，但**不放进续扫输入**；
- `outOfSearchRootCandidateCount`：相加，但要说清它是"几批累计"（它本来就是计数不是集合）；
- `isComplete` = `truncatedRoots.isEmpty && inaccessibleRoots.isEmpty`，沿用现有口径。
  合并后必须重跑 §1.3 的守恒检查（一个根只出现在一个列表里），这条写成单测。

### 4.6 时间：清单是几批拼出来的

`duration` 是每批各自的墙钟；副标题的「扫描于」用的是模型的 `scannedAt`（`DevArtifactView.swift:37` 的注释
已经说了"清单是几分钟前的"这件事必须写在脸上）。续扫后这个数要改口径：
建议 `scannedAt` 记**最后一批完成时刻**，另在点名那行写"含 2 批 · 第 2 批跑了 3.1 秒 ·
1 个根仍没扫完"。`activity` 里的天数是各批 `now` 算出来的（`activity(...)` :721），
跨批最多差几小时，而 `selectUntouched()` 只看枚举 case 不看数字，可以接受；
文档要写明这是**已知近似**，别说它是精确值。

## 5. 勾选与删除安全

### 5.1 续扫不清空勾选

`apply(_:)` 现在无条件 `selectedPaths = []`，理由（`DevArtifactView.swift:102-103` 的注释）是"路径可能已经
不存在，勾着不存在的目录按删除，回执里只有找不到文件"。这个理由针对**全量重扫**成立。
续扫的正确做法是**修剪而不是清空**：只保留合并后仍然成立的行（判据见下一段）。
路径没变、判定没变、用户 consent 的对象没变；清空等于让用户在每次按「继续」之后
重选一遍，而续扫本来就是给"想扫完再删"的人用的。

一条必须同时立的规矩：被续扫根里**这次没再发现**的行（目录被删了/改名了）要从勾选里
消失。更要紧的是——**修剪的判据不是"路径还在"，而是"合并后这一行仍然 `isSelectable`"**：
`isSelectable`（`DevArtifactView.swift:692`）的三条是"非嵌套 + 体积量到了 + 判为可回收"，
而 §4.3 的并集重算恰恰会把一行从"独立行"改成"已计入上一行"。那一行的勾选框必须一起消失，
否则「已选 X GB」（`selectedSize`，`DevArtifactView.swift:71-82`）会把父和子各算一遍，用户按下删除时看到的
第一个数字就是虚高的——这一屏最不该骗人的那个数。

规矩落在实现上的分工：`isSelectable` 是 MMCleaner 侧的判定（不在扫描器里），
所以**修剪必须在模型做**，不能指望 `mergedReport` 顺手把勾选一起收拾干净。写成单测。

### 5.2 续扫不新增任何删除权限

- 合并只会让行的可选性**变窄不会变宽**：`protected` 不会因为再扫一遍变成可勾，
  而唯一会让可勾行失去框的变化是 §5.1 说的嵌套重标（方向是更安全的一侧）；
- 按下删除后，`FileTrashService` 对每条路径现场问 `DeletionGuard`
  （`FileTrashService.swift:43`），`DeletionGuard` 同时检查逻辑路径和
  `realpath` 解析后的物理路径（`DeletionGuard.swift:68-72`）。
  扫描是几分钟前还是几批前，对这道闸门没有影响。

### 5.3 陈旧窗口确实被拉长了，如实写明

`verdict` 是扫描时刻的证据（邻居文件、ownChildren 里有没有 `.git`）。
第一批判"可回收"的行，在两批之间可能被用户塞进 `.git` 变成签出目录——
这个窗口 P5.1 本来就有（`scannedAt` 到 `clean()` 之间），续扫把它从"一次扫描的间隔"
变成"用户按了几次按钮"。接受它的理由是 §5.2 的双层结构：扫描器判定是**前置体验**，
真正兜住误删的是删除现场的 `DeletionGuard` + `FileTrashService`；
而 `clean()` 之后立刻 `scan()`（`DevArtifactView.swift:160`）会把清单换成新的。

不做的事：不在删除前逐条重跑 `verdict`（那是把扫描器搬到删除路径上，
多一次全量遍历换一点心理安全），也不给行加"过期"倒计时。

## 6. 为什么不做后台常驻，也不自动循环

1. **按按钮的人在场，是这份清单的全部意义**。这一屏的产物目录属于用户自己的项目，
   "7 天没碰"是判据，不是许可；后台常驻会把"我准备清一下"变成"这个应用一直在读我的
   Desktop/Documents"——TCC 授权、电量、iCloud 占位文件（dataless，读一次就触发下载）都会因此变贵。
2. **自动循环 = 把截断藏起来**。如果一批接一批直到扫完，橙色那条点名就永远在闪，
   用户看到的是"它在自己努力"，而产品该说的是"这个根在你的预算内扫不完"。
3. **截断是有信息量的**：一个根在 15 秒预算内扫不完，意味着里面的候选又多又大。
   出路应该交给用户，不是交给循环：把项目放在更浅的目录，或者**把某个具体项目目录
   单独配成搜索根**（深度 0 豁免见 `isDepthAllowed` :470 与 `rootIsProject` :455，
   单项目模式本来就支持）。
4. 所以 D7：续扫是**用户按一次跑一批**。同一个根第二次仍然截断，就把文案从
   "继续扫描这 N 个根"改成"这 1 个根在 15 秒内扫不完"+ 上面那条出路。
   判定用 §4.1 新加的 `sourceRoot` 做尝试计数（内存里计数即可，不跨启动）。

预算**不**递加（D3）：递加超时是把 15 秒的白屏换成 60 秒的白屏，而且它让
"再按一次"的代价变得不可预期。要真想把这一类根一次扫完，正解是 §8 的那次遍历合并。

## 7. 落地切口（给 P6.1b/c）

### 7.1 MMFileScanner

- `ProjectArtifact` 补 `sourceRoot: String`（扫描时已在 `found` 元组里，:310）。
- `ProjectArtifact` 补 `withNestedFlag(_:)`（§4.3）。
- `scan(progress:)` 加续扫入参：`roots: [String]?`（nil = 全量语义，含容器探测）
  与 `reuse: [String: ProjectArtifact]`（§4.2 的复用表）。默认参数保持现有调用点不动。
- 新增纯函数（都 `nonisolated static`，好测）：
  - `mergedReport(base:continuation:)`——§4.1 分区 + §4.3 重算 + §4.4 重组 +
    §4.5 账本守恒；
  - `isCompleteObservation(_:) -> Bool`——§4.2 三条判据；
  - `rootsToContinue(report:previouslyTried:) -> [String]`——D2 + D7（排除
    `inaccessibleRoots`，带上尝试次数）。

### 7.2 MMCleaner（`DevArtifactView`）

- 模型加 `continueTruncatedRoots()`：跑一批、成功后 `mergedReport` 替换 `report`，
  勾选按 §5.1 **修剪**；失败/取消**不换报表**（取消的一批不留半成品，沿用 `DevArtifactView.swift:95` 的
  `Task.isCancelled` 早退）。
- 点名那行（`DevArtifactView.swift:306-316`）加一个 `Button("继续扫描这 N 个根")`；`isScanning` 期间禁用
  「重新扫描」，续扫按钮共用同一个 spinner 文案，别造两套忙态。
- 副标题（`headerSubtitle`，`DevArtifactView.swift:263`）说清批次：`… · 含 2 批 · 1 个根没扫完`。
- 第二次的文案按 D7 改口（"在 15 秒内扫不完" + 出路）。

### 7.3 钩子（要能拍到，且不碰真项目）

- `MM_DEV_ROOT_BUDGET_SECONDS`：覆写 `rootBudgetSeconds`。续扫的取证必须有
  "第一批真的截断"，而夹具目录太小、默认预算下永远扫得完。取 `0.05` 这类小值
  让第一批确定性地截断、第二批扫完。**只认数值，解析失败忽略**。
- 复用 `MM_PURGE_FIXTURE_HOME`（只认 `/tmp`，`DevArtifactView.swift:45`）与
  `Scripts/purge-fixture.sh`；夹具里造一个"父产物 + 内层嵌套产物"的配对，
  让 §4.3 的双重计数在照片里能被证伪（第一批只见父、第二批才见子）。
- 不新增任何会落盘写真路径的钩子。

### 7.4 单测清单（纯函数面，不打 IO）

1. `mergedReport`：续扫根的行整区替换，未续扫根逐字节不变。
2. `mergedReport`：第一批的父 + 第二批的子 → 子标 `isNestedInAnotherArtifact`、
   组体积不重复计（断言 `reclaimableSize` 等于父的体积）。
3. `mergedReport`：第二批发现 monorepo 标志 → 原本裂成两组的同一 workspace 合成一组。
4. `mergedReport`：账本守恒——任一根不同时出现在 `scannedRoots` 与 `truncatedRoots`；
   全部根走完 → `isComplete == true`。
5. `isCompleteObservation`：`size == nil` → 假；`activity == .unknown(_)` → 假；
   `protected("读不进产物目录…")` → 假；正常行 → 真。
6. `rootsToContinue`：`inaccessibleRoots` 不进续扫输入；同一根第二次仍截断 →
   返回的尝试计数为 2（供 D7 文案）。
7. 勾选修剪：续扫后 `selectedPaths` 只留**合并后仍 `isSelectable`** 的 id——
   路径消失要剪掉，被重标成"已计入上一行"的更要剪掉；父行与被剪掉的子行同时存在时，
   `selectedSize` 不得把两者都算进去。
8. `scan(roots:)`：传入显式根时**不**跑 home 容器探测（夹具里造一个 home 一级
   容器目录，断言它不在扫描日志里）。

## 8. 这一轮不做（记下来免得下轮重新发现）

- **遍历合并**（§2 的第 3、4 步合成一趟：`stats` 顺便带 mtime 判据，
  或 `activityProbe` 的枚举结果喂给体积统计）。这是**吞吐的正解**，
  能把每个候选的两趟子树砍成一趟，真机上截断的根很可能就此扫得完。
  本轮不做的原因：它改的是 `process()`/`FileTreeWalker` 的度量口径，
  牵动 `DirectoryMetrics` 与其他模块共用的一致性（`FileTreeWalker.swift:230` 的注释
  就是这条约束），风险等级和续扫不是一个量级。做完续扫之后作为独立候选提出。
- 跨启动的续扫状态（游标、报表落盘）。P1.6 有删除历史持久化，不代表扫描结论也该持久化——
  产物目录随时被工具重写，落盘的清单比不落盘更容易骗人。
- 后台常驻、开机自启、自动循环（§6）。
- 预算递加（§6.4）。

## 9. 拍不到的（诚实列）

- **真机上"续扫到扫完"**这一张可能拍不到：`~/Desktop`、`~/Documents` 的剩余工作是
  测量阶段（§2），一批 15 秒能推进多少取决于磁盘与冷缓存，第二次按按钮不一定收尾。
  收尾档用 §7.3 的小预算夹具拍，真机那一张只拍"点名 + 续扫按钮 + 批次数"。
- **§4.3 的双重计数**在真机照片里看不出来（要跨两批对表），只在夹具那张里可证伪。
- **`.unknown` 行被重测**没有独立画面——它的可见后果是"这一行的徽章从『未确认』
  变成『N 天未触碰』"，得靠夹具造一行注定超预算的活动度探测才能拍到。
