# Steam 启动器型 bundle 在卸载页里现在长什么样（P32a 审计，2026-10-10）

本文只回答一个问题：**这类 bundle 走到我们的界面上，被说成了什么**。不改代码，不改文案，
不预设 P32b 一定要做成哪样。所有数字都是这一轮实拍与现读得到的，出处在每行旁边。

## 0. 结论先行

1. **它被当成"一个很小的普通应用"**。照片上那一行是「SteamGame 1.0 593 字节」，
   详情四格是「应用大小 593 字节 · 包含文件 2 · 残留大小 524 KB · 残留项 3」，
   来源「无法判定」，运行状态「未检测到运行中的进程」，确认面板「合计 525 KB」。
   画面上没有一处说出"这是一个启动器，游戏本体不在这里"。
   参考项目对同一件事的原话是 Mole `lib/uninstall/steam.sh:5`
   "Its bundle size is the launcher's size, not the installed game"。
2. **反方向也已经成立，而且更要紧**：卸载 Steam 本体自己时，
   `~/Library/Application Support/Steam` 会作为一条「名称与包名对应」的谨慎残留出现在清单里，
   夹具里那一条量到 **25.2 MB**——那一个目录在真机上装着 `steamapps/common/` 下**所有已装游戏**。
   默认不勾选这一道挡住了误删（照片 08 里那一行的复选框是空的、页脚「已选 0 项残留 · 0 字节」），
   但那一条行上的说明是"可能包含登录态或未同步数据"，说的是账号，不是"这里面是你全部的游戏库"。
3. 所以 P32b 要做的不是"抄 Mole 那一格显示"，而是**两件事**：认出它是启动器（一句话的事），
   以及把"游戏本体在哪、有多大"这句话说得出口——两个方向（本体够不到、总目录收得进）都要说。

## 1. 本机实测：没有 Steam，所以全族靠夹具

| 事项 | 现读（2026-10-10） |
| --- | --- |
| `/Applications/Steam.app` | **不存在** |
| `~/Library/Application Support/Steam` | **不存在** |
| 结论 | 这一族没有 P31 那种"点名本机真在跑的应用"的对照档，八张全部来自 `/tmp` 假 home |

夹具：`Scripts/p32-steam-fixture.sh`，五种 bundle 各钉一件事——
`SteamGame.app`（可执行文件与 bundle 同名、有包标识，Mole 的识别合同走这一档）、
`SteamRunSh.app`（可执行文件叫 `run.sh`，Pearcleaner 写死的那个名字）、
`SteamNoId.app`（**整份 Info.plist 没有 `CFBundleIdentifier`**）、
`Steam.app`（启动器自己，包名 `com.valvesoftware.Steam`）、
`PlainTool.app`（对照组，本体 8 MiB 真实字节），
外加 `Applications/Steam Shortcuts/DeepShortcut.app`（藏在子目录里，用来钉"清单是全集还是子集"）。
游戏本体放在参考项目的同一个位置：`Library/Application Support/Steam/steamapps/common/SteamGame/`
（24 MiB 真实字节 + `steam_appid.txt`），账本 `appmanifest_<号>.acf` 三份。

## 2. 实拍事实（八张，`docs/verification/p32-steam/`）

每档的 `.log` 里都带三行哨兵：本体字节（`find -type f` 现算，口径同界面「本体」）、
游戏目录字节（**照片里不该出现的那个量**）、以及拍完之后的 `# post-shot:`。

