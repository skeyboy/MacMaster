import Foundation
import XCTest
@testable import MMCore

/// 删除历史的落盘与跨启动撤回。
///
/// 全程不碰真实废纸篓：`FileManager.trashItem` 会把文件送进 `~/.Trash`，
/// 单测没有权利往那里放东西。所以记录里的 `trashPath` 由临时目录冒充，
/// `undo` 只是把文件从"假废纸篓"搬回原位——被测的是历史的状态机，不是系统的废纸篓。
@MainActor
final class TrashHistoryStoreTests: XCTestCase {
    private var root: URL!
    private var storeURL: URL { root.appendingPathComponent("state/trash-history.json") }
    private var store: TrashHistoryStore { TrashHistoryStore(url: storeURL) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMCoreTrashTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    private func touch(_ name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("0123456789".utf8).write(to: url)
        return url
    }

    private func operation(id: UUID = UUID(), files: [TrashRecord], isUndone: Bool = false) -> TrashOperation {
        var operation = TrashOperation(id: id, timestamp: Date(), files: files, failures: [])
        if isUndone { operation = operation.markedUndone() }
        return operation
    }

    // MARK: 落盘本身

    func testRoundTripKeepsEveryFactNeededToUndo() throws {
        let original = try touch("notes.txt", in: root.appendingPathComponent("home"))
        let trashed = try touch("notes.txt", in: root.appendingPathComponent("trash"))
        let saved = operation(files: [TrashRecord(originalPath: original.path, trashPath: trashed.path, size: 10)])
        store.save([saved])

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, saved.id)
        XCTAssertEqual(loaded[0].timestamp.timeIntervalSince1970,
                       saved.timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(loaded[0].files.first?.originalPath, original.path)
        XCTAssertEqual(loaded[0].files.first?.trashPath, trashed.path)
        // 字节数是"当时"量到的，事后再读原路径只会得到 0，所以必须原样回来。
        XCTAssertEqual(loaded[0].files.first?.size, 10)
    }

    func testMissingFileReadsAsEmptyHistory() {
        XCTAssertTrue(store.load().isEmpty)
    }

    /// 坏掉的历史不能静默覆盖：改名留档，用户随时能自己看一眼。
    func testCorruptFileIsSetAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("这不是 json".utf8).write(to: storeURL)

        XCTAssertTrue(store.load().isEmpty)

        let leftovers = try FileManager.default.contentsOfDirectory(at: storeURL.deletingLastPathComponent(),
                                                                   includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("corrupt") }
        XCTAssertEqual(leftovers.count, 1)
        XCTAssertEqual(try Data(contentsOf: leftovers[0]), "这不是 json".data(using: .utf8))
    }

    // MARK: 跨启动

    func testUndoStillWorksAfterRelaunch() async throws {
        let original = root.appendingPathComponent("home/notes.txt")
        let trashed = try touch("notes.txt", in: root.appendingPathComponent("trash"))
        let saved = operation(files: [TrashRecord(originalPath: original.path, trashPath: trashed.path, size: 10)])
        store.save([saved])

        // 新实例 = 重启后的进程：它只认识磁盘上那份 JSON。
        let service = FileTrashService(store: store)
        XCTAssertEqual(service.trashHistory.count, 1)
        let result = await service.undo(operationID: saved.id)
        XCTAssertEqual(result.restoredCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))

