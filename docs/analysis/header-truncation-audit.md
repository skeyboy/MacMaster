# 页头副标题截断审计（P26，2026-10-07）

## 0. 这一轮量的是哪一句

P25 修掉了清理页页头那一格，同时留了两笔账：一是**残余**（整句还是超预算，被吃掉的是
「可释放」这个标签，约 5 个字符宽度，记在 `docs/analysis/fidelity-cleaner.md` §11.4），
二是那句没有回答的问题——**这条截断合同对九屏都成立吗**。这一轮就是回答第二句。

判据沿用 P25 的三条，不另立：① 截断是一种说谎；② 长度预算要靠实拍量，不靠推理；
③ 中间态照片留在档里。

范围：十处 `MMPageHeader` 调用点里带副标题的九处（设置页无副标题）。
**不在范围**：行级 `lineLimit(1)` 站点（本轮现数 **79** 处），见 §6。

## 1. 结论

- 九屏在 1000 pt 硬最小宽度下实拍：**两屏被中间截断，七屏整句可见**。
  被截的两屏 = 清理页（P25 残余，本轮复核仍在）+ 磁盘页（本轮新账）。
- **机制上的新账：预算不是"窗口宽度"的函数，是"窗口宽度 − 侧栏 − 这一屏动作簇"的函数。**
  清理页与磁盘页正是九屏里动作簇最宽的两屏（分段选择器 + 搜索/筛选框 + 两三个按钮），
  守护页只有一个「刷新」——所以守护页那句 63 字符整句放得下，清理页 50 字符放不下。
  P25 写的"≈48 字符预算"**只对清理页成立，别当常数抄到别的屏**。
- 磁盘页是本轮唯一一处**截断之后画面在说谎**：`77.8 MB · 44…aster-disk-fixture`——
  "44" 的单位「个文件」被吃了，留下两个并排的光秃秃数字。这一条源码里有一段注释
  **主动认过**（§3），但它认的是"用时该被吃"，没认"数字的单位会被连带吃掉"。
- 优化页是另一种"看不见"：首帧**根本没有副标题**（`updatedAt` 为 nil，只有开过
  「系统状态」页签才有值），不是截断，是空。设计稿早就写了这一条，本轮只复核。
- **本轮修了两处**（§5 A + §B），但磁盘页那一处是**两档**才对的：只改段序的第一档被实拍否掉
  （"用时"被切成 `….1 s`，真值 0.1 s），第二档才把页头收成三段。
  这条值得留在结论里，因为它否掉的是一个**看起来已经想清楚了**的方案——
  旧注释自己排过"谁该被吃"，却没算到"被吃一半"比"整段不见"更糟（§8）。

## 2. 逐屏实测

产物 `cae60fe+e3b0c442`（`MMGitCommit=cae60fe`，不带 `-dirty`：本轮**第三次**照做
"提交 → 构建 → 出片"），窗口一律 `MM_WINDOW_SIZE=1000x600`，应用自己回一句
"请求 1000x600pt，窗口实际 1000x652pt（被 .frame(minWidth:minHeight:) 夹住）"，
所以九张都是 1000×652。证据：`docs/verification/p26-min/`、`docs/verification/p26-dev-worst/`、
`docs/verification/p26-disk-deep/`。

