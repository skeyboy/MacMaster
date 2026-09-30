import Foundation

// MARK: - 判定规则（纯函数）
//
// 真实 `~/.Trash` 在本机是 TCC 保护的：`lstat` 看得到位（`drwx------ lee staff`），
// 但 `contentsOfDirectory` 直接 NSCocoaErrorDomain 257。既然"能不能读到目录内容"
// 由授权决定，就不能拿它当测试前提 —— 把判定拆成纯函数，在 /tmp 夹具里完整测。

public enum TrashWatchRule {

    /// 值得看一眼的条目名：以 `.app` 结尾、不是隐藏项、去掉后缀还剩字。
    /// 这里只看名字不做类型判断：访达里的替身同样叫 `Foo.app`，
    /// 它读不出 `CFBundleIdentifier`，由 `isReportable` 那一关拦下。
    public static func isAppBundleEntry(_ name: String) -> Bool {
        guard name.hasSuffix(".app"), name.hasPrefix(".") == false else { return false }
        return name.dropLast(4).isEmpty == false
    }

    /// 这一批新出现的条目。`previous == nil` 表示首帧 —— 只建基线，不报事件：
    /// 启动时废纸篓里已经躺着的应用不是"刚被拖进来"，报出来等于凭空造一次操作。
    public static func appearedEntries(current: [String], previous: Set<String>?) -> [String] {
        guard let previous else { return [] }
        return current.filter { previous.contains($0) == false }
    }

    /// 能不能报给用户：包名读不出来（替身、缺 Info.plist、损坏的 bundle）
    /// 或系统自带应用都不报。前者尤其重要 —— 没有包标识就没有可靠的残留匹配线索，
    /// 硬扫一遍只会给出"没找到残留"这种听起来像结论的假话。
    public static func isReportable(bundleID: String) -> Bool {
        guard bundleID.isEmpty == false else { return false }
        return AppScanner.isSystemOwned(bundleID: bundleID) == false
    }
}

// MARK: - 一次拖入

/// 刚进废纸篓的一个应用。`entry` 是它在废纸篓目录里的条目名，
/// 判定"它还在不在废纸篓"要用这个名字对着目录清单查，不能拿路径 `fileExists` ——
/// 用户还原之后原位置也可能有个同名 app，那时提示必须消失。
public struct TrashArrival: Identifiable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let entry: String
    /// 显示名（本地化 `CFBundleDisplayName` 优先），不是磁盘名。
    public let name: String
    public let bundleID: String

    init?(trashDirectory: String, entry: String) {
        let path = "\(trashDirectory)/\(entry)"
        let bundleID = AppScanner.bundleIdentifier(at: path)
        guard TrashWatchRule.isReportable(bundleID: bundleID) else { return nil }
        self.id = path
        self.path = path
        self.entry = entry
        self.bundleID = bundleID
        self.name = AppScanner.displayName(at: path, bundleName: String(entry.dropLast(4)))
    }
}

// MARK: - 监听器

/// 用 kqueue 盯废纸篓目录的 fd，把新出现的 `.app` 报给页面。
/// 只做只读的目录列举与 Info.plist 解析，不写任何东西。
@MainActor
public final class TrashWatcher: ObservableObject {

    public enum Status: Equatable {
        case stopped
        case watching
        /// 读不到就是读不到。`needsFullDiskAccess` 只在权限被拒（EPERM/EACCES）时为真 ——
        /// 目录还没创建（ENOENT）也说成"要授权"就是猜原因。
        case unreadable(reason: String, needsFullDiskAccess: Bool)
    }

    @Published public private(set) var status: Status = .stopped
    /// 本次会话里进过废纸篓、且此刻还在里面的应用，最新一条在最后。
    @Published public private(set) var arrivals: [TrashArrival] = []

    /// 访达移入一个 `.app` 会连着发好几个 `NOTE_WRITE`，逐个处理会把同一个应用报两次。
    static let coalescingInterval: Duration = .milliseconds(400)

