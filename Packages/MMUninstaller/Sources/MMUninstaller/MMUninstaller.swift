import SwiftUI
import MMCore
import MMUI

// MARK: - 模块注册

public struct UninstallerModule: ModuleRegistrable {
    public var moduleID: String { "uninstaller" }
    public var moduleName: String { L("module.uninstaller") }
    public var moduleIcon: String { "xmark.circle" }
    public var modulePriority: Int { 2 }

    public init() {}

    public func createView() -> AnyView {
        AnyView(UninstallerView())
    }
}

// MARK: - 页面
//
// 视觉对照设计稿 `docs/design-system/screens/mmuninstaller/03-uninstaller.html`：
// 左侧应用列表 + 右侧详情（信息卡 / 键值对 / 将一并移除的残留），底部操作栏收口。
// 颜色、间距、圆角、行高一律取 MM* 令牌，不写死数值。

public struct UninstallerView: View {
    private enum ConfirmationMode {
        case appOnly, withResiduals
    }

    /// 两屏共用敏感度与废纸篓服务，但看的是相反的方向：
    /// 「已装应用」问"这个应用的文件在哪"，「卸载后遗症」问"这些文件是谁的"。
    private enum Pane: String, CaseIterable, MMHookKeyed {
        case apps, orphans
        var title: String { self == .apps ? L("ui.uninstall.pane_apps") : L("ui.uninstall.pane_orphans") }
        var hookKey: String { rawValue }
    }

    /// 仅供无头截图验证：把反向扫描的 home 换成夹具目录。
    /// 只接受 /tmp 下的路径 —— 验证钩子一旦指向真实主目录，
    /// 自动勾选 + 确认面板再被误按一次回车就是真删用户文件。
    private static var orphanFixtureHome: String? {
        guard let raw = ProcessInfo.processInfo.environment["MM_ORPHAN_FIXTURE_HOME"],
              raw.isEmpty == false else { return nil }
        guard raw.hasPrefix("/tmp/") || raw.hasPrefix("/private/tmp/") else {
            FileHandle.standardError.write(
                "MM_ORPHAN_FIXTURE_HOME=\(raw) 不在 /tmp 之下，忽略该钩子\n".data(using: .utf8)!)
            return nil
        }
        return raw
    }

    private static var confirmationFixtureHome: String? {
        guard let raw = ProcessInfo.processInfo.environment["MM_UNINSTALL_CONFIRM_FIXTURE_HOME"] else {
            return nil
        }
        guard let home = UninstallFixtureHooks.canonicalHome(raw) else {
            FileHandle.standardError.write(
                "MM_UNINSTALL_CONFIRM_FIXTURE_HOME 不是 /tmp 下的真实目录，忽略该钩子\n".data(using: .utf8)!)
            return nil
        }
        return home
    }

    /// `MM_UNINSTALL_CONFIRM_MODE` 的三档。档位名一律小写（`MMHookValue` 比较前把 env 的值转小写），
    /// 所以 `withResiduals` 与 `withresiduals` 是同一档：改前这是个 case-sensitive 的 switch，
    /// 大小写写错不会说话，只会静默变成 appOnly——面板弹出来是另一档的样子。
    private enum ConfirmHookMode: String, CaseIterable, MMHookKeyed {
        case appOnly = "apponly"
        case withResiduals = "withresiduals"
        case noPanel = "none"

        var hookKey: String { rawValue }
    }

    /// 自动打开确认面板时选哪一档；`none` = 只拍页面不拍面板（面板会盖住列表与详情）。
    /// 省略沿用旧口径 `appOnly`，那批 P1.5 截图的跑法不变。
    private static var confirmationModeToOpen: ConfirmationMode? {
        switch MMHookValue.selected(key: "MM_UNINSTALL_CONFIRM_MODE", fallback: ConfirmHookMode.appOnly) {
        case .noPanel: nil
        case .withResiduals: .withResiduals
        case .appOnly: .appOnly
        }
    }

    /// 自动走一遍消失卡的「重新载入并扫描」。合成点击进不了原生按钮，而这张卡片的终点
    /// （刷新归属清单 → 反查残留 → 切到后遗症页）不跑一次就截不到证据。
    /// 只有应用目录夹具成立时才允许 —— 那个钩子本身只认 /tmp。
    private static var autoRunDepartureScan: Bool {
        guard TrashWatcher.fixtureEnvironmentValue(key: "MM_APPS_WATCH_FIXTURE_DIR") != nil else {
            return false
        }
        return MMHookValue.flag(key: "MM_APPS_WATCH_AUTO_SCAN", token: "1")
    }

    /// 自动执行一次「仅卸载应用」，用来拍 §5 那两种自我回声文案
    /// （「你刚卸出了 X，残留还在」+「由 MacMaster 移入」）。
    /// 这两句只有我们自己的按钮能触发，而合成点击是禁用的；同时这一跑也在验证
    /// 回声抑制：我们自己移走的那个应用，不该再冒出一张「刚从应用目录消失」。
    /// 只有确认夹具成立时才允许（它会把那个应用真的移进废纸篓）。
    private static var autoUninstallForSelfEcho: Bool {
        guard confirmationFixtureHome != nil else { return false }
        return MMHookValue.flag(key: "MM_UNINSTALL_SELF_ECHO", token: "1")
    }

    /// `.task` 里要选中的那一行：`MM_UNINSTALL_SELECT` 点名优先（拍"某一档来源"用），
    /// 没点名时退回夹具 home 里的第一个应用（沿用 P1.5 那批截图的口径）。
    /// 点名点不到就什么都不选——宁可拍出一张空态，也不要悄悄换成别的应用。
    private func confirmationTarget() -> UninstallCandidate? {
        let named = ProcessInfo.processInfo.environment["MM_UNINSTALL_SELECT"]
        if let named, named.isEmpty == false {
            let hit = model.apps.first { $0.bundleName.caseInsensitiveCompare(named) == .orderedSame }
            // 点到了也留一行，而且把**点到的那一条在哪**写进去。判"外接卷那一行进了清单"不能靠
            // "日志里没有『没有对应的应用』"：真扫 `/Applications` 的耗时在本机从十几秒到两分钟
            // 以上都有（P49 同一份产物三档实测 96 s / 81 s / 126 s 才落定），还没走到这一行的那一跑，
            // 读起来与点到了完全一样——一条缺席判据在这种耗时上就是假绿。
            // 留痕成对，判据才只有一种读法。
            if let hit {
                FileHandle.standardError.write("MM_UNINSTALL_SELECT=\(named) 已点名到 \(hit.path)\n".data(using: .utf8)!)
            } else {
                FileHandle.standardError.write("MM_UNINSTALL_SELECT=\(named) 没有对应的应用\n".data(using: .utf8)!)
            }
            return hit
        }
        guard let home = Self.confirmationFixtureHome else { return nil }
        return model.apps.first { $0.path.hasPrefix(home + "/Applications/") }
    }

    /// 消费一次入站点名（`macmaster://uninstall?path=…`，见 `UninstallerOpenURL`）。
    ///
    /// 只切"看哪一个"，不做任何删除动作，也不额外改勾选——勾选仍由 `select(_:)` 按 safe 档给。
    ///
    /// 清单没就绪时**不消费**（请求继续挂在 `scanRequest` 上）：`reloadListing` 一边把
    /// `apps` 清空一边在测几十个大文件，这时候取走就等于把点名吞了，
    /// 而 `.task` 载入完成后那一次调用才是它能被找到的第一个时刻。
    private func applyScanRequestIfNeeded() {
        guard model.isScanningApps == false, model.apps.isEmpty == false else { return }
        let paths = scanRequest.consume()
        guard paths.isEmpty == false else { return }
        // 点名只在「已装应用」那一屏有意义，先把人带到能看见的地方。
        pane = .apps
        if model.focusInbound(paths: paths) == nil {
            FileHandle.standardError.write("入站点名的 bundle 不在应用清单里：\(paths.joined(separator: "、"))\n"
                .data(using: .utf8)!)
        }
    }

    @StateObject private var model = UninstallerModel()
    /// 入站 URL 的待办点名。用进程级那一份而不是本视图的状态：URL 到得比视图建起来早
    /// （冷启动、从别的页跳转），见 `UninstallerScanRequest`。
    @ObservedObject private var scanRequest = UninstallerScanRequest.shared
    @StateObject private var trashWatcher = TrashWatcher()
    @StateObject private var appWatcher = AppFolderWatcher()
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchText = ""
    @State private var showConfirm = false
    @State private var confirmationMode: ConfirmationMode = .withResiduals
    @State private var showOrphanConfirm = false
    @State private var showTrashConfirm = false
    /// 消失提示当前展示的那一条。它和 `appWatcher.departures` 是两回事：
    /// 清单里可以有好几条历史，而"正在提示的"只能有一条，且用户点了忽略就不再回来。
    @State private var shownDeparture: AppDeparture?
    @State private var dismissedDepartureIDs: Set<String> = []
    /// 「重新载入并扫描」正在跑：这一步是两次串行工作（刷新归属清单 + 扫全部残留根），
    /// 在它返回之前不给任何数字，也不让用户重复点。
    @State private var isRunningDepartureScan = false
    /// 自动执行钩子只跑一次：它由"出现了一条消失提示"触发，而那条提示之后还会因
    /// 废纸篓清单变化被重新算好几次。
    @State private var didAutoRunDepartureScan = false
    @State private var toastSeconds = 0
    @State private var pane: Pane = MMHookValue.selected(key: "MM_UNINSTALL_PANE", fallback: .apps)

    public init() {}

