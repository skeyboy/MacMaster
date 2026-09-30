import XCTest
import Foundation
@testable import MMUninstaller

/// 反向扫描的评估口径：**宁可漏报，不可错报**。
/// 这里每一条"不该报"的断言都比"该报"的断言重要——一个被错判成孤儿的
/// 正在使用的缓存，用户删掉之后是回不来的。
final class OrphanScannerTests: XCTestCase {
    private var fixture: ResidualFixture!
    private let myApp = InstalledAppIdentity(name: "My App", bundleID: "com.example.MyApp")

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: "Orphan")
    }

    override func tearDown() {
        fixture?.cleanup()
        fixture = nil
        super.tearDown()
    }

    private func scan(installed: [InstalledAppIdentity], sensitivity: ResidualSensitivity = .strict,
                      includeSystem: Bool = false) -> [OrphanCandidate] {
        OrphanScanner.scan(
            installed: installed,
            options: fixture.options(sensitivity: sensitivity, includeSystem: includeSystem)
        )
    }

    func testCacheOfInstalledAppIsNotReported() throws {
        try fixture.libraryFolder("Caches/com.example.MyApp")
        XCTAssertTrue(scan(installed: [myApp]).isEmpty)
    }

    func testCacheOfUnknownAppIsReported() throws {
        try fixture.libraryFolder("Caches/com.ghostwriter.Gone")
        let found = scan(installed: [myApp])
        XCTAssertEqual(found.map(\.name), ["com.ghostwriter.Gone"])
        XCTAssertEqual(found.first?.category, .cache)
        XCTAssertEqual(found.first?.owner, "com.ghostwriter.Gone")
        // 展示路径相对 home 缩写：绝对路径会把尾部那个真正的标识挤进截断里。
        XCTAssertTrue(found.first!.displayPath.hasPrefix("~/Library/Caches/"),
                      found.first!.displayPath)
        XCTAssertFalse(found.first!.path.hasPrefix("~"))
    }

    /// 系统组件的缓存在磁盘上永远"没有对应的已安装应用"——应用就在 /System 里。
    /// 不挡住这一类，名单会被上千条 com.apple.* 淹没。
    func testAppleIdentifiersAreNeverOrphans() throws {
        try fixture.libraryFolder("Caches/com.apple.SafariServices")
        try fixture.libraryFolder("Preferences/com.apple.CharacterPaletteIM.plist")
        XCTAssertTrue(scan(installed: [myApp]).isEmpty)
    }

    func testDerivedIdentifierBelongsToItsApp() throws {
        try fixture.libraryFolder("Caches/com.example.MyApp.Helper")
        try fixture.libraryFolder("Caches/com.example.MyApp.Updater")
        XCTAssertTrue(scan(installed: [myApp]).isEmpty)
    }

    /// 分隔符与大小写不该决定一个标识有没有主人：磁盘上写 `com.example.my.app`，
    /// Info.plist 里写 `com.example.my-app`，是同一个应用。
    func testSeparatorAndCaseVariantsShareOwnership() throws {
        try fixture.libraryFolder("Caches/com.example.my.app")
        let installed = InstalledAppIdentity(name: "My App", bundleID: "com.example.my-app")
        XCTAssertTrue(scan(installed: [installed]).isEmpty)
    }

    /// 两段形态（`io.gh`）既可能是被截断的标识，也可能是厂商缩写。
    /// 判定要求三段以上，短线索一律不报。
    func testTwoSegmentNameIsNotEnoughEvidence() throws {
        try fixture.libraryFolder("Caches/io.gh")
        try fixture.libraryFolder("Caches/abc.de")
        XCTAssertTrue(scan(installed: [myApp]).isEmpty)
    }

    func testUUIDNamedEntriesAreSkipped() throws {
        try fixture.libraryFolder("Caches/550E8400-E29B-41D4-A716-446655440000")
        // Containers 走元数据反查，反向没有名称可判，整条清单跳过。
        try fixture.makeContainer(dirName: "com.realapp.Thing", identifier: nil)
        let found = scan(installed: [myApp])
        XCTAssertTrue(found.isEmpty)
    }

    /// 末段是 UUID 的名字是"每次运行换一个"的实例产物：先剥掉尾段再判形态。
    /// 剩下的仍然像包名（`com.foo.Bar`）就报，只像个类名（`MMCleaner.ExclusionStoreTests`，
    /// 真实机型上就是我们自己的单测漏进 ~/Library/Preferences 的那批）就不报。
    func testUUIDTailSegmentIsStrippedBeforeJudging() throws {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        try fixture.libraryFolder("Caches/com.vanishing.Point.\(uuid)")
        try fixture.libraryFolder("Preferences/MMCleaner.ExclusionStoreTests.\(uuid).plist")
        let found = scan(installed: [myApp])
        XCTAssertEqual(found.map(\.name), ["com.vanishing.Point.\(uuid)"])
        XCTAssertEqual(found.first?.owner, "com.vanishing.Point")
    }

    func testEnhancedOnlyCategoriesRespectSensitivity() throws {
        try fixture.libraryFolder("WebKit/com.vanishing.Point")
        XCTAssertTrue(scan(installed: [myApp], sensitivity: .strict).isEmpty)
        XCTAssertEqual(scan(installed: [myApp], sensitivity: .enhanced).map(\.name),
                       ["com.vanishing.Point"])
    }

    /// 未测量的大小是 nil，不是 0：0 字节读起来等于"这里没东西"。
    func testSizeStaysUnmeasured() throws {
        try fixture.libraryFolder("Caches/com.ghostwriter.Gone")
        XCTAssertNil(scan(installed: [myApp]).first?.size)
    }

    func testSystemDomainScannedOnlyWhenAsked() throws {
        try fixture.libraryFolder("Preferences/com.gone.SystemWide.plist",
                                  under: fixture.systemRoot)
        XCTAssertTrue(scan(installed: [myApp]).isEmpty)
        let found = scan(installed: [myApp], includeSystem: true)
        XCTAssertEqual(found.map(\.name), ["com.gone.SystemWide.plist"])
        XCTAssertEqual(found.first?.category, .preference)
    }

    func testPackageReceiptSuppressesMatchingOrphanWithoutBecomingCandidate() throws {
        try fixture.libraryFolder("Caches/com.vendor.PaidApp")
        try fixture.libraryFolder("Caches/com.ghostwriter.Gone")
        let receipts = fixture.root.appendingPathComponent("receipts", isDirectory: true)
        try fixture.writePlist(receipts.appendingPathComponent("com.vendor.PaidApp.plist").path,
                               ["PackageIdentifier": "com.vendor.PaidApp"])
        let options = ResidualScanOptions(home: fixture.homePath, receiptsRoot: receipts.path)

        let found = OrphanScanner.scan(installed: [myApp], options: options)
        XCTAssertEqual(found.map(\.name), ["com.ghostwriter.Gone"])
        XCTAssertFalse(found.contains { $0.path.hasPrefix(receipts.path) })
    }

    func testUnreadableOrInvalidReceiptsDoNotClaimOwnership() throws {
        try fixture.libraryFolder("Caches/com.vendor.PaidApp")
        let receipts = fixture.root.appendingPathComponent("receipts", isDirectory: true)
        try fixture.writeFile(receipts.appendingPathComponent("broken.plist").path, contents: "not a plist")
        let options = ResidualScanOptions(home: fixture.homePath, receiptsRoot: receipts.path)

        XCTAssertEqual(OrphanScanner.scan(installed: [myApp], options: options).map(\.name),
                       ["com.vendor.PaidApp"])
        XCTAssertEqual(ReceiptOwnerIndex.identifiers(at: receipts.path), [])
    }

    /// 隐藏文件与 .DS_Store 之类的杂项不参与判断。
    func testHiddenAndJunkEntriesIgnored() throws {
        try fixture.writeFile(fixture.homePath + "/Library/Caches/.DS_Store")
        try fixture.libraryFolder("Caches/com.example.MyApp")
        XCTAssertTrue(scan(installed: [myApp]).isEmpty)
    }
}
