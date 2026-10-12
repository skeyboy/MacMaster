import Foundation
import Darwin
import MMCore

// MARK: - 残留扫描引擎
//
// 这里替换的是旧写法"探测 11 个固定候选路径"：固定清单只能覆盖缓存/偏好这几类，
// 沙盒容器、Group Containers、启动项全部漏掉；应用把数据放在厂商子目录里也找不到。
// 新引擎 = 目录清单（哪些 Library 子目录可以枚举）× 归一化名称匹配（怎么判定属于这个 app）
// × 敏感度三档（放到多宽、下探多深）。
//
// 许可说明：清单与分档的思路参考了 Pearcleaner（GPLv3），此处为独立实现，未复制其代码。

// MARK: - 敏感度

/// 匹配宽度分三档，默认 strict：宁可漏报，也不误删别的应用的数据。
public enum ResidualSensitivity: String, CaseIterable, Sendable {
    /// 只接受"名称完全对应"或"包名前缀"，且只看目录的直接子项。
    case strict
    /// 在 strict 之外，接受名称包含匹配，并多下探一层厂商目录。
    case enhanced
    /// 在 enhanced 之外，再纳入 WebKit / Application Scripts / Cookies，并多下探两层。
    case deep

    public var label: String {
        switch self {
        case .strict: "严格"
        case .enhanced: "增强"
        case .deep: "深度"
        }
    }

    public var note: String {
        switch self {
        case .strict: "只按包名与完整名称匹配，最不容易误删"
        case .enhanced: "额外接受包含匹配，并进入厂商子目录一层"
        case .deep: "多层递归，命中最多，但每条都要自己看过"
        }
    }

    var rank: Int {
        switch self {
        case .strict: 0
        case .enhanced: 1
        case .deep: 2
        }
    }
}

/// 取证钩子 `MM_UNINSTALL_SENSITIVITY` 的档位协议。档位名就是这三个 rawValue，
/// 界面上「敏感度」选择器读的也是同一个值——钩子与 UI 不存在两套档位，
/// 所以照片里那一档说什么，选择器上就是什么。
/// P32a §5.5 记的取证缺口就在这儿：在那之前，"增强/深度两档到不到得了某一层目录"
/// 只有代码推导、没有照片可拍。
extension ResidualSensitivity: MMHookKeyed {
    public var hookKey: String { rawValue }
}

// MARK: - 类别

/// 残留的来源类别。类别决定默认风险档，也决定 UI 的分组文案与图标。
public enum ResidualCategory: String, CaseIterable, Sendable {
    case cache
    case applicationSupport
    case preference
    case savedState
    case log
    case httpStorage
    case webKit
    case cookie
    case applicationScript
    case container
    case containerCache
    case groupContainer
    case launchService

    public var title: String {
        switch self {
        case .cache: "缓存"
        case .applicationSupport: "应用数据"
        case .preference: "偏好设置"
        case .savedState: "窗口状态"
        case .log: "日志"
        case .httpStorage: "网络存储"
        case .webKit: "WebKit 数据"
        case .cookie: "Cookie"
        case .applicationScript: "自动化脚本"
        case .container: "沙盒容器"
        case .containerCache: "容器内缓存"
        case .groupContainer: "共享容器"
        case .launchService: "启动项"
        }
    }

    /// 该类别的默认风险档。容器整目录与启动项一律谨慎：它们要么含用户文档，
    /// 要么影响自启动；只有其中可重建的子目录才是默认可选。
    public var defaultRisk: MMRisk {
        switch self {
        case .cache, .savedState, .log, .httpStorage, .webKit, .containerCache:
            return .safe
        case .applicationSupport, .preference, .cookie, .applicationScript,
             .container, .groupContainer, .launchService:
            return .caution
        }
    }

    /// 设计稿每行右侧那句"为什么算它"的短说明，类别级默认值，命中证据可覆盖。
    public var note: String {
        switch self {
        case .cache, .containerCache: "缓存，可重建"
        case .applicationSupport: "可能含账号与下载状态"
        case .preference: "偏好设置"
        case .savedState: "窗口状态，可重建"
        case .log: "日志"
        case .httpStorage: "网络存储，可能含登录态"
        case .webKit: "WebKit 数据，可重建"
        case .cookie: "Cookie，属个人数据"
        case .applicationScript: "自动化脚本"
        case .container: "沙盒容器，可能含文档"
        case .groupContainer: "共享容器，可能被其他应用使用"
        case .launchService: "影响自启动，通常需 root"
        }
    }

