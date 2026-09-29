import SwiftUI
import MMCore
import MMFileScanner
import MMUI

/// Task 1 UI：用户文件夹「先查看、再手动勾选」。
/// 与缓存页的默认全选相反，这里所有条目初始状态都是未选中，
/// 只有用户逐项点选的文件夹/子项才会被移入废纸篓（FileTrashService，可撤回）。
struct UserFolderCleanView: View {
    @State private var folders: [UserFolderInfo] = []
    @State private var hasScanned = false
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var selectedPaths: Set<String> = []
    @State private var expandedFolderPath: String?
    @State private var folderChildren: [String: [UserFolderChild]] = [:]
    @State private var childrenLoadingPath: String?
    @State private var scanningPath = ""
    @State private var scannedFileCount = 0
    @State private var lastResult: TrashResult?
    @State private var lastFailures: [TrashFailure] = []
    @State private var toastSeconds = 0
    @State private var showConfirmAlert = false
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            MMPageHeader("用户文件夹", subtitle: headerSubtitle) {
                Button {
                    startScan()
                } label: {
                    Label(isScanning ? "扫描中…" : "重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning || isCleaning)
            }

            content

            if !lastFailures.isEmpty {
                MMFailurePanel(
                    summary: lastResult.map { "已回收 \(MMFormat.bytes($0.totalSize))" },
                    lastFailures
                ) {
                    lastFailures = []
                }
            }

            Divider()
            actionBar
        }
        .alert("确认清理选中的项目？", isPresented: $showConfirmAlert) {
            Button("取消", role: .cancel) {}
            Button("移入废纸篓", role: .destructive) {
                Task { await cleanSelected() }
            }
        } message: {
            Text("共 \(cleanTargets.count) 项，约 \(MMFormat.bytes(selectedSize))。\n选中的内容将移入废纸篓（可撤回），不会永久删除。")
        }
        .overlay(alignment: .bottom) {
            if let result = lastResult, toastSeconds > 0 {
                MMUndoToast(
                    message: "已将 \(result.successCount) 项移入废纸篓",
                    detail: MMFormat.bytes(result.totalSize),
                    secondsRemaining: toastSeconds,
                    onUndo: { Task { await undoClean() } },
                    onRevealTrash: { MMReveal.openDirectory(NSHomeDirectory() + "/.Trash") }
                )
                .padding(.bottom, MMMetric.actionBar + MMGap.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toastSeconds)
        .task(id: toastSeconds) {
            guard toastSeconds > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            toastSeconds -= 1
        }
        // 仅供截图验证：合成点击会逃到别的应用，扫描结果态没有别的办法进入。
        .task {
            guard ProcessInfo.processInfo.environment["MM_AUTO_SCAN"] != nil else { return }
            if !hasScanned, !isScanning { startScan() }
        }
        .onChange(of: hasScanned) { _, scanned in
            guard scanned, ProcessInfo.processInfo.environment["MM_SHOW_CONFIRM"] != nil else { return }
            // 勾最小的那个文件夹：这条路径只为把确认弹窗截出来，
            // 万一被误触发，损失也要是"几乎为零"而不是整个文稿目录。
            if let smallest = folders.filter(\.isAccessible).min(by: { $0.size < $1.size }) {
                selectedPaths = [smallest.path]
                showConfirmAlert = true
            }
        }
    }

    private var headerSubtitle: String {
        if isScanning { return "扫描中…" }
        guard hasScanned else { return "尚未扫描" }
        let total = folders.reduce(UInt64(0)) { $0 + $1.size }
        let inaccessible = folders.filter { !$0.isAccessible }.count
        var text = "\(folders.count) 个文件夹 · \(MMFormat.bytes(total))"
        if inaccessible > 0 { text += " · \(inaccessible) 个无访问权限" }
        return text
    }

    @ViewBuilder
    private var content: some View {
        if isScanning && folders.isEmpty {
            VStack(spacing: 0) {
                MMScanProgress(
                    action: "正在扫描用户文件夹",
                    currentPath: scanningPath.isEmpty ? nil : scanningPath,
                    processedCount: scannedFileCount,
                    estimatedRemaining: nil,
                    progress: nil
                )
                Divider()
                ForEach(0..<6, id: \.self) { _ in
                    MMSkeletonRow(nameWidth: 120, valueWidth: 72)
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("取消扫描") { scanTask?.cancel() }
                        .padding(.bottom, MMGap.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MMColor.contentBackground)
        } else if !hasScanned {
            MMEmptyState(
                systemImage: "folder.badge.person.crop",
                title: "扫描桌面 / 文稿 / 下载 / 图片 / 影片 / 音乐",
                detail: "受 macOS 隐私保护，首次访问可能需要在系统弹窗中允许。默认全部未选中，只有逐项勾选的内容才会被清理。",
                action: AnyView(
                    Button {
                        startScan()
                    } label: {
                        Label("扫描用户文件夹", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                )
            )
        } else {
            folderTable
        }
    }

    private var folderTable: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(folders) { folder in
                        UserFolderSection(
                            folder: folder,
                            isSelected: selectionBinding(for: folder.path),
                            isExpanded: expandedFolderPath == folder.path,
                            children: folderChildren[folder.path] ?? [],
                            isLoadingChildren: childrenLoadingPath == folder.path,
                            childSelection: selectionBinding(for:),
                            onToggleExpand: { toggleExpand(folder: folder) }
                        )
                        Divider().padding(.leading, MMGap.md)
                    }
                    HStack(alignment: .top, spacing: MMGap.xs) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                        Text("清理一律移入废纸篓，可在「最近操作」中撤回；未勾选的内容不会被读取之外的任何修改。")
                            .font(.caption)
                            .foregroundStyle(MMColor.secondaryLabel)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, MMGap.md)
                    .padding(.vertical, MMGap.sm)
                }
                // 必须显式给宽：LazyVStack 在 ScrollView 里会按最宽子项的理想宽度
                // 排版，整张表就会横向溢出、右侧数值被裁掉。
                .frame(width: proxy.size.width - MMGap.lg * 2)
                .background(MMColor.contentBackground)
                .overlay(RoundedRectangle(cornerRadius: MMRadius.card).stroke(MMColor.separator))
                .padding(.horizontal, MMGap.lg)
                .padding(.vertical, MMGap.lg)
            }
        }
    }

    private var actionBar: some View {
        MMActionBar(
            summary: "已选 \(cleanTargets.count) 项 · \(MMFormat.bytes(selectedSize))",
            note: isScanning ? "扫描未完成，数字只包含已扫到的部分" : "未勾选的内容绝不会被清理"
        ) {
            Button("清理选中 \(cleanTargets.count) 项") {
                showConfirmAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(MMColor.destructive)
            .disabled(cleanTargets.isEmpty || isScanning || isCleaning)
        }
    }

    private func selectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(path) },
            set: { on in
                if on { selectedPaths.insert(path) } else { selectedPaths.remove(path) }
            }
        )
    }

    // MARK: - 选中项计算

    /// 去掉祖先已被选中的后代路径：文件夹整体入回收站后，其子项无需再单独移动。
    private var cleanTargets: [String] {
        let sorted = selectedPaths.sorted { $0.count < $1.count }
        var kept: [String] = []
        for path in sorted {
            let hasSelectedAncestor = kept.contains { path.hasPrefix($0 + "/") }
            if !hasSelectedAncestor {
                kept.append(path)
            }
        }
        return kept
    }

    private var sizeLookup: [String: UInt64] {
        var map: [String: UInt64] = [:]
        for folder in folders {
            map[folder.path] = folder.size
        }
        for children in folderChildren.values {
            for child in children {
                map[child.path] = child.size
            }
        }
        return map
    }

    private var selectedSize: UInt64 {
        cleanTargets.reduce(UInt64(0)) { partial, path in
            partial + (sizeLookup[path] ?? 0)
        }
    }

    // MARK: - 动作

    private func toggleExpand(folder: UserFolderInfo) {
        if expandedFolderPath == folder.path {
            expandedFolderPath = nil
            return
        }
        expandedFolderPath = folder.path
        guard folderChildren[folder.path] == nil, folder.isAccessible else { return }
        childrenLoadingPath = folder.path
        let path = folder.path
        let scanner = UserFolderScanner()
        Task {
            let children = await scanner.listChildren(of: path)
            await MainActor.run {
                folderChildren[path] = children
                childrenLoadingPath = nil
            }
        }
    }

    private func startScan() {
        isScanning = true
        scanningPath = ""
        scannedFileCount = 0

        let tracker = FileScanProgressTracker()
        let scanner = UserFolderScanner()

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                scanningPath = tracker.currentPath
                scannedFileCount = tracker.fileCount
            }
        }

        scanTask = Task {
            let result = await scanner.scan(tracker: tracker)
            progressTask.cancel()
            guard !Task.isCancelled else {
                await MainActor.run {
                    isScanning = false
                }
                return
            }
            await MainActor.run {
                withAnimation {
                    folders = result
                    hasScanned = true
                    isScanning = false
                    selectedPaths = []
                    expandedFolderPath = nil
                    folderChildren = [:]
                }
            }
        }
    }

    private func cleanSelected() async {
        let paths = cleanTargets
        guard !paths.isEmpty else { return }
        isCleaning = true

        let result = await FileTrashService.shared.moveToTrash(paths: paths)
        lastResult = result
        lastFailures = result.operation.failures
        // 一项都没搬动就别弹"已移入废纸篓"，失败清单已经在面板里说清楚了。
        if result.successCount > 0 { toastSeconds = 15 }

        await applyCleaned(paths)
        selectedPaths = []
        isCleaning = false
    }

    /// 就地更新状态：整删的顶层文件夹重新统计（此时目录为空，很快），
    /// 被清理的子项从缓存中移除并从父目录扣减大小/文件数。
    private func applyCleaned(_ paths: [String]) async {
        let scanner = UserFolderScanner()
        var parentDeltas: [String: (size: UInt64, count: Int)] = [:]

        for path in paths {
            if let index = folders.firstIndex(where: { $0.path == path }) {
                let fresh = await scanner.scanFolder(atPath: path)
                if let fresh {
                    folders[index] = fresh
                } else {
                    folders.remove(at: index)
                }
                folderChildren.removeValue(forKey: path)
            } else {
                let parent = (path as NSString).deletingLastPathComponent
                let childSize = sizeLookup[path] ?? 0
                let childCount = folderChildren[parent]?.first { $0.path == path }?.fileCount ?? 1
                parentDeltas[parent, default: (0, 0)].size += childSize
                parentDeltas[parent, default: (0, 0)].count += childCount
                folderChildren[parent] = folderChildren[parent]?.filter { $0.path != path }
            }
        }

        for (parent, delta) in parentDeltas {
            guard let index = folders.firstIndex(where: { $0.path == parent }) else { continue }
            folders[index].size = folders[index].size > delta.size ? folders[index].size - delta.size : 0
            folders[index].fileCount = max(0, folders[index].fileCount - delta.count)
        }
    }

    private func undoClean() async {
        _ = await FileTrashService.shared.undoLastOperation()
        toastSeconds = 0
        startScan()
    }

}

