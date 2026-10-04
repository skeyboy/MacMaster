import Foundation
import Darwin

/// 扫描进度共享对象：后台扫描线程上报，UI 轮询读取。
/// 与 MMDisk 中 ScanProgressTracker 相同的模式，保证 UI 能显示进度而不在主线程做文件遍历。
public final class FileScanProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _currentPath: String = ""
    private var _fileCount: Int = 0

    public init() {}

    public var currentPath: String { lock.withLock { _currentPath } }
    public var fileCount: Int { lock.withLock { _fileCount } }

    public func report(path: String) {
        lock.withLock {
            _fileCount += 1
            _currentPath = path
        }
    }
}

/// 共享的文件遍历逻辑。全部放在非隔离的 enum 中，绝不放在 View 里：
/// View 结构体隐式 @MainActor，把遍历放进 View 会卡死主线程（本仓库曾有 1000+ 秒卡顿教训）。
/// 性能特征对齐 MMDisk 的 DiskScanner：每个条目单次 lstat、任务组有限并行、
/// 目录大小由子项求和得出（不对同一目录二次枚举）、符号链接不跟随。
enum FileTreeWalker {
    struct Entry {
        let name: String
        let path: String
        let isDirectory: Bool
        let size: UInt64      // 目录恒为 0，大小由子节点求和
        let modificationDate: Date
    }

    struct Stats {
        var size: UInt64 = 0
        var fileCount: Int = 0
    }

    private static let maxDepth = 20
    private static let maxParallelDepth = 3
    private static let workerLimit = max(2, ProcessInfo.processInfo.activeProcessorCount)

    /// 单次 lstat 同时取得类型、大小与修改时间。
    /// TCC 拒绝或权限不足时 contentsOfDirectory/lstat 只是返回错误，本函数返回空数组，不崩溃、不阻塞。
    static func readEntries(path: String) -> [Entry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }

