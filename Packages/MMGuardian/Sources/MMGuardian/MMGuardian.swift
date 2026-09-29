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
            MMPageHeader("隐私守护", subtitle: "摄像头与麦克风的当前占用（手动测量，非实时监听）· 登录项管理") {
                Button("刷新") { Task { await vm.loadAll() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MMGap.lg) {
                    if !vm.scanErrors.isEmpty {
                        readErrorBanner
                    }
                    occupancyCard
                    loginItemsCard
                    activityCard
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
        VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "camera.fill")
                    .font(.system(size: MMMetric.iconSmall))
                    // 卡头这个图标不能常驻红色：本屏的红色专属于"正在被使用"，
                    // 一个恒红的摄像头图标会被读成"正在录"，而它只是个标题装饰。
                    .foregroundStyle(MMColor.secondaryLabel)
                Text("当前占用").font(.headline)
                Spacer()
                // 副标题只报"上次测量时刻"，不报"实时"——读数会过期，诚实标注采样时间。
                Text(vm.measuredAt.map { "测量于 " + MMFormat.dateTime($0) } ?? "测量中")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                    .monospacedDigit()
            }

            if vm.deviceUsage.isEmpty {
                MMSkeletonRow(nameWidth: 80, valueWidth: 72)
                MMSkeletonRow(nameWidth: 80, valueWidth: 72)
            } else {
                ForEach(DeviceUsageKind.allCases, id: \.self) { kind in
                    DeviceUsageRow(kind: kind, state: vm.deviceUsage[kind] ?? .indeterminate(.readFailed))
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
        .padding(MMGap.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator)
        )
    }

    // MARK: - 登录项

    private var loginItemsCard: some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "power")
                    .font(.system(size: MMMetric.iconSmall))
                    .foregroundStyle(MMColor.caution)
                Text("登录项").font(.headline)
                Spacer()
                Text("\(vm.loginItems.count) 项")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                // 系统域没有可编程开关：给用户的动作是"被带去正确的设置面板"。
                Button("打开系统设置 · 登录项") {
                    MMReveal.openSystemSettings(pane: "com.apple.LoginItems-Settings.extension")
                }
                .controlSize(.small)
            }

            if vm.loginItems.isEmpty {
                MMEmptyState(
                    systemImage: "tray",
                    title: "未检测到登录项",
                    detail: "用户目录与系统目录的 LaunchAgents 均为空。"
                )
                .frame(minHeight: 120)
            } else {
                ForEach(vm.loginItems) { item in
                    LoginItemRow(item: item) {
                        Task { await vm.toggle(item) }
                    }
                }
            }
        }
        .padding(MMGap.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator)
        )
    }

    // MARK: - 系统活动

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "eye")
                    .font(.system(size: MMMetric.iconSmall))
                    .foregroundStyle(MMColor.informational)
                Text("系统活动").font(.headline)
                Spacer()
            }
            if vm.activities.isEmpty {
                Text("近 5 分钟没有可读到的活动事件。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            } else {
                ForEach(vm.activities) { activity in
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
                    .frame(height: MMMetric.rowCompact)
                    .padding(.horizontal, MMGap.md)
                    .background(MMColor.contentBackground, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                }
            }
        }
        .padding(MMGap.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator)
        )
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
    @Published var activities: [ActivityItem] = []
    /// 摄像头/麦克风占用档位；空字典 = 还在测。
    @Published var deviceUsage: [DeviceUsageKind: DeviceUsageState] = [:]
    /// 上次完成测量的时刻（"测量于 …"），读数会过期，不写"实时"。
    @Published var measuredAt: Date?
    /// 目录/解析读取失败原文（读侧不静默）。
    @Published var scanErrors: [String] = []
    /// 写操作失败逐条收集，UI 用 MMFailurePanel 展示。
    @Published var writeFailures: [TrashFailure] = []

    /// 仅供无头截图逐档核对渲染（照 MM_ORPHAN_FIXTURE_HOME 的写法）。
    /// 只接受 `camera|mic=inuse|idle|unknown|absent`；含非法项时整体忽略并写 stderr——
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

    func loadAll() async {
        // 占用检测最先：它是进程内读数（微秒级），不该排在 `log show` 这类
        // 秒级子进程扫描之后——"此刻有没有人用摄像头"晚一秒回答都算失真。
        await loadDeviceUsage()
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

    func loadLoginItems() async {
        let report = await Task.detached {
            LoginItemScanner.scan()
        }.value
        loginItems = report.items
        scanErrors = report.readErrors
    }

    func loadActivity() async {
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
        .frame(height: MMMetric.rowRegular)
        .padding(.horizontal, MMGap.md)
        .background(MMColor.contentBackground, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
    }
}

// MARK: - 占用行（当前占用卡）

struct DeviceUsageRow: View {
    let kind: DeviceUsageKind
    let state: DeviceUsageState

    var body: some View {
        let copy = DeviceUsageCopyTable.copy(for: kind, state: state)
        HStack(alignment: .center, spacing: MMGap.md) {
            Image(systemName: kind.systemImage)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(tint)
                .frame(width: MMMetric.iconRow)
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
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.xs)
        .background(MMColor.contentBackground, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
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
        proc.waitUntilExit()

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
