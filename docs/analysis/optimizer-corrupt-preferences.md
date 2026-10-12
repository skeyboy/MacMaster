# 优化页「损坏偏好文件检测」审计（P34a，2026-10-12）

**范围**：v1.1 四条里的第 3 条（`docs/analysis/feature-roadmap.md:1039` 那一格）——
`~/Library/Preferences` 里的 plist「损坏」检测，只报位置与建议、不代删。
**本轮只审计，生产代码一行未动**；改动集中在两支取证探针（`Scripts/p34a-prefs-plist-probe.sh`
与它的 Swift 主体）和两份证据日志。

一句话结论：**这一族的真实故障率在本机是零，而它最容易被写成假话的那一处恰恰是"读不到"**。
本轮把四态判据的边界量到了可以直接写文案合同的程度，也把"要不要开第五个 tab"变成一个人能拍的问题。

---

## 1. 本轮量了什么

两支探针，同一条采集路径（`collect(prefs:_:)`，`Scripts/p34a-prefs-plist-probe.swift:53`）：

| 档 | 命令 | 证据 | 问的是 |
|---|---|---|---|
| 真 home | `./Scripts/p34a-prefs-plist-probe.sh` | `docs/verification/p34a-prefs/prefs-plist.log` | 本机这一族到底是什么构成 |
| 夹具 | `./Scripts/p34a-prefs-plist-probe.sh --synthetic` | `docs/verification/p34a-prefs/synth-cases.log` | 我们的判据会不会把好文件说成坏的 |

两份日志的 `# digest:` 都是 `2a78491+e3b0c442`，即探针不参与编译输入、提交前后指纹一致
（`Scripts/mm-provenance.sh` 那套配方；`Scripts/` 与 `docs/` 不进指纹）。

**为什么必须先有夹具那一档**：真机上 625 条里 0 条解析失败（下面的账），
所以"判据会不会误报"这个问题**在真 home 上问不出来**——只有把已知答案的样本摆在面前才量得出来。
这句话写进探针自己的注释（`p34a-prefs-plist-probe.swift:91-93`），是因为它是这一轮的方法论，
不是随手解释。

## 2. 真机现状账（现读自 `prefs-plist.log`）

```
扫到的 .plist 条数=625
解析成功=614  0 字节=0  解析失败=0  读不到=11
格式分布: binary=613 xml=1
根对象分布: dict=614
```

把 625 拆干净（都是同一份日志里的数，减法是本轮做的）：

| 分层 | 条数 | 说明 |
|---|---|---|
| 受保护名（`com.apple.*` / `.GlobalPreferences*` / `loginwindow.plist`） | 407 | 与 Mole 的保护名单同一族，见 `docs/github-references/Mole/lib/optimize/maintenance.sh:7-23` |
| ├ 其中"读不到" | **11** | **全部**是受保护名——非 Apple 的那 218 条里一条都没有 |
| 非受保护名 | 218 | |
| ├ 我们自己单测留下的（名字含 `Tests`） | 91 | 合计 3,822 字节，见 §7 |
| └ 第三方真实偏好文件 | 127 | 这 127 条里 **0 条**读不到、0 条 0 字节、0 条解析失败 |

三种"看起来坏"里，真机上只有 `解析成功=614` 与 `读不到=11` 两栏非零；
`0 字节`、`解析失败`、`解析成功但根不是字典` 三栏都是 0。

**所以这一族在本机上的用户可见答案是"没有发现"**。任何实现都不能把这句话写成
"你的偏好文件都是健康的"——它只说明**这一台机器、这一个判据**下没抓到，
见 §5 的文案合同与 §11 的否证。

## 3. 「读不到」这一栏的归因（本轮把它和"损坏"分开了）

日志里那 11 条的两句原文是同一次拒绝的两个转写：

```
plutil="(The file "com.apple.TV.plist" couldn't be opened because you don't have permission to view it.)"
Foundation=读不到 Cocoa 257：…
```

Cocoa 257 是"没有权限"那一类，字面上像 POSIX 权限。本轮当场核了那几条的权限位与属主：