| 屏 | 副标题出处 | 画面上实际读到 | 判定 |
| --- | --- | --- | --- |
| 概览 | `Sources/MacMaster/MainWindow.swift:268-272` | 「上次采样 刚刚 · CPU/内存/磁盘均为本机实时读数」 | ✅ 整句 |
| 缓存清理 | `Packages/MMCleaner/Sources/MMCleaner/MMCleaner.swift:881-891` | 「已扫描 16 类 · 10-07 21:58 ·…4.04 GB · 另有 139.9 MB 只读」 | ⚠️ P25 残余：被吃的是「可释放」标签，只读那一段活着 |
| 应用卸载 | `Packages/MMUninstaller/Sources/MMUninstaller/MMUninstaller.swift:331-339` | 「41 个应用 · 已测 0 · 41 个测量中」 | ✅ 整句 |
| 磁盘分析（浅） | `Packages/MMDisk/Sources/MMDisk/MMDisk.swift:230-236`（文案在 `:1555-1561`） | 「77.8 MB · 44…aster-disk-fixture」 | ❌ 单位「个文件」+ 用时 + 路径前段被吃 |
| 磁盘分析（深） | 同上，扫 `/tmp/macmaster-disk-fixture/Library/Developer/Xcode` | 「33.6 MB · 1 个…eveloper/Xcode」 | ❌ 同上，且路径越长被吃得越多 |
| 系统监控 | `Packages/MMMonitor/Sources/MMMonitor/MMMonitor.swift:37-40` | 「上次采样 2026-10-07 21:58 · 实时更新」 | ✅ 整句 |
| 隐私守护 | `Packages/MMGuardian/Sources/MMGuardian/MMGuardian.swift:796-805` | 四段全在：「摄像头与麦克风的当前占用（手动测量，非实时监听） · TCC 授权只读视图 · 登录项管理 · 密钥与自启配置的改动时间（只读 mtime）」 | ✅ 整句（63 字符） |
| 系统优化 | `Packages/MMOptimizer/Sources/MMOptimizer/MMOptimizer.swift:51` | 副标题**不出现**（`diagnostics.updatedAt` 为 nil） | ⚠️ 空，不是截断 |
| 开发产物（最坏档） | `Packages/MMCleaner/Sources/MMCleaner/DevArtifactView.swift:464-486` | 「26 个项目 · 34 处产物 · 本清单由 2 批拼成 · 最近一批扫于 2026-10-07 22:00 · 累计耗时 0.1 秒」 | ✅ 整句 |
| 设置 | `Sources/MacMaster/SettingsView.swift:21` | 无副标题 | — |

**这一列的"画面上实际读到"是修复前那份产物（`cae60fe`）拍的**，修复后的画面在 §8。
出处列给的是**当前树**（`17f4371`）的行号：审计文档要活到下一轮，行号就得跟着树走，
所以磁盘页那两格指的是改过之后的位置，读它们看不到本节描述的那句旧文案。

**两个清理子页（用户文件夹 / 系统分析）本轮没有实拍。** 理由是它们的副标题在代码里就有上界
（`Packages/MMCleaner/Sources/MMCleaner/UserFolderCleanView.swift:131-139`、
`Packages/MMCleaner/Sources/MMCleaner/SystemAnalysisView.swift:91-97`，
最长约 26 字符），而实拍要真扫本机目录——几十秒、结果随机器变、和别的证据族不可比。
**这条判断是读码得出的，不是量出来的**，所以它进 §6 的待办而不是进 §1 的结论。

## 3. 磁盘页那段注释认过什么、没认什么

`cae60fe` 那份 `MMDisk.swift` 里、`headerSubtitle` 上方有一段注释（**本轮已被 §8 的新注释
整段替换，所以这里刻意不给行号——给了就是一个查不到的死锚**），里面写死了预期画面：
「实测（1000pt 窗口 + 44 个文件的夹具）截完是
`77.8 MB · 44…aster-disk-fixture`：占用和目录名活着，用时整段被吃掉、文件数只剩个位数」。

本轮在 P26 的产物上重拍，画面与这句预期**逐字相同**——所以注释没有过期，
它是全仓唯一一处**提前把截断结果写进源码**的地方（P25 之前清理页没有这一句）。

过期的是它的**代价清单**：它把"文件数只剩个位数"当成可接受的损耗，
但界面上留下的是 `77.8 MB · 44` 这样两个并排数字，"44" 没有任何单位。
P25 第①条判据针对的正是这个形态：**用户看见的那一句必须是一句能核对的话**，
而"77.8 MB · 44"核对不了。

## 4. 参考项目怎么躲开这一类（行号全部现读复核）

