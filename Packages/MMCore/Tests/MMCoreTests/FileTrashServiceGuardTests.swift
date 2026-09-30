import Foundation
import XCTest
@testable import MMCore

/// 闸门确实接在删除出口上。
///
/// `DeletionGuardTests` 只测纯字符串判断，改不动那份清单接在哪儿；这一组测的是
/// `moveToTrash` 那条**真会删东西**的路径。全程不碰真实用户文件：危险路径一律用
/// "位于保护目录之下、但并不存在"的路径来代表。万一闸门失效，`trashItem` 会因为
/// ENOENT 失败，拿到的 code 就不是 `PROTECTED`，测试照样报红 —— 而我们从来没有
/// 机会把用户真实存在的文件送进废纸篓（`~/.Trash` 本机读不到，也就无法清理现场）。
@MainActor
final class FileTrashServiceGuardTests: XCTestCase {

    private func service() -> FileTrashService { FileTrashService(store: nil) }

    /// 保护清单里的路径：一条失败记录、code 是 PROTECTED、没有任何文件被移走。
    func testProtectedPathIsReportedNotTrashed() async throws {
        let missing = NSHomeDirectory() + "/Library/Keychains/探针-\(UUID().uuidString).keychain-db"
        let result = await service().moveToTrash(paths: [missing])

        XCTAssertEqual(result.successCount, 0, "被挡下的路径不能算移走成功")
        XCTAssertEqual(result.errorCount, 1)
        let failure = try XCTUnwrap(result.operation.failures.first)
        XCTAssertEqual(failure.code, "PROTECTED")
        XCTAssertEqual(failure.path, missing)
        XCTAssertFalse(failure.message.isEmpty, "拒绝要带原因，光一个错误码用户不知道发生了什么")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing))
    }

    /// 空路径同样从这里挡掉：传给 `URL(fileURLWithPath:)` 它会变成当前工作目录，
    /// 那是比删错文件更糟的事故。
    func testEmptyPathIsRefusedAtTheGate() async throws {
        let result = await service().moveToTrash(paths: [""])
        XCTAssertEqual(result.successCount, 0)
        let failure = try XCTUnwrap(result.operation.failures.first)
        XCTAssertEqual(failure.code, "PROTECTED")
    }

    /// 反向证明闸门没有把一切都挡死：普通路径要能走到文件系统那一层。
    /// 这里用一个 /tmp 下不存在的文件，失败来自 ENOENT 而不是 PROTECTED。
    func testOrdinaryPathReachesTheFileSystemLayer() async throws {
        let missing = NSTemporaryDirectory() + "mm-guard-\(UUID().uuidString).txt"
        let result = await service().moveToTrash(paths: [missing])
        XCTAssertEqual(result.errorCount, 1)
        let failure = try XCTUnwrap(result.operation.failures.first)
        XCTAssertNotEqual(failure.code, "PROTECTED", "非保护路径不该被闸门拦下")
    }

    /// 一批里混进保护路径时，被挡的那条单独记账，不影响批次里其它判断，
    /// 也不会悄悄少一条 —— 界面按 failures 逐条显示才有机会说明白。
    func testBatchKeepsOneFailurePerRefusedPath() async throws {
        let home = NSHomeDirectory()
        let paths = [
            home + "/Desktop",                                     // 目录本身
            home + "/Library/Keychains/探针-\(UUID().uuidString)",  // 凭证子树
            "/System/Library/CoreServices/Finder.app",             // 系统域
        ]
        let result = await service().moveToTrash(paths: paths)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 3)
        XCTAssertEqual(Set(result.operation.failures.compactMap(\.code)), ["PROTECTED"])
        XCTAssertEqual(Set(result.operation.failures.map(\.path)), Set(paths))
    }

    /// 闸门不能把「用户文件夹清理」这一页堵死：那六个目录的**内容**必须放行。
    /// 这里用 `~/Documents` 下一个不存在的文件，期望失败来自文件系统（ENOENT），
    /// 而不是 PROTECTED —— 真实文件一个都不碰。
    func testUserDataContentsStillReachTheFileSystemLayer() async throws {
        let missing = NSHomeDirectory() + "/Documents/探针-\(UUID().uuidString).txt"
        let result = await service().moveToTrash(paths: [missing])
        XCTAssertEqual(result.errorCount, 1)
        let failure = try XCTUnwrap(result.operation.failures.first)
        XCTAssertNotEqual(failure.code, "PROTECTED", "用户目录里的单项不该被闸门拦下")
    }

    /// 台账必须如实记下"这一条是被挡的"：历史页如果只按 files 计数，
    /// 用户会看到一次空操作，而拒绝的理由就丢了。
    func testRefusalIsWrittenIntoHistory() async throws {
        let service = service()
        let result = await service.moveToTrash(paths: ["/etc/hosts"])
        XCTAssertEqual(service.trashHistory.count, 1)
        let operation = try XCTUnwrap(service.trashHistory.first)
        XCTAssertEqual(operation.id, result.operation.id)
        XCTAssertTrue(operation.files.isEmpty)
        XCTAssertEqual(operation.failures.first?.code, "PROTECTED")
    }
}
