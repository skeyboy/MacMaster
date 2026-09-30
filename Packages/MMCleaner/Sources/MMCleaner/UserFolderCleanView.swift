import SwiftUI
import MMCore
import MMFileScanner
import MMUI

/// 仅供无头截图验证：把「安装包残留」的扫描根换成 /tmp 下的夹具目录。
/// 只接受 /tmp 或 /private/tmp 前缀 —— 这一屏的删除按钮是真删文件，
/// 验证钩子一旦指向真实的 ~/Downloads，自动勾选 + 确认面板再被误按一次回车就是真删用户文件。
/// 口径与 MMUninstaller 的 orphanFixtureHome 一致：非法值打 stderr 后回落到真实（只读）范围。
enum InstallerScanScope {
    static func roots(fixtureDir raw: String?) -> [String]? {
        guard let raw, raw.isEmpty == false else { return nil }
        guard raw.hasPrefix("/tmp/") || raw.hasPrefix("/private/tmp/") else {
            FileHandle.standardError.write(
                "MM_INSTALLER_FIXTURE_DIR=\(raw) 不在 /tmp 之下，忽略该钩子\n".data(using: .utf8)!)
            return nil
        }
        return [raw]
    }
}

/// Task 1 UI：用户文件夹「先查看、再手动勾选」。
/// 与缓存页的默认全选相反，这里所有条目初始状态都是未选中，
/// 只有用户逐项点选的文件夹/子项才会被移入废纸篓（FileTrashService，可撤回）。
/// P4.4：同一屏下方还有「安装包残留」区块——同一勾选/清理管线，默认同样不勾选。
struct UserFolderCleanView: View {
    @State private var folders: [UserFolderInfo] = []
    @State private var hasScanned = false
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var selectedPaths: Set<String> = []
    @State private var expandedFolderPath: String?
    @State private var folderChildren: [String: [UserFolderChild]] = [:]
    @State private var childrenLoadingPath: String?
    @State private var scanningPath = ""
    @State private var scannedFileCount = 0
    @State private var lastResult: TrashResult?
    @State private var lastFailures: [TrashFailure] = []
    @State private var toastSeconds = 0
    @State private var showConfirmAlert = false
    @State private var scanTask: Task<Void, Never>?

