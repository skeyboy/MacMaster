import XCTest
import Foundation
import MMCore
@testable import MMUninstaller

/// 卸载页"能删哪儿"的口径（`UninstallerModel.deletionRoots`）。
///
/// 这一组不真的把东西送进废纸篓：正向闸本身是纯路径判断（判据在 MMCore 的
/// `DeletionGuardTests` 里钉），这里要钉的是**接线**——根清单跟着夹具的 home 走、
/// 没扫系统域时 `/Library` 不在授权范围内、以及应用目录与 Library 根两边都收进来。
@MainActor
final class UninstallerDeletionRootsTests: XCTestCase {

    private func model(with fixture: ResidualFixture, systemRoot: String? = nil) -> UninstallerModel {
        let model = UninstallerModel()
        model.optionsFactory = {
            ResidualScanOptions(home: fixture.homePath, systemRoot: systemRoot ?? fixture.systemPath)
        }
        model.appDirectoriesFactory = { _ in [fixture.homePath + "/Applications"] }
        model.provenancePrefixesFactory = { _ in [] }
        model.provenanceReceiptsRootFactory = { _ in nil }
        return model
    }

    func testRootsCoverTheAppDirectoryAndBothLibraryDomains() throws {
        let fixture = try ResidualFixture(caseName: "deletionRoots")
        defer { fixture.cleanup() }
        let roots = model(with: fixture).deletionRoots(for: ResidualScanOptions(home: fixture.homePath,
                                                                                systemRoot: fixture.systemPath))
        XCTAssertTrue(roots.contains(fixture.homePath + "/Applications"), "\(roots)")
        XCTAssertTrue(roots.contains(fixture.homePath + "/Library"), "\(roots)")
        XCTAssertTrue(roots.contains(fixture.systemPath + "/Library"), "\(roots)")
    }

    /// 应用本体与它扫出来的残留都在授权范围内 —— 包括 `ContainerScanner` 那种
    /// 要下探两层的容器路径。
    func testAppAndItsResidualsAreInsideTheRoots() throws {
        let fixture = try ResidualFixture(caseName: "deletionRoots")
        defer { fixture.cleanup() }
        let appPath = try fixture.makeApp(name: "Foo", bundleID: "com.example.Foo")
        let cache = try fixture.folderWithFile(fixture.libraryFolder("Caches") + "/com.example.Foo")
        let container = try fixture.folderWithFile(
            fixture.libraryFolder("Containers") + "/com.example.Foo/Data/Library/Caches")

        let roots = model(with: fixture).deletionRoots(for: ResidualScanOptions(home: fixture.homePath,
                                                                                systemRoot: fixture.systemPath))
        for path in [appPath, cache, container] {
            XCTAssertTrue(DeletionGuard.isInside(path, roots: roots), "\(path) 应当可删，roots=\(roots)")
        }
    }

    /// 这一片是这道闸存在的理由：卸载页从没见过 `/System/Applications` 里的东西，
    /// 那它就不该删得掉。注意闸只管**位置**不管**归属** —— 同一层 Library 里别人家的
    /// 数据目录（`~/Library/Application Support/另一个应用`）在位置上是合格的，
    /// 把它降级成默认不勾选是归属复核（`ResidualOwnershipReview`）的活，不是这道闸的活。
    func testUninstallerCannotReachOutsideItsOwnListing() throws {
        let fixture = try ResidualFixture(caseName: "deletionRoots")
        defer { fixture.cleanup() }
        let roots = model(with: fixture).deletionRoots(for: ResidualScanOptions(home: fixture.homePath,
                                                                                systemRoot: fixture.systemPath))
        for path in ["/System/Applications/Calculator.app",
                     "/Applications/Other.app",
                     fixture.homePath + "/Documents/报告.docx",
                     fixture.homePath + "/Applications",
                     fixture.homePath + "/Library",
                     fixture.systemPath + "/private/tmp/别的什么"] {
            XCTAssertFalse(DeletionGuard.isInside(path, roots: roots), "\(path) 不该在授权范围内")
        }
        XCTAssertTrue(DeletionGuard.isInside(fixture.homePath + "/Library/Application Support/另一个应用",
                                             roots: roots), "位置合格，归属另判")
    }

    /// 没扫系统域（`systemRoot` 为空，真实机型默认就是这样）时，`/Library` 也不该被授权：
    /// 看不见的位置给写权限，等于把闸门按最坏那次扫描的口径放宽。
    func testSystemDomainIsNotAuthorizedWhenItWasNotScanned() throws {
        let fixture = try ResidualFixture(caseName: "deletionRoots")
        defer { fixture.cleanup() }
        let roots = model(with: fixture, systemRoot: "").deletionRoots(for: ResidualScanOptions(home: fixture.homePath))
        XCTAssertFalse(roots.contains { $0.hasSuffix("/system/Library") }, "\(roots)")
        XCTAssertFalse(DeletionGuard.isInside("/Library/Caches/com.example.Foo", roots: roots))
        XCTAssertNotNil(DeletionGuard.allowedRootRejection(for: "/Library/Caches/com.example.Foo", roots: roots))
    }
}