| 档 | 画面上读到什么 | 独立哨兵对不对得上 |
| --- | --- | --- |
| 01 列表 + 详情（SteamGame） | 五行清单（PlainTool 8.4 MB / Steam 581 字节 / SteamGame 593 字节 +「3 项残留 524 KB」/ SteamNoId 518 字节 / SteamRunSh 516 字节），页头「5 个应用 · 合计 8.4 MB · 大小已实测」 | 593 B / 2 个文件 ✓；`DeepShortcut` **不在清单里** ✓（应用根非递归，`AppScanner.swift:41` 只枚举直接子项） |
| 02 详情（SteamNoId） | 「包名 —」「来源 无法判定」「残留大小 0 字节 · 残留项 0」「可执行文件 SteamNoId」 | 518 B ✓；无包标识 ⇒ 残留只剩名字这一条腿，而 `Application Support/Steam` 与它名字不同 ⇒ 0 项 ✓ |
| 03 详情（SteamRunSh） | 「可执行文件 run.sh」，其余与 02 同形 | 516 B ✓；`run.sh` 这一格现在只是把 plist 里的字符串抄出来（`MMUninstaller.swift:1735`），没人拿它当识别依据 |
| 04 确认面板（SteamGame，连残留） | 「应用 SteamGame / 来源 无法判定 / 包名 com.example.steamgame / 本体 593 字节 / 残留 1 项 · 524 KB / **合计 525 KB**」，两条路径：本体 + `Caches/com.example.steamgame` | 593 B ✓；**24 MiB 的游戏本体不在任何一行里** ✓ |
| 05 确认面板（SteamNoId） | 「本体 518 字节 / 残留 0 项 · 0 字节 / 合计 518 字节」 | 518 B ✓ |
| 06 详情（PlainTool 对照组） | 「应用大小 8.4 MB · 包含文件 3 · 残留 0 字节 · 残留项 0」；另有一处与本族无关的显示瑕疵见 §5 第 6 条 | 8,389,057 B ✓ |
| 07 详情下半（SteamGame，窗口 1400×1000） | 「将一并移除的残留」三条：`~/Library/Caches/com.example.steamgame`（包名完全对应，524 KB，安全，默认勾选）、`~/Library/Application Support/SteamGame`（名称与包名对应，1 MB，谨慎，默认不勾）、`~/Library/Preferences/com.example.steamgame.plist`（包名完全对应，0 字节，谨慎，默认不勾）；页脚「已选 1 项残留 · 524 KB」 | 三条都在**直接子项**那一层；`Steam/steamapps/common/SteamGame` 在第三层，一条都没有（见 §4） |
| 08 详情下半（**Steam 本体**，1400×1000） | 残留一条：`~/Library/Application Support/Steam` · 名称与包名对应 · **25.2 MB** · 谨慎 · 默认不勾；页脚「已选 0 项残留 · 0 字节」 | 与 §0 第 2 条同事实 |

八张里每一张都带着两条横幅：「`~/Applications` 不在这台机器上」和「读不到废纸篓 ·
Operation not permitted（错误码 1）」。前者是这台机器真没有 `~/Applications`（假 home 只换扫描根，
不换监听），后者是这台机器上这个从 `/tmp` 启动的 ad-hoc 产物没有完全磁盘访问——
两条都与本族无关，读照片时别把它当这一族的结论。

## 3. 参考项目怎么认定"这是一个启动器"，以及认定之后做了什么

| 项目 | 识别 | 认定之后 |
| --- | --- | --- |
| Mole | `lib/uninstall/steam.sh:19-62`：读 `Contents/Info.plist` 的 `CFBundleExecutable`（`steam.sh:25`），取不到才退回 bundle 文件名（`steam.sh:27-30`，连 `.APP` 大小写都兜）；那个文件必须存在、可读、可执行（`steam.sh:33-34`）；**≤4096 字节**（`steam.sh:41-42`）；首行必须是 sh/bash/zsh/env 的 shebang，非空非注释的**有效行正好一行**且匹配 `open steam://(run|rungameid|launch)/<数字>`（`steam.sh:44-58`） | **只改显示，不碰删除**：`bin/uninstall.sh:57-63` 把大小换成字面量 `N/A (Steam-managed)`，`lib/ui/app_selector.sh:25-26` 因为菜单只有 9 列宽再缩成 `Steam`，`lib/uninstall/batch.sh:1754-1757` 在确认行上同样换掉大小，`batch.sh:1774` 追一句提醒 "Steam launcher only; game files managed by Steam are not included" |
| Pearcleaner | 不解析脚本内容而是**按名字**去 `~/Library/Application Support/Steam/steamapps/common/` 里找同名目录（`Logic/AppInfoFetch.swift:593` 起的 `SteamAppInfoFetcher`，调用点 `:581-583`，命中即 `steam: true`，见 `:685`）；另有两处写死的对撞：`Logic/AppPathsFetch.swift:448-451` 读死 `Contents/MacOS/run.sh` 再 grep `steam://run/`，与 `appmanifest_<号>.acf` 文件名里的号对（`Logic/AppPathsFetch.swift:343-355`） | 它**主动把游戏目录当残留**：`Logic/Locations.swift:62` 把 `~/Desktop` 列为扫描根（注释 "for steam game shortcuts"），`:68-69` 把 `Steam/steamapps` 与 `steamapps/common` 也列为根 |
| disktree | 不认启动器，只把 `SteamLibrary`/`steamapps` 归类为 Media（`crates/disktree-core/src/classify.rs:164-166`），即"不可回收" | 无提示 |
| 其余（Epic / Battle.net / GOG / Ubisoft / itch.io / Amazon） | 四个参考仓库里对"别的平台的 launcher 脚本"**零命中**；Mole 只清它们的缓存（`lib/clean/app_caches.sh:1941-1947`） | 不做 |

