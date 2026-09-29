# disktree 采纳分析：MacMaster 磁盘分析（逻辑与树展示）

> 参考源：`docs/github-references/disktree`（tobi/disktree，Rust + GPUI，MIT）。
> 本文所有 MacMaster 侧行号均经人工复核；disktree 侧行号来自逐文件阅读。
> 复核日期：2026-09-29。

## 一句话结论

disktree 的核心价值不在 Rust/GPUI 管线，而在四套可直接移植的产品逻辑——**真实占用口径（st_blocks、硬链去重）、按"数据种类着色 + 可回收斜纹"的分类模型、"先标记后审查提交"的两阶段删除、以及多层嵌套 treemap 的 header-band 布局**。MacMaster 的 treemap 引擎已有 squarify 骨架但只排单层、颜色只按大小分级、磁盘模块完全没有删除能力，故前三项判定 ADOPT，布局与键盘导航判定 ADAPT，Linux 挂载表 / MFT / GPUI 专属逻辑判定 SKIP。

## MacMaster 磁盘分析现状速览

- 扫描：`Packages/MMDisk/Sources/MMDisk/MMDisk.swift` 的 `DiskScanner`，深度上限 20、仅前 3 层并行、worker 数 = 核心数；`scanChildren` 用 TaskGroup 滑动窗口补任务。
- 大小口径：单次 `lstat` 取 `st_size`（**表观大小**），目录大小由子节点求和；**无 st_blocks、无硬链去重**；跳过隐藏项；深度兜底再走 3 层。
- 权限：`prepareAccessiblePaths` 用 security-scoped resource 探测敏感目录；不可读目录被静默跳过、不留痕（用户分不清"没东西"和"读不到"）。
- 取消：`performScan` 一次性返回完整树，`DiskScanner` 侧无 `Task.isCancelled` 检查点（只有 `FileTreeWalker` 有）。
- Treemap：`Packages/MMUI/Sources/MMUI/TreemapView.swift:33` `compute(items:in:)` 只排单层——`TreemapItem.children`（同文件 :8）声明了却从不参与布局；无 header 带；无 min-tile/Others 合并语义（合并在数据层做，渲染窗口 200 项）；标签仅在 ≥40pt 时绘制（:146）。
- 配色：`MMDisk.swift:281` `colorForSize` 按 GB 分 red/orange/yellow/blue/gray——表达"多大"而不是"是什么"。
- 导航：`MMDisk.swift:307` `doNavigate` 每次回跳都调 `DiskScanner.childrenOfDirectory` 重新遍历该目录求子项大小，而 `DiskScanStore` 已持有全量树。
- 删除：MMDisk **无任何删除入口**。`MMFileScanner/SystemAnalyzer.swift` 的四级安全分级与 `MMCore/FileTrashService.swift` 的废纸篓+撤回机制已经存在，只是没接到磁盘树上。

## 逐维度分析

### 1. 扫描模型

| | |
|---|---|
| disktree | dust 式 rayon scope；`PendingDir` 的 `+1` 哨兵保证目录在全部子任务落地后才构建（scan.rs:677-743）；`ScanProgress` relaxed 原子计数供 UI 轮询；大小默认 `st_blocks×512`（分配量，删了能回来的数），表观大小可切换（1030-1051）；仅 `nlink>1` 的叶子保留 `(dev, ino)` 身份做硬链去重（1002-1017）；符号链接默认不跟随；不可读目录记 `read_error` 而非静默（929-932）；iCloud/FileProvider 已驱逐项凭 `SF_DATALESS` 跳过，绝不触发下载（1064-1070） |
| MacMaster | 纯表观大小；无硬链去重；不可读目录静默消失；无 dataless 识别；DiskScanner 无取消检查点 |
| 判定 | **ADOPT**（分配大小 + 硬链去重 + readError 语义 + dataless 跳过）。rayon 骨架本身 SKIP |
| 落地 | `readEntries` 改读 `st_blocks*512`（lstat 已带回，零额外 syscall）；`DiskTreeNode` 增 `allocated/apparent` 双口径与 `readError: Bool`；扫描后一趟 `dedupeHardlinks`；`st_flags & SF_DATALESS` 判断；循环补 `Task.isCancelled`（照抄 FileTreeWalker.swift:55） |
| 代价 | S（口径与去重）～ M（双口径全链路） |

