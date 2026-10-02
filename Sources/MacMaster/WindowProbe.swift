import AppKit

/// 窗口几何探针：`MM_PROBE_WINDOW=1` 时按若干时间点把每个真实窗口的 AppKit 帧打到 stderr。
///
/// 存在的理由是一类特定的 bug：SwiftUI 把某页按自己的理想高度布局，
/// `AppKitPlatformViewHost` 就跟着长高，整窗内容上下溢出——照片上看着像"整页错位"，
/// 但只有量出 host 的高度和窗口高度不相等才能定案。只读，不改任何帧；
/// 没有这个环境变量时 `start` 直接返回，产物里等于不存在。
@MainActor
enum MMWindowProbe {
    static func start(_ env: [String: String] = ProcessInfo.processInfo.environment) {
        guard env["MM_PROBE_WINDOW"] != nil else { return }
        for delay in [0.2, 1.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { dump(delay: delay) }
        }
    }

    private static func dump(delay: Double) {
        for window in NSApp.windows where window is NSPanel == false {
            let className = String(describing: type(of: window))
            guard let content = window.contentView else { continue }
            var line = "PROBE win t=\(delay) \(className) vis=\(window.isVisible)"
                + " title=\(window.title) frame=\(f(window.frame))"
                + " content=\(f(content.frame)) bounds=\(f(content.bounds))"
                + " layout=\(f(window.contentLayoutRect))"
            for sub in content.subviews {
                line += " | sub \(String(describing: type(of: sub))) \(f(sub.frame))"
            }
            FileHandle.standardError.write((line + "\n").data(using: .utf8) ?? Data())
        }
    }

    private static func f(_ r: NSRect) -> String {
        "W\(Int(r.width))xH\(Int(r.height))@Y\(Int(r.origin.y))"
    }
}
