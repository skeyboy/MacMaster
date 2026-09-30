import Foundation
import MMCore
import MMFileScanner

// MARK: - 卸载候选

/// 一个可卸载应用 + 它当前扫出来的残留。
public struct UninstallCandidate: Identifiable, Sendable {
    public let id: String          // app 的绝对路径
    public let name: String
    /// `.app` 之外的目录名，参与归一化名称匹配（`name` 可能是本地化显示名）。
    public let bundleName: String
    public let path: String
    public let bundleID: String
    public let version: String
    public let build: String
    public let minSystemVersion: String
    public let executable: String
    public let developer: String
    public let teamID: String
    public let modificationDate: Date?
    public var size: UInt64?
    public var fileCount: Int?
    public var residuals: [ResidualItem]
    /// 残留合计大小，只在互不嵌套的删除根上求和。
    public var residualSize: UInt64?
    public var residualScanFailed: Bool
    /// 系统自带应用不提供残留扫描（`com.apple.*` 的数据由系统管理）。
    public var isSystemOwned: Bool

    init(id: String, name: String, bundleName: String, path: String, bundleID: String, version: String,
         build: String, minSystemVersion: String, executable: String, developer: String, teamID: String,
         modificationDate: Date?, size: UInt64? = nil, fileCount: Int? = nil,
         residuals: [ResidualItem] = [], residualSize: UInt64? = nil,
         residualScanFailed: Bool = false, isSystemOwned: Bool = false) {
        self.id = id
        self.name = name
        self.bundleName = bundleName
        self.path = path
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.minSystemVersion = minSystemVersion
        self.executable = executable
        self.developer = developer
        self.teamID = teamID
        self.modificationDate = modificationDate
        self.size = size
        self.fileCount = fileCount
        self.residuals = residuals
        self.residualSize = residualSize
        self.residualScanFailed = residualScanFailed
        self.isSystemOwned = isSystemOwned
    }
}

// MARK: - 勾选与删除集合（纯函数，便于单测）

public enum UninstallSelection {

    /// 默认勾选只能来自 `.safe`：谨慎与只读都必须由用户明确点选。
    public static func defaultSelectedIDs(_ items: [ResidualItem]) -> Set<String> {
        Set(items.filter { $0.risk.isDefaultSelected }.map(\.id))
    }

    /// 允许出现在勾选框里的项：只读项不提供删除入口，因此也不允许被选中。
    public static func selectableIDs(_ items: [ResidualItem]) -> Set<String> {
        Set(items.filter { $0.risk.allowsDeletion }.map(\.id))
    }

    /// 真正交给 `FileTrashService` 的路径：app 本体 + 勾选项的互不嵌套删除根。
    /// 这里再挡一次只读项，即使上层状态被改坏，root 属主文件也进不了删除列表。
    public static func deletionPaths(appPath: String, items: [ResidualItem], selectedIDs: Set<String>) -> [String] {
        let allowed = items.filter { $0.risk.allowsDeletion && selectedIDs.contains($0.id) }
        let grouped = Dictionary(grouping: allowed, by: \.id)
        let roots = ResidualScanReport.nonNestedIDs(Array(grouped.keys)).compactMap { grouped[$0]?.first?.path }
        return [appPath] + roots
    }

    /// 勾选项合计大小：同一绝对路径只算一次，父目录已入选时不再累加其子项。
    public static func selectedSize(items: [ResidualItem], selectedIDs: Set<String>) -> UInt64 {
        let allowed = items.filter { $0.risk.allowsDeletion && selectedIDs.contains($0.id) }
        var sizes: [String: UInt64] = [:]
        for item in allowed { sizes[item.id] = max(sizes[item.id] ?? 0, item.size ?? 0) }
        return ResidualScanReport.nonNestedIDs(Array(sizes.keys))
            .reduce(UInt64(0)) { $0 + (sizes[$1] ?? 0) }
    }

    /// 仍属于本次扫描但没被勾选的可删项，对应设计稿"11 项默认不勾选"那枚徽章。
    public static func unselectedDeletableCount(_ items: [ResidualItem], selectedIDs: Set<String>) -> Int {
        items.filter { $0.risk.allowsDeletion && selectedIDs.contains($0.id) == false }.count
    }
}

