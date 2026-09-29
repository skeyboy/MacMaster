import XCTest
@testable import MMOptimizer

final class DevToolCacheAuditTests: XCTestCase {

    // MARK: - 环境变量的可用性判据

    func testUsableEnvPathRejectsRelative() {
        XCTAssertNil(DevToolCacheAuditor.usableEnvPath("go/pkg/mod"))
    }

    func testUsableEnvPathRejectsParentTraversal() {
        XCTAssertNil(DevToolCacheAuditor.usableEnvPath("/Users/lee/go/../etc"))
        XCTAssertNil(DevToolCacheAuditor.usableEnvPath("/../../etc"))
    }

    func testUsableEnvPathRejectsNewline() {
        // 换行能把一个路径变成两条指令的形态，任何情况下都不该往下传。
        XCTAssertNil(DevToolCacheAuditor.usableEnvPath("/Users/lee/go\n/var/root"))
        XCTAssertNil(DevToolCacheAuditor.usableEnvPath("/Users/lee/go\r"))
    }

    func testUsableEnvPathAcceptsAndTrimsTrailingSlash() {
        XCTAssertEqual(DevToolCacheAuditor.usableEnvPath("/Users/lee/go/pkg/mod"),
                       "/Users/lee/go/pkg/mod")
        XCTAssertEqual(DevToolCacheAuditor.usableEnvPath("/Users/lee/go/pkg/mod/"),
                       "/Users/lee/go/pkg/mod")
        XCTAssertEqual(DevToolCacheAuditor.usableEnvPath("/"), "/")
    }

    func testUsableEnvPathRejectsEmptyAndNil() {
        XCTAssertNil(DevToolCacheAuditor.usableEnvPath(""))
        XCTAssertNil(DevToolCacheAuditor.usableEnvPath(nil))
    }

    // MARK: - 工具解析（只 stat）

    func testToolPathScansPATHInOrder() {
        let found = DevToolCacheAuditor.toolPath(name: "go",
                                                 env: ["PATH": "/a:/b"]) { $0 == "/b/go" }
        XCTAssertEqual(found, "/b/go")
    }

    func testToolPathReturnsNilWhenNothingMatches() {
        XCTAssertNil(DevToolCacheAuditor.toolPath(name: "go", env: ["PATH": "/a:/b"]) { _ in false })
    }

    func testToolPathFallsBackToDefaultSearchDirsWhenPATHMissing() {
        // 没有 PATH 时不能判成"什么都没装"——回落到达尔文默认目录。
        let found = DevToolCacheAuditor.toolPath(name: "sh", env: [:]) { p in
            p == "/bin/sh"
        }
        XCTAssertEqual(found, "/bin/sh")
    }

    // MARK: - 根位置来源

    func testEnvRootIsLabeledWithItsKey() {
        let e = entry(for: "go-mod", env: ["GOMODCACHE": "/Volumes/ext/mod"], presence: .present)
        XCTAssertEqual(e.root, "/Volumes/ext/mod")
        XCTAssertEqual(e.rootSource, .environment(key: "GOMODCACHE"))
    }

    func testInvalidEnvRootFallsBackToDefaultAndSaysSo() {
        let e = entry(for: "go-mod", env: ["GOMODCACHE": "../evil"], presence: .present,
                      home: "/Users/lee")
        XCTAssertEqual(e.root, "/Users/lee/go/pkg/mod")
        XCTAssertEqual(e.rootSource, .defaultPath)
        XCTAssertTrue(e.rootSource.badgeText.contains("未向工具求证"))
    }

    // MARK: - 测量诚实

    func testAbsentRootHasNilSizeAndSaysNotZero() {
        // 目录不存在时把大小渲染成 0，就是"没看过"冒充"干净"。
        let e = entry(for: "go-mod", env: ["GOMODCACHE": "/x/mod"], presence: .absent)
        XCTAssertNil(e.bytes)
        XCTAssertEqual(e.presence, .absent)
        XCTAssertEqual(DevToolCacheCopy.presenceBadge(e), DevToolCacheCopy.absentBadge)
        XCTAssertTrue(e.caveat?.contains("不是「0 字节可清理」") == true)
    }

