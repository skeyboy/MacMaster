# 界面文案多语言覆盖率（P56b 建档，P57d 现读更新，2026-10-19）

**范围**：P56 把国际化从"表是死的"接到"壳层整面可切"——`Sources/MacMaster/MainWindow.swift`
（侧栏 + 概览页所有卡片）与它消费的 `DashboardMetrics` / `MMDesign` / `MMFormat` 文案全部走
`L` / `LF`。P57 按这份文档 §6 的顺序接下一档：**共享层 MMUI 两支文件接满**（`MMDesign.swift`
14 行 + `TreemapView.swift` 2 行），**壳层除设置页外接满**（`LaunchBehavior.swift` 3 行 +
`MacMasterApp.swift` 1 行），两语各 202 键。模块页（清理、卸载、磁盘、监控、守护、优化）
和设置页那 81 行**仍是一行未动**。
**这一份文档只登记缺口与推进顺序，不含改动**；改动在 P56a/P57a（代码）与 P56c/P57c（双语实拍）。

一句话结论：**壳层与共享层翻完了（这两面各 0 行未接），全站还剩 1519 行含汉字的界面字面量**。
这 1519 不能直接当待办清单读。第一块要扣的是表自己：MMCore 的 230 行里 201 行就是那张双语表的
中文一侧（§5）；第二块是**故意留成中文**的数据层原话与机器可读输出（§6 逐类分派，含夹具档位）；
剩下的才是"某个页面还没翻"。这份文档的主要作用就是把这三块分开。

---

## 1. 量尺与口径

`Scripts/p56-l10n-gap.swift`（Swift，不是 grep）。口径逐条写在脚本头注释里，这里只重复结论：

1. 只扫 `Sources/` 下的 `.swift`——测试里断言中文原话是刻意的，不算缺口；
2. 注释（`//` 与 `/* … */`）里的中文不计；本仓注释密度很高，不剥注释会把数放大好几倍；
3. **缺口行** = 该行有含汉字（U+4E00–U+9FFF）的字符串字面量；
4. **已接行** = 该行出现 `L("` / `LF("` / `L(key` / `LF(key`；
5. 键名是 ASCII，所以两列天然不重叠：一行里的中文要么还没进表，要么已经在表里。

为什么不用 grep：BSD grep 的 `[一-鿿]` 走字节序，会把 `·` 也认成汉字——本轮在
`MainWindow.swift` 现读到 3 行假阳性，而这一面恰恰是本轮刚接完、必须报 0 的那一面。
量尺报 0 而实际不是 0，比报一个偏大的数更糟。

已知偏差：三引号跨行字面量按行独立扫描（脚本第 88 行），这一类在本仓的界面文件里几乎没有。
这组数用来定"先翻哪一面"的排序，不用来对外主张任何覆盖率。

## 2. 十面的账（P57d 现读于 2026-10-19，命令见文末）

| 面 | 文件 | 缺口行 | 已接行 |
|---|---|---|---|
| 壳层 `Sources/MacMaster` | 6 | 91 | 70 |
| MMUI | 2 | **0** | 30 |
| MMCore | 15 | 230 | 0 |
| MMCleaner | 8 | 271 | 0 |
| MMUninstaller | 16 | 275 | 0 |
| MMDisk | 7 | 147 | 0 |
| MMMonitor | 11 | 102 | 0 |
| MMGuardian | 9 | 134 | 0 |
| MMOptimizer | 7 | 148 | 15 |
| MMFileScanner | 9 | 121 | 0 |
| **合计** | **90** | **1519** | **115** |

对 P56 那一档的账（缺口 1521 → 1519、已接 95 → 115，两列都要逐面核，别按总数读）：

- 壳层 95 → 91：4 行从缺口搬进已接（`LaunchBehavior` 3 + `MacMasterApp` 1），设置页那 81 行没动；
- MMUI 17 → 0：`MMDesign` 的 14 行接进表，`TreemapView` 的 3 行里 2 行走表、
  **1 行是随解耦一起消失的**——"这块能不能下钻"从前靠 `name.hasPrefix("其余 ")` 判断，
  名字一本地化那条判据就静默失效，所以它换成了显式标志（§4），中文名字不再被读；
  于是这一面缺口减 17 而只接 16 行；