// MARK: - 页面状态

@MainActor
public final class UninstallerModel: ObservableObject {
    @Published public var apps: [UninstallCandidate] = []
    @Published public var selectedAppID: String?
    @Published public var selectedResidualIDs: Set<String> = []
    @Published public var sensitivity: ResidualSensitivity = .strict {
        didSet {
            guard oldValue != sensitivity else { return }
            rescanSelectedApp()
            rescanTrashArrival()
        }
    }
    @Published public var isScanningApps = false
    @Published public var isMeasuring = false
    @Published public var lastResult: TrashResult?
    @Published public var failures: [TrashFailure] = []
    @Published public var undoFailures: [TrashFailure] = []

    /// 扫描参数注入点：单测把 home 指到临时目录，真实运行用默认值（当前用户）。
    var optionsFactory: () -> ResidualScanOptions = { ResidualScanOptions() }

    public init() {}

    public var selectedApp: UninstallCandidate? {
        apps.first { $0.id == selectedAppID }
    }

    public var totalSize: UInt64 { apps.reduce(UInt64(0)) { $0 + ($1.size ?? 0) } }

    public var measuredCount: Int { apps.filter { $0.size != nil }.count }

    public var selectedResidualSize: UInt64 {
        guard let app = selectedApp else { return 0 }
        return UninstallSelection.selectedSize(items: app.residuals, selectedIDs: selectedResidualIDs)
    }

    public var selectedResidualCount: Int {
        guard let app = selectedApp else { return 0 }
        return app.residuals.filter { $0.risk.allowsDeletion && selectedResidualIDs.contains($0.id) }.count
    }

    public var unselectedCount: Int {
        guard let app = selectedApp else { return 0 }
        return UninstallSelection.unselectedDeletableCount(app.residuals, selectedIDs: selectedResidualIDs)
    }

    // MARK: 载入

    public func loadApps() async {
        isScanningApps = true
        apps = []
        selectedAppID = nil
        selectedResidualIDs = []
        failures = []

        let options = optionsFactory()
        let discovered = await Task.detached(priority: .userInitiated) {
            AppScanner.applications(in: AppScanner.defaultSearchDirectories(home: options.home))
        }.value

        apps = discovered.map { makeCandidate(from: $0) }
        isScanningApps = false
        await enrich(options: ResidualScanOptions(home: options.home, systemRoot: options.systemRoot,
                                                  sensitivity: sensitivity))
    }

    private func makeCandidate(from app: DiscoveredApp) -> UninstallCandidate {
        let info = AppScanner.infoDictionary(at: app.path)
        let signature = AppScanner.signatureInfo(of: app.path)
        return UninstallCandidate(
            id: app.path,
            name: AppScanner.displayName(at: app.path, bundleName: app.bundleName),
            bundleName: app.bundleName,
            path: app.path,
            bundleID: app.bundleID,
            version: AppScanner.stringValue(info, "CFBundleShortVersionString"),
            build: AppScanner.stringValue(info, "CFBundleVersion"),
            minSystemVersion: AppScanner.stringValue(info, "LSMinimumSystemVersion"),
            executable: AppScanner.stringValue(info, "CFBundleExecutable"),
            developer: signature.developer,
            teamID: signature.teamID,
            modificationDate: AppScanner.modificationDate(of: app.path),
            isSystemOwned: AppScanner.isSystemOwned(bundleID: app.bundleID)
        )
    }

    struct EnrichedApp: Sendable {
        let id: String
        let residuals: [ResidualItem]
        let size: UInt64?
        let fileCount: Int?
        let residualSize: UInt64
        let failed: Bool
    }

    /// 后台补齐残留清单与真实占用。遍历与求和都脱离主线程，主线程只回填状态；
    /// 并发上限按核数收敛，几十个应用不能同时打满磁盘。
    private func enrich(options: ResidualScanOptions) async {
        guard apps.isEmpty == false else { return }
        isMeasuring = true
        defer { isMeasuring = false }

        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let snapshot = apps
        await withTaskGroup(of: EnrichedApp?.self) { group in
            var next = 0
            func enqueue() {
                guard next < snapshot.count else { return }
                let app = snapshot[next]
                next += 1
                if app.isSystemOwned {
                    group.addTask { await Self.measure(app: app) }
                } else {
                    group.addTask { await Self.enrich(app: app, options: options) }
                }
            }
            for _ in 0..<min(limit, snapshot.count) { enqueue() }
            while let enriched = await group.next() {
                guard let enriched else { continue }
                apply(enriched)
                enqueue()
            }
        }
    }

