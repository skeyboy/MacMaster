# 开发产物「两趟并一趟」调研（P6.3 · 吞吐）

> 任务：`docs/analysis/feature-roadmap.md:776-780` 的 P6.3——把 `activityProbe` 与
> `FileTreeWalker.stats` 两趟全遍历并成一趟，顺带作为 `fidelity-cleaner.md` §8.6
> 「根报已扫完而组里挂着读不到」的修法窗口。
> 前置：`dev-artifact-continuation.md`（P6.1a）§2 的实测与 §8 第一条「本轮不做」。
> **纯调研，不动代码**；所有行号本次都亲自打开核对过。

## 0. 结论先行

| # | 结论 | 依据（小节） |
|---|---|---|
| C1 | 两趟之间**没有顺序依赖**，合并是可行的：`process()` 先跑 probe（`ProjectArtifactScanner.swift:583`）再跑 stats（`:596`），stats 不消费 probe 的任何输出，唯一共享的是同一个根级 `deadline` | §2 |
| C2 | 两趟分家不是历史巧合，是**两份不同的遍历合同**：stats 是全站共用的度量口径（跳点条目、符号链接计体积、深度 20+3 静默截断、读不进静默计 0），probe 需要的是另一套（含点条目、不读符号链接、无深度限、fail closed、可早退）。一次 `lstat` 的字段两边都够用了 | §1、§3.1 |
| C3 | 合并的正确形状是**给 `FileTreeWalker` 新增一个内部合并入口**，返回 `(size, fileCount, sawRecentFile, unreadableDirectories, stopReason)` 五元组；`stats`/`readEntries` 的既有签名与语义一字不动，其余四个调用方（UserFolderScanner / SystemAnalyzer / InstallerScanner / DirectoryMetrics）不受牵动 | §3 |
| C4 | §8.6 的矛盾修在 `scan()` 的成案循环收尾（`:410-417` 只查"处理**前**是否超时"）：合并遍历把"这一行有没有出结论"变成 walk 返回值里的显式字段，超时落在最后一个候选**中间**时根要进 `truncated` 而不是继续当"已扫完" | §4.3 |
| C5 | 收益量级：对**完整跑的**候选（久未触碰、非嵌套），测量阶段的 readdir+lstat 遍历从两趟变一趟，接近砍半；对早退的候选（近期在用）只省根目录一层。P6.1a §2 的 0.38 s/趟是 `find` 的数，不是本应用单趟的数——**本调研没跑过任何应用内计时** | §5 |
| C6 | 红线不破：本合并只发生在一批扫描的内存里，**不引入游标、不落盘、不常驻**；预算数值（15/60）不动 | §6 |

## 1. 两趟现状（可核对的行号）

两趟都发生在 `ProjectArtifactScanner.process()`
（`Packages/MMFileScanner/Sources/MMFileScanner/ProjectArtifactScanner.swift:534`），
对**每一个候选产物目录**各跑一遍子树。它们都不使用 `URLResourceKey`/`resourceValues`，
读的字段全部来自 `Darwin.lstat`：`st_mode & S_IFMT`（类型）、`st_size`、`st_mtimespec`。

### 1.1 趟一：`activityProbe(in:deadline:)`（`ProjectArtifactScanner.swift:636-657`，P36 整段现读重指：本小节原记的锚点全部停在该文件 +49/+17 两次插行之前）

- 走什么：**候选整棵子树**，含 `.` 开头的条目（枚举用 `listAllEntries`，`:643`；
  该函数 `:1082-1104` 与 `readEntries` 同一份 lstat 口径，但保留点条目 `:1079-1081` 前后、
  且**跳过符号链接** `:1091-1092`）。
- 形状：串行 DFS（显式栈 `:638-639`，`popLast`），**无深度上限**。
- 读什么：每个条目的 `modificationDate`（lstat 的 `st_mtimespec`，`:1099-1100`）
  与 `threshold = now - minAgeDays*86400` 比较（`:637` 定义、`:651` 处比较）。
- 预算：根级 `deadline`（`rootDeadline` `:711-715` = `min(每根 15 s, 整轮 60 s)`，
  默认值 `:136-137`），**每弹出一个目录查一次** `Date() >= deadline`（`:639-641`），
  另查 `Task.isCancelled`。
