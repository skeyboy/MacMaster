# P35a 审计：磁盘页跨卷枚举 +「最满的那卷优先」（v1.1 §2 第 4 条，判据侧的现状量尺）

本轮**只审计、代码一行未动**：证据是 `docs/verification/p35a-volumes/volumes.log` 头部那行
`# digest: 864f682+e3b0c442`——后半截 `e3b0c442` 是空输入的 sha256 前缀，也就是
"没有任何未提交编译输入"的机械自证（配方在 `Scripts/mm-provenance.sh:49-56`，
`Scripts/` 与 `docs/` 都不进编译输入）。

要回答的是路线上那一格的原话：**"磁盘页跨卷枚举 + 最满的那卷优先"**（`feature-roadmap.md:1051`）。
参考实现是 disktree 的 `volumes()`（"Every volume worth offering as a scan root, fullest first"，
`space.rs:540`）。本轮没有直接照任何一档落地，因为量完之后发现**三件被当成前提的事都不是真的**：

1. 「要像 disktree 那样排除 Data 卷，否则同一块盘数两次」——在 Foundation 的枚举面上，
   `/System/Volumes/Data` **根本不会被给出来**（实测：挂载表有、默认档没有），
   那笔债我们**不欠**；真正的重复在别处（见 §4）。
2. 「fullest first 就是把可用容量升序排」——disktree 的键确实是**可用字节升序**
   （`space.rs:591`），但那把键在本机把用户真正要清理的那块盘排到**第 9 / 共 14**（见 §5）。
3. 「默认枚举回来的是"用户看得见的卷"」——默认档 14 条里 **13 条是隐藏卷**，
   而且这个 SDK 里**没有** `.includeHiddenVolumes` 这个成员（现读编译核实），
   方向和大家以为的相反：默认档**已经包含**隐藏卷，要"少"才传 `.skipHiddenVolumes`（见 §3）。

---

## 1. 这一族怎么量的（两把尺子，都在同一个进程内）

| 尺子 | 拿什么 | 为什么用它 |
|---|---|---|
| Foundation 侧 | `FileManager.mountedVolumeURLs(includingResourceValuesForKeys:options:)` 跑两趟：`options=[]` 与 `[.skipHiddenVolumes]`，逐条读 `volumeIsBrowsable` / `volumeIsReadOnly` / `volumeIsRemovable` / `volumeIsEjectable` / `volumeIsLocal` / `isDirectory` + 三种可用容量 | 这是将来生产代码唯一允许用的入口（路线那一格明写"用 Foundation 的卷枚举"） |
| 挂载表侧 | 进程内 `getmntinfo(MNT_NOWAIT)` + 逐条 `statvfs`，解 `f_mntfromname` / `f_flags` / `f_fsid` / `f_bavail` | 它是"另一种判据"，也是 disktree 用来筛选与排序的那一份数据——**但它拿的是 `mount` 的文本输出**（`space.rs:647` `Command::new("mount")`），我们这一支只调系统调用，不 spawn 子进程 |

命令（`Scripts/p35a-volumes-probe.sh`，67 行）：

```
./Scripts/p35a-volumes-probe.sh              写 docs/verification/p35a-volumes/volumes.log
./Scripts/p35a-volumes-probe.sh --stdout     只打终端，不写证据目录
OUT=… ./Scripts/p35a-volumes-probe.sh        换输出目录（同族多跑必须换目录）
```

探针源文件单文件 `swiftc -parse-as-library` 编译（行数由日志头部自己印，这里不抄），**不链任何生产源文件**
（所以它测的是 Foundation、内核挂载表与这台机器，不是我们的代码）。全程只读：
不扫目录树、不写、不弹 `NSOpenPanel`、不 mount/diskutil、不请求权限。退出码恒为 0（量尺），
真正的门将落在 P35b 的单测与照片上。

这一支**没有夹具档**。原因是假的挂载表造不出来：要造就得动真系统或伪造内核返回，
两者都比"这一轮只量现状"贵。已知代价写在 §11。

---

## 2. 现状账（全部现读，`Sources` 与 `Packages` 的生产代码）

| 位置 | 现在做什么 | 与本轮问题的关系 |
|---|---|---|
| `MMDisk.swift:1432-1442` | `scanDirectory()` 弹 `NSOpenPanel`（只允许选目录、单选），选中后 `startAccessingSecurityScopedResource` 再 `scan(rootPath:)` | **磁盘页的根只有一个来源：用户手动选**。没有任何"列卷给用户挑"的入口 |
| `MMDisk.swift:1493-1499` | `totalSize` 走 `.volumeTotalCapacityKey`，读不到给 0 | 容量的"总"这一格 |
| `MMDisk.swift:1502-1512` | `freeSize` **先读"重要用途"口径**（`:1503-1505`），再回落普通口径（`:1507-1510`），`:1500-1501` 的注释写明"普通口径把 purgeable 算成已用，结果进度条常年 95% 满，和关于本机对不上" | 这就是本轮要选的"哪一把尺子"——**已经选过一次了**，在磁盘页 |
| `VolumeRoots.swift:243`+`:258`（**P49 现读重指**：这一格从前写 `:237`+`:252`，P49 改那段夹具档位的作废注释时净 +6 行把它顶下去了——**注释也进指纹、也进行号**） | **P35b 起这一格换了位置**：全站生产侧的卷枚举只剩这一处，`mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])`（默认档）+ 自己按 `browsable` 筛，不再直接要 `.skipHiddenVolumes` 的条数（为什么：§4 的去重要看挂载点，跳过隐藏卷就没有对账对象）。原 `DashboardModel.swift:75-76` 那一处已删（`:35` 现在是 `volumeCount: Int?`，读不到就是 nil，不写 0） | 上一版这条主张"**唯一**一处生产侧卷枚举"在写下时是真的，P35b 把它从"数条数"换成"取回一份带判据的快照"，**唯一性也仍然成立**——现跑 `grep -rn mountedVolumeURLs --include='*.swift' Packages Sources` 的非测试命中就是这一条 |
| `MainWindow.swift:280` | 页脚 `Text("\(volumeCount) 个卷")`（`:283` 是读不到那一支） | 那句话本机今天的读数是 **1**（§3 实测），不是"看起来应该有很多" |
| `MainWindow.swift:330` | 启动卷容量读不到时的文案："未能读取启动卷容量（volumeTotalCapacity / 重要用途可用容量均未返回），这里不猜数字。" | 已经有一条"读不到就说读不到"的合同，P35b 的新文案必须复用这个句式 |
| `SystemSampler.swift:143-152` | 启动卷容量：`.volumeTotalCapacityKey` + `.volumeAvailableCapacityForImportantUsageKey`，`:13-16` 的注释解释了为什么用重要用途口径（**P35b 把这一族键的字节对账也写进了同一段注释**） | 第三处口径选择点，与磁盘页同源 |
| `SystemSpaceReport.swift:70-81`（`Packages/MMFileScanner`） | 同一族键；`:30` 的注释已经写了「某些 APFS 卷上普通可用会大于重要用途可用，差额为负时不能说"可清除 -3 GB"」；`:64` 还写着「Data 卷与系统卷同一 APFS 容器，数字一致」 | **`:30` 本轮被实测坐实**：14 条里 `普通>重要` **12 条**、`普通<重要` 1 条、两口径都是 0 的 1 条（§7）。`:64` 那句 §4 也量到了同一机制 |
| `DiskRemovalTests.swift:184-186` | 测试里用 `[.skipHiddenVolumes]` 取第一条卷做删除夹具 | 测试与生产取的是同一档选项，但用途完全不同，不构成规格 |
| `MMDisk.swift:154-196` | 截图钩子 `MM_DISK_HOLD` / `MM_DISK_SCAN` / `MM_DISK_RESCAN`，扫描类钩子只认 `/tmp` 之下 | P35b 若要拍"多卷切换"的照片，这三个钩子是唯一合法入口 |

