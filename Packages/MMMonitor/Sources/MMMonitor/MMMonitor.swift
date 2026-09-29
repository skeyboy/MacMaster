import SwiftUI
import MMCore

public struct MonitorModule: ModuleRegistrable {
    public var moduleID: String { "monitor" }
    public var moduleName: String { "系统监控" }
    public var moduleIcon: String { "gauge" }
    public var modulePriority: Int { 4 }

    public init() {}

    public func createView() -> AnyView {
        AnyView(MonitorView())
    }
}

public struct MonitorView: View {
    @StateObject private var menuBar = MenuBarManager.shared
    @State private var processes: [MonitorProcess] = []

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    gaugeSection
                    processSection
                }
                .padding()
            }
        }
        .onAppear {
            if !menuBar.isEnabled {
                menuBar.enable()
            }
            loadProcesses()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle-67percent")
                .font(.largeTitle)
                .foregroundStyle(.purple)
            VStack(alignment: .leading) {
                Text("系统监控")
                    .font(.title2.bold())
                Text("实时监控系统资源使用情况")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("菜单栏监控", isOn: Binding(
                get: { menuBar.isEnabled },
                set: { $0 ? menuBar.enable() : menuBar.disable() }
            ))
            .toggleStyle(.switch)
        }
        .padding()
    }

    private var gaugeSection: some View {
        HStack(spacing: 16) {
            GaugeCard(title: "CPU", value: menuBar.cpuUsage, unit: "%", color: .blue, icon: "cpu")
            GaugeCard(title: "内存", value: menuBar.memoryUsage, unit: "%", color: .green, icon: "memorychip")
            GaugeCard(title: "上传", value: menuBar.networkUp, unit: "KB/s", color: .orange, icon: "arrow.up.circle")
            GaugeCard(title: "下载", value: menuBar.networkDown, unit: "KB/s", color: .cyan, icon: "arrow.down.circle")
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("进程 TOP 10")
                    .font(.headline)
                Spacer()
                Button {
                    loadProcesses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ForEach(processes.prefix(10)) { proc in
                HStack {
                    Text(proc.name)
                        .font(.body)
                    Spacer()
                    Text(String(format: "CPU %.1f%%", proc.cpuUsage))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(proc.cpuUsage > 50 ? .red : .secondary)
                    Text(formatMemory(proc.memoryMB))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(.rect(cornerRadius: 6))
            }
        }
    }

    private func loadProcesses() {
        var pids = [pid_t](repeating: 0, count: 2048)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return }

        var procs: [MonitorProcess] = []
        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var info = proc_taskallinfo()
            let size = MemoryLayout<proc_taskallinfo>.size
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: Int8.self, capacity: size) {
                    proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, $0, Int32(size))
                }
            }
            guard result > 0 else { continue }

            let name = withUnsafePointer(to: &info.pbsd.pbi_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }

            let cpu = Double(info.ptinfo.pti_total_user + info.ptinfo.pti_total_system) / 1_000_000
            let memMB = Double(info.ptinfo.pti_virtual_size) / 1_048_576

            procs.append(MonitorProcess(
                name: name.isEmpty ? "pid:\(pid)" : name,
                pid: pid,
                cpuUsage: cpu,
                memoryMB: memMB
            ))
        }

        processes = procs.sorted { $0.cpuUsage > $1.cpuUsage }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb > 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}

struct MonitorProcess: Identifiable {
    let id = UUID()
    let name: String
    let pid: Int32
    let cpuUsage: Double
    let memoryMB: Double
}

struct GaugeCard: View {
    let title: String
    let value: Double
    let unit: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(value / 100, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: value)
                VStack(spacing: 0) {
                    Text(String(format: "%.0f", value))
                        .font(.title2.bold().monospacedDigit())
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 12))
    }
}
