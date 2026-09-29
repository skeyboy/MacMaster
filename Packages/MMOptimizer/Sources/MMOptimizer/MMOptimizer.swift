import SwiftUI
import MMCore
import MMFileScanner
import MMUI

public struct OptimizerModule: ModuleRegistrable {
    public var moduleID: String { "optimizer" }
    public var moduleName: String { "系统优化" }
    public var moduleIcon: String { "gearshape.2" }
    public var modulePriority: Int { 6 }
    public init() {}
    public func createView() -> AnyView { AnyView(OptimizerView()) }
}

// MARK: - 取消标记

/// 扫描是异步且耗时的，取消位必须能被 non-Sendable 之外的地方安全读写。
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock(); value = true; lock.unlock()
    }

    func reset() {
        lock.lock(); value = false; lock.unlock()
    }
}

// MARK: - View

public struct OptimizerView: View {
    /// MM_OPEN_TAB=duplicates|browser|status：只用于逐屏截图核对设计稿，
    /// 正常启动不会带这个变量。
    @State private var tab: OptimizerTab =
        OptimizerTab(rawValue: ProcessInfo.processInfo.environment["MM_OPEN_TAB"] ?? "") ?? .duplicates
    @StateObject private var duplicates = DuplicateScanModel()
    @StateObject private var diagnostics = SystemDiagnosticsModel()
    @StateObject private var browser = BrowserCacheModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            MMPageHeader("系统优化", subtitle: diagnostics.updatedAt)

