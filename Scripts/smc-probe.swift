// smc-probe.swift — P6.4 事实核查：本机 AppleSMC 到底能读出什么。
// 只读，绝不写 SMC（不碰 F{id}Md / Ftst，不解锁风扇控制）。
// 用法：swift Scripts/smc-probe.swift
// 结论写进 docs/analysis/feature-roadmap.md 的 P6.4 一节，别只留在终端滚动里。

import Foundation
import IOKit

typealias EByte = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
struct SMCKeyData {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: EByte = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

func fourCC(_ s: String) -> UInt32 {
    var r: UInt32 = 0
    for b in s.utf8 { r = (r << 8) | UInt32(b) }
    return r
}
func fromFourCC(_ v: UInt32) -> String {
    String(bytes: [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff].map { UInt8($0) },
           encoding: .ascii) ?? "????"
}

var conn: io_connect_t = 0
var iter = io_iterator_t(0)
guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iter) == kIOReturnSuccess else {
    print("SMC match FAILED"); exit(1)
}
let dev = IOIteratorNext(iter)
IOObjectRelease(iter)
guard dev != 0, IOServiceOpen(dev, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
    print("SMC open FAILED"); exit(1)
}
IOObjectRelease(dev)
print("SMC open OK")

func call(_ input: inout SMCKeyData) -> (kern_return_t, SMCKeyData) {
    var out = SMCKeyData()
    var size = MemoryLayout<SMCKeyData>.stride
    let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCKeyData>.stride, &out, &size)
    return (r, out)
}

func readKey(_ key: String) -> (type: String, bytes: [UInt8])? {
    var input = SMCKeyData()
    input.key = fourCC(key)
    input.data8 = 9  // kSMCCmdReadKeyInfo
    var (r, out) = call(&input)
    guard r == kIOReturnSuccess, out.result == 0 else { return nil }
    let dataSize = Int(out.keyInfo.dataSize)
    let type = fromFourCC(out.keyInfo.dataType)
    input.keyInfo.dataSize = UInt32(dataSize)
    input.data8 = 5  // kSMCCmdReadBytes
    (r, out) = call(&input)
    guard r == kIOReturnSuccess, out.result == 0 else { return nil }
    return (type, withUnsafeBytes(of: out.bytes) { Array($0.prefix(dataSize)) })
}

func decode(_ type: String, _ b: [UInt8]) -> Double? {
    guard b.count > 0 else { return nil }
    switch type {
    case "ui8 ": return Double(b[0])
    case "ui16": guard b.count >= 2 else { return nil }; return Double((UInt16(b[0]) << 8) | UInt16(b[1]))
    case "ui32": guard b.count >= 4 else { return nil }
        return Double((UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3]))
    case "sp78": guard b.count >= 2 else { return nil }
        return Double(Int16(bitPattern: (UInt16(b[0]) << 8) | UInt16(b[1]))) / 256.0
    case "fpe2": guard b.count >= 2 else { return nil }
        return Double((UInt16(b[0]) << 6) | (UInt16(b[1]) >> 2))
    case "flt ": guard b.count >= 4 else { return nil }
        // 小端 IEEE float：b0 是最低位字节。按大端拼会得到 4.4e19 这种垃圾。
        let bits = (UInt32(b[3]) << 24) | (UInt32(b[2]) << 16) | (UInt32(b[1]) << 8) | UInt32(b[0])
        return Double(Float(bitPattern: bits))
    default: return nil
    }
}

guard let (t, bs) = readKey("#KEY"), let n = decode(t, bs) else { print("#KEY read FAILED"); exit(1) }
print("#KEY = \(Int(n)) type=[\(t)]")

var keys: [String] = []
for i in 0..<Int(n) {
    var input = SMCKeyData()
    input.data8 = 8  // kSMCCmdGetPkeyFromIdx
    input.data32 = UInt32(i)
    let (r, out) = call(&input)
    if r == kIOReturnSuccess, out.result == 0 { keys.append(fromFourCC(out.key)) }
}
print("enumerated keys = \(keys.count)")