`volumeIsBrowsable` 在生产代码 **0 命中**（全仓唯一命中在探针源文件里）。
`getmntinfo` / `statvfs` 在生产代码里**调用 0 处**——全仓 `Sources` + `Packages` 的唯一命中是
`SystemSampler.swift:15` 那句**注释**（讲的是口径差，不是调用。**P35b 现读重指**：这一族注释本轮按 §10 第 6 条
改写过，含 "statvfs" 那一句从第 14 行挪到了第 15 行，整段现在是 `:13-16`），其余命中都在 `docs/` 的笔记与本轮的探针、取证日志里。也就是说：
**"跨卷"这件事现在不是"做得不完整"，而是根本还没有判据**——路线那一格写的"1 命中"是对的，
但它只说了条数，没说那一条数出来的 1 到底意味着什么（§3 把它量出来）。

---

## 3. 三档枚举的实测差：16 / 14 / 1

| 档 | 条数 | 本机是谁 |
|---|---|---|
| `getmntinfo` 挂载表全量 | **16** | 含 `/System/Volumes/Data` 与 `/dev`（devfs） |
| Foundation `options=[]` | **14** | 其中 **13 条 `browsable=否`** |
| Foundation `[.skipHiddenVolumes]` | **1** | 只剩启动卷 `/` |

两趟枚举耗时 **73 ms**（这一行含两趟与逐条 `resourceValues`，没拆细，不外推）。

默认档比 `.skipHiddenVolumes` 多出来的 13 条，按形态分四类，**每一类都不该出现在"你可以扫这些盘"的名单里**：

- **系统切片一族**（`/System/Volumes/` 下 Preboot / Update / VM / Hardware / xarts / iSCPreboot，加 `/Volumes/Recovery`）：
  它们带 `MNT_DONTBROWSE`，容量还和启动卷一模一样（§4）。
- **快照与只读分发卷**（cryptexd 下三条 `com.apple.iPhoneOS.SimulatorRuntime-*` / `MetalToolchain-*`，
  和 `/Library/Developer/CoreSimulator/Volumes/watchOS_23T570` 一族）：`readOnly=是`、`removable=是`、`ejectable=是`——
  在界面上它们会被说成"可移出的外置盘"，这是假话。
- **自动挂载占位**（`/System/Volumes/Data/home`，设备名 `map auto_home`）：`total=0`，占比算不出来。
- **稀疏设备假容量**（`/Users/lee/Library/Developer/CoreDevice/DeviceFS`）：`total=1024.0 GiB`、`avail普通=1024.0 GiB`
  → 使用率 0.0%，而它背后是 CoreDevice 的一个 file:// 目录。这一条最能说明**"容量条"不能当"盘"**。

**方向性的一条结论**：`volumeIsBrowsable`（Foundation）与 `MNT_DONTBROWSE`（挂载表）在本机
14 条上**逐条一致**——`两边都说可浏览=1  两边都说不可浏览=13  只有 Foundation 报=0  只有挂载表报=0`。
所以"要不要显示这一条"这一格**不需要**第二把尺子，Foundation 单独够用，
这一条是"不 spawn `mount` 不欠账"的直接证据（§6 有反面：`readOnly` 那一格两把尺子会打脸）。

---

## 4. 「同一块盘被数两次」的真正形态：不是 fsid，是同一对容量数

disktree 的去重键是**设备名 + fstype**，同一设备挂两处时保留最短挂载点
（`space.rs:557-576`，注释 `:543-547`）。这一条搬到本机来会失效，实测：

- **按 fsid 归组：默认档里没有任何一个 fsid 对应两条以上路径**（`space.rs:487` 那一套 `device_for` 我们不需要）。
- **按（total, avail普通）这一对数归组**：
  - `⚠（就是启动卷那一对）total=460.4 GiB avail普通=40.3 GiB 条数=5`
    —— `/`、`/System/Volumes/Preboot`、`/System/Volumes/Update`、`/System/Volumes/VM`、`/Volumes/Recovery`；
  - `· total=0.5 GiB avail普通=0.5 GiB 条数=3` —— Hardware / iSCPreboot / xarts；
  - 汇总：`默认档里有容量的条数=13，不同的容量对=7`。
