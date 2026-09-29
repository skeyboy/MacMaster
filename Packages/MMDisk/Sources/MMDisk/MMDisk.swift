import SwiftUI
import Darwin
import MMCore
import MMUI
import MMFileScanner

public struct DiskModule: ModuleRegistrable {
    public var moduleID: String { "disk" }
    public var moduleName: String { "磁盘分析" }
    public var moduleIcon: String { "internaldrive" }
    public var modulePriority: Int { 3 }

    public init() {}

    public func createView() -> AnyView {
        AnyView(DiskAnalyzerView())
    }
}

public struct DiskAnalyzerView: View {
    enum ViewMode: String, CaseIterable, Identifiable {
        case treemap = "Treemap"
        case list = "列表"
        case large = "大文件"
        var id: String { rawValue }
    }

    @State private var selected: DiskTreeNode?
    @State private var scanResult: DiskScanResult?
    @State private var isScanning = false
    @State private var scanningPath: String = ""
    @State private var scanningFileCount: Int = 0
    @State private var scanStartTime: Date = Date()
    @State private var scanDuration: TimeInterval = 0
    @State private var navigationStack: [String] = []
    // currentItems 只存有界渲染窗口；全量数据在 scanStore 里，一条不丢
    @State private var currentItems: [DiskTreeNode] = []
    @State private var scanStore: DiskScanStore?
    @State private var largeFiles: [DiskTreeNode] = []
    @State private var mode: ViewMode = .treemap
    @State private var nameFilter = ""
    /// 标记待处理的目录/文件：Treemap 上 ⌘ 点击打点，底部统一结算。
    @State private var marked: [String: DiskTreeNode] = [:]
    @State private var showMarkConfirm = false
    @State private var isTrashing = false
    @State private var trashFailures: [TrashFailure] = []
    @State private var undoSeconds = 0
    @State private var trashedCount = 0
    @State private var trashedSize: UInt64 = 0
    /// 当前层总大小：行内占比的分母，导航时算一次，不在 body 里重算。
    @State private var levelTotal: UInt64 = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            if isScanning && scanResult == nil {
                scanningView
            } else if let result = scanResult {
                breadcrumbBar
                Divider()
                HStack(spacing: 0) {
                    mainColumn
                    if let node = selected {
                        Divider()
                        inspector(node: node)
                            .frame(width: MMMetric.inspector)
                    }
                }
                Divider()
                if !trashFailures.isEmpty {
                    MMFailurePanel(trashFailures) { trashFailures = [] }
                        .padding([.horizontal, .top], MMGap.md)
                }
                actionBar(result: result)
            } else {
                placeholder
            }
        }
        .sheet(isPresented: $showMarkConfirm) { markConfirmSheet }
        .overlay(alignment: .bottom) {
            if undoSeconds > 0 {
                MMUndoToast(
                    message: "已移入废纸篓 \(MMFormat.bytes(trashedSize))",
                    detail: "共 \(trashedCount) 项",
                    secondsRemaining: undoSeconds,
                    onUndo: { Task { await undoTrash() } },
                    onRevealTrash: { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")) }
                )
                .padding(.bottom, MMGap.lg)
            }
        }
        .task(id: undoSeconds) {
            while undoSeconds > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                undoSeconds -= 1
            }
        }
        .task {
            // 仅用于无头截图验证：NSOpenPanel 没法自动点，用环境变量把扫描根传进来。
            let env = ProcessInfo.processInfo.environment
            guard scanResult == nil, let root = env["MM_DISK_SCAN"], !root.isEmpty else { return }
            await scan(rootPath: (root as NSString).expandingTildeInPath)
        }
    }

    private var header: some View {
        MMPageHeader("磁盘分析", subtitle: headerSubtitle) {
            Picker("视图", selection: $mode) {
                ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()

            TextField("筛选名称", text: $nameFilter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 132)
                .disabled(mode == .large)

            Button {
                if let path = navigationStack.last { Task { await doNavigate(path: path) } }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(isScanning || navigationStack.isEmpty)

            Button {
                Task { await scanDirectory() }
            } label: {
                Label(isScanning ? "分析中…" : "选择目录", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)
        }
    }

    /// 副标题只报事实：路径、文件数、占用、用时。
    private var headerSubtitle: String? {
        guard let result = scanResult else {
            return isScanning ? scanningPath : "选择一个目录开始分析"
        }
        return "\(result.path) · \(MMFormat.count(result.fileCount)) 个文件 · "
            + "\(MMFormat.bytes(result.scannedSize)) · 扫描用时 \(String(format: "%.1f", scanDuration)) s"
    }

    private var placeholder: some View {
        MMEmptyState(
            systemImage: "internaldrive",
            title: "还没有分析结果",
            detail: "选一个目录，MacMaster 会按实际占用画出每一层，点块下钻、⌘ 点块标记。"
        ) {
            Button {
                Task { await scanDirectory() }
            } label: {
                Label("选择目录", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// 深度扫描进行中。头部已经在报"扫描…"和实时文件数，所以这里只补
    /// 头部放不下的两件事：完成度估算，和当前正在枚举的那一层。
    /// 图标不用带警告三角的变体——扫描是正常的长任务，不是出错。
    private var scanningView: some View {
        VStack(spacing: MMGap.xl) {
            Spacer()

            Image(systemName: "internaldrive")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(MMColor.accent)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: MMGap.xs) {
                Text("正在分析磁盘结构")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MMColor.label)
                Text("完成后即可按面积下钻，中途可以切换目录重新扫描")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            // 不确定态：总量未知时任何百分比都是编的，这里只报已经数出来的东西。
            ProgressView()
                .controlSize(.small)
                .frame(width: 260)

            VStack(spacing: MMGap.sm) {
                if !scanningPath.isEmpty {
                    HStack(spacing: MMGap.xs) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(MMColor.secondaryLabel)
                        Text(scanningPath)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(MMColor.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 460)
                }

                HStack(spacing: MMGap.lg) {
                    Label(MMFormat.count(scanningFileCount) + " 个文件", systemImage: "doc")
                    Label(elapsedTimeText, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MMColor.contentBackground)
    }

    private var elapsedTimeText: String {
        let elapsed = Int(Date().timeIntervalSince(scanStartTime))
        if elapsed < 60 { return "\(elapsed) 秒" }
        return "\(elapsed / 60) 分 \(elapsed % 60) 秒"
    }

    private var breadcrumbBar: some View {
        HStack(spacing: MMGap.sm) {
            breadcrumbTrail

            Spacer(minLength: MMGap.md)

            if !marked.isEmpty {
                MMBadge("已标记 \(marked.count) 项 · \(MMFormat.bytes(markedSize))",
                        tint: MMColor.informational, systemImage: "checkmark.circle.fill")
            }
            MMBadge("卷可用 \(MMFormat.bytes(freeSize))", tint: MMColor.secondaryLabel)
        }
        .padding(.horizontal, MMGap.lg)
        .frame(height: 34)
        .background(MMColor.contentBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var breadcrumbTrail: some View {
        BreadcrumbView(
            items: navigationStack.enumerated().map { BreadcrumbItem(index: $0.offset, path: $0.element) },
            lastIndex: navigationStack.count - 1,
            onTap: { index in navigateTo(index: index) }
        )
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if mode == .treemap { legend }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if isScanning {
            // 单层枚举没有进度可估（不知道总量），只给不确定态指示
            VStack(spacing: MMGap.sm) {
                ProgressView().controlSize(.small)
                Text("正在枚举 \(scanningPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch mode {
            case .treemap: treemapView
            case .list: listView
            case .large: largeFilesList
            }
        }
    }

    private var treemapView: some View {
        TreemapView(
            items: visibleItems.map { treemapItem(for: $0, depth: 0) },
            options: treemapOptions,
            markedIDs: Set(marked.keys),
            selectedID: selected?.path,
            onSelect: { item in selected = resolve(item) },
            onDrill: { item in drill(path: item.id) },
            onMark: { item in toggleMark(resolve(item)) },
            onBack: {
                guard navigationStack.count > 1 else { return }
                navigateTo(index: navigationStack.count - 2)
            }
        )
        .padding(MMGap.sm)
        .help("Tab 聚焦后可用方向键移动选中块，回门下钻，空格标记，Esc 返回上一层")
    }

    /// 图例说明的是读法，不是配色表：色相=种类，斜纹=可清理。
    /// 窄窗口下先保住色块和纹样（它们是解码图形所必需的），
    /// 让右侧那句说明截断，而不是把色块挤没。
    private var legend: some View {
        HStack(spacing: MMGap.md) {
            ForEach(NodeCategory.allCases, id: \.self) { category in
                swatch(label: category.displayName, fill: category.color)
            }
            HStack(spacing: MMGap.xs) {
                TreemapHatchSwatch()
                Text("可清理（斜纹）").font(.caption).foregroundStyle(MMColor.secondaryLabel).fixedSize()
            }
            .layoutPriority(1)
            Spacer(minLength: MMGap.sm)
            Text("面积 = 实际占用（st_blocks × 512）· 双击下钻 · ⌘点击标记")
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
        .padding(.horizontal, MMGap.lg)
        .frame(height: 26)
        .background(MMColor.contentBackground)
        .overlay(alignment: .top) { Divider() }
    }

    private func swatch(label: String, fill: Color) -> some View {
        HStack(spacing: MMGap.xs) {
            RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(MMColor.secondaryLabel).fixedSize()
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: MMGap.xxs) {
                // visibleItems 存入时已按大小排序，body 里不再重排
                ForEach(visibleItems) { node in
                    nodeRow(node)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = node }
                        .onTapGesture(count: 2) { drill(path: node.path) }
                        .contextMenu { rowMenu(node) }
                }
            }
            .padding(MMGap.md)
        }
    }

    private func nodeRow(_ node: DiskTreeNode) -> some View {
        let share = levelTotal > 0 ? Double(node.size) / Double(levelTotal) : 0
        return HStack(spacing: MMGap.sm) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: MMGap.lg))
                .foregroundStyle(node.isDirectory ? MMColor.accent : MMColor.secondaryLabel)
                .frame(width: MMGap.xxl)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MMColor.fillActive)
                        Capsule().fill(MMColor.accent.opacity(0.7))
                            .frame(width: max(2, proxy.size.width * CGFloat(share)))
                    }
                }
                .frame(height: 3)
            }
            Spacer(minLength: MMGap.md)
            Text(MMFormat.percent(share))
                .font(.caption.monospacedDigit())
                .foregroundStyle(MMColor.tertiaryLabel)
                .frame(width: 44, alignment: .trailing)
            Text(MMFormat.bytes(node.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(width: 78, alignment: .trailing)
            if marked[node.path] != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MMColor.informational)
                    .font(.system(size: MMGap.lg))
            }
        }
        .padding(.horizontal, MMGap.sm)
        .frame(height: MMMetric.rowRegular)
        .background(selected?.path == node.path ? MMColor.fillActive : .clear)
        .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
    }

    @ViewBuilder
    private func rowMenu(_ node: DiskTreeNode) -> some View {
        Button("在访达中显示") { MMReveal.open(node.path) }
        if node.isDirectory {
            Divider()
            Button("进入该目录") { drill(path: node.path) }
            Button(marked[node.path] == nil ? "标记" : "取消标记") { toggleMark(node) }
                .disabled(!risk(of: node.path).allowsDeletion)
        }
    }

    private var largeFilesList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                // largeFiles 存入时已按大小排序，body 里不再重排
                ForEach(largeFiles) { file in
                    nodeRow(file)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = file }
                        .contextMenu { rowMenu(file) }
                }
            }
            .padding()
        }
    }

    private func inspector(node: DiskTreeNode) -> some View {
        let risk = risk(of: node.path)
        let children = node.children.sorted { $0.size > $1.size }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: MMGap.xs) {
                HStack(spacing: MMGap.sm) {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(risk.color)
                    Text(node.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: MMGap.xs)
                    MMBadge(risk: risk)
                }
                Text(node.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(MMGap.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.cardBackground)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: MMGap.md) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MMGap.sm) {
                        MMStatItem("占用", MMFormat.bytes(node.size))
                        MMStatItem("占当前层", MMFormat.percent(levelTotal > 0 ? Double(node.size) / Double(levelTotal) : 0))
                        MMStatItem("子项", node.isDirectory ? MMFormat.count(children.count) : "—")
                        MMStatItem("修改", MMFormat.dateTime(modDate(of: node.path)))
                    }

                    if !children.isEmpty {
                        VStack(alignment: .leading, spacing: MMGap.xs) {
                            Text("内部构成").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                            VStack(spacing: 0) {
                                ForEach(children.prefix(6)) { child in
                                    HStack {
                                        Text(child.name).font(.callout).lineLimit(1)
                                        Spacer(minLength: MMGap.sm)
                                        Text(MMFormat.bytes(child.size))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(MMColor.secondaryLabel)
                                    }
                                    .frame(height: MMMetric.rowCompact)
                                    Divider()
                                }
                            }
                            .background(MMColor.contentBackground)
                            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: MMRadius.control).stroke(MMColor.separator))
                        }
                    }

                    HStack(spacing: MMGap.sm) {
                        MMRevealButton(path: node.path, title: "在访达中显示")
                        if risk.allowsDeletion {
                            Button {
                                toggleMark(node)
                            } label: {
                                Label(marked[node.path] == nil ? "标记" : "取消标记",
                                      systemImage: marked[node.path] == nil ? "checkmark.circle" : "circle")
                            }
                        }
                    }

                    Divider()

                    if let reclaim = node.reclaim {
                        // 斜纹说了"可清"，这里要说"为什么可清、清了会怎样"，
                        // 否则用户只能凭色相猜。
                        HStack(alignment: .top, spacing: MMGap.xs) {
                            TreemapHatchSwatch(base: node.category.color)
                                .padding(.top, 2)
                            Text("可清理 · \(reclaim.note)")
                                .font(.caption)
                                .foregroundStyle(MMColor.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(risk.groupNote)
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MMGap.md)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MMColor.contentBackground)
    }

    private func actionBar(result: DiskScanResult) -> some View {
        MMActionBar(
            summary: marked.isEmpty ? "卷可用 \(MMFormat.bytes(result.freeSize))"
                                    : "已标记 \(marked.count) 项 · \(MMFormat.bytes(markedSize))",
            note: marked.isEmpty ? "统计不含符号链接目标 · 硬链接只计一次"
                                 : "移入废纸篓后 15 秒内可一键撤回"
        ) {
            HStack(spacing: MMGap.sm) {
                if !marked.isEmpty {
                    Button("清空标记") { marked.removeAll() }
                        .disabled(isTrashing)
                    Button(isTrashing ? "处理中…" : "移入废纸篓", action: requestTrash)
                        .buttonStyle(.borderedProminent)
                        .tint(MMColor.destructive)
                        .disabled(isTrashing)
                }
            }
        }
    }

    /// 嵌套 treemap 的输入：只带上布局真正会画的子块，
    /// 每层的数量上限和 TreemapLayoutOptions 保持一致，避免白构造。
    private func treemapItem(for node: DiskTreeNode, depth: Int) -> TreemapItem {
        var children: [TreemapItem] = []
        if node.isDirectory, depth + 1 < treemapOptions.maxDepth {
            children = node.children
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }
                .prefix(treemapOptions.childCap(at: depth + 1))
                .map { treemapItem(for: $0, depth: depth + 1) }
        }
        return TreemapItem(
            id: node.id,
            name: node.name,
            value: Double(node.size),
            color: TreemapPalette.shade(node.category.color, depth: depth),
            children: children,
            isDirectory: node.isDirectory,
            reclaimable: node.reclaim != nil
        )
    }

    private var treemapOptions: TreemapLayoutOptions {
        var options = TreemapLayoutOptions()
        options.maxDepth = 3
        return options
    }

    private func navigateTo(index: Int) {
        guard index < navigationStack.count else { return }
        navigationStack = Array(navigationStack.prefix(index + 1))
        guard let path = navigationStack.last else { return }
        openDirectory(at: path)
    }

    private func openDirectory(at path: String, prefetched: [DiskTreeNode]? = nil) {
        guard !path.isEmpty else { return }
        if let prefetched, !prefetched.isEmpty {
            apply(children: prefetched, for: path)
            return
        }
        if let cached = scanStore?.cachedChildren(for: path) {
            apply(children: cached, for: path)
            return
        }
        Task { await doNavigate(path: path) }
    }

    private func apply(children: [DiskTreeNode], for path: String) {
        let sorted = children.sorted { $0.size > $1.size }
        levelTotal = sorted.reduce(UInt64(0)) { $0 + $1.size }
        guard let scanStore else {
            currentItems = sorted
            return
        }
        scanStore.commit(sorted, for: path)
        currentItems = scanStore.displayWindow(of: scanStore.currentChildren)
    }

    // MARK: - 选中、标记与删除

    private var visibleItems: [DiskTreeNode] {
        guard !nameFilter.isEmpty else { return currentItems }
        return currentItems.filter { $0.name.localizedCaseInsensitiveContains(nameFilter) }
    }

    private var markedSize: UInt64 {
        marked.values.reduce(0) { $0 + $1.size }
    }

    private var freeSize: UInt64 { scanResult?.freeSize ?? 0 }

    /// 在当前层及其已扫描的子树里找节点；找不到返回 nil
    /// （深层块的大小由 TreemapItem 自带，见 resolve(_:)）。
    private func node(atPath path: String) -> DiskTreeNode? {
        guard !path.isEmpty, let current = scanStore?.currentChildren else { return nil }
        if let direct = current.first(where: { $0.path == path }) { return direct }
        for top in current {
            if let deep = Self.search(path: path, in: top.children) { return deep }
        }
        return nil
    }

    /// TreemapItem 是从扫描数据直接构建的，块上的 value 就是真实大小；
    /// 点中的块不在当前层时用它还原节点，详情面板照样有准确数字。
    private func resolve(_ item: TreemapItem) -> DiskTreeNode {
        node(atPath: item.id) ?? DiskTreeNode(
            id: item.id, name: item.name, path: item.id,
            size: UInt64(max(0, item.value)),
            isDirectory: item.isDirectory, children: []
        )
    }

    private static func search(path: String, in nodes: [DiskTreeNode]) -> DiskTreeNode? {
        for node in nodes {
            if node.path == path { return node }
            if let deeper = search(path: path, in: node.children) { return deeper }
        }
        return nil
    }

    private func drill(path: String) {
        guard !path.isEmpty else { return }
        navigationStack.append(path)
        // 扫描时已经把这一层拿全就直接用；深度截断留下的空 children
        // 必须回落到重新枚举，否则会点进一个"看起来是空"的目录。
        openDirectory(at: path, prefetched: node(atPath: path)?.children)
    }

    private func modDate(of path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// 风险判定与清理页共用 MMRisk：同一个路径在两处给出同一个结论。
    /// 按路径组件判断，避免 "/build" 这类前缀误伤 "rebuild" 之类的目录名。
    private func risk(of path: String) -> MMRisk {
        let protectedRoots = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private/etc"]
        if protectedRoots.contains(where: { path.hasPrefix($0) }) { return .readOnly }
        let home = NSHomeDirectory()
        let userData = ["Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]
            .map { home + "/" + $0 }
        if userData.contains(where: { path.hasPrefix($0) }) { return .readOnly }
        let rebuildable: Set<String> = ["Caches", "DerivedData", "node_modules", "Logs",
                                       ".Trash", ".cache", "Build", "build", "CoreSimulator"]
        if path.split(separator: "/").contains(where: { rebuildable.contains(String($0)) }) {
            return .safe
        }
        return .caution
    }

    private func toggleMark(_ node: DiskTreeNode) {
        guard risk(of: node.path).allowsDeletion else { return }
        if marked.removeValue(forKey: node.path) == nil { marked[node.path] = node }
    }

    private func requestTrash() {
        guard !marked.isEmpty else { return }
        showMarkConfirm = true
    }

    /// 仅供截图验证：MM_DISK_SELECT 给一个路径，展开它所在的一层并选中，
    /// 这样详情面板能在没有任何人工点击的情况下被拍到。
    private func applySelectionHook() {
        guard let target = ProcessInfo.processInfo.environment["MM_DISK_SELECT"],
              !target.isEmpty else { return }
        let parent = (target as NSString).deletingLastPathComponent
        if parent != navigationStack.last {
            navigationStack.append(parent)
            openDirectory(at: parent)
        }
        selected = node(atPath: target)
    }

    private var markConfirmSheet: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            Text("把 \(marked.count) 项移入废纸篓？")
                .font(.title3.weight(.semibold))
            Text("项目会进入废纸篓，15 秒内可一键撤回；此后需要自己在访达里恢复。")
                .font(.callout)
                .foregroundStyle(MMColor.secondaryLabel)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(marked.values.sorted { $0.size > $1.size }) { node in
                    HStack(spacing: MMGap.sm) {
                        Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(risk(of: node.path).color)
                            .frame(width: MMGap.xxl)
                        Text(node.name).font(.callout).lineLimit(1)
                        Spacer(minLength: MMGap.sm)
                        Text(MMFormat.bytes(node.size))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MMColor.secondaryLabel)
                    }
                    .padding(.horizontal, MMGap.md)
                    .frame(height: MMMetric.rowCompact)
                    Divider()
                }
            }
            .background(MMColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.control).stroke(MMColor.separator))

            HStack {
                Spacer()
                Button("取消") { showMarkConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button("移入废纸篓 \(MMFormat.bytes(markedSize))") {
                    Task { await trashMarked() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MMGap.lg)
        .frame(width: 420)
    }

    private func trashMarked() async {
        isTrashing = true
        defer { isTrashing = false }
        showMarkConfirm = false
        let paths = Array(marked.keys)
        marked.removeAll()

        let result = await FileTrashService.shared.moveToTrash(paths: paths)
        trashedCount = result.successCount
        trashedSize = result.totalSize
        trashFailures = result.operation.failures
        selected = nil
        undoSeconds = trashedCount > 0 ? 15 : 0

        // 删完之后磁盘和内存里的数字必须一致：重新枚举当前层
        if let path = navigationStack.last { await doNavigate(path: path) }
    }

    private func undoTrash() async {
        undoSeconds = 0
        let restored = await FileTrashService.shared.undoLastOperation()
        trashFailures = restored.failures
        if let path = navigationStack.last { await doNavigate(path: path) }
    }

    private func doNavigate(path: String) async {
        isScanning = true
        scanningPath = path
        scanningFileCount = 0
        scanStartTime = Date()
        // 单层重新枚举要把父层已有的分类/可清理结论带下去，
        // 否则同一目录在全盘扫描和下钻视图里会长得不一样。
        let parent = node(atPath: path)
        let items = await Task.detached {
            await DiskScanner.childrenOfDirectory(
                path: path,
                inheritedCategory: parent?.category ?? DiskClassify.context(forPath: path).0,
                inheritedReclaim: parent?.reclaim ?? DiskClassify.context(forPath: path).1
            )
        }.value
        // 枚举期间用户可能已经点到别处，只接受最新一次导航的结果
        guard navigationStack.last == path else {
            isScanning = false
            return
        }
        apply(children: items, for: path)
        isScanning = false
    }

    private func scanDirectory() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let scoped = url.startAccessingSecurityScopedResource()
        await scan(rootPath: url.path)
        if scoped { url.stopAccessingSecurityScopedResource() }
    }

    private func scan(rootPath: String) async {
        let rootURL = URL(fileURLWithPath: rootPath)

        isScanning = true
        scanningPath = "正在检查访问权限..."
        scanningFileCount = 0
        scanStartTime = Date()

        let accessiblePaths = await Task.detached {
            DiskScanner.prepareAccessiblePaths(rootURL: rootURL, rootPath: rootPath)
        }.value

        scanningPath = "正在分析目录结构..."

        let tracker = ScanProgressTracker()

        // 轮询放在 detached 任务上，不占用 MainActor 时间片；500ms 采样、内容未变则跳过赋值。
        // 丢掉的中间帧只影响进度展示；权威统计始终由 performScan 的返回值给出。
        let progressTask = Task.detached(priority: .utility) {
            var lastPath = ""
            var lastCount = -1
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    break
                }
                let snap = tracker.snapshot()
                if snap.path != lastPath || snap.fileCount != lastCount {
                    lastPath = snap.path
                    lastCount = snap.fileCount
                    await MainActor.run {
                        if !snap.path.isEmpty {
                            self.scanningPath = snap.path
                        }
                        self.scanningFileCount = snap.fileCount
                    }
                }
            }
        }

        let output = await Task.detached {
            await DiskScanner.performScan(rootPath: rootPath, accessiblePaths: accessiblePaths, tracker: tracker)
        }.value

        progressTask.cancel()
        // 等待轮询退出，确保 commit 之后不再有迟到的进度写入
        await progressTask.value

        let totalSize: UInt64 = {
            if let vals = try? rootURL.resourceValues(forKeys: [.volumeTotalCapacityKey]),
               let cap = vals.volumeTotalCapacity {
                return UInt64(cap)
            }
            return 0
        }()
        // 可用容量按"重要用途"口径读：普通口径把 purgeable 空间算成已用，
        // 结果进度条常年 95% 满，和"关于本机"对不上。
        let freeSize: UInt64 = {
            if let vals = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let cap = vals.volumeAvailableCapacityForImportantUsage, cap > 0 {
                return UInt64(cap)
            }
            if let vals = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
               let cap = vals.volumeAvailableCapacity {
                return UInt64(cap)
            }
            return 0
        }()
        let usedSize = totalSize > freeSize ? totalSize - freeSize : 0

        await MainActor.run {
            // 不用 withAnimation：整棵结果子树的换入会被纳入动画事务反复 diff/布局，
            // 大目录结果下会长时间占住主线程
            let store = DiskScanStore(rootItems: output.topItems)
            self.scanStore = store
            self.scanResult = DiskScanResult(
                path: rootPath,
                totalSize: totalSize,
                usedSize: usedSize,
                freeSize: freeSize,
                scannedSize: output.topItems.reduce(UInt64(0)) { $0 + $1.size },
                fileCount: output.fileCount
            )
            self.navigationStack = [rootPath]
            self.marked = [:]
            self.selected = nil
            self.trashFailures = []
            self.largeFiles = Array(output.largeFilesList.prefix(100))
            self.apply(children: output.topItems, for: rootPath)
            self.applySelectionHook()
            self.scanDuration = Date().timeIntervalSince(scanStartTime)
            self.isScanning = false
        }
    }
}

