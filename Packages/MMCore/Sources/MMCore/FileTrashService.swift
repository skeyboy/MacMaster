import Foundation
import AppKit

@MainActor
public final class FileTrashService: ObservableObject {
    public static let shared = FileTrashService()

    @Published public private(set) var trashHistory: [TrashOperation] = []

    private init() {}

    public func moveToTrash(paths: [String]) async -> TrashResult {
        var movedFiles: [TrashRecord] = []
        var errors: [String] = []

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
                errors.append("\(path): \(error.localizedDescription)")
            }
        }

        let operation = TrashOperation(
            id: UUID(),
            timestamp: Date(),
            files: movedFiles,
            errors: errors
        )
        trashHistory.insert(operation, at: 0)
        if trashHistory.count > 20 {
            trashHistory.removeLast(trashHistory.count - 20)
        }

        return TrashResult(operation: operation)
    }

    public func undoLastOperation() async -> UndoResult {
        guard let lastOp = trashHistory.first else {
            return UndoResult(restoredCount: 0, errors: ["没有可撤回的操作"])
        }
        return await undo(operationID: lastOp.id)
    }

    public func undo(operationID: UUID) async -> UndoResult {
        guard let opIndex = trashHistory.firstIndex(where: { $0.id == operationID }) else {
            return UndoResult(restoredCount: 0, errors: ["操作记录不存在"])
        }

        let operation = trashHistory[opIndex]
        var restoredCount = 0
        var errors: [String] = []

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
                    errors.append("\(record.originalPath): \(error.localizedDescription)")
                }
            } else {
                errors.append("\(record.originalPath): 无废纸篓路径，无法恢复")
            }
        }

        trashHistory[opIndex] = operation.markedUndone()
        return UndoResult(restoredCount: restoredCount, errors: errors)
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

public struct TrashOperation: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let files: [TrashRecord]
    public let errors: [String]
    public var isUndone: Bool

    public var totalSize: UInt64 {
        files.reduce(0) { size, record in size + record.size }
    }

    public var fileCount: Int { files.count }

    init(id: UUID, timestamp: Date, files: [TrashRecord], errors: [String]) {
        self.id = id
        self.timestamp = timestamp
        self.files = files
        self.errors = errors
        self.isUndone = false
    }

    func markedUndone() -> TrashOperation {
        var copy = self
        copy.isUndone = true
        return copy
    }
}

public struct TrashResult {
    public let operation: TrashOperation
    public var successCount: Int { operation.files.count }
    public var errorCount: Int { operation.errors.count }
    public var totalSize: UInt64 { operation.totalSize }
}

public struct UndoResult {
    public let restoredCount: Int
    public let errors: [String]
    public var success: Bool { errors.isEmpty }
}
