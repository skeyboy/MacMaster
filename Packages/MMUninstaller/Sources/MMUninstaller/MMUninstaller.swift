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
    private enum Pane: String, CaseIterable {
        case apps, orphans
        var title: String { self == .apps ? "已装应用" : "卸载后遗症" }

        init?(hookValue: String) {
            let match = Pane.allCases.first { $0.rawValue == hookValue }
            guard let match else { return nil }
            self = match
        }
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

    @StateObject private var model = UninstallerModel()
    @StateObject private var trashWatcher = TrashWatcher()
    @ObservedObject private var settings = AppSettings.shared
    @State private var searchText = ""
    @State private var showConfirm = false
    @State private var confirmationMode: ConfirmationMode = .withResiduals
    @State private var showOrphanConfirm = false
    @State private var showTrashConfirm = false
    @State private var toastSeconds = 0
    @State private var pane: Pane =
        Pane(hookValue: ProcessInfo.processInfo.environment["MM_UNINSTALL_PANE"] ?? "") ?? .apps

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
        }
        .task {
            if let home = Self.confirmationFixtureHome {
                model.optionsFactory = { ResidualScanOptions(home: home) }
                model.appDirectoriesFactory = { _ in [home + "/Applications"] }
            }
            if model.apps.isEmpty, model.isScanningApps == false {
                await model.loadApps()
            }
            if let home = Self.confirmationFixtureHome,
               let app = model.apps.first(where: { $0.path.hasPrefix(home + "/Applications/") }) {
                model.select(app.id)
                let mode = ProcessInfo.processInfo.environment["MM_UNINSTALL_CONFIRM_MODE"]
                requestConfirmation(mode == "withResiduals" ? .withResiduals : .appOnly)
            }
            // 启动就落在「卸载后遗症」时 onChange(of: pane) 不会触发，这里补一次。
            startOrphanScanIfNeeded()
        }
        .onDisappear { trashWatcher.stop() }
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
                        AppListRow(app: app)
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
            Text(listFooter)
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
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
        let fixtureHome = Self.orphanFixtureHome
        Task {
            await model.scanOrphans(home: fixtureHome)
            guard let fixtureHome else { return }
            model.selectedOrphanIDs = Set(model.orphans.map(\.id))
            showOrphanConfirm = true
            FileHandle.standardError.write("已用夹具目录 \(fixtureHome) 自动勾选并打开确认面板\n".data(using: .utf8)!)
        }
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
                    MMKeyRow("包名", app.bundleID, monospaced: true)
                    MMKeyRow("本体", MMFormat.bytes(app.size))
                    MMKeyRow("残留", includeResiduals
                        ? "\(paths.count - 1) 项 · \(MMFormat.bytes(residualSize))"
                        : "保留，不修改")
                    MMKeyRow("合计", MMFormat.bytes(UninstallSelection.confirmationSize(
                        appSize: app.size, residualSize: residualSize, includeResiduals: includeResiduals)))
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

    /// 完全磁盘访问面板。守护页用的是同一个 URL scheme 参数，这里不另写一份。
    private static let fullDiskAccessPane = "com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"

    /// 无头截图用的假 home。规矩沿用 `MM_ORPHAN_FIXTURE_HOME`：只认 /tmp 之下，
    /// 因为这张卡片的终点是删除按钮。
    private static var trashScanHome: String? { TrashWatcher.fixtureScanHome() }

    /// 只认 /tmp 假 home：合成点击进不了原生勾选框，截图验证确认态只能靠钩子自动打开，
    /// 而那必须只在夹具目录成立时才允许。
    private static var trashConfirmHook: Bool {
        guard TrashWatcher.fixtureScanHome() != nil else { return false }
        return ProcessInfo.processInfo.environment["MM_SHOW_TRASH_CONFIRM"] == "1"
    }

    private func startTrashWatching() {
        guard settings.watchTrashForResidualCleanup else { return }
        trashWatcher.start()
        syncTrashNotice(with: trashWatcher.arrivals)
    }

    /// 监听端的清单是真相源：选中项不在清单里了（用户把它还原或彻底删除）就整块撤掉提示。
    /// 还原回去的应用残留是活的，这时候再挂着"清理残留"入口就是害人的。
    private func syncTrashNotice(with arrivals: [TrashArrival]) {
        if arrivals.isEmpty {
            model.selectTrashArrival(nil)
            return
        }
        if let current = model.trashArrival,
           arrivals.contains(where: { $0.id == current.id }) { return }
        guard let chosen = arrivals.last else { return }
        model.selectTrashArrival(chosen)
        Task {
            await model.scanTrashResiduals(home: Self.trashScanHome)
            if Self.trashConfirmHook { showTrashConfirm = true }
        }
    }

    @ViewBuilder
    private var trashRegion: some View {
        if settings.watchTrashForResidualCleanup == false {
            // 关掉就不留任何痕迹：把"已关闭"再在这页复述一遍，等于把设置页的话说两次。
            EmptyView()
        } else if case .unreadable(let reason, let needsFullDiskAccess) = trashWatcher.status {
            MMPermissionBanner(
                title: needsFullDiskAccess ? "读不到废纸篓" : "废纸篓现在读不了",
                detail: needsFullDiskAccess
                    ? reason + " 在系统设置里授予「完全磁盘访问」后，重新进入这一页或重启应用才会生效。"
                    : reason + " 这和权限无关，所以这里不放授权按钮。",
                settingsPane: needsFullDiskAccess ? Self.fullDiskAccessPane : nil
            )
        } else if trashWatcher.arrivals.isEmpty == false, pane == .apps {
            trashNoticeCard
        }
    }

    private var trashNoticeCard: some View {
        let arrivals = trashWatcher.arrivals
        let items = model.trashResidualItems
        let arrivalPath = model.trashArrival?.path ?? arrivals.last?.path ?? ""
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
                } else {
                    Text("刚拖进废纸篓：\(arrivals[0].name)").font(.callout.weight(.semibold))
                }

                MMBadge("本体已在废纸篓", tint: MMColor.informational, systemImage: "trash")

                Spacer(minLength: MMGap.sm)

                Button {
                    MMReveal.open(model.trashArrival?.path ?? arrivals.last?.path ?? "")
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)

                Button("忽略") { trashWatcher.dismiss() }
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
                Text(model.trashArrival?.bundleID ?? arrivals.last?.bundleID ?? "")
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

// MARK: - 应用列表行

struct AppListRow: View {
    let app: UninstallCandidate

    var body: some View {
        HStack(spacing: MMGap.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: MMMetric.iconApp, height: MMMetric.iconApp)

            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(app.name).font(.body).lineLimit(1)
                HStack(spacing: MMGap.xs) {
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

            Spacer(minLength: MMGap.sm)

            if app.residuals.isEmpty == false {
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
                Text(app.name).font(.title2.weight(.semibold)).lineLimit(1)
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
                MMKeyRow("包名", app.bundleID, monospaced: true)
                MMKeyRow("版本", app.version.isEmpty ? "" : "\(app.version) (\(app.build))")
                MMKeyRow("开发者", app.developer.isEmpty ? "" : "\(app.developer)（来自代码签名）")
                MMKeyRow("最低系统", app.minSystemVersion)
                MMKeyRow("可执行文件", app.executable)
                MMKeyRow("修改时间", MMFormat.dateTime(app.modificationDate))
                MMKeyRow("所在文件夹", (app.path as NSString).deletingLastPathComponent)
            }
            .textSelection(.enabled)
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
