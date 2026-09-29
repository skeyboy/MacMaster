import XCTest
import Foundation
@testable import MMDisk

/// 全量扫描必须把子层带回来：treemap 的多层嵌套、下钻预取、详情面板的
/// "内部构成"全都依赖 children。children 为空时界面不会报错，只会
/// 安静地画一张只有顶层的平面图——所以这条要钉住。
final class DiskScannerHierarchyTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "mmdisk-tree-\(UUID().uuidString)"
        let fm = FileManager.default
        for depth in 0..<4 {
            var path: String = root!
            for level in 0...depth {
                path += "/dir\(level)"
            }
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            fm.createFile(atPath: path + "/payload.bin",
                          contents: Data(repeating: 0x5A, count: 40_000))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func testPerformScanKeepsChildrenAtEveryLevel() async {
        let output = await DiskScanner.performScan(rootPath: root)
        XCTAssertFalse(output.topItems.isEmpty)

        var node = output.topItems.first { $0.isDirectory }
        var depth = 0
        while let current = node, !current.children.isEmpty {
            node = current.children.first { $0.isDirectory }
            depth += 1
        }
        XCTAssertGreaterThanOrEqual(depth, 3, "四层目录树至少应带下三层 children，实际 \(depth)")
    }

    func testRealDirectoryScanKeepsChildren() async throws {
        // 真实目录：Developer 下必然还有内容，用来验证权限/枚举分支没有吞掉子层。
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer").path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw XCTSkip("无 Developer 目录")
        }
        let output = await DiskScanner.performScan(rootPath: path)
        let withChildren = output.topItems.filter { !$0.children.isEmpty }
        XCTAssertFalse(withChildren.isEmpty, "顶层块全部没有 children，treemap 会退化成单层图")
    }
}