### 2. Treemap 布局

| | |
|---|---|
| disktree | Bruls/Huizing/van Wijk squarified；`LayoutOptions`：默认画 3 层、min_tile=5px 丢弃、padding 内 1 外 3、每目录最多 96 子、**尾部合并成一个 Others tile 保证面积守恒**（treemap.rs:107-139, 232-258）；子列表每次布局重排（201-223）；可细分目录顶部保留 header 带放自己的名字，宽度 <44px 或剩余体 <3×min_tile 就放弃细分（266-317）；tile 的 crumbs 是从被扫根出发的**绝对**索引链（不变量，591-608）；布局算在未缩放的 base 空间并缓存，`screen=(base-origin)*scale`；标签在屏幕空间按尺寸阈值决定画否，一律裁到本块 |
| MacMaster | squarify 数学正确但单层；无 header / Others / min-tile 布局语义；无视图变换缓存，body 内联重算 |
| 判定 | **ADOPT**（多层嵌套 + header 带 + Others 入引擎）；**ADAPT**（zoom-to-descend 用 SwiftUI 手势重做，代价高，靠后） |
| 落地 | `TreemapView.swift` 新增 `TreemapLayoutOptions(maxDepth/padding/minTile/maxChildren/headerH)`；`compute` 改递归 `placeChildren`，返回带 `depth`、`header: CGRect?`、`isOthers` 的 `TreemapRect`；块多时换 `Canvas` 一次绘完（对齐 disktree"treemap 是画出来的，不是元素拼出来的"），标签在 draw 闭包里按尺寸阈值分支 |
| 代价 | M |

### 3. 分类 / 着色

| | |
|---|---|
| disktree | 9 类 `Category` + 9 种 `Reclaim` 理由（classify.rs:21-93）；判定全靠名字表；`reclaim_of` 带**兄弟证据**规则——`target` 只在有 `Cargo.toml` 旁才算构建输出、`node_modules` 须伴 `package.json`（185-223）；自顶向下：本名优先否则继承父类，reclaim 向下继承（缓存下整片都是斜纹）；未知顶层目录取"最大可识别子目录"的颜色；**颜色=种类、斜纹=可否回收，两个问题独立可读**（palette.rs:1-12） |
| MacMaster | 颜色只按 GB 分档；`SystemAnalyzer` 侧有近似的安全分级模型但没有共享给磁盘树 |
| 判定 | **ADOPT**——disktree 最具产品价值的逻辑，纯查表、零平台耦合，且词条本身已含 macOS 路径（DerivedData、iOS DeviceSupport、CoreSimulator） |
| 落地 | 新建 `MMDisk/DiskClassify.swift`，定义 `enum NodeCategory` / `enum ReclaimReason`，移植 `categoryOfName` / `reclaimOf`；扫描后一趟 `classify(tree)`；`nodeToTreemapItem` 改为按 category 取色，`TreemapItem` 增 `reclaimable: Bool`，Canvas 叠斜线 pattern |
| 代价 | M |

### 4. Insights（"Worth a look"）

| | |
|---|---|
| disktree | 只有三种发现，全部指向**人一秒能判断的目录**而非原始大小；规则：取最顶层（可回收目录下的不再列）、<64MiB 不值得列一行、发现互不嵌套所以总和可信；面板限 6 条 |
| MacMaster | 仅"大文件 >10MiB 前 100"，是原始大小榜，无判断辅助 |
| 判定 | **ADOPT**（把 worktrees/experiments 换成 Mac 语义：DerivedData、各 app 缓存、久未触碰的 Downloads 子项） |
| 落地 | `DiskInsights.swift` 的 `worthALook(root:now:limit:)` 复用第 3 条的 reclaim 标记 + mtime（需在 lstat 里补采 `st_mtimespec`，口径同 FileTreeWalker.swift:66）；详情面板加一节 |
| 代价 | S～M（依赖 #1/#3 先落地） |

