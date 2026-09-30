import Foundation
import XCTest
@testable import MMUninstaller

final class UninstallFixtureHooksTests: XCTestCase {
    func testOnlyPhysicalTemporaryHomesAreAccepted() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("MMUninstallHook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let accepted = try XCTUnwrap(UninstallFixtureHooks.canonicalHome(root.path))
        XCTAssertTrue(accepted.hasPrefix("/private/tmp/") || accepted.hasPrefix("/tmp/"))
        XCTAssertNil(UninstallFixtureHooks.canonicalHome(NSHomeDirectory()))

        let link = root.appendingPathComponent("outside")
        try FileManager.default.createSymbolicLink(at: link,
                                                   withDestinationURL: URL(fileURLWithPath: NSHomeDirectory()))
        XCTAssertNil(UninstallFixtureHooks.canonicalHome(link.path))
    }
}
