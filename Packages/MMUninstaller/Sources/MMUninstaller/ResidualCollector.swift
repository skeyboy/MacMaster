import Foundation
import Darwin
import MMCore

// MARK: - 候选收集与去重

/// 「归属复核」（P33b B 档）的输入：除本应用以外的已装应用身份。
///
/// 判据只有一条：**这一项的归属证据只有「名称包含应用名」，而别人对它有更强的主张**。
/// 包含匹配说的是"这个名字里带着应用名"，它到不了归属。别人的主张从两个方向来，
/// 由近到远各问一次：
///   · **这一项本身**——另一个已装应用用包名或精确名称在同一路径上主张它
///     （`Caches/AssetsFork` 躺在 Fork 的清单里，而 AssetsFork 给它的是硬证据）；
///   · **它的某个上层目录**——主人是那层目录的应用
///     （`JetBrains/IntelliJIdea2026.2/ts-go-fork-embedded` 就是 IntelliJ 的目录里
///     一个名字带 fork 的子项）。
///
/// 第一条不是补装饰：审计 `docs/analysis/uninstaller-deep-residual-scope.md` §4 记的那个完整形态
/// （`Caches/com.example.steamgame` 被归到 Steam 名下、524 KB、默认勾选）撞的是**同层**，
/// 它的上层只有 `Caches`，谁都不主张——只做祖先那一层的复核对这一族一个字都不会说。
/// `Scripts/p33b-nesting-fixture.sh` 把这一族钉进了夹具。
///
/// 复核**不减少召回**：条目照样出现在清单里，只是不再默认勾选，主人写进行下方那句提醒。
/// 上层目录的主人同样按包含语义找（与扫描同语义）——真主人常常也是靠名称认领自己产品目录的，
/// 要求它给硬证据就等于这条判据永远不成立（P33a 审计 §3：同路径严格主张本机只有 1 条，
/// 补上祖先这一层才抓出默认勾选的那 3 条）。反过来，认领**这一项本身**要的就是硬证据：
/// 弱对弱只是两个人一起猜，不构成主张。
struct ResidualOwnershipReview {
    let home: String
    /// 待复核应用的显示名，只用于提醒文案里"可能不是 X 的数据"那一句。
    let appName: String
    let foreign: [(name: String, matcher: ResidualNameMatcher)]

    /// 另一个已装应用是否用**硬证据**（包名或精确名称）主张这一项本身。
    /// `allowContains: false` 是这一条的整个分量所在：这里要的是"别人给了证据"，
    /// 不是"别人的猜测和我的猜测同名"。
    func hardClaim(on path: String) -> (name: String, evidence: ResidualEvidence)? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        for other in foreign {
            if let evidence = other.matcher.evidence(for: url, bundleID: "", allowContains: false) {
                return (other.name, evidence)
            }
        }
        return nil
    }

    /// 往上逐层问别人"这一层归不归你"，只走到**第一个有主人的**那一层为止：
    /// 更外层的主人由那个主人自己的清单去报。走到 home 或文件系统根就停。
    func foreignOwner(of path: String) -> (name: String, ancestor: String)? {
        var parent = (path as NSString).deletingLastPathComponent
        while parent.count > 1, parent != home {
            for other in foreign {
                let url = URL(fileURLWithPath: parent, isDirectory: true)
                if other.matcher.evidence(for: url, bundleID: "", allowContains: true) != nil {
                    return (other.name, parent)
                }
            }
            parent = (parent as NSString).deletingLastPathComponent
        }
        return nil
    }
}

/// 三个扫描路（目录清单 / 容器反查 / 启动项）都往这里投候选。
/// 收口只做一件事：以"解析符号链接后的绝对路径"为主键合并，
/// 于是 `/var` 与 `/private/var` 这类同一文件的不同写法不会各算一次。
struct ResidualCollector {
    private struct Candidate {
        let path: String
        let displayPath: String
        let name: String
        let category: ResidualCategory
        let risk: MMRisk
        /// 给用户看的那一句，随语言。
        let reason: String
        /// 判据只看这个：`reason` 会跟着界面变，拿它当前缀判就是给自己埋雷。
        let evidenceKind: ResidualEvidenceKind
        let caveat: String?
        let size: UInt64?
    }

