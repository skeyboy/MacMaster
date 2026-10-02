# 安装来源识别（Homebrew / App Store / 安装包）· 只读可行性调研

> P5.2 的调研底稿。参考实现在 `docs/github-references/`（Pearcleaner、Mole），
> 本机事实是 2026-10-01 一条条 `ls`/`cat` 出来的，不是从参考项目推的。
> 落地代码：`Packages/MMUninstaller/Sources/MMUninstaller/AppProvenance.swift`。

## 0. 结论先行

**不跑 `brew` 也能把来源说清楚**，但要换一条路：参考项目把"来源"当成一次查询
（`brew list --cask`、`brew info --json`），我们把它当成**读一份 brew 自己留下的账本**。
账本就在 `<prefix>/Caskroom/<token>/.metadata/INSTALL_RECEIPT.json` 里，
里面明确写着这个 cask 往哪儿放了哪个 `.app`。

三条本机实测出来的关键事实，其中两条**和参考项目的假设相反**：

1. **软链的方向是 Caskroom → /Applications，不是反过来。**
   `/opt/homebrew/Caskroom/highball/0.9.39/Highball.app` 是指向
   `/Applications/Highball.app` 的符号链接，`/Applications` 里那份才是真身。
   所以"把应用的 realpath 拿去比对是否落在 Caskroom 里"这一招在本机**永远不成立**；
   能用的是反向：枚举 Caskroom → 解析每个 staged `.app` 链接 → 拿 `lstat` 的
   `st_dev`/`st_ino` 和候选应用比**设备号同一**。
   Mole 的 `_detect_cask_via_symlink_check`（`readlink` 应用自身路径）在本机会空转，
   它的 `_detect_cask_via_caskroom_search`（`find` + `-ef` 设备号比对）才是干活的那一级。