- 截断语义（`:630-631` 注释是合同原文）：**只有完整跑完才许 `.noRecentFile`（`:656`）**；
  超时/取消 → `.incomplete`（`:640-642`）；目录存在却一条都列不出（TCC/权限）→ `.incomplete`
  （`:644-647`）。撞到第一个近期文件**早退** `.recentFileFound`（`:651-652`）。
  `.incomplete` 经 `activity(rootModified:probe:…)`（`:809` 起）映射为 `.unknown`，
  绝不折成"很久没碰"（文件头纪律 3，`:17-19`）。

### 1.2 趟二：`FileTreeWalker.stats(path:)`（`FileTreeWalker.swift:73-135`）

- 走什么：**同一棵候选子树**，但枚举用 `readEntries`（`:48-70`）：
  `contentsOfDirectory`（`:49`）后**跳过点条目**（`:54`）；符号链接 lstat 后
  非目录，**按链接自身的 `st_size` 计入文件**（`:58-66` 不做 S_IFLNK 剔除）。
- 形状：`depth < 3` 时任务组并行（`:104-125`，workerLimit = CPU 数 `:44`）。
- 读什么：非目录的 `st_size` 求和 + 计数（`:88-90`），目录不取大小（`:65`）。
- 预算：**它自己不认识 deadline**。`process()` 在 probe 跑完后取剩余时间
  `remaining = deadline - now`（`ProjectArtifactScanner.swift:592-594`），
  用 `Self.bounded(remaining)`（`:595`，实现 `:1102-1114`）竞速：超时返回 nil、
  组收尾时隐式 cancel 掉 stats 内部早退（`FileTreeWalker.swift:78`/`:96`/`:128` 的
  `Task.isCancelled`）。
- 截断语义：超时 → `measured == nil` → 行 `size = nil` 显示"—"
  （`ProjectArtifactScanner.swift:588-606`、`:194-196`）。深度 `>= 20` 转
  `fallbackStats(remainingDepth: 3)`（`FileTreeWalker.swift:42`、`:94-101`），
  实际 23 层以下**静默计 0**（`:139`）；**任何一层 `contentsOfDirectory` 失败都返回空数组、
  静默计 0**（`:49` 的 `try?`，`:72` 注释"访问失败的子目录静默计 0"），单条目 lstat 失败
  静默丢弃（`:58` guard-continue）。

### 1.3 顺带的第三、四次重复

同一个候选目录根本身，`process()` 还各枚举了一遍：判 verdict 的 ownChildren
（`:556`，`canEnumerate` `:555` + `listAllEntries`）与 probe 弹出的第一个目录（`:626`）；
stats 在 `readEntries(path:)` 里又是第三次。也就是说**候选根这一层今天被 readdir 三遍**。
父目录 `listAllEntries(parent)`（`:538`）另算。

### 1.4 只有非嵌套候选付两趟全款

`stats` 只在 `!isNested && readable` 时跑（`:591`，嵌套不量是防重复计数，注释 `:590`）；
probe 对所有可读候选都跑。真正"两趟全遍历"的对象是**非嵌套、判完 verdict、还没早退**的候选。

## 2. 为什么现在是两趟（回答"有没有顺序依赖"）

**没有数据依赖。** probe 的输入只有候选路径与 deadline（`:583`），stats 的输入只有候选
路径与 probe 用剩的 deadline（`:592-596`）；stats 不等 probe 的结论，probe 不等 stats 的
体积，两者结果分别落在 `activity` 与 `size` 两个互不消费的字段上（`:608-613`）。
唯一真实的顺序耦合是**预算的串行消耗**：stats 的 `remaining` 是 probe 花完之后的余额，
并成一趟反而把这个耦合消掉（一趟共享一份预算，见 §3.3）。