    public var icon: String {
        switch self {
        case .cache: "doc.on.doc"
        case .applicationSupport: "shippingbox"
        case .preference: "slider.horizontal.3"
        case .savedState: "macwindow"
        case .log: "doc.text"
        case .httpStorage: "network"
        case .webKit: "globe"
        case .cookie: "cookie"
        case .applicationScript: "applescript"
        case .container, .containerCache: "cube.box"
        case .groupContainer: "square.stack.3d.up"
        case .launchService: "power"
        }
    }
}

// MARK: - 匹配到的残留

public struct ResidualItem: Identifiable, Hashable, Sendable {
    /// 去重主键是"解析符号链接后的绝对路径"，不是展示字符串：
    /// 同一文件被两条规则命中时必须在求和之前塌成一项，否则"可回收总量"会虚增。
    public let id: String
    public let path: String
    /// 展示用的 `~` 缩写形式。
    public let displayPath: String
    public let name: String
    public let category: ResidualCategory
    public let risk: MMRisk
    /// 命中证据，逐条展示给用户判断"这真是这个应用的吗"。
    public let reason: String
    /// 这一行自己的一句提醒，显示在行下方而不是挤进副标题：副标题只有一行且中间省略，
    /// 装不下"路径 + 证据 + 提醒"三样东西（判据见 `SteamGameLibraryCaveat.note`）。
    public let caveat: String?
    public var size: UInt64?

    init(id: String, path: String, displayPath: String, name: String,
         category: ResidualCategory, risk: MMRisk, reason: String, size: UInt64? = nil,
         caveat: String? = nil) {
        self.id = id
        self.path = path
        self.displayPath = displayPath
        self.name = name
        self.category = category
        self.risk = risk
        self.reason = reason
        self.caveat = caveat
        self.size = size
    }

    public static func == (lhs: ResidualItem, rhs: ResidualItem) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 目录清单

/// 清单只列出"允许枚举的 Library 子目录"，每一项自带敏感度门槛与下探层数。
///
/// 红线（任何一档都不进默认清单）：
/// `/Library/Extensions`（内核扩展）、`/usr/local/*`（Homebrew 等工具链的所有权不属于卸载器）、
/// `/private/var/db/receipts`（安装包账本）。
/// 同理 `/Library/PrivilegedHelperTools`、`/Library/Apple` 与一切 `com.apple.*` 也不列入。
enum ResidualCatalog {

    /// 一个清单条目的遍历语义。
    enum Scope {
        /// 通用：枚举该目录的子项并按名称匹配。
        case generic
        /// 容器：交给 `ContainerScanner` 走元数据反查（容器名不等于包名）。
        case containers
    }

    struct Entry {
        let subpath: String
        let category: ResidualCategory
        let minSensitivity: ResidualSensitivity
        /// 额外下探层数（0 只看直接子项）。敏感度越高，层数越多。
        let extraDescent: Int
        let scope: Scope
        /// 更宽的"名称包含应用名"规则是否对该条目开放。共享容器与厂商子目录形态需要它。
        let allowsContains: Bool

        init(subpath: String, category: ResidualCategory, minSensitivity: ResidualSensitivity,
             extraDescent: Int = 0, scope: Scope = .generic, allowsContains: Bool = false) {
            self.subpath = subpath
            self.category = category
            self.minSensitivity = minSensitivity
            self.extraDescent = extraDescent
            self.scope = scope
            self.allowsContains = allowsContains
        }
    }

    static let userEntries: [Entry] = [
        Entry(subpath: "Caches", category: .cache, minSensitivity: .strict),
        Entry(subpath: "Preferences", category: .preference, minSensitivity: .strict),
        Entry(subpath: "Application Support", category: .applicationSupport, minSensitivity: .strict),
        Entry(subpath: "Saved Application State", category: .savedState, minSensitivity: .strict),
        Entry(subpath: "Logs", category: .log, minSensitivity: .strict),
        Entry(subpath: "HTTPStorages", category: .httpStorage, minSensitivity: .strict),
        // 容器与共享容器名常是随机标识，必须读元数据反查，不能靠目录名硬猜。
        Entry(subpath: "Containers", category: .container, minSensitivity: .strict, scope: .containers),
        Entry(subpath: "Group Containers", category: .groupContainer, minSensitivity: .strict,
              scope: .containers, allowsContains: true),
        Entry(subpath: "WebKit", category: .webKit, minSensitivity: .enhanced),
        // Library 根：命中"厂商目录里放应用数据"的形态（~/Library/<Vendor>/MyApp）。
        Entry(subpath: "", category: .applicationSupport, minSensitivity: .enhanced,
              extraDescent: 1, allowsContains: true),
        Entry(subpath: "Application Scripts", category: .applicationScript, minSensitivity: .deep),
        Entry(subpath: "Cookies", category: .cookie, minSensitivity: .deep),
    ]

