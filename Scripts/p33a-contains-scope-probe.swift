// P33a 审计探针：`名称包含应用名` 这一条证据在增强/深度档会不会把**别的应用**的残留收进
// 本机某个应用的清单里，以及被这样收进来的项有多少落在默认勾选上。
//
// 用法在 `Scripts/p33a-contains-scope-probe.sh`（它把真源文件和本文件编成同一个模块）。
// 全程只读：不调用任何删除接口，也只在被点名的项上量大小。
//
// 为什么这里一行判定逻辑都不写：包含匹配、类别默认风险、默认勾选三件事分别住在
// `ResidualNameMatcher` / `ResidualCategory.defaultRisk` / `MMRisk.isDefaultSelected`，
// 本探针抄任何一段，跑出来的就是一份"我以为它会这样"的表，而不是它现在的行为。
import Foundation

@main struct ContainsScopeProbe {

    /// 真证据后面被 `descend` 追加的那一句后缀——它不是另一种证据，判据要把它剥掉再看。
    static let descentSuffixMarker = "（位于 "
    static let containmentEvidence = "名称包含应用名"

    struct Hit {
        let owner: DiscoveredApp
        let item: ResidualItem
        /// 更硬的主张者：用 allowContains=false 严格对每个**别的**应用复核，命中就记下来。
        let claimants: [(app: DiscoveredApp, reason: String)]
        /// 住在别人的残留里：这一条本身没人严格主张，但它的**某个祖先目录**归别的应用。
        let nestedIn: [(app: DiscoveredApp, ancestor: String, reason: String)]
    }

    struct Identity {
        let app: DiscoveredApp
        let matcher: ResidualNameMatcher
    }

    static func main() {
        let home = NSHomeDirectory()
        let allApps = AppScanner.applications(in: AppScanner.defaultSearchDirectories(home: home))
        let apps = allApps.filter { AppScanner.isSystemOwned(bundleID: $0.bundleID) == false }
        // 主张者池子不能只装"可卸载的那 41 个"：`com.apple.*` 自己不扫残留，
        // 但它的文件是真的。把系统应用也纳入复核，"没有别人主张"这句话才真的没有漏项。
        let claimPool = allApps.map { Identity(app: $0, matcher: ResidualNameMatcher(appName: $0.bundleName, bundleID: $0.bundleID)) }

        print("# 应用清单：\(allApps.count) 个 .app，剔除 com.apple.* 后 \(apps.count) 个参与扫描")
        print("# home=\(home)")
        print("")

        printMechanismTable()

        // strict 档按定义不可能有包含命中（ResidualScanner.swift:529 的 allowContains 要求
        // rank 高于 strict），所以只跑增强与深度两档；这一句在日志里当成一条否证，而不是"没跑"。
        report(tier: .enhanced, hits: census(tier: .enhanced, apps: apps, claimPool: claimPool, home: home))
        report(tier: .deep, hits: census(tier: .deep, apps: apps, claimPool: claimPool, home: home))

        print("## 四、口径与边界")
        print("")
        print("- 跨应用的判据是「别的应用用 allowContains=false 也主张这一项」，方向单调：更硬证据不含包含匹配，")
        print("  所以这一条成立时，删除动作拿走的是**另一个仍在盘上的应用**的数据，而不是本应用的孤儿文件。")
        print("- 但同层判据不够：真主人常常主张的是**父目录**（`~/Library/Caches/JetBrains/IntelliJIdea2026.2` 这种")
        print("  厂商/产品嵌套形态），所以另列「祖先目录归别人」那一族——它才是这台机上跑得出数的那一族。")
        print("- 主张者池子含 com.apple.*（它们不进扫描清单，但它们的文件是真的归属），")
        print("  也含这次没扫的 owner 自己以外的全部 .app。")
        print("- 包含命中但没有任何安装应用严格主张的项，本探针不计入跨应用（可能是孤儿，也可能是尚未安装的第二方），")
        print("  这一族的条数在上面的「命中总数 − 跨应用」里；默认勾选的那些逐条列在明细表里，交人工判。")
        print("- 大小只对本机跑出的跨应用项与默认勾选项量，避免整轮扫描变成全盘遍历。")
    }

