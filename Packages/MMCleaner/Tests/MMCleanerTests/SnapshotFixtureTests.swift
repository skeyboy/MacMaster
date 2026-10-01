import XCTest
@testable import MMCleaner
import MMFileScanner

/// 截图夹具自身的体检。这些文本是"无合成点击取证"唯一的状态来源，
/// 它们要是解析不出预期结构，照片就会拍到一块和真实代码路径不同的界面，
/// 而看上去完全正常。
final class SnapshotFixtureTests: XCTestCase {

    func testEveryFixtureParsesToItsIntendedShape() {
        let expected: [String: Int] = ["mixed": 5, "overflow": 9, "updateonly": 2, "none": 0]
        for (name, count) in expected {
            guard let text = CleanerModel.snapshotFixtureText[name] else {
                return XCTFail("夹具 \(name) 不见了")
            }
            let listing = LocalSnapshotReader.parse(text, fallbackVolume: "/")
            guard case .available(let snapshots) = listing else {
                return XCTFail("夹具 \(name) 解析失败：\(listing.reason ?? "—")")
            }
            XCTAssertEqual(snapshots.count, count, "夹具 \(name) 的条目数不对")
        }
        // 表头与首条之间漏换行会把第一条粘进表头行被吃掉，条数就会少 1。
        let broken = CleanerModel.snapshotFixtureText["broken"] ?? ""
        XCTAssertFalse(LocalSnapshotReader.parse(broken, fallbackVolume: "/").isAvailable,
                       "broken 档要拍到「不可用」那一支")
    }

    func testMixedFixtureCoversAllThreeKinds() {
        guard let text = CleanerModel.snapshotFixtureText["mixed"] else {
            return XCTFail("夹具 mixed 不见了")
        }
        let listing = LocalSnapshotReader.parse(text, fallbackVolume: "/")
        XCTAssertEqual(listing.count(of: .timeMachine), 2)
        XCTAssertEqual(listing.count(of: .systemUpdate), 2)
        XCTAssertEqual(listing.count(of: .other), 1,
                       "分档是这块卡片新加的能力，夹具必须能把它拍出来")
    }
}
