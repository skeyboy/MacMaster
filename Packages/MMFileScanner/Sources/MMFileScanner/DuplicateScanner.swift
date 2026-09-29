import Foundation
import CryptoKit

// MARK: - 重复文件检测
//
// 这份输出会被用户当成"可以放心删的东西"，所以判定必须比"看起来一样"更严格：
// 1. 只按大小分组 + 只哈希文件头部会造成误判，误判的代价是用户丢数据；
// 2. 读取失败必须显式报告，绝不能退化成"同一个哈希"而被归为一组；
// 3. 硬链接的多个路径指向同一份内容，删掉任何一条都释放不了空间，不能算重复；
// 4. 未落地的 iCloud / File Provider 占位文件读它就得下载，直接跳过并说明原因。
//
// 三段漏斗：同大小 → 同抽样指纹（头尾各 4 MB）→ 同全量 SHA-256。
// 前两段只为省 IO，最终判定一定走完整内容。

public struct DuplicateFile: Identifiable, Hashable {
    public let id: URL
    public let path: URL
    public let size: UInt64
    public let modificationDate: Date

    public init(path: URL, size: UInt64, modificationDate: Date) {
        self.id = path
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
    }
}

public struct DuplicateGroup: Identifiable {
    /// 内容指纹（完整文件的 SHA-256）。同时作为 id，重扫之后勾选状态仍可对得上。
    public let id: String
    public let size: UInt64
    public let files: [DuplicateFile]
    /// 删掉其中 n-1 份能释放的空间。n 是去重后的独立文件数，不含硬链接别名。
    public let wastedSpace: UInt64

    public init(hash: String, size: UInt64, files: [DuplicateFile]) {
        self.id = hash
        self.hash = hash
        self.size = size
        self.files = files
        self.wastedSpace = files.isEmpty ? 0 : size * UInt64(files.count - 1)
    }

    public let hash: String

    /// 默认保留最早修改的那份（通常是"原件"），其余才是候选。
    public var suggestedKeep: URL? { files.first?.path }
}

public struct DuplicateScanReport {
    public let groups: [DuplicateGroup]
    public let candidateCount: Int
    /// 因权限 / IO 错误没能完成读取的路径。这些文件没有参与判定，也不会出现在结果里。
    public let unreadablePaths: [String]
    /// 未落地的云端占位文件，读取会触发下载，已跳过。
    public let datalessSkippedCount: Int
    /// 指向同一 inode 的多余路径数（分组前已去掉，不会被当成重复）。
    public let hardlinkAliasSkippedCount: Int
    /// false 表示用户中途停止，结果不完整，UI 不能再把它当"全量结论"。
    public let isComplete: Bool
    public let duration: TimeInterval

    public var totalWastedSpace: UInt64 { groups.reduce(0) { total, group in total + group.wastedSpace } }

    public var hasCaveats: Bool {
        !unreadablePaths.isEmpty || datalessSkippedCount > 0
    }
}

public enum DuplicateScanStage: String, Sendable {
    case preparing = "归类候选"
    case sampling = "抽样比对"
    case verifying = "逐字节校验"
}

public struct DuplicateScanProgress: Sendable {
    public let stage: DuplicateScanStage
    public let processed: Int
    public let total: Int
    public let currentPath: String?

    public init(stage: DuplicateScanStage, processed: Int, total: Int, currentPath: String?) {
        self.stage = stage
        self.processed = processed
        self.total = total
        self.currentPath = currentPath
    }

    public var fraction: Double? { total > 0 ? Double(processed) / Double(total) : nil }
}