    /// 类别 → 默认风险 → 默认勾选：三列全是真函数的返回值，这张表钉住"证据强度不参与定档"这件事。
    static func printMechanismTable() {
        print("## 一、哪几类的命中会默认勾选（真值来自 ResidualCategory.defaultRisk 与 MMRisk.isDefaultSelected）")
        print("")
        print("| 类别 | defaultRisk | 默认勾选 |")
        print("|---|---|---|")
        for category in ResidualCategory.allCases {
            let risk = category.defaultRisk
            print("|\(category.rawValue)|\(risk.rawValue)|\(risk.isDefaultSelected ? "是" : "否")|")
        }
        print("")
    }

    static func census(tier: ResidualSensitivity, apps: [DiscoveredApp],
                       claimPool: [Identity], home: String) -> [Hit] {
        var hits: [Hit] = []
        for (index, app) in apps.enumerated() {
            if index % 20 == 0 {
                FileHandle.standardError.write("  \(tier.rawValue) 档 \(index + 1)/\(apps.count) \(app.bundleName)\n".data(using: .utf8)!)
            }
            let report = ResidualScanner.scan(appName: app.bundleName, bundleID: app.bundleID,
                                              appPath: app.path,
                                              options: ResidualScanOptions(home: home, sensitivity: tier),
                                              measure: { _ in 0 })
            for item in report.items where item.reason.hasPrefix(containmentEvidence) {
                let url = URL(fileURLWithPath: item.path)
                var claimants: [(DiscoveredApp, String)] = []
                for other in claimPool where other.app.path != app.path {
                    guard let reason = other.matcher.reason(for: url, bundleID: other.app.bundleID,
                                                            allowContains: false),
                          reason.hasPrefix(descentSuffixMarker) == false else { continue }
                    claimants.append((other.app, reason))
                }
                hits.append(Hit(owner: app, item: item, claimants: claimants,
                                nestedIn: nestedOwner(of: url, owner: app, claimPool: claimPool, home: home)))
            }
        }
        return hits
    }

    /// 这一项是不是**住在别人的残留里**：往上逐层问其它应用"这一层归不归你"，
    /// 用语义与扫描一致（allowContains=true）。同层判据看不见这一族——真主人主张的是
    /// 父目录而不是这一条本身，`本机跨应用 = 1 条`那种数就是这么漏掉的。
    /// 只走到第一个有主人的祖先为止：更外层的主人由那个主人自己的清单去报。
    static func nestedOwner(of url: URL, owner: DiscoveredApp, claimPool: [Identity], home: String)
        -> [(app: DiscoveredApp, ancestor: String, reason: String)] {
        var parent = url.deletingLastPathComponent()
        while parent.path.count > 1, parent.path != home {
            var found: [(DiscoveredApp, String, String)] = []
            for other in claimPool where other.app.path != owner.path {
                if let reason = other.matcher.reason(for: parent, bundleID: other.app.bundleID, allowContains: true),
                   reason.hasPrefix(descentSuffixMarker) == false {
                    found.append((other.app, parent.lastPathComponent, reason))
                }
            }
            if found.isEmpty == false { return found }
            parent = parent.deletingLastPathComponent()
        }
        return []
    }

