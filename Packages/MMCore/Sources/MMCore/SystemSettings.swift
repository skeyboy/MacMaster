import Foundation

// MARK: - 系统设置面板标识

/// 跳到系统设置的哪一格——全仓只有这里给得出这个串。
///
/// 为什么收在一处、而且不留 String 入口：`MMReveal.openSystemSettings(pane:)` 会自己
/// 拼 `x-apple.systempreferences:` 前缀，调用方再把整串 URL 当参数传进来，拼出来就是
/// **双前缀死链**——这不是假想：清理页的权限横幅就是这么写的，P29 探针实测这一串交给
/// 系统以后面板一动不动（`docs/verification/p29-panes-v3/pane-urls.log` C 档），
/// 而 `NSWorkspace.open` 不返回成败，按钮按下去什么反馈都没有。
/// 用枚举，"手写 URL 当参数"这件事就没有编译期入口。
///
/// 面板标识本身按 macOS 13+ 的新式 extension id 统一（旧式 `com.apple.preference.security`
/// 在这台 macOS 27 上实测也还能跳，但两套写法并存迟早又长出一个不一致的调用点）。
public enum MMSettingsPane: String, CaseIterable, Sendable {
    /// 隐私与安全性 → 完全磁盘访问权限
    case fullDiskAccess = "com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
    /// 登录项与扩展
    case loginItems = "com.apple.LoginItems-Settings.extension"
    /// 通知
    case notifications = "com.apple.Notifications-Settings.extension"

    /// scheme 在全仓只出现在这一行。
    static let schemePrefix = "x-apple.systempreferences:"

    /// 面板标识串**不含** scheme：拼出来才是能用的深链，写进参数里就是双前缀死链。
    public var paneIdentifier: String { rawValue }

    public var settingsURL: URL? {
        URL(string: Self.schemePrefix + rawValue)
    }
}

// MARK: - 跨模块的设置入口请求

extension Notification.Name {
    /// 菜单栏下拉里的「设置…」发这个，壳层接：设置弹窗的状态（`AppState.showSettings`）
    /// 只有壳层持有，而 MMMonitor 拿不到它。
    public static let mmOpenSettings = Notification.Name("macmaster.openSettings")
}