var typeHistogram: [String: Int] = [:]
var readable: [(key: String, type: String, value: Double)] = []
var unreadableTempKeys: [String] = []
for k in keys where k.hasPrefix("T") || k.hasPrefix("t") {
    guard let (ty, b) = readKey(k) else { unreadableTempKeys.append(k); continue }
    typeHistogram[ty, default: 0] += 1
    guard let v = decode(ty, b) else { continue }
    readable.append((k, ty, v))
}
print("\n== T* keys: \(keys.filter { $0.hasPrefix("T") || $0.hasPrefix("t") }.count), decodable \(readable.count), unreadable \(unreadableTempKeys.count) ==")
print("type histogram: \(typeHistogram.sorted { $0.value > $1.value })")
print("out of plausible range (-20...125): \(readable.filter { $0.value < -20 || $0.value > 125 }.map { "\($0.key)[\($0.type)]=\($0.value)" })")
print("\n== hottest 20 ==")
for r in readable.filter({ $0.value >= -20 && $0.value <= 125 }).sorted(by: { $0.value > $1.value }).prefix(20) {
    print(String(format: "%@ [%@] = %.1f", r.key, r.type, r.value))
}

print("\n== 未识别类型的 T* 键（按小端 float 试解，判断该不该加进解码表）==")
for k in keys where k.hasPrefix("T") || k.hasPrefix("t") {
    guard let (ty, b) = readKey(k) else { continue }
    guard decode(ty, b) == nil else { continue }
    let asFloat = b.count >= 4
        ? Double(Float(bitPattern: (UInt32(b[3]) << 24) | (UInt32(b[2]) << 16) | (UInt32(b[1]) << 8) | UInt32(b[0])))
        : nil
    print("\(k) [\(ty)] size=\(b.count) leFloat=\(asFloat.map { String(format: "%.1f", $0) } ?? "n/a")")
}

print("\n== fans ==")
if let (t, b) = readKey("FNum"), let v = decode(t, b) {
    print("FNum [\(t)] = \(Int(v))")
    for i in 0..<Int(v) {
        for suffix in ["Ac", "Mn", "Mx", "Tg", "Md", "md"] {
            let key = "F\(i)\(suffix)"
            if let (ty, bs) = readKey(key), let d = decode(ty, bs) {
                print(String(format: "%@ [%@] = %.1f", key, ty, d))
            }
        }
        if let (ty, bs) = readKey("F\(i)ID"), let s = String(bytes: bs, encoding: .ascii) {
            print("F\(i)ID [\(ty)] = \(s.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")))")
        }
    }
} else { print("FNum unreadable") }

// 采样节拍的成本核算：每个 tick 读 1 遍温度键要多久（决定 2s 节拍是否可承受）。
let warmKeys = readable.map { $0.key }
print("\n== 稳态成本：读 \(warmKeys.count) 个键 ==")
for pass in 1...3 {
    let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    var sum = 0.0
    for k in warmKeys {
        if let (ty, b) = readKey(k), let v = decode(ty, b) { sum += v }
    }
    let ms = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1_000_000
    print(String(format: "pass %d: %.1f ms (sum %.1f)", pass, ms, sum))
}
// 缓存 dataType/size 后只剩 1 次内核往返，量一下差别。
var cached: [String: (type: String, size: Int)] = [:]
for k in warmKeys { if let (ty, b) = readKey(k) { cached[k] = (ty, b.count) } }
let start2 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
var sum2 = 0.0
for k in warmKeys {
    guard let c = cached[k] else { continue }
    var input = SMCKeyData()
    input.key = fourCC(k)
    input.keyInfo.dataSize = UInt32(c.size)
    input.data8 = 5
    let (r, out) = call(&input)
    if r == kIOReturnSuccess, out.result == 0,
       let v = decode(c.type, withUnsafeBytes(of: out.bytes) { Array($0.prefix(c.size)) }) { sum2 += v }
}
let ms2 = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start2) / 1_000_000
print(String(format: "cached-type pass: %.1f ms (sum %.1f)", ms2, sum2))

IOServiceClose(conn)