    /// 系统域只收这几类：偏好、缓存、系统级 Application Support 与日志。
    /// `/Library/Extensions`、`/Library/PrivilegedHelperTools` 一律不列。
    static let systemEntries: [Entry] = [
        Entry(subpath: "Preferences", category: .preference, minSensitivity: .strict),
        Entry(subpath: "Caches", category: .cache, minSensitivity: .enhanced),
        Entry(subpath: "Application Support", category: .applicationSupport, minSensitivity: .enhanced),
        Entry(subpath: "Logs", category: .log, minSensitivity: .deep),
    ]

    /// 容器里"默认可选"的子路径：只有可重建的缓存类，绝不包含用户文档。
    static let containerCacheSubpaths: [String] = [
        "Data/Library/Caches",
        "Data/Library/Saved Application State",
    ]

    /// 敏感度决定下探层数：strict 只看直接子项，enhanced 多一层，deep 多两层。
    static func descentLimit(for sensitivity: ResidualSensitivity, entry: Entry) -> Int {
        sensitivity.rank + entry.extraDescent
    }

    /// Library 根目录下的"已知用途目录"名单。Library 根那条清单条目做厂商目录下探时
    /// 必须跳过它们：这些要么已由专属条目按正确类别处理（重复处理会让同一绝对路径
    /// 以两个类别各计一次），要么是 Apple 自己的数据（Mail / Keychains / Developer …），
    /// 不该由"名称包含应用名"这种宽规则碰到。
    static let standardLibrarySubdirectoryNames: Set<String> = Set([
        "Application Scripts", "Application Support", "Assets", "Audio", "Automator",
        "Calendars", "Caches", "ColorPickers", "ColorSync", "Components", "Compositions",
        "Containers", "CoreImage", "Data Sources", "Desktop Pictures", "Dictionaries",
        "Extensions", "Favorites", "Filters", "Fonts", "FrameworkResources",
        "Group Containers", "HTTPStorages", "Images", "Input Methods", "Internet Plug-Ins",
        "Keychains", "LaunchAgents", "LaunchDaemons", "Localization", "Mail", "Messages",
        "MIS", "Preferences", "PreferencePanes", "Printers", "PrivilegedHelperTools",
        "QuickLook", "Safari", "Saved Application State", "Screen Savers", "Services",
        "Sounds", "Spelling", "Spotlight", "Stickers", "SyncServer", "Teachments",
        "WebKit", "Widgets",
    ])

    /// 清单的绝对路径（容器类条目由此取到目录）。
    static func libraryRoots(home: String, systemRoot: String) -> [(library: String, entries: [Entry])] {
        let options = ResidualScanOptions(home: home, systemRoot: systemRoot)
        var roots: [(String, [Entry])] = [(options.userLibrary, userEntries)]
        if let systemLibrary = options.systemLibrary {
            roots.append((systemLibrary, systemEntries))
        }
        return roots
    }
}

// MARK: - 扫描参数

public struct ResidualScanOptions: Sendable {
    /// 可注入的 home：单元测试一律传临时目录，绝不触碰真实用户文件。
    public var home: String
    /// 系统域根（真实机型是 "/"，即 `/Library` 的父目录）。测试注入假目录即可完整覆盖系统域。
    public var systemRoot: String
    /// 仅作为孤儿归属线索读取，不进入残留候选或删除清单。
    public var receiptsRoot: String?
    public var sensitivity: ResidualSensitivity
    /// 本机其它已安装应用的身份，用于「归属复核」（两条线索：这一项本身、它的上层目录；
    /// 判据见 `ResidualOwnershipReview`）。
    /// 空数组 = 不复核，命中项的风险档完全由类别决定（旧行为，也是单测的默认）。
    /// 调用方给整张清单即可：引擎自己剔除"待扫描的那一个"，不需要在传之前过滤。
    public var foreignApps: [InstalledAppIdentity]