- **按 APFS 容器归组**（设备名里 `diskN` 那一段）：
  - `容器 disk3：挂载点数=6  容量集合数=1  可用集合数=1`——6 个挂载点报的是**同一份** 460.4 GiB / 40.3 GiB，
    其中 5 个会进 Foundation 默认档，第 6 个（`/System/Volumes/Data`，`/dev/disk3s1`）**恰好不给**；
  - `容器 disk1：挂载点数=3` 同样同一对数。

**机制归因**：APFS 一个容器里几个卷共享同一个空闲池，`statfs`/`resourceValues` 对每个挂载点都回同一份
容器级数字（`SystemSpaceReport.swift:64` 那句"Data 卷与系统卷同一 APFS 容器，数字一致"说的是同一件事，
本轮把它从注释变成了分布数字）。所以"数卷"这件事在本机的正确问法不是"这块盘被挂了几次"，
而是**"这几个挂载点说的是不是同一份剩余空间"**。去重的键如果是 fsid 或设备名，
本机会把同一块盘数 5 次；如果按容量对（或容器），答案是 1。

`/Network` 一族本机**没有样本**（挂载表无、默认档无），disktree 的 `never_scanned`
（`space.rs:453`，名单 `:457` = `MACOS_DATA_VOLUME` 与 `/Network`）里那一半在本机不可测——写在 §11。

---

## 5. 「最满的那卷优先」：三把尺子给出三个不同的名单

同一批 14 条，各排一次（`—` = 占比算不出来）：

| 排序键 | 第一条 | `/` 的位置 | 100% 的条数 |
|---|---|---|---|
| 使用率，avail **普通** | cryptexd 的 `iPhoneOS.SimulatorRuntime-v24.1.94232.0`（97.3%） | 第 5（91.3%） | 0 |
| 使用率，avail **重要** | `/Library/Developer/CoreSimulator/Volumes/watchOS_23T570`（100.0%） | 第 13（91.2%） | **12** |
| 使用率，avail **机会** | 同上（100.0%） | 第 13（**93.7%**） | **12** |
| **可用字节升序**（disktree 的键，`space.rs:591`） | `/System/Volumes/Data/home`（0 B） | **第 9 / 共 14** | — |

读数原文（见日志的排序那一节，行号按 §13 的规矩不抄进文档）：`普通 vs 重要 排序相同=false`、
`重要 vs 机会 排序相同=true`、`启动卷 / 在这一把尺子下排第 9（默认档共 14 条，前面 8 条的可用字节都比它小）`。

三条都必须写进将来的判据：

1. **排序只能跑在候选根集合上**（§6：本机 = 1 条），不能跑在枚举全量上。
   跑在全量上时，"重要用途"口径会把 12 条系统卷报成 **100% 满**——
   因为它们的 `avail重要` 全是 0（13 条为 0），而 0 可用在百分比里没有"满"的含义，只有"这个口径没数"。
2. **绝对字节那把键在 macOS 的卷集合上是错的**。disktree 在 Linux 上用它没问题，因为它的候选根
   先被 `is_volume_candidate`（`space.rs:604` 起，按 fstype 白/黑名单）砍掉了伪文件系统；
   我们若只按"可用字节升序"排，0.5 GiB 的系统切片永远排在几十 GiB 可用的用户盘之前。
   → 排序键**用使用率**，并且**只在候选根上排**。
3. **口径要显式选一个并留在文案里**。磁盘页已经选了重要用途口径（`MMDisk.swift:1500-1512`），
   概览页那一格（`SystemSampler.swift:143-152`）也是同一口径，所以新加的卷名单**沿用同一口径**，
   不引入第四把尺子；`avail机会` 那一档本轮量了但**不用**（§9）。

---

## 6. 候选根：`browsable && isDirectory` 在本机给 1 条，`readOnly` 那一格两把尺子会打脸

- `默认档条数=14  候选根=1  被 browsable/isDirectory 挡掉的=13`，唯一的候选根是 `/`
  （`browsable=是  total=460.4 GiB  used%重要=91.2%  readOnly=否  local=是  removable=否`）。
- 13 条被挡掉的，**每一条的挡掉原因两把尺子都给得出**（Foundation `browsable=否` 且挂载表带 `MNT_DONTBROWSE`），
  没有一条是"只有其中一把尺子报"。
- **唯一一处打脸在"只读"这一格**：`⚠ /：Foundation readOnly=否  挂载表 MNT_RDONLY=是
  flags=0x4480d001 RDONLY|LOCAL|ROOTFS|JOURNALED|MULTILABEL|SNAPSHOT`；
  汇总 `默认档=14  两把尺子说同一件事=13  打脸=1`。
  **机制归因**：`/` 是只读系统卷，但 firmlink 把可写的 Data 卷拼进来，所以面向用户的 API 说"可写"，
  内核标志位说"这个挂载点是 RDONLY"。两句都对，但界面上只能有一句。
  → 将来的文案**不许**在这格写"这块盘是只读的/可写的"这种二值主张；
  要说得说成"根目录本身是系统卷，用户数据在另一个卷上（这里不显示）"或者干脆不说。
  这条与路线 §6 里"磁盘风险标签与删除闸门在 symlink 上口径不同"是同族问题（`feature-roadmap.md` §6 的"有意不修两条"）。
- `removable` / `ejectable` 那两格会把 4 条只读快照/分发卷说成"可移出"——
  **不许**据此在界面上写"外置盘"。

---

## 7. 容量口径对账：三处口径 + 一次对自家注释的现读复核

- **总容量**：14/14 条 `Foundation total 与 statfs 同数`（`blocks × f_bsize`），没有一条打脸。
  `statvfs` 的 `blocks × frsize` 也同数。disktree 那条"`f_frsize` 为 0 就回落 `f_bsize`"的兜底
  （`space.rs:61-67`）**本轮补了直接读数**：本机挂载表 16 条里触发回落的 = **0 条**
  （日志头部那一行）——是"这台机器上 `statvfs` 一直给得出 `f_frsize`"，不是"这条支路不需要"。
- **可用**：以 `/` 为例，
  `avail普通=40.3 GiB (43244281856 B)`、`avail重要=40.6 GiB (43595157504 B)`、`avail机会=28.8 GiB (30905741312 B)`、
  `statvfs f_bavail=40.3 GiB (43244294144 B)`。
  → `f_bavail` 与 Foundation 普通口径只差 **12288 B**；与重要口径差 **350863360 B（≈0.33 GiB）**。
  两个"40.3 GiB"在 GiB 精度上相同、字节上不同（差 12288 B），所以**对账必须到字节**，看界面数字会以为两者本来就是一回事。
