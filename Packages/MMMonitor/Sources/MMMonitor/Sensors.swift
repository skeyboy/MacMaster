//
//  Sensors.swift — 温度/风扇的纯函数层（解码 + 可信区间 + 定序）
//
//  读数口径参考 exelban/stats（MIT License, Copyright (c) 2019 Serhiy Mytrovtsiy）：
//  SMC 键类型解码表（ui8 /ui16/ui32/sp78/fpe2/flt ）与风扇四件套 F{id}Ac/Mn/Mx/Tg
//  （stats/SMC/smc.swift、stats/Modules/CPU/smc.swift 的做法）。本文件为独立实现，
//  未复制 stats 源码（MIT 要求保留署名，见上文）。
//
//  与 MetricTypes.swift 同一条铁律：**量不出用 nil，不塌成 0**。
//  温度尤其危险——`flt ` 字节序解错时本机曾量到 4.4e19 °C，那种值一旦被当成 0
//  或截断进显示列表，卡片看起来完全正常，数据全是假的。所以这里除了类型解码，
//  还要过一遍可信区间：区间外的键整个丢弃（少一个读数是可以的，错一个读数是不行的）。
//

import Foundation

// MARK: - 解码

public enum SensorCodec {

    /// 温度可信区间（°C）。下限给"冷机/环境传感器"留余量，上限给节流点留余量；
    /// 区间外一律视为解码或语义不可信。
    public static let plausibleTemperatureRange: ClosedRange<Double> = -20...125

    /// 风扇转速可信区间（RPM）。本机实测量程 1000–4900，上限留到 3 万（服务器级风扇）。
    public static let plausibleFanRPMRange: ClosedRange<Double> = 0...30_000

    /// SMC 的 (dataType, bytes) → 数值。类型不认识 → nil（不是 0）。
    ///
    /// 刻意不支持的类型：`ioft`（本机 6 个 TR*x 键是 8 字节、语义未定，恒读回 0，
    /// 当温度用就是把"没数据"报成 0 °C）、`{fds`（风扇名字符串）、`hex_`/`Ver_` 等。
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let bits = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            return Double(bits)
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 6) | (UInt16(bytes[1]) >> 2))
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            // 小端 IEEE float：bytes[0] 是最低位字节。按大端拼会得到 4.4e19 这种垃圾。
            let bits = (UInt32(bytes[3]) << 24) | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[1]) << 8) | UInt32(bytes[0])
            return Double(Float(bitPattern: bits))
        default:
            return nil
        }
    }

    /// 数值 + 可信区间。非有限值（NaN/±Inf）也在这道闸外——`flt ` 解坏时会出现。
    public static func value(type: String, bytes: [UInt8], in range: ClosedRange<Double>) -> Double? {
        guard let decoded = decode(type: type, bytes: bytes), decoded.isFinite else { return nil }
        return range.contains(decoded) ? decoded : nil
    }

    public static func celsius(type: String, bytes: [UInt8]) -> Double? {
        value(type: type, bytes: bytes, in: plausibleTemperatureRange)
    }

    public static func rpm(type: String, bytes: [UInt8]) -> Double? {
        value(type: type, bytes: bytes, in: plausibleFanRPMRange)
    }
}

// MARK: - 一帧传感器读数

/// 一个温度读数。**key 是 SMC 原始键名**（TCMz、Tp0W……），不做 CPU/GPU 归属推测——
/// Apple 没有公布 Apple Silicon 上这些键的语义，把它标成"CPU 温度"是编的。
public struct SensorTemperature: Equatable, Sendable, Comparable, Identifiable {
    public let key: String
    public let celsius: Double

    /// SMC 键名在一帧里天然唯一（键表按序号取，重名会被内核合并）。
    public var id: String { key }

    public init(key: String, celsius: Double) {
        self.key = key
        self.celsius = celsius
    }

    /// 降序（最热在前），同温度按键名升序——顺序必须与 SMC 返回顺序无关，
    /// 否则夹具截图每次抖一位，逐张核对做不了。
    public static func < (lhs: SensorTemperature, rhs: SensorTemperature) -> Bool {
        if lhs.celsius != rhs.celsius { return lhs.celsius > rhs.celsius }
        return lhs.key < rhs.key
    }
}

public struct SensorFan: Equatable, Sendable, Identifiable {
    /// SMC 序号（0-based），UI 显示 1-based。
    public let index: Int
    public var id: Int { index }
    /// F{id}Ac。nil = 这一路读不出，显示 "—"，不是停转（停转是 0）。
    public let currentRPM: Double?
    public let minRPM: Double?
    public let maxRPM: Double?

    public init(index: Int, currentRPM: Double?, minRPM: Double?, maxRPM: Double?) {
        self.index = index
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

public enum SensorsStatus: Equatable, Sendable {
    case loaded
    /// 整卡读不到（SMC 打不开 / 键表读不出 / 一个可信读数都没有）。
    /// reason 是原文，UI 一行 caption 显示，和磁盘 IO 同一套话术。
    case unavailable(reason: String)
}

public struct SensorsSnapshot: Equatable, Sendable {
    public var status: SensorsStatus
    /// 已按 `SensorTemperature.<` 定序（最热在前）。
    public var temperatures: [SensorTemperature]
    /// `FNum` 读数。nil = 键没读到或解不出（"不知道有几个风扇"）；
    /// 0 = 真的读到 0 个（无风扇机型）——两者在 UI 上是两句话。
    public var fanCount: Int?
    public var fans: [SensorFan]

    public init(
        status: SensorsStatus,
        temperatures: [SensorTemperature],
        fanCount: Int?,
        fans: [SensorFan]
    ) {
        self.status = status
        self.temperatures = temperatures
        self.fanCount = fanCount
        self.fans = fans
    }

    /// 首帧之前的状态：和 `MetricSnapshot.empty` 同一条约定——"还没采过"
    /// 不能被说成"SMC 打不开"。
    public static let notSampled = SensorsSnapshot(
        status: .unavailable(reason: "尚未完成首次采样"),
        temperatures: [],
        fanCount: nil,
        fans: []
    )

    public static func unavailable(reason: String) -> SensorsSnapshot {
        SensorsSnapshot(status: .unavailable(reason: reason), temperatures: [], fanCount: nil, fans: [])
    }

    /// `.loaded` 的成立条件：至少有一个可信温度点或一个风扇。两个都没有就是 unavailable，
    /// 省掉 UI 里"状态说 ok、列表是空的"这种自相矛盾的分支。
    public static func loaded(
        temperatures: [SensorTemperature],
        fanCount: Int?,
        fans: [SensorFan]
    ) -> SensorsSnapshot {
        let sorted = temperatures.sorted()
        if sorted.isEmpty && (fanCount ?? 0) == 0 {
            return .unavailable(reason: "SMC 没有返回任何可信的温度键或风扇键")
        }
        return SensorsSnapshot(status: .loaded, temperatures: sorted, fanCount: fanCount, fans: fans)
    }
}