那为什么分家？因为**合同不同**，而 stats 的合同是全站的：文件头纪律 2
（`:15-16`）与 `FileTreeWalker.swift:157-160`（`DirectoryMetrics` 注释）明说"同一目录在
清理页与磁盘分析页显示的数字不许互相矛盾"。probe 需要的三个行为——含点条目
（`.venv`/`.bin` 恰恰是目标，`ProjectArtifactScanner.swift:1029-1031` 注释）、无深度限、
读不进必须 fail closed——每一个都违反 stats 的既有口径，塞进共用函数会改动
UserFolderScanner / SystemAnalyzer / InstallerScanner / MMUninstaller 四个消费方的数字。
所以当时在扫描器内部另起了一趟。结论：**并趟不是免费的还原，而是要在"共用口径不动"
的前提下新建一个私有合并口**——这正是下一节的形状。

## 3. 并趟方案与受影响调用方

### 3.1 一次 lstat 够不够？够，但两套集合规则都要保住

两边需要的字段是同一次 `lstat` 已经带回的：`S_IFMT`、`st_size`、`st_mtimespec`。
分歧全在**集合与求和规则**上：

| 维度 | stats/readEntries | activityProbe/listAllEntries | 合并后怎么办 |
|---|---|---|---|
| 点条目 | 整条排除（含不进入其子树）`FileTreeWalker.swift:54` | 枚举、遍历、查 mtime `ProjectArtifactScanner.swift:1082`（保留点条目那条理由在紧邻注释 `:1078-1081`） | 遍历走宽集合（含点目录），但子树带 `counted=false` 继承标志：点目录内部**不计体积**，只供 mtime 判断 |
| 符号链接 | 计为文件、链接自身 st_size 入和（`:58-66` 无 S_IFLNK 分支） | 直接跳过、不进枚举（`:1043`） | 枚举保留它：计体积/计数（stats 侧），不查近期性、不下潜（probe 侧本来见不到它，维持不可见） |
| 深度 | 20 + 3 静默截断（`:42`、`:94-101`、`:139`） | 无上限 | 遍历无上限（保 probe）；超过 23 层的子树停止**计入体积和**并置 `sizeDepthTruncated=true`，数值仍与今天的 stats 逐字节一致 |
| 失败 | 静默计 0（`:49`、`:72`、`:58`） | `.incomplete`（`:627-630`） | 收集 `unreadableDirectories: [String]`（封顶条数，见 §4.2），stats 侧行为**不改**（其它页共用），新字段只服务本项目扫描器 |
| 早退 | 无 | `.recentFileFound` 即返回（`:634`） | 非嵌套候选：不早退（体积必须量完，见 §3.2）；嵌套候选：维持现 probe 原路或带 `needSize=false` 的同一函数 |
| 并行 | depth<3 任务组（`:104-125`） | 串行栈（`:621`） | 沿用 stats 的任务组骨架，把活动累加做成群上的幺半组 |

一句话：**同一趟、两套记账**。字段级合并公式（对每个非目录条目）：
`size`/`fileCount` 累加当且仅当「名字不点开头的链继承 + 深度 ≤20+3 预算内」（与今天的
`readEntries` 完全同集合，符号链接按 readEntries 的既成事实计入）；
`sawRecentFile` 取当且仅当「非符号链接」（与今天的 `listAllEntries` 完全同集合）。
这样合并后的两个输出与两趟各自跑**逐位相等**——这是第 2 步落地要钉的对拍单测（§7）。

### 3.2 早退与量体积互斥，必须按候选分档

今天的成本分布是：久未触碰的候选 = 全趟 probe + 全趟 stats（两趟）；近期在用的候选 =
早退 probe（通常一两层目录）+ 全趟 stats（约一趟半）。嵌套候选 = 只有（可能早退的）probe。
合并后：

- **非嵌套**：一趟全程跑完，体积与活动同时出结论。近期在用的那个"早退红利"没了，
  但换回的是省掉一整趟 stats——净赚（一趟全量 ≤ 早退+全量两趟，恒成立）。
- **嵌套**（`:591` 不量体积的）：只需要活动。要么保留现 `activityProbe` 不动，
  要么给合并口加 `needSize=false` 模式并保留早退。**本轮建议后者**，两趟的分支在
  `process()` 一处（`:577-606`），收敛成一个调用点。
