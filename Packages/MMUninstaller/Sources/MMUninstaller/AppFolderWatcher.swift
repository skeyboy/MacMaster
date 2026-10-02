import Foundation
import Dispatch

// MARK: - 判定规则（纯函数）
//
// 与 `TrashWatcher` 同一套纪律：判据是纯函数，在 /tmp 夹具里完整测；
// 监听只是"什么时候重扫目录"的调度器，结论永远来自目录清单的差异，不来自事件本身。
// 为什么不能信事件体：本机探针实测（`Scripts/apps-watch-probe.swift`，
// 结论在 `docs/analysis/apps-watch.md` §3）三次目录改动收到四条 `NOTE_WRITE`，
// 分不出哪条对应哪次改动，而且目录里写一个毫不相干的普通文件同样触发。

public enum AppWatchRule {

    /// 基线里的一条应用条目。**身份必须在这时候记下来**：本体一旦离开目录，
    /// `Info.plist` 就再也读不到了，那时候才知道"消失的是 bundleID 为 X 的应用"毫无办法。
    public struct Snapshot: Equatable, Sendable {
        public let entry: String
        public let bundleID: String
        /// 显示名（本地化 `CFBundleDisplayName` 优先），不是磁盘名。
        public let name: String

        public init(entry: String, bundleID: String, name: String) {
            self.entry = entry
            self.bundleID = bundleID
            self.name = name
        }
    }

    /// 基线里有、现在没有的条目 —— 这才叫"消失"。
    public static func departed(current: Set<String>, baseline: [Snapshot]) -> [Snapshot] {
        baseline.filter { current.contains($0.entry) == false }
    }

    /// 现在有、基线里没有的条目名 —— 清单过期了。
    public static func appeared(current: [String], baseline: Set<String>) -> [String] {
        current.filter { baseline.contains($0) == false }
    }
}

// MARK: - 两个方向的结论

/// 从应用目录里消失的一个应用。`path` 是**最后已知位置**，不是"现在还在"的路径 ——
/// 界面上必须带上这四个字的语义，否则用户会以为我们还能打开它。
public struct AppDeparture: Identifiable, Equatable, Sendable {
    public let id: String
    public let directory: String
    public let entry: String
    public let path: String
    public let name: String
    public let bundleID: String

    init(directory: String, snapshot: AppWatchRule.Snapshot) {
        self.directory = directory
        self.entry = snapshot.entry
        self.path = "\(directory)/\(snapshot.entry)"
        self.name = snapshot.name
        self.bundleID = snapshot.bundleID
        self.id = path
    }
}

/// 应用目录里新出现的条目。刻意**不带包标识**：这里报的是"清单过期"这个事实，
/// 不是"这是一个可卸载应用" —— 替身与缺 `Info.plist` 的坏 bundle 也算多了个条目，
/// 而它们撑不起后一个结论。
public struct AppAppearance: Identifiable, Equatable, Sendable {
    public let id: String
    public let directory: String
    public let entry: String

    init(directory: String, entry: String) {
        self.directory = directory
        self.entry = entry
        self.id = "\(directory)/\(entry)"
    }
}

// MARK: - 监听器

/// 用 kqueue 盯应用目录，把"清单已经不反映磁盘"这件事报给页面。
/// 只做只读的目录列举与 Info.plist 解析，不写任何东西；
/// **只在页面存活期监听**（进页 `start()`、离页 `stop()`），不是后台常驻代理。
@MainActor
public final class AppFolderWatcher: ObservableObject {

    public enum Status: Equatable {
        case stopped
        case watching
        /// 一个目标都没打开才升成这个态。`needsFullDiskAccess` 只在 EPERM/EACCES 时为真 ——
        /// `/Applications` 本来是世界可读的，把"目录不存在"说成"要授权"就是猜原因。
        case unreadable(reason: String, needsFullDiskAccess: Bool)
    }

