import SwiftUI
import MMCore
import MMFileScanner
import MMUI

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

// MARK: - 状态

@MainActor
final class CleanerModel: ObservableObject {
    @Published var categories: [CacheCategory] = []
    @Published var selectedIDs: Set<String> = []
    /// 排除名单（持久化）。`CleanerExclusionStore` 是唯一真源，这里只是可观察的快照。
    @Published var excludedEntries: [CleanerExclusionEntry] = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var progress: CacheScanProgress?
    @Published var isPartial = false
    @Published var scannedAt: Date?
    @Published var lastResult: TrashResult?
    @Published var failures: [TrashFailure] = []
    @Published var expandedCategories: Set<String> = []
    @Published var expandedSubItemPath: String?
    @Published var children: [String: [CacheFileEntry]] = [:]
    /// 4.6 的只读报告：APFS 可清除空间 + Time Machine 本地快照。只展示，不删除。
    @Published var spaceReadout: SystemSpaceReadout?
    @Published var isLoadingSpaceReadout = false

    private var scanTask: Task<Void, Never>?
    private let cancellation = CancellationFlag()
    private let exclusionStore: CleanerExclusionStore

    init(exclusionStore: CleanerExclusionStore = CleanerExclusionStore()) {
        self.exclusionStore = exclusionStore
        self.excludedEntries = exclusionStore.entries()
    }

    /// 明细条目是否已被排除。判定走存储的同一口径，界面与扫描才不会一边算 excluded、
    /// 一边照样把它算进合计。
    func isExcluded(_ path: String) -> Bool {
        excludedEntries.contains { CleanerExclusionStore.matches(path, exclusion: $0.path) }
    }

    var inaccessiblePaths: [String] {
        categories.flatMap(\.inaccessiblePaths)
    }

    /// "可释放"只能说真的能释放的那部分：只读档没有删除入口，
    /// 把它的体积算进可释放数字就是把用户带偏。
    var measuredTotal: UInt64 {
        categories.filter(\.risk.allowsDeletion).reduce(0) { $0 + $1.scannedSize }
    }

    var readOnlyTotal: UInt64 {
        categories.filter { !$0.risk.allowsDeletion }.reduce(0) { $0 + $1.scannedSize }
    }

    /// 只有"允许删除且被勾选、且未被排除"的字节才会真的动磁盘。
    var selectedSize: UInt64 {
        var total: UInt64 = 0
        for category in categories where selectedIDs.contains(category.id) && category.risk.allowsDeletion {
            for item in category.subItems where !isExcluded(item.path) {
                total += item.size ?? 0
            }
        }
        return total
    }

    var selectedDeletableCount: Int {
        categories.filter { selectedIDs.contains($0.id) && $0.risk.allowsDeletion }.count
    }

    var selectedPaths: [String] {
        var paths: [String] = []
        for category in categories where selectedIDs.contains(category.id) && category.risk.allowsDeletion {
            paths.append(contentsOf: category.subItems
                .filter { !isExcluded($0.path) }
                .map(\.path))
        }
        return paths
    }

    func scope(from settings: AppSettings) -> CacheScanScope {
        var scope: CacheScanScope = []
        if settings.scanSystemCache { scope.insert(.systemCache) }
        if settings.scanAppCache { scope.insert(.appCache) }
        if settings.scanLogFiles { scope.insert(.logs) }
        if settings.scanTempFiles { scope.insert(.temp) }
        return scope
    }

    /// 扫描真正消费的排除清单：设置页的永久排除目录 + 清理页逐条排除的持久化名单。
    /// 少了后半段，"排除"就只是个视觉状态，下一轮扫描照样把字节算回来。
    func excludedPathsForScan(settings: AppSettings) -> [String] {
        var merged = settings.excludedFolderPaths
        merged.append(contentsOf: excludedEntries.map(\.path))
        return Array(Set(merged)).sorted()
    }