- 进一步的红利（父的全趟覆盖子的子树，子的活动可以直接从父的 `sawRecentFile` 派生）
  要做需要给每层目录记子树最大 mtime，跨行协调复杂、且父子在不同根不同批时不成立——
  **本轮不做**，记在这里免得下轮重新发现。

### 3.3 接口形状

在 `FileTreeWalker`（它是 `internal`，`FileTreeWalker.swift:28`，不跨模块出接口）新增：

```swift
struct SubtreeWalk {                       // 名字随意，形状是重点
    var size: UInt64                       // readEntries 口径之和
    var fileCount: Int
    var sawRecentFile: Bool                // listAllEntries 口径的 mtime 判断
    var unreadableDirectories: [String]    // fail-closed 通道（封顶 8~16 条 + 计数）
    var stopReason: Stop?                  // .deadline / .cancelled / nil=完整跑完
    var sizeDepthTruncated: Bool           // 23 层静默截断的显式化
}
static func walkForArtifact(path: String, deadline: Date, recentThreshold: Date,
                            includeDotEntries: Bool /* 活动侧恒 true */,
                            needSize: Bool) async -> SubtreeWalk
```

`process()` 侧派生（替换 `:577-606` 的三个分支）：
`probe = stopReason != nil || !unreadableDirectories.isEmpty ? .incomplete(带首个路径)
: sawRecentFile ? .recentFileFound : .noRecentFile`；
`size = (stopReason == nil && unreadableDirectories.isEmpty && !isNested) ? walk.size : nil`
——最后这半句是否收紧，见 §4.2 的开放决策。`Self.bounded`（`:1102-1114`）对这条路径
退役：deadline 检查进了 walk 内部（沿用 probe 的每目录检查点 `:623`），
不再需要竞速包装，也就不再出现"stats 白跑一段被丢弃"的浪费。

### 3.4 受影响调用方全名单（grep `FileTreeWalker\.` 逐个点名）

| 文件 | 用到的成员 | 本轮影响 |
|---|---|---|
| `Packages/MMFileScanner/Sources/MMFileScanner/ProjectArtifactScanner.swift` | `Entry`（`:482-498`、`:1033` 返回类型）、`canEnumerate`（`:350`、`:441`、`:520`、`:555`、`:627`）、`modificationDate`（`:576`）、`stats`（`:596`） | **唯一消费者变更**：`:596` 与 `:583` 换成一次 `walkForArtifact`；其余不动 |
| `Packages/MMFileScanner/Sources/MMFileScanner/FileTreeWalker.swift` | `DirectoryMetrics.measure` → `stats`（`:239`） | 不动：`stats` 原样保留 |
| `Packages/MMFileScanner/Sources/MMFileScanner/UserFolderScanner.swift` | `modificationDate`（`:100`、`:131`）、`canEnumerate`（`:102`、`:133`）、`stats`（`:110`、`:139`、`:158`）、`readEntries`（`:150`）、`Stats`（`:156`、`:160`） | 不动 |
| `Packages/MMFileScanner/Sources/MMFileScanner/SystemAnalyzer.swift` | `readEntries`（`:227`）、`Stats`（`:232`、`:236`）、`stats`（`:234`）、`Entry`（`:293`）、`largeFiles`（`:296`）、`fallbackStats`（`:335`）、`modificationDate`（`:341`） | 不动 |
| `Packages/MMFileScanner/Sources/MMFileScanner/InstallerScanner.swift` | `canEnumerate`（`:123`、`:211`）、`readEntries`（`:131`）、`Entry`（`:175`）、`modificationDate`（`:184`）、`stats`（`:212`） | 不动 |
| `Packages/MMUninstaller/Sources/MMUninstaller/UninstallerModel.swift` | 间接经 `DirectoryMetrics.measure`（`:302`、`:312`、`:315`） | 不动 |

也就是说：**只要不动 `Entry`/`Stats`/`readEntries`/`stats` 的签名与语义，波及面
恰好只有 `ProjectArtifactScanner.process()` 一处**。这是把合并做成"新增口"而不是
"改造旧口"的全部理由。

## 4. 失败与截断语义如何合并

### 4.1 现状：两条互不相认的"没出结论"通道

