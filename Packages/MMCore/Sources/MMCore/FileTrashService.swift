import Foundation
import AppKit

@MainActor
public final class FileTrashService: ObservableObject {
    public static let shared = FileTrashService()

    @Published public private(set) var trashHistory: [TrashOperation] = []

    /// 落盘位置。nil 表示这台机器上拿不到 Application Support，历史只在内存里。
    private let store: TrashHistoryStore?

    /// 内存与磁盘共用同一个上限，避免出现"磁盘上还有、界面上没有"的两套真相。
    /// public 是因为设置页要把"最多 N 条"这个承诺原样报给用户，不能在界面上抄一份数字。
    public static let historyLimit = 20

    /// 台账文件在哪。设置页要如实告诉用户这份含绝对路径的文件存在哪里、并能直接打开它，
    /// 所以路径由这里给，不让视图自己拼一遍——拼错一次就说明错了用户的数据在哪。
    public var historyFileURL: URL? { store?.url }

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
            // 闸口在这里，不在各个扫描器里：上游误判、调用方拼错、以后新增的入口，
            // 都从这一个出口走。被挡下要当成"失败"逐条上报，不能静默跳过 ——
            // 用户看到"移走 3 项"而实际挡了 1 项，比看到一条拒绝更糟。
            if let rejection = DeletionGuard.rejection(for: path) {
                failures.append(TrashFailure(path: rejection.path, message: rejection.reason, code: "PROTECTED"))
                continue
            }
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

    /// 永久删除：字节直接从盘上走，不经过废纸篓，**没有任何撤回**。
    ///
    /// 和 `moveToTrash` 放在同一个类里是刻意的：闸门只有一道，多一个出口就多一次
    /// "忘了接"的机会，而这条路径出错的代价是不可恢复。同样逐条上报拒绝，不静默跳过。
    ///
    /// 两点必须说清的边界：
    /// - **不写台账**。`TrashOperation` 存的是"从哪来、到哪去"，为的是放回原处；
    ///   这里没有"到哪去"，写进「最近操作」只会多出一个点不动的撤回按钮。
    /// - **目录连同整棵子树一起消失**。`removeItem` 逐层递归，中途失败会留下半个目录，
    ///   失败的那条照样上报 —— 所以确认面板必须点名是哪几项，不能只给一个合计字节。
    public func permanentlyDelete(paths: [String]) async -> PermanentDeleteResult {
        var deleted: [PermanentDeletion] = []
        var failures: [TrashFailure] = []

        for path in paths {
            if let rejection = DeletionGuard.rejection(for: path) {
                failures.append(TrashFailure(path: rejection.path, message: rejection.reason, code: "PROTECTED"))
                continue
            }
            // 删之前量一次：删完之后原路径只剩 0，"释放了多少"就变成编的。
            let size = Self.allocatedBytes(of: URL(fileURLWithPath: path))
            do {
                try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
                deleted.append(PermanentDeletion(path: path, size: size))
            } catch {
                failures.append(TrashFailure(path: path, error: error))
            }
        }
        return PermanentDeleteResult(deleted: deleted, failures: failures)
    }

    public func undoLastOperation() async -> UndoResult {
        guard let lastOp = trashHistory.first(where: \.canUndo) else {
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
        guard operation.canUndo else {
            return UndoResult(restoredCount: 0, failures: [
                TrashFailure(path: "—", message: "没有仍在废纸篓中、可以恢复的文件")
            ])
        }
        var restoredCount = 0
        var failures: [TrashFailure] = []

        var restoredIndices = Set<Int>()
        for (index, record) in operation.files.enumerated() {
            if let trashPath = record.trashPath {
                let trashURL = URL(fileURLWithPath: trashPath)
                let originalURL = URL(fileURLWithPath: record.originalPath)
                let originalDir = originalURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: originalDir, withIntermediateDirectories: true)
                do {
                    try FileManager.default.moveItem(at: trashURL, to: originalURL)
                    restoredCount += 1
                    restoredIndices.insert(index)
                } catch {
                    failures.append(TrashFailure(path: record.originalPath, error: error))
                }
            }
        }

        record(.replaced(index: opIndex, with: operation.recordingRestored(restoredIndices)))
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
        case .cleared:
            trashHistory = []
        }
        store?.save(trashHistory)
    }

    private enum Change {
        case inserted(TrashOperation)
        case replaced(index: Int, with: TrashOperation)
        case cleared
    }

    /// 清空删除台账。**只删记录，不碰废纸篓里的文件**——那些东西该由用户在访达里决定。
    /// 代价是撤回入口一起消失：没有记录就不知道该把哪个文件放回哪儿。
    public func clearHistory() {
        record(.cleared)
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
    public private(set) var files: [TrashRecord]
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

    func recordingRestored(_ indices: Set<Int>) -> TrashOperation {
        var copy = self
        for index in indices { copy.files[index].trashPath = nil }
        copy.isUndone = copy.files.allSatisfy { $0.trashPath == nil }
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

/// 一条永久删除的凭据：路径 + **删除当时**量到的占用字节。没有"落到哪儿"这一项，
/// 因为无处可回。
public struct PermanentDeletion: Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let size: UInt64
}

public struct PermanentDeleteResult {
    public let deleted: [PermanentDeletion]
    public let failures: [TrashFailure]
    public var successCount: Int { deleted.count }
    public var errorCount: Int { failures.count }
    public var totalSize: UInt64 { deleted.reduce(0) { $0 + $1.size } }
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