    private let trashDirectory: String
    private var eventSource: DispatchSourceFileSystemObject?
    private var pendingTick: Task<Void, Never>?
    private var knownEntries: Set<String>?

    public init(trashDirectory: String = TrashWatcher.watchTarget()) {
        self.trashDirectory = trashDirectory
    }

    /// 监听哪个目录：截图夹具钩子优先，否则真实废纸篓。
    /// `nonisolated` 是因为它要当 `init` 的默认值用 —— 默认参数不在隔离域里求值。
    nonisolated public static func watchTarget() -> String {
        fixtureEnvironmentValue(key: "MM_TRASH_FIXTURE_DIR") ?? (NSHomeDirectory() + "/.Trash")
    }

    /// 无头验证时残留扫描的 home。和监听目录是两个钩子：夹具废纸篓里放的是 bundle，
    /// 要让它扫出残留，得把 `~/Library` 那一侧也指到 /tmp 的假 home。
    nonisolated public static func fixtureScanHome() -> String? {
        fixtureEnvironmentValue(key: "MM_TRASH_SCAN_HOME")
    }

    /// 钩子一律只认 /tmp 下的路径 —— 和 `MM_ORPHAN_FIXTURE_HOME` 同一套规矩：
    /// 这条链路的尽头是删除按钮，指向真实主目录就等于拿用户文件做截图。
    nonisolated static func fixtureEnvironmentValue(key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key], raw.isEmpty == false else { return nil }
        guard raw.hasPrefix("/tmp/") || raw.hasPrefix("/private/tmp/") else {
            FileHandle.standardError.write(
                "\(key)=\(raw) 不在 /tmp 之下，忽略该钩子\n".data(using: .utf8)!)
            return nil
        }
        return raw
    }

    // MARK: 生命周期

    public func start() {
        guard eventSource == nil else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trashDirectory, isDirectory: &isDirectory) else {
            // 全新用户从没删过东西，`~/.Trash` 就是还不存在。
            // 这不能报成"要授权"：那是把两种原因说成一种。
            status = .unreadable(reason: "废纸篓目录还不存在：\(trashDirectory)", needsFullDiskAccess: false)
            return
        }
        guard isDirectory.boolValue else {
            status = .unreadable(reason: "\(trashDirectory) 不是目录。", needsFullDiskAccess: false)
            return
        }

        // 量过：没有完全磁盘访问时 `stat` 放行、`open` 直接 EPERM(1)，
        // 所以真实机型上第一次进来就落在这个分支，而不是"读到空目录"。
        let descriptor = Darwin.open(trashDirectory, O_RDONLY)
        guard descriptor >= 0 else {
            status = .unreadable(reason: Self.failureText(action: "打开废纸篓目录", errnoValue: errno),
                                 needsFullDiskAccess: Self.isPermissionFailure(errno))
            return
        }

        // 打开成功不代表读得动（TCC 也可能只拦 readdir），所以列举失败同样要说"读不到"，
        // 不能让它冒充"废纸篓是空的"。
        guard let entries = Self.listing(of: trashDirectory) else {
            Darwin.close(descriptor)
            let reason = Self.failureText(action: "读取废纸篓内容", errnoValue: errno)
            status = .unreadable(reason: reason, needsFullDiskAccess: Self.isPermissionFailure(errno))
            return
        }

        knownEntries = Set(entries)
        status = .watching
        // 第二次进入这一页时，上一轮留下的 arrivals 可能早就不算"刚拖进来"了：
        // 用户把它还原了，或者连废纸篓一起清空了。基线一建好就先对一次账，
        // 让已经不在了的那几条当场消失，而不是等第一个改动事件来收拾。
        arrivals = arrivals.filter { knownEntries?.contains($0.entry) ?? false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak source, weak self] in
            guard let source else { return }
            let fired = source.data
            // 回调虽排在 main queue，但它是非隔离闭包：直接改 @Published 等于绕过 MainActor。
            Task { @MainActor [weak self] in
                self?.handleEvents(fired)
            }
        }
        // 取消时由这里收尾关 fd：`stop()` 之外还要兜住"对象被丢弃却没人调 stop"。
        source.setCancelHandler { Darwin.close(descriptor) }
        eventSource = source
        source.resume()
    }

    public func stop() {
        pendingTick?.cancel()
        pendingTick = nil
        eventSource?.cancel()
        eventSource = nil
    }

    /// 关掉提示。清单里的条目已经进过基线，改动事件不会把它们再报一遍，
    /// 所以这里只需要清空，不需要额外记账。
    public func dismiss() {
        arrivals = []
    }

    // MARK: 事件处理

    /// 内部可见：kqueue 在测试进程里不保证投递，单测直接喂一个事件把合并 + 重扫这条路走通。
    func handleEvents(_ fired: DispatchSource.FileSystemEvent) {
        if fired.contains(.delete) || fired.contains(.rename) || fired.contains(.revoke) {
            // 目录本身被换掉了，这个 fd 之后不会再来事件。重开一个，别默默失去监听。
            scheduleReopen()
            return
        }
        if fired.contains(.write) { scheduleRescan() }
    }

    private func scheduleRescan() {
        pendingTick?.cancel()
        pendingTick = Task { [weak self] in
            try? await Task.sleep(for: TrashWatcher.coalescingInterval)
            guard Task.isCancelled == false else { return }
            self?.rescan()
        }
    }

    private func scheduleReopen() {
        pendingTick?.cancel()
        pendingTick = Task { [weak self] in
            try? await Task.sleep(for: TrashWatcher.coalescingInterval)
            guard Task.isCancelled == false else { return }
            guard let self else { return }
            self.stop()
            self.start()
        }
    }

    private func rescan() {
        guard let entries = Self.listing(of: trashDirectory) else {
            // 事件已经证明目录刚改动，现在却读不到内容：按读不到处理。
            stop()
            status = .unreadable(reason: Self.failureText(action: "读取废纸篓内容", errnoValue: errno),
                                 needsFullDiskAccess: Self.isPermissionFailure(errno))
            return
        }
        let present = Set(entries)
        for name in TrashWatchRule.appearedEntries(current: entries, previous: knownEntries)
        where TrashWatchRule.isAppBundleEntry(name) {
            guard let arrival = TrashArrival(trashDirectory: trashDirectory, entry: name) else { continue }
            arrivals.removeAll { $0.id == arrival.id }
            arrivals.append(arrival)
        }
        knownEntries = present
        // 用户把应用从废纸篓还原（或彻底删除）之后，提示必须消失：
        // 还原回去的应用残留是活的，这时候再提供"清理残留"就是害人的入口。
        arrivals = arrivals.filter { present.contains($0.entry) }
    }

    // MARK: 读取

    /// 只列一层。读不到时返回 nil 并留下 errno，别让空数组冒充"废纸篓是空的"。
    /// 量过：`~/.Trash` 在没有完全磁盘访问时 `contentsOfDirectory` 抛
    /// NSCocoaErrorDomain 257，而 errno 仍是真实的 EPERM(1) —— 先把 errno 清零，
    /// 读到的就不是上一次调用留下的残值。
    private static func listing(of path: String) -> [String]? {
        errno = 0
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            return nil
        }
    }

    static func isPermissionFailure(_ value: Int32) -> Bool {
        value == EPERM || value == EACCES
    }

    static func failureText(action: String, errnoValue: Int32) -> String {
        guard errnoValue != 0 else { return "无法\(action)。" }
        return "无法\(action)：\(String(cString: strerror(errnoValue)))（错误码 \(errnoValue)）。"
    }
}
