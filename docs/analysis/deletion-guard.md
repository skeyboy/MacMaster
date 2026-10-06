# 删除闸门 `DeletionGuard`：为什么在出口处挡，以及挡到哪一层

对应实现：`Packages/MMCore/Sources/MMCore/DeletionGuard.swift`、
`Packages/MMCore/Sources/MMCore/FileTrashService.swift`（唯一接入点）、
判据测试 `Packages/MMCore/Tests/MMCoreTests/DeletionGuardTests.swift`、
出口测试 `Packages/MMCore/Tests/MMCoreTests/FileTrashServiceGuardTests.swift`、
界面侧同源判定 `Packages/MMDisk/Sources/MMDisk/DiskRisk.swift`（P21 提出去的那一份）及其
`Packages/MMDisk/Tests/MMDiskTests/DiskRiskTests.swift`。

## 1. 缺口是怎么来的

`FileTrashService.moveToTrash(paths:)` 是 9 个模块（清理 / 卸载 / 磁盘 / 优化 / 残留 / 孤儿 …）
共用的删除出口，改动前它对路径**一个字都不检查**：给什么就 `trashItem` 什么。
各扫描器各自有一份"危险目录"名单，但那份名单的用途是**上色**——
`DiskRisk.swift:15` 的 `protectedRoots`（判定函数 `risk(of:)` 在 `:27-36`；P1.7 当时它还内联在
`MMDisk.swift` 的视图里，P21 才提出去，见 §7）只把 `/System`、`~/Documents` 之类标成
`.readOnly` 徽标，标完照样能把路径交给 `moveToTrash`。标签和闸门是两回事，
之前只有标签。

参考项目 Mole 的 `app_protection.sh` 与它的 `delete_test.go` 回归集说明这件事必须
在出口做：保护清单散在扫描器里，就永远会有新入口绕过它。

## 2. 三条设计红线

1. **闸口只有一个。** 接在 `moveToTrash` 的循环开头，上游误判、调用方拼错、
   以后新增的入口都从这里过。扫描器里不加第二道判断，避免两份清单各说各话。
2. **拒绝必须逐条上报，不能静默跳过。** 被挡的路径生成一条
   `TrashFailure(code: "PROTECTED")`，和 EPERM 那些失败走同一个面板、同一份台账。
   用户看到"移走 3 项"而实际挡了 1 项，比看到一条拒绝更糟。
3. **保护不能把已有功能废掉。** 这条最难，见 §4。

## 3. 本机实测的依据（不是抄来的规矩）

复现脚本：`swift Scripts/realpath-probe.swift`。

| 事实 | 实测结果 | 影响 |
| --- | --- | --- |
| `/etc`、`/var`、`/tmp` 是符号链接 | `ls -ld` 显示三者都指向 `private/` 下同名目录 | 同一个目录有两种写法，清单必须先归一 |
| C `realpath` 的容忍度 | 末段缺失、断链、父目录缺失一律 `NULL` + `errno=2`；**不像 glibc 允许最后一段不存在** | 断链解析不出来，只能退回链接自身位置判 |
| `URL.standardizedFileURL` | `standardize("/private/etc/hosts")` → `/etc/hosts`，而 `standardize("/private/var/db/receipts/x")` 原样返回 | 同一个函数对同一类前缀给两种答案，不能当比较基准 |
| APFS 默认大小写不敏感 | `/system` 与 `/System` 同一个 inode | 所有比较都走 `lowercased()`，且按路径组件边界比 |

所以 `canonicalize` 是自己写的：纯字面清理（`.`、`..`、重复斜杠、尾斜杠）
+ 只在第一段是 `etc`/`var`/`tmp` 时剥掉 `/private`。确定性优先于聪明——
符号链接交给 `realpath` 那一遍，字面归一不碰磁盘。

## 4. 清单的三层口径（以及为什么不是一个口径）

