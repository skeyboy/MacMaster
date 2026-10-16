import Foundation
import Security
import Darwin
import MMCore

// MARK: - 应用清单

/// 已在磁盘上的应用条目。`bundleName` 是 `.app` 之外的目录名，
/// 归一化后作为名称匹配的证据之一；`path` 是唯一主键。
public struct DiscoveredApp: Sendable, Equatable {
    public let path: String
    public let bundleName: String
    public let bundleID: String

    public init(path: String, bundleName: String, bundleID: String) {
        self.path = path
        self.bundleName = bundleName
        self.bundleID = bundleID
    }
}

/// 应用发现：只枚举可卸载的应用目录，并只读地读 Info.plist 与代码签名。
/// 与真实扫描不同，这里刻意不使用 `Bundle(path:)` 取包名：
/// 单测里的伪造 bundle 没有经过 LaunchServices 注册，只有直接读 plist 才能测到真实行为。
public enum AppScanner {

    /// 默认应用目录：系统级与用户级 `/Applications`、`/Applications/Utilities`，
    /// 外加每块非启动卷上的 `/Applications`（存在才算）。
    ///
    /// 这一格同时是 `AppFolderWatcher` 的监听范围 —— 监听范围必须等于列举范围，
    /// 所以扩目录只改这一处，装卸监听自动跟着宽。
    public static func defaultSearchDirectories(home: String) -> [String] {
        applicationDirectories(home: home,
                               volumePaths: VolumeRoots.nonBootVolumePaths(from: VolumeRootProbe.snapshot() ?? []),
                               directoryExists: { FileManager.default.fileExists(atPath: $0) })
    }

    /// 纯的那一半：三条固定的 + 每个候选卷一条。拆开是为了让"外接卷上得有这个目录才算"
    /// 这一条在单测里跑完，不用真插一块盘。
    ///
    /// `VolumeRootProbe` 读不到（`MM_VOLUME_FIXTURE=fail` 那档）时传空数组进来：
    /// 那是"没数过外接卷"，不是"没有外接卷"，名单退回固定三条即可，界面上不假装扫过。
    static func applicationDirectories(home: String, volumePaths: [String],
                                       directoryExists: (String) -> Bool) -> [String] {
        var directories = ["/Applications", "/Applications/Utilities", "\(home)/Applications"]
        directories += volumePaths.map { "\($0)/Applications" }.filter(directoryExists)
        return directories
    }

    public static func applications(in directories: [String]) -> [DiscoveredApp] {
        var found: [DiscoveredApp] = []
        var seen = Set<String>()
        for directory in directories {
            let entries: [String]
            do {
                entries = try FileManager.default.contentsOfDirectory(atPath: directory)
            } catch {
                continue
            }
            for entry in entries where entry.hasSuffix(".app") {
                let path = "\(directory)/\(entry)"
                let canonical = ResidualCollector.canonicalPath(path)
                guard seen.contains(canonical) == false else { continue }
                seen.insert(canonical)
                found.append(DiscoveredApp(
                    path: path,
                    bundleName: String(entry.dropLast(4)),
                    bundleID: bundleIdentifier(at: path)
                ))
            }
        }
        return found.sorted { $0.bundleName.localizedCaseInsensitiveCompare($1.bundleName) == .orderedAscending }
    }

    /// 用 PropertyListSerialization 读 Info.plist（二进制与 XML 都支持）。
    public static func infoDictionary(at appPath: String) -> [String: Any]? {
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    public static func bundleIdentifier(at appPath: String) -> String {
        guard let info = infoDictionary(at: appPath) else { return "" }
        return (info["CFBundleIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Finder 显示的名字优先取本地化过的 `CFBundleDisplayName`，再退到 `CFBundleName`，
    /// 都没有才用目录名（`mdls -name kMDItemDisplayName` 拿到的是磁盘文件名，不是这个名字）。
    public static func displayName(at appPath: String, bundleName: String) -> String {
        guard let info = infoDictionary(at: appPath) else { return bundleName }
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let value = info[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false { return value }
            }
        }
        return bundleName
    }

    public static func stringValue(_ info: [String: Any]?, _ key: String) -> String {
        guard let value = info?[key] as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func modificationDate(of path: String) -> Date? {
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
            + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    /// 从代码签名的叶子证书取开发者与团队标识，无需联网。
    /// 证书主题形如 `Developer ID Application: Example Inc (TEAMID0000)`。
    public static func signatureInfo(of path: String) -> (developer: String, teamID: String) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return ("", "") }

        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let subject = SecCertificateCopySubjectSummary(leaf) as String? else { return ("", "") }

        let teamID = (info[kSecCodeInfoTeamIdentifier as String] as? String) ?? ""
        guard let colon = subject.firstIndex(of: ":") else { return (subject, teamID) }
        let remainder = subject[subject.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let paren = remainder.lastIndex(of: "(") else { return (remainder, teamID) }
        return (String(remainder[remainder.startIndex..<paren]).trimmingCharacters(in: .whitespaces), teamID)
    }

    /// 系统自带应用（`com.apple.*`）不提供残留扫描：
    /// 它们的容器与偏好由系统管理，删掉会破坏系统状态而不是回收空间。
    public static func isSystemOwned(bundleID: String) -> Bool {
        bundleID.lowercased().hasPrefix("com.apple.")
    }
}
