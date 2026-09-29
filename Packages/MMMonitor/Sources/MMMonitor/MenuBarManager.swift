import AppKit
import Combine
import UserNotifications
import MMCore

@MainActor
public final class MenuBarManager: ObservableObject {
    public static let shared = MenuBarManager()

    @Published public var cpuUsage: Double = 0
    @Published public var memoryUsage: Double = 0
    @Published public var memoryUsedGB: Double = 0
    @Published public var memoryTotalGB: Double = 0
    @Published public var networkUp: Double = 0
    @Published public var networkDown: Double = 0

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var prevCPUTimes: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var prevNetBytes: (sent: UInt64, received: UInt64)?

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

    /// 监听设置变化：间隔改变 → 重启定时器；显隐改变 → 立即重绘标题；
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
        restartTimerIfNeeded()
        updateStatusItemTitle()
        requestNotificationAuthorizationIfNeeded()
    }

    private func restartTimerIfNeeded() {
        guard let timer, timer.timeInterval != settings.monitorRefreshIntervalSeconds else { return }
        timer.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: settings.monitorRefreshIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: settings.monitorRefreshIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
        updateMetrics()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMetrics() {
        updateCPU()
        updateMemory()
        updateNetwork()
        updateStatusItemTitle()
        evaluateThresholdNotifications()
    }

    private func updateCPU() {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let user = cpuLoad.cpu_ticks.0
        let system = cpuLoad.cpu_ticks.1
        let idle = cpuLoad.cpu_ticks.2
        let nice = cpuLoad.cpu_ticks.3

        if let prev = prevCPUTimes {
            let userDelta = Double(user - prev.user)
            let systemDelta = Double(system - prev.system)
            let idleDelta = Double(idle - prev.idle)
            let niceDelta = Double(nice - prev.nice)
            let total = userDelta + systemDelta + idleDelta + niceDelta
            if total > 0 {
                cpuUsage = (userDelta + systemDelta + niceDelta) / total * 100
            }
        }

        prevCPUTimes = (user, system, idle, nice)
    }

    private func updateMemory() {
        var stats = vm_statistics64()
        var statCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(statCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &statCount)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let total = Foundation.ProcessInfo.processInfo.physicalMemory

        memoryUsedGB = (active + wired) / 1_073_741_824
        memoryTotalGB = Double(total) / 1_073_741_824
        memoryUsage = memoryUsedGB / memoryTotalGB * 100
    }

    private func updateNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        var bytesSent: UInt64 = 0
        var bytesReceived: UInt64 = 0

        var ptr = first
        while true {
            if ptr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    bytesSent += UInt64(data.pointee.ifi_obytes)
                    bytesReceived += UInt64(data.pointee.ifi_ibytes)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        if let prev = prevNetBytes {
            let sentDelta = Double(bytesSent - prev.sent)
            let recvDelta = Double(bytesReceived - prev.received)
            // 采样间隔跟随设置项，不能再用写死的 2 秒
            let interval = settings.monitorRefreshIntervalSeconds
            networkUp = sentDelta / interval / 1024
            networkDown = recvDelta / interval / 1024
        }

        prevNetBytes = (bytesSent, bytesReceived)
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        var parts: [String] = []
        if settings.showCPUMetric {
            parts.append("CPU \(String(format: "%.0f%%", cpuUsage))")
        }
        if settings.showMemoryMetric {
            parts.append("MEM \(String(format: "%.0f%%", memoryUsage))")
        }
        if settings.showNetworkMetric {
            let up = formatSpeed(networkUp)
            let down = formatSpeed(networkDown)
            parts.append("↑\(up) ↓\(down)")
        }
        button.title = parts.isEmpty ? "MacMaster" : parts.joined(separator: "  ")
    }

    private func formatSpeed(_ kbps: Double) -> String {
        if kbps > 1024 {
            return String(format: "%.1fMB", kbps / 1024)
        }
        return String(format: "%.0fKB", kbps)
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
    private func evaluateThresholdNotifications() {
        let now = Date()

        if settings.notifyHighCPU && cpuUsage >= cpuThreshold {
            let cooledDown = lastCPUNotificationAt.map { now.timeIntervalSince($0) >= notificationCooldown } ?? true
            if !cpuAboveThreshold && cooledDown {
                lastCPUNotificationAt = now
                postNotification(
                    identifier: "macmaster.cpu.high",
                    title: "CPU 使用率过高",
                    body: String(format: "当前 CPU 使用率 %.0f%%，请检查是否有异常进程占用资源。", cpuUsage)
                )
                cpuAboveThreshold = true
            } else if !cpuAboveThreshold {
                cpuAboveThreshold = true // 冷却期内再次越线只静默吸收，避免重复推送
            }
        } else if cpuUsage < cpuThreshold - 5 {
            cpuAboveThreshold = false
        }

        if settings.notifyLowMemory && memoryUsage >= memoryThreshold {
            let cooledDown = lastMemoryNotificationAt.map { now.timeIntervalSince($0) >= notificationCooldown } ?? true
            if !memoryAboveThreshold && cooledDown {
                lastMemoryNotificationAt = now
                postNotification(
                    identifier: "macmaster.memory.low",
                    title: "内存不足",
                    body: String(format: "当前内存使用率 %.0f%%（%.1f / %.1f GB），建议关闭部分应用。", memoryUsage, memoryUsedGB, memoryTotalGB)
                )
                memoryAboveThreshold = true
            } else if !memoryAboveThreshold {
                memoryAboveThreshold = true
            }
        } else if memoryUsage < memoryThreshold - 5 {
            memoryAboveThreshold = false
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

@MainActor
private class MenuDelegate: NSObject, NSMenuDelegate {
    static let shared = MenuDelegate()

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let manager = MenuBarManager.shared

        let header = NSMenuItem(title: "MacMaster 系统监控", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let cpuItem = NSMenuItem(title: String(format: "CPU: %.1f%%", manager.cpuUsage), action: nil, keyEquivalent: "")
        cpuItem.isEnabled = false
        menu.addItem(cpuItem)

        let memItem = NSMenuItem(
            title: String(format: "内存: %.1f / %.1f GB (%.0f%%)", manager.memoryUsedGB, manager.memoryTotalGB, manager.memoryUsage),
            action: nil, keyEquivalent: ""
        )
        memItem.isEnabled = false
        menu.addItem(memItem)

        let netItem = NSMenuItem(
            title: String(format: "网络: ↑ %.1f KB/s  ↓ %.1f KB/s", manager.networkUp, manager.networkDown),
            action: nil, keyEquivalent: ""
        )
        netItem.isEnabled = false
        menu.addItem(netItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "打开 MacMaster...", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
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
