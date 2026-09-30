//
//  DeviceUsage.swift — 「谁在用我的摄像头/麦克风」(P3.1) 的纯逻辑层
//
//  检测路径选型与本机验证矩阵见 docs/analysis/guardian-device-usage.md。
//  本文件不碰任何系统 API：只放状态判定表、文案映射与截图夹具解析，
//  真正调 CoreAudio/CMIO/AVFoundation 的一层在 DeviceUsageProbe.swift。
//
//  测量诚实口径（项目法则 1）：
//  - .idle 只表示"设备存在且这次测到了 0"；读不到/测不准一律 .indeterminate，
//    绝不把"我没看到占用"渲染成"没有应用在用"。
//  - 公开接口（DeviceIsRunningSomewhere）只给是/否，不给进程，
//    所以模型里根本没有"进程名"字段——没有可信来源就不编。
//

import Foundation

// MARK: - 模型

enum DeviceUsageKind: String, CaseIterable, Sendable {
    case camera
    case mic

    var displayName: String {
        switch self {
        case .camera: "摄像头"
        case .mic: "麦克风"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: "camera.fill"
        case .mic: "mic.fill"
        }
    }
}

enum DeviceUsageState: Equatable, Sendable {
    /// 设备在跑 IO，读数可信为 1（不回答"是谁"）。
    case inUse
    /// 设备存在，且本次测量确认读到了 0。
    case idle
    /// 没测到或测不准 —— 与 idle 是两种承诺。
    case indeterminate(IndeterminateReason)
    /// 设备枚举确认本机没有该设备（硬件事实，信息量比 indeterminate 大，
    /// 但同样不是"没有应用在用"）。
    case deviceAbsent

    enum IndeterminateReason: Equatable, Sendable {
        /// 原生属性读取失败/接口不可用。
        case readFailed
        /// 麦克风+扬声器一体的组合设备：'gone' 不分 scope（本机实测），
        /// 播放音乐也会翻 1，分不清是哪一侧在跑。
        case comboAmbiguity
        /// 两个独立枚举器（CMIO 与 AVCapture）结果互相矛盾。
        case enumeratorConflict
    }
}

// MARK: - 探针原始读数（判定表输入，纯数据）

/// 一个 CoreAudio 设备的输入/输出通道数与 running-somewhere 读数。
/// nil = 该属性这次没读到，**不等于 0**：把读失败当成"这台设备没有输入"，
/// 就会把"我不知道"渲染成"本机无麦克风"这条硬件事实。
struct AudioDeviceReading: Equatable, Sendable {
    let id: UInt32
    let name: String
    let inputChannels: Int?
    let outputChannels: Int?
    let running: Bool?
}

/// 摄像头侧读数：CMIO 设备数 + 每台设备的 running 读数 + AVCapture 枚举数（交叉核对）。
struct CameraReading: Equatable, Sendable {
    var cmioDeviceCount: Int { cmioRunning.count }
    /// 每个元素对应一台 CMIO 设备；nil = 读取失败。
    let cmioRunning: [Bool?]
    let avCaptureVideoCount: Int
}

// MARK: - 判定表

enum DeviceUsageJudge {

    /// 麦克风：只看"有输入通道"的设备。
    /// 优先级：确定的 inUse > 组合设备歧义 > 读取失败 > 空闲。
    /// 组合设备（同时有输出通道）读到 1 时不能算 inUse —— 可能只是有人在放音乐。
    static func micState(readings: [AudioDeviceReading]) -> DeviceUsageState {
        let inputs = readings.filter { ($0.inputChannels ?? 0) > 0 }
        if inputs.isEmpty {
            // 一台都没读到通道配置时，"没有输入设备"这条硬件结论没有依据。
            return readings.contains { $0.inputChannels == nil }
                ? .indeterminate(.readFailed) : .deviceAbsent
        }
        if inputs.contains(where: { $0.running == true && $0.outputChannels == 0 }) {
            return .inUse
        }
        if inputs.contains(where: { $0.running == true }) {
            // 输出通道读不到时也走这一档：分不清是不是组合设备，就不敢断言 inUse。
            return .indeterminate(.comboAmbiguity)
        }
        if inputs.contains(where: { $0.running == nil }) {
            return .indeterminate(.readFailed)
        }
        return .idle
    }

    /// 摄像头：CMIO 枚举为主，AVCapture 枚举做存在性交叉核对。
    /// 两个枚举器一个说有一个说没有 → 无法确定（绝不猜"没有"）。
    static func cameraState(_ reading: CameraReading) -> DeviceUsageState {
        if reading.cmioDeviceCount == 0 && reading.avCaptureVideoCount == 0 {
            return .deviceAbsent
        }
        if reading.cmioDeviceCount == 0 || reading.avCaptureVideoCount == 0 {
            return .indeterminate(.enumeratorConflict)
        }
        if reading.cmioRunning.contains(true) { return .inUse }
        if reading.cmioRunning.contains(nil) { return .indeterminate(.readFailed) }
        return .idle
    }
}