struct DiskTreeNode: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: UInt64
    let isDirectory: Bool
    var children: [DiskTreeNode]
    var category: NodeCategory = .other
    var reclaim: ReclaimReason? = nil
}

/// 完整扫描结果驻留在引用类型里：@State 只持有有界渲染窗口，
/// 这样数据一条不丢，而 SwiftUI 每次 body 重算的 diff/map 成本从全量节点降到窗口大小。
/// 仅在主线程访问，不做跨线程共享。
final class DiskScanStore {
    static let renderWindow = 200
    let rootItems: [DiskTreeNode]
    var currentChildren: [DiskTreeNode]
    /// 已经拿到手的层缓存起来：面包屑回退时直接命中，不必重新枚举整棵子树。
    private var childrenByPath: [String: [DiskTreeNode]] = [:]

    init(rootItems: [DiskTreeNode]) {
        self.rootItems = rootItems
        self.currentChildren = rootItems
    }

    func cachedChildren(for path: String) -> [DiskTreeNode]? {
        childrenByPath[path]
    }

    /// 空结果不写缓存：目录本身为空时重新枚举几乎不花钱，
    /// 而深度截断产生的假空层一旦被缓存，回退后就再也看不到内容。
    func cache(_ children: [DiskTreeNode], for path: String) {
        guard !children.isEmpty else { return }
        childrenByPath[path] = children
    }

