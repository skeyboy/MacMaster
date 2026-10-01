//
//  DevArtifactView.swift — 「开发产物」页（P5.1）
//
//  把散在各个项目里的可重建构建产物按**项目**聚合成一张清单：node_modules、target、
//  .build、DerivedData 这类目录在磁盘上通常是大头，但它们在文件树里是分散的叶子，
//  用户在清理页看到的只有"缓存 2.4 GB"这种按位置切的类别，看不到"哪个项目吃了多少、
//  多久没碰"。这一页换的是切法。
//
//  三条纪律：
//  1. **默认一项都不勾**。这一屏删的是用户自己项目里的目录，名字像产物不等于就是产物
//     （`build/` 里可能签着源码），所以整页按"谨慎"处理：勾由用户点，批量按钮只挑
//     "久未触碰 + 证据成立"的那些。
//  2. **只报能核对的证据**。受保护的行不给勾选框，并把"为什么不动它"写在行上；
//     体积没测到就显示"—"，不折成 0（那是把"没读到"说成"没东西"）。
//  3. 删除仍然只有 `FileTrashService` 一个出口，`DeletionGuard` 是第二道闸门——
//     例如 iCloud 同步目录在扫描层已判受保护，闸门再挡一次，两层各自独立成立。
//

import SwiftUI
import MMCore
import MMFileScanner
import MMUI

// MARK: - 状态

@MainActor
final class DevArtifactModel: ObservableObject {
    @Published var report: ProjectArtifactReport?
    @Published var isScanning = false
    @Published var selectedPaths: Set<String> = []
    @Published var expandedRoots: Set<String> = []
    @Published var lastResult: TrashResult?
    @Published var failures: [TrashFailure] = []
    @Published var isCleaning = false
    /// 扫描完成时刻与耗时由模型自己记：报告里没有 scannedAt，而这一屏的副标题
    /// 必须说清"清单是几分钟前的"——产物目录随时会被工具重写。
    @Published var scannedAt: Date?
    @Published var scanDuration: TimeInterval?

    private var scanTask: Task<Void, Never>?

    /// 截图预演用的假 home。规矩沿用 `MM_ORPHAN_FIXTURE_HOME`：只认 /tmp 之下，
    /// 因为这一屏的终点是删除按钮——钩子绝不能把用户的真项目变成可以整片勾选的夹具。
    static var fixtureHome: String? {
        guard let raw = ProcessInfo.processInfo.environment["MM_PURGE_FIXTURE_HOME"],
              raw.hasPrefix("/tmp/") || raw.hasPrefix("/private/tmp/"),
              let resolved = realpath(raw, nil) else { return nil }
        defer { free(resolved) }
        let home = String(cString: resolved)
        guard home.hasPrefix("/tmp/") || home.hasPrefix("/private/tmp/") else { return nil }
        return home
    }

    var scanHome: String { Self.fixtureHome ?? NSHomeDirectory() }

    var groups: [ProjectArtifactGroup] { report?.groups ?? [] }

    /// 有勾选框的行：证据成立 **且** 体积真的量到了。
    /// 量不到体积的行即便判为可回收也不给删——用户看不到多大就要按删除，等于盲选。
    var selectableArtifacts: [ProjectArtifact] {
        groups.flatMap(\.artifacts).filter { $0.isSelectable }
    }

    var reclaimableSize: UInt64? {
        groups.flatMap(\.artifacts).reduce(UInt64?.none) { sum, artifact in
            guard artifact.isSelectable, let size = artifact.size else { return sum }
            return (sum ?? 0) + size
        }
    }

    var selectedSize: UInt64? {
        let picked = groups.flatMap(\.artifacts).filter { selectedPaths.contains($0.id) }
        guard !picked.isEmpty else { return nil }
        var total: UInt64 = 0
        for artifact in picked {
            // 少一行体积就说"未测全"，不静默把那一行跳过——跳过就是少报，
            // 而"已选 X GB"是用户按下删除按钮时唯一在看的那个数。
            guard let size = artifact.size else { return nil }
            total += size
        }
        return total
    }

