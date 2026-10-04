//
//  HotBand.swift — "转红"的进出双阈值（迟滞），纯函数无 UI
//
//  单点阈值（`celsius >= 90`）在数值贴着阈值摆动时会让颜色每帧闪一次：
//  本机截图负载下最高温度实测 89.4 °C（docs/verification/p64-dark/01），离阈值 0.6 °C，
//  而采样每 2 秒一帧（见 fidelity-monitor.md §2.13 I11）。
//  规则：当前不热 → 越过 enter 才转红；当前已热 → 跌到 exit 以下才复原。
//
//  这里只管判定，不管"阈值是多少"——阈值留在调用方，因为它是产品口径（90 °C 是我们
//  自定的余量，不是苹果给的官方值），不该由机制层替它做主。
//

import Foundation

public struct HotBand: Equatable, Sendable {
    public let enter: Double
    public let exit: Double

    public init(enter: Double, exit: Double) {
        // exit 必须 ≤ enter，否则"已经热着"的条目比"刚够热"更容易维持，
        // 同一帧既算热又算不热——区间反了，闪的只是换了个方向。
        precondition(exit <= enter, "HotBand 的退出阈值必须不高于进入阈值")
        self.enter = enter
        self.exit = exit
    }

    /// `alreadyHot` 是上一帧的判定结果；nil（这一帧读不出）一律不算热。
    public func isHot(value: Double?, alreadyHot: Bool) -> Bool {
        guard let value else { return false }
        return value >= (alreadyHot ? exit : enter)
    }
}

/// 一组条目在各自营的"当前是否热"，键在本帧内唯一（SMC 键名）。
public struct HotBandTrack: Equatable, Sendable {
    public private(set) var hotKeys: Set<String> = []

    public init() {}

    /// 用这一帧的读数整体换掉上一帧的状态。这一帧没出现的键自动掉出集合——
    /// 读不到了就不热，不需要为它单独写"退出"判定。
    public mutating func update(_ values: [(key: String, value: Double?)], band: HotBand) {
        var next: Set<String> = []
        for entry in values
        where band.isHot(value: entry.value, alreadyHot: hotKeys.contains(entry.key)) {
            next.insert(entry.key)
        }
        hotKeys = next
    }

    public func isHot(_ key: String) -> Bool {
        hotKeys.contains(key)
    }
}
