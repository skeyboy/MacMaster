import AppKit
import Combine
import UserNotifications
import MMCore
import MMUI

@MainActor
public final class MenuBarManager: ObservableObject {
    public static let shared = MenuBarManager()

    /// 唯一的数据出口：后台 Task 采样后整体赋值，主线程只读它，不做任何系统调用。
    @Published public private(set) var snapshot: MetricSnapshot = .empty

    /// 旧 API 兼容：仪表盘/通知逻辑继续按百分数读。
    public var cpuUsage: Double { snapshot.totalCPU.map { $0 * 100 } ?? 0 }
    public var memoryUsage: Double { snapshot.memory?.usedRatio.map { $0 * 100 } ?? 0 }
    public var memoryUsedGB: Double { Double(snapshot.memory?.usedBytes ?? 0) / 1_073_741_824 }
    public var memoryTotalGB: Double { Double(snapshot.memory?.totalBytes ?? 0) / 1_073_741_824 }
    /// 单位从旧的 KB/s 改为 bytes/s，展示统一交给 MMFormat。
    public var networkUp: Double { snapshot.networkUpBytesPerSecond ?? 0 }
    public var networkDown: Double { snapshot.networkDownBytesPerSecond ?? 0 }

    private var statusItem: NSStatusItem?
    /// 采样循环跑在后台；主线程只接收快照。disable() 必须取消它（项目既有约定）。
    private var samplingTask: Task<Void, Never>?
    private var samplingInterval: TimeInterval?
    private var fixtureFrozen = false

    private let settings = AppSettings.shared
    private var settingsObservation: AnyCancellable?

    // 阈值通知状态（跨阈值触发 + 冷却，避免每次刷新刷屏）
    private var cpuAboveThreshold = false
    private var memoryAboveThreshold = false
    private var lastCPUNotificationAt: Date?
    private var lastMemoryNotificationAt: Date?
    private var notificationAuthorizationRequested = false

    private let cpuThreshold: Double = 85
    private let memoryThreshold: Double = 90
    private let notificationCooldown: TimeInterval = 300

    public var isEnabled: Bool {
        get { statusItem != nil }
    }

    private init() {}

