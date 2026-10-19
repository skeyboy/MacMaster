# 界面文案多语言覆盖率（P56b，2026-10-19）

**范围**：P56 这轮把国际化从"表是死的"接到"壳层整面可切"——`Sources/MacMaster/MainWindow.swift`
（侧栏 + 概览页所有卡片）与它消费的 `DashboardMetrics` / `MMDesign` / `MMFormat` 文案全部走
`L` / `LF`，两语各 184 键。模块页（清理、卸载、磁盘、监控、守护、优化）本轮**一行未动**。
**这一份文档只登记缺口与推进顺序，不含改动**；改动在 P56a（代码）与 P56c（双语实拍）。

一句话结论：**壳层翻完了（0 行未接），全站还剩 1521 行含汉字的界面字面量**。
这 1521 不能直接当待办清单读。第一块要扣的是表自己：MMCore 的 211 行里 182 行就是那张双语表的
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

## 2. 十面的账（现读于 2026-10-19，命令见文末）

| 面 | 文件 | 缺口行 | 已接行 |
|---|---|---|---|
| 壳层 `Sources/MacMaster` | 6 | 95 | 66 |
| MMUI | 2 | 17 | 14 |
| MMCore | 15 | 211 | 0 |
| MMCleaner | 8 | 271 | 0 |
| MMUninstaller | 16 | 275 | 0 |
| MMDisk | 7 | 147 | 0 |
| MMMonitor | 11 | 102 | 0 |
| MMGuardian | 9 | 134 | 0 |
| MMOptimizer | 7 | 148 | 15 |
| MMFileScanner | 9 | 121 | 0 |
| **合计** | **90** | **1521** | **95** |

## 3. 壳层：本轮翻完的这一面

逐文件（`--by-file` 现读）：

```
    缺口  已接
    81     0   Sources/MacMaster/SettingsView.swift
    12     0   Sources/MacMaster/LaunchBehavior.swift
     2     0   Sources/MacMaster/MacMasterApp.swift
     0     0   Sources/MacMaster/DashboardModel.swift
     0    66   Sources/MacMaster/MainWindow.swift   ← 本轮
     0     0   Sources/MacMaster/WindowProbe.swift
```

`MainWindow.swift` 现在只剩三处非汉字的"中文样式"残留：`Text("·")`（:291、:294）和
`.joined(separator: " · ")`（:545）。分隔符是符号不是词，两语通用，**不接**——接进表反而
让"分隔符要不要本地化"变成一个需要维护的问题。

壳层这 66 行查的是同一张表；`DashboardModel` 与 `WindowProbe` 是 0/0，因为它们本来就不产出
面向用户的字面量（前者返回结构化状态，后者只写探针输出）。

## 4. 共享层：接了一半的两处

- `Packages/MMUI/Sources/MMUI/MMDesign.swift`：已接 14（`format.*` 五处：:150、:151、:156、:157、:217；
  删除结果面板的 `panel.*` 九处：:731、:734、:768、:777、:781、:796-799），缺口 14 行逐条是：treemap 图例七个分类名（:81-87）、
  行内动作按钮的默认标题（:422、:424）、`Button("打开系统设置")`（:510）、
  进度两格（:586「剩余约…」、:596「已处理…项」）、undo toast 的两个按钮（:653「撤回」、:657「打开废纸篓」）。
  注意 `MMFormat.duration` / `MMFormat.count` 已经在表后面了，剩下的是句子外壳。
  这一面是**全站共用组件**，接一句九个模块页同时受益，
  所以它是下一轮性价比最高的一处。
- `Packages/MMOptimizer/Sources/MMOptimizer/DashboardMetrics.swift`：已接 15，缺口 8。
  这 8 行不是漏接：它们是 `:162-165`（磁盘构成四段）与 `:196-201`（内存构成四段）的
  `Segment.label` / `Part.label`，壳层已经按 id 用 `segmentLabel(_:_:)` 重新贴过了——
  数据层留中文原话、呈现层查表是本轮定的边界。
  同文件里的 `placeholder = "—"`、`↑`/`↓` 一类符号不进表（汉字判据本来也不会算它们）。

## 5. MMCore 的 211 行里，182 行是表自己

`Packages/MMCore/Sources/MMCore/Localization.swift` 单独占了 182 行缺口。对账：
中文表 184 条键值，其中 3 条的值不含汉字（`app.name` = MacMaster、`disk.treemap` = Treemap、
`monitor.cpu` = CPU），剩下 181 条被量尺算作缺口；再加上钩子留痕那一行
`MMHookValue.emit("MM_LANGUAGE 含非法取值（…")`——**181 + 1 = 182**。

MMCore 剩下的 29 行才是这个面的真实缺口，且分三种性质，处置不一样：

- **拒绝/失败原因字符串**：`DeletionGuard.swift` 10（闸门拒绝语，:86-152）、
  `FileTrashService.swift` 5（:118、:171「移入废纸篓后该项仍在原地」等，好消息是这两条已经带
  `code: "STILL_PRESENT"`，按码查表是可行的）、`TrashHistoryStore.swift` 1（落盘失败的 stderr 行）。
  前两支要译就得定"原因码 → 键"的合同，是结构改动不是文案改动。