    @Published public private(set) var status: Status = .stopped
    /// 本次会话里观察到消失的应用，最新一条在最后。
    @Published public private(set) var departures: [AppDeparture] = []
    /// 本次会话里观察到新出现的条目，最新一条在最后。
    @Published public private(set) var appearances: [AppAppearance] = []
    /// 没监起来的目录 → 原因。`~/Applications` 不存在是常态，所以它只进这张表、不进横幅。
    @Published public private(set) var skippedDirectories: [String: String] = [:]

    private let directories: [String]
    private var watchedDirectories: [String] = []
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingTick: Task<Void, Never>?
    private var baseline: [String: [AppWatchRule.Snapshot]] = [:]

    public init(directories: [String]? = nil) {
        self.directories = directories ?? AppFolderWatcher.watchTargets()
    }

    /// 监听哪些目录。夹具钩子给了就只听那一个（截图要能造出"消失"，
    /// 又不能拿真 `/Applications` 做实验）；否则与列举口径完全一致 ——
    /// **监听范围必须等于 `AppScanner` 的列举范围**，
    /// 更宽就会为从来不在清单里的条目报事件（`/Applications/Utilities/Foo.app`），
    /// 更窄就会漏报。
    nonisolated public static func watchTargets() -> [String] {
        if let fixture = TrashWatcher.fixtureEnvironmentValue(key: "MM_APPS_WATCH_FIXTURE_DIR") {
            return [fixture]
        }
        return AppScanner.defaultSearchDirectories(home: NSHomeDirectory())
    }

    // MARK: 生命周期

    public func start() {
        guard sources.isEmpty else { return }
        var opened: [(directory: String, descriptor: Int32)] = []
        var skips: [String: String] = [:]
        var permissionDenied = false

        for directory in directories {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) else {
                skips[directory] = "这台机器没有这个目录"
                continue
            }
            guard isDirectory.boolValue else {
                skips[directory] = "不是目录"
                continue
            }
            let descriptor = Darwin.open(directory, O_RDONLY)
            guard descriptor >= 0 else {
                let code = errno
                skips[directory] = TrashWatcher.failureText(action: "打开目录", errnoValue: code)
                permissionDenied = permissionDenied || TrashWatcher.isPermissionFailure(code)
                continue
            }
            // 打开成功不代表读得动，列举失败要说"读不到"，不能让它冒充"目录是空的"。
            guard let entries = Self.listing(of: directory) else {
                let code = errno
                Darwin.close(descriptor)
                skips[directory] = TrashWatcher.failureText(action: "读取目录内容", errnoValue: code)
                permissionDenied = permissionDenied || TrashWatcher.isPermissionFailure(code)
                continue
            }
            baseline[directory] = Self.snapshots(in: directory, entries: entries)
            opened.append((directory, descriptor))
        }
        skippedDirectories = skips