- **现读复核我们自己的一句旧账**：审计当时 `SystemSampler.swift` 第 13-14 行写着（旧树坐标，按 §7.7 裸写）
  "用 statvfs 的 `f_bavail` 会比访达少好几 GB"。本轮**没有量访达**（要拍 Finder 才能对账），
  但量到了同一台机器上 `f_bavail` 与两种 Foundation 口径的差：与重要口径差 0.33 GiB，不是"好几 GB"。
  → 这句注释的**量级**在今天这台机器上已经撑不住它想表达的意思（"两者差到不能混用"仍然成立，但差值是 0.3 GiB 级）。
  本轮不改代码，所以只在 §12 的检查单里给它挂一条待办：**要么把注释改成量出来的口径差，要么补一次与访达的实拍对账**。
  → **P35b 落了前一个选项**：整段注释现在在 `SystemSampler.swift:13-16`，写的是量出来的两个差值
  （与重要口径差 350,863,360 B、与普通口径差 12,288 B），并明写「访达那一侧 P35a 没量，本轮不替它担保」——
  **"少好几 GB"那句虚量级已从源码里消失**，实拍对账仍没做。
- **三档可用不是单调梯子**：`机会 < 普通 < 重要`（28.8 / 40.3 / 40.6 GiB），
  且 14 条里 `普通>重要` **12 条**、`普通<重要` 1 条（只有 `/`）、相等 1 条（`/System/Volumes/Data/home` 两口径都是 0），
  `avail重要` 读到 0 的共 **13 条**——这把 `SystemSpaceReport.swift:30` 那条注释**坐实**了（它以前只有推理，没有分布数字）。

---

## 8. 代价

一趟两档枚举 + 逐条 `resourceValues` + 全量挂载表 = **73 ms**（本机 14 条卷）。
这个数**不构成"每次界面刷新都重枚举一次"的许可**：

- 它没有拆分枚举 / 读取 / `statvfs` 三段，只有一条总时间；
- 条数是 14，换成接了 8 个外置卷的机器没有量过；
- 参照 P34a 那一族的规矩（`optimizer-corrupt-preferences.md` §8），**测量本身不产出策略**，
  刷新时点要和 P31a 一样显式列出来并钉进单测（载入时 / 用户主动切卷时；**不轮询、不设定时器**）。

---

## 9. 呈现落点与三档建议

| 档 | 内容 | 判据落点 | 单测钉什么 | 照片钉什么 | 本轮推荐 |
|---|---|---|---|---|---|
| **A** | 磁盘页页头把"分析对象"说全：现在选的根 + 它所在卷的容量 + **"这台机器还有 N 卷可切"**（N = 候选根数 − 1，`N=0` 时这一句**不出现**） | `Packages/MMDisk` 新增纯函数层（候选根筛选 + 去重键 + 排序键），界面只吃数组 | 候选根筛选（喂假 `[Row]`：browsable 否 / isDirectory 否 / total=0 / removable 快照各一条）、容量对去重（§4 那 5 条压成 1 条）、排序键（同一批数据在两种口径下各钉一条） | 本机不挂第二块卷时候选根=1 ⟹ 正分支（"还有 N 卷"）**当时只能由夹具出照片**，与 P34a 健康机器上那一屏同一句话；负分支（不出现那句话）可以实拍。**〔P49 更正：这一格"只能由夹具"已经不成立〕** `Scripts/p49-external-volume-fixture.sh` 用 `hdiutil` 挂一块 APFS 镜像卷，它就是一个真的可浏览候选根（探针读数是「默认档条数=15 候选根=2 被 browsable/isDirectory 挡掉的=13」），正分支有这台机器的实拍：`docs/verification/p49-external-volume/03-disk-mounted-badge.png`（页头「这台机器还有 1 卷可以切换分析」）与 `05-overview-mounted-count.png`（页脚「2 个卷」），卸载对照是 04/06；`MM_VOLUME_FIXTURE=two` 那一档降级成"跟实拍对账"的一档 | ✅ 做 |
| **B** | 概览页页脚 `"\(model.volumeCount) 个卷"` 的**口径换掉**：从"`.skipHiddenVolumes` 的条数"改成 A 档的"候选根数"。今天两者都是 1，所以**画面上看不出来**，但语义不同：前者是"没被标隐藏的挂载点"，后者是"我们能扫的卷" | **P35a 当时读到的两处**是 `DashboardModel.swift` 第 75-76 行与 `MainWindow.swift` 第 278 行（旧树坐标，按 §7.7 那条写法约束裸写）。**P35b 落点**：新加的 `DashboardModel.swift:167` 那个 `refreshVolumeRoots()`（属性在 `:35`，类型是 `Int?`）；页脚在 `MainWindow.swift:279-285`——有数那一支文案不变，变的是它下面多了一条 nil 分支 | 纯函数已钉；这一层再加一条"两者在假数据上可以不等"的钉子（例：一条 `.skipHiddenVolumes` 档枚举得到、`browsable` 筛不掉的样本。**这一格此前写的是那个选项名的半截省略式**，而半截名在全仓源码词汇表里不存在——引用门禁符号面报的那两条死符号就是它，那条账记在 `release-readiness.md` §1 的 P35b 八读那一格，本轮按它把名字写全，两条随之归零） | 与 A 同一批照片 | ✅ 做（与 A 同轮，因为它不新增屏） |
| **C** | 真正的多卷切换器（下拉选卷 → 换根重扫） | 要动 `MMDisk.swift:1432-1442` 的根来源（**P35b 现读**，P35a 那一版写的是 1416-1426，同一支被这一轮往上顶了 16 行）、`DiskMarks.reattach`（`:1537`）的 rootPath 语义、扫描缓存，以及 `MM_DISK_SCAN` 钩子（`:154-196`，它只认 `/tmp` 之下，而真卷根不在 `/tmp`） | — | 需要**外置卷实拍**——**〔P49 更正〕** 这一格从前写"本机零样本"，现在不是：`hdiutil` 挂的镜像卷就是外置卷的形状，`docs/verification/p49-external-volume/` 那七张拍到了它进候选根、进徽标计数、进页脚。但 C 档要的"选中另一卷再重扫"仍然没有证据也没有实现：`MM_DISK_SCAN` 只认 `/tmp` 之下的根，真卷根不在 `/tmp`，而换根重扫要动的东西见本行第 3 格 | ❌ 暂缓，另开版本（它一改就作废磁盘页全部像素基线，属 v1.3 那类"版本边界 = 照片边界"的事；**P49 之后这条理由不再包含"照片拍不出来"那句**） |