- **已经有键、只是数据层留了原话**：`Risk.swift` 9 行里的 :16-18 三档短标签，表里就是
  `risk.safe/caution/readOnly`（:172-174、:399-401），呈现层按 id 重贴；
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

**建议顺序**：MMUI（共用，14 行解锁全站）→ 壳层其余两个文件（设置页 81 + 启动行为 12）
→ 卸载页 → 清理页 → 磁盘 → 守护 → 监控 → 优化 → 菜单栏。

## 7. 一条现在已经是半谎的话（本轮不改，登记）

`Sources/MacMaster/SettingsView.swift:80`：

> 界面文案尚未接入多语言，切换不会改变界面

前半句从本轮起**不成立**（壳层 66 行已接，`MM_LANGUAGE=en` 起进程后侧栏与概览页整面变英文）。
后半句仍然成立，因为 :79 那个 `.disabled(true)` 还在——用户从界面里切不动。
所以这一格现在的准确说法是：**开关仍然禁用，但界面已经不是"切了也不变"的死表**。

不动它的原因不是没看见：`SettingsView.swift` 属于本轮外来那一族未提交改动（与
`README.md`、`Scripts/make-app.sh` 同一批），一条都不能混进本轮提交。
解禁那个 Picker 需要一次真机点击验证，而 §6 的顺序里设置页排在壳层之后——两件事一起在那一轮做。

**同一句话的其他副本面（本轮一并登记，一处没改）**：①`Sources/MacMaster/SettingsView.swift:76-78` 的代码注释——逐字写着"`L(_:)` 在界面上零调用点（现读 2026-10-05）"，本轮之后是假的，它跟 `:80` 那份脚注在同一次改动里；②`Packages/MMCore/Sources/MMCore/AppSettings.swift:11-12` 的文档注释——"持久化是好的，**生效不是**：`L(_:)` 在界面上零调用点，切换语言目前不改变任何文案"；③设计稿 `docs/design-system/screens/shell/09-settings.html:96`（"便捷函数 `L(_:)` 在界面代码里**零调用点**"）与 `:111` 那条脚注文案——改稿要重渲染 09 那一族的像素基线，按 §6 那条约定排到集成批次；④`RELEASE-NOTES.md:115` 那句"多语言（语言开关是禁用的，切换不会改变界面）"——**这句对已经发出去的 v1.0.1 是实话**（那一版确实零调用点），所以不改历史，但**下一版的正文不能照抄这一句**，准确的写法是"设置里的语言开关仍禁用；壳层与共享组件已接两语，模块页未接"。
判据是同一条命令：`grep -rnE '(^|[^A-Za-z0-9_])L\(' --include='*.swift' Packages Sources`（现读 95 行接表、缺口 1521 行，见 §2）。

## 8. 双语实拍的前置（P56c 会踩）

`MM_LANGUAGE=en` 不是"只在本进程生效一次"：`Localization.init` 把它**写回 UserDefaults**
（写回在 `Packages/MMCore/Sources/MMCore/Localization.swift:42`，key 是 :21 的
`storageKey = "app.language"`）。
后果是忘带的下一屏会悄悄停在英文档，而照片上看不出启动时带了什么变量。
所以每个双语脚本收尾必须 `defaults delete` 那一个 key，且落一张中文档的照片作为"档已复位"的证据。

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
- **壳层引用的每个键都在表里**：扫 `MainWindow.swift` / `DashboardModel.swift` /
  `DashboardMetrics.swift` / `MMDesign.swift` 里的 `L("…")` 与 `key = "…"` 两种写法，
  并断言扫到的条数 > 40——这条是防止正则本身过期：扫不到任何键时它应该红，
  而不是绿着宣布"没有缺口"。

I16（撤回五档）那 17 条在 `UndoTierTests.swift`，与语言无关，归 P56a。

第 15 条钉的是 `Localization.appliedNote(_:)` 那一句**留痕逐字**（档位值 + `app.language` 那个 key 名都在句里）。
它不是装饰：双语取证的机械判据就是照片旁边那一行日志，"这张到底是哪一档"不许只靠人眼读像素；
措辞一改脚本的 `grep -F` 就断，所以两边由这一条测试绑在一起。

## 11. 这一轮的验证账（P56c，2026-10-19 实跑）

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

## 10. 复现

```
swift Scripts/p56-l10n-gap.swift            # 十面小计
swift Scripts/p56-l10n-gap.swift --by-file  # 逐文件（§2–§5 的数从这里来）
cd Packages/MMCore && swift test --filter LocalizationTests
```

表键数（§5 的 184）来自 `awk` 过 `static let chinese` / `static let english` 两段后按
`^\s*"[a-z]` 计数，两侧同数由单测保证；这里重复一遍是为了下次不必猜量法。