```
-rw-------@ 1 lee  staff  2214 Sep 16 com.apple.TV.plist
```

属主就是当前用户、模式 0600——**POSIX 层面是允许读的**，所以挡住它的不是权限位。
换成 shell 直接读也一样被拒：

```
$ dd if=Library/Messages/chat.db …  → dd: …: Operation not permitted
```

结论写到本轮敢写的程度：这一栏是 macOS 的**按文件保护**（data vault / TCC 那一类），
errno 是 `Operation not permitted`；而跑探针的这个 shell **没有完全磁盘访问**
（`chat.db` 同一句拒绝是旁证）。**"给了 FDA 的进程能不能读到这 11 条"本轮没有量**，
所以 §11 把它列成 P34b 的第一个待测项——它决定界面那句"这 11 个我们没看"在别的机器上会不会变成
"这 11 个是坏的"。

要紧的设计含义只有一句：**「读不到」不是「损坏」，也不许在界面上共用一个图标**。
它就是这一族最容易犯的假话，而真机上它恰好是唯一的非零异常栏。

## 4. 判据边界：夹具 12 条与两把尺子的对读

`synth-cases.log` 的 12 条（期望是造之前写死的，跑回来对）：

| 样本 | bytes | Foundation | plutil | 这一条问的是 |
|---|---|---|---|---|
| valid-binary / valid-xml / valid-openstep | 86 / 302 / 52 | 正常 | OK | 三种格式都能读吗 |
| empty-dict | 42 | 正常 | OK | 空字典 ≠ 空文件 |
| root-array / root-string | 50 / 204 | 正常但根不是字典 | OK | 根类型算不算故障 |
| zero-byte | 0 | 0 字节 | Cannot parse a NULL or zero-length data | 半路创建的 0 字文件 |
| truncated-binary | 12 | 解析失败 | Unexpected character b | 截断 |
| xml-unclosed | 282 | 解析失败 | Encountered unexpected EOF | 截尾的 XML |
| garbage-text | 43 | 解析失败 | Unexpected character è | 根本不是 plist |
| perm-000 | 86 | 读不到 | 没有权限 | 真·权限问题（000） |
| ByHost/byhost-truncated | 8 | **正常但根不是字典** | **OK** | 只有魔数的文件 |

两个读数：`与期望一致=12 不一致=0`；`Foundation 与 plutil 判「异常/不异常」分开的条数=0`。

三条从量里出来的、不是查来的：

1. **两种判据在这 12 条上完全不分家**。所以约束里"生产不 spawn `plutil`"（`feature-roadmap.md:1039`
   那一格的后半句）**不会让我们看得更少**——用 `PropertyListSerialization` 不欠账。
2. **只有 8 字节的 `bplist00`（魔数本身，后面什么都没有）两把尺子都说"正常"**：
   `plutil -lint` 给 OK，Foundation 把它当 **openStep** 解析出一个非字典根。
   如果界面把"根不是字典"算成损坏，就造出一条**对照判据不认的假故障**。
   这条实测直接写进了 `isBad` 的注释（`p34a-prefs-plist-probe.swift:187-190`），
   它不在"有问题"那一栏里。
3. **`PropertyListSerialization` 能读 openStep，但不能写 openStep**——造夹具时 `try!` 直接打死探针：
   `kCFPropertyListOpenStepFormat not supported for writing`。
   我们这一族只读，所以不受影响；但**任何"顺手写一份回去"的想法都会撞上它**（§10 第 3 条）。

`kind()` 把四态渲染成四个词（`p34a-prefs-plist-probe.swift:198-205`）：
读不到 / 0 字节 / 解析失败 / 正常（含"正常但根不是字典"这一支）。
`isBad` 取的是前三者（`:191-196`）——注意它的语义是**"要不要占那一栏"**，
不是"是不是坏了"；§5 的分档就是把这一栏再劈开。

## 5. 四态在界面上各自怎么说（建议的文案合同）

