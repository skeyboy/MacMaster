import Foundation
import AppKit

@MainActor
public final class FileTrashService: ObservableObject {
    public static let shared = FileTrashService()

    @Published public private(set) var trashHistory: [TrashOperation] = []

    /// 落盘位置。nil 表示这台机器上拿不到 Application Support，历史只在内存里。
    private let store: TrashHistoryStore?

    /// 内存与磁盘共用同一个上限，避免出现"磁盘上还有、界面上没有"的两套真相。
    static let historyLimit = 20

    private convenience init() {
        self.init(store: TrashHistoryStore.default())
    }

    /// 注入 store 才能单测：默认那条路径是真实的 `~/Library/Application Support`。
    init(store: TrashHistoryStore?) {
        self.store = store
        if let store {
            // 一条都不删：「最近操作」是台账，不是待办清单。废纸篓已经被倒空的
            // 那条照样列出来，由界面用"废纸篓已清空"说明它为什么没有撤回按钮。
            trashHistory = store.load()
        }
    }

    public func moveToTrash(paths: [String]) async -> TrashResult {
        var movedFiles: [TrashRecord] = []
        var failures: [TrashFailure] = []

        for path in paths {
            let fileURL = URL(fileURLWithPath: path)
            // 移走之后再想统计就没机会了：原来那条路径会直接消失。
            let size = Self.allocatedBytes(of: fileURL)
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &resultingURL)
                let trashPath = resultingURL?.path
                movedFiles.append(TrashRecord(originalPath: path, trashPath: trashPath, size: size))
            } catch {
                failures.append(TrashFailure(path: path, error: error))
            }
        }

        let operation = TrashOperation(
            id: UUID(),
            timestamp: Date(),
            files: movedFiles,
            failures: failures
        )
        record(.inserted(operation))

        return TrashResult(operation: operation)
    }

    public func undoLastOperation() async -> UndoResult {
        guard let lastOp = trashHistory.first else {
            return UndoResult(restoredCount: 0, failures: [
                TrashFailure(path: "—", message: "没有可撤回的操作")
            ])
        }
        return await undo(operationID: lastOp.id)
    }

    public func undo(operationID: UUID) async -> UndoResult {
        guard let opIndex = trashHistory.firstIndex(where: { $0.id == operationID }) else {
            return UndoResult(restoredCount: 0, failures: [
                TrashFailure(path: "—", message: "操作记录不存在")
            ])
        }

        let operation = trashHistory[opIndex]
        var restoredCount = 0
        var failures: [TrashFailure] = []

        for record in operation.files {
            if let trashPath = record.trashPath {
                let trashURL = URL(fileURLWithPath: trashPath)
                let originalURL = URL(fileURLWithPath: record.originalPath)
                let originalDir = originalURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: originalDir, withIntermediateDirectories: true)
                do {
                    try FileManager.default.moveItem(at: trashURL, to: originalURL)
                    restoredCount += 1
                } catch {
                    failures.append(TrashFailure(path: record.originalPath, error: error))
                }
            } else {
                failures.append(TrashFailure(path: record.originalPath, message: "无废纸篓路径，无法恢复"))
            }
        }

        record(.replaced(index: opIndex, with: operation.markedUndone()))
        return UndoResult(restoredCount: restoredCount, failures: failures)
    }

    /// 历史与磁盘只通过这一个出口改动，两边就不会各说各话。
    private func record(_ change: Change) {
        switch change {
        case .inserted(let operation):
            trashHistory.insert(operation, at: 0)
            if trashHistory.count > Self.historyLimit {
                trashHistory.removeLast(trashHistory.count - Self.historyLimit)
            }
        case .replaced(let index, let operation):
            guard trashHistory.indices.contains(index) else { return }
            trashHistory[index] = operation
        }
        store?.save(trashHistory)
    }

    private enum Change {
        case inserted(TrashOperation)
        case replaced(index: Int, with: TrashOperation)
    }

    /// 实际占用的块数，不是标称大小：APFS 压缩和稀疏文件的标称大小会把"释放了多少"夸大。
    private static func allocatedBytes(of url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey,
        ]) else { return 0 }
        if values.isDirectory == true {
            return SystemSampler.directoryBytes(url.path) ?? 0
        }
        return UInt64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }
}

public struct TrashRecord: Codable {
    public let originalPath: String
    public var trashPath: String?
    /// 移走**当时**量到的占用字节数。事后再读原路径只会得到 0，
    /// 那样"释放了多少"就变成了编数字。
    public let size: UInt64

    public init(originalPath: String, trashPath: String? = nil, size: UInt64 = 0) {
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.size = size
    }
}

public struct TrashOperation: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let files: [TrashRecord]
    public let failures: [TrashFailure]
    public var isUndone: Bool

    public var totalSize: UInt64 {
        files.reduce(0) { size, record in size + record.size }
    }

    public var fileCount: Int { files.count }

    /// 记录还在，但废纸篓里的那个文件已经不在了（用户倒过垃圾，或自己移回去过）。
    /// 这不是失败，是事实：撤回按钮该消失，而不是等用户按下去才拿到一个错误。
    public var canUndo: Bool {
        guard isUndone == false else { return false }
        return files.contains { file in
            guard let trashPath = file.trashPath else { return false }
            return FileManager.default.fileExists(atPath: trashPath)
        }
    }

    init(id: UUID, timestamp: Date, files: [TrashRecord], failures: [TrashFailure]) {
        self.id = id
        self.timestamp = timestamp
        self.files = files
        self.failures = failures
        self.isUndone = false
    }

    func markedUndone() -> TrashOperation {
        var copy = self
        copy.isUndone = true
        return copy
    }
}

/// 删除失败必须逐条上报。旧实现把错误拼成一句字符串，界面就只能整段塞进
/// 一个 Text 里；路径与错误码分开才能做成设计稿那种"路径 + EPERM"的清单。
public struct TrashFailure: Hashable, Identifiable, Sendable, Codable {
    public var id: String { path }
    public let path: String
    public let message: String
    /// POSIX 错误码文本（EPERM / EACCES…），原文保留便于用户搜索。
    public let code: String?

    public init(path: String, message: String, code: String? = nil) {
        self.path = path
        self.message = message
        self.code = code
    }

    init(path: String, error: Error) {
        let nsError = error as NSError
        var code: String?
        var chain: NSError? = nsError
        while let current = chain {
            if current.domain == NSPOSIXErrorDomain {
                code = String(cString: strerror(Int32(current.code)))
                break
            }
            chain = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        self.init(
            path: path,
            message: nsError.localizedDescription,
            code: code ?? "Cocoa \(nsError.code)"
        )
    }
}

public struct TrashResult {
    public let operation: TrashOperation
    public var successCount: Int { operation.files.count }
    public var errorCount: Int { operation.failures.count }
    public var totalSize: UInt64 { operation.totalSize }
}

public struct UndoResult {
    public let restoredCount: Int
    public let failures: [TrashFailure]
    public var success: Bool { failures.isEmpty }

    init(restoredCount: Int, failures: [TrashFailure]) {
        self.restoredCount = restoredCount
        self.failures = failures
    }
}
