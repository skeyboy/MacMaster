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
    /// 怎么来到这台机器上的（只读凭据推断，见 `AppProvenance.swift`）。
    /// 载入时一次算好贴在条目上：证据是"账本 + 设备号"，与残留扫描无关，不必跟着敏感度重算。
    public let provenance: AppProvenance
    /// 这是一个 Steam 启动器型 bundle（本体只是一个 `open steam://run/<数字>` 脚本）。
    /// nil = 没成立。与 `provenance` 是**两个维度**：brew 装的启动器两句同时成立，
    /// 所以它刻意不并进 `AppProvenance.Source`（判定与合同见 `SteamLauncherProbe.swift`）。
    public let steamLauncher: SteamLauncherInfo?

    init(id: String, name: String, bundleName: String, path: String, bundleID: String, version: String,
         build: String, minSystemVersion: String, executable: String, developer: String, teamID: String,
         modificationDate: Date?, size: UInt64? = nil, fileCount: Int? = nil,
         residuals: [ResidualItem] = [], residualSize: UInt64? = nil,
         residualScanFailed: Bool = false, isSystemOwned: Bool = false,
         provenance: AppProvenance = .unknown, steamLauncher: SteamLauncherInfo? = nil) {
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
        self.provenance = provenance
        self.steamLauncher = steamLauncher
    }
}

// MARK: - 勾选与删除集合（纯函数，便于单测）

public enum UninstallSelection {

    public static func confirmationSize(appSize: UInt64?, residualSize: UInt64?,
                                        includeResiduals: Bool) -> UInt64? {
        guard let appSize else { return nil }
        guard includeResiduals else { return appSize }
        guard let residualSize else { return nil }
        let (total, overflow) = appSize.addingReportingOverflow(residualSize)
        return overflow ? nil : total
    }

