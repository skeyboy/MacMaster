import Foundation
import Darwin

// MARK: - 删除硬保护清单

/// 所有删除动作的唯一闸口。`FileTrashService.moveToTrash` 是 9 个模块共用的出口，
/// 上游扫描器的误判、调用方拼错的路径、设计稿之外的新入口，最后都从这里出去，
/// 所以"绝对不能进废纸篓"的东西必须在这里挡，而不是指望每个调用方自己检查。
///
/// 与 `MMDisk` 里那份 `protectedRoots` 不是一回事：那份只用来给 treemap 上色
/// （风险标签，可以商量），这份是拒绝执行。两者口径不同是故意的。
public enum DeletionGuard {

    public struct Rejection: Equatable, Sendable {
        public let path: String
        /// 直接给用户看的一句话，说明为什么不动它。
        public let reason: String
    }

    /// 系统目录：大小写不敏感比较。APFS 默认不区分大小写，`/system` 和 `/System`
    /// 是同一个 inode，只做区分大小写的前缀匹配等于漏判（Mole 的删除回归里就栽过）。
    ///
    /// 写的是 `canonicalize` 之后的形态，所以 `/etc`、`/var/db` 不带 `/private` 前缀 ——
    /// 真实目录在 `/private` 下，但那三个别名会被统一掉，见 `privateAliases`。
    private static let systemRoots: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/Library",
        "/etc", "/var/db", "/var/root",
        // `/dev` 与 `/private` 是补上来的那两条。别名剥前缀只认 `etc`/`var`/`tmp` 三个名字，
        // 所以 `/private/tftpboot` 这类归一之后仍然带着 `/private`，而 `/dev` 根本没有别名；
        // 磁盘页的 `DiskRemoval.systemFirstComponents` 早就把这两个名字对外说成"系统树"了，
        // 闸门这一侧此前反而没有对应的条目。
        "/dev", "/private",
    ]

    /// home 之下永不删的相对路径，**整棵子树**都要挡。
    ///
    /// 判据是"这个位置里有没有不可再生的东西"：私钥删了就没了，缓存删了会自动长回来。
    /// 这里刻意**不收** `~/.npm`、`~/.cargo` 这类开发工具目录：它们里面的缓存正是清理
    /// 模块的合法目标，一刀切会把已有功能废掉，所以只点名真正存密钥的那几个位置。
    ///
    /// `Data/vms` 而不是 `Data`：Docker/OrbStack 的虚拟磁盘镜像在 `Data/vms/**` 下（按上游
    /// 文档的布局，本机未安装这两个软件、无法实测目录树），而 `Data/Library/Caches` 是
    /// 沙盒容器缓存类别的正常目标。挡根会把能清的一起挡掉，挡 vms 才刚好卡住镜像文件。
    private static let protectedHomeSubtrees: [String] = [
        ".ssh", ".gnupg", ".aws", ".azure", ".config/gh",
        "Library/Keychains", "Library/CloudStorage", "Library/Mail", "Library/Calendars",
        "Library/Application Support/MobileSync", "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CallHistoryTransactions",
        "Library/Containers/com.docker.docker/Data/vms",
        "Library/Containers/com.orbstack.orbstack/Data/vms",
        "Library/Group Containers/HUAQ24HBR6.dev.orbstack/Data/vms",
    ]

    /// 只挡**目录本身**、里面的内容照常可删的相对路径。
    ///
    /// 「用户文件夹清理」页把桌面/文稿/下载/图片/影片/音乐六个目录做成了可逐项勾选、
    /// 移入废纸篓且可撤回的功能 —— 子树全挡等于把这一页废掉。但把整个目录本身一次性
    /// 扔进废纸篓是另一种量级的事故（iCloud「桌面与文稿」同步、照片图库都在这一层），
    /// 所以这一组按精确匹配处理：目录留着，里面的东西由用户逐条决定。
    private static let protectedHomeDirectories: [String] = [
        "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies",
    ]

    /// 废纸篓目录本身。里面的条目当然可以移来移去，但把 `~/.Trash` 自己塞进废纸篓
    /// 会让后续所有回收站语义失效，这一条单独挡。
    private static let trashDirectory = ".Trash"

    public static func rejection(for path: String) -> Rejection? {
        // 两个口径都要过：逻辑路径挡"写出来就很危险"，物理路径挡"符号链接绕进去"。
        // 只查其一会漏 —— ~/Downloads/link → /System 这种，逻辑上无害、物理上致命。
        if let literal = literalRejection(for: path) { return literal }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = physicalPath(trimmed)
        guard resolved != trimmed else { return nil }
        return check(resolved, original: path)
    }

    /// 只按**字面路径**判，不调 `realpath`。
    ///
    /// 给界面用：treemap 每一行都要问一次"这个能不能标"，而视图 body 里做系统调用
    /// 不划算（一次重排几十上百行）。执行那一层照旧走 `rejection(for:)` 的两遍口径，
    /// 所以这里少掉的只是"链接指向受保护目录"那一类，界面上标得出、执行时仍会被挡。
    public static func literalRejection(for path: String) -> Rejection? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return Rejection(path: path, reason: "空路径：没有任何东西会被移走。")
        }
        return check(trimmed, original: path)
    }

    // MARK: 正向闸（允许根）

    /// 黑名单回答"这里绝不能动"，它永远补不全 —— "这个位置本来就不归这个功能管"
    /// 这一类误判没有任何一条黑名单能对上。允许根回答的是另一半：这次操作只可能在这几个目录里。
    ///
    /// 纯字面判定，不调 `realpath`：与 `literalRejection` 同一个理由（视图里做系统调用不划算），
    /// 而且纯函数才能把三档边界钉死在单测里 —— 根本身、同前缀的兄弟目录、大小写。
    public static func isInside(_ path: String, roots: [String]) -> Bool {
        let normalized = canonicalize(path)
        return roots.contains { rawRoot in
            let root = rawRoot.trimmingCharacters(in: .whitespacesAndNewlines)
            guard root.isEmpty == false else { return false }
            // 空串归一之后是 `/`，拿它当前缀等于放行整台机器 —— 那正是这道闸要挡的东西。
            let canonicalRoot = canonicalize(root)
            guard canonicalRoot != "/" else { return false }
            return matches(normalized, prefix: canonicalRoot) && equals(normalized, canonicalRoot) == false
        }
    }

    /// 执行处用的正向闸：**字面路径与 `realpath` 之后的路径都要在根内**。
    ///
    /// 只查字面会漏 `~/Library/Caches/Foo → ~/Documents/重要目录` 这一类别名：负向黑名单挡得住
    /// "逃进保护区"，挡不住"逃出自己的职责范围"。与 `rejection(for:)` 一样，
    /// 解析失败时 `physicalPath` 原样返回，等于退回只按字面判，而不是"读不到就当安全"。
    public static func allowedRootRejection(for path: String, roots: [String]) -> Rejection? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isInside(trimmed, roots: roots) else {
            return Rejection(path: path, reason: "不在本次操作允许的位置之内（只处理清单列出的那几个目录），已拒绝。")
        }
        let resolved = physicalPath(trimmed)
        guard isInside(resolved, roots: roots) else {
            return Rejection(path: path,
                             reason: "这条路径实际指向允许位置之外（\(resolved)），已拒绝。")
        }
        return nil
    }

    private static func check(_ path: String, original: String) -> Rejection? {
        let normalized = canonicalize(path)

        if normalized == "/" {
            return Rejection(path: original, reason: "这是系统根目录本身，不是里面的某个文件。")
        }
        for root in systemRoots where matches(normalized, prefix: root) {
            return Rejection(path: original, reason: "位于系统目录 \(root) 之下，本应用不删系统域内容。")
        }

        let home = canonicalize(NSHomeDirectory())
        if equals(normalized, home) {
            return Rejection(path: original, reason: "这是你的主目录本身。")
        }
        if equals(normalized, home + "/" + trashDirectory) {
            return Rejection(path: original, reason: "废纸篓目录本身不能进废纸篓。")
        }
        for relative in protectedHomeSubtrees where matches(normalized, prefix: home + "/" + relative) {
            return Rejection(path: original,
                             reason: "属于主目录下的凭证或活数据（\(relative)），不在可清理范围内。")
        }
        for relative in protectedHomeDirectories where equals(normalized, home + "/" + relative) {
            return Rejection(path: original,
                             reason: "这是 \(relative) 目录本身。逐项选择里面的内容可以移入废纸篓，"
                                   + "整个目录不行——它可能正被 iCloud 同步或当作图库根目录。")
        }
        return nil
    }

    // MARK: 路径工具

    /// `realpath` 解析符号链接。解析失败（文件本就不存在，这在删除前很常见）时原样返回，
    /// 让逻辑路径那一遍继续起作用，而不是"读不到就当安全"。
    ///
    /// 本机实测：macOS 的 C `realpath` 要求全路径每一段都存在，末段缺失也返回 NULL/ENOENT，
    /// 和 glibc"允许最后一段不存在"的行为不同 —— 别指望它能兜住断链。
    static func physicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// `/etc`、`/var`、`/tmp` 是指向 `/private` 下同名的符号链接（本机实测 `ls -ld`）。
    /// 同一个目录因此有两种写法，硬保护清单只认一种就必须先归一：把 `/private` 前缀剥掉。
    /// 反方向（只保留 `/private/...`）也能自洽，但 `/private` 会连带影响别名下面的深层路径，
    /// 剥前缀的规则最短：只在第一段是这三个名字时剥。
    private static let privateAliases: Set<String> = ["etc", "var", "tmp"]

    /// 归一路径：先做纯字面清理（`.`、`..`、重复斜杠、尾部斜杠），再统一 `/private` 别名。
    ///
    /// 这里刻意不用 `URL.standardizedFileURL`：它内部会跟着符号链接重写路径，实测
    /// `standardize("/private/etc/hosts")` 得到 `/etc/hosts`，而
    /// `standardize("/private/var/db/receipts/x")` 原样返回（末段不存在）—— 同一个函数
    /// 对同一类路径给两种结果，等于清单里的字面量什么时候生效看运气。保护清单的比较
    /// 基准必须是确定性的，宁可不解析符号链接（符号链接另有 `physicalPath` 那一遍负责）。
    static func canonicalize(_ path: String) -> String {
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..":
                // 根目录没有父目录，`/..` 仍是 `/`；不能让它把清单前缀弹出根外。
                if components.isEmpty == false { components.removeLast() }
            default: components.append(String(component))
            }
        }
        if let first = components.first, first == "private",
           components.count > 1, privateAliases.contains(components[1]) {
            components.removeFirst()
        }
        return "/" + components.joined(separator: "/")
    }

    /// 按**路径组件**边界比较，且大小写不敏感。
    /// `"/Library"` 必须命中 `/Library/Foo`，但不能命中 `/LibraryFoo`；
    /// `"/system"` 在 APFS 上就是 `/System`。
    private static func matches(_ path: String, prefix: String) -> Bool {
        let haystack = path.lowercased()
        let needle = prefix.lowercased()
        if needle == "/" { return haystack.hasPrefix("/") }
        if haystack == needle { return true }
        return haystack.hasPrefix(needle.hasSuffix("/") ? needle : needle + "/")
    }

    /// 整个路径相等与否：同样大小写不敏感 —— `~/documents` 和 `~/Documents` 在 APFS 上
    /// 是同一个目录，"目录本身"这条线不能因为用户少按一个 shift 就绕过去。
    private static func equals(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() == rhs.lowercased()
    }
}
