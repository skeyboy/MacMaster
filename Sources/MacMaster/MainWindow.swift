import SwiftUI
import MMCore
import MMUI
import MMOptimizer

struct MainWindow: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    /// 概览的读数放在这一层：侧边栏的"系统清理 2.4 GB"和概览页要用同一个测量结果，
    /// 各自采一份迟早会打架（一个显示 2.4 一个显示 2.6）。
    @StateObject private var dashboard = DashboardModel()

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            DetailView()
        }
        .environmentObject(dashboard)
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        // 采样挂在这一层而不是概览页：侧边栏底部那根容量条在每一页都要显示，
        // 挂在概览页上就会在别的模块里量不到。窗口开着才采样，窗口关掉任务即取消。
        .task { await dashboard.sampleContinuously() }
        .onAppear {
            LaunchMinimizeHandler.applyOnceIfEnabled(settings: settings)
            applyLaunchTargetIfNeeded()
            LaunchWindowSizeOverride.applyOnce()
            MMWindowProbe.start()
        }
    }

    /// MM_OPEN_MODULE=optimizer 之类只用于逐屏截图核对设计稿，正常启动不会带这个变量。
    /// 放在 onAppear 而不是 App.init：侧边栏的 List(selection:) 首次渲染会把选中值写回 nil。
    private func applyLaunchTargetIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        if env["MM_SHOW_SETTINGS"] != nil {
            appState.showSettings = true
        }
        guard let target = env["MM_OPEN_MODULE"] else { return }
        guard let destination = MMDestination(rawValue: target) else {
            // 写错一个字母就会停在概览，而截图看上去照样是"跑通了"。
            // 这种假通过必须在日志里留痕，核对的人才有东西可查。
            FileHandle.standardError.write("MM_OPEN_MODULE=\(target) 不是已知模块，仍停在概览\n".data(using: .utf8)!)
            return
        }
        guard destination != .dashboard else { return }
        appState.selectedModuleID = destination.rawValue
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dashboard: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            // App Header
            HStack(spacing: MMGap.sm) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MMColor.accent, MMColor.informational],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("MacMaster")
                    .font(.title3.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, MMGap.lg)
            .padding(.vertical, MMGap.md)

            Divider()

            // Module List
            List(selection: $appState.selectedModuleID) {
                Section {
                    NavigationLink(value: MMDestination.dashboard.rawValue) {
                        Label("概览", systemImage: "gauge")
                            .font(.body)
                    }
                    .tag(MMDestination.dashboard.rawValue)

                    ForEach(moduleRegistry.modules) { module in
                        NavigationLink(value: module.id) {
                            HStack(spacing: MMGap.xs) {
                                Label(module.name, systemImage: module.iconName)
                                    .font(.body)
                                Spacer(minLength: MMGap.sm)
                                // 尾巴上的数字来自概览页那次真实扫描，所以没扫过时这一格是空的，
                                // 不是显示一个 "—"：侧边栏常年挂着个未知数比不挂更糟。
                                if module.id == MMDestination.cleaner.rawValue,
                                   case .measured(let total, _) = dashboard.reclaimState {
                                    Text(MMFormat.bytes(total))
                                        .font(.caption).monospacedDigit()
                                        .foregroundStyle(MMColor.tertiaryLabel)
                                }
                            }
                        }
                        .tag(module.id)
                    }
                } header: {
                    Text("功能模块")
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                }
            }
            .listStyle(.sidebar)

            Divider()

            volumeFooter

            // Settings
            Button {
                appState.showSettings = true
            } label: {
                Label("设置", systemImage: "gear")
                    .font(.body)
            }
            .padding(.horizontal, MMGap.lg)
            .padding(.vertical, MMGap.sm)
        }
    }

    /// 设计稿把"还剩多少空间"放在侧边栏底部：它是用户决定要不要清理的第一信号，
    /// 不该只在概览页看得到。可用低于 10% 时条子转红，与概览页同一阈值。
    private var volumeFooter: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            if let volume = dashboard.volume {
                HStack(spacing: MMGap.xs) {
                    Image(systemName: "internaldrive")
                        .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                    Text(volume.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text(MMFormat.percent(1 - volume.usedRatio, digits: 0))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(MMColor.tertiaryLabel)
                }
                MMStackedBar(segments: [
                    MMBarSegment(id: "used", label: "已用", value: Double(volume.used),
                                 color: StorageBreakdown.isLowSpace(total: volume.total, available: volume.available)
                                     ? MMColor.destructive : MMColor.accent),
                    MMBarSegment(id: "available", label: "可用", value: Double(volume.available),
                                 color: MMColor.fillActive),
                ], height: 4)
            } else {
                Text("未能读取启动卷容量").font(.caption).foregroundStyle(MMColor.tertiaryLabel)
            }
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.md)
    }
}