| 态 | 界面位置 | 允许说 | 禁止说 |
|---|---|---|---|
| 解析成功 | 不列行，只进"检查过 N 个"的计数 | — | 任何"修复/健康"式表扬 |
| 正常但根不是字典 | 不列行（`isBad` 不含它） | 若要提，只能在脚注说"有些文件的根不是字典，两种判据都不认为这是坏" | "损坏" |
| 0 字节 | 列行，档「可能是写到一半」 | "这个文件是空的，可能是上次写入中断" | "已损坏，建议删除" |
| 解析失败 | 列行，档「读不成字典」 | "这份偏好文件读不出来。要恢复它得由那个 app 自己做（重设它的偏好），MacMaster 不动它。" | 任何"我们修好了" |
| 读不到 | **单独一栏**，档「这一族我们没看到」 | "系统对 N 个文件拒绝读取（属主是你、权限位允许），这不代表它们坏了，也不代表它们没坏。" | 与"损坏"共用图标/文案 |

**主人名与建议去哪**：进 `caveat`，不进 `reason`。这一族的结构可以直接套
`DevToolCacheEntry`（`DevToolCacheAudit.swift:37-69`）——它的 `caveat` 字段本来就是给
"这条为什么不能当成结论"准备的（`:51` 那句注释说得很清楚），而 `presence` 的
`.unreadable(reason:)`（`:31-34`）正是"读不到 ≠ 没有"这一族的现成先例。

## 6. 参考实现教我们的两件事（它和我们做的不是同一件事）

Mole 那一支的完整形状：`docs/github-references/Mole/lib/optimize/maintenance.sh:97` 定
`~/Library/Preferences`，顶层 maxdepth 1、`ByHost` 递归；保护名单在 `docs/github-references/Mole/lib/optimize/maintenance.sh:7-23`；批量 lint 在 `:69`，
坏的那一批再逐条 fallback 判保护/白名单，然后 **`safe_remove "$candidate" true`（`:82`）真的删掉**；
对外那句在 `docs/github-references/Mole/lib/optimize/tasks.sh:407` `Repaired $broken_prefs corrupted preference files`。

- **它的卖点是"删"，我们这一条被约束成"只报"**。这不是我们弱一档，而是**两件事**：
  删掉一个数据损坏的偏好文件确实会让 app 下次启动重设偏好（Mole 在 `tasks.sh:379`
  写的 Expected outcome 就是这个），而这是一种我们没有主张过的权力
  （同 P31a 对"结束进程"的处置：`feature-roadmap.md:1179`）。
  **只报的那一半价值有限**——这是 §9 里 C 档存在的理由，不回避。
- **Mole 自己的注释承认了本机量到的现象**：`maintenance.sh:48`
  "Preferences dirs can hold tens of thousands of plists (leaky test suites write one per run)"。
  §7 那 91 条就是它说的那一类，只是我们 leak 得比"成千上万"轻。
  它的应对不是清理，是**时间预算**：`maintenance.sh:59` 一个 15 秒 deadline，
  超了就 `return "$partial"`，调用方把话改成"scan hit its time budget, repaired N so far"
  （`tasks.sh:405`、`:410`）。**"扫不完"必须是一句能被说出来的话，不是静默少报**——
  这条我们照抄语义（§9 B 档），不抄实现。

## 7. 这一族里我们自己的那份账

`prefs-plist.log` 最后一段：`条数=91 合计字节=3822`，逐条都是 42 字节的
`MMCoreTests-<UUID>.plist` 与 `MMCleaner.ExclusionStoreTests.<UUID>.plist`，mtime 铺在 09-29 到 10-09。

这不是新发现，是**认过账的**：`Packages/MMCleaner/Tests/MMCleanerTests/CleanerExclusionStoreTests.swift:13`
起那一段注释写的就是"要验证真落盘必然要付的账"——`removePersistentDomain` 能把内容清成
42 字节的空域，但删不掉文件本身；cfprefsd 会为每次 XCTest 运行留一个 `<suite>.<uuid>.plist`。

