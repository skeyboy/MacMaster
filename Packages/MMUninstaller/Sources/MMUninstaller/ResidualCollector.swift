import Foundation
import Darwin
import MMCore

// MARK: - 候选收集与去重

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
        let reason: String
        let size: UInt64?
    }

    private let home: String
    /// 大小在命中时就量好（同步口径，扫描本身在后台线程）。
    private let measure: (String) -> UInt64
    private var order: [String] = []
    private var candidates: [String: Candidate] = [:]
    private(set) var inaccessiblePaths: [String] = []

    init(home: String, measure: @escaping (String) -> UInt64 = DirectoryResidualSizeMeasurer.size(of:)) {
        self.home = home
        self.measure = measure
    }

    /// 同一个路径只保留第一次命中的证据；风险取更保守（更宽）的那一档，
    /// 于是"清单认为安全、容器认为谨慎"不会变成"界面显示安全"。
    mutating func add(url: URL, category: ResidualCategory, reason: String, riskOverride: MMRisk? = nil) {
        add(path: url.path, category: category, reason: reason, riskOverride: riskOverride)
    }

    mutating func add(path: String, category: ResidualCategory, reason: String, riskOverride: MMRisk? = nil) {
        let id = Self.canonicalPath(path)
        let risk = riskOverride ?? resolvedRisk(for: path, category: category)
        guard candidates[id] == nil else {
            if let existing = candidates[id], riskPriority(risk) > riskPriority(existing.risk) {
                candidates[id] = Candidate(path: existing.path, displayPath: existing.displayPath,
                                           name: existing.name, category: existing.category,
                                           risk: risk, reason: existing.reason, size: existing.size)
            }
            return
        }
        candidates[id] = Candidate(
            path: path,
            displayPath: Self.display(path, home: home),
            name: URL(fileURLWithPath: path).lastPathComponent,
            category: category,
            risk: risk,
            reason: reason,
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
            return ResidualItem(
                id: id,
                path: candidate.path,
                displayPath: candidate.displayPath,
                name: candidate.name,
                category: candidate.category,
                risk: candidate.risk,
                reason: candidate.reason,
                size: candidate.size
            )
        }
        .sorted { lhs, rhs in
            if lhs.risk != rhs.risk { return riskPriority(lhs.risk) > riskPriority(rhs.risk) }
            if lhs.category != rhs.category { return lhs.category.sortIndex < rhs.category.sortIndex }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
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