    /// UNUserNotificationCenter.current() 在脱离 .app bundle 运行时会直接崩溃，
    /// 所有通知相关调用必须先过这道闸。
    private var supportsUserNotifications: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    public func enable() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "MacMaster"
            button.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        }

        let menu = NSMenu()
        menu.delegate = MenuDelegate.shared
        statusItem?.menu = menu

        observeSettings()
        startMonitoring()
        requestNotificationAuthorizationIfNeeded()
    }

    public func disable() {
        stopMonitoring()
        settingsObservation = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    /// 监听设置变化：间隔改变 → 重启采样任务；显隐改变 → 立即重绘标题；
    /// 通知开关打开 → 补请求授权。objectWillChange 在赋值前发出，
    /// 用 receive(on: .main) 把处理排到下一个主队列 tick，届时新值已写入。
    private func observeSettings() {
        settingsObservation = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySettingsChange()
            }
    }

    private func applySettingsChange() {
        restartSamplingIfNeeded()
        updateStatusItemTitle()
        requestNotificationAuthorizationIfNeeded()
    }

    // MARK: - 采样节拍（后台 Task；主线程只赋值快照）

    private func startMonitoring() {
        guard samplingTask == nil else { return }
        let interval = settings.monitorRefreshIntervalSeconds
        samplingInterval = interval
        // Task.detached 不继承 MainActor：host_processor_info / IOKit 这些系统调用
        // 全部在后台线程跑，节拍用 Task.sleep，不再占主线程 Timer。
        // 单例永生，MainActor.run 里再取 shared（访问落在主线程隔离域内）；
        // disable()/重启通过 cancel 终止循环。
        samplingTask = Task.detached(priority: .utility) {
            var sampler = SystemMetricSampler()
            // 立刻出第一帧（各速率为 "—"），之后按设置间隔轮询。
            while !Task.isCancelled {
                let snapshot = sampler.tick()
                // 回主线程只做赋值与标题/通知，绝不在主线程采样。
                await MainActor.run {
                    MenuBarManager.shared.apply(snapshot)
                }
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break // sleep 被取消 = 采样任务被 disable()/重启掐掉，正常退出
                }
            }
        }
    }

    private func restartSamplingIfNeeded() {
        let interval = settings.monitorRefreshIntervalSeconds
        guard samplingInterval != interval else { return }
        samplingTask?.cancel()
        samplingTask = nil
        samplingInterval = interval
        if statusItem != nil {
            startMonitoring()
        }
    }

    private func stopMonitoring() {
        samplingTask?.cancel()
        samplingTask = nil
        samplingInterval = nil
    }

    private func apply(_ snapshot: MetricSnapshot) {
        guard !fixtureFrozen else { return }
        self.snapshot = snapshot
        updateStatusItemTitle()
        evaluateThresholdNotifications(at: snapshot.sampledAt == .distantPast ? Date() : snapshot.sampledAt)
    }

    /// 仅供无头截图注入确定快照（照 MM_GUARDIAN_FIXTURE 的写法）：
    /// 只替换展示数据、不启动采样循环，整页定格在夹具值上便于逐档核对。
    /// 生产路径永不调用——采样循环走 `apply(_:)`。
    func applyFixture(_ snapshot: MetricSnapshot) {
        fixtureFrozen = true
        stopMonitoring()
        self.snapshot = snapshot
        updateStatusItemTitle()
    }

    // MARK: - 标题

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        var parts: [String] = []
        if settings.showCPUMetric {
            parts.append("CPU \(Self.percentText(snapshot.totalCPU))")
        }
        if settings.showMemoryMetric {
            parts.append("MEM \(Self.percentText(snapshot.memory?.usedRatio))")
        }
        if settings.showNetworkMetric {
            let up = snapshot.networkUpBytesPerSecond.map { MMFormat.compactBytes(UInt64($0)) + "/s" } ?? "—"
            let down = snapshot.networkDownBytesPerSecond.map { MMFormat.compactBytes(UInt64($0)) + "/s" } ?? "—"
            parts.append("↑\(up) ↓\(down)")
        }
        button.title = parts.isEmpty ? "MacMaster" : parts.joined(separator: "  ")
    }

    /// 量不出来就显示 "—"，不显示 0%。入参是 0...1 比值。
    nonisolated static func percentText(_ ratio: Double?) -> String {
        guard let ratio else { return "—" }
        return MMFormat.percent(ratio)
    }

    /// Swap 一行（I9）。`sysctl(VM_SWAPUSAGE)` 读不到 → "—"；读到且已用与总量都是 0 →
    /// 补一句"未使用"：「0 字节 / 0 字节」在中文里读起来像采样坏了，而它其实是"确实一点没用"。
    /// 只有两侧同为 0 才省略这个对仗——一侧有数就照原样报「已用 / 总量」，不替用户解释。
    nonisolated static func swapText(_ memory: MemoryMetrics, compact: Bool = false) -> String {
        guard memory.swapAvailable else { return "—" }
        let used: String, total: String
        if compact {
            used = MMFormat.compactBytes(memory.swapUsedBytes)
            total = MMFormat.compactBytes(memory.swapTotalBytes)
        } else {
            used = MMFormat.bytes(memory.swapUsedBytes)
            total = MMFormat.bytes(memory.swapTotalBytes)
        }
        if memory.swapUsedBytes == 0 && memory.swapTotalBytes == 0 {
            return "\(used)（未使用）"
        }
        return "\(used) / \(total)"
    }

    // MARK: - Threshold notifications

    private func requestNotificationAuthorizationIfNeeded() {
        guard !notificationAuthorizationRequested else { return }
        guard settings.notifyHighCPU || settings.notifyLowMemory else { return }
        guard supportsUserNotifications else {
            notificationAuthorizationRequested = true
            return
        }
        notificationAuthorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 跨阈值时通知一次（带冷却）：CPU ≥ 85%、内存 ≥ 90%。
    /// 快照里对应值为 nil（未采出）时不评估，而不是当 0 处理。
    private func evaluateThresholdNotifications(at now: Date) {
        if let cpu = snapshot.totalCPU {
            let cpuPercent = cpu * 100
            if settings.notifyHighCPU && cpuPercent >= cpuThreshold {
                let cooledDown = lastCPUNotificationAt.map { now.timeIntervalSince($0) >= notificationCooldown } ?? true
                if !cpuAboveThreshold && cooledDown {
                    lastCPUNotificationAt = now
                    postNotification(
                        identifier: "macmaster.cpu.high",
                        title: "CPU 使用率过高",
                        body: String(format: "当前 CPU 使用率 %.0f%%，请检查是否有异常进程占用资源。", cpuPercent)
                    )
                    cpuAboveThreshold = true
                } else if !cpuAboveThreshold {
                    cpuAboveThreshold = true // 冷却期内再次越线只静默吸收，避免重复推送
                }
            } else if cpuPercent < cpuThreshold - 5 {
                cpuAboveThreshold = false
            }
        }

        if let ratio = snapshot.memory?.usedRatio {
            let memPercent = ratio * 100
            if settings.notifyLowMemory && memPercent >= memoryThreshold {
                let cooledDown = lastMemoryNotificationAt.map { now.timeIntervalSince($0) >= notificationCooldown } ?? true
                if !memoryAboveThreshold && cooledDown {
                    lastMemoryNotificationAt = now
                    postNotification(
                        identifier: "macmaster.memory.low",
                        title: "内存不足",
                        body: String(format: "当前内存使用率 %.0f%%（%.1f / %.1f GB），建议关闭部分应用。",
                                     memPercent, memoryUsedGB, memoryTotalGB)
                    )
                    memoryAboveThreshold = true
                } else if !memoryAboveThreshold {
                    memoryAboveThreshold = true
                }
            } else if memPercent < memoryThreshold - 5 {
                memoryAboveThreshold = false
            }
        }
    }

    private func postNotification(identifier: String, title: String, body: String) {
        guard supportsUserNotifications else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { _ in }
    }
}