public actor DuplicateScanner {
    private let minFileSize: UInt64
    private let sampleSize: Int
    private let readChunkSize: Int

    public init(
        minFileSize: UInt64 = 200 * 1024,
        sampleSize: Int = 4 * 1024 * 1024,
        readChunkSize: Int = 1024 * 1024
    ) {
        self.minFileSize = minFileSize
        self.sampleSize = sampleSize
        self.readChunkSize = readChunkSize
    }

    public func findDuplicates(
        in entries: [FileEntry],
        shouldContinue: @escaping @Sendable () -> Bool = { true },
        progress: (@Sendable (DuplicateScanProgress) -> Void)? = nil
    ) async -> DuplicateScanReport {
        let started = Date()
        var unreadable: [String] = []
        var datalessSkipped = 0
        var hardlinkAliases = 0
        var stopped = false

        // ---- 漏斗 0：剔除目录、过小文件、未落地文件、硬链接别名 ----
        var candidates: [FileEntry] = []
        candidates.reserveCapacity(entries.count)
        var identitySeen: Set<String> = []

        for entry in entries {
            guard shouldContinue() else { stopped = true; break }
            guard !entry.isDirectory, entry.size >= minFileSize else { continue }
            var info = stat()
            guard lstat(entry.path.path, &info) == 0 else {
                unreadable.append(entry.path.path)
                continue
            }
            // 有大小却零占用块：数据还在云端，读它就要下载。
            if info.st_blocks == 0, entry.size > 512 {
                datalessSkipped += 1
                continue
            }
            let key = "\(Int(info.st_dev)):\(info.st_ino)"
            guard identitySeen.insert(key).inserted else {
                hardlinkAliases += 1
                continue
            }
            candidates.append(entry)
        }
        progress?(.init(stage: .preparing, processed: candidates.count,
                        total: candidates.count, currentPath: nil))

        // ---- 漏斗 1：同大小 ----
        let sizeGroups = Dictionary(grouping: candidates) { $0.size }
            .values.filter { $0.count > 1 }

        // ---- 漏斗 2：同抽样指纹 ----
        var sampled: [String: [FileEntry]] = [:]
        var processed = 0
        let sampleTotal = sizeGroups.reduce(0) { total, group in total + group.count }
        sampleLoop: for group in sizeGroups {
            for entry in group {
                guard shouldContinue() else { stopped = true; break sampleLoop }
                processed += 1
                if processed % 16 == 0 || processed == sampleTotal {
                    progress?(.init(stage: .sampling, processed: processed,
                                    total: sampleTotal, currentPath: entry.path.path))
                }
                switch sampleDigest(of: entry) {
                case .failure:
                    unreadable.append(entry.path.path)
                case .success(let digest):
                    sampled[digest, default: []].append(entry)
                }
            }
        }

        // ---- 漏斗 3：抽样命中的才做全量校验 ----
        let verifyGroups = sampled.values.filter { $0.count > 1 }
        let verifyTotal = verifyGroups.reduce(0) { total, group in total + group.count }
        var fullHashGroups: [String: [FileEntry]] = [:]
        var verified = 0
        verifyLoop: for group in verifyGroups {
            for entry in group {
                guard shouldContinue() else { stopped = true; break verifyLoop }
                verified += 1
                if verified % 4 == 0 || verified == verifyTotal {
                    progress?(.init(stage: .verifying, processed: verified,
                                    total: verifyTotal, currentPath: entry.path.path))
                }
                switch fullDigest(of: entry) {
                case .failure:
                    unreadable.append(entry.path.path)
                case .success(let digest):
                    fullHashGroups[digest, default: []].append(entry)
                }
            }
        }

        let groups = fullHashGroups.compactMap { digest, files -> DuplicateGroup? in
            guard files.count > 1, let size = files.first?.size else { return nil }
            let sorted = files.sorted { a, b in
                if a.modificationDate != b.modificationDate {
                    return a.modificationDate < b.modificationDate
                }
                return a.path.path < b.path.path
            }
            return DuplicateGroup(
                hash: digest,
                size: size,
                files: sorted.map {
                    DuplicateFile(path: $0.path, size: $0.size, modificationDate: $0.modificationDate)
                }
            )
        }
        .sorted { a, b in
            if a.wastedSpace != b.wastedSpace { return a.wastedSpace > b.wastedSpace }
            return a.files.count > b.files.count
        }

        return DuplicateScanReport(
            groups: groups,
            candidateCount: candidates.count,
            unreadablePaths: unreadable,
            datalessSkippedCount: datalessSkipped,
            hardlinkAliasSkippedCount: hardlinkAliases,
            isComplete: !stopped,
            duration: Date().timeIntervalSince(started)
        )
    }

    // MARK: Hashing

    private enum HashOutcome { case success(String), failure }

    private func sampleDigest(of entry: FileEntry) -> HashOutcome {
        digest(of: entry, sampleBytes: sampleSize)
    }

    private func fullDigest(of entry: FileEntry) -> HashOutcome {
        digest(of: entry, sampleBytes: nil)
    }

    /// sampleBytes == nil 时读取整份文件。任何失败都返回 .failure，由调用方计入
    /// unreadablePaths —— 宁可漏报，不可误报。
    private func digest(of entry: FileEntry, sampleBytes: Int?) -> HashOutcome {
        guard let handle = try? FileHandle(forReadingFrom: entry.path) else { return .failure }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            if let sampleBytes, Int(entry.size) > sampleBytes * 2 {
                guard let head = try handle.read(upToCount: sampleBytes), !head.isEmpty else { return .failure }
                hasher.update(data: head)
                try handle.seek(toOffset: entry.size - UInt64(sampleBytes))
                guard let tail = try handle.read(upToCount: sampleBytes), !tail.isEmpty else { return .failure }
                hasher.update(data: tail)
            } else {
                var remaining = Int(entry.size)
                while remaining > 0 {
                    guard let chunk = try handle.read(upToCount: min(readChunkSize, remaining)),
                          !chunk.isEmpty else { return .failure }
                    hasher.update(data: chunk)
                    remaining -= chunk.count
                }
            }
        } catch {
            return .failure
        }
        return .success(hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