    public init(home: String? = nil, systemRoot: String? = nil, receiptsRoot: String? = nil,
                sensitivity: ResidualSensitivity = .strict,
                foreignApps: [InstalledAppIdentity] = []) {
        self.home = Self.normalizeHome(home ?? NSHomeDirectory())
        // 默认不扫系统域：真实机型的 /Library 需要 root 才读得动，
        // 而启动项那一路已在 `LaunchServiceScanner` 显式覆盖两个域。
        self.systemRoot = systemRoot ?? ""
        self.receiptsRoot = receiptsRoot
        self.sensitivity = sensitivity
        self.foreignApps = foreignApps
    }

    static func normalizeHome(_ value: String) -> String {
        if value == "/" { return value }
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    var userLibrary: String { "\(home)/Library" }

    /// 系统域的 Library 目录。`systemRoot` 传 "/" 时不能拼出 `//Library`，
    /// 那是 POSIX 里可能被实现单独解释的形式，也会让路径前缀比较失配。
    var systemLibrary: String? {
        guard systemRoot.isEmpty == false else { return nil }
        let base = systemRoot == "/" ? "" : systemRoot
        return "\(base)/Library"
    }
}

// MARK: - 大小度量

/// 扫描在后台线程同步进行，`DirectoryMetrics`（async）在这里用不上，
/// 因此单独给一个同步口径：目录累加子项占用块数，文件取 lstat 的 st_blocks。
public protocol ResidualSizeMeasuring: Sendable {
    static func size(of path: String) -> UInt64
}

public enum DirectoryResidualSizeMeasurer: ResidualSizeMeasuring {
    public static func size(of path: String) -> UInt64 {
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { return 0 }
        if (info.st_mode & S_IFMT) == S_IFDIR {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: nil,
                options: [],
                errorHandler: { _, _ in true }
            ) else { return UInt64(max(0, info.st_blocks)) * 512 }

            var total: UInt64 = 0
            // 必须 while nextObject()：for-in 的批量预取会让 skipDescendants() 失效。
            while let child = enumerator.nextObject() as? URL {
                var childInfo = stat()
                guard Darwin.lstat(child.path, &childInfo) == 0 else { continue }
                if (childInfo.st_mode & S_IFDIR) != S_IFDIR {
                    total += UInt64(max(0, childInfo.st_blocks)) * 512
                }
            }
            return total
        }
        return UInt64(max(0, info.st_blocks)) * 512
    }
}

// MARK: - 扫描结果

public struct ResidualScanReport: Sendable {
    public let items: [ResidualItem]
    /// 扫描期间读不动的目录（TCC 拒绝等）。必须可见，不能假装什么都没发生。
    public let inaccessiblePaths: [String]

    init(items: [ResidualItem], inaccessiblePaths: [String]) {
        self.items = items
        self.inaccessiblePaths = inaccessiblePaths
    }

    public func items(in category: ResidualCategory) -> [ResidualItem] {
        items.filter { $0.category == category }
    }

    /// 按风险档分组，组序固定 safe → caution → readOnly，对应 `MMRisk.groupTitle/groupNote`。
    public var riskGroups: [(risk: MMRisk, items: [ResidualItem])] {
        MMRisk.allCases.compactMap { risk in
            let group = items.filter { $0.risk == risk }
            return group.isEmpty ? nil : (risk, group)
        }
    }

    /// 默认可选项的总大小。两步保证不重复计数：
    /// 1) 按 id（规范绝对路径）聚合，同一绝对路径被两个类别命中也只算一次；
    /// 2) 目录大小本身就是子项之和，父目录与子目录同时入选会各算一遍，
    ///    所以只在"互不嵌套的删除根"上求和。
    public var defaultSelectableSize: UInt64 {
        let sizes = Self.aggregate(items.filter { $0.risk.isDefaultSelected })
        return Self.nonNestedIDs(Array(sizes.keys)).reduce(UInt64(0)) { $0 + (sizes[$1] ?? 0) }
    }

    public var defaultSelectableCount: Int {
        Self.nonNestedIDs(Set(items.filter { $0.risk.isDefaultSelected }.map(\.id)).sorted()).count
    }

