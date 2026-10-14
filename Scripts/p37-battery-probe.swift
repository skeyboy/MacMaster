// p37-battery-probe.swift — P37a 事实核查：AppleSmartBattery 的属性在本机到底是什么类型、什么值。
// 只读（IORegistryEntryCreateCFProperty / CreateCFProperties），不写任何键。
// 用法：swift Scripts/p37-battery-probe.swift
// 结论写进 docs/analysis/feature-roadmap.md 的 P37a 一节：解码写法要按这里量到的类型分支来定，
// 不能按"ioreg 打印成 Yes/No 就是 Swift Bool"去猜。

import Foundation
import IOKit

let keys = [
    "BatteryInstalled", "CurrentCapacity", "MaxCapacity",
    "AppleRawCurrentCapacity", "AppleRawMaxCapacity", "DesignCapacity",
    "NominalChargeCapacity", "FullChargeCapacity", "CycleCount",
    "Voltage", "Amperage", "TimeRemaining",
    "ExternalConnected", "ExternalChargeCapable", "IsCharging", "FlaggedFailure",
    "BatteryData", "AdapterDetails", "ChargerData"
]

let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
print("IOServiceGetMatchingService(AppleSmartBattery) = \(service)")
guard service != 0 else {
    print("没有匹配的 AppleSmartBattery 节点")
    exit(0)
}
defer { IOObjectRelease(service) }

func describe(_ value: Any) -> String {
    let mirror = String(reflecting: value)
    if let data = value as? Data { return "Data(\(data.count) 字节) \(mirror)" }
    if let num = value as? NSNumber {
        return "NSNumber objCType=\(String(cString: num.objCType)) bool=\(num.boolValue) int=\(num.intValue) uint64=\(num.uint64Value) mirror=\(mirror)"
    }
    if let dict = value as? [String: Any] {
        return "字典 \(dict.keys.sorted())"
    }
    return mirror
}

print("---- 逐个键 ----")
for key in keys {
    guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
        print("\(key): <键缺席>")
        continue
    }
    let value = cf.takeRetainedValue()
    // 这三种桥接是我们解码层的判据：as? Bool / as? Int / as? NSNumber
    let asBool = (value as? Bool).map { $0 ? "true" : "false" } ?? "nil"
    let asInt = (value as? Int).map(String.init) ?? "nil"
    print("\(key): \(describe(value)) | as?Bool=\(asBool) as?Int=\(asInt)")
}

print("---- 整张属性字典（IORegistryEntryCreateCFProperties）----")
var propsPointer: Unmanaged<CFMutableDictionary>?
let kr = IORegistryEntryCreateCFProperties(service, &propsPointer, kCFAllocatorDefault, 0)
print("kern_return_t = \(kr)")
if let props = propsPointer?.takeRetainedValue() as? [String: Any] {
    print("键数 = \(props.count)")
    for key in keys where props[key] != nil {
        print("props[\(key)] = \(describe(props[key]!))")
    }
} else {
    print("属性字典没拿到")
}
