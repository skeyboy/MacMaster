# MacMaster 项目架构设计

> 基线：2026-09-30 现有 SwiftPM 工程。产品范围以 `technical-analysis/02-产品规划文档.md` 为准；界面尺寸、颜色和状态以 `design-system/` 的逐屏稿及 `analysis/fidelity-*.md` 的实机校验为准。`design/` 中的四张图用于视觉方向，不作为可执行的数字或交互规格。

## 1. 目标与边界

MacMaster 是本机运行的 macOS 14+ SwiftUI 工具。所有读数来自本机采样；无测量结果时显示未知或原因，不以零值冒充。默认不索取管理员权限。文件操作仅移到废纸篓，必须有预览、确认、逐项回执和可持久撤回的历史。系统保护位置由 `MMCore.DeletionGuard` 在最后出口拒绝，界面上的风险标记不是安全闸门。

详细 HTML 稿覆盖普通、空、加载、失败和权限降级态。实现优先保持信息层级、间距、字体和状态语义；示意稿中的样例数字不得写入生产视图。

## 2. 设计与技术参考

界面以 [设计系统说明](design-system/README.md)、[设计令牌](design-system/tokens.css) 和 `design-system/screens/<模块>/` 的 HTML 稿为依据。每个模块按同目录 PNG 核对正常态，再按 [逐屏审计](analysis/fidelity-monitor.md) 核对加载、空、失败、权限降级等状态。CSS px 对应 SwiftUI pt；在窗口最小尺寸和浅、深色下检查列对齐、文字截断与按钮状态。视觉概念图只提供品牌方向，不替代这些可量化规格。

`github-references/` 与 `lemon-cleaner/` 是技术参照，仓库内的流程说明不构成 MacMaster 的产品要求。参考映射如下：

| MacMaster 模块 | 本地技术参照 | 借鉴的机制与本项目取舍 |
| --- | --- | --- |
| MMUninstaller | `github-references/Pearcleaner`、`lemon-cleaner/localPod/LemonUninstaller` | App 归属、残留位置与废纸篓事件；孤儿候选默认不勾选，容器缓存与用户数据分级 |
| MMCleaner / MMFileScanner | `github-references/Mole`、`lemon-cleaner/LemonClener` | 缓存类别、安装包识别和测量状态；删除统一接入 `FileTrashService` |
| MMDisk / MMUI | `github-references/disktree`、`github-references/Mole` | 树扫描、面积守恒、Treemap、筛选与两阶段审查；macOS 保护路径再过 `DeletionGuard` |
| MMMonitor | `github-references/stats`、`lemon-cleaner/Tools/LemonMonitor` | CPU/内存/网络/磁盘的采样与菜单栏展示；速率必须由相邻快照差分，首帧保持未知 |
| MMGuardian | `github-references/OverSight`、`github-references/Pearcleaner` | 摄像头/麦克风占用信号、TCC 与登录项只读审核；只报告可证实的状态，不承诺拦截 |
| MMOptimizer | `github-references/Mole` | 开发工具缓存位置及 owner 命令、系统空间报告；只展示命令，不代用户运行 |

许可按仓库中的本地文件核对：Pearcleaner 是 Apache 2.0 + Commons Clause，Mole、OverSight、Lemon Cleaner 主模块为 GPLv3，Lemon Daemon 单独说明为 GPLv2；stats 与 disktree 为 MIT。当前模块实现借鉴行为和边界，不从 GPL 或 Commons Clause 项目搬运源码。将来确需引入第三方代码时，先确认具体文件的许可、署名和发布义务。

## 3. 依赖结构

```text
MacMaster (App 壳、注册、导航、概览、设置)
  ├── MMCore (导航、设置、采样、删除闸门、废纸篓与历史)
  ├── MMUI (语义令牌、公共组件、Treemap)
  ├── MMFileScanner (无界面的文件枚举与分类)
  ├── MMCleaner ──────── MMFileScanner, MMCore, MMUI
  ├── MMUninstaller ───── MMCore, MMUI
  ├── MMDisk ──────────── MMCore, MMUI
  ├── MMMonitor ───────── MMCore, MMUI
  ├── MMGuardian ──────── MMCore, MMUI
  └── MMOptimizer ─────── MMFileScanner, MMCore, MMUI
```

模块由 `ModuleRegistrable` 提供 ID、标题、图标、顺序和视图工厂；壳层显式注册。跨模块跳转只发送 `MMNavigation` 目的地，由壳层切换，功能模块彼此不 import。扫描和系统调用在后台执行，`@MainActor` 模型只发布状态。副作用服务集中在 `MMCore`，避免某个模块绕开删除闸门。

## 4. 模块契约