    private var filteredApps: [UninstallCandidate] {
        guard searchText.isEmpty == false else { return model.apps }
        return model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            MMPageHeader(L("module.uninstaller"), subtitle: headerSubtitle) {
                Picker(L("ui.uninstall.view"), selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(L("ui.uninstall.pane_help"))

                Picker(L("ui.uninstall.sensitivity"), selection: $model.sensitivity) {
                    ForEach(ResidualSensitivity.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(LF("ui.uninstall.sensitivity_help", model.sensitivity.note))

                Button {
                    Task { await model.loadApps() }
                } label: {
                    Label(L("ui.action.reload"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanningApps)
            }

            appsWatchRegion

            trashRegion

            HStack(spacing: 0) {
                if pane == .apps {
                    appList
                        .frame(width: MMMetric.inspector)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    orphanPane
                }
            }
            .frame(maxHeight: .infinity)

            if model.failures.isEmpty == false {
                MMFailurePanel(summary: failureSummary, model.failures) {
                    model.failures = []
                }
            }

            if model.undoFailures.isEmpty == false {
                MMFailurePanel(model.undoFailures) {
                    model.undoFailures = []
                }
            }

            Divider()
            Group {
                if pane == .apps {
                    actionBar
                } else {
                    orphanActionBar
                }
            }
        }
        .onAppear {
            // 监听不能排在 `.task` 里 `await model.loadApps()` 之后：应用列表要测几十个大文件
            // 才算得完，那样废纸篓要等几分钟才开始看，第一条拖入还会被当成基线漏掉。
            startTrashWatching()
            startAppWatching()
        }
        .task {
            if let home = Self.confirmationFixtureHome {
                model.optionsFactory = { ResidualScanOptions(home: home) }
                model.appDirectoriesFactory = { _ in [home + "/Applications"] }
                // 假 home 配假账本：让来源去读真机的 /opt/homebrew，
                // 拍出来的表里每一行"brew 装的"都和画面里那个假应用无关。
                model.provenancePrefixesFactory = { _ in [home + "/.homebrew"] }
                model.provenanceReceiptsRootFactory = { _ in nil }
            }
            if model.apps.isEmpty, model.isScanningApps == false {
                await model.loadApps()
            }
            if let target = self.confirmationTarget() {
                model.select(target.id)
                // 确认面板只有夹具目录成立时才自动打开；`MM_UNINSTALL_CONFIRM_MODE=none`
                // 用来只拍列表与详情（面板会盖住它们）。
                if Self.confirmationFixtureHome != nil, let mode = Self.confirmationModeToOpen {
                    requestConfirmation(mode)
                }
                if Self.autoUninstallForSelfEcho {
                    // 走按钮走的同一条路：`move()` 会记下包标识，两张卡都按它处理。
                    await model.uninstallAppOnly()
                }
            }
            // 启动就落在「卸载后遗症」时 onChange(of: pane) 不会触发，这里补一次。
            startOrphanScanIfNeeded()
            // 点名也可能在清单还没建起来时就到了（冷启动那条时序），这里补消费一次。
            applyScanRequestIfNeeded()
        }
        .onChange(of: scanRequest.paths) { _, _ in
            applyScanRequestIfNeeded()
        }
        .onDisappear {
            trashWatcher.stop()
            appWatcher.stop()
        }
        .task(id: toastSeconds) {
            guard toastSeconds > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            toastSeconds -= 1
        }
        .onChange(of: model.selectedAppID) { _, newValue in
            model.select(newValue)
        }
        .onChange(of: model.lastResult?.operation.id) { _, newValue in
            guard newValue != nil else { return }
            toastSeconds = (model.lastResult?.successCount ?? 0) > 0 ? 15 : 0
        }
        .sheet(isPresented: $showConfirm) { confirmSheet }
        .sheet(isPresented: $showOrphanConfirm) { orphanConfirmSheet }
        .sheet(isPresented: $showTrashConfirm) { trashConfirmSheet }
        .onChange(of: trashWatcher.arrivals) { _, arrivals in
            syncTrashNotice(with: arrivals)
            // 双向都要同步：拖进废纸篓让消失卡让位，从废纸篓里彻底删掉又把它请回来。
            syncDepartureNotice(with: appWatcher.departures)
        }
        .onChange(of: appWatcher.departures) { _, departures in
            syncDepartureNotice(with: departures)
        }
        .onChange(of: model.selfMovedBundleIDs) { _, _ in
            syncDepartureNotice(with: appWatcher.departures)
            // 同一次卸载既写回声抑制集合、也写下我们自己那条废纸篓凭据。
            // 监听读不动废纸篓时不会再有别的触发点，卡片只能在这里被同步出来。
            syncTrashNotice(with: trashWatcher.arrivals)
        }
        .onChange(of: settings.watchAppFolderChanges) { _, enabled in
            if enabled {
                appWatcher.start()
                syncDepartureNotice(with: appWatcher.departures)
            } else {
                appWatcher.stop()
                shownDeparture = nil
            }
        }
        .onChange(of: settings.watchTrashForResidualCleanup) { _, enabled in
            if enabled {
                trashWatcher.start()
            } else {
                trashWatcher.stop()
                model.selectTrashArrival(nil)
            }
        }
        .onChange(of: pane) { _, newValue in
            guard newValue == .orphans else { return }
            startOrphanScanIfNeeded()
        }
        // 应用列表还在枚举时反查会错报，这里等它扫完再补一次。
        .onChange(of: model.isScanningApps) { _, scanning in
            guard scanning == false else { return }
            startOrphanScanIfNeeded()
        }
        // 运行状态是这一页唯一会自己变的字段（其余字段都靠重新载入），所以它配两条通知：
        // 用户在这里卸哪个应用，往往就是刚刚才把它打开或退出的那一个。
        // 启动那一条只覆盖**连上窗口服务**的应用（P31a 实测：纯命令行、不初始化
        // NSApplication 的进程会进 `runningApplications`，却不发这条通知）。这不是漏检
        // 的窟窿，只是取证夹具必须写成 Cocoa 应用的原因——见 `Scripts/p31-running-fixture.sh`。
        .onReceive(NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            model.refreshRunningStates()
        }
        .onReceive(NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            model.refreshRunningStates()
        }
        .overlay(alignment: .bottom) {
            if let result = model.lastResult, result.successCount > 0, toastSeconds > 0 {
                MMUndoToast(
                    message: LF(model.lastOperationTrashedApps ? "ui.uninstall.toast_uninstalled"
                                                               : "ui.uninstall.toast_trashed",
                                MMFormat.count(result.successCount)),
                    detail: MMFormat.bytes(result.totalSize),
                    secondsRemaining: toastSeconds,
                    onUndo: { Task { await model.undoLast() } },
                    onRevealTrash: { MMReveal.open(NSHomeDirectory() + "/.Trash") }
                )
                .padding(.bottom, MMMetric.actionBar + MMGap.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toastSeconds)
    }

    private var headerSubtitle: String {
        var line = LF("ui.uninstall.app_count", MMFormat.count(model.apps.count))
        if model.isMeasuring || model.measuredCount < model.apps.count {
            line += LF("ui.uninstall.subtitle_measuring",
                       MMFormat.count(model.measuredCount),
                       MMFormat.count(model.apps.count - model.measuredCount))
        } else if model.apps.isEmpty == false {
            line += LF("ui.uninstall.subtitle_measured", MMFormat.bytes(model.totalSize))
        }
        return line
    }

    private var failureSummary: String? {
        let freed = model.lastResult?.totalSize ?? 0
        return freed > 0 ? LF("ui.uninstall.recovered", MMFormat.bytes(freed)) : nil
    }

    // MARK: 左侧应用列表

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(MMColor.secondaryLabel)
                TextField(L("ui.uninstall.search_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, MMGap.md)
            .frame(height: MMMetric.rowCompact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.recessedSurface)
            .overlay(alignment: .bottom) { Divider() }

            if model.isScanningApps {
                VStack(spacing: MMGap.md) {
                    ProgressView().controlSize(.small)
                    Text(L("ui.uninstall.scanning_apps")).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                MMEmptyState(systemImage: "app.dashed",
                             title: searchText.isEmpty ? L("ui.uninstall.empty_title")
                                                       : L("ui.uninstall.empty_filtered_title"),
                             detail: searchText.isEmpty ? L("ui.uninstall.empty_detail")
                                                        : L("ui.uninstall.empty_filtered_detail"))
            } else {
                List(selection: Binding(
                    get: { model.selectedAppID },
                    set: { model.selectedAppID = $0 }
                )) {
                    ForEach(filteredApps) { app in
                        AppListRow(app: app,
                                   goneFromDirectory: appWatcher.departures.contains { $0.path == app.path },
                                   runningState: model.runningState(for: app))
                            .tag(app.id)
                            .contextMenu {
                                Button {
                                    MMReveal.open(app.path)
                                } label: {
                                    Label(L("ui.action.reveal_folder"), systemImage: "folder")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }

            Divider()
            HStack(spacing: MMGap.xs) {
                Text(listFooter)
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                // 不自动刷新是有意的：这张表是用户正在看的，悄悄换行会把他选中的那个换掉。
                // 但"没刷新"必须说出来，否则旧快照看着就像实时视图。
                if isListingStale {
                    Text(L("ui.uninstall.listing_stale"))
                        .font(.caption)
                        .foregroundStyle(MMColor.caution)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MMGap.md)
            .padding(.vertical, MMGap.xs)
        }
        .frame(maxHeight: .infinity)
        .background(MMColor.contentBackground)
    }

    private var listFooter: String {
        let measured = model.measuredCount
        let pending = model.apps.count - measured
        var line = LF("ui.uninstall.list_footer",
                      MMFormat.count(model.apps.count), MMFormat.count(measured))
        if pending > 0 { line += LF("ui.uninstall.pending_suffix", MMFormat.count(pending)) }
        return line
    }

    /// 监听观察到了目录变化、而清单还停在载入时的那一帧。
    /// 这只说"对不上"，不说哪个应用装了或卸了 —— 那要重新载入之后才知道。
    private var isListingStale: Bool {
        guard settings.watchAppFolderChanges, appWatcher.status == .watching else { return false }
        return appWatcher.departures.isEmpty == false || appWatcher.appearances.isEmpty == false
    }

    // MARK: 右侧详情

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            AppDetailView(
                app: app,
                selectedIDs: $model.selectedResidualIDs,
                unselectedCount: model.unselectedCount,
                runningState: model.runningState(for: app),
                onToggle: { model.toggle($0) },
                onToggleAll: { model.toggleAllDeletable() },
                onUninstallWithResiduals: { requestConfirmation(.withResiduals) },
                onUninstallAppOnly: { requestConfirmation(.appOnly) }
            )
        } else {
            MMEmptyState(
                systemImage: "app.dashed",
                title: L("ui.uninstall.no_app_selected"),
                detail: L("ui.uninstall.no_app_selected_detail")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MMColor.contentBackground)
        }
    }

    // MARK: 底部操作栏

    private var actionBar: some View {
        MMActionBar(
            summary: LF("ui.uninstall.selected_residuals",
                        MMFormat.count(model.selectedResidualCount),
                        MMFormat.bytes(model.selectedResidualSize)),
            note: L("ui.uninstall.unselected_untouched"),
            trailing: {
                // 本体只读时这两个按钮一起收掉，和详情面板同一口径：只读档说的是"不提供删除入口"，
                // 留两个点了没反应的按钮就是死控件（`requestConfirmation` 那道 guard 只是兜底，
                // 不是给用户按的）。`selectedApp == nil` 仍然走 `.disabled`，那一档按钮要留着，
                // 否则选中一个应用之前这一格是空的。
                if model.selectedApp?.bodyDeletable != false {
                    Button(L("ui.uninstall.app_only_button")) {
                        requestConfirmation(.appOnly)
                    }
                    .disabled(model.selectedApp == nil)

                    Button(role: .destructive) {
                        requestConfirmation(.withResiduals)
                    } label: {
                        Label(L("ui.action.move_to_trash"), systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MMColor.destructive)
                    .disabled(model.selectedApp == nil)
                }
            }
        )
    }

    // MARK: 卸载后遗症

    /// 切到「卸载后遗症」就自动反查一次，用户不必先按按钮再等一屏空白。
    /// 带夹具目录时（仅截图验证）再把结果全部勾上并打开确认面板：
    /// 合成点击进不了勾选框，没有别的办法截到确认态。
    private func startOrphanScanIfNeeded() {
        guard pane == .orphans else { return }
        guard model.hasScannedOrphans == false, model.isScanningOrphans == false else { return }
        Task { await runOrphanScan() }
    }

    private func runOrphanScan() async {
        let fixtureHome = Self.orphanFixtureHome
        // `scanOrphans` 在"应用清单还在枚举"或"清单为空"时**静默 return**（`UninstallerModel.swift:490`）。
        // 旧写法在这之后无条件写一行"已用夹具目录… 自动勾选并打开确认面板"，于是扫描根本没跑时
        // 日志也是绿的——取证脚本自己造了一条假凭据（P6.7 夹具审计查出）。这里先把同一个前置条件
        // 判一遍：不满足就点名退出、不打开面板。只在给了夹具 home 时判，真机那趟自动扫描行为不变。
        if fixtureHome != nil, model.isScanningApps || model.apps.isEmpty {
            FileHandle.standardError.write(
                "孤儿夹具扫描**没有执行**：应用清单还在枚举或为空（isScanningApps=\(model.isScanningApps), apps=\(model.apps.count)），未勾选、确认面板未打开\n"
                    .data(using: .utf8)!)
            return
        }
        await model.scanOrphans(home: fixtureHome)
        guard let fixtureHome else { return }
        model.selectedOrphanIDs = Set(model.orphans.map(\.id))
        showOrphanConfirm = true
        // 把条数写进日志：这行从此是一个**可核对的断言**（照片里应当正好有这么多行），
        // 而不是一句"我跑了"的自报。0 条也照写，空面板与没扫描是两件事。
        FileHandle.standardError.write("已用夹具目录 \(fixtureHome) 自动勾选并打开确认面板（\(model.orphans.count) 条）\n".data(using: .utf8)!)
    }

    private var orphanPane: some View {
        Group {
            if model.isScanningOrphans {
                VStack(spacing: MMGap.md) {
                    ProgressView().controlSize(.small)
                    Text(L("ui.orphan.scanning"))
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.orphans.isEmpty {
                MMEmptyState(
                    systemImage: "questionmark.folder",
                    title: model.hasScannedOrphans ? L("ui.orphan.empty_title") : L("ui.orphan.none_title"),
                    detail: model.hasScannedOrphans
                        ? L("ui.orphan.empty_detail")
                        : L("ui.orphan.none_detail")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.orphans) { item in
                            OrphanRow(
                                item: item,
                                isSelected: orphanBinding(item),
                                onToggle: { model.toggleOrphan(item) }
                            )
                            Divider()
                        }
                    }
                    .padding(.horizontal, MMGap.lg)
                    .padding(.vertical, MMGap.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MMColor.contentBackground)
    }

    private func orphanBinding(_ item: OrphanCandidate) -> Binding<Bool> {
        Binding(
            get: { model.selectedOrphanIDs.contains(item.id) },
            set: { on in
                if on { model.selectedOrphanIDs.insert(item.id) } else { model.selectedOrphanIDs.remove(item.id) }
            }
        )
    }

    /// 没扫过就不能写"0 项"：那读起来等于"这里干净"，而真相是还没看过。
    private var orphanSummary: String {
        if model.isScanningOrphans { return L("ui.orphan.scanning") }
        guard model.hasScannedOrphans else { return L("ui.orphan.none_summary") }
        return LF("ui.orphan.summary", MMFormat.count(model.orphans.count),
                  MMFormat.count(model.selectedOrphanIDs.count), MMFormat.bytes(model.selectedOrphanSize))
    }

    private var orphanActionBar: some View {
        MMActionBar(
            summary: orphanSummary,
            note: model.hasScannedOrphans ? L("ui.orphan.note_scanned") : L("ui.orphan.note_unscanned"),
            trailing: {
                Button {
                    Task { await model.scanOrphans() }
                } label: {
                    Label(model.hasScannedOrphans ? L("ui.orphan.rescan") : L("ui.orphan.scan"),
                          systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanningOrphans)

                Button(role: .destructive) {
                    showOrphanConfirm = true
                } label: {
                    Label(L("ui.action.move_to_trash"), systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .disabled(model.selectedOrphanIDs.isEmpty || model.isScanningOrphans)
            }
        )
    }

    private var orphanConfirmSheet: some View {
        let picked = model.selectedOrphans
        return VStack(alignment: .leading, spacing: MMGap.md) {
            Text(LF("ui.orphan.confirm_title", MMFormat.count(picked.count)))
                .font(.title3.weight(.semibold))
            Text(L("ui.orphan.confirm_body"))
                .font(.callout)
                .foregroundStyle(MMColor.secondaryLabel)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(picked) { item in
                    HStack(spacing: MMGap.sm) {
                        Image(systemName: item.category.icon)
                            .foregroundStyle(MMColor.caution)
                            .frame(width: MMGap.xxl)
                        Text(item.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: MMGap.sm)
                        Text(MMFormat.bytes(item.size))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MMColor.secondaryLabel)
                    }
                    .padding(.horizontal, MMGap.md)
                    .frame(height: MMMetric.rowCompact)
                    Divider()
                }
            }
            .background(MMColor.recessedSurface)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.control).stroke(MMColor.separator))

            HStack {
                Spacer()
                Button(L("ui.action.cancel")) { showOrphanConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button(L("ui.action.put_in_trash")) {
                    showOrphanConfirm = false
                    Task { await model.trashSelectedOrphans() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MMGap.lg)
        .frame(width: 480)
    }

    // MARK: 确认

    private func requestConfirmation(_ mode: ConfirmationMode) {
        // 本体只读（系统自带应用）不进这一屏：详情面板已经不给它按钮了，
        // 而 `MM_UNINSTALL_CONFIRM_MODE` 那条自动打开面板的夹具路径会绕过按钮。
        guard model.selectedApp?.bodyDeletable == true else { return }
        // 删除前的最后一次读。进程在页面打开这段时间里起落过，
        // 面板要说的是按下按钮这一刻的状态，不是载入清单那一帧的。
        model.refreshRunningStates()
        confirmationMode = mode
        showConfirm = true
    }

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            Text(L("ui.uninstall.confirm_title"))
                .font(.title3.weight(.semibold))

            if let app = model.selectedApp {
                let includeResiduals = confirmationMode == .withResiduals
                let paths = includeResiduals
                    ? UninstallSelection.deletionPaths(appPath: app.path, bodyDeletable: app.bodyDeletable,
                                                       items: app.residuals,
                                                       selectedIDs: model.selectedResidualIDs)
                    : [app.path]
                let residualSize = includeResiduals ? model.selectedResidualSize : 0
                VStack(alignment: .leading, spacing: MMGap.xs) {
                    MMKeyRow(L("ui.field.app"), app.name)
                    MMKeyRow(L("ui.field.source"), app.sourceValue)
                    MMKeyRow(L("ui.field.bundle_id"), app.bundleID, monospaced: true)
                    MMKeyRow(L("ui.field.body"), MMFormat.bytes(app.size))
                    MMKeyRow(L("ui.field.residuals"), includeResiduals
                        ? LF("ui.uninstall.confirm_residual_row",
                             MMFormat.count(paths.count - 1), MMFormat.bytes(residualSize))
                        : L("ui.uninstall.confirm_kept"))
                    MMKeyRow(L("ui.field.total"), MMFormat.bytes(UninstallSelection.confirmationSize(
                        appSize: app.size, residualSize: residualSize, includeResiduals: includeResiduals)))
                }

                // brew 装的应用被拖进废纸篓，账本不会同步——这句话说在动手之前，
                // 因为做完之后没人会想起来。这里仍然只有废纸篓一条路径，不新增执行能力。
                if let warning = app.sourceWarning {
                    cautionNotice(warning)
                }

                // 运行中排在同一格：这一屏是删除前的最后一站，而"移到废纸篓不会让它退出"
                // 是一件做完之后才会发现的事。它不给按钮加禁用——不代杀，也就不拦人。
                runningNotice(app, model.runningState(for: app))

                ScrollView {
                    VStack(alignment: .leading, spacing: MMGap.xs) {
                        ForEach(paths, id: \.self) { path in
                            Text(path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(path)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(CGFloat(paths.count) * 24, 168))

                Text(includeResiduals
                     ? L("ui.uninstall.confirm_note_with_residuals")
                     : L("ui.uninstall.confirm_note_app_only"))
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            HStack(spacing: MMGap.sm) {
                Spacer()
                Button(L("ui.action.cancel")) { showConfirm = false }
                Button(confirmationMode == .appOnly ? L("ui.uninstall.app_only_button")
                                                    : L("ui.uninstall.uninstall_button"),
                       role: .destructive) {
                    showConfirm = false
                    if confirmationMode == .appOnly {
                        Task { await model.uninstallAppOnly() }
                    } else {
                        Task { await model.uninstallAppWithSelection() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
            }
        }
        .padding(MMGap.lg)
        .frame(width: 420)
    }

    /// 确认面板顶上的橙色提醒块。来源与运行状态两句共用一个版式：
    /// 同一屏里两种"做完之后才发现"的事，不该长得不一样。
    private func cautionNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: MMGap.sm) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(MMColor.caution)
            Text(text)
                .font(.caption)
                .foregroundStyle(MMColor.caution)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MMGap.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.caution, 0.10),
                    in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
    }

    /// 确认面板里的运行状态提醒。只在真的对上进程时才出现：
    /// "没检测到"与"无法判定"在详情页已经说过了，这一屏不给它们占地方。
    @ViewBuilder
    private func runningNotice(_ app: UninstallCandidate, _ state: AppRunningState?) -> some View {
        if let state, let warning = app.runningWarning(state) {
            cautionNotice(warning)
        }
    }

    // MARK: 废纸篓提示

    /// 无头截图用的假 home。规矩沿用 `MM_ORPHAN_FIXTURE_HOME`：只认 /tmp 之下，
    /// 因为这张卡片的终点是删除按钮。
    private static var trashScanHome: String? { TrashWatcher.fixtureScanHome() }

    /// 只认 /tmp 假 home：合成点击进不了原生勾选框，截图验证确认态只能靠钩子自动打开，
    /// 而那必须只在夹具目录成立时才允许。
    private static var trashConfirmHook: Bool {
        guard TrashWatcher.fixtureScanHome() != nil else { return false }
        return MMHookValue.flag(key: "MM_SHOW_TRASH_CONFIRM", token: "1")
    }

    private func startTrashWatching() {
        guard settings.watchTrashForResidualCleanup else { return }
        trashWatcher.start()
        syncTrashNotice(with: trashWatcher.arrivals)
    }

    /// 监听端的清单是真相源：选中项不在清单里了（用户把它还原或彻底删除）就整块撤掉提示。
    /// 还原回去的应用残留是活的，这时候再挂着"清理残留"入口就是害人的。
    ///
    /// 「带残留卸载」那条路也在这里过滤掉：用户刚在确认面板里逐项勾选过残留，
    /// 紧接着再收到一张「清理勾选的残留」是重复提示（`docs/analysis/apps-watch.md` §5）。
    /// 「仅卸载应用」不在这里过滤 —— 那条路径确实留下了没人管的残留，只是主语要换。
    private func syncTrashNotice(with arrivals: [TrashArrival]) {
        let candidates = arrivals.filter {
            model.selfMovedWithResidualsBundleIDs.contains($0.bundleID) == false
        }
        // 监听读得到废纸篓时以它为准（还原、清空都会让条目从清单里消失）。
        // 只有它读不动的时候，才退回我们自己那条卸载凭据。
        let echoFallback = trashWatcher.status == .watching ? nil : model.selfEchoArrival
        if let current = model.trashArrival,
           candidates.contains(where: { $0.id == current.id }) || current.id == echoFallback?.id { return }
        guard let chosen = candidates.last ?? echoFallback else {
            model.selectTrashArrival(nil)
            return
        }
        model.selectTrashArrival(chosen)
        Task {
            await model.scanTrashResiduals(home: Self.trashScanHome)
            if Self.trashConfirmHook { showTrashConfirm = true }
        }
    }

    /// 这张卡是**我们自己的卸载按钮**造成的。那时候「刚拖进废纸篓」的主语是假的 ——
    /// 用户没拖。徽章要说谁干的，标题要用第二人称。
    /// 读 `selfEchoArrival` 兜底：卸载刚完成、同步还没跑的那一帧里 `trashArrival` 还是空的，
    /// 慢半拍就会闪出一句「刚拖进废纸篓：」——主语错一句话比空一帧贵。
    private var isSelfEchoTrashArrival: Bool {
        guard let bundleID = (model.trashArrival ?? model.selfEchoArrival)?.bundleID,
              bundleID.isEmpty == false else { return false }
        return model.selfMovedBundleIDs.contains(bundleID)
    }

    // MARK: 应用目录监听提示

    private func startAppWatching() {
        guard settings.watchAppFolderChanges else { return }
        appWatcher.start()
        syncDepartureNotice(with: appWatcher.departures)
    }

    /// 三条不报消失的规则，缺一不可：
    /// ① 用户点过「忽略」的不再回来；
    /// ② 本次会话里我们自己移走的 —— 那是自己动作的回声；
    /// ③ 包标识命中 P1.5 废纸篓清单时**让位**：拖进废纸篓会同时触发两个监听，
    ///    而废纸篓那条更强（本体还在、能还原，而且动词是真的「拖」）。
    ///    在废纸篓里被"立即删除"后 `arrivals` 会把它过滤掉，这张卡就该重新出现。
    private func syncDepartureNotice(with departures: [AppDeparture]) {
        let visible = departures.filter { departure in
            guard dismissedDepartureIDs.contains(departure.id) == false else { return false }
            guard model.selfMovedBundleIDs.contains(departure.bundleID) == false else { return false }
            return trashWatcher.arrivals.contains { $0.bundleID == departure.bundleID } == false
        }
        // 正在展示的这条仍然成立就不换：换卡会被读成"又消失了一个"。
        if let shown = shownDeparture, visible.contains(where: { $0.id == shown.id }) { return }
        shownDeparture = visible.last
        if shownDeparture != nil, Self.autoRunDepartureScan, didAutoRunDepartureScan == false {
            didAutoRunDepartureScan = true
            reloadListingAndScan()
        }
    }

    private func dismissDeparture(_ departure: AppDeparture) {
        dismissedDepartureIDs.insert(departure.id)
        shownDeparture = nil
        syncDepartureNotice(with: appWatcher.departures)
    }

    /// 两个动作都必须**先把归属清单刷新**：孤儿判定的依据就是这份清单
    /// （`OrphanScanner` 拿 `model.apps` 当主人集合）。停在旧快照上扫，
    /// 刚消失的那个应用还在清单里，它自己的残留会被判成"有主人"——
    /// 恰好漏掉我们正要提示的那几项。所以这里不是"扫一下看看"。
    private func reloadListingOnly() {
        guard isRunningDepartureScan == false else { return }
        isRunningDepartureScan = true
        Task {
            await model.reloadListing()
            isRunningDepartureScan = false
            resolveWatchNotices()
        }
    }

    private func reloadListingAndScan() {
        guard isRunningDepartureScan == false else { return }
        isRunningDepartureScan = true
        Task {
            await model.reloadListing()
            await runOrphanScan()
            isRunningDepartureScan = false
            resolveWatchNotices()
            pane = .orphans
        }
    }

    /// 清单一旦重新反映了磁盘，两张提示的使命就完成了。
    private func resolveWatchNotices() {
        appWatcher.dismiss()
        shownDeparture = nil
    }

    @ViewBuilder
    private var appsWatchRegion: some View {
        if settings.watchAppFolderChanges == false {
            // 与废纸篓那一路同一条规矩：设置页已经说过"关掉了"，这里不再复述一遍。
            EmptyView()
        } else {
            if pane == .apps, let departure = shownDeparture {
                appsDepartureCard(departure)
            }
            if pane == .apps, appWatcher.appearances.isEmpty == false {
                appsArrivalStrip
            }
            appsSkippedNote
            if case .unreadable(let reason, let needsFullDiskAccess) = appWatcher.status {
                MMPermissionBanner(
                    title: needsFullDiskAccess ? L("ui.watch.banner_unreadable") : L("ui.watch.banner_busy"),
                    detail: reason + " " + (needsFullDiskAccess
                        ? L("ui.watch.banner_clause_fdsa")
                        : L("ui.watch.banner_clause_other"))
                    + " " + L("ui.watch.banner_tail"),
                    settingsPane: needsFullDiskAccess ? .fullDiskAccess : nil
                )
            }
        }
    }

    private func appsDepartureCard(_ departure: AppDeparture) -> some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "xmark.app").foregroundStyle(MMColor.accent)
                Text(LF("ui.watch.departure_title", departure.name))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                MMBadge(L("ui.watch.departure_badge"), tint: MMColor.informational, systemImage: "xmark.app")
                Spacer(minLength: MMGap.sm)
                Button(L("ui.action.dismiss")) { dismissDeparture(departure) }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }

            HStack(spacing: MMGap.xs) {
                Text(ResidualCollector.display(departure.path, home: NSHomeDirectory()))
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·").foregroundStyle(MMColor.tertiaryLabel)
                Text(departure.bundleID.isEmpty ? L("ui.watch.no_bundle_id") : departure.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·").foregroundStyle(MMColor.tertiaryLabel)
                Text(L("ui.watch.last_known_location"))
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .fixedSize()
            }

            if isRunningDepartureScan {
                HStack(spacing: MMGap.sm) {
                    ProgressView().controlSize(.small)
                    Text(L("ui.watch.relisting")).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                }
            } else {
                Text(L("ui.watch.departure_explain"))
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            HStack(spacing: MMGap.sm) {
                Text(isRunningDepartureScan ? L("ui.watch.departure_scanning")
                                            : L("ui.watch.departure_unscanned"))
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                Spacer(minLength: MMGap.sm)
                Button {
                    reloadListingOnly()
                } label: {
                    Label(L("ui.watch.reload_listing_only"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(isRunningDepartureScan || model.isScanningApps)

                Button {
                    reloadListingAndScan()
                } label: {
                    Label(L("ui.watch.reload_and_scan"), systemImage: "list.bullet.below.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRunningDepartureScan || model.isScanningApps)
            }
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.informational, 0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 反向问题：目录里多了条目。这里**没有删除按钮、也不内嵌残留清单** ——
    /// "刚装好"和"该清理"之间没有因果关系，把两张卡画成一个样就是在暗示一个不存在的结论。
    private var appsArrivalStrip: some View {
        let appearances = appWatcher.appearances
        return VStack(alignment: .leading, spacing: MMGap.xs) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "plus.circle").foregroundStyle(MMColor.informational)
                Text(LF("ui.watch.arrival_title", MMFormat.count(appearances.count)))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                MMBadge(L("ui.watch.stale_badge"), tint: MMColor.informational, systemImage: "arrow.clockwise")
                Spacer(minLength: MMGap.sm)
                Button {
                    Task {
                        await model.loadApps()
                        appWatcher.dismissAppearances()
                    }
                } label: {
                    Label(L("ui.action.reload"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(model.isScanningApps || isRunningDepartureScan)

                Button(L("ui.action.dismiss")) { appWatcher.dismissAppearances() }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }

            Text(appearances.map(\.entry).joined(separator: "  ·  "))
                .font(.caption.monospaced())
                .foregroundStyle(MMColor.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(L("ui.watch.arrival_note"))
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.informational, 0.05))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 没监起来的目录。`~/Applications` 不存在是常态，所以它**不占横幅**：
    /// 只有所有目标都没打开才升成上面那条 `MMPermissionBanner`。
    /// 把"不存在"说成"要授权"就是猜原因。
    @ViewBuilder
    private var appsSkippedNote: some View {
        if appWatcher.status == .watching, appWatcher.skippedDirectories.isEmpty == false,
           pane == .apps {
            let first = appWatcher.skippedDirectories.sorted { $0.key < $1.key }.first!
            HStack(alignment: .top, spacing: MMGap.sm) {
                Image(systemName: "info.circle").foregroundStyle(MMColor.informational).padding(.top, 1)
                VStack(alignment: .leading, spacing: MMGap.xxs) {
                    Text(LF("ui.watch.skip_title",
                            ResidualCollector.display(first.key, home: NSHomeDirectory())))
                        .font(.callout.weight(.semibold))
                    Text(L("ui.watch.skip_note"))
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                }
                Spacer(minLength: MMGap.sm)
            }
            .padding(.horizontal, MMGap.lg)
            .padding(.vertical, MMGap.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.soft(MMColor.informational, 0.05))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    @ViewBuilder
    private var trashRegion: some View {
        if settings.watchTrashForResidualCleanup == false {
            // 关掉就不留任何痕迹：把"已关闭"再在这页复述一遍，等于把设置页的话说两次。
            EmptyView()
        } else if hasTrashNotice, pane == .apps {
            // 有可说的卡片时先说卡片。横幅讲的是"我们看不见废纸篓"，
            // 而回声卡讲的是"我们刚亲手做过一件事"——后者才是用户此刻要的答案。
            trashNoticeCard
        } else if case .unreadable(let reason, let needsFullDiskAccess) = trashWatcher.status {
            MMPermissionBanner(
                title: needsFullDiskAccess ? L("ui.trash.banner_unreadable") : L("ui.trash.banner_busy"),
                detail: reason + " " + (needsFullDiskAccess
                    ? L("ui.trash.banner_clause_fdsa")
                    : L("ui.trash.banner_clause_other")),
                settingsPane: needsFullDiskAccess ? .fullDiskAccess : nil
            )
        }
    }

    /// 卡片有没有内容可讲：监听报到的拖入，或我们自己那次「仅卸载应用」。
    private var hasTrashNotice: Bool {
        trashWatcher.arrivals.isEmpty == false || model.selfEchoArrival != nil
    }

    private var trashNoticeCard: some View {
        let arrivals = trashWatcher.arrivals
        /// 卡片讲的是"当前选中的那一条"。监听读不到废纸篓时它会是空的，
        /// 这时候拿 `arrivals[0]` 念名字既不对也会越界 —— 主语得跟着选中项走。
        let subject = model.trashArrival ?? model.selfEchoArrival ?? arrivals.last
        let items = model.trashResidualItems
        let selfEcho = isSelfEchoTrashArrival
        let arrivalPath = subject?.path ?? ""
        let arrivalDisplayPath = ResidualCollector.display(arrivalPath, home: NSHomeDirectory())
        return VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(MMColor.accent)

                if arrivals.count > 1 {
                    Picker(L("ui.trash.arrival_picker"), selection: trashArrivalSelection) {
                        ForEach(arrivals) { arrival in
                            Text(arrival.name).tag(Optional(arrival.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    Text(LF("ui.trash.multiple_arrivals", MMFormat.count(arrivals.count)))
                        .font(.callout.weight(.semibold))
                } else if selfEcho {
                    // 第二人称才是实话：用户没拖，是我们自己的按钮把它移走的。
                    Text(LF("ui.trash.self_echo_title", subject?.name ?? ""))
                        .font(.callout.weight(.semibold))
                } else {
                    Text(LF("ui.trash.dragged_in", subject?.name ?? ""))
                        .font(.callout.weight(.semibold))
                }

                MMBadge(selfEcho ? L("ui.trash.badge_self") : L("ui.trash.badge_in_trash"),
                        tint: MMColor.informational,
                        systemImage: selfEcho ? "tag" : "trash")

                Spacer(minLength: MMGap.sm)

                Button {
                    MMReveal.open(subject?.path ?? "")
                } label: {
                    Label(L("ui.action.reveal_in_finder"), systemImage: "folder")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)

                Button(L("panel.dismiss")) {
                    trashWatcher.dismiss()
                    model.dismissSelfEchoArrival()
                }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }

            HStack(spacing: MMGap.xs) {
                Text(arrivalDisplayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .foregroundStyle(MMColor.tertiaryLabel)
                Text(subject?.bundleID ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if model.isScanningTrashResiduals {
                HStack(spacing: MMGap.sm) {
                    ProgressView().controlSize(.small)
                    Text(L("ui.trash.residual_scanning")).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                }
            } else if model.hasScannedTrashResiduals == false {
                Text(L("ui.trash.residual_none_scanned"))
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            } else if items.isEmpty {
                Text(L("ui.trash.residual_no_match"))
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            ResidualRow(item: item, isSelected: trashResidualBinding(item),
                                         onToggle: { model.toggleTrashResidual(item) })
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(MMColor.recessedSurface)
                .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MMRadius.control).stroke(MMColor.separator))
            }

            HStack(spacing: MMGap.sm) {
                Text(trashNoticeSummary)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .monospacedDigit()
                Spacer(minLength: MMGap.sm)
                if items.isEmpty == false {
                    Button(L("ui.action.select_deletable")) { model.toggleAllTrashResiduals() }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                }
                Button(role: .destructive) {
                    if settings.confirmBeforeDelete {
                        showTrashConfirm = true
                    } else {
                        Task { await model.trashSelectedTrashResiduals() }
                    }
                } label: {
                    Label(L("ui.trash.clean_selected"), systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .disabled(model.hasScannedTrashResiduals == false || model.selectedTrashResidualCount == 0)
            }
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.informational, 0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 勾选数与合计。没扫过时不能说"0 项"—— 那读起来等于"这里干净"，真相是还没看过。
    private var trashNoticeSummary: String {
        if model.isScanningTrashResiduals { return L("ui.progress.scanning") }
        guard model.hasScannedTrashResiduals else { return L("ui.progress.not_scanned") }
        var line = LF("ui.trash.summary_selected",
                      MMFormat.count(model.selectedTrashResidualCount),
                      MMFormat.bytes(model.selectedTrashResidualSize))
        if model.unselectedTrashResidualCount > 0 {
            line += LF("ui.trash.summary_unselected", MMFormat.count(model.unselectedTrashResidualCount))
        }
        return line
    }

    private var trashArrivalSelection: Binding<String?> {
        Binding(
            get: { model.trashArrival?.id },
            set: { id in
                guard let arrival = trashWatcher.arrivals.first(where: { $0.id == id }) else { return }
                model.selectTrashArrival(arrival)
                Task { await model.scanTrashResiduals(home: Self.trashScanHome) }
            }
        )
    }

    private func trashResidualBinding(_ item: ResidualItem) -> Binding<Bool> {
        Binding(
            get: { item.risk.allowsDeletion && model.selectedTrashResidualIDs.contains(item.id) },
            set: { _ in model.toggleTrashResidual(item) }
        )
    }

    private var trashConfirmSheet: some View {
        let roots = model.trashResidualReport?.deletionRoots(for: model.selectedTrashResidualIDs) ?? []
        return VStack(alignment: .leading, spacing: MMGap.md) {
            Text(LF("ui.trash.confirm_title",
                    model.trashArrival?.name ?? "",
                    MMFormat.count(roots.count)))
                .font(.title3.weight(.semibold))
            Text(LF("ui.trash.confirm_body", model.trashArrival?.name ?? L("ui.trash.this_app")))
                .font(.callout)
                .foregroundStyle(MMColor.secondaryLabel)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(roots, id: \.self) { path in
                    HStack(spacing: MMGap.sm) {
                        Image(systemName: "doc")
                            .foregroundStyle(MMColor.secondaryLabel)
                            .frame(width: MMGap.xxl)
                        Text(path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: MMGap.sm)
                    }
                    .padding(.horizontal, MMGap.md)
                    .frame(height: MMMetric.rowCompact)
                    Divider()
                }
            }
            .background(MMColor.recessedSurface)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.control).stroke(MMColor.separator))

            Text(LF("ui.trash.confirm_total", MMFormat.bytes(model.selectedTrashResidualSize)))
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)

            HStack {
                Spacer()
                Button(L("ui.action.cancel")) { showTrashConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button(L("ui.action.put_in_trash")) {
                    showTrashConfirm = false
                    Task { await model.trashSelectedTrashResiduals() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MMGap.lg)
        .frame(width: 480)
    }
}

// MARK: - 安装来源的呈现口径
//
// 事实层在 `AppProvenance.swift`：它只回答"对上的是哪一档凭据"。颜色、措辞、
// 哪一档值得在列表里占一格，全部收在这里。
// 文案合同 = 设计稿 `docs/design-system/screens/mmuninstaller/03d-uninstaller-provenance.html`
// 第三块那张五行表，逐字一致；改这里要同步改那张表，否则还原度对照就失去基准。

extension UninstallCandidate {
    /// 列表行内的短标记。**只有 brew 相关才占这一格**：这枚标记存在的理由是它会改变
    /// 你接下来的动作——brew 装的应用被拖进废纸篓，brew 的账本不会同步，
    /// 下次 `brew list` 还说它装着。App Store 与安装包没有这种后果，就不在列表里打扰。
    var sourceChip: (text: String, tint: Color)? {
        switch provenance.source {
        case .homebrewCask: ("brew", MMColor.accent)
        case .homebrewCaskNameOnly: (L("ui.provenance.chip_name_only"), MMColor.caution)
        default: nil
        }
    }

    /// 详情标题旁的徽章。`unknown` 没有徽章：把"没查到"做成一种属性是假话。
    var sourceBadge: (text: String, tint: Color, symbol: String)? {
        switch provenance.source {
        case .homebrewCask:
            ("Homebrew cask · \(provenance.cask?.token ?? "")", MMColor.informational, "shippingbox")
        case .homebrewCaskNameOnly:
            (L("ui.provenance.badge_name_only"), MMColor.caution, "questionmark.circle")
        case .appStore:
            ("App Store", MMColor.secondaryLabel, "app.badge")
        case .installerPackage:
            (L("ui.provenance.badge_installer"), MMColor.secondaryLabel, "square.and.arrow.down")
        case .unknown:
            nil
        }
    }

    /// 「来源」键值行。
    var sourceValue: String {
        guard let cask = provenance.cask else {
            switch provenance.source {
            case .appStore: return "Mac App Store"
            case .installerPackage: return LF("ui.provenance.value_installer",
                                              provenance.packageIdentifier ?? "")
            case .unknown:
                let tokens = provenance.ambiguousCaskTokens
                if tokens.isEmpty { return L("ui.provenance.unknown") }
                let joined = tokens.joined(separator: L("ui.format.list_join"))
                return provenance.ambiguousByDeviceIdentity
                    ? LF("ui.provenance.unknown_device_ambiguous", joined)
                    : LF("ui.provenance.unknown_name_ambiguous", joined)
            default: return L("ui.provenance.unknown")
            }
        }
        switch provenance.source {
        case .homebrewCask:
            var line = "Homebrew cask · \(cask.token)"
            if let version = cask.version { line += " \(version)" }
            if let tap = cask.tap { line += LF("ui.provenance.value_cask_tap", tap) }
            return line
        case .homebrewCaskNameOnly:
            return LF("ui.provenance.value_name_only", cask.token)
        default: return L("ui.provenance.unknown")
        }
    }

    /// 「来源凭据」：能说出这句话是哪份文件写的。只有 brew 两档有账本可指。
    var sourceReceipt: String? {
        provenance.cask.map(\.receiptPath)
    }

    /// 「对应命令」——**只展示，本应用不会代用户执行**。
    /// 名字对上而设备号没对上的那一档不给：凭据不足时不推荐一条会改动系统状态的指令。
    var sourceCommand: String? {
        guard provenance.source == .homebrewCask, let token = provenance.cask?.token else { return nil }
        return "brew uninstall --cask \(token)"
    }

    /// 「判定依据」小字：把结论的强度写在脸上。
    var sourceBasis: String {
        switch provenance.source {
        case .homebrewCask:
            LF("ui.provenance.basis_cask", bundleName)
        case .homebrewCaskNameOnly:
            LF("ui.provenance.basis_name_only", bundleName)
        case .appStore:
            L("ui.provenance.basis_app_store")
        case .installerPackage:
            L("ui.provenance.basis_installer")
        case .unknown:
            provenance.ambiguousCaskTokens.isEmpty
                ? L("ui.provenance.basis_unknown")
                : (provenance.ambiguousByDeviceIdentity
                    ? LF("ui.provenance.basis_ambiguous_device",
                         provenance.ambiguousCaskTokens.joined(separator: L("ui.format.list_join_words")))
                    : LF("ui.provenance.basis_ambiguous_name",
                         provenance.ambiguousCaskTokens.joined(separator: L("ui.format.list_join_words"))))
        }
    }

    /// 确认面板的提醒。只有 brew 两档有：这一页的删除动作只有废纸篓一条路径，
    /// 而 brew 装的app走这条路会让账本失真——那是一件做完之后才会发现的事。
    var sourceWarning: String? {
        switch provenance.source {
        case .homebrewCask:
            guard let token = provenance.cask?.token else { return nil }
            return LF("ui.provenance.warning_cask", path, token)
        case .homebrewCaskNameOnly:
            guard let token = provenance.cask?.token else { return nil }
            return LF("ui.provenance.warning_name_only", token)
        default: return nil
        }
    }
}

// MARK: - 运行状态的呈现口径
//
// 事实层在 `RunningAppProbe.swift`：它只回答"快照里有没有对上、按哪一条对上"。
// 措辞与颜色收在这里。
// 文案合同 = 设计稿 `docs/design-system/screens/mmuninstaller/03f-uninstaller-running.html`
// 那三块（列表行、详情键值行、确认面板提醒），逐字一致；改这里要同步改那张图。
//
// 三处话术的共同底线：**这一版不代用户退出应用**。所以每说一次"正在运行"都要同时
// 交代两件事——移到废纸篓不会让它退出（macOS 允许删掉正在运行的应用包，进程继续用
// 已经载入内存的代码跑），以及"先退出"得用户自己做。只说前半句会让人以为删完就干净了，
// 只说后半句像在暗示按钮会替他做。既然不代杀，这里也就没有"杀不动怎么办"这一类分支。

extension UninstallCandidate {
    /// 列表行的小标记。**只有"正在运行"占这一格**：它会改变你接下来的动作。
    /// "没检测到"与"无法判定"都没有这种后果，与 `sourceChip` 同一取舍。
    func runningChip(_ state: AppRunningState) -> (text: String, tint: Color)? {
        guard state.isRunning else { return nil }
        return (L("ui.running.chip"), MMColor.caution)
    }

    /// 详情页「运行状态」那一行的值。
    func runningValue(_ state: AppRunningState) -> String {
        switch state {
        case .notRunning:
            L("ui.running.value_not_running")
        case .undetermined(let count):
            LF("ui.running.value_undetermined", String(count))
        case .running(let matches):
            matches.count == 1
                ? LF("ui.running.value_single", pidList(matches))
                : LF("ui.running.value_multiple", String(matches.count), pidList(matches))
        }
    }

    /// 「判定依据」小字：结论的强度写在脸上，与 `sourceBasis` 同一规矩。
    func runningBasis(_ state: AppRunningState) -> String {
        switch state {
        case .notRunning:
            return L("ui.running.basis_not_running")
        case .undetermined(let count):
            return LF("ui.running.basis_undetermined", String(count))
        case .running(let matches):
            var line = L("ui.running.basis_prefix")
            let here = matches.filter { $0.evidence == .sameBundle }
            let elsewhere = matches.filter { $0.evidence == .bundleIdentifierOnly }
            if here.isEmpty == false {
                line += LF("ui.running.basis_here", pidList(here), path)
            }
            if elsewhere.isEmpty == false {
                line += LF("ui.running.basis_elsewhere", pidList(elsewhere), locationList(elsewhere))
            }
            // 这句只在两档**同时**出现时才说：它是回答"包名对上、位置对不上的那一份算不算在跑"的。
            // 只有一档的时候它是假话——真机照片上 WeChat 是「2 个进程（1094、1276）」，
            // 两条都是按位置对上的，画面里没有任何"两档"可数。
            if here.isEmpty == false && elsewhere.isEmpty == false {
                line += " " + L("ui.running.basis_both")
            }
            return line
        }
    }

    /// 详情页那一块「运行状态」的图标与颜色。三档各有各的颜色，
    /// 因为三档说的话不一样：警告 / 说明 / 承认看不出。
    func runningEmphasis(_ state: AppRunningState) -> (symbol: String, tint: Color) {
        switch state {
        case .running: ("exclamationmark.triangle", MMColor.caution)
        case .notRunning: ("circle", MMColor.secondaryLabel)
        case .undetermined: ("questionmark.circle", MMColor.secondaryLabel)
        }
    }

    /// 「移到废纸篓不会让它退出」那一句。详情页与确认面板共用，所以它不复述状态行
    /// 已经说过的"正在运行（进程 …）"，只说后果与边界。
    ///
    /// 只有包名对上那一档的措辞是实拍教出来的：P31a 第一版写的是"与这里要移除的不是
    /// 同一个文件"，而照片（`docs/verification/p31-running/05-fixture-identifier-only.png`）
    /// 里那句话当场就是假的——清单上的路径经 `canonicalHome` 变成 `/private/tmp/…`，
    /// 进程报出的还是 `/tmp/…`，**同一个文件的两种写法**。判定只比字符串（见
    /// `AppRunningState.resolve` 上不解析符号链接的取舍），所以话只能说到"写法不同"，
    /// 由用户自己判断是不是别处那一份。
    func runningWarning(_ state: AppRunningState) -> String? {
        guard case .running(let matches) = state else { return nil }
        var line = ""
        if matches.allSatisfy({ $0.evidence == .bundleIdentifierOnly }) {
            line += LF("ui.running.warning_identifier_only", locationList(matches))
        }
        return line + L("ui.running.warning_tail")
    }

    private func pidList(_ matches: [RunningAppMatch]) -> String {
        matches.map { String($0.pid) }.joined(separator: L("ui.format.list_join"))
    }

    /// 进程报出的位置列表：报不出位置的那一条要说出来，不能空着。
    private func locationList(_ matches: [RunningAppMatch]) -> String {
        matches.map { $0.bundlePath ?? L("ui.running.no_path") }
            .joined(separator: L("ui.format.list_join"))
    }
}

// MARK: - 启动器型 bundle 的呈现口径
//
// 事实层在 `SteamLauncherProbe.swift`：它只回答"这个 bundle 的可执行文件是不是
// 一份 `steam://` 启动脚本"。措辞与颜色全部收在这里。
// 文案合同 = 设计稿 `docs/design-system/screens/mmuninstaller/03g-uninstaller-steam-launcher.html`
//
// 措辞的边界由 `docs/analysis/uninstaller-steam-launcher.md` §5.3 定：这一层只读过那个脚本，
// 没有读过也没有数过游戏目录，所以只能说"大小那一格量的是启动器"——
// 既不能说"游戏有 N GB"，也不能说"这里没有你的游戏"。
// 与 P31a「只有包名对上」那一档只说"写法不同"是同一条纪律。

extension UninstallCandidate {
    /// 列表行的小标记。占这一格的理由与 `sourceChip` 同一取舍：它会改变你怎么读右边那个数——
    /// 那一格是 bundle 的大小，而这类 bundle 里装的是启动脚本。
    var steamLauncherChip: (text: String, tint: Color)? {
        steamLauncher == nil ? nil : (L("ui.launcher.name"), MMColor.informational)
    }

    /// 详情标题旁的徽章。识别不成立时一个都不出现，与 `sourceBadge` 不给 `unknown` 编造属性同一规矩。
    /// 这里只放四个字：appid 已经写在「启动器」那一行里，标题栏同时挂两枚徽章时长度不可控。
    var steamLauncherBadge: (text: String, tint: Color, symbol: String)? {
        guard steamLauncher != nil else { return nil }
        return (L("ui.launcher.badge"), MMColor.informational, "gamecontroller")
    }

    /// 「启动器」键值行的值。
    var steamLauncherValue: String? {
        guard let launcher = steamLauncher else { return nil }
        return LF("ui.launcher.value", launcher.scriptName, launcher.appID)
    }

    /// 「启动器」的判定依据。两句：凭据是什么，以及那个数字量的是谁。
    var steamLauncherBasis: String? {
        guard let launcher = steamLauncher else { return nil }
        return LF("ui.launcher.basis", launcher.scriptName,
                  String(SteamLauncherProbe.maxScriptBytes),
                  launcher.verb.rawValue, launcher.appID)
    }
}

/// 行内来源标记：比 `MMBadge` 小一号（列表行只有两行文字的空间），
/// 对应设计稿 `.src` 那枚 16pt 高的等宽小胶囊。
private struct SourceChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(MMColor.soft(tint, 0.14), in: RoundedRectangle(cornerRadius: MMRadius.badge, style: .continuous))
            .fixedSize()
    }
}

// MARK: - 应用列表行

struct AppListRow: View {
    let app: UninstallCandidate
    /// 监听观察到这个路径已经从应用目录里消失了，而清单还是载入时的快照。
    /// 判据来自监听端的目录清单差异，不是这一行自己去 stat —— 一行一次 stat
    /// 会把 45 行的列表变成 45 次系统调用，而那件事监听已经做过一次了。
    var goneFromDirectory: Bool = false
    /// 上一次读进程快照算出的状态。nil = 还没读过（清单载入之前），
    /// 这时这一行不给任何关于运行与否的话。
    var runningState: AppRunningState? = nil

    var body: some View {
        HStack(spacing: MMGap.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .opacity(goneFromDirectory ? 0.55 : 1)
                .frame(width: MMMetric.iconApp, height: MMMetric.iconApp)

            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(app.name).font(.body).lineLimit(1)
                if goneFromDirectory {
                    Text(L("ui.uninstall.row_gone"))
                        .font(.caption)
                        .foregroundStyle(MMColor.caution)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    HStack(spacing: MMGap.xs) {
                        if let state = runningState, let chip = app.runningChip(state) {
                            SourceChip(text: chip.text, tint: chip.tint)
                        }
                        if let chip = app.sourceChip {
                            SourceChip(text: chip.text, tint: chip.tint)
                        }
                        if let chip = app.steamLauncherChip {
                            SourceChip(text: chip.text, tint: chip.tint)
                        }
                        // 版本号长度不可控（ChatGPT 是 26.924.22138），不限行就会折成两行
                        // 把整行撑高。这里不能用 fixedSize：它会把空间全部划给大小，
                        // 反过来把 "6.9.3" 这种短版本号截成 "6.…"。让大小优先、版本让步。
                        Text(app.version.isEmpty ? L("ui.uninstall.unknown_version") : app.version)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(MMFormat.bytes(app.size))
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .monospacedDigit()
                }
            }

            Spacer(minLength: MMGap.sm)

            if goneFromDirectory {
                Text(L("ui.uninstall.not_on_disk"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MMColor.caution)
            } else if app.residuals.isEmpty == false {
                VStack(alignment: .trailing, spacing: MMGap.xxs) {
                    Text(LF("ui.uninstall.row_residual_count", MMFormat.count(app.residuals.count)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MMColor.accent)
                    Text(MMFormat.bytes(app.residualSize))
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .monospacedDigit()
                }
            } else if app.isSystemOwned {
                MMBadge(L("ui.uninstall.system_app"), tint: MMColor.secondaryLabel)
            }
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: MMMetric.rowApp)
        .background(goneFromDirectory ? MMColor.soft(MMColor.caution, 0.07) : Color.clear)
    }
}

// MARK: - 详情

struct AppDetailView: View {
    let app: UninstallCandidate
    @Binding var selectedIDs: Set<String>
    let unselectedCount: Int
    /// 上一次读进程快照算出的状态；nil = 还没读过，这一屏不提运行与否。
    var runningState: AppRunningState? = nil
    let onToggle: (ResidualItem) -> Void
    let onToggleAll: () -> Void
    let onUninstallWithResiduals: () -> Void
    let onUninstallAppOnly: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MMGap.lg) {
                identityHeader
                Divider()
                statsCards
                Divider()
                if let runningState {
                    runningSection(runningState)
                    Divider()
                }
                infoSection
                Divider()
                residualSection
            }
            .padding(MMGap.lg)
        }
        .background(MMColor.contentBackground)
    }

    private var identityHeader: some View {
        HStack(alignment: .top, spacing: MMGap.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))

            VStack(alignment: .leading, spacing: MMGap.xxs) {
                HStack(spacing: MMGap.sm) {
                    Text(app.name).font(.title2.weight(.semibold)).lineLimit(1)
                    if let badge = app.sourceBadge {
                        MMBadge(badge.text, tint: badge.tint, systemImage: badge.symbol)
                    }
                    // 「来源」与「是启动器」是正交的两句：brew 装的 Steam 启动器两枚同时挂。
                    if let badge = app.steamLauncherBadge {
                        MMBadge(badge.text, tint: badge.tint, systemImage: badge.symbol)
                    }
                }
                Text("\(app.bundleID) · \(MMFormat.bytes(app.size)) · \((app.path as NSString).deletingLastPathComponent)")
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: MMGap.md)

            MMRevealButton(path: app.path)
                .controlSize(.small)
        }
    }

    private var statsCards: some View {
        HStack(spacing: MMGap.sm) {
            MMStatItem(L("ui.field.app_size"), MMFormat.bytes(app.size))
            MMStatItem(L("ui.field.included_files"),
                       app.fileCount.map { MMFormat.count($0) } ?? L("format.measuring"))
            MMStatItem(L("ui.field.residual_size"), MMFormat.bytes(app.residualSize))
            MMStatItem(L("ui.field.residual_items"), MMFormat.count(app.residuals.count))
        }
    }

    /// 「运行状态」这一屏排在基本信息之前：它比版本号更影响"现在能不能卸"，
    /// 而它又是这一页里唯一会自己变的一行（进程起落由通知刷新）。
    /// 三档都给话，包括"无法判定"——那一档要说的是我们看不看得出，不是安慰。
    private func runningSection(_ state: AppRunningState) -> some View {
        let emphasis = app.runningEmphasis(state)
        return HStack(alignment: .top, spacing: MMGap.sm) {
            Image(systemName: emphasis.symbol).foregroundStyle(emphasis.tint)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(app.runningValue(state))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(emphasis.tint)
                Text(app.runningBasis(state))
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = app.runningWarning(state) {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(MMColor.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: MMGap.sm)
        }
        .padding(MMGap.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(emphasis.tint, state.isRunning ? 0.10 : 0.06),
                    in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            Text(L("ui.uninstall.info_header")).font(.headline)
            VStack(alignment: .leading, spacing: MMGap.xs) {
                MMKeyRow(L("ui.field.source"), app.sourceValue)
                if let receipt = app.sourceReceipt {
                    MMKeyRow(L("ui.field.source_receipt"), receipt, monospaced: true)
                }
                if let command = app.sourceCommand {
                    MMKeyRow(L("ui.field.source_command"), command, monospaced: true)
                }
                MMKeyRow(L("ui.field.bundle_id"), app.bundleID, monospaced: true)
                MMKeyRow(L("ui.field.version"), app.version.isEmpty ? "" : "\(app.version) (\(app.build))")
                MMKeyRow(L("ui.field.developer"),
                         app.developer.isEmpty ? "" : LF("ui.uninstall.developer_signed", app.developer))
                MMKeyRow(L("ui.field.min_system"), app.minSystemVersion)
                MMKeyRow(L("ui.field.executable"), app.executable)
                if let launcher = app.steamLauncherValue {
                    MMKeyRow(L("ui.launcher.name"), launcher, monospaced: true)
                    if let basis = app.steamLauncherBasis {
                        Text(basis)
                            .font(.caption)
                            .foregroundStyle(MMColor.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                MMKeyRow(L("ui.field.modified"), MMFormat.dateTime(app.modificationDate))
                MMKeyRow(L("ui.field.folder"), (app.path as NSString).deletingLastPathComponent)
            }
            .textSelection(.enabled)

            HStack(alignment: .top, spacing: MMGap.sm) {
                Image(systemName: "info.circle").foregroundStyle(MMColor.tertiaryLabel)
                Text(app.sourceBasis)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var residualSection: some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Text(app.bodyDeletable ? L("ui.uninstall.residual_header")
                                       : L("ui.uninstall.residual_readonly_header")).font(.headline)
                if unselectedCount > 0 {
                    MMBadge(LF("ui.uninstall.unselected_badge", MMFormat.count(unselectedCount)),
                            tint: MMColor.caution, systemImage: "exclamationmark.triangle")
                }
                Spacer(minLength: MMGap.sm)
                Text(L("ui.uninstall.residual_match_note"))
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                if app.bodyDeletable {
                    // 本体不给删时这一屏没有任何东西会被移走，"全选"就是死控件。
                    Button(action: onToggleAll) {
                        Label(L("ui.action.select_deletable"), systemImage: "checklist")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                }
            }

            if app.isSystemOwned {
                // 这一句只管"不扫"；"不删"是本体那一层的另一个决定，说在下面那块。
                // 两句分开是 `docs/analysis/uninstaller-app-body-risk.md` §5 第 2 条的要求。
                Text(L("ui.uninstall.system_no_scan_note"))
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .padding(MMGap.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MMColor.recessedSurface, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            } else if app.residuals.isEmpty {
                Text(L("ui.uninstall.residual_no_match"))
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .padding(MMGap.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MMColor.recessedSurface, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            } else {
                residualGroups
            }

            if app.bodyDeletable {
                HStack(alignment: .top, spacing: MMGap.sm) {
                    Image(systemName: "info.circle").foregroundStyle(MMColor.tertiaryLabel)
                    Text(confirmationNote)
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                }

                Button(role: .destructive, action: onUninstallWithResiduals) {
                    Label(L("ui.uninstall.uninstall_with_residuals"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)

                Button(L("ui.uninstall.app_only_keep_residuals"), action: onUninstallAppOnly)
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            } else {
                // 本体只读，两个删除入口一起收掉。这句沿用残留层只读档的同一套话
                // （`MMRisk.groupNote` = 「仅供查看，MacMaster 不提供删除入口」）：
                // 两处只读说同一种话，读的人不需要先学会我们的枚举。
                HStack(alignment: .top, spacing: MMGap.sm) {
                    MMBadge(risk: .readOnly)
                    Text(L("ui.uninstall.system_readonly_note"))
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: MMGap.sm)
                }
                .padding(MMGap.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MMColor.recessedSurface,
                            in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            }
        }
    }

    private var residualGroups: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            ForEach(groups, id: \.risk) { group in
                VStack(spacing: 0) {
                    HStack(spacing: MMGap.sm) {
                        MMBadge(risk: group.risk)
                        Text(group.risk.groupNote)
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                        Spacer(minLength: MMGap.sm)
                        Text(LF("ui.uninstall.group_count", MMFormat.count(group.items.count)))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(MMColor.secondaryLabel)
                    }
                    .padding(.horizontal, MMGap.md)
                    .padding(.vertical, MMGap.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MMColor.recessedSurface)

                    ForEach(group.items) { item in
                        ResidualRow(item: item, isSelected: binding(for: item), onToggle: { onToggle(item) })
                        Divider()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator))
            }
        }
    }

    private var groups: [(risk: MMRisk, items: [ResidualItem])] {
        ResidualScanReport(items: app.residuals, inaccessiblePaths: []).riskGroups
    }

    private func binding(for item: ResidualItem) -> Binding<Bool> {
        Binding(
            get: { item.risk.allowsDeletion && selectedIDs.contains(item.id) },
            set: { _ in onToggle(item) }
        )
    }

    private var confirmationNote: String {
        let size = MMFormat.bytes(totalSelectedSize)
        return LF("ui.uninstall.confirm_note", app.name, MMFormat.count(selectedCount), size)
    }

    private var selectedCount: Int {
        app.residuals.filter { $0.risk.allowsDeletion && selectedIDs.contains($0.id) }.count
    }

    private var totalSelectedSize: UInt64? {
        UninstallSelection.selectedSize(items: app.residuals, selectedIDs: selectedIDs)
    }
}

// MARK: - 残留行

/// 复用 `MMItemRow` 的行高与勾选框语义，右侧再加一列"在访达中显示"。
/// 只读项由 `MMItemRow` 自动禁用勾选框，因此不会出现在删除列表里。
/// `caveat` 走行下方独立的一行小字，不挤进副标题：`MMItemRow` 的副标题只有一行、
/// 且中间省略，"路径 · 证据 · 提醒"三样在窗口硬最小宽度下放不进去
/// （判据是 `docs/verification/p32b-steam/11a-narrow-window-truncation-before-fix.png`，
/// 修复后的同一档在 `11-steam-self-narrow-window.png`）。
struct ResidualRow: View {
    let item: ResidualItem
    @Binding var isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MMItemRow(
                title: item.name,
                subtitle: "\(item.displayPath) · \(item.reason)",
                value: MMFormat.bytes(item.size),
                risk: item.risk,
                systemImage: item.category.icon,
                isSelected: $isSelected
            ) {
                Button {
                    MMReveal.open(item.path)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(L("ui.action.reveal_in_finder"))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if let caveat = item.caveat {
                Text(caveat)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MMGap.md)
                    .padding(.bottom, MMGap.xs)
            }
        }
    }
}

// MARK: - 孤儿残留行

/// 与 `ResidualRow` 同一套行高与勾选语义，差别在措辞：这里的结论是"查不到主人"，
/// 不是"确认可以删"，所以副标题必须把不确定性摆在脸上，风险等级给 `caution`。
struct OrphanRow: View {
    let item: OrphanCandidate
    @Binding var isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        MMItemRow(
            title: item.name,
            subtitle: LF("ui.orphan.row_subtitle", item.displayPath, item.owner),
            value: MMFormat.bytes(item.size),
            risk: .caution,
            systemImage: item.category.icon,
            isSelected: $isSelected
        ) {
            Button {
                MMReveal.open(item.path)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(L("ui.action.reveal_in_finder"))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}