    /// 只渲染按大小排序后的前 renderWindow 项，其余合并为一个"其余"块；
    /// 合并块的大小由剩余项求和得出，treemap 总面积与真实占用保持一致。
    /// 调用方需保证 items 已按 size 降序。
    func displayWindow(of items: [DiskTreeNode]) -> [DiskTreeNode] {
        guard items.count > Self.renderWindow else { return items }
        let rest = items[Self.renderWindow...]
        let restSize = rest.reduce(UInt64(0)) { $0 + $1.size }
        let remainder = DiskTreeNode(
            id: "__remaining__",
            name: "其余 \(rest.count) 项",
            path: "",
            size: restSize,
            isDirectory: false,
            children: []
        )
        return Array(items.prefix(Self.renderWindow)) + [remainder]
    }

    /// 把一层结果设为当前视图，并写入路径缓存。调用方保证 children 来自真实枚举。
    func commit(_ children: [DiskTreeNode], for path: String) {
        let sorted = children.sorted { $0.size > $1.size }
        currentChildren = sorted
        cache(sorted, for: path)
    }
}

struct ProgressSnapshot {
    let path: String
    let fileCount: Int
}

/// 只报已经发生的事实：当前枚举到哪、累计多少条目。
/// 这里刻意没有百分比。目录总量在扫完之前是未知的，而"已完成/已进入"
/// 这种比值恒等于 1（读一个目录的开销就是读它本身），拿它当进度会在
/// 两秒内冲到顶格。宁可给不确定态进度条，也不要一个会撒谎的数字。
final class ScanProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _currentPath: String = ""
    private var _fileCount: Int = 0
    private var counter = 0

    var currentPath: String { lock.withLock { _currentPath } }
    var fileCount: Int { lock.withLock { _fileCount } }

    func report(path: String) {
        lock.withLock {
            counter += 1
            if counter % 10 == 0 {
                _currentPath = path
            }
            _fileCount += 1
        }
    }

    /// UI 侧单次加锁取全量快照，避免多次锁竞争。
    /// 真实统计口径以 DiskScanner.performScan 的返回值为准。
    func snapshot() -> ProgressSnapshot {
        lock.withLock {
            ProgressSnapshot(path: _currentPath, fileCount: _fileCount)
        }
    }
}