| 模块 | 输入和职责 | 输出与界面 | 安全边界 |
| --- | --- | --- | --- |
| Shell | 注册模块、持有全局设置和概览采样 | 侧栏、概览、设置；提供统一导航 | 概览与侧栏共用同一测量结果 |
| MMCore | 设置、系统读数、删除服务和台账 | `MMDestination`、`FileTrashService`、`DeletionGuard` | 路径先校验，再执行；失败逐项记录 |
| MMUI | 语义色、间距、卡片、表格、状态组件 | 与 `design-system/tokens.css` 对应 | 不读取用户文件，不启动任务 |
| MMFileScanner | 缓存、安装包、重复文件等枚举 | 有证据的扫描结果及未读原因 | 不做删除；不可读文件不进重复组 |
| MMCleaner | 系统与用户缓存、安装包、空间报告 | 分类选择、确认、回执 | 仅经 `FileTrashService` 执行 |
| MMUninstaller | App 与残留归属、收据只读线索、孤儿反查、废纸篓提示 | 已装应用 / 卸载后遗症双视图 | 容器谨慎勾选；孤儿默认不勾选；收据不进入删除路径 |
| MMDisk | 树形扫描、过滤、Treemap、大文件 | 面包屑、占比和两阶段审查 | 标记是预览；执行仍过 `DeletionGuard` |
| MMMonitor | CPU、内存、磁盘和网络采样，进程只读枚举 | 页面与菜单栏共用采样快照 | 未采样、失败、空结果分开表示 |
| MMGuardian | 设备占用、TCC 只读视图、登录项审核 | 状态、原因和可操作提示 | 不暗示可拦截系统访问 |
| MMOptimizer | 重复项、浏览器缓存、开发工具缓存建议 | 诊断与明确的维护动作 | 不运行第三方 owner 命令 |

## 5. 关键数据流

1. 启动时壳层注册模块，`MainWindow` 保存导航和概览模型；菜单栏由 `MenuBarManager` 独立采样。
2. 扫描模块返回路径、大小、风险、测量状态；视图只用这些结果生成选择与预览。
3. 用户确认后，模块将明确选中的路径交给 `FileTrashService`；服务逐项调用 `DeletionGuard`，移动到废纸篓并持久化 `TrashHistoryStore`。
4. 回执展示成功、失败和受保护拒绝；撤回从台账找到原路径与废纸篓路径再恢复。部分失败不报作全部成功。
5. 监控读数用同一 `MetricSnapshot` 提供菜单栏和页面，首次差分前的速率保持未知。

## 6. 按模块开发与验收

当前缺口和每阶段进度统一记录在 [模块优先级清单](analysis/module-priority.md)，以该清单选择下一模块。

| 顺序 | 工作 | 完成标准 |
| --- | --- | --- |
| 1 | MMCore / MMUI / Shell | 依赖和导航单向；真实数据取代示意数字；删除出口统一；设计令牌与壳层几何一致 |
| 2 | MMCleaner / MMUninstaller | 扫描、风险分级、确认、回执、撤回贯通；权限不足有降级态 |
| 3 | MMDisk / MMMonitor | 面积与大小口径可验证；采样、空态和失败态分明；菜单栏与主窗口读数同源 |
| 4 | MMGuardian / MMOptimizer | 只读诊断不夸大能力；维护动作有真实效果和反馈 |
| 5 | 全站集成 | 各屏对照 HTML 稿和真机窗口；浅/深色与最小窗口复核；全包测试和 App 构建通过 |

现有工程已经实现上述模块主体；`analysis/fidelity-*.md` 是逐模块差异清单，不把规划文档里尚未接入的 XPC Helper、Widget 或自动更新视为已完成。扩展这些目标时先定义权限、发布和数据契约，再增加 target。验证钩子仅用于可重复的截图或 `/tmp` 夹具，不能成为生产数据源。

## 7. 本轮验证

`swift build`、`Packages/MMMonitor` 下的 `swift test`（20 项）、`Packages/MMUninstaller` 下的 `swift test`（72 项）和 `Scripts/make-app.sh -o /tmp/macmaster-codex-build` 均通过。使用 `MM_OPEN_MODULE=monitor MM_MONITOR_FIXTURE=populated,processes` 启动构建产物，按进程 ID 抓取窗口；[监控页夹具截图](verification/mmmonitor/monitor-fixture.jpg) 显示固定采样值和设计稿对应的卡片结构。该图是夹具态，不是当前机器的实时系统读数；常规启动仍由菜单栏采样器读取本机指标。卸载模块的收据测试仅使用临时目录。

后续 P0 收口把删除结果回写统一为“只采纳 `operation.files`”：共享台账支持部分撤回重试，清理、卸载、磁盘和重复文件列表保留失败项；相关模块测试及实机清理页列顺序见 [模块优先级清单](analysis/module-priority.md)。

P1 对缓存清理与卸载的扫描、预览和执行清单作了同源收口；两种卸载模式都经过确认，未测体积保持未知。验收截图与权限边界见 [P1 清理与卸载验收](analysis/p1-cleaner-uninstaller.md)。
