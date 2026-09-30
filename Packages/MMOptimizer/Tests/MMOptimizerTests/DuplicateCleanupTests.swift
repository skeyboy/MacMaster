import Foundation
import MMFileScanner
import XCTest
@testable import MMOptimizer

@MainActor
final class DuplicateCleanupTests: XCTestCase {
    func testFailedMoveRemainsInDuplicateGroup() {
        let files = ["kept", "moved", "failed"].map { name in
            DuplicateFile(path: URL(fileURLWithPath: "/tmp/\(name)"), size: 10,
                          modificationDate: .distantPast)
        }
        let group = DuplicateGroup(hash: "same-content", size: 10, files: files)

        let remaining = DuplicateScanModel.remainingGroups([group], moved: ["/tmp/moved"])

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].files.map { $0.path.lastPathComponent }, ["kept", "failed"])
        XCTAssertEqual(remaining[0].wastedSpace, 10)
    }
}