### 5. 标记 → 审查 → 提交的两阶段删除

| | |
|---|---|
| disktree | marks 以**绝对路径**为键，重扫后凭路径重新挂回树、消失的 mark 归零重读（marks.rs:64-81）；标父吞子；四个屏幕 Explore/Review/Running/Done；commit 时 Trash 直接执行（可撤回），Permanent 必先弹确认并点名"什么会走、回来多少"；删除前 `plan()` 统一裁决：root 外路径 blocked、挂载点/家目录/系统树拒绝（removal.rs:97-191）；完成后以 statvfs 前后差报告**实际**回收 |
| MacMaster | 磁盘模块 0 删除能力；`FileTrashService` 已是 disktree TrashBackend 的等价物，缺的是树上标记与安全裁决 |
| 判定 | **ADAPT**——SwiftUI 里 selection-set + review sheet 完全可行，但要补三条纪律：按绝对路径存 marks、祖先吞并、永久删除单独确认 |
| 落地 | `@State markedPaths: Set<String>`；`DiskScanStore.target(for:) -> MarkTarget?`；Tile 渲染加 danger 描边；新增 `RemovalReviewSheet`（列出 marks、合计字节、blocked 原因），Trash 走 `FileTrashService.shared`，永久删除加 `.confirmationDialog`；在现有 `protectedNames`（MMDisk.swift:550-559）之上加 root / 挂载盘 / `/System` 前缀拒绝 |
| 代价 | M |

### 6. 空闲空间始终在视野

| | |
|---|---|
| disktree | `SpaceInfo{total, free, available}`，used 由 free 推；`after_removing(bytes)` 饱和且同一字节不重复计；侧栏实时显示"现在 free → 标记后 free"；卷选择器按最满优先、滤掉伪文件系统与重复挂载 |
| MacMaster | 有静态三数 + StorageBar，但无标记投影、无跨卷 |
| 判定 | **ADOPT**（投影，随 #5 免费落地）；卷选择器 **ADAPT** |
| 落地 | `DiskScanResult` 旁存 `SpaceInfo` 与 `afterRemoving(_:)` 纯函数；有 marks 时信息条追加 "→ X 可用"。卷枚举改用 `volumeAvailableCapacityForImportantUsageKey`，比 `df` 口径更接近 Finder |
| 代价 | S |

### 7. 导航 / 选择 UX

| | |
|---|---|
| disktree | Enter 进入 / Backspace 上升 / 方向键与 hjkl 几何移动 / Tab 轮转同层最大兄弟 / Space 标记；前进后退历史栈存**绝对路径**而非 crumbs（重扫会重编号）；`[`/`]` 增减绘制深度；`/` 三键搜索框：匹配项保色、含匹配祖先退色两级、Enter 应用为按匹配体积重排的 filtered layout、Esc 即弃 |
| MacMaster | 点击 drillInto + 面包屑回跳，且回跳会重新遍历目录求大小；无键盘、无 filter、无深度切换 |
| 判定 | **ADOPT**（filter + 深度切换 + 键盘选中）；**ADAPT**（zoom-to-descend）；**SKIP**（crumb 兄弟菜单，macOS 用户习惯侧键即可）。另必须修：面包屑回跳改为从 `DiskScanStore` 解析，不重扫 |
| 代价 | M（键盘+filter）；L（含缩放手势全套） |

## 优先级落地清单（Top 5，按价值 / 成本）