    /// 系统应用不扫残留，只量本体。
    nonisolated private static func measure(app: UninstallCandidate) async -> EnrichedApp {
        let metrics = await DirectoryMetrics.measure(path: app.path)
        return EnrichedApp(id: app.id, residuals: [], size: metrics.size, fileCount: metrics.fileCount,
                           residualSize: 0, failed: false)
    }

    nonisolated private static func enrich(app: UninstallCandidate, options: ResidualScanOptions) async -> EnrichedApp {
        let report = ResidualScanner.scan(appName: app.bundleName, bundleID: app.bundleID,
                                          appPath: app.path, options: options)
        var residuals = report.items
        for index in residuals.indices {
            let metrics = await DirectoryMetrics.measure(path: residuals[index].path)
            residuals[index].size = metrics.size
        }
        let bundle = await DirectoryMetrics.measure(path: app.path)
        let summary = ResidualScanReport(items: residuals, inaccessiblePaths: report.inaccessiblePaths)
        return EnrichedApp(id: app.id, residuals: residuals, size: bundle.size, fileCount: bundle.fileCount,
                           residualSize: summary.defaultSelectableSize, failed: false)
    }

    private func apply(_ enriched: EnrichedApp) {
        guard let index = apps.firstIndex(where: { $0.id == enriched.id }) else { return }
        apps[index].size = enriched.size
        apps[index].fileCount = enriched.fileCount
        apps[index].residuals = enriched.residuals
        apps[index].residualSize = enriched.residualSize
        apps[index].residualScanFailed = enriched.failed
        // 正在看的那个应用要立刻拿到新命中集合的默认勾选。
        if selectedAppID == enriched.id {
            selectedResidualIDs = UninstallSelection.defaultSelectedIDs(enriched.residuals)
        }
    }

    // MARK: 选择

    public func select(_ appID: String?) {
        guard selectedAppID != appID else { return }
        selectedAppID = appID
        guard let app = appID.flatMap({ id in apps.first { $0.id == id } }) else {
            selectedResidualIDs = []
            return
        }
        // 默认勾选只能来自 safe；谨慎与只读一律不预选。
        selectedResidualIDs = UninstallSelection.defaultSelectedIDs(app.residuals)
    }

    public func toggle(_ item: ResidualItem) {
        guard item.risk.allowsDeletion else { return }
        if selectedResidualIDs.contains(item.id) {
            selectedResidualIDs.remove(item.id)
        } else {
            selectedResidualIDs.insert(item.id)
        }
    }

    public func toggleAllDeletable() {
        guard let app = selectedApp else { return }
        let selectable = UninstallSelection.selectableIDs(app.residuals)
        if selectedResidualIDs.isSuperset(of: selectable) {
            selectedResidualIDs.subtract(selectable)
        } else {
            selectedResidualIDs.formUnion(selectable)
        }
    }

    /// 敏感度变更后重扫当前应用的残留，并重置勾选（旧勾选属于旧的命中集合）。
    public func rescanSelectedApp() {
        guard let app = selectedApp, app.isSystemOwned == false else { return }
        let base = optionsFactory()
        let options = ResidualScanOptions(home: base.home, systemRoot: base.systemRoot, sensitivity: sensitivity)
        Task { [weak self] in
            guard let self else { return }
            let enriched = await Self.enrich(app: app, options: options)
            self.apply(enriched)
        }
    }

    // MARK: 卸载

    /// app 本体 + 勾选的残留，一次进废纸篓；失败逐条回传，绝不 `try?` 吞掉。
    public func uninstallAppWithSelection() async {
        guard let app = selectedApp else { return }
        let paths = UninstallSelection.deletionPaths(appPath: app.path, items: app.residuals,
                                                     selectedIDs: selectedResidualIDs)
        await move(to: paths, removing: app.id)
    }

