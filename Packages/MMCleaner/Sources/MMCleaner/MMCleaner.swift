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

    var selectionPlan: CleanerSelectionPlan {
        CleanerSelectionPlan(categories: categories, selectedIDs: selectedIDs, isExcluded: isExcluded)
    }

    /// 未测得的选中路径不折成 0 字节；执行清单与确认面板共用 selectionPlan。
    var selectedSize: UInt64? { selectionPlan.size }

    var selectedDeletableCount: Int {
        selectionPlan.groups.count
    }

    var selectedPaths: [String] {
        selectionPlan.paths
    }

    /// 拼法在 `CacheScanScope.selected(...)`：概览页走的是同一条，所以两个页面的
    /// "可清理"不会因为一处看勾选、一处全开而量出两个数。
    func scope(from settings: AppSettings) -> CacheScanScope {
        CacheScanScope.selected(systemCache: settings.scanSystemCache,
                                appCache: settings.scanAppCache,
                                logs: settings.scanLogFiles,
                                temp: settings.scanTempFiles)
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
            // 只摘真的搬进废纸篓的那批：被 DeletionGuard 拒绝或 EPERM 失败的条目仍在磁盘上，
            // 若按"尝试过的全部路径"整行删掉，主表面就把失败当成了已清理。
            let cleaned = Set(result.operation.files.map(\.originalPath))
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
            self?.spaceReadout = Self.applySnapshotFixture(readout)
            self?.isLoadingSpaceReadout = false
        }
    }

    /// 截图预演（`MM_SNAPSHOT_FIXTURE=mixed|updateonly|none|broken`）：
    /// 只把快照那一块换成样例文本，卷容量仍是真读的。
    /// 本机上一刻只有一条什么快照都没有、下一刻有三条，"另有 N 个"和
    /// "多种来历"这两支没法靠真机稳定拍到——而这两支恰恰最容易写错。
    /// 解析是纯函数：不碰磁盘、不起命令，未知取值整块忽略走真实结果。
    static func applySnapshotFixture(_ readout: SystemSpaceReadout) -> SystemSpaceReadout {
        guard let name = ProcessInfo.processInfo.environment["MM_SNAPSHOT_FIXTURE"],
              name.isEmpty == false else { return readout }
        guard let text = snapshotFixtureText[name] else {
            // 可接受集合由夹具表自己算，免得加了档而文案还是旧的。
            MMHookValue.emit("MM_SNAPSHOT_FIXTURE 含非法取值（\(name)），只接受 "
                                + snapshotFixtureText.keys.sorted().joined(separator: "|")
                                + "，快照整块按真实读取结果显示")
            return readout
        }
        return SystemSpaceReadout(
            purgeable: readout.purgeable,
            snapshots: LocalSnapshotReader.parse(text, fallbackVolume: "/"),
            readAt: readout.readAt
        )
    }

    /// 内部而非私有：`SnapshotFixtureTests` 要逐条喂回解析器，
    /// 保证夹具文本本身长得像 tmutil 的输出（多行字面量漏个换行就会把第一条吃掉）。
    static let snapshotFixtureText: [String: String] = [
        "mixed": """
        Snapshots for volume group containing disk /:
        com.apple.TimeMachine.2026-05-01-120100.local
        com.apple.TimeMachine.2026-05-02-093312.local
        com.apple.os.update-5203530F8BB20B9DABC5CE76A0FFE87CCC885EE69B8A5488C24B458A7555E3AB
        com.apple.os.update-MSUPrepareUpdate
        com.apple.ThirdPartyTool.weekly-2026-05-03-010101
        """,
        // 多行字面量收尾不带换行，直接拼会把第一条粘到表头上被吃掉——这里显式补一个。
        "overflow": "Snapshots for disk /System/Volumes/Data:\n"
            + (1...9).map { "com.apple.TimeMachine.2026-05-0\($0)-0\(100000 + $0)000.local" }
                .joined(separator: "\n"),
        "updateonly": """
        Snapshots for volume group containing disk /:
        com.apple.os.update-5203530F8BB20B9DABC5CE76A0FFE87CCC885EE69B8A5488C24B458A7555E3AB
        com.apple.os.update-MSUPrepareUpdate
        """,
        "none": "Snapshots for disk /:\n",
        "broken": "tmutil: Error: Getting snapshot infos failed with error: 70",
    ]

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
                    summary: model.lastResult.map { "已回收 \(MMFormat.bytes($0.totalSize))" },
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
            // 无头截图核对拒绝文案的排版用（MM_FAILURE_FIXTURE=protected）。
            // 这条路只往展示状态里写记录，不调 `moveToTrash`，所以一个文件都不会被动：
            // 真正的 PROTECTED 回执只有在按下删除后才有，而按下删除需要合成点击 —— 本项目禁止。
            if MMHookValue.flag(key: "MM_FAILURE_FIXTURE", token: "protected"),
               model.failures.isEmpty {
                model.failures = Self.refusalPreview()
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
            // 一个类别都没勾选时 `CacheScanner` 直接返回空清单、`isComplete` 仍是 true，
            // 说"没有可清理的内容"就是替用户下他没问过的结论：本轮压根没检查任何类别。
            let scopeEmpty = model.scope(from: settings).isEmpty
            MMEmptyState(
                systemImage: scopeEmpty ? "slider.horizontal.below.rectangle" : "sparkles",
                title: scopeEmpty ? "没有勾选任何扫描类别"
                      : model.isPartial ? "扫描中途取消，结果不完整"
                      : "没有可清理的内容",
                detail: scopeEmpty ? "设置 · 清理里的四个类别开关都关着，这一轮一项都没有检查。"
                      : model.isPartial ? "第一类还没扫完就取消了，现在还不能说有没有可清理的东西。"
                      : "已勾选的类别全部检查完，没有发现可清理的条目。",
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
            Text("操作").frame(width: 52)
        }
        .font(.caption)
        .foregroundStyle(MMColor.secondaryLabel)
        .padding(.horizontal, MMGap.md)
        .frame(height: 26)
        .background(MMColor.recessedSurface)
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
        .background(MMColor.recessedSurface.opacity(0.5))
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
            summary: "已选 \(model.selectedDeletableCount) 类 · \(model.selectionPlan.sizeSummary)",
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
        let plan = model.selectionPlan
        return VStack(alignment: .leading, spacing: MMGap.md) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MMColor.destructive)
                Text("将 \(plan.groups.count) 类共 \(plan.paths.count) 项移入废纸篓？")
                    .font(.headline)
            }
            Text("合计 \(plan.sizeSummary)。移入废纸篓后仍可恢复，清空废纸篓前不会真正消失。")
                .font(.callout)
                .foregroundStyle(MMColor.secondaryLabel)

            // 确认框是删除前的最后一站：清单要一次看全，不用滚动条
            // （ScrollView 在 sheet 里会被压成零高，等于什么都没列出来）。
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                ForEach(plan.groups) { group in
                    HStack {
                        Text(group.name).font(.callout)
                        Text("\(group.paths.count) 项")
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                        Spacer()
                        Text(group.sizeSummary)
                            .font(.callout.monospaced())
                            .foregroundStyle(MMColor.secondaryLabel)
                    }
                    .padding(.vertical, MMGap.xxs)
                }
            }
            .padding(MMGap.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.recessedSurface, in: RoundedRectangle(cornerRadius: MMRadius.control))
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
                .disabled(plan.paths.isEmpty || model.isScanning || model.isCleaning)
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
            .background(MMColor.recessedSurface, in: RoundedRectangle(cornerRadius: MMRadius.control))
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
        CleanerHeaderCopy.subtitleSegments(
            isScanning: model.isScanning,
            scanningCategoryName: model.progress?.categoryName,
            categoryCount: model.categories.count,
            measuredTotal: model.measuredTotal,
            readOnlyTotal: model.readOnlyTotal,
            scannedAt: model.scannedAt,
            isPartial: model.isPartial
        ).joined(separator: " · ")
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

