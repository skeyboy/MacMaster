# P33a 审计：`名称包含应用名` 这条证据与默认勾选是两件事

- 日期：2026-10-12；跑的树：`55de1e1`（干净）。
- 量尺：`Scripts/p33a-contains-scope-probe.sh`（把卸载页扫描那条链的 9 个真源文件与探针编成同一个模块，
  判定一行都不在探针里），证据 `docs/verification/p33a-contains-scope/contains-scope.log`。
- 一句话结论：**这台机上"跨应用收残留"和"弱证据默认勾选"两件事各自都真实发生了，
  只是各被另一个无关的性质救了一次——而那两个性质都不是这条判据自己给的。**
- 本轮**不改任何代码**：§5 是建议分档，选哪一档等你拍板。任务 #161，排期见 §7。

## 1. 这条证据是怎么产生的

包含匹配住在 `ResidualNameMatcher.swift:88`：把应用名归一化再压掉分隔符，只要**文件名压完之后含有这串**就返回
「名称包含应用名」。唯一的安全垫是 `candidate.compressed.count >= 4`——三个字母的名字（`QQ`、`App`）不放行，
四个起就放行。放行宽度由档位决定：`ResidualScanner.swift:529` 只在档位高于 strict 时打开 `allowContains`，
容器与启动项两路同构（`ContainerScanner.swift:41`、`LaunchServiceScanner.swift:39`）。
所以 strict 档按构造不可能有这类命中，本探针因此只跑增强与深度两档（这是一条否证，不是"没跑"）。

## 2. 默认勾选为什么不看这条证据

风险不是按证据强度定的，是按**类别**定的：`ResidualCollector.swift:98` 取 `category.defaultRisk`，
而 `ResidualScanner.swift:99` 把 `cache/savedState/log/httpStorage/webKit/containerCache` 六类一律标 `safe`；
`Risk.swift:39` 里 `isDefaultSelected == (self == .safe)`，页面按它建勾选集（`UninstallerModel.swift:87`）。
**这两条链在同一个格子里错过：一句「名称包含应用名」只要落在 Caches 上，就是默认勾选。**
反过来，落在 `Application Scripts` 上（caution）就不会被自动勾——救它的是类别，不是证据。

## 3. 本机实测（45 个 .app，剔除 com.apple.* 后 41 个参与扫描）

| 档 | 包含命中 | 同路径上别的应用以更硬证据也主张 | 祖先目录归别人 | 默认勾选的包含命中 |
|---|---|---|---|---|
| 增强 | 63 条 / 24 个应用 | 0 | 0 | 18 条 |
| 深度 | 372 条 / 25 个应用 | 1 | 3 | 21 条 |

三件要紧的事都在这张表的右边三列：

1. **跨应用收残留真发生了 1 次**（深度档）：`~/Library/Application Scripts/com.tencent.workbuddy.mac.WechatShare`
   被收进 **WeChat** 的清单，而 WorkBuddy 用「包名完全对应」在同一路径上主张它。它没进默认勾选，
   因为 `Application Scripts` 是 caution——**挡住删除的是类别，不是这条证据到不了归属这件事**。
2. **默认勾选那一族也真发生了 3 次**：`Fork` 名下三条
   `~/Library/Caches/JetBrains/{IntelliJIdea,PyCharm,RustRover}2026.2/ts-go-fork-embedded`，
   祖先目录分别归 IntelliJ IDEA / PyCharm / RustRover（它们自己也是靠包含匹配拿到那个祖先的），
   三条全是 `cache` → safe → **默认勾选**。这台机上它们的实测体积是 0 字节（目录现在是空的），
   所以本轮**不能**把这一族写成"删掉了 N MB 别人的东西"；能写的是：**规则本身给不出这两家的区别**。
   这一族恰恰相反的方向也成立——`ts-go-fork-embedded` 很可能真的是 Fork 自己写进 JetBrains 目录的缓存，
   也就是说同一条规则这次**碰巧是对的**，而画面上那句「名称包含应用名」不含任何信息让人分辨这次对不对。
