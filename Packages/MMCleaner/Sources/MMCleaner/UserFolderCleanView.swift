import SwiftUI
import MMCore
import MMFileScanner

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
    @State private var showUndoToast = false
    @State private var showConfirmAlert = false
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isScanning && folders.isEmpty {
                scanProgressView
            } else if !hasScanned {
                emptyView
            } else {
                folderList
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
            Text("共 \(cleanTargets.count) 项，约 \(formatSize(selectedSize))。\n选中的内容将移入废纸篓（可撤回），不会永久删除。")
        }
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
            Image(systemName: "folder.badge.person.crop")
                .font(.largeTitle)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 4) {
                Text("用户文件夹")
                    .font(.title2.bold())
                Text("桌面、文稿、下载等个人目录。默认全部未选中——只有你逐项勾选的内容才会被清理，且只移入废纸篓。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !selectedPaths.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("已选 \(cleanTargets.count) 项")
                        .font(.title3.bold())
                        .foregroundStyle(Color.orange)
                    Text(formatSize(selectedSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("扫描你的桌面 / 文稿 / 下载 / 图片 / 影片 / 音乐")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("受 macOS 隐私保护，首次访问可能需要在系统弹窗中允许")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                startScan()
            } label: {
                Label("扫描用户文件夹", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanProgressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("正在扫描用户文件夹...")
                .font(.headline)
            if !scanningPath.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                    Text(scanningPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            }
            Text("已遍历 \(scannedFileCount) 个条目")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("取消扫描") {
                scanTask?.cancel()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var folderList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(folders) { folder in
                    UserFolderSection(
                        folder: folder,
                        selectedPaths: selectedPaths,
                        isSelected: selectedPaths.contains(folder.path),
                        isExpanded: expandedFolderPath == folder.path,
                        children: folderChildren[folder.path] ?? [],
                        isLoadingChildren: childrenLoadingPath == folder.path,
                        onToggleSelect: {
                            toggleSelection(folder.path)
                        },
                        onToggleExpand: {
                            toggleExpand(folder: folder)
                        },
                        onToggleChildSelect: { path in
                            toggleSelection(path)
                        },
                        onOpenInFinder: { path in
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
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
                startScan()
            } label: {
                Label(isScanning ? "扫描中..." : "重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(isScanning || isCleaning)

            Spacer()

            if !selectedPaths.isEmpty {
                Text("未勾选的内容绝不会被清理")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                showConfirmAlert = true
            } label: {
                Label(isCleaning ? "清理中..." : "清理选中 (\(cleanTargets.count))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(cleanTargets.isEmpty || isScanning || isCleaning)
        }
        .padding()
    }

    @ViewBuilder
    private var undoToast: some View {
        if let result = lastResult {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("已将 \(result.successCount) 项移入废纸篓（约 \(formatSize(result.totalSize))）")
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

    private func toggleSelection(_ path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

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
        showUndoToast = true

        await applyCleaned(paths)
        selectedPaths = []
        isCleaning = false

        try? await Task.sleep(for: .seconds(15))
        showUndoToast = false
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
        showUndoToast = false
        startScan()
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// 单个用户文件夹卡片：醒目展示「是否被选中清理」，可展开查看子项并逐项勾选。
struct UserFolderSection: View {
    let folder: UserFolderInfo
    let selectedPaths: Set<String>
    let isSelected: Bool
    let isExpanded: Bool
    let children: [UserFolderChild]
    let isLoadingChildren: Bool
    let onToggleSelect: () -> Void
    let onToggleExpand: () -> Void
    let onToggleChildSelect: (String) -> Void
    let onOpenInFinder: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                selectBox(enabled: folder.isAccessible, isSelected: isSelected, action: onToggleSelect)

                Image(systemName: folder.iconName)
                    .font(.title3)
                    .foregroundStyle(folder.isAccessible ? .purple : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(folder.name)
                            .font(.body.weight(.medium))
                        if !folder.isAccessible {
                            Text("无访问权限")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(.capsule)
                                .overlay(Capsule().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                        }
                    }
                    if folder.isAccessible {
                        Text("\(folder.fileCount) 个文件 · 修改于 \(formatDate(folder.modificationDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("macOS 隐私保护（TCC）阻止访问，请在「系统设置 → 隐私与安全性」中授权")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Text("已选择清理")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                }

                Text(formatSize(folder.size))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.orange : .secondary)

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .disabled(!folder.isAccessible)

                Button {
                    onOpenInFinder(folder.path)
                } label: {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("在访达中打开")
            }

            if isExpanded {
                Divider().padding(.leading, 40)
                VStack(spacing: 0) {
                    if isLoadingChildren {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在统计子项...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 40)
                        .padding(.vertical, 6)
                    } else {
                        ForEach(children) { child in
                            UserFolderChildRow(
                                child: child,
                                isSelected: selectedPaths.contains(child.path),
                                onToggleSelect: { onToggleChildSelect(child.path) },
                                onOpenInFinder: { onOpenInFinder(child.path) }
                            )
                        }
                        if children.isEmpty {
                            Text("无内容")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 40)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.orange.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.orange.opacity(0.5) : .clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func selectBox(enabled: Bool, isSelected: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            Button(action: action) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.green : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "取消选择" : "选择此项进行清理（默认不选）")
        } else {
            Image(systemName: "lock.circle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct UserFolderChildRow: View {
    let child: UserFolderChild
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onOpenInFinder: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.green : Color.secondary.opacity(0.6))
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "取消选择" : "选择此项进行清理（默认不选）")

            Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                .font(.caption2)
                .foregroundStyle(child.isDirectory ? .purple.opacity(0.6) : .secondary)
                .frame(width: 14)

            Text(child.name)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)

            Spacer()

            Text("\(child.fileCount) 个文件 · \(formatDate(child.modificationDate))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(formatSize(child.size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.orange : Color.secondary)

            Button(action: onOpenInFinder) {
                Image(systemName: "folder")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("在访达中打开")
        }
        .padding(.vertical, 4)
        .padding(.leading, 40)
        .padding(.trailing, 4)
        .background(isSelected ? Color.orange.opacity(0.06) : Color(nsColor: .textBackgroundColor).opacity(0.3))
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
