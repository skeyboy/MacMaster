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

    // MARK: 分批续扫的状态（P6.1）

    /// 当前清单由几批拼成。1 = 一次全量扫完；>1 时副标题必须说"这张清单是拼出来的"——
    /// 各批的时刻不同，只写「扫描于 X 时」会把第一批的观测说成最后一批的。
    @Published private(set) var batchCount = 1
    /// 最近一批**真正扫完**的根（点名条的「✓ 本轮」chip 与组头的「第 N 批补全」都取它）。
    /// 存这个而不是"这一批跑了哪些根"：跑了但再次截断的根不算本轮，它还得是橙色。
    @Published private(set) var lastBatchRoots: Set<String> = []
    /// 最近一批**补全**的行（组头「第 2 批补全」取它）。与 `lastBatchRoots` 分开记：
    /// 根扫完了不等于这一组补上了东西——整行复用的组会被错标，见 `rowsCompletedByBatch`。
    @Published private(set) var lastBatchRows: Set<String> = []
    @Published private(set) var lastBatchDuration: TimeInterval?
    /// 每个截断根在**本次会话**里试过几次。不跨启动保存：它唯一的作用是
    /// "这个根在预算内就是扫不完"那句改口，而磁盘状况下次启动就不一样了。
    @Published private(set) var triedRoots: [String: Int] = [:]

    /// 一个根续扫到第 2 次仍截断就改口、不再给按钮（D7）。第 3 次按下去大概率是
    /// 同一个 15 秒白费，而且让"再按一次"的代价变得不可预期。
    static let maxAttemptsPerRoot = 2

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

    /// 点名条要说"多少秒内扫不完"，这个数就必须和扫描器实际用的那个同源。
    /// 抄字面量 15 的话，钩子一改文案就开始骗人。
    var rootBudgetSeconds: Double { rules(forContinuation: false).rootBudgetSeconds }

    /// 还能续扫的根：试满 `maxAttemptsPerRoot` 次的已经从按钮名单里退出。
    var continuableRoots: [String] {
        truncatedRoots.filter { (triedRoots[$0] ?? 0) < Self.maxAttemptsPerRoot }
    }

    /// 试满次数的根：点名条从"给一个继续扫的按钮"换成"说清这是这一处的上限"。
    var exhaustedRoots: [String] {
        truncatedRoots.filter { (triedRoots[$0] ?? 0) >= Self.maxAttemptsPerRoot }
    }

    var canContinueTruncatedRoots: Bool { report != nil && !continuableRoots.isEmpty }

    /// 按钮上的数字。设计稿写死了口径："数字是这一批真正要重跑的根数，不是截断根的总数"。
    /// 全部试满时按钮仍要出现但置灰（D7）：藏起来等于什么都不说，而"不是坏了，
    /// 是不该再按"恰恰是这一档要让读者看见的那件事。
    var continueButtonRootCount: Int {
        continuableRoots.isEmpty ? truncatedRoots.count : continuableRoots.count
    }

    /// 组头「第 N 批补全」：这一组里有行是最近一批才把证据看全的。
    /// 只在 batchCount > 1 时才有意义，第一批的清单不需要说自己由几批拼成。
    func containsLatestBatch(_ group: ProjectArtifactGroup) -> Bool {
        guard batchCount > 1, !lastBatchRows.isEmpty else { return false }
        return group.artifacts.contains { lastBatchRows.contains($0.id) }
    }

    /// 预算覆盖钩子，只在截图取证时用（值必须 >0 才生效，真机不设就是原口径）。
    /// 为什么要两个键：同一个极小预算下，第 1 批截断的根在第 2 批必然同样截断，
    /// 「本轮扫完」那一档就永远拍不到。全量批次与续扫批次各自独立，
    /// 才能同时定格"首批必截断"与"续扫扫得完"。
    private static func budgetOverride(_ key: String) -> Double? {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let value = Double(raw), value > 0 else { return nil }
        return value
    }

    private func rules(forContinuation: Bool) -> ProjectArtifactRules {
        var rules = ProjectArtifactRules.default(home: scanHome)
        let key = forContinuation ? "MM_DEV_CONTINUE_BUDGET_SECONDS" : "MM_DEV_ROOT_BUDGET_SECONDS"
        if let override = Self.budgetOverride(key) {
            rules.rootBudgetSeconds = override
            // 总预算跟着抬：只改每根预算而总时限仍写死 60 秒的话，钩子写 120
            // 实际拿到的是 60——"这一根给了多少"就跟钩子说的不是一回事了。
            rules.totalBudgetSeconds = max(rules.totalBudgetSeconds, override)
        }
        return rules
    }

    /// 取证钩子：全量扫完之后自动再跑最多 N 批续扫（只认 1…3）。
    /// 有了它，「续扫之后」与「已试过 2 次」两档都不需要点一次按钮才能进——
    /// 禁合成点击这条老规矩下，按钮的点击链本身不在取证范围。
    private static var autoContinueCount: Int? {
        guard let raw = ProcessInfo.processInfo.environment["MM_DEV_AUTO_CONTINUE"],
              let value = Int(raw), (1...3).contains(value) else { return nil }
        return value
    }

    func scan() {
        scanTask?.cancel()
        isScanning = true
        let home = scanHome
        let task = Task { [weak self] in
            guard let self else { return }
            let report = await ProjectArtifactScanner(home: home, rules: self.rules(forContinuation: false))
                .scan()
            guard !Task.isCancelled else { return }
            self.apply(report)
            if let batches = Self.autoContinueCount {
                self.runContinuations(remaining: batches)
            }
        }
        scanTask = task
    }

    /// 续扫被截断的根。**显式传根**：不重新探测 home 一级容器（调研文档 §3.4）——
    /// 新出现的顶层项目属于「重新扫描」的语义，续扫只负责把上一批没量完的地方量完。
    /// 上一批已经看完证据的行整行复用，这一批的预算全花在没量完的行上：
    /// 实测截断吃在成案阶段而不是遍历阶段，复用才是续扫比全量重扫快的原因。
    func continueTruncatedRoots(onFinish: (@MainActor () -> Void)? = nil) {
        let roots = continuableRoots
        guard let base = report, !roots.isEmpty else { onFinish?(); return }
        var reuse: [String: ProjectArtifact] = [:]
        for artifact in base.groups.flatMap(\.artifacts)
        where ProjectArtifactScanner.isCompleteObservation(artifact) {
            reuse[artifact.path] = artifact
        }
        isScanning = true
        let home = scanHome
        let task = Task { [weak self] in
            guard let self else { return }
            let continuation = await ProjectArtifactScanner(home: home,
                                                            rules: self.rules(forContinuation: true))
                .scan(roots: roots, reuse: reuse)
            guard !Task.isCancelled else { return }
            self.applyMerged(continuation, rootsRun: roots)
            onFinish?()
        }
        scanTask = task
    }

    /// 连着跑几批续扫（只有 `MM_DEV_AUTO_CONTINUE` 会用到）。
    /// 每批之间检查 `canContinueTruncatedRoots`：中途扫完就没有下一批，
    /// 试满两次也被排除，所以这里最多跑 N 批就停，不会自己循环成常驻扫描。
    private func runContinuations(remaining: Int) {
        guard remaining > 0, canContinueTruncatedRoots else { return }
        continueTruncatedRoots { [weak self] in
            self?.runContinuations(remaining: remaining - 1)
        }
    }

    private func apply(_ report: ProjectArtifactReport) {
        // 上一轮的勾选不能带到新一轮：路径可能已经不存在，勾着一个不存在的目录
        // 按删除，回执里只会是一串"找不到文件"。
        self.report = report
        self.scannedAt = .now
        self.scanDuration = report.duration
        selectedPaths = []
        isScanning = false
        // 「重新扫描」= 全新账本：批数、本轮扫完的根、尝试计数全部归零。
        // 上一轮"这个根已经试过 2 次"的判断不污染这一轮——磁盘状况与预算都已不同。
        batchCount = 1
        lastBatchRoots = []
        lastBatchRows = []
        lastBatchDuration = nil
        // 首批就是每个截断根的**第一次**尝试：计数从 1 起算，"已经扫过 2 次"才是
        // 两批的事实而不是三批。漏了这一步，改口要等到第三次扫描才出现。
        triedRoots = ProjectArtifactScanner.attemptCounts(
            rootsRun: report.scannedRoots + report.truncatedRoots,
            stillTruncated: Set(report.truncatedRoots), previous: [:])
        if ProcessInfo.processInfo.environment["MM_DEV_EXPAND"] != nil {
            expandedRoots = Set(report.groups.map(\.id))
        }
        if ProcessInfo.processInfo.environment["MM_DEV_SELECT"] == "untouched" {
            selectUntouched()
        }
    }

    private func applyMerged(_ continuation: ProjectArtifactReport, rootsRun: [String]) {
        guard let base = report else { return }
        let merged = ProjectArtifactScanner.mergedReport(base: base, continuation: continuation,
                                                         home: scanHome)
        report = merged
        batchCount += 1
        lastBatchRoots = Set(rootsRun).intersection(merged.scannedRoots)
        lastBatchRows = ProjectArtifactScanner.rowsCompletedByBatch(base: base, merged: merged)
        lastBatchDuration = continuation.duration
        triedRoots = ProjectArtifactScanner.attemptCounts(
            rootsRun: rootsRun,
            stillTruncated: Set(continuation.truncatedRoots),
            previous: triedRoots
        )
        // 续扫不新增删除权限，也**不清空**勾选：它只会让已有的行改变结论
        // （被重标成"已计入上一行"、或改判受保护），那些行的勾选框必须跟着消失。
        // 清空是把"修剪"做成"全撤"——用户上一批的勾选会被无端抹掉。
        selectedPaths = ProjectArtifactScanner.survivingSelection(selectedPaths, report: merged) {
            $0.isSelectable
        }
        // 「扫描于」改成"最近一批的时刻"：分批清单的时间戳只对最后一批成立。
        scannedAt = .now
        scanDuration = merged.duration
        isScanning = false
        if ProcessInfo.processInfo.environment["MM_DEV_EXPAND"] != nil {
            expandedRoots = Set(merged.groups.map(\.id))
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
                // 续扫按钮放在页头而不是扫描根那一行：那一行本来就要容纳七八枚 chip，
                // 再塞两枚按钮在 1000pt 最小窗下必然挤掉 chip 的文字（P5.1 的教训）。
                if !model.truncatedRoots.isEmpty {
                    Button {
                        model.continueTruncatedRoots()
                    } label: {
                        Label("继续扫描这 \(model.continueButtonRootCount) 个根", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isScanning || !model.canContinueTruncatedRoots)
                }
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
                    summary: model.lastResult.map { "已回收 \(MMFormat.bytes($0.totalSize))" },
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
        if model.batchCount > 1 {
            // 分批拼出来的清单不能说"扫描于 X 时"就完事：那个时刻只属于最后一批，
            // 第一批的行可能早好几分钟。"这张清单是拼出来的"得写在脸上。
            parts.append("本清单由 \(model.batchCount) 批拼成")
        }
        if let at = model.scannedAt {
            parts.append(model.batchCount > 1 ? "最近一批扫于 \(MMFormat.dateTime(at))"
                                              : "扫描于 \(MMFormat.dateTime(at))")
        }
        if let duration = model.scanDuration {
            // 合并报告的 duration 是各批之和。单批时写"耗时"没问题，多批时不写
            // "累计"，它就会和下面点名条里"第 N 批用了 X 秒"打架——两个数都对，
            // 只是量的不是同一件事。
            parts.append("\(model.batchCount > 1 ? "累计耗时" : "耗时") \(secondsText(duration)) 秒")
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
                    rootChip(root)
                }
                if rootsToShow.count > 7 {
                    Text("另有 \(rootsToShow.count - 7) 个").font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                }
                Spacer(minLength: MMGap.md)
            }
            HStack(alignment: .top, spacing: MMGap.xs) {
                Image(systemName: "info.circle").font(.caption2)
                    .foregroundStyle(MMColor.tertiaryLabel)
                Text("只读扫描：不跟随符号链接，链接指向夹具之外的目录一律不列；"
                     + "项目根靠 package.json / Cargo.toml / Package.swift 这类清单文件认定，认不出项目根的产物不列出来。"
                     + outOfRootNote + continuationNote)
                    .font(.caption2).foregroundStyle(MMColor.secondaryLabel)
                Spacer(minLength: 0)
            }
            if !model.truncatedRoots.isEmpty {
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "exclamationmark.triangle").font(.caption2)
                        .foregroundStyle(MMColor.caution)
                    Text(truncationNote)
                        .font(.caption2).foregroundStyle(MMColor.caution)
                    Spacer(minLength: 0)
                }
            }
            if !model.exhaustedRoots.isEmpty {
                // 试满两次就不再给按钮：点名条从"给一个继续扫的按钮"改成
                // "说清这是这一处的上限 + 给出两条出路"（D7）。
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "hand.raised").font(.caption2)
                        .foregroundStyle(MMColor.tertiaryLabel)
                    Text("想把它扫完，两条路都比再按一次有效：把项目放到更浅一层的目录，"
                         + "或者把某一个项目目录单独设为搜索根（单项目模式允许产物直接落在根上，深度 0 也认）。"
                         + "本应用不做后台常驻扫描——那等于一直在读这些目录。")
                        .font(.caption2).foregroundStyle(MMColor.secondaryLabel)
                    Spacer(minLength: 0)
                }
            }
            if model.batchCount > 1, let duration = model.lastBatchDuration {
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "clock").font(.caption2)
                        .foregroundStyle(MMColor.tertiaryLabel)
                    Text("第 \(model.batchCount) 批用了 \(secondsText(duration)) 秒："
                         + "上一批已经量到的行直接复用，这一批的预算全花在没测完的行上。")
                        .font(.caption2).foregroundStyle(MMColor.secondaryLabel)
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

    /// chip 名单 = 扫完的根 + 仍在截断的根。被截断的根必须在这一行看得见：
    /// 否则副标题说"有 1 个根没扫完"，而扫描根那一行压根没有它，读者无从核对。
    /// 读不动与不存在的根不进这里——它们各有各的点名条，混进来会丢掉颜色区分。
    private var rootsToShow: [String] {
        guard let report = model.report else {
            return ProjectArtifactRules.default(home: model.scanHome).searchRoots
        }
        return report.scannedRoots + report.truncatedRoots
    }

    /// 扫描根 chip 三态：无色 = 之前几批就扫完了；绿底带「✓ 本轮」= 最近一批扫完；
    /// 橙底 = 仍在截断，只有橙的那些根会被下一批重跑。
    @ViewBuilder
    private func rootChip(_ root: String) -> some View {
        let isTruncated = model.truncatedRoots.contains(root)
        let isLatest = model.lastBatchRoots.contains(root)
        let tint: Color? = isTruncated ? MMColor.caution : (isLatest ? MMColor.safe : nil)
        HStack(spacing: 3) {
            Text(abbreviated(root))
                .font(.caption.monospaced())
                .lineLimit(1).truncationMode(.middle)
            if isLatest {
                Text("✓ 本轮").font(.caption2)
            }
        }
        .foregroundStyle(tint ?? MMColor.label)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(tint.map { MMColor.soft($0, 0.12) } ?? MMColor.recessedSurface,
                    in: RoundedRectangle(cornerRadius: MMRadius.badge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MMRadius.badge, style: .continuous)
            .stroke(tint?.opacity(0.5) ?? MMColor.separator))
    }

    /// 截断点名。三种情况不能混成一句话：还能续扫（按钮上的数字是这一批真正要重跑的根数）、
    /// 已试过 2 次（按钮置灰，说清"扫不完"是这一处的结论而不是"里面很干净"）、
    /// 以及其余根照常报数。
    private var truncationNote: String {
        let truncated = model.truncatedRoots
        let exhausted = model.exhaustedRoots
        let budget = String(format: "%g", model.rootBudgetSeconds)
        let done = model.report?.scannedRoots.count ?? 0
        let tail = "。截断范围内的项目没被扫过，不等于它们干净"
            + (done > 0 ? "；其余 \(done) 个根已扫完。" : "。")

        // 截断根全都试满了，就别再念"有 N 个根超时"那半句：同一批根点名两遍，
        // 读起来像出了新情况。直接以"这个根已经扫过 2 次"开头。
        if !exhausted.isEmpty, exhausted.count == truncated.count {
            return "有 \(truncated.count) 个根各扫过 \(DevArtifactModel.maxAttemptsPerRoot) 次，"
                + "每次 \(budget) 秒的预算都没扫完："
                + exhausted.prefix(2).map(abbreviated).joined(separator: "、")
                + "。这里的产物本轮不报数——\"扫不完\"是这一处的结论，不是\"里面很干净\"。"
        }
        var text = "有 \(truncated.count) 个根扫到一半就超时，本轮不报数："
            + truncated.prefix(2).map(abbreviated).joined(separator: "、")
        if !exhausted.isEmpty {
            text += "。其中 " + exhausted.prefix(2).map(abbreviated).joined(separator: "、")
                + " 已试过 \(DevArtifactModel.maxAttemptsPerRoot) 次、不再重跑"
        }
        return text + tail
    }

    /// 挂在只读声明后面的一句：续扫的语义边界。放在同一条 info note 里，
    /// 是为了让它和"哪些根没扫完"那条橙色点名离得最近——读者刚看到截断就看到出路。
    private var continuationNote: String {
        guard model.canContinueTruncatedRoots else { return "" }
        return "「继续扫描」只重跑被截断的那些根，不重新发现新的顶层目录——"
            + "新项目要按「重新扫描」才会进来。"
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

    /// 秒数展示。不足 0.1 秒不写成"0.0 秒"：那一档里"这一批量完了九个候选"和
    /// "这一批什么都没干"会是同一个数，而点名条正要靠它区分有没有在白费预算。
    private func secondsText(_ duration: TimeInterval) -> String {
        duration < 0.05 ? "不足 0.1" : String(format: "%.1f", duration)
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
                     + "近期在用、受保护、体积读不到的行不会被自动选中。"
                     + batchSelectionNote)
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

    /// 续扫之后「已选 N 处」这个数字只会变小，不会变大：新扫出来的行一律不自动选中，
    /// 而失去勾选框的行（改判受保护、被重标成嵌套）会自动退出勾选——
    /// 留着就是拿一个按不到的行报一个虚高的体积。
    private var batchSelectionNote: String {
        guard model.batchCount > 1 else { return "" }
        return "续扫不替你勾选：新一批扫出来的行全部未选中，只有失去勾选框的行会自动退出勾选。"
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
            if model.containsLatestBatch(group) {
                // 「第 2 批补全」：这一组里有行是最近一批量完的。合并后的清单不写这个，
                // 读者就看不出哪些行是新证据、哪些还是几分钟前那一批的观测。
                MMBadge("第 \(model.batchCount) 批补全", tint: MMColor.informational)
            }
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
