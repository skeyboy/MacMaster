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
