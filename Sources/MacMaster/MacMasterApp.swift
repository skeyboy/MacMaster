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
        // 用 `Window` 而不是 `WindowGroup`：后者把"外部送进来一个 URL"当成"再开一个窗口"，
        // 于是深链一按就出现第二扇主窗口（实测：`open -a MacMaster.app -u macmaster://…`
        // 之后 pid 不变、`title=MacMaster` 的窗口从 1 扇变 2 扇，新那扇还是 `.defaultSize` 的
        // 1100×700——`LaunchWindowSizeOverride` 是一次性的，只夹得住第一扇）。
        // 两扇 `MainWindow` 各有自己的 `@StateObject`，而卸载页的点名队列是进程级的，
        // 谁先 `onChange` 谁吃掉点名，另一扇就停在没选中的样子——那是给用户看两个互相矛盾的结论。
        // 本应用从设计上就是单窗口（侧栏 + 访问过的模块常驻），单例场景才是它本来的形状。
        Window("MacMaster", id: "main") {
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
                // 深链入口：`macmaster://uninstall?path=/Applications/Foo.app`。
                // 这是 FinderSync 扩展的必要条件（扩展那边只会拼一条 URL 交给 `NSWorkspace.open`），
                // 但它今天就能单独用：`open` 一条命令、或者「打开方式」把 bundle 交给我们。
                .onOpenURL { url in
                    appState.handleOpen(url: url)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
        // macOS 用户的第一个反射是应用菜单里的「设置…」或者 ⌘,。这一版之前两处都没有：
        // 设置只能从主窗口侧栏底部那一枚按钮进，窗口一收进菜单栏就无处可去。
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { appState.requestSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
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

    /// 菜单栏下拉里「设置...」发来的请求。监听挂在进程级对象上而不是视图上：
    /// MMMonitor 那一层拿不到本类的状态，而主窗口收进菜单栏时视图侧的 onReceive 已经没了。
    private var openSettingsObserver: NSObjectProtocol?

    init() {
        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .mmOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.requestSettings() }
        }
    }

    func selectModule(_ id: String) {
        selectedModuleID = id
    }

    /// 三个入口（应用菜单「设置…」+ ⌘,、侧栏底部按钮、菜单栏下拉）都收在这一处。
    func requestSettings() {
        showSettings = true
    }

    /// 入站 URL 只有一件事可以做：把卸载页指向那个 bundle 去**扫描**。
    ///
    /// 它碰不到删除，两重：`UninstallerModel.focusInbound(paths:)` 只认清单里已有的条目，
    /// 而删除入参只从"当前选中项的残留列表 + 用户勾选"拼，外面送进来的字符串没有一条路
    /// 变成那个入参（判据与实测见 `UninstallerOpenURL`）。
    ///
    /// 先进队再跳转，顺序不能反：卸载页在跳转这一刻才建立，反过来的话
    /// 它 `.task` 消费时队里还是空的，这次点名就只能等下一条 URL。
    func handleOpen(url: URL) {
        let paths = UninstallerOpenURL.bundlePaths(from: url)
        guard paths.isEmpty == false else {
            FileHandle.standardError.write("收到的 URL 里没有可用的 path=：\(url.absoluteString)\n"
                .data(using: .utf8)!)
            return
        }
        UninstallerScanRequest.shared.enqueue(paths)
        MMNavigation.go(.uninstaller)
    }
}
