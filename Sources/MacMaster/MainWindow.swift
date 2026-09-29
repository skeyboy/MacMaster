import SwiftUI
import MMCore
import MMUI

struct MainWindow: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            DetailView()
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .onAppear {
            LaunchMinimizeHandler.applyOnceIfEnabled(settings: settings)
            applyLaunchTargetIfNeeded()
        }
    }

    /// MM_OPEN_MODULE=optimizer 之类只用于逐屏截图核对设计稿，正常启动不会带这个变量。
    /// 放在 onAppear 而不是 App.init：侧边栏的 List(selection:) 首次渲染会把选中值写回 nil。
    private func applyLaunchTargetIfNeeded() {
        guard let target = ProcessInfo.processInfo.environment["MM_OPEN_MODULE"],
              let destination = MMDestination(rawValue: target), destination != .dashboard else { return }
        appState.selectedModuleID = destination.rawValue
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // App Header
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ThemeColor.primary, ThemeColor.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("MacMaster")
                    .font(.title3.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Module List
            List(selection: $appState.selectedModuleID) {
                ForEach(moduleRegistry.modules) { module in
                    NavigationLink(value: module.id) {
                        Label(module.name, systemImage: module.iconName)
                            .font(.body)
                    }
                    .tag(module.id)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Settings
            Button {
                appState.showSettings = true
            } label: {
                Label("设置", systemImage: "gear")
                    .font(.body)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState

    // 已访问过的模块保持常驻视图树，避免 SwiftUI 回收其 @State
    @State private var visitedModuleIDs: Set<String> = []

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
        switch destination {
        case .dashboard:
            visitedModuleIDs = []
            appState.selectedModuleID = nil
        default:
            visitedModuleIDs.insert(destination.rawValue)
            appState.selectedModuleID = destination.rawValue
        }
    }

    @ViewBuilder
    private var content: some View {
        if visitedModuleIDs.isEmpty {
            DashboardView(isActive: appState.selectedModuleID == nil)
        } else {
            ZStack {
                ForEach(moduleRegistry.modules) { module in
                    if visitedModuleIDs.contains(module.id) {
                        let isActive = module.id == appState.selectedModuleID
                        module.viewBuilder()
                            .opacity(isActive ? 1 : 0)
                            .allowsHitTesting(isActive)
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    /// 视图在模块切换后仍留在视图树里（为了保住各模块的 @State），
    /// 所以采样必须显式 gated，否则后台会一直转。
    var isActive: Bool = true

    @StateObject private var model = DashboardModel()
    @ObservedObject private var trashService = FileTrashService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MMGap.lg) {
                header
                storageCard
                loadCard
                recentCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MMGap.xl)
        }
        .background(MMColor.contentBackground)
        .task(id: isActive) {
            guard isActive else { return }
            await model.sampleContinuously()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text("概览").font(.title2.weight(.semibold))
                Text(model.sampledAt.map { "上次采样 " + MMFormat.relative($0) } ?? "正在读取系统状态…")
                    .font(.caption).foregroundStyle(MMColor.secondaryLabel)
            }
            Spacer()
            Button {
                Task { await model.measureReclaimable() }
            } label: {
                Label("重新测量", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isMeasuringReclaimable)
        }
    }

    // MARK: 存储

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            sectionTitle("存储", trailing: model.volume.map { MMFormat.percent($0.usedRatio) + " 已用" })

            if let volume = model.volume {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MMColor.fillActive)
                        Capsule()
                            .fill(MMColor.accent)
                            .frame(width: max(2, proxy.size.width * volume.usedRatio))
                    }
                }
                .frame(height: 6)

                HStack(spacing: MMGap.lg) {
                    legend(color: MMColor.accent, text: "已用 \(MMFormat.bytes(volume.used))")
                    legend(color: MMColor.fillActive, text: "可用 \(MMFormat.bytes(volume.available))")
                    Spacer()
                    Text("\(volume.name) · 共 \(MMFormat.bytes(volume.total))")
                        .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                }
            } else {
                Text("未能读取启动卷信息").font(.callout).foregroundStyle(MMColor.secondaryLabel)
            }

            Divider()

            HStack(spacing: MMGap.sm) {
                Text("可清理缓存").font(.callout)
                Spacer()
                if model.isMeasuringReclaimable || model.reclaimableBytes == nil {
                    Text(model.measureFailed ? "测量失败" : "测量中…")
                        .font(.callout).foregroundStyle(MMColor.secondaryLabel)
                } else {
                    Text(MMFormat.bytes(model.reclaimableBytes))
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(MMColor.informational)
                }
                Button("去清理") { MMNavigation.go(.cleaner) }
                    .buttonStyle(.bordered).controlSize(.small)
            }

            HStack(spacing: MMGap.sm) {
                Text("重复文件").font(.callout)
                Spacer()
                Text("需先扫描").font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                Button("去检测") { MMNavigation.go(.optimizer) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(MMGap.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.controlBackground, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator))
    }

    // MARK: 负载

    private var loadCard: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            sectionTitle("系统负载", trailing: nil)

            HStack(alignment: .top, spacing: MMGap.lg) {
                metric(title: "CPU",
                       value: model.cpuLoad.map { MMFormat.percent($0) } ?? "—",
                       note: "\(model.coreCount) 核",
                       ratio: model.cpuLoad)
                metric(title: "内存",
                       value: model.memory.map { MMFormat.percent($0.pressure) } ?? "—",
                       note: model.memory.map { "\(MMFormat.bytes($0.used)) / \(MMFormat.bytes($0.total))" } ?? "—",
                       ratio: model.memory?.pressure)
                VStack(alignment: .leading, spacing: MMGap.xxs) {
                    Text("网络").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                    Text(model.netRate.map { MMFormat.compactBytes($0.received) + "/s" } ?? "—")
                        .font(.title3).monospacedDigit()
                    Text(model.netRate.map { "↑ " + MMFormat.compactBytes($0.sent) + "/s" } ?? "上传 —")
                        .font(.caption).foregroundStyle(MMColor.tertiaryLabel).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(MMGap.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.controlBackground, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator))
    }

    private func metric(title: String, value: String, note: String, ratio: Double?) -> some View {
        VStack(alignment: .leading, spacing: MMGap.xxs) {
            Text(title).font(.caption).foregroundStyle(MMColor.secondaryLabel)
            Text(value).font(.title3).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(MMColor.tertiaryLabel).monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MMColor.fillActive)
                    Capsule().fill(MMColor.accent)
                        .frame(width: max(0, proxy.size.width * min(1, max(0, ratio ?? 0))))
                }
            }
            .frame(width: 72, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 最近操作

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            sectionTitle("最近操作", trailing: "只有移入废纸篓的动作可以撤回")

            if trashService.trashHistory.isEmpty {
                HStack(spacing: MMGap.sm) {
                    Text("还没有清理记录。").font(.callout).foregroundStyle(MMColor.secondaryLabel)
                    Spacer()
                    Button("开始清理") { MMNavigation.go(.cleaner) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                ForEach(model.trashHistory) { operation in
                    HStack(spacing: MMGap.sm) {
                        Image(systemName: operation.errors.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.system(size: MMMetric.iconSmall))
                            .foregroundStyle(operation.errors.isEmpty ? MMColor.safe : MMColor.caution)
                        Text("\(operation.fileCount) 个文件")
                            .font(.callout)
                        Text(MMFormat.bytes(operation.totalSize))
                            .font(.callout).monospacedDigit()
                            .foregroundStyle(MMColor.secondaryLabel)
                        if !operation.errors.isEmpty {
                            MMBadge("\(operation.errors.count) 项失败", tint: MMColor.caution)
                        }
                        if operation.isUndone {
                            MMBadge("已撤回", tint: MMColor.secondaryLabel)
                        }
                        Spacer()
                        Text(MMFormat.relative(operation.timestamp))
                            .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                        Button("撤回") {
                            Task { await model.undo(operation) }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(operation.isUndone)
                    }
                    .frame(height: MMMetric.rowCompact)
                }
            }
        }
        .padding(MMGap.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.controlBackground, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator))
    }

    // MARK: 小件

    private func sectionTitle(_ text: String, trailing: String?) -> some View {
        HStack(spacing: MMGap.sm) {
            Text(text).font(.headline)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(MMColor.secondaryLabel).monospacedDigit()
            }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: MMGap.xs) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(MMColor.secondaryLabel).monospacedDigit()
        }
    }
}
