import Foundation

// P41 量尺：`dev-artifact-walk-merge.md` §4.2(b) 的影响面。
//
// 问题只有一个：如果按 (b) 把「子树里有读不进的目录」的体积判成 nil，本机开发产物页会有
// 多少行从「有个数字」变成「—」。这条数在 P38a/P39 两轮都被记成「没量」，而 P6.3b 合并
// 一趟遍历之后 `SubtreeWalk.unreadableDirectories` 已经在返回值里，所以能量。
//
// 探针里没有一行判定逻辑的复刻：行集合来自真 `ProjectArtifactScanner.scan()`（走真根发现、
// 真候选词面、真成案规则），每条行的读不进目录来自真 `FileTreeWalker.walkForArtifact`。
//
// 口径边界（写进日志头，别让它被当成精确值读）：这里的 deadline 给的是宽裕值，不是真扫描
// 那一刻按 rootBudget/totalBudget 分给每个候选的那条线。所以量出来的是 **(b) 影响面的上界**：
// 真扫描里被截断的行本来就走 `stopReason != nil` → 已经是 nil，不会「因为 (b) 才变 nil」。
// 上界接近 0 → (b) 免费；上界一大片 → (b) 的代价就是那一片。

@main
struct P41NilSizeProbe {
    static func main() async {
        let home = NSHomeDirectory()
        let rules = ProjectArtifactRules.default(home: home)
        let scanner = ProjectArtifactScanner(home: home, rules: rules)
        let started = Date()
        let report = await scanner.scan()

        print("# 真扫描结论")
        print("  根：扫完 \(report.scannedRoots.count) / 截断 \(report.truncatedRoots.count) / 读不动 \(report.inaccessibleRoots.count) / 不存在 \(report.missingRoots.count)")
        print("  成案：群 \(report.groups.count) 个，行 \(report.groups.reduce(0) { $0 + $1.artifacts.count }) 条，越界丢弃 \(report.outOfSearchRootCandidateCount) 条")
        print("  isComplete=\(report.isComplete)  真扫描耗时 \(String(format: "%.1f", report.duration)) s（探针总耗时 \(String(format: "%.1f", Date().timeIntervalSince(started))) s）")
        print("")

        let now = Date()
        let deadline = now.addingTimeInterval(600)
        let recentThreshold = now.addingTimeInterval(-30 * 86400)

        var totalRows = 0
        var nestedRows = 0
        var nilSizeToday = 0
        var wouldFlip = 0
        var depthTruncated = 0
        var groupsNilToday = 0
        var groupsWouldNil = 0
        var unreadableTally: [String: Int] = [:]
        var flipSamples: [String] = []

        for group in report.groups {
            var groupHasSizeToday = group.reclaimableSize != nil
            var groupWouldGoNil = false
            if group.reclaimableSize == nil { groupsNilToday += 1 }
            for artifact in group.artifacts {
                totalRows += 1
                if artifact.isNestedInAnotherArtifact {
                    nestedRows += 1
                    continue
                }
                if artifact.size == nil { nilSizeToday += 1 }
                let walk = await FileTreeWalker.walkForArtifact(path: artifact.path, deadline: deadline,
                                                                recentThreshold: recentThreshold, needSize: true)
                if walk.sizeDepthTruncated { depthTruncated += 1 }
                guard !walk.unreadableDirectories.isEmpty else { continue }
                wouldFlip += 1
                groupWouldGoNil = true
                for dir in walk.unreadableDirectories { unreadableTally[dir, default: 0] += 1 }
                if flipSamples.count < 20 {
                    flipSamples.append("\(artifact.path)  ←  首个读不进：\(walk.unreadableDirectories[0])")
                }
            }
            if groupWouldGoNil && groupHasSizeToday { groupsWouldNil += 1 }
        }

        let measurable = totalRows - nestedRows
        print("# (b) 的影响面（上界）")
        print("  行合计 \(totalRows)，其中嵌套候选 \(nestedRows) 条（今天体积恒 nil，不受 (b) 影响）")
        print("  可测行 \(measurable)：今天已是 nil 的 \(nilSizeToday) 条，**因 (b) 新翻成 nil 的 \(wouldFlip) 条**")
        print("  占比：\(measurable > 0 ? String(format: "%.1f", Double(wouldFlip) * 100 / Double(measurable)) : "—")% of 可测行")
        print("  群：今天 reclaimableSize 已是 nil 的 \(groupsNilToday) 个，**因 (b) 新翻成 nil 的 \(groupsWouldNil) 个**（页顶「可释放」总数就是按群加的）")
        print("  附：深于 23 层的行 \(depthTruncated) 条（`sizeDepthTruncated`，与 (b) 无关，顺带记录）")
        print("")
        print("# 新翻 nil 的行（前 \({ min(20, flipSamples.count) }) 条）")
        if flipSamples.isEmpty { print("  （无）") }
        for s in flipSamples { print("  \(s)") }
        print("")
        print("# 读不进的目录（按被牵到的行数排，前 15）")
        if unreadableTally.isEmpty { print("  （无）") }
        for (dir, n) in unreadableTally.sorted(by: { $0.value > $1.value }).prefix(15) {
            print("  \(n) 行  \(dir)")
        }
    }
}
