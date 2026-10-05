//
//  GuardianHeaderContractTests.swift — 页头副标题与"这一屏有几张卡"的对照测试
//
//  这一条缺口是 P11c 的改名照出来的（P13 记为 D1，`fidelity-guardian.md` §7.1）：
//  副标题从前只列三件事——占用 / TCC / 登录项——而这一屏一直有四张卡。
//  设计稿与源码逐字相同，所以十几轮对照表都给 ✅：**"两边一致"从来不等于"两边都对"**。
//  从前那第四张叫「系统活动」，名字含糊到没人拿它去数副标题列了几项；改成
//  「密钥与自启配置的改动时间」之后它和另外三项成了同一类东西，缺的那一项才看得见。
//
//  所以这里钉两件事：① 段数跟着 `GuardianCard.allCases` 走（加一张卡而忘了改副标题，
//  这一条会红）；② 活动卡那一段必须用它自己的标题，不许再换一个说法写第二遍
//  （P11c 的教训就是"同一个东西有两个名字"）。
//

import XCTest
@testable import MMGuardian

final class GuardianHeaderContractTests: XCTestCase {

    func testSubtitleHasExactlyOneSegmentPerCard() {
        XCTAssertEqual(GuardianPageCopy.subtitleSegments.count, GuardianCard.allCases.count,
                       "这一屏有 \(GuardianCard.allCases.count) 张卡，副标题却列了 \(GuardianPageCopy.subtitleSegments.count) 件事")
    }

    func testSubtitleSegmentsAreNonEmptyAndDistinct() {
        for segment in GuardianPageCopy.subtitleSegments {
            XCTAssertFalse(segment.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        XCTAssertEqual(Set(GuardianPageCopy.subtitleSegments).count, GuardianPageCopy.subtitleSegments.count)
    }

    func testActivityCardSegmentUsesTheCardsOwnTitle() {
        let activitySegment = GuardianPageCopy.subtitleSegments.last ?? ""
        XCTAssertTrue(activitySegment.hasPrefix(ActivityCardCopy.title),
                      "副标题最后一段是「\(activitySegment)」，而卡片自己的标题是「\(ActivityCardCopy.title)」——同一个东西不许有两个说法")
    }

    func testSubtitleStillDisclaimsRealtimeMonitoring() {
        // 「非实时监听」是这一屏最容易被顺手删掉的那半句：删了就等于承诺常驻监控。
        XCTAssertTrue(GuardianPageCopy.subtitleSegments[0].contains("非实时监听"))
    }
}
