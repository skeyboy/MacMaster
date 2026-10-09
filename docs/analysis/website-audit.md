# 落地页对外主张审计（`docs/website/index.html`）

> 这一份是 P17a。立项原因写在 `release-readiness.md` §11 第 3 条与 §6 最后一行：
> **逐元素对照表量的是"设计稿 ↔ 实现"，而落地页既不在稿里也不在代码里，没有任何一张表替它把关。**
> P14 那一轮为了扫改名残留才撞上这件事（当时落地页那句"监控系统活动"从 P11c 起就是假话，
> 而改动前 `grep -rn website docs/analysis/` 是 0 命中——从来没被核过）。
> 那一轮只改了被证伪的两句，其余全部记成待办。这一轮把待办清掉：**把整页逐条对着源码读一遍。**
>
> 判据一律现读。表里"判据在哪"那一列的每一行都由本轮 grep/sed 打开确认过，
> 文末 §6 是复跑方法（包括把这一页也交给引用审计脚本跑一次）。

## 1. 判定表

判定档位沿用 `release-readiness.md` §6 的三档：**真** / **真·需标注** / **说不到**（假话或无法证实的主张）。

| # | 页面原文（`index.html` 的行） | 判据在哪 | 判定 |
|---|---|---|---|
| 1 | 「智能扫描系统缓存、日志、临时文件，释放宝贵磁盘空间。」 | `Packages/MMCleaner/Sources/MMCleaner/MMCleaner.swift:129-130`（扫描结果按类别落列表）；勾选集由 `CacheScanScope` 决定（`release-readiness.md` §8 第一条记的 P8 收口） | **真** |
| 2 | 「支持一键清理和安全撤回。」 | 界面上那个按钮写的是「清理已选 N 类」（`MMCleaner.swift:688`），点下去先弹确认、默认按钮是「移到废纸篓」（`MMCleaner.swift:753`）；撤回是开关 + 15 秒窗口（`MMCleaner.swift:746`）与删除历史里的「恢复」（`MMCleaner.swift:798`） | **说不到**（"一键清理"恰恰是产品内注释里那句要避免的语义） |
| 3 | 「完全卸载应用及其残留文件，包括配置文件、缓存和支持文件。」 | 残留引擎确实覆盖容器与共享容器（`ResidualScanner.swift:214` 一类条目）、启动项、安装包收据（`MMUninstaller.swift:1349` 的判定依据说明） | **真·需标注**（"完全"是一个保证不到的词：匹配靠包名与厂商子目录推断，未知形态只会漏，不会报"没找到=没有"） |
| 4 | 「可视化磁盘空间使用情况，快速定位大文件和占用目录。Treemap 直观展示。」 | `Packages/MMUI/Sources/MMUI/TreemapView.swift:132` 起算、`:140` 放置；分类与可清理是两条独立判定链（`DiskClassify.swift:4-7`） | **真** |
| 5 | 「实时监控 CPU、内存、磁盘和网络使用情况。菜单栏显示，一目了然。」 | 菜单栏是 `NSStatusItem`（`Packages/MMMonitor/Sources/MMMonitor/MenuBarManager.swift:69`），磁盘 IO 走 IOKit `IOBlockStorageDriver`（`MetricReaders.swift:78`）；页面上磁盘是一整张卡（`MMMonitor.swift:161`） | **真** |
| 6 | 「检测摄像头与麦克风的当前占用（手动测量，非实时监听），查看 TCC 授权与密钥目录的改动时间，管理登录项启停。」 | 这一句就是产品内页头清单的改写：`Packages/MMGuardian/Sources/MMGuardian/MMGuardian.swift:797-802` 四段（占用 / TCC 只读视图 / 登录项 / mtime 卡）；TCC 有独立探针文件 `TCCProbe.swift` | **真**（P14 已把这格对齐到实现） |
| 7 | 「重复文件检测、浏览器清理、系统优化建议。」 | 重复文件 `Packages/MMFileScanner/Sources/MMFileScanner/DuplicateScanner.swift:244`（SHA256，读取失败进 `unreadablePaths` 而不是当成一组）；优化器四 tab 见 `docs/analysis/fidelity-optimizer.md` | **真** |
| 8 | 「让 Mac 运行更快更流畅。」 | 没有任何一处代码或取证测过"清理前 vs 清理后"的性能差 | **说不到**（这是效果承诺，不是功能描述；我们连"回收了多少"都要分成功/失败两栏报） |
| 9 | 「6+ 核心功能模块」 | 六个业务模块（Cleaner/Uninstaller/Disk/Monitor/Guardian/Optimizer）+ Core/UI/FileScanner 三个共享层 | **真**（写 6 是低估，可以照旧） |
| 10 | 「100% 原生 Swift 开发」 | `find Sources Packages -type f -not -name '*.swift'` 返回 **0 个文件**，149 份 .swift；无 ObjC/SwiftUI 之外的 UI 栈 | **真** |
| 11 | 「0 广告和追踪」 | `release-readiness.md` §1 那一格：`URLSession`/`NWConnection`/`Socket`/`Reachability` 在非测试源码里零命中 | **真**（还可以更硬：整个应用不联网） |
| 12 | 「∞ 免费使用」 | 许可还没拍板（`release-readiness.md` §2.3），产物里关于页那一格写的是"尚未选择许可" | **真·需标注**（没有许可条款时，"免费"只是一个口头说法） |
| 13 | 两个下载按钮：hero 的「免费下载」与末屏的「下载 MacMaster」 | 末屏那个按钮的 `href` 是 `#`——**点了什么都不发生**；而根本没有可分发的产物：adhoc 签名、`TeamIdentifier=not set`、Gatekeeper 判 `rejected`（§2.1） | **说不到**（产品内对同一件事的写法是"未找到官方反馈渠道地址，不做虚构链接"） |
| 14 | 「适用于 macOS 14.0 或更高版本」 | `Scripts/make-app.sh:104-105` 写进 plist 的就是 `LSMinimumSystemVersion` / `14.0`（**P19 现读改指**：那一轮往同一份 plist 里插了 `MMGitCommit` 两行，这一对键往下走了 10 行；改之前审计器的硬判据没亮、只有符号面报了"位置存疑 +1"，这就是那一层唯一能看见的一类漂。**P23 再改指**：同一处又插了 `MMSourceDigest` 两行，编译之后另加 7 行算指纹，95-96 → 104-105。连着两轮都被"往 plist 里加一对键"挪动，说明这一格天然脆——按符号名找比按行号找可靠） | **真** |
| 15 | 页脚「© 2026 MacMaster. All rights reserved.」 | 权利人与年份属于 §10 第 4 步那三项人的决定之一（`NSHumanReadableCopyright` 也还没填） | **待人拍板**（本轮不动它，只记账） |
| 16 | 四个截图位：审计时是四个灰底占位 `<div class="screenshot-placeholder">`，全页 `<img>` 计数为 **0** | 仓库里有 47 个 `docs/verification/` 目录的真实照片（P16 现读数；本轮实拍之后是 48），但**没有一张适合直接放上去**（见 §3） | **已补**（P17c 走夹具档实拍，见 §7；夹具覆盖不到的部分改成"在页面上明说"） |

