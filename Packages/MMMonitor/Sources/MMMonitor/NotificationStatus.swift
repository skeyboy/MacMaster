import Foundation
import UserNotifications

/// 「通知」这一栏的真实授权状态。
///
/// 为什么光有开关不够：设置里那两个开关说的是"用户希望通知"，系统记的是"这个 app
/// 有没有被允许发通知"，两者不是一回事。用户在系统设置里拒过一次之后，开关照样拨得动、
/// `requestAuthorization` 也不会再弹（它只在"未决定"时有效），于是这一栏看起来一切正常、
/// 实际一条通知都发不出去。P29 之前这里没有任何地方把授权状态露出来。
@MainActor
public final class NotificationStatusModel: ObservableObject {
    public static let shared = NotificationStatusModel()

    /// nil = 拿不到（脱离 .app bundle 运行；那种情况下 `UNUserNotificationCenter.current()`
    /// 会直接崩进程，所以根本不碰）。
    @Published public private(set) var authorizationStatus: UNAuthorizationStatus?

    private init() {}

    public func refresh() async {
        guard MenuBarManager.supportsUserNotifications else { return }
        let center = UNUserNotificationCenter.current()
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// 授权状态 → 这一栏下面那句实话。返回 nil 表示状态正常（已授权），不用多说。
    public nonisolated static func caption(for status: UNAuthorizationStatus?) -> String? {
        switch status {
        case .authorized:
            return nil
        case .notDetermined:
            return "系统还没被问过：把上面任一开关打开时才会弹授权询问，在那之前通知一条也不会发。"
        case .denied:
            return "系统里已拒绝 MacMaster 发送通知：这两个开关拨成开也不会有任何通知，要去系统设置里允许。"
        case .provisional:
            return "通知是「静默投递」状态：会进通知中心，但不会弹横幅、也不会响。"
        case nil:
            return "当前跑法拿不到系统的通知授权状态（脱离 .app bundle 直接跑就是这样），这里只按开关本身判断。"
        default:
            return nil
        }
    }

    /// 要不要给"打开系统设置 · 通知"这个出口。已授权时不需要；拿不到状态时也不需要
    /// （那种跑法下系统设置里根本没有 MacMaster 这一项，跳过去只会让人更困惑）。
    public nonisolated static func needsSystemSettings(for status: UNAuthorizationStatus?) -> Bool {
        switch status {
        case .notDetermined, .denied, .provisional: return true
        default: return false
        }
    }
}
