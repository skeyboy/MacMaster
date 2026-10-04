//
//  SMC.swift — AppleSMC 用户客户端（**只读**）
//
//  调用形状参考 exelban/stats（MIT License, Copyright (c) 2019 Serhiy Mytrovtsiy）
//  的 SMC/ 目录（IOServiceMatching("AppleSMC") → IOServiceOpen → 单个 selector 的
//  IOConnectCallStructMethod），本文件为独立实现，未复制 stats 源码。
//
//  只读是结构性的，不是靠自觉：本类型只发三个命令字（读键信息 9 / 读字节 5 /
//  按序号取键名 8），没有写命令（6/7）、不碰风扇模式键 F{id}Md、不做 stats 里的
//  unlockFanControl（写 Ftst）。写 SMC 能把风扇永久锁进一个转速，那是会烧硬件的
//  副作用，与"监控页看一眼温度"完全不成比例。
//
//  布局警告：SMCParamBlock 的 Swift 元组声明的 stride 必须与内核 SMCKeyData_t 一致，
//  IOConnectCallStructMethod 才接受。这里是实测可用的那一版（真机读出 TCMz/flt /FNum）；
//  任何字段顺序、类型或补齐的改动都可能静默变成 kIOReturnBadArgument，改之前先跑
//  Scripts/smc-probe.swift。
//

import Foundation
import IOKit

// MARK: - 内核参数块

/// 32 字节数据区（SMCBytes_t）。用元组而不是数组，是为了让 Swift 算出的 stride
/// 与内核的定长结构一致。
private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamBlock {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

enum SMCFourCC {
    static func encode(_ text: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in text.utf8.prefix(4) { result = (result << 8) | UInt32(byte) }
        return result
    }

    static func decode(_ value: UInt32) -> String {
        let bytes = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
                    UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

/// SMC 命令字（放在 data8）。只有这三个——写命令一概不发。
private enum SMCCommand: UInt8 {
    case readBytes = 5
    case keyFromIndex = 8
    case readKeyInfo = 9
}

// MARK: - 客户端

/// 一个键的原始读数：类型标签（4 字符，如 "flt "）+ 数据字节。
public struct SMCRawValue: Equatable, Sendable {
    public let type: String
    public let bytes: [UInt8]

    public init(type: String, bytes: [UInt8]) {
        self.type = type
        self.bytes = bytes
    }
}

/// AppleSMC 用户客户端。连接是一次性打开、进程存活期长期持有（每次采样重开
/// IOServiceOpen 会把 350 次内核往返的开销再乘一遍，且没有收益）。
///
/// 线程模型：`@unchecked Sendable` + 一把锁。采样循环是 detached Task，
/// 设置里改节拍时新旧 Task 会短暂并存，两次 read 可能撞上同一连接。
public final class SMCClient: @unchecked Sendable {

    public init() {}

    private let lock = NSLock()
    private var conn: io_connect_t = 0
    private var openFailureReason: String?
    private var cachedTemperatureKeys: [String]?

    /// 打开连接。成功返回 nil，失败返回一句可以直接上 UI 的原文原因。
    public func ensureOpen() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if conn != 0 { return nil }
        openConnection()
        return openFailureReason
    }

    /// 读一个键（两次内核往返：先问类型和长度，再取数据）。
    public func read(key: String) -> SMCRawValue? {
        lock.lock()
        defer { lock.unlock() }
        guard conn != 0 else { return nil }
        return readUnlocked(key: key)
    }

    /// 键表里所有温度键的名字（首字母 T，SMC 键名大小写有意义，两种都收）。
    /// 结果缓存——枚举整表要 1369 次往返，只有第一次采样付。
    public func temperatureKeys() -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedTemperatureKeys { return cached }
        guard conn != 0 else { return nil }
        guard let raw = readUnlocked(key: "#KEY"),
              let count = SensorCodec.value(type: raw.type, bytes: raw.bytes, in: 1...65_535)
        else { return nil }

        var names: [String] = []
        for index in 0..<Int(count) {
            var block = SMCParamBlock()
            block.data8 = SMCCommand.keyFromIndex.rawValue
            block.data32 = UInt32(index)
            guard let output = call(block), output.result == 0 else { continue }
            names.append(SMCFourCC.decode(output.key))
        }
        let keys = names.filter { $0.hasPrefix("T") || $0.hasPrefix("t") }
        cachedTemperatureKeys = keys
        return keys
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
    }

    // MARK: 内部（调用方持锁）

    private func openConnection() {
        var iterator = io_iterator_t(0)
        guard let matching = IOServiceMatching("AppleSMC") else {
            openFailureReason = "IOServiceMatching(\"AppleSMC\") 返回空，本机没有 AppleSMC 服务"
            return
        }
        let matchKR = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard matchKR == kIOReturnSuccess else {
            openFailureReason = "枚举 AppleSMC 服务失败：\(machErrorString(matchKR) ?? "kern_return_t \(matchKR)")"
            return
        }
        defer { IOObjectRelease(iterator) }
        // 注册表枚举逐个取（同 DiskIOReader 的已知坑）。
        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            openFailureReason = "AppleSMC 服务列表为空，无法建立用户客户端"
            return
        }
        defer { IOObjectRelease(service) }
        let openKR = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard openKR == kIOReturnSuccess, conn != 0 else {
            conn = 0
            openFailureReason = "IOServiceOpen(AppleSMC) 失败：\(machErrorString(openKR) ?? "kern_return_t \(openKR)")"
            return
        }
        openFailureReason = nil
    }

    private func readUnlocked(key: String) -> SMCRawValue? {
        var block = SMCParamBlock()
        block.key = SMCFourCC.encode(key)
        block.data8 = SMCCommand.readKeyInfo.rawValue
        guard let info = call(block), info.result == 0 else { return nil }
        let dataSize = Int(info.keyInfo.dataSize)
        let type = SMCFourCC.decode(info.keyInfo.dataType)
        guard dataSize > 0, dataSize <= 32 else { return nil }

        block.keyInfo.dataSize = UInt32(dataSize)
        block.data8 = SMCCommand.readBytes.rawValue
        guard let output = call(block), output.result == 0 else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(dataSize)) }
        return SMCRawValue(type: type, bytes: bytes)
    }

    /// 所有 SMC 命令都走 selector 2（内核里那唯一的 struct method）。
    /// 内核往返本身失败（kr ≠ success）与命令被 SMC 拒绝（output.result ≠ 0）是两回事，
    /// 这里都折成 nil：调用方只需要"这个键这次没读到"。
    private func call(_ input: SMCParamBlock) -> SMCParamBlock? {
        var request = input
        var output = SMCParamBlock()
        var outputSize = MemoryLayout<SMCParamBlock>.stride
        let kr = withUnsafeMutableBytes(of: &request) { inputBuffer in
            withUnsafeMutableBytes(of: &output) { outputBuffer in
                IOConnectCallStructMethod(
                    conn, 2,
                    inputBuffer.baseAddress, MemoryLayout<SMCParamBlock>.stride,
                    outputBuffer.baseAddress, &outputSize
                )
            }
        }
        guard kr == kIOReturnSuccess else { return nil }
        return output
    }
}