    // MARK: 安装包残留（P4.4）状态
    @State private var installerFindings: [InstallerFinding] = []
    @State private var installerInspectedCount = 0
    @State private var installerInaccessibleRoots: [String] = []
    @State private var isScanningInstallers = false
    @State private var hasSniffedInstallers = false
    @State private var installerScanPartial = false
    /// 本轮真正扫过的根目录（来自 report.scannedRoots）：范围声明要按实际用的根写，
    /// 不能硬编码"桌面/下载/…"——夹具模式下扫的是 /tmp，硬编码就成了假话。
    @State private var installerScannedRoots: [String] = []
    @State private var installerScanTask: Task<Void, Never>?
    /// 夹具模式下自动勾选的安装包路径。文件夹扫描完成会清空勾选重开一轮，
    /// 这里记下夹具勾了什么，让两条独立扫描不论谁先完成，自动勾选都不会被对方抹掉。
    @State private var installerAutoSelection: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            MMPageHeader("用户文件夹", subtitle: headerSubtitle) {
                Button {
                    startScan()
                } label: {
                    Label(isScanning ? "扫描中…" : "重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning || isCleaning)
            }

            content

            if !lastFailures.isEmpty {
                MMFailurePanel(
                    summary: lastResult.map { "已回收 \(MMFormat.bytes($0.totalSize))" },
                    lastFailures
                ) {
                    lastFailures = []
                }
            }

            Divider()
            actionBar
        }
        .alert("确认清理选中的项目？", isPresented: $showConfirmAlert) {
            Button("取消", role: .cancel) {}
            Button("移入废纸篓", role: .destructive) {
                Task { await cleanSelected() }
            }
        } message: {
            Text("共 \(cleanTargets.count) 项，约 \(MMFormat.bytes(selectedSize))。\n选中的内容将移入废纸篓（可撤回），不会永久删除。")
        }
        .overlay(alignment: .bottom) {
            if let result = lastResult, toastSeconds > 0 {
                MMUndoToast(
                    message: "已将 \(result.successCount) 项移入废纸篓",
                    detail: MMFormat.bytes(result.totalSize),
                    secondsRemaining: toastSeconds,
                    onUndo: { Task { await undoClean() } },
                    onRevealTrash: { MMReveal.openDirectory(NSHomeDirectory() + "/.Trash") }
                )
                .padding(.bottom, MMMetric.actionBar + MMGap.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toastSeconds)
        .task(id: toastSeconds) {
            guard toastSeconds > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            toastSeconds -= 1
        }
        // 仅供截图验证：合成点击会逃到别的应用，扫描结果态没有别的办法进入。
        .task {
            guard ProcessInfo.processInfo.environment["MM_AUTO_SCAN"] != nil else { return }
            if !hasScanned, !isScanning { startScan() }
        }
        .onChange(of: hasScanned) { _, scanned in
            guard scanned, ProcessInfo.processInfo.environment["MM_SHOW_CONFIRM"] != nil else { return }
            // 安装包夹具的确认由夹具分支自己开：这里再叠一个"真实最小文件夹"进
            // 同一张确认面板，就等于把真实用户目录带进自动勾选状态（法则第 6 条）。
            guard InstallerScanScope.roots(
                fixtureDir: ProcessInfo.processInfo.environment["MM_INSTALLER_FIXTURE_DIR"]
            ) == nil else { return }
            // 勾最小的那个文件夹：这条路径只为把确认弹窗截出来，
            // 万一被误触发，损失也要是"几乎为零"而不是整个文稿目录。
            if let smallest = folders.filter(\.isAccessible).min(by: { $0.size < $1.size }) {
                selectedPaths = [smallest.path]
                showConfirmAlert = true
            }
        }
    }

    private var headerSubtitle: String {
        if isScanning { return "扫描中…" }
        guard hasScanned else { return "尚未扫描" }
        let total = folders.reduce(UInt64(0)) { $0 + $1.size }
        let inaccessible = folders.filter { !$0.isAccessible }.count
        var text = "\(folders.count) 个文件夹 · \(MMFormat.bytes(total))"
        if inaccessible > 0 { text += " · \(inaccessible) 个无访问权限" }
        return text
    }

    @ViewBuilder
    private var content: some View {
        if isScanning && folders.isEmpty {
            VStack(spacing: 0) {
                MMScanProgress(
                    action: "正在扫描用户文件夹",
                    currentPath: scanningPath.isEmpty ? nil : scanningPath,
                    processedCount: scannedFileCount,
                    estimatedRemaining: nil,
                    progress: nil
                )
                Divider()
                ForEach(0..<6, id: \.self) { _ in
                    MMSkeletonRow(nameWidth: 120, valueWidth: 72)
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("取消扫描") {
                        scanTask?.cancel()
                        installerScanTask?.cancel()
                    }
                        .padding(.bottom, MMGap.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MMColor.contentBackground)
        } else if !hasScanned {
            MMEmptyState(
                systemImage: "folder.badge.person.crop",
                title: "扫描桌面 / 文稿 / 下载 / 图片 / 影片 / 音乐",
                detail: "受 macOS 隐私保护，首次访问可能需要在系统弹窗中允许。默认全部未选中，只有逐项勾选的内容才会被清理。",
                action: AnyView(
                    Button {
                        startScan()
                    } label: {
                        Label("扫描用户文件夹", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                )
            )
        } else {
            folderTable
        }
    }

    private var folderTable: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(folders) { folder in
                        UserFolderSection(
                            folder: folder,
                            isSelected: selectionBinding(for: folder.path),
                            isExpanded: expandedFolderPath == folder.path,
                            children: folderChildren[folder.path] ?? [],
                            isLoadingChildren: childrenLoadingPath == folder.path,
                            childSelection: selectionBinding(for:),
                            onToggleExpand: { toggleExpand(folder: folder) }
                        )
                        Divider().padding(.leading, MMGap.md)
                    }

                    installerSection

                    HStack(alignment: .top, spacing: MMGap.xs) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                        Text("清理一律移入废纸篓，可在「最近操作」中撤回；未勾选的内容不会被读取之外的任何修改。")
                            .font(.caption)
                            .foregroundStyle(MMColor.secondaryLabel)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, MMGap.md)
                    .padding(.vertical, MMGap.sm)
                }
                // 必须显式给宽：LazyVStack 在 ScrollView 里会按最宽子项的理想宽度
                // 排版，整张表就会横向溢出、右侧数值被裁掉。
                .frame(width: proxy.size.width - MMGap.lg * 2)
                .background(MMColor.contentBackground)
                .overlay(RoundedRectangle(cornerRadius: MMRadius.card).stroke(MMColor.separator))
                .padding(.horizontal, MMGap.lg)
                .padding(.vertical, MMGap.lg)
            }
        }
    }

    // MARK: - 安装包残留区块（P4.4）

    /// 与文件夹清理事务共用同一套勾选/清理管线：这里只负责把"证据"摆出来，
    /// 勾与不勾永远是用户的决定——与本页"默认全部未选中"的口径一致。
    @ViewBuilder
    private var installerSection: some View {
        installerGroupHeader
        // 范围声明排在条目之前：一屏放不下几十条时，"看过哪里"必须仍然看得见。
        installerScopeLine

        if isScanningInstallers && installerFindings.isEmpty {
            HStack(spacing: MMGap.sm) {
                ProgressView().controlSize(.small)
                Text("正在嗅探安装包签名（只读文件头/尾，不解压、不执行）…")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                Spacer(minLength: MMGap.sm)
            }
            .padding(.leading, MMGap.md)
            .frame(height: MMMetric.rowCompact, alignment: .leading)
        } else if installerFindings.isEmpty {
            Text(installerEmptyLine)
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
                .padding(.leading, MMGap.md)
                .padding(.vertical, MMGap.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(installerFindings) { finding in
                installerRow(finding)
                Divider().padding(.leading, MMGap.md)
            }
        }

        installerScopeLine

        if !installerInaccessibleRoots.isEmpty {
            Text("\(installerInaccessibleRoots.count) 个位置读不到（多半是 macOS 隐私保护），本轮没有检查它们，也不计入结果。")
                .font(.caption)
                .foregroundStyle(MMColor.caution)
                .padding(.leading, MMGap.md)
                .padding(.vertical, MMGap.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var installerGroupHeader: some View {
        HStack(spacing: MMGap.sm) {
            Text("安装包残留")
                .font(.callout.weight(.semibold))
                .foregroundStyle(MMColor.label)
            Text(installerCounter)
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
            Spacer()
            Text("DMG / PKG / XIP + 按内容嗅探的 ZIP · 全部默认不勾选")
                .font(.caption)
                .foregroundStyle(MMColor.tertiaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .trailing)
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: 30)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 没嗅过就说"尚未嗅探"，不能读成 0 个：0 是"查过、这里干净"。
    private var installerCounter: String {
        if isScanningInstallers { return "嗅探中…" }
        guard hasSniffedInstallers else { return "尚未嗅探" }
        let verifiedCount = installerFindings.filter { $0.evidence == .verified }.count
        return "\(installerFindings.count) 项（\(verifiedCount) 项签名已核实）"
    }

    /// 扫过的根 + 深度上限。空结果最容易骗人的地方就是"没看过"被读成"没有"：
    /// 只进一层子目录是硬口径，必须在页面上写明，让用户知道更深处没查。
    private var installerScopeLine: some View {
        Text(installerScopeText)
            .font(.caption)
            .foregroundStyle(MMColor.tertiaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, MMGap.md)
            .padding(.vertical, MMGap.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var installerScopeText: String {
        let depth = "只查这些位置本身及其一层子目录，更深的目录本轮没有查看"
        let home = NSHomeDirectory()
        let roots = installerScannedRoots.map { path in
            path.hasPrefix(home + "/") ? "~/" + path.dropFirst(home.count + 1) : path
        }
        if roots.isEmpty { return "尚未嗅探。\(depth)。" }
        return "扫描范围：\(roots.joined(separator: "、")) · \(depth)。"
    }

    private var installerEmptyLine: String {
        guard hasSniffedInstallers else { return "尚未嗅探。" }
        if installerScanPartial { return "嗅探未完成（已取消），下面的数字只包含已扫到的部分。" }
        if installerInspectedCount > 0 {
            return "检查过 \(installerInspectedCount) 个候选，未确认到安装介质。普通 ZIP 判不出安装包时一律不列——宁可漏报，不错报。"
        }
        return "未发现 DMG / PKG / MPKG / XIP，也没有装着应用的 ZIP。"
    }

    private func installerRow(_ finding: InstallerFinding) -> some View {
        MMItemRow(
            title: finding.name,
            subtitle: "\(finding.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) · \(finding.evidenceDetail) · 修改于 \(MMFormat.dateTime(finding.modificationDate))",
            value: MMFormat.bytes(finding.size),
            systemImage: finding.isDirectory ? "shippingbox" : "externaldrive",
            isSelectable: true,
            isSelected: selectionBinding(for: finding.path)
        ) {
            HStack(spacing: MMGap.sm) {
                if finding.evidence == .verified {
                    MMBadge("签名已核实", tint: MMColor.informational, systemImage: "checkmark.seal")
                } else {
                    // nameOnly 是"没核实"，不是"确认是"：橙色 + 问号，绝不借用绿/蓝。
                    MMBadge("仅按名称识别", tint: MMColor.caution, systemImage: "questionmark")
                }
                MMRowAction(systemImage: "folder", help: "在访达中打开") { MMReveal.open(finding.path) }
            }
        }
        .background(selectedPaths.contains(finding.path) ? MMColor.soft(MMColor.accent, 0.06) : .clear)
    }

    private func startInstallerScan() {
        installerScanTask?.cancel()
        isScanningInstallers = true
        hasSniffedInstallers = false
        installerScanPartial = false
        installerAutoSelection = []
        installerFindings = []
        installerScannedRoots = []
        let fixtureRoots = InstallerScanScope.roots(
            fixtureDir: ProcessInfo.processInfo.environment["MM_INSTALLER_FIXTURE_DIR"]
        )
        installerScanTask = Task {
            let report = await InstallerScanner(roots: fixtureRoots).scan()
            guard !Task.isCancelled else {
                await MainActor.run { isScanningInstallers = false }
                return
            }
            await MainActor.run {
                installerFindings = report.findings
                installerScannedRoots = report.scannedRoots
                installerInspectedCount = report.inspectedCount
                installerInaccessibleRoots = report.inaccessibleRoots
                hasSniffedInstallers = true
                installerScanPartial = !report.isComplete
                isScanningInstallers = false
                if fixtureRoots != nil,
                   !report.findings.isEmpty,
                   ProcessInfo.processInfo.environment["MM_SHOW_CONFIRM"] != nil {
                    // 夹具 + 显式确认钩子两个条件都满足才走这一步：
                    // 真实用户目录永远不许被"自动勾选 + 弹确认"（法则第 6 条）。
                    installerAutoSelection = Set(report.findings.map(\.path))
                    selectedPaths.formUnion(installerAutoSelection)
                    showConfirmAlert = true
                    FileHandle.standardError.write("安装包残留夹具：已自动勾选并打开确认面板\n".data(using: .utf8)!)
                }
            }
        }
    }

    private var actionBar: some View {
        MMActionBar(
            summary: "已选 \(cleanTargets.count) 项 · \(MMFormat.bytes(selectedSize))",
            note: isScanning ? "扫描未完成，数字只包含已扫到的部分" : "未勾选的内容绝不会被清理"
        ) {
            Button("清理选中 \(cleanTargets.count) 项") {
                showConfirmAlert = true
            }
            .buttonStyle(.borderedProminent)
            .tint(MMColor.destructive)
            .disabled(cleanTargets.isEmpty || isScanning || isCleaning)
        }
    }

    private func selectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(path) },
            set: { on in
                if on { selectedPaths.insert(path) } else { selectedPaths.remove(path) }
            }
        )
    }

    // MARK: - 选中项计算

    /// 去掉祖先已被选中的后代路径：文件夹整体入回收站后，其子项无需再单独移动。
    private var cleanTargets: [String] {
        let sorted = selectedPaths.sorted { $0.count < $1.count }
        var kept: [String] = []
        for path in sorted {
            let hasSelectedAncestor = kept.contains { path.hasPrefix($0 + "/") }
            if !hasSelectedAncestor {
                kept.append(path)
            }
        }
        return kept
    }

    private var sizeLookup: [String: UInt64] {
        var map: [String: UInt64] = [:]
        for folder in folders {
            map[folder.path] = folder.size
        }
        for children in folderChildren.values {
            for child in children {
                map[child.path] = child.size
            }
        }
        // 安装包残留并进同一张查找表：底部合计与确认面板的数字才会把它们算进去。
        // 没量到的条目贡献 0，但行内仍显示"测量中"——合计里少算是漏，虚报是假。
        for finding in installerFindings {
            map[finding.path] = finding.size ?? 0
        }
        return map
    }

    private var selectedSize: UInt64 {
        cleanTargets.reduce(UInt64(0)) { partial, path in
            partial + (sizeLookup[path] ?? 0)
        }
    }

    // MARK: - 动作

    private func toggleExpand(folder: UserFolderInfo) {
        if expandedFolderPath == folder.path {
            expandedFolderPath = nil
            return
        }
        expandedFolderPath = folder.path
        guard folderChildren[folder.path] == nil, folder.isAccessible else { return }
        childrenLoadingPath = folder.path
        let path = folder.path
        let scanner = UserFolderScanner()
        Task {
            let children = await scanner.listChildren(of: path)
            await MainActor.run {
                folderChildren[path] = children
                childrenLoadingPath = nil
            }
        }
    }

    private func startScan() {
        isScanning = true
        scanningPath = ""
        scannedFileCount = 0
        startInstallerScan()

        let tracker = FileScanProgressTracker()
        let scanner = UserFolderScanner()

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                scanningPath = tracker.currentPath
                scannedFileCount = tracker.fileCount
            }
        }

        scanTask = Task {
            let result = await scanner.scan(tracker: tracker)
            progressTask.cancel()
            guard !Task.isCancelled else {
                await MainActor.run {
                    isScanning = false
                }
                return
            }
            await MainActor.run {
                withAnimation {
                    folders = result
                    hasScanned = true
                    isScanning = false
                    selectedPaths = installerAutoSelection
                    expandedFolderPath = nil
                    folderChildren = [:]
                }
            }
        }
    }

    private func cleanSelected() async {
        let paths = cleanTargets
        guard !paths.isEmpty else { return }
        isCleaning = true

        let result = await FileTrashService.shared.moveToTrash(paths: paths)
        lastResult = result
        lastFailures = result.operation.failures
        // 一项都没搬动就别弹"已移入废纸篓"，失败清单已经在面板里说清楚了。
        if result.successCount > 0 { toastSeconds = 15 }

        let moved = Set(result.operation.files.map(\.originalPath))
        await applyCleaned(Array(moved))
        // 只有真的搬进废纸篓的安装包条目才从清单里摘掉；失败的留在原地——
        // 它们还在磁盘上，条目消失才是假话（失败详情由 MMFailurePanel 逐条报）。
        installerFindings.removeAll { UserFolderCleanup.wasMoved($0.path, under: moved) }
        installerAutoSelection = Set(installerAutoSelection.filter {
            !UserFolderCleanup.wasMoved($0, under: moved)
        })
        selectedPaths = Set(selectedPaths.filter { !UserFolderCleanup.wasMoved($0, under: moved) })
        isCleaning = false
    }

    /// 就地更新状态：整删的顶层文件夹重新统计（此时目录为空，很快），
    /// 被清理的子项从缓存中移除并从父目录扣减大小/文件数。
    private func applyCleaned(_ paths: [String]) async {
        let scanner = UserFolderScanner()
        var parentDeltas: [String: (size: UInt64, count: Int)] = [:]

        for path in paths {
            if let index = folders.firstIndex(where: { $0.path == path }) {
                let fresh = await scanner.scanFolder(atPath: path)
                if let fresh {
                    folders[index] = fresh
                } else {
                    folders.remove(at: index)
                }
                folderChildren.removeValue(forKey: path)
            } else {
                let parent = (path as NSString).deletingLastPathComponent
                let childSize = sizeLookup[path] ?? 0
                let childCount = folderChildren[parent]?.first { $0.path == path }?.fileCount ?? 1
                parentDeltas[parent, default: (0, 0)].size += childSize
                parentDeltas[parent, default: (0, 0)].count += childCount
                folderChildren[parent] = folderChildren[parent]?.filter { $0.path != path }
            }
        }

        for (parent, delta) in parentDeltas {
            guard let index = folders.firstIndex(where: { $0.path == parent }) else { continue }
            folders[index].size = folders[index].size > delta.size ? folders[index].size - delta.size : 0
            folders[index].fileCount = max(0, folders[index].fileCount - delta.count)
        }
    }

    private func undoClean() async {
        _ = await FileTrashService.shared.undoLastOperation()
        toastSeconds = 0
        startScan()
    }

}

enum UserFolderCleanup {
    static func wasMoved(_ path: String, under roots: Set<String>) -> Bool {
        roots.contains { root in path == root || path.hasPrefix(root + "/") }
    }
}

/// 单个用户文件夹行：勾选 + 展开查看子项并逐项勾选。
/// 默认不勾选，与缓存页的"安全档预选"相反——个人目录里没有可自动重建的东西。
struct UserFolderSection: View {
    let folder: UserFolderInfo
    @Binding var isSelected: Bool
    let isExpanded: Bool
    let children: [UserFolderChild]
    let isLoadingChildren: Bool
    let childSelection: (String) -> Binding<Bool>
    let onToggleExpand: () -> Void

    var body: some View {
        MMItemRow(
            title: folder.name,
            subtitle: folder.isAccessible
                ? "\(folder.fileCount) 个文件 · 修改于 \(formatDate(folder.modificationDate))"
                : "macOS 隐私保护（TCC）阻止访问，请在「系统设置 → 隐私与安全性」中授权",
            value: MMFormat.bytes(folder.size),
            systemImage: folder.iconName,
            isSelectable: folder.isAccessible,
            isSelected: $isSelected
        ) {
            HStack(spacing: MMGap.sm) {
                if !folder.isAccessible {
                    MMBadge("无权限", tint: MMColor.caution, systemImage: "lock")
                }
                MMRowAction(
                    systemImage: isExpanded ? "chevron.down" : "chevron.right",
                    help: isExpanded ? "收起子项" : "展开子项"
                ) {
                    onToggleExpand()
                }
                .disabled(!folder.isAccessible)
                MMRowAction(systemImage: "folder", help: "在访达中打开") { MMReveal.open(folder.path) }
            }
        }
        .background(isSelected ? MMColor.soft(MMColor.accent, 0.08) : .clear)

        if isExpanded {
            if isLoadingChildren {
                HStack(spacing: MMGap.sm) {
                    ProgressView().controlSize(.small)
                    Text("正在统计子项…")
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                }
                .padding(.leading, MMGap.xl * 2 + MMGap.sm)
                .frame(height: MMMetric.rowCompact, alignment: .leading)
            } else {
                ForEach(children) { child in
                    UserFolderChildRow(
                        child: child,
                        isSelected: childSelection(child.path),
                        onOpenInFinder: { MMReveal.open(child.path) }
                    )
                }
                if children.isEmpty {
                    Text("无内容")
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .padding(.leading, MMGap.xl * 2 + MMGap.sm)
                        .frame(height: MMMetric.rowCompact, alignment: .leading)
                }
            }
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct UserFolderChildRow: View {
    let child: UserFolderChild
    @Binding var isSelected: Bool
    let onOpenInFinder: () -> Void

    var body: some View {
        HStack(spacing: MMGap.sm) {
            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(isSelected ? "取消选择" : "选择此项进行清理（默认不选）")

            Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                .font(.caption2)
                .foregroundStyle(MMColor.tertiaryLabel)
                .frame(width: 14)

            Text(child.name)
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
                .lineLimit(1)

            Spacer(minLength: MMGap.sm)

            Text("\(child.fileCount) 个文件 · \(child.modificationDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(MMColor.tertiaryLabel)

            Text(MMFormat.bytes(child.size))
                .font(.caption.monospaced())
                .foregroundStyle(isSelected ? MMColor.label : MMColor.tertiaryLabel)
                .frame(minWidth: 72, alignment: .trailing)

            MMRowAction(systemImage: "folder", help: "在访达中打开", action: onOpenInFinder)
        }
        .padding(.leading, MMGap.xl * 2 + MMGap.sm)
        .padding(.trailing, MMGap.md)
        .frame(height: MMMetric.rowCompact)
        .background(isSelected ? MMColor.soft(MMColor.accent, 0.06) : .clear)
    }
}
