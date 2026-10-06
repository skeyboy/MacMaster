//
//  LaunchHookTests.swift — 启动钩子（MM_APPEARANCE / MM_WINDOW_SIZE）解析的单测
//
//  这两个钩子原先住在壳层（零测试目标的那一层），解析结果直接决定拍出来是浅色还是深色、
//  窗口是 900 还是 1000 宽。写错的后果是"照片是真的、结论是错的"，所以抽到这里钉住。
//  全程零窗口、零 AppKit。
//

import XCTest
@testable import MMCore

final class LaunchHookTests: XCTestCase {

    // MARK: - MM_APPEARANCE

    func testAppearanceAcceptsBothNamesPerScheme() {
        XCTAssertEqual(MMLaunchHook.resolveAppearance(raw: "light"), .light)
        XCTAssertEqual(MMLaunchHook.resolveAppearance(raw: "aqua"), .light)
        XCTAssertEqual(MMLaunchHook.resolveAppearance(raw: "dark"), .dark)
        XCTAssertEqual(MMLaunchHook.resolveAppearance(raw: "darkAqua"), .dark)
    }

    func testAppearanceNormalizesCaseAndBlank() {
        XCTAssertEqual(MMLaunchHook.resolveAppearance(raw: "  DARK  "), .dark)
    }

    func testAppearanceRejectsEverythingElse() {
        // "写错值会静默沿用系统外观"是这一档最坏的失效方式： nil 会被调用方翻译成一行留痕。
        for raw in ["pink", "", "   ", "lght", "dark-light", "系统"] {
            XCTAssertNil(MMLaunchHook.resolveAppearance(raw: raw), "\(raw) 不该被接受")
        }
        XCTAssertNil(MMLaunchHook.resolveAppearance(raw: nil))
    }

    // MARK: - MM_WINDOW_SIZE

    func testWindowSizeAcceptsWidthTimesHeight() {
        XCTAssertEqual(MMLaunchHook.resolveWindowSize(raw: "1280x800")?.text, "1280x800")
        XCTAssertEqual(MMLaunchHook.resolveWindowSize(raw: "900X600")?.text, "900x600")
        XCTAssertEqual(MMLaunchHook.resolveWindowSize(raw: " 900 x 600 ")?.text, "900x600")
    }

    func testWindowSizeFloorsAreInclusive() {
        XCTAssertEqual(MMLaunchHook.resolveWindowSize(raw: "320x200"),
                       MMWindowSizeRequest(width: 320, height: 200))
        XCTAssertNil(MMLaunchHook.resolveWindowSize(raw: "319x200"))
        XCTAssertNil(MMLaunchHook.resolveWindowSize(raw: "320x199"))
    }

    func testWindowSizeRejectsMalformed() {
        for raw in ["900", "900x", "x600", "abcx600", "900x600x100", "", "   ", "900,600"] {
            XCTAssertNil(MMLaunchHook.resolveWindowSize(raw: raw), "\(raw) 不该被接受")
        }
        XCTAssertNil(MMLaunchHook.resolveWindowSize(raw: nil))
    }

    /// 夹取地板可注入：壳层用 320x200 防呆，而内容区另有 minWidth，
    /// 生效值要靠日志里那句"实际 WxH"来对，不是靠这个解析函数保证。
    func testWindowSizeFloorsAreOverridable() {
        XCTAssertNotNil(MMLaunchHook.resolveWindowSize(raw: "100x100", minWidth: 100, minHeight: 100))
        XCTAssertNil(MMLaunchHook.resolveWindowSize(raw: "100x100", minWidth: 200, minHeight: 100))
    }
}
