import SwiftUI
import MMCore
import MMFileScanner
import MMUI

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
    @State private var lastFailures: [TrashFailure] = []
    @State private var toastSeconds = 0
    @State private var showConfirmAlert = false
    @State private var analyzeTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            MMPageHeader("系统级文件分析", subtitle: headerSubtitle) {
                Button {
                    startAnalyze()
                } label: {
                    Label(isAnalyzing ? "分析中…" : "重新分析", systemImage: "arrow.clockwise")
                }
                .disabled(isAnalyzing || isCleaning)
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
        // 这一页列的是系统目录，删除前必须和另两页一样先确认一次。
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
                    onUndo: { Task { await undoAnalysisClean() } },
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
        // 仅供截图验证：合成点击会逃到别的应用，分析结果态没有别的办法进入。
        .task {
            guard ProcessInfo.processInfo.environment["MM_AUTO_SCAN"] != nil else { return }
            if !hasAnalyzed, !isAnalyzing { startAnalyze() }
        }
        .onChange(of: hasAnalyzed) { _, analyzed in
            guard analyzed, ProcessInfo.processInfo.environment["MM_SHOW_CONFIRM"] != nil else { return }
            // 只勾可清理项中最小的一个：这条路径只为截确认弹窗，误触发的损失要接近零。
            if let smallest = selectableItems.filter { $0.size > 0 }.min(by: { $0.size < $1.size }) {
                selectedPaths = [smallest.path]
                showConfirmAlert = true
            }
        }
    }

    private var headerSubtitle: String {
        if isAnalyzing { return "分析中…" }
        guard hasAnalyzed else { return "尚未分析" }
        let total = groups.reduce(UInt64(0)) { $0 + $1.totalSize }
        let cleanable = selectableItems.reduce(UInt64(0)) { $0 + $1.size }
        return "\(groups.count) 组 · \(MMFormat.bytes(total)) · 可清理 \(MMFormat.bytes(cleanable))"
    }

    @ViewBuilder
    private var content: some View {
        if isAnalyzing && groups.isEmpty {
            VStack(spacing: 0) {
                MMScanProgress(
                    action: "正在分析系统文件",
                    currentPath: scanningPath.isEmpty ? nil : scanningPath,
                    processedCount: scannedFileCount,
                    estimatedRemaining: nil,
                    progress: nil
                )
                Divider()
                ForEach(0..<6, id: \.self) { _ in
                    MMSkeletonRow(nameWidth: 140, valueWidth: 72)
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("取消分析") { analyzeTask?.cancel() }
                        .padding(.bottom, MMGap.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MMColor.contentBackground)
        } else if !hasAnalyzed {
            MMEmptyState(
                systemImage: "magnifyingglass.circle",
                title: "分析系统日志、诊断报告、设备备份与大文件热点",
                detail: "只读分析。SIP 保护区与需要 root 的内容永远仅供查看，本应用绝不执行 sudo。",
                action: AnyView(
                    Button {
                        startAnalyze()
                    } label: {
                        Label("开始分析", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                )
            )
        } else if groups.isEmpty {
            MMEmptyState(
                systemImage: "checkmark.seal",
                title: "没有可报告的系统占用",
                detail: "分析中途取消时结果不完整，请重新分析。"
            )
        } else {
            groupTable
        }
    }

    private var groupTable: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        groupHeader(group)
                        Divider()
                        ForEach(group.items) { item in
                            SystemItemRow(
                                item: item,
                                isSelected: selectionBinding(for: item.path),
                                onOpenInFinder: { MMReveal.open(item.path) }
                            )
                        }
                    }
                    HStack(alignment: .top, spacing: MMGap.xs) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                        Text("「仅供查看」与「SIP 保护」两类不提供删除入口；勾选只作用于可清理项，且一律移入废纸篓。")
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

    private func groupHeader(_ group: SystemAnalysisGroup) -> some View {
        HStack(spacing: MMGap.sm) {
            Image(systemName: group.iconName)
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
            Text(group.name)
                .font(.callout.weight(.semibold))
            Text("\(group.items.count) 项 · \(MMFormat.bytes(group.totalSize))")
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
            Spacer()
            Text(group.description)
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                // 不封顶时这行会按理想宽度撑破分组行，尾字被卡片边框切掉。
                .frame(maxWidth: 280, alignment: .trailing)
            if group.hasCleanableItems {
                Button(groupCleanableAllLabel(group)) {
                    toggleGroup(group)
                }
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: 30)
        .background(MMColor.cardBackground)
    }

    private func groupCleanableAllLabel(_ group: SystemAnalysisGroup) -> String {
        let cleanable = group.items.filter { $0.safety.isUserSelectable }.map(\.path)
        return cleanable.allSatisfy { selectedPaths.contains($0) } ? "全不选" : "全选可清理"
    }

    private var actionBar: some View {
        MMActionBar(
            summary: "已选 \(cleanTargets.count) 项 · \(MMFormat.bytes(selectedSize))",
            note: isAnalyzing ? "分析未完成，数字只包含已扫到的部分" : "仅供查看的项目永远不会被清理"
        ) {
            Button("清理选中 \(cleanTargets.count) 项") {
                showConfirmAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(MMColor.destructive)
            .disabled(cleanTargets.isEmpty || isAnalyzing || isCleaning)
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
        lastFailures = result.operation.failures
        // 一项都没搬动就别弹"已移入废纸篓"，失败清单已经在面板里说清楚了。
        if result.successCount > 0 { toastSeconds = 15 }

        let cleaned = Set(paths)
        for i in groups.indices {
            groups[i].items.removeAll { cleaned.contains($0.path) }
        }
        groups = groups.filter { !$0.items.isEmpty }
        selectedPaths = []
        isCleaning = false
    }

    private func undoAnalysisClean() async {
        _ = await FileTrashService.shared.undoLastOperation()
        toastSeconds = 0
        startAnalyze()
    }

}

/// 一行一项：可清理项给勾选框，只读项给眼睛，安全档一律用徽章表达。
struct SystemItemRow: View {
    let item: SystemAnalysisItem
    @Binding var isSelected: Bool
    let onOpenInFinder: () -> Void

    var body: some View {
        HStack(spacing: MMGap.md) {
            if item.safety.isUserSelectable {
                Toggle("", isOn: $isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(isSelected ? "取消选择" : "选择此项进行清理（默认不选）")
            } else {
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .frame(width: 14)
                    .help("仅供查看，不提供删除入口")
            }

            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(item.name).font(.body).lineLimit(1)
                Text(item.detail).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: MMGap.sm)

            MMBadge(item.safety.badgeText, tint: item.safety.badgeTint, systemImage: item.safety.badgeImage)
                .fixedSize()

            Text(item.modificationDate.map { "修改于 \(($0).formatted(date: .abbreviated, time: .omitted))" } ?? "日期未知")
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)

            Text(MMFormat.bytes(item.size))
                .font(.callout.monospaced())
                .foregroundStyle(isSelected ? MMColor.label : MMColor.secondaryLabel)
                .frame(minWidth: 72, alignment: .trailing)

            MMRowAction(systemImage: "folder", help: "在访达中打开", action: onOpenInFinder)
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: MMMetric.rowRegular)
        .background(isSelected ? MMColor.soft(MMColor.accent, 0.08) : .clear)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}

private extension SystemItemSafety {
    /// 徽章的文案/色/图标全部由安全档推导，页面不再各写一遍颜色，
    /// 也就不会出现"扫描器认为安全、界面显示红色"。
    var badgeText: String { label }

    var badgeImage: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .cleanWithWarning: "exclamationmark.triangle.fill"
        case .readOnly: "eye"
        case .sipProtected: "lock.fill"
        }
    }

    var badgeTint: Color {
        switch self {
        case .safe: MMColor.safe
        case .cleanWithWarning: MMColor.caution
        case .readOnly: MMColor.secondaryLabel
        case .sipProtected: MMColor.destructive
        }
    }
}
