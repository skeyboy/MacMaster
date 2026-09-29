import Foundation
import MMCore

/// 扫描范围。设置页的四个开关一一对应，界面改了就真的少扫一类，
/// 而不是"设置里关掉、扫描时照样算进可清理总量"。
public enum CacheScope: String, CaseIterable, Sendable {
    case systemCache
    case appCache
    case logs
    case temp
}

public struct CacheScanScope: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let systemCache = CacheScanScope(rawValue: 1 << 0)
    public static let appCache = CacheScanScope(rawValue: 1 << 1)
    public static let logs = CacheScanScope(rawValue: 1 << 2)
    public static let temp = CacheScanScope(rawValue: 1 << 3)
    public static let all: CacheScanScope = [.systemCache, .appCache, .logs, .temp]

    public func allows(_ scope: CacheScope) -> Bool {
        switch scope {
        case .systemCache: contains(.systemCache)
        case .appCache: contains(.appCache)
        case .logs: contains(.logs)
        case .temp: contains(.temp)
        }
    }
}

public struct CacheCategory: Identifiable, Hashable {
    public let id: String
    public let name: String
    /// 路径摘要，用 ~ 缩写后直接显示在副标题里。
    public let subtitle: String
    public let iconName: String
    public let risk: MMRisk
    public let scope: CacheScope
    /// 支持单层 `*`，用于 ~/Library/Containers/*/Data/Library/Caches 这类通配。
    public let paths: [String]

    public var scannedSize: UInt64
    public var scannedFiles: Int
    public var subItems: [CacheSubItem]
    /// 存在但读不进去的路径。它们不计入总量，界面要单独显示"需要权限"，
    /// 不能静默当成 0——那是把"没扫到"说成"很干净"。
    public var inaccessiblePaths: [String]

    public init(id: String, name: String, subtitle: String, iconName: String,
                risk: MMRisk, scope: CacheScope, paths: [String]) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.iconName = iconName
        self.risk = risk
        self.scope = scope
        self.paths = paths
        self.scannedSize = 0
        self.scannedFiles = 0
        self.subItems = []
        self.inaccessiblePaths = []
    }
}

public struct CacheSubItem: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    /// nil 表示没测出来（无权限或路径已消失），界面显示"测量中"而不是 0 字节。
    public var size: UInt64?
    public var fileCount: Int
    public var isAccessible: Bool

    public init(name: String, path: String, size: UInt64?, fileCount: Int, isAccessible: Bool = true) {
        self.name = name
        self.path = path
        self.size = size
        self.fileCount = fileCount
        self.isAccessible = isAccessible
    }
}

public struct CacheFileEntry: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: UInt64
    public let isDirectory: Bool
}

public struct CacheScanProgress: Sendable {
    public let categoryName: String
    public let categoryIndex: Int
    public let categoryCount: Int
    public let currentPath: String?
    public let processedItems: Int
    /// 当前类别内部的比例，用于把整轮进度平滑到 0~1。
    public let categoryFraction: Double

    public var fraction: Double {
        guard categoryCount > 0 else { return 1 }
        return (Double(categoryIndex) + categoryFraction) / Double(categoryCount)
    }
}

public struct CacheScanReport {
    public let categories: [CacheCategory]
    /// 用户中途取消时为 false：此时"可释放 2.4 GB"只是扫到一半的数，
    /// 界面必须标注不完整，不能按完整结果口吻播报。
    public let isComplete: Bool
    public let duration: TimeInterval
    public let processedItems: Int

    public var totalSize: UInt64 {
        categories.reduce(0) { sum, category in sum + category.scannedSize }
    }

    public var totalFiles: Int {
        categories.reduce(0) { sum, category in sum + category.scannedFiles }
    }

    public var inaccessiblePaths: [String] {
        categories.flatMap(\.inaccessiblePaths)
    }
}