推荐 **A + B 同轮**，C 另开。理由：A 的判据全是纯函数（可钉单测），
B 是 A 的免费副产品；而 C 需要的那张照片当时拍不出来（本机没有第二块可扫的卷），
强行做就只能靠合成 UI 事件——那是本仓库明令禁止的（P31a 也吃过这条）。**〔P49 更正这一句的前提〕**：那块"根本不存在的第二块卷"现在造得出来（`Scripts/p49-external-volume-fixture.sh` 挂 `hdiutil` 镜像卷），照片也拍了，所以 C 的暂缓理由只剩"一改作废磁盘页全部像素基线"那一条，不再有"证据拿不到"这一条。

**A 档的文案合同**（沿用 `MainWindow.swift:330` 那句"这里不猜数字"的句式）：

| 状态 | 允许说 | 禁止说 |
|---|---|---|
| 候选根 > 1 | 「这台机器还有 N 卷可以切换分析」 | 「N 块硬盘」（卷 ≠ 物理盘，§4 已证同一容器 6 个挂载点） |
| 候选根 = 1 | **不说这一句**（缺席就是缺席，不写"只有 1 卷"这种自证） | 「没有其他卷」（我们只查了 Foundation 的默认档，没查网络卷） |
| 枚举返回 nil 或 0 条 | 「未能读取卷列表，这里不猜数字」 | 把 0 说成"只有系统卷" |
| 某条 total 读不到 / 为 0 | 直接从名单里去掉，不报占比 | 当成 0% 或 100% 参与排序 |

主人名、设备名（`/dev/disk3s5s1`）这类**证据**进 `caveat` 那一格，不进 `reason`——
套 `DevToolCacheEntry` 已有的分工（`DevToolCacheAudit.swift:37-69` 的字段划分、`:51` 的 caveat 注释、
`:31-34` 的 `reason` 是 `.lineLimit(1)` 那一族）。

---

## 10. 明确不做（写在这里是为了下一轮别当新候选再提）

1. **不 spawn `mount`**，也不解析它的文本（`space.rs:647` 那一套）。挂载表这一格如果将来生产代码要用，
   走 `getmntinfo`——本轮已经证明"候选根"这一格 **Foundation 单独就够**（§3 零打脸）。
2. **不把 `getmntinfo` 的 16 条全量端给界面**。全量只用于交叉对读。
3. **不用绝对可用字节做排序键**（§5 第 2 条，本机实测会把用户盘排到第 9）。
4. **不引入第四把可用容量尺子**：`avail机会` 本轮量了，不进界面。
5. **不请求新权限、不弹 TCC**：`mountedVolumeURLs` 与 `getmntinfo` 都是零权限只读。
6. **不做"一次扫全部卷"**：跨卷扫描的代价、越界（系统卷、快照卷）与结果合并语义都没定义，
   而且和 C 档绑在一起，本机也没有能证明它成立的照片。
7. **不在 `readOnly` 那一格写二值主张**（§6 的打脸条）。
8. **不学 disktree 的 `never_scanned` 名单**去排除 `/System/Volumes/Data`——
   Foundation 不给它（§4），加这条排除是**给一个不存在的入口写代码**。

---

## 11. 本轮没能确认的（下一轮先问这几句）

1. **外接卷 / 网络卷 / 加密卷 / 多容器 APFS 全盘是零样本**（**P49 收掉外接卷那一半**：
   `Scripts/p49-external-volume-fixture.sh` 用 `hdiutil` 挂了一块 APFS 镜像卷，§9-A 的正分支与 §6 的候选根数
   现在有了这台机器的读数，见 `docs/verification/p49-external-volume/`；网络卷、加密卷、同一型号两块独立外置盘
   仍然零样本，§4 那个容量对去重键的"两块独立同容量外置盘会被并成一条"也仍然只有单测）。
   本机一块内部盘、14 条里 13 条隐藏，所以 §4 的去重键、§6 的候选根数、§9-A 的正分支都**只在这台机器上成立**。
   要收口剩下的几档必须换一台插了外置盘的机器，或由用户手动挂一个网络卷再拍——本轮**没有**为了拍照去动系统设置。
2. **`/System/Volumes/Data` 缺席的因果**：量到的是"它带 `MNT_DONTBROWSE` 且默认档不给"，
   两者谁决定谁没量（可能是 Foundation 按 DONTBROWSE 过滤，也可能是它自己有一份 firmlink 去重）。
   这不影响判据（我们不依赖它），但影响"能不能把 browsable 当唯一闸门"的信心。
3. **访达 / 「关于本机」那个可用数字本轮没量**，所以 §7 那条旧注释只做到"量级不再成立"，
   做不到"注释是假的"这一句。
4. **73 ms 没拆段**（枚举 / `resourceValues` / `statvfs` 各占多少不知道），也没有第二条机器做对照。
5. **这一族没有夹具档**：**P35b 已作废这一条**——实现轮补了 `MM_VOLUME_FIXTURE`（`off|two|zero|fail`），
   理由与代价记在 §14 第 3 条。P35a 当时写下的原文是：假的挂载表要造假 `getmntinfo` 返回或动真系统，都比本轮目的贵。
   代价是 §9-A 的正分支只能靠喂给纯函数的假 `[Row]` 钉规则，**界面上那一行将只有实拍负分支 + 单测正分支**，
   与 P31a 那一条"合成值只能证明界面会写字"的口径一致，文档里要明写。
   **〔P49 作废这一条的"只能"〕**：正分支现在有这台机器的实拍（挂 `hdiutil` 镜像卷，
   `docs/verification/p49-external-volume/03-disk-mounted-badge.png` 与 `05-overview-mounted-count.png`），
   "合成值只证明界面会写字"那句对 `zero`/`fail` 两档仍然成立，对 `two` 已经不是唯一的证据来源了。