**小结**（P17c 回写时逐行重数过一遍，原来那句把"真"数成了 8——第 14 行"适用于 macOS 14.0"漏进去了）：
16 条里 **9 条真**、2 条真但需标注、**3 行说不到**（对应 4 条主张：一键清理、更快更流畅、两个下载按钮）、
1 条待人拍板、1 条待补。三条"说不到"和那条"待补"在 P17b/P17c 全部收口，见 §7——
判定表记的是**审计当时那一版页面**，不是现在这一版。

## 2. 三条"说不到"为什么值得单独改

它们不是文笔问题，方向和其余各处相反：

- **「一键清理」**：产品内那条注释（`MMCleaner.swift:129-130`）说的正是"谨慎与只读类别不预选，
  这样'一键清理'永远不会顺手带走用户没看过的东西"。也就是说**代码专门做了防"一键"的设计，
  而对外文案在把"一键"当卖点**。这一条改成界面上真实存在的动作：先扫、类别默认按风险档预选、
  确认弹层、移到废纸篓。
- **「让 Mac 运行更快更流畅」**：效果类承诺需要一次前后测量才叫真话，而这一族数字我们一个都没有
  （§1 那八个实测数里没有性能项）。清理页能说的是"释放了多少、哪些失败了、哪些被保护挡下"。
