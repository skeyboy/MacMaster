import Foundation

// MARK: - 系统级文件分析（Task 2）
//
// 只读分析为默认姿态：扫描用户级/系统级日志、诊断报告、iOS 设备备份、
// /Library 缓存、开发工具版本残留、大文件热点与 SIP 保护区占用。
// 每个条目都带安全等级标记，只有用户级缓存/日志/诊断报告和「有明确警告」的旧设备备份
// 可进入清理流程，且清理一律走 FileTrashService（移入废纸篓、可撤回）。
// 绝不触碰 SIP 保护路径，绝不 shell out sudo，绝不 FileManager.removeItem 用户数据。

public enum SystemItemSafety: String, Hashable, Sendable {
    /// 用户级日志/诊断报告/缓存等，可安全移入废纸篓
    case safe
    /// 可清理但必须先看到明确警告（如 iOS 设备备份）
    case cleanWithWarning
    /// 仅供查看：需要 root/管理员权限、或属于个人数据，本工具不提供删除
    case readOnly
    /// SIP 保护路径（/System、/usr、/bin、/sbin、/Library/Extensions），绝对不可动
    case sipProtected

    public var label: String {
        switch self {
        case .safe: return "可安全清理"
        case .cleanWithWarning: return "可清理·需谨慎"
        case .readOnly: return "仅供查看"
        case .sipProtected: return "SIP 保护"
        }
    }

    /// 用户是否能主动勾选此项（仅 safe / cleanWithWarning 可勾选，且都需手动选择）。
    public var isUserSelectable: Bool {
        self == .safe || self == .cleanWithWarning
    }
}

public struct SystemAnalysisItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: UInt64
    public let fileCount: Int
    public let modificationDate: Date?
    public let safety: SystemItemSafety
    public let detail: String

    public init(
        name: String,
        path: String,
        size: UInt64,
        fileCount: Int,
        modificationDate: Date?,
        safety: SystemItemSafety,
        detail: String
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.fileCount = fileCount
        self.modificationDate = modificationDate
        self.safety = safety
        self.detail = detail
    }
}

public struct SystemAnalysisGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public var items: [SystemAnalysisItem]

    public var totalSize: UInt64 { items.reduce(UInt64(0)) { $0 + $1.size } }
    public var hasCleanableItems: Bool { items.contains { $0.safety.isUserSelectable } }

    public init(
        id: String,
        name: String,
        description: String,
        iconName: String,
        items: [SystemAnalysisItem]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.items = items
    }
}