3. 默认勾选的 21 条里，体积大的是应用**自己**的缓存（IntelliJ IDEA 2.1 GB、RustRover 1.1 GB、
   Qoder CN 504 MB 等）：这些删了能重建，产品口径没问题。但它们与第 2 条那 3 条在界面上**长得一模一样**
   ——同一句证据、同一个勾选态。同一次跑里那条 2.1 GB 的数字在两跑之间动了 178 KB，
   所以本文只把体积当量级用，不登记成读数。

## 4. 夹具那一档才是机制的正面实物

`docs/analysis/feature-roadmap.md:1364` 记的 P32b 现场是这一族的完整形态：
`~/Library/Caches/com.example.steamgame · 名称包含应用名` 被归到 **Steam** 名下、
页脚「已选 1 项残留 · 524 KB」——**跨应用 + 默认勾选同时成立**，照片在
`docs/verification/p32b-steam/07-enhanced-steamgame-residuals.png` 与 `08-deep-steamgame-residuals.png`，
逐档说明在 `docs/analysis/fidelity-uninstaller.md:598` 那一节。
本机没跑出这个完整形态，只是因为这台机的应用清单里没有一个"名字被 Steam 包住、又落在 Caches 里"的邻居；
夹具替我们把形状钉住了。这也是本审计不写"实机没有 ⇒ 不是问题"的理由。

## 5. 建议分档（每档代价，选哪档等人）

- **A 措辞档（最便宜，且无论选哪档都该做）**：把这句证据改成含来源与缺口的说法，
  例如「名称里含 `Fork`，非包名对应——可能不是本应用的文件」。**行为一个都不变**，代价：那一行变长，
  界面上是 `.lineLimit(1)` + 中间截断的那一族（§7.5 的教训），改文案必须同时改判据否则截断会把后半句吃掉。
- **B 判据档（我 recommended 的那一档）**：包含匹配命中时**再看一次祖先归属**——若某个祖先目录被**另一个已安装应用**
  主张，就整条降级为 caution（默认不勾选），并把那句主人写进证据里。代价：扫描时每个命中多走几层 `lstat` 与
  名称判定（可忽略），实现面落在 `ResidualCollector.swift` 的定档那一步；召回不降，只降自动勾选。
  它对症的正是第 3 节那两条链：一个被类别救、一个被空目录救，B 让判据自己救。
- **C 清单档（最保守）**：`Caches`/`Logs`/`HTTPStorages` 这几类**只认包名证据**，包含匹配不再进这些默认勾选类别。
  代价：召回下降——`JetBrains/IntelliJIdea2026.2` 这种形态会整族漏掉（版本号写法无穷，靠包名对不上），
  而这一族恰恰是体积最肥、用户最想删的那部分。
- **D 展示档**：给行加一枚"证据强度：包名 / 名称"标签，勾选行为不变。代价最小，收益也最小：
  它把分辨责任推给用户，而页脚那个「已选 N 项 · X GB」的合计仍然把两族混算。

我的建议顺序：**B + A**（B 关掉"默认勾选会拿走别人的东西"这一条实际风险，A 让剩下的那些行说实话）；
C 只有在"我们不想为归属复核付任何扫描成本"时才选，D 单独选等于没选。
四档都不动 v1.1 那四条产品口径。

## 6. 复跑与门禁

```sh
./Scripts/p33a-contains-scope-probe.sh            # 写证据目录
./Scripts/p33a-contains-scope-probe.sh --stdout    # 只打终端
```
脚本头部把"参与编译的 9 个真源文件 + 各自行数 + 唯一机械改动（剥 `import MMCore`，剥前后各记一次行数、
差一条不等于 1 行就当场退出）"全部写进日志；探针全程只读（`contentsOfDirectory` / `lstat` /
`PropertyListSerialization`），不调用任何删除接口，体积只对被点名的项量。
退出码恒为 0：它是量尺，本轮结论恰恰是"量出来的是违例"，把违例做成红门会在修复落地前一直红；真正的门是 p16。

## 7. 排期

`feature-roadmap.md` v1.1 §2 只有四条，本项**不在其中**（`docs/analysis/feature-roadmap.md:1366` 已记），
排在那四条之后。若采纳 §5 的 B 档，它是一次独立实现轮：判据 + 单测（含"祖先归别人 ⇒ 不许默认勾选"的正反两判据）
+ 夹具那一档照片（夹具已经有现成形状，`Scripts/p32-steam-fixture.sh` 的 `SteamGame` 邻居就是这一族）。