struct DiskScanResult {
    let path: String
    let totalSize: UInt64
    let usedSize: UInt64
    let freeSize: UInt64
    /// 被扫描那棵树自己的占用，和"卷总容量"是两回事，页面上不能混用。
    let scannedSize: UInt64
    let fileCount: Int
}

enum DiskScanner {
    struct ScanOutput {
        let topItems: [DiskTreeNode]
        let largeFilesList: [DiskTreeNode]
        let fileCount: Int
    }

    private struct FileEntry: Sendable {
        let name: String
        let path: String
        let isDirectory: Bool
        let size: UInt64
    }

    private static let maxDepth = 20
    private static let maxParallelDepth = 3

    /// 按 (卷, inode) 去重：硬链接的多个名字指向同一份磁盘数据，
    /// 只有第一次出现的那个名字计入占用，其余记 0。
    /// 用锁而不是 actor，是为了能在同步的 lstat 循环里直接调用。
    final class HardlinkLedger: @unchecked Sendable {
        private struct Key: Hashable { let dev: UInt64; let ino: UInt64 }
        private let lock = NSLock()
        private var claimed: Set<Key> = []

        /// 返回 false 表示这份 inode 已经被别的名字统计过。
        func claim(dev: UInt64, ino: UInt64, nlink: UInt16) -> Bool {
            guard nlink > 1 else { return true }
            return lock.withLock { claimed.insert(Key(dev: dev, ino: ino)).inserted }
        }
    }
    private static let protectedNames: Set<String> = [
        "Photos Library.photoslibrary",
        "Mobile Documents",
        ".Trash",
        ".Spotlight-V100",
        ".fseventsd",
        ".TemporaryItems",
        ".PKISyncStore",
        "Library"
    ]
    private static let workerLimit = ProcessInfo.processInfo.activeProcessorCount

