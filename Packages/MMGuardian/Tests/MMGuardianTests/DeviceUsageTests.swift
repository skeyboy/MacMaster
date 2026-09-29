//
//  DeviceUsageTests.swift — P3.1 判定表与夹具的纯函数测试
//
//  只打 DeviceUsage.swift 的纯逻辑；CoreAudio/CMIO/AVFoundation 实调
//  （DeviceUsageProbe.swift）不在单测里假装覆盖，见调研文档的验证矩阵。
//  全程零文件写入、零系统调用。
//

import XCTest
@testable import MMGuardian

final class DeviceUsageTests: XCTestCase {

    private func reading(
        _ id: UInt32, input: Int?, output: Int?, running: Bool?
    ) -> AudioDeviceReading {
        AudioDeviceReading(id: id, name: "dev\(id)", inputChannels: input, outputChannels: output, running: running)
    }

    // MARK: - 麦克风判定表

    func testChannelConfigReadFailureIsNotDeviceAbsent() {
        // 通道属性读失败 ≠ "本机没有麦克风"。0 是量到的硬件事实，nil 是这次没测到，
        // 两者混在一起就会把"我不知道"渲染成一句用户会当真的设备清单。
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [reading(1, input: nil, output: nil, running: nil)]),
            .indeterminate(.readFailed)
        )
        // 同一条读数里只要有一台设备确认了 0 输入，另一台读失败也不算整机没有麦克风。
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [reading(1, input: 0, output: 2, running: false),
                                                 reading(2, input: nil, output: nil, running: nil)]),
            .indeterminate(.readFailed)
        )
    }

    func testMicAbsentWhenNoInputDevice() {
        // 只有输出设备（本机 Mac mini 的真实形态）：是"无可用麦克风"，不是"空闲"也不是"无法确定"。
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [reading(1, input: 0, output: 2, running: false)]),
            .deviceAbsent
        )
        XCTAssertEqual(DeviceUsageJudge.micState(readings: []), .deviceAbsent)
    }

    func testPureInputRunningIsInUse() {
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [reading(2, input: 1, output: 0, running: true)]),
            .inUse
        )
    }

    func testComboDeviceRunningIsNeverInUseNorIdle() {
        // 本机实测：'gone' 不分 scope，纯播放也会让组合设备读 1。
        // 所以组合设备 1 → 无法确定；且绝不能被其他设备的 0 拉成"空闲"。
        let combo = reading(3, input: 1, output: 2, running: true)
        let quiet = reading(4, input: 1, output: 0, running: false)
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [combo, quiet]),
            .indeterminate(.comboAmbiguity)
        )
    }

    func testAllInputsQuietIsIdle() {
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [
                reading(2, input: 1, output: 0, running: false),
                reading(3, input: 2, output: 2, running: false),
            ]),
            .idle
        )
    }

    func testReadFailureIsIndeterminateNotIdle() {
        // 测量诚实：读失败(nil)绝不能塌缩成"空闲"。
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [
                reading(2, input: 1, output: 0, running: false),
                reading(5, input: 1, output: 0, running: nil),
            ]),
            .indeterminate(.readFailed)
        )
    }

    func testConfirmedInUseBeatsAmbiguityAndFailure() {
        // 只要有一台纯输入设备确定在跑，"正在被使用"就是事实，优先级最高。
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [
                reading(2, input: 1, output: 0, running: true),
                reading(3, input: 1, output: 2, running: nil),
            ]),
            .inUse
        )
    }

    func testOutputOnlyDeviceRunningDoesNotAffectMic() {
        // 扬声器在响（本机 afplay 实测形态）不能把麦克风判成"被使用"甚至"无法确定"。
        XCTAssertEqual(
            DeviceUsageJudge.micState(readings: [
                reading(1, input: 0, output: 2, running: true),
                reading(2, input: 1, output: 0, running: false),
            ]),
            .idle
        )
    }

    // MARK: - 摄像头判定表

    func testCameraAbsentOnlyWhenBothEnumeratorsAgree() {
        XCTAssertEqual(
            DeviceUsageJudge.cameraState(CameraReading(cmioRunning: [], avCaptureVideoCount: 0)),
            .deviceAbsent
        )
    }

    func testEnumeratorConflictIsIndeterminate() {
        // 一个枚举器说有、另一个说没有 → 绝不猜"没有"。
        XCTAssertEqual(
            DeviceUsageJudge.cameraState(CameraReading(cmioRunning: [], avCaptureVideoCount: 1)),
            .indeterminate(.enumeratorConflict)
        )
        XCTAssertEqual(
            DeviceUsageJudge.cameraState(CameraReading(cmioRunning: [false], avCaptureVideoCount: 0)),
            .indeterminate(.enumeratorConflict)
        )
    }

    func testCameraStatesFromCMIO() {
        XCTAssertEqual(
            DeviceUsageJudge.cameraState(CameraReading(cmioRunning: [true], avCaptureVideoCount: 1)),
            .inUse
        )
        XCTAssertEqual(
            DeviceUsageJudge.cameraState(CameraReading(cmioRunning: [false, false], avCaptureVideoCount: 2)),
            .idle
        )
        XCTAssertEqual(
            DeviceUsageJudge.cameraState(CameraReading(cmioRunning: [false, nil], avCaptureVideoCount: 2)),
            .indeterminate(.readFailed)
        )
    }

    // MARK: - 文案表（口径的单一来源）

    func testIndeterminateCopyNeverReadsAsNoUsage() {
        for kind in DeviceUsageKind.allCases {
            for reason in [DeviceUsageState.IndeterminateReason.readFailed, .comboAmbiguity, .enumeratorConflict] {
                let copy = DeviceUsageCopyTable.copy(for: kind, state: .indeterminate(reason))
                XCTAssertEqual(copy.badge, "无法确定")
                // 核心断言："无法确定"档必须自带"这不等于没人用"的免责小字。
                XCTAssertNotNil(copy.note, "\(kind)/\(reason) 缺免责小字")
                XCTAssertTrue(copy.note!.contains("没有应用在用"))
            }
        }
    }

    func testInUseCopyAdmitsUnknownOwner() {
        // 公开接口给不出进程名 → 文案必须明说"使用方无法确定"，也不许编一个。
        for kind in DeviceUsageKind.allCases {
            let copy = DeviceUsageCopyTable.copy(for: kind, state: .inUse)
            XCTAssertEqual(copy.badge, "正在被使用")
            XCTAssertTrue(copy.note!.contains("使用方无法确定"))
            XCTAssertFalse(copy.detail.contains("Finder"))
        }
    }

    func testIdleAndAbsentAreDistinctBadges() {
        XCTAssertEqual(DeviceUsageCopyTable.copy(for: .camera, state: .idle).badge, "当前空闲")
        XCTAssertEqual(DeviceUsageCopyTable.copy(for: .camera, state: .deviceAbsent).badge, "本机没有摄像头")
        XCTAssertEqual(DeviceUsageCopyTable.copy(for: .mic, state: .deviceAbsent).badge, "无可用麦克风")
    }

    // MARK: - 夹具钩子

    func testFixtureParsesSafeValues() {
        let r = DeviceUsageFixture.parse("camera=inuse,mic=idle")
        XCTAssertTrue(r.rejected.isEmpty)
        XCTAssertEqual(r.overrides[.camera], .inUse)
        XCTAssertEqual(r.overrides[.mic], .idle)

        let r2 = DeviceUsageFixture.parse("CAMERA=ABSENT,mic=unknown")
        XCTAssertTrue(r2.rejected.isEmpty)
        XCTAssertEqual(r2.overrides[.camera], .deviceAbsent)
        XCTAssertEqual(r2.overrides[.mic], .indeterminate(.readFailed))
    }

    func testFixtureRejectsWholeHookOnAnyBadToken() {
        // 半生效夹具 = 假通过，必须整体作废并报告被拒 token。
        let r = DeviceUsageFixture.parse("camera=inuse,mic=/Users/lee")
        XCTAssertEqual(r.rejected, ["mic=/Users/lee"])
        XCTAssertTrue(r.overrides.isEmpty)

        let r2 = DeviceUsageFixture.parse("home=/tmp/x")
        XCTAssertEqual(r2.rejected, ["home=/tmp/x"])
        XCTAssertTrue(r2.overrides.isEmpty)
    }
}