- **两个下载 `href="#"`**：产品内对同一件事的口径是"没找到地址就明说不配置，不虚构链接"
  （`release-readiness.md` §8 的"反馈问题"那一条）。落地页却挂着两个点了不响的按钮，
  比"没有下载"更接近一句假话。改法是把它换成**真的能兑现的获取路径**：从源码构建的两条命令 +
  一句"当前没有签名产物，装到别人机器上会被 Gatekeeper 拦"。

「完全卸载」那一格（判定表第 3 行）不动语义只换词：把"完全"换成"尽力识别并列出"，
因为残留引擎确实是靠包名/容器/收据推断的，**未识别的形态只会漏报，不会报错**。

## 3. 四个截图位为什么不能用现成照片直接填

`docs/verification/` 下那 47 个目录（P16 现读数；P17c 实拍之后是 48）里是**真机实拍**，画面内容是这台机器的状态：
真实卷名与占用、真实登录项列表（含若干公司名下的服务）、真实密钥目录路径与 mtime。
它们作为验收证据放在仓库里是有意的（每一张都配 `# expected/# observed` 归因头），
但**放进一个准备给陌生人看的落地页**是另一件事——那是把用户数据当宣传图。

所以这一格走**夹具档**：应用本来就有一套 `MM_*` 环境变量钩子（全量清单见
`docs/analysis/hook-ledger.md`），能把这四屏的内容换成 `/tmp` 夹具或纯合成值：

| 屏 | 用的钩子 | 画面里出现的路径 |
|---|---|---|
| 系统清理 | `MM_OPEN_MODULE=cleaner` + `MM_OPEN_TAB=dev` + `MM_PURGE_FIXTURE_HOME` | `/tmp` 下的夹具目录 |
| 磁盘分析 | `MM_OPEN_MODULE=disk` + `MM_DISK_SCAN` | 同上 |
| 系统监控 | `MM_OPEN_MODULE=monitor` + `MM_MONITOR_FIXTURE` | 无路径，纯合成读数（`com.example.*` 进程、`TZZ*` 温度键） |
| 隐私守护 | `MM_OPEN_MODULE=guardian` + `MM_GUARDIAN_FIXTURE` + 另三个 `=rows` 钩子 | 夹具档条目 |

**这一节里两条是 P17c 实拍时才发现的，不是 P17a 审计时就知道的**：

1. **清理屏只能用「开发产物」tab**。`MM_PURGE_FIXTURE_HOME` 的解析点在
   `Packages/MMCleaner/Sources/MMCleaner/DevArtifactView.swift:65`——它是**第四个子页**的扫描根替换，
   不喂第一个 tab。而第一个 tab（缓存/日志/临时文件）进页面就自己扫：
   `Packages/MMCleaner/Sources/MMCleaner/MMCleaner.swift:382-385` 那个 `.task` 在列表为空时直接
   `model.scan(settings:)`，扫的是**这台机器的真实目录**，没有任何钩子能把它换成夹具。
   所以 01 那张图画的是「开发产物」页（`MM_OPEN_TAB=dev`），卡片标题写的是"清理 · 开发产物"——
   不是随便起的名，是被钩子覆盖面决定的。
