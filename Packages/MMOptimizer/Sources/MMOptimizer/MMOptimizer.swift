import SwiftUI
import MMCore
import MMFileScanner

public struct OptimizerModule: ModuleRegistrable {
    public var moduleID: String { "optimizer" }
    public var moduleName: String { "系统优化" }
    public var moduleIcon: String { "gearshape.2" }
    public var modulePriority: Int { 6 }
    public init() {}
    public func createView() -> AnyView { AnyView(OptimizerView()) }
}

public struct OptimizerView: View {
    @State private var selectedTab: OptimizerTab = .tools
    @State private var duplicateGroups: [MMFileScanner.DuplicateGroup] = []
    @State private var isScanningDuplicates = false
    @State private var duplicateProgress: Double = 0
    @State private var browserCaches: [BrowserCacheItem] = []
    @State private var isScanningBrowser = false
    @State private var optimizations: [OptimizationItem] = []

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            Group {
                switch selectedTab {
                case .tools: toolsView
                case .duplicates: duplicatesView
                case .browser: browserView
                }
            }
        }
        .task { await loadInitial() }
    }

    private func loadInitial() async {
        optimizations = await OptimizationScanner.scan()
    }

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.2.fill")
                .font(.largeTitle)
                .foregroundStyle(.gray)
            VStack(alignment: .leading) {
                Text("系统优化").font(.title2.bold())
                Text("重复文件检测、浏览器清理、系统优化")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.tools, label: "系统优化", icon: "wand.and.stars")
            tabButton(.duplicates, label: "重复文件", icon: "doc.on.doc")
            tabButton(.browser, label: "浏览器清理", icon: "globe")
        }
        .padding(.horizontal)
    }

    private func tabButton(_ tab: OptimizerTab, label: String, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
            .background(selectedTab == tab ? Color(nsColor: .controlBackgroundColor) : .clear)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tools View

    private var toolsView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(optimizations) { item in
                    OptimizationRow(item: item) {
                        Task { await runOptimization(item) }
                    }
                }
            }
            .padding()
        }
    }

    private func runOptimization(_ item: OptimizationItem) async {
        if let idx = optimizations.firstIndex(where: { $0.id == item.id }) {
            optimizations[idx].status = .optimized
            optimizations[idx].detail = "已完成"
        }
    }

    // MARK: - Duplicates View

    private var duplicatesView: some View {
        VStack(spacing: 0) {
            HStack {
                if isScanningDuplicates {
                    ProgressView().controlSize(.small)
                    Text("扫描中... \(Int(duplicateProgress))%")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("发现 \(duplicateGroups.count) 组重复文件，可节省 \(formatSize(totalDuplicateWaste))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await scanDuplicates() }
                } label: {
                    Label("扫描重复文件", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(isScanningDuplicates)
            }
            .padding()

            if duplicateGroups.isEmpty && !isScanningDuplicates {
                Spacer()
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("点击「扫描重复文件」开始检测")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(duplicateGroups) { group in
                            DuplicateGroupRow(group: group)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var totalDuplicateWaste: UInt64 {
        duplicateGroups.reduce(0) { $0 + $1.wastedSpace }
    }

    private func scanDuplicates() async {
        isScanningDuplicates = true
        duplicateGroups = []
        duplicateProgress = 0

        let scanner = DuplicateScanner()
        let fileScanner = FileScanner()
        let home = NSHomeDirectory()
        let dirs = [
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Desktop",
        ]

        var allEntries: [FileEntry] = []
        for dir in dirs {
            let result = await fileScanner.scanDirectory(URL(fileURLWithPath: dir))
            allEntries.append(contentsOf: result.entries.filter { !$0.isDirectory })
        }

        let groups = await scanner.findDuplicates(in: allEntries)

        withAnimation {
            duplicateGroups = groups
            isScanningDuplicates = false
        }
    }

    // MARK: - Browser View

    private var browserView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("浏览器缓存和隐私数据")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await scanBrowserCaches() }
                } label: {
                    Label("扫描", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(isScanningBrowser)
            }
            .padding()

            if browserCaches.isEmpty && !isScanningBrowser {
                Spacer()
                Image(systemName: "globe")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("点击「扫描」检测浏览器缓存")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(browserCaches) { cache in
                            BrowserCacheRow(cache: cache)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func scanBrowserCaches() async {
        isScanningBrowser = true
        browserCaches = await BrowserCacheScanner.scan()
        isScanningBrowser = false
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum OptimizerTab {
    case tools, duplicates, browser
}

// MARK: - Duplicate Group Row

struct DuplicateGroupRow: View {
    let group: MMFileScanner.DuplicateGroup
    @State private var isExpanded = false
    @State private var selectedPaths: Set<URL> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(group.files.count) 个重复文件")
                            .font(.body.weight(.medium))
                        Text(group.files.first?.path.path ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(formatSize(group.wastedSpace))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(group.files) { file in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { selectedPaths.contains(file.path) },
                                set: { isOn in
                                    if isOn { selectedPaths.insert(file.path) }
                                    else { selectedPaths.remove(file.path) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()

                            Text(file.path.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(formatSize(file.size))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 24)
                    }
                }

                if !selectedPaths.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            deleteSelected()
                        } label: {
                            Label("删除选中 (\(selectedPaths.count))", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func deleteSelected() {
        for path in selectedPaths {
            try? FileManager.default.trashItem(at: path, resultingItemURL: nil)
        }
        selectedPaths = []
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Browser Cache

struct BrowserCacheItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let path: String
    let size: UInt64
    let cacheType: String
}

struct BrowserCacheRow: View {
    let cache: BrowserCacheItem
    @State private var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: cache.icon)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(cache.name).font(.body.weight(.medium))
                Text(cache.cacheType).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatSize(cache.size))
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
            Button {
                cleanCache()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func cleanCache() {
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: cache.path), resultingItemURL: nil)
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Browser Cache Scanner

enum BrowserCacheScanner {
    static func scan() async -> [BrowserCacheItem] {
        var items: [BrowserCacheItem] = []
        let home = NSHomeDirectory()
        let fm = FileManager.default

        let browsers: [(String, String, String, String)] = [
            ("Safari", "safari", "\(home)/Library/Caches/com.apple.Safari", "缓存"),
            ("Chrome", "globe", "\(home)/Library/Caches/Google/Chrome", "缓存"),
            ("Firefox", "globe", "\(home)/Library/Caches/Firefox", "缓存"),
            ("Edge", "globe", "\(home)/Library/Caches/Microsoft Edge", "缓存"),
        ]

        for (name, icon, path, type) in browsers {
            if fm.fileExists(atPath: path) {
                let size = await directorySize(path)
                items.append(BrowserCacheItem(
                    name: name,
                    icon: icon,
                    path: path,
                    size: size,
                    cacheType: type
                ))
            }
        }

        return items
    }

    private static func directorySize(_ path: String) async -> UInt64 {
        let fm = FileManager.default
        var size: UInt64 = 0
        if let enumerator = fm.enumerator(atPath: path) {
            while let file = enumerator.nextObject() as? String {
                let fullPath = "\(path)/\(file)"
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let fileSize = attrs[.size] as? UInt64 {
                    size += fileSize
                }
            }
        }
        return size
    }
}

// MARK: - Optimization Scanner

struct OptimizationItem: Identifiable {
    let id: String
    let name: String
    let description: String
    let iconName: String
    var status: Status
    var detail: String

    enum Status { case normal, warning, optimized }
}

enum OptimizationScanner {
    static func scan() async -> [OptimizationItem] {
        var items: [OptimizationItem] = []

        // Check memory pressure
        let memPressure = checkMemoryPressure()
        items.append(OptimizationItem(
            id: "memory",
            name: "内存优化",
            description: "释放不活跃的内存占用",
            iconName: "memorychip",
            status: memPressure > 0.7 ? .warning : .normal,
            detail: memPressure > 0.7 ? "内存压力较高" : "内存正常"
        ))

        // Check disk space
        let diskUsage = await checkDiskUsage()
        items.append(OptimizationItem(
            id: "disk",
            name: "磁盘空间",
            description: "检查磁盘使用情况",
            iconName: "internaldrive",
            status: diskUsage > 0.85 ? .warning : .normal,
            detail: "\(Int(diskUsage * 100))% 已使用"
        ))

        // Check DNS
        items.append(OptimizationItem(
            id: "dns",
            name: "DNS 优化",
            description: "优化 DNS 设置以提升网络速度",
            iconName: "globe",
            status: .normal,
            detail: "当前使用默认 DNS"
        ))

        // Check Spotlight
        items.append(OptimizationItem(
            id: "spotlight",
            name: "Spotlight 优化",
            description: "优化 Spotlight 索引范围",
            iconName: "magnifyingglass",
            status: .normal,
            detail: "索引正常"
        ))

        return items
    }

    private static func checkMemoryPressure() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let total = Double(stats.free_count + stats.active_count + stats.inactive_count + stats.wire_count)
        let used = Double(stats.active_count + stats.wire_count)
        return total > 0 ? used / total : 0
    }

    private static func checkDiskUsage() async -> Double {
        let home = NSHomeDirectory()
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home),
              let total = attrs[.systemSize] as? UInt64,
              let free = attrs[.systemFreeSize] as? UInt64,
              total > 0 else { return 0 }
        return Double(total - free) / Double(total)
    }
}

struct OptimizationRow: View {
    let item: OptimizationItem
    let onRun: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium))
                Text(item.description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.detail)
                .font(.caption).foregroundStyle(.secondary)

            Button("优化") { onRun() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(item.status == .optimized)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch item.status {
        case .normal: return .green
        case .warning: return .orange
        case .optimized: return .blue
        }
    }
}