对本轮的两个影响：
1. **它不进界面**：这些是"读得懂的空字典"，`解析成功=614` 那栏里就包括它们；
2. **它是判据的一个真实干扰项**：91/625 ≈ 15% 的条目是我们的测试产物。
   任何"按 bundle 名找主人"的映射（§9 C 档）都会先撞上一堆没有主人的名字——
   卸载模块的反向扫描已经有先例：末段是 UUID 的名字当实例产物，不当应用标识
   （`CleanerExclusionStoreTests.swift:17` 那句）。

§2 那句 218 − 91 = 127 的减法依赖"这 91 条全在非受保护名那一侧"，本轮当场核了：
顶层名字含 `Tests` 的 `.plist` 91 条（ByHost 一条没有），而 `com.apple.*` 里名字含 `Tests` 的
**0 条**——两个集合不重叠，减法成立。

## 8. 代价：这轮量到的时间，和没量到的部分

`Foundation 一趟（枚举+读取+解析，不含 plutil 对照）耗时=226 ms`，625 条。

- 这是**平均 0.36 ms/条**，但**不能拿去外推**：一条 42 字节的空域和一条 11 KB 的 MobileSMS 不是一个价，
  而本轮**没有把枚举、读取、解析拆开计时**。写实现时若要用"预计 N 秒"这类话，得先补这一刀。
- Mole 那句"tens of thousands"不是危言：本机 91 条是我们自己造的，别的机器上跑过多年 XCTest/
  第三方安装器的域完全可能上千到上万条。**所以预算 + partial 是必需项，不是加分项**（§9 B 档）。
- 读全量 plist 的内存代价本轮也没量。`.mappedIfSafe`（`p34a-prefs-plist-probe.swift:227`）
  是探针的做法，实现照做即可，但**别据此主张"低内存"**。

## 9. 呈现落点：三档建议

`OptimizerTab` 现在是四个 case（`MMOptimizer.swift:264-265`，`id` 与 `hookKey` 都取 `rawValue`），
`MM_OPEN_TAB` 逐 tab 触发截图（`:41`）。`v1.1` 那一格已经定了方向：**新 tab 复用开发工具页版式**。

- **A 档（推荐，判据 + 呈现的最小闭环）**
  第五个 tab `preferences`；纯判定层照 `DevToolCacheAuditor.entries(env:home:presenceProbe:sizeProbe:toolProbe:)`
  的**全注入**形状（`DevToolCacheAudit.swift:99`）——环境、home、四个探针都能替，所以判据那 12 条
  能在单测里逐条钉死（§4 的矩阵直接搬进 `XCTAssertEqual`）；视图层照 `DevToolCacheRow`
  （`DevToolCacheView.swift:90`）一行一条，`caveat` 承载主人名与建议；
  夹具钩子照 `devtools:unreadable` 的先例（`OptimizerFixtureHooks.swift:111-112`）加
  `prefs:broken` / `prefs:unreadable` / `prefs:empty` 三档，**"读不到"那一栏必须能拍到**，
  因为真机上它是唯一非零的异常栏，也是唯一会被写错的一栏。
- **B 档 = A + 预算与截断态**：时间预算（数值由 P34b 现量，不抄 Mole 的 15 秒）+
  `partial` 标记 + 页头那句"检查到 N 个就停了，剩下的没看"。
- **C 档 = B + 主人名映射**：把 bundle id 对到已装应用清单，给"这条属于哪个 app"。
  **建议暂缓**：§7 那 91 条无主人名字先撞进来，而映射错的主人名比不写名字更伤信任
  （P33a 那轮的教训正是"看起来对归属"会跨应用收东西）。

**推荐：A 档照做，B 档的预算与 partial 是必需项一起进 A，C 档另开一轮。**
理由：本轮证据说明这一屏大多数时候是空的；空屏的代价不是"没活干"，
而是**照片必须由夹具出**（真机档只能拍到"检查过 625 个，没有发现"+ 那一栏"读不到"）。
这一条要写进 `fidelity-optimizer.md` 的验收项，别到取证那轮才发现拍不到。

## 10. 明确不做