    static func performScan(
        rootPath: String,
        accessiblePaths: Set<String>? = nil,
        tracker: ScanProgressTracker? = nil
    ) async -> ScanOutput {
        // 账本贯穿整棵树，跨目录的硬链接也只算一次。
        let ledger = HardlinkLedger()
        let children = await scanChildren(
            path: rootPath, depth: 0,
            accessiblePaths: accessiblePaths, tracker: tracker, ledger: ledger
        )
        let rootContext = DiskClassify.context(forPath: rootPath)
        let topItems = DiskClassify.classify(
            children, inheritedCategory: rootContext.0, inheritedReclaim: rootContext.1
        ).sorted { $0.size > $1.size }

        var fileCount = 0
        var largeFiles: [DiskTreeNode] = []
        collect(children, fileCount: &fileCount, largeFiles: &largeFiles)
        largeFiles.sort { $0.size > $1.size }

        return ScanOutput(
            topItems: topItems,
            largeFilesList: largeFiles,
            fileCount: fileCount
        )
    }

    static func childrenOfDirectory(
        path: String,
        inheritedCategory: NodeCategory = .other,
        inheritedReclaim: ReclaimReason? = nil,
        tracker: ScanProgressTracker? = nil
    ) async -> [DiskTreeNode] {
        // 单独下钻时只能拿到这一子树的账本；与兄弟子树重复计数的
        // 硬链接会各算一次，这是重新枚举单层的固有代价，不谎报为全局去重。
        let nodes = await scanChildren(
            path: path, depth: 0, accessiblePaths: nil, tracker: tracker,
            ledger: HardlinkLedger()
        )
        return DiskClassify.classify(
            nodes, inheritedCategory: inheritedCategory, inheritedReclaim: inheritedReclaim
        )
    }