    /// 只卸载 app 本体，不动任何残留。
    public func uninstallAppOnly() async {
        guard let app = selectedApp else { return }
        await move(to: [app.path], removing: app.id)
    }

    private func move(to paths: [String], removing appID: String) async {
        let result = await FileTrashService.shared.moveToTrash(paths: paths)
        lastResult = result
        failures = result.operation.failures
        apps.removeAll { $0.id == appID }
        selectedAppID = nil
        selectedResidualIDs = []
    }

    public func undoLast() async {
        guard let operationID = lastResult?.operation.id else { return }
        let restored = await FileTrashService.shared.undo(operationID: operationID)
        undoFailures = restored.failures
        lastResult = nil
        await loadApps()
    }

    // MARK: - 卸载后遗症（反向扫描）

    @Published public var orphans: [OrphanCandidate] = []
    /// 反向判断的结论只是"高度可疑"，所以一律默认不勾选，由用户逐条确认。
    @Published public var selectedOrphanIDs: Set<String> = []
    @Published public var isScanningOrphans = false
    @Published public var hasScannedOrphans = false

    public var selectedOrphans: [OrphanCandidate] {
        orphans.filter { selectedOrphanIDs.contains($0.id) }
    }

    /// 只要还有一项没量到就不给合计：一个"0 字节"的总数读起来等于"这里没东西"。
    public var selectedOrphanSize: UInt64? {
        let picked = selectedOrphans
        guard !picked.isEmpty else { return 0 }
        var total: UInt64 = 0
        for item in picked {
            guard let size = item.size else { return nil }
            total += size
        }
        return total
    }

    public func toggleOrphan(_ item: OrphanCandidate) {
        if selectedOrphanIDs.contains(item.id) {
            selectedOrphanIDs.remove(item.id)
        } else {
            selectedOrphanIDs.insert(item.id)
        }
    }

    /// 扫一遍残留目录，把"本机已装应用里没有主人"的条目列出来。
    /// 大小在这一步一起量：候选通常只有几十条，量完再一次公布，
    /// 比先列一堆"测量中"再逐行变数字更不容易让人以为扫完了。
    public func scanOrphans(home: String? = nil) async {
        // 归属清单就是判定依据：应用列表还在枚举时扫，每一项都可能是错报；
        // 列表为空（读不到 /Applications）时更没有判断基础，直接不响应。
        guard isScanningApps == false, apps.isEmpty == false else { return }
        isScanningOrphans = true
        defer { isScanningOrphans = false }
        let installed = apps.map { InstalledAppIdentity(name: $0.name, bundleID: $0.bundleID) }
        let options = ResidualScanOptions(home: home, sensitivity: sensitivity)
        let found = await Task.detached(priority: .utility) {
            var items = OrphanScanner.scan(installed: installed, options: options)
            for index in items.indices {
                items[index].size = DirectoryResidualSizeMeasurer.size(of: items[index].path)
            }
            return items
        }.value
        orphans = found
        selectedOrphanIDs = []
        hasScannedOrphans = true
    }

    public func trashSelectedOrphans() async {
        let paths = selectedOrphans.map(\.path)
        guard paths.isEmpty == false else { return }
        let result = await FileTrashService.shared.moveToTrash(paths: paths)
        lastResult = result
        failures = result.operation.failures
        let removed = Set(paths)
        orphans.removeAll { removed.contains($0.path) }
        selectedOrphanIDs = []
    }

    /// 最近一次操作删的是不是 .app 本体。撤回提示的动词要跟着变：
    /// 只清残留时说"已卸载"是假话。
    public var lastOperationTrashedApps: Bool {
        lastResult?.operation.files.contains { $0.originalPath.hasSuffix(".app") } ?? false
    }

    // MARK: - 废纸篓拖入