    /// 删除根可能是容器父目录；成功移走父目录后，子项也已不存在。
    static func wasMoved(_ path: String, under roots: Set<String>) -> Bool {
        roots.contains { root in path == root || path.hasPrefix(root + "/") }
    }

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
    public static func selectedSize(items: [ResidualItem], selectedIDs: Set<String>) -> UInt64? {
        let allowed = items.filter { $0.risk.allowsDeletion && selectedIDs.contains($0.id) }
        let grouped = Dictionary(grouping: allowed, by: \.id)
        var total: UInt64 = 0
        for id in ResidualScanReport.nonNestedIDs(Array(grouped.keys)) {
            guard let size = grouped[id]?.compactMap(\.size).max() else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(size)
            guard !overflow else { return nil }
            total = sum
        }
        return total
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

    /// 本次会话里**我们自己**移进废纸篓的包标识。两个监听（废纸篓、应用目录）都按它抑制：
    /// 那是自己动作的回声 —— 而且「刚拖进废纸篓」这个主语在这种情况下是假的，用户没拖。
    @Published public private(set) var selfMovedBundleIDs: Set<String> = []

    /// 其中**连勾选的残留一起**移走的那些。废纸篓提示对它们没有新信息：
    /// 用户刚在确认面板里逐项勾选过残留，紧接着又收到一张「清理勾选的残留」是重复。
    /// 「仅卸载应用」不在这里——那条路径确实只带走了本体，提示有价值，只该换文案。
    @Published public private(set) var selfMovedWithResidualsBundleIDs: Set<String> = []

    /// 「仅卸载应用」那一条被我们送进废纸篓后的凭据（目的地路径 + 包标识）。
    /// 它不来自列目录：废纸篓读不动的机器上，卸载回声是这张卡唯一的来源。
    @Published public private(set) var selfEchoArrival: TrashArrival?

    /// 扫描参数注入点：单测把 home 指到临时目录，真实运行用默认值（当前用户）。
    var optionsFactory: () -> ResidualScanOptions = { ResidualScanOptions() }
    var appDirectoriesFactory: (String) -> [String] = AppScanner.defaultSearchDirectories
    /// 来源凭据的根：真实运行同时探两个 brew 前缀（不按 CPU 架构猜），
    /// 无头截图把它换成 /tmp 夹具目录。
    var provenancePrefixesFactory: (String) -> [String] = { _ in AppProvenanceScanner.defaultPrefixes() }
    /// 安装包收据目录。夹具截图下给 nil：假 home 不该去读真机的系统收据，
    /// 那样"这一档没有命中"到底是凭据缺失还是没读系统，就分不出来了。
    var provenanceReceiptsRootFactory: (String) -> String? = { _ in "/private/var/db/receipts" }
    /// 运行中快照的注入点。**只有单测改它**：取证截图走的是真启动
    /// （`Scripts/p31-running-capture.sh` 真的 `open -g` 一个 /tmp 下的夹具应用），
    /// 所以照片里那个 pid 背后确实有进程。这一处刻意不给截图留 env 钩子，理由写在
    /// `RunningAppProbe.snapshot()` 的注释上：合成值只能证明界面会写字，证明不了写的是真话。
    var runningAppsFactory: () -> [RunningAppInfo] = { RunningAppProbe.snapshot() }

    /// 每个应用上一次读到的运行状态，键是候选的 id（绝对路径）。
    /// 存着而不是每次界面刷新都现读：一次 `runningApplications` 遍历不算贵，
    /// 但不该跟着 SwiftUI 的重算跑。更新只有三个时点——载入清单（`reloadListing`）、
    /// 按下卸载/移到废纸篓打开确认面板（`requestConfirmation`）、进程启动与退出的两条通知；
    /// **换选中项不重读**（详情那一格读的是这张表里现成的值），也没有定时器。
    /// 缺席 = 还没读过，界面这时什么都不说（`.notRunning` 是一种主张，不能当默认值）。
    /// 缺席 = 还没读过，界面这时什么都不说（`.notRunning` 是一种主张，不能当默认值）。
    @Published public private(set) var runningStates: [String: AppRunningState] = [:]

    public init() {
        // 取证钩子：拍"增强/深度两档到底能说到哪一句"用得上它。写错值会回落 strict
        // 并在 stderr 留一行（`MMHookValue` 那套规矩），所以不会有"照片停在另一档而日志不说"的事。
        sensitivity = MMHookValue.selected(key: "MM_UNINSTALL_SENSITIVITY", fallback: .strict)
    }

    public var selectedApp: UninstallCandidate? {
        apps.first { $0.id == selectedAppID }
    }

    public var totalSize: UInt64 { apps.reduce(UInt64(0)) { $0 + ($1.size ?? 0) } }

    public var measuredCount: Int { apps.filter { $0.size != nil }.count }

    public var selectedResidualSize: UInt64? {
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
        await reloadListing()
        let options = optionsFactory()
        await enrich(options: ResidualScanOptions(home: options.home, systemRoot: options.systemRoot,
                                                  sensitivity: sensitivity))
    }

    /// 只重举清单与来源凭据，**不等体积测量**。
    /// 给"应用刚消失，要先把归属清单刷新"这一步用：孤儿判定的依据就是这份清单，
    /// 慢的那一半（测大小，真机几十秒）不该挡在结论前面。
    public func reloadListing() async {
        isScanningApps = true
        apps = []
        selectedAppID = nil
        selectedResidualIDs = []
        failures = []

        let options = optionsFactory()
        let directories = appDirectoriesFactory(options.home)
        let prefixes = provenancePrefixesFactory(options.home)
        let receiptsRoot = provenanceReceiptsRootFactory(options.home)
        let discovered = await Task.detached(priority: .userInitiated) {
            AppScanner.applications(in: directories)
        }.value
        // 来源识别只读账本与 bundle 的元数据（一次 stat 一条），不遍历任何应用树，
        // 所以放在测大小之前算：列表刚出来就该有 brew 徽章，而不是等几十秒。
        let provenances = await Task.detached(priority: .userInitiated) {
            Self.provenanceMap(for: discovered, prefixes: prefixes, receiptsRoot: receiptsRoot)
        }.value
        // 启动器判定和来源识别一样是"每条目一次 plist + 一两次 stat"，不遍历树，
        // 所以同样放在测大小之前：列表出来那一秒就该知道谁是启动器。
        let launchers = await Task.detached(priority: .userInitiated) {
            Self.steamLauncherMap(for: discovered)
        }.value

        apps = discovered.map {
            makeCandidate(from: $0, provenance: provenances[$0.path], steamLauncher: launchers[$0.path])
        }
        // 运行状态跟着清单一起读：这一次遍历覆盖整张列表，等测大小那几十秒过去再读，
        // 列表里那些"运行中"就已经是过期结论了。
        refreshRunningStates()
        isScanningApps = false
    }

    // MARK: 运行状态

    /// 读一次快照，给列表里每个应用算一份状态。**只读**：不启动、不结束任何进程。
    public func refreshRunningStates() {
        let snapshot = runningAppsFactory()
        var next: [String: AppRunningState] = [:]
        next.reserveCapacity(apps.count)
        for app in apps {
            next[app.id] = AppRunningState.resolve(bundleID: app.bundleID, bundlePath: app.path,
                                                   running: snapshot)
        }
        runningStates = next
    }

    /// nil = 这一份还没读过（清单载入之前、或列表里还没有它）。
    public func runningState(for app: UninstallCandidate) -> AppRunningState? {
        runningStates[app.id]
    }

    /// 路径 → 来源。纯 `unknown` 不入表：默认值就是它，没必要为 44 个应用各存一份空结构。
    /// 但"两个 cask 都声明了同一份 bundle"也是 `unknown` 却带着事实，丢了就只剩一句空白的"无法判定"。
    nonisolated private static func provenanceMap(for discovered: [DiscoveredApp],
                                                  prefixes: [String],
                                                  receiptsRoot: String?) -> [String: AppProvenance] {
        let index = AppProvenanceScanner.buildIndex(prefixes: prefixes)
        let packages = receiptsRoot.map { ReceiptOwnerIndex.identifiers(at: $0) } ?? []
        var map: [String: AppProvenance] = [:]
        for app in discovered {
            let found = AppProvenanceScanner.provenance(for: app, index: index, packageIdentifiers: packages)
            if found.source != .unknown || found.ambiguousCaskTokens.isEmpty == false {
                map[app.path] = found
            }
        }
        return map
    }

    /// 路径 → 启动器凭据。没成立的不入表（nil 就是默认值）。
    /// 成本：每个应用多一次 `Contents/Info.plist` 读取加一到两次 `lstat`，
    /// 正文只可能是启动器的形状才读（可执行且 ≤4096 字节），几十兆的 Mach-O 不会被 slurp 进内存。
    nonisolated private static func steamLauncherMap(for discovered: [DiscoveredApp])
        -> [String: SteamLauncherInfo] {
        var map: [String: SteamLauncherInfo] = [:]
        for app in discovered {
            let executable = AppScanner.stringValue(AppScanner.infoDictionary(at: app.path),
                                                    "CFBundleExecutable")
            let candidates = SteamLauncherProbe.read(appPath: app.path, bundleExecutable: executable)
            if let info = SteamLauncherProbe.resolve(candidates: candidates) {
                map[app.path] = info
            }
        }
        return map
    }

    private func makeCandidate(from app: DiscoveredApp, provenance: AppProvenance?,
                               steamLauncher: SteamLauncherInfo?) -> UninstallCandidate {
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
            isSystemOwned: AppScanner.isSystemOwned(bundleID: app.bundleID),
            provenance: provenance ?? .unknown,
            steamLauncher: steamLauncher
        )
    }

