//
//  NotificationStatusTests.swift — 通知授权状态到文案的映射
//
//  真正的授权读取要 .app bundle 里的 UNUserNotificationCenter（单测进程里碰它会崩），
//  所以这里只钉"状态 → 用户看到哪一句"这一层：这一层的错是"系统已经拒了，界面还说没事"。
//

import XCTest
import UserNotifications
@testable import MMMonitor

final class NotificationStatusTests: XCTestCase {

    func testAuthorizedNeedsNoWarning() {
        XCTAssertNil(NotificationStatusModel.caption(for: .authorized))
        XCTAssertFalse(NotificationStatusModel.needsSystemSettings(for: .authorized))
    }

    /// 被拒时最要命的是"开关看着是开的"，所以文案必须点破开关不顶用。
    func testDeniedSaysTheSwitchAloneIsNotEnough() {
        let text = NotificationStatusModel.caption(for: .denied)
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("拒绝"))
        XCTAssertTrue(text!.contains("开关"))
        XCTAssertTrue(NotificationStatusModel.needsSystemSettings(for: .denied))
    }

    func testNotDeterminedAndProvisionalBothPointAtSystemSettings() {
        XCTAssertTrue(NotificationStatusModel.needsSystemSettings(for: .notDetermined))
        XCTAssertTrue(NotificationStatusModel.needsSystemSettings(for: .provisional))
        XCTAssertNotNil(NotificationStatusModel.caption(for: .notDetermined))
        XCTAssertNotNil(NotificationStatusModel.caption(for: .provisional))
    }

    /// 拿不到状态（脱离 bundle 跑）不该伪装成"已授权"，也不该给一个跳过去找不到东西的链接。
    func testUnavailableStatusIsHonestAndGivesNoLink() {
        XCTAssertNotNil(NotificationStatusModel.caption(for: nil))
        XCTAssertFalse(NotificationStatusModel.needsSystemSettings(for: nil))
    }
}