    /// 默认可选且互不嵌套的删除根路径。删除列表用它，
    /// 否则"容器整目录"与"容器内缓存"会把同一段字节数报两次。
    public var defaultDeletionRoots: [String] {
        let byID = Dictionary(grouping: items.filter { $0.risk.isDefaultSelected }, by: \.id)
        return Self.nonNestedIDs(Array(byID.keys)).compactMap { id in
            byID[id]?.first?.path
        }
    }

    /// 实际要移到废纸篓的路径：勾选的项去掉已被勾选父目录覆盖的子项。
    public func deletionRoots(for selectedIDs: Set<String>) -> [String] {
        let byID = Dictionary(grouping: items.filter {
            $0.risk.allowsDeletion && selectedIDs.contains($0.id)
        }, by: \.id)
        return Self.nonNestedIDs(Array(byID.keys)).compactMap { id in byID[id]?.first?.path }
    }

    public func selectedSize(for selectedIDs: Set<String>) -> UInt64? {
        let grouped = Dictionary(grouping: items.filter {
            $0.risk.allowsDeletion && selectedIDs.contains($0.id)
        }, by: \.id)
        var total: UInt64 = 0
        for id in Self.nonNestedIDs(Array(grouped.keys)) {
            guard let size = grouped[id]?.compactMap(\.size).max() else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(size)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }

    private static func aggregate(_ subset: [ResidualItem]) -> [String: UInt64] {
        var sizes: [String: UInt64] = [:]
        for item in subset {
            sizes[item.id] = max(sizes[item.id] ?? 0, item.size ?? 0)
        }
        return sizes
    }

    /// 只保留最浅一层：某个路径的祖先已经在集合里时它就不必再出现。
    /// 比较对象一律是 `canonicalPath`，所以符号链接与 `/var`↔`/private/var` 不会各算一次。
    static func nonNestedIDs(_ ids: [String]) -> [String] {
        let sorted = ids.sorted { depth($0) < depth($1) }
        var kept: [String] = []
        for id in sorted {
            if kept.contains(where: { id.hasPrefix($0 + "/") }) == false {
                kept.append(id)
            }
        }
        return kept
    }

    private static func depth(_ path: String) -> Int {
        path.split(separator: "/").count
    }

    public var groupedByCategory: [(category: ResidualCategory, items: [ResidualItem])] {
        ResidualCategory.allCases.compactMap { category in
            let group = items.filter { $0.category == category }
            return group.isEmpty ? nil : (category, group)
        }
    }
}

// MARK: - 引擎

/// 残留扫描引擎。全部同步、只读、home 可注入，因此在临时目录里可以完整测试。
public enum ResidualScanner {

    public static func scan(appName: String,
                            bundleID: String,
                            appPath: String,
                            options: ResidualScanOptions,
                            measure: ((String) -> UInt64)? = nil) -> ResidualScanReport {
        let context = ResidualScanContext(
            options: options,
            bundleID: bundleID,
            matcher: ResidualNameMatcher(appName: appName, bundleID: bundleID)
        )
        var collector = ResidualCollector(home: options.home,
                                          measure: measure ?? DirectoryResidualSizeMeasurer.size(of:),
                                          ownership: ownershipReview(for: options, appName: appName,
                                                                     bundleID: bundleID))

        scanCatalogs(context: context, collector: &collector)
        ContainerScanner.scan(context: context, collector: &collector)
        LaunchServiceScanner.scan(context: context, appPath: appPath, collector: &collector)

        return ResidualScanReport(items: collector.items(), inaccessiblePaths: collector.inaccessiblePaths)
    }

    /// 归属复核用的身份：清单里剔除"待扫描的这一个"之后才有意义——
    /// 自己主张自己的上层目录是常态（`Foo.app` 的 `~/Library/Caches/Foobar/baz-foo`），
    /// 把它算进主人名单，就会把自己每一层嵌套的弱证据项都降成谨慎。
    /// 剔除按两条独立线索分别比：包名（相等）与归一化后的名称（相等），
    /// 因为废纸篓那一路传进来的 name 可能是显示名而不是目录名。
    ///
    /// 这一层是 internal 而不是 private：端到端拿不到"自己主张上层目录而子项仍被收进来"的形状
    /// （自己一主张那一层，`enumerate` 就收下它并 `continue`，下探根本到不了子项），
    /// 所以剔除逻辑由 `ResidualOwnershipReviewTests` 在这个函数上直接钉。
    static func ownershipReview(for options: ResidualScanOptions,
                                appName: String,
                                bundleID: String) -> ResidualOwnershipReview? {
        let normalizedSelf = ResidualNameMatcher.normalize(appName)
        let trimmedID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let foreign = options.foreignApps.compactMap { identity -> (name: String, matcher: ResidualNameMatcher)? in
            let id = identity.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmedID.isEmpty == false, id == trimmedID { return nil }
            if ResidualNameMatcher.normalize(identity.name) == normalizedSelf { return nil }
            return (identity.name, ResidualNameMatcher(appName: identity.name, bundleID: identity.bundleID))
        }
        guard foreign.isEmpty == false else { return nil }
        return ResidualOwnershipReview(home: options.home, appName: appName, foreign: foreign)
    }