| 手法 | 出处 | 一句话 |
| --- | --- | --- |
| 不让窗口窄到出问题 | `docs/github-references/Pearcleaner/Pearcleaner/Views/MainWindow.swift:134` + `docs/github-references/Pearcleaner/Pearcleaner/PearcleanerApp.swift:53` | `minWidth: 900` 配 `.windowResizability(.contentMinSize)` |
| 每段独立 `Text` + 尾部截断 + 给数字列留宽度 | `docs/github-references/Pearcleaner/Pearcleaner/Views/AppsView/AppListItems.swift:92-124` | 同文件 :124 `.frame(minWidth: 60)`；中间截断只留给路径（`Views/PluginsView.swift:906`） |
| 低优先级段整段可关 | 同上 `:19`、`:92`（`@AppStorage("settings.interface.minimalist")`） | 不是截断，是"少说一段" |
| 截断的那一格挂 tooltip | `docs/github-references/stats/Modules/Disk/popup.swift:448`（`nameField.toolTip = name`），配 `Kit/helpers.swift:273-274` 的单行截断、`Kit/constants.swift:15` 写死 264 宽 | 视觉上少了，悬停能拿回来 |
| 只有名字列允许截，数字列保宽度 | `docs/github-references/Mole/bin/uninstall.sh:1893`、`:1906` | shell 版同一条优先级思想 |

本仓现状（审计那一刻）：`.help()` 已有 **31** 处（概览页与磁盘页的徽标都在用），
**唯独页头副标题这一格没挂**——`Packages/MMUI/Sources/MMUI/MMDesign.swift:295-299`
当时只有 `.lineLimit(1)` + `.truncationMode(.middle)`。本轮已把 `.help(subtitle)` 挂上（§8）。

## 5. 改法（三档，各自代价）

**A. 共享层一行：副标题挂 `.help(subtitle)`。** 零布局风险、九屏同时受益，
把 P25 的残余从"看不见"降成"悬停可见"。代价：悬停是个弱发现路径，不能当唯一手段。
→ **已做**（`59e653b`），实拍确认没改任何一屏的排版（§8）。

**B. 磁盘页段序：让"用时"当唯一牺牲者，单位跟着数字走。**
把 `size · count 个文件 · 扫描用时 · path` 里被吃的那一段固定成"用时 + 路径中段"，
而不是"单位的尾"。代价：段序是**排版**决定，SwiftUI 的头/尾分配不是推理得出的，
必须实拍验证；验证不过就退回"用时出页头"（注释自己已把它排为最没用）。
→ **本轮做了两档**：第一档（只改段序）实拍**没过**——单位活了，但"用时"自己成了新的半句；
于是走预登记的退路，第二档把"用时"整段请出页头，实拍过（§8）。

**C. 共享层把副标题改成"段数组 + 每段独立 Text + 优先级"**（Pearcleaner 那条路）。
这是唯一能从根上保证"关键段永不被吃"的形态。代价：十处调用点、九张设计稿、
`MMDesign.swift` 的公开签名，而且它改的是所有页头的排版合同。
→ **不本轮做**，挂 P4 最小窗口那笔账（`docs/analysis/fidelity-cleaner.md` §11.4 已记过同一笔，
两处是同一件事，别再各记一遍）。

## 6. 本轮没做、没量到（下一轮的起点）

- **逐屏余量像素没拿到。** 试过用 PIL 自动定位"副标题那一行"再量文字最右列与动作簇最左列，
  九屏里四屏定位到了错误的行（概览/磁盘/优化/设置的副标题带和它下面的内容带混了），
  出的数不可信，所以 §1 那句"预算不是常数"只有"守护页 63 字符整句可见 vs 清理页 50 字符被吃"
  这一组对比撑着，**没有余量表**。可复用的方法是：先逐屏手写 y 带（或用
  `MM_WINDOW_SIZE` 逐档二分找临界宽度），再取列分布。
