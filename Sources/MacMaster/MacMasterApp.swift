import SwiftUI
import MMCore
import MMUI
import MMCleaner
import MMUninstaller
import MMDisk
import MMMonitor
import MMGuardian
import MMOptimizer

// MARK: - App Entry

@main
struct MacMasterApp: App {
    @StateObject private var moduleRegistry = ModuleRegistry.shared
    @StateObject private var appState = AppState()
    @StateObject private var settings = AppSettings.shared

    init() {
        // 外观要在第一个窗口上屏之前定下来：晚一步就会拍到半深半浅的窗口，
        // 那种照片看起来只是"截图失败了"，实际是把整轮色档结论污染掉。
        LaunchAppearanceOverride.applyIfNeeded()
        registerAllModules()
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(moduleRegistry)
                .environmentObject(appState)
                .environmentObject(settings)
                // 下限不是拍脑袋：设计稿 `tokens.css` 里 `.content { min-width: --content-min }`
                // 钉的是 760pt，侧栏实测 220pt，所以窗口内容区要到 1000pt 才不违反稿自己的
                // 地板值。之前写 900 时内容区只有 670pt，磁盘页头部（分段控件 + 筛选框 +
                // 两个按钮）直接放不下，按钮标题被截成"重新…""选择…"。
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear {
                    MenuBarManager.shared.enable()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
    }

    private func registerAllModules() {
        let registry = ModuleRegistry.shared
        registry.register(CleanerModule())
        registry.register(UninstallerModule())
        registry.register(DiskModule())
        registry.register(MonitorModule())
        registry.register(GuardianModule())
        registry.register(OptimizerModule())
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    /// 概览不是注册模块（它不进 moduleRegistry），但它必须是侧边栏里第一个被选中的行：
    /// 留 nil 的话侧边栏没有任何高亮，用户看不出自己在哪一页。
    @Published var selectedModuleID: String? = MMDestination.dashboard.rawValue
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var showSettings = false

    func selectModule(_ id: String) {
        selectedModuleID = id
    }
}
