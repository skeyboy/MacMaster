import Foundation
import XCTest
@testable import MMCore

/// 永久删除那条路径。它没有撤回，所以每一条断言都得自己站得住：
/// 测试全程只在 `temporaryDirectory` 下按 UUID 单独开一间，写自己的文件、删自己的文件；
/// 危险路径一律用"位于保护清单之下、但本机并不存在"的探针路径代表——闸门万一失效，
/// 拿到的会是 ENOENT 而不是 PROTECTED，测试照样报红，而真实用户文件一个都不会少。
@MainActor
final class PermanentDeleteTests: XCTestCase {

    private let fileManager = FileManager.default
    private var scratch: String!

    override func setUpWithError() throws {
        scratch = fileManager.temporaryDirectory
            .appendingPathComponent("MMPermanent-\(UUID().uuidString)", isDirectory: true).path
        try fileManager.createDirectory(atPath: scratch!, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? fileManager.removeItem(atPath: scratch) }
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int) throws -> String {
        let path = scratch! + "/" + relative
        try fileManager.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true)
        fileManager.createFile(atPath: path, contents: Data(repeating: 0x41, count: bytes))
        return path
    }

    /// 删掉就是删掉：文件不在、字节如实记数，而且**不留台账**。
    /// 台账是撤回的依据，永久删除没有"放回原处"可写，混进去只会多一个点不动的撤回按钮。
    func testOrdinaryFileIsGoneWithNoHistoryEntry() async throws {
        let service = FileTrashService(store: nil)
        let path = try write("victim.bin", bytes: 512 * 1024)
        let result = await service.permanentlyDelete(paths: [path])

        XCTAssertEqual(result.successCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: path), "说删了却没删，比报错更糟")
        XCTAssertGreaterThan(result.totalSize, 0, "释放量要在删除前量好，事后原路径只剩 0")
        XCTAssertTrue(service.trashHistory.isEmpty, "不可恢复的操作不该出现在「最近操作」里")
    }

    /// 目录连同整棵子树一起走，一条记录对应一次用户看得见的标记。
    func testDirectorySubtreeGoesTogether() async throws {
        let service = FileTrashService(store: nil)
        _ = try write("tree/a.bin", bytes: 64 * 1024)
        _ = try write("tree/deep/b.bin", bytes: 64 * 1024)
        let dir = scratch! + "/tree"
        let result = await service.permanentlyDelete(paths: [dir])

        XCTAssertEqual(result.successCount, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: dir))
        XCTAssertFalse(fileManager.fileExists(atPath: dir + "/deep/b.bin"))
    }

    /// 闸门同样管着这条路径：保护清单下的路径一个字节都不动，并逐条给出原因。
    func testProtectedPathIsRefusedAndUntouched() async throws {
        let service = FileTrashService(store: nil)
        let probe = NSHomeDirectory() + "/Library/Keychains/探针-\(UUID().uuidString).keychain-db"
        let result = await service.permanentlyDelete(paths: [probe])

        XCTAssertEqual(result.deleted.isEmpty, true)
        let failure = try XCTUnwrap(result.failures.first)
        XCTAssertEqual(failure.code, "PROTECTED")
        XCTAssertFalse(failure.message.isEmpty, "拒绝要带原因，光一个错误码说明不了什么")
        XCTAssertFalse(fileManager.fileExists(atPath: probe))
    }

    /// 混一批：被挡的那条不拖累其它条，也不会有任何一条被静默吞掉——
    /// 界面按 deleted / failures 逐条显示才有机会把下落说清楚。
    /// 保护路径同样用"不存在于本机"的探针：闸门万一失效，删掉的是我编出来的路径，
    /// 而不是用户真的 `~/.ssh/config`。
    func testBatchKeepsProtectedAndOrdinaryApart() async throws {
        let service = FileTrashService(store: nil)
        let kept = try write("ok.bin", bytes: 32 * 1024)
        let probe = NSHomeDirectory() + "/.ssh/探针-\(UUID().uuidString).key"
        let result = await service.permanentlyDelete(paths: [probe, kept])

        XCTAssertEqual(result.deleted.map(\.path), [kept])
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.failures.first?.code, "PROTECTED")
        XCTAssertFalse(fileManager.fileExists(atPath: kept))
    }

    /// 标记到按下之间隔着一次重扫，路径可能已经没了。这不是崩，是事实：
    /// 失败原因得来自文件系统，而不是被闸门误伤。
    func testVanishedPathFailsWithoutTrippingTheGate() async throws {
        let service = FileTrashService(store: nil)
        let missing = scratch! + "/already-gone.bin"
        let result = await service.permanentlyDelete(paths: [missing])

        XCTAssertTrue(result.deleted.isEmpty)
        XCTAssertEqual(result.failures.first?.code != "PROTECTED", true)
    }
}
