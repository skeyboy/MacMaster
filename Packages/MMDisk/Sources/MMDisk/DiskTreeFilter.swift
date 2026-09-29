import Foundation

/// 全树名称过滤器（disktree #7 口径）：匹配看整棵子树，不看当前这一层。
///
/// 三条规则：
/// 1. 一个目录只要它的任意后代命中，就以「命中体积」出现在结果里——
///    块面积是命中部分的字节数，不是目录自身的总占用；
/// 2. 自身名称命中的目录按全量计入（用户找的就是这个目录整体），
///    子树原样展示，不再按名字剪枝；
/// 3. 「测过、确实没命中」和「没扫到那一层、判不了」是两回事：
///    后者以 `indeterminateCount/indeterminateBytes` 如实上报，
///    绝不折叠成零命中，也绝不参与布局面积（编不出该画多大）。
enum DiskTreeFilter {

    /// 结果里的一个命中节点。
    struct Node: Sendable {
        enum Tier: Sendable {
            /// 自身名称命中：保色，面积 = 整个目录的占用。
            case matched
            /// 自身未命中、含命中后代：退色，面积 = 子树里的命中体积。
            case containsMatch
        }
        let node: DiskTreeNode
        let tier: Tier
        /// 全树命中体积。containsMatch 时是各命中分支求和，必 ≤ node.size。
        let matchedBytes: UInt64
        /// nil：自身命中，子树原样展示；非 nil：祖先只保留含命中的分支，
        /// 已按 matchedBytes 降序。
        let children: [Node]?

        var id: String { node.path }
    }

    struct Result: Sendable {
        /// 顶层命中节点，按命中体积降序——treemap 布局的输入就是这个顺序。
        let nodes: [Node]
        /// 没扫到深度、无法判断是否命中的目录数量与其实际占用。
        let indeterminateCount: Int
        let indeterminateBytes: UInt64
        /// 命中侧总量：过滤生效时"占当前层"的分母（占比的是命中盘，不是全层）。
        let matchedBytesTotal: UInt64
    }

    /// 与旧单层过滤一致的匹配方式：大小写不敏感的子串匹配。
    static func matches(name: String, filter: String) -> Bool {
        name.localizedCaseInsensitiveContains(filter)
    }

    /// filter 为空返回 nil——视图据此直接回到原始布局，不留任何残状态。
    static func apply(_ nodes: [DiskTreeNode], filter: String) -> Result? {
        guard !filter.isEmpty else { return nil }
        var tally = (count: 0, bytes: UInt64(0))
        var hits: [Node] = []
        hits.reserveCapacity(nodes.count)
        for node in nodes {
            if let hit = visit(node, filter: filter, tally: &tally) { hits.append(hit) }
        }
        hits.sort { $0.matchedBytes > $1.matchedBytes }
        let total = hits.reduce(UInt64(0)) { $0 &+ $1.matchedBytes }
        return Result(nodes: hits, indeterminateCount: tally.count,
                      indeterminateBytes: tally.bytes, matchedBytesTotal: total)
    }

    /// 返回该子树的命中节点；nil = 量过了、确实没有命中。
    /// 「没扫到底」的目录不返回节点，但要记进 tally——它和零命中的区别
    /// 必须一路保留到界面文案，这里是最初的分叉点。
    private static func visit(
        _ node: DiskTreeNode, filter: String,
        tally: inout (count: Int, bytes: UInt64)
    ) -> Node? {
        let selfHit = matches(name: node.name, filter: filter)

        if !node.isDirectory {
            guard selfHit else { return nil }
            return Node(node: node, tier: .matched, matchedBytes: node.size, children: [])
        }
        if selfHit {
            // 目录名本身就是答案：整体算命中、保色，内部不再剪枝。
            return Node(node: node, tier: .matched, matchedBytes: node.size, children: nil)
        }
        if !node.descendantsMeasured {
            // 子树没有逐层枚举过，里面有没有命中判不了。
            // 不画它（面积无从谈起），但要如实计数——这就是"未测量 ≠ 零命中"。
            tally.count += 1
            tally.bytes &+= node.size
            return nil
        }

        var kept: [Node] = []
        for child in node.children {
            if let hit = visit(child, filter: filter, tally: &tally) { kept.append(hit) }
        }
        guard !kept.isEmpty else { return nil }
        kept.sort { $0.matchedBytes > $1.matchedBytes }
        let bytes = kept.reduce(UInt64(0)) { $0 &+ $1.matchedBytes }
        return Node(node: node, tier: .containsMatch, matchedBytes: bytes, children: kept)
    }
}