1. **不删、不改名、不 `defaults delete`**——v1.1 §2 那一格的"不代删"照字面执行；
   Mole 的 `safe_remove` 那一半我们**不做**，不是"以后做"。
2. **不为此 spawn `plutil`**。本轮对读证明少看了不存在的那一类（§4 第 1 条），所以这条约束不欠账。
3. **不写任何偏好文件**。openStep 写不出去（§4 第 3 条），而"备份一份再改"的整个思路在这一族
   没有任何正当用途。
4. **不请求 FDA**，不为这一族加 TCC 弹窗（v1.1 四条的前提就是零新权限，`feature-roadmap.md:1033`）。
   读不到就说读不到。
5. **不碰 `~/Library/Containers/*/Library/Preferences`**。沙盒应用的那一份在 `~/Library/Containers` 下
   另有目录，本轮一条都没扫；它是不是同一族语义（损坏的后果、保护名单、谁的主人）都没量过，
   排到后议，别顺手扩进来。
6. **不把 `.GlobalPreferences.plist` 当特殊文件处理**：本轮它就是 407 条受保护名里的一员，
   没有单独量过它的行为，别写只针对它的规则。

## 11. 本轮没能确认的（P34b 先问这几句）

1. **GUI 起的那个 `.app`（非沙盒、ad-hoc 签名）读这 11 条是什么答复**——本轮的数来自一个没有
   FDA 的 shell。若 GUI 进程能看到更多/更少，§5 那句"N 个我们没看到"的 N 就不是本机那个 11。
2. **给了 FDA 的进程读不读得到 data vault 里那些文件**（§3 末句）。这决定"读不到"这一栏的
   语义是"系统不给看"还是"我们可以选择不去看"。
3. **枚举/读取/解析三段的耗时拆分**（§8），以及上千条时的形状——预算数值要由它给。
4. **ByHost 递归的真实深度**：本轮跟 Mole 一样递归（`p34a-prefs-plist-probe.swift:68-79`），
   但没统计过这一层在本机贡献了多少条，也没量过有没有环/软链。
5. **别的机器**：Mac mini 之外没有第二台可测（同 `feature-roadmap.md:1094` 那条限制）。
   0 故障是本机的数，不是产品承诺。

## 12. 给 P34b 的检查单

1. 纯函数层：`Verdict` 四态 + `isBad`（不含非字典根）搬进 `MMOptimizer`，12 条夹具等价物进单测；
   **注入形状照 `entries(env:home:presenceProbe:sizeProbe:toolProbe:)`（`DevToolCacheAudit.swift:99`），
   不要读 env 的假系统快照**——判据读的是文件系统状态，合成值只能证明界面会写字，
   证明不了写的是真话（P31a 为运行状态写的就是这一句，`docs/analysis/feature-roadmap.md:1110-1111`）。
2. 呈现层：第五 tab + `caveat` 承载建议；文案照 §5 那张表逐行落，
   **"读不到"独立成栏且不与"损坏"共用图标**。
3. 预算 + `partial`：数值现量现写，页头一句话。
4. 钩子：`prefs:broken` / `prefs:unreadable` / `prefs:empty` 三档 + 非法取值整个作废的老铁律
   （`OptimizerFixtureHooks.swift:7-11`）。
5. 照片：夹具档出"有内容"那几屏，真机档只许拍"检查过 N 个 + 读不到 M 个"；
   设计稿 `08-optimizer.html` 要同步加第五 tab，否则下一轮会拿旧稿当规格（§8 那条老风险）。
6. 九包重跑 + 引用门禁 + `# digest:` 当场同源（v1.1 那四条共用的验收不变量，
   `feature-roadmap.md:1081-1090`）。

## 13. 证据、命令与门禁

