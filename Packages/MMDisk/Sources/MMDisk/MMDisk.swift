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
    @State private var selectedPath: String?
    @State private var scanResult: DiskScanResult?
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanningPath: String = ""
    @State private var scanningFileCount: Int = 0
    @State private var scanStartTime: Date = Date()
    @State private var navigationStack: [String] = []
    // currentItems 只存有界渲染窗口；全量数据在 scanStore 里，一条不丢
    @State private var currentItems: [DiskTreeNode] = []
    @State private var scanStore: DiskScanStore?
    @State private var largeFiles: [DiskTreeNode] = []
    @State private var showLargeFiles = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isScanning && scanResult == nil {
                scanningView
            } else if let result = scanResult {
                diskInfoBar(result: result)
                Divider()
                breadcrumbBar
                Divider()
                if showLargeFiles {
                    largeFilesList
                } else {
                    treemapView
                }
                Divider()
                bottomBar
            } else {
                placeholder
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "internaldrive.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text("磁盘分析")
                    .font(.title2.bold())
                Text("可视化分析磁盘空间占用，快速定位大文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.pie")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("选择目录开始分析")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("选择目录") {
                Task { await scanDirectory() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "internaldrive.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating)

            Text("正在分析磁盘...")
                .font(.title3.bold())

            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: 200)

            // 按"已完成目录/已进入目录"估算，明确标注估算；权威数值以扫描结束后的结果为准
            VStack(spacing: 4) {
                ProgressView(value: scanProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                Text("进度估算：\(Int(scanProgress * 100))%（按目录完成比例）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 8) {
                if !scanningPath.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(scanningPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 400)
                }

                HStack(spacing: 16) {
                    Label("\(scanningFileCount) 个文件", systemImage: "doc")
                    Label(elapsedTimeText, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("正在扫描目录结构，请稍候...")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var elapsedTimeText: String {
        let elapsed = Int(Date().timeIntervalSince(scanStartTime))
        if elapsed < 60 { return "\(elapsed) 秒" }
        return "\(elapsed / 60) 分 \(elapsed % 60) 秒"
    }

    private func diskInfoBar(result: DiskScanResult) -> some View {
        HStack(spacing: 24) {
            infoItem(title: "总容量", value: formatSize(result.totalSize))
            infoItem(title: "已使用", value: formatSize(result.usedSize))
            infoItem(title: "可用", value: formatSize(result.freeSize))
            infoItem(title: "文件数", value: "\(result.fileCount)")
            Spacer()
            StorageBar(used: Double(result.usedSize), total: Double(result.totalSize))
                .frame(width: 200)
        }
        .padding()
    }

    private func infoItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium))
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button {
                showLargeFiles = false
            } label: {
                Label("Treemap", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.bordered)
            .tint(showLargeFiles ? .secondary : .blue)

            Button {
                showLargeFiles = true
            } label: {
                Label("大文件", systemImage: "doc.badge.arrow.up")
            }
            .buttonStyle(.bordered)
            .tint(showLargeFiles ? .blue : .secondary)

            Spacer()

            breadcrumbTrail
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var breadcrumbTrail: some View {
        BreadcrumbView(
            items: navigationStack.enumerated().map { BreadcrumbItem(index: $0.offset, path: $0.element) },
            lastIndex: navigationStack.count - 1,
            onTap: { index in navigateTo(index: index) }
        )
    }

    private var treemapView: some View {
        TreemapView(items: currentItems.map { nodeToTreemapItem($0) }) { item in
            if let node = findNode(id: item.id) {
                drillInto(node: node)
            }
        }
        .padding(8)
    }

    private var largeFilesList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                // largeFiles 存入时已按大小排序，body 里不再重排
            ForEach(largeFiles) { file in
                    HStack {
                        Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(file.isDirectory ? .blue : .secondary)
                            .frame(width: 20)
                        Text(file.name)
                            .font(.body)
                            .lineLimit(1)
                        Spacer()
                        Text(formatSize(file.size))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(.rect(cornerRadius: 6))
                }
            }
            .padding()
        }
    }

    private var bottomBar: some View {
        HStack {
            if isScanning {
                ProgressView(value: scanProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                Text("扫描中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await scanDirectory() }
            } label: {
                Label(isScanning ? "分析中..." : "选择目录", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)
        }
        .padding()
    }

    private func nodeToTreemapItem(_ node: DiskTreeNode) -> TreemapItem {
        let color = colorForSize(node.size)
        return TreemapItem(
            id: node.id,
            name: node.name,
            value: Double(node.size),
            color: color,
            isDirectory: node.isDirectory
        )
    }

    private func colorForSize(_ size: UInt64) -> Color {
        let gb = Double(size) / 1_073_741_824
        if gb > 10 { return .red }
        if gb > 5 { return .orange }
        if gb > 1 { return .yellow }
        if gb > 0.1 { return .blue }
        return .gray
    }

    private func findNode(id: String) -> DiskTreeNode? {
        scanStore?.node(withID: id)
    }

    private func drillInto(node: DiskTreeNode) {
        guard node.isDirectory, let scanStore else { return }
        navigationStack.append(node.path)
        currentItems = scanStore.drill(into: node)
    }

    private func navigateTo(index: Int) {
        guard index < navigationStack.count else { return }
        navigationStack = Array(navigationStack.prefix(index + 1))
        guard let path = navigationStack.last else { return }
        Task { await doNavigate(path: path) }
    }

    private func doNavigate(path: String) async {
        isScanning = true
        scanningPath = path
        scanningFileCount = 0
        scanStartTime = Date()
        let items = await Task.detached {
            await DiskScanner.childrenOfDirectory(path: path)
                .sorted { $0.size > $1.size }
        }.value
        if let scanStore {
            scanStore.currentChildren = items
            currentItems = scanStore.displayWindow(of: items)
        } else {
            currentItems = items
        }
        isScanning = false
    }

    private func scanDirectory() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let hasAccess = url.startAccessingSecurityScopedResource()
        let rootPath = url.path

        isScanning = true
        scanProgress = 0
        scanResult = nil
        scanningPath = "正在检查访问权限..."
        scanningFileCount = 0
        scanStartTime = Date()

        let accessiblePaths = await Task.detached {
            DiskScanner.prepareAccessiblePaths(rootURL: url, rootPath: rootPath)
        }.value

        scanningPath = "正在分析目录结构..."

        let tracker = ScanProgressTracker()

        // 轮询放在 detached 任务上，不占用 MainActor 时间片；500ms 采样、内容未变则跳过赋值。
        // 丢掉的中间帧只影响进度展示；权威统计始终由 performScan 的返回值给出。
        let progressTask = Task.detached(priority: .utility) {
            var lastPath = ""
            var lastCount = -1
            var lastBucket = -1
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    break
                }
                let snap = tracker.snapshot()
                let bucket = Int(snap.estimatedProgress * 50)
                if snap.path != lastPath || snap.fileCount != lastCount || bucket != lastBucket {
                    lastPath = snap.path
                    lastCount = snap.fileCount
                    lastBucket = bucket
                    await MainActor.run {
                        if !snap.path.isEmpty {
                            self.scanningPath = snap.path
                        }
                        self.scanningFileCount = snap.fileCount
                        self.scanProgress = snap.estimatedProgress
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
            if let vals = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]),
               let cap = vals.volumeTotalCapacity {
                return UInt64(cap)
            }
            return 0
        }()
        let freeSize: UInt64 = {
            if let vals = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
               let cap = vals.volumeAvailableCapacity {
                return UInt64(cap)
            }
            return 0
        }()
        let usedSize = totalSize - freeSize

        if hasAccess { url.stopAccessingSecurityScopedResource() }

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
                fileCount: output.fileCount
            )
            self.navigationStack = [rootPath]
            self.currentItems = store.displayWindow(of: store.rootItems)
            self.largeFiles = Array(output.largeFilesList.prefix(100))
            self.scanProgress = 1
            self.isScanning = false
        }
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct DiskTreeNode: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: UInt64
    let isDirectory: Bool
    var children: [DiskTreeNode]
}

/// 完整扫描结果驻留在引用类型里：@State 只持有有界渲染窗口，
/// 这样数据一条不丢，而 SwiftUI 每次 body 重算的 diff/map 成本从全量节点降到窗口大小。
/// 仅在主线程访问，不做跨线程共享。
final class DiskScanStore {
    static let renderWindow = 200
    let rootItems: [DiskTreeNode]
    var currentChildren: [DiskTreeNode]

    init(rootItems: [DiskTreeNode]) {
        self.rootItems = rootItems
        self.currentChildren = rootItems
    }

    func node(withID id: String) -> DiskTreeNode? {
        currentChildren.first { $0.id == id }
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

    func drill(into node: DiskTreeNode) -> [DiskTreeNode] {
        let children = node.children.sorted { $0.size > $1.size }
        currentChildren = children
        return displayWindow(of: children)
    }
}

struct ProgressSnapshot {
    let path: String
    let fileCount: Int
    let estimatedProgress: Double
}

final class ScanProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _currentPath: String = ""
    private var _fileCount: Int = 0
    private var dirsEntered = 0
    private var dirsCompleted = 0
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

    func dirEntered() { lock.withLock { dirsEntered += 1 } }
    func dirCompleted() { lock.withLock { dirsCompleted += 1 } }

    /// UI 侧单次加锁取全量快照，避免多次锁竞争。进度是按
    /// 已完成目录/已进入目录得出的估算值，允许采样丢帧；
    /// 真实统计口径以 DiskScanner.performScan 的返回值为准。
    func snapshot() -> ProgressSnapshot {
        lock.withLock {
            let raw = dirsEntered > 0 ? Double(dirsCompleted) / Double(dirsEntered) : 0
            return ProgressSnapshot(
                path: _currentPath,
                fileCount: _fileCount,
                estimatedProgress: min(raw, 0.98)
            )
        }
    }
}

struct DiskScanResult {
    let path: String
    let totalSize: UInt64
    let usedSize: UInt64
    let freeSize: UInt64
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
        let children = await scanChildren(
            path: rootPath, depth: 0,
            accessiblePaths: accessiblePaths, tracker: tracker
        )
        let topItems = children.sorted { $0.size > $1.size }

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
        tracker: ScanProgressTracker? = nil
    ) async -> [DiskTreeNode] {
        await scanChildren(path: path, depth: 0, accessiblePaths: nil, tracker: tracker)
    }

    /// 目录大小直接由子节点求和得出，避免对同一目录重复枚举。
    private static func scanNode(
        entry: FileEntry, depth: Int, tracker: ScanProgressTracker?
    ) async -> DiskTreeNode {
        let children = await scanChildren(path: entry.path, depth: depth, accessiblePaths: nil, tracker: tracker)
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
        tracker: ScanProgressTracker?
    ) async -> [DiskTreeNode] {
        // 进入/完成计数只服务于进度估算，不参与任何大小或数量统计
        tracker?.dirEntered()
        defer { tracker?.dirCompleted() }

        let entries = readEntries(path: path)
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
                    size: deepSize(path: dir.path, remainingDepth: 3),
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
                    group.addTask { await scanNode(entry: dir, depth: depth + 1, tracker: tracker) }
                }
                while let node = await group.next() {
                    result.append(node)
                    if next < directories.count {
                        let dir = directories[next]
                        next += 1
                        group.addTask { await scanNode(entry: dir, depth: depth + 1, tracker: tracker) }
                    }
                }
            }
        } else {
            for dir in directories {
                result.append(await scanNode(entry: dir, depth: depth + 1, tracker: tracker))
            }
        }

        return result
    }

    /// 单次 lstat 同时取得类型和大小；不跟随符号链接，避免环状递归。
    private static func readEntries(path: String) -> [FileEntry] {
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
            // 目录大小由子节点求和得出；符号链接等按 lstat 报告的大小计，且不进入递归
            let size: UInt64 = isDirectory ? 0 : UInt64(info.st_size)

            entries.append(FileEntry(
                name: name, path: fullPath, isDirectory: isDirectory, size: size
            ))
        }
        return entries
    }

    /// 触达深度上限时的兜底统计，不再构建节点。
    private static func deepSize(path: String, remainingDepth: Int) -> UInt64 {
        guard remainingDepth > 0 else { return 0 }
        var total: UInt64 = 0
        for entry in readEntries(path: path) {
            if protectedNames.contains(entry.name) { continue }
            total += entry.isDirectory
                ? deepSize(path: entry.path, remainingDepth: remainingDepth - 1)
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
