import Foundation

/// 「值得看一眼」：把一棵扫描树压成几条人能一秒判断的发现，
/// 而不是"最大的 100 个条目"那种原始排行榜。
///
/// 三条纪律照抄 disktree 的判定，因为它们决定了这份清单能不能被信任：
/// 1. 只取最顶层——命中即停，不再往里走，所以清单里的条目互不嵌套；
/// 2. 有互不嵌套这条前提，把它们的字节数相加才是个有意义的总数；
/// 3. 低于门槛的条目不值得占一行，宁可少列也不要刷屏。
enum DiskInsights {
    struct Finding: Identifiable, Sendable {
        enum Kind: String, Sendable {
            case reclaimable
            case stale
            case largeFile

            var label: String {
                switch self {
                case .reclaimable: "可回收"
                case .stale: "久未触碰"
                case .largeFile: "单个大文件"
                }
            }
        }

        /// 路径就是天然唯一键，重扫之后仍然指同一个目录。
        let id: String
        let name: String
        let path: String
        let size: UInt64
        let kind: Kind
        let reason: String
    }

    /// 低于这条线的目录不值得单列一行。
    static let minBytes: UInt64 = 64 * 1024 * 1024
    /// 目录自身的 mtime 超过这么久没动，才算"久未触碰"。
    static let staleAfter: TimeInterval = 180 * 24 * 3600
    /// 单个文件要到这个量级才值得从所属目录里跳出来单列。
    static let largeFileBytes: UInt64 = 1024 * 1024 * 1024
    /// 面板只给 6 条：再多就不是"看一眼"，是第二份列表了。
    static let panelLimit = 6

    /// 深度不限，但命中即停。返回按大小降序、最多 `limit` 条。
    static func worthALook(
        root: [DiskTreeNode],
        now: Date,
        limit: Int = panelLimit
    ) -> [Finding] {
        var findings: [Finding] = []
        collect(root, now: now, into: &findings)
        return Array(findings.sorted { $0.size > $1.size }.prefix(max(limit, 0)))
    }

    private static func collect(_ nodes: [DiskTreeNode], now: Date, into findings: inout [Finding]) {
        for node in nodes {
            if let finding = finding(for: node, now: now) {
                findings.append(finding)
                continue
            }
            // 可回收目录即使没到门槛也不再往里看：它下面的每一层都随它同一个结论，
            // 列出来只会是同一件事的碎片。
            if node.reclaim != nil { continue }
            if node.isDirectory { collect(node.children, now: now, into: &findings) }
        }
    }

    private static func finding(for node: DiskTreeNode, now: Date) -> Finding? {
        if node.reclaim != nil, node.size >= minBytes {
            return Finding(id: node.path, name: node.name, path: node.path, size: node.size,
                           kind: .reclaimable, reason: reclaimText(node.reclaim!))
        }
        if !node.isDirectory {
            guard node.size >= largeFileBytes else { return nil }
            return Finding(id: node.path, name: node.name, path: node.path, size: node.size,
                           kind: .largeFile,
                           // 不重复报体积：右边那一列就是同一个数，写两遍只会挤掉名字。
                           reason: "单个文件，比同目录里的其他条目大得多")
        }
        // mtime 没量到就不下"久未触碰"的结论：缺数不等于旧。
        guard let modified = node.modificationDate, node.size >= minBytes else { return nil }
        let idle = now.timeIntervalSince(modified)
        guard idle >= staleAfter else { return nil }
        return Finding(id: node.path, name: node.name, path: node.path, size: node.size,
                       kind: .stale, reason: "已 \(approxDays(idle))没有增删过内容")
    }

    /// 发现条目要的是"读起来像人话"的量词，和页面上的精确字节不是一回事。
    private static func approxDays(_ seconds: TimeInterval) -> String {
        let days = Int(seconds / 86_400)
        if days >= 365 { return "\(days / 365) 年" }
        if days >= 30 { return "\(days / 30) 个月" }
        return "\(max(days, 0)) 天"
    }

    private static func reclaimText(_ reason: ReclaimReason) -> String {
        switch reason {
        case .buildOutput: "构建产物，工具链可以随时重新生成"
        case .dependency: "依赖缓存，下次安装会重新下载"
        case .cache: "应用缓存，会自动重建"
        case .log: "日志与诊断记录"
        case .inherited: "位于可清理目录之内"
        }
    }
}
