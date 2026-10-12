// P33b 取证探针：「归属复核」（两条线索：这一项本身、它的上层目录）在本机真 home 上把哪几行
// 从默认勾选改成了谨慎，以及改完之后清单条目集合有没有变化（判据是"不减少召回"）。
//
// 用法在 `Scripts/p33b-ownership-review-probe.sh`（它把真源文件和本文件编成同一个模块）。
// 全程只读：不调用任何删除接口，大小只对被点名的降级项量。
//
// 为什么每个应用要扫两遍：`foreignApps=[]` 那一路就是复核接入前的行为（单测与旧调用点走的
// 同一条路），把它和页面现在的传法放在**同一个二进制、同一次运行**里对读，
// 表里的差值才不是"上一次跑的是另一棵树或另一个版本"。
//
// 夹具模式（`P33B_PROBE_FIXTURE_HOME=/tmp/macmaster-p33b-nesting.XXXX`）：把 home 换成
// `Scripts/p33b-nesting-fixture.sh` 那棵树，逐应用**把整张残留清单连风险档、勾选、提醒一起打出来**，
// 三档都打（strict 也打，因为 05 那一档的照片要的正是"这一档没有弱证据行"）。
// 它存在的理由是取证纪律：照片的预期行如果由我照着代码推导写进 `.log`，那照片拍到什么都能自圆其说；
// 这张表由真 `ResidualScanner` 在同一棵树上返值，照片与它不符就是照片（或夹具）错。
import Foundation

@main struct OwnershipReviewProbe {

    /// 与 `ResidualNameMatcher` / `ResidualCollector` 同一个前缀口径（A 档改的是括号里的话）。
    static let containmentEvidence = "名称包含应用名"

    struct Row {
        let app: DiscoveredApp
        let item: ResidualItem
    }

    static func main() {
        let fixture = ProcessInfo.processInfo.environment["P33B_PROBE_FIXTURE_HOME"] ?? ""
        if fixture.isEmpty == false {
            runFixture(home: fixture)
            return
        }
        let home = NSHomeDirectory()
        let allApps = AppScanner.applications(in: AppScanner.defaultSearchDirectories(home: home))
        let apps = allApps.filter { AppScanner.isSystemOwned(bundleID: $0.bundleID) == false }
        // 传的是**整张**已装清单（含 com.apple.*），与 `UninstallerModel.installedIdentities` 同形；
        // 剔除"待扫描的这一个"由引擎负责，探针不替它过滤。
        let identities = allApps.map { InstalledAppIdentity(name: $0.bundleName, bundleID: $0.bundleID) }

        print("# 应用清单：\(allApps.count) 个 .app，剔除 com.apple.* 后 \(apps.count) 个参与扫描")
        print("# home=\(home)")
        print("# 每个应用扫两遍：foreignApps=[] 与 foreignApps=\(identities.count) 条整张清单")
        print("")

        run(tier: .enhanced, apps: apps, identities: identities, home: home)
        run(tier: .deep, apps: apps, identities: identities, home: home)

        print("## 四、口径与边界")
        print("")
        print("- 复核动手要两件事同时成立：这一项的证据只有「名称包含应用名」，且**另一个已安装应用**")
        print("  对同一件事有更硬的证据——要么它直接主张这一项本身，要么它主张这一项的某个上层目录；")
        print("  两条线索按离这一项更近的顺序问，第一条成立就不问第二条。")
        print("  判据实现只有一处（`ResidualCollector.reviewed`），本探针不复述它。")
        print("- 动作只有两个：风险档 safe→caution（于是默认不勾选，`MMRisk.isDefaultSelected` 只认 safe），")
        print("  以及行下方那句 `caveat` 写上主人（「这一项本身归 X」或「上层目录归 X」）。")
        print("  证据串、命中集合、类别都不动。")
        print("- 「清单条目集合两遍相同」就是这条不变量的直接读数：不一致会打 ⚠ 行并列出差集。")
        print("- 大小只对被点名的降级项量（`DirectoryResidualSizeMeasurer.size(of:)` 同步口径），")
        print("  两遍扫描本身的 measure 一律返回 0，避免整轮变成全盘遍历。")
        print("- strict 档不跑：包含匹配按构造到不了那一档（`enumerate` 的 allowContains 闸门），")
        print("  这一条由 `ResidualOwnershipReviewTests.testStrictTierHasNoContainmentHit` 钉住。")
    }

