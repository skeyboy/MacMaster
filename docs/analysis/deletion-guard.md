# 删除闸门 `DeletionGuard`：为什么在出口处挡，以及挡到哪一层

对应实现：`Packages/MMCore/Sources/MMCore/DeletionGuard.swift`、
`Packages/MMCore/Sources/MMCore/FileTrashService.swift`（唯一接入点）、
判据测试 `Packages/MMCore/Tests/MMCoreTests/DeletionGuardTests.swift`、
出口测试 `Packages/MMCore/Tests/MMCoreTests/FileTrashServiceGuardTests.swift`。

## 1. 缺口是怎么来的

`FileTrashService.moveToTrash(paths:)` 是 9 个模块（清理 / 卸载 / 磁盘 / 优化 / 残留 / 孤儿 …）
共用的删除出口，改动前它对路径**一个字都不检查**：给什么就 `trashItem` 什么。
各扫描器各自有一份"危险目录"名单，但那份名单的用途是**上色**——
`MMDisk.swift:971` 的 `protectedRoots` 只把 `/System`、`~/Documents` 之类标成
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
| 系统域 | `/System` `/usr` `/bin` `/sbin` `/Library` `/etc` `/var/db` `/var/root` | 子树 | 本应用没有权限也不该有权限动系统域。以前删它们会拿到 EPERM，现在拿到一句人话 |
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
- `MMDisk` 的风险标签**保持原样**，没有改成读闸门清单：treemap 要表达"这块地方贵"，
  和"这个删除请求被拒绝"是两个问题，合并会让上色逻辑丢掉粒度。

## 6. 验证

- **判据**：`DeletionGuardTests` 15 条 —— 系统域、大小写变体、组件边界
  （`/LibraryFoo` 不算 `/Library`）、别名归一、凭证子树、六个目录的"本身挡/内容放"、
  `.Trash` 本身与其中条目、空路径、指向 `/System` 与 `~/Documents` 的符号链接、断链的真实行为。
- **出口**：`FileTrashServiceGuardTests` 6 条 —— 保护路径得到 `PROTECTED` 且
  `successCount == 0`、空路径同样被挡、普通路径仍走到文件系统层（失败码不是 `PROTECTED`）、
  `~/Documents` 下的单项仍能走到文件系统层（证明功能没被堵死）、混合批次逐条记账、
  拒绝写进删除台账。这批测试**全程只喂不存在的路径**：万一闸门失效，
  `trashItem` 会因 ENOENT 失败并让断言报红，而真实用户文件一个都不会被碰。
- **渲染**：`docs/verification/p1.7-deletion-guard/cleaner-refusal-panel.jpg`
  是清理页失败回执里的三条 PROTECTED（桌面目录本身 / 钥匙串 / `/System`），
  琥珀色盾牌 + 原因 + 错误码三列齐全。截图来自钩子 `MM_FAILURE_FIXTURE=protected`，
  它只往展示状态里写记录、不调 `moveToTrash`，内容全部由 `DeletionGuard` 现场算出，
  不是手写的假文案。设计稿同步更新：`docs/design-system/screens/05-states.html`
  的"部分失败"一栏把原来的假想码 `KEPT` 换成真实的 `PROTECTED`。
- **诚实缺口**：没有"真按下删除后拿到 PROTECTED"的实机照片。要走到那一步需要合成点击，
  本项目的验证红线禁止（合成事件会逃逸到用户当时的前台应用）。上面那张预演图覆盖的是
  排版与文案来源，不覆盖"点击 → 拒绝 → 回执"这条交互链。
- 全量：9 个包 300+ 条测试通过（`swift test --package-path Packages/<X>`）。