- MMCore 211 → 230：**涨 19，且涨的全是表自己**（新 18 键的中文一侧 + `appliedNote` 那一行——
  它是 P56c 才进的文件，§5 那档 182 没算它，所以 P56 收尾时这一面其实已经是 183）。

所以**缺口列不能当"还剩多少要翻"读**：它把表自己也算进去了，§5 与 §6 各扣一块。

## 3. 壳层：只剩设置页没翻

逐文件（`--by-file` 现读）：

```
    缺口  已接
    81     0   Sources/MacMaster/SettingsView.swift
     9     3   Sources/MacMaster/LaunchBehavior.swift    ← P57
     1     1   Sources/MacMaster/MacMasterApp.swift      ← P57
     0     0   Sources/MacMaster/DashboardModel.swift
     0    66   Sources/MacMaster/MainWindow.swift        ← P56
     0     0   Sources/MacMaster/WindowProbe.swift
```

`MainWindow.swift` 现在只剩三处非汉字的"中文样式"残留：`Text("·")`（:291、:294）和
`.joined(separator: " · ")`（:545）。分隔符是符号不是词，两语通用，**不接**——接进表反而
让"分隔符要不要本地化"变成一个需要维护的问题。

壳层这 70 行查的是同一张表；`DashboardModel` 与 `WindowProbe` 是 0/0，因为它们本来就不产出
面向用户的字面量（前者返回结构化状态，后者只写探针输出）。

`LaunchBehavior` 剩下的 9 行**不是漏接**：:108、:112、:137、:155、:156、:160、:188、:191 全是
`MMHookValue.emit(...)` 的钩子留痕（取证脚本按行读它们），:199 是 `MM_DUMP_MENUS` 在拿不到
mainMenu 时打进那份 dump 的一行——那份输出本身就是机器读的。
`MacMasterApp` 剩下的 1 行同理：:121 是 URL scheme 收不到可用 path 时的 stderr 行。
这一族按 §6 的第二类处理：**不进表**。

## 4. 共享层：本轮翻完的这一面（0 行未接）

- `Packages/MMUI/Sources/MMUI/MMDesign.swift`：0 缺口 / 28 已接。P56 接的是 `format.*` 五处
  （:150、:151、:156、:157、:217）与删除结果面板的 `panel.*` 九处（:731、:734、:768、:777、:781、
  :796-799）；P57 接掉剩下那 14 行——treemap 图例七个分类名（:81-87，`ui.category.*`）、
  行内动作按钮的默认标题（:422、:424，`ui.action.reveal_folder`）、`Button(打开系统设置)`（:510）、
  进度两格（:586「剩余约…」、:596「已处理…项」）、undo toast 的两个按钮（:653「撤回」、
  :657「打开废纸篓」）。两处口径要记着：① :422/:424 是**默认值**，调用方自己给了标题就用不上——
  磁盘页详情面板那两个按钮现在仍写「在访达中显示」（P57c 照片 06 里可见），那是模块页的字面量，
  归下一轮；② `MMFormat.duration` / `MMFormat.count` 出来的数字本来就在表后面，接的是句子外壳。
- `Packages/MMUI/Sources/MMUI/TreemapView.swift`：0 缺口 / 2 已接（:163 合并块名走
  `ui.treemap.others`，:369 方块图的辅助功能标签走 `ui.treemap.a11y`）。
  **这一面带着本轮唯一一处行为改动**：合并块"不许下钻"的判据从前是 `item.name.hasPrefix("其余 ")`，
  名字一跟着语言走，英文档下那条前缀判断静默失效，那块会变成可下钻的空目录。
  现在 `isOthers` 是显式标志：布局层合成那块时写死 `isOthers: true`（:167），
  磁盘页自己那份合并块由 `MMDisk.swift` 按它自己的 id 贴（`node.id == "__remaining__"`，
  :910 与 :939 两处构造），消费点 :326、:331、:390、:399、:411 一律读标志不读名字。
  钉住这条的是 MMUI 的新单测（§12），双语照片 02/04 是它在实机上的对照。