    func scan(settings: AppSettings) {
        scanTask?.cancel()
        cancellation.reset()
        isScanning = true
        progress = nil
        isPartial = false
        let scope = scope(from: settings)
        let exclusions = excludedPathsForScan(settings: settings)
        // 闭包在后台 actor 上被反复调用，强引用标志本身而不是 self：
        // 用 `self?.isCancelled ?? true` 会在模型释放的瞬间把整轮扫描判成已取消。
        let cancellation = self.cancellation

        scanTask = Task { [weak self] in
            let report = await CacheScanner().scan(
                scope: scope,
                excludedFolderPaths: exclusions,
                shouldContinue: { !cancellation.isCancelled },
                progress: { snapshot in
                    Task { @MainActor in self?.progress = snapshot }
                }
            )
            self?.apply(report)
        }
    }

    private func apply(_ report: CacheScanReport) {
        categories = report.categories
        // 默认勾选状态由风险档决定：谨慎与只读不预选，
        // 这样"一键清理"永远不会顺手带走用户没看过的东西。
        selectedIDs = Set(report.categories
            .filter { $0.risk.isDefaultSelected && $0.scannedSize > 0 }
            .map(\.id))
        isScanning = false
        isPartial = !report.isComplete
        scannedAt = Date()
        // 只用于截图核对：合成点击会逃到别的应用，展开态没有别的办法验证。
        if ProcessInfo.processInfo.environment["MM_EXPAND_CATEGORIES"] != nil {
            expandedCategories = Set(report.categories.map(\.id))
        }
    }

    func cancelScan() {
        cancellation.cancel()
    }

    func toggleSelection(_ category: CacheCategory) {
        guard category.risk.allowsDeletion else { return }
        if selectedIDs.contains(category.id) {
            selectedIDs.remove(category.id)
        } else {
            selectedIDs.insert(category.id)
        }
    }

    func toggleAll(in group: [CacheCategory]) {
        let deletable = group.filter(\.risk.allowsDeletion)
        let ids = Set(deletable.map(\.id))
        if selectedIDs.isSuperset(of: ids) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    func toggleExclusion(_ path: String) {
        if exclusionStore.remove(path: path) {
            excludedEntries = exclusionStore.entries()
            return
        }
        // 新的排除默认就是"按扫描到的明细条目排除"。
        addExclusion(path, source: .scannedItem)
    }

    @discardableResult
    func addExclusion(_ path: String, source: CleanerExclusionSource) -> Bool {
        guard exclusionStore.add(path: path, source: source) else { return false }
        excludedEntries = exclusionStore.entries()
        return true
    }

    func removeExclusion(_ path: String) {
        guard exclusionStore.remove(path: path) else { return }
        excludedEntries = exclusionStore.entries()
    }

    func toggleCategoryExpanded(_ category: CacheCategory) {
        if expandedCategories.contains(category.id) {
            expandedCategories.remove(category.id)
        } else {
            expandedCategories.insert(category.id)
        }
    }

    func loadChildren(of item: CacheSubItem) {
        expandedSubItemPath = expandedSubItemPath == item.path ? nil : item.path
        guard children[item.path] == nil else { return }
        Task {
            let entries = await CacheScanner().listChildren(path: item.path)
            children[item.path] = entries
        }
    }

    func clean() {
        let paths = selectedPaths
        guard !paths.isEmpty else { return }
        isCleaning = true
        Task { [weak self] in
            guard let self else { return }
            // 唯一删除出口：FileTrashService 负责废纸篓、操作记录与逐条失败上报。
            let result = await FileTrashService.shared.moveToTrash(paths: paths)
            self.lastResult = result
            self.failures = result.operation.failures
            let cleaned = Set(paths)
            for index in self.categories.indices {
                self.categories[index].subItems.removeAll { cleaned.contains($0.path) }
                self.categories[index].scannedSize = self.categories[index].subItems.reduce(0) { sum, item in
                    sum + (item.size ?? 0)
                }
                if self.categories[index].subItems.isEmpty {
                    self.selectedIDs.remove(self.categories[index].id)
                }
            }
            // 条目已经不存在了，排除记录留着只会变成点不开的幽灵行。
            self.exclusionStore.remove(paths: cleaned)
            self.excludedEntries = self.exclusionStore.entries()
            self.isCleaning = false
        }
    }

    /// 4.6：只读地把可清除空间与本地快照读一遍。
    /// tmutil 要起子进程，所以整段放在 actor 里，主线程只接结果。
    func loadSpaceReadout() {
        guard !isLoadingSpaceReadout else { return }
        isLoadingSpaceReadout = true
        Task { [weak self] in
            let readout = await SystemSpaceReporter().readout()
            self?.spaceReadout = readout
            self?.isLoadingSpaceReadout = false
        }
    }

    func undo() {
        let operationID = lastResult?.operation.id
        isCleaning = true
        Task { [weak self] in
            guard let self else { return }
            let restored: UndoResult
            if let operationID {
                restored = await FileTrashService.shared.undo(operationID: operationID)
            } else {
                restored = await FileTrashService.shared.undoLastOperation()
            }
            self.failures = restored.failures
            self.lastResult = nil
            self.isCleaning = false
            self.scan(settings: AppSettings.shared)
        }
    }
}

// MARK: - 页面

public struct CleanerView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var model = CleanerModel()
    @State private var filter: CleanerFilter = .all
    /// MM_CLEANER_FILTER 只是给搜索框一个初值（和用户在框里打字是同一个状态），
    /// 供无头截图把某个类别单独留在视口里——不用合成键盘输入，那会逃逸到别的 app。
    @State private var search = ProcessInfo.processInfo.environment["MM_CLEANER_FILTER"] ?? ""
    @State private var showConfirm = false
    @State private var showExclusions = false
    @State private var toastSeconds = 0