    struct EnrichedApp: Sendable {
        let id: String
        let residuals: [ResidualItem]
        let size: UInt64?
        let fileCount: Int?
        let residualSize: UInt64?
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
        return EnrichedApp(id: app.id, residuals: residuals, size: bundle.size, fileCount: bundle.fileCount,
                           residualSize: UninstallSelection.selectedSize(
                               items: residuals, selectedIDs: UninstallSelection.defaultSelectedIDs(residuals)),
                           failed: false)
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
        await move(to: paths, removing: app.id, movedResidualsToo: true)
    }

    /// 只卸载 app 本体，不动任何残留。
    public func uninstallAppOnly() async {
        guard let app = selectedApp else { return }
        await move(to: [app.path], removing: app.id, movedResidualsToo: false)
    }

    private func move(to paths: [String], removing appID: String, movedResidualsToo: Bool) async {
        let result = await FileTrashService.shared.moveToTrash(paths: paths)
        lastResult = result
        failures = result.operation.failures
        let moved = Set(result.operation.files.map(\.originalPath))
        if moved.contains(appID) {
            // 我们自己移走的那条，两个监听都不该再报：那是自己的动作的回声。
            if let app = apps.first(where: { $0.id == appID }), app.bundleID.isEmpty == false {
                let bundleID = app.bundleID
                selfMovedBundleIDs.insert(bundleID)
                if movedResidualsToo {
                    selfMovedWithResidualsBundleIDs.insert(bundleID)
                } else {
                    // 撤回后重卸（或反过来）要按最新那条路径处理，集合里不能留旧档位。
                    selfMovedWithResidualsBundleIDs.remove(bundleID)
                    // 「仅卸载应用」留下的残留没人管，那张提示卡不能等列目录的监听来发现：
                    // 本机没有「完全磁盘访问」时 `~/.Trash` 根本列不动，而卸载确实成功了。
                    if let trashPath = result.operation.files.first(where: { $0.originalPath == appID })?.trashPath {
                        selfEchoArrival = TrashArrival(selfMovedPath: trashPath, name: app.name, bundleID: bundleID)
                    }
                }
            }
            apps.removeAll { $0.id == appID }
            selectedAppID = nil
            selectedResidualIDs = []
        } else if let index = apps.firstIndex(where: { $0.id == appID }) {
            apps[index].residuals.removeAll { UninstallSelection.wasMoved($0.path, under: moved) }
            apps[index].residualSize = UninstallSelection.selectedSize(
                items: apps[index].residuals,
                selectedIDs: UninstallSelection.defaultSelectedIDs(apps[index].residuals))
            selectedResidualIDs = Set(selectedResidualIDs.filter {
                !UninstallSelection.wasMoved($0, under: moved)
            })
        }
    }