- probe：`.incomplete` → `activity = .unknown(reason)`（`:777-778`），UI 徽章「未确认」
  （`DevArtifactView.swift:1009-1013`）。
- stats：`size == nil` → UI 徽章「读不到」（`DevArtifactView.swift:997-1001`，
  文案自己就写着"读不动**或预算用尽**"——两种事共用一个徽章，靠 reason 文本区分）。
- 根账本：`scan()` 的成案循环只在**每个候选处理前**查 deadline（`:410-414`），
  处理中间超时不会补记 `truncated`；收尾 `honestScanned = walked − (truncated ∪ inaccessible)`
  （`:421-422`）。

### 4.2 §8.6 的矛盾出在哪一行、合并后修在哪一行

`fidelity-cleaner.md` §8.6（`:450-458`）描述的现象：根进了 `scannedRoots`
（`:426`），组里却挂着一行「读不到（预算用尽）」。机制复盘：deadline 恰好落在
**最后一个候选的 `process()` 内部**——`:410` 的前置检查已放行，probe 在 `:623`
撞线给 `.incomplete`、stats 在 `:595` 竞速里输掉给 `nil`，行成了但账没改，
循环接着正常收尾。**读不到 ≠ 这根扫完了**，这个信息今天就丢在 `process()` 返回值里
（`ProjectArtifactScanner.swift:624` 的 reason 字符串是唯一的线索，还和"读不动"混写）。

合并后的修法就一处：`SubtreeWalk.stopReason` 是显式字段，`process()` 把它带出来
（或返回 `(artifact, closed: Bool)`），`scan()` 的成案循环在 `:415` 调用之后补一行判定——
**本轮处理过、且有任一候选因 deadline 没出结论 → 该根进 `truncated`**。
"根扫完 = 每个候选都出了结论"从口径口号变成字段等式：
`root ∈ scannedRoots ⟺ 其全部候选的 walk 返回 stopReason == nil`。
IO 读不进（`unreadableDirectories` 非空但 stopReason==nil）**算出了结论**——
结论就是 fail-closed 的「读不到/protected」，根不必因此截断；这条要与 §8.6 的原案
（"拖过截止线反而多截断"）对齐：只把预算性未完成归入 truncated，不把权限性事实归入。

顺带一个**开放决策**（不并趟也存在，但并趟后有了数据才能修）：今天 stats 对子树内部
"某个目录读不进"是静默计 0 的（`FileTreeWalker.swift:49`、`:72`），所以一行可以显示
一个**偏小的完整数字**。合并后 `unreadableDirectories` 就在返回值里，两个选项：
(a) 维持现状（数字口径与其它页一致，但"量到了"其实没量全）；
(b) 收紧为 size=nil（与 `group` 的"任一没测到整组 nil"规则同向，`:794-799`，代价是
`reclaimableSize` 变小/变 nil）。**本调研倾向 (b) 但它是口径变更，须 owner 拍板**，
且只作用于开发产物页，不改共用 `stats`。

### 4.3 「没扫到」不许混成「没有」——合并后的完整映射表

| 世界发生的事 | 今天的表达 | 合并后的表达 |
|---|---|---|
| 候选完整跑完、无近期文件 | probe `.noRecentFile` + size 有值 | `stopReason=nil, unreadable=[], sawRecent=false` → 同左 |
| 中途超时（activity 侧） | `.incomplete("超时")` → `.unknown` | `stopReason=.deadline` → 同左 + **根进 truncated**（新） |
| 中途超时（size 侧） | `bounded` 竞速输 → size=nil，**原因丢失** | 同一字段，不再有两套竞速 |
| 目录读不进（TCC） | probe `.incomplete("读不动")`；stats 静默计 0 | `unreadableDirectories=[path]`，两路同一来源 |
| 深于 23 层 | stats 静默少加 | `sizeDepthTruncated=true`（显式，数值不变） |
| 嵌套候选 | 只有 probe，size 恒 nil（`:591`、`:236` 注释） | `needSize=false` 的同一趟，早退保留 |

## 5. 收益量级（实测 vs 推算分开标）

**已实测**（P6.1a §2，`dev-artifact-continuation.md:66-73`，开发机 macOS 27.0/arm64）：