/// 系统给"当前这个登录用户"分配的 per-user 缓存目录，也就是
/// `getconf DARWIN_USER_CACHE_DIR` 的返回值（形如 `/var/folders/ab/xxxx/C/`）。
///
/// 4.1 的可删除类别只挂在这个目录下面：它是唯一一个"既是系统缓存、
/// 又确定属于当前用户"的位置。取不到就什么都别扫——退化成
/// `/private/var/folders/*/*/C` 会把别人的、以及守护账号的同名目录列成
/// "可安全清理"，而那些文件属主不是当前用户，删除注定失败。
///
/// 注意系统返回的是 `/var` 开头的别名路径，枚举回来是 `/private/var`：
/// 一律交给 `CacheScanner.standardize` 的 `resolvingSymlinksInPath` 口径，别处不另拼一套。
public enum DarwinCachePaths {
    public static func userCacheDirectory() -> String? {
        let size = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
        guard size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, size) > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }
}

public actor CacheScanner {
    /// 可注入的"家目录"，让类别路径能在临时目录里整棵树验证。
    private let home: String
    /// `/private/var/folders` 的根。只读类别用它列出守护账号的那批目录。
    private let varRoot: String
    /// 系统级 `/Library`。只读类别用它，单测里换成临时目录才不会量到真机。
    private let systemLibrary: String
    /// 当前用户的 per-user 缓存目录；nil 表示拿不到，4.1 的类别就不声明任何路径。
    private let userCacheRoot: String?

    public init(home: String = NSHomeDirectory(),
                varRoot: String = "/private/var/folders",
                systemLibrary: String = "/Library",
                userCacheRoot: String? = DarwinCachePaths.userCacheDirectory()) {
        self.home = home
        self.varRoot = varRoot
        self.systemLibrary = systemLibrary
        self.userCacheRoot = userCacheRoot
    }

    /// 兼容旧调用点（概览页只要一个总量）。新代码用带进度的 `scan`。
    public func scanAll() async -> [CacheCategory] {
        await scan().categories
    }

    public func scan(scope: CacheScanScope = .all,
                     excludedFolderPaths: [String] = [],
                     shouldContinue: @escaping @Sendable () -> Bool = { true },
                     progress: (@Sendable (CacheScanProgress) -> Void)? = nil) async -> CacheScanReport {
        let started = Date()
        let enabled = Self.categories(home: home, varRoot: varRoot,
                                      systemLibrary: systemLibrary,
                                      userCacheRoot: userCacheRoot)
            .filter { scope.allows($0.scope) }
        let exclusions = excludedFolderPaths.map { Self.standardize($0) }
        // 通配展开每轮只算一次并复用：类别清单的 `claimed` 与逐类别测量用的是同一批路径，
        // 各算一遍会把同一层目录重复列出来。
        let resolvedPaths = enabled.map { category in
            category.paths.flatMap { Self.expand(glob: $0) }
        }
        // 每个类别都声明自己"拥有"哪些绝对路径。父目录扫描时跳过这些子树，
        // 否则 ~/Library/Caches 会把 Safari 缓存算两遍，两个类别相加就大于真实可释放量。
        let claimed: Set<String> = Set(resolvedPaths.flatMap { $0 }.map { Self.standardize($0) })

        var result: [CacheCategory] = []
        var processed = 0
        var complete = true

        for (index, category) in enabled.enumerated() {
            guard shouldContinue() else { complete = false; break }
            let resolved = resolvedPaths[index]
            var filled = category
            var subItems: [CacheSubItem] = []
            var inaccessible: [String] = []
            var totalSize: UInt64 = 0
            var totalFiles = 0

            for (pathIndex, rawPath) in resolved.enumerated() {
                guard shouldContinue() else { complete = false; break }
                let path = Self.standardize(rawPath)
                if Self.isExcluded(path, against: exclusions) { continue }

                progress?(CacheScanProgress(
                    categoryName: category.name,
                    categoryIndex: index,
                    categoryCount: enabled.count,
                    currentPath: path,
                    processedItems: processed,
                    categoryFraction: resolved.isEmpty ? 1 : Double(pathIndex) / Double(resolved.count)
                ))

                // 排除名单和更细粒度的类别都要从父目录里挖掉，
                // 否则"排除 ~/Library/Caches/Google"只挡住了顶层一项。
                let nested = claimed.filter { Self.isStrictDescendant($0, of: path) }
                    + exclusions.filter { Self.isStrictDescendant($0, of: path) }
                let outcome = measureTree(at: path, skipping: Set(nested))
                processed += 1

                guard FileManager.default.fileExists(atPath: path) else { continue }
                if !outcome.isAccessible {
                    inaccessible.append(path)
                    subItems.append(CacheSubItem(
                        name: (path as NSString).lastPathComponent,
                        path: path, size: nil, fileCount: 0, isAccessible: false
                    ))
                    continue
                }
                guard outcome.size > 0 else { continue }
                totalSize += outcome.size
                totalFiles += outcome.fileCount
                subItems.append(CacheSubItem(
                    name: (path as NSString).lastPathComponent,
                    path: path, size: outcome.size, fileCount: outcome.fileCount
                ))
            }

            filled.scannedSize = totalSize
            filled.scannedFiles = totalFiles
            filled.subItems = subItems.sorted { first, second in
                let left = first.size ?? 0
                let right = second.size ?? 0
                if left != right { return left > right }
                return first.path < second.path
            }
            filled.inaccessiblePaths = inaccessible
            result.append(filled)
        }

        progress?(CacheScanProgress(
            categoryName: "", categoryIndex: enabled.count, categoryCount: enabled.count,
            currentPath: nil, processedItems: processed, categoryFraction: 1
        ))
        return CacheScanReport(
            categories: result,
            isComplete: complete,
            duration: Date().timeIntervalSince(started),
            processedItems: processed
        )
    }

    public func scan(category: CacheCategory) async -> CacheCategory {
        let report = await scan(scope: CacheScanScope.single(category.scope))
        return report.categories.first { $0.id == category.id } ?? category
    }

    /// 单层通配展开：`*` 只替换**一层**目录名，多个 `*` 从左到右逐层展开。
    /// （旧实现只处理最左边一个 `*`，剩下的 `*` 会当字面量留在路径里，
    /// 于是 `a/*/*/C` 这类glob 静默匹配不到任何东西。）
    static func expand(glob: String) -> [String] {
        guard glob.contains("*") else { return [glob] }
        let parts = glob.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let star = parts.firstIndex(of: "*") else { return [glob] }
        let parent = parts.prefix(star).joined(separator: "/")
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: parent), includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let suffix = parts[(star + 1)...].joined(separator: "/")
        // 一个 `*` 只代表**一层**目录名，所以剩余部分还要继续展开：
        // /private/var/folders 的 per-user 缓存是 `<2 字符>/<16 字符>/<uid 目录>/com.apple.xxx`，
        // 只展开最左边那个 `*` 会把后面的 `*` 当字面量留在路径里，永远匹配不到任何条目。
        return names
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .flatMap { expand(glob: "\($0.path)/\(suffix)") }
            .sorted()
    }

    private struct TreeOutcome {
        var size: UInt64 = 0
        var fileCount = 0
        var isAccessible = true
    }

    /// 递归统计**实际占用**字节。标称大小会把 APFS 压缩文件算大，
    /// 清理完发现没腾出那么多空间，用户只会认为应用在撒谎。
    private func measureTree(at path: String, skipping: Set<String>) -> TreeOutcome {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return TreeOutcome(isAccessible: true)
        }
        guard isDirectory.boolValue else {
            var outcome = TreeOutcome()
            outcome.size = Self.allocatedBytes(of: url) ?? 0
            outcome.fileCount = 1
            return outcome
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            return TreeOutcome(isAccessible: false)
        }

        let denied = DeniedFlag()
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey,
                                         .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in denied.count += 1; return true }
        ) else {
            return TreeOutcome(isAccessible: false)
        }

        var outcome = TreeOutcome()
        // 用 nextObject 逐条取，不用 for-in：快速枚举会一次预取一批，
        // skipDescendants() 对已经在批次里的条目不生效，嵌套类别就又算重了。
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
            ) else {
                denied.count += 1
                continue
            }
            // 只有目录才可能是被挖走的子树，符号链接解析只花在这一层。
            if values.isDirectory == true {
                if skipping.contains(Self.standardize(fileURL.path)) {
                    enumerator.skipDescendants()
                }
                continue
            }
            outcome.size += Self.allocatedBytes(values: values) ?? 0
            outcome.fileCount += 1
        }
        // 整棵树一个文件都没读到、且确实报过错，才算无权限；
        // 只是空目录不该吓用户。
        if outcome.fileCount == 0, denied.count > 0 {
            outcome.isAccessible = false
        }
        return outcome
    }

    private final class DeniedFlag {
        var count = 0
    }

    public func listChildren(path: String) -> [CacheFileEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [CacheFileEntry] = []
        for url in contents {
            guard let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            ) else { continue }
            let isDir = values.isDirectory == true
            let size: UInt64 = isDir
                ? (SystemSampler.directoryBytes(url.path) ?? 0)
                : (Self.allocatedBytes(values: values) ?? 0)
            entries.append(CacheFileEntry(
                name: url.lastPathComponent, path: url.path, size: size, isDirectory: isDir
            ))
        }
        return entries.sorted { first, second in
            if first.isDirectory != second.isDirectory { return first.isDirectory }
            return first.size > second.size
        }
    }

    // MARK: - 路径工具

    private static func standardize(_ path: String) -> String {
        // 必须解析符号链接：/var 下的枚举结果由系统返回成 /private/var，
        // 字面标准化后的路径和它对不上，跳过子树就会静默失效（重复计数）。
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .resolvingSymlinksInPath().path
    }

    private static func isStrictDescendant(_ candidate: String, of parent: String) -> Bool {
        candidate.count > parent.count && candidate.hasPrefix(parent + "/")
    }

    private static func isExcluded(_ path: String, against exclusions: [String]) -> Bool {
        exclusions.contains { exclusion in
            path == exclusion || isStrictDescendant(path, of: exclusion)
        }
    }

    private static func allocatedBytes(of url: URL) -> UInt64? {
        guard let values = try? url.resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        ) else { return nil }
        return allocatedBytes(values: values)
    }

    private static func allocatedBytes(values: URLResourceValues) -> UInt64? {
        guard let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize else {
            return UInt64(values.fileSize ?? 0)
        }
        return UInt64(allocated)
    }

    // MARK: - 类别清单

    /// 类别清单的**不变量**：同一个绝对路径只能被一个类别计入。
    /// 新增类别时必须检查它是否与已有类别的路径互为祖先/后代（扫描时靠 `claimed`
    /// 集合挖子树来保证不重复计数），否则界面上的"可释放 X GB"就会虚高。
    static func categories(home: String,
                           varRoot: String = "/private/var/folders",
                           systemLibrary: String = "/Library",
                           userCacheRoot: String? = nil) -> [CacheCategory] {
        // 拿不到当前用户的 per-user 缓存目录时，4.1 的四个类别声明空路径：
        // 空路径不计量、不进默认可选，也不会误扫到别人的 bucket。
        let userCache = userCacheRoot.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        func perUser(_ names: [String]) -> [String] {
            guard let userCache else { return [] }
            return names.map { "\(userCache)/\($0)" }
        }
        // 每个 GUI 应用在这个缓存目录里都有自己的 bucket，里面可能再放一份
        // 自己编译的着色器库。`*` 只代表一层目录名，展开后按应用逐个成条目。
        func perUserNested(_ names: [String]) -> [String] {
            guard let userCache else { return [] }
            return names.map { "\(userCache)/*/\($0)" }
        }
        return [
            CacheCategory(
                id: "system_cache", name: "系统缓存",
                subtitle: "~/Library/Caches · 不含下方单列的类别",
                iconName: "internaldrive", risk: .safe, scope: .systemCache,
                paths: ["\(home)/Library/Caches"]
            ),
            CacheCategory(
                id: "thumbnail_cache", name: "缩略图与预览缓存",
                subtitle: "QuickLook · IconServices · Help",
                iconName: "photo", risk: .safe, scope: .systemCache,
                paths: [
                    "\(home)/Library/Caches/com.apple.helpd",
                    "\(home)/Library/Caches/com.apple.iconservices.store",
                    "\(home)/Library/Caches/com.apple.QuickLook",
                ]
            ),
            CacheCategory(
                id: "trash", name: "废纸篓",
                subtitle: "~/.Trash",
                iconName: "trash", risk: .safe, scope: .systemCache,
                paths: ["\(home)/.Trash"]
            ),

            // MARK: 非显性系统缓存（4.1：当前用户的 per-user 缓存目录）
            //
            // 这些目录 Finder 与「关于本机」都不显示，但 Apple Silicon 上 Metal 着色器库
            // 常年能吃到 GB 级。叶子名一律用**精确目录名**，不用前缀通配，
            // 免得扫进同层的用户状态目录；每个应用自己那份（`<bucket>/<bundle id>/com.apple.metalfe`）
            // 用一层 `*` 单独展开，它和上面那份不是祖先/后代关系，不会重复计数。
            CacheCategory(
                id: "var_metal_cache", name: "GPU 与 Metal 着色器缓存",
                subtitle: "系统缓存目录 · metalfe · gpuarchiver",
                iconName: "memorychip", risk: .safe, scope: .systemCache,
                paths: perUser([
                    "com.apple.metalfe",
                    "com.apple.gpuarchiver",
                    "com.apple.opencl",
                ]) + perUserNested(["com.apple.metalfe", "com.apple.gpuarchiver"])
            ),
            CacheCategory(
                id: "var_icon_preview_cache", name: "QuickLook 与图标服务缓存",
                subtitle: "系统缓存目录 · QuickLook · iconservices · helpd",
                iconName: "photo.stack", risk: .safe, scope: .systemCache,
                paths: perUser([
                    "com.apple.QuickLook.thumbnailcache",
                    "com.apple.QuickLookUIFramework.QLPreviewGenerationExtension",
                    "com.apple.quicklook.QuickLookUIService",
                    "com.apple.iconservices",
                    "com.apple.iconservicesagent",
                    "com.apple.helpd",
                ])
            ),
            CacheCategory(
                id: "var_geo_cache", name: "地图瓦片缓存",
                subtitle: "系统缓存目录 · GeoServices · 清理后需重新联网下载",
                iconName: "map", risk: .caution, scope: .systemCache,
                paths: perUser([
                    "com.apple.GEO",
                    "com.apple.geod",
                ])
            ),
            CacheCategory(
                id: "var_photo_analysis_cache", name: "照片分析与视觉搜索缓存",
                subtitle: "系统缓存目录 · photoanalysisd · 清理后会重新分析",
                iconName: "photo.on.rectangle.angled", risk: .caution, scope: .systemCache,
                paths: perUser([
                    "com.apple.photoanalysisd",
                ])
            ),
            CacheCategory(
                id: "logs", name: "应用日志",
                subtitle: "~/Library/Logs",
                iconName: "doc.text", risk: .safe, scope: .logs,
                paths: ["\(home)/Library/Logs"]
            ),
            CacheCategory(
                id: "crash_reports", name: "崩溃与诊断报告",
                subtitle: "~/Library/Logs/DiagnosticReports · /Library/Logs/DiagnosticReports",
                iconName: "exclamationmark.triangle", risk: .safe, scope: .logs,
                paths: [
                    "\(home)/Library/Logs/DiagnosticReports",
                    "/Library/Logs/DiagnosticReports",
                ]
            ),
            CacheCategory(
                id: "temp_files", name: "临时文件",
                subtitle: "/tmp · 系统临时目录",
                iconName: "clock.arrow.circlepath", risk: .safe, scope: .temp,
                paths: ["/tmp", NSTemporaryDirectory()]
            ),
            CacheCategory(
                id: "browser_cache", name: "浏览器缓存",
                subtitle: "Safari · Chrome · Edge · Brave — 不含历史与 Cookie",
                iconName: "globe", risk: .caution, scope: .appCache,
                paths: [
                    "\(home)/Library/Caches/com.apple.Safari",
                    "\(home)/Library/Caches/Google/Chrome",
                    "\(home)/Library/Caches/com.microsoft.edgemac",
                    "\(home)/Library/Caches/com.brave.Browser",
                ]
            ),
            CacheCategory(
                id: "dev_cache", name: "开发工具缓存",
                // 交叉引用不是装饰：这一屏说"删了它"，「系统优化 → 开发工具」说
                // "这几处该由 owner 自己清"。两处口径必须互相指得过去。
                // 长度要克制：MMItemRow 的副标题是 lineLimit(1) + 中间截断，
                // 写长了被截掉的正好是后半句，等于没写。
                subtitle: "DerivedData · npm · pip · Go build · Homebrew · 另有工具自带的清理命令",
                iconName: "hammer", risk: .caution, scope: .appCache,
                paths: [
                    "\(home)/Library/Developer/Xcode/DerivedData",
                    "\(home)/Library/Developer/CoreSimulator/Caches",
                    "\(home)/.npm/_cacache",
                    "\(home)/Library/Caches/pip",
                    "\(home)/Library/Caches/go-build",
                    "\(home)/Library/Caches/Homebrew",
                ]
            ),
            CacheCategory(
                id: "sandbox_container_cache", name: "沙盒容器缓存",
                subtitle: "~/Library/Containers/*/Data/Library/Caches",
                iconName: "shippingbox", risk: .caution, scope: .appCache,
                // 只取容器里的 `Data/Library/Caches`，不碰容器根：容器根含用户文档、
                // 登录态与未同步数据，整目录只能是谨慎档。`*` 按容器逐个展开成条目，
                // 这样用户能看到到底是哪个应用的缓存在占空间。
                paths: ["\(home)/Library/Containers/*/Data/Library/Caches"]
            ),
            CacheCategory(
                id: "mail_cache", name: "邮件附件与预览",
                subtitle: "~/Library/Mail · 需要完全磁盘访问",
                iconName: "envelope", risk: .caution, scope: .appCache,
                paths: ["\(home)/Library/Mail", "\(home)/Library/Caches/com.apple.mail"]
            ),
            // 需要 root 的两处一律只读：/Library/Caches 里是系统守护进程与其它用户的缓存，
            // /private/var/folders/zz 是 _windowserver 等守护账号的 per-user 目录。
            // 界面不给删除入口，也不进默认可选清单。
            CacheCategory(
                id: "privileged_cache", name: "系统级缓存（需管理员权限）",
                subtitle: "/Library/Caches · /private/var/folders 守护账号目录 · 仅供查看",
                iconName: "lock.folder", risk: .readOnly, scope: .systemCache,
                paths: ["\(systemLibrary)/Caches", "\(varRoot)/zz"]
            ),
            CacheCategory(
                id: "system_logs", name: "系统日志",
                subtitle: "/var/log · /Library/Logs · SIP 保护",
                iconName: "lock.doc", risk: .readOnly, scope: .logs,
                paths: ["/var/log", "/Library/Logs"]
            ),
        ]
    }
}

extension CacheScanScope {
    static func single(_ scope: CacheScope) -> CacheScanScope {
        switch scope {
        case .systemCache: .systemCache
        case .appCache: .appCache
        case .logs: .logs
        case .temp: .temp
        }
    }
}