| 文件 | 行数 | 怎么再跑 |
|---|---|---|
| `Scripts/p34a-prefs-plist-probe.sh` | 83 | 入口；`--stdout` 只打终端，`--synthetic` 走夹具档 |
| `Scripts/p34a-prefs-plist-probe.swift` | 437 | 单文件编译，**不链任何生产源文件**（所以它测的是 Foundation 与本机文件系统，不是我们的代码） |
| `docs/verification/p34a-prefs/prefs-plist.log` | 62 | `./Scripts/p34a-prefs-plist-probe.sh` |
| `docs/verification/p34a-prefs/synth-cases.log` | 26 | `./Scripts/p34a-prefs-plist-probe.sh --synthetic` |
| `docs/verification/p34a-citations/audit.log` | 181 | `./Scripts/p16-citation-audit.sh docs/verification/p34a-citations` |

两份探针日志的 `# digest:` 都是 `2a78491+e3b0c442`，`# repo:` 是 `2a78491`（不带 `-dirty`，
因为脚本按 `git status --porcelain -uno` 只看跟踪文件，本轮那五个新文件还没进 HEAD 时就已经是干净的）。
后半截 `e3b0c442` 是**空输入那把哈希的前缀**——`Scripts/` 与 `docs/` 都不进编译输入，
所以"工作树里没有任何未提交的编译输入"这句话在这一跑里是真的；
它同时是"代码一行未动"的机械证明（本轮一个新源文件都没添）。

引用门禁本轮读数（现读自上面那份 `audit.log`，**跑在 `git add` 之后**，v1.1 §7 第 4 条）：
引用条次 1007、唯一「路径+行段」834、命本仓库 735、命参考仓库 98（Mole 41）、命苹果 SDK 头文件 1、
两头都不到 0、行号越界 0、整段空白 0、同一条路径命中两个文件 0、**硬失败 0**（`exit 0`）；
索引 1128、词汇表 8309、入库 .md 40 篇且 40 篇真抽到。

与上一轮那份（P33b 的 `docs/verification/p33b-citations/audit-postcommit.log`）逐项对差：
条次 +31、唯一面 +29、命本仓库 +22、命参考仓库 +7、SDK 头文件 1 → 1；
四道硬判据**逐个仍是 0**。只提示那两层：**死符号仍是 0**，**位置存疑 126 → 127**——
多的那一条是本轮在路线表格第三格里新加的那处引用（引的是登录项实现里那条"定点读一个文件"的
路径字面量），而门禁按整句点名的符号是 `PropertyListSerialization`，它落在同一文件的另外两行上。
**引用没说错，是软层按句子抓符号的那一层松**；我没有为了让它归零去把引用挪走。

索引 1121 → 1128 那 7 个：1 个是 P33b 自己的 `audit-postcommit.log` 在 `2a78491` 里进了 HEAD，
其余 6 个是本轮新入库的——两支探针、两份探针日志、这一份文档，**以及这一份门禁日志自己**
（这也是为什么它的行数不登记在这里：下一跑它会把自己写长）。

**本轮没有重跑九包**，理由是上面那句 `e3b0c442`：编译输入与 HEAD 逐字节一致，
而 HEAD 那份的结论行已经入库——`docs/verification/p33b-citations/run-all-tests.log:38`
「合计：720 个测试，0 个失败，1 个跳过」描述的仍是当前这棵树。
一旦 P34b 动 `Packages/MMOptimizer`，这一句立刻作废，那时要重跑并另立结论行。

提交后同族又跑了一次并归位成 `docs/verification/p34a-citations/audit-postcommit.log`
（换目录再改名，没覆盖提交前那一份，照 `f7bca94` 立的那条规矩）。
两份 `diff` 出来**只有 `# date:` 与 `# repo:` 两行**，181 行对 181 行，
六个业务读数（条次 / 唯一面 / 命本仓库 / 死符号 / 位置存疑 / 硬失败）逐字相同。
这一份的 `# repo:` 是 `b073aa4`，**不带 `-dirty`**——与 P33b 那一份不同：那一轮的提交后跑
头上还挂着"文档未提交"，所以它当不了"工作树干净"的自证，本轮这一份能当。
本轮不再给"提交换出处、不换判据"这句话数序：同一句在旧文档里已经被数成过互不相容的几个序数，
再加一个只会多一笔没人能复核的账。