    struct ResidualScanContext {
        let options: ResidualScanOptions
        let bundleID: String
        let matcher: ResidualNameMatcher

        var sensitivity: ResidualSensitivity { options.sensitivity }
    }

    // MARK: 目录清单遍历

    private static func scanCatalogs(context: ResidualScanContext, collector: inout ResidualCollector) {
        for (library, entries) in ResidualCatalog.libraryRoots(
            home: context.options.home, systemRoot: context.options.systemRoot
        ) {
            // Library 根那一条只做"厂商目录"下探，已经在清单里单列的子目录要排除，
            // 否则同一个命中会以两种语义（正确类别 / 误标成应用数据）各进一次收集器。
            let alreadyCovered = Set(
                entries.filter { $0.subpath.isEmpty == false && $0.scope == .generic }.map(\.subpath)
            )
            for entry in entries where context.sensitivity.rank >= entry.minSensitivity.rank {
                // 容器类条目由 ContainerScanner 走元数据反查，这里不重复处理。
                guard entry.scope == .generic else { continue }
                let root = URL(fileURLWithPath: entry.subpath.isEmpty ? library : "\(library)/\(entry.subpath)",
                               isDirectory: true)
                enumerate(root: root, entry: entry, excludedNames: alreadyCovered,
                          context: context, collector: &collector)
            }
        }
    }

    private static func enumerate(root: URL,
                                  entry: ResidualCatalog.Entry,
                                  excludedNames: Set<String>,
                                  context: ResidualScanContext,
                                  collector: inout ResidualCollector) {
        guard let children = listChildren(of: root, collector: &collector) else { return }
        let descent = ResidualCatalog.descentLimit(for: context.sensitivity, entry: entry)
        let isLibraryRoot = entry.subpath.isEmpty

        for child in children {
            if isLibraryRoot, ResidualCatalog.standardLibrarySubdirectoryNames.contains(child.lastPathComponent) {
                continue
            }
            if isLibraryRoot, excludedNames.contains(child.lastPathComponent) { continue }
            // strict 只接受精确/包名前缀；enhanced 起才接受包含匹配。
            let allowContains = context.sensitivity.rank > ResidualSensitivity.strict.rank
                && (entry.allowsContains || descent > 0)
            if let reason = context.matcher.reason(for: child, bundleID: context.bundleID,
                                                   allowContains: allowContains) {
                collector.add(url: child, category: entry.category, reason: reason)
                continue
            }
            if descent > 0, isLibraryRoot == false || isDirectory(child) {
                descend(child, depth: 1, limit: descent, entry: entry, context: context, collector: &collector)
            }
        }
    }

    /// 下探厂商目录（`~/Library/Application Support/Google/Chrome` 这种形态）：
    /// 父目录不匹配时才进去看一层，逐层用同一个 matcher 复核，绝不整目录收下。
    private static func descend(_ url: URL,
                                depth: Int,
                                limit: Int,
                                entry: ResidualCatalog.Entry,
                                context: ResidualScanContext,
                                collector: inout ResidualCollector) {
        guard depth <= limit, isDirectory(url) else { return }
        guard let children = listChildren(of: url, collector: &collector) else { return }
        for child in children {
            if let reason = context.matcher.reason(for: child, bundleID: context.bundleID, allowContains: true) {
                collector.add(url: child, category: entry.category,
                              reason: "\(reason)（位于 \(url.lastPathComponent) 内）")
                continue
            }
            if depth < limit {
                descend(child, depth: depth + 1, limit: limit, entry: entry,
                        context: context, collector: &collector)
            }
        }
    }

    private static func listChildren(of root: URL, collector: inout ResidualCollector) -> [URL]? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        do {
            return try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
        } catch {
            collector.addInaccessible(root.path)
            return nil
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }
}
