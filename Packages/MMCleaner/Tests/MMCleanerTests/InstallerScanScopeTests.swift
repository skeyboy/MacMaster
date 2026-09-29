import XCTest
@testable import MMCleaner

/// 截图验证钩子的护栏（项目法则第 6 条）：
/// 安装包残留这一屏的删除按钮是真删文件，验证钩子只许指向 /tmp 下的夹具。
/// 这个守卫一旦放行非 /tmp 路径，真实的 ~/Downloads 就可能出现在
/// "已自动勾选 + 确认面板已打开"的状态里——那是一次误触就能兑现的事故。
final class InstallerScanScopeTests: XCTestCase {
    func testValidTmpFixtureIsHonored() {
        XCTAssertEqual(InstallerScanScope.roots(fixtureDir: "/tmp/mm-installer-fixture"),
                       ["/tmp/mm-installer-fixture"])
        XCTAssertEqual(InstallerScanScope.roots(fixtureDir: "/private/tmp/fx"), ["/private/tmp/fx"])
    }

    func testRealHomeIsRefusedAndFallsBackToDefaultScope() {
        // 非 /tmp 前缀：拒绝钩子，返回 nil 让扫描回落到真实（只读）范围，
        // 绝不把用户目录带进自动勾选流程。
        XCTAssertNil(InstallerScanScope.roots(fixtureDir: "/Users/lee/Downloads"))
        XCTAssertNil(InstallerScanScope.roots(fixtureDir: "/tmp"))        // 必须是 /tmp/ 下的目录
        XCTAssertNil(InstallerScanScope.roots(fixtureDir: "/tmpx/fx"))    // 前缀欺骗
        XCTAssertNil(InstallerScanScope.roots(fixtureDir: ""))            // 空值 = 没设钩子
        XCTAssertNil(InstallerScanScope.roots(fixtureDir: nil))
    }
}