- `Packages/MMOptimizer/Sources/MMOptimizer/DashboardMetrics.swift`：已接 15，缺口 8。
  这 8 行不是漏接：它们是 :162-165（磁盘构成四段）与 :196-198、:201（内存构成四段）的
  `Segment.label` / `Part.label`，壳层已经按 id 用 `segmentLabel(_:_:)` 重新贴过了——
  数据层留中文原话、呈现层查表是本轮定的边界。
  同文件里的 `placeholder = "—"`、`↑`/`↓` 一类符号不进表（汉字判据本来也不会算它们）。

## 5. MMCore 的 230 行里，201 行是表自己

`Packages/MMCore/Sources/MMCore/Localization.swift` 单独占了 201 行缺口。对账：
中文表 202 条键值，其中 3 条的值不含汉字（`app.name` = MacMaster、`disk.treemap` = Treemap、
`monitor.cpu` = CPU），剩下 199 条被量尺算作缺口；再加上表外那两行留痕——
:39 的 `MMHookValue.emit("MM_LANGUAGE 含非法取值（…")` 与 :53 的 `appliedNote` 那句「已生效」——
**199 + 2 = 201**。这两行都不该进表（改了破取证，见 §6 第二类）。
P56b 那档读的是 182（181 + 1），差的那一行是 `appliedNote`：它是 P56c 才加进这个文件的，
§5 的旧读数没跟着改，所以 P56 收尾时这一面已经是 183。

MMCore 剩下的 29 行才是这个面的真实缺口，且分三种性质，处置不一样：

- **拒绝/失败原因字符串**：`DeletionGuard.swift` 10（闸门拒绝语，:86-152）、
  `FileTrashService.swift` 5（:118、:171「移入废纸篓后该项仍在原地」等，好消息是这两条已经带
  `code: "STILL_PRESENT"`，按码查表是可行的）、`TrashHistoryStore.swift` 1（落盘失败的 stderr 行）。
  前两支要译就得定"原因码 → 键"的合同，是结构改动不是文案改动。
- **已经有键、只是数据层留了原话**：`Risk.swift` 9 行里的 :16-18 三档短标签，表里就是
  `risk.safe/caution/readOnly`（中文侧 :182-184、英文侧 :434-436），呈现层按 id 重贴；
  :24-26 与 :32-34 那六行详细说明还没进表，属于"接的时候顺手补键"。
- **机器可读留痕**：`HookValues.swift` 3（:31、:71、:96 的非法取值提示，脚本按行匹配）、
  `VolumeRoots.swift` 1（:204 夹具快照声明）。这两行**不该进表**，改了破取证。

## 6. 缺口行 ≠ 待办行数

按 §2 的排序动手之前，先按这三类把不该算的扣掉（都还在缺口行里）：

| 类别 | 典型 | 处置 |
|---|---|---|
| 数据层中文原话 | `CacheScanner` 的 16 个分类名、`ResidualScanner`/`MMDisk` 的标签 | 不接。壳层用 `L(key, or: 原话)` 兜，新类别忘记补键时界面缺的是翻译、不是字 |
| 机器可读输出 | `TrashHistoryStore` 写 stderr 的落盘失败行、`HookValues`/`VolumeRoots` 的钩子留痕 | 不接。这些行是脚本读的，改英文会破取证 |
| 夹具档位文案 | `*FixtureHooks.swift`、`MonitorFixtureHooks` 等 | 本轮不动，实拍时才看得到 |