| 层 | 内容 | 口径 | 理由 |
| --- | --- | --- | --- |
| 系统域 | `/System` `/usr` `/bin` `/sbin` `/Library` `/etc` `/var/db` `/var/root` **`/dev`、`/private`**（这两条 P21 补，见 §7.1） | 子树 | 本应用没有权限也不该有权限动系统域。以前删它们会拿到 EPERM，现在拿到一句人话 |
| 凭证与活数据 | `.ssh` `.gnupg` `.aws` `.azure` `.config/gh` `Library/Keychains` `Library/CloudStorage` `Library/Mail` `Library/Calendars` `MobileSync` `CallHistory*` `Containers/*/Data/vms` | 子树 | 删了不可再生。`~/.npm`、`~/.cargo` **故意不收**：里面的缓存正是清理模块的合法目标 |
| 六个用户目录 | `Documents` `Desktop` `Downloads` `Pictures` `Music` `Movies` | **仅目录本身** | 见下 |

第三层是被既有功能逼出来的。`UserFolderScanner.folderSpecs()` 列的正好就是这六个目录，
「用户文件夹清理」页把它们做成逐项勾选 + 确认面板 + 可撤回的功能；
按子树挡等于把这一页整体废掉。但那一页的每个文件夹行**本身也是可勾选的**
（`UserFolderCleanView` 把 `folder.path` 直接塞进 `selectedPaths`），
整层桌面进废纸篓是另一种量级的事故（iCloud「桌面与文稿」同步、照片图库根都在这一层）。
于是拆开：目录本身按精确匹配拒绝，里面的内容照常放行。

`Data/vms` 而不是 `Data` 同理：沙盒容器缓存类别的目标是
`~/Library/Containers/*/Data/Library/Caches`，挡容器根会连正常缓存一起否掉，
而真正贵的东西（虚拟磁盘镜像）在 `Data/vms/**`。Docker 与 OrbStack 本机未安装，
这一组按上游文档布局写，判据是纯字符串，不依赖"这台机器上恰好有这个东西"。

## 5. 被这个闸门改掉的行为

- **`~/Library/Mail` 从缓存类别里摘掉。** `CacheScanner` 的 `mail_cache` 以前把
  `~/Library/Mail` 和 `~/Library/Caches/com.apple.mail` 并列，名字还叫"邮件附件与预览"。
  那里面是邮件正文与附件，不是缓存；闸门一上，用户勾了、确认了、最后拿到一条拒绝 ——
  那是清单在骗人。现在只列真正的缓存路径，名字改成"邮件缓存"。
- `/Library/Caches`、`/var/log` 那两种类别本来就标 `.readOnly` 且"不给删除入口"，
  闸门只是把这句承诺从界面约定变成执行约束。
- `MMDisk` 的风险标签**原本是独立的一份清单**，P1.7 那一句"不改它"讲的是一个方向的问题
  （treemap 要表达"这块地方贵"，和"这个删除请求被拒绝"是两个问题）。P21 把它改成
  半同源：标签自己那几档照旧，但**闸门按字面路径就会拒绝的，界面不再说"可以标"**。
  完整理由与那条 `literalRejection` 为什么不调 `realpath`，见 §7.2。

## 6. 验证

- **判据**：`DeletionGuardTests` 18 条（P1.7 是 15 条，P21 加 3 条）—— 系统域、大小写变体、组件边界
  （`/LibraryFoo` 不算 `/Library`）、别名归一、凭证子树、六个目录的"本身挡/内容放"、
  `.Trash` 本身与其中条目、空路径、指向 `/System` 与 `~/Documents` 的符号链接、断链的真实行为；
  P21 那 3 条分别锁 `/dev` 与 `/private` 子树（含 `/DEV/random`、`/System/../dev/null` 这种绕法）、
  锁"临时目录与 `/opt/homebrew` 不被误挡"、锁字面那一遍与完整那一遍在普通路径上给出**同一个理由**。
- **界面侧**：`DiskRiskTests` 6 条（P21 新增）—— 见 §7.2，核心是那条 31 个路径的抽样，
  断言"闸门拒绝 && 界面说可以标"这个组合一次都不许出现。