// MARK: - 文案映射（用户可见口径的唯一来源）

struct DeviceUsageCopy: Equatable, Sendable {
    let badge: String
    let detail: String
    /// 徽章下方的小字；nil 就不画。
    let note: String?
}

enum DeviceUsageCopyTable {
    static func copy(for kind: DeviceUsageKind, state: DeviceUsageState) -> DeviceUsageCopy {
        switch state {
        case .inUse:
            // 公开接口不返回进程名，这里必须明说"使用方无法确定"，留白会被读成"在查了但没写"。
            return DeviceUsageCopy(
                badge: "正在被使用",
                detail: kind == .camera
                    ? "有进程正在驱动采集，此刻摄像头在跑"
                    : "有进程正在驱动输入设备",
                note: "使用方无法确定 · 公开接口不返回进程"
            )
        case .idle:
            return DeviceUsageCopy(
                badge: "当前空闲",
                detail: kind == .camera
                    ? "摄像头存在，本次测量未读到任何进程驱动"
                    : "输入设备存在，本次测量未读到任何进程驱动",
                note: nil
            )
        case .indeterminate(let reason):
            switch reason {
            case .readFailed:
                return DeviceUsageCopy(
                    badge: "无法确定",
                    detail: "原生属性读取失败，本次没有拿到读数",
                    note: "不等于\"没有应用在用\" · 可点\"刷新\"重测"
                )
            case .comboAmbiguity:
                return DeviceUsageCopy(
                    badge: "无法确定",
                    detail: "设备在跑，但它与扬声器一体——播放也会触发同一标志，分不清是哪侧",
                    note: "不等于\"没有应用在用\""
                )
            case .enumeratorConflict:
                return DeviceUsageCopy(
                    badge: "无法确定",
                    detail: "设备枚举结果互相矛盾，无法判定",
                    note: "不等于\"没有应用在用\""
                )
            }
        case .deviceAbsent:
            return DeviceUsageCopy(
                badge: kind == .camera ? "本机没有摄像头" : "无可用麦克风",
                detail: kind == .camera
                    ? "CoreMediaIO 与采集设备枚举均未发现摄像头"
                    : "未发现任何带输入通道的音频设备",
                note: nil
            )
        }
    }
}

// MARK: - 截图夹具钩子（MM_GUARDIAN_FIXTURE）

/// 仅供无头截图逐档核对渲染（照 MM_ORPHAN_FIXTURE_HOME 的写法）：
/// 取值只接受 `camera|mic = inuse|idle|unknown|absent|combo|conflict` 的逗号分隔对，
/// 任何非法项整体忽略并交回调用方写 stderr——半生效的夹具比没有夹具更危险。
/// `combo`/`conflict` 是后补档：indeterminate 的两个细分成因（组合设备播放歧义、
/// 枚举器互相矛盾）原本没有夹具可达路径，只有判定表单测覆盖，实机渲染验不了。
/// 老四档（inuse/idle/unknown/absent）语义不变，向后兼容既有截图口径。
enum DeviceUsageFixture {
    struct Result: Equatable, Sendable {
        let overrides: [DeviceUsageKind: DeviceUsageState]
        /// 被拒绝的原始 token；非空时调用方必须往 stderr 写一句说明。
        let rejected: [String]
    }

    static func parse(_ raw: String) -> Result {
        var overrides: [DeviceUsageKind: DeviceUsageState] = [:]
        var rejected: [String] = []
        for token in raw.split(separator: ",") {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  let kind = kind(for: parts[0]),
                  let state = state(for: parts[1]) else {
                rejected.append(String(token))
                continue
            }
            overrides[kind] = state
        }
        // 任一项非法 → 整体作废：截图者以为夹具生效了、实际半真半假，是最坏的一种假通过。
        if !rejected.isEmpty { return Result(overrides: [:], rejected: rejected) }
        return Result(overrides: overrides, rejected: [])
    }

    private static func kind(for token: Substring) -> DeviceUsageKind? {
        switch token.lowercased() {
        case "camera": .camera
        case "mic": .mic
        default: nil
        }
    }

    private static func state(for token: Substring) -> DeviceUsageState? {
        switch token.lowercased() {
        case "inuse": .inUse
        case "idle": .idle
        case "unknown": .indeterminate(.readFailed)
        case "absent": .deviceAbsent
        // 后补档（语义与老档正交，不顶替任何老取值）：indeterminate 的另两个成因。
        case "combo": .indeterminate(.comboAmbiguity)
        case "conflict": .indeterminate(.enumeratorConflict)
        default: nil
        }
    }
}
