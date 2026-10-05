import Combine
import Foundation

/// 全局用户设置存储：以 UserDefaults 为后端，使用显式类型化 key。
///
/// - 所有值在 init 时从 UserDefaults 读出（配合 register(defaults:) 保证首次启动
///   即与 UI 可见默认值一致），后续每次赋值自动回写。
/// - UI 层通过 SwiftUI `.environmentObject(AppSettings.shared)` 注入并绑定。
/// - 约定：仅在主线程写入（UI 绑定路径），读取线程安全（值类型快照）。
/// - 界面语言不在本存储中，由 `Localization` 自身通过 @AppStorage 持久化。
///   持久化是好的，**生效不是**：`L(_:)` 在界面上零调用点，切换语言目前不改变任何文案
///   （设置页那一行已按"暂不生效"如实标注）。
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // MARK: - Typed keys

    public enum Key: String, CaseIterable {
        case launchAtLogin = "settings.general.launchAtLogin"
        case minimizeToMenuBarOnLaunch = "settings.general.minimizeToMenuBarOnLaunch"

        case showCPUMetric = "settings.monitor.showCPU"
        case showMemoryMetric = "settings.monitor.showMemory"
        case showNetworkMetric = "settings.monitor.showNetwork"
        case monitorRefreshInterval = "settings.monitor.refreshIntervalSeconds"
        case notifyHighCPU = "settings.monitor.notifyHighCPU"
        case notifyLowMemory = "settings.monitor.notifyLowMemory"

        case scanSystemCache = "settings.cleaner.scanSystemCache"
        case scanAppCache = "settings.cleaner.scanAppCache"
        case scanLogFiles = "settings.cleaner.scanLogFiles"
        case scanTempFiles = "settings.cleaner.scanTempFiles"
        case confirmBeforeDelete = "settings.cleaner.confirmBeforeDelete"
        case allowUndo = "settings.cleaner.allowUndo"
        case excludedFolderPaths = "settings.cleaner.excludedFolderPaths"

        case watchTrashForResidualCleanup = "settings.uninstaller.watchTrashForResidualCleanup"
        case watchAppFolderChanges = "settings.uninstaller.watchAppFolderChanges"
    }

    /// 「更新间隔」仅允许的取值（秒），与 Settings UI 的分段选项一致。
    public static let allowedMonitorIntervals: [Int] = [1, 2, 5]

    private let defaults: UserDefaults

    // MARK: - General

    /// 开机自动启动。该值是「期望状态」；真实状态以 SMAppService 为准，
    /// 由 app 目标的 LoginItemManager 在注册成功/失败后同步写回。
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue) }
    }

    @Published public var minimizeToMenuBarOnLaunch: Bool {
        didSet { defaults.set(minimizeToMenuBarOnLaunch, forKey: Key.minimizeToMenuBarOnLaunch.rawValue) }
    }

    // MARK: - Monitor

    @Published public var showCPUMetric: Bool {
        didSet { defaults.set(showCPUMetric, forKey: Key.showCPUMetric.rawValue) }
    }

    @Published public var showMemoryMetric: Bool {
        didSet { defaults.set(showMemoryMetric, forKey: Key.showMemoryMetric.rawValue) }
    }

    @Published public var showNetworkMetric: Bool {
        didSet { defaults.set(showNetworkMetric, forKey: Key.showNetworkMetric.rawValue) }
    }

    /// 菜单栏刷新间隔（秒），取值限定在 allowedMonitorIntervals。
    @Published public var monitorRefreshInterval: Int {
        didSet {
            let clamped = Self.allowedMonitorIntervals.contains(monitorRefreshInterval)
                ? monitorRefreshInterval
                : Self.defaultMonitorRefreshInterval
            if clamped != monitorRefreshInterval {
                monitorRefreshInterval = clamped
                return
            }
            defaults.set(monitorRefreshInterval, forKey: Key.monitorRefreshInterval.rawValue)
        }
    }

    @Published public var notifyHighCPU: Bool {
        didSet { defaults.set(notifyHighCPU, forKey: Key.notifyHighCPU.rawValue) }
    }

    @Published public var notifyLowMemory: Bool {
        didSet { defaults.set(notifyLowMemory, forKey: Key.notifyLowMemory.rawValue) }
    }

    // MARK: - Cleaner

    /// 以下扫描范围/安全选项当前仅持久化，供 MMCleaner/MMFileScanner 侧消费
    /// （清理扫描逻辑在另一任务线中改造，本存储不直接参与扫描）。
    @Published public var scanSystemCache: Bool {
        didSet { defaults.set(scanSystemCache, forKey: Key.scanSystemCache.rawValue) }
    }

    @Published public var scanAppCache: Bool {
        didSet { defaults.set(scanAppCache, forKey: Key.scanAppCache.rawValue) }
    }

    @Published public var scanLogFiles: Bool {
        didSet { defaults.set(scanLogFiles, forKey: Key.scanLogFiles.rawValue) }
    }

    @Published public var scanTempFiles: Bool {
        didSet { defaults.set(scanTempFiles, forKey: Key.scanTempFiles.rawValue) }
    }

    @Published public var confirmBeforeDelete: Bool {
        didSet { defaults.set(confirmBeforeDelete, forKey: Key.confirmBeforeDelete.rawValue) }
    }

    @Published public var allowUndo: Bool {
        didSet { defaults.set(allowUndo, forKey: Key.allowUndo.rawValue) }
    }

    /// 排除文件夹绝对路径列表。设置页可增删；消费点在 MMCleaner 扫描/清理链路。
    @Published public var excludedFolderPaths: [String] {
        didSet { defaults.set(excludedFolderPaths, forKey: Key.excludedFolderPaths.rawValue) }
    }

    // MARK: - Uninstaller

    /// 停在「应用卸载」页时监听废纸篓，把刚拖进来的应用提示成可清理残留的机会。
    /// 消费点在 MMUninstaller 页面（进页启动、离页停止），不是后台常驻进程。
    @Published public var watchTrashForResidualCleanup: Bool {
        didSet { defaults.set(watchTrashForResidualCleanup, forKey: Key.watchTrashForResidualCleanup.rawValue) }
    }

    /// 停在「应用卸载」页时监听应用目录，把"清单已经不反映磁盘"这件事报出来：
    /// 应用被废纸篓以外的方式删走（立即删除、`rm`、自带卸载器）时提示去扫残留，
    /// 装了新应用时提示清单过期。与上一条同样只在页面存活期监听，不是后台常驻。
    @Published public var watchAppFolderChanges: Bool {
        didSet { defaults.set(watchAppFolderChanges, forKey: Key.watchAppFolderChanges.rawValue) }
    }

    // MARK: - Setup

    public static let defaultMonitorRefreshInterval = 2

    private static func builtinDefaults() -> [String: Any] {
        [
            Key.launchAtLogin.rawValue: false,
            Key.minimizeToMenuBarOnLaunch.rawValue: false,

            Key.showCPUMetric.rawValue: true,
            Key.showMemoryMetric.rawValue: true,
            Key.showNetworkMetric.rawValue: true,
            Key.monitorRefreshInterval.rawValue: defaultMonitorRefreshInterval,
            Key.notifyHighCPU.rawValue: true,
            Key.notifyLowMemory.rawValue: true,

            Key.scanSystemCache.rawValue: true,
            Key.scanAppCache.rawValue: true,
            Key.scanLogFiles.rawValue: true,
            Key.scanTempFiles.rawValue: true,
            Key.confirmBeforeDelete.rawValue: true,
            Key.allowUndo.rawValue: true,
            Key.excludedFolderPaths.rawValue: [String](),

            Key.watchTrashForResidualCleanup.rawValue: true,
            Key.watchAppFolderChanges.rawValue: true,
        ]
    }

    /// 允许注入自定义 suite（用于单测/命令行校验）；生产代码用 .standard。
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.builtinDefaults())

        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)
        self.minimizeToMenuBarOnLaunch = defaults.bool(forKey: Key.minimizeToMenuBarOnLaunch.rawValue)

        self.showCPUMetric = defaults.bool(forKey: Key.showCPUMetric.rawValue)
        self.showMemoryMetric = defaults.bool(forKey: Key.showMemoryMetric.rawValue)
        self.showNetworkMetric = defaults.bool(forKey: Key.showNetworkMetric.rawValue)

        let storedInterval = defaults.integer(forKey: Key.monitorRefreshInterval.rawValue)
        self.monitorRefreshInterval = Self.allowedMonitorIntervals.contains(storedInterval)
            ? storedInterval
            : Self.defaultMonitorRefreshInterval

        self.notifyHighCPU = defaults.bool(forKey: Key.notifyHighCPU.rawValue)
        self.notifyLowMemory = defaults.bool(forKey: Key.notifyLowMemory.rawValue)

        self.scanSystemCache = defaults.bool(forKey: Key.scanSystemCache.rawValue)
        self.scanAppCache = defaults.bool(forKey: Key.scanAppCache.rawValue)
        self.scanLogFiles = defaults.bool(forKey: Key.scanLogFiles.rawValue)
        self.scanTempFiles = defaults.bool(forKey: Key.scanTempFiles.rawValue)
        self.confirmBeforeDelete = defaults.bool(forKey: Key.confirmBeforeDelete.rawValue)
        self.allowUndo = defaults.bool(forKey: Key.allowUndo.rawValue)
        self.excludedFolderPaths = defaults.stringArray(forKey: Key.excludedFolderPaths.rawValue) ?? []
        self.watchTrashForResidualCleanup = defaults.bool(forKey: Key.watchTrashForResidualCleanup.rawValue)
        self.watchAppFolderChanges = defaults.bool(forKey: Key.watchAppFolderChanges.rawValue)
    }

    /// 供 MenuBarManager 等处使用的秒数（保底 >= 1，避免除零）。
    public var monitorRefreshIntervalSeconds: TimeInterval {
        TimeInterval(max(1, monitorRefreshInterval))
    }
}