            Picker("", selection: $tab) {
                ForEach(OptimizerTab.allCases) { t in Text(t.label).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)
            .padding(.horizontal, MMGap.lg)
            .padding(.vertical, MMGap.sm)

            Divider()

            switch tab {
            case .duplicates: duplicatesView
            case .browser: browserView
            case .status: statusView
            }
        }
        .background(MMColor.contentBackground)
        .environmentObject(duplicates)
    }

    // MARK: 重复文件

    private var duplicatesView: some View {
        VStack(spacing: 0) {
            HStack(spacing: MMGap.sm) {
                Text(duplicates.headline)
                    .font(.callout)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(2)
                Spacer(minLength: MMGap.md)
                if duplicates.isScanning {
                    Button("停止") { duplicates.cancel() }
                        .buttonStyle(.bordered)
                }
                Button {
                    Task { await duplicates.scan() }
                } label: {
                    Label(duplicates.hasScanned ? "重新扫描" : "查找重复文件",
                          systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(duplicates.isScanning)
            }
            .padding(.horizontal, MMGap.lg)
            .frame(height: MMMetric.rowRegular)

            if let progress = duplicates.progress {
                MMScanProgress(
                    action: progress.stage.rawValue,
                    currentPath: progress.currentPath,
                    processedCount: progress.processed,
                    estimatedRemaining: nil,
                    progress: progress.fraction
                )
            }

            if let caveat = duplicates.caveatText {
                MMPermissionBanner(title: "部分文件没能参与判定", detail: caveat)
            }

            duplicatesContent

            if !duplicates.trashFailures.isEmpty {
                MMFailurePanel(summary: nil, duplicates.trashFailures) {
                    duplicates.trashFailures = []
                }
            }

            duplicates.actionBar
        }
    }

    @ViewBuilder
    private var duplicatesContent: some View {
        if duplicates.isScanning && duplicates.groups.isEmpty {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in MMSkeletonRow() }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if duplicates.groups.isEmpty {
            MMEmptyState(
                systemImage: "doc.on.doc",
                title: duplicates.hasScanned ? "没有发现内容完全相同的文件" : "还未开始检测",
                detail: duplicates.scannedScope
            )
        } else {
            ScrollView {
                LazyVStack(spacing: MMGap.sm) {
                    ForEach(duplicates.groups) { group in
                        DuplicateGroupRow(group: group)
                    }
                }
                .padding(MMGap.md)
            }
        }
    }

    // MARK: 浏览器缓存

    private var browserView: some View {
        VStack(spacing: 0) {
            HStack(spacing: MMGap.sm) {
                Text(browser.headline)
                    .font(.callout).foregroundStyle(MMColor.secondaryLabel)
                Spacer(minLength: MMGap.md)
                Button {
                    Task { await browser.scan() }
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(browser.isScanning)
            }
            .padding(.horizontal, MMGap.lg)
            .frame(height: MMMetric.rowRegular)
            Divider()

            if browser.items.isEmpty {
                MMEmptyState(
                    systemImage: "globe",
                    title: browser.hasScanned ? "没有发现可清理的浏览器缓存" : "正在统计缓存体积…",
                    detail: "只读取用户目录下的浏览器缓存（Library/Caches），不碰历史记录、密码与 Cookie。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MMGap.xs) {
                        ForEach(browser.items) { item in
                            BrowserCacheRowView(item: item, model: browser)
                        }
                        .overlay(alignment: .bottom) { Divider() }
                    }
                    .padding(MMGap.sm)
                }
            }

            if !browser.failures.isEmpty {
                MMFailurePanel(browser.failures) { browser.failures = [] }
            }
        }
        .task { await browser.scanIfNeeded() }
    }

    // MARK: 系统状态

    private var statusView: some View {
        ScrollView {
            LazyVStack(spacing: MMGap.xs) {
                ForEach(diagnostics.checks) { check in
                    SystemCheckRow(check: check) {
                        Task { await diagnostics.refresh() }
                    }
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
            .padding(MMGap.sm)
        }
        .overlay {
            if diagnostics.checks.isEmpty {
                ProgressView().controlSize(.small)
            }
        }
        .task { await diagnostics.refresh() }
    }
}

enum OptimizerTab: String, CaseIterable, Identifiable {
    case duplicates, browser, status
    var id: String { rawValue }
    var label: String {
        switch self {
        case .duplicates: "重复文件"
        case .browser: "浏览器缓存"
        case .status: "系统状态"
        }
    }
}

// MARK: - 重复文件模型

@MainActor
final class DuplicateScanModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var progress: DuplicateScanProgress?
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var selection: Set<URL> = []
    @Published var unreadableCount = 0
    @Published var datalessCount = 0
    @Published var wasStopped = false
    @Published var toast: UndoToast?
    @Published var trashFailures: [TrashFailure] = []

    struct UndoToast: Equatable {
        let message: String
        let detail: String?
        let operationID: UUID
    }

    let scopes: [String] = {
        let home = NSHomeDirectory()
        return [home + "/Documents", home + "/Downloads", home + "/Desktop"]
    }()

    private var cancelFlag = CancelFlag()
    private var lastReport: DuplicateScanReport?

    var totalWaste: UInt64 { groups.reduce(0) { $0 + $1.wastedSpace } }

    var selectedSize: UInt64 {
        groups.reduce(0) { sum, group in
            sum + group.files.filter { selection.contains($0.path) }.reduce(0) { $0 + $1.size }
        }
    }

    var headline: String {
        if isScanning { return "正在按内容比对，未完成前不会给出结果。" }
        if wasStopped { return "扫描已停止，下面的结果不完整。" }
        guard hasScanned else { return "按文件内容比对，不看文件名。" }
        if groups.isEmpty { return "未发现内容完全相同的文件。" }
        let n = groups.reduce(0) { $0 + $1.files.count }
        return "\(groups.count) 组 · \(n) 个文件内容完全相同 · 每组保留一份后可释放 \(MMFormat.bytes(totalWaste))"
    }

    var scannedScope: String {
        let names = scopes.map { ($0 as NSString).lastPathComponent }.joined(separator: " / ")
        let base = "检测范围：\(names)。判定前会读完整个文件，内容不完全相同的不会被列在这里。"
        guard let lastReport else { return base }
        return base + " 本次比对 \(MMFormat.count(lastReport.candidateCount)) 个候选。"
    }

    var caveatText: String? {
        var parts: [String] = []
        if unreadableCount > 0 { parts.append("\(unreadableCount) 个文件读取失败，未参与判定") }
        if datalessCount > 0 { parts.append("\(datalessCount) 个仅有云端占位的文件已跳过") }
        return parts.isEmpty ? nil : parts.joined(separator: "；") + "。"
    }

    func cancel() { cancelFlag.cancel() }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        wasStopped = false
        cancelFlag.reset()
        progress = nil
        groups = []
        selection = []
        unreadableCount = 0
        datalessCount = 0
        toast = nil

        var entries: [FileEntry] = []
        let fileScanner = FileScanner()
        for dir in scopes where !cancelFlag.isCancelled {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            let result = await fileScanner.scanDirectory(URL(fileURLWithPath: dir))
            entries.append(contentsOf: result.entries)
        }

        var report: DuplicateScanReport?
        if !cancelFlag.isCancelled {
            let scanner = DuplicateScanner()
            let flag = cancelFlag
            report = await scanner.findDuplicates(
                in: entries,
                shouldContinue: { !flag.isCancelled }
            ) { update in
                Task { @MainActor [weak self] in self?.progress = update }
            }
        }

        lastReport = report
        wasStopped = report.map { !$0.isComplete } ?? cancelFlag.isCancelled
        groups = report?.groups ?? []
        unreadableCount = Set(report?.unreadablePaths ?? []).count
        datalessCount = report?.datalessSkippedCount ?? 0
        progress = nil
        isScanning = false
        hasScanned = true
    }

    func toggleKeep(_ file: DuplicateFile, in group: DuplicateGroup) {
        if selection.contains(file.path) { selection.remove(file.path) }
        else if !isKeepRequired(file, in: group) { selection.insert(file.path) }
    }

    /// 一组里必须留下一份：当它已是唯一未勾选的文件时，它就是"保留"项，不能再勾。
    func isKeepRequired(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool {
        guard !selection.contains(file.path) else { return false }
        let others = group.files.filter { $0.path != file.path }
        return others.allSatisfy { selection.contains($0.path) }
    }

    func moveToTrash() async {
        let paths = Array(selection).map(\.path)
        guard !paths.isEmpty else { return }
        let selectedSnapshot = selection
        let result = await FileTrashService.shared.moveToTrash(paths: paths)
        trashFailures = result.operation.failures
        if result.operation.fileCount > 0 {
            toast = UndoToast(
                message: "已移到废纸篓 · \(result.operation.fileCount) 个文件",
                detail: MMFormat.bytes(result.operation.totalSize),
                operationID: result.operation.id
            )
        }
        groups = groups.compactMap { group in
            let kept = group.files.filter { !selectedSnapshot.contains($0.path) }
            guard kept.count > 1 else { return nil }
            return DuplicateGroup(hash: group.hash, size: group.size, files: kept)
        }
        selection = []
    }

    func undo(_ operationID: UUID) async {
        let result = await FileTrashService.shared.undo(operationID: operationID)
        toast = nil
        trashFailures = result.failures
        await scan()
    }

    @ViewBuilder
    var actionBar: some View {
        MMActionBar(
            summary: selection.isEmpty
                ? "已选 0 项"
                : "已选 \(selection.count) 项 · \(MMFormat.bytes(selectedSize))",
            note: selection.isEmpty ? "未勾选的文件不会被改动。" : "被勾选的文件会先移入废纸篓，可撤回。"
        ) {
            Button("打开废纸篓") {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
            }
            .buttonStyle(.bordered)

            Button("移到废纸篓") {
                Task { await self.moveToTrash() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selection.isEmpty)
        }
        .overlay(alignment: .top) {
            if let toast {
                MMUndoToast(
                    message: toast.message,
                    detail: toast.detail,
                    onUndo: { Task { await self.undo(toast.operationID) } },
                    onRevealTrash: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
                    }
                )
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    if self.toast == toast { self.toast = nil }
                }
            }
        }
    }
}

// MARK: - 重复分组行

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @EnvironmentObject var model: DuplicateScanModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: MMGap.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(MMColor.tertiaryLabel)
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(MMColor.caution)
                        .frame(width: MMMetric.iconSmall)
                    Text("\(group.files.count) 个文件内容相同")
                        .font(.body.weight(.medium))
                    Text(MMFormat.bytes(group.size) + " × \(group.files.count)")
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                        .monospacedDigit()
                    Spacer(minLength: MMGap.sm)
                    MMBadge(risk: .caution)
                    Text("可释放 " + MMFormat.bytes(group.wastedSpace))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(MMColor.informational)
                        .frame(minWidth: 110, alignment: .trailing)
                }
                .padding(.horizontal, MMGap.md)
                .frame(height: MMMetric.rowRegular)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.files) { file in
                        fileRow(file)
                    }
                }
                .overlay(alignment: .top) { Divider() }
            }
        }
        .background(MMColor.contentBackground, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator))
    }

    private func fileRow(_ file: DuplicateFile) -> some View {
        let keepRequired = model.isKeepRequired(file, in: group)
        let isChecked = model.selection.contains(file.path)
        return HStack(spacing: MMGap.sm) {
            Toggle("", isOn: Binding(
                get: { isChecked },
                set: { _ in model.toggleKeep(file, in: group) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(keepRequired)

            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(file.path.lastPathComponent).font(.callout).lineLimit(1)
                Text(file.path.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: MMGap.sm)

            if keepRequired { MMBadge("需保留", tint: MMColor.secondaryLabel) }
            Text(MMFormat.relative(file.modificationDate))
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(width: 72, alignment: .trailing)
            Text(MMFormat.bytes(file.size))
                .font(.callout).monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
            Button {
                MMReveal.open(file.path.path)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在访达中显示")
        }
        .padding(.horizontal, MMGap.md)
        .padding(.leading, MMGap.lg)
        .frame(height: MMMetric.rowRegular)
        .background(isChecked ? MMColor.soft(MMColor.accent, 0.07) : .clear)
    }
}

// MARK: - 浏览器缓存

struct BrowserCacheRow: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let path: String
    /// nil = 目录存在但体积没量出来（无权限/已消失）。显示"测量中"，
    /// 不能 `?? 0` 把"没读到"伪装成"很干净"。
    let size: UInt64?
    let kind: String
}

enum BrowserCacheProbe {
    static func collect() -> [BrowserCacheRow] {
        let home = NSHomeDirectory()
        let candidates: [(String, String, String, String)] = [
            ("Safari", "safari", home + "/Library/Caches/com.apple.Safari", "网页缓存"),
            ("Chrome", "globe", home + "/Library/Caches/Google/Chrome", "网页缓存"),
            ("Firefox", "globe", home + "/Library/Caches/Firefox", "网页缓存"),
            ("Edge", "globe", home + "/Library/Caches/Microsoft Edge", "网页缓存"),
        ]
        let fm = FileManager.default
        var rows: [BrowserCacheRow] = []
        for (name, symbol, path, kind) in candidates where fm.fileExists(atPath: path) {
            rows.append(BrowserCacheRow(id: path, name: name, systemImage: symbol,
                                        path: path, size: SystemSampler.directoryBytes(path),
                                        kind: kind))
        }
        return rows.filter { $0.size == nil || ($0.size ?? 0) > 0 }
            .sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }
}

@MainActor
final class BrowserCacheModel: ObservableObject {
    @Published var items: [BrowserCacheRow] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var failures: [TrashFailure] = []

    var headline: String {
        if isScanning { return "正在统计缓存体积…" }
        guard !items.isEmpty else { return "只清缓存，不动历史记录、密码和 Cookie。" }
        let measured = items.compactMap(\.size)
        var text = "\(items.count) 个缓存目录 · 合计 \(MMFormat.bytes(measured.reduce(UInt64(0), +)))"
        if measured.count != items.count {
            text += "（\(items.count - measured.count) 个目录没读到，未计入）"
        }
        return text
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let found = await Task.detached(priority: .utility) { BrowserCacheProbe.collect() }.value
        items = found
        hasScanned = true
        isScanning = false
    }

    /// 缓存体积量一次不到一秒，进页面就量，比摆一个"请先点扫描"的空态有用。
    func scanIfNeeded() async {
        guard !hasScanned, !isScanning else { return }
        await scan()
    }

    func clean(_ row: BrowserCacheRow) async {
        let result = await FileTrashService.shared.moveToTrash(paths: [row.path])
        failures = result.operation.failures
        if result.successCount > 0 { items.removeAll { $0.id == row.id } }
    }
}

struct BrowserCacheRowView: View {
    let item: BrowserCacheRow
    let model: BrowserCacheModel

    var body: some View {
        HStack(spacing: MMGap.md) {
            Image(systemName: item.systemImage)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(MMColor.informational)
                .frame(width: MMMetric.iconSmall)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(item.name).font(.body.weight(.medium))
                Text("\(item.kind) · \(item.path)")
                    .font(.caption).foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: MMGap.sm)
            MMRevealButton(path: item.path, title: "位置")
                .buttonStyle(.borderless)
                .controlSize(.small)
            Text(MMFormat.bytes(item.size))
                .font(.callout).monospacedDigit()
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(minWidth: 72, alignment: .trailing)
                .help(item.size == nil ? "目录存在，但体积没能读出来；不是 0 字节。" : "")
            Button {
                Task { await model.clean(item) }
            } label: {
                Label("移到废纸篓", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: MMMetric.rowRegular)
    }
}

// MARK: - 系统状态检测
//
// 只列"量得出来的"和"点了真有效果的"。此前这里的「DNS 优化 / Spotlight 优化」
// 按下去只是把文案改成"已完成"，那种按钮不能留。

struct SystemCheck: Identifiable {
    enum Kind: String { case memory, disk, trash }

    let id: Kind
    let title: String
    let value: String
    let note: String
    let risk: MMRisk
    let destination: MMDestination?
    let revealPath: String?

    var systemImage: String {
        switch id {
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .trash: "trash"
        }
    }
}

@MainActor
final class SystemDiagnosticsModel: ObservableObject {
    @Published var checks: [SystemCheck] = []
    @Published var updatedAt: String?

    func refresh() async {
        let measured = await Task.detached(priority: .utility) { SystemDiagnostics.measure() }.value
        checks = measured
        updatedAt = "上次检测 " + MMFormat.dateTime(Date())
    }
}

enum SystemDiagnostics {
    static func measure() -> [SystemCheck] {
        var out: [SystemCheck] = []

        let mem = DashboardMemory.sample()
        let memoryNote: String
        if mem.used == nil {
            memoryNote = "vm_statistics64 没读数，这里不猜占用；显示 —。"
        } else if let swapUsed = mem.swapUsed {
            memoryNote = swapUsed > 0
                ? "已使用交换空间 \(MMFormat.bytes(swapUsed))，关掉占内存大的应用才会回落"
                : "未使用交换空间"
        } else {
            memoryNote = "交换空间读数不可用（sysctl vm.swapusage 失败），显示 —。"
        }
        out.append(SystemCheck(
            id: .memory,
            title: "内存占用",
            value: DashboardText.memoryUsedText(mem),
            note: memoryNote,
            risk: mem.pressure == nil ? .readOnly : (mem.pressure! > 0.85 ? .caution : .safe),
            destination: .monitor,
            revealPath: nil
        ))

        if let disk = SystemSampler.volume() {
            out.append(SystemCheck(
                id: .disk,
                title: "磁盘可用",
                value: MMFormat.bytes(disk.available),
                note: "已用 \(MMFormat.percent(disk.usedRatio)) · \(disk.name) 容量 \(MMFormat.bytes(disk.total))",
                risk: disk.usedRatio > 0.9 ? .caution : .safe,
                destination: .disk,
                revealPath: nil
            ))
        } else {
            out.append(SystemCheck(id: .disk, title: "磁盘可用", value: DashboardText.placeholder,
                                   note: "未能读取卷信息（容量键未返回），不显示 0。", risk: .readOnly,
                                   destination: .disk, revealPath: nil))
        }

        // 用 directoryBytes 而不是 trashBytes：后者把"没量到"折成 0，
        // 会让"废纸篓占用 0 字节"在这种失败下说谎。
        let trash = SystemSampler.directoryBytes(NSHomeDirectory() + "/.Trash")
        out.append(SystemCheck(
            id: .trash,
            title: "废纸篓占用",
            value: trash.map(MMFormat.bytes) ?? DashboardText.placeholder,
            note: "清空废纸篓会同时丢掉撤回入口，所以这里只带你过去，不代你清空。",
            risk: (trash ?? 0) > 5 * 1024 * 1024 * 1024 ? .caution : .readOnly,
            destination: nil,
            revealPath: NSHomeDirectory() + "/.Trash"
        ))

        return out
    }
}

struct SystemCheckRow: View {
    let check: SystemCheck
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: MMGap.md) {
            Image(systemName: check.systemImage)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(check.risk.color)
                .frame(width: MMMetric.iconSmall)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(check.title).font(.body.weight(.medium))
                Text(check.note).font(.caption).foregroundStyle(MMColor.secondaryLabel).lineLimit(2)
            }
            Spacer(minLength: MMGap.sm)
            Text(check.value).font(.callout).monospacedDigit()
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(minWidth: 110, alignment: .trailing)
            MMBadge(risk: check.risk)
            if let destination = check.destination {
                Button("查看") { MMNavigation.go(destination) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if let path = check.revealPath {
                MMRevealButton(path: path, title: "打开")
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("重新检测")
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: MMMetric.rowRegular)
    }
}
