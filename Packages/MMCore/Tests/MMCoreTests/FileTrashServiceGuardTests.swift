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

    // MARK: - 正向闸（允许根）

    /// 清单之外的位置删不掉，而且要记成 `OUT_OF_SCOPE` 而不是 `PROTECTED` ——
    /// 前者是"这个功能不该碰那里"，后者是"那里绝对不能碰"，界面与排障要能分清。
    /// 用的路径在临时目录里、并不存在：闸门一旦失效，失败来自 ENOENT，测试照样报红。
    func testPathOutsideAllowedRootsIsRefusedWithItsOwnCode() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mm-roots-\(UUID().uuidString)", isDirectory: true)
        let missing = dir.appendingPathComponent("Foo.app").path
        let result = await service().moveToTrash(paths: [missing], allowedRoots: ["/Applications"])
        XCTAssertEqual(result.successCount, 0)
        let failure = try XCTUnwrap(result.operation.failures.first)
        XCTAssertEqual(failure.code, "OUT_OF_SCOPE")
        XCTAssertFalse(failure.message.isEmpty)
    }

    /// 否证：给了允许根不等于把黑名单换成白名单。根内的东西若同时位于保护区，
    /// 仍按 `PROTECTED` 挡 —— 两道闸是叠加的，正向那道只会更严。
    func testAllowedRootsNeverOverrideTheDenylist() async throws {
        let home = NSHomeDirectory()
        let credential = home + "/.ssh/探针-\(UUID().uuidString)"
        let result = await service().moveToTrash(paths: [credential],
                                                 allowedRoots: [home + "/.ssh", home])
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(try XCTUnwrap(result.operation.failures.first).code, "PROTECTED")
    }

    /// 不传允许根时行为一字不变（清理页、磁盘页走的就是这一条）。
    /// 这里断言的是"根外路径照样能走到文件系统那一层"，即 ENOENT 而不是 OUT_OF_SCOPE。
    func testNilAllowedRootsKeepsTheOldBehavior() async throws {
        let missing = NSTemporaryDirectory() + "mm-roots-\(UUID().uuidString).txt"
        let result = await service().moveToTrash(paths: [missing], allowedRoots: nil)
        let failure = try XCTUnwrap(result.operation.failures.first)
        XCTAssertNotEqual(failure.code, "OUT_OF_SCOPE")
    }

    /// 永久删除那条出口同样接闸：它没有废纸篓兜底，误删的代价更高，不该是第二套规矩。
    func testPermanentDeleteHonoursAllowedRoots() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mm-roots-\(UUID().uuidString)", isDirectory: true)
        let kept = dir.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createFile(atPath: kept.path, contents: Data())
        let result = await service().permanentlyDelete(paths: [kept.path], allowedRoots: ["/Applications"])
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(try XCTUnwrap(result.failures.first).code, "OUT_OF_SCOPE")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "挡下之后文件必须还在")
        try? FileManager.default.removeItem(at: dir)
    }
}