    /// 目录大小直接由子节点求和得出，避免对同一目录重复枚举。
    private static func scanNode(
        entry: FileEntry, depth: Int, tracker: ScanProgressTracker?, ledger: HardlinkLedger?
    ) async -> DiskTreeNode {
        let children = await scanChildren(path: entry.path, depth: depth, accessiblePaths: nil, tracker: tracker, ledger: ledger)
        let size = children.reduce(UInt64(0)) { $0 + $1.size }
        return DiskTreeNode(
            id: entry.path, name: entry.name, path: entry.path,
            size: size, isDirectory: true, children: children
        )
    }

    private static func scanChildren(
        path: String,
        depth: Int,
        accessiblePaths: Set<String>?,
        tracker: ScanProgressTracker?,
        ledger: HardlinkLedger?
    ) async -> [DiskTreeNode] {
        let entries = readEntries(path: path, ledger: ledger)
        guard !entries.isEmpty else { return [] }

        var result: [DiskTreeNode] = []
        result.reserveCapacity(entries.count)
        var directories: [FileEntry] = []

        for entry in entries {
            if protectedNames.contains(entry.name) { continue }

            if depth == 0, let accessible = accessiblePaths,
               !accessible.contains(entry.path),
               !FileManager.default.isReadableFile(atPath: entry.path) {
                continue
            }

            tracker?.report(path: entry.path)

            if entry.isDirectory {
                directories.append(entry)
            } else {
                result.append(DiskTreeNode(
                    id: entry.path, name: entry.name, path: entry.path,
                    size: entry.size, isDirectory: false, children: []
                ))
            }
        }

        guard !directories.isEmpty else { return result }

        if depth >= maxDepth {
            for dir in directories {
                result.append(DiskTreeNode(
                    id: dir.path, name: dir.name, path: dir.path,
                    size: deepSize(path: dir.path, remainingDepth: 3, ledger: ledger),
                    isDirectory: true, children: []
                ))
            }
            return result
        }

        if depth < maxParallelDepth && directories.count > 1 {
            await withTaskGroup(of: DiskTreeNode.self) { group in
                var next = 0
                while next < min(workerLimit, directories.count) {
                    let dir = directories[next]
                    next += 1
                    group.addTask { await scanNode(entry: dir, depth: depth + 1, tracker: tracker, ledger: ledger) }
                }
                while let node = await group.next() {
                    result.append(node)
                    if next < directories.count {
                        let dir = directories[next]
                        next += 1
                        group.addTask { await scanNode(entry: dir, depth: depth + 1, tracker: tracker, ledger: ledger) }
                    }
                }
            }
        } else {
            for dir in directories {
                result.append(await scanNode(entry: dir, depth: depth + 1, tracker: tracker, ledger: ledger))
            }
        }

        return result
    }

