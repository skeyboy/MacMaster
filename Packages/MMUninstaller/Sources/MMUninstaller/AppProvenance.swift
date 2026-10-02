import Foundation
import Darwin

/// 安装来源识别：只读地回答"这个应用是怎么来到这台机器上的"。
///
/// 参考项目（Pearcleaner / Mole）把这个问题当成一次查询——`brew list`、`brew info --json`；
/// 我们不执行任何第三方二进制，所以把它当成**读一份 brew 自己留下的账本**：
/// `<prefix>/Caskroom/<token>/.metadata/INSTALL_RECEIPT.json` 里写着这个 cask
/// 往哪个目录放了哪个 `.app`。账本可能过期、可能同名撞车，所以结论分档，
/// 并且"什么都没对上"就是 `.unknown`——**不写成"手动安装"**，没有凭据不等于手动。
public struct CaskEvidence: Equatable, Sendable {
    public let token: String
    public let version: String?
    public let installedAt: Date?
    public let tap: String?
    public let installedOnRequest: Bool?
    /// 凭据文件本身的路径。UI 要能说出"这句话是哪份文件写的"。
    public let receiptPath: String
    /// cask 作者在凭据里声明的 zap 残留条数。只报数，不展开——
    /// 展开是残留引擎的活（见 docs/analysis/uninstaller-provenance.md §4）。
    public let zapEntryCount: Int
    /// 凭据声明的 `.app` 名字（小写），如 `highball.app`。
    public let declaredAppNames: [String]

    public init(token: String, version: String?, installedAt: Date?, tap: String?,
                installedOnRequest: Bool?, receiptPath: String, zapEntryCount: Int,
                declaredAppNames: [String]) {
        self.token = token
        self.version = version
        self.installedAt = installedAt
        self.tap = tap
        self.installedOnRequest = installedOnRequest
        self.receiptPath = receiptPath
        self.zapEntryCount = zapEntryCount
        self.declaredAppNames = declaredAppNames
    }
}

public struct AppProvenance: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// Caskroom 里 staged 的那份 `.app` 链接解析后与这个 bundle 是**同一个 inode**。
        case homebrewCask
        /// 凭据声明的 `.app` 名字对上了，但设备号对不上（复制过一份、`--adopt`、换过目标目录）。
        case homebrewCaskNameOnly
        case appStore
        case installerPackage
        /// 没有任何凭据。不是"手动安装"。
        case unknown
    }

    public let source: Source
    public let cask: CaskEvidence?
    public let packageIdentifier: String?
    /// 两个以上 cask 都声明同一个 `.app` 名字时不替用户挑第一个：
    /// 降级成 `.unknown`，但把候选 token 留下，UI 可以说清"为什么不说"。
    public let ambiguousCaskTokens: [String]
    /// 歧义出在哪一层：`true` = 两份 staged 链接解析后**都是这个 bundle**（设备号同一，
    /// 两份账本在抢同一份文件）；`false` = 只有声明的名字撞上。两者的可信度不一样，
    /// 文案不能混着说。
    public let ambiguousByDeviceIdentity: Bool

    public init(source: Source, cask: CaskEvidence? = nil,
                packageIdentifier: String? = nil, ambiguousCaskTokens: [String] = [],
                ambiguousByDeviceIdentity: Bool = false) {
        self.source = source
        self.cask = cask
        self.packageIdentifier = packageIdentifier
        self.ambiguousCaskTokens = ambiguousCaskTokens
        self.ambiguousByDeviceIdentity = ambiguousByDeviceIdentity
    }

    public static let unknown = AppProvenance(source: .unknown)
}

/// 一个 bundle 在文件系统上的身份：`(st_dev, st_ino)`。
/// 名字可以改、可以复制，设备号 + inode 号改不了——这是"同一份"的唯一硬证据。
struct DeviceIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct CaskRecord: Sendable {
    let evidence: CaskEvidence
    /// staged `.app` 链接解析后的设备身份；链接悬空时这里没有它。
    let stagedIdentities: Set<DeviceIdentity>
}

/// 一次扫描期内的 cask 账本快照。构建只读 `.metadata` 与每个 token 一层版本目录，
/// 不遍历任何应用树。
public struct CaskIndex: Sendable {
    let records: [CaskRecord]

    init(records: [CaskRecord]) {
        self.records = records
    }

    public static let empty = CaskIndex(records: [])
}

public enum AppProvenanceScanner {

    /// 不按 CPU 架构猜前缀：ARM 机器上另装一份 Intel brew、或自定义前缀都会让猜测落空。
    /// 两个候选都探 `Caskroom` 是否存在（Mole 的做法，`lib/uninstall/brew.sh`）。
    public static func defaultPrefixes() -> [String] {
        ["/opt/homebrew", "/usr/local"]
    }

    public static func buildIndex(prefixes: [String] = defaultPrefixes(),
                                  fileManager: FileManager = .default) -> CaskIndex {
        var records: [CaskRecord] = []
        for prefix in prefixes {
            let caskroom = "\(prefix)/Caskroom"
            guard let tokens = try? fileManager.contentsOfDirectory(atPath: caskroom) else { continue }
            for token in tokens.sorted() {
                let tokenRoot = "\(caskroom)/\(token)"
                guard let record = readRecord(token: token, tokenRoot: tokenRoot, fileManager: fileManager) else { continue }
                records.append(record)
            }
        }
        return CaskIndex(records: records)
    }