- `find ~/Desktop -maxdepth 3 -type d` 0.06 s / 406 目录；`~/Documents` 0.07 s / 1412 目录
  ——发现遍历不是瓶颈。〔实测〕
- 单个 `node_modules` 子树（`Desktop/artisan_heir/node_modules`）40,396 条目，
  `find` 一趟 0.38 s。〔实测，但注意这是 **find 的进程**、非本应用一趟的成本〕
- 两根内产物名目录（深度≤6、不 prune）9,321 个 / 10.4 s。〔实测〕
- P6.1 夹具：首批 76.4 MB → 续扫后 162.8 MB（`feature-roadmap.md:737`）。〔实测，
  证明截断吃在成案/测量阶段——并趟攻击的正是这个阶段的成本〕

**推算**（明确标注依据，无应用内计时）：

- 每个非嵌套久未触碰候选：现成本 = probe 全趟 + stats 全趟（各 ≈ 一次递归 readdir +
  每条目一次 lstat，两趟同集合≈），并趟后 = 一趟 → **测量阶段 syscall 趋近减半**。
  依据：§1 两趟的枚举集合与 syscall 种类（代码事实），非实测。
- 近期在用候选：现成本 ≈ 早退 probe + 全趟 stats，并趟 = 全趟 → 省"早退那零点几趟"，
  方向是省、幅度小。依据：`:634` 早退语义。
- "真机上截断的根很可能就此扫得完"——`dev-artifact-continuation.md:317` 原文就是
  推测语气（"很可能"），**本调研维持为假设**，留待 §7 第 4 步真机取证判定。

## 6. 风险与本轮不做清单

红线（roadmap `:737` D6/D7、`:660-662`，continuation §3.3/§6/§8）：

1. **不做游标/落盘**：合并只是同一批内的函数重构，`SubtreeWalk` 不出 `process()`，
   不新增任何跨批状态。
2. **不做常驻/自动循环/预算递加**（D3/D7）：15/60 不动；attemptCounts 仍在内存。
3. **不改共用 `stats`/`readEntries`/`DirectoryMetrics` 的语义**——§3.4 名单里其它
   五处消费方零改动，这是本方案与"直接给 stats 加 mtime"（continuation §8 提过的
   另一条路）的关键区别：后者会牵动跨模块口径一致性（`FileTreeWalker.swift:157-160`）。
4. **不顺手改 verdict/嵌套判定/删除链路**：`verdict`、`nestedFlags`、`DeletionGuard`、
   `FileTrashService` 一概不碰；本调研连 §4.2(b) 的 size 收紧都只列为待拍板选项〔**P41 更新**：那条已于 P41 按 (b) 落地，见 §7 第 5 条与 `docs/verification/p41-nil-size/`〕。
5. **不把 probe 的早退在嵌套/无体积需求路径上改掉**（§3.2）——那会让"近期在用的大
   嵌套目录"从近免费变全量。
6. **不做父遍历结果复用给嵌套子候选**的子树最大 mtime 传播（§3.2 末），收益真实但
   跨行协调是另一个量级的正确性风险，独立提案。
7. **不引入 `resourceValues`/第二套字段读取**：保持"单次 lstat"是全仓度量口径
   （`FileTreeWalker.swift:26-27`、`ProjectArtifactScanner.swift:1029-1032`）。
8. 最大单点风险：**对拍不等价**。两套集合规则（点条目、符号链接）任何一处理解偏了，
   表现是同一目录在开发产物页与磁盘页数字开始互相矛盾——正是文件头纪律 2 明令的事故
   口径。所以 §7 第 2 步的"双跑对拍"是硬闸，不是可选项。

## 7. 建议的落地切分（每步可单独验证）

1. **纯函数面先行**：定义 `SubtreeWalk` + 派生函数（`SubtreeWalk → (size?, ActivityProbe)`、
   `stopReason → root 账本动作`），单测打纯派生表（§4.3 的六行就是六个用例）。
   验证：`swift test` 全绿，无 IO。
