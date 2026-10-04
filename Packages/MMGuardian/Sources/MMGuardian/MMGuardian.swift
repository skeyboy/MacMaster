import SwiftUI
import AppKit
import MMCore
import MMUI

public struct GuardianModule: ModuleRegistrable {
    public var moduleID: String { "guardian" }
    public var moduleName: String { "隐私守护" }
    public var moduleIcon: String { "lock.shield" }
    public var modulePriority: Int { 5 }
    public init() {}
    public func createView() -> AnyView { AnyView(GuardianView()) }
}

public struct GuardianView: View {
    @StateObject private var vm = GuardianViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 副标题不写"实时"：这一屏是点"刷新"时测一次，不是常驻监听。
            // 卡头另有"测量于 …"标采样时刻，两处口径必须一致。
            MMPageHeader("隐私守护", subtitle: "摄像头与麦克风的当前占用（手动测量，非实时监听）· TCC 授权只读视图 · 登录项管理") {
                Button("刷新") { Task { await vm.loadAll() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MMGap.lg) {
                    if !vm.scanErrors.isEmpty {
                        readErrorBanner
                    }
                    // 取景钩子只决定"渲染哪几张卡"，四张卡各自的内容与读法一律不动。
                    // 用途与代价见 `GuardianCardFilter`（第 4 张卡在 760pt 窗口里必然在折叠线下）。
                    if shows(.occupancy) { occupancyCard }
                    if shows(.tcc) { tccCard }
                    if shows(.login) { loginItemsCard }
                    if shows(.activity) { activityCard }
                }
                .padding(MMGap.lg)
            }
            // 写失败必须可见：逐条列出路径 + 错误原文 + POSIX 码，绝不报"成功"。
            if !vm.writeFailures.isEmpty {
                MMFailurePanel(
                    summary: "以下操作没有生效（MacMaster 未改动系统域，或写入被拒绝）",
                    vm.writeFailures,
                    onDismiss: { vm.writeFailures.removeAll() }
                )
            }
        }
        .task { await vm.loadAll() }
    }

    private func shows(_ card: GuardianCard) -> Bool {
        guard let keep = GuardianViewModel.cardFilter else { return true }
        return keep.contains(card)
    }

    private var readErrorBanner: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            ForEach(vm.scanErrors, id: \.self) { message in
                HStack(spacing: MMGap.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(MMColor.caution)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                        .lineLimit(2)
                }
            }
        }
        .padding(MMGap.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.caution, 0.10), in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
    }

    // MARK: - 当前占用（P3.1）

    private var occupancyCard: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            sectionHeader(systemImage: "camera.fill",
                          // 卡头图标不常驻红色：本屏的红只属于"正在被使用"，
                          // 恒红的摄像头会被读成"正在录"，而它只是个标题装饰。
                          iconTint: MMColor.secondaryLabel,
                          title: "当前占用",
                          caption: "只读检测 · 不申请任何权限") {
                // 只报"上次测量时刻"，不报"实时"——读数会过期，诚实标注采样时间。
                Text(vm.measuredAt.map { "测量于 " + MMFormat.dateTime($0) } ?? "测量中")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .monospacedDigit()
            }

            MMCard(padding: 0) {
                VStack(spacing: 0) {
                    if vm.deviceUsage.isEmpty {
                        VStack(spacing: MMGap.sm) {
                            MMSkeletonRow(nameWidth: 80, valueWidth: 72)
                            MMSkeletonRow(nameWidth: 80, valueWidth: 72)
                        }
                        .padding(MMGap.md)
                    } else {
                        ForEach(Array(DeviceUsageKind.allCases.enumerated()), id: \.offset) { index, kind in
                            if index > 0 { Divider() }
                            DeviceUsageRow(kind: kind, state: vm.deviceUsage[kind] ?? .indeterminate(.readFailed))
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: MMGap.xs) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                Text("口径：空闲 = 设备在、且此刻测到没人驱动它；无法确定 ≠ 没有应用在用。占用时系统公开接口不返回进程名，本面板不猜使用方。")
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 稿 06 的三个区块都是同一个骨架：**标题行在卡外**（图标 + 标题 + 口径小字 + 右侧动作），
    /// **卡是通栏的、`padding:0`**，卡内只有带底分隔线的行。
    /// 之前实现把标题和脚注一起塞进带内边距的卡里、每行刷成沉底药丸，于是"这一组到哪里结束"
    /// 只能靠猜——而概览页与清理页的表格行早就是 `Divider()` 那一种语言。
    @ViewBuilder
    private func sectionHeader<Trailing: View>(systemImage: String,
                                               iconTint: Color,
                                               title: String,
                                               caption: String? = nil,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: MMGap.sm) {
            Image(systemName: systemImage)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(iconTint)
            Text(title).font(.headline)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }
            Spacer(minLength: MMGap.sm)
            trailing()
        }
    }

    // MARK: - 敏感权限授权（P3.2，TCC 只读视图）

    private var tccCard: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            sectionHeader(systemImage: "lock.shield",
                          iconTint: MMColor.secondaryLabel,
                          title: "敏感权限授权",
                          caption: "SQLite 只读查询 · 不写库不提权") {
                EmptyView()
            }

            MMCard(padding: 0) {
                VStack(spacing: 0) {
                    switch vm.tccState {
                    case nil:
                        VStack(spacing: MMGap.sm) {
                            MMSkeletonRow(nameWidth: 120, valueWidth: 72)
                            MMSkeletonRow(nameWidth: 120, valueWidth: 72)
                        }
                        .padding(MMGap.md)
                    case .unreadable(let detail):
                        // 读不到 ≠ 没有授权：这一档不画列表，只给原因 + 引导。
                        MMEmptyState(
                            systemImage: "lock.fill",
                            title: TCCCopyTable.unreadableTitle,
                            detail: detail + "\n\n" + TCCCopyTable.unreadableGuide
                        ) {
                            Button("打开系统设置 · 完全磁盘访问") {
                                MMReveal.openSystemSettings(pane: "com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
                            }
                            .controlSize(.small)
                        }
                        .frame(minHeight: 140)
                        .padding(MMGap.md)
                    case .emptyRead:
                        MMEmptyState(
                            systemImage: "checkmark.shield",
                            title: "相关服务没有授权记录",
                            detail: "两个 TCC 库都读取成功，查询返回 0 行——这次是「查到了没有」，不是「没查到」。"
                        )
                        .frame(minHeight: 120)
                        .padding(MMGap.md)
                    case .partial(let rows, let note):
                        // 警示条是卡内的一行，不是浮在卡上的胶囊：稿 `.strip` 通栏带底分隔线，
                        // 这样"清单不完整"和它下面那几行是同一件事，而不是两个控件。
                        partialStrip(note)
                        tccRowsList(rows)
                    case .loaded(let rows):
                        tccRowsList(rows)
                    }

                    // auth_value 的读法脚注留在卡内最后一格（稿 `.foot-note`，无边框）：
                    // 它解释的是上面那几行的徽章，隔着一层卡就没人读。
                    HStack(alignment: .top, spacing: MMGap.xs) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                        Text(TCCCopyTable.valueLegend)
                            .font(.caption)
                            .foregroundStyle(MMColor.tertiaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, MMGap.lg)
                    .padding(.vertical, MMGap.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// 部分可读警示条：点名没读到的库。列表只覆盖读到的那部分，必须说破，
    /// 否则用户会把"用户级没有"读成"整机没有"。
    private func partialStrip(_ note: String) -> some View {
        HStack(alignment: .top, spacing: MMGap.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(MMColor.caution)
            Text(note)
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.caution, 0.10))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tccRowsList(_ rows: [TCCDisplayRow]) -> some View {
        // partial 档允许 0 行（那由 partialStrip 解释"清单不完整"），loaded 档不会为空。
        // 行之间加分隔线、最后一行不加（稿 `.trow:last-child{border-bottom:0}`）：
        // 卡下面紧跟的 auth_value 脚注自带边界，再多一条线就把它和列表切成两截。
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            if index > 0 { Divider() }
            TCCAuthorizationRow(row: row)
        }
    }

    // MARK: - 登录项

    private var loginItemsCard: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            sectionHeader(systemImage: "power",
                          iconTint: MMColor.caution,
                          title: "登录项",
                          caption: "\(vm.loginItems.count) 项") {
                // 系统域没有可编程开关：给用户的动作是"被带去正确的设置面板"。
                Button("打开系统设置 · 登录项") {
                    MMReveal.openSystemSettings(pane: "com.apple.LoginItems-Settings.extension")
                }
                .controlSize(.small)
            }

            MMCard(padding: 0) {
                VStack(spacing: 0) {
                    if vm.loginItems.isEmpty {
                        MMEmptyState(
                            systemImage: "tray",
                            title: "未检测到登录项",
                            detail: "用户目录与系统目录的 LaunchAgents 均为空。"
                        )
                        .frame(minHeight: 120)
                        .padding(MMGap.md)
                    } else {
                        ForEach(Array(vm.loginItems.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            LoginItemRow(item: item, anomaly: vm.loginAudit.anomalies[item.path]) {
                                Task { await vm.toggle(item) }
                            }
                        }
                        // 脚注在卡内、列表下面，带一条顶分隔线（稿 `.foot-note{border-top}`）：
                        // 它是对上面这一整列的核对结论，不该被卡边界挪到"另一块"里去。
                        auditFooter
                    }
                }
            }
        }
    }

    /// 核对结果的脚注。不可核对时必须显式说"这一轮没对表"——
    /// 没有徽章的列表读起来像"全部正常"，那是最省事也最假的一种呈现。
    @ViewBuilder
    private var auditFooter: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            if !vm.loginAudit.determinate {
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(MMColor.caution)
                    Text(vm.loginAudit.reason.map(LoginItemAnomalyCopy.indeterminateNote)
                         ?? LoginItemAnomalyCopy.indeterminateNote("尚未执行"))
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if !vm.loginAudit.orphanLabels.isEmpty {
                    HStack(alignment: .top, spacing: MMGap.xs) {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(MMColor.caution)
                        Text("launchd 里还挂着 \(vm.loginAudit.orphanLabels.count) 个非苹果标签，五个已知 LaunchAgents/Daemons 目录都找不到它们的 plist："
                             + vm.loginAudit.orphanLabels.prefix(6).joined(separator: "、")
                             + (vm.loginAudit.orphanLabels.count > 6 ? " 等" : "")
                             + "。" + LoginItemAnomalyCopy.orphanNote)
                            .font(.caption)
                            .foregroundStyle(MMColor.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                    Text(LoginItemAnomalyCopy.footnote)
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - 系统活动

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            sectionHeader(systemImage: "eye",
                          iconTint: MMColor.informational,
                          title: "系统活动") {
                EmptyView()
            }
            MMCard(padding: 0) {
                VStack(spacing: 0) {
                    if vm.activities.isEmpty {
                        Text("近 5 分钟没有可读到的活动事件。")
                            .font(.caption)
                            .foregroundStyle(MMColor.secondaryLabel)
                            .padding(MMGap.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(vm.activities.enumerated()), id: \.element.id) { index, activity in
                            if index > 0 { Divider() }
                            HStack(spacing: MMGap.md) {
                                Image(systemName: activity.icon)
                                    .foregroundStyle(tint(for: activity.tone))
                                    .frame(width: MMMetric.iconRow)
                                VStack(alignment: .leading, spacing: MMGap.xxs) {
                                    Text(activity.title).font(.body.weight(.medium))
                                    Text(activity.detail)
                                        .font(.caption)
                                        .foregroundStyle(MMColor.secondaryLabel)
                                }
                                Spacer(minLength: MMGap.sm)
                                Text(activity.time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(MMColor.secondaryLabel)
                            }
                            // 原来是 `.frame(height: rowCompact)`：28pt 装两行文字，
                            // 标题的下沿被齐根切掉。行高只给下限，多出来的高度给内容。
                            .frame(minHeight: MMMetric.rowCompact)
                            .padding(.horizontal, MMGap.lg)
                            .padding(.vertical, MMGap.sm)
                        }
                    }
                }
            }
        }
    }

    private func tint(for tone: ActivityTone) -> Color {
        switch tone {
        case .info: MMColor.informational
        case .caution: MMColor.caution
        case .destructive: MMColor.destructive
        case .neutral: MMColor.secondaryLabel
        }
    }
}

// MARK: - ViewModel

@MainActor
final class GuardianViewModel: ObservableObject {
    @Published var loginItems: [LoginItem] = []
    /// 磁盘清单 × launchd 快照的交叉核对结果；`.indeterminate` = 还没跑过。
    @Published var loginAudit: LoginItemAudit = .indeterminate
    @Published var activities: [ActivityItem] = []
    /// 摄像头/麦克风占用档位；空字典 = 还在测。
    @Published var deviceUsage: [DeviceUsageKind: DeviceUsageState] = [:]
    /// TCC 授权视图状态；nil = 还在测。
    @Published var tccState: TCCViewerState?
    /// 上次完成测量的时刻（"测量于 …"），读数会过期，不写"实时"。
    @Published var measuredAt: Date?
    /// 目录/解析读取失败原文（读侧不静默）。
    @Published var scanErrors: [String] = []
    /// 写操作失败逐条收集，UI 用 MMFailurePanel 展示。
    @Published var writeFailures: [TrashFailure] = []

    /// 仅供无头截图逐档核对渲染（照 MM_ORPHAN_FIXTURE_HOME 的写法）。
    /// 只接受 `camera|mic=inuse|idle|unknown|absent|combo|conflict`；含非法项时整体忽略并写 stderr——
    /// 半生效的夹具会让截图者把"半真半假"当成"全按夹具渲染"，是最坏的假通过。
    static let fixtureOverrides: [DeviceUsageKind: DeviceUsageState] = {
        guard let raw = ProcessInfo.processInfo.environment["MM_GUARDIAN_FIXTURE"],
              raw.isEmpty == false else { return [:] }
        let result = DeviceUsageFixture.parse(raw)
        if !result.rejected.isEmpty {
            FileHandle.standardError.write(
                "MM_GUARDIAN_FIXTURE 含非法取值（\(result.rejected.joined(separator: ", "))），整个钩子已忽略\n".data(using: .utf8)!)
            return [:]
        }
        return result.overrides
    }()

    /// 仅供无头截图逐档核对渲染（同上写法）：只接受 `rows|unreadable|empty|partial` 单值；
    /// 含非法值时整个钩子作废并写 stderr。`rows`/`partial` 档注入的全是 com.example.* 合成行。
    static let tccFixtureState: TCCViewerState? = {
        guard let raw = ProcessInfo.processInfo.environment["MM_TCC_FIXTURE"],
              raw.isEmpty == false else { return nil }
        let result = TCCFixture.parse(raw)
        if !result.rejected.isEmpty {
            FileHandle.standardError.write(
                "MM_TCC_FIXTURE 含非法取值（\(result.rejected.joined(separator: ", "))），只接受 rows|unreadable|empty|partial，整个钩子已忽略\n".data(using: .utf8)!)
            return nil
        }
        return result.state
    }()

    /// 仅供无头截图逐档核对渲染：登录项卡只接受 `rows|empty|indeterminate|scanerror` 单值。
    /// 合成条目全 com.example.*、判定走真实 LoginItemAuditor.audit，钩子不写盘、不落夹具文件。
    static let loginFixtureStage: LoginFixtureStage? = {
        let result = LoginItemFixture.parse(ProcessInfo.processInfo.environment["MM_GUARDIAN_LOGIN_FIXTURE"])
        if let rejected = result.rejected {
            FileHandle.standardError.write(
                "MM_GUARDIAN_LOGIN_FIXTURE 含非法取值（\(rejected)），只接受 rows|empty|indeterminate|scanerror，整个钩子已忽略\n".data(using: .utf8)!)
            return nil
        }
        return result.stage
    }()

    /// MM_GUARDIAN_LOAD=hold：loadAll 直接返回，页面定格在首帧（测量中 + 骨架）。
    /// 纯展示闸门，非法取值只写 stderr 并按未设置处理，不影响生产路径。
    static let holdInitialFrame: Bool = {
        let result = GuardianLoadHook.parse(ProcessInfo.processInfo.environment["MM_GUARDIAN_LOAD"])
        if let rejected = result.rejected {
            FileHandle.standardError.write(
                "MM_GUARDIAN_LOAD 含非法取值（\(rejected)），只接受 hold，钩子已忽略\n".data(using: .utf8)!)
        }
        return result.holdInitialFrame
    }()

    /// 系统活动卡夹具（fidelity-guardian G1）：只接受 `empty|rows` 单值，非法整体作废。
    /// 只顶替展示数据：真扫描照样跑一次（结果丢弃），钩子不写盘、不 spawn、不读 /tmp。
    static let activityFixtureStage: GuardianActivityFixture.Stage? = {
        let result = GuardianActivityFixture.parse(ProcessInfo.processInfo.environment["MM_GUARDIAN_ACTIVITY_FIXTURE"])
        if let rejected = result.rejected {
            FileHandle.standardError.write(
                "MM_GUARDIAN_ACTIVITY_FIXTURE 含非法取值（\(rejected)），只接受 empty|rows，整个钩子已忽略\n".data(using: .utf8)!)
            return nil
        }
        return result.stage
    }()

    /// 卡片取景（`MM_GUARDIAN_CARDS`）：`occupancy|tcc|login|activity` 的逗号子集，
    /// 只影响渲染哪几张卡；未设置时四张全在，含非法项整体作废并写 stderr。
    static let cardFilter: [GuardianCard]? = {
        let result = GuardianCardFilter.parse(ProcessInfo.processInfo.environment["MM_GUARDIAN_CARDS"])
        if let rejected = result.rejected {
            FileHandle.standardError.write(
                "MM_GUARDIAN_CARDS 含非法取值（\(rejected)），只接受 occupancy|tcc|login|activity 的逗号子集，整个钩子已忽略\n".data(using: .utf8)!)
            return nil
        }
        return result.keep
    }()

    func loadAll() async {
        // 首帧定格钩子：MM_GUARDIAN_LOAD=hold 时整轮加载直接返回，
        // 页面停在「测量中 + 骨架」的首帧，让平时抢拍不到的加载态可被截图核对。
        if Self.holdInitialFrame { return }
        // 占用检测最先：它是进程内读数（微秒级），不该排在 `log show` 这类
        // 秒级子进程扫描之后——"此刻有没有人用摄像头"晚一秒回答都算失真。
        await loadDeviceUsage()
        await loadTCC()
        await loadLoginItems()
        await loadActivity()
    }

    func loadDeviceUsage() async {
        let overrides = Self.fixtureOverrides
        var states = await Task.detached(priority: .userInitiated) {
            DeviceUsageProbe.snapshot()
        }.value
        for (kind, state) in overrides { states[kind] = state }
        deviceUsage = states
        measuredAt = Date()
    }

    func loadTCC() async {
        if let fixture = Self.tccFixtureState {
            // 夹具只顶替展示状态：真库照样读一次（失败也无妨），保证探针调用路径
            // 不被截图流程悄悄绕过。
            _ = await Task.detached(priority: .utility) { TCCProbe.snapshot() }.value
            tccState = fixture
            return
        }
        let report = await Task.detached(priority: .userInitiated) {
            TCCProbe.snapshot()
        }.value
        tccState = TCCViewer.build(outcomes: report.outcomes, rows: report.rows)
    }

    func loadLoginItems() async {
        if let stage = Self.loginFixtureStage {
            // 夹具只顶替展示数据：真扫描照样跑一次（结果丢弃），保证截图流程
            // 不会悄悄绕过真实读取路径；钩子本身不写任何东西。
            _ = await Task.detached { LoginItemScanner.scan() }.value
            switch stage {
            case .empty:
                loginItems = []
                loginAudit = .indeterminate
                scanErrors = []
            case .rows, .scanerror:
                loginItems = LoginItemFixture.items()
                loginAudit = LoginItemFixture.audit()
                scanErrors = stage == .scanerror ? LoginItemFixture.scanErrorLines : []
            case .indeterminate:
                loginItems = LoginItemFixture.items()
                loginAudit = LoginItemFixture.indeterminateAudit
                scanErrors = []
            }
            return
        }
        let report = await Task.detached {
            // 磁盘清单和 launchd 快照一起取：分两次 await 会让界面短暂出现
            // "有清单、没核对"的中间态，那一屏看起来就像"核对过、一切正常"。
            let scan = LoginItemScanner.scan()
            let snapshot = LaunchctlRunner.listSnapshot()
            return (scan, LoginItemAuditor.audit(items: scan.items, snapshot: snapshot) { path in
                FileManager.default.fileExists(atPath: path)
            })
        }.value
        loginItems = report.0.items
        scanErrors = report.0.readErrors
        loginAudit = report.1
    }

    func loadActivity() async {
        if let stage = Self.activityFixtureStage {
            // 夹具只顶替展示数据：真扫描照样跑一次（结果丢弃），保证截图流程
            // 不会悄悄绕过真实读取路径；钩子本身不 spawn 额外进程、不写盘。
            _ = await Task.detached { ActivityScanner.scan() }.value
            activities = stage == .empty ? [] : GuardianActivityFixture.items()
            return
        }
        let items = await Task.detached {
            ActivityScanner.scan()
        }.value
        activities = items
    }

    /// 切换开关。系统域条目根本不给按钮；真到了这里（用户域）失败会把
    /// 错误原文 append 进 writeFailures 供 MMFailurePanel 展示。
    func toggle(_ item: LoginItem) async {
        let failure = await Task.detached {
            LoginItemStore.toggle(item)
        }.value
        if let failure {
            writeFailures.append(failure)
        }
        await loadLoginItems()
    }
}

// MARK: - 登录项行

struct LoginItemRow: View {
    let item: LoginItem
    let anomaly: LoginItemAnomaly?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: MMGap.md) {
            Image(systemName: item.icon)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(width: MMMetric.iconRow)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(item.name).font(.body).lineLimit(1)
                Text((item.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.fileKind == .renamedDisabled || anomaly != nil {
                    HStack(spacing: MMGap.xs) {
                        if item.fileKind == .renamedDisabled {
                            // 停用有两种做法：写 Disabled 键，和把文件改名。后者 launchd
                            // 根本不读，混在一起说"已关闭"会让人以为改个键就能恢复。
                            MMBadge("改名停用", tint: MMColor.secondaryLabel, systemImage: "doc.badge.ellipsis")
                        }
                        if let anomaly {
                            let copy = LoginItemAnomalyCopy.badge(anomaly)
                            MMBadge(copy.text, tint: anomalyTint, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            Spacer(minLength: MMGap.sm)
            if item.isWritable {
                Toggle("", isOn: Binding(get: { item.enabled }, set: { _ in onToggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            } else {
                // 系统域：只读徽章 + 就地引导，不做任何写尝试。
                MMBadge("只读", tint: MMColor.secondaryLabel, systemImage: "lock")
                Button("在系统设置中管理") {
                    MMReveal.openSystemSettings(pane: "com.apple.LoginItems-Settings.extension")
                }
                .controlSize(.small)
            }
        }
        // 行高只给下限：异常徽章会多出第三行，钉死 44/56 就把多出来的那行切掉。
        .frame(minHeight: MMMetric.rowRegular)
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
    }

    /// 这三条都是"两处记录对不上"，不是"确认坏了"：用 caution，绝不借红色。
    private var anomalyTint: Color { MMColor.caution }
}

// MARK: - 占用行（当前占用卡）

struct DeviceUsageRow: View {
    let kind: DeviceUsageKind
    let state: DeviceUsageState

    var body: some View {
        let copy = DeviceUsageCopyTable.copy(for: kind, state: state)
        HStack(alignment: .center, spacing: MMGap.md) {
            ZStack {
                // 稿 06 `.urow .ring`：2px 描边圆环，**只有 live 那一档上色**（红环 + 红底），
                // 其余态一律中性描边。之前环跟着语义 tint 走，空闲态就成了一枚绿环——
                // 而稿里绿色只属于右侧那枚 `badge safe`，环和图标不参与表态。
                // 这一屏的红是专属信号（"此刻确有进程在驱动"），多一处上色就稀释一次。
                Circle()
                    .fill(state == .inUse ? MMColor.soft(MMColor.destructive) : Color.clear)
                Circle()
                    .stroke(state == .inUse ? MMColor.destructive : MMColor.separator, lineWidth: 2)
                Image(systemName: kind.systemImage)
                    .font(.system(size: MMMetric.iconSmall))
                    .foregroundStyle(state == .inUse ? MMColor.destructive : MMColor.secondaryLabel)
            }
            .frame(width: MMMetric.iconRing, height: MMMetric.iconRing)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(kind.displayName).font(.body.weight(.medium))
                Text(copy.detail)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: MMGap.sm)
            VStack(alignment: .trailing, spacing: MMGap.xs) {
                MMBadge(copy.badge, tint: tint, systemImage: state == .inUse ? "exclamationmark.triangle.fill" : nil)
                if let note = copy.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(minHeight: MMMetric.rowRegular)
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
    }

    /// 颜色只走语义三档：红=正在被使用，绿=测到了空闲，灰=无法确定/没有设备。
    /// "无法确定"绝不借绿色——灰色才对应"我们不知道"。
    private var tint: Color {
        switch state {
        case .inUse: MMColor.destructive
        case .idle: MMColor.safe
        case .indeterminate, .deviceAbsent: MMColor.secondaryLabel
        }
    }
}

// MARK: - 授权行（敏感权限授权卡）

struct TCCAuthorizationRow: View {
    let row: TCCDisplayRow

    var body: some View {
        let copy = TCCCopyTable.copy(for: row.status)
        HStack(alignment: .center, spacing: MMGap.md) {
            Image(systemName: row.serviceImage)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(width: MMMetric.iconRow)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(row.appName).font(.body.weight(.medium)).lineLimit(1)
                // 原始 client（bundle id / 路径）永远在副行：解析出的名字要有出处可查。
                Text(row.client)
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: MMGap.sm)
            VStack(alignment: .trailing, spacing: MMGap.xs) {
                MMBadge(copy.badge, tint: copy.grantsAccess ? MMColor.informational : MMColor.secondaryLabel)
                Text(row.serviceName)
                    .font(.caption2)
                    .foregroundStyle(MMColor.tertiaryLabel)
            }
            VStack(alignment: .trailing, spacing: MMGap.xs) {
                Text(row.source.displayName)
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                Text(row.lastModified.map(MMFormat.dateTime) ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MMColor.tertiaryLabel)
            }
            .frame(width: 84, alignment: .trailing)
        }
        .frame(minHeight: MMMetric.rowRegular)
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
    }
}

// MARK: - 活动模型

public enum ActivityTone: Sendable {
    case info, caution, destructive, neutral
}

struct ActivityItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
    let time: String
    let icon: String
    let tone: ActivityTone
}

// MARK: - Activity Scanner

enum ActivityScanner {
    static func scan() -> [ActivityItem] {
        var items: [ActivityItem] = []

        if let logItems = scanUnifiedLog() {
            items.append(contentsOf: logItems)
        }

        // 最近改动的用户 LaunchAgents 视作活动信号。
        let fm = FileManager.default
        let agentsDir = "\(NSHomeDirectory())/Library/LaunchAgents"
        if let files = try? fm.contentsOfDirectory(atPath: agentsDir) {
            for file in files.prefix(3) where file.hasSuffix(".plist") {
                let path = "\(agentsDir)/\(file)"
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let modDate = attrs[.modificationDate] as? Date {
                    items.append(ActivityItem(
                        title: file.replacingOccurrences(of: ".plist", with: ""),
                        detail: "LaunchAgent 最近修改",
                        time: relativeTime(modDate),
                        icon: "gear",
                        tone: .caution
                    ))
                }
            }
        }

        items.append(contentsOf: scanRecentEvents())
        return items
    }

    private static func scanUnifiedLog() -> [ActivityItem]? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        proc.arguments = ["show", "--last", "5m", "--predicate",
                          "eventMessage contains \"login\" OR eventMessage contains \"auth\""]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            // 只读探测失败降级为空列表（活动流本来就允许没有事件），
            // 但不再让 try? 把"启动不了 log"和"没有事件"混成一样。
            return nil
        }

        // 子进程超时保护：沙盒环境下 /usr/bin/log 可能挂起（sandbox_extension_issue），
        // waitUntilExit() 会永远阻塞。8 秒足够正常 log show 完成（实测 ~1s），
        // 超时后杀掉子进程、丢弃输出，降级为空列表。
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            proc.waitUntilExit()
            finished.signal()
        }
        if finished.wait(timeout: .now() + 8) == .timedOut {
            proc.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return nil
        }

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }.prefix(5)
        return lines.map { line in
            ActivityItem(
                title: "系统日志事件",
                detail: String(line.prefix(80)),
                time: "最近",
                icon: "doc.text",
                tone: .info
            )
        }
    }

    private static func scanRecentEvents() -> [ActivityItem] {
        var events: [ActivityItem] = []

        let sensitivePaths: [(String, String, String, ActivityTone)] = [
            ("\(NSHomeDirectory())/.ssh", "SSH 密钥目录", "key.fill", .destructive),
            ("\(NSHomeDirectory())/.gnupg", "GPG 密钥目录", "lock.fill", .destructive),
            ("\(NSHomeDirectory())/Library/Keychains", "钥匙串", "key.fill", .caution),
        ]

        let fm = FileManager.default
        for (path, name, icon, tone) in sensitivePaths {
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                events.append(ActivityItem(
                    title: name,
                    detail: "最近访问: \(relativeTime(modDate))",
                    time: relativeTime(modDate),
                    icon: icon,
                    tone: tone
                ))
            }
        }

        return events
    }

    private static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}
