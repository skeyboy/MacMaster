import SwiftUI
import MMCore
import MMUI

// MARK: - 模块注册

public struct UninstallerModule: ModuleRegistrable {
    public var moduleID: String { "uninstaller" }
    public var moduleName: String { "应用卸载" }
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
        var title: String { self == .apps ? "已装应用" : "卸载后遗症" }
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
            if hit == nil {
                FileHandle.standardError.write("MM_UNINSTALL_SELECT=\(named) 没有对应的应用\n".data(using: .utf8)!)
            }
            return hit
        }
        guard let home = Self.confirmationFixtureHome else { return nil }
        return model.apps.first { $0.path.hasPrefix(home + "/Applications/") }
    }

    @StateObject private var model = UninstallerModel()
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
            MMPageHeader("应用卸载", subtitle: headerSubtitle) {
                Picker("视图", selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("已装应用：选一个应用清理它的残留。卸载后遗症：找已经没有主人的残留。")

                Picker("敏感度", selection: $model.sensitivity) {
                    ForEach(ResidualSensitivity.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("残留扫描的匹配宽度：\(model.sensitivity.note)")

                Button {
                    Task { await model.loadApps() }
                } label: {
                    Label("重新载入", systemImage: "arrow.clockwise")
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
        .overlay(alignment: .bottom) {
            if let result = model.lastResult, result.successCount > 0, toastSeconds > 0 {
                MMUndoToast(
                    message: (model.lastOperationTrashedApps ? "已卸载 " : "已移入废纸篓 ")
                        + "\(result.successCount) 项",
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
        var line = "\(model.apps.count) 个应用"
        if model.isMeasuring || model.measuredCount < model.apps.count {
            line += " · 已测 \(model.measuredCount) · \(model.apps.count - model.measuredCount) 个测量中"
        } else if model.apps.isEmpty == false {
            line += " · 合计 \(MMFormat.bytes(model.totalSize)) · 大小已实测"
        }
        return line
    }

    private var failureSummary: String? {
        let freed = model.lastResult?.totalSize ?? 0
        return freed > 0 ? "已回收 \(MMFormat.bytes(freed))" : nil
    }

    // MARK: 左侧应用列表

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(MMColor.secondaryLabel)
                TextField("搜索应用…", text: $searchText)
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
                    Text("扫描应用…").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                MMEmptyState(systemImage: "app.dashed",
                             title: searchText.isEmpty ? "没有应用" : "没有匹配的应用",
                             detail: searchText.isEmpty ? "重新载入以刷新应用列表。" : "换一个名称或包名再试试。")
            } else {
                List(selection: Binding(
                    get: { model.selectedAppID },
                    set: { model.selectedAppID = $0 }
                )) {
                    ForEach(filteredApps) { app in
                        AppListRow(app: app,
                                   goneFromDirectory: appWatcher.departures.contains { $0.path == app.path })
                            .tag(app.id)
                            .contextMenu {
                                Button {
                                    MMReveal.open(app.path)
                                } label: {
                                    Label("打开所在文件夹", systemImage: "folder")
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
                    Text("· 清单是载入时的快照，未自动刷新")
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
        var line = "\(model.apps.count) 个应用 · 已测 \(measured)"
        if pending > 0 { line += " · \(pending) 个测量中" }
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
                onToggle: { model.toggle($0) },
                onToggleAll: { model.toggleAllDeletable() },
                onUninstallWithResiduals: { requestConfirmation(.withResiduals) },
                onUninstallAppOnly: { requestConfirmation(.appOnly) }
            )
        } else {
            MMEmptyState(
                systemImage: "app.dashed",
                title: "未选择应用",
                detail: "从左侧列表选择一个应用，查看它的信息与将被一并移除的残留文件。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MMColor.contentBackground)
        }
    }

    // MARK: 底部操作栏

    private var actionBar: some View {
        MMActionBar(
            summary: "已选 \(model.selectedResidualCount) 项残留 · \(MMFormat.bytes(model.selectedResidualSize))",
            note: "未勾选项不会被修改",
            trailing: {
                Button("仅卸载应用") {
                    requestConfirmation(.appOnly)
                }
                .disabled(model.selectedApp == nil)

                Button(role: .destructive) {
                    requestConfirmation(.withResiduals)
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .disabled(model.selectedApp == nil)
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
                    Text("正在反查残留归属…")
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.orphans.isEmpty {
                MMEmptyState(
                    systemImage: "questionmark.folder",
                    title: model.hasScannedOrphans ? "没有发现没有主人的残留" : "还没有反查过",
                    detail: model.hasScannedOrphans
                        ? "残留目录里的每一项都能对应到本机已安装的应用。"
                        : "扫一遍 ~/Library 的残留目录，列出对不上任何已装应用的条目。判断口径偏保守：宁可漏报，不可错报。"
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
        if model.isScanningOrphans { return "正在反查残留归属…" }
        guard model.hasScannedOrphans else { return "尚未反查 · 点右侧「反查残留」扫一遍 ~/Library" }
        return "可疑残留 \(model.orphans.count) 项 · 已选 \(model.selectedOrphanIDs.count) 项 · "
            + MMFormat.bytes(model.selectedOrphanSize)
    }

    private var orphanActionBar: some View {
        MMActionBar(
            summary: orphanSummary,
            note: model.hasScannedOrphans
                ? "反向判断只认反向域名形态的归属线索，全部默认不勾选"
                : "先扫一次，结果永远默认不勾选",
            trailing: {
                Button {
                    Task { await model.scanOrphans() }
                } label: {
                    Label(model.hasScannedOrphans ? "重新反查" : "反查残留", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanningOrphans)

                Button(role: .destructive) {
                    showOrphanConfirm = true
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
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
            Text("把 \(picked.count) 项可疑残留移入废纸篓？")
                .font(.title3.weight(.semibold))
            Text("这些条目在本机已安装的应用里找不到对应包名，但「找不到」不等于「没在用」——"
                 + "装在别的卷、或包名与磁盘名不同形的应用也会被判成可疑。请逐条核对路径。")
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
                Button("取消") { showOrphanConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button("移入废纸篓") {
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
        confirmationMode = mode
        showConfirm = true
    }

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            Text("确认卸载")
                .font(.title3.weight(.semibold))

            if let app = model.selectedApp {
                let includeResiduals = confirmationMode == .withResiduals
                let paths = includeResiduals
                    ? UninstallSelection.deletionPaths(appPath: app.path, items: app.residuals,
                                                       selectedIDs: model.selectedResidualIDs)
                    : [app.path]
                let residualSize = includeResiduals ? model.selectedResidualSize : 0
                VStack(alignment: .leading, spacing: MMGap.xs) {
                    MMKeyRow("应用", app.name)
                    MMKeyRow("来源", app.sourceValue)
                    MMKeyRow("包名", app.bundleID, monospaced: true)
                    MMKeyRow("本体", MMFormat.bytes(app.size))
                    MMKeyRow("残留", includeResiduals
                        ? "\(paths.count - 1) 项 · \(MMFormat.bytes(residualSize))"
                        : "保留，不修改")
                    MMKeyRow("合计", MMFormat.bytes(UninstallSelection.confirmationSize(
                        appSize: app.size, residualSize: residualSize, includeResiduals: includeResiduals)))
                }

                // brew 装的应用被拖进废纸篓，账本不会同步——这句话说在动手之前，
                // 因为做完之后没人会想起来。这里仍然只有废纸篓一条路径，不新增执行能力。
                if let warning = app.sourceWarning {
                    HStack(alignment: .top, spacing: MMGap.sm) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(MMColor.caution)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(MMColor.caution)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(MMGap.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MMColor.soft(MMColor.caution, 0.10),
                                in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                }

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
                     ? "列出的路径将移入废纸篓；未勾选与只读项不修改，谨慎项仅在主动勾选时移除。可在「最近操作」中撤回。"
                     : "只移动应用本体，残留文件不会被修改。可在「最近操作」中撤回。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            HStack(spacing: MMGap.sm) {
                Spacer()
                Button("取消") { showConfirm = false }
                Button(confirmationMode == .appOnly ? "仅卸载应用" : "卸载", role: .destructive) {
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
                    title: needsFullDiskAccess ? "读不到应用目录" : "应用目录现在读不了",
                    detail: (needsFullDiskAccess
                        ? reason + " 在系统设置里授予「完全磁盘访问」后，重新进入这一页才会重试。"
                        : reason + " 这和权限无关，所以这里不放授权按钮；重新进入这一页会重试。")
                    + " 在恢复监听之前，这里不会给出任何残留判定。",
                    settingsPane: needsFullDiskAccess ? .fullDiskAccess : nil
                )
            }
        }
    }

    private func appsDepartureCard(_ departure: AppDeparture) -> some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "xmark.app").foregroundStyle(MMColor.accent)
                Text("刚从应用目录消失：\(departure.name)")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                MMBadge("本体已不在应用目录", tint: MMColor.informational, systemImage: "xmark.app")
                Spacer(minLength: MMGap.sm)
                Button("忽略") { dismissDeparture(departure) }
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
                Text(departure.bundleID.isEmpty ? "无包标识" : departure.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·").foregroundStyle(MMColor.tertiaryLabel)
                Text("最后已知位置")
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .fixedSize()
            }

            if isRunningDepartureScan {
                HStack(spacing: MMGap.sm) {
                    ProgressView().controlSize(.small)
                    Text("正在刷新归属清单…").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                }
            } else {
                Text("我们只看见它离开了应用目录：不知道是谁删的，也不知道它去了哪里。"
                     + "左侧清单里它还挂着，所以扫描会先重新载入清单——"
                     + "否则它会把自己散在 ~/Library 的文件当成「有主人」漏掉。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            HStack(spacing: MMGap.sm) {
                Text(isRunningDepartureScan ? "扫描中 · 这一步不提前给数字" : "未扫描 · 扫描会先重新载入清单")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                Spacer(minLength: MMGap.sm)
                Button {
                    reloadListingOnly()
                } label: {
                    Label("只重新载入清单", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(isRunningDepartureScan || model.isScanningApps)

                Button {
                    reloadListingAndScan()
                } label: {
                    Label("重新载入并扫描残留", systemImage: "list.bullet.below.rectangle")
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
                Text("应用目录里有 \(appearances.count) 个新条目")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                MMBadge("当前清单是旧快照", tint: MMColor.informational, systemImage: "arrow.clockwise")
                Spacer(minLength: MMGap.sm)
                Button {
                    Task {
                        await model.loadApps()
                        appWatcher.dismissAppearances()
                    }
                } label: {
                    Label("重新载入", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(model.isScanningApps || isRunningDepartureScan)

                Button("忽略") { appWatcher.dismissAppearances() }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }

            Text(appearances.map(\.entry).joined(separator: "  ·  "))
                .font(.caption.monospaced())
                .foregroundStyle(MMColor.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("只列出目录名；不会自动改动左侧清单。装在别处的应用我们看不见——"
                 + "监听范围与列举范围一致，只覆盖应用目录第一层的 .app。")
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
                    Text("\(ResidualCollector.display(first.key, home: NSHomeDirectory())) 不在这台机器上")
                        .font(.callout.weight(.semibold))
                    Text("不是故障：这台机器没有这个应用目录，所以监听只覆盖已经打开的那些。"
                         + "目录不存在与读不到是两种原因，这里不混为一谈，也不放授权按钮。")
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
                title: needsFullDiskAccess ? "读不到废纸篓" : "废纸篓现在读不了",
                detail: needsFullDiskAccess
                    ? reason + " 在系统设置里授予「完全磁盘访问」后，重新进入这一页或重启应用才会生效。"
                    : reason + " 这和权限无关，所以这里不放授权按钮。",
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
                    Picker("废纸篓中的应用", selection: trashArrivalSelection) {
                        ForEach(arrivals) { arrival in
                            Text(arrival.name).tag(Optional(arrival.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    Text("有 \(arrivals.count) 个应用刚进废纸篓").font(.callout.weight(.semibold))
                } else if selfEcho {
                    // 第二人称才是实话：用户没拖，是我们自己的按钮把它移走的。
                    Text("你刚卸载了 \(subject?.name ?? "")，残留还在").font(.callout.weight(.semibold))
                } else {
                    Text("刚拖进废纸篓：\(subject?.name ?? "")").font(.callout.weight(.semibold))
                }

                MMBadge(selfEcho ? "由 MacMaster 移入" : "本体已在废纸篓",
                        tint: MMColor.informational,
                        systemImage: selfEcho ? "tag" : "trash")

                Spacer(minLength: MMGap.sm)

                Button {
                    MMReveal.open(subject?.path ?? "")
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)

                Button("忽略") {
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
                    Text("按包名与容器证据扫残留…").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                }
            } else if model.hasScannedTrashResiduals == false {
                Text("还没扫残留。本体已经在废纸篓里，这里只列出它散在 ~/Library 的文件。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            } else if items.isEmpty {
                Text("按当前敏感度没有匹配到残留文件。")
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
                    Button("全选可删项") { model.toggleAllTrashResiduals() }
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
                    Label("清理勾选的残留", systemImage: "trash")
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
        if model.isScanningTrashResiduals { return "扫描中…" }
        guard model.hasScannedTrashResiduals else { return "尚未扫描" }
        var line = "已选 \(model.selectedTrashResidualCount) 项 · "
            + MMFormat.bytes(model.selectedTrashResidualSize)
        if model.unselectedTrashResidualCount > 0 {
            line += " · 未勾选 \(model.unselectedTrashResidualCount) 项"
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
            Text("清理 \(model.trashArrival?.name ?? "") 的 \(roots.count) 项残留？")
                .font(.title3.weight(.semibold))
            Text("只移除勾选的残留，\(model.trashArrival?.name ?? "这个应用") 的本体留在废纸篓里不动。"
                 + "标记为谨慎与只读的项不会进入这份列表。")
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

            Text("合计 \(MMFormat.bytes(model.selectedTrashResidualSize))，可在 15 秒内或「最近操作」中撤回。")
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)

            HStack {
                Spacer()
                Button("取消") { showTrashConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button("移入废纸篓") {
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
        case .homebrewCaskNameOnly: ("疑似 brew", MMColor.caution)
        default: nil
        }
    }

    /// 详情标题旁的徽章。`unknown` 没有徽章：把"没查到"做成一种属性是假话。
    var sourceBadge: (text: String, tint: Color, symbol: String)? {
        switch provenance.source {
        case .homebrewCask:
            ("Homebrew cask · \(provenance.cask?.token ?? "")", MMColor.informational, "shippingbox")
        case .homebrewCaskNameOnly:
            ("疑似 Homebrew cask", MMColor.caution, "questionmark.circle")
        case .appStore:
            ("App Store", MMColor.secondaryLabel, "app.badge")
        case .installerPackage:
            ("安装包", MMColor.secondaryLabel, "square.and.arrow.down")
        case .unknown:
            nil
        }
    }

    /// 「来源」键值行。
    var sourceValue: String {
        guard let cask = provenance.cask else {
            switch provenance.source {
            case .appStore: return "Mac App Store"
            case .installerPackage: return "安装包 · \(provenance.packageIdentifier ?? "")"
            case .unknown:
                let tokens = provenance.ambiguousCaskTokens
                if tokens.isEmpty { return "无法判定" }
                return provenance.ambiguousByDeviceIdentity
                    ? "无法判定（\(tokens.joined(separator: "、")) 两份账本把同一个 .app 摆到了这里）"
                    : "无法判定（两个 cask 都声明了这个名字：\(tokens.joined(separator: "、"))）"
            default: return "无法判定"
            }
        }
        switch provenance.source {
        case .homebrewCask:
            var line = "Homebrew cask · \(cask.token)"
            if let version = cask.version { line += " \(version)" }
            if let tap = cask.tap { line += "（tap \(tap)）" }
            return line
        case .homebrewCaskNameOnly:
            return "可能是 Homebrew cask · \(cask.token)（只有名字对上）"
        default: return "无法判定"
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
            "判定依据：Caskroom 里 staged 的 \(bundleName).app 链接解析后与本 bundle 是同一个文件"
                + "（设备号 + inode 相同）。这里只读账本，不执行 brew；把 bundle 移进废纸篓不会让 brew 的账本同步。"
        case .homebrewCaskNameOnly:
            "判定依据：账本声明了 \(bundleName).app，但那一份 staged 链接指向别处或已经失效，"
                + "没验证到与本 bundle 是同一个文件。这一档不给 brew 命令。"
        case .appStore:
            "判定依据：bundle 内有 Contents/_MASReceipt/receipt。收据跟着 bundle 走，拷贝一份也带着，"
                + "所以排在设备号证据之后。"
        case .installerPackage:
            "判定依据：包名出现在 /var/db/receipts 的已装包清单里。收据可能在卸载后仍然留着，"
                + "所以它只用来标来源，不参与任何删除判断。"
        case .unknown:
            provenance.ambiguousCaskTokens.isEmpty
                ? "判定依据：没有 brew 账本、App Store 收据或安装包凭据对得上。"
                    + "「无法判定」不等于「手动安装」——装在别的卷、换了名字、用了别的安装器都会落在这里。"
                : (provenance.ambiguousByDeviceIdentity
                    ? "判定依据：\(provenance.ambiguousCaskTokens.joined(separator: " 与 ")) 的 Caskroom staged 链接"
                        + "解析后都是本 bundle（设备号 + inode 相同）——两份账本在抢同一份文件，不替用户挑一个。"
                    : "判定依据：\(provenance.ambiguousCaskTokens.joined(separator: " 与 ")) 两份账本都声明了同一个 "
                        + ".app 名字，不替用户挑第一个。")
        }
    }

    /// 确认面板的提醒。只有 brew 两档有：这一页的删除动作只有废纸篓一条路径，
    /// 而 brew 装的app走这条路会让账本失真——那是一件做完之后才会发现的事。
    var sourceWarning: String? {
        switch provenance.source {
        case .homebrewCask:
            guard let token = provenance.cask?.token else { return nil }
            return "这个应用由 Homebrew cask 安装。移到废纸篓只会动 \(path)，"
                + "brew 的账本不会跟着更新；要连账本一起清，请自己执行 brew uninstall --cask \(token)。"
                + "MacMaster 不会代你运行 brew。"
        case .homebrewCaskNameOnly:
            guard let token = provenance.cask?.token else { return nil }
            return "来源只是名字对上（token：\(token)），没有按设备号验证。"
                + "若是 brew 装的，删除后 brew 的账本可能与实际不符。"
        default: return nil
        }
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

    var body: some View {
        HStack(spacing: MMGap.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .opacity(goneFromDirectory ? 0.55 : 1)
                .frame(width: MMMetric.iconApp, height: MMMetric.iconApp)

            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(app.name).font(.body).lineLimit(1)
                if goneFromDirectory {
                    Text("已在目录里消失，待重新载入")
                        .font(.caption)
                        .foregroundStyle(MMColor.caution)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    HStack(spacing: MMGap.xs) {
                        if let chip = app.sourceChip {
                            SourceChip(text: chip.text, tint: chip.tint)
                        }
                        // 版本号长度不可控（ChatGPT 是 26.924.22138），不限行就会折成两行
                        // 把整行撑高。这里不能用 fixedSize：它会把空间全部划给大小，
                        // 反过来把 "6.9.3" 这种短版本号截成 "6.…"。让大小优先、版本让步。
                        Text(app.version.isEmpty ? "未知版本" : app.version)
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
                Text("不在磁盘")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MMColor.caution)
            } else if app.residuals.isEmpty == false {
                VStack(alignment: .trailing, spacing: MMGap.xxs) {
                    Text("\(app.residuals.count) 项残留")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MMColor.accent)
                    Text(MMFormat.bytes(app.residualSize))
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .monospacedDigit()
                }
            } else if app.isSystemOwned {
                MMBadge("系统应用", tint: MMColor.secondaryLabel)
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
            MMStatItem("应用大小", MMFormat.bytes(app.size))
            MMStatItem("包含文件", app.fileCount.map { MMFormat.count($0) } ?? "测量中")
            MMStatItem("残留大小", MMFormat.bytes(app.residualSize))
            MMStatItem("残留项", MMFormat.count(app.residuals.count))
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            Text("基本信息").font(.headline)
            VStack(alignment: .leading, spacing: MMGap.xs) {
                MMKeyRow("来源", app.sourceValue)
                if let receipt = app.sourceReceipt {
                    MMKeyRow("来源凭据", receipt, monospaced: true)
                }
                if let command = app.sourceCommand {
                    MMKeyRow("对应命令", command, monospaced: true)
                }
                MMKeyRow("包名", app.bundleID, monospaced: true)
                MMKeyRow("版本", app.version.isEmpty ? "" : "\(app.version) (\(app.build))")
                MMKeyRow("开发者", app.developer.isEmpty ? "" : "\(app.developer)（来自代码签名）")
                MMKeyRow("最低系统", app.minSystemVersion)
                MMKeyRow("可执行文件", app.executable)
                MMKeyRow("修改时间", MMFormat.dateTime(app.modificationDate))
                MMKeyRow("所在文件夹", (app.path as NSString).deletingLastPathComponent)
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
                Text("将一并移除的残留").font(.headline)
                if unselectedCount > 0 {
                    MMBadge("\(unselectedCount) 项默认不勾选", tint: MMColor.caution, systemImage: "exclamationmark.triangle")
                }
                Spacer(minLength: MMGap.sm)
                Text("按包名与容器证据匹配 · 不含其他应用的共享文件")
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                Button(action: onToggleAll) {
                    Label("全选可删项", systemImage: "checklist")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }

            if app.isSystemOwned {
                Text("系统自带应用不提供残留扫描：它的数据由系统管理，删除不会回收空间。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .padding(MMGap.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MMColor.recessedSurface, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            } else if app.residuals.isEmpty {
                Text("没有按当前敏感度匹配到残留文件。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .padding(MMGap.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MMColor.recessedSurface, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            } else {
                residualGroups
            }

            HStack(alignment: .top, spacing: MMGap.sm) {
                Image(systemName: "info.circle").foregroundStyle(MMColor.tertiaryLabel)
                Text(confirmationNote)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            Button(role: .destructive, action: onUninstallWithResiduals) {
                Label("卸载应用并移除勾选的残留", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MMColor.destructive)

            Button("仅卸载应用，保留所有残留", action: onUninstallAppOnly)
                .controlSize(.small)
                .buttonStyle(.borderless)
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
                        Text("\(group.items.count) 项")
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
        return "卸载会把 \(app.name) 以及勾选的 \(selectedCount) 项残留（合计 \(size)）移到废纸篓，可在 15 秒内或「最近操作」中撤回。"
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
struct ResidualRow: View {
    let item: ResidualItem
    @Binding var isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
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
            .help("在访达中显示")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
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
            subtitle: "\(item.displayPath) · 在已装应用里找不到 \(item.owner)",
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
            .help("在访达中显示")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}