---

## 12. P35b 检查单（实现轮——**已做完，逐条结果与五条偏离记在 §14**）

1. 纯函数层：`候选根筛选`（browsable && isDirectory && total>0）、`按容量对去重`、
   `按使用率排序（显式口径参数，默认重要用途）`、`读不到排最后`。
   **不假装单测能读到系统状态**——四把喂进去的都是假 `[Row]`（照 P31a `resolve(bundleID:bundlePath:running:)` 的写法）。
2. 否证钉子：`skipHiddenVolumes 档给的条数 ≠ browsable 档给的条数` 至少一条假样本（§9-B）。
3. 界面接入：A 档那一行只在候选根 > 1 时出现；B 档把 `DashboardModel.swift:79-80` 换成调纯函数。
   → **P35b 落点**：那两行（`.skipHiddenVolumes` 数条数）**已从源码删除**，同一位置现在是不读卷名单的那两条注释
   （`DashboardModel.swift:79-80`）；调纯函数的那一处是 `:167` 的 `refreshVolumeRoots()`，属性在 `:35`。
   A 档那一行的正分支在本机不出现（候选根 = 1），只有单测钉住规则——这一句与 §9-A 同一口径。
   **〔P49 更正〕**：这一句记的是 P35b 那一跑的现场，今天挂上镜像卷就能让候选根 = 2、那一行真的出现在页头；口径以 §9-A 那一格的更正版为准。
4. 刷新时点写死并钉进单测：载入清单 / 用户主动切卷两处；**无定时器、不轮询、不跟随选中项**（照 P31a §9 那条）。
5. 文案按 §9 的合同表逐格实现；`caveat` 与 `reason` 的分工不许串门。
6. 顺手修 `SystemSampler.swift:13-16` 那句注释的量级（§7）：改成量出来的口径差，或补一次访达实拍对账——
   **注释进指纹**，改它就要重建 + 整族重跑照片（P31a 那次就是这么处理的）。
   → **P35b 选了前一个选项**，那一句"少好几 GB"已换成量出来的两个差值；实拍对账仍没做（§7 那条待办还挂着）。
7. 九包重跑 + 结论行入库；动编译输入 → 前后两族照片 + `# digest:` 当场同源（路线 §7 第 1 条那道门禁）。

---

## 13. 证据、命令与门禁

| 文件 | 是什么 | 怎么再跑 |
|---|---|---|
| `Scripts/p35a-volumes-probe.sh` | 入口，67 行 | `./Scripts/p35a-volumes-probe.sh`（`--stdout` 只打终端，`OUT=…` 换目录） |
| `Scripts/p35a-volumes-probe.swift` | 探针本体，**不链任何生产源文件**（行数由日志头部自己印） | 由上一支编译，不单独跑 |
| `docs/verification/p35a-volumes/volumes.log` | 本轮唯一的读数（行数不抄进文档：重跑一次就漂，抄一次多一个副本面） | 同第一支 |

`# repo:` 与 `# digest:` 那两行以日志文件自己为准（§0 只引了 `e3b0c442` 那半截，因为它答的是"有没有未提交的编译输入"，配方决定它不会漂）。
`Scripts/` 与 `docs/` 都不进编译输入，所以本轮的指纹后半截与提交前那一份同源——
**代码一行未动**由它自己证明。

探针内部的关键位置（要复核判据时按这些跳，别在本文档里复述数字）：
入口在 `:63`，挂载表采集在 `:130`，同盘归组在 `:162`，三种口径排序与 `avail` 逐条比在 `:225`，
候选根与两把尺子对读在 `:309`，容器键在 `:398`，启动卷单独一行在 `:409`，
`statfs` 字段读法在 `:446`。

引用门禁（`Scripts/p16-citation-audit.sh`）本轮跑两次并各存一份：**提交前**与**提交后**，
顺序按路线 §7 第 4 条（门禁读暂存区，跑反了会记一笔假账）。
读数登记在两份日志自己的头部与结论行里，**本文档不抄这些数**——
因为这一节新增的引用会让下一跑的总数漂移，抄一次就多一个对不上的副本面。

本轮写这份文档时**自己抓出来并已修**的五处假话（记下来是因为它们都是"顺手写的解释"，不是判据）：

1. 探针一度把 disktree 那把键的本机后果写成"有 13 条比 `/` 小"，而同一份日志实测 `/` 排第 9 / 共 14、
   前面 8 条——那句解释与它自己旁边的读数对不上。改成由 `idx` 现场算出来打印，
   散文里不再写死条数。
2. 格式化那一格用 `%d` 打字节数，把 3.1 GiB 那卷打成 `-998244352 B`（超过 Int32 就回绕）。
   字节数改走整数插值。**这条如果留到生产代码里就是"负容量"的显示假账**，
   和 `SystemSpaceReport.swift:30` 防的是同一族。
3. 容器归组那一节最初把"这条路径在不在默认档枚举里"标成了"browsable 在默认档"，
   两个不同的问法共用了一格标签。标签改为"在默认档枚举里"。
4. §7 原先写「14 条里 `普通>重要` **13 条**、相等 **0** 条」——那是**我逐行数每行读数**数出来的，
   把 `/System/Volumes/Data/home`（两个口径都读到 0）算进了"普通>重要"。
   本轮给探针补了直接打印，终版读数是 `普通>重要=12  普通<重要=1  相等=1`。
   **教训**：文档里凡是自己数出来的分布数字，先想办法让它变成打印出来的。
5. §7 的 `f_frsize` 兜底那一格原先只有推断（"本机用不上"），没有读数。
   本轮补成直接读数（挂载表 16 条里触发回落 **0 条**），并把这句写进日志头部——
   **量不到的时候要说"这台机器给不出这一格"，不能说"不需要这一格"。**

---

## 14. P35b 实现结果（与 §9/§12 的偏离逐条记在这里）