/// 单个用户文件夹行：勾选 + 展开查看子项并逐项勾选。
/// 默认不勾选，与缓存页的"安全档预选"相反——个人目录里没有可自动重建的东西。
struct UserFolderSection: View {
    let folder: UserFolderInfo
    @Binding var isSelected: Bool
    let isExpanded: Bool
    let children: [UserFolderChild]
    let isLoadingChildren: Bool
    let childSelection: (String) -> Binding<Bool>
    let onToggleExpand: () -> Void

    var body: some View {
        MMItemRow(
            title: folder.name,
            subtitle: folder.isAccessible
                ? "\(folder.fileCount) 个文件 · 修改于 \(formatDate(folder.modificationDate))"
                : "macOS 隐私保护（TCC）阻止访问，请在「系统设置 → 隐私与安全性」中授权",
            value: MMFormat.bytes(folder.size),
            systemImage: folder.iconName,
            isSelectable: folder.isAccessible,
            isSelected: $isSelected
        ) {
            HStack(spacing: MMGap.sm) {
                if !folder.isAccessible {
                    MMBadge("无权限", tint: MMColor.caution, systemImage: "lock")
                }
                MMRowAction(
                    systemImage: isExpanded ? "chevron.down" : "chevron.right",
                    help: isExpanded ? "收起子项" : "展开子项"
                ) {
                    onToggleExpand()
                }
                .disabled(!folder.isAccessible)
                MMRowAction(systemImage: "folder", help: "在访达中打开") { MMReveal.open(folder.path) }
            }
        }
        .background(isSelected ? MMColor.soft(MMColor.accent, 0.08) : .clear)

        if isExpanded {
            if isLoadingChildren {
                HStack(spacing: MMGap.sm) {
                    ProgressView().controlSize(.small)
                    Text("正在统计子项…")
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                }
                .padding(.leading, MMGap.xl * 2 + MMGap.sm)
                .frame(height: MMMetric.rowCompact, alignment: .leading)
            } else {
                ForEach(children) { child in
                    UserFolderChildRow(
                        child: child,
                        isSelected: childSelection(child.path),
                        onOpenInFinder: { MMReveal.open(child.path) }
                    )
                }
                if children.isEmpty {
                    Text("无内容")
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .padding(.leading, MMGap.xl * 2 + MMGap.sm)
                        .frame(height: MMMetric.rowCompact, alignment: .leading)
                }
            }
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct UserFolderChildRow: View {
    let child: UserFolderChild
    @Binding var isSelected: Bool
    let onOpenInFinder: () -> Void

    var body: some View {
        HStack(spacing: MMGap.sm) {
            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(isSelected ? "取消选择" : "选择此项进行清理（默认不选）")

            Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                .font(.caption2)
                .foregroundStyle(MMColor.tertiaryLabel)
                .frame(width: 14)

            Text(child.name)
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
                .lineLimit(1)

            Spacer(minLength: MMGap.sm)

            Text("\(child.fileCount) 个文件 · \(child.modificationDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(MMColor.tertiaryLabel)

            Text(MMFormat.bytes(child.size))
                .font(.caption.monospaced())
                .foregroundStyle(isSelected ? MMColor.label : MMColor.tertiaryLabel)
                .frame(minWidth: 72, alignment: .trailing)

            MMRowAction(systemImage: "folder", help: "在访达中打开", action: onOpenInFinder)
        }
        .padding(.leading, MMGap.xl * 2 + MMGap.sm)
        .padding(.trailing, MMGap.md)
        .frame(height: MMMetric.rowCompact)
        .background(isSelected ? MMColor.soft(MMColor.accent, 0.06) : .clear)
    }
}