/// 拒绝回执的截图预演（`MM_FAILURE_FIXTURE=protected`）。
/// 内容全部由 `DeletionGuard` 现场算出来，不手写字符串 —— 截图要证明的是"用户真按下
/// 删除时看到的那几句"，抄一份措辞就等于给设计稿配了个假道具。
extension CleanerView {
    static func refusalPreview() -> [TrashFailure] {
        let home = NSHomeDirectory()
        return [home + "/Desktop", home + "/Library/Keychains/login.keychain-db",
                "/System/Library/CoreServices/Finder.app"]
            .compactMap { DeletionGuard.rejection(for: $0) }
            .map { TrashFailure(path: $0.path, message: $0.reason, code: "PROTECTED") }
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

// MARK: - 页头副标题

/// 副标题的**段序就是优先级**。`MMPageHeader` 的副标题是单行 + 中间截断
/// （`lineLimit(1)` 配 `truncationMode(.middle)`）：画面上保得住的是头与尾，被吃掉的是中段，
/// 而加长它**不报错、不换行、没有任何一条测试会红**，只多一个省略号。
///
/// 所以那两段"合起来才是能删多少"的（可释放 / 另有 N 只读）排在**最后**。P25 之前时间戳在它们后面，
/// 1000 pt 宽的窗口一掐，藏起来的正是"另有 N"那个数字——而它单独存在的理由就是
/// "只读档混进可释放里就是一个偏大的假数字"。时间挪到中段，并且不带年份（`scanTime`）：
/// 它不改变这一屏的任何决定，可整句一旦超出可用宽度，被吃掉的还是尾部那两段的**标签**。
/// **要加一段就先想位置，再想它值不值得占那几个字符，别往末尾追加。**
enum CleanerHeaderCopy {
    static func subtitleSegments(
        isScanning: Bool,
        scanningCategoryName: String?,
        categoryCount: Int,
        measuredTotal: UInt64,
        readOnlyTotal: UInt64,
        scannedAt: Date?,
        isPartial: Bool
    ) -> [String] {
        if isScanning {
            var scanning = ["正在扫描 \(scanningCategoryName ?? "")"]
            if isPartial { scanning.append("未完成") }
            return scanning
        }
        var segments = ["已扫描 \(categoryCount) 类"]
        if isPartial { segments.append("未完成") }
        if let scannedAt { segments.append(scanTime(scannedAt)) }
        segments.append("可释放 \(MMFormat.bytes(measuredTotal))")
        if readOnlyTotal > 0 {
            // 只读档没有删除入口，混进"可释放"里就是一个假数字，单独报。
            segments.append("另有 \(MMFormat.bytes(readOnlyTotal)) 只读")
        }
        return segments
    }

    /// 扫描时刻写成不带年份的短格式：中间截断先吃的是"整句超出来的那几个字符"，
    /// 而年份是这一格里最不像判据的五个。
    ///
    /// 没有放进 `MMFormat`（那里有 `dateTime`/`relative`/`duration`）：那是九个模块共用的文件，
    /// 为这一个调用点往里插十二行，代价是入库文档里指向该文件第 201 行之后的约四十处行号引用
    /// 全部要重指一遍——P21 那一轮还的就是这种债，那一轮为 11 行的搬家重指了六份文档。
    static func scanTime(_ date: Date) -> String { scanTimeFormatter.string(from: date) }

    private static let scanTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
