import SwiftUI
import MMCore
import MMFileScanner

public struct CleanerModule: ModuleRegistrable {
    public var moduleID: String { "cleaner" }
    public var moduleName: String { "系统清理" }
    public var moduleIcon: String { "trash" }
    public var modulePriority: Int { 1 }

    public init() {}

    public func createView() -> AnyView {
        AnyView(CleanerContainerView())
    }
}

public struct CleanerView: View {
    @State private var categories: [CacheCategory] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var scanProgress: Double = 0
    @State private var lastResult: TrashResult?
    @State private var showUndoToast = false
    @State private var excludedPaths: Set<String> = []
    @State private var expandedSubItemID: String?
    @State private var subItemChildren: [String: [CacheFileEntry]] = [:]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isScanning {
                scanProgressView
            } else if categories.isEmpty {
                emptyView
            } else {
                categoryList
            }
            Divider()
            actionBar
        }
        .task { await initialScan() }
        .overlay(alignment: .bottom) {
            if showUndoToast && lastResult != nil {
                undoToast
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring, value: showUndoToast)
    }

    private var header: some View {
        HStack {
            Image(systemName: "trash.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("系统清理")
                    .font(.title2.bold())
                Text("扫描系统缓存、日志、临时文件等可安全清理的垃圾文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !categories.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("可清理: \(formatSize(effectiveCleanSize))")
                        .font(.title3.bold())
                        .foregroundStyle(effectiveCleanSize > 0 ? .red : .secondary)
                    if !excludedPaths.isEmpty {
                        Text("已排除 \(excludedPaths.count) 项")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding()
    }

    private var scanProgressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("正在扫描系统文件...")
                .font(.headline)
            ProgressView(value: scanProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("点击「扫描」开始分析系统垃圾文件")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categoryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach($categories) { $category in
                    CategorySection(
                        category: $category,
                        isSelected: selectedIDs.contains(category.id),
                        excludedPaths: $excludedPaths,
                        expandedSubItemID: $expandedSubItemID,
                        subItemChildren: $subItemChildren,
                        onToggleCategory: {
                            if selectedIDs.contains(category.id) {
                                selectedIDs.remove(category.id)
                            } else {
                                selectedIDs.insert(category.id)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }

    private var actionBar: some View {
        HStack {
            Button {
                Task { await initialScan() }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(isScanning || isCleaning)

            Spacer()

            Button {
                Task { await startClean() }
            } label: {
                Label(isCleaning ? "清理中..." : "立即清理", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(effectiveCleanSize == 0 || isScanning || isCleaning)
        }
        .padding()
    }

    @ViewBuilder
    private var undoToast: some View {
        if let result = lastResult {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("已清理 \(formatSize(result.totalSize))，共 \(result.successCount) 个文件")
                    .font(.body.weight(.medium))
                Spacer()
                Button("撤回") {
                    Task { await undoClean() }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(radius: 8)
            .padding(.horizontal)
        }
    }

    private var effectiveCleanSize: UInt64 {
        var total: UInt64 = 0
        for cat in categories where selectedIDs.contains(cat.id) {
            for sub in cat.subItems where !excludedPaths.contains(sub.path) {
                total += sub.size
            }
        }
        return total
    }

    private var totalScannableSize: UInt64 {
        categories.reduce(0) { $0 + $1.scannedSize }
    }

    private var totalSelectedSize: UInt64 {
        categories
            .filter { selectedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.scannedSize }
    }

    private func initialScan() async {
        isScanning = true
        scanProgress = 0
        categories = []
        selectedIDs = []
        excludedPaths = []
        expandedSubItemID = nil
        subItemChildren = [:]

        let scanner = CacheScanner()
        var scanned: [CacheCategory] = []
        scanned = await scanner.scanAll()

        withAnimation {
            categories = scanned
            selectedIDs = Set(scanned.filter { $0.scannedSize > 0 }.map(\.id))
            isScanning = false
            scanProgress = 1.0
        }
    }

    private func startClean() async {
        isCleaning = true
        let selectedCategories = categories.filter { selectedIDs.contains($0.id) }
        var allPaths: [String] = []
        for cat in selectedCategories {
            for subItem in cat.subItems where !excludedPaths.contains(subItem.path) {
                allPaths.append(subItem.path)
            }
        }

        let trashService = FileTrashService.shared
        let result = await trashService.moveToTrash(paths: allPaths)

        lastResult = result
        showUndoToast = true

        let cleanedPaths = Set(allPaths)
        for i in categories.indices {
            categories[i].subItems.removeAll { cleanedPaths.contains($0.path) }
            categories[i].scannedSize = categories[i].subItems.reduce(0) { $0 + $1.size }
            categories[i].scannedFiles = categories[i].subItems.reduce(0) { $0 + $1.fileCount }
            if categories[i].subItems.isEmpty {
                selectedIDs.remove(categories[i].id)
            }
        }
        excludedPaths = excludedPaths.filter { !cleanedPaths.contains($0) }
        isCleaning = false

        try? await Task.sleep(for: .seconds(15))
        showUndoToast = false
    }

    private func undoClean() async {
        let trashService = FileTrashService.shared
        _ = await trashService.undoLastOperation()
        showUndoToast = false
        await initialScan()
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct CategorySection: View {
    @Binding var category: CacheCategory
    let isSelected: Bool
    @Binding var excludedPaths: Set<String>
    @Binding var expandedSubItemID: String?
    @Binding var subItemChildren: [String: [CacheFileEntry]]
    let onToggleCategory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                Image(systemName: category.iconName)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.body.weight(.medium))
                    Text(category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatSize(effectiveSize))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(effectiveSize > 0 ? .red : .secondary)
                    Text("\(category.scannedFiles) 个文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleCategory() }

            if !category.subItems.isEmpty {
                Divider().padding(.leading, 52)
                VStack(spacing: 2) {
                    ForEach(category.subItems) { subItem in
                        SubItemRow(
                            subItem: subItem,
                            isExcluded: excludedPaths.contains(subItem.path),
                            isExpanded: expandedSubItemID == subItem.id,
                            children: subItemChildren[subItem.id] ?? [],
                            onToggleExpand: {
                                toggleExpand(subItem: subItem)
                            },
                            onToggleExclude: {
                                toggleExclude(subItem: subItem)
                            },
                            onToggleChildExclude: { path in
                                if excludedPaths.contains(path) {
                                    excludedPaths.remove(path)
                                } else {
                                    excludedPaths.insert(path)
                                }
                            },
                            onOpenInFinder: { path in
                                revealInFinder(path)
                            }
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.blue.opacity(0.05) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue.opacity(0.3) : .clear, lineWidth: 1)
        )
    }

    private var effectiveSize: UInt64 {
        category.subItems
            .filter { !excludedPaths.contains($0.path) }
            .reduce(0) { $0 + $1.size }
    }

    private func toggleExpand(subItem: CacheSubItem) {
        if expandedSubItemID == subItem.id {
            expandedSubItemID = nil
        } else {
            expandedSubItemID = subItem.id
            if subItemChildren[subItem.id] == nil {
                let scanner = CacheScanner()
                let path = subItem.path
                Task {
                    let children = await scanner.listChildren(path: path)
                    await MainActor.run {
                        subItemChildren[subItem.id] = children
                    }
                }
            }
        }
    }

    private func toggleExclude(subItem: CacheSubItem) {
        if excludedPaths.contains(subItem.path) {
            excludedPaths.remove(subItem.path)
        } else {
            excludedPaths.insert(subItem.path)
        }
    }

    private func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct SubItemRow: View {
    let subItem: CacheSubItem
    let isExcluded: Bool
    let isExpanded: Bool
    let children: [CacheFileEntry]
    let onToggleExpand: () -> Void
    let onToggleExclude: () -> Void
    let onToggleChildExclude: (String) -> Void
    let onOpenInFinder: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundStyle(.blue.opacity(0.7))
                    .frame(width: 16)

                Text(subItem.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isExcluded ? .secondary : .primary)
                    .strikethrough(isExcluded)
                    .lineLimit(1)

                Spacer()

                Text(formatSize(subItem.size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isExcluded ? Color.secondary : Color.orange)

                Button(action: { onOpenInFinder(subItem.path) }) {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("在访达中打开")

                Button(action: onToggleExclude) {
                    Image(systemName: isExcluded ? "arrow.uturn.backward.circle.fill" : "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(isExcluded ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(isExcluded ? "恢复清理" : "保留此项（不清理）")
            }
            .padding(.vertical, 4)
            .padding(.leading, 40)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(children) { child in
                        ChildEntryRow(
                            child: child,
                            isExcluded: false,
                            onToggleExclude: { onToggleChildExclude(child.path) },
                            onOpenInFinder: { onOpenInFinder(child.path) }
                        )
                    }
                    if children.isEmpty {
                        Text("无内容")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 60)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct ChildEntryRow: View {
    let child: CacheFileEntry
    let isExcluded: Bool
    let onToggleExclude: () -> Void
    let onOpenInFinder: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                .font(.caption2)
                .foregroundStyle(child.isDirectory ? .blue.opacity(0.5) : .secondary)
                .frame(width: 14)

            Text(child.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(formatSize(child.size))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            Button(action: onOpenInFinder) {
                Image(systemName: "folder")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("在访达中打开")

            Button(action: onToggleExclude) {
                Image(systemName: isExcluded ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption2)
                    .foregroundStyle(isExcluded ? .green : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("排除此项")
        }
        .padding(.vertical, 3)
        .padding(.leading, 60)
        .padding(.trailing, 8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