2. **侧栏的卷信息条和磁盘页的"卷可用"没有钩子，画面上是真机状态**。
   `Sources/MacMaster/MainWindow.swift:144-169` 的 `volumeFooter`（卷名 + 剩余百分比 + 那条堆叠条）
   数据来自 `Sources/MacMaster/DashboardModel.swift:71` 的 `SystemSampler.volume()`；
   磁盘页右上角 `Packages/MMDisk/Sources/MMDisk/MMDisk.swift:363` 那个 `卷可用 …` badge 同理。
   还有第三处：**侧栏"系统清理"后面那格体积**（`Sources/MacMaster/MainWindow.swift:108-111`）
   读的是概览页那次真实扫描的 `dashboard.reclaimState`，也不是钩子能顶替的东西——
   本轮是放大 01 那张照片时才看到它带着 `1.14 GB`，于是把页面上那句披露从两处改成三处。
   （顺带一条反证：01 画面里 `~/Code/macmaster-web` 看着像真项目，其实它是
   `Scripts/purge-fixture.sh:61-65` 造的，所以"清单全部来自夹具"这半句仍然成立。）
   两条都是直接读启动卷，夹具钩子一个都碰不到它们——**只要拍整窗，"Macintosh HD 10%"就会进画面**。
   可选的做法是裁掉侧栏，但那有两个问题：裁切后的截图不再是产品里真实看到的那一屏，
   而且裁切本身就是在藏一件事。所以这一轮的做法是**在 §界面预览 下面那句话里明说**：
   清单与读数全部来自夹具，唯独侧栏卷名/占用与磁盘页"卷可用"是拍摄那台机器的真实状态。
   `Scripts/p17-website-capture.sh` 的 CSS 注释里也留了同一句理由（不裁切的原因写回图片样式旁边，
   下次有人想"顺手裁一下"时能看到这里已经有过决定）。

窗口尺寸统一用 `MM_WINDOW_SIZE`（`Sources/MacMaster/LaunchBehavior.swift:140` 那条解析路径，
格式 `宽x高`），外观统一暗档（设计稿那一套就是暗色底）。截图仍旧按 pid 找自己的窗口
（`Scripts/window-ids.swift`），**不发一个合成点击**。

## 4. 待人拍板的那一条

页脚那句 `© 2026 MacMaster. All rights reserved.` 里的"权利人"就是 §2.3 / §10 第 4 步
那三项没定的东西之一（许可、`NSHumanReadableCopyright` 的年份与权利人、签名方式）。
**本轮不改这一行**：改它等于替一个还没做的决定填一个名字。它留在账上，
和「∞ 免费使用」那一格是同一件事——许可一落地，这两处一起改。

## 5. 这一轮的边界

- 只动 `docs/website/index.html` 的文案、两个死链、四个截图位；**不动 CSS 结构**（样式本轮没证伪过任何东西）。
- 不动代码。审计过程中如果发现文案与实现不符，改的是文案——这一页不是产品。
- 不发布。这页目前只在仓库里；真要在网上挂出来，先决条件是 §2.1 的签名与公证，
  否则"下载"那一屏换成什么写法都没有产物。

## 6. 复跑

```
./Scripts/p16-citation-audit.sh            # 本文档里每一处 文件:行号 都在这条命令的范围内
```

**两个和这一族文档有关的坑，都记在这里而不是脚本里**（脚本只在自己的注释里记判据本身）：

1. 引用审计**只扫 `git ls-files` 里的 .md**。新建的分析文档在 `git add` 之前不会被验一次——
   本轮这份文档就是靠先 `git add` 才吃到判据的。所以新文档的锚点要么先 add 再跑，
   要么写完立刻 add（提交前它反正要进暂存区）。
2. `.html` 也在那条命令的扩展名清单里。所以本文档里那种"落地页某一行"的行号引用**同样会被验**——
   P17a 的判定表原本就写着四个 `index.html:NNN`，改完页面之后它们全都漂到了别人身上。
   本轮的收口方式不是重新对一遍行号，而是**把它们改成文字描述**（"hero 那个按钮"、"四个占位 div"），
   理由和 `reference-repos.md` §3 第 4 条一样：抓取器是机械的，一行漂了的行号看起来仍旧像证据。
   结论：**落地页这种会被整段重写的文件，别用行号锚点指它。**

