//
//  MonitorLoadHookTests.swift — `MM_MONITOR_HOLD` 的接受面与拒值面
//
//  P44 要给首帧那一族出片，而这一档不改任何数值：冻结出来的画面和真机首帧本来就同形，
//  所以照片本身证明不了钩子被消费。取证脚本只看 stderr 那行留痕，而留痕来自这个解析函数——
//  测试钉的是"哪一串取值算生效、哪一串算作废"，也就是留痕行会不会出现在错误的档位上。
//

import XCTest
import MMCore
@testable import MMMonitor

final class MonitorLoadHookTests: XCTestCase {

    func testUnsetOrBlankKeepsProductionPath() {
        for raw in [nil, "", "   "] {
            let r = MonitorLoadHook.parse(raw)
            XCTAssertFalse(r.holdInitialFrame, "取值 \(String(describing: raw)) 不该冻结首帧")
            XCTAssertNil(r.rejected, "取值 \(String(describing: raw)) 等于没设，不该写拒值留痕")
        }
    }

    func testHoldTokenAcceptsCaseAndPadding() {
        for raw in ["hold", "HOLD", " Hold ", "hold\n"] {
            let r = MonitorLoadHook.parse(raw)
            XCTAssertTrue(r.holdInitialFrame, "\(raw.debugDescription) 应当算生效")
            XCTAssertNil(r.rejected)
        }
    }

    func testAnyOtherValueDisablesTheWholeHook() {
        for raw in ["yes", "1", "true", "halt", "hold2"] {
            let r = MonitorLoadHook.parse(raw)
            XCTAssertFalse(r.holdInitialFrame, "\(raw.debugDescription) 不该被当成 hold")
            XCTAssertNotNil(r.rejected, "非法取值必须有拒值留痕，否则'钩子被忽略'与'钩子生效'分不开")
        }
    }

    /// 生效留痕必须写的是"冻结首帧"这件事本身——取证脚本判这一族只看这一行。
    func testAppliedNoteNamesTheHookAndTheFrame() {
        XCTAssertTrue(MonitorLoadHook.appliedNote.contains("MM_MONITOR_HOLD=hold"))
        XCTAssertTrue(MonitorLoadHook.appliedNote.contains("首帧"))
    }

    func testRejectedNoteNamesTheAcceptedToken() {
        let resolution = MMHookValue.resolveFlag(raw: "yes", token: "hold")
        let note = resolution.note(key: "MM_MONITOR_HOLD", token: "hold")
        XCTAssertEqual(note, "MM_MONITOR_HOLD 含非法取值（yes），只接受 hold，钩子已忽略")
    }
}
