//
//  DiskHeaderContractTests.swift — 磁盘页页头副标题的段序合同（P26）
//
//  缺口是 P26 的逐屏窄窗实拍照出来的（`docs/analysis/header-truncation-audit.md` §3）：
//  磁盘页的动作簇是九屏里最宽的一档，1000 pt 窗口下副标题**中段必掉**。
//  旧顺序「占用 · 文件数 · 用时 · 路径」截完是 `77.8 MB · 44…aster-disk-fixture`——
//  "44" 的单位被吃掉，界面上留下两个并排的光数，那是一句核对不了的话。
//
//  这里钉三件事：① 「N 个文件」必须在**尾部**（中间截断保头保尾，单位不许落在中段）；
//  ② 占用必须在**头部**；③ 被牺牲的那一段固定是"扫描用时"，不是任何一个数字的单位。
//
//  钉不住的那一半写在这儿：单测能钉段序，钉不住"这一句在 1000 pt 放不放得下"——
//  那要实机照片，复现命令在 `docs/analysis/header-truncation-audit.md` §7。
//

import XCTest
import Foundation
import MMUI
@testable import MMDisk

final class DiskHeaderContractTests: XCTestCase {

    private func line(path: String = "/tmp/macmaster-disk-fixture",
                      size: UInt64 = 81_612_800,
                      duration: Double = 0.4,
                      count: Int = 44) -> String {
        DiskHeaderCopy.subtitle(size: size, path: path, duration: duration, fileCount: count)
    }

    /// ① 尾部必须是带单位的文件数：窄窗上"保尾"保的就是这一截。
    func testFileCountWithItsUnitHoldsTheTail() {
        let s = line()
        XCTAssertTrue(s.hasSuffix("44 个文件"), "尾部不是带单位的文件数：\(s)")
    }

    /// ② 头部必须是占用——磁盘页最不该没的就是这个数（旧注释里已经认过一次，本轮沿用）。
    func testSizeHoldsTheHead() {
        let s = line()
        let head: UInt64 = 81_612_800
        XCTAssertTrue(s.hasPrefix(MMFormat.bytes(head)), "头部不是占用：\(s)")
    }

    /// ③ 牺牲者固定是"扫描用时"：它排在路径之后、文件数之前，
    /// 所以窄窗上被吃掉的只会是它和路径中段，不会是任何一个数字的单位。
    func testSegmentOrderIsSizePathDurationCount() {
        let s = line()
        let head: UInt64 = 81_612_800
        let marks = [MMFormat.bytes(head), "/tmp/macmaster-disk-fixture",
                     "扫描用时 0.4 s", "44 个文件"].map { s.range(of: $0)!.lowerBound }
        XCTAssertEqual(marks, marks.sorted(), "段序变了：\(s)")
    }

    /// 千位分隔不许把单位挤散：`1,234 个文件` 整段都得到尾部。
    func testGroupedCountKeepsItsUnitAdjacent() {
        XCTAssertTrue(line(count: 1_234).hasSuffix("1,234 个文件"))
    }
}
