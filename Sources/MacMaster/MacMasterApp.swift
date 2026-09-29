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
        registerAllModules()
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(moduleRegistry)
                .environmentObject(appState)
                .environmentObject(settings)
                .frame(minWidth: 900, minHeight: 600)
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