    private let home: String
    /// 大小在命中时就量好（同步口径，扫描本身在后台线程）。
    private let measure: (String) -> UInt64
    /// nil = 不做归属复核（旧调用、单测、以及"没传已装清单"的场合）。
    private let ownership: ResidualOwnershipReview?
    private var order: [String] = []
    private var candidates: [String: Candidate] = [:]
    private(set) var inaccessiblePaths: [String] = []

    init(home: String,
         measure: @escaping (String) -> UInt64 = DirectoryResidualSizeMeasurer.size(of:),
         ownership: ResidualOwnershipReview? = nil) {
        self.home = home
        self.measure = measure
        self.ownership = ownership
    }

    /// 同一个路径只保留第一次命中的证据；风险取更保守（更宽）的那一档，
    /// 于是"清单认为安全、容器认为谨慎"不会变成"界面显示安全"。
    mutating func add(url: URL, category: ResidualCategory, evidence: ResidualEvidence, riskOverride: MMRisk? = nil) {
        add(path: url.path, category: category, evidence: evidence, riskOverride: riskOverride)
    }

    mutating func add(path: String, category: ResidualCategory, evidence: ResidualEvidence, riskOverride: MMRisk? = nil) {
        let id = Self.canonicalPath(path)
        let risk = riskOverride ?? resolvedRisk(for: path, category: category)
        guard candidates[id] == nil else {
            if let existing = candidates[id], riskPriority(risk) > riskPriority(existing.risk) {
                candidates[id] = Candidate(path: existing.path, displayPath: existing.displayPath,
                                           name: existing.name, category: existing.category,
                                           risk: risk, reason: existing.reason,
                                           evidenceKind: existing.evidenceKind,
                                           caveat: existing.caveat, size: existing.size)
            }
            return
        }
        candidates[id] = Candidate(
            path: path,
            displayPath: Self.display(path, home: home),
            name: URL(fileURLWithPath: path).lastPathComponent,
            category: category,
            risk: risk,
            reason: evidence.text,
            evidenceKind: evidence.kind,
            caveat: Self.steamGameLibraryCaveat(path: path, category: category),
            size: measure(path)
        )
        order.append(id)
    }

    mutating func addInaccessible(_ path: String) {
        let id = Self.canonicalPath(path)
        guard inaccessiblePaths.contains(id) == false else { return }
        inaccessiblePaths.append(id)
    }