扣掉之后，真正"模块页用户可见"的大头是页面文件自己：`MMUninstaller.swift` 207、
`MMDisk.swift` 115、`MMCleaner` 四支页面文件（DevArtifactView 92 + MMCleaner 69 +
UserFolderCleanView 53 + SystemAnalysisView 28）、`MMOptimizer.swift` 69、
`MMGuardian.swift` 44、`MMMonitor.swift` 54 + 菜单栏 18。
菜单栏（`MenuBarManager.swift` 18 行）单独一提：它不在窗口里，双语实拍拍不到，
得用 `MM_LANGUAGE` 起进程再看 `screenshot` 之外的路径，成本比页面高一档。

**建议顺序（P57 收口后重排）**：头两档做完了——MMUI 那 14 行、壳层除设置页外能接的 4 行，
逐处见 §3 与 §4。剩下的按同一份账排：
**卸载页 → 清理页四支 → 磁盘 → 守护 → 监控 → 优化 → 菜单栏 → 设置页**。
设置页排最后不是它工作量小（81 行），而是它属外来那一族未提交改动（§7），
且解禁那个 Picker 需要一次真机点击验证。
还有一条给下一轮的规矩：**每接完一面都要重拍双语**——接表只是把字搬进表，
照片才是"这一面真的跟着语言档变"的凭据（§8 的复位坑每个脚本都要带）。

## 7. 一条现在已经是半谎的话（本轮不改，登记）

`Sources/MacMaster/SettingsView.swift:80`：

> 界面文案尚未接入多语言，切换不会改变界面

前半句从 P56 起**不成立**（壳层 70 行、共享层 30 行已接，`MM_LANGUAGE=en` 起进程后侧栏、概览页
和 MMUI 那几处共用组件都跟着变——P57c 的八张照片就是这一句的凭据）。
后半句仍然成立，因为 :79 那个 `.disabled(true)` 还在——用户从界面里切不动。
所以这一格现在的准确说法是：**开关仍然禁用，但界面已经不是"切了也不变"的死表**。

不动它的原因不是没看见：`SettingsView.swift` 属于本轮外来那一族未提交改动（与
`README.md`、`Scripts/make-app.sh` 同一批），一条都不能混进本轮提交。
解禁那个 Picker 需要一次真机点击验证，而 §6 的顺序里设置页排在壳层之后——两件事一起在那一轮做。

**同一句话的其他副本面（本轮一并登记，一处没改）**：①`Sources/MacMaster/SettingsView.swift:76-78` 的代码注释——逐字写着"`L(_:)` 在界面上零调用点（现读 2026-10-05）"，本轮之后是假的，它跟 `:80` 那份脚注在同一次改动里；②`Packages/MMCore/Sources/MMCore/AppSettings.swift:11-12` 的文档注释——"持久化是好的，**生效不是**：`L(_:)` 在界面上零调用点，切换语言目前不改变任何文案"；③设计稿 `docs/design-system/screens/shell/09-settings.html:96`（"便捷函数 `L(_:)` 在界面代码里**零调用点**"）与 `:111` 那条脚注文案——改稿要重渲染 09 那一族的像素基线，按 §6 那条约定排到集成批次；④`RELEASE-NOTES.md:115` 那句"多语言（语言开关是禁用的，切换不会改变界面）"——**这句对已经发出去的 v1.0.1 是实话**（那一版确实零调用点），所以不改历史，但**下一版的正文不能照抄这一句**，准确的写法是"设置里的语言开关仍禁用；壳层与共享组件已接两语，模块页未接"。
判据分两把尺，别混着引：`grep -rnE '(^|[^A-Za-z0-9_])LF?\(' --include='*.swift' Packages Sources`
现读 129 行，但它把函数定义、注释里的 `L(` 一起数了，只能回答"界面上到底有没有调用点"；
**行数的账以 §2 那把量尺为准**（P57d 现读 115 行已接、1519 行缺口）。
P56b 那一档在这句里把两把尺的数并成了一句（"现读 95 行接表"既像 grep 又像 §2 的已接列），
本轮顺手分家。

## 8. 双语实拍的前置（P56c 立的规矩，P57c 照做）

