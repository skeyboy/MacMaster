import Foundation
import XCTest
import Darwin
@testable import MMCore

/// 删除执行处的复验：`trashItem` / `removeItem` 没抛错，不等于东西真的走了。
///
/// 参考侧那一手是"删完立刻回看一眼，还在原地就当失败"（`Services/DeletionExecutor.swift:86-112`）。
/// 这一组钉两件事：① 复验确实接进了上报（假成功翻成 `STILL_PRESENT`，且不留撤回凭据）；
/// ② 它没有把真删除挡下来（正常移除照样只出一条成功记录）。
/// 全程只在 `temporaryDirectory` 下按 UUID 开一间，写自己的文件、删自己的文件；
/// 真废纸篓一次都不碰（本机 `~/.Trash` 读不到，落点回不来，现场清不掉）。
@MainActor
final class FileTrashServiceReverifyTests: XCTestCase {

    private let fileManager = FileManager.default
    private var scratch: String!

    override func setUpWithError() throws {
        scratch = fileManager.temporaryDirectory
            .appendingPathComponent("MMReverify-\(UUID().uuidString)", isDirectory: true).path
        try fileManager.createDirectory(atPath: scratch!, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { chmod(scratch, 0o755) }
        if let scratch { try? fileManager.removeItem(atPath: scratch) }
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int = 4096) throws -> String {
        let path = scratch! + "/" + relative
        try fileManager.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true)
        fileManager.createFile(atPath: path, contents: Data(repeating: 0x41, count: bytes))
        return path
    }

    // MARK: - 复验接进了上报

    /// 假成功：调用方没抛错、东西还在原地 → 报失败，`successCount` 归零，
    /// 而且**不写撤回凭据**（台账里那条"从哪来、到哪去"这时是假的，撤回按钮会指向一个原地未动的条目）。
    func testPhantomTrashIsReportedAsFailureWithNoUndoCredential() async throws {
        let service = FileTrashService(store: nil)
        let path = try write("victim.bin")
        service.trashStep = { _ in "/tmp/一个并不存在的落点.bin" }

        let result = await service.moveToTrash(paths: [path])
        XCTAssertEqual(result.successCount, 0, "还在原地的东西不能算移走成功")
        let failure = try XCTUnwrap(result.operation.failures.first)
        XCTAssertEqual(failure.code, "STILL_PRESENT")
        XCTAssertFalse(failure.message.isEmpty, "光一个错误码说明不了用户该做什么")
        XCTAssertTrue(fileManager.fileExists(atPath: path))

        let operation = try XCTUnwrap(service.trashHistory.first)
        XCTAssertTrue(operation.files.isEmpty, "假成功不该进台账的撤回凭据")
        XCTAssertEqual(operation.failures.first?.code, "STILL_PRESENT")
        XCTAssertFalse(operation.canUndo)
    }

    /// 反向：真把东西移走了（这里用等价的一步"原路径消失"来代表），复验必须放行，
    /// 一条失败都不许多报。这一条是上面那条的否证——复验不是把每次删除都判成可疑。
    func testRealRemovalPassesTheReverifyUnchanged() async throws {
        let service = FileTrashService(store: nil)
        let path = try write("gone-for-real.bin")
        service.trashStep = { target in
            try FileManager.default.removeItem(atPath: target)
            return "/tmp/夹具废纸篓/gone-for-real.bin"
        }

        let result = await service.moveToTrash(paths: [path])
        XCTAssertEqual(result.successCount, 1)
        XCTAssertTrue(result.operation.failures.isEmpty, "复验不该把正常删除也报一条")
        XCTAssertEqual(result.operation.files.first?.trashPath, "/tmp/夹具废纸篓/gone-for-real.bin")
        XCTAssertGreaterThan(result.totalSize, 0, "体积是在移走之前量好的，复验不该把它抹掉")
    }

