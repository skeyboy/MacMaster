import XCTest
import Foundation
@testable import MMUninstaller

/// 应用目录清单（`AppScanner.defaultSearchDirectories` 的纯那一半）。
///
/// 这一格同时决定两件事：卸载页能看见哪些应用、`AppFolderWatcher` 监听哪些目录
/// （不变量写在 `AppFolderWatcher.watchTargets` 的注释里：**监听范围 = 列举范围**）。
/// 所以"外接卷要目录存在才算"必须是纯函数级能测的 —— 单测不能真插一块盘。
final class AppScannerDirectoriesTests: XCTestCase {

    func testFixedDirectoriesAreAlwaysListedInOrder() {
        XCTAssertEqual(AppScanner.applicationDirectories(home: "/Users/lee", volumePaths: [],
                                                         directoryExists: { _ in true }),
                       ["/Applications", "/Applications/Utilities", "/Users/lee/Applications"])
    }

    /// 外接卷补的是 `<卷>/Applications`，**目录不存在的那卷不收**：
    /// 一块只有影片的移动硬盘不该在监听失败汇总里占一行"读不动"。
    func testVolumeApplicationsAreAppendedOnlyWhenTheyExist() {
        let directories = AppScanner.applicationDirectories(
            home: "/Users/lee",
            volumePaths: ["/Volumes/Data", "/Volumes/Movies"],
            directoryExists: { $0 != "/Volumes/Movies/Applications" })
        XCTAssertEqual(directories,
                       ["/Applications", "/Applications/Utilities", "/Users/lee/Applications",
                        "/Volumes/Data/Applications"])
    }

    /// 启动卷不在这条链上（由 `VolumeRoots.nonBootVolumePaths` 挡掉），这里再钉一次形状：
    /// 传进来的若是 `/`，拼出的 `/Applications` 会与固定那条重复列进监听名单。
    /// 生产路径不会给，所以这一条是"接口不重复、也不许靠调用方自觉"的证据。
    func testCallingSideNeverFeedsTheBootVolume() {
        let roots = AppScanner.defaultSearchDirectories(home: NSHomeDirectory())
        XCTAssertEqual(roots.filter { $0 == "/Applications" }.count, 1, "\(roots)")
        XCTAssertEqual(Set(roots).count, roots.count, "目录名单里不该有重复项：\(roots)")
    }
}