- **开发产物页的绝对最坏档没逼出来。** `MM_DEV_ROOT_BUDGET_SECONDS=0.05 MM_DEV_AUTO_CONTINUE=2`
  逼出了分批那一段，但夹具的根太小，没逼出「N 个根没扫完」（`Scripts/p68-dev-capture.sh` 的 08 档）。
  所以这一屏实测是 4 段 / 63 字符，5 段那一档是**推算**（约 +9 字符）。
- **用户文件夹 / 系统分析两子页**：读码上界，未实拍（§2 末）。
- **行级 79 处 `lineLimit(1)`** 不在本轮判据里。其中一处源码注释已经自己认了这条合同：
  `Packages/MMFileScanner/Sources/MMFileScanner/CacheScanner.swift:565`
  「长度要克制：MMItemRow 的副标题是 lineLimit(1) + 中间截断，写长了被截掉的正好是后半句，等于没写」。
- **`.help` 浮层没有照片**：拍到它要悬停，悬停是合成指针事件（禁）。§8 那节写清了
  哪一半是代码事实、哪一半没被证明。
- **优化页副标题为空**：本轮只复核了现象，没查"该不该在首帧给一句别的"。

## 7. 复现命令

```
./Scripts/make-app.sh -o /tmp/mm-app-p26 -s /tmp/mm-scratch-p26        # 树须先干净
./Scripts/p4-sweep.sh /tmp/mm-app-p26/MacMaster.app docs/verification/p26-min \
    light 1000x600 "dashboard cleaner uninstaller monitor guardian optimizer settings"
./Scripts/p4-sweep.sh /tmp/mm-app-p26/MacMaster.app docs/verification/p26-min \
    light 1000x600 "disk" "MM_DISK_SCAN=/tmp/macmaster-disk-fixture"
./Scripts/p4-sweep.sh /tmp/mm-app-p26/MacMaster.app docs/verification/p26-disk-deep \
    light 1000x600 "disk" "MM_DISK_SCAN=/tmp/macmaster-disk-fixture/Library/Developer/Xcode"
KEEP_FIXTURE=1 ONLY=01 ./Scripts/p68-dev-capture.sh /tmp/mm-app-p26/MacMaster.app \
    docs/verification/p26-dev-min light 1000x600
KEEP_FIXTURE=1 ONLY=08 ./Scripts/p68-dev-capture.sh /tmp/mm-app-p26/MacMaster.app \
    docs/verification/p26-dev-worst light
```

`Scripts/p4-sweep.sh` 本轮**新接了同源门禁**（`cae60fe`）：不同源 exit 4、一张都不出，
每屏日志多四行归因头（`# date:` 一行的形态是 `# <脚本> <屏> <时间> app=<产物>`）。
它此前是 27 支持照脚本里 22 支没有门禁的那一支。

## 8. 修复之后的实拍（两档：`59e653b` 没过 → `6aa897e` 过）

判据只有一条在管：**中间截断只保头尾，跨在中段边界上的那一段一定会被切成半句**。
所以"谁当牺牲者"不是排版的口味问题——牺牲者必须是一段**切成两半也不构成主张**的东西。

### 第一档：只改段序（`59e653b`）——没过

| 档 | 画面上读到 | 判定 |
| --- | --- | --- |
| 浅（44 个文件的夹具根） | `77.8 MB · /tmp….1 s · 44 个文件` | ❌ 单位活了，但"用时"自己成了半句：真值 0.1 s，画面 1 s |
| 深（`…/Developer/Xcode`） | `33.6 MB · /tmp/….0 s · 1 个文件` | ❌ 同上 |

证据 `docs/verification/p26-fix/`（disk/cleaner/dashboard/guardian 四屏）、
`docs/verification/p26-fix-disk-deep/`，产物 `59e653b+e3b0c442`。

**这一档的教训值得单独记**：改之前我判断"把用时排到中段，它整段被吃掉是可接受的代价"。
实拍否掉了这个判断——它没有被**整段**吃掉，它被吃了**一半**，剩下的一半是个读起来像真数的数。
"牺牲者"必须是一段切了也不撒谎的东西（路径的腰就是这种：谁都知道 `…` 两边是同一串路径）。

