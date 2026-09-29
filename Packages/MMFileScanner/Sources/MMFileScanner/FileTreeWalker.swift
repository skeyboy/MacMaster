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