2. **合并口 + 双跑对拍**：`FileTreeWalker` 新增 `walkForArtifact`（任务组骨架从
   `stats` 复制改造），集成测试在 `Scripts/purge-fixture.sh` 类夹具（含点目录、
   符号链接、深目录、chmod 000 子目录）上断言
   `walkForArtifact == (stats(path:).size, stats(path:).fileCount, 现 activityProbe 结果)`
   逐字段相等；同时记录两趟 vs 一趟的耗时比（这才有 §5 欠的应用内实测数）。
   验证：对拍测试 + 一份计时样本；现网行为零变化（还没接线）。
3. **接线 `process()` + 修 §8.6 收尾**：替换 `:577-606`；`scan()` 循环补
   "行内超时 → 根进 truncated"（§4.2），并加不变式单测：
   `root ∈ scannedRoots ⇒ 该根所有非嵌套行 isCompleteObservation 或结论为读不到(非预算)`。
   验证：现有 `ProjectArtifactScannerTests`（`testRootDeadlineTakesTheEarlierOfTwoBudgets`、
   mergedReport 五连、`testIsCompleteObservationIsTheReuseGate` 等）不改动即全绿 + 新用例。
4. **取证**：用已有钩子 `MM_DEV_ROOT_BUDGET_SECONDS`（`hook-ledger.md`，
   continuation §7.3 的 `0.05` 小预算档）拍"截断→续扫→收尾"三态，验证 §8.6 的矛盾组合
   （已扫完 + 读不到(预算用尽)）在照片里不可能再同屏；真机 `~/Desktop`/`~/Documents`
   各跑一次全量与 P6.1a §2 数字对照。
5. **§4.2(b) 的 unreadable→size=nil 收紧**（**P41 已落地**，原标"待拍板，独立提交"）与 UI 文案联动
   （`DevArtifactView.swift:585-587`「其余 N 个根已扫完」的计数可能因修复而变小——
   这是更诚实，不是回归，但要在文案评审里点名）。

## 8. 本轮没能验证的部分（逐条列缺什么）

- **应用内两趟各自的真实耗时**：没跑任何 build/test/计时（任务硬约束）。缺第 2 步的
  双跑对拍样本；§5 的"趋近减半"只有 syscall 数推算，缺墙钟证据。
- **符号链接计体积的口径差在真树上的影响**：`readEntries` 把符号链接按链接字节计入
  size/count、`listAllEntries` 完全跳过（`FileTreeWalker.swift:58-66` vs
  `ProjectArtifactScanner.swift:1091-1092`），理论上合并要保持两套记账，但没造夹具实测
  node_modules 里 `.bin` 这类链接密集目录的差值幅度。缺一个含大量链接的夹具对拍。
- **深度 23 层的静默截断**：由 `:42`、`:94-101`、`:139` 的代码阅读推得，
  没构造 >23 层目录实测 stats 的实际丢漏。
- **`:627` 的"存在但列不出"判定**（`directoryExists`+`canEnumerate` 两次 stat，
  有 TOCTOU 窗口且 `canEnumerate` 内部又枚举一遍）：合并后 probe 趟消失，这个检查
  随 walk 的 readdir 错误自然合并，但真 TCC 拒绝场景本轮无法取证（无授权弹窗自动化）。
- **合并后"截断根一趟扫得完"是否成立**：continuation §9 已声明真机可能拍不到，
  本调研同样只能留作假设，需第 4 步真机取证。
- **§4.2(b) 收紧对 `reclaimableSize`/UI 的连带影响**：没算过真机上有多少行会从有数字
  变"—"。缺第 2 步夹具里对 unreadable 子目录的行数统计。〔**P41 补量**：只读探针 `Scripts/p41-nil-size-probe.sh` 已在本机量过，
  结论是**可测 7 行里新翻 nil 0 行、新翻 nil 的群 0 个**（日志 `docs/verification/p41-nil-size/nil-size.log`，repo `87a3e69`）；
  探针的 deadline 比真扫描宽裕，所以这是**影响面的上界**，不是恒等于 0 的承诺。UI 文案「其余 N 个根已扫完」因此本机不变。〕
- **UI 侧「已扫完」计数变化是否要改文案**（第 5 步）：没和产品设计口径对过，属待拍板。
