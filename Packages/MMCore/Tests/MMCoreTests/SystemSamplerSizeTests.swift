import XCTest
@testable import MMCore

/// `directoryBytes` 的口径：路径下所有非目录文件的实际占块之和。
/// 关键是"隐藏目录也要算进去"——这条曾经被 `.skipsHiddenFiles` 悄悄剪掉，
/// 导致 cargo registry 报成 12 KB（实测 75 MB）。
final class SystemSamplerSizeTests: XCTestCase {

    private var root: URL!
    private let block = 4096

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mm-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 写不可压缩的内容：APFS 会对可压缩块做透明压缩，`totalFileAllocatedSize`
    /// 报的是压缩后的占块，用全 'A' 会让"按块算"的断言飘掉。
    private func write(_ relative: String, blocks: Int) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var data = Data(count: block * blocks)
        _ = data.withUnsafeMutableBytes { ptr in
            for i in 0..<ptr.count { ptr[i] = UInt8(truncatingIfNeeded: i &* 31 &+ i / block) }
        }
        try data.write(to: url)
    }

    func testCountsVisibleAndHiddenFilesInPlainSubdirectory() throws {
        try write("a/visible.bin", blocks: 1)
        try write("a/.dotfile", blocks: 1)
        XCTAssertEqual(SystemSampler.directoryBytes(root.path), UInt64(block * 2))
    }

    func testCountsFilesInsideHiddenSubdirectory() throws {
        // 回归：`.cache/` 这类点开头目录里的文件必须算——cargo registry 的体积
        // 几乎全在 index.crates.io-*/.cache/ 底下。
        try write(".cache/bulk.bin", blocks: 2)
        try write("index/.nested/deep.bin", blocks: 1)
        XCTAssertEqual(SystemSampler.directoryBytes(root.path), UInt64(block * 3))
    }

    func testMissingPathIsNilNotZero() {
        // 没量到 ≠ 0：调用方靠 nil 渲染"—"，折成 0 就是谎报"这里干净"。
        XCTAssertNil(SystemSampler.directoryBytes(root.appendingPathComponent("nope").path))
    }

    func testEmptyDirectoryIsZero() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(SystemSampler.directoryBytes(root.path), 0)
    }
}
