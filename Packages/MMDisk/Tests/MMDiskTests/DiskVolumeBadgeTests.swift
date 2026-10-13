//
//  DiskVolumeBadgeTests.swift — 磁盘页「还有 N 卷可以切换分析」的措辞合同（P35b A 档）
//
//  合同表在 `docs/analysis/disk-volume-enumeration.md` §9，四行状态各有各的允许与禁止。
//  这一族最贵的一类错不是画不出来，是**说多**：本机候选根恒为 1（一块内部盘），
//  所以"还有 N 卷"那一档在真机上根本不会出现；一旦代码把 N 的分母写错（count 而不是 count−1），
//  或者把"没读到"说成"0 卷"，界面上仍然是一句通顺的话，只有单测拦得住。
//
//  钉不住的那一半写在这儿：
//  ① 这台机器现在到底有几个候选根——单测读不到挂载表，那一格由 `Scripts/p35b-volumes-capture.sh`
//     的真机档照片与 `docs/verification/p35a-volumes/volumes.log` 负责；
//  ② 这一枚徽标在 1000 pt 窗口里和「未纳入 N 个受保护目录」「卷可用 X」挤不挤得下——
//     那是像素问题，同一族的窄窗照片负责（P25/P26 那一族的口径）。
//

import XCTest
import Foundation
import MMUI
@testable import MMDisk

final class DiskVolumeBadgeTests: XCTestCase {

    /// ① 候选根 > 1：说那一句，而且 N = 候选根数 − 1（**当下这一卷已经在分析了，不能再卖一次**）。
    func testMoreThanOneRootAnnouncesTheRest() {
        XCTAssertEqual(DiskVolumeBadgeCopy.text(candidateCount: 2), "这台机器还有 1 卷可以切换分析")
        XCTAssertEqual(DiskVolumeBadgeCopy.text(candidateCount: 3), "这台机器还有 2 卷可以切换分析")
    }

    /// ② 候选根 = 1：这一格**不出现**。"只有 1 卷"是自证，"没有其他卷"我们说不出
    /// （只查了 Foundation 的默认档，网络卷不在它的答复里）。
    func testSingleRootStaysSilent() {
        XCTAssertNil(DiskVolumeBadgeCopy.text(candidateCount: 1))
    }

    /// ③ 读到了挂载点但没有一条能扫：也是沉默。这一档不许长成"0 卷可以切换"，
    /// 更不许回落成"读不到"那句——两者是不同的事实。
    func testZeroCandidateRootsIsNotReportedAsFailure() {
        XCTAssertNil(DiskVolumeBadgeCopy.text(candidateCount: 0))
    }

    /// ④ 一行都没读到：沿用 `MainWindow.swift` 那句"这里不猜数字"的句式。
    func testUnreadableEnumerationSaysSo() {
        XCTAssertEqual(DiskVolumeBadgeCopy.text(candidateCount: nil), "未能读取卷列表，这里不猜数字")
    }

    /// 千位分隔不许把单位挤散（`DiskHeaderContractTests` 同一族规矩）。
    func testGroupedCountKeepsItsUnitAdjacent() {
        XCTAssertTrue(DiskVolumeBadgeCopy.text(candidateCount: 1_235)?.hasSuffix("1,234 卷可以切换分析") == true)
    }

    /// 禁语钉在这儿：卷 ≠ 物理盘（§4 量到同一个 APFS 容器 6 个挂载点），
    /// 而"没有其他卷"这一句在任何一个分支都不许出现。
    func testCopyNeverConfusesVolumesWithDisks() {
        for count in [0, 1, 2, 5, 1_235] {
            guard let text = DiskVolumeBadgeCopy.text(candidateCount: count) else { continue }
            XCTAssertFalse(text.contains("块硬盘"), "把卷说成了物理盘：\(text)")
            XCTAssertFalse(text.contains("没有其他卷"), "说出了我们没查的范围：\(text)")
            XCTAssertFalse(text.contains("只有 1 卷"), "缺席被写成了自证：\(text)")
        }
        let unreadable = DiskVolumeBadgeCopy.text(candidateCount: nil) ?? ""
        XCTAssertFalse(unreadable.contains("0 卷"), "把没读到说成了零个：\(unreadable)")
    }

    /// 证据与条件走 `caveat` 那一格，不进徽标：口径名、今天怎么换卷、范围边界都在 help 里；
    /// 徽标那一行不出现挂载点路径、设备名，也不出现"选择目录"这种操作说明。
    func testEvidenceStaysInTheCaveatNotInTheBadge() {
        XCTAssertTrue(DiskVolumeBadgeCopy.caveat.contains("重要用途"), "caveat 该写明用的是哪把尺子")
        XCTAssertTrue(DiskVolumeBadgeCopy.caveat.contains("选择目录"), "caveat 该说明今天怎么换卷")
        XCTAssertTrue(DiskVolumeBadgeCopy.caveat.contains("网络卷"), "caveat 该写清这一格查了哪些范围")

        for count in [2, 3] {
            let text = DiskVolumeBadgeCopy.text(candidateCount: count) ?? ""
            XCTAssertFalse(text.contains("选择目录"), "操作说明挤进了徽标：\(text)")
            XCTAssertFalse(text.contains("重要用途"), "口径写进了徽标：\(text)")
            XCTAssertFalse(text.contains("/dev"), "设备名进了徽标：\(text)")
        }
    }

    /// 四个分支里只有两个会画东西：这一条钉的是"另外两档不许有兜底文案"。
    /// 将来有人给 nil 分支补一句"暂无其他卷"，这一条会先红。
    func testExactlyTwoOfTheFourBranchesRender() {
        let rendered = [nil, 0, 1, 2].filter { DiskVolumeBadgeCopy.text(candidateCount: $0) != nil }
        XCTAssertEqual(rendered.count, 2)
    }
}