`MM_LANGUAGE=en` 不是"只在本进程生效一次"：`Localization.init` 把它**写回 UserDefaults**
（写回在 `Packages/MMCore/Sources/MMCore/Localization.swift:45`，key 是 :21 的
`storageKey = "app.language"`；P56b 那档记的是 :42，被 P56c 加的留痕挤下去了 3 行）。
后果是忘带的下一屏会悄悄停在英文档，而照片上看不出启动时带了什么变量。
所以每个双语脚本收尾必须 `defaults delete` 那一个 key，且落一张中文档的照片作为"档已复位"的证据。
P57c 照这条做了，并把判据**反过来用**：第八张不带 `MM_LANGUAGE`，于是它的日志里也不该出现那行留痕——
**出现了才说明复位没生效、又是钩子在驱动**（脚本里那条断言写成了 `grep -qF` 取反）。

## 9. 单测锁住了什么

`Packages/MMCore/Tests/MMCoreTests/LocalizationTests.swift` 15 条（P56 新增，随九包门禁跑；
**P56c 现读复核**：本节初稿写 14 条，那是 `testAppliedNoteNamesTheLanguageAndTheKey` 加进来之前的读数）：

- 两语**键集合逐项相等**（双向）+ 值非空；
- **占位符数量与形态跨语言一致**，且只允许 `%@` 对象形——`%@` 拿到 Swift `Int` 会崩，
  而它只在切到那一条文案时才走，是最容易漏测的一类；
- 英文表**真的是英文**（按 U+4E00–U+9FFF 逐字符判）；
- `L(key, or:)` 在键缺失时回落原话而不是把 key 印到屏幕上；
- 启动钩子 `MMLaunchHook.resolveLanguage` 的四档行为：中文写法（`zh` / `zh-hans`，吃空白与大小写）、
  `en`、缺省时沿用当前档且不留痕、非法写法交回调用方留痕而不是静默按中文跑；
- **壳层与共享层引用的每个键都在表里**：扫 `MainWindow.swift` / `DashboardModel.swift` /
  `DashboardMetrics.swift` / `MMDesign.swift` 里的 `L("…")` 与 `key = "…"` 两种写法，
  并断言扫到的条数 > 40——这条是防止正则本身过期：扫不到任何键时它应该红，
  而不是绿着宣布"没有缺口"。
  P57 把消费者名单加上了 `TreemapView.swift`、`LaunchBehavior.swift`、`MacMasterApp.swift`
  （**`SettingsView.swift` 刻意不在名单里**：那一面一行没接，加进来等于让键校验对着一片空地打靶），
  合法前缀加了 `ui`。新键一律写成 `ui.category.app_data` 这种 snake_case 而不是
  `ui.category.appData`：键名校验那条正则只认小写字母与点号，camelCase 会整条躲过检查。

I16（撤回五档）那 17 条在 `UndoTierTests.swift`，与语言无关，归 P56a。
P57 在 **MMUI** 那边加了第 18 条（`TreemapLayoutTests.testOthersFlagIsNotDerivedFromTheItemName`）：
它同时摆一个"名字长得像合并块、但真有 children 的普通目录"和一块布局层合成的合并块，
断言前者的 `isOthers` 为假、后者为真——**这条钉的就是 §4 那次解耦**：
判据要是还从名字推，切了英文档之后那块会静默变成可下钻的空目录，而单测在中文档下全绿。

第 15 条钉的是 `Localization.appliedNote(_:)` 那一句**留痕逐字**（档位值 + `app.language` 那个 key 名都在句里）。
它不是装饰：双语取证的机械判据就是照片旁边那一行日志，"这张到底是哪一档"不许只靠人眼读像素；
措辞一改脚本的 `grep -F` 就断，所以两边由这一条测试绑在一起。

## 10. 复现

```
swift Scripts/p56-l10n-gap.swift            # 十面小计（§2 那三列）
swift Scripts/p56-l10n-gap.swift --by-file  # 逐文件（§3–§5 的数从这里来）
cd Packages/MMCore && swift test --filter LocalizationTests
./Scripts/p57-treemap-fixture.sh            # 双语那一族的两棵夹具（150 / 250 个子项）
./Scripts/p57-shared-l10n-capture.sh /tmp/mm-app-p57/MacMaster.app docs/verification/p57-shared-l10n-bilingual
```

