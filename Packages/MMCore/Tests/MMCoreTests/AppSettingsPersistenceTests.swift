import XCTest
@testable import MMCore

/// 设置项的注入 suite 走的是 `AppSettings(defaults:)`，所以这条测试不碰真实用户偏好。
final class AppSettingsPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "MMCoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// 废纸篓监听默认开：这一档关掉之后页面不留任何痕迹，用户不该在"从没设置过"时
    /// 就先错过它；而它本身只在停在应用卸载页时才 arm，默认开的代价足够小。
    func testTrashWatchingDefaultsToOn() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.watchTrashForResidualCleanup)
    }

    func testTrashWatchingPersistsAcrossInstances() {
        let first = AppSettings(defaults: defaults)
        first.watchTrashForResidualCleanup = false
        XCTAssertEqual(defaults.object(forKey: "settings.uninstaller.watchTrashForResidualCleanup") as? Bool, false)
        XCTAssertTrue(AppSettings(defaults: defaults).watchTrashForResidualCleanup == false)
    }
}