// MARK: - Detail View

struct DetailView: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState

    // 已访问过的模块保持常驻视图树，避免 SwiftUI 回收其 @State
    @State private var visitedModuleIDs: Set<String> = []

    private static let dashboardID = MMDestination.dashboard.rawValue

    var body: some View {
        content
            .onAppear {
                if let id = appState.selectedModuleID { visitedModuleIDs.insert(id) }
            }
            .onChange(of: appState.selectedModuleID) { _, newID in
                if let id = newID { visitedModuleIDs.insert(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: MMNavigation.didRequestDestination)) { note in
                guard let raw = note.object as? String, let destination = MMDestination(rawValue: raw) else { return }
                navigate(to: destination)
            }
    }

    /// 侧边栏之外还要能跳转：诊断项、仪表盘的入口都走这里。
    private func navigate(to destination: MMDestination) {
        appState.selectedModuleID = destination.rawValue
        if destination != .dashboard { visitedModuleIDs.insert(destination.rawValue) }
    }

    @ViewBuilder
    private var content: some View {
        let selected = appState.selectedModuleID ?? Self.dashboardID
        ZStack {
            if selected == Self.dashboardID {
                DashboardView()
            }
            ForEach(moduleRegistry.modules) { module in
                if visitedModuleIDs.contains(module.id) {
                    let isActive = module.id == selected
                    module.viewBuilder()
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                }
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    /// 模型挂在 MainWindow 上：侧边栏那个"系统清理 2.4 GB"和概览页必须同源，
    /// 采样也由那一层驱动，这里只读不采。
    @EnvironmentObject private var model: DashboardModel
    /// 清理历史存在 FileTrashService 里（模型只是转发），所以视图必须观察它，
    /// 否则撤回完页面还是旧列表。
    @ObservedObject private var trashService = FileTrashService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MMGap.md) {
                storageCard
                HStack(alignment: .top, spacing: MMGap.md) {
                    loadCard
                    VStack(spacing: MMGap.md) {
                        reclaimableCard
                        recentCard
                    }
                    .frame(width: 300)
                }
                if !model.undoFailures.isEmpty {
                    MMFailurePanel(summary: "撤回未完成，文件仍在废纸篓", model.undoFailures) {
                        model.undoFailures = []
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MMGap.lg)
        }
        .background(MMColor.contentBackground)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    private var header: some View {
        MMPageHeader("概览", subtitle: headerSubtitle) {
            Button {
                Task { await model.measureReclaimable() }
            } label: {
                Label("重新测量", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.reclaimState == .measuring)
        }
    }

    private var headerSubtitle: String {
        guard let sampledAt = model.sampledAt else { return "正在读取系统状态…" }
        return "上次采样 " + MMFormat.relative(sampledAt)
            + " · CPU/内存/磁盘均为本机实时读数"
    }

    /// 底部状态条：设计稿放在内容区最下方。只报量得到的事实，
    /// 卷数来自挂载表、文件系统名来自 statfs、上次清理来自废纸篓记录。
    private var statusBar: some View {
        HStack(spacing: MMGap.sm) {
            Text("\(model.volumeCount) 个卷")
            if let filesystem = model.filesystemName {
                Text("·")
                Text("文件系统 \(filesystem)")
            }
            Text("·")
            Text(model.lastCleanupAt.map { "上次清理 " + MMFormat.relative($0) } ?? "尚无清理记录")
            Spacer()
            Text("数据更新于 \(MMFormat.dateTime(model.sampledAt))")
        }
        .font(.caption).monospacedDigit().foregroundStyle(MMColor.tertiaryLabel)
        .padding(.horizontal, MMGap.lg)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(MMColor.recessedSurface)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: 存储

    private var storageCard: some View {
        MMCard {
            VStack(alignment: .leading, spacing: MMGap.sm) {
                HStack(spacing: MMGap.sm) {
                    Text("存储").font(.headline)
                    if let volume = model.volume,
                       StorageBreakdown.isLowSpace(total: volume.total, available: volume.available) {
                        MMBadge("可用空间偏低", tint: MMColor.destructive)
                    }
                    Spacer()
                    if let volume = model.volume {
                        Text("\(MMFormat.bytes(volume.available)) 可用 · 共 \(MMFormat.bytes(volume.total))")
                            .font(.caption).monospacedDigit().foregroundStyle(MMColor.secondaryLabel)
                    } else {
                        Text(DashboardText.placeholder + " 可用")
                            .font(.caption).monospacedDigit().foregroundStyle(MMColor.secondaryLabel)
                    }
                }

                if let volume = model.volume {
                    MMStackedBar(segments: storageSegments, height: 8)
                    MMLegend(storageLegend)
                    Text("\(volume.name) · 已用 \(MMFormat.percent(volume.usedRatio))")
                        .font(.caption2).monospacedDigit().foregroundStyle(MMColor.tertiaryLabel)
                } else {
                    Text("未能读取启动卷容量（volumeTotalCapacity / 重要用途可用容量均未返回），这里不猜数字。")
                        .font(.caption).foregroundStyle(MMColor.secondaryLabel)
                }

                Divider()

                HStack(spacing: MMGap.sm) {
                    releaseText
                    Spacer(minLength: MMGap.md)
                    Button("查看占用排行") { MMNavigation.go(.disk) }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button(releaseButtonTitle) { MMNavigation.go(.cleaner) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
    }

    /// 堆叠条的配色只区分"种类"，不表达好坏：可清理=信息蓝、废纸篓=橙、
    /// 其他已用=主色、可用=极淡的填充色（可用本来就该"看起来没有"）。
    private var storageSegments: [MMBarSegment] {
        model.storageSegments.map { segment in
            MMBarSegment(id: segment.id, label: segment.label,
                         value: Double(segment.bytes), color: storageColor(segment.id))
        }
    }

    private func storageColor(_ id: String) -> Color {
        switch id {
        case "reclaimable": MMColor.informational
        case "trash": MMColor.caution
        case "available": MMColor.fillActive
        default: MMColor.accent
        }
    }

    private var storageLegend: [MMLegend.Item] {
        model.storageSegments.map {
            MMLegend.Item(id: $0.id, text: "\($0.label) \(MMFormat.bytes($0.bytes))",
                          color: storageColor($0.id))
        }
    }

    /// "可立即释放" = 真实扫描的可清理 + 废纸篓实测。没扫过就明说没扫过，
    /// 不拿"已用-系统保留"之类的减法凑一个数字出来。
    private var releasableBytes: UInt64? {
        guard case .measured(let total, _) = model.reclaimState else { return nil }
        return total + (model.trashBytes ?? 0)
    }

    private var releaseText: some View {
        HStack(spacing: MMGap.xs) {
            Text("可立即释放").font(.callout)
            if let releasableBytes {
                Text(MMFormat.bytes(releasableBytes))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(MMColor.informational)
                Text(releaseDetail).font(.caption).foregroundStyle(MMColor.tertiaryLabel).monospacedDigit()
            } else {
                Text(DashboardText.reclaimableText(model.reclaimState))
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(MMColor.secondaryLabel)
            }
        }
        .help(DashboardText.reclaimDetailText(model.reclaimState))
    }

    private var releaseDetail: String {
        guard case .measured(let total, _) = model.reclaimState else { return "" }
        guard let trash = model.trashBytes else { return "（可清理 \(MMFormat.bytes(total)) · 废纸篓未读到）" }
        return "（可清理 \(MMFormat.bytes(total)) + 废纸篓 \(MMFormat.bytes(trash))）"
    }

    private var releaseButtonTitle: String {
        guard let releasableBytes else { return "去扫描" }
        return "清理 \(MMFormat.bytes(releasableBytes))"
    }

    // MARK: 负载

    private var loadCard: some View {
        MMCard(padding: 0) {
            VStack(spacing: 0) {
                cardHeader("系统负载", trailing: AnyView(
                    Group {
                        if let verdict = LoadVerdict.text(cpu: model.cpuLoad,
                                                          memoryPressure: model.memory?.pressure) {
                            MMBadge(verdict, tint: verdict == "运行平稳" ? MMColor.safe : MMColor.caution)
                        }
                    }
                ))

                HStack(spacing: MMGap.lg) {
                    gaugeRow(title: "CPU",
                             ratio: model.cpuLoad,
                             value: DashboardText.cpuCaliberNote(coreCount: model.coreCount),
                             note: DashboardText.cpuCoreNote(total: model.coreCount,
                                                             performance: model.performanceCoreCount,
                                                             efficiency: model.efficiencyCoreCount))
                        .help("口径：host_statistics 两次采样差分，跨所有核的总占用率（非每核）；首次差分出结果前显示 —。")
                    gaugeRow(title: "内存",
                             ratio: model.memory?.pressure,
                             value: DashboardText.memoryUsedText(model.memory),
                             note: DashboardText.swapText(model.memory))
                        .help("口径：(active + wired + compressed) × pageSize，不含可即时回收的 inactive。")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MMGap.lg)
                .padding(.vertical, MMGap.md)

                Divider()

                memoryComposition

                Divider()

                HStack(spacing: MMGap.lg) {
                    metricMini(title: "网络",
                               value: model.netRate.map { MMFormat.rate(Double($0.received), up: false) }
                                   ?? DashboardText.placeholder,
                               history: model.netHistory,
                               note: model.netRate.map { MMFormat.rate(Double($0.sent), up: true) + " · 全部物理接口" }
                                   ?? "上传 \(DashboardText.placeholder)")
                    metricMini(title: "磁盘 I/O",
                               value: model.diskRead.map { "读 " + MMFormat.compactBytes(UInt64(max(0, $0))) + "/s" }
                                   ?? DashboardText.placeholder,
                               history: model.diskHistory,
                               note: diskIONote)
                        .help(model.diskIOFailure ?? "口径：IOKit IOBlockStorageDriver 累计字节两次采样差分，含全部磁盘驱动。")
                }
                .padding(.horizontal, MMGap.lg)
                .padding(.vertical, MMGap.md)
            }
        }
    }

    private var diskIONote: String {
        if let write = model.diskWrite {
            return "写 " + MMFormat.compactBytes(UInt64(max(0, write))) + "/s · 全部磁盘驱动"
        }
        return "写 \(DashboardText.placeholder) · \(model.diskIOFailure == nil ? "等待差分" : "IOKit 未返回统计")"
    }

    private func cardHeader(_ title: String, trailing: AnyView?) -> some View {
        HStack(spacing: MMGap.sm) {
            Text(title).font(.headline)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, MMGap.lg)
        .frame(height: 38)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func gaugeRow(title: String, ratio: Double?, value: String, note: String) -> some View {
        HStack(spacing: MMGap.md) {
            MMGauge(ratio: ratio, text: ratio.map { MMFormat.percent($0, digits: 0) } ?? DashboardText.placeholder)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(title).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                Text(value).font(.callout).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Text(note).font(.caption2).monospacedDigit().foregroundStyle(MMColor.tertiaryLabel).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var memoryComposition: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            HStack(spacing: MMGap.sm) {
                Text("内存构成").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                Spacer()
                if let parts = model.memoryParts {
                    Text(parts.map { "\($0.label) \(MMFormat.bytes($0.bytes))" }.joined(separator: " · "))
                        .font(.caption2).monospacedDigit().foregroundStyle(MMColor.tertiaryLabel)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if let parts = model.memoryParts {
                MMStackedBar(segments: parts.map {
                    MMBarSegment(id: $0.id, label: $0.label, value: Double($0.bytes), color: memoryColor($0.id))
                }, height: 8)
            } else {
                Text("三项没读全就不画构成：缺的那段并进“未占用”会画出一条骗人的绿条。")
                    .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
            }
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.md)
    }

    private func memoryColor(_ id: String) -> Color {
        switch id {
        case "active": MMColor.accent
        case "wired": MMColor.informational
        case "compressed": MMColor.caution
        default: MMColor.fillActive
        }
    }

    private func metricMini(title: String, value: String, history: [Double?], note: String) -> some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            HStack(alignment: .firstTextBaseline, spacing: MMGap.sm) {
                Text(title).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                Spacer(minLength: MMGap.xs)
                Text(value).font(.callout.weight(.medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            MMSparkline(values: history)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(note).font(.caption2).monospacedDigit().foregroundStyle(MMColor.tertiaryLabel)
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 可释放空间

    private struct ReclaimRow: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let bytes: UInt64
        let systemImage: String
        let isDeletable: Bool
    }

    /// 只列真实扫描出来的分类，按大小取前三，再补一行废纸篓。
    /// 只读分类保留在列表里但置灰加锁——设计稿要传达的是"这里能看到，但不动它"。
    private var reclaimRows: [ReclaimRow] {
        let top = model.categories
            .sorted { $0.scannedSize > $1.scannedSize }
            .prefix(3)
            .map { category in
                ReclaimRow(id: category.id,
                           name: category.name,
                           subtitle: "\(MMFormat.count(category.scannedFiles)) 项 · \(category.risk.label)",
                           bytes: category.scannedSize,
                           systemImage: category.risk.allowsDeletion ? category.iconName : "lock",
                           isDeletable: category.risk.allowsDeletion)
            }
        var rows = Array(top)
        if let trash = model.trashBytes, trash > 0 {
            rows.append(ReclaimRow(id: "trash", name: "废纸篓", subtitle: "移入后可撤回",
                                   bytes: trash, systemImage: "trash", isDeletable: true))
        }
        return rows
    }

    private var reclaimableCard: some View {
        MMCard(padding: 0) {
            VStack(spacing: 0) {
                cardHeader("可释放空间", trailing: AnyView(
                    Button("全部") { MMNavigation.go(.cleaner) }
                        .buttonStyle(.borderless).controlSize(.small)
                ))
                if reclaimRows.isEmpty {
                    VStack(alignment: .leading, spacing: MMGap.xs) {
                        Text(DashboardText.reclaimableText(model.reclaimState))
                            .font(.callout).foregroundStyle(MMColor.secondaryLabel)
                        Text(DashboardText.reclaimDetailText(model.reclaimState))
                            .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MMGap.lg)
                } else {
                    ForEach(Array(reclaimRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        reclaimRowView(row)
                    }
                }
            }
        }
    }

    private func reclaimRowView(_ row: ReclaimRow) -> some View {
        HStack(spacing: MMGap.md) {
            Image(systemName: row.systemImage)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(row.isDeletable ? MMColor.caution : MMColor.tertiaryLabel)
                .frame(width: MMMetric.iconSmall)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(row.name).font(.callout).lineLimit(1)
                Text(row.subtitle).font(.caption).foregroundStyle(MMColor.tertiaryLabel).lineLimit(1)
            }
            Spacer(minLength: MMGap.sm)
            Text(MMFormat.bytes(row.bytes))
                .font(.callout.monospaced()).monospacedDigit()
                .foregroundStyle(row.isDeletable ? MMColor.label : MMColor.secondaryLabel)
        }
        .padding(.horizontal, MMGap.lg)
        .frame(height: MMMetric.rowRegular)
        .contentShape(Rectangle())
        .onTapGesture { MMNavigation.go(.cleaner) }
    }

    // MARK: 最近操作

    private var recentCard: some View {
        MMCard(padding: 0) {
            VStack(spacing: 0) {
                cardHeader("最近操作", trailing: AnyView(
                    Text("只有移入废纸篓的动作可以撤回")
                        .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                ))
                if model.trashHistory.isEmpty {
                    HStack(spacing: MMGap.sm) {
                        Text("还没有清理记录。").font(.callout).foregroundStyle(MMColor.secondaryLabel)
                        Spacer(minLength: MMGap.sm)
                        Button("开始清理") { MMNavigation.go(.cleaner) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(MMGap.lg)
                } else {
                    ForEach(Array(model.trashHistory.enumerated()), id: \.element.id) { index, operation in
                        if index > 0 { Divider() }
                        recentRowView(operation)
                    }
                }
            }
        }
    }

    private func recentRowView(_ operation: TrashOperation) -> some View {
        HStack(spacing: MMGap.md) {
            Image(systemName: operation.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(operation.failures.isEmpty ? MMColor.safe : MMColor.caution)
                .frame(width: MMMetric.iconSmall)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text("移入废纸篓 \(MMFormat.bytes(operation.totalSize))")
                    .font(.callout).lineLimit(1)
                Text(recentSubtitle(operation))
                    .font(.caption).foregroundStyle(MMColor.tertiaryLabel).lineLimit(1)
            }
            Spacer(minLength: MMGap.sm)
            if operation.isUndone {
                MMBadge("已撤回", tint: MMColor.secondaryLabel)
            } else if operation.canUndo {
                Button("撤回") { Task { await model.undo(operation) } }
                    .buttonStyle(.borderless).controlSize(.small)
            } else {
                // 记录还在，但废纸篓里的那个文件已经不在了。按钮该在这里消失，
                // 而不是等用户按下去才拿到一个错误。
                MMBadge("废纸篓已清空", tint: MMColor.tertiaryLabel)
            }
        }
        .padding(.horizontal, MMGap.lg)
        .frame(height: MMMetric.rowRegular)
    }

    private func recentSubtitle(_ operation: TrashOperation) -> String {
        // 卡片只有 ~330pt 宽，"N 个文件"加上失败数就会被截掉尾巴，
        // 而失败数恰恰是最不该看不见的一段。统一用"项"。
        var text = MMFormat.relative(operation.timestamp) + " · \(MMFormat.count(operation.fileCount)) 项"
        if operation.failures.isEmpty == false {
            text += " · \(operation.failures.count) 项失败"
        }
        return text
    }
}