    func testUnreadableRootHasNilSize() {
        let e = entry(for: "npm", env: ["npm_config_cache": "/x/npm"],
                      presence: .unreadable(reason: "没有读权限"))
        XCTAssertNil(e.bytes)
        XCTAssertEqual(DevToolCacheCopy.presenceBadge(e), DevToolCacheCopy.unreadableBadge)
    }

    func testPresentRootIsMeasured() {
        let e = entry(for: "cargo-registry", env: ["CARGO_HOME": "/Users/lee/.cargo"],
                      presence: .present, size: 75_000_000)
        XCTAssertEqual(e.bytes, 75_000_000)
        XCTAssertEqual(e.root, "/Users/lee/.cargo/registry")
    }

    func testMissingToolOverridesPresenceBadge() {
        // 工具没装时，"位置不存在"这条读数没有意义——先说没装。
        let e = entry(for: "go-mod", env: ["GOMODCACHE": "/x/mod"], presence: .absent,
                      installed: false)
        XCTAssertEqual(DevToolCacheCopy.presenceBadge(e), DevToolCacheCopy.notInstalledBadge)
        XCTAssertTrue(e.caveat?.contains("PATH 里没找到 go") == true)
    }

    // MARK: - 命令只给文本

    func testPipHasNoOwnerCommandAndSaysSo() {
        let e = entry(for: "pip", env: [:], presence: .present, size: 1)
        XCTAssertNil(e.ownerCommand)
        XCTAssertTrue(e.caveat?.contains("没有 owner 清理命令") == true)
    }

    func testHomebrewCommandIsTheDryRunPreview() {
        // 预览形态：不带 -n 的那条会真删旧版本，这一屏绝不给。
        let e = entry(for: "homebrew", env: [:], presence: .present, size: 1)
        XCTAssertEqual(e.ownerCommand, "brew cleanup -n")
    }

    func testAutoremoveIsNotOfferedAnywhere() {
        // brew autoremove 卸载的是软件本身，不是缓存；整屏都不该出现这条。
        let all = DevToolCacheAuditor.entries(
            env: ["PATH": "/usr/bin"], home: "/Users/lee",
            presenceProbe: { _ in .present }, sizeProbe: { _ in 10 }, toolProbe: { _ in true })
        XCTAssertTrue(all.allSatisfy { ($0.ownerCommand ?? "").contains("autoremove") == false })
        XCTAssertTrue(all.allSatisfy { $0.why.contains("autoremove") == false })
    }

    func testEveryEntryCarriesAReason() {
        let all = DevToolCacheAuditor.entries(
            env: ["PATH": "/usr/bin"], home: "/Users/lee",
            presenceProbe: { _ in .present }, sizeProbe: { _ in 10 }, toolProbe: { _ in true })
        XCTAssertEqual(all.count, 6)
        XCTAssertTrue(all.allSatisfy { !$0.why.isEmpty })
    }

    // MARK: - helpers

    private func entry(for id: String, env: [String: String], presence: DevCachePresence,
                       size: UInt64? = nil, installed: Bool = true,
                       home: String = "/Users/lee") -> DevToolCacheEntry {
        var merged = env
        merged["PATH"] = merged["PATH"] ?? "/usr/bin"
        let all = DevToolCacheAuditor.entries(
            env: merged, home: home,
            presenceProbe: { _ in presence },
            sizeProbe: { _ in size },
            toolProbe: { _ in installed })
        guard let e = all.first(where: { $0.id == id }) else {
            XCTFail("没有条目 \(id)")
            return DevToolCacheEntry(id: id, title: "", root: "", rootSource: .defaultPath,
                                     toolInstalled: false, toolName: "", presence: .absent,
                                     bytes: nil, ownerCommand: nil, why: "", caveat: nil)
        }
        return e
    }
}