实现轮：`Packages/MMCore/Sources/MMCore/VolumeRoots.swift`（判据层）+ 磁盘页与概览页两处接入 +
`Scripts/p35b-volumes-capture.sh`（八档照片）。**下面五条是本轮相对 §9/§12 的字面写法改动的地方**，
每条都写清"改了什么、为什么、判据落在哪"，别让下一个人从 §9 的表里读出一个人没做过的形状。

1. **判据层落在 MMCore，不是 §9-A 原写的 MMDisk。**
   理由只有一条：两个消费方里有一个是壳（概览页页脚），而壳工程不 import MMDisk
   （它 import MMCore/MMUI/MMOptimizer/MMCleaner/MMFileScanner/MMMonitor）。
   为一个只读的系统枚举让壳依赖一个功能模块，代价大于收益。
   这条偏离同时记在 `docs/design-system/README.md` §2 的 MMCore 那一段。
2. **A 档那一行没进页头副标题，进的是面包屑条的徽标位。**
   §9-A 的原话是"页头把分析对象说全"，但页头副标题被 `DiskHeaderContractTests` 钉成
   **正好三段、且不含秒数**（那是 `header-truncation-audit.md` §3/§8 两轮实拍逼出来的合同），
   再塞一句带数字的话进去就是把刚修好的截断缺陷重新引进来。
   面包屑条右侧本来就有「未纳入 N 个受保护目录」与「卷可用 X」两枚 `MMBadge`，
   §9-A 要的"现在选的根 + 它所在卷的容量"这两格**已经在那一列上**，A 档新增的只有第三枚。
3. **`MM_VOLUME_FIXTURE` 这一支钩子是 §11.5 那条"这一族没有夹具档"的作废声明。**
   不是违背 §11.5，是 §9-A 自己写明了正分支"只能由夹具出照片"，而 P35a 判断"造夹具比本轮目的贵"
   的前提在实现轮不成立：要造的不是挂载表，是一个 `[VolumeRootRow]` 数组（纯函数已经吃这个形状）。
   四档 `off|two|zero|fail`，台账见 `hook-ledger.md`。
4. **B 档的"文案不变"（§12 第 3 条）只做到一半**：`N 个卷` 这一句不变，
   但"一行都没读到"那一格必须换——照 §9 合同表第三行它不能说"0 个卷"，
   于是走全站那一句"这里不猜数字"的句式：页脚显示占位 `— 个卷` + `.help("未能读取卷列表，这里不猜数字")`。
   `DashboardModel.volumeCount` 因此从 `Int` 变成 `Int?`（nil 与 0 是两件事，这正是 §9 第三行与第四行的分界）。
5. **刷新时点**（§12 第 4 条）：磁盘页 = **扫描结果落地那一次**（`scan(rootPath:)` 提交前读，
   跟 `volumeRoots` 一起进 `MainActor.run`）；概览页 = **`measureReclaimable()` 的开头**，
   而它只在载入首帧与用户点「重新测量」时被起。两处都不是定时器、不轮询、不跟随选中项。
   §8 那个 73 ms 因此一次界面刷新最多花一趟，而不是每 2 s 花一趟（旧的 `volumeCount` 恰恰挂在 2 s 采样里，本轮把它从那一条路上摘下来了）。

**本轮自己抓出来的两处假绿，都是这一族的老坑**（记下来是因为它们都不是判据层的错，是取证层的）：

1. 留痕行写成 `"MM_VOLUME_FIXTURE=\tier.rawValue 已生效…"`——`\(…)` 少了括号，`\t` 被当制表符，
   stderr 打出来是「=〈TAB〉ier.rawValue 已生效」。**照片照常拍到徽标、日志照常有一行"已生效"**，
   而这一族唯一的机械判据（P6.6/P6.7 立起来的那一条）当场失效。
   现在那句是 `VolumeFixtureTier.appliedNote` 纯函数，`testAppliedNoteNamesTheTier` 钉档位名必须出现在里面。
2. 概览页那两档（07/08）第一版漏传了 `shot` 的第四个参数（页别），于是 07 拍的还是磁盘页，
   而且**与 06 逐字节相同**——同一页、同一夹具、同一窗宽、那一屏没有任何会走的字段。
   md5 交叉核对当时一句都没响，因为它只比了"注入档 vs 真机档"。
   现在每档的 `.log` 都写一行 `# 页：disk|overview`，核对块逐档断言它，另加一条 06↔07 不许相同的兜底。

**证据**（`docs/verification/p35b-volumes/`，八档 light 全族 + `p35b-volumes-dark/` 一份暗档）：
01 真机负分支（那一格缺席）· 02 夹具 two（「这台机器还有 1 卷可以切换分析」）·
03 夹具 zero（有挂载点、零候选根，仍然缺席——判据在留痕行）· 04 夹具 fail（「未能读取卷列表，这里不猜数字」）·
05 夹具 two 窄窗 1000×760（这一族最长的一句在硬最小宽度下不截断）· 06 非法取值 `tw0`（整支作废 + stderr 留痕）·
07 概览页真机档（页脚「1 个卷」）· 08 概览页 fail（页脚「— 个卷」）。
**01/07 那两张"什么都没写"的照片单独是不可证的**——空那一格既可能是"量到 1 所以不说"，
也可能是"根本没跑"。所以同日重跑了 `Scripts/p35a-volumes-probe.sh` 到
`docs/verification/p35b-volumes-probe/`：同一台机器、**同一个 `# digest:`**（探针与产物一致），
读数是 `默认档条数=14 候选根=1 被 browsable/isDirectory 挡掉的=13`。
这两张照片 + 这一行读数合起来才是负分支的证据；单看照片不算。

**仍然没收口的还是 §11 那四条**（外接卷/网络卷零样本、Data 卷缺席的因果、访达那一侧没量、73 ms 没拆段；
**P49 收了第一条的外接卷那一半**——`docs/verification/p49-external-volume/` 七张是挂镜像卷的实拍，网络卷/加密卷仍然零样本），
本轮没有为它们增加任何证据；C 档（一键换卷重扫）继续暂缓，理由只剩"一改作废磁盘页全部像素基线"，**不再包含"照片拍不出来"**，
徽标那句的 `caveat` 里已经写明"一键换卷的重扫还没做，现在按「选择目录」走到那卷上的任意目录"。