### 第二档：三段合同（`6aa897e`，取证跑在 `17f4371` 的产物上）——过

| 档 | 画面上读到 | 判定 |
| --- | --- | --- |
| 浅 | `77.8 MB · /tmp…ture · 44 个文件` | ✅ 两头各是一句完整的话 |
| 深 | `33.6 MB · /tmp…code · 1 个文件` | ✅ 同上 |

证据 `docs/verification/p26-disk-fixed/`、`docs/verification/p26-disk-fixed-deep/`，
日志头 `# digest: tree=17f4371+e3b0c442 app=17f4371+e3b0c442`。
路径的腰被吃掉了，但路径的尾（目录名）没有说谎——而且它本来就另外出现在面包屑条上
（同一两张照片里读得到 `macmaster-disk-fixture` / `Xcode`）。

### 同一批照片里顺带复核到的三件事

- **`.help` 没有改任何一屏的排版**：守护页 63 字符仍整句（`p26-fix/guardian.png`）。
- **清理页的 P25 残余仍在**：`p26-fix/cleaner.png` 读到
  `已扫描 16 类 · 10-07 22:15 · …放 4.51 GB · 另有 141 MB 只读`——"可释"两个字还在中段，
  本轮只是让它悬停可回，**这一格没修**（§5 C 那笔账，`fidelity-cleaner.md` §11.4）。
- **开发产物页的最坏档整句可见**：`p26-dev-worst2/` 读到
  `26 个项目 · 34 处产物 · 本清单由 2 批拼成 · 最近一批扫于 2026-10-07 22:23 · 累计耗时 0.1 秒`。
  **这一屏也带秒数，却没被切**——它只有一个「重新扫描」按钮，预算大。
  这条从反面坐实了 §1 的机制判断：问题从来不是"副标题里有没有数字"，是"这一屏的动作簇吃掉多少"。

### 照片没证明的那一件事

`.help` 的浮层本身没拍。要拍到它得悬停，而悬停是合成指针事件（老规矩：会逃逸到用户的其它应用）。
所以 §5 A 那句"悬停可见"是**代码事实**（`.help(subtitle)` 在 `Packages/MMUI/Sources/MMUI/MMDesign.swift:299`，
本仓另有 31 处同样手法早就在画面上用），不是照片事实。要把它变成照片事实，
需要一个能安全注入 hover 的手段——这条进 §6 的待办，不算已验证。

### 与设计稿的新差异（回写 `fidelity-disk.md`）

`docs/design-system/screens/mmdisk/04-disk.html:60` 与
`docs/design-system/screens/mmdisk/04b-disk-confirm.html:87` 的副标题样例都含"扫描用时"。
本轮实现把它移出页头，这两处样例与画面不再一致——按"记录"级差异入账，
理由就是本节第一档那两张照片，不是"设计稿没抄"。

### 复现（第二档）

```
./Scripts/make-app.sh -o /tmp/mm-app-p26d -s /tmp/mm-scratch-p26d      # 树须先干净
./Scripts/p4-sweep.sh /tmp/mm-app-p26d/MacMaster.app docs/verification/p26-disk-fixed \
    light 1000x600 "disk" "MM_DISK_SCAN=/tmp/macmaster-disk-fixture"
./Scripts/p4-sweep.sh /tmp/mm-app-p26d/MacMaster.app docs/verification/p26-disk-fixed-deep \
    light 1000x600 "disk" "MM_DISK_SCAN=/tmp/macmaster-disk-fixture/Library/Developer/Xcode"
KEEP_FIXTURE=1 ONLY=08 ./Scripts/p68-dev-capture.sh /tmp/mm-app-p26d/MacMaster.app \
    docs/verification/p26-dev-worst2 light 1000x600
```

