import Foundation
import MMCore

/// 清理页"排除名单"（白名单）的条目来源。
///
/// 界面上必须显示来源：用户半年后回来看这条排除，要能想起它是
/// 自己在清理页点掉的、还是设置页里永久排除的整个目录。
public enum CleanerExclusionSource: String, Codable, CaseIterable, Sendable {
    /// 在清理页按明细条目点"排除"
    case scannedItem
    /// 通过文件面板选定的整个目录
    case chosenFolder
    /// 从旧的会话内存态迁移过来的历史条目
    case migrated

    public var label: String {
        switch self {
        case .scannedItem: "清理页排除"
        case .chosenFolder: "手动选择的目录"
        case .migrated: "旧版本迁移"
        }
    }
}

/// 一条持久化下来的排除记录。以绝对路径为身份，重启后按路径重新匹配扫描结果。
public struct CleanerExclusionEntry: Codable, Hashable, Identifiable, Sendable {
    public let path: String
    public let source: CleanerExclusionSource
    public let addedAt: Date

    public var id: String { path }

    public init(path: String, source: CleanerExclusionSource, addedAt: Date = Date()) {
        self.path = path
        self.source = source
        self.addedAt = addedAt
    }
}

/// UserDefaults 支撑的排除名单存储。
///
/// MMCore 的 `AppSettings.excludedFolderPaths` 已经在持久化"设置页选定的永久排除目录"，
/// 但清理页逐条点"排除"的那批条目此前只活在 `CleanerModel` 的内存 Set 里，重启即忘，
/// 而且扫描根本没读它。这里先在本模块内落盘（键名带 `mmcleaner.` 模块前缀），
/// 并让扫描与清理两条链路都真正消费它。
/// 长期正确的位置是 MMCore 的设置存储：见交付报告的"需要共享包配合的需求"。
public final class CleanerExclusionStore {
    /// 带模块前缀的键名，避免与其它模块的 UserDefaults 键撞车。
    public static let storageKey = "mmcleaner.exclusions.v1"
    public static let schemaKey = "mmcleaner.exclusions.schema"
    private static let currentSchema = 1

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func entries() -> [CleanerExclusionEntry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        guard let decoded = try? JSONDecoder().decode([CleanerExclusionEntry].self, from: data) else {
            // 解不出来时不能静默清空：那等于把用户的白名单删了。
            // 保留原始数据，只当它是空的，界面会显示"当前没有排除项"。
            return []
        }
        return decoded.sorted { $0.addedAt > $1.addedAt }
    }

    /// 交给扫描器的排除路径清单（绝对路径）。
    public func paths() -> [String] { entries().map(\.path) }

    public func contains(path: String) -> Bool {
        entries().contains { Self.matches(path, exclusion: $0.path) }
    }

    @discardableResult
    public func add(path: String, source: CleanerExclusionSource) -> Bool {
        guard !path.isEmpty else { return false }
        var current = entries()
        guard !current.contains(where: { $0.path == path }) else { return false }
        current.append(CleanerExclusionEntry(path: path, source: source))
        return save(current)
    }

    @discardableResult
    public func remove(path: String) -> Bool {
        let current = entries()
        let kept = current.filter { $0.path != path }
        guard kept.count != current.count else { return false }
        return save(kept)
    }

    /// 删除后重新出现（撤回清理）时不该把排除记录留下当幽灵。
    @discardableResult
    public func remove(paths: Set<String>) -> Bool {
        let current = entries()
        let kept = current.filter { !paths.contains($0.path) }
        guard kept.count != current.count else { return false }
        return save(kept)
    }

    private func save(_ entries: [CleanerExclusionEntry]) -> Bool {
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        defaults.set(Self.currentSchema, forKey: Self.schemaKey)
        return true
    }

    /// 排除的判定口径：命中目录本身**或它的任何子路径**。
    /// 只做字面量相等的话，排除 `~/Library/Caches/Google` 就挡不住里面的 Chrome 缓存。
    static func matches(_ path: String, exclusion: String) -> Bool {
        path == exclusion || path.hasPrefix(exclusion.hasSuffix("/") ? exclusion : exclusion + "/")
    }
}
