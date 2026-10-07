//
//  DiskHeaderContractTests.swift — 磁盘页页头副标题的段序合同（P26）
//
//  缺口是 P26 的逐屏窄窗实拍照出来的（`docs/analysis/header-truncation-audit.md` §3）：
//  磁盘页的动作簇是九屏里最宽的一档，1000 pt 窗口下副标题**中段必掉**。
//  旧顺序「占用 · 文件数 · 用时 · 路径」截完是 `77.8 MB · 44…aster-disk-fixture`——
//  "44" 的单位被吃掉，界面上留下两个并排的光数，那是一句核对不了的话。
//
//  这里钉三件事：① 「N 个文件」必须在**尾部**（中间截断保头保尾，单位不许落在中段）；
//  ② 占用必须在**头部**；③ 整句只有三段——中段唯一的牺牲者是路径的腰，页头不许有
//  第二个数字来抢那条被拦腰切的缝（「扫描用时」因此出页头，见 :③ 的注释）。
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
                      count: Int = 44) -> String {
        DiskHeaderCopy.subtitle(size: size, path: path, fileCount: count)
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

    /// ③ 中段只留给路径：整句恰好三段，被切成半句的只可能是路径的腰。
    /// 「扫描用时」在 P26 之前是第四段，实拍两次都不肯安静地整段消失——
    /// 旧序截成 `44…`（单位没了），新序截成 `….1 s`（真值 0.1 s 画成 1 s）。
    /// 所以这一条钉的是"页头上不再有任何会被拦腰切的数字"。
    func testOnlyThePathIsSacrificial() {
        let s = line()
        let segments = s.components(separatedBy: " · ")
        XCTAssertEqual(segments.count, 3, "页头副标题不是三段：\(s)")
        XCTAssertEqual(segments, [MMFormat.bytes(UInt64(81_612_800)),
                                 "/tmp/macmaster-disk-fixture", "44 个文件"], "段序或措辞变了：\(s)")
        XCTAssertFalse(s.contains(" s"), "页头又出现了秒数（中间截断会把它切成假话）：\(s)")
    }

    /// 千位分隔不许把单位挤散：`1,234 个文件` 整段都得到尾部。
    func testGroupedCountKeepsItsUnitAdjacent() {
        XCTAssertTrue(line(count: 1_234).hasSuffix("1,234 个文件"))
    }
}
