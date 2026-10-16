import Foundation

// MARK: - 入站 URL：只回答"要扫哪个 bundle"

/// `macmaster://uninstall?path=…` 的解析。形状照抄 Uninstally 的
/// `Services/SelectionReceiver.swift:9-22`（文件 URL 与字面路径两条分支、同名参数全收），
/// 三条改动见下面各自的注释。
///
/// **这一层不认识删除。** 全仓唯一的删除出口是 `FileTrashService`，它的入参只从
/// 页面上"用户勾选的残留项"拼出来（`UninstallSelection.deletionPaths`），外面送进来的
/// 字符串没有任何一条路能变成那个入参。所以这里不需要再做一次安全判断——
/// 需要的是"送进来的东西认不出时不许瞎猜"，那由 `UninstallerModel.focusInbound(paths:)` 兜。
public enum UninstallerOpenURL {

    /// 注册进 Info.plist 的 scheme。同一个字面量写在两处：这里，
    /// 和 `Scripts/make-app.sh` 生成 `CFBundleURLTypes` 的那一段。
    public static let scheme = "macmaster"

    /// 目前唯一认识的动作主机。参考侧对 host 不加判断（任何 `uninstally://…?path=` 都收），
    /// 我们收死：以后加动作时，打错的 URL 什么都不做，而不是被别的动作吃掉。
    public static let actionHost = "uninstall"

    /// 参数名。访达多选传进来就是同一个名字重复出现，所以按名字全收、保序、去重。
    public static let pathParameter = "path"

    /// 收到一条 URL，返回它点名的 bundle 路径（可能为空 = 这条 URL 没有任何可用点名）。
    ///
    /// 只收**绝对路径**：相对路径要先猜"基于什么解析"，猜错的后果是选中另一个应用，
    /// 那比不选更糟。参考侧连这一步都没有（`SelectionReceiver.swift:15-17` 只要值非空就收）。
    ///
    /// 后缀不在这里判：能不能算一个可卸载的 bundle 由应用清单说了算
    ///（`AppScanner` 只枚举 `.app`），这里再写一条 `.hasSuffix(".app")` 只会多出第二个口径。
    public static func bundlePaths(from url: URL) -> [String] {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == actionHost else { return [] }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [] }
        var seen: Set<String> = []
        var paths: [String] = []
        for item in items where item.name == pathParameter {
            guard let path = pathValue(item.value) else { continue }
            if seen.insert(path).inserted { paths.append(path) }
        }
        return paths
    }

    /// 取值有两种形态：`path=/Applications/Foo.app` 和 `path=file:///Applications/Foo.app`
    /// （后者是参考侧 `SelectionReceiver.swift:16` 那条 `isFileURL` 分支，我们从别的应用转发时
    /// 拼的就是这一种）。两种都归成一条路径；给不出绝对路径的一律返回 nil。
    ///
    /// 编码这一层实测过（`xcrun swift` 直接喂含 `%20`、`%2B`、字面 `+` 的查询串）：
    /// `URLComponents.queryItems` 已经把 `%20`→空格、`%2B`→`+` 解开了，
    /// 且**不会**把字面 `+` 当 form 编码变成空格，所以这里不再手动解码。
    private static func pathValue(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        if trimmed.hasPrefix("file://") {
            guard let fileURL = URL(string: trimmed), fileURL.scheme == "file" else { return nil }
            return fileURL.path.isEmpty ? nil : fileURL.path
        }
        return trimmed.hasPrefix("/") ? trimmed : nil
    }
}

// MARK: - 还没被页面消费的那一次点名

/// 收到了但卸载页还没来得及用的点名请求。
///
/// 放进程级而不是视图的 `@State`，因为两种时序都会发生：页面活着时送到这里（普通一次变更），
/// 以及**冷启动/别的页面时**送到这里而视图还没建（`MainWindow.swift:207-213` 只渲染访问过的模块）。
/// 只订阅 `onChange` 会漏掉后一种，而漏掉的表象是"从访达打开一个 app，窗口亮了一切没发生"——
/// 用户只会以为这功能坏了。
@MainActor
public final class UninstallerScanRequest: ObservableObject {
    public static let shared = UninstallerScanRequest()

    /// 排队中的点名，按到达顺序。空数组 = 没有待办。
    @Published public private(set) var paths: [String] = []

    public init() {}

    public func enqueue(_ newPaths: [String]) {
        guard newPaths.isEmpty == false else { return }
        paths.append(contentsOf: newPaths)
    }

    /// 取出并清空。**消费式**的：一条 URL 只该点一次名，
    /// 留在队列里的话，用户手动选别的应用之后还会被这条旧点名抢回去。
    public func consume() -> [String] {
        let pending = paths
        paths = []
        return pending
    }
}
