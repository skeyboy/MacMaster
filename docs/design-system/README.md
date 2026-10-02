# MacMaster 设计系统 · 划分与归属

设计稿按 **SPM 模块**划分，一个模块一个目录、一个目录一个主人。这样切不是为了整洁，
而是为了让多路并进的施工互不踩脚：谁 owns 哪个目录，谁才能写那个目录，
跨目录的事一律走"提请协调者"，不在别人家里改东西。

## 1. 目录

```
docs/design-system/
├── tokens.css        设计令牌（颜色/字号/间距/圆角）—— 共享层
├── screen.css        窗口骨架样式（.win/.sidebar/.row-h/.kv）—— 共享层
├── icons.js          图标 sprite（#i-<name>）—— 共享层
├── render.sh         渲染：HTML → 2x PNG。`./render.sh screens/<模块>/<稿>.html W H`
└── screens/
    ├── shell/         01-dashboard · 09-settings
    ├── mmui/          components · 05-states
    ├── mmcleaner/     02-cleaner · 02b-cleaner-installers · 02c-cleaner-dev
    ├── mmuninstaller/ 03-uninstaller · 03b-uninstaller-orphans · 03c-uninstaller-trash · 03d-uninstaller-provenance · 03e-uninstaller-watch
    ├── mmdisk/        04-disk · 04b-disk-confirm
    ├── mmguardian/    06-guardian
    ├── mmmonitor/     07-monitor
    └── mmoptimizer/   08-optimizer
```

文件名保留 `NN-` 前缀：那是侧栏顺序，去掉就没法一眼看出哪屏在前哪屏在后。
CSS px 与 SwiftUI pt 一一对应，所以稿子里的量可以直接拿去和实机像素比。

## 2. 归属矩阵

`MMDestination`（`Packages/MMCore/Sources/MMCore/Navigation.swift`）是壳工程的导航真源，
`MM_OPEN_MODULE=<id>` 用的就是它的 rawValue。

| 稿目录 | SPM 包 | `MM_OPEN_MODULE` | 主视图 | 该模块可用钩子 |
| --- | --- | --- | --- | --- |
| `shell/` | 壳 `Sources/MacMaster` + MMCore | `dashboard` | `MainWindow.swift` `DashboardModel.swift` `SettingsView.swift` `LaunchBehavior.swift` `WindowProbe.swift` | `MM_SHOW_SETTINGS` `MM_SETTINGS_TAB` + 全局取证档 `MM_APPEARANCE`(light/dark) `MM_WINDOW_SIZE`(宽x高) `MM_PROBE_WINDOW`(逐时间点打窗口/宿主帧，配 `Scripts/window-probe-sweep.sh` 量整页溢出) |
| `mmui/` | `Packages/MMUI` | —（组件库，不单独成页） | `MMDesign.swift` `TreemapView.swift` | 无。回执面板的实机渲染借 `MM_FAILURE_FIXTURE`（钩子在 MMCleaner） |
| `mmcleaner/` | `Packages/MMCleaner` + MMFileScanner | `cleaner` | `CleanerContainerView.swift` `MMCleaner.swift` `UserFolderCleanView.swift` `SystemAnalysisView.swift` `DevArtifactView.swift` | `MM_OPEN_TAB`(cache/folders/system/dev) `MM_CLEANER_FILTER` `MM_EXPAND_CATEGORIES` `MM_AUTO_SCAN` `MM_SHOW_CONFIRM` `MM_INSTALLER_FIXTURE_DIR` `MM_FAILURE_FIXTURE` `MM_SNAPSHOT_FIXTURE`(mixed/overflow/updateonly/none/broken，只换快照块的解析输入) + 开发产物页(02c 三档：① 首批含截断 ② 续扫之后 ③ 同一根再截断就改口) `MM_PURGE_FIXTURE_HOME`(只认 /tmp) `MM_DEV_EXPAND` `MM_DEV_SELECT`(untouched) `MM_DEV_SCROLL`(end) `MM_DEV_CONFIRM` |
| `mmuninstaller/` | `Packages/MMUninstaller` | `uninstaller` | `MMUninstaller.swift` `UninstallerModel.swift` `OrphanScanner.swift` `TrashWatcher.swift` `AppFolderWatcher.swift` `AppProvenance.swift` `AppProvenanceScanner` | `MM_UNINSTALL_PANE` `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` `MM_UNINSTALL_CONFIRM_MODE`(appOnly/withResiduals/none) `MM_UNINSTALL_SELECT`(按 bundleName 点名选中行，03d 逐档取证) `MM_ORPHAN_FIXTURE_HOME` `MM_TRASH_FIXTURE_DIR` `MM_TRASH_SCAN_HOME` `MM_SHOW_TRASH_CONFIRM` + 装卸监听(03e) `MM_APPS_WATCH_FIXTURE_DIR`(只认 /tmp) `MM_APPS_WATCH_AUTO_SCAN` `MM_UNINSTALL_SELF_ECHO`(⚠️ 会真的把夹具里那个 app 移进废纸篓，夹具 home 不成立就不生效) |
| `mmdisk/` | `Packages/MMDisk` | `disk` | `MMDisk.swift` `DiskClassify.swift` `DiskInsights.swift` | `MM_OPEN_TAB`(tree/list/large) `MM_DISK_DEPTH` `MM_DISK_FILTER` `MM_DISK_SCAN`(只认 /tmp) `MM_DISK_SELECT`(只认 /tmp) `MM_DISK_HOLD`(hold) `MM_SHOW_CONFIRM` `MM_SHOW_TOAST`(=permanent 拍永久删除回执) `MM_SHOW_PERMANENT`(=acked 把确认勾选打上，仅换面板不删) |
| `mmguardian/` | `Packages/MMGuardian` | `guardian` | `MMGuardian.swift` `DeviceUsageProbe.swift` `TCCProbe.swift` `LoginItemStore.swift` | `MM_GUARDIAN_FIXTURE` `MM_TCC_FIXTURE` `MM_GUARDIAN_LOGIN_FIXTURE` `MM_GUARDIAN_LOAD` `MM_GUARDIAN_ACTIVITY_FIXTURE`(empty/rows，系统活动卡) |
| `mmmonitor/` | `Packages/MMMonitor` | `monitor` | `MMMonitor.swift` `MetricReaders.swift` `MenuBarManager.swift` | `MM_OPEN_MODULE` + 内容钩子 `MM_MONITOR_HOLD` `MM_MONITOR_FIXTURE`（#50 新增，覆盖 `docs/analysis/fidelity-monitor.md` §4 的 13 项未验证态） |
| `mmoptimizer/` | `Packages/MMOptimizer` | `optimizer` | `MMOptimizer.swift` `DevToolCacheView.swift` `DashboardMetrics.swift` | `MM_OPEN_TAB`(duplicates/browser/status/devtools) `MM_OPTIMIZER_FIXTURE`（#52 后补：duplicates:N/duplicates:empty/duplicates:scannedEmpty/browser:rows/browser:empty/status:allReadOnly/devtools:notInstalled/devtools:unreadable/protected） |

