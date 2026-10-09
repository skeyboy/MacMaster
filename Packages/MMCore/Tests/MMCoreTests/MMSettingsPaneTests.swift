//
//  MMSettingsPaneTests.swift — 系统设置深链拼接的单测
//
//  这一类缺陷在界面上是"按钮按了没反应"，在真机上要人工点一下才发现，而合成点击
//  在本项目是禁止的取证手法。所以把拼接规则下沉到 MMCore 用单测钉住：
//  P29 实测过清理页那一串（参数里自带 scheme）拼出来是双前缀死链，面板一动不动。
//  全程零窗口、零 AppKit。
//

import XCTest
@testable import MMCore

final class MMSettingsPaneTests: XCTestCase {

    /// 回归钉子：参数里绝不能再出现 scheme。清理页以前传的就是整串 URL。
    func testPaneIdentifierNeverCarriesScheme() {
        for pane in MMSettingsPane.allCases {
            XCTAssertFalse(pane.paneIdentifier.contains(MMSettingsPane.schemePrefix),
                           "\(pane) 的面板标识里不该有 scheme，拼出来会是双前缀死链")
            XCTAssertFalse(pane.rawValue.hasPrefix("x-apple"), "\(pane) 的 rawValue 不该以 scheme 开头")
        }
    }

    func testAssembledURLHasExactlyOneSchemePrefix() {
        for pane in MMSettingsPane.allCases {
            guard let url = pane.settingsURL else {
                return XCTFail("\(pane) 拼不出 URL")
            }
            XCTAssertEqual(url.absoluteString.components(separatedBy: MMSettingsPane.schemePrefix).count - 1, 1)
            XCTAssertTrue(url.absoluteString.hasPrefix("\(MMSettingsPane.schemePrefix)com.apple."))
        }
    }

    /// scheme 之外的部分必须原样保留：`?Privacy_AllFiles` 这一段是"跳到面板里的哪一格"，
    /// 被百分号编码掉就等于只跳到隐私页，用户还是要自己找。
    func testQueryPartSurvivesUntouched() {
        let url = MMSettingsPane.fullDiskAccess.settingsURL
        XCTAssertEqual(url?.absoluteString,
                       "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
    }

    func testPanesAreDistinct() {
        let ids = Set(MMSettingsPane.allCases.map(\.rawValue))
        XCTAssertEqual(ids.count, MMSettingsPane.allCases.count)
    }
}