- **出口**：`FileTrashServiceGuardTests` 6 条 —— 保护路径得到 `PROTECTED` 且
  `successCount == 0`、空路径同样被挡、普通路径仍走到文件系统层（失败码不是 `PROTECTED`）、
  `~/Documents` 下的单项仍能走到文件系统层（证明功能没被堵死）、混合批次逐条记账、
  拒绝写进删除台账。这批测试**全程只喂不存在的路径**：万一闸门失效，
  `trashItem` 会因 ENOENT 失败并让断言报红，而真实用户文件一个都不会被碰。
- **渲染**：`docs/verification/p1.7-deletion-guard/cleaner-refusal-panel.jpg`
  是清理页失败回执里的三条 PROTECTED（桌面目录本身 / 钥匙串 / `/System`），
  琥珀色盾牌 + 原因 + 错误码三列齐全。截图来自钩子 `MM_FAILURE_FIXTURE=protected`，
  它只往展示状态里写记录、不调 `moveToTrash`，内容全部由 `DeletionGuard` 现场算出，
  不是手写的假文案。设计稿同步更新：`docs/design-system/screens/mmui/05-states.html`
  的"部分失败"一栏把原来的假想码 `KEPT` 换成真实的 `PROTECTED`。
- **诚实缺口**：没有"真按下删除后拿到 PROTECTED"的实机照片。要走到那一步需要合成点击，
  本项目的验证红线禁止（合成事件会逃逸到用户当时的前台应用）。上面那张预演图覆盖的是
  排版与文案来源，不覆盖"点击 → 拒绝 → 回执"这条交互链。
- 全量：9 个包 **622 条测试、0 失败、1 跳过**（入口是 `./Scripts/run-all-tests.sh`，
  仓库根直接 `swift test` 会报"no tests found"。P22 那一跑逐包
  73/17/117/18/121/73/53/96/54，2026-10-06（P21 是 621，那一跑 MMDisk 是 72）。
  **注意这一格是别的模块的文档在抄一个会变的数**——它每次都要现跑，别顺手 +1；
  这份文档 P1.7 写的"300+ 条"就是老读数留在这里的样子。）

## 7. P21：清单补两条根，以及"标签不许承诺闸门做不到的事"

### 7.1 `/dev` 与 `/private`

P20 收口时留在 §8 账上的两条。判据不是"看着像系统目录"，而是**这两条早就被别人对外说出去了**：
磁盘页的 `DiskRemoval.systemFirstComponents` 把 `dev`、`private` 当成"系统树"来拦第一层，
`DeletionGuard` 这一侧反而没有对应条目 —— 一个对外承诺比内部实现更宽的缺口。
补完之后 `/dev/null`、`/dev/disk0s1`、`/private/tftpboot` 这些以前靠 EPERM 兜的，
现在拿到的是人话；`/System/../dev/null` 这种绕法由 `canonicalize` 的 `..` 规则处理，另有测试锁。

补这两条不改变任何现有功能：全仓没有任何扫描器产出 `/dev` 或裸 `/private` 路径，
而清理主战场（`/var/folders/**` 的临时目录、`/tmp` 夹具、`/opt/homebrew/**`）
在归一之后仍然落在清单外 —— 这三处各有一条"不许误挡"的测试。

### 7.2 标签与闸门同源（只在一个方向上）

`risk(of:)` 决定 treemap 某一行给不给"标进回收清单"这个按钮，`DeletionGuard` 决定这次删除
放不放行。P1.7 之后它们各存一份系统目录清单，靠人肉对齐，结果是一批路径在界面上显示成
"可标记"，用户标了、确认了，最后由闸门在最后一刻拒绝 —— **界面给出的是一个做不到的承诺**。
这一轮把那条线定成一句可测的合同：**闸门按字面路径拒绝的，界面就不许说可以标**
（`DiskRisk.swift:33` 那一问）。

反方向**不要求同源**，而且故意留着更严的那几档：六个用户目录**里面的内容**（闸门放行、标签仍上
只读，因为磁盘页不是逐项清理用户文件的地方，那一页有专门的「用户文件夹清理」），
以及 `hasPrefix` 造成的 `/LibraryFoo` 那种误伤。少给一个按钮不是假话，多给一个才是。