    public func undoLast() async {
        guard let operationID = lastResult?.operation.id else { return }
        let restored = await FileTrashService.shared.undo(operationID: operationID)
        undoFailures = restored.failures
        lastResult = nil
        await loadApps()
        // 撤回把本体放回应用目录了：它之后的离开就不再是我们的动作。不清这两个集合，
        // 用户真把它拖进废纸篓时那张卡还会说「你刚卸载了」—— 正是这一路要修的假主语。
        let back = Set(apps.map(\.bundleID))
        selfMovedBundleIDs.subtract(back)
        selfMovedWithResidualsBundleIDs.subtract(back)
        // 本体被我们放回应用目录了：那条回声不再是"在废纸篓里等清理"。
        selfEchoArrival = nil
    }

    /// 「忽略」这张回声卡。要清的是来源本身，只清选中项的话下一次同步又把它选回来。
    public func dismissSelfEchoArrival() {
        selfEchoArrival = nil
        selectTrashArrival(nil)
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
        let options = ResidualScanOptions(home: home,
                                          receiptsRoot: home == nil ? "/private/var/db/receipts" : nil,
                                          sensitivity: sensitivity)
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
        let moved = Set(result.operation.files.map(\.originalPath))
        orphans.removeAll { UninstallSelection.wasMoved($0.path, under: moved) }
        selectedOrphanIDs = Set(selectedOrphanIDs.filter {
            !UninstallSelection.wasMoved($0, under: moved)
        })
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

    public var selectedTrashResidualSize: UInt64? {
        guard let report = trashResidualReport else { return nil }
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
        let moved = Set(result.operation.files.map(\.originalPath))
        trashResidualReport = ResidualScanReport(
            items: report.items.filter { !UninstallSelection.wasMoved($0.path, under: moved) },
            inaccessiblePaths: report.inaccessiblePaths
        )
        selectedTrashResidualIDs = Set(selectedTrashResidualIDs.filter {
            !UninstallSelection.wasMoved($0, under: moved)
        })
    }
}
