import Foundation

// MARK: - 跨模块跳转
//
// 模块包之间不允许互相依赖（MMCore 是谁都能 import 的那一层），所以跳转用通知解耦：
// 模块只说"我要去 disk"，由根视图决定怎么切。这样诊断项可以直接把用户送到能处理问题的页面，
// 而不是留一个点了没反应的按钮。

public enum MMDestination: String, Sendable {
    case dashboard
    case cleaner
    case uninstaller
    case disk
    case monitor
    case guardian
    case optimizer
}

public enum MMNavigation {
    public static let didRequestDestination = Notification.Name("MacMaster.navigation")

    public static func go(_ destination: MMDestination) {
        NotificationCenter.default.post(name: didRequestDestination, object: destination.rawValue)
    }
}