    var truncatedRoots: [String] { report?.truncatedRoots ?? [] }
    var isPartial: Bool { report.map { !$0.isComplete } ?? false }

    func scan() {
        scanTask?.cancel()
        isScanning = true
        let home = scanHome
        let task = Task { [weak self] in
            let report = await ProjectArtifactScanner(home: home,
                                                      rules: ProjectArtifactRules.default(home: home))
                .scan()
            guard !Task.isCancelled else { return }
            self?.apply(report)
        }
        scanTask = task
    }

    private func apply(_ report: ProjectArtifactReport) {
        // 上一轮的勾选不能带到新一轮：路径可能已经不存在，勾着一个不存在的目录
        // 按删除，回执里只会是一串"找不到文件"。
        self.report = report
        self.scannedAt = .now
        self.scanDuration = report.duration
        selectedPaths = []
        isScanning = false
        if ProcessInfo.processInfo.environment["MM_DEV_EXPAND"] != nil {
            expandedRoots = Set(report.groups.map(\.id))
        }
        if ProcessInfo.processInfo.environment["MM_DEV_SELECT"] == "untouched" {
            selectUntouched()
        }
    }

    func toggleGroup(_ group: ProjectArtifactGroup) {
        if expandedRoots.contains(group.id) {
            expandedRoots.remove(group.id)
        } else {
            expandedRoots.insert(group.id)
        }
    }

    func toggle(_ artifact: ProjectArtifact) {
        guard artifact.isSelectable else { return }
        if selectedPaths.contains(artifact.id) {
            selectedPaths.remove(artifact.id)
        } else {
            selectedPaths.insert(artifact.id)
        }
    }

    /// 批量只挑"证据成立 + 久未触碰"的：近期在用的行即便可勾选也不进批量，
    /// 那一档的语义就是"可能正在编译"，批量按钮不该替用户冒这个风险。
    func selectUntouched() {
        selectedPaths = Set(selectableArtifacts.filter {
            if case .untouchedForDays = $0.activity { return true }
            return false
        }.map(\.id))
    }

    func clearSelection() {
        selectedPaths = []
    }

    func clean() {
        let paths = Array(selectedPaths).sorted()
        guard !paths.isEmpty else { return }
        isCleaning = true
        Task { [weak self] in
            guard let self else { return }
            let result = await FileTrashService.shared.moveToTrash(paths: paths)
            self.lastResult = result
            self.failures = result.operation.failures
            self.selectedPaths = []
            self.isCleaning = false
            // 产物目录会被工具重新写出来，清单只在扫描那一刻成立；
            // 删完直接重扫，比在旧清单上手工摘几行更诚实（也顺手把新长出来的显示出来）。
            self.scan()
        }
    }

    func undo() {
        let operationID = lastResult?.operation.id
        isCleaning = true
        Task { [weak self] in
            guard let self else { return }
            let restored: UndoResult
            if let operationID {
                restored = await FileTrashService.shared.undo(operationID: operationID)
            } else {
                restored = await FileTrashService.shared.undoLastOperation()
            }
            self.failures = restored.failures
            self.lastResult = nil
            self.isCleaning = false
            self.scan()
        }
    }
}

// MARK: - 页面

