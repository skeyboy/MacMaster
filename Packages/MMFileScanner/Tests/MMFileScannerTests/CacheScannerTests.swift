import XCTest
@testable import MMFileScanner

/// 清理页的"可释放 X GB"是用户按下删除按钮前唯一的依据，
/// 所以这里测的是**账对不对**：同一块字节不能算两次，排除的必须真的不算，
/// 取消后的结果必须自己承认不完整。
final class CacheScannerTests: XCTestCase {
    private var home: URL!
    private var caches: URL!

    override func setUpWithError() throws {
        home = try makeTempDirectory()
        caches = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeFile(_ name: String, in directory: URL, size: Int) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(count: size).write(to: url)
        return url
    }

    private func category(_ id: String, in report: CacheScanReport) -> CacheCategory? {
        report.categories.first { $0.id == id }
    }

    func testNestedCategoryDoesNotDoubleCount() async throws {
        // Safari 缓存物理上就在 ~/Library/Caches 里面。若父类别照单全收，
        // 两个类别相加就会超过磁盘上真实可释放的量。
        try writeFile("loose.bin", in: caches, size: 320 * 1024)
        try writeFile("page.bin", in: caches.appendingPathComponent("com.apple.Safari"), size: 240 * 1024)

        let report = await CacheScanner(home: home.path).scan(scope: [.systemCache, .appCache])

        let system = try XCTUnwrap(category("system_cache", in: report))
        let browser = try XCTUnwrap(category("browser_cache", in: report))
        XCTAssertLessThan(system.scannedSize, 340 * 1024, "系统缓存不应包含 Safari 子树")
        XCTAssertGreaterThan(browser.scannedSize, 200 * 1024)

        let combined = system.scannedSize + browser.scannedSize
        XCTAssertLessThan(combined, 640 * 1024, "两类相加被重复计数了")
        XCTAssertGreaterThan(combined, 500 * 1024)
    }

    func testExcludedFolderIsSkippedEntirely() async throws {
        try writeFile("loose.bin", in: caches, size: 128 * 1024)
        let devCache = caches.appendingPathComponent("Homebrew")
        try writeFile("bottle.bin", in: devCache, size: 512 * 1024)

        let report = await CacheScanner(home: home.path)
            .scan(scope: .systemCache, excludedFolderPaths: [devCache.path])

        let system = try XCTUnwrap(category("system_cache", in: report))
        XCTAssertFalse(system.subItems.contains { $0.path == devCache.path })
        XCTAssertLessThan(system.scannedSize, 300 * 1024)
    }

    func testSandboxContainerGlobExpandsPerContainer() async throws {
        let base = home.appendingPathComponent("Library/Containers", isDirectory: true)
        for bundle in ["com.foo.app", "com.bar.app"] {
            try writeFile("blob.bin",
                          in: base.appendingPathComponent("\(bundle)/Data/Library/Caches"),
                          size: 96 * 1024)
        }

        let report = await CacheScanner(home: home.path).scan(scope: .appCache)
        let sandbox = try XCTUnwrap(category("sandbox_container_cache", in: report))
        XCTAssertEqual(sandbox.subItems.count, 2)
        XCTAssertGreaterThanOrEqual(sandbox.scannedFiles, 2)
    }

    func testCancelledScanAdmitsItIsIncomplete() async throws {
        try writeFile("loose.bin", in: caches, size: 64 * 1024)

        let report = await CacheScanner(home: home.path)
            .scan(scope: .systemCache, shouldContinue: { false })

        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.categories.isEmpty)
    }

    func testEmptyCategoryContributesNothing() async throws {
        let report = await CacheScanner(home: home.path).scan(scope: .systemCache)
        let trash = try XCTUnwrap(category("trash", in: report))
        XCTAssertEqual(trash.scannedSize, 0)
        XCTAssertTrue(trash.inaccessiblePaths.isEmpty)
    }
}
