# P1.5 调研：读废纸篓到底需要什么权限（trash-watch-fda）

> 结论先行：**本机（macOS 27.0 beta / Build 26A428，ad-hoc 签名、非沙盒、无完全磁盘访问）
> 读不到 `~/.Trash` 的目录内容**，而且失败方式很会骗人——
> `fileExists` 返回 true、`attributesOfItem` 把属主/权限位全给你、`isWritableFile` 甚至说"可写"，
> 但真正要列举内容时 `open(2)` / `opendir(3)` 一律 **EPERM(1)**。
> 所以「废纸篓监听 → 提示清理残留」这一屏在常态下必须走**"读不到 · 原因 + 授权入口"降级档**，
> 绝不能显示"废纸篓是空的"（空列表会被读成"用户没删过东西"）。
> 下面每条都是本机命令实测输出，不是推测。

## 1. 本机实测（2026-09-30）

### 1.1 探针

`/tmp/trash_stat.swift`、`/tmp/trash_probe.swift`（`swift <file>` 直接跑，进程本身无 FDA）。

```
fileExists=true   isWritable=true
attrs: NSFileType=NSFileTypeDirectory  NSFileOwnerAccountID=501(lee)
       NSFileGroupOwnerAccountID=20(staff)  NSFilePosixPermissions=448(=0o700)
open(O_RDONLY)    fd=-1  errno=1  text=Operation not permitted
opendir           FAILED errno=1  text=Operation not permitted
FileManager.contentsOfDirectory
  → ERR domain=NSCocoaErrorDomain code=257 errno=1 text=Operation not permitted
```

三个容易踩的坑，逐条说明：

- **`fileExists` 为 true 不代表读得动。** 它走 `stat(2)`，而 TCC 对 `~/.Trash` 拦的是
  `open`/`readdir` 这一层。用 `fileExists` 当门神，就会得出"能访问"的假结论。
- **`isWritableFile` 返回 true 更是反直觉。** 权限位 0o700 + 属主是自己，Unix 层面确实"可写"；
  所以实现里**不用它做判断**，只把 `open()` 的 errno 当真相。
- **Cocoa 抛的 `NSCocoaErrorDomain 257`（"The file "…" couldn't be opened because you don't have
  permission to see it."）本身不区分"被 TCC 拒"和"权限位拒绝"。** 257 抛出后 `errno` 仍是 1，
  所以 `TrashWatcher.listing(of:)` 在调用前先把 `errno` 清零，失败时读原始 errno 报给用户——
  文案里的"错误码 1"就是这么来的，不是猜的。

### 1.2 应用侧独立复现

同一个探针是命令行进程，还得证明**打包后的 App 也一样**。把钩子全关、只带
`MM_OPEN_MODULE=uninstaller` 启动 `build/MacMaster.app`，页面顶部出现的就是降级横幅：

> 读不到废纸篓
> 无法打开废纸篓目录：Operation not permitted（错误码 1）。 在系统设置里授予「完全磁盘访问」后，
> 重新进入这一页或重启应用才会生效。　［打开系统设置］

截图：`docs/verification/p1.5-trash/uninstaller-no-fda-banner.jpg`。**这就是绝大多数用户第一次进这一页看到的画面**，
所以它必须是设计稿里的一等公民（`03c-3`），而不是一个藏起来的错误分支。

授权入口深链到具体面板，不是把人丢进"系统设置"首页：
`x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles`
（`MMUninstaller.fullDiskAccessPane` → `MMReveal.openSystemSettings(pane:)`）。

- **本机未验证"授予 FDA 之后确实可读"**：给 ad-hoc 构建的 App 授 FDA 要人工点系统设置，
  不在自动化验证范围内。按 Apple 文档与同类实现（Mole / Pearcleaner 都要求 FDA 才碰 `~/.Trash`）
  的共识，授予后可读；**此结论标注为未在本机验证**。
- 授予之后**不会热生效**：TCC 判定在进程启动时建立，所以文案明说"重新进入这一页或重启应用"。

### 1.3 kqueue 监听本身可用（在能读的目录上）

`/tmp/kq_probe3.swift`：对 `/tmp` 下一个目录取 fd（`O_RDONLY`），
`DispatchSource.makeFileSystemObjectSource(eventMask: [.write, .delete, .rename, .revoke])`，
往目录里 `mv` 一个 `.app` 进去，收到 `fired=2`（`NOTE_WRITE` 的 rawValue 就是 2）。

两点实现上的硬约束：

- **fd 必须一直开着。** `setCancelHandler` 里 `close(descriptor)` 是唯一收尾点，
  `stop()` 之外还要兜住"对象被丢弃却没人调 stop"。
- **目录本身被换掉要重开。** 收到 `.delete/.rename/.revoke` 时这个 fd 之后不会再有事件，
  所以走 `scheduleReopen()`（`stop()` + `start()`），而不是默默失去监听还显示"正在监听"。

### 1.4 事件回调必须显式 hop 回 MainActor

`eventMask` 的 source 排在 `.main` queue，但 `setEventHandler` 的闭包本身是**非隔离**的 GCD 闭包，
直接改 `@Published` 等于绕过 Swift 的隔离检查。实测过程还顺带暴露了第二件事：
最初版把重扫写成 `Task { try await Task.sleep(for: .milliseconds(400)) … }`，
在应用卸载页正在批量测量 45 个应用大小时，这个 sleep 的续体**几十秒都没被恢复**——
MainActor 被逐条回填 + 列表重渲染占满，合并计时器排在同一个 actor 上就只能等。
现在的写法是 `Task { @MainActor in self?.handleEvents(fired) }` + 一个可取消的 `pendingTick`。

