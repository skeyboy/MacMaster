import Foundation
import SwiftUI
import Combine
import MMCore
import MMFileScanner

/// 仪表盘的数据源。原则：这里只放"每次都从系统量出来的"和"没量出来就显示测量中"的，
/// 不允许出现写死的样例数字。
@MainActor
final class DashboardModel: ObservableObject {
    @Published var volume: SystemSampler.Volume?
    @Published var memory: SystemSampler.Memory?
    @Published var cpuLoad: Double?
    @Published var netRate: SystemSampler.NetBytes?
    @Published var sampledAt: Date?

    @Published var reclaimableBytes: UInt64?
    @Published var isMeasuringReclaimable = false
    @Published var measureFailed = false

    let coreCount = ProcessInfo.processInfo.activeProcessorCount

    private var lastTicks: SystemSampler.CPUTicks?
    private var lastNet: SystemSampler.NetBytes?
    private var lastNetAt: Date?
    private var didStartMeasuring = false

    /// 每 2 秒采一次样。视图不可见时由调用方取消这个任务，避免后台空转。
    func sampleContinuously(interval: TimeInterval = 2) async {
        while !Task.isCancelled {
            sampleOnce()
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    func sampleOnce() {
        volume = SystemSampler.volume()
        memory = SystemSampler.memory()

        if let ticks = SystemSampler.cpuTicks() {
            if let load = SystemSampler.load(from: lastTicks, to: ticks) {
                cpuLoad = load
            }
            lastTicks = ticks
        }

        let now = Date()
        if let net = SystemSampler.networkBytes() {
            if let previous = lastNet, let at = lastNetAt,
               let rate = SystemSampler.rate(from: previous, to: net,
                                             interval: now.timeIntervalSince(at)) {
                netRate = rate
            }
            lastNet = net
            lastNetAt = now
        }
        sampledAt = now

        if !didStartMeasuring {
            didStartMeasuring = true
            Task { await measureReclaimable() }
        }
    }

    /// "可清理"这个数字和清理页用的是同一个扫描器，两处不会量出两个结果。
    func measureReclaimable() async {
        guard !isMeasuringReclaimable else { return }
        isMeasuringReclaimable = true
        measureFailed = false
        let categories = await CacheScanner().scanAll()
        if categories.isEmpty {
            measureFailed = true
        } else {
            reclaimableBytes = categories.reduce(0) { total, category in total + category.scannedSize }
        }
        isMeasuringReclaimable = false
    }

    var trashHistory: [TrashOperation] {
        Array(FileTrashService.shared.trashHistory.prefix(4))
    }

    func undo(_ operation: TrashOperation) async {
        _ = await FileTrashService.shared.undo(operationID: operation.id)
        sampleOnce()
    }
}
