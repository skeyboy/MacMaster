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
// 视觉对照设计稿 `docs/design-system/screens/03-uninstaller.html`：
// 左侧应用列表 + 右侧详情（信息卡 / 键值对 / 将一并移除的残留），底部操作栏收口。
// 颜色、间距、圆角、行高一律取 MM* 令牌，不写死数值。

public struct UninstallerView: View {
    @StateObject private var model = UninstallerModel()
    @State private var searchText = ""
    @State private var showConfirm = false
    @State private var toastSeconds = 0

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

            HStack(spacing: 0) {
                appList
                    .frame(width: MMMetric.inspector)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            actionBar
        }
        .task {
            if model.apps.isEmpty, model.isScanningApps == false {
                await model.loadApps()
            }
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
            toastSeconds = 15
        }
        .sheet(isPresented: $showConfirm) { confirmSheet }
        .overlay(alignment: .bottom) {
            if model.lastResult != nil, toastSeconds > 0 {
                MMUndoToast(
                    message: "已卸载 \(model.lastResult?.successCount ?? 0) 项",
                    detail: MMFormat.bytes(model.lastResult?.totalSize),
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
            .background(MMColor.cardBackground)
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
                onUninstallWithResiduals: { showConfirm = true },
                onUninstallAppOnly: { Task { await model.uninstallAppOnly() } }
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
            note: model.unselectedCount > 0 ? "未勾选的 \(model.unselectedCount) 项不会被修改" : "未勾选项不会被修改",
            trailing: {
                Button("仅卸载应用") {
                    Task { await model.uninstallAppOnly() }
                }
                .disabled(model.selectedApp == nil)

                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .disabled(model.selectedApp == nil)
            }
        )
    }

    // MARK: 确认

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: MMGap.md) {
            Text("确认卸载")
                .font(.title3.weight(.semibold))

            if let app = model.selectedApp {
                VStack(alignment: .leading, spacing: MMGap.xs) {
                    MMKeyRow("应用", app.name)
                    MMKeyRow("包名", app.bundleID, monospaced: true)
                    MMKeyRow("移除", "\(model.selectedResidualCount) 项残留 · \(MMFormat.bytes(model.selectedResidualSize))")
                    MMKeyRow("合计", MMFormat.bytes(model.selectedResidualSize))
                }

                Text("全部内容移到废纸篓，可在 15 秒内或「最近操作」中撤回。标记为谨慎与只读的项不会被删除。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            HStack(spacing: MMGap.sm) {
                Spacer()
                Button("取消") { showConfirm = false }
                Button("卸载", role: .destructive) {
                    showConfirm = false
                    Task { await model.uninstallAppWithSelection() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
            }
        }
        .padding(MMGap.lg)
        .frame(width: 420)
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
                    .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            } else if app.residuals.isEmpty {
                Text("没有按当前敏感度匹配到残留文件。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .padding(MMGap.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
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
                    .background(MMColor.cardBackground)

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
        return "卸载会把 \(app.name) 以及勾选的 \(selectedCount) 项残留（合计 \(size)）移到废纸篓，可在 15 秒内撤回。"
    }

    private var selectedCount: Int {
        app.residuals.filter { $0.risk.allowsDeletion && selectedIDs.contains($0.id) }.count
    }

    private var totalSelectedSize: UInt64 {
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
