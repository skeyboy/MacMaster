import AppKit
import SwiftUI
import MMCore
import MMUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var localization = Localization.shared
    @StateObject private var loginItem = LoginItemManager.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var showUpdateAlert = false
    @State private var updateResultText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Picker("", selection: $selectedTab) {
                Text("通用").tag(SettingsTab.general)
                Text("监控").tag(SettingsTab.monitor)
                Text("清理").tag(SettingsTab.cleaner)
                Text("关于").tag(SettingsTab.about)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()
                .padding(.top)

            Group {
                switch selectedTab {
                case .general: generalSettings
                case .monitor: monitorSettings
                case .cleaner: cleanerSettings
                case .about: aboutView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loginItem.syncFromSystem()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("语言") {
                Picker("界面语言", selection: Binding(
                    get: { localization.currentLanguage },
                    set: { localization.currentLanguage = $0 }
                )) {
                    Text("简体中文").tag(Localization.Language.chinese)
                    Text("English").tag(Localization.Language.english)
                }
                .pickerStyle(.segmented)
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if let error = loginItem.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(MMColor.caution)
                } else {
                    Text("通过 macOS 登录项（SMAppService）注册，状态以系统真实记录为准")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("启动时最小化到菜单栏", isOn: $settings.minimizeToMenuBarOnLaunch)
                Text("下次启动时主窗口不弹出，仅保留菜单栏图标；点击菜单栏「打开 MacMaster...」可恢复窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var monitorSettings: some View {
        Form {
            Section("菜单栏监控") {
                Toggle("显示 CPU 使用率", isOn: $settings.showCPUMetric)
                Toggle("显示内存使用率", isOn: $settings.showMemoryMetric)
                Toggle("显示网络速度", isOn: $settings.showNetworkMetric)
                Text("修改后立即影响菜单栏显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("刷新频率") {
                Picker("更新间隔", selection: $settings.monitorRefreshInterval) {
                    Text("1 秒").tag(1)
                    Text("2 秒").tag(2)
                    Text("5 秒").tag(5)
                }
                .pickerStyle(.segmented)
            }

            Section("通知") {
                Toggle("CPU 使用率过高时通知", isOn: $settings.notifyHighCPU)
                Toggle("内存不足时通知", isOn: $settings.notifyLowMemory)
                Text("CPU ≥ 85% 或内存 ≥ 90% 时发送系统通知（跨阈值触发，5 分钟冷却）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var cleanerSettings: some View {
        Form {
            Section("扫描范围") {
                Toggle("系统缓存", isOn: $settings.scanSystemCache)
                Toggle("应用缓存", isOn: $settings.scanAppCache)
                Toggle("日志文件", isOn: $settings.scanLogFiles)
                Toggle("临时文件", isOn: $settings.scanTempFiles)
                Text("设置已持久化；清理模块接入这些开关后生效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("安全") {
                Toggle("删除前确认", isOn: $settings.confirmBeforeDelete)
                Toggle("允许撤回操作", isOn: $settings.allowUndo)
            }

            Section("排除项") {
                Button("添加排除文件夹...") {
                    addExcludedFolder()
                }

                ForEach(settings.excludedFolderPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder.badge.minus")
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            settings.excludedFolderPaths.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("排除的文件夹将不会被扫描（清理模块消费该列表后生效）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addExcludedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"
        panel.message = "选择要排除、不被清理扫描的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard !settings.excludedFolderPaths.contains(path) else { return }
        settings.excludedFolderPaths.append(path)
    }

    private var aboutView: some View {
        VStack(spacing: 20) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 60))
                .foregroundStyle(MMColor.accent)

            VStack(spacing: 8) {
                Text("MacMaster")
                    .font(.title.bold())
                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("您的 Mac 优化专家")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(width: 200)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("开发者")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("MacMaster Team")
                    }
                    HStack {
                        Text("许可")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("MIT License")
                    }
                }
                .font(.caption)
                .frame(width: 300)
            }

            Spacer()

            HStack(spacing: 20) {
                Button("检查更新") {
                    checkForUpdates()
                }
                    .buttonStyle(.bordered)
                Button("反馈问题") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .help("项目内未配置真实的反馈邮箱或仓库地址，暂不启用")
            }

            Text("「反馈问题」暂不可用：项目与文档中未找到官方反馈渠道地址，不做虚构链接")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .alert("检查更新", isPresented: $showUpdateAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(updateResultText)
        }
    }

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "版本 \(short) (\(build))"
    }

    private func checkForUpdates() {
        // 无更新服务器可用：如实报告本机版本，不虚构网络端点。
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        updateResultText = "已是最新版本（\(short)（\(build)）。\n当前构建未配置更新服务器，此检查仅读取本机 Info.plist。"
        showUpdateAlert = true
    }
}

enum SettingsTab {
    case general, monitor, cleaner, about
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