2. **`.metadata/<版本>/<时间戳>/Casks/<token>.json` 在当代 Homebrew 里就是 `{}`。**
   本机 brew 6.0.10，`INSTALL_RECEIPT.json` 里 `loaded_from_api: true`，
   真正的 cask 定义改从 `~/Library/Caches/Homebrew/api/internal/packages.<arch>.jws.json` 加载，
   落盘的 Casks/*.json 成了空壳。Pearcleaner 的 `getCaskNameDescVersionPin` 以这份 JSON 为主证据，
   我们必须以 `INSTALL_RECEIPT.json` 为主、Casks/*.json 只做**可选增强**（能解析出
   `full_token`/`auto_updates`/`name` 就用，解析不出不报错）。
3. **prefix 不能按 CPU 架构猜。** Pearcleaner 写死 `isOSArm()` → `/opt/homebrew`，否则 `/usr/local`
   （`HomebrewController.swift:246-247`）；这台机器只有 ARM brew，看着没事，
   但"ARM 机器上另装一份 Intel brew"或自定义前缀就双双落空。Mole 是两个前缀都探
   （`lib/uninstall/brew.sh:83` 同时匹配 `/opt/homebrew/Caskroom/` 与 `/usr/local/Caskroom/`）——
   我们照 Mole：**探测 `Caskroom` 是否存在**，不猜架构。

## 1. 本机实测（2026-10-01）

| 事项 | 实测 |
| --- | --- |
| `/opt/homebrew/Caskroom` | 6 个 token：`android-platform-tools` `codeedit` `highball` `homebrew-app` `temurin@17` `wailbrew` |
| `/usr/local/Caskroom`、`/usr/local/Homebrew` | **不存在**（本机没有 Intel brew） |
| `Cellar` 里的 GUI 应用 | 有，但都在 Cellar 内部（`python@3.13/…/IDLE 3.app`），不在 `/Applications`，所以不进应用清单 |
| `/Applications` | 44 个 `.app`（含 `~/Applications` 一起算）；`Homebrew.app` `Highball.app` `WailBrew.app` 三个能对上 cask |
| 悬空凭据 | `codeedit` 的链接指向 `/Applications/CodeEdit.app`，**该路径不存在** → 账本还在、应用已走 |
| 没有 app 的 cask | `temurin@17`（pkg 型，`uninstall_artifacts` 里没有 `app`）、`android-platform-tools`（只有 7 个 `binary` 绝对路径） |
| `INSTALL_RECEIPT.json` 可用字段 | `source.{tap,version,path}`、`installed_on_request`、`time`、`arch`、`homebrew_version`、`uninstall_artifacts[]`（`app` / `binary` / `zap` 等单键字典的数组） |
| `config.json` | `default.appdir = /Applications`、`appimagedir = ~/Applications` → **目标目录读它，别硬编码** |
| App Store 凭据 | `Contents/_MASReceipt/receipt` 命中 9/44（Developer、LocalSend、QQ、TencentMeeting、TestFlight、The Unarchiver、Transporter、WeChat、Xcode） |
| 安装包凭据 | `/var/db/receipts` 9 条 `PackageIdentifier`，与本机任何应用的 bundleID **零命中**（所以这一档在真机上大概率是空的，取证要靠夹具） |

## 2. 判定顺序与置信度

来源之间会互相打脸（一个 bundle 完全可以既带 `_MASReceipt` 又有一条陈年 cask 账本），
所以顺序和"要不要说出口"比信号本身更重要：

| 档 | 判据 | 界面上怎么说 |
| --- | --- | --- |
| 强 · Homebrew cask | Caskroom 里某个 staged `.app` 链接**解析后的设备号**与该应用相同 | 「Homebrew cask：`<token>`」+ 凭据文件路径 + 版本 + 装于何时 |
| 强 · App Store | `Contents/_MASReceipt/receipt` 存在 | 「Mac App Store」 |
| 中 · 仅名字对上 | 收据的 `uninstall_artifacts.app` 名单里有这个 `.app` 名，但设备号对不上（用户复制过一份、`--adopt`、cask 换过目标目录） | 「疑似 Homebrew cask：`<token>`（凭据只对上名字）」 |
| 歧义 | 两个 token 的 staged 链接**解析后都是这一份 bundle**（两份账本在抢同一份文件），或两个 token 只把名字声明重了 | 不挑第一个，降级成「无法判定」并**点名两个 token**；两种歧义分开措辞，它们的可信度不一样 |
| 中 · 安装包 | bundleID 与 `/var/db/receipts` 里的 `PackageIdentifier` 相同（复用 `ReceiptOwnerIndex`，`OrphanScanner.swift:181`） | 「安装包装的（台账 `<id>`）」 |
| **未知** | 以上都不成立 | 「没有留下安装凭据」——**绝不写成「手动安装」** |

未知 ≠ 手动。没有凭据可能只是凭据被清掉了、或者装在别的地方；把它说成"手动安装"
就是这一路一直在防的那件事：**把未知当已知**。

## 3. 不采纳的信号（以及为什么）

| 信号 | 出处 | 不采纳原因 |
| --- | --- | --- |
| `brew list` / `brew info --json=v2` / `brew --prefix` | Pearcleaner `HomebrewUninstaller.swift`、Mole 全程 | 要 spawn 第三方二进制。项目红线：不执行 brew/git/cargo，判定只用目录里看得见的证据 |
| `pkgutil --pkgs`、`mdls -name kMDItemAppStoreAdamID` | Pearcleaner | 同样是子进程；`mdls` 还依赖元数据服务器活着 |
| 私有框架 `PackageKit` 枚举 `.bom` | Pearcleaner `PKG/PKGManager.swift` | 不用私有 API。代价是 pkg 型 cask（`temurin@17`）只能落到"没有 app 的凭据"，本来也不该给它编一个来源 |
| `opt/`、`bin/` 软链指向 Cellar | Pearcleaner `Locations.swift` 把它们列为残留搜索根 | 那是 formula 的信号，用它证明 GUI 应用的来源会被 CLI 工具目录污染 |
| Sparkle（`SUFeedURL`/`SUPublicEDKey`）、DevMateKit、`-setapp` 后缀 | Pearcleaner `AppInfoFetch.swift` | 这些是"它自己会更新"的旁证，能降低 cask 置信度但证明不了来源。真要做，应该做成"更新方式"那一栏，别混进"来源" |
| `TeamIdentifier` | Pearcleaner `AppPathsFetch.swift` | 它自己也只拿去匹配残留，不拿来判来源；我们没有新增信息量 |

## 4. 下一轮值得接的一条

`INSTALL_RECEIPT.json` 里的 `zap` 是 **cask 作者手写的残留清单**（例如 codeedit 列了
`~/Library/Application Support/CodeEdit`、`~/Library/Caches/*.CodeEdit`、`*.CodeEdit.savedState` 等 8 条）。
我们的残留引擎现在靠 bundleID / 包名启发式匹配，**这份清单是外部维护的、按应用逐个核对过的证据**，
喂进 `ResidualScanner` 能把"我们猜的残留"升级成"cask 作者声明的残留"。
但要注意两条：`zap` 里带 `*` 通配和 `~` 前缀，得先归一化；
并且它只该作为**加分证据**出现，不能反过来因为"zap 没列"就判某条残留不存在。

## 5. 落地情况（2026-10-02，P5.2）

本节是"调研 → 实现"的对账，实现细节与逐元素还原度见 `fidelity-uninstaller.md` §8，
规划口径见 `feature-roadmap.md` 的「P5.2 落地」。

**照原样落地的**：判据强度排序、五种来源 + 歧义降级、"未知 ≠ 手动安装"的文案红线、
不 spawn 任何第三方二进制、`/var/db/receipts` 复用 `ReceiptOwnerIndex`、命令只展示不代跑。

**比调研时多做的两件事**：

- **歧义分两种，措辞分开**。原本只写了"两个 token 声明重名"这一种；实现时发现
  两份 staged 链接解析后指向**同一个 inode**（`firefox` 与 `firefox-beta` 都摆着同一份 `Firefox.app`）
  是强得多的信号，说成"名字撞上"等于把已知事实说小。`AppProvenance` 因此多一个
  `ambiguousByDeviceIdentity`，来源行与判定依据各自分叉。
- **来源识别排在测体积之前**。一条 stat 一次的开销，不该等 `DirectoryMetrics` 那几十秒
  才有徽章——列表刚出来就该说得出这一行是什么。

**没落地的（事实已经在结构里，界面上还没说出口）**：

- 「装于何时」：`CaskEvidence.installedAt`（收据的 `time`）已解析，UI 未渲染。
- `installedOnRequest`：能区分"用户主动装的"与"被依赖带进来的"，是下一轮 `brew leave`
  提示的现成凭据，本轮没做。
- `zapEntryCount`：只作为事实存在（`testZapEntryCountIsReportedAsAFact`），
  §4 那条"把 zap 清单喂进 `ResidualScanner`"仍未做——它是独立的一轮，别顺手混进来。
- **安装包档没有实机照片**：夹具运行刻意不读真机 `/var/db/receipts`，这台机器也没有
  bundleID 命中的包，所以该档只有单测与文案合同。

**真机对账**（`docs/verification/p7-brew/09-real-machine.jpg`）：44 个应用，3 个设备号级
cask 命中、9 个 MAS 收据、0 个安装包命中、0 个误报——其余全部如实落在「无法判定」。
