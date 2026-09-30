import XCTest
@testable import MMCleaner

final class UserFolderCleanupTests: XCTestCase {
    func testSuccessfulParentMoveCoversChildrenButFailedSiblingRemains() {
        let moved = Set(["/tmp/folder/Build"])
        XCTAssertTrue(UserFolderCleanup.wasMoved("/tmp/folder/Build", under: moved))
        XCTAssertTrue(UserFolderCleanup.wasMoved("/tmp/folder/Build/installer.dmg", under: moved))
        XCTAssertFalse(UserFolderCleanup.wasMoved("/tmp/folder/Build-old", under: moved))
        XCTAssertFalse(UserFolderCleanup.wasMoved("/tmp/folder/Failed", under: moved))
    }

    func testUnknownSelectedInstallerSizeDoesNotBecomeZero() {
        XCTAssertEqual(UserFolderCleanup.selectedSize(paths: ["/tmp/a", "/tmp/b"],
                                                      lookup: ["/tmp/a": 25, "/tmp/b": 10]), 35)
        XCTAssertNil(UserFolderCleanup.selectedSize(paths: ["/tmp/a", "/tmp/b"],
                                                     lookup: ["/tmp/a": 25]))
    }
}
