//
//  SensorTests.swift — P6.4 温度/风扇：解码表、可信区间、装配分支与夹具档
//
//  这套测试钉的是"解错字节序 / 把量不出当 0"两类会静说谎的失败：
//  实机调试时 `flt ` 按大端拼出过 4.4e19 °C，那种值只要不丢弃就会一路进 UI。
//

import XCTest
@testable import MMMonitor

private func raw(_ type: String, _ bytes: [UInt8]) -> SMCRawValue {
    SMCRawValue(type: type, bytes: bytes)
}

/// 喂一张假 SMC 表：键名 → (类型, 字节)。keys 为 nil 表示"键表读不出"。
private func fakeSource(_ table: [String: SMCRawValue], keys: [String]?) -> SensorKeySource {
    SensorKeySource(read: { table[$0] }, temperatureKeys: { keys })
}

final class SensorCodecTests: XCTestCase {

    // MARK: 类型表

    /// `flt ` 是小端 IEEE float：0x42D90000 = 108.5，内存里就是 00 00 D9 42。
    /// 这组字节同时是大端解码的"反例"——拼错方向会得到 3.4e-41，测试会红。
    func testFloatIsLittleEndian() {
        XCTAssertEqual(SensorCodec.decode(type: "flt ", bytes: [0x00, 0x00, 0xD9, 0x42]), 108.5)
    }

    func testIntegerTypes() {
        XCTAssertEqual(SensorCodec.decode(type: "ui8 ", bytes: [0x01]), 1)
        XCTAssertEqual(SensorCodec.decode(type: "ui16", bytes: [0x12, 0x34]), 4660)
        XCTAssertEqual(SensorCodec.decode(type: "ui32", bytes: [0x00, 0x00, 0x12, 0x34]), 4660)
    }

    func testSignedAndFanTypes() {
        XCTAssertEqual(SensorCodec.decode(type: "sp78", bytes: [0x01, 0x80]), 1.5)
        XCTAssertEqual(SensorCodec.decode(type: "sp78", bytes: [0xFF, 0x00]), -1.0)
        // fpe2：value = b0×64 + (b1 >> 2)，2400 RPM 的编码是 25 80。
        XCTAssertEqual(SensorCodec.decode(type: "fpe2", bytes: [0x25, 0x80]), 2400)
    }