`Scripts/p68-dev-capture.sh` 也在本轮接了同一道门禁（`17f4371`）：它此前只有两行归因头
（时间 + env），没有源码指纹，所以 08 档那句"最长副标题放得下"在两轮之后就没法复核。
**已经入库的那两族补不回来了**：`docs/verification/p26-dev-min/`（21:58）与
`docs/verification/p26-dev-worst/`（22:00）是**加门禁之前**那一版脚本拍的，日志里只有
`app=/tmp/mm-app-p26/…` 这个路径，没有 `# digest:`——产物早已不在，谁也无法把它们重新绑到某一份源码上。
所以本轮关于开发产物页的主张，**只对 `p26-dev-worst2/`（22:23，`tree=17f4371+e3b0c442`）成立**；
前两族留在这里是当作"同一档画面的两次记录"，不是当作同源的证据。
这是 §7.14 那条残余的一个新实例：**门禁只管得住装上之后的轮次，管不住已经入库的历史证据族**——
下一轮如果要对这一屏再主张什么，重拍，别引用前两族。

## 9. 锚点代价：本轮真正花时间的事不是那两档修复

本轮动了两个源文件（磁盘页净 +18 行、共享层净 +4 行）。动的都不是页头那一句文案的位置，
动的是**它上面的行**——于是全仓文档里指到这两个文件的行号整体失配，这是"改源码的轮次"必然欠下的债，
P21、P25 记过两次，本轮是第三次，但**第一次把债的量测出来了**：

| 量的东西 | 数 | 谁量的 |
| --- | --- | --- |
| 门禁报的硬失败 | **2** | `./Scripts/p16-citation-audit.sh` 第一读（还债之前） |
| 实际漂移的带文件名引用 | **88** | 逐块对差现读（同一把那更窄的正则，只作分解） |
| 实际漂移的不带文件名裸写行号 | **26**（散在 9 份文档） | 同上；**这一类门禁一条都不查** |
| 本轮新写 / 改没的引用 | **+50 / −8** | 同上 |
| 门禁收口的条次 / 唯一 | **745→754 / 633→637** | 审计器自己报 |

**门禁 2 与实漂 88 之间是 44 倍，这不是脚本漏跑，是判据本来不量这件事**：四条硬判据问的是
"文件在不在、行号越不越界、那几行空不空、同后缀歧不歧"，**没有一条问"它指的是不是当初那一行"**。
被抓到的那两条是因为**漂过去的行恰好是空行**；其余 86 条漂到的地方挨着真代码，
读起来仍然像话——磁盘页那一条漂到 `Spacer()`（就在 Toggle 旁边），
共享层那一条漂到一块面板的文档注释。**"漂得像话"是这一类债最难查的形态**，
它不会报错，只会在下一轮被人当成坐标读。

**第二次跑才发现明细只点名一处**：照着明细改完那两条，第二读仍是同一对锚点，只是换了文件名。
`grep` 全仓才知道同一个死锚点有多份引用——明细那一段**按锚点去重**，一条锚点只打印第一个引用它的文档。
判据没错，错的是"照明细改"这个读法。

**收口那两个数（条次 +9 / 唯一 +4）不能当债的读数**：重指是旧键换新键，一个换一个是净 0，
只有新写的才涨总数。**本轮还了 88 条，唯一面只动 4 条**。前面几轮用"条次 +N / 唯一 +N 对得上账"
证明改码代价可控，那个手法只在**只加新锚点**的轮次成立，重指的轮次会当场失真——
所以债由逐块对差量，总数由审计器报，两件事分开写（已并入 `docs/analysis/release-readiness.md` §1 那一格）。

**本轮立下的记法**：活坐标一律带文件名（这样下一轮漂了会被门禁看见），
旧树坐标一律裸写、并注明是哪一棵树上的读数（这样它不会冒充一条真引用）。
`docs/analysis/fidelity-disk.md` §15 ④ 记了这条约束的机制（抽取器只认"文件名紧邻冒号"那个形态）
和现读的裸写锚点总数。