| # | 事项 | 判定 | 代价 | 理由 |
|---|---|---|---|---|
| 1 | `st_blocks×512` 口径 + 表观切换 + 硬链去重 + `readError` 标记 + iCloud dataless 跳过 | ADOPT | S | 数字不对，一切白搭；纯 lstat 内改动 |
| 2 | Category / Reclaim 分类着色 + 可回收斜纹 | ADOPT | M | disktree 的灵魂；查表逻辑零平台耦合 |
| 3 | 树上 marks → Review sheet → Trash 直提 / Permanent 先确认 + 空间投影 | ADAPT | M | 磁盘模块目前"只能看不能清"，机制侧已备好 |
| 4 | Worth a look 面板（reclaimable + stale + 大文件统一为"发现"） | ADOPT | S-M | 依赖 #2/#3 的状态，边际成本低、感知价值高 |
| 5 | Treemap 多层嵌套 + header 带 + Others 入引擎 + Canvas 重写；随后 filter / 键盘导航；顺带修 `doNavigate` 重扫 | ADOPT/ADAPT | M-L | 显示逻辑的主战场 |

## 明确不采纳项及理由

- **rayon scope + `PendingDir` 原子计数器整套扫描骨架**：解决的是 Rust 无 GC 递归栈问题；Swift `withTaskGroup` 滑动窗口已是同型工程解，重写只赚风险不赚性能。
- **`/proc` 挂载表解析、btrfs 子卷/快照/bind-mount 去重**：Linux 专属。macOS 对应问题（Data 卷二次挂载、本地快照）简化为跳过 `/System/Volumes/Data` 并说明 purgeable 口径即可。
- **MFT 直读与 Windows 卷审计**（mft.rs、windows.rs）：平台不相关。
- **GPUI canvas / rem / 主题混合体系**：SwiftUI 已有等价物；只取其绘制顺序与标签分级规则，不取其实现。
- **重复文件查找**：disktree 本身没有，不属本条采纳范围（另案，见功能演化清单 P0）。
- **`Known` 加宽扫描记忆化**：MacMaster 尚无"加宽扫描根"的交互，等根切换需求出现后再议。

## 落地进度（2026-09-30）

| 清单项 | 状态 | 落点 |
|---|---|---|
| #1 口径（st_blocks / 硬链 / readError / dataless） | ✅ 已落地 | `MMDisk.swift` `DiskScanner` |
| #2 Category + Reclaim 着色、可回收斜纹 | ✅ 已落地 | `DiskClassify.swift` + `TreemapView` 斜纹 |
| #3 marks → Review → Trash | 🟡 部分落地 | `DiskRemoval.plan` 裁决 + 审查面板 + Trash/撤回已通；**Permanent 删除未做**（见下） |
| #4 Worth a look | ✅ 已落地 | `DiskInsights.swift`，8 条单测 |
| #5 嵌套 treemap / Canvas / header 带 / Others | ✅ 已落地 | `TreemapLayoutOptions` |
| #6 空间投影 afterRemoving | ✅ 已落地 | `DiskRemoval.afterRemoving`，面包屑与审查面板共用 |
| #7 键盘导航 / filter / 深度切换 / 面包屑回跳不重扫 | ✅ 已落地 | `DiskTreeFilter.swift` + `MMDisk.swift`，口径见 `feature-roadmap.md` 的「P1.7 落地」；filter 从"只过滤当前层"改成全树命中体积 |

### 刻意推迟的两件事

- **永久删除（Permanent delete）**：机制上只剩"确认文案 + 二次对话框"，但它把本模块的
  最坏情况从"进废纸篓、可撤回"提升到"数据不可恢复"。在 #7 的键盘导航落地之前，
  误标概率已经足够低，先不引入这条路径；引入时它必须走独立的确认文案，
  点名"什么会走、回来多少"，而不是复用 Trash 的面板。
- **跨重扫保留 marks**（disktree 的"凭绝对路径重新挂回树"）：当前实现是重扫即清空标记。
  保留标记要连带解决"旧快照的大小与新扫描不一致"的口径问题，收益是少点几次标记，
  风险是面板上的数字来自两个时间点。留到 #7 一起做。