    /// 单次 lstat 同时取得类型和大小；不跟随符号链接，避免环状递归。
    /// 大小口径取 `st_blocks × 512`（实际占用的块数），它已经把 APFS
    /// 透明压缩和稀疏文件算进去了；`st_size` 是解压后的表观大小，
    /// 用它做图会把"看不见但确实占着盘"的部分低估或高估反了方向。
    private static func readEntries(path: String, ledger: HardlinkLedger?) -> [FileEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }

        var entries: [FileEntry] = []
        entries.reserveCapacity(names.count)
        for name in names {
            if name.hasPrefix(".") { continue }
            let fullPath = path + "/" + name
            var info = stat()
            guard Darwin.lstat(fullPath, &info) == 0 else { continue }

            let fileType = info.st_mode & S_IFMT
            let isDirectory = fileType == S_IFDIR

            var size: UInt64 = 0
            if !isDirectory {
                // 符号链接自身不占块，表观大小也会误导，按 0 处理。
                if fileType != S_IFLNK {
                    let counted = ledger?.claim(
                        dev: UInt64(UInt32(bitPattern: info.st_dev)),
                        ino: info.st_ino,
                        nlink: info.st_nlink
                    ) ?? true
                    if counted { size = UInt64(max(0, info.st_blocks)) &* 512 }
                }
            }
            // 目录大小由子节点求和得出。

            entries.append(FileEntry(
                name: name, path: fullPath, isDirectory: isDirectory, size: size
            ))
        }
        return entries
    }

    /// 触达深度上限时的兜底统计，不再构建节点。
    private static func deepSize(path: String, remainingDepth: Int, ledger: HardlinkLedger?) -> UInt64 {
        guard remainingDepth > 0 else { return 0 }
        var total: UInt64 = 0
        for entry in readEntries(path: path, ledger: ledger) {
            if protectedNames.contains(entry.name) { continue }
            total += entry.isDirectory
                ? deepSize(path: entry.path, remainingDepth: remainingDepth - 1, ledger: ledger)
                : entry.size
        }
        return total
    }

    /// 单次遍历得出文件数与大文件列表，避免为百万级节点再复制一份扁平数组。
    private static func collect(
        _ nodes: [DiskTreeNode],
        fileCount: inout Int,
        largeFiles: inout [DiskTreeNode]
    ) {
        for node in nodes {
            if node.isDirectory {
                collect(node.children, fileCount: &fileCount, largeFiles: &largeFiles)
            } else {
                fileCount += 1
                if node.size > 10 * 1024 * 1024 { largeFiles.append(node) }
            }
        }
    }

    static func prepareAccessiblePaths(rootURL: URL, rootPath: String) -> Set<String> {
        var accessible = Set<String>()
        accessible.insert(rootPath)

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return accessible }

        let sensitiveNames: Set<String> = [
            "Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies",
            "Library", "iCloud Drive"
        ]

        for itemURL in contents {
            let name = itemURL.lastPathComponent
            let itemPath = itemURL.path

            guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                accessible.insert(itemPath)
                continue
            }

            if name == "Photos Library.photoslibrary" || name == "Library" {
                continue
            }

            if sensitiveNames.contains(name) {
                let hasItemAccess = itemURL.startAccessingSecurityScopedResource()
                if hasItemAccess {
                    accessible.insert(itemPath)
                    if !fm.isReadableFile(atPath: itemPath) {
                        itemURL.stopAccessingSecurityScopedResource()
                    }
                }
            } else {
                if fm.isReadableFile(atPath: itemPath) {
                    accessible.insert(itemPath)
                }
            }
        }

        return accessible
    }
}

struct BreadcrumbItem: Identifiable {
    let id = UUID()
    let index: Int
    let path: String
}

struct BreadcrumbView: View {
    let items: [BreadcrumbItem]
    let lastIndex: Int
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                breadcrumbContent(item)
            }
        }
    }

    @ViewBuilder
    private func breadcrumbContent(_ item: BreadcrumbItem) -> some View {
        if item.index > 0 {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        Button {
            onTap(item.index)
        } label: {
            Text((item.path as NSString).lastPathComponent)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(item.index == lastIndex ? Color.primary : Color.blue)
    }
}