## 7. P17b / P17c 落地的账

判定表里那三条"说不到"和那条"待补"现在的状态：

| 判定表 | 改法 | 依据 |
|---|---|---|
| 第 2 行「一键清理和安全撤回」 | 换成界面上真实存在的动作序列：按类别列出 + 风险档预选 + 确认弹层 + 移到废纸篓 + 15 秒撤回 | §2 第一条；措辞逐句对着 `MMCleaner.swift` 的确认面板与撤回开关读 |
| 第 8 行「让 Mac 运行更快更流畅」 | 删掉效果承诺，改成"找出可以处理的对象"，并明写不承诺提速多少 | §2 第二条 |
| 第 3 行「完全卸载」 | 语义不动、词换成"尽力找出…逐项列出来由你确认"，并补一句"没见过的形态会漏列，不会替你打包证" | §2 末尾那段 |
| 第 13 行两个下载按钮 | hero 那个改成 `#features`（**能跳**）；末屏整段换成「现在还没有能下载的安装包」+ 两条真的能跑通的构建命令 | §2 第三条。仓库地址那一格写成 `<你的 MacMaster 仓库地址>` 占位——本轮 `curl` 过两个猜测的 GitHub 地址都是 404，**不把一个没验过的 URL 放上去** |
| 第 11 行「0 广告和追踪」 | 顺手加硬：`0 广告、追踪与联网请求`、`0 内购与付费入口`（第二格从前是"内购与订阅：代码里没有付费入口"，无头浏览器整页渲染时那一行**折出一个孤字**，所以缩短到与左邻同宽——事实不变，`grep` 全仓无 StoreKit 依赖） | §1 那两条 grep（网络 API 零命中、无 StoreKit 依赖） |
| 第 16 行四个截图位 | 新增 `Scripts/p17-website-capture.sh`，四张夹具档实拍落 `docs/website/assets/`，四个占位 div 换成 `<img>`；§界面预览 下方加一段"哪些是夹具、哪些是真机状态"的说明 | §3 两条新发现 |

**超出 §5 边界的两点**：那条"不动 CSS 结构"被改了两次，都记在这里。
① **加**了一条 `.screenshot-card img`（宽度铺满、保持比例、暗底）——占位框换成图片之后**必须**有，
否则 2560×1600 的原图按 intrinsic size 溢出卡片；规则旁边留了注释说明截图为什么**不裁切**。
② **删**了 `.screenshot-placeholder` 那一条（12 行）：四个占位 div 换成 `<img>` 之后它**零个使用者**
（`grep -c 'class="screenshot-placeholder' docs/website/index.html` 现读 **0**），
留着就是一份"看着还有、其实没人用"的死样式——和界面上那些死开关同一族，只是代价小得多。
除此之外 CSS 一行未动。

**证据链**：
- `Scripts/p17-website-capture.sh`（可重跑，`ONLY` / `KEEP_FIXTURE` / `SETTLE` / `DISK_SETTLE` / `SIZE` 可调）
- `docs/verification/p17-website/capture.log`（每一档的 env 原样写下来 + 产出的宽高与体积；`# expected/# observed` 归因头）
- `docs/website/assets/0{1,2,3,4}-*.png`，全部 2560×1600（1280×800 pt @2x）

页面渲染态本轮用 headless Chrome 看过整页（`--window-size=1440,4200 --screenshot`）：
`browser-use` 的截图这条路当时拿不到视口（`NATIVE_BROWSER_VIEWPORT_UNAVAILABLE`，viewport=0x0），
所以落地页这一侧的"看"走无头浏览器，**应用的实拍仍旧全部来自带窗口的真机进程**——两者不要混为一谈。

**没做的**：不发布（§5）。页面现在只在仓库里；`© 2026` 那行照 §4 留着。
