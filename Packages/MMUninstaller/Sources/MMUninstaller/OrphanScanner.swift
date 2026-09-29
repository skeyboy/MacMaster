import Foundation

/// "卸载后遗症"：反着查——磁盘上还有谁的残留，但本机已经装不回那个应用了。
///
/// 正向扫描（`ResidualScanner`）是"给定 app，找它的文件"；这里是它的逆问题，
/// 难点完全不在遍历，而在**什么才算没有主人**：
/// 一个 `~/Library/Caches/com.foo.bar` 被判成孤儿，可能是 bar 真的被删了，
/// 也可能是 bar 装在别的卷上、或者它的 bundle id 和磁盘名压根不同形。
/// 所以这里的规则一律偏保守：宁可漏报，不可错报——漏了用户再扫一遍增强档，
/// 错报则是让他去删一个正在用的应用的缓存。
public struct InstalledAppIdentity: Sendable {
    public let name: String
    public let bundleID: String

    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

public struct OrphanCandidate: Identifiable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let category: ResidualCategory
    /// 归属线索：磁盘上这个名字看起来属于谁。
    public let owner: String
    /// 未测量时为 nil，交给 UI 显示"测量中"，不写 0。
    public var size: UInt64?
}

public enum OrphanScanner {
    /// 名称短于这个长度的条目太容易撞车（"Code"、"Google"），不参与判断。
    static let minNameLength = 10

    /// Apple 自己的标识。这些永远不该出现在孤儿名单里——系统组件的缓存和偏好
    /// 看起来全都"没有对应的已安装应用"，因为应用就在 /System 里。
    static let applePrefixes = ["com-apple"]

    /// 容器目录名常是随机标识，正向要靠元数据反查；反向同理，没有名称可判。
    static func isUUIDLike(_ name: String) -> Bool {
        let layout = [8, 4, 4, 4, 12]
        let parts = name.lowercased().split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == layout.count else { return false }
        return zip(parts, layout).allSatisfy { part, length in
            part.count == length && part.allSatisfy(\.isHexDigit)
        }
    }

    public static func scan(
        installed: [InstalledAppIdentity],
        options: ResidualScanOptions,
        fileManager: FileManager = .default
    ) -> [OrphanCandidate] {
        let owners = OwnerIndex(installed: installed)
        var found: [OrphanCandidate] = []
        var seen = Set<String>()

        for (library, entries) in ResidualCatalog.libraryRoots(
            home: options.home, systemRoot: options.systemRoot
        ) {
            for entry in entries {
                guard entry.minSensitivity.rank <= options.sensitivity.rank,
                      entry.scope == .generic else { continue }
                let root = library.isEmpty ? entry.subpath : "\(library)/\(entry.subpath)"
                guard let children = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
                for child in children {
                    let path = root == "/" ? child : "\(root)/\(child)"
                    guard seen.insert(path).inserted else { continue }
                    guard let candidate = judge(
                        fileName: child, path: path, category: entry.category, against: owners
                    ) else { continue }
                    found.append(candidate)
                }
            }
        }
        return found.sorted { ($0.name) < ($1.name) }
    }

    static func judge(
        fileName: String,
        path: String,
        category: ResidualCategory,
        against owners: OwnerIndex
    ) -> OrphanCandidate? {
        guard fileName.count >= minNameLength, !fileName.hasPrefix(".") else { return nil }
        if isUUIDLike(fileName) { return nil }
        // Library 根那条目录清单会枚举到 Mail、Keychains、Containers 之类，
        // 它们要么有专属条目处理，要么是 Apple 的数据，都不该出现在这里。
        if ResidualCatalog.standardLibrarySubdirectoryNames.contains(fileName) { return nil }

        // 剥掉真扩展名（.plist / .savedState / .shm）；`com.foo.Bar` 的最后一段不是
        // 扩展名，一律 deletingPathExtension() 会把强证据本身削掉。
        let base = fileName.replacingOccurrences(
            of: #"\.(plist|savedState|shm|binarycookies)$"#, with: "", options: .regularExpression
        )
        // 归属线索用剥掉 UUID 尾段后的形态：`MMCleaner.ExclusionStoreTests.<uuid>`
        // 这种每次运行换一个的名字是实例产物，不是应用标识，剩下的两段也不像包名。
        let identity = strippingUUIDTailSegment(base)
        let ownerKey = ResidualNameMatcher.normalize(identity)
        guard ownerKey.count >= minNameLength else { return nil }
        let lower = ownerKey.lowercased()
        if applePrefixes.contains(where: { lower.hasPrefix($0) }) { return nil }
        // 只认反向域名形态。厂商子目录（~/Library/Google/Chrome）的磁盘名属于厂商
        // 而不是某个应用，判它"没有主人"等于判整个厂商目录死刑，太激进了。
        guard isOwnerShaped(identity) else { return nil }
        if owners.owns(ownerKey) { return nil }

        return OrphanCandidate(
            id: path, path: path, name: fileName, category: category, owner: identity, size: nil
        )
    }

    /// 末段是 UUID 时把它削掉，其余原样。真实应用标识不会以 UUID 结尾，
    /// 但"应用 + 每次运行一个实例目录"会（`com.foo.Bar.<uuid>`），
    /// 所以只削尾段、保留前缀，让它仍然能被认出来。
    static func strippingUUIDTailSegment(_ base: String) -> String {
        let segments = base.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let last = segments.last, segments.count > 1, isUUIDLike(last) else { return base }
        return segments.dropLast().joined(separator: ".")
    }

    /// 强证据只认"反向域名"形态：至少两段点分、每段不短。
    /// `Caches`、`Saved`、`HomeKit` 这种单词目录不可能是应用归属线索。
    static func isOwnerShaped(_ base: String) -> Bool {
        let segments = base.split(separator: ".").map(String.init)
        guard segments.count >= 3 else { return false }
        return segments.allSatisfy { $0.count >= 2 }
    }
}

/// 已装应用的归属索引。判断"这个名字有没有主人"要同时看点分标识和名称，
/// 而且派生标识（`com.foo.bar.Updater`）算它主人的。
struct OwnerIndex {
    private var owned: Set<String> = []

    init(installed: [InstalledAppIdentity]) {
        for app in installed {
            // 归一化把 "." 和 "-" 都折成同一种分隔符并统一小写，所以磁盘名和包名
            // 放进同一个集合就能直接比——分隔符写法不该决定一个标识有没有主人。
            let id = ResidualNameMatcher.normalize(app.bundleID)
            guard id.count >= 2 else { continue }
            owned.insert(id)
        }
    }

    func owns(_ key: String) -> Bool {
        guard owned.contains(key) == false else { return true }
        // 派生标识：`com.example.MyApp.Helper` / `.Updater` 属于 `com.example.MyApp`。
        // 只从前往后截短比对，所以 `io.github.whitesmith.RunCat` 不会因为装了
        // 同厂商的另一款应用就被判成有主人——那需要厂商前缀本身是个已装包名。
        var prefix = ""
        for part in key.split(separator: "-") {
            prefix = prefix.isEmpty ? String(part) : prefix + "-" + String(part)
            if owned.contains(prefix) { return true }
        }
        return false
    }
}
