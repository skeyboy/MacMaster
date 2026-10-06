import Foundation
import MMCore

/// treemap 的风险标签：决定界面上哪一行给得出"标进回收清单"这个按钮。
///
/// 与 `DeletionGuard` 的分工是两件事 —— 那份拒绝执行，这一份决定承诺。
/// P21 之前两处各存一份系统目录清单，口径靠人肉对齐，结果是 `/etc/hosts`、
/// `/var/db/receipts/…`、`/system/…`（少按一个 shift）、主目录本身、`~/.ssh/…`
/// 这些行在界面上都显示成"可标记"，等用户真的标了，才由闸门在最后一刻拒绝。
/// 现在这条线只有一个来源：**闸门按字面路径就会拒绝的，这里就不给按钮**。
/// 这份清单自己比闸门更保守的那几档照旧留着（六个用户目录**里面的内容**、
/// `/LibraryFoo` 这类前缀误伤）—— 少给一个按钮不是假话，多给一个才是。
enum DiskRisk {

    private static let protectedRoots = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private/etc"]

    /// 六个用户目录：整棵子树在 treemap 里按只读上色。闸门只挡目录本身、放行内容，
    /// 这里比闸门严是**故意**的——磁盘页是看体积的地方，不是逐项清理用户文件的地方，
    /// 那一页有专门的「用户文件夹清理」。
    private static let userDataDirectories = ["Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]

    private static let rebuildable: Set<String> = ["Caches", "DerivedData", "node_modules", "Logs",
                                                   ".Trash", ".cache", "Build", "build", "CoreSimulator"]

    /// `home` 只为那两条前缀规则可注入；闸门那一遍问的是进程真实主目录（`DeletionGuard`
    /// 内部用 `NSHomeDirectory()`），传别的 home 不会改变闸门那一遍的结论。
    static func risk(of path: String, home: String = NSHomeDirectory()) -> MMRisk {
        if protectedRoots.contains(where: { path.hasPrefix($0) }) { return .readOnly }
        if userDataDirectories.map({ home + "/" + $0 })
            .contains(where: { path.hasPrefix($0) }) { return .readOnly }
        // 兜底那一问：清单里没写、但闸门按字面路径就会拒绝的（`/etc`、`/var/db`、
        // 大小写变体、主目录与废纸篓本身、凭证子树），一律不再承诺"可以标"。
        if DeletionGuard.literalRejection(for: path) != nil { return .readOnly }
        if path.split(separator: "/").contains(where: { rebuildable.contains(String($0)) }) { return .safe }
        return .caution
    }
}
