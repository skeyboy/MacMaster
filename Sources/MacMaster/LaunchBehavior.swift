import AppKit
import Foundation
import ServiceManagement
import MMCore

/// 「开机自动启动」的真实执行者：SMAppService.mainApp。
///
/// 注意：本仓库产物是 ad-hoc 签名、手工组装的 .app bundle（无 Developer ID、未公证），
/// 在这种构建配置下 register() 有可能抛出错误或无法跨重启持久化。
/// 这里不做任何假装成功：UI 一律以 SMAppService 的真实 status + 本类的 lastError
/// 为准，注册失败时把错误原文和原因展示给用户。
@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    /// 真实注册状态（以系统为准，不由设置存储单方面宣称）。
    @Published var isEnabled: Bool
    /// 最近一次注册/注销失败的原因；nil 表示无错误。
    @Published var lastError: String?

    private var cachedSettings: AppSettings { AppSettings.shared }

    private init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// 把系统真实状态同步回设置存储，避免「存储说开、系统说关」。
    func syncFromSystem() {
        isEnabled = SMAppService.mainApp.status == .enabled
        cachedSettings.launchAtLogin = isEnabled
    }

    func setEnabled(_ desired: Bool) {
        lastError = nil
        do {
            if desired {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "登录项操作失败：\(error.localizedDescription)。当前为 ad-hoc 签名的手工打包构建（无 Developer ID / 未公证），macOS 可能拒绝注册登录项；正式签名打包后此功能方可稳定生效。"
        }
        // 一切以系统真实状态收尾，不假装成功
        isEnabled = SMAppService.mainApp.status == .enabled
        cachedSettings.launchAtLogin = isEnabled
    }
}

/// 「启动时最小化到菜单栏」的一次性执行器。
/// 只在首个主窗口出现时应用一次（该设置语义上是「启动时」行为，不是运行中开关）。
@MainActor
enum LaunchMinimizeHandler {
    private static var didApply = false

    static func applyOnceIfEnabled(settings: AppSettings) {
        guard !didApply else { return }
        didApply = true
        guard settings.minimizeToMenuBarOnLaunch else { return }

        // onAppear 时窗口刚创建、尚未完成上屏，排到下一个主队列 tick 再收起。
        DispatchQueue.main.async {
            for window in NSApp.windows {
                let className = String(describing: type(of: window))
                if className.contains("StatusBar") || window is NSPanel { continue }
                if window.isVisible {
                    window.orderOut(nil)
                }
            }
            // 切到菜单栏模式（无 Dock 图标）；菜单栏「打开 MacMaster...」会恢复为 .regular。
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// 截图核对用的外观强制。设计稿是浅色档、以往实机取证清一色深色档，两边从来没在
/// 同一档上对照过，"色档一致"其实是拿浅色稿比深色照片得出来的。这里只改本进程的
/// `NSApp.appearance`，不动用户的系统外观设置；未设 `MM_APPEARANCE` 时零影响。
enum LaunchAppearanceOverride {
    static func applyIfNeeded(_ env: [String: String] = ProcessInfo.processInfo.environment) {
        guard let raw = env["MM_APPEARANCE"] else { return }
        guard let scheme = MMLaunchHook.resolveAppearance(raw: raw) else {
            // 写错值会静默沿用系统外观，而截图看上去照样"是真的"——必须留痕
            MMHookValue.emit("MM_APPEARANCE=\(raw) 不是 light/dark，沿用系统外观")
            return
        }
        NSApplication.shared.appearance = NSAppearance(named: Self.name(for: scheme))
        MMHookValue.emit("MM_APPEARANCE=\(raw) 已强制 \(raw) 外观（仅本进程，不改系统设置）")
    }

    /// 唯一的 AppKit 触点：色档到 `NSAppearance.Name` 的映射。
    /// 接受哪些写法、写错怎么办都在 `MMLaunchHook.resolveAppearance`（MMCore，有单测）。
    private static func name(for scheme: MMColorScheme) -> NSAppearance.Name {
        switch scheme {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

/// 截图核对用的窗口尺寸强制。走 `setContentSize` 而不是 `.defaultSize`：后者只在
/// "没有恢复记录"时生效，而 SwiftUI 会按窗口标识自动存档frame，第二次起就被忽略，
/// 于是同一份脚本两次跑出来的可视区高度不一样，逐屏几何结论就不成立了。
@MainActor
enum LaunchWindowSizeOverride {
    private static var didApply = false

    static func applyOnce(_ env: [String: String] = ProcessInfo.processInfo.environment) {
        guard !didApply else { return }
        didApply = true
        guard let raw = env["MM_WINDOW_SIZE"] else { return }
        guard let request = MMLaunchHook.resolveWindowSize(raw: raw) else {
            MMHookValue.emit("MM_WINDOW_SIZE=\(raw) 解析失败（要写成 900x600），沿用默认尺寸")
            return
        }
        let width = request.width, height = request.height
        // 与 LaunchMinimizeHandler 同理：onAppear 时窗口尚未完成上屏。
        DispatchQueue.main.async {
            for window in NSApp.windows where Self.isMainWindow(window) {
                window.setContentSize(NSSize(width: width, height: height))
                window.center()
                // 报"生效值"而不是"请求值"，而且要等布局稳定再读：内容区有 minWidth 地板，
                // 夹取发生在 setContentSize 之后的布局轮里——就地读、甚至再排一轮 async 都
                // 还会拿到没夹过的 900（实测：同一批截图 2000px 宽 = 1000pt，日志却写 900）。
                // 日志说"实际 900x600"、照片其实是 1000x600，拿它当"最小窗口"的证据就是假的。
                // 0.3s 远早于截图脚本的 3.5s 等待，所以这条凭据一定在照片之前落进日志。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let size = window.frame.size
                    let clamped = Int(size.width) != Int(width) || Int(size.height) != Int(height)
                    MMHookValue.emit(
                        "MM_WINDOW_SIZE=\(raw) 请求 \(Int(width))x\(Int(height))pt，窗口实际 \(Int(size.width))x\(Int(size.height))pt"
                            + (clamped ? "（被 .frame(minWidth:minHeight:) 夹住，见 MacMasterApp）" : ""))
                }
                return
            }
            MMHookValue.emit("MM_WINDOW_SIZE=\(raw) 没找到主窗口，尺寸未改")
        }
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        let className = String(describing: type(of: window))
        guard className.contains("StatusBar") == false, window is NSPanel == false else { return false }
        return window.isVisible
    }
}