    public static func provenance(for app: DiscoveredApp,
                                  index: CaskIndex,
                                  packageIdentifiers: Set<String> = [],
                                  fileManager: FileManager = .default) -> AppProvenance {
        if let identity = deviceIdentity(of: app.path, fileManager: fileManager) {
            let hits = index.records.filter { $0.stagedIdentities.contains(identity) }
            if hits.count == 1 {
                return AppProvenance(source: .homebrewCask, cask: hits[0].evidence)
            }
            // 两个 token 的 staged 链接指向同一份 bundle：账本自己打架，不挑。
            if hits.count > 1 {
                return AppProvenance(source: .unknown,
                                     ambiguousCaskTokens: hits.map { $0.evidence.token }.sorted(),
                                     ambiguousByDeviceIdentity: true)
            }
        }

        if fileManager.fileExists(atPath: "\(app.path)/Contents/_MASReceipt/receipt") {
            // MAS 收据排在设备号之后：它跟着 bundle 走，拷一份也带着；
            // 设备号同一则是"这份就是 brew 摆在这里的那份"的直接证据。
            return AppProvenance(source: .appStore)
        }

        let declared = app.bundleName.lowercased() + ".app"
        let nameHits = index.records.filter { $0.evidence.declaredAppNames.contains(declared) }
        if nameHits.count == 1 {
            return AppProvenance(source: .homebrewCaskNameOnly, cask: nameHits[0].evidence)
        }
        if nameHits.count > 1 {
            return AppProvenance(source: .unknown,
                                 ambiguousCaskTokens: nameHits.map { $0.evidence.token }.sorted())
        }

        if !app.bundleID.isEmpty, packageIdentifiers.contains(app.bundleID) {
            return AppProvenance(source: .installerPackage, packageIdentifier: app.bundleID)
        }
        return .unknown
    }

    // MARK: - 账本解析

    private static func readRecord(token: String, tokenRoot: String,
                                   fileManager: FileManager) -> CaskRecord? {
        let receiptPath = "\(tokenRoot)/.metadata/INSTALL_RECEIPT.json"
        guard let data = fileManager.contents(atPath: receiptPath),
              let json = try? JSONSerialization.jsonObject(with: data),
              let receipt = json as? [String: Any] else { return nil }

        let artifacts = receipt["uninstall_artifacts"] as? [[String: Any]] ?? []
        var declared: [String] = []
        var zapEntries = 0
        for artifact in artifacts {
            for (key, value) in artifact {
                switch key {
                case "app":
                    declared.append(contentsOf: appNames(from: value))
                case "zap":
                    zapEntries += zapCount(from: value)
                default:
                    break
                }
            }
        }

        let source = receipt["source"] as? [String: Any]
        let evidence = CaskEvidence(
            token: token,
            version: source?["version"] as? String,
            installedAt: (receipt["time"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) },
            tap: source?["tap"] as? String,
            installedOnRequest: receipt["installed_on_request"] as? Bool,
            receiptPath: receiptPath,
            zapEntryCount: zapEntries,
            declaredAppNames: declared.map { $0.lowercased() }
        )
        return CaskRecord(evidence: evidence,
                          stagedIdentities: stagedIdentities(tokenRoot: tokenRoot, fileManager: fileManager))
    }

    /// `uninstall_artifacts` 里的 app 条目有两种历史形态：纯字符串，或带 `target` 的字典。
    private static func appNames(from value: Any) -> [String] {
        if let strings = value as? [String] { return strings }
        if let string = value as? String { return [string] }
        if let dicts = value as? [[String: Any]] {
            return dicts.compactMap { ($0["target"] ?? $0["name"]) as? String }
        }
        if let dict = value as? [String: Any], let target = (dict["target"] ?? dict["name"]) as? String {
            return [target]
        }
        return []
    }

    private static func zapCount(from value: Any) -> Int {
        if let strings = value as? [String] { return strings.count }
        if let dicts = value as? [[String: Any]] {
            return dicts.reduce(0) { $0 + zapCount(from: $1.values.map { $0 }) }
        }
        if let dict = value as? [String: Any] {
            return dict.values.reduce(0) { $0 + zapCount(from: $1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + zapCount(from: $1) }
        }
        return 0
    }

    /// 每个 token 只看一层版本目录：staged 的 `.app` 是**指向真实 bundle 的符号链接**
    /// （方向是 Caskroom → /Applications），解析后取设备身份；悬空链接直接没有身份，
    /// 于是"账本还在、应用已走"的 token 自然落不进任何一档。
    private static func stagedIdentities(tokenRoot: String,
                                         fileManager: FileManager) -> Set<DeviceIdentity> {
        var identities = Set<DeviceIdentity>()
        guard let versions = try? fileManager.contentsOfDirectory(atPath: tokenRoot) else { return identities }
        for version in versions where version != ".metadata" {
            let versionRoot = "\(tokenRoot)/\(version)"
            guard let entries = try? fileManager.contentsOfDirectory(atPath: versionRoot) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let staged = URL(fileURLWithPath: "\(versionRoot)/\(entry)")
                let resolved = staged.resolvingSymlinksInPath().path
                if let identity = deviceIdentity(of: resolved, fileManager: fileManager) {
                    identities.insert(identity)
                }
            }
        }
        return identities
    }

    static func deviceIdentity(of path: String, fileManager: FileManager) -> DeviceIdentity? {
        var stats = stat()
        guard stat(path, &stats) == 0 else { return nil }
        return DeviceIdentity(device: UInt64(stats.st_dev), inode: UInt64(stats.st_ino))
    }
}
