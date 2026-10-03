import Foundation

/// 重扫之后把旧标记挂回新扫描的树（disktree 的"凭绝对路径重新挂回树"）。
///
/// 两件口径必须分开：**标记按绝对路径存续，体积一律换成新扫描那一份**。
/// 挂不回去的路径直接丢弃并说出来——底部那行「已标记 N 项 · X」是要被当成待删总量读的，
/// 让它掺进一个旧快照的字节，等于在面板上留一个谁也核对不了的数。
enum DiskMarks {
    struct Outcome {
        var marks: [String: DiskTreeNode]
        /// 这次重新枚举覆盖到的、却已经不在了的标记路径（已删除、或扫描根本不含它）。
        var dropped: [String]
    }

    /// 整根重扫：新树里找不到的标记一律丢弃。
    /// `rootPath` 自己不算"找不到"——扫描报告的是它的孩子，它这一层没被这次枚举观察到。
    static func reattach(_ previous: [String: DiskTreeNode],
                         rootPath: String,
                         into rootItems: [DiskTreeNode]) -> Outcome {
        var marks: [String: DiskTreeNode] = [:]
        var dropped: [String] = []
        for (path, old) in previous {
            guard path != rootPath else {
                marks[path] = old
                continue
            }
            if let fresh = find(path: path, in: rootItems) {
                marks[path] = fresh
            } else {
                dropped.append(path)
            }
        }
        return Outcome(marks: marks, dropped: dropped.sorted())
    }

    /// 单层重新枚举（「重新扫描」按钮、下钻未缓存的目录）。
    /// `scope` 是这次真正重新枚举过的那个目录：它底下的标记要么换成新节点，
    /// 要么确认不在了就丢弃；scope 之外的原样留着——
    /// 没在这一层扫到 ≠ 不存在，"它没了"只有整根重扫说得起。
    static func refresh(_ previous: [String: DiskTreeNode],
                        with items: [DiskTreeNode], under scope: String) -> Outcome {
        var marks: [String: DiskTreeNode] = [:]
        var dropped: [String] = []
        for (path, old) in previous {
            // items 是 scope 的孩子，scope 自己不在里面：别把"孩子里没找到"读成"它没了"。
            guard path != scope, isUnder(path, scope) else {
                marks[path] = old
                continue
            }
            if let fresh = find(path: path, in: items) {
                marks[path] = fresh
            } else {
                dropped.append(path)
            }
        }
        return Outcome(marks: marks, dropped: dropped.sorted())
    }

    /// 按路径组件判断，不是纯前缀："/tmp/build" 不算 "/tmp/bu" 底下。
    static func isUnder(_ path: String, _ scope: String) -> Bool {
        guard !scope.isEmpty else { return false }
        if path == scope { return true }
        return path.hasPrefix(scope.hasSuffix("/") ? scope : scope + "/")
    }

    private static func find(path: String, in nodes: [DiskTreeNode]) -> DiskTreeNode? {
        for node in nodes {
            if node.path == path { return node }
            if let deeper = find(path: path, in: node.children) { return deeper }
        }
        return nil
    }
}
