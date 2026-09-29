import XCTest
@testable import MMFileScanner

/// 重复文件检测的判定边界。这里测的不是"能不能找出重复"，
/// 而是"会不会把不重复的文件报成重复"——后者会让用户删掉自己的文件。
final class DuplicateScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuplicateScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func write(_ name: String, _ data: Data) throws -> FileEntry {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileEntry(
            path: url,
            name: name,
            size: UInt64(values.fileSize ?? data.count),
            isDirectory: false,
            modificationDate: values.contentModificationDate ?? Date()
        )
    }

    /// 前 `sharedBytes` 完全一样、尾部不同的两个文件。
    private func prefixCollidingPair() -> (Data, Data) {
        let shared = 700 * 1024
        var a = Data(count: shared)
        var b = Data(count: shared)
        for i in 0..<shared { a.append(UInt8(i % 251)); b.append(UInt8(i % 251)) }
        a.append(contentsOf: [0x01, 0x02, 0x03])
        b.append(contentsOf: [0xF1, 0xF2, 0xF3])
        return (a, b)
    }

    private func identicalPair(_ payload: Data) -> (Data, Data) { (payload, payload) }

    // MARK: Tests

    func testIdenticalContentIsGroupedOnce() async throws {
        let payload = Data((0..<600_000).map { UInt8($0 % 256) })
        let a = try write("a.bin", payload)
        let b = try write("b.bin", payload)

        let report = await DuplicateScanner().findDuplicates(in: [a, b])

        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups.first?.files.count, 2)
        XCTAssertEqual(report.groups.first?.wastedSpace, UInt64(payload.count))
    }

    func testSamePrefixDifferentTailIsNotADuplicate() async throws {
        let (aData, bData) = prefixCollidingPair()
        XCTAssertEqual(aData.count, bData.count, "两个文件必须一样大，才能验证检测器没有只看大小")
        let a = try write("a.bin", aData)
        let b = try write("b.bin", bData)

        let report = await DuplicateScanner().findDuplicates(in: [a, b])

        XCTAssertTrue(report.groups.isEmpty, "只有前缀相同的文件被判为重复会造成误删")
    }

    func testHardlinkAliasesAreNotReportedAsDuplicates() async throws {
        let payload = Data((0..<600_000).map { UInt8($0 % 251) })
        let original = try write("original.bin", payload)
        let link = root.appendingPathComponent("alias.bin")
        try FileManager.default.linkItem(at: original.path, to: link)

        let alias = FileEntry(path: link, name: link.lastPathComponent, size: UInt64(payload.count),
                              isDirectory: false, modificationDate: Date())
        let report = await DuplicateScanner().findDuplicates(in: [original, alias])

        XCTAssertTrue(report.groups.isEmpty, "同一 inode 的两条路径删掉任何一条都释放不了空间")
        XCTAssertEqual(report.hardlinkAliasSkippedCount, 1)
    }

    func testUnreadableFileNeverFormsAGroup() async throws {
        guard geteuid() != 0 else { throw XCTSkip("root 下 chmod 000 仍然可读") }
        let payload = Data((0..<600_000).map { UInt8($0 % 251) })
        let readable = try write("readable.bin", payload)
        let locked = try write("locked.bin", payload)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path.path)
        let lockedPath = locked.path.path
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedPath)
        }

        let report = await DuplicateScanner().findDuplicates(in: [readable, locked])

        XCTAssertTrue(report.groups.isEmpty,
                      "读不了的文件必须单独报告，不能落到同一个哈希桶里被当成重复")
        XCTAssertEqual(Set(report.unreadablePaths).count, 1)
        XCTAssertTrue(report.unreadablePaths.contains(locked.path.path))
    }

    func testStoppingEarlyMarksTheReportIncomplete() async throws {
        let payload = Data((0..<600_000).map { UInt8($0 % 251) })
        var entries: [FileEntry] = []
        for i in 0..<8 { entries.append(try write("f\(i).bin", payload)) }

        let report = await DuplicateScanner().findDuplicates(in: entries, shouldContinue: { false })

        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.groups.isEmpty, "被停止的扫描不能给出结论")
    }

    func testSmallFilesBelowThresholdAreIgnored() async throws {
        let tiny = Data(count: 1024)
        let a = try write("a.bin", tiny)
        let b = try write("b.bin", tiny)

        let report = await DuplicateScanner(minFileSize: 100 * 1024).findDuplicates(in: [a, b])

        XCTAssertTrue(report.groups.isEmpty)
        XCTAssertEqual(report.candidateCount, 0)
    }
}