表键数（§5 的 202）来自 `awk` 过 `static let chinese` / `static let english` 两段后按
`^\s*"[a-z]` 计数，两侧同数由单测保证；这里重复一遍是为了下次不必猜量法。

## 11. 上一轮的验证账（P56c，2026-10-19 实跑）

**九包门禁**：`876 条 / 0 失败 / 1 跳过`（逐包：MMCore **146**、MMUI 17、MMFileScanner 117、MMCleaner 25、
MMUninstaller 226、MMDisk **85**（含那 1 跳过）、MMMonitor 92、MMGuardian 96、MMOptimizer **72**；逐包求和 = 876）。
比仓库根那一格 README 的旧读（843，逐包 114/17/117/25/226/85/92/96/71）**涨 33，且 33 全部来自本轮**：
MMCore +32 = `UndoTierTests` 17 + `LocalizationTests` 15，MMOptimizer +1 =
`DashboardMetricsTests.testLoadVerdictWordingIsResolvedSeparatelyFromTheTier`（钉"措辞按语言解、档位按数值解"两件事不许互相顶）。
**README 那一格本轮没改**——它属外来那一族（QuickLook + 设置页）正在改的文件，一行不进；
这两格差 33 这件事登记在这里，等那一族收口时按 `P50` 的写法一并回写。

**两族照片**（都是带窗口实机截图，零合成点击；产物与源码同源由 `mm_provenance_check` 当场把关）：

| 族 | 目录 | 拍什么 | 关键读数 |
| --- | --- | --- | --- |
| 双语五档 | `docs/verification/p56-undo-tier-bilingual/` | 五档**同框**（合成台账：`trashVolumeUUID` 里没有一条是这台机器真删出来的）× 中英两档 × 宽窄两档 + 一张复位后的中文档 | 每张的 `.log` 里都有一行 `MM_LANGUAGE=… 已生效`；05 那一张**不含** `MM_LANGUAGE=`（`defaults delete` 生效）；像素 01↔02 = 43211、02↔05 = 40869、03↔04 = 38436（侧栏条不参与判据）；台账跑完 sha 与跑前逐字相同 |
| 真删真拔 | `docs/verification/p56-cross-volume-detached-badge/` | P53 那一族在**同一支夹具**上重拍：挂载中删一次 → 拔盘 → 重挂，五档顺序跑 | 落点 `/private/tmp/mm-p53-mnt/.Trashes/501/AaaP53CrossVolume.app`（跨卷成立：主目录卷 ≠ 挂载卷）；拔盘后 `test -e` 假、重挂后真；像素 03↔04 = 5999（按钮 → 徽标）、01↔02 = 286564；台账 sha 恢复逐字相同（13 条 / 6991 字节） |

第二族里 04 那一张人眼读到的是：**这一行印「盘已取下」**，而同卡另外三行（用户真实历史、台账里没有卷身份的老记录）
印「无法撤回」——I16 之前那三行印的是「废纸篓已清空」，也就是**同一句假话当时正挂在用户自己的数据上**。
这一条是本轮唯一一张"改判前后用户看到的字真的变了"的照片，所以它不能只由合成夹具代拍。

复现：

```
./Scripts/p56-undo-tier-capture.sh /tmp/mm-app-p56/MacMaster.app docs/verification/p56-undo-tier-bilingual
./Scripts/p53-cross-volume-fixture.sh create && ./Scripts/p53-cross-volume-fixture.sh mount
./Scripts/p53-cross-volume-capture.sh /tmp/mm-app-p56/MacMaster.app docs/verification/p56-cross-volume-detached-badge
./Scripts/p53-cross-volume-fixture.sh clean
```