两份参考对"那个脚本叫什么"**没有共识**（Mole 走 `CFBundleExecutable`，Pearcleaner 写死 `run.sh`），
所以夹具两种都做了（`SteamGame` / `SteamRunSh`）——实现时要兜住两个形状，而不是选一个边。
Mole 的测试夹具 `tests/uninstall_steam_launcher.bats:38-48` 用的包标识是
`com.example.steamgame`，而**真机上这类 bundle 常常根本没有包标识**
（`lib/uninstall/batch.sh:927-929` 与 `lib/clean/apps.sh:255-258` 两处注释都说过这件事），
所以夹具也做了 `SteamNoId.app`。

## 4. 为什么我们的机制正好错过它（同一件事的两面）

| 现象 | 机制 | 出处 |
| --- | --- | --- |
| 本体大小是真话，但不是"这个游戏有多大" | 「本体」= 遍历累加 `st_size` | `Packages/MMFileScanner/Sources/MMFileScanner/FileTreeWalker.swift:65`，取数在 `UninstallerModel.swift:343-355` 那一趟 |
| 游戏本体在任何一档都进不了残留清单 | `Application Support` 那条 entry（`ResidualScanner.swift:208`）没有传 `extraDescent`，默认 0（`init` 在 `:195`），下探层数 = 敏感度秩 + 0 ⇒ 严格 0 层 / 增强 1 层 / 深度 2 层；而 `Steam/steamapps/common/SteamGame` 在第三层。第二层 `common` 名字对不上就不再往下走。**另一条能探更深的路径也够不到**：Library 根那条 entry（`:218`，增强起、`extraDescent: 1`）在深度档层数到 3，最深检查到的是 `common` 这一层的名字，仍然不是游戏目录 | `ResidualScanner.swift:208`（entry）、`:218`（Library 根 entry）、`:239-242`（层数）、`:506`（取层数）、`:530-549`（逐层判，命中即停、不整目录收） |
| 但 Steam 本体自己会把整个游戏库当一条残留 | 同名直接子项，严格档第 0 层就命中「名称与包名对应」 | 同上 `:208` + `ResidualNameMatcher.swift:83-85`；风险档来自 `ResidualCategory.defaultRisk`（`applicationSupport` = caution，`:88-96`） |
| 没有包标识 ⇒ 证据面一起变窄 | `bundleIdentifier` 读不到就返回空串，界面上「包名 —」，来源必然「无法判定」，残留只剩名字一条腿 | `AppScanner.swift:63-67`、`MMUninstaller.swift:1731`、`AppProvenance.swift:40-48`（五档里没有"启动器"这一档） |
| 子目录里的快捷方式看不见 | 应用根只有 `/Applications` 与 `~/Applications`，且只枚举直接子项的 `.app` | `AppScanner.swift:27-29`、`:41`；照片 01/08 的清单里确实没有 `DeepShortcut` |
| 运行状态一律「未检测到」 | 这一族从没启动过（夹具是 shell 脚本，`open` 它会真的去叫 `steam://`，本机没有 Steam 只会弹报错） | 八张的「未检测到运行中的进程」；启动之后那一行会不会变，本轮**没测**（§6） |

一句话把两面缝起来：**我们既不会误删游戏（层数够不到），也完全说不出游戏在哪（同一句层数）**。
前者是运气还是设计？现在的答案是"清单语义的副产品"——`ResidualScanner.swift:528-529` 的注释写的是
"下探厂商目录（`~/Library/Application Support/Google/Chrome` 这种形态）"，
`Steam/steamapps/common` 恰好不在那个形状的覆盖范围里。P32b 不该把这句副产品当合同用。

## 5. P32b 建议清单（按"能不能一句话收口"排序，不含实现）

1. **事实层**：新增一个 `SteamLauncherProbe`，形状照 `RunningAppProbe.swift`——
   纯判定函数吃快照值 + 一个只读读取器，本文件零用户可见字符串。
   合同照 Mole 的边界（可执行文件存在/可读/可执行、≤4096 字节、首行 shebang、
   有效行正好一行、URL 三个动词、appid 取数字），**入口先取 `CFBundleExecutable`、
   取不到再试 `run.sh`**（把 §3 那处分歧兜住）。不做 realpath、不 spawn 任何进程。