    func items() -> [ResidualItem] {
        order.compactMap { id in
            guard let candidate = candidates[id] else { return nil }
            let reviewed = reviewed(candidate)
            return ResidualItem(
                id: id,
                path: reviewed.path,
                displayPath: reviewed.displayPath,
                name: reviewed.name,
                category: reviewed.category,
                risk: reviewed.risk,
                reason: reviewed.reason,
                size: reviewed.size,
                caveat: reviewed.caveat
            )
        }
        .sorted { lhs, rhs in
            if lhs.risk != rhs.risk { return riskPriority(lhs.risk) > riskPriority(rhs.risk) }
            if lhs.category != rhs.category { return lhs.category.sortIndex < rhs.category.sortIndex }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    // MARK: 归属复核

    /// 「包含匹配 + 别人有更硬的归属主张」这一族在这里定档：默认勾选由 `MMRisk.isDefaultSelected`
    /// 决定，而降级必须发生在建 item 之前（`ResidualItem.risk/caveat` 都是 `let`），
    /// 否则徽章、勾选集、合计三者会各说一套。复核只在出清单时做一次：
    /// 每个唯一路径只看一次，也不看子项。
    private func reviewed(_ candidate: Candidate) -> Candidate {
        guard candidate.risk == .safe,
              candidate.evidenceKind == .nameContains,
              let ownership else { return candidate }
        // 两条线索按"离这一项更近"的顺序问，第一条成立就不问第二条：同一件事不用说两遍。
        // 整句（含"可能不是 X 的数据"）进文案表，不在这里拼接：中英的语序不一样。
        let note: String
        if let hard = ownership.hardClaim(on: candidate.path) {
            note = LF("ui.ownership.self_claim", hard.name, hard.evidence.text, ownership.appName)
        } else if let owner = ownership.foreignOwner(of: candidate.path) {
            note = LF("ui.ownership.ancestor_claim", owner.name,
                      Self.display(owner.ancestor, home: home), ownership.appName)
        } else {
            return candidate
        }
        // 主人的名字进下方那句提醒，不进副标题：副标题只有一行且中间省略，
        // 路径已经占满它（判据 `docs/verification/p32b-steam/11a-narrow-window-truncation-before-fix.png`）。
        // 证据串不动：`Candidate` 的字段是 `let`，重建一条比就地改更直白，
        // 也钉住"复核只动风险档与提醒这两样"。
        // 已经挂着别句提醒的行（Steam 游戏库那一族）不覆盖，两句都留在行下方。
        return Candidate(path: candidate.path, displayPath: candidate.displayPath,
                         name: candidate.name, category: candidate.category,
                         risk: .caution, reason: candidate.reason,
                         evidenceKind: candidate.evidenceKind,
                         caveat: candidate.caveat.map { note + " " + $0 } ?? note,
                         size: candidate.size)
    }

    // MARK: 风险判定

    /// 默认风险来自类别，但"当前用户根本删不掉"必须降级为只读：
    /// 移到废纸篓要的是父目录的写权限，所以检查的是父目录而不是项本身。
    private func resolvedRisk(for path: String, category: ResidualCategory) -> MMRisk {
        let base = category.defaultRisk
        guard base.allowsDeletion else { return base }
        return Self.isDeletableByCurrentUser(path) ? base : .readOnly
    }

    /// root 属主的 `/Library` 项、以及任何父目录不可写的项，普通用户删不掉。
    static func isDeletableByCurrentUser(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        guard parent.isEmpty == false else { return false }
        if access(parent, W_OK) != 0 { return false }
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { return false }
        // 不可变标志（uchg）会让 trashItem 直接失败，显示只读比给一个坏按钮诚实。
        return (info.st_flags & UInt32(UF_IMMUTABLE)) == 0
    }

    // MARK: 这一行自己的提醒

    /// `Application Support` 这一类的行只在候选新建时看一次直接子项：
    /// 命中 `steamapps` 就把"这一行里装的是什么"交给这一行下方那一句话。
    /// 只做一次目录列举、不递归、不数大小——分组那句"可能包含登录态或未同步数据"
    /// 说的是账号，游戏库是另一件事，得由这一行自己说。
    private static func steamGameLibraryCaveat(path: String, category: ResidualCategory) -> String? {
        guard category == .applicationSupport else { return nil }
        let children = try? FileManager.default.contentsOfDirectory(atPath: path)
        return SteamGameLibraryCaveat.note(children: children)
    }

    /// `/var` 与 `/private/var` 是同一个目录的两种写法，不先解析就会静默不等。
    static func canonicalPath(_ path: String) -> String {
        physicalPath(path)
    }

    /// 物理路径，语义与 `realpath(3)` 一致；目标不存在时解析最近的存在祖先再接回尾段。
    ///
    /// 不能用 `URL.resolvingSymlinksInPath()`：Foundation 会把结果里的 `/private/var`
    /// 折成 `/var`，而且**只在目标存在时**才这么做。于是"还在的 app 目录"与
    /// "已经不存在的可执行文件"会拿到两种写法，前缀比较静默失配——
    /// 而卸载场景里 app 常常正是已经被拖进废纸篓了，这条路径必须成立。
    static func physicalPath(_ path: String) -> String {
        guard path.isEmpty == false else { return "" }
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        // 目标不存在：往下找第一个存在的最深祖先解析掉，再把尾段原样接回来。
        // 先做纯词法规范化——它会把相对写法补成绝对路径，于是下面按 "/" 切分时
        // components[0] 必然为空（绝对路径的前导斜杠），下标才不会整体错位一格。
        let lexical = URL(fileURLWithPath: path).standardizedFileURL.path
        let components = lexical.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var cut = components.count
        while cut > 1 {
            cut -= 1
            let prefix = "/" + components[1..<cut].joined(separator: "/")
            if let resolved = realpath(prefix, nil) {
                defer { free(resolved) }
                return String(cString: resolved) + "/" + components[cut...].joined(separator: "/")
            }
        }
        return lexical
    }

    static func display(_ path: String, home: String) -> String {
        if home.isEmpty == false, path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func riskPriority(_ risk: MMRisk) -> Int {
        switch risk {
        case .safe: 2
        case .caution: 1
        case .readOnly: 0
        }
    }
}

extension ResidualCategory {
    /// UI 分组顺序：与 `ResidualCatalog` 的清单顺序一致，避免同一列表每次排法不同。
    var sortIndex: Int { ResidualCategory.allCases.firstIndex(of: self) ?? Int.max }
}