struct DevArtifactView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var model = DevArtifactModel()
    @State private var showConfirm = false
    @State private var toastSeconds = 0

    var body: some View {
        VStack(spacing: 0) {
            MMPageHeader("开发产物", subtitle: headerSubtitle) {
                Button {
                    model.scan()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
            }

            scopeBar

            if model.isScanning && model.report == nil {
                MMScanProgress(action: "正在扫描开发目录", currentPath: nil,
                               processedCount: 0, estimatedRemaining: nil, progress: nil)
                Spacer()
            } else if model.groups.isEmpty {
                MMEmptyState(
                    systemImage: "hammer",
                    title: "没找到可回收的项目构建产物",
                    detail: "扫描根里没认出带清单文件（package.json / Cargo.toml / Package.swift 等）的项目目录。"
                        + "项目放在别处的话，把那个位置加进设置页的扫描范围再扫一次。",
                    action: AnyView(Button("重新扫描") { model.scan() })
                )
            } else {
                summaryBar
                groupTable
            }

            if !model.failures.isEmpty {
                MMFailurePanel(
                    summary: "已回收 \(MMFormat.bytes(model.lastResult?.totalSize))",
                    model.failures
                ) {
                    model.failures = []
                }
            }

            Divider()
            actionBar
                .sheet(isPresented: $showConfirm) { confirmSheet }
        }
        .task {
            if model.report == nil, !model.isScanning { model.scan() }
            if ProcessInfo.processInfo.environment["MM_DEV_CONFIRM"] != nil { showConfirm = true }
        }
        .task(id: toastSeconds) {
            guard toastSeconds > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            toastSeconds -= 1
        }
        .overlay(alignment: .bottom) {
            if model.lastResult != nil, settings.allowUndo, toastSeconds > 0 {
                MMUndoToast(
                    message: "已回收 \(MMFormat.bytes(model.lastResult?.totalSize))",
                    detail: "\(model.lastResult?.successCount ?? 0) 处产物已移入废纸篓",
                    secondsRemaining: toastSeconds,
                    onUndo: { model.undo() },
                    onRevealTrash: { MMReveal.openDirectory(NSHomeDirectory() + "/.Trash") }
                )
                .padding(.bottom, MMMetric.actionBar + MMGap.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: toastSeconds)
        .onChange(of: model.lastResult?.operation.id) { _, newValue in
            guard newValue != nil, settings.allowUndo else { return }
            toastSeconds = 15
        }
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        parts.append("\(model.groups.count) 个项目 · \(model.groups.reduce(0) { $0 + $1.artifacts.count }) 处产物")
        if let at = model.scannedAt { parts.append("扫描于 \(MMFormat.dateTime(at))") }
        if let duration = model.scanDuration {
            parts.append("耗时 \(String(format: "%.1f", duration)) 秒")
        }
        if !model.truncatedRoots.isEmpty {
            parts.append("\(model.truncatedRoots.count) 个根没扫完")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 扫描范围条

    private var scopeBar: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            HStack(spacing: MMGap.sm) {
                Text("扫描根").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                ForEach(Array(rootsToShow.prefix(7)), id: \.self) { root in
                    Text(abbreviated(root))
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(MMColor.recessedSurface,
                                    in: RoundedRectangle(cornerRadius: MMRadius.badge, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: MMRadius.badge, style: .continuous)
                            .stroke(MMColor.separator))
                }
                if let extra = model.report?.scannedRoots.count, extra > 7 {
                    Text("另有 \(extra - 7) 个").font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                }
                Spacer(minLength: MMGap.md)
            }
            HStack(alignment: .top, spacing: MMGap.xs) {
                Image(systemName: "info.circle").font(.caption2)
                    .foregroundStyle(MMColor.tertiaryLabel)
                Text("只读扫描：不跟随符号链接，链接指向夹具之外的目录一律不列；"
                     + "项目根靠 package.json / Cargo.toml / Package.swift 这类清单文件认定，认不出项目根的产物不列出来。"
                     + outOfRootNote)
                    .font(.caption2).foregroundStyle(MMColor.secondaryLabel)
                Spacer(minLength: 0)
            }
            if !model.truncatedRoots.isEmpty {
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "exclamationmark.triangle").font(.caption2)
                        .foregroundStyle(MMColor.caution)
                    Text("有 \(model.truncatedRoots.count) 个根扫到一半就超时，本轮不报数："
                         + model.truncatedRoots.prefix(2).map(abbreviated).joined(separator: "、")
                         + "。截断范围内的项目没被扫过，不等于它们干净。")
                        .font(.caption2).foregroundStyle(MMColor.caution)
                    Spacer(minLength: 0)
                }
            }
            if let report = model.report, !report.inaccessibleRoots.isEmpty {
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "lock").font(.caption2)
                        .foregroundStyle(MMColor.caution)
                    Text("有 \(report.inaccessibleRoots.count) 个根读不进去（权限或 TCC 拒绝）："
                         + report.inaccessibleRoots.prefix(2).map(abbreviated).joined(separator: "、")
                         + "。它们不计入总量，也不会被说成「很干净」。")
                        .font(.caption2).foregroundStyle(MMColor.caution)
                    Spacer(minLength: 0)
                }
            }
            if let report = model.report, !report.missingRoots.isEmpty {
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "questionmark.circle").font(.caption2)
                        .foregroundStyle(MMColor.tertiaryLabel)
                    Text("另有 \(report.missingRoots.count) 个默认搜索根在这台 Mac 上不存在（是压根没有，不是读不动）："
                         + report.missingRoots.prefix(3).map(abbreviated).joined(separator: "、")
                         + (report.missingRoots.count > 3 ? "…" : "")
                         + "。项目放在别处的话，home 下的一级目录仍会被当容器扫。")
                        .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.recessedSurface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var rootsToShow: [String] {
        model.report?.scannedRoots ?? ProjectArtifactRules.default(home: model.scanHome).searchRoots
    }

    /// 越界候选数：名字像产物、但解析符号链接后落在了搜索根之外。
    /// 这些行不会出现在清单里，所以数量必须单独说一句——不然是把丢掉的证据
    /// 静默藏起来，读者会以为清单是全的。
    private var outOfRootNote: String {
        let count = model.report?.outOfSearchRootCandidateCount ?? 0
        guard count > 0 else { return "" }
        return "另有 \(count) 个候选在解析符号链接后越出了搜索根，已丢弃、不列进清单。"
    }

    private func abbreviated(_ path: String) -> String {
        path.hasPrefix(model.scanHome) ? "~" + path.dropFirst(model.scanHome.count) : path
    }

    // MARK: 汇总条

    private var summaryBar: some View {
        HStack(spacing: MMGap.md) {
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text("\(model.groups.count) 个项目 · "
                     + "\(model.groups.reduce(0) { $0 + $1.artifacts.count }) 处产物 · "
                     + reclaimableHeadline)
                    .font(.callout.weight(.semibold)).monospacedDigit()
                Text("默认一项都不勾选。批量按钮只会挑「证据成立且 7 天以上没碰过」的行；"
                     + "近期在用、受保护、体积读不到的行不会被自动选中。")
                    .font(.caption2).foregroundStyle(MMColor.secondaryLabel)
            }
            Spacer(minLength: MMGap.md)
            Button("选中 7 天未触碰的") { model.selectUntouched() }
                .disabled(model.selectableArtifacts.isEmpty)
            Button("取消全选") { model.clearSelection() }
                .disabled(model.selectedPaths.isEmpty)
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 汇总条上的头号数字。整页没有一处可勾选时说"无可回收条目"，有可勾选的
    /// 但体积没测全时写"—"：这一屏最显眼的那个 GB 宁可少说，也不能编。
    private var reclaimableHeadline: String {
        guard !model.selectableArtifacts.isEmpty else { return "无可回收条目" }
        guard let size = model.reclaimableSize else { return "可回收 —（有产物没测到体积）" }
        return "可回收 \(MMFormat.bytes(size))"
    }

    // MARK: 分组清单

    private var groupTable: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        headerRow.id("header")
                        ForEach(model.groups) { group in
                            groupHeader(group)
                            if model.expandedRoots.contains(group.id) {
                                ForEach(group.artifacts) { artifact in
                                    artifactRow(artifact)
                                }
                            }
                        }
                        footnote.id("footnote")
                    }
                    // 与清理主页同一条教训：LazyVStack 在 ScrollView 里按最宽子项排版，
                    // 不显式给宽整张表会横向溢出。
                    .frame(width: proxy.size.width - MMGap.lg * 2)
                    .background(MMColor.contentBackground)
                    .overlay(RoundedRectangle(cornerRadius: MMRadius.card).stroke(MMColor.separator))
                    .padding(.horizontal, MMGap.lg)
                    .padding(.vertical, MMGap.md)
                }
                // MM_DEV_SCROLL=end：截图取证用。窗口高度受屏幕限制，列表下半截
                // （CACHEDIR.TAG 最强档、读不到的行、嵌套行）默认进不了画面，
                // 而合成滚动事件会逃逸到用户的其它应用——只能让 app 自己滚。
                .task(id: model.groups.count) {
                    guard ProcessInfo.processInfo.environment["MM_DEV_SCROLL"] == "end",
                          !model.groups.isEmpty else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    scroller.scrollTo("footnote", anchor: .bottom)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: MMGap.md) {
            Toggle("", isOn: selectAllBinding).toggleStyle(.checkbox).labelsHidden()
            Text("产物 · 相对项目根的路径").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("体积").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                .frame(minWidth: 84, alignment: .trailing)
            Text("状态").font(.caption).foregroundStyle(MMColor.secondaryLabel)
                .frame(width: 132, alignment: .trailing)
                .padding(.trailing, 22 + MMGap.md)   // 让开每行的访达按钮
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: MMMetric.rowCompact)
        .background(MMColor.recessedSurface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var selectAllBinding: Binding<Bool> {
        let selectable = model.selectableArtifacts
        return Binding(
            get: { !selectable.isEmpty && selectable.allSatisfy { model.selectedPaths.contains($0.id) } },
            set: { on in
                model.selectedPaths = on ? Set(selectable.map(\.id)) : []
            }
        )
    }

    private func groupHeader(_ group: ProjectArtifactGroup) -> some View {
        HStack(spacing: MMGap.sm) {
            Image(systemName: model.expandedRoots.contains(group.id)
                  ? "chevron.down" : "chevron.right")
                .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                .frame(width: 12)
            Image(systemName: "folder").font(.caption).foregroundStyle(MMColor.tertiaryLabel)
            Text(group.displayName).font(.callout.weight(.semibold)).lineLimit(1)
            Text(group.relativeToHome)
                .font(.caption.monospaced())
                .foregroundStyle(MMColor.secondaryLabel)
                .lineLimit(1).truncationMode(.middle)
            if group.isCloudSynced {
                MMBadge("iCloud 同步", tint: MMColor.caution, systemImage: "icloud")
            }
            Spacer(minLength: MMGap.sm)
            Text(groupSummary(group))
                .font(.caption.monospaced()).foregroundStyle(MMColor.secondaryLabel)
            if let indicator = group.monorepoIndicator {
                MMBadge(indicator, tint: MMColor.informational)
            }
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: MMMetric.rowCompact + 4)
        .background(MMColor.cardSurface)
        .contentShape(Rectangle())
        .onTapGesture { model.toggleGroup(group) }
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    /// 组头的小计。三种情况得分开说：整组没有一处可勾选（全受保护或全在用）、
    /// 有可勾选的但体积没测全、以及正常的数字。把前两种都写成"0 字节"，
    /// 等于把"没东西可删"和"没量到"混成同一个数。
    private func groupSummary(_ group: ProjectArtifactGroup) -> String {
        let count = "\(group.artifacts.count) 处"
        guard group.artifacts.contains(where: \.isSelectable) else { return "无可回收 · \(count)" }
        return "\(group.reclaimableSize.map { MMFormat.bytes($0) } ?? "—") · \(count)"
    }

    private func artifactRow(_ artifact: ProjectArtifact) -> some View {
        let style = artifact.rowStyle
        return VStack(spacing: 0) {
            HStack(spacing: MMGap.md) {
                if artifact.isSelectable {
                    Toggle("", isOn: selectionBinding(for: artifact))
                        .toggleStyle(.checkbox).labelsHidden()
                } else {
                    // 占位保持列对齐：受保护的行没有勾选框，但列不能因此错位。
                    Toggle("", isOn: .constant(false)).toggleStyle(.checkbox).labelsHidden()
                        .disabled(true).opacity(0.35)
                }
                VStack(alignment: .leading, spacing: MMGap.xxs) {
                    Text(artifact.name)
                        .font(.body.weight(style.isStrongestEvidence ? .semibold : .medium))
                        .foregroundStyle(style.isDimmed ? MMColor.secondaryLabel : MMColor.label)
                        .lineLimit(1)
                    Text(artifact.relativeToProject)
                        .font(.caption.monospaced())
                        .foregroundStyle(MMColor.secondaryLabel)
                        .lineLimit(1).truncationMode(.middle)
                    if let note = style.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(MMColor.tertiaryLabel)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: MMGap.sm)
                Text(artifact.size.map { MMFormat.bytes($0) } ?? "—")
                    .font(.callout.monospaced())
                    .foregroundStyle(artifact.size == nil ? MMColor.tertiaryLabel : MMColor.label)
                    .frame(minWidth: 84, alignment: .trailing)
                MMBadge(style.badgeText, tint: style.badgeTint, systemImage: style.badgeSymbol)
                    .frame(width: 132, alignment: .trailing)
                MMRowAction(systemImage: "folder", help: "在访达中打开") { MMReveal.open(artifact.path) }
            }
            .padding(.horizontal, MMGap.md)
            .frame(minHeight: MMMetric.rowRegular)
            .background(rowBackground(style, selected: model.selectedPaths.contains(artifact.id)))
            .overlay(alignment: .leading) {
                if style.isStrongestEvidence {
                    Rectangle().fill(MMColor.accent).frame(width: 3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.toggle(artifact) }
            Divider().opacity(0.6)
        }
    }

    /// 四种底色互斥：选中（含最强证据）> 整行降级（受保护 / 读不到）> 无底色。
    private func rowBackground(_ style: DevArtifactRowStyle, selected: Bool) -> Color {
        if selected { return MMColor.soft(MMColor.accent, 0.08) }
        if style.isStrongestEvidence { return MMColor.soft(MMColor.informational, 0.07) }
        if style.isDimmed { return MMColor.recessedSurface.opacity(0.6) }
        return .clear
    }

    private func selectionBinding(for artifact: ProjectArtifact) -> Binding<Bool> {
        Binding(
            get: { model.selectedPaths.contains(artifact.id) },
            set: { _ in model.toggle(artifact) }
        )
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: MMGap.xs) {
            Image(systemName: "info.circle").font(.caption).foregroundStyle(MMColor.tertiaryLabel)
            Text("删除一律先移入废纸篓，可在「最近操作」里撤回；受保护的行不给勾选框，"
                 + "原因是名字相同不代表能重建（Go 的 vendor/ 是源码、产物目录里有 .git 就是签出的仓库）。"
                 + "MacMaster 不执行 git、cargo 这类第三方二进制，判定只用目录里看得见的证据。")
                .font(.caption).foregroundStyle(MMColor.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
    }

    // MARK: 底部操作栏

    /// 一处都没选时说"已选 0 处"，不说"体积未测全"——"没选"和"量不到"是两件事，
    /// 混在一句话里会让用户以为扫描出了问题。
    private var actionBarSummary: String {
        let count = model.selectedPaths.count
        guard count > 0 else { return "已选 0 处" }
        return "已选 \(count) 处 · " + (model.selectedSize.map { MMFormat.bytes($0) } ?? "体积未测全")
    }

    private var actionBar: some View {
        MMActionBar(
            summary: actionBarSummary,
            note: model.isPartial
                ? "扫描未完成，数字只包含已扫到的部分"
                : "未勾选项不会被修改；受保护的行没有勾选框"
        ) {
            EmptyView()
        } trailing: {
            // 按钮上不带数字：数字是 summary 的活（"已选 N 处 · X"），这里跟着缓存清理页
            // 和磁盘页写死"移入废纸篓"。曾经写成"移 0 处产物入废纸篓"，两桩毛病：
            // 一个禁用按钮报 0 像是算错了数，而且这串长标题在最小窗口下会被截掉尾巴。
            Button(model.isCleaning ? "清理中…" : "移入废纸篓") {
                if settings.confirmBeforeDelete {
                    showConfirm = true
                } else {
                    model.clean()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(MMColor.destructive)
            .disabled(model.selectedPaths.isEmpty || model.isScanning || model.isCleaning)
        }
    }

    private var confirmSheet: some View {
        let picked = model.groups.flatMap(\.artifacts).filter { model.selectedPaths.contains($0.id) }
        return VStack(alignment: .leading, spacing: MMGap.md) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MMColor.destructive)
                Text("移除 \(picked.count) 处构建产物？").font(.headline)
            }
            Text("这些目录由各自的工具重建：下次安装依赖或编译会长回来，代价是重下与重编的时间。"
                 + "先移入废纸篓，可撤回。")
                .font(.callout).foregroundStyle(MMColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            // 与清理主页同一条教训：确认框是删除前的最后一站，清单要一次看全，
            // 不用滚动条——ScrollView 在 sheet 里会被压成零高，等于什么都没列出来。
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                ForEach(picked.prefix(12)) { artifact in
                    HStack(spacing: MMGap.sm) {
                        Text(artifact.name).font(.callout.weight(.medium))
                        Text(abbreviated(artifact.path))
                            .font(.caption.monospaced())
                            .foregroundStyle(MMColor.secondaryLabel)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: MMGap.sm)
                        Text(artifact.size.map { MMFormat.bytes($0) } ?? "—")
                            .font(.caption.monospaced()).foregroundStyle(MMColor.secondaryLabel)
                    }
                    .padding(.vertical, 2)
                }
                if picked.count > 12 {
                    Text("另有 \(picked.count - 12) 处（清单在扫描页里逐行可见）")
                        .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                }
            }
            .padding(MMGap.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.recessedSurface, in: RoundedRectangle(cornerRadius: MMRadius.control))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.control).stroke(MMColor.separator))
            HStack(spacing: MMGap.md) {
                Spacer()
                Button("取消") { showConfirm = false }.keyboardShortcut(.cancelAction)
                Button("移入废纸篓") {
                    showConfirm = false
                    model.clean()
                }
                .buttonStyle(.borderedProminent)
                .tint(MMColor.destructive)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MMGap.lg)
        .frame(width: 520)
    }
}

// MARK: - 行的呈现口径
//
// 扫描层只给事实（verdict / activity / 是否嵌套 / 体积量没量到），"这行挂哪个徽章、
// 底下那行小字写什么"是 UI 的判断，留在 MMCleaner 一侧：扫描器不该认识颜色和图标。
// 分支顺序就是优先级：受保护压过一切（里面就算长着 CACHEDIR.TAG 也不能给勾选框），
// 其次是"体积没量到"——两个都不该被更花哨的徽章盖过去。

struct DevArtifactRowStyle {
    let badgeText: String
    let badgeTint: Color
    let badgeSymbol: String?
    /// 名称与相对路径之下的第三行小字：这一行为什么是这个结论。nil 就不占行。
    let note: String?
    /// 最强证据档（CACHEDIR.TAG）：左侧 3pt 强调条 + 蓝底。
    let isStrongestEvidence: Bool
    /// 受保护 / 体积读不到的行整行降级：灰底，名字取次级文字色。
    let isDimmed: Bool
}

extension ProjectArtifact {
    /// 有勾选框 = 判为可回收 **且** 体积真的量到了 **且** 不是嵌套行。
    /// 量不到体积的行即便证据成立也不给删：看不见多大就按删除等于盲选。
    var isSelectable: Bool {
        guard !isNestedInAnotherArtifact, size != nil else { return false }
        if case .reclaimable = verdict { return true }
        return false
    }

    var rowStyle: DevArtifactRowStyle {
        if case .protected(let reason) = verdict {
            return DevArtifactRowStyle(badgeText: "受保护", badgeTint: MMColor.secondaryLabel,
                                       badgeSymbol: "lock", note: reason,
                                       isStrongestEvidence: false, isDimmed: true)
        }
        if isNestedInAnotherArtifact {
            return DevArtifactRowStyle(badgeText: "已计入上一行", badgeTint: MMColor.secondaryLabel,
                                       badgeSymbol: nil,
                                       note: "嵌套在另一处产物里，体积只在祖先那一行计一次，不重复统计",
                                       isStrongestEvidence: false, isDimmed: true)
        }
        // 到这儿 verdict 一定是 reclaimable。
        let evidenceIsTag: Bool
        if case .reclaimable(.cacheDirectoryTag) = verdict { evidenceIsTag = true }
        else { evidenceIsTag = false }

        if size == nil {
            return DevArtifactRowStyle(badgeText: "读不到", badgeTint: MMColor.caution,
                                       badgeSymbol: nil,
                                       note: "体积没能测到（读不动或预算用尽），不折成 0 字节，也不计入合计",
                                       isStrongestEvidence: false, isDimmed: true)
        }
        switch activity {
        case .touchedDaysAgo(let days):
            return DevArtifactRowStyle(badgeText: days == 0 ? "今天改动过" : "\(days) 天前改动过",
                                       badgeTint: MMColor.caution, badgeSymbol: nil,
                                       note: "可能正在编译或调试，默认不选中，也不会被批量按钮挑中",
                                       isStrongestEvidence: false, isDimmed: false)
        case .unknown(let reason):
            return DevArtifactRowStyle(badgeText: "未确认", badgeTint: MMColor.secondaryLabel,
                                       badgeSymbol: nil,
                                       note: "改动时间没探到（\(reason)）：探测失败不是「很久没碰」的证据",
                                       isStrongestEvidence: false, isDimmed: false)
        case .untouchedForDays(let days):
            if evidenceIsTag {
                return DevArtifactRowStyle(badgeText: "目录自述为缓存", badgeTint: MMColor.informational,
                                           badgeSymbol: "tag",
                                           note: "目录自带 CACHEDIR.TAG 标记文件——最强的一档证据 · \(days) 天未触碰",
                                           isStrongestEvidence: true, isDimmed: false)
            }
            return DevArtifactRowStyle(badgeText: "\(days) 天未触碰", badgeTint: MMColor.safe,
                                       badgeSymbol: nil, note: evidenceNoteForReclaimable,
                                       isStrongestEvidence: false, isDimmed: false)
        }
    }

    /// 名字本身不足以定性的行（bin / obj / vendor / target / build…），
    /// 把扫描器给出的邻居证据原样抄上行；名字本身就够的行不再加小字，
    /// 免得每行都写一堆解释，反而把真正需要解释的行淹没。
    private var evidenceNoteForReclaimable: String? {
        guard case .reclaimable(let evidence) = verdict else { return nil }
        switch evidence {
        case .nameIsEnough, .cacheDirectoryTag: return nil
        case .contextProven(let detail): return detail
        }
    }
}
