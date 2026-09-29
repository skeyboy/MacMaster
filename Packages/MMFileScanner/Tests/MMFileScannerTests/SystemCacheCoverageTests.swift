import XCTest
@testable import MMFileScanner

/// 4.1（非显性系统缓存）与 4.2（沙盒容器内缓存）的对账测试。
///
/// 断言方式是**恰好等于**：用与扫描器同一口径（`totalFileAllocatedSize`、跳过隐藏文件、
/// 目录本身不计字节）在测试里把整棵假树独立量一遍，要求所有类别相加正好等于它。
/// 只写"小于某个阈值"抓不到重复计数——重复计数只是让总数变大，而变大未必越过阈值。
///
/// 三棵树（家目录 / `/private/var/folders` / 系统 `/Library`）全部注入临时目录，
/// 单测不会去量真机的用户文件。比较路径时统一走 `resolvingSymlinksInPath`：
/// 临时目录本身就在 `/var/folders` 下，字面量和枚举回来的 `/private/var` 永远对不上。
final class SystemCacheCoverageTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var varRoot: URL!
    private var systemLibrary: URL!
    /// 当前用户的 per-user 缓存目录，真实形态是 `<varRoot>/<2 字符>/<16 字符>/C`。
    private var userCache: URL!

    override func setUpWithError() throws {
        root = try makeTempDirectory("coverage")
        home = root.appendingPathComponent("home", isDirectory: true)
        varRoot = root.appendingPathComponent("var-folders", isDirectory: true)
        systemLibrary = root.appendingPathComponent("Library", isDirectory: true)
        userCache = varRoot.appendingPathComponent("aa/bb/C", isDirectory: true)
        for url in [home, varRoot, systemLibrary] {
            try FileManager.default.createDirectory(at: url!, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeTempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coverage-\(name)-\(UUID().uuidString)", isDirectory: true)
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

    private func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private func scanner(userCacheRoot: String? = nil) -> CacheScanner {
        CacheScanner(home: home.path, varRoot: varRoot.path, systemLibrary: systemLibrary.path,
                     userCacheRoot: userCacheRoot ?? userCache.path)
    }

    private func category(_ id: String, in report: CacheScanReport) -> CacheCategory? {
        report.categories.first { $0.id == id }
    }

    /// 与 `measureTree` 同一口径的独立测量：递归求每个**文件**的实际占用字节，目录本身不计。
    /// 同样用 `nextObject` 逐条取，理由和扫描器里一致（for-in 预取会让 skipDescendants 失效）。
    private func treeBytes(_ directory: URL) throws -> UInt64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey,
                                         .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey,
                          .fileAllocatedSizeKey, .fileSizeKey]
            ) else { continue }
            if values.isDirectory == true { continue }
            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize
                             ?? values.fileSize ?? 0)
        }
        return total
    }

    private func isInside(_ path: String, _ parent: URL) -> Bool {
        let head = canonical(parent)
        return path == head || path.hasPrefix(head + "/")
    }

    // MARK: - 4.1：per-user 缓存目录里的非显性系统缓存

    func testVarFolderCachesAreCountedExactlyOnce() async throws {
        try writeFile("loose.bin", in: home.appendingPathComponent("Library/Caches"), size: 32 * 1024)
        try writeFile("help.bin", in: home.appendingPathComponent("Library/Caches/com.apple.helpd"),
                      size: 8 * 1024)

        try writeFile("shader.bin", in: userCache.appendingPathComponent("com.apple.metalfe"),
                      size: 16 * 1024)
        try writeFile("gl.bin", in: userCache.appendingPathComponent("com.apple.gpuarchiver"),
                      size: 8 * 1024)
        try writeFile("cl.bin", in: userCache.appendingPathComponent("com.apple.opencl"),
                      size: 4 * 1024)
        try writeFile("icon.bin", in: userCache.appendingPathComponent("com.apple.iconservices"),
                      size: 12 * 1024)
        try writeFile("tile.bin", in: userCache.appendingPathComponent("com.apple.GEO"),
                      size: 20 * 1024)
        try writeFile("face.bin", in: userCache.appendingPathComponent("com.apple.photoanalysisd"),
                      size: 6 * 1024)
        // 某个应用自己 bucket 里的第二份着色器库：与顶层那份不是祖先/后代关系。
        try writeFile("app-shader.bin",
                      in: userCache.appendingPathComponent("com.apple.finder/com.apple.metalfe"),
                      size: 10 * 1024)
        // 这两个位置没有任何类别认领，必须一格都不计入。
        try writeFile("stray.bin", in: userCache, size: 44 * 1024)
        try writeFile("unknown.bin", in: userCache.appendingPathComponent("com.apple.unknown"),
                      size: 55 * 1024)

        // 守护账号 bucket（只读类别拥有）与系统 /Library/Caches。
        let daemonBucket = varRoot.appendingPathComponent("zz", isDirectory: true)
        try writeFile("root-shader.bin",
                      in: daemonBucket.appendingPathComponent("yy/C/com.apple.metalfe"), size: 10 * 1024)
        try writeFile("keep.bin", in: daemonBucket.appendingPathComponent("yy/C/com.apple.other"),
                      size: 5 * 1024)
        try writeFile("sys.bin", in: systemLibrary.appendingPathComponent("Caches"), size: 7 * 1024)

        let report = await scanner().scan(scope: [.systemCache])
        XCTAssertTrue(report.isComplete)

        // 独立口径的期望值：家目录缓存树 + 被认领的 per-user 叶子 + 只读两处。
        let expected = try treeBytes(home.appendingPathComponent("Library/Caches"))
            + treeBytes(userCache.appendingPathComponent("com.apple.metalfe"))
            + treeBytes(userCache.appendingPathComponent("com.apple.gpuarchiver"))
            + treeBytes(userCache.appendingPathComponent("com.apple.opencl"))
            + treeBytes(userCache.appendingPathComponent("com.apple.iconservices"))
            + treeBytes(userCache.appendingPathComponent("com.apple.GEO"))
            + treeBytes(userCache.appendingPathComponent("com.apple.photoanalysisd"))
            + treeBytes(userCache.appendingPathComponent("com.apple.finder/com.apple.metalfe"))
            + treeBytes(daemonBucket)
            + treeBytes(systemLibrary.appendingPathComponent("Caches"))
        XCTAssertEqual(report.totalSize, expected, "类别相加与独立测量的整棵树不一致")

        // 同一个绝对路径不能同时出现在两个类别的明细里。
        var seen: Set<String> = []
        for item in report.categories.flatMap(\.subItems) {
            XCTAssertTrue(seen.insert(item.path).inserted, "\(item.path) 被两个类别同时计入")
        }

        // Metal 类别：bucket 顶层 3 个 + 应用自己那份，逐个成条目。
        let metal = try XCTUnwrap(category("var_metal_cache", in: report))
        XCTAssertEqual(metal.subItems.count, 4)
        XCTAssertEqual(metal.scannedFiles, 4)
        XCTAssertTrue(metal.risk.isDefaultSelected, "着色器库由系统重建，可以默认可选")

        let geo = try XCTUnwrap(category("var_geo_cache", in: report))
        XCTAssertEqual(geo.risk, .caution, "地图瓦片要重新联网下载，不能默认勾选")
        XCTAssertFalse(geo.risk.isDefaultSelected)
    }

    func testUnclaimedFoldersAreNeverCounted() async throws {
        // 认领表之外的目录一个字节都不能进合计，否则"可释放"里混着没人负责的东西。
        try writeFile("stray.bin", in: userCache, size: 44 * 1024)
        try writeFile("unknown.bin", in: userCache.appendingPathComponent("com.apple.unknown"),
                      size: 55 * 1024)

        let report = await scanner().scan(scope: [.systemCache])
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.totalSize, 0)
        XCTAssertTrue(report.categories.flatMap(\.subItems).isEmpty)
    }

    // MARK: - 需要 root 的位置：只读、不给删除入口

    func testPrivilegedCacheIsReadOnlyAndNotOfferedForDeletion() async throws {
        let daemonBucket = varRoot.appendingPathComponent("zz", isDirectory: true)
        try writeFile("root.bin", in: daemonBucket.appendingPathComponent("yy/C/com.apple.metalfe"),
                      size: 10 * 1024)
        try writeFile("sys.bin", in: systemLibrary.appendingPathComponent("Caches"), size: 8 * 1024)
        try writeFile("shader.bin", in: userCache.appendingPathComponent("com.apple.metalfe"),
                      size: 16 * 1024)

        let report = await scanner().scan(scope: [.systemCache])
        let privileged = try XCTUnwrap(category("privileged_cache", in: report))

        XCTAssertEqual(privileged.risk, .readOnly)
        XCTAssertFalse(privileged.risk.allowsDeletion, "只读档不允许删除")
        XCTAssertFalse(privileged.risk.isDefaultSelected, "只读档不进默认可选清单")
        XCTAssertEqual(privileged.subItems.count, 2)

        // 可删除类别不得列出守护账号 bucket 或系统 /Library/Caches 里的路径。
        for item in report.categories.filter({ $0.risk.allowsDeletion }).flatMap(\.subItems) {
            XCTAssertFalse(isInside(item.path, daemonBucket), "\(item.path) 落在只读子树里")
            XCTAssertFalse(isInside(item.path, systemLibrary.appendingPathComponent("Caches")),
                           "\(item.path) 落在只读子树里")
        }
        // 用户自己那份仍然可删，且只计一次。
        let metal = try XCTUnwrap(category("var_metal_cache", in: report))
        XCTAssertEqual(metal.subItems.count, 1)
    }

    // MARK: - 4.2：通配展开逐条成条目

    func testMultiLevelGlobExpandsOneEntryPerLevel() throws {
        try writeFile("a.bin", in: userCache.appendingPathComponent("com.apple.metalfe"), size: 1024)
        try writeFile("b.bin",
                      in: varRoot.appendingPathComponent("zz/yy/C/com.apple.metalfe"), size: 1024)
        // 第三个 bucket 没有这个叶子：展开按目录名拼路径，存在性交给测量阶段判定。
        try FileManager.default.createDirectory(
            at: varRoot.appendingPathComponent("ee/ff/C"), withIntermediateDirectories: true)

        let expanded = CacheScanner.expand(glob: "\(varRoot.path)/*/*/C/com.apple.metalfe")
        XCTAssertEqual(expanded.count, 3, "每个 `*` 只替换一层目录名，两个 `*` 必须逐层展开")
        XCTAssertTrue(expanded.allSatisfy { $0.hasSuffix("C/com.apple.metalfe") })
        // FileManager 枚举回来的是 `/private/var` 形态，而 `resolvingSymlinksInPath`
        // 又把 `/private` 前缀摘掉：比较绝对路径必须先统一到同一口径，否则静默不相等。
        let canonicalized = expanded.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        XCTAssertTrue(canonicalized.contains(canonical(userCache) + "/com.apple.metalfe"))

        // 单层通配按容器逐个成条目。
        let containers = home.appendingPathComponent("Library/Containers", isDirectory: true)
        for bundle in ["com.foo.app", "com.bar.app", "com.baz.app"] {
            try writeFile("x.bin",
                          in: containers.appendingPathComponent("\(bundle)/Data/Library/Caches"),
                          size: 16 * 1024)
        }
        let globbed = CacheScanner.expand(glob: "\(home.path)/Library/Containers/*/Data/Library/Caches")
        XCTAssertEqual(globbed.count, 3)
        XCTAssertTrue(globbed.allSatisfy { $0.hasSuffix("Data/Library/Caches") })
        XCTAssertTrue(globbed.contains { $0.contains("com.foo.app") })
        XCTAssertEqual(Set(globbed.map { ($0 as NSString).lastPathComponent }), ["Caches"])
        // 无通配时原样返回，不做任何二次拼接。
        XCTAssertEqual(CacheScanner.expand(glob: "/tmp"), ["/tmp"])
    }

    func testContainerCachesAndUserCachesDoNotDoubleCount() async throws {
        try writeFile("big.bin", in: home.appendingPathComponent("Library/Caches"), size: 48 * 1024)
        try writeFile("safari.bin",
                      in: home.appendingPathComponent("Library/Caches/com.apple.Safari"),
                      size: 24 * 1024)
        let containers = home.appendingPathComponent("Library/Containers", isDirectory: true)
        var containerCacheBytes: UInt64 = 0
        for bundle in ["com.foo.app", "com.bar.app", "com.baz.app"] {
            let caches = containers.appendingPathComponent("\(bundle)/Data/Library/Caches")
            try writeFile("x.bin", in: caches, size: 16 * 1024)
            containerCacheBytes += try treeBytes(caches)
            // 容器里的用户文档：任何类别都不许计进来。
            try writeFile("thesis.docx",
                          in: containers.appendingPathComponent("\(bundle)/Documents"),
                          size: 33 * 1024)
        }

        // userCacheRoot 传 nil：拿不到 per-user 缓存目录时 4.1 的类别应当一格都不扫，
        // 而不是退化成通配去撞别人的 bucket。
        let report = await scanner(userCacheRoot: nil).scan(scope: [.systemCache, .appCache])
        XCTAssertTrue(report.isComplete)

        let expected = try treeBytes(home.appendingPathComponent("Library/Caches"))
            + containerCacheBytes
        XCTAssertEqual(report.totalSize, expected, "容器缓存与 ~/Library/Caches 之间重复计数了")

        let sandbox = try XCTUnwrap(category("sandbox_container_cache", in: report))
        XCTAssertEqual(sandbox.subItems.count, 3, "每个容器单独成一条")
        XCTAssertFalse(sandbox.risk.isDefaultSelected, "容器缓存默认不勾选")
        for item in sandbox.subItems {
            XCTAssertTrue(item.path.hasSuffix("Data/Library/Caches"), "只取容器内的缓存子树")
        }
        for id in ["var_metal_cache", "var_icon_preview_cache", "var_geo_cache",
                   "var_photo_analysis_cache"] {
            let empty = try XCTUnwrap(category(id, in: report))
            XCTAssertEqual(empty.scannedSize, 0, "\(id) 在没有 per-user 目录时不该扫任何东西")
            XCTAssertTrue(empty.subItems.isEmpty)
        }
    }

    // MARK: - 取消

    func testCancelledScanReportsIncompleteAndMonotonicProgress() async throws {
        try writeFile("loose.bin", in: home.appendingPathComponent("Library/Caches"), size: 32 * 1024)
        for name in ["com.apple.metalfe", "com.apple.gpuarchiver", "com.apple.opencl",
                     "com.apple.iconservices", "com.apple.iconservicesagent", "com.apple.helpd",
                     "com.apple.GEO", "com.apple.geod", "com.apple.photoanalysisd"] {
            try writeFile("x.bin", in: userCache.appendingPathComponent(name), size: 4 * 1024)
        }

        let gate = CallGate(limit: 6)
        let samples = ProgressSamples()
        let report = await scanner().scan(
            scope: [.systemCache],
            shouldContinue: { gate.pass() },
            progress: { samples.append($0.processedItems) }
        )

        XCTAssertFalse(report.isComplete, "中途取消的报告必须自己承认不完整")
        let values = samples.values
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values, values.sorted(), "已处理条目数必须单调不减")
        XCTAssertLessThan(report.processedItems, 20, "取消之后不该继续把整轮扫完")
        XCTAssertLessThan(report.categories.count, 8, "取消后只剩扫完的那几个类别")
    }
}

/// 前 N 次放行、之后一律拒绝的取消闸门。扫描循环在后台 actor 上反复调用它，所以自己带锁。
private final class CallGate: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var calls = 0

    init(limit: Int) { self.limit = limit }

    func pass() -> Bool {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return calls <= limit
    }
}

/// 进度回调在 actor 线程上被调用，收集样本同样要带锁。
private final class ProgressSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int] = []

    func append(_ value: Int) {
        lock.lock(); stored.append(value); lock.unlock()
    }

    var values: [Int] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}
