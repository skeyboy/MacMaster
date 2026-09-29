import XCTest
import Darwin
@testable import MMDisk

/// 磁盘分析的口径契约：页面上的图例写着"实际占用（含 APFS 压缩与硬链接去重）"，
/// 这三条测试就是那句图例的可执行版本。哪天 readEntries 退回 st_size，
/// 这里必须炸。
final class DiskScannerSizeTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "mmdisk-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func write(_ name: String, bytes: Int) -> String {
        let path = root + "/" + name
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 0x41, count: bytes))
        return path
    }

    private func allocated(_ path: String) -> UInt64 {
        var info = stat()
        XCTAssertEqual(Darwin.lstat(path, &info), 0)
        return UInt64(max(0, info.st_blocks)) &* 512
    }

    private func scan() async -> [DiskTreeNode] {
        await DiskScanner.childrenOfDirectory(path: root)
    }

    func testFileSizesUseAllocatedBlocksNotApparentSize() async {
        let path = write("blob.bin", bytes: 100_000)
        let nodes = await scan()
        let node = nodes.first { $0.name == "blob.bin" }
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.size, allocated(path))
        // st_blocks 恒为 512 的整数倍，而 100_000 不是，所以相等只可能是
        // 口径退回了 st_size（或者 APFS 压缩后的占用恰好撞上，可忽略）。
        XCTAssertNotEqual(node?.size, UInt64(100_000))
        XCTAssertGreaterThan(node?.size ?? 0, 0)
    }

    func testHardlinksCountOnce() async {
        let source = write("twin-a", bytes: 50_000)
        let twin = root + "/twin-b"
        XCTAssertEqual(Darwin.link(source, twin), 0)

        let nodes = await scan()
        let a = nodes.first { $0.name == "twin-a" }?.size ?? 0
        let b = nodes.first { $0.name == "twin-b" }?.size ?? 0
        XCTAssertEqual(a + b, allocated(source), "同一 inode 的两个名字只应计一次占用")
        XCTAssertTrue([a, b].contains(0))
    }

    func testSymlinkContributesNothing() async {
        let target = write("real.txt", bytes: 10_000)
        XCTAssertEqual(symlink(target, root + "/alias.txt"), 0)

        let nodes = await scan()
        XCTAssertEqual(nodes.first { $0.name == "alias.txt" }?.size, 0)
        XCTAssertGreaterThan(nodes.first { $0.name == "real.txt" }?.size ?? 0, 0)
    }

    func testDirectorySizeIsSumOfChildren() async throws {
        let dir = root + "/sub"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let one = dir + "/a.txt"
        let two = dir + "/b.txt"
        FileManager.default.createFile(atPath: one, contents: Data(repeating: 1, count: 1_000))
        FileManager.default.createFile(atPath: two, contents: Data(repeating: 2, count: 1_000))

        let nodes = await scan()
        let sub = nodes.first { $0.name == "sub" }
        XCTAssertEqual(sub?.size, allocated(one) + allocated(two))
    }
}
