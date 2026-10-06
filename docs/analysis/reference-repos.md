# 参考仓库清单（reference repos：从哪儿取、钉在哪个 commit）

**这份文件解决的是 §8 那条账**：`.gitignore` 把 `docs/github-references/`、`docs/Mole/`、
`docs/lemon-cleaner/` 排掉了（各自带独立 `.git` 与许可证，不纳入本仓库），
而 `docs/analysis/*.md` 里有**按那些路径写的逐行引用**。别人 clone 本仓库之后，
`.gitignore` 里那三个目录是空的，那些引用就再也打不开——写的人知道去哪儿取，读的人不知道。

P16 把这件事变成了数，并把取法钉在 commit 上：

```
./Scripts/p16-citation-audit.sh
```

这一条命令扫全部入库 `.md`（本轮 31 份，报告里 `# docs scanned:` 会把"真抽了几个"和
"入库几个"两个数都打出来），抽出每一处 `路径:行号` 引用，逐条去三个索引里定位。
**本文里所有计数都由它产出，不要抄**（同一支脚本自产的数字一旦被手写进注释就开始漂，
这条在 P15 已经中过一次；本轮自己又应验一次：下表改到第三遍才和 audit.log 对上）。

## 1. 本轮实测的分布

P16 收口那一跑（`docs/verification/p16-citations/audit.log`，本机 2026-10-06）：

| 计数 | 值 | 含义 |
| --- | --- | --- |
| 引用条次 | 645 | 同一处再引一次也计 |
| 唯一「路径+行段」 | 545 | 去重后逐条判的单元 |
| 命本仓库 | 487 | clone 之后直接可打开 |
| 命参考仓库 | 57 | **clone 之后一律打不开**，要靠下面第 2 节 |
| 命苹果 SDK 头文件 | 1 | 见第 4 节 |
| 都不到 | 0 | 路径写错了；本轮清掉 5 处（第 3 节） |
| 行号越界 / 落在空行 | 0 / 0 | 早期那一跑是 1 处越界 + 11 处整段空白，都在这轮改掉了 |
| 符号面·死符号 / 位置存疑 | 0 / 96 | **只提示，不进退出码**；判据与它的盲区见 `release-readiness.md` §7.7 |

57 处按仓库分：`Mole` / `Pearcleaner` / `OverSight` / `disktree` / `stats` / `lemon-cleaner` 各有若干，
`SwiftFormat` 一份都被 clone 了却**零处逐行引用**（引它的时候只说结论，没给行号）。
分仓库的准确数字看 `.log` 里 `#     <仓库名>: N` 那几行。

## 2. 六个参考仓库与钉住的 commit

**引用里的行号只在这些 commit 上成立。** 这一列不是装饰：`Pearcleaner` 里 `AVMonitor.m` 这种
几百行的文件，上游动一次，行号全线漂。换 commit 之后要重跑 `./Scripts/p16-citation-audit.sh`，
它会把越界与空行的那一批点名出来。

| 项目 | 上游 | 钉住的 commit（提交日） | 本地路径 | 许可证 |
| --- | --- | --- | --- | --- |
| Mole | `https://github.com/tw93/Mole.git` | `f32fa0c6b082ed76705cbc45f2c42169a09e2503`（2026-09-28） | `docs/github-references/Mole` | GPL-3.0 |
| Pearcleaner | `https://github.com/alienator88/Pearcleaner.git` | `7724df7111bff82ae243301cf701992ef05ecf19`（2026-06-22） | `docs/github-references/Pearcleaner` | Apache-2.0 **+ Commons Clause**（不许拿去卖） |
| OverSight | `https://github.com/objective-see/OverSight.git` | `58e4a643a32018b861d378ac8b51f4662328f5af`（2024-09-24） | `docs/github-references/OverSight` | GPL-3.0 |
| disktree | `https://github.com/tobi/disktree.git` | `158f9cc2f0b332194a3ffc5acec47760c99146d8`（2026-09-26） | `docs/github-references/disktree` | MIT |
| stats | `https://github.com/exelban/stats.git` | `e888802a4efce288576f2817ab381b4d31bcb7a1`（2026-09-28） | `docs/github-references/stats` | MIT |
| SwiftFormat | `https://github.com/nicklockwood/SwiftFormat.git` | `173d2cb252474cd8e8baeaf13636f5d565408ec9`（2026-09-16） | `docs/github-references/SwiftFormat` | MIT |
| lemon-cleaner | `https://github.com/Tencent/lemon-cleaner.git` | `7ff8676f1dbe624b039f6b5d50ca81b50963629e`（2026-05-08） | `docs/lemon-cleaner` | GPL-3.0（`LICENSE.txt`）；`LemonCleaner/LemonDaemon` 另见 `LICENSE_LemonCleaner_LemonDaemon.txt`（GPL-2.0） |

取法（在仓库根执行；`checkout` 那一步是把工作树钉回上表那一行）：

```
git clone --depth 1 https://github.com/tw93/Mole.git docs/github-references/Mole
cd docs/github-references/Mole && git fetch --unshallow origin && git checkout f32fa0c6b082ed76705cbc45f2c42169a09e2503
```