        let relaunched = FileTrashService(store: store)
        XCTAssertEqual(relaunched.trashHistory.first?.id, saved.id)
        XCTAssertEqual(relaunched.trashHistory.first?.isUndone, true)
    }

    func testPartialUndoKeepsFailedFileAvailableForRetryAcrossRelaunch() async throws {
        let home = root.appendingPathComponent("home")
        let trash = root.appendingPathComponent("trash")
        let conflictingOriginal = try touch("a.txt", in: home)
        let trashedA = try touch("a.txt", in: trash)
        let trashedB = try touch("b.txt", in: trash)
        let saved = operation(files: [
            TrashRecord(originalPath: conflictingOriginal.path, trashPath: trashedA.path, size: 10),
            TrashRecord(originalPath: home.appendingPathComponent("b.txt").path,
                        trashPath: trashedB.path, size: 10),
        ])
        store.save([saved])

        let service = FileTrashService(store: store)
        let first = await service.undo(operationID: saved.id)
        XCTAssertEqual(first.restoredCount, 1)
        XCTAssertEqual(first.failures.map(\.path), [conflictingOriginal.path])
        XCTAssertFalse(service.trashHistory[0].isUndone)
        XCTAssertTrue(service.trashHistory[0].canUndo)
        XCTAssertNil(service.trashHistory[0].files[1].trashPath)

        try FileManager.default.removeItem(at: conflictingOriginal)
        let relaunched = FileTrashService(store: store)
        let second = await relaunched.undo(operationID: saved.id)
        XCTAssertEqual(second.restoredCount, 1)
        XCTAssertTrue(second.failures.isEmpty)
        XCTAssertTrue(relaunched.trashHistory[0].isUndone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflictingOriginal.path))
    }

    /// 废纸篓被倒空过的记录要留在台账里，只是不再提供撤回——「最近操作」是历史，
    /// 把它从名单里抹掉等于告诉用户"这次清理没发生过"。
    func testUnrestorableRecordStaysInHistoryWithoutAnUndoPath() throws {
        let gone = root.appendingPathComponent("trash/notes.txt")
        store.save([operation(files: [TrashRecord(originalPath: "/tmp/nope/notes.txt",
                                                  trashPath: gone.path, size: 10)])])
        let loaded = FileTrashService(store: store).trashHistory
        XCTAssertEqual(loaded.count, 1)
        XCTAssertFalse(loaded.first!.canUndo)
    }

    func testUndoWithoutRestorableFilesReportsWhyNothingMoved() async throws {
        let saved = operation(files: [TrashRecord(originalPath: root.appendingPathComponent("home/a.txt").path,
                                                  trashPath: root.appendingPathComponent("trash/a.txt").path)])
        store.save([saved])
        let result = await FileTrashService(store: store).undo(operationID: saved.id)
        XCTAssertEqual(result.restoredCount, 0)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testUndoLastSkipsNewerOperationWithNoMovedFiles() async throws {
        let original = root.appendingPathComponent("home/notes.txt")
        let trashed = try touch("notes.txt", in: root.appendingPathComponent("trash"))
        let restorable = operation(files: [TrashRecord(originalPath: original.path,
                                                        trashPath: trashed.path)])
        let failedOnly = operation(files: [])
        store.save([failedOnly, restorable])

        let service = FileTrashService(store: store)
        let result = await service.undoLastOperation()

        XCTAssertEqual(result.restoredCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(service.trashHistory[1].isUndone)
    }

    /// 已经撤回过的记录要留在名单里（设计稿要的是"长期可查"），即使原文件又没了。
    func testUndoneRecordSurvivesLoadEvenWhenNothingIsRestorable() throws {
        store.save([operation(files: [TrashRecord(originalPath: "/tmp/nope/a.txt",
                                                  trashPath: "/tmp/nope/trash/a.txt", size: 1)],
                              isUndone: true)])
        let loaded = FileTrashService(store: store).trashHistory
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.isUndone, true)
        XCTAssertFalse(loaded.first!.canUndo)
    }

    /// 拿不到 Application Support 时（store 为 nil）历史退回内存，删除本身照常。
    func testServiceWorksWithoutAStore() async throws {
        let service = FileTrashService(store: nil)
        XCTAssertTrue(service.trashHistory.isEmpty)
        let result = await service.undo(operationID: UUID())
        XCTAssertEqual(result.restoredCount, 0)
    }

    /// 清空台账必须内存和磁盘一起清。只清内存的话，下次启动记录又回来了，
    /// 用户在设置页点的"清空"就成了一个假动作。
    func testClearHistoryEmptiesMemoryAndDiskTogether() throws {
        store.save([operation(files: [TrashRecord(originalPath: "/tmp/nope/a.txt",
                                                  trashPath: "/tmp/nope/trash/a.txt", size: 1)]),
                    operation(files: [TrashRecord(originalPath: "/tmp/nope/b.txt",
                                                  trashPath: "/tmp/nope/trash/b.txt", size: 1)])])
        let service = FileTrashService(store: store)
        XCTAssertEqual(service.trashHistory.count, 2)

        service.clearHistory()

        XCTAssertTrue(service.trashHistory.isEmpty)
        XCTAssertTrue(store.load().isEmpty)
    }
}