    /// 刚进废纸篓、正被提供残留清理的那个应用。它和 `selectedApp` 是两条独立的状态线：
    /// 那条是"卸载 + 残留"，这条只有"残留" —— 本体已经在废纸篓里了。
    @Published public private(set) var trashArrival: TrashArrival?
    @Published public private(set) var trashResidualReport: ResidualScanReport?
    @Published public var selectedTrashResidualIDs: Set<String> = []
    @Published public private(set) var isScanningTrashResiduals = false
    /// "还没扫"和"扫了但没有残留"必须能分开说，后者是真的干净，前者不是。
    @Published public private(set) var hasScannedTrashResiduals = false

    /// 上一次扫描用的 home（真实机型是 nil = 当前用户；夹具截图传 /tmp 假 home）。
    /// 敏感度变更要按同一个口径重扫，不能让两次扫描用两个 home。
    private var trashScanHome: String?

    public var trashResidualItems: [ResidualItem] { trashResidualReport?.items ?? [] }

    public var selectedTrashResidualSize: UInt64 {
        guard let report = trashResidualReport else { return 0 }
        return report.selectedSize(for: selectedTrashResidualIDs)
    }

    public var selectedTrashResidualCount: Int {
        trashResidualItems.filter { $0.risk.allowsDeletion && selectedTrashResidualIDs.contains($0.id) }.count
    }

    public var unselectedTrashResidualCount: Int {
        guard let report = trashResidualReport else { return 0 }
        return UninstallSelection.unselectedDeletableCount(report.items, selectedIDs: selectedTrashResidualIDs)
    }

    /// 换目标（同一批里选了另一个应用）或目标消失时调用：旧勾选属于旧的命中集合。
    public func selectTrashArrival(_ arrival: TrashArrival?) {
        guard trashArrival?.id != arrival?.id else { return }
        trashArrival = arrival
        trashResidualReport = nil
        selectedTrashResidualIDs = []
        hasScannedTrashResiduals = false
    }

    public func toggleTrashResidual(_ item: ResidualItem) {
        guard item.risk.allowsDeletion else { return }
        if selectedTrashResidualIDs.contains(item.id) {
            selectedTrashResidualIDs.remove(item.id)
        } else {
            selectedTrashResidualIDs.insert(item.id)
        }
    }

    public func toggleAllTrashResiduals() {
        guard let report = trashResidualReport else { return }
        let selectable = UninstallSelection.selectableIDs(report.items)
        if selectedTrashResidualIDs.isSuperset(of: selectable) {
            selectedTrashResidualIDs.subtract(selectable)
        } else {
            selectedTrashResidualIDs.formUnion(selectable)
        }
    }

    public func scanTrashResiduals(home: String? = nil) async {
        guard let arrival = trashArrival, isScanningTrashResiduals == false else { return }
        trashScanHome = home
        isScanningTrashResiduals = true
        defer { isScanningTrashResiduals = false }

        let options = ResidualScanOptions(home: home, sensitivity: sensitivity)
        let report = await Task.detached(priority: .userInitiated) {
            ResidualScanner.scan(appName: arrival.name, bundleID: arrival.bundleID,
                                 appPath: arrival.path, options: options)
        }.value

        // 扫的是刚才那个目标的话，中途用户已经换过就别把结果贴错地方。
        guard trashArrival?.id == arrival.id else { return }
        trashResidualReport = report
        selectedTrashResidualIDs = UninstallSelection.defaultSelectedIDs(report.items)
        hasScannedTrashResiduals = true
    }

    private func rescanTrashArrival() {
        guard trashArrival != nil else { return }
        let home = trashScanHome
        Task { await scanTrashResiduals(home: home) }
    }

    /// 只把勾选的残留送进废纸篓。这里绝不能走 `UninstallSelection.deletionPaths`：
    /// 那个函数会把 app 本体一起加上，而本体此刻已经在废纸篓里 ——
    /// 再 trash 一次要么失败，要么把用户刚还原出来的副本又扔回去。
    public func trashSelectedTrashResiduals() async {
        guard let report = trashResidualReport else { return }
        let paths = report.deletionRoots(for: selectedTrashResidualIDs)
        guard paths.isEmpty == false else { return }
        let result = await FileTrashService.shared.moveToTrash(paths: paths)
        lastResult = result
        failures = result.operation.failures
        trashResidualReport = nil
        selectedTrashResidualIDs = []
        hasScannedTrashResiduals = false
    }
}