## 15. P49 追加（2026-10-16）：挂一块镜像卷，把"外接卷"这一族从合成快照换成这台机器的读数

§11 第一条的外接卷那一半、§14 那句"照片拍不出来"，本轮一起收。做法不是加钩子，是**造一块真卷**：
`Scripts/p49-external-volume-fixture.sh`（`create` / `mount` / `seed` / `detach` / `clean` / `info`）用
`hdiutil create -fs APFS -format UDRW` 在 `/tmp/mm-p49-volume/MMVolumeP49.dmg` 造一块 122 840 KB 的可读写镜像，
挂到 `/Volumes/MMVolumeP49`，往卷里的 `Applications` 放一个只有 Info.plist、不链可执行文件、不签名的
`AaaP49VolumeFixture.app`。**为什么是 UDRW 而不是只读压缩镜像**：取证中途还要往卷里 `seed`，只读镜像做不到。
**为什么故意不做签名**：`AppScanner` 那一路只直接读 plist，签名读不到时 developer/teamID 就是空串，
照片上"未签名第三方"是正常一档，不是夹具的缺陷。

### 15.1 探针先量，照片后拍

同一日把 `Scripts/p35a-volumes-probe.sh` 重跑在挂载态上，归档在
`docs/verification/p49-external-volume/volumes.log`，读数是
`默认档条数=15 候选根=2 被 browsable/isDirectory 挡掉的=13`。
对 §14 那一行（`14 / 1 / 13`）的差**只有一条**：多出来的正是这块卷，被挡掉的 13 条一条没变。
这一句是本轮唯一的交叉验证——它排掉了"候选根从 1 变 2 是因为别的卷形状变了"这一读法。
**这块卷在挂载表里的标志位是 `NOSUID|NODEV|REMOVABLE|IGNORE_OWNERSHIP|LOCAL|JOURNALED|MULTILABEL`**，
`removable=是`、`readOnly=否`，也就是说它走的是和一块真 U 盘同一条判定链，不是靠某个特例进来的。

### 15.2 四张磁盘/概览侧照片，各钉哪一句

`Scripts/p49-external-volume-capture.sh` 七档里 03~06 属于本页（01/02/07 是卸载页，记在
`fidelity-uninstaller.md` §16）。七份 `.log` 头部同一个
`# digest: tree=0d122f9+b539b844 app=0d122f9+b539b844`，**照片、二进制、跑测的输入同源**；
03~06 这四档全程不注 `MM_VOLUME_FIXTURE`，脚本末尾有一条判据专门盯这件事（日志里出现那个钩子名就算这一档没读真机）。

| 档 | 画面读数 | 钉住的东西 |
|---|---|---|
| 03 挂载态 · 磁盘页 | 页头面包屑条右端「这台机器还有 **1** 卷可以切换分析」 | 这一句的正分支第一次是**这台机器的读数**，不是合成快照 |
| 04 卸盘 · 磁盘页 | 同一格**缺席**，只剩「未纳入 1 个受保护目录」「卷可用 40.25 GB」 | 缺席档也是实拍；判据是"这一格没画"，由挂载态留痕背书 |
| 05 挂载态 · 概览页 | 页脚「**2** 个卷 · 文件系统 APFS」 | 口径从"挂载点条数"换成候选根数之后，2 这个值第一次有照片 |
| 06 卸盘 · 概览页 | 页脚「**1** 个卷」 | 同一句的另一端 |

**03↔04 那一对像素差（4612 个像素、最大幅度 209）不能当判据**——两帧里「卷可用」从 39.27 GB 漂到 40.25 GB
是这台机器在这一刻真的多出了 1 GB 空闲，跟徽标没关系。徽标本身占的像素在这个数里连零头都不到。
**05↔06 干脆不做像素判据**（脚本里标 `ℹ`）：概览页有"上次采样 刚刚"和网络/磁盘速率柱，两帧必然不同。
这两对画面靠的是人眼读上面那四个字 + 每份 `.log` 头部那行「# 卷：/Volumes/MMVolumeP49 已挂载 / 未挂载」，
后者由脚本逐档核对，声明的挂载态与留痕不符就判红。

### 15.3 附带收掉的一条跳过测试

`Packages/MMDisk/Tests/MMDiskTests/DiskRemovalTests.swift:183` 的 `testMountedVolumeRootIsBlocked`
是全仓唯一一条 `skipped`，跳过理由原文 `本机没有第二块挂载卷`（现读：函数声明在 `:183`、`try XCTSkipIf` 在 `:189`，
`release-readiness.md` §1 那一格从前写的是 `:167` / `:173`，本轮已重指）。
**这条测试是纯只读的**（枚举挂载卷、在内存里组一个 `DiskRemoval.plan`），所以趁卷还挂着跑一次就能真执行：

```
挂载态：MMDisk XCTest=85 swift-testing=0 skipped=0  ⟹ 该条 passed (0.002 seconds)
卸盘后：MMDisk XCTest=85 swift-testing=0 skipped=1  ⟹ 回到原状
```

两跑合起来才算数——单看第一跑，"skipped 从 1 变 0"既可能是挂载态给的、也可能是 `run-all-tests.sh`
的计数口径变了。归档在 `docs/verification/p49-external-volume/mmdisk-tests-mounted.log`（两跑都在同一份里）。
**§1 那张表里的 `跳过 = 1` 没作废**：它记的是不挂卷时的基线档。

### 15.4 这一轮仍然没碰的

网络卷、加密卷、同型号两块盘、Data 卷缺席的因果、访达那一侧、73 ms 没拆段——**一条没量**；
本轮只把"外接卷"这一格从"零样本"改成"一块镜像卷、一个 plist-only 应用"。
C 档（一键换卷重扫）继续暂缓。重跑配方：
`./Scripts/p49-external-volume-fixture.sh create && … mount && … seed AaaP49VolumeFixture`，
再 `KEEP_MOUNT=1 ./Scripts/p49-external-volume-capture.sh <app> <输出目录>`，收尾 `… detach && … clean`。
