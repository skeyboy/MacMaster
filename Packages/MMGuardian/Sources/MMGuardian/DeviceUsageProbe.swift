//
//  DeviceUsageProbe.swift — 真正调系统 API 的一层（P3.1）
//
//  全部为进程内只读调用：无子进程、无 TCC 弹窗、单次微秒级。
//  选型依据与"为什么没有进程归属"见 docs/analysis/guardian-device-usage.md。
//  本文件刻意不被单测覆盖（假数据测不了真 IOKit/CoreAudio，装了就是假绿）；
//  判定规则全部在 DeviceUsage.swift 的纯函数里，那边有测试。
//

import Foundation
import CoreAudio
import CoreMediaIO
import AVFoundation

enum DeviceUsageProbe {

    static func snapshot() -> [DeviceUsageKind: DeviceUsageState] {
        [
            .mic: DeviceUsageJudge.micState(readings: micReadings()),
            .camera: DeviceUsageJudge.cameraState(cameraReading()),
        ]
    }

    // MARK: - 麦克风：CoreAudio 'gone'（kAudioDevicePropertyDeviceIsRunningSomewhere）

    static func micReadings() -> [AudioDeviceReading] {
        var size = UInt32(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0
        else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }

        return ids.map { id in
            AudioDeviceReading(
                id: id,
                name: deviceName(id) ?? "设备 \(id)",
                inputChannels: channelCount(id, scope: kAudioObjectPropertyScopeInput),
                outputChannels: channelCount(id, scope: kAudioObjectPropertyScopeOutput),
                running: runningSomewhere(id)
            )
        }
    }

    private static func deviceName(_ id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var ref: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ref) == noErr,
              let cf = ref?.takeUnretainedValue() else { return nil }
        return String(cf)
    }

    /// nil = 这个 scope 的流配置没读到。**不能返回 0 代替**：0 是"这台设备没有输入"
    /// 这条硬件事实，nil 是"这次没测到"，判定表要靠它区分"无可用麦克风"和"无法确定"。
    /// 实测：无输入设备的 scope 读取是成功的，返回 size=8、mNumberBuffers=0，
    /// 所以"读到 0 个 buffer"走 0，属性调用失败才走 nil。
    private static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<UInt32>.size) else { return nil }
        var buf = [UInt8](repeating: 0, count: Int(size))
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &buf) == noErr else { return nil }
        return buf.withUnsafeBytes { raw -> Int? in
            guard let base = raw.baseAddress else { return nil }
            let num = base.bindMemory(to: UInt32.self, capacity: 1).pointee
            if num == 0 { return 0 }
            let stride = MemoryLayout<AudioBuffer>.stride
            let header = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers)!
            // 声称有 buffer 却装不下，这份数据不可信。
            guard raw.count >= header + Int(num) * stride else { return nil }
            var total = 0
            for i in 0..<Int(num) {
                let b = base.advanced(by: header + i * stride)
                    .bindMemory(to: AudioBuffer.self, capacity: 1)
                total += Int(b.pointee.mNumberChannels)
            }
            return total
        }
    }

    /// nil = 读取失败（判定表会落到"无法确定"，不会当成 0）。
    private static func runningSomewhere(_ id: AudioObjectID) -> Bool? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value != 0
    }

    // MARK: - 摄像头：CoreMediaIO 'gone' + AVCapture 存在性交叉核对

    // Swift 未导入 CMIO 的常量名，按头文件里的 FourCharCode 就地定义：
    // kCMIOHardwarePropertyDevices = 'dev#'，kCMIODevicePropertyDeviceIsRunningSomewhere = 'gone'，
    // kCMIOObjectPropertyScopeGlobal = 'glob'，kCMIOObjectSystemObject = kAudioObjectSystemObject。
    private static let devicesSelector: CMIOObjectPropertySelector = 0x6465_7623 // 'dev#'
    private static let runningSomewhereSelector: CMIOObjectPropertySelector = 0x676F_6E65 // 'gone'
    private static let globalScope: CMIOObjectPropertyScope = 0x676C_6F62 // 'glob'
    private static let systemObject = CMIOObjectID(kAudioObjectSystemObject)

    static func cameraReading() -> CameraReading {
        CameraReading(
            cmioRunning: cmioRunningFlags(),
            avCaptureVideoCount: avCaptureVideoCount()
        )
    }

    private static func cmioDeviceIDs() -> [CMIOObjectID]? {
        var addr = CMIOObjectPropertyAddress(mSelector: devicesSelector, mScope: globalScope, mElement: 0)
        var size = UInt32(0)
        let qs = withUnsafePointer(to: &addr) { p in
            CMIOObjectGetPropertyDataSize(systemObject, p, 0, nil, &size)
        }
        guard qs == noErr else { return nil }
        guard size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used = UInt32(0)
        let gs = withUnsafePointer(to: &addr) { p in
            withUnsafeMutableBytes(of: &ids) { raw in
                CMIOObjectGetPropertyData(systemObject, p, 0, nil, size, &used, raw.baseAddress)
            }
        }
        guard gs == noErr else { return nil }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    /// 返回每台 CMIO 设备的 running 读数；枚举整体失败时给 [nil]，
    /// 让判定表走"读取失败"而不是误入"本机没有摄像头"分支。
    private static func cmioRunningFlags() -> [Bool?] {
        guard let ids = cmioDeviceIDs() else { return [nil] }
        return ids.map { id in
            var addr = CMIOObjectPropertyAddress(
                mSelector: runningSomewhereSelector, mScope: globalScope, mElement: 0)
            var value: UInt32 = 0
            var used = UInt32(0)
            let st = withUnsafePointer(to: &addr) { p in
                withUnsafeMutableBytes(of: &value) { raw in
                    CMIOObjectGetPropertyData(id, p, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, raw.baseAddress)
                }
            }
            guard st == noErr else { return nil }
            return value != 0
        }
    }

    /// 只枚举不建 session、不开采集 —— 不触发 TCC 摄像头弹窗（本机已验证枚举零设备无弹窗）。
    private static func avCaptureVideoCount() -> Int {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) { types.append(.external) } else { types.append(.externalUnknown) }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified)
        return session.devices.count
    }
}
