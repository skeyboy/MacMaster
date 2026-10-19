import Foundation
import AppKit
import Darwin

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
            // 一条都不删：「最近操作」是台账，不是待办清单。落点已经读不到的那条照样列出来，
            // 由界面按 `UndoTier` 说明它为什么没有撤回按钮——是垃圾倒了、还是盘被取走了、
            // 还是这条记录本来就没留下卷身份。
            trashHistory = store.load()
        }
    }

    /// 真会动盘的那一步留成可注入，两个理由都在测试那一侧：
    /// ① 单测不能把东西真送进用户废纸篓——本机 `~/.Trash` 读不到，落点回不来，现场清不掉；
    /// ② "调用没抛错而项还在原地"这一档在真机上造不出来，而那正是复验要防的一档。
    /// 返回值 = 废纸篓里的落点；永久删除没有落点。
    var trashStep: (String) throws -> String? = FileTrashService.moveToFinderTrash
    var eraseStep: (String) throws -> Void = FileTrashService.eraseFromDisk
    /// 落点卷身份。跟 `trashStep` 一样留成可注入：单测里落点是临时目录冒充的，
    /// 而那一句要钉的是"身份必须在删除那一刻取"，不是"这台机器上有几块卷"。
    var volumeUUIDStep: (String) -> String? = VolumeIdentities.volumeUUID(ofPath:)

    private static func moveToFinderTrash(atPath path: String) throws -> String? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resultingURL)
        return resultingURL?.path
    }

    private static func eraseFromDisk(atPath path: String) throws {
        try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    /// 复验的读法：移走前后各看一眼原路径，把"调用没报错"翻译成"这一项到底走了没有"。
    /// **用 `lstat` 不用 `fileExists`**：悬空的符号链接与断掉的别名在 `fileExists` 那里读成
    /// "不存在"，而那一项在盘上还实实在在占着一个目录项——复验要防的正是这一类"看着没了"。
    enum Aftermath: Equatable {
        /// 原路径上查不到东西了（`ENOENT`）：删除成立。
        case gone
        /// 原地站着同一个目录项（同一对 `(st_dev, st_ino)`）：假成功，报失败。
        case sameEntry
        /// 原地换成了另一个目录项：老那条确实走了，只是这个名字被别的东西占了
        /// （跑着的应用立刻把自己的缓存文件写回来就是这一档）。这不是一次失败的删除。
        case replacedEntry
        /// 核对不了（`EACCES` 一类）：既不能说还在，也不能说走了。
        case unverifiable
    }

    private static func entryIdentity(of path: String) -> (dev: UInt64, ino: UInt64)? {
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { return nil }
        return (UInt64(truncatingIfNeeded: info.st_dev), UInt64(truncatingIfNeeded: info.st_ino))
    }

    /// 事前那一眼没给到身份（事前就 `lstat` 失败）时按"还是那一条"处理：
    /// 宁可多报一条可疑，也不把"读不到"说成"换了东西"。
    /// `unverifiable` 与 `replacedEntry` 都由调用方按成功走——把 API 报的成功改成失败
    /// 是另一种谎，用户会对着一个已经进废纸篓的条目再按一次删除。
    static func aftermath(atPath path: String, movedFrom identity: (dev: UInt64, ino: UInt64)?) -> Aftermath {
        guard let now = entryIdentity(of: path) else { return errno == ENOENT ? .gone : .unverifiable }
        guard let identity else { return .sameEntry }
        return (now.dev, now.ino) == (identity.dev, identity.ino) ? .sameEntry : .replacedEntry
    }

    /// `allowedRoots` 是给"职责范围明确"的入口用的正向闸（见 `DeletionGuard.isInside`）：
    /// 路径必须严格落在其中之一内，否则按 `OUT_OF_SCOPE` 逐条上报。
    /// nil = 不启用，行为与只有黑名单时完全一致 —— 清理页与磁盘页的可选范围本来就跨整盘，
    /// 硬套一个根清单只会把它们自己的功能挡掉。
    public func moveToTrash(paths: [String], allowedRoots: [String]? = nil) async -> TrashResult {
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
            if let allowedRoots, let rejection = DeletionGuard.allowedRootRejection(for: path, roots: allowedRoots) {
                failures.append(TrashFailure(path: rejection.path, message: rejection.reason, code: "OUT_OF_SCOPE"))
                continue
            }
            let fileURL = URL(fileURLWithPath: path)
            // 移走之后再想统计就没机会了：原来那条路径会直接消失。
            let size = Self.allocatedBytes(of: fileURL)
            let identity = Self.entryIdentity(of: path)
            do {
                let trashPath = try trashStep(path)
                // 没抛错不等于移走了：还站着同一条就不算成功，并且**不**留撤回凭据
                // ——台账里那条"从哪来、到哪去"这时候是假的，撤回按钮会指向一个原地未动的条目。
                if Self.aftermath(atPath: path, movedFrom: identity) == .sameEntry {
                    failures.append(TrashFailure(
                        path: path, message: "移入废纸篓后该项仍在原地", code: "STILL_PRESENT"
                    ))
                    continue
                }
                movedFiles.append(TrashRecord(originalPath: path, trashPath: trashPath, size: size,
                                              trashVolumeUUID: trashPath.flatMap(volumeUUIDStep)))
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
    public func permanentlyDelete(paths: [String], allowedRoots: [String]? = nil) async -> PermanentDeleteResult {
        var deleted: [PermanentDeletion] = []
        var failures: [TrashFailure] = []

        for path in paths {
            if let rejection = DeletionGuard.rejection(for: path) {
                failures.append(TrashFailure(path: rejection.path, message: rejection.reason, code: "PROTECTED"))
                continue
            }
            if let allowedRoots, let rejection = DeletionGuard.allowedRootRejection(for: path, roots: allowedRoots) {
                failures.append(TrashFailure(path: rejection.path, message: rejection.reason, code: "OUT_OF_SCOPE"))
                continue
            }
            // 删之前量一次：删完之后原路径只剩 0，"释放了多少"就变成编的。
            let size = Self.allocatedBytes(of: URL(fileURLWithPath: path))
            let identity = Self.entryIdentity(of: path)
            do {
                try eraseStep(path)
                // 同一条复验。永久删除这一侧更贵：没有废纸篓兜底，也没有撤回按钮。
                if Self.aftermath(atPath: path, movedFrom: identity) == .sameEntry {
                    failures.append(TrashFailure(
                        path: path, message: "永久删除后该项仍在原地", code: "STILL_PRESENT"
                    ))
                    continue
                }
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
    /// 落点（`trashPath`）所在那块卷的 UUID，同样是**删除那一刻**取的。
    /// 为什么不等到要用的时候再问：本体在第二块卷上时落点就在那块卷的 `.Trashes` 里，
    /// 盘一拔，路径读不到、`resourceValues` 直接抛错，那时候已经问不出它是哪块卷了
    /// （P53 实拍 + P55 两档探针，读数在 `docs/verification/p55-undo-badge-criterion/`）。
    /// `nil` = 这条记录是新增字段之前落盘的，或者是当时就没取到身份——界面据此只说"撤不回来"，
    /// 不替用户猜成因。
    public var trashVolumeUUID: String?

    public init(originalPath: String, trashPath: String? = nil, size: UInt64 = 0,
                trashVolumeUUID: String? = nil) {
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.size = size
        self.trashVolumeUUID = trashVolumeUUID
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

    /// 记录还在，但废纸篓里的那个文件已经不在了。这不是失败，是事实：撤回按钮该消失，
    /// 而不是等用户按下去才拿到一个错误。
    /// **这一句只回答"能不能撤"，不回答"为什么不能"**——后者有三种成因（倒过垃圾、
    /// 落点所在那块卷被取走、老记录读不到身份），措辞一律走 `UndoTier`，别在这里指认成因。
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