- **残留的已知代价（诚实记录）**：合并窗口 400ms 是"最少等多久"，不是"最多等多久"。
  页面还在批量测量时，提示卡会推迟到主线程空下来才出现。没有把它做成后台线程，
  是因为要落的状态是 UI 状态；宁可晚出现，也不在测量中途插一整块列表刷新。
- 调试期间加过 11 条 `FileHandle.standardError` 的 DBG 打点，用来把失败点定位到"sleep 续体没恢复"
  而不是"事件没投递"。**这些打点已全部移除**，只留下上面那条 hop 修复。
- **移除打点后复测（2026-09-30 09:37，`docs/verification/p1.5-trash/uninstaller-trash-notice.jpg`）**：把 `Foo.app` 移进假废纸篓时，
  应用列表还在测量中（页头"已测 31 · 13 个测量中"），提示卡连同 4 项残留在约 8 秒内就出现了。
  也就是说"几十秒不恢复"里绝大部分是**那 11 条 stderr 打点自己把主线程拖住的**，
  不是架构问题。上面那条"会推迟"仍然成立，只是量级从"几十秒"降到"秒级"。

## 2. 由此定下的三条设计红线

1. **nil ≠ 0。** 读不到就说读不到并给原因；扫描还没回来时汇总行写"尚未扫描"，
   不写"0 项 · 0 字节"（那读起来等于"这里干净"）。见 `trashNoticeSummary`。
2. **两种原因不合成一种。** 目录压根不存在（新用户从没删过东西）走"废纸篓目录还不存在"，
   **且不给授权按钮**——那是权限之外的解释。见 `Status.unreadable(needsFullDiskAccess:)`。
3. **本体绝不进删除列表。** 卡片的前提就是"本体已经在废纸篓里"，
   删除路径只由 `report.deletionRoots(for:)` 单点给出，
   单测 `TrashResidualNoticeFlowTests` 锁住这条（同时锁"所有根都在注入的 home 之下"）。

## 3. 验证方式（不碰合成点击）

原生 UI 不用合成点击验证（点击会逃逸到用户其他应用）。这一屏全部靠环境变量钩子 +
窗口 ID 抓屏：`MM_TRASH_FIXTURE_DIR`（假废纸篓）、`MM_TRASH_SCAN_HOME`（假 home）、
`MM_SHOW_TRASH_CONFIRM`（自动开确认面板）。**三个钩子都只认 `/tmp` 或 `/private/tmp` 之下的路径**，
否则向 stderr 打一行"不在 /tmp 之下，忽略该钩子"并当作未设置——
带删除动作的入口不能因为一个拼错的环境变量就指向真实用户目录。

对照截图：`docs/verification/p1.5-trash/uninstaller-trash-notice.jpg`（夹具态，卡片 + 4 项残留 + 已选 2 项 · 6.3 MB）
vs `docs/design-system/screens/03c-uninstaller-trash.png`（设计稿 03c / 03c-2 / 03c-3）。

夹具本身入库为 `Scripts/trash-fixture.sh`（只在 `/tmp` 下造文件，可重复跑）；
窗口 id 查询入库为 `Scripts/window-ids.swift`。

### 3.1 没截到的一张图（如实记）

**设置页「废纸篓」那一行没有实机截图。** 实机 sheet 固定 `500×400`（`SettingsView` 的
`.frame`，见 `09-settings.html` 的说明），清理 tab 有 5 个 section，
「废纸篓」排在「安全」之后，落在 400pt 折线以下；把它截进来需要滚动，
而滚动属于合成输入，本项目的验证红线不允许（合成事件会逃逸到用户当时的前台应用）。

为此改走两条替代验证：

- **数据层**：`Packages/MMCore/Tests/MMCoreTests/AppSettingsPersistenceTests.swift`
  用注入的 `UserDefaults(suiteName:)` 锁住"出厂默认开"与"关掉后跨实例保持"。
- **渲染层**：只到"清理 tab 本身渲染正常"为止——那次抓的图（可见「扫描范围」四行与「安全」标题，
  400pt 折线正好切在「安全」处）**存在 `/tmp` 且已被系统清掉，没进仓库**，所以这条现在是
  一段无法复核的记述，不当证据用。新行本身是同一个 `Form` 里的 `Toggle` + `Text`，画在稿子 `09c` 里。

期间试过把 `.frame` 临时改成 620 再截图，但第二次启动时这个后台拉起的进程没能把 sheet
窗口挂到窗口列表（`CGWindowListCopyWindowInfo` 查不到），**没有拿到图**，
临时改动已还原为 400。这一行仍是本次交付里唯一"代码 + 单测 + 设计稿齐、实机图缺"的部分。

## 4. 参考与出处

- 分批卸载时"把 app 关联的启动项/残留一起列出来"的思路参考 Mole（GPLv3，
  `docs/Mole/`）；**实现独立**，未复制其代码。
- `~/.Trash` 需要完全磁盘访问这一点，与 Pearcleaner 的 TCC 要求一致
  （见 [guardian-tcc.md](guardian-tcc.md) 里同类"未在本机验证"的标注口径）。
