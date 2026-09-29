import SwiftUI
import MMCore
import MMFileScanner

/// Task 2 UI：系统级文件分析。默认只读——每项都带安全等级徽标，
/// 只有「可安全清理」与「可清理·需谨慎」两类需要用户逐项手动勾选，
/// 且清理一律通过 FileTrashService 移入废纸篓并支持撤回。
struct SystemAnalysisView: View {
    @State private var groups: [SystemAnalysisGroup] = []
    @State private var hasAnalyzed = false
    @State private var isAnalyzing = false
    @State private var isCleaning = false
    @State private var selectedPaths: Set<String> = []
    @State private var scanningPath = ""
    @State private var scannedFileCount = 0
    @State private var lastResult: TrashResult?
    @State private var showUndoToast = false
    @State private var analyzeTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isAnalyzing && groups.isEmpty {
                analyzeProgressView
            } else if !hasAnalyzed {
                emptyView
            } else {
                groupList
            }
            Divider()
            actionBar
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
            Image(systemName: "gearshape.2.fill")
                .font(.largeTitle)
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text("系统级文件分析")
                    .font(.title2.bold())
                Text("只读分析日志、诊断报告、设备备份与 SIP 保护区占用。SIP 路径与需要 root 的内容永远仅供查看，绝不执行 sudo。")
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
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("分析系统日志、诊断报告、设备备份与大文件热点")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button {
                startAnalyze()
            } label: {
                Label("开始分析", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var analyzeProgressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("正在分析系统文件...")
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
            Button("取消分析") {
                analyzeTask?.cancel()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(groups) { group in
                    SystemGroupSection(
                        group: group,
                        selectedPaths: selectedPaths,
                        onToggleSelect: { path in
                            toggleSelection(path)
                        },
                        onToggleSelectAllCleanable: {
                            toggleGroup(group)
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
                startAnalyze()
            } label: {
                Label(isAnalyzing ? "分析中..." : "重新分析", systemImage: "arrow.clockwise")
            }
            .disabled(isAnalyzing || isCleaning)

            Spacer()

            Text("仅供查看的项目永远不会被清理")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await cleanSelected() }
            } label: {
                Label(isCleaning ? "清理中..." : "清理选中 (\(cleanTargets.count))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(cleanTargets.isEmpty || isAnalyzing || isCleaning)
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
                    Task { await undoAnalysisClean() }
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

    // MARK: - 选中项

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

    private var selectableItems: [SystemAnalysisItem] {
        groups.flatMap(\.items).filter { $0.safety.isUserSelectable }
    }

    private var selectedSize: UInt64 {
        let lookup = Dictionary(selectableItems.map { ($0.path, $0.size) }) { $1 }
        return cleanTargets.reduce(UInt64(0)) { $0 + (lookup[$1] ?? 0) }
    }

    // MARK: - 动作

    private func toggleSelection(_ path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    private func toggleGroup(_ group: SystemAnalysisGroup) {
        let cleanable = group.items.filter { $0.safety.isUserSelectable }.map(\.path)
        let allSelected = cleanable.allSatisfy { selectedPaths.contains($0) }
        if allSelected {
            for path in cleanable {
                selectedPaths.remove(path)
            }
        } else {
            for path in cleanable {
                selectedPaths.insert(path)
            }
        }
    }

    private func startAnalyze() {
        isAnalyzing = true
        scanningPath = ""
        scannedFileCount = 0

        let tracker = FileScanProgressTracker()
        let analyzer = SystemAnalyzer()

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                scanningPath = tracker.currentPath
                scannedFileCount = tracker.fileCount
            }
        }

        analyzeTask = Task {
            let result = await analyzer.analyze(tracker: tracker)
            progressTask.cancel()
            guard !Task.isCancelled else {
                await MainActor.run {
                    isAnalyzing = false
                }
                return
            }
            await MainActor.run {
                withAnimation {
                    groups = result
                    hasAnalyzed = true
                    isAnalyzing = false
                    selectedPaths = []
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

        let cleaned = Set(paths)
        for i in groups.indices {
            groups[i].items.removeAll { cleaned.contains($0.path) }
        }
        groups = groups.filter { !$0.items.isEmpty }
        selectedPaths = []
        isCleaning = false

        try? await Task.sleep(for: .seconds(15))
        showUndoToast = false
    }

    private func undoAnalysisClean() async {
        _ = await FileTrashService.shared.undoLastOperation()
        showUndoToast = false
        startAnalyze()
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct SystemGroupSection: View {
    let group: SystemAnalysisGroup
    let selectedPaths: Set<String>
    let onToggleSelect: (String) -> Void
    let onToggleSelectAllCleanable: () -> Void
    let onOpenInFinder: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: group.iconName)
                    .font(.title3)
                    .foregroundStyle(.teal)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.body.weight(.medium))
                    Text(group.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(formatSize(group.totalSize))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(group.hasCleanableItems ? Color.red : Color.secondary)

                if group.hasCleanableItems {
                    Button {
                        onToggleSelectAllCleanable()
                    } label: {
                        Text(groupCleanableAllLabel)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            VStack(spacing: 2) {
                ForEach(group.items) { item in
                    SystemItemRow(
                        item: item,
                        isSelected: selectedPaths.contains(item.path),
                        onToggleSelect: { onToggleSelect(item.path) },
                        onOpenInFinder: { onOpenInFinder(item.path) }
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var groupCleanableAllLabel: String {
        let cleanable = group.items.filter { $0.safety.isUserSelectable }.map(\.path)
        let allSelected = cleanable.allSatisfy { selectedPaths.contains($0) }
        return allSelected ? "全不选" : "全选可清理"
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct SystemItemRow: View {
    let item: SystemAnalysisItem
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onOpenInFinder: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if item.safety.isUserSelectable {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.green : Color.secondary.opacity(0.6))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "取消选择" : "选择此项进行清理（默认不选）")
            } else {
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .help("仅供查看，不提供删除")
            }

            SafetyBadge(safety: item.safety)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if item.fileCount > 1 {
                Text("\(item.fileCount) 个文件 · \(formatDate(item.modificationDate))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if item.modificationDate != nil {
                Text(formatDate(item.modificationDate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(formatSize(item.size))
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
        .padding(.horizontal, 6)
        .background(isSelected ? Color.orange.opacity(0.06) : Color(nsColor: .textBackgroundColor).opacity(0.3))
        .clipShape(.rect(cornerRadius: 5))
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct SafetyBadge: View {
    let safety: SystemItemSafety

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(safety.label)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(badgeColor)
        .background(badgeColor.opacity(0.12))
        .clipShape(.capsule)
    }

    private var iconName: String {
        switch safety {
        case .safe: return "checkmark.shield.fill"
        case .cleanWithWarning: return "exclamationmark.triangle.fill"
        case .readOnly: return "eye"
        case .sipProtected: return "lock.fill"
        }
    }

    private var badgeColor: Color {
        switch safety {
        case .safe: return .green
        case .cleanWithWarning: return .orange
        case .readOnly: return .secondary
        case .sipProtected: return .red
        }
    }
}