其余六个照这一条换 URL 与 commit。这些目录**只在分析参考实现时临时存在**，
不进版本控制，也不随产物分发——所以它们的 GPL/Apache/Commons Clause 义务没有被触发：
本项目没有复制它们的代码（各份 `docs/analysis/*.md` 的结论都写的是"实现独立"），
分发时也没有附带它们。若将来真的引了某一段源代码，这张表要连同许可证义务一起重看。

## 3. 写引用的三条口径（本轮定下，由脚本判）

1. **路径相对各仓库根**：`lib/clean/apps.sh:151` 指 `docs/github-references/Mole/lib/clean/apps.sh`。
   本仓库的引用写完整路径（`Packages/MMCore/Sources/MMCore/CommandRunner.swift:51`）。
2. **同名文件必须带目录**。本轮抓到的实锤：`apps-watch.md` 原文写 `main.swift:58`，而
   Pearcleaner 里有**两个** `main.swift`（`PearcleanerSentinel/` 与 `PearcleanerHelper/`），
   正确那一份是 Sentinel。"行号在不在文件里"这一条判据抓不出这种错——落错文件的那一行
   恰好也是非空行。**这就是为什么脚本单独把"同一条路径命中两个文件"计一项。**
3. **行号是易腐的**。脚本点名的 5 条唯一引用（分布在 4 句文档里）**都不是"行号漂了一格"，
   而是路径本身不存在**：
   DeepLink 在 `Logic/` 而文档写 `Views/`、FilesView 在 `Views/FilesView/` 而文档写 `Views/Files/`、
   `ReversePathsFetch.swift` 不在 `Logic/ZombieScanner/` 这一层、`McSoftwareFileScanner.m` 被写成了
   带省略号的 `QMCoreFunction/…/`（省略号让人和脚本都到不了那个文件）。
   顺带被这一跑牵出来的是同一句里的另一件事：`ReversePathsFetch.swift` 那句话引的
   `currentPaths`/`currentBundleIds` 两个标识符在整个 Pearcleaner 里 grep 不到
   （`count >= 5` 是真的，位置在 `:232`）——**它落进了"路径存在、说法不成立"这一类，
   脚本抓不到，是本轮人工复核那一条时读出来的**。
   这几处的改法与复核记录在 `docs/analysis/apps-watch.md` 的表下注与 `fidelity-guardian.md`。
4. **记"某个位置已经失效"时，别让文件名、冒号、行号连成一串**。抽取器不读语义：一句
   "本文此前记的那一行已经没了"如果按常规写法带上 `文件名 + 冒号 + 数字`，就会被当成一条真引用
   再判一次——本轮回写文档时自己触发了两道判据（越界与都不到各一次），改法见
   `release-readiness.md` §7.7 末尾那段。

## 4. 苹果 SDK 那一档

`docs/analysis/guardian-device-usage.md:84` 引 `AVCaptureDevice.h:323`——既不在本仓库也不在参考仓库。
脚本给它建了第三个索引（`$(xcrun --show-sdk-path)/System/Library/Frameworks/*/Headers`，本轮 6,274 个头文件），
所以这一条也在本机验过：那正是
`@property(nonatomic, readonly, getter=isInUseByAnotherApplication) BOOL inUseByAnotherApplication API_AVAILABLE(macCatalyst(14.0)) API_UNAVAILABLE(ios, watchos, tvos, visionos);`
这一行。**SDK 版本要一起记**：本轮是 macOS SDK `27.0`，换 Xcode 之后这一行会漂，
而这一条不在任何人的 clone 里——读它的人只能在自己机器的 SDK 里 grep `isInUseByAnotherApplication`。

## 5. `docs/Mole/` 是个空壳

P16 现读：`docs/Mole/` 里有 `.git`，`git -C docs/Mole ls-files` 返回 **0** 个文件，
`rev-parse HEAD` 失败——**没有工作树**（一次没做完的 clone），而它的 `origin` 和
`docs/github-references/Mole` 是同一个上游。也就是说 `docs/Mole/**` 这类路径**在本机也打不开**。
本轮把脚本的探查看到这件事并写进报告的 `# ref:` 行，没有删它：删目录是人的决定，
而 `release-readiness.md` §9 已经把 helper/widget 那两个空壳一起挂在"不发"那一栏里，一并处理更省事。
Mole 的工作树在 `docs/github-references/Mole/`，引用一律走那一条。

## 6. 复跑

```
./Scripts/p16-citation-audit.sh docs/verification/p16-citations
```

判据：`硬失败（本仓库引用漂了 + 都不到）: 0`，退出码 0。
参考仓库没克隆不算失败——那一档会走 `定位不到文件因而没试行号判据的` 这一行，报的是"N 条待验证"，
不是"N 条错"。带输出目录那一跑会把整份报告落成 `audit.log`；
**重跑要换目录或先确认覆盖**，`.log` 里的 `# date:` 与 `# repo: <commit>` 是这一份证据属于哪一轮的唯一凭据。