    static func report(tier: ResidualSensitivity, hits: [Hit]) {
        print("## \(tier == .enhanced ? "二" : "三")、\(tier.rawValue) 档：`名称包含应用名` 的命中编目")
        print("")
        let crossApp = hits.filter { $0.claimants.isEmpty == false }
        let nested = hits.filter { $0.nestedIn.isEmpty == false }
        let nestedSelected = nested.filter { $0.item.risk.isDefaultSelected }
        let defaultSelected = hits.filter { $0.item.risk.isDefaultSelected }
        let crossAppSelected = crossApp.filter { $0.item.risk.isDefaultSelected }
        let uniqueCrossPaths = Set(crossApp.map { $0.item.id })
        let uniqueNestedPaths = Set(nested.map { $0.item.id })

        print("- 命中总数：\(hits.count) 条，涉及 \(Set(hits.map { $0.owner.path }).count) 个应用")
        print("- 其中**别的应用以更硬的证据在同一路径上也主张这一项**（跨应用）：\(crossApp.count) 条，去重后 \(uniqueCrossPaths.count) 个路径")
        print("- 其中**祖先目录归别的应用**（住在别人的残留里）：\(nested.count) 条，去重后 \(uniqueNestedPaths.count) 个路径；这些里默认勾选的 \(nestedSelected.count) 条")
        print("- 其中默认勾选（risk=\(MMRisk.safe.rawValue)）：\(defaultSelected.count) 条；跨应用且默认勾选：\(crossAppSelected.count) 条")
        print("")

        if nested.isEmpty == false {
            print("### 祖先目录归别人的命中（往上只走到第一个有主人的那一层）")
            print("")
            print("| 挂在谁名下 | 路径 | 类别 | 风险 | 默认勾选 | 主人（祖先目录 + 证据） | 字节 |")
            print("|---|---|---|---|---|---|---|")
            for hit in nested.sorted(by: { $0.item.path < $1.item.path }) {
                let owners = hit.nestedIn.map { "\($0.app.bundleName) 的 \($0.ancestor)（\($0.reason)）" }
                    .joined(separator: "、")
                print("|\(hit.owner.bundleName)|\(hit.item.displayPath)|\(hit.item.category.rawValue)|"
                    + "\(hit.item.risk.rawValue)|\(hit.item.risk.isDefaultSelected ? "是" : "否")|\(owners)|"
                    + "\(DirectoryResidualSizeMeasurer.size(of: hit.item.path))|")
            }
            var nestedSelectedBytes: UInt64 = 0
            var countedNested = Set<String>()
            for hit in nestedSelected where countedNested.insert(hit.item.id).inserted {
                nestedSelectedBytes += DirectoryResidualSizeMeasurer.size(of: hit.item.path)
            }
            print("")
            print("- 这一族里**默认勾选**的按删除根口径合计：**\(nestedSelectedBytes) 字节**")
            print("")
        }

        if crossApp.isEmpty {
            print("本机没有跑出跨应用命中（不代表机制不成立，只代表这台机的应用清单撞不上）。")
            print("")
        } else {
            print("### 跨应用命中明细（大小只对这一族量，真值来自 DirectoryResidualSizeMeasurer）")
            print("")
            print("| 被勾选进谁的清单 | 路径 | 类别 | 风险 | 默认勾选 | 更硬的主张者（allowContains=false） | 字节 |")
            print("|---|---|---|---|---|---|---|")
            var totalSelected: UInt64 = 0
            var counted = Set<String>()
            for hit in crossApp.sorted(by: { lhs, rhs in
                lhs.owner.bundleName == rhs.owner.bundleName ? lhs.item.path < rhs.item.path : lhs.owner.bundleName < rhs.owner.bundleName
            }) {
                let owners = hit.claimants.map { "\($0.app.bundleName)（\($0.reason)）" }.joined(separator: "、")
                let size = DirectoryResidualSizeMeasurer.size(of: hit.item.path)
                if hit.item.risk.isDefaultSelected, counted.insert(hit.item.id).inserted { totalSelected += size }
                print("|\(hit.owner.bundleName)|\(hit.item.displayPath)|\(hit.item.category.rawValue)|\(hit.item.risk.rawValue)|\(hit.item.risk.isDefaultSelected ? "是" : "否")|\(owners)|\(size)|")
            }
            print("")
            print("- 跨应用且默认勾选的项按删除根口径合计：**\(totalSelected) 字节**（父目录已计入时不再加子项）")
            print("")

            var byOwner: [String: Int] = [:]
            for hit in crossApp { byOwner[hit.owner.bundleName, default: 0] += 1 }
            print("- 按被勾选方汇总：" + byOwner.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            print("")
        }

        // 用户真正点下「移入废纸篓」就能拿走的那一族：证据只有包含匹配、却默认勾选。
        // 它们没有被第二个应用严格主张，所以不等于"安全"，只等于"这条证据到不了归属"——逐条列出来交人工判。
        if defaultSelected.isEmpty == false {
            print("### 默认勾选且证据只有「名称包含应用名」的项（逐条列，含体积）")
            print("")
            print("| 挂在谁名下 | 路径 | 类别 | 体积字节 | 有没有第二个主张者 |")
            print("|---|---|---|---|---|")
            for hit in defaultSelected.sorted(by: { $0.item.path < $1.item.path }) {
                print("|\(hit.owner.bundleName)|\(hit.item.displayPath)|\(hit.item.category.rawValue)|"
                    + "\(DirectoryResidualSizeMeasurer.size(of: hit.item.path))|"
                    + "\(hit.claimants.isEmpty ? "无" : hit.claimants.map { $0.app.bundleName }.joined(separator: "、"))|")
            }
            print("")
        }
    }
}