2. **不要塞进 `AppProvenance.Source`**。那一档回答"谁装的"，这一档回答"它是什么"，
   两个维度正交：一个 brew 装的 Steam 启动器同时有这两句。落点是详情面板另起一行
   （与「来源」并列的 `MMKeyRow`），徽章只在识别成立时出现。
   这条要写在实现之前，否则下一轮就会有人往 `AppProvenance.swift:40-48` 那个枚举里加 case。
3. **措辞合同**：那句提醒只能说"这是 Steam 生成的启动器（appid 数字），本体大小只是启动器"，
   不许写"游戏在别处、我们不管"之外的猜测——我们**没有**去数过游戏目录（§4 第一行），
   所以既不能说"游戏有 N GB"，也不能说"这里没有你的游戏"。
   与 P31a「只有包名对上」那一档只说"写法不同"是同一条纪律。
4. **反向那一条优先于上面三条**：`Application Support/Steam` 作为 **Steam 本体**的残留出现时，
   行文案必须点名"这里面是 `steamapps` 下所有已装游戏"，或者给它一条排除/降级规则。
   两档待拍板：改措辞（只动呈现层）vs 改清单（动 `ResidualCatalog`，代价是别的厂商总目录要不要同规则）。
   这一条不需要识别启动器就能成立，所以它可以先做。
5. **取证缺口**：敏感度现在没有钩子（`MM_UNINSTALL_*` 那五个里没有它），
   所以"增强/深度两档到不到得了游戏目录"这一轮只有代码推导、没有照片。
   P32b 若要动 §4 那张表的任何一行，先把 `MM_UNINSTALL_SENSITIVITY` 做成钩子。
6. **顺带发现，与本族无关**：`CFBundleVersion` 缺失时「版本」那一行显示成 `1.0 ()`
   （照片 06 的 PlainTool 上能读到）。它属呈现层的一处空值口径，另开一格修，别混进 P32。

## 6. 本轮没测的（如实记）

- **启动一个脚本 bundle 之后**，「运行状态」那一行会不会变成「正在运行」：
  这一族从没 `open` 过它们（理由在 §4 最后一行）。
- **真机 Steam**：本机没装，所以 §0 第 2 条那个 25.2 MB 是夹具量出来的，
  真机上同一条行会是几十到几百 GB——这句话是推算，不是实测。
- **增强 / 深度两档的照片**：没有敏感度钩子，只有 §4 的代码推导。
- **`undetermined` 那一档**（P31 遗留）与本族无关，仍然只有单测。
- **Epic / Battle.net / GOG 的 launcher 脚本**：参考项目零命中，本轮也没造夹具。

## 7. 复现

```
./Scripts/make-app.sh -o /tmp/mm-app-p32 -s /tmp/mm-scratch-p32
./Scripts/p32-steam-capture.sh /tmp/mm-app-p32/MacMaster.app docs/verification/p32-steam light
ONLY=08 FIX=/tmp/macmaster-steam-fixture.XXXX ./Scripts/p32-steam-capture.sh …   # 重拍单档
```

产物与源码不同源时那一道指纹门禁会 exit 4 一张都不出（本族实跑命中过一次正向：
`# digest: tree=2d49642+e3b0c442 app=2d49642+e3b0c442`）。

**这一族的第一次实跑出过一次意外，记在这里而不是抹掉**：04 那一档（自动弹出"连残留一起"的
确认面板）第一次拍到的照片是**删除之后**的状态——列表少一行、一条「已卸载 2 项 · 532 KB」的
toast，而夹具目录里的 `Applications/SteamGame.app` 当场没了（那张照片仍在目录里，
叫 `incident-04-panel-opened-then-confirmed.png`）。代码上能走到删除的只有一处：
`MMUninstaller.swift:728-735` 那个 prominent 的「卸载」按钮；本脚本不发任何合成事件
（老规矩），所以最可能是那十秒钟里一次真实按键落在了我们自己的窗口上——
钩子自动把面板弹出来，而面板的默认按钮是破坏性的。
同一档重拍时 05 的面板就好好地开着（照片 05 是证据），所以这不是"每次都会发生"，
而是"会发生过一次，而当时的脚本没有能力发现自己看见了删除之后的画面"。
处置：脚本现在每档拍完都查一次自己的夹具目录，写 `# post-shot:` 并在本体消失时判这一档不作数
（`Scripts/p32-steam-capture.sh` 的 shot 尾部）。产品侧不改——一次回车确认删除是正常 macOS 交互，
要收的是取证脚本自己"弹面板 + 等十秒"这个跑法。
