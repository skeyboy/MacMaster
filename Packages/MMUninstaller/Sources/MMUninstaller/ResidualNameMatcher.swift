import Foundation
import MMCore

// MARK: - 命中证据

/// 一条命中证据的两个面：`kind` 给判定用，`text` 给用户看。
///
/// 分成两样是 P58 接双语时必须的：`ResidualOwnershipReview` 的降级判据原本是
/// `reason.hasPrefix("名称包含应用名")`——拿展示字符串的前缀当判据。文案进表之后
/// 英文档拿到的是 "Name contains the app name"，那句中文前缀再也不会匹配，
/// 于是降级静默失效、跨应用收进来的弱匹配项重新默认勾选，而画面上一个字都没变。
/// 判据从此只认 `kind`。
public enum ResidualEvidenceKind: String, Sendable {
    case plistOwner
    case identifierExact
    case identifierPrefix
    case nameExact
    case nameContains
    case identifierSuffix
    case identifierSuffixDerived
    case containerMetadata
    case containerName
    case containerCache
    case containerWebKit
    case launchFileName
    case launchLabel
    case launchExecutable

    var localizationKey: String {
        switch self {
        case .plistOwner: "ui.evidence.plist_owner"
        case .identifierExact: "ui.evidence.identifier_exact"
        case .identifierPrefix: "ui.evidence.identifier_prefix"
        case .nameExact: "ui.evidence.name_exact"
        case .nameContains: "ui.evidence.name_contains"
        case .identifierSuffix: "ui.evidence.identifier_suffix"
        case .identifierSuffixDerived: "ui.evidence.identifier_suffix_derived"
        case .containerMetadata: "ui.evidence.container_metadata"
        case .containerName: "ui.evidence.container_name"
        case .containerCache: "ui.evidence.container_cache"
        case .containerWebKit: "ui.evidence.container_webkit"
        case .launchFileName: "ui.evidence.launch_file_name"
        case .launchLabel: "ui.evidence.launch_label"
        case .launchExecutable: "ui.evidence.launch_executable"
        }
    }

    func text(_ arguments: [String]) -> String {
        // 必须走带 `arguments:` 标签的那一条：位置形式命中的是变长重载，整个数组被当成**一个** `%@`，
        // 带参的那几句会印成 NSArray 字面量、第二个占位符直接是 `(null)`（判据见 `testEvidenceTextKeepsTheChineseWording`）。
        String(format: L(localizationKey), arguments: arguments)
    }
}

/// 证据本体：`kind` 是不可翻的判定，`text` 是随语言的那一句。
public struct ResidualEvidence: Sendable {
    public let kind: ResidualEvidenceKind
    public let text: String

    init(_ kind: ResidualEvidenceKind, _ arguments: String...) {
        self.kind = kind
        self.text = kind.text(arguments)
    }

    /// 只由「名称包含应用名」这种弱匹配认领——归属复核降级的整个判据。
    var isContainmentOnly: Bool { kind == .nameContains }

    /// 下探厂商目录时给证据补一句"它是在哪一层里找到的"。`kind` 原样带走。
    func found(inside directoryName: String) -> ResidualEvidence {
        ResidualEvidence(text: LF("ui.evidence.inside", text, directoryName), kind: kind)
    }

    init(text: String, kind: ResidualEvidenceKind) {
        self.text = text
        self.kind = kind
    }
}

// MARK: - 归一化名称匹配

/// 归一化后的应用身份。`My App` / `my-app` / `MyApp` 归一化并压缩后都是 `myapp`，
/// 因此命中同一个 bundle；`My App Helper` 与 `My App` 不相等，严格档不会误命中，
/// 增强档才按"包含关系"收下。
public struct ResidualNameMatcher: Sendable {
    /// 一个候选名称的三种形态：分隔符统一串、去分隔符压缩串、词段集合。
    struct NameCandidate: Sendable {
        let normalized: String
        let compressed: String
        let segments: Set<String>
    }

    /// 归一化后的名称候选（含只留字母的写法）。内部细节，不参与对外 API。
    let nameCandidates: [NameCandidate]
    /// 小写包名及其分段，用于包名前缀与末段判断。
    let identifier: String
    let identifierSegments: [String]

    public init(appName: String, bundleID: String) {
        var candidates: [NameCandidate] = []
        var seen = Set<String>()
        for raw in [appName, ResidualNameMatcher.lettersOnly(appName)] {
            let normalized = ResidualNameMatcher.normalize(raw)
            guard normalized.isEmpty == false, seen.contains(normalized) == false else { continue }
            seen.insert(normalized)
            let compressed = ResidualNameMatcher.compress(normalized)
            let segments = ResidualNameMatcher.segments(of: normalized)
            guard compressed.isEmpty == false else { continue }
            candidates.append(NameCandidate(normalized: normalized, compressed: compressed, segments: segments))
        }
        nameCandidates = candidates

        let trimmedID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        identifier = ResidualNameMatcher.normalize(trimmedID)
        identifierSegments = identifier.isEmpty ? [] : identifier.split(separator: "-").map(String.init)
    }

    /// 严格档判定：包名对应或名称完全对应。
    public func matches(fileURL url: URL, bundleID: String) -> Bool {
        evidence(for: url, bundleID: bundleID, allowContains: false) != nil
    }

