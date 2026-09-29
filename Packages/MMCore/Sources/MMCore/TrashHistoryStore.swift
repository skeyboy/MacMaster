import Foundation

/// 删除历史的落盘。
///
/// 单独一个类型，是为了能把 URL 注入到临时目录：`FileTrashService` 是 `@MainActor`
/// 单例，单测里既拿不到第二个实例，也绝不能让它写真实的 Application Support。
///
/// 为什么必须落盘：设计稿写的是"撤回在「最近操作」里长期可用，15 秒过期不等于
/// 不可撤回"。只活在内存里的历史，重启之后就变成一句兑现不了的文案。
public struct TrashHistoryStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/<目录名>/trash-history.json`。
    public static func `default`(subdirectory: String = "MacMaster") -> TrashHistoryStore? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return TrashHistoryStore(url: base.appendingPathComponent(subdirectory)
                                        .appendingPathComponent("trash-history.json"))
    }

    /// 读不出来就当没有：损坏的历史记录不该把整个清理功能锁死。
    /// 但不能静默覆盖——原文件改名留档，用户随时能自己看一眼。
    public func load() -> [TrashOperation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            let operations = try JSONDecoder().decode([StoredOperation].self, from: data)
            return operations.map(\.operation)
        } catch {
            discardCorruptFile()
            return []
        }
    }

    public func save(_ operations: [TrashOperation]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(operations.map(StoredOperation.init))
            // 原子写：中途掉电/被杀不能留下半个 JSON，否则下次启动直接是"没有历史"。
            try data.write(to: url, options: [.atomic])
        } catch {
            // 写失败只影响"重启后还能不能撤回"，不该让已经完成的删除变成错误。
            FileHandle.standardError.write("删除历史未能落盘：\((error as NSError).localizedDescription)\n"
                                            .data(using: .utf8)!)
        }
    }

    private func discardCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: target)
    }
}

/// `TrashOperation.isUndone` 是可变的，而 `files` / `failures` 里存的
/// 是"当时"的事实（路径、量到的字节数、当时的错误码），所以整条都要原样存下来。
/// 包一层是为了给将来的格式迁移留一个显式落点，不把 Codable 合进公开类型里。
private struct StoredOperation: Codable {
    let version: Int
    let operation: TrashOperation

    init(_ operation: TrashOperation) {
        version = 1
        self.operation = operation
    }
}