判定本身从 `DiskAnalyzerView` 的私有方法提成了 `DiskRisk`（`Packages/MMDisk/Sources/MMDisk/DiskRisk.swift:27`），
理由很朴素：它此前**一行测试都没有**，而它是那批假承诺的产地。`MMDiskTests` 因此新增对
`MMCore` 的依赖（`Packages/MMDisk/Package.swift`）—— 性质测试要同时问两边，不然就只是自说自话。

同源那一问走的是 `DeletionGuard.literalRejection(for:)`（`DeletionGuard.swift:83`），
**不是** `rejection(for:)`：后者会先做一遍 `realpath`，而 `risk(of:)` 是在 SwiftUI 的 body 里
按可见行逐行调用的 —— 每行一次系统调用、每次布局重算都再来一遍，把符号链接解析塞进渲染路径
换不来任何保护（真删除仍然走 `rejection(for:)` 的两遍口径）。所以闸门公开两个入口，
判据测试里另有一条锁住"普通路径上两遍给出同一个理由"。

### 7.3 这一轮拍不到照片的东西

新判成只读的那些行**没有实机截图**，原因和 P1.7 那条"没有真按下删除后的 PROTECTED 照片"是同一个，
而且这轮更硬：磁盘页的 `MM_DISK_SCAN` / `MM_DISK_SELECT` 按红线只认 `/tmp` 下的夹具路径
（`MMDisk.swift:171-176`、`:1080-1085`），越界直接忽略钩子 —— 也就是说
**没有任何钩子能把 `/etc/hosts` 或 `~/.ssh` 摆到那一行上去拍**。这一档的证据换成两处：

- `DiskRiskTests` 那 6 条（判据）。
- `./Scripts/p21-disk-risk-probe.sh` 打的逐路径判定表
  （`docs/verification/p21-disk-risk/risk-labels.log`，34 行 × 四列：路径 / 标签 / 字面闸门 / 闸门，
  闸门理由取原文）。这条脚本不抄逻辑 —— 它把 `Risk.swift`、`DeletionGuard.swift`、`DiskRisk.swift`
  三个真源文件连同探针**一起编译**再调那两个真函数（唯一的机械改动是去掉 `DiskRisk.swift` 那行
  `import MMCore`，四个文件合成一个模块才有内部可见性；行数核对与这条声明都写在日志头部）。
  表里那 3 条符号链接是**现场造在 `/tmp` 下、跑完即删**的：没有真链接，`realpath` 那一遍就是空转，
  而"残余缺口"那一栏会永远显示 0 —— 那是最容易被假装成通过的一格。

表末两个计数就是这一轮的合同：
**合同 1**（标签给按钮 && 字面闸门要拒）= **0 违例**，脚本以此决定退出码，可以当门禁跑；
**合同 2**（标签给按钮 && 只有 `realpath` 那遍才拒）= **2 条残余**，都是指向受保护目标的符号链接。
这一格**不修**，理由是修它的代价比它本身大：标签是在 SwiftUI body 里逐行算的，
把 `realpath` 放进去等于每行每次布局一趟系统调用。而且它不是假承诺 —— 被标上的链接进不了删除清单，
`DiskRemoval.swift:98` 会先在确认面板里把它列成"被拦下"那一档（`.guarded`）并带上闸门原话，
用户在**点确认之前**就看到这条不动。

夹具侧"没把正常东西挡掉"的证据是 `docs/verification/p21-disk/` 那四档实拍
（`./Scripts/p68-disk-capture.sh <app> docs/verification/p21-disk`，和 P6.8c 同一棵 `/tmp` 树、
同一组固定体积）：日志里那四行带数字的回执与 `docs/verification/p68-disk/` **逐字节相同**
（`已选中 …/Downloads（50.3 MB）`、`确认面板（3 个标记）`、面板里"把 2 项移入废纸篓 · 回收 58.7 MB"
+ 1 项"就是正在扫描的目录本身"被列成不能删）。数字没变就是功能没变的证据 —— 这一族的哨兵体积
是夹具脚本写死的，真机上不会出现第二个。