        var entries: [Entry] = []
        entries.reserveCapacity(names.count)
        for name in names {
            if name.hasPrefix(".") { continue }
            if Task.isCancelled { break }
            let fullPath = path + "/" + name
            var info = stat()
            guard Darwin.lstat(fullPath, &info) == 0 else { continue }

            let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            entries.append(Entry(
                name: name,
                path: fullPath,
                isDirectory: isDirectory,
                size: isDirectory ? 0 : UInt64(info.st_size),
                modificationDate: Self.date(fromTimespec: info.st_mtimespec)
            ))
        }
        return entries
    }

    /// 递归统计目录大小与文件数（有限并行、可取消；访问失败的子目录静默计 0）。
    static func stats(
        path: String,
        depth: Int = 0,
        tracker: FileScanProgressTracker? = nil
    ) async -> Stats {
        if Task.isCancelled { return Stats() }
        let entries = readEntries(path: path)

        var result = Stats()
        var directories: [Entry] = []
        for entry in entries {
            tracker?.report(path: entry.path)
            if entry.isDirectory {
                directories.append(entry)
            } else {
                result.size += entry.size
                result.fileCount += 1
            }
        }
        guard !directories.isEmpty else { return result }

        if depth >= maxDepth {
            for dir in directories {
                if Task.isCancelled { return result }
                let sub = fallbackStats(path: dir.path, remainingDepth: 3)
                result.size += sub.size
                result.fileCount += sub.fileCount
            }
            return result
        }

        if depth < maxParallelDepth && directories.count > 1 {
            await withTaskGroup(of: Stats.self) { group in
                var next = 0
                while next < min(workerLimit, directories.count) {
                    let dir = directories[next]
                    next += 1
                    group.addTask {
                        await stats(path: dir.path, depth: depth + 1, tracker: tracker)
                    }
                }
                while let sub = await group.next() {
                    result.size += sub.size
                    result.fileCount += sub.fileCount
                    if next < directories.count {
                        let dir = directories[next]
                        next += 1
                        group.addTask {
                            await stats(path: dir.path, depth: depth + 1, tracker: tracker)
                        }
                    }
                }
            }
        } else {
            for dir in directories {
                if Task.isCancelled { return result }
                let sub = await stats(path: dir.path, depth: depth + 1, tracker: tracker)
                result.size += sub.size
                result.fileCount += sub.fileCount
            }
        }
        return result
    }

    /// 深度上限处的一次性有限递归兜底统计，不构建节点。
    static func fallbackStats(path: String, remainingDepth: Int) -> Stats {
        if Task.isCancelled || remainingDepth <= 0 { return Stats() }
        var result = Stats()
        for entry in readEntries(path: path) {
            if entry.isDirectory {
                let sub = fallbackStats(path: entry.path, remainingDepth: remainingDepth - 1)
                result.size += sub.size
                result.fileCount += sub.fileCount
            } else {
                result.size += entry.size
                result.fileCount += 1
            }
        }
        return result
    }

    // MARK: - 合并遍历（P6.3b：activityProbe + stats 两趟并一趟）
    //
    // 形状、集合规则与理由全部照 docs/analysis/dev-artifact-walk-merge.md §3：
    // **stats / readEntries / DirectoryMetrics 的签名与语义这里一字未动**——它们另有
    // UserFolderScanner / SystemAnalyzer / InstallerScanner / MMUninstaller（经
    // DirectoryMetrics）四个消费方，同一目录在清理页与磁盘页的数字不许互相矛盾
    // （文件头纪律 2）。合并口是 internal，只被本模块的 ProjectArtifactScanner 消费。

    /// 合并入口的返回形状（调研 §3.3）。
    struct SubtreeWalk: Sendable {
        /// 遍历没走完的原因。nil = 完整跑完（嵌套档允许在撞到近期文件后合法早退）。
        enum Stop: String, Sendable {
            case deadline
            case cancelled
        }
        /// 与 readEntries **完全同集合**的体积和：点条目（连同其子树）不计、
        /// 符号链接按链接自身 st_size 计入、20+3 层之外静默不计——
        /// 数值必须与 stats(path:) 逐位相等（调研 §6.8：对拍不等价就是事故口径）。
        var size: UInt64 = 0
        var fileCount: Int = 0
        /// 与 listAllEntries **完全同集合**的活动判断：含点条目、跳过符号链接、无深度上限。
        var sawRecentFile: Bool = false
        /// fail-closed 通道：枚举失败且目录仍存在（既不是"空目录"，也不是"目录消失"）。
        /// 封顶 16 条——消费方只需要"有没有 + 第一条是谁"（调研 §4.2）。
        var unreadableDirectories: [String] = []
        var stopReason: Stop?
        /// 深于 23 层的静默截断的显式化：数值与今天的 stats 一致，此旗标只说明"越过了"。
        var sizeDepthTruncated: Bool = false

        static let unreadableDirectoriesCap = 16

        /// 群上的合并（调研 §3.1"把活动累加做成群上的幺半组"）。
        /// 停止原因优先级：cancelled > deadline > nil；读不进按收集顺序拼接并封顶。
        mutating func merge(_ other: SubtreeWalk) {
            size += other.size
            fileCount += other.fileCount
            sawRecentFile = sawRecentFile || other.sawRecentFile
            sizeDepthTruncated = sizeDepthTruncated || other.sizeDepthTruncated
            for dir in other.unreadableDirectories where unreadableDirectories.count < Self.unreadableDirectoriesCap {
                unreadableDirectories.append(dir)
            }
            switch (stopReason, other.stopReason) {
            case (_, .some(.cancelled)): stopReason = .cancelled
            case (.none, .some(.deadline)): stopReason = .deadline
            default: break
            }
        }
    }

    /// 体积记账的最深条目层（候选根直接子项为第 0 层）：stats 主遍历计 0...20
    /// （:94 的 `depth >= maxDepth` 在**计入本层条目之后**才判），fallbackStats
    /// （remainingDepth 3）补到第 23 层，第 24 层起静默计 0。合并口沿用同一界限。
    private static let sizeDepthLimit = maxDepth + 3

    /// 合并入口（调研 §3.3）：一趟并两套记账。
    /// - `needSize == true`：非嵌套候选。体积 + 活动同一趟全程走完，**不早退**
    ///   （省掉的是整趟 stats；早退红利小于这个数，净赚，见 §3.2）。
    /// - `needSize == false`：嵌套候选。只要活动结论，保留旧 activityProbe 的
    ///   串行栈 + 早退——"近期在用的大嵌套目录"不许从近免费改成全量（§6.5 红线）。
    /// deadline 检查在遍历内部，每进一个目录查一次（沿用旧 activityProbe :623 的粒度）；
    /// `ProjectArtifactScanner.bounded` 的竞速包装对这条路径退役。
    static func walkForArtifact(path: String, deadline: Date, recentThreshold: Date,
                                needSize: Bool) async -> SubtreeWalk {
        if needSize {
            return await walkCountedDirectory(path, depth: 0, ancestorsCounted: true,
                                              deadline: deadline, recentThreshold: recentThreshold)
        }
        return walkActivityOnly(path: path, deadline: deadline, recentThreshold: recentThreshold)
    }

    /// 与旧 activityProbe 同形状同顺序的早退遍历：串行显式栈 DFS（LIFO），
    /// 含点条目、跳过符号链接、无深度上限；deadline/取消、第一个"读不进目录"、
    /// 第一个近期文件都**立即停**——顺序即结论（首个读不进目录写进理由字符串，
    /// 与旧实现的弹出顺序一致，前提是同一次 contentsOfDirectory 给出同序枚举）。
    private static func walkActivityOnly(path: String, deadline: Date,
                                         recentThreshold: Date) -> SubtreeWalk {
        var result = SubtreeWalk()
        var stack = [path]
        while let dir = stack.popLast() {
            if Task.isCancelled { result.stopReason = .cancelled; return result }
            if Date() >= deadline { result.stopReason = .deadline; return result }
            guard let entries = readAllEntries(path: dir) else {
                // 枚举失败：目录还在才算读不进并停在这（旧 probe 的 incomplete 即停），
                // 目录中途消失则静默跳过（旧遍历 directoryExists=false 时继续走）。
                if directoryStillExists(dir) {
                    result.unreadableDirectories.append(dir)
                    return result
                }
                continue
            }
            // 取消可能正好落在上面那次枚举中间：`readAllEntries` 会返回**半截清单**，
            // 这时候把栈走空当成"完整跑完"就会给出假的 `.noRecentFile`。
            if Task.isCancelled { result.stopReason = .cancelled; return result }
            for entry in entries {
                if entry.isSymlink { continue }   // 活动侧（listAllEntries）对符号链接完全不可见
                if entry.isDirectory {
                    stack.append(entry.path)
                } else if entry.modificationDate >= recentThreshold {
                    result.sawRecentFile = true
                    return result
                }
            }
        }
        return result
    }

    /// 非嵌套候选的全量趟：体积侧 + 活动侧同一趟各记各的账，不早退。
    /// 任务组骨架照 stats（depth < 3 并行、workerLimit 窗口滚动），把两趟的
    /// syscall（readdir + 每条目一次 lstat）收敛成一份。
    private static func walkCountedDirectory(_ path: String, depth: Int, ancestorsCounted: Bool,
                                             deadline: Date, recentThreshold: Date) async -> SubtreeWalk {
        var result = SubtreeWalk()
        if Task.isCancelled { result.stopReason = .cancelled; return result }
        if Date() >= deadline { result.stopReason = .deadline; return result }
        guard let entries = readAllEntries(path: path) else {
            if directoryStillExists(path) { result.unreadableDirectories = [path] }
            // 旧 stats 对读不进的子目录就是静默计 0 且不进（readEntries 的 try?）——
            // 体积侧行为不改，unreadableDirectories 只是新增的 fail-closed 事实通道。
            return result
        }
        // 取消可能正好落在上面那次枚举中间，那是一份**半截清单**：部分和冒充完整数字
        // 是本仓库明令的事故口径，所以这里必须把 stopReason 钉成 cancelled 再返回。
        if Task.isCancelled { result.stopReason = .cancelled; return result }
        // 两套记账的开关（调研 §3.1）：体积侧 = 祖先链全非点 ∧ 层数 ≤ 20+3；
        // 活动侧与点/深度无关，只认"非符号链接"。chain 条件与深度条件必须分开传：
        // 链条件决定 sizeDepthTruncated 是否还有意义，点目录子树本来就哪儿都不去。
        let counts = ancestorsCounted && depth <= sizeDepthLimit
        if ancestorsCounted && depth > sizeDepthLimit && !entries.isEmpty {
            result.sizeDepthTruncated = true   // 显式化"这层起 stats 也会静默少加"
        }
        var childDirectories: [(path: String, chainCounted: Bool)] = []
        for entry in entries {
            let isDot = entry.name.hasPrefix(".")
            if !entry.isDirectory && counts && !isDot {
                // 非目录一律计入——符号链接按链接自身 st_size，同 readEntries :58-66
                // 的既成事实；listAllEntries 那边则整体跳过符号链接，两边各取所需。
                result.size += entry.size
                result.fileCount += 1
            }
            if entry.isSymlink { continue }    // 活动侧不可见，也不下潜
            if entry.isDirectory {
                childDirectories.append((entry.path, ancestorsCounted && !isDot))
            } else if entry.modificationDate >= recentThreshold {
                result.sawRecentFile = true   // 不早退：体积必须量完（§3.2）
            }
        }
        guard !childDirectories.isEmpty else { return result }

        let childDepth = depth + 1
        if depth < maxParallelDepth && childDirectories.count > 1 {
            await withTaskGroup(of: SubtreeWalk.self) { group in
                var next = 0
                while next < min(workerLimit, childDirectories.count) {
                    let dir = childDirectories[next]
                    next += 1
                    group.addTask {
                        await walkCountedDirectory(dir.path, depth: childDepth, ancestorsCounted: dir.chainCounted,
                                                   deadline: deadline, recentThreshold: recentThreshold)
                    }
                }
                while let sub = await group.next() {
                    result.merge(sub)
                    if next < childDirectories.count {
                        let dir = childDirectories[next]
                        next += 1
                        group.addTask {
                            await walkCountedDirectory(dir.path, depth: childDepth, ancestorsCounted: dir.chainCounted,
                                                       deadline: deadline, recentThreshold: recentThreshold)
                        }
                    }
                }
            }
        } else {
            for dir in childDirectories {
                let sub = await walkCountedDirectory(dir.path, depth: childDepth, ancestorsCounted: dir.chainCounted,
                                                     deadline: deadline, recentThreshold: recentThreshold)
                result.merge(sub)
            }
        }
        return result
    }

    /// 合并遍历的条目：与 readEntries / listAllEntries 同一份单次 lstat 口径，
    /// 但保留点条目、保留符号链接（isSymlink 标记让两套记账各取所需），
    /// 且能区分"枚举失败"（nil，读不进）与"空目录"（[]）。lstat 失败的条目
    /// 静默丢弃——两趟旧遍历都是这个行为（readEntries :58、listAllEntries :1041）。
    private struct WalkEntry {
        let name: String
        let path: String
        let isDirectory: Bool
        let isSymlink: Bool
        let size: UInt64      // 目录恒 0；符号链接取 lstat 的链接自身 st_size
        let modificationDate: Date
    }

    private static func readAllEntries(path: String) -> [WalkEntry]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        var entries: [WalkEntry] = []
        entries.reserveCapacity(names.count)
        for name in names {
            if Task.isCancelled { break }   // 取消后整体作废（stopReason 兜住），部分枚举无害
            let fullPath = path + "/" + name
            var info = stat()
            guard Darwin.lstat(fullPath, &info) == 0 else { continue }
            let type = info.st_mode & S_IFMT
            entries.append(WalkEntry(
                name: name,
                path: fullPath,
                isDirectory: type == S_IFDIR,
                isSymlink: type == S_IFLNK,
                size: type == S_IFDIR ? 0 : UInt64(info.st_size),
                modificationDate: Self.date(fromTimespec: info.st_mtimespec)
            ))
        }
        return entries
    }

    /// "目录还在但一条都列不出"才算读不进（旧 activityProbe :627 的
    /// directoryExists + !canEnumerate 判定，语义原样保留）：目录中途消失不是
    /// 读不进，旧遍历遇到时静默跳过。
    private static func directoryStillExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// 收集目录中 >= minSize 的文件（浅层任务组并行、可取消、深度受限）。
    static func largeFiles(
        path: String,
        minSize: UInt64,
        depth: Int,
        maxDepth: Int,
        tracker: FileScanProgressTracker?
    ) async -> [Entry] {
        if Task.isCancelled || depth > maxDepth { return [] }
        let entries = readEntries(path: path)

        var hits: [Entry] = []
        var directories: [Entry] = []
        for entry in entries {
            if Task.isCancelled { break }
            tracker?.report(path: entry.path)
            if entry.isDirectory {
                directories.append(entry)
            } else if entry.size >= minSize {
                hits.append(entry)
            }
        }
        guard !directories.isEmpty else { return hits }

        if depth < 2 && directories.count > 1 {
            await withTaskGroup(of: [Entry].self) { group in
                var next = 0
                while next < min(workerLimit, directories.count) {
                    let dir = directories[next]
                    next += 1
                    group.addTask {
                        await largeFiles(path: dir.path, minSize: minSize, depth: depth + 1, maxDepth: maxDepth, tracker: tracker)
                    }
                }
                while let sub = await group.next() {
                    hits.append(contentsOf: sub)
                    if next < directories.count {
                        let dir = directories[next]
                        next += 1
                        group.addTask {
                            await largeFiles(path: dir.path, minSize: minSize, depth: depth + 1, maxDepth: maxDepth, tracker: tracker)
                        }
                    }
                }
            }
        } else {
            for dir in directories {
                if Task.isCancelled { break }
                hits.append(contentsOf: await largeFiles(
                    path: dir.path, minSize: minSize, depth: depth + 1, maxDepth: maxDepth, tracker: tracker
                ))
            }
        }
        return hits
    }

    /// 目录自身修改时间；失败返回 nil（TCC 拒绝时不崩溃）。
    static func modificationDate(ofPath path: String) -> Date? {
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { return nil }
        return date(fromTimespec: info.st_mtimespec)
    }

    private static func date(fromTimespec ts: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000)
    }

    /// 能否实际枚举目录内容。TCC 拒绝时 contentsOfDirectory 会抛错，此处返回 false，
    /// 由调用方降级为「不可访问」展示，绝不 crash、绝不等待授权弹窗之外的阻塞。
    static func canEnumerate(path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }
}

/// 供其他模块使用的目录度量入口。口径与磁盘分析保持一致：单次 lstat 取类型与大小、
/// 不跟随符号链接、目录大小由子项求和，因此同一目录下各模块显示的数字不会互相矛盾。
public enum DirectoryMetrics {
    public struct Result: Sendable {
        public let size: UInt64
        public let fileCount: Int
    }

    public static func measure(path: String) async -> Result {
        let stats = await FileTreeWalker.stats(path: path)
        return Result(size: stats.size, fileCount: stats.fileCount)
    }
}