        guard opened.isEmpty == false else {
            status = .unreadable(reason: Self.aggregateText(skips), needsFullDiskAccess: permissionDenied)
            return
        }
        watchedDirectories = opened.map(\.directory)
        status = .watching
        // 第二次进入这一页时，上一轮报过的条目可能早就不成立了：消失的那个被还原回来，
        // 新出现的那个又被删走。基线一建好先对一次账，别等第一个改动事件来收拾。
        pruneReported()
        for openedDirectory in opened { attach(directory: openedDirectory.directory,
                                               descriptor: openedDirectory.descriptor) }
    }

    public func stop() {
        pendingTick?.cancel()
        pendingTick = nil
        sources.forEach { $0.cancel() }
        sources = []
        watchedDirectories = []
    }

    /// 关掉全部提示。清单里的条目已经进过基线，改动事件不会把它们再报一遍，
    /// 所以这里只需要清空，不需要额外记账。
    public func dismiss() {
        departures = []
        appearances = []
    }

    /// 只收「多了条目」那一条。「重新载入」之外用户还可以选忽略，
    /// 这时候不该顺手把另一张卡（可能正指向别的应用）一起抹掉。
    public func dismissAppearances() {
        appearances = []
    }

    // MARK: 事件处理

    /// 内部可见：kqueue 在测试进程里不保证投递，单测直接喂一个事件把合并 + 重扫这条路走通。
    func handleEvents(_ fired: DispatchSource.FileSystemEvent) {
        if fired.contains(.delete) || fired.contains(.rename) || fired.contains(.revoke) {
            // 目录本身被换掉了，这些 fd 之后不会再来事件。重开一遍，别默默失去监听。
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

    private func attach(directory: String, descriptor: Int32) {
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
        source.resume()
        sources.append(source)
    }

    // MARK: 对账

    private func rescan() {
        var snapshot: [String: [AppWatchRule.Snapshot]] = [:]
        for directory in watchedDirectories {
            guard let entries = Self.listing(of: directory) else {
                // 事件已经证明目录刚改动，现在却读不到内容：按读不到处理。
                stop()
                let code = errno
                status = .unreadable(reason: TrashWatcher.failureText(action: "读取目录内容", errnoValue: code),
                                     needsFullDiskAccess: TrashWatcher.isPermissionFailure(code))
                return
            }
            snapshot[directory] = Self.snapshots(in: directory, entries: entries)
        }
        for directory in watchedDirectories {
            let found = snapshot[directory] ?? []
            let present = Set(found.map(\.entry))
            for old in AppWatchRule.departed(current: present, baseline: baseline[directory] ?? [])
            where TrashWatchRule.isReportable(bundleID: old.bundleID) {
                // 没有包标识就没有可靠的残留匹配线索，报出来只会给出一句
                // "没找到残留"这种听起来像结论的假话 —— 与 P1.5 同一道闸门。
                report(AppDeparture(directory: directory, snapshot: old), in: &departures)
            }
            for name in AppWatchRule.appeared(current: found.map(\.entry),
                                              baseline: Set((baseline[directory] ?? []).map(\.entry)))
            where TrashWatchRule.isAppBundleEntry(name) {
                report(AppAppearance(directory: directory, entry: name), in: &appearances)
            }
        }
        baseline = snapshot
        pruneReported()
    }

    /// 基线建好之后清一遍旧账：条目已经回到目录里的，那条"消失"就不再成立；
    /// 报过的新条目又不见了，那条"清单过期"也不再成立（它可能变成一条"消失"，
    /// 但那是下一次对账的事，这里不凭空补报）。
    private func pruneReported() {
        let presentByDirectory = baseline.mapValues { Set($0.map(\.entry)) }
        departures = departures.filter { presentByDirectory[$0.directory]?.contains($0.entry) == false }
        appearances = appearances.filter { presentByDirectory[$0.directory]?.contains($0.entry) == true }
    }

    private func report<T: Identifiable & Equatable>(_ value: T, in list: inout [T]) where T.ID == String {
        list.removeAll { $0.id == value.id }
        list.append(value)
    }

    // MARK: 读取

    private static func snapshots(in directory: String, entries: [String]) -> [AppWatchRule.Snapshot] {
        entries.filter { TrashWatchRule.isAppBundleEntry($0) }.map { entry in
            let path = "\(directory)/\(entry)"
            return AppWatchRule.Snapshot(entry: entry,
                                         bundleID: AppScanner.bundleIdentifier(at: path),
                                         name: AppScanner.displayName(at: path,
                                                                      bundleName: String(entry.dropLast(4))))
        }
    }

    /// 只列一层。读不到时返回 nil 并留下 errno，别让空数组冒充"目录是空的"。
    private static func listing(of path: String) -> [String]? {
        errno = 0
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            return nil
        }
    }

    /// 一个都没打开时的说明。逐目录把原因列出来 ——
    /// "读不到应用目录"而不说哪一个、为什么，用户就没法判断这是不是故障。
    static func aggregateText(_ skips: [String: String]) -> String {
        skips.keys.sorted().map { "\($0)：\(skips[$0] ?? "读不到")" }.joined(separator: "；")
    }
}
