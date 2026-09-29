import Foundation

/// 把"用户标了什么"裁决成"能删什么、不能删什么、为什么不能删"。
///
/// 这条流水线必须是一个纯函数，而不是散在按钮回调里的几个 if：确认面板要列的清单、
/// 按钮上的合计字节、"删完之后还剩多少可用"的投影，三者必须是同一次裁决的结果，
/// 否则面板写着 3 项、按钮写着 4 项，用户就再也不知道该信谁。
enum DiskRemoval {
    struct Mark: Sendable {
        let path: String
        let name: String
        let size: UInt64
    }

    struct Target: Identifiable, Sendable {
        let path: String
        let name: String
        let size: UInt64
        var id: String { path }
    }

    /// 拦截理由要能直接印在面板上：被拦住的东西必须说清为什么，
    /// 不然用户只会以为程序漏算了。
    enum BlockReason: String, Sendable {
        case outsideRoot
        case isScanRoot
        case isHome
        case isVolumeRoot
        case systemTree
        case vanished

        var note: String {
            switch self {
            case .outsideRoot: return "不在本次扫描的目录之内"
            case .isScanRoot: return "就是正在扫描的目录本身"
            case .isHome: return "用户主目录"
            case .isVolumeRoot: return "整块卷的根目录"
            case .systemTree: return "系统目录树"
            case .vanished: return "扫描之后已经不在磁盘上了"
            }
        }
    }

    struct Blocked: Identifiable, Sendable {
        let path: String
        let name: String
        let size: UInt64
        let reason: BlockReason
        var id: String { path }
    }

    struct Plan: Sendable {
        let targets: [Target]
        let blocked: [Blocked]
        /// 被父目录吞掉的标记：它们不额外释放任何空间，但也不能算漏。
        let absorbed: Int

        var total: UInt64 { targets.reduce(0) { $0 + $1.size } }
        var isEmpty: Bool { targets.isEmpty }

        static let empty = Plan(targets: [], blocked: [], absorbed: 0)
    }

    /// 只有从卷根往下数第一层是这些名字时才算系统树。`/Volumes` 不在其列——
    /// 那是别的卷的入口，扫外接盘时所有路径都在它下面；`~/Library` 也不在，
    /// 用户资源库里全是第三方缓存，正是该清理的地方。
    private static let systemFirstComponents: Set<String> = [
        "System", "usr", "bin", "sbin", "private", "dev", "Library",
    ]

    static func plan(marks: [Mark], root: String, home: String = NSHomeDirectory()) -> Plan {
        guard !marks.isEmpty else { return .empty }
        let scanRoot = (root as NSString).standardizingPath
        var accepted: [Target] = []
        var blocked: [Blocked] = []
        var absorbed = 0

        // 浅的先收：这样"祖先已收"只要看已收集的路径，不用回溯整棵树。
        for mark in marks.sorted(by: { depth($0.path) < depth($1.path) }) {
            let path = (mark.path as NSString).standardizingPath
            if path != scanRoot, !isInside(path, container: scanRoot) {
                blocked.append(Blocked(path: path, name: mark.name, size: mark.size, reason: .outsideRoot))
            } else if path == scanRoot {
                blocked.append(Blocked(path: path, name: mark.name, size: mark.size, reason: .isScanRoot))
            } else if path == home {
                blocked.append(Blocked(path: path, name: mark.name, size: mark.size, reason: .isHome))
            } else if isSystemTree(path) {
                blocked.append(Blocked(path: path, name: mark.name, size: mark.size, reason: .systemTree))
            } else if isVolumeRoot(path) {
                blocked.append(Blocked(path: path, name: mark.name, size: mark.size, reason: .isVolumeRoot))
            } else if !exists(path) {
                blocked.append(Blocked(path: path, name: mark.name, size: mark.size, reason: .vanished))
            } else if alreadyCovered(path, by: accepted) {
                absorbed += 1
            } else {
                accepted.append(Target(path: path, name: mark.name, size: mark.size))
            }
        }
        return Plan(
            targets: accepted.sorted { $0.size > $1.size },
            blocked: blocked.sorted { $0.size > $1.size },
            absorbed: absorbed
        )
    }

    /// 删掉这些字节之后还剩多少可用。饱和相加，绝不返回超过卷容量的数——
    /// "可用 2 TB / 总容量 512 GB"这种数字一旦出现，整个面板的可信度就没了。
    static func afterRemoving(free: UInt64, capacity: UInt64, bytes: UInt64) -> UInt64 {
        let (sum, overflow) = free.addingReportingOverflow(bytes)
        if overflow { return max(free, capacity) }
        return capacity > 0 ? min(sum, capacity) : sum
    }

    private static func depth(_ path: String) -> Int {
        path.reduce(0) { $1 == "/" ? $0 + 1 : $0 }
    }

    /// 按路径组件判断包含关系：`/Users/lee` 是 `/Users/leestat` 的字符串前缀，
    /// 但绝不是它的父目录，所以必须比到分隔符。
    private static func isInside(_ path: String, container: String) -> Bool {
        if container == "/" { return path != "/" && path.hasPrefix("/") }
        return path.hasPrefix(container + "/")
    }

    private static func alreadyCovered(_ path: String, by targets: [Target]) -> Bool {
        targets.contains { isInside(path, container: $0.path) }
    }

    private static func isSystemTree(_ path: String) -> Bool {
        guard let first = path.split(separator: "/").first else { return false }
        return systemFirstComponents.contains(String(first))
    }

    /// 卷根 = 挂载点：自己的 st_dev 和父目录不同。这是 Unix 上判断挂载最可靠的口径，
    /// 不用查挂载表，也不会被符号链接骗到。
    private static func isVolumeRoot(_ path: String) -> Bool {
        if path == "/" { return true }
        guard let dev = device(of: path),
              let parentDev = device(of: (path as NSString).deletingLastPathComponent)
        else { return false }
        return dev != parentDev
    }

    private static func device(of path: String) -> dev_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_dev
    }

    /// 标记到确认之间可能隔着一轮重扫，也可能用户自己在访达里删掉了。
    /// 用 lstat 而不是 FileManager 的 exists：符号链接本身也在磁盘上，删它是安全的。
    private static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}
