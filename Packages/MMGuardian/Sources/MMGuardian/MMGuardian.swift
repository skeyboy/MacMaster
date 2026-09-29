import SwiftUI
import MMCore

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
            header
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    loginItemsCard
                    activityCard
                }
                .padding()
            }
        }
        .task { await vm.loadAll() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "lock.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.indigo)
            VStack(alignment: .leading) {
                Text("隐私守护").font(.title2.bold())
                Text("管理登录项，监控系统活动")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var loginItemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "power").foregroundStyle(.orange)
                Text("登录项").font(.headline)
                Spacer()
                Text("\(vm.loginItems.count) 项")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if vm.loginItems.isEmpty {
                Text("未检测到登录项")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding()
            } else {
                ForEach(vm.loginItems) { item in
                    LoginItemRow(item: item) {
                        Task { await vm.toggle(item) }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "eye.fill").foregroundStyle(.indigo)
                Text("系统活动").font(.headline)
                Spacer()
                Button("刷新") { Task { await vm.loadActivity() } }
                    .buttonStyle(.bordered).controlSize(.small)
            }

            ForEach(vm.activities) { activity in
                HStack(spacing: 10) {
                    Image(systemName: activity.icon)
                        .foregroundStyle(activity.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title).font(.body.weight(.medium))
                        Text(activity.detail)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(activity.time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - ViewModel

@MainActor
final class GuardianViewModel: ObservableObject {
    @Published var loginItems: [LoginItem] = []
    @Published var activities: [ActivityItem] = []

    func loadAll() async {
        async let items = loadLoginItems()
        async let activity = loadActivity()
        _ = await (items, activity)
    }

    func loadLoginItems() async {
        let items = await Task.detached {
            LoginItemScanner.scan()
        }.value
        loginItems = items
    }

    func loadActivity() async {
        let items = await Task.detached {
            ActivityScanner.scan()
        }.value
        activities = items
    }

    func toggle(_ item: LoginItem) async {
        await Task.detached {
            LoginItemScanner.toggle(item)
        }.value
        await loadLoginItems()
    }
}

// MARK: - LoginItem Row

struct LoginItemRow: View {
    let item: LoginItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .foregroundStyle(.orange.opacity(0.7))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium))
                Text(item.kind.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { item.enabled }, set: { _ in onToggle() }))
                .toggleStyle(.switch).labelsHidden()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - Models

struct LoginItem: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let kind: LoginItemKind
    let enabled: Bool
    let icon: String

    static func == (lhs: LoginItem, rhs: LoginItem) -> Bool { lhs.id == rhs.id }
}

enum LoginItemKind: String {
    case user = "用户"
    case system = "系统"
    case launchAgent = "Launch Agent"
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let time: String
    let icon: String
    let color: Color
}

// MARK: - Login Item Scanner

enum LoginItemScanner {
    static func scan() -> [LoginItem] {
        var items: [LoginItem] = []
        let fm = FileManager.default
        let home = NSHomeDirectory()

        let dirs: [(String, LoginItemKind)] = [
            ("\(home)/Library/LaunchAgents", .launchAgent),
            ("/Library/LaunchAgents", .system),
            ("/Library/LaunchDaemons", .system),
        ]

        for (dir, kind) in dirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let path = "\(dir)/\(file)"
                guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else { continue }
                let label = dict["Label"] as? String ?? file
                let disabled = dict["Disabled"] as? Bool ?? false
                items.append(LoginItem(
                    id: path,
                    name: label,
                    path: path,
                    kind: kind,
                    enabled: !disabled,
                    icon: iconForKind(kind)
                ))
            }
        }

        // Also check SMLoginItemSetEnabled via LSSharedFileList for user-level items
        if let userItems = scanUserLoginItems() {
            items.append(contentsOf: userItems)
        }

        return items.sorted { $0.name < $1.name }
    }

    private static func scanUserLoginItems() -> [LoginItem]? {
        var items: [LoginItem] = []

        // Check ~/Library/Preferences/loginitems.plist (legacy)
        let home = NSHomeDirectory()
        let prefsPath = "\(home)/Library/Preferences/loginitems.plist"
        if let dict = NSDictionary(contentsOfFile: prefsPath) as? [String: Any],
           let userItems = dict["AutoLaunchedApplicationDictionary"] as? [[String: Any]] {
            for item in userItems {
                let name = item["Name"] as? String ?? "Unknown"
                let path = item["Path"] as? String ?? ""
                let enabled = item["Enabled"] as? Bool ?? true
                items.append(LoginItem(
                    id: "login-\(name)",
                    name: name,
                    path: path,
                    kind: .user,
                    enabled: enabled,
                    icon: "app"
                ))
            }
        }

        return items.isEmpty ? nil : items
    }

    static func toggle(_ item: LoginItem) {
        guard var dict = NSDictionary(contentsOfFile: item.path) as? [String: Any] else { return }
        dict["Disabled"] = item.enabled
        (dict as NSDictionary).write(toFile: item.path, atomically: true)

        let cmd = item.enabled ? "unload" : "load"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = [cmd, "-w", item.path]
        try? proc.run()
    }

    private static func iconForKind(_ kind: LoginItemKind) -> String {
        switch kind {
        case .user: return "person"
        case .system: return "gearshape.2"
        case .launchAgent: return "gear"
        }
    }
}

// MARK: - Activity Scanner

enum ActivityScanner {
    static func scan() -> [ActivityItem] {
        var items: [ActivityItem] = []

        // Check recent login items from system log
        if let logItems = scanUnifiedLog() {
            items.append(contentsOf: logItems)
        }

        // Check recently modified LaunchAgents as activity
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let agentsDir = "\(home)/Library/LaunchAgents"
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
                        color: .orange
                    ))
                }
            }
        }

        // Check recent security events
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
        try? proc.run()
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
                color: .secondary
            )
        }
    }

    private static func scanRecentEvents() -> [ActivityItem] {
        var events: [ActivityItem] = []

        // Check for recently accessed sensitive files
        let sensitivePaths = [
            ("\(NSHomeDirectory())/.ssh", "SSH 密钥目录", "key.fill", Color.red),
            ("\(NSHomeDirectory())/.gnupg", "GPG 密钥目录", "lock.fill", Color.red),
            ("\(NSHomeDirectory())/Library/Keychains", "钥匙串", "key.fill", Color.orange),
        ]

        let fm = FileManager.default
        for (path, name, icon, color) in sensitivePaths {
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                events.append(ActivityItem(
                    title: name,
                    detail: "最近访问: \(relativeTime(modDate))",
                    time: relativeTime(modDate),
                    icon: icon,
                    color: color
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