    func testUnknownTypeAndShortBytesReturnNil() {
        // ioft：本机 6 个 TR*x 键是 8 字节、语义未定且恒为 0，当温度用就是把"没数据"报成 0 °C。
        XCTAssertNil(SensorCodec.decode(type: "ioft", bytes: [0, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertNil(SensorCodec.decode(type: "{fds", bytes: Array("CPU_FAN".utf8)))
        XCTAssertNil(SensorCodec.decode(type: "flt ", bytes: [0x00, 0x00, 0xD9]))
        XCTAssertNil(SensorCodec.decode(type: "ui16", bytes: [0x12]))
        XCTAssertNil(SensorCodec.decode(type: "ui8 ", bytes: []))
    }

    // MARK: 可信区间

    func testOutOfRangeIsNilNotZero() {
        // 字节序解错时的典型产物（真实踩过的坑）。
        let garbage = SensorCodec.decode(type: "flt ", bytes: [0x00, 0x40, 0x9F, 0x5D])
        XCTAssertNotNil(garbage, "这条只是确认坏字节确实能解出一个数")
        XCTAssertNil(SensorCodec.celsius(type: "flt ", bytes: [0x00, 0x40, 0x9F, 0x5D]))
        XCTAssertNil(SensorCodec.celsius(type: "sp78", bytes: [0x80, 0x00]))  // -128 °C（sp78 下溢到量程外）
        XCTAssertNil(SensorCodec.celsius(type: "flt ", bytes: [0x00, 0x00, 0xC0, 0x7F]))  // NaN
        XCTAssertNil(SensorCodec.celsius(type: "flt ", bytes: [0x00, 0x00, 0x80, 0x7F]))  // +Inf
    }

    func testPlausibleRangeBoundaries() {
        XCTAssertEqual(SensorCodec.celsius(type: "flt ", bytes: [0x00, 0x00, 0xFA, 0x42]), 125.0, "上界含 125")
        XCTAssertNil(SensorCodec.celsius(type: "flt ", bytes: [0x00, 0x00, 0xFC, 0x42]))  // 126.0 越界
        XCTAssertEqual(SensorCodec.rpm(type: "fpe2", bytes: [0x25, 0x80]), 2400)
        XCTAssertNil(SensorCodec.rpm(type: "ui32", bytes: [0x00, 0x0F, 0x42, 0x40]))  // 1e6 RPM
    }
}

final class SensorAssemblerTests: XCTestCase {

    func testMissingKeyTableIsUnavailableWithReason() {
        let snapshot = SMCSensorAssembler.snapshot(from: fakeSource([:], keys: nil))
        guard case .unavailable(let reason) = snapshot.status else { return XCTFail("键表读不出应是 unavailable") }
        XCTAssertTrue(reason.contains("键表"))
        XCTAssertNil(snapshot.fanCount, "键表都读不出时不能猜风扇数")
    }

    func testNoTemperatureKeysAndNoFanIsUnavailable() {
        let snapshot = SMCSensorAssembler.snapshot(from: fakeSource([:], keys: []))
        guard case .unavailable(let reason) = snapshot.status else { return XCTFail() }
        XCTAssertTrue(reason.contains("没有温度键"))
    }

    /// 有 T* 键但一个都解不出（类型不认识/超出量程）——原因要说"解不出"，不能说"没有"。
    func testUndecodableTemperatureKeysIsUnavailable() {
        let snapshot = SMCSensorAssembler.snapshot(from: fakeSource([
            "TA00": raw("ioft", [0, 0, 0, 0, 0, 0, 0, 0]),
            "TA01": raw("flt ", [0x00, 0x40, 0x9F, 0x5D]),   // 1.4e18 °C——量程外，整个键丢弃
        ], keys: ["TA00", "TA01"]))
        guard case .unavailable(let reason) = snapshot.status else { return XCTFail() }
        XCTAssertTrue(reason.contains("都没解出可信读数"), reason)
        XCTAssertTrue(reason.contains("2"), reason)
    }

    func testTemperaturesAreSortedDescendingWithKeyTieBreak() {
        let snapshot = SMCSensorAssembler.snapshot(from: fakeSource([
            "TZZc": raw("flt ", [0x00, 0x00, 0x48, 0x42]),   // 50.0
            "TZZa": raw("flt ", [0x00, 0x00, 0x48, 0x42]),   // 50.0（同值，键名升序在前）
            "TZZb": raw("flt ", [0x00, 0x00, 0xBC, 0x42]),   // 94.0
        ], keys: ["TZZc", "TZZa", "TZZb"]))
        XCTAssertEqual(snapshot.status, .loaded)
        XCTAssertEqual(snapshot.temperatures.map(\.key), ["TZZb", "TZZa", "TZZc"])
    }

    func testFanCountZeroIsDistinctFromUnknown() {
        let tempsOnly: [String: SMCRawValue] = ["TZZa": raw("flt ", [0x00, 0x00, 0x48, 0x42])]
        var table = tempsOnly
        table["FNum"] = raw("ui8 ", [0])
        let none = SMCSensorAssembler.snapshot(from: fakeSource(table, keys: ["TZZa"]))
        XCTAssertEqual(none.fanCount, 0)
        XCTAssertTrue(none.fans.isEmpty)
        XCTAssertEqual(none.status, .loaded)

        table.removeValue(forKey: "FNum")
        let unknown = SMCSensorAssembler.snapshot(from: fakeSource(table, keys: ["TZZa"]))
        XCTAssertNil(unknown.fanCount)
    }

    /// FNum 解出离谱值时必须当"读不出"，不能拿去 `Int()` 再 for 一遍——
    /// Int(4.4e19) 是运行时 trap，会让采样线程直接崩。
    func testAbsurdFanCountIsTreatedAsUnknown() {
        let snapshot = SMCSensorAssembler.snapshot(from: fakeSource([
            "TZZa": raw("flt ", [0x00, 0x00, 0x48, 0x42]),
            "FNum": raw("flt ", [0x00, 0x40, 0x9F, 0x5D]),
        ], keys: ["TZZa"]))
        XCTAssertNil(snapshot.fanCount)
        XCTAssertTrue(snapshot.fans.isEmpty)
    }

    func testFanRowsReadCurrentMinMax() {
        let snapshot = SMCSensorAssembler.snapshot(from: fakeSource([
            "TZZa": raw("flt ", [0x00, 0x00, 0x48, 0x42]),
            "FNum": raw("ui8 ", [2]),
            "F0Ac": raw("flt ", [0x00, 0x00, 0x7D, 0x44]),   // 1012.0
            "F0Mn": raw("flt ", [0x00, 0x00, 0x7A, 0x44]),   // 1000.0
            "F0Mx": raw("flt ", [0x00, 0x20, 0x99, 0x45]),   // 4900.0
            "F1Ac": raw("flt ", [0x00, 0x40, 0x9F, 0x5D]),   // 垃圾 → nil，而不是 0
        ], keys: ["TZZa"]))
        XCTAssertEqual(snapshot.fanCount, 2)
        XCTAssertEqual(snapshot.fans.count, 2)
        XCTAssertEqual(snapshot.fans[0].index, 0)
        XCTAssertEqual(snapshot.fans[1].index, 1)
        XCTAssertEqual(snapshot.fans[0].minRPM, 1000.0, "F0Mn = 0x447A0000 小端")
        XCTAssertEqual(snapshot.fans[0].maxRPM, 4900.0)
        XCTAssertEqual(snapshot.fans[0].currentRPM, 1012.0)
        XCTAssertNil(snapshot.fans[1].currentRPM, "超出量程的转速是读不出，不是停转")
    }

    func testLoadedFactoryRejectsEmptyEverything() {
        let snapshot = SensorsSnapshot.loaded(temperatures: [], fanCount: 0, fans: [])
        guard case .unavailable = snapshot.status else { return XCTFail("没有温度也没有风扇应是 unavailable") }
        XCTAssertNil(SensorsSnapshot.notSampled.fanCount)
        guard case .unavailable(let reason) = SensorsSnapshot.notSampled.status else { return XCTFail() }
        XCTAssertEqual(reason, "尚未完成首次采样", "首帧前不能推给 SMC")
    }
}

final class MonitorCardFilterTests: XCTestCase {

    func testAbsentEnvMeansNoFilter() {
        let result = MonitorCardFilter.parse(nil)
        XCTAssertNil(result.visible)
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testSubsetParse() {
        let result = MonitorCardFilter.parse("sensors, memory")
        XCTAssertEqual(result.visible, [.sensors, .memory])
        XCTAssertTrue(result.rejected.isEmpty)
    }

    /// 非法值整批作废（照 MM_GUARDIAN_CARDS 的口径）：半生效的过滤会让截图被当成"卡齐了"。
    func testIllegalTokenRejectsWholeHook() {
        let result = MonitorCardFilter.parse("sensors,typo")
        XCTAssertNil(result.visible)
        XCTAssertEqual(result.rejected, ["typo"])
    }

    func testSensorFixtureTiers() {
        XCTAssertEqual(MonitorSnapshotFixture.parse("sensors").snapshot?.sensors.status, .loaded)

        let noFan = MonitorSnapshotFixture.parse("sensorsNoFan").snapshot?.sensors
        XCTAssertEqual(noFan?.fanCount, 0)
        XCTAssertTrue(noFan?.fans.isEmpty ?? false)

        let unknown = MonitorSnapshotFixture.parse("sensorsFanUnknown").snapshot?.sensors
        XCTAssertNil(unknown?.fanCount)
        XCTAssertEqual(unknown?.temperatures.count, 10)

        let hot = MonitorSnapshotFixture.parse("sensorsHot").snapshot?.sensors
        XCTAssertEqual(hot?.temperatures.first?.celsius, 94.0, "E5 红档要能踩到 ≥90 °C 那条线")
        XCTAssertEqual(hot?.temperatures.count, 10)

        let unavailable = MonitorSnapshotFixture.parse("sensors-unavailable:自定义原因")
        guard case .unavailable(let reason) = unavailable.snapshot?.sensors.status else {
            return XCTFail("应落到 unavailable 档")
        }
        XCTAssertEqual(reason, "自定义原因")

        // 冒号后面空 → 整批作废，不允许"reason 缺失但档位生效"的半吊子夹具。
        XCTAssertTrue(MonitorSnapshotFixture.parse("sensors-unavailable:").snapshot == nil)
        XCTAssertEqual(MonitorSnapshotFixture.parse("sensors-unavailable:").rejected, ["sensors-unavailable:"])
    }

    /// 夹具键名必须是 TZZ*：真实 SMC 键不带 ZZ，截图才不会被人当成本机读数。
    func testFixtureSensorKeysAreObviouslySynthetic() {
        let temps = MonitorSnapshotFixture.parse("sensors").snapshot?.sensors.temperatures ?? []
        XCTAssertFalse(temps.isEmpty)
        XCTAssertTrue(temps.allSatisfy { $0.key.hasPrefix("TZZ") })
        XCTAssertEqual(temps.first?.celsius, 78.0)
    }
}