    /// 一批里混一条假成功：各记各的，被复验拦下的那条不拖累其它条。
    func testPhantomInABatchStaysSeparate() async throws {
        let service = FileTrashService(store: nil)
        let phantom = try write("phantom.bin")
        let reallyGone = try write("really-gone.bin")
        service.trashStep = { target in
            if target == phantom { return "/tmp/夹具废纸篓/phantom.bin" }
            try FileManager.default.removeItem(atPath: target)
            return "/tmp/夹具废纸篓/really-gone.bin"
        }

        let result = await service.moveToTrash(paths: [phantom, reallyGone])
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.operation.files.map(\.originalPath), [reallyGone])
        XCTAssertEqual(result.operation.failures.map(\.path), [phantom])
        XCTAssertTrue(fileManager.fileExists(atPath: phantom), "报失败的那一条必须还在原地，否则用户没法重试")
    }

    /// 永久删除那一侧同一句话，而且代价更高：它没有废纸篓兜底，也没有撤回按钮。
    /// 同时钉住"失败那条不计体积"——释放量只能由真正走了的那些项构成。
    func testPhantomPermanentDeleteIsNotCountedAsDeleted() async throws {
        let service = FileTrashService(store: nil)
        let path = try write("still-here.bin", bytes: 128 * 1024)
        service.eraseStep = { _ in }

        let result = await service.permanentlyDelete(paths: [path])
        XCTAssertTrue(result.deleted.isEmpty)
        XCTAssertEqual(try XCTUnwrap(result.failures.first).code, "STILL_PRESENT")
        XCTAssertEqual(result.totalSize, 0, "没删掉的东西不能算进释放量")
        XCTAssertTrue(fileManager.fileExists(atPath: path))
    }

    /// 原地换成了**另一个**目录项：老那条确实走了。这是真机上最容易撞上的一次"路径还在"——
    /// 跑着的应用把它刚被移走的缓存文件立刻写回来。报成失败等于把一次真删除说成没发生，
    /// 而且用户会对着同一个名字再按一次。
    func testReplacedEntryIsNotReportedAsAFailure() async throws {
        let service = FileTrashService(store: nil)
        let path = try write("cache.bin")
        service.eraseStep = { target in
            try FileManager.default.removeItem(atPath: target)
            FileManager.default.createFile(atPath: target, contents: Data(repeating: 0x42, count: 2048))
        }

        let result = await service.permanentlyDelete(paths: [path])
        XCTAssertEqual(result.successCount, 1, "名字被新文件占了，不意味着老那条没被删掉")
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertGreaterThan(result.totalSize, 0, "体积按移走之前那一条算，新写回来的那条不算我们的账")
    }

    // MARK: - 复验用的那"一眼"本身

    /// 为什么用 `lstat` 不用 `fileExists`，而且是**整条链**上的一次证明：
    /// 断链（悬空符号链接）在 `fileExists` 那里读成"不存在"，而它实实在在还占着一个目录项——
    /// 这一档如果按 `fileExists` 复验，假成功会一路绿灯。
    func testDanglingSymlinkIsCaughtByTheWholeChain() async throws {
        let link = scratch! + "/dangling.link"
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: scratch! + "/没有这个目标")
        XCTAssertFalse(fileManager.fileExists(atPath: link), "前提：这一档 fileExists 会说「没有」")

        let service = FileTrashService(store: nil)
        service.eraseStep = { _ in }   // 假成功：什么都没做
        let result = await service.permanentlyDelete(paths: [link])
        XCTAssertEqual(try XCTUnwrap(result.failures.first).code, "STILL_PRESENT")
        XCTAssertTrue(result.deleted.isEmpty)
    }

    /// 三条读法各自要对上哪一件事：查不到 = `gone`；`EACCES` 这类核不了 ≠ 还在原地。
    func testAftermathNamesTheThreeReadingsApart() throws {
        let path = try write("ordinary.bin")
        var info = stat()
        XCTAssertEqual(Darwin.lstat(path, &info), 0)
        let identity = (dev: UInt64(truncatingIfNeeded: info.st_dev), ino: UInt64(truncatingIfNeeded: info.st_ino))

        XCTAssertEqual(FileTrashService.aftermath(atPath: path, movedFrom: identity), .sameEntry)
        XCTAssertEqual(FileTrashService.aftermath(atPath: scratch! + "/没写过.bin", movedFrom: identity), .gone)

        guard geteuid() != 0 else { throw XCTSkip("root 之下权限位不生效，`unverifiable` 这一档造不出来") }
        let sealed = scratch! + "/sealed"
        try fileManager.createDirectory(atPath: sealed, withIntermediateDirectories: true)
        let inside = sealed + "/inside.bin"
        fileManager.createFile(atPath: inside, contents: Data([0x41]))
        chmod(sealed, 0o000)
        defer { chmod(sealed, 0o755) }

        XCTAssertEqual(Darwin.lstat(inside, &info), -1, "前提：这一档确实核对不了")
        XCTAssertEqual(errno, EACCES, "前提：不是 ENOENT，否则这条测的是别的东西")
        XCTAssertEqual(FileTrashService.aftermath(atPath: inside, movedFrom: nil), .unverifiable)
    }
}
