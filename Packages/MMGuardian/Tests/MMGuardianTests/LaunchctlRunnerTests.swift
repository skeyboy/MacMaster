//
//  LaunchctlRunnerTests.swift — 只读快照这一处真跑一次 `launchctl list`
//
//  这个文件里只有**读**：`launchctl list` 是纯查询。写侧（disable）照旧不在单测里真动
//  launchd——口径见 `LoginItemStoreTests` 顶部那句"绝不动真实系统 plist"。
//

import XCTest
@testable import MMGuardian

final class LaunchctlRunnerTests: XCTestCase {

    /// `launchctl list` 是全站输出量最大的一条子进程命令：现测（2026-10-05 本机，5 轮）
    /// 19,169–19,459 字节，是 `Pipe` 那 64 KB 内核缓冲的三成，而这个数还随此刻在跑的
    /// 作业数上下走。旧的"先等退出再读"在这一处**恰好**没发作——而没发作从来拦不住
    /// 哪天作业变多。
    ///
    /// 大输出的形状由 `MMCore` 的 `CommandRunnerPipeTests` 用一条必定 512 KB 的命令钉住；
    /// 这里钉的是真机这一头：我们确实把这台机器的清单读回来了，而不是读出一句"没跑成"。
    /// 与 `SystemSpaceReportTests.testRealMachineOutputParses` 同一个道理——
    /// 样例全对、真机全废的那种错，只有真机跑一次才拦得住。
    func testListSnapshotReadsTheRealMachine() {
        let snapshot = LaunchctlRunner.listSnapshot()
        switch snapshot {
        case .unavailable(let reason):
            XCTFail("真机的 launchctl list 必须读得回来，实际报：\(reason)")
        case .labels(let labels):
            XCTAssertFalse(labels.isEmpty, "读到空集合等于没读到")
            XCTAssertTrue(labels.contains { $0.hasPrefix("com.apple.") },
                          "一台在跑的 Mac 不可能一个系统 Agent 都没有，多半是解析读歪了")
        }
    }
}