    /// 夹具模式：把一棵已知形状的假 home 里每一行该长什么样打成表，供截图脚本的 `.log` 对照。
    ///
    /// 这里**不打差值**（差值是给真 home 那一路的问题），只打"页面现在会说什么"：
    /// 每一行给证据串、风险档、默认勾选、字节、行下方提醒，全部是真 `ResidualScanner` 的返值。
    /// `foreignApps` 传的是夹具 `Applications` 下那三份 bundle 的身份，
    /// 与页面 `UninstallerModel.installedIdentities` 在同一棵树上给的是同一份东西
    /// （页面的清单也来自那个根，`AppScanner.defaultSearchDirectories` 的第一项）。
    static func runFixture(home: String) {
        let allApps = AppScanner.applications(in: [home + "/Applications"])
        let identities = allApps.map { InstalledAppIdentity(name: $0.bundleName, bundleID: $0.bundleID) }
        print("# 夹具模式：home=\(home)")
        print("# 应用清单（home/Applications，非递归，与页面同一个根）：\(allApps.map(\.bundleName).joined(separator: ", "))")
        print("# 每档每个应用扫两遍，本表只打后一遍（foreignApps=\(identities.count) 条）；两遍的 id 集合不等会当场打 ⚠")
        print("")

        for tier in [ResidualSensitivity.strict, .enhanced, .deep] {
            print("## \(tier.rawValue) 档")
            print("")
            for app in allApps {
                let bare = ResidualScanner.scan(appName: app.bundleName, bundleID: app.bundleID,
                                                appPath: app.path,
                                                options: ResidualScanOptions(home: home, sensitivity: tier),
                                                measure: { _ in 0 })
                let report = ResidualScanner.scan(appName: app.bundleName, bundleID: app.bundleID,
                                                  appPath: app.path,
                                                  options: ResidualScanOptions(home: home, sensitivity: tier,
                                                                              foreignApps: identities),
                                                  measure: { DirectoryResidualSizeMeasurer.size(of: $0) })
                print("### \(app.bundleName)（\(app.bundleID)）：\(report.items.count) 行")
                print("")
                if Set(bare.items.map(\.id)) != Set(report.items.map(\.id)) {
                    print("⚠ 两遍的清单条目集合不等：只在前一遍 "
                        + "\(Set(bare.items.map(\.id)).subtracting(report.items.map(\.id)).sorted())"
                        + " 只在后一遍 \(Set(report.items.map(\.id)).subtracting(bare.items.map(\.id)).sorted())")
                    print("")
                }
                if report.items.isEmpty {
                    print("（这一档这一份应用没有行）")
                    print("")
                    continue
                }
                print("| 路径 | 类别 | 证据（原样） | 风险 | 默认勾选 | 字节 | 行下方提醒 |")
                print("|---|---|---|---|---|---|---|")
                for item in report.items.sorted(by: { $0.path < $1.path }) {
                    print("|\(item.displayPath)|\(item.category.rawValue)|\(item.reason)|"
                        + "\(item.risk.rawValue)|\(item.risk.isDefaultSelected ? "是" : "否")|"
                        + "\(item.size ?? 0)|\(item.caveat ?? "（无）")|")
                }
                print("")
            }
        }
    }

    static func run(tier: ResidualSensitivity, apps: [DiscoveredApp],
                    identities: [InstalledAppIdentity], home: String) {
        var rows: [Row] = []
        var mismatches: [String] = []
        var containment = 0
        var beforeSelected = 0
        var afterSelected = 0
        var downgradedIDs = Set<String>()

        for (index, app) in apps.enumerated() {
            if index % 20 == 0 {
                FileHandle.standardError.write("  \(tier.rawValue) 档 \(index + 1)/\(apps.count) \(app.bundleName)\n".data(using: .utf8)!)
            }
            let before = ResidualScanner.scan(appName: app.bundleName, bundleID: app.bundleID,
                                              appPath: app.path,
                                              options: ResidualScanOptions(home: home, sensitivity: tier),
                                              measure: { _ in 0 })
            let after = ResidualScanner.scan(appName: app.bundleName, bundleID: app.bundleID,
                                             appPath: app.path,
                                             options: ResidualScanOptions(home: home, sensitivity: tier,
                                                                         foreignApps: identities),
                                             measure: { _ in 0 })

            let beforeIDs = Set(before.items.map(\.id))
            let afterIDs = Set(after.items.map(\.id))
            if beforeIDs != afterIDs {
                mismatches.append("\(app.bundleName)：只在前一遍 \(Array(beforeIDs.subtracting(afterIDs)).sorted())"
                    + " 只在后一遍 \(Array(afterIDs.subtracting(beforeIDs)).sorted())")
            }
            let riskBefore = Dictionary(uniqueKeysWithValues: before.items.map { ($0.id, $0.risk) })
            containment += after.items.filter { $0.reason.hasPrefix(containmentEvidence) }.count
            beforeSelected += before.defaultSelectableCount
            afterSelected += after.defaultSelectableCount

            for item in after.items where item.reason.hasPrefix(containmentEvidence)
                && riskBefore[item.id] == .safe && item.risk != .safe {
                guard downgradedIDs.insert(item.id).inserted else { continue }
                rows.append(Row(app: app, item: item))
            }
        }

        print("## \(tier == .enhanced ? "一" : "二")、\(tier.rawValue) 档：复核前后的差值")
        print("")
        print("- 包含匹配命中条数（后一遍，按 id 去重前逐应用累计）：\(containment)")
        print("- 被复核降级的条数：\(rows.count)")
        print("- 默认勾选条数合计：前 \(beforeSelected) → 后 \(afterSelected)")
        print("- 清单条目集合是否两遍相同：\(mismatches.isEmpty ? "是" : "否（见下方 ⚠）")")
        if mismatches.isEmpty == false {
            for line in mismatches { print("⚠ \(line)") }
        }
        print("")
        if rows.isEmpty {
            print("本机这一档没有行被降级（不代表机制不成立，只代表这台机上这些弱证据行既没有")
            print("别的应用在同一路径上以更硬证据主张，上层目录也没有）。")
            print("")
        } else {
            print("### 被降级的行（风险档、勾选、提醒三样都来自真函数返回值）")
            print("")
            print("| 挂在谁名下 | 路径 | 类别 | 证据（原样） | 现在的风险 | 字节 | 行下方那句提醒 |")
            print("|---|---|---|---|---|---|---|")
            for row in rows.sorted(by: { $0.item.path < $1.item.path }) {
                print("|\(row.app.bundleName)|\(row.item.displayPath)|\(row.item.category.rawValue)|"
                    + "\(row.item.reason)|\(row.item.risk.rawValue)|"
                    + "\(DirectoryResidualSizeMeasurer.size(of: row.item.path))|"
                    + "\(row.item.caveat ?? "（无）")|")
            }
            print("")
        }
    }
}