    /// 返回命中证据（nil 表示不命中）。证据要印在行上，所以 `text` 是短句而不是枚举名；
    /// 判定方（归属复核）读 `kind`，不读那句话——理由见 `ResidualEvidence`。
    public func evidence(for url: URL, bundleID: String, allowContains: Bool) -> ResidualEvidence? {
        if url.pathExtension.lowercased() == "plist",
           let owner = Self.ownerIdentifier(in: url, matcher: self),
           matchesIdentifier(owner) {
            return ResidualEvidence(.plistOwner, owner)
        }

        // `.app` / `.plist` 这类真扩展名要剥掉再比；但 `com.example.MyApp` 的最后一段
        // 不是扩展名，一律 deletingPathExtension() 会把它削成 `com.example`，
        // 于是"包名完全对应"这条最硬的证据反而永远不成立。
        // 两种写法都过一遍：先剥扩展名（证据更干净），再试原名。
        let last = url.lastPathComponent
        let stripped = url.deletingPathExtension().lastPathComponent
        for form in stripped == last ? [last] : [stripped, last] {
            if let evidence = evidence(forFileName: form, allowContains: allowContains) {
                return evidence
            }
        }
        return nil
    }

    private func evidence(forFileName fileName: String, allowContains: Bool) -> ResidualEvidence? {
        let normalizedFile = Self.normalize(fileName)
        guard normalizedFile.isEmpty == false else { return nil }
        let compressedFile = Self.compress(normalizedFile)
        let fileSegments = Self.segments(of: normalizedFile)

        if identifier.isEmpty == false {
            // 标识比较保留分隔符边界：`com.example.MyAppSuite` 不能因为压缩后
            // 以 `comexamplemyapp` 开头就被当成本包的派生标识。
            if normalizedFile == identifier { return ResidualEvidence(.identifierExact) }
            // com.example.MyApp.plugin / -Helper 都是这个 bundle 的派生标识。
            if normalizedFile.hasPrefix(identifier + "-") { return ResidualEvidence(.identifierPrefix) }
            if let suffix = identifierSuffixEvidence(for: normalizedFile) { return suffix }
        }

        for candidate in nameCandidates {
            if candidate.compressed == compressedFile { return ResidualEvidence(.nameExact) }
            if candidate.segments == fileSegments, candidate.segments.isEmpty == false { return ResidualEvidence(.nameExact) }
            // 包含匹配只在 enhanced/deep 开放，并且要求应用名本身不太短，
            // 否则 "App" 这种名字会把半个 Library 收进来。
            if allowContains, candidate.compressed.count >= 4,
               compressedFile.contains(candidate.compressed) {
                return ResidualEvidence(.nameContains)
            }
        }
        return nil
    }

    /// plist / 容器元数据里的标识是否属于这个包（保留分隔符边界）。
    private func matchesIdentifier(_ other: String) -> Bool {
        guard identifier.isEmpty == false else { return false }
        let normalizedOther = ResidualNameMatcher.normalize(other.lowercased())
        guard normalizedOther.isEmpty == false else { return false }
        return normalizedOther == identifier || normalizedOther.hasPrefix(identifier + "-")
    }

    /// 启动项与插件常省略首段域（`com.example.MyApp.xpc` → `example.my.app.xpc`），
    /// 用包名末段再对一次；只接受至少两段构成的末段，避免单个词到处命中。
    private func identifierSuffixEvidence(for normalizedFile: String) -> ResidualEvidence? {
        guard identifierSegments.count >= 3 else { return nil }
        for start in 1..<(identifierSegments.count - 1) {
            let suffix = identifierSegments[start...].joined(separator: "-")
            guard suffix.count >= 4 else { continue }
            if normalizedFile == suffix { return ResidualEvidence(.identifierSuffix) }
            if normalizedFile.hasPrefix(suffix + "-") { return ResidualEvidence(.identifierSuffixDerived) }
        }
        return nil
    }

    // MARK: plist 内容反查

    /// 偏好目录里的文件名常不含包名（ByHost、容器元数据等），
    /// plist 内部的主标识才是证据。用 PropertyListSerialization 读，绝不做字符串硬解析。
    private static func ownerIdentifier(in url: URL, matcher: ResidualNameMatcher) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        // MCMMetadataIdentifier 是容器元数据里"这个容器属于哪个 bundle"的键，
        // 容器扫描那一路共用同一个键名。
        if let identifier = plist[ContainerScanner.metadataIdentifierKey] as? String,
           identifier.isEmpty == false {
            return identifier
        }
        for key in ["ByHostIdentifier", "StoreFrontID", "DeviceIdentifier"] {
            if let value = plist[key] as? String, value.isEmpty == false { return value }
        }
        return nil
    }

    // MARK: 归一化

    /// 大小写、空格、连字符、下划线、点都归一到 `-`：`"My App"`、`"my-app"`、`"My.App"`
    /// 全部得到 `"my-app"`。
    public static func normalize(_ value: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSeparator = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                // 首段之前的分隔符丢掉，段与段之间只留一个 `-`。
                if pendingSeparator, result.isEmpty == false { result.append("-") }
                pendingSeparator = false
                result.append(scalar)
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || scalar == "-" || scalar == "_" || scalar == "." {
                if result.isEmpty == false { pendingSeparator = true }
            }
            // 其余字符（emoji、变体选择符等）直接丢弃，不参与匹配。
        }
        return String(result)
    }

    /// 去掉所有分隔符：`"my-app"` → `"myapp"`，让 `"My App"` 与 `"MyApp"` 等价。
    public static func compress(_ normalized: String) -> String {
        normalized.replacingOccurrences(of: "-", with: "")
    }

    /// 只留字母，覆盖 `"MyApp 2"` 与 `"MyApp"` 这类带版本号/后缀的写法。
    public static func lettersOnly(_ value: String) -> String {
        String(value.unicodeScalars.filter { CharacterSet.letters.contains($0) }).lowercased()
    }

    public static func segments(of normalized: String) -> Set<String> {
        Set(normalized.split(separator: "-").map(String.init)).filter { $0.isEmpty == false }
    }
}