// MARK: - 下拉菜单

@MainActor
final class MenuDelegate: NSObject, NSMenuDelegate {
    static let shared = MenuDelegate()

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let snapshot = MenuBarManager.shared.snapshot

        let header = NSMenuItem(title: "MacMaster 系统监控", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(Self.infoItem("CPU: \(MenuBarManager.percentText(snapshot.totalCPU))"))

        if !snapshot.perCoreCPU.isEmpty {
            let coreItem = NSMenuItem(title: "每核 CPU", action: nil, keyEquivalent: "")
            coreItem.isEnabled = false
            let coreMenu = NSMenu()
            for (index, usage) in snapshot.perCoreCPU.enumerated() {
                coreMenu.addItem(Self.infoItem("核 \(index + 1): \(MenuBarManager.percentText(usage))"))
            }
            coreItem.submenu = coreMenu
            menu.addItem(coreItem)
        }

        if let memory = snapshot.memory {
            menu.addItem(Self.infoItem("内存: \(MMFormat.compactBytes(memory.usedBytes)) / \(MMFormat.compactBytes(memory.totalBytes)) (\(MenuBarManager.percentText(memory.usedRatio)))"))
            menu.addItem(Self.infoItem("压缩: \(MMFormat.compactBytes(memory.compressedBytes))"))
            menu.addItem(Self.infoItem("Swap: \(MenuBarManager.swapText(memory, compact: true))"))
        } else {
            menu.addItem(Self.infoItem("内存: —"))
        }

        switch snapshot.diskIOStatus {
        case .ok:
            let read = snapshot.diskReadBytesPerSecond.map { MMFormat.compactBytes(UInt64($0)) + "/s" } ?? "—"
            let write = snapshot.diskWriteBytesPerSecond.map { MMFormat.compactBytes(UInt64($0)) + "/s" } ?? "—"
            menu.addItem(Self.infoItem("磁盘 IO: 读 \(read)  写 \(write)"))
        case .unavailable(let reason):
            menu.addItem(Self.infoItem("磁盘 IO: —"))
            menu.addItem(Self.captionItem(reason))
        }

        let up = snapshot.networkUpBytesPerSecond.map { MMFormat.rate($0, up: true) } ?? "↑ —"
        let down = snapshot.networkDownBytesPerSecond.map { MMFormat.rate($0, up: false) } ?? "↓ —"
        menu.addItem(Self.infoItem("网络: \(up)  \(down)"))

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "打开 MacMaster...", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private static func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// 磁盘 IO 拿不到时的副标题说明行（二级灰字，不吞原因）。
    private static func captionItem(_ text: String) -> NSMenuItem {
        let item = infoItem(text)
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)),
            ]
        )
        return item
    }

    @objc private func openApp() {
        // 若启动时选择了「最小化到菜单栏」（activation policy 被切到 .accessory、
        // 主窗口被 orderOut），这里恢复常规模式并重新显示主窗口。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        Task { @MainActor in
            MenuBarManager.shared.disable()
            NSApp.terminate(nil)
        }
    }
}