钩子的值域写在各模块视图的注释里，本表只列名字。**表里有的钩子都是 `grep` 出来的真值**，
新增钩子要同步改这张表，否则下一个人会按不存在的钩子安排验证。

`MM_APPEARANCE` / `MM_WINDOW_SIZE` 是**跨屏生效**的取证档（在壳层 `LaunchBehavior.swift`，
不属于任何模块页），逐屏扫描用 `./Scripts/p4-sweep.sh <app> <outdir> [light|dark] [宽x高] [屏名…]`。
设计稿是浅色档，所以**任何"色档一致"的结论都必须至少有一轮 `MM_APPEARANCE=light` 的截图**——
只拍系统默认档等于拿浅色稿比深色照片。实测值与判定见 `docs/analysis/fidelity-light-dark.md`。

`MMCore` / `MMFileScanner` 没有自己的稿子：前者是设置、导航、删除闸门、台账这些
无画面契约，后者是扫描引擎。它们的"设计"体现在消费方的屏里，规约写在
`docs/analysis/` 对应文档里（如 `deletion-guard.md`）。

## 3. 共享层：谁能改

`tokens.css` `screen.css` `icons.js` `render.sh`、`Packages/MMUI`、`Packages/MMCore`、
`Sources/MacMaster` —— 只有协调者能改。

模块施工中发现共享层有问题（缺图标、令牌语义不对、`MMFailurePanel` 排版不够），
**不要自己动手**：写进本模块审计文档的「提请协调者」一节，附上现象、复现命令和期望值。
理由是这些文件被 8 个模块同时依赖，一处改动会让别人刚截的图作废，
并发写还会互相覆盖。

## 4. 每屏交付物

一个模块收口时，这四样必须齐：

1. **稿**：`screens/<模块>/NN-<名>.html` + 同名 `.png`（`./render.sh` 重出，不许手贴截图）。
   稿子里每个 artboard 要覆盖该视图**真能画出来的每一种状态**：正常、空、加载中、
   部分失败、被闸门拒绝、无权限降级。画不出来的状态标"推演档"。
2. **审计**：`docs/analysis/fidelity-<模块>.md`，格式照 `fidelity-monitor.md`：
   先结论先行，再列"哪些数字是量出来的"，然后逐元素对照表，差异按
   **实现该改 / 设计稿该改 / 两边都改** 归属，最后单列「没能验证到的部分」和「提请协调者」。
3. **实机图**：`docs/verification/<模块>/*.jpg`。`/tmp` 会被系统清理，
   证据必须入库；文档里引用某个 `/tmp` 路径前先确认文件还在。
4. **代码**：判据单测 +（如需要）无头验证钩子。钩子一律只认 `/tmp` 之下的夹具路径，
   越界就写 stderr 并忽略——这条链路的尽头常常是删除按钮。

## 5. 验证红线

- **禁止合成点击/滚轮/键盘**。原生 UI 只走"抓窗口"：
  `swift Scripts/window-ids.swift --pid <自己的 pid>` → `screencapture -o -x -l<id>` → `sips -s format jpeg`。
  合成事件会逃逸到用户当时的前台应用，这是不可接受副作用。
- **`--pid` 不是可选项**。多个实例同时在跑时按进程名过滤会把别人实例的窗口一起列出来，
  抓错窗口的截图比没截图更糟——它会让一份错误的证据看起来是真的。
- 只 `kill` 自己记下 pid 的实例，禁止宽匹配 `pkill`。
- **测量诚实**：没测过 ≠ 0，没看过 ≠ 干净，原因未知 ≠ 某个具体原因。
  未测得的字段留 nil 并显示"测量中/尚未…"，不许编数字。
- 不删真实用户文件。涉及删除的验证一律在 `/tmp` 夹具里跑。
- **窗口下限 = `--content-min`(760pt) + 侧栏宽(实测 220pt)**，所以现在实现是 `minWidth: 1000`。
  低于这个宽度时布局不报错、只是把话截一半（按钮标题被截成"重新…""选择…"），
  这类缺陷肉眼最容易漏。要支持更窄的窗口，先补一张窄档 artboard 定义降级顺序，
  别在代码里临时决定截哪句。推导与实测见 `docs/analysis/fidelity-min-window.md`。
- 不 `git commit`、不 `git checkout/reset`：提交由主代理串行完成，避免并发写索引。