**引用门禁这一轮跑八回、归档七份**（`docs/verification/p56-citations/`：`audit-pre.log` / `audit-postdocs.log` / `audit-final.log` / `audit-recheck.log` / 提交后的 `audit-postcommit-ambig.log`、`audit-postcommit.log` 与 `audit-postcommit-recheck.log`，改稿阶段中间那回纠错读数没归档），硬失败 **4 → 6 → 4 → 4 → 3 → 2**，定稿后那一跑与定稿逐字只差日期。四条的构成与其中两条"把旧坐标写进引号就等于把它重新请进门"的自伤，记在 `fidelity-shell.md` §7 门禁那一格；本轮新增的判定层文件在提交之前被门禁判成"两头都不到"（它的索引只数 `git ls-files`），**这一条已在提交后复跑验证：那 2 条如期归零**。同一次复跑又抓到本文件自己的一条：验证账那一格原先用「文件名加行数」引仓库根 README，仓里五份同名文件判不出哪一篇，已改成不带形状的说法——终稿硬失败 2，两条都是外来那一族设置页源码上的整段空白，本文件不动它们。

## 12. 这一轮的验证账（P57c，2026-10-19 实跑）

**九包门禁**：`877 条 / 0 失败 / 1 跳过`（逐包：MMCore 146、MMUI **18**、MMFileScanner 117、MMCleaner 25、
MMUninstaller 226、MMDisk 85（含那 1 跳过）、MMMonitor 92、MMGuardian 96、MMOptimizer 72；逐包求和 = 877）。
比 §11 那一档只涨 1 条，就是 §9 说的 `testOthersFlagIsNotDerivedFromTheItemName`。
仓库根 README 那两格仍是 843（它属外来那一族正在改的文件，一行不进），与本轮差 34，登记在这里。

**八张照片**：`docs/verification/p57-shared-l10n-bilingual/`，全在磁盘页（`MM_OPEN_MODULE=disk`），
零合成点击，产物与源码同源由 `mm_provenance_check` 当场把关（tree 与 app 的 digest 逐字相同）。

| 档 | 拍什么 | 人眼读到 |
| --- | --- | --- |
| 01 / 02 合并块 × 双语 | 150 子项那棵（> 96 = `childCap(at: 0)`） | 中文「其余 54 项 / 221 KB」↔ 英文「54 more items / 221 KB」：同一块、同一个数，只有名字跟语言走；54 = 150 − 96 与夹具对得上 |
| 03 / 04 两块合并同框 | 250 子项那棵（> 200 = `renderWindow`） | 英文档下「其余 50 项 / 205 KB」（模块页自己拼的那块，id `__remaining__`）与「105 more items / 430 KB」（布局层那块）**并排一屏中英混排**——这就是"模块页那一轮还没接"的实物，不是拍坏了；105 = 201 − 96（模块页送进布局的 200 个渲染项 + 它自己那块合并块） |
| 05 / 06 / 07 回执条 × 双语 + 窄窗 | `MM_DISK_SELECT` + `MM_SHOW_TOAST=1` | 中文「撤回 / 打开废纸篓」↔ 英文「Undo / Open Trash」；条上那句「已移入废纸篓 4 KB · 共 1 项」两档**都还是中文**（模块页字面量，归下一轮）；详情面板那两个按钮也仍是「在访达中显示」——§4 说的默认值被调用方盖掉了；07 在 1000 pt 下 Undo / Open Trash / 11s 三格都不截断 |
| 08 复位 | 不带 `MM_LANGUAGE` | 侧栏、设置按钮回到中文，合并块回到「其余 54 项」；日志里**没有** `MM_LANGUAGE=` 那一行 ⟹ `defaults delete` 生效（§8 的反向判据） |

机械判据（脚本自己算的，不靠人眼）：七张各带一行 `MM_LANGUAGE=<档> 已生效`；三张回执条各带一行
带数字的钩子凭据「MM_SHOW_TOAST 已画出「移入废纸篓」回执条（1 项 · 4 KB）」；三对中英的内容区像素
1328 / 537 / 3299（侧栏条不参与判据）。

