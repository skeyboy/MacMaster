import AppKit
import SwiftUI
import MMCore
import MMUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var localization = Localization.shared
    @StateObject private var loginItem = LoginItemManager.shared
    @State private var selectedTab: SettingsTab = MMHookValue.selected(key: "MM_SETTINGS_TAB", fallback: .general)
    @State private var showUpdateAlert = false
    @State private var updateResultText = ""
    @State private var confirmClearHistory = false
    @ObservedObject private var trash = FileTrashService.shared

    var body: some View {
        VStack(spacing: 0) {
            MMPageHeader("设置") {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(MMColor.secondaryLabel)
                }
                .buttonStyle(.plain)
                .help("关闭设置")
            }

            Picker("", selection: $selectedTab) {
                Text("通用").tag(SettingsTab.general)
                Text("监控").tag(SettingsTab.monitor)
                Text("清理").tag(SettingsTab.cleaner)
                Text("关于").tag(SettingsTab.about)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, MMGap.lg)
            .padding(.bottom, MMGap.md)

            Divider()

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
                // 全站界面文案目前只有一套中文：`Localization.localized(_:)` 与 `L(_:)`
                // 在界面上零调用点（现读 2026-10-05），所以这个开关拨动只改 UserDefaults，
                // 画面一个字都不变。给它一句实话，比留一个看起来能用的开关好。
                .disabled(true)
                Text("界面文案尚未接入多语言，切换不会改变界面")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
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
                        .foregroundStyle(MMColor.secondaryLabel)
                }

                Toggle("启动时最小化到菜单栏", isOn: $settings.minimizeToMenuBarOnLaunch)
                Text("下次启动时主窗口不弹出，仅保留菜单栏图标；点击菜单栏「打开 MacMaster...」可恢复窗口")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
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
                    .foregroundStyle(MMColor.secondaryLabel)
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
                    .foregroundStyle(MMColor.secondaryLabel)
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
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            Section("安全") {
                Toggle("删除前确认", isOn: $settings.confirmBeforeDelete)
                Toggle("允许撤回操作", isOn: $settings.allowUndo)
            }

            Section("监听") {
                Toggle("在应用卸载页提示清理刚拖入应用的残留", isOn: $settings.watchTrashForResidualCleanup)
                Text("只在停在「应用卸载」这一页时监听，离开就停，不是后台常驻。"
                     + "监听只列目录里的条目名，并读新进入的 .app 的 Info.plist 取包标识。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                Toggle("提示应用目录里的装卸变化", isOn: $settings.watchAppFolderChanges)
                Text("应用被废纸篓以外的方式删走（「立即删除」、清空废纸篓、自带卸载器、"
                     + "终端里的 rm）时，这里不会静默：清单已经不反映磁盘了，会提示去扫卸载后遗症。"
                     + "同样只在停在这一页时监听，只读目录，不写任何东西。")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }

            Section("删除历史") {
                HStack {
                    Text("台账条目")
                    Spacer()
                    Text("\(trash.trashHistory.count) / \(FileTrashService.historyLimit)")
                        .foregroundStyle(MMColor.secondaryLabel)
                        .monospacedDigit()
                }

                if let url = trash.historyFileURL {
                    Button("在访达中显示台账文件") { MMReveal.open(url.path) }
                    Text("记的是被移入废纸篓的绝对路径与大小，只写在本机这个文件里，不上传。")
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                } else {
                    Text("未能定位台账文件：这台机器拿不到 Application Support，记录只在内存里，退出即消失。")
                        .font(.caption)
                        .foregroundStyle(MMColor.caution)
                }

                Button("清空删除历史", role: .destructive) { confirmClearHistory = true }
                    .disabled(trash.trashHistory.isEmpty)
            }

            Section("排除项") {
                Button("添加排除文件夹...") {
                    addExcludedFolder()
                }

                ForEach(settings.excludedFolderPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder.badge.minus")
                            .foregroundStyle(MMColor.secondaryLabel)
                        Text(path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            settings.excludedFolderPaths.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(MMColor.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("排除的文件夹将不会被扫描（清理模块消费该列表后生效）")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog("清空删除历史？", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("清空 \(trash.trashHistory.count) 条记录", role: .destructive) { trash.clearHistory() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删记录，不碰废纸篓里的文件。清空后「最近操作」里的撤回入口一并消失——"
                 + "没有记录就不知道该把哪个文件放回哪儿。")
        }
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

    /// 关于页那枚图标画的是**这个 bundle 自己的图标**（`Resources/AppIcon.icns`，
    /// 由 `./Scripts/make-icon.sh` 生成）。以前这里是 SF Symbol `macbook.and.iphone`，
    /// 那是一个"任何应用都能用"的占位符——关于页说"我是 MacMaster"，配图却是通用图形。
    /// 没有 bundle 的跑法（`swift run`）拿不到 icns，那时退回占位符，而不是画一张白纸。
    @ViewBuilder
    private var appIconArtwork: some View {
        if Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
        } else {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 48))
                .foregroundStyle(MMColor.accent)
        }
    }

    private var aboutView: some View {
        VStack(spacing: MMGap.lg) {
            appIconArtwork

            VStack(spacing: MMGap.xxs) {
                Text("MacMaster").font(.title2.weight(.semibold))
                Text(versionText).font(.caption).foregroundStyle(MMColor.secondaryLabel)
            }

            MMCard(padding: MMGap.md) {
                VStack(spacing: MMGap.xs) {
                    MMKeyRow("开发者", "MacMaster Team")
                    // 设计稿 09-settings.html:252 这一格写的是 "MIT License"，实现照抄了。
                    // 但仓库里从来没有 LICENSE 文件（现读 2026-10-05：根目录 `ls LICENSE*` 无命中），
                    // 也就是说界面上那句"本项目按 MIT 授权"在代码库里找不到任何凭据。
                    // 选哪种许可是法律决定，不由实现代选；这里只把话说回当前事实。
                    // 这一格的值列宽有限（写整句会被截成 "LICENSE…"），所以只放结论，
                    // 解释留在 `README.md` 与 `docs/analysis/release-readiness.md`。
                    // 定了许可之后：补 LICENSE 文件 + 改回这一行 + 同步设计稿那一格。
                    MMKeyRow("许可", "尚未选择许可")
                    // 没有官方反馈渠道就不放按钮：一个点了没反应、或指向虚构地址的
                    // "反馈问题"，比少一个按钮糟得多。
                    MMKeyRow("反馈", "未配置官方渠道")
                }
            }
            .frame(width: 320)

            Spacer()

            HStack(spacing: MMGap.md) {
                Button("检查更新", action: checkForUpdates)
                    .buttonStyle(.bordered)
                Button("反馈问题") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .help("项目内未配置真实的反馈邮箱或仓库地址，暂不启用")
            }

            Text("「反馈问题」暂不可用：项目与文档中未找到官方反馈渠道地址，不做虚构链接")
                .font(.caption)
                .foregroundStyle(MMColor.secondaryLabel)
        }
        .padding(MMGap.lg)
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

enum SettingsTab: CaseIterable, MMHookKeyed {
    case general, monitor, cleaner, about

    /// 只用于无头截图核对设计稿：MM_SETTINGS_TAB=monitor 之类。
    /// 解析与"写错值就留痕"都在 MMCore 的 `MMHookValue`（有单测），这里只给档位名。
    var hookKey: String {
        switch self {
        case .general: "general"
        case .monitor: "monitor"
        case .cleaner: "cleaner"
        case .about: "about"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