    public init() {}

    private var visibleCategories: [CacheCategory] {
        model.categories.filter { category in
            (filter == .all || filter.contains(category.scope))
                && (search.isEmpty
                    || category.name.localizedCaseInsensitiveContains(search)
                    || category.subtitle.localizedCaseInsensitiveContains(search))
        }
    }

    private var groups: [(risk: MMRisk, categories: [CacheCategory])] {
        MMRisk.allCases.compactMap { risk in
            let items = visibleCategories.filter { $0.risk == risk }
            return items.isEmpty ? nil : (risk, items)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            MMPageHeader("系统清理", subtitle: headerSubtitle) {
                Picker("", selection: $filter) {
                    ForEach(CleanerFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                TextField("搜索类别", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                Button {
                    model.scan(settings: settings)
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
            }

            if !model.inaccessiblePaths.isEmpty {
                MMPermissionBanner(
                    title: "有 \(model.inaccessiblePaths.count) 个位置读不到，统计不到它们的体积",
                    detail: "多数是其他应用的沙盒容器。未授权的部分不计入合计，也不会显示为 0。",
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                )
            }

            content

            if !model.failures.isEmpty {
                MMFailurePanel(
                    summary: "已回收 \(MMFormat.bytes(model.lastResult?.totalSize))",
                    model.failures
                ) {
                    model.failures = []
                }
            }

            Divider()
            actionBar
                .sheet(isPresented: $showConfirm) { confirmSheet }
                .sheet(isPresented: $showExclusions) { exclusionSheet }
        }
        .task {
            if model.categories.isEmpty, !model.isScanning {
                model.scan(settings: settings)
            }
            // 只读报告与清理扫描互不依赖，进页面顺手读一次即可；要更新用区块里的刷新按钮。
            if model.spaceReadout == nil {
                model.loadSpaceReadout()
            }
            if ProcessInfo.processInfo.environment["MM_SHOW_CONFIRM"] != nil {
                showConfirm = true
            }
        }
        .task(id: toastSeconds) {
            guard toastSeconds > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            toastSeconds -= 1
        }
        .overlay(alignment: .bottom) {
            if model.lastResult != nil, settings.allowUndo, toastSeconds > 0 {
                toast
                    .padding(.bottom, MMMetric.actionBar + MMGap.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toastSeconds)
        .onChange(of: model.lastResult?.operation.id) { _, newValue in
            guard newValue != nil, settings.allowUndo else { return }
            toastSeconds = 15
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning && model.categories.isEmpty {
            VStack(spacing: 0) {
                MMScanProgress(
                    action: "正在扫描 \(model.progress?.categoryName ?? "系统缓存")",
                    currentPath: model.progress?.currentPath,
                    processedCount: model.progress?.processedItems ?? 0,
                    estimatedRemaining: nil,
                    progress: model.progress?.fraction
                )
                Divider()
                ForEach(0..<5, id: \.self) { _ in
                    MMSkeletonRow(nameWidth: 160, valueWidth: 64)
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("取消") { model.cancelScan() }
                        .padding(.bottom, MMGap.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MMColor.contentBackground)
        } else if model.categories.isEmpty {
            MMEmptyState(
                systemImage: "sparkles",
                title: "没有可清理的内容",
                detail: "已检查 \(model.categories.count) 个类别。扫描中途取消时结果不完整，请重新扫描。",
                action: AnyView(Button("重新扫描") { model.scan(settings: settings) })
            )
        } else {
            categoryTable
        }
    }

    private var categoryTable: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    tableHeader
                    ForEach(groups, id: \.risk) { group in
                        groupHeader(group.risk, group.categories)
                        ForEach(group.categories) { category in
                            categoryRows(category)
                        }
                    }
                    HStack(alignment: .top, spacing: MMGap.xs) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                        Text("所有删除一律先移入废纸篓，可在「最近操作」中撤回；被占用或无权限的条目会单独报告，不会静默跳过。")
                            .font(.caption)
                            .foregroundStyle(MMColor.secondaryLabel)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, MMGap.md)
                    .padding(.vertical, MMGap.sm)

                    // 4.6：APFS 可清除空间与本地快照。整块只读，没有任何删除入口。
                    ReadOnlySpaceReportSection(
                        readout: model.spaceReadout,
                        isLoading: model.isLoadingSpaceReadout,
                        onRefresh: { model.loadSpaceReadout() }
                    )
                }
                // 必须显式给宽：LazyVStack 在 ScrollView 里会按最宽子项的
                // 理想宽度排版，整张表就会横向溢出、右侧说明文字被裁掉。
                .frame(width: proxy.size.width - MMGap.lg * 2)
                .background(MMColor.contentBackground)
                .overlay(RoundedRectangle(cornerRadius: MMRadius.card).stroke(MMColor.separator))
                .padding(.horizontal, MMGap.lg)
                .padding(.vertical, MMGap.lg)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: MMGap.md) {
            Toggle("", isOn: selectAllBinding).toggleStyle(.checkbox).labelsHidden()
            Text("").frame(width: MMMetric.iconSmall)
            Text("类别").frame(maxWidth: .infinity, alignment: .leading)
            Text("大小").frame(minWidth: 72, alignment: .trailing)
            Text("风险").frame(width: 44, alignment: .trailing)
            Text("").frame(width: 52)
        }
        .font(.caption)
        .foregroundStyle(MMColor.secondaryLabel)
        .padding(.horizontal, MMGap.md)
        .frame(height: 26)
        .background(MMColor.cardBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var selectAllBinding: Binding<Bool> {
        let deletable = visibleCategories.filter(\.risk.allowsDeletion)
        return Binding(
            get: {
                !deletable.isEmpty
                    && model.selectedIDs.isSuperset(of: Set(deletable.map(\.id)))
            },
            set: { isOn in
                if isOn {
                    model.selectedIDs.formUnion(deletable.map(\.id))
                } else {
                    model.selectedIDs.subtract(deletable.map(\.id))
                }
            }
        )
    }

    private func groupHeader(_ risk: MMRisk, _ categories: [CacheCategory]) -> some View {
        HStack(spacing: MMGap.sm) {
            Text(risk.groupTitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(risk.color)
            Text("\(categories.count) 类 · \(MMFormat.bytes(categories.reduce(0) { $0 + $1.scannedSize }))")
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
            Spacer()
            Text(risk.groupNote)
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                // 不封顶时这行会按理想宽度撑破分组行，尾字被卡片边框切掉。
                .frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func categoryRows(_ category: CacheCategory) -> some View {
        MMItemRow(
            title: category.name,
            subtitle: "\(category.subtitle) · \(MMFormat.count(category.scannedFiles)) 项",
            value: category.scannedSize > 0 ? MMFormat.bytes(category.scannedSize) : "—",
            risk: category.risk,
            systemImage: category.iconName,
            isSelectable: category.risk.allowsDeletion,
            isSelected: selectionBinding(for: category)
        ) {
            if !category.subItems.isEmpty {
                MMRowAction(systemImage: model.expandedCategories.contains(category.id)
                            ? "chevron.up" : "chevron.down",
                            help: "展开明细") { model.toggleCategoryExpanded(category) }
            }
            if let path = category.subItems.first?.path {
                MMRowAction(systemImage: "folder", help: "在访达中打开") { MMReveal.open(path) }
            }
        }
        .frame(maxWidth: .infinity)
        .background(model.selectedIDs.contains(category.id) ? MMColor.soft(MMColor.accent, 0.06) : .clear)
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture { model.toggleSelection(category) }

        if model.expandedCategories.contains(category.id) {
            ForEach(category.subItems) { item in
                subItemRow(item, category: category)
            }
        }
    }

    private func selectionBinding(for category: CacheCategory) -> Binding<Bool> {
        Binding(
            get: { model.selectedIDs.contains(category.id) },
            set: { _ in model.toggleSelection(category) }
        )
    }

    @ViewBuilder
    private func subItemRow(_ item: CacheSubItem, category: CacheCategory) -> some View {
        let isExcluded = model.isExcluded(item.path)
        HStack(spacing: MMGap.sm) {
            Button {
                model.loadChildren(of: item)
            } label: {
                Image(systemName: model.expandedSubItemPath == item.path ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Image(systemName: item.isAccessible ? "folder" : "lock")
                .font(.caption)
                .foregroundStyle(item.isAccessible ? MMColor.tertiaryLabel : MMColor.caution)
                .frame(width: 14)

            Text(item.name)
                .font(.callout)
                .foregroundStyle(isExcluded ? MMColor.secondaryLabel : MMColor.label)
                .strikethrough(isExcluded)
                .lineLimit(1)

            if !item.isAccessible {
                Text("无法访问 · 需要权限").font(.caption).foregroundStyle(MMColor.caution)
            }
            Spacer(minLength: MMGap.sm)

            Text(item.size.flatMap { $0 > 0 ? MMFormat.bytes($0) : nil } ?? "测量中")
                .font(.callout.monospaced())
                .foregroundStyle(isExcluded ? MMColor.tertiaryLabel : MMColor.secondaryLabel)
                .frame(minWidth: 72, alignment: .trailing)

            if category.risk.allowsDeletion {
                Button(isExcluded ? "已排除" : "排除") { model.toggleExclusion(item.path) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isExcluded ? "已写入排除名单，重启后依然生效；在名单里可恢复"
                                     : "加入排除名单，之后每次扫描都不再计入")
            }
        }
        .padding(.leading, MMGap.xl + MMGap.sm)
        .padding(.trailing, MMGap.md)
        .frame(height: MMMetric.rowCompact)
        .background(MMColor.cardBackground.opacity(0.5))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }

        if model.expandedSubItemPath == item.path {
            ForEach(model.children[item.path] ?? []) { child in
                HStack(spacing: MMGap.sm) {
                    Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                        .font(.caption2)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .frame(width: 14)
                    Text(child.name).font(.caption).foregroundStyle(MMColor.secondaryLabel).lineLimit(1)
                    Spacer(minLength: MMGap.sm)
                    Text(MMFormat.bytes(child.size))
                        .font(.caption.monospaced())
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .frame(minWidth: 72, alignment: .trailing)
                    MMRowAction(systemImage: "folder", help: "在访达中打开") { MMReveal.open(child.path) }
                }
                .padding(.leading, MMGap.xl * 2 + MMGap.sm)
                .padding(.trailing, MMGap.md)
                .frame(height: MMMetric.rowCompact)
            }
            if (model.children[item.path] ?? []).isEmpty {
                Text(model.children[item.path] == nil ? "展开中…" : "无内容")
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .padding(.leading, MMGap.xl * 2 + MMGap.sm)
                    .frame(height: MMMetric.rowCompact)
            }
        }
    }

    private var actionBar: some View {
        MMActionBar(
            summary: "已选 \(model.selectedDeletableCount) 类 · \(MMFormat.bytes(model.selectedSize))",
            note: model.isPartial
                ? "扫描未完成，数字只包含已扫到的部分"
                : "未勾选项不会被修改"
        ) {
            Button("排除名单 (\(model.excludedEntries.count))") { showExclusions = true }
                .disabled(model.excludedEntries.isEmpty && settings.excludedFolderPaths.isEmpty)
        } trailing: {
            Button(model.isCleaning ? "清理中…" : "清理已选 \(model.selectedDeletableCount) 类") {
                if settings.confirmBeforeDelete {
                    showConfirm = true
                } else {
                    model.clean()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(MMColor.destructive)
            .disabled(model.selectedPaths.isEmpty || model.isScanning || model.isCleaning)
        }
    }

    private var toast: some View {
        MMUndoToast(
            message: "已回收 \(MMFormat.bytes(model.lastResult?.totalSize))",
            detail: "\(model.lastResult?.successCount ?? 0) 项已移入废纸篓",
            secondsRemaining: toastSeconds,
            onUndo: { model.undo() },
            onRevealTrash: { MMReveal.openDirectory(NSHomeDirectory() + "/.Trash") }
        )
    }

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MMColor.destructive)
                Text("将 \(model.selectedDeletableCount) 类共 \(model.selectedPaths.count) 项移入废纸篓？")
                    .font(.headline)
            }
            Text("合计 \(MMFormat.bytes(model.selectedSize))。移入废纸篓后仍可恢复，清空废纸篓前不会真正消失。")
                .font(.callout)
                .foregroundStyle(MMColor.secondaryLabel)

            // 确认框是删除前的最后一站：清单要一次看全，不用滚动条
            // （ScrollView 在 sheet 里会被压成零高，等于什么都没列出来）。
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                ForEach(model.categories.filter { model.selectedIDs.contains($0.id) }) { category in
                    HStack {
                        Text(category.name).font(.callout)
                        Text("\(category.subItems.count) 项")
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                        Spacer()
                        Text(MMFormat.bytes(category.scannedSize))
                            .font(.callout.monospaced())
                            .foregroundStyle(MMColor.secondaryLabel)
                    }
                    .padding(.vertical, MMGap.xxs)
                }
            }
            .padding(MMGap.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.control))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.control).stroke(MMColor.separator))

            Toggle("清理后 15 秒内可一键撤回", isOn: $settings.allowUndo)
                .font(.caption)

            HStack {
                Spacer()
                Button("取消") { showConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button("移到废纸篓") {
                    showConfirm = false
                    model.clean()
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MMGap.lg)
        .frame(width: 420)
    }

    private var exclusionSheet: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            Text("排除名单").font(.headline)
            Text("名单里的目录与条目不会计入清理范围，也不会被删除；重启后依然生效。")
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)

            // 两块来源分开列：清理页逐条排除的走本模块的持久化存储，
            // 设置页选定的永久目录仍由 MMCore.AppSettings 持有。
            VStack(alignment: .leading, spacing: MMGap.xs) {
                Text("本页面排除的条目").font(.caption.weight(.semibold))
                    .foregroundStyle(MMColor.secondaryLabel)
                if model.excludedEntries.isEmpty {
                    Text("尚无逐条排除的条目")
                        .font(.callout).foregroundStyle(MMColor.tertiaryLabel)
                        .padding(.vertical, MMGap.sm)
                } else {
                    // 逐条删除 + 显示来源，是这份名单能不能被信任的关键：
                    // 只显示数量、只能整体清空的话，用户找不到那条被误排除的条目。
                    ScrollView {
                        VStack(alignment: .leading, spacing: MMGap.xxs) {
                            ForEach(model.excludedEntries) { entry in
                                HStack(spacing: MMGap.sm) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text((entry.path as NSString).abbreviatingWithTildeInPath)
                                            .font(.callout.monospaced())
                                            .lineLimit(1).truncationMode(.middle)
                                        Text("\(entry.source.label) · \(MMFormat.dateTime(entry.addedAt))")
                                            .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                                    }
                                    Spacer(minLength: MMGap.sm)
                                    Button("恢复") {
                                        model.removeExclusion(entry.path)
                                        model.scan(settings: settings)
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .help("从排除名单移除并重新扫描")
                                    MMRowAction(systemImage: "folder", help: "在访达中打开") {
                                        MMReveal.open(entry.path)
                                    }
                                }
                                .padding(.vertical, MMGap.xxs)
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }
            .padding(MMGap.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.control))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.control).stroke(MMColor.separator))

            VStack(alignment: .leading, spacing: MMGap.xs) {
                Text("设置里永久排除的目录").font(.caption.weight(.semibold))
                    .foregroundStyle(MMColor.secondaryLabel)
                if settings.excludedFolderPaths.isEmpty {
                    Text("尚无永久排除的目录")
                        .font(.callout)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, MMGap.md)
                } else {
                    List {
                        ForEach(settings.excludedFolderPaths, id: \.self) { path in
                            HStack {
                                Text((path as NSString).abbreviatingWithTildeInPath)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                Spacer()
                                Button("移除") {
                                    settings.excludedFolderPaths.removeAll { $0 == path }
                                    model.scan(settings: settings)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(height: 110)
                }
            }

            HStack {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = true
                    guard panel.runModal() == .OK else { return }
                    // 写进本模块的持久化名单并标来源，下一轮扫描就真的少扫这些子树。
                    for url in panel.urls {
                        model.addExclusion(url.path, source: .chosenFolder)
                    }
                    model.scan(settings: settings)
                } label: {
                    Label("添加目录…", systemImage: "plus")
                }
                Spacer()
                Button("完成") { showExclusions = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MMGap.lg)
        .frame(width: 480)
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if model.isScanning {
            parts.append("正在扫描 \(model.progress?.categoryName ?? "")")
        } else {
            parts.append("已扫描 \(model.categories.count) 类")
            parts.append("可释放 \(MMFormat.bytes(model.measuredTotal))")
            if model.readOnlyTotal > 0 {
                // 只读档没有删除入口，混进"可释放"里就是一个假数字，单独报。
                parts.append("另有 \(MMFormat.bytes(model.readOnlyTotal)) 只读")
            }
            if let scannedAt = model.scannedAt {
                parts.append(MMFormat.dateTime(scannedAt))
            }
        }
        if model.isPartial { parts.append("未完成") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 过滤器

enum CleanerFilter: String, CaseIterable, Identifiable {
    case all
    case cache
    case logs
    case temp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "全部"
        case .cache: "缓存"
        case .logs: "日志"
        case .temp: "临时"
        }
    }

    func contains(_ scope: CacheScope) -> Bool {
        switch self {
        case .all: true
        case .cache: scope == .systemCache || scope == .appCache
        case .logs: scope == .logs
        case .temp: scope == .temp
        }
    }
}

/// 行内图标按钮。设计稿里这类按钮默认隐藏、hover 才出现，
/// SwiftUI 用 opacity + hover 表达同一意图。
struct MMRowAction: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(width: 22, height: 22)
                .background(isHovering ? MMColor.fillHover : .clear, in: RoundedRectangle(cornerRadius: MMRadius.badge))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}