public actor SystemAnalyzer {
    public init() {}

    /// SIP 保护区前缀，任何匹配路径一律只读展示，不提供删除。
    private static let sipRoots: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library/Extensions",
    ]

    /// 用户级、可安全清理的路径前缀（日志/诊断本身在 user_logs 组内）。
    private static let userSafeRoots: [String] = [
        "/Library/Logs",
        "/Library/Caches",
        "/Library/Developer/Xcode/iOS DeviceSupport",
        "/Library/Developer/Xcode/tvOS DeviceSupport",
        "/Library/Developer/Xcode/watchOS DeviceSupport",
        "/Library/Developer/Xcode/visionOS DeviceSupport",
    ]

    public static func safety(for path: String, home: String) -> SystemItemSafety {
        for root in sipRoots where path == root || path.hasPrefix(root + "/") {
            return .sipProtected
        }
        guard path.hasPrefix(home + "/") else { return .readOnly }

        let backupRoot = home + "/Library/Application Support/MobileSync/Backup"
        if path == backupRoot || path.hasPrefix(backupRoot + "/") {
            return .cleanWithWarning
        }
        for root in userSafeRoots where path.hasPrefix(home + root + "/") {
            return .safe
        }
        // 其余用户目录内容（文稿、下载、Application Support 个人数据等）一律仅供查看
        return .readOnly
    }

    public func analyze(tracker: FileScanProgressTracker? = nil) async -> [SystemAnalysisGroup] {
        let home = NSHomeDirectory()
        var groups: [SystemAnalysisGroup] = []

        groups.append(await group(
            id: "user_logs",
            name: "用户日志与诊断报告",
            description: "~/Library/Logs：应用日志、崩溃与诊断报告，删除后系统会自动重建",
            iconName: "doc.text",
            directory: home + "/Library/Logs",
            home: home,
            forceSafety: .safe,
            detail: "用户级日志，可安全移入废纸篓",
            tracker: tracker
        ))

        groups.append(await group(
            id: "device_backups",
            name: "iOS 设备备份",
            description: "警告：删除备份后，对应设备将无法恢复到该时间点之前的状态。请确认备份已过时再勾选。",
            iconName: "iphone",
            directory: home + "/Library/Application Support/MobileSync/Backup",
            home: home,
            forceSafety: .cleanWithWarning,
            detail: "设备完整备份，删除前请三思（移入废纸篓仍可撤回）",
            tracker: tracker
        ))

        groups.append(await developerLeftoverGroup(home: home, tracker: tracker))

        groups.append(await group(
            id: "system_logs",
            name: "系统日志（/Library/Logs）",
            description: "系统级日志，属 root 管辖，仅供查看占用，本工具不尝试删除",
            iconName: "network",
            directory: "/Library/Logs",
            home: home,
            forceSafety: .readOnly,
            detail: "需要管理员权限，仅供查看",
            tracker: tracker
        ))

        groups.append(await group(
            id: "system_caches",
            name: "系统缓存（/Library/Caches）",
            description: "系统级更新/语言包/守护进程缓存，root 管辖，仅供查看",
            iconName: "externaldrive.badge.timemachine",
            directory: "/Library/Caches",
            home: home,
            forceSafety: .readOnly,
            detail: "需要管理员权限，仅供查看",
            tracker: tracker
        ))

        groups.append(await group(
            id: "update_leftovers",
            name: "软件更新残留（/Library/Updates）",
            description: "macOS 软件更新下载缓存与语言资源，由更新守护进程管理，仅供查看",
            iconName: "arrow.triangle.2.circlepath",
            directory: "/Library/Updates",
            home: home,
            forceSafety: .readOnly,
            detail: "更新助理管理，需 root，仅供查看",
            tracker: tracker
        ))

        groups.append(await largeFileGroup(home: home, tracker: tracker))
        groups.append(await sipOverviewGroup(tracker: tracker))

        return groups.filter { !$0.items.isEmpty }
    }

    // MARK: - 组构建

    private func group(
        id: String,
        name: String,
        description: String,
        iconName: String,
        directory: String,
        home: String,
        forceSafety: SystemItemSafety?,
        detail: String,
        tracker: FileScanProgressTracker?
    ) async -> SystemAnalysisGroup {
        let items = await analyzeItems(in: directory, home: home, forceSafety: forceSafety, detail: detail, tracker: tracker)
        return SystemAnalysisGroup(
            id: id, name: name, description: description, iconName: iconName, items: items
        )
    }

    private func analyzeItems(
        in directory: String,
        home: String,
        forceSafety: SystemItemSafety?,
        detail: String,
        tracker: FileScanProgressTracker?
    ) async -> [SystemAnalysisItem] {
        let entries = FileTreeWalker.readEntries(path: directory)
        var items: [SystemAnalysisItem] = []
        items.reserveCapacity(entries.count)
        for entry in entries {
            if Task.isCancelled { break }
            let stats: FileTreeWalker.Stats
            if entry.isDirectory {
                stats = await FileTreeWalker.stats(path: entry.path, depth: 1, tracker: tracker)
            } else {
                stats = FileTreeWalker.Stats(size: entry.size, fileCount: 1)
            }
            let safety = forceSafety ?? Self.safety(for: entry.path, home: home)
            items.append(SystemAnalysisItem(
                name: entry.name,
                path: entry.path,
                size: stats.size,
                fileCount: stats.fileCount,
                modificationDate: entry.modificationDate,
                safety: safety,
                detail: detail
            ))
        }
        return items.sorted { $0.size > $1.size }
    }

    /// 开发工具版本残留：Xcode 旧版设备支持文件（用户级、可安全清理）。
    private func developerLeftoverGroup(home: String, tracker: FileScanProgressTracker?) async -> SystemAnalysisGroup {
        let roots = [
            "iOS DeviceSupport",
            "tvOS DeviceSupport",
            "watchOS DeviceSupport",
            "visionOS DeviceSupport",
        ].map { home + "/Library/Developer/Xcode/" + $0 }

        var items: [SystemAnalysisItem] = []
        for root in roots {
            if Task.isCancelled { break }
            items.append(contentsOf: await analyzeItems(
                in: root,
                home: home,
                forceSafety: .safe,
                detail: "旧版系统符号支持文件，可按版本清理",
                tracker: tracker
            ))
        }
        items.sort { $0.size > $1.size }
        return SystemAnalysisGroup(
            id: "dev_leftovers",
            name: "开发工具版本残留",
            description: "~/Library/Developer/Xcode 下的旧版设备支持文件，属于可再生的版本残留",
            iconName: "hammer.fill",
            items: items
        )
    }

    /// 大文件热点：用户常见目录与 /Library 中 >= 100 MB 的文件（限量、限深、可取消）。
    private func largeFileGroup(home: String, tracker: FileScanProgressTracker?) async -> SystemAnalysisGroup {
        let minSize: UInt64 = 100 * 1024 * 1024
        let roots: [(path: String, maxDepth: Int)] = [
            (home + "/Downloads", 6),
            (home + "/Desktop", 6),
            (home + "/Documents", 6),
            (home + "/Library/Caches", 8),
            ("/Library", 4),
        ]

        var hits: [FileTreeWalker.Entry] = []
        for root in roots {
            if Task.isCancelled { break }
            let found = await FileTreeWalker.largeFiles(
                path: root.path, minSize: minSize, depth: 0, maxDepth: root.maxDepth, tracker: tracker
            )
            hits.append(contentsOf: found)
            if hits.count >= 500 { break }
        }

        let items = hits
            .sorted { $0.size > $1.size }
            .prefix(30)
            .map { entry in
                SystemAnalysisItem(
                    name: entry.name,
                    path: entry.path,
                    size: entry.size,
                    fileCount: 1,
                    modificationDate: entry.modificationDate,
                    safety: Self.safety(for: entry.path, home: home),
                    detail: "大文件热点：请自行确认用途后再决定是否清理"
                )
            }

        return SystemAnalysisGroup(
            id: "large_files",
            name: "大文件热点",
            description: "常见目录中超过 100 MB 的文件（最多列出 30 个）。个人数据一律仅供查看，只有位于用户缓存中的文件才可清理",
            iconName: "doc.badge.ellipsis",
            items: Array(items)
        )
    }

    /// SIP 保护区总览：浅层估算占用，全部标记为不可操作。
    private func sipOverviewGroup(tracker: FileScanProgressTracker?) async -> SystemAnalysisGroup {
        var items: [SystemAnalysisItem] = []
        for root in Self.sipRoots {
            if Task.isCancelled { break }
            guard FileManager.default.fileExists(atPath: root) else { continue }
            tracker?.report(path: root)
            // 限深浅层估算，避免对密封系统卷做全量遍历；UI 上明确标注为估算值
            let stats = FileTreeWalker.fallbackStats(path: root, remainingDepth: 2)
            items.append(SystemAnalysisItem(
                name: root,
                path: root,
                size: stats.size,
                fileCount: stats.fileCount,
                modificationDate: FileTreeWalker.modificationDate(ofPath: root),
                safety: .sipProtected,
                detail: "浅层估算占用，受 SIP 保护，绝对不可修改或删除"
            ))
        }
        items.sort { $0.size > $1.size }
        return SystemAnalysisGroup(
            id: "sip_overview",
            name: "SIP 保护区占用",
            description: "/System、/usr、/bin、/sbin、/Library/Extensions 的浅层占用估算。这些路径受系统完整性保护，本工具永远只提供查看",
            iconName: "lock.shield.fill",
            items: items
        )
    }
}
