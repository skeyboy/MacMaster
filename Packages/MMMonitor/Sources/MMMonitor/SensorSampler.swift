//
//  SensorSampler.swift — 把 SMC 键拼成一帧 SensorsSnapshot
//
//  分两层：`SMCSensorAssembler` 只认"键 → 原始读数"这一个抽象动作（SensorKeySource），
//  不碰 IOKit，单测喂字典就能复写全部分支；`SMCSensorReader` 才接生产用的 SMCClient。
//  与 SystemMetricSampler 同一约定：跑在后台线程，主线程只收结果。
//

import Foundation

/// 一个键的取数入口 + 温度键清单。生产由 SMCClient 提供，测试喂字典。
public struct SensorKeySource: Sendable {
    public var read: @Sendable (_ key: String) -> SMCRawValue?
    /// nil = 键表读不出（#KEY / 按序号取键名失败）；`[]` = 表里没有温度键。
    /// 两者在 UI 上是两句话，不能塌成同一个空数组。
    public var temperatureKeys: @Sendable () -> [String]?

    public init(
        read: @escaping @Sendable (_ key: String) -> SMCRawValue?,
        temperatureKeys: @escaping @Sendable () -> [String]?
    ) {
        self.read = read
        self.temperatureKeys = temperatureKeys
    }
}

public enum SMCSensorAssembler {

    /// 风扇数量上限的合理性闸：FNum 解出 4.4e19 这类值时 `Int()` 会直接 trap，
    /// 而且没有一台 Mac 有 20 个风扇。区间外当作"读不出"（fanCount = nil）。
    static let plausibleFanCountRange: ClosedRange<Double> = 0...16

    public static func snapshot(from source: SensorKeySource) -> SensorsSnapshot {
        guard let tempKeys = source.temperatureKeys() else {
            return .unavailable(reason: "SMC 键表读不出（#KEY 或按序号取键名失败），拿不到温度键清单")
        }

        var temperatures: [SensorTemperature] = []
        for key in tempKeys {
            guard let raw = source.read(key),
                  let celsius = SensorCodec.celsius(type: raw.type, bytes: raw.bytes)
            else { continue }
            temperatures.append(SensorTemperature(key: key, celsius: celsius))
        }

        let fanCount = fanCountValue(from: source)
        var fans: [SensorFan] = []
        if let count = fanCount {
            for index in 0..<count {
                fans.append(SensorFan(
                    index: index,
                    currentRPM: rpmValue("F\(index)Ac", from: source),
                    minRPM: rpmValue("F\(index)Mn", from: source),
                    maxRPM: rpmValue("F\(index)Mx", from: source)
                ))
            }
        }

        if temperatures.isEmpty && fanCount == nil {
            return .unavailable(reason: tempKeys.isEmpty
                ? "SMC 键表里没有温度键（本机 SMC 未暴露 T* 读数）"
                : "温度键一个都没解出可信读数（清单里 \(tempKeys.count) 个 T* 键，全部超出类型或量程）")
        }
        return .loaded(temperatures: temperatures, fanCount: fanCount, fans: fans)
    }

    private static func fanCountValue(from source: SensorKeySource) -> Int? {
        // FNum 在 Apple Silicon 上是 ui8，Intel 机型上见过 ui16/fpe2；
        // 解码交给类型表，这里只加"不可能是 20 个风扇"这道闸。
        guard let raw = source.read("FNum"),
              let value = SensorCodec.value(type: raw.type, bytes: raw.bytes, in: plausibleFanCountRange)
        else { return nil }
        return Int(value)
    }

    private static func rpmValue(_ key: String, from source: SensorKeySource) -> Double? {
        guard let raw = source.read(key) else { return nil }
        return SensorCodec.rpm(type: raw.type, bytes: raw.bytes)
    }
}

/// 生产入口：长期持有一个 SMCClient 单例（连接不每次重开）。
public struct SMCSensorReader: Sendable {

    public static let shared = SMCSensorReader()

    private let client: SMCClient

    public init(client: SMCClient = SMCClient()) {
        self.client = client
    }

    public func read() -> SensorsSnapshot {
        if let openFailure = client.ensureOpen() {
            return .unavailable(reason: openFailure)
        }
        return SMCSensorAssembler.snapshot(from: SensorKeySource(
            read: { [client] key in client.read(key: key) },
            temperatureKeys: { [client] in client.temperatureKeys() }
        ))
    }
}