**这一族第一遍没过，拦下它的是它自己的判据**：05/06/07 三张的 `.log` 里查不到那行回执条凭据，
脚本按"没凭据就不算拍到"报了 `✗ 核对没过，这一族不算取证完成`。查下去不是钩子写错值，
是 `MMDisk.swift` 里撤回那条支路一直挂在 `guard env["MM_SHOW_CONFIRM"] != nil` **之下**——
要让它生效就得同时开确认面板，而 `.sheet` 那块面板正盖住这条 `.overlay` 的条。
"回执条摆在标记之前"那句注释从写下那天起只对 `permanent` 那一支成立。
P57c 把撤回这一支也挪到 guard 之上（不设 `return`，`MM_SHOW_TOAST=1` 配 `MM_SHOW_CONFIRM=1`
的老用法照旧开面板），重建后八张全过。
这条记在这里是因为**它是照片抓出来的**：没有任何一条单测走这个钩子，而 p68 那一族只用
`permanent` 那一支——所以这个坑从 P6.8 起就在，只是没人拿它拍过撤回条。

**未拍清单（本轮接了、但画面上没有路径）**：`ui.treemap.a11y`（辅助功能标签，画面上根本不出现）、
`ui.category.*` 七个分类名（`MMCategory` 全仓只有自身定义与那张调色板字典引用它，没有任何页面在渲染它）、
`ui.progress.remaining` / `ui.progress.processed`（要真在跑的扫描才有那两格）、
`ui.action.open_system_settings`（要系统设置深链读不到才亮）、
`ui.menu.settings`（主菜单栏那一项，展开它只能合成点击——禁用）、
`ui.login_item.*` 三句（设置页那一行的状态文案，而设置页本轮一行没接，解禁开关还要真机点击）。
这六处由 §9 的两条兜着：两语键集合逐项相等 + 消费者引用的键必须在表里——**它们不会印错字，
但"印出来确实对"要等各自那一轮有了钩子路径再拍**。

**引用门禁这一轮跑到定点，归档两份**（`docs/verification/p57-citations/`：`audit-drift.log` 是改完源码、
文档还没重指那一跑，`audit-docs.log` 是文档收口后那一跑）：硬失败 **3 → 2**。
多出来的那一条不是外来那一族的，是**本轮自己顶出来的**——共享层 `TreemapView` 那支文件被解耦改动往下漂了
8 行，磁盘那份还原度文档里"圆角 3pt"那一格的坐标正落在漂出来的空白行上，门禁当场报「整段空白」，
本轮重指（这一条的账记在 `fidelity-shell.md` §8 的"还的一笔锚点债"那一格）。
剩下 2 条逐字还是 P56 收尾时那两处：都落在外来那一族（QuickLook + 设置页）正在改的那份设置页源码上，
本轮一行不碰，等那一族提交时一起重指。
读数：条次 1554、唯一「路径+行段」1151、两头都不到 0、同一条路径命中两份文件 0、行号越界 0、
位置存疑 167（提示级，比 P56 终稿那一跑的 162 涨 5，涨的都是本轮新写进去的坐标）。
本文件与 `fidelity-shell.md` 这两份新账里凡引旧坐标的地方一律用裸写法（只说形状不写坐标），
否则等于把上一轮的错坐标重新请进门——这一课 P56 踩过，见 `fidelity-shell.md` §7 门禁那一格。

**提交后复跑**（`audit-postcommit.log`，代码批落在 `f5519bc`、文档批落在 `a1171d7`）：四个引用读数
**逐字未动**（1554 / 1151 / 167 / 2），变的只有 `# date:`、`# repo:`（`f77fa79-dirty` → `a1171d7-dirty`）、
`# index:` 的跟踪文件数 1610 → **1631**（本批入库 21 份：两支脚本 + 十七份照片族产物 + 两份门禁归档）
与 `# vocab:` 的源码 token 数（9872 → 9882，MMDisk 那一处修改带来的）。`-dirty` 仍在：外来那一族的
未提交改动还挂在 `git status --porcelain -uno` 看得见的跟踪文件上，与本批无关。
**这一格里唯一会漂的就是它自己数的东西**——写完这一跑之后没有再改这四张归档，所以它停在定点。
