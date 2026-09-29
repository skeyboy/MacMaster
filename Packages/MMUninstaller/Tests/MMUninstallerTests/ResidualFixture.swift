import Foundation
import Darwin
import XCTest
@testable import MMUninstaller

/// 测试夹具：在临时目录里造出假的 app bundle 与假的 `~/Library` 结构，
/// 并把 home 作为可注入参数交给扫描器 —— 单测绝不读写真实用户文件。
final class ResidualFixture {
    let root: URL
    let home: URL
    let systemRoot: URL
    /// 测试里被 chmod 成只读的目录，cleanup 前必须恢复权限才删得干净。
    private var lockedDirectories: [String] = []

    /// 取物理路径。`URL.resolvingSymlinksInPath()` 在这台机器上并不会把
    /// `/var` 换成 `/private/var`（实测原样返回），而 `contentsOfDirectory`
    /// 交回来的是 `/private/var/...`。夹具若用前者，测试里的路径字符串
    /// 比较就永远不等——扫描器其实是对的，只有断言在撒谎。
    private static func physicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    init(caseName: String) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMUninstallerTests-\(caseName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: Self.physicalPath(base.path), isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        systemRoot = root.appendingPathComponent("system", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemRoot, withIntermediateDirectories: true)
    }

    func cleanup() {
        // 先恢复被锁成只读的目录权限，否则 removeItem 会留下删不掉的临时文件。
        for path in lockedDirectories {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        lockedDirectories.removeAll()
        try? FileManager.default.removeItem(at: root)
    }

    var homePath: String { home.path }
    var systemPath: String { systemRoot.path }

    /// `~/Library/<相对路径>`（`under` 可指向假系统域，用来覆盖 `/Library` 条目）。
    @discardableResult
    func libraryFolder(_ relative: String, under homeRoot: URL? = nil) throws -> String {
        let base = (homeRoot ?? home).appendingPathComponent("Library", isDirectory: true)
        let url = base.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    /// 在某个目录下写一个占位文件，让目录真的有内容可枚举。
    func writeFile(_ path: String, contents: String = "x") throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    /// 目录 + 一个占位文件，一步到位造出可命中的残留。
    @discardableResult
    func folderWithFile(_ path: String) throws -> String {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try writeFile(path + "/payload.bin", contents: String(repeating: "a", count: 4_096))
        return path
    }

    func writePlist(_ path: String, _ dictionary: [String: Any]) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
        try data.write(to: url)
    }

    /// 造一个最小可用的假 app bundle（含 Info.plist），返回其绝对路径。
    @discardableResult
    func makeApp(name: String, bundleID: String, version: String = "1.0", inApplicationsOf homeRoot: URL? = nil) throws -> String {
        let base = (homeRoot ?? home).appendingPathComponent("Applications", isDirectory: true)
        let appURL = base.appendingPathComponent("\(name).app", isDirectory: true)
        let path = appURL.path
        try FileManager.default.createDirectory(at: appURL.appendingPathComponent("Contents/MacOS", isDirectory: true),
                                                withIntermediateDirectories: true)
        try writePlist("\(path)/Contents/Info.plist", [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "42",
            "CFBundleExecutable": name.replacingOccurrences(of: " ", with: ""),
        ])
        try writeFile("\(path)/Contents/MacOS/\(name.replacingOccurrences(of: " ", with: ""))", contents: "binary")
        return path
    }

    /// 造一个沙盒容器：目录名故意不等于包名，归属只能由元数据反查。
    @discardableResult
    func makeContainer(dirName: String, identifier: String?, withCaches: Bool = true) throws -> String {
        let path = try libraryFolder("Containers/\(dirName)")
        if let identifier {
            try writePlist(path + "/\(ContainerScanner.metadataFileName)", ["MCMMetadataIdentifier": identifier])
        }
        if withCaches {
            try folderWithFile(path + "/Data/Library/Caches/\(dirName)")
            try folderWithFile(path + "/Data/Documents")
        }
        return path
    }

    /// 让某个目录不可写，用来模拟 root 属主的系统域（普通用户删不掉）。
    func makeReadOnly(_ path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
        lockedDirectories.append(path)
    }

    func options(sensitivity: ResidualSensitivity, includeSystem: Bool = false) -> ResidualScanOptions {
        ResidualScanOptions(home: homePath, systemRoot: includeSystem ? systemPath : "", sensitivity: sensitivity)
    }

    /// 固定大小，方便断言求和：每个命中项都是 10 字节。
    static let constantMeasure: (String) -> UInt64 = { _ in 10 }
}

extension XCTestCase {
    /// 用统一的名字跑一次扫描，减少测试里的样板。
    func scan(_ fixture: ResidualFixture, app: String = "My App", bundleID: String = "com.example.MyApp",
              appPath: String, sensitivity: ResidualSensitivity,
              includeSystem: Bool = false) -> ResidualScanReport {
        ResidualScanner.scan(appName: app, bundleID: bundleID, appPath: appPath,
                             options: fixture.options(sensitivity: sensitivity, includeSystem: includeSystem),
                             measure: ResidualFixture.constantMeasure)
    }
}
