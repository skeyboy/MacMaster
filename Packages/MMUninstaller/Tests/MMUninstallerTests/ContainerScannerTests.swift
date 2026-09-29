import Foundation
import XCTest
@testable import MMUninstaller

/// 1.2 沙盒容器反查：容器目录名不等于包名，归属只能由元数据的 MCMMetadataIdentifier 证明。
final class ContainerScannerTests: XCTestCase {
    private var fixture: ResidualFixture!

    override func setUpWithError() throws {
        fixture = try ResidualFixture(caseName: name)
    }

    override func tearDownWithError() throws {
        fixture?.cleanup()
        fixture = nil
    }

    /// 目录名是一串随机标识，只有元数据能把它关联回 bundleID。
    func testMetadataIdentifierAssociatesContainerWithBundle() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let container = try fixture.makeContainer(dirName: "A1B2C3D4E5F6", identifier: "com.example.MyApp")

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        let item = report.items.first { $0.path == container }
        XCTAssertNotNil(item, "元数据标识命中的容器应被关联到本包")
        XCTAssertEqual(item?.category, .container)
        XCTAssertTrue(item?.reason.contains("MCMMetadata") == true || item?.reason.contains("容器元数据") == true,
                      "命中证据要说明是元数据反查出来的，实际：\(item?.reason ?? "nil")")
    }

    /// 别的应用的容器不能因为同在一个目录里就被收下。
    func testForeignContainerIsNotClaimed() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let other = try fixture.makeContainer(dirName: "ZZ99", identifier: "com.other.Unrelated")

        let report = scan(fixture, appPath: app, sensitivity: .deep)
        XCTAssertTrue(report.items.contains { $0.path == other } == false, "不该认领其他 bundle 的容器")
    }

    /// 整容器含用户文档 → 谨慎且默认不勾选；只有其中的缓存默认可选。
    func testWholeContainerIsCautionWhileInnerCacheIsSelectable() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let container = try fixture.makeContainer(dirName: "BOX01", identifier: "com.example.MyApp")
        let innerCache = container + "/Data/Library/Caches"

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        let containerItem = try XCTUnwrap(report.items.first { $0.path == container },
                                          "整容器应作为谨慎项出现：\(container)")
        let cacheItem = try XCTUnwrap(report.items.first { $0.path == innerCache },
                                      "容器内缓存应被单列：\(innerCache)")

        XCTAssertEqual(containerItem.risk, .caution, "容器整目录必须标为谨慎")
        XCTAssertEqual(cacheItem.category, .containerCache)
        XCTAssertEqual(cacheItem.risk, .safe, "容器内的可重建缓存默认可选")

        let defaults = UninstallSelection.defaultSelectedIDs(report.items)
        XCTAssertTrue(defaults.contains(cacheItem.id), "默认可选项里必须有容器内缓存")
        XCTAssertTrue(defaults.contains(containerItem.id) == false, "整个容器绝不默认勾选")

        // 用户文档目录绝不能出现在删除列表里（容器只有整目录这一层，且未勾选）。
        XCTAssertTrue(report.items.contains { $0.path.contains("Data/Documents") } == false)
    }

    /// Group Containers 的目录名就是 app group 标识，内嵌包名，按同一条证据链认领。
    func testGroupContainerClaimedByBundleID() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let group = try fixture.folderWithFile(try fixture.libraryFolder("Group Containers/group.com.example.MyApp"))

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        let item = report.items.first { $0.path == group }
        XCTAssertNotNil(item, "共享容器应按包名证据认领")
        XCTAssertEqual(item?.category, .groupContainer)
        XCTAssertEqual(item?.risk, .caution, "共享容器可能被别的应用共用，默认不勾选")
    }

    /// helper 容器（`包名.helper`）属于同一个 bundle，也要收进来。
    func testDerivedIdentifierContainerIsClaimed() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let helper = try fixture.makeContainer(dirName: "HELP01", identifier: "com.example.MyApp.Helper", withCaches: false)

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        XCTAssertNotNil(report.items.first { $0.path == helper })
    }

    /// 没有包名就没有证据：宁可漏报也不按目录名乱猜容器归属。
    func testNoBundleIDMeansNoContainerClaims() throws {
        _ = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        try fixture.makeContainer(dirName: "A1B2", identifier: "com.example.MyApp")

        let report = ResidualScanner.scan(appName: "My App", bundleID: "", appPath: fixture.homePath,
                                          options: fixture.options(sensitivity: .deep),
                                          measure: ResidualFixture.constantMeasure)
        XCTAssertTrue(report.items.contains { $0.category == .container } == false)
    }

    /// 元数据文件读不出来（损坏/缺失）时退回名称匹配，不崩溃也不认领别人。
    func testMissingMetadataFallsBackToDirectoryName() throws {
        let app = try fixture.makeApp(name: "My App", bundleID: "com.example.MyApp")
        let named = try fixture.makeContainer(dirName: "com.example.MyApp", identifier: nil, withCaches: false)
        _ = try fixture.makeContainer(dirName: "com.other.Unrelated", identifier: nil, withCaches: false)

        let report = scan(fixture, appPath: app, sensitivity: .strict)
        XCTAssertNotNil(report.items.first { $0.path == named }, "目录名等于包名时应按名称命中")
        XCTAssertTrue(report.items.contains { $0.path.contains("com.other.Unrelated") } == false)
    }
}
