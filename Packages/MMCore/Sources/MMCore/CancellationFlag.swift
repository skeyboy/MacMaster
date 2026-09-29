import Foundation

/// 跨线程取消标志。扫描循环在后台 actor 上跑，取消状态必须能被主线程写、
/// 后台线程读；用 @Published 会每帧回主线程，用普通 var 又是数据竞争。
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    public func reset() {
        lock.lock(); cancelled = false; lock.unlock()
    }
}
