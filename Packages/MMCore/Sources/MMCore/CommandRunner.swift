import Foundation

// MARK: - 子进程命令执行
//
// 全站唯一的"起一条系统命令、拿它的 stdout/stderr"的入口。放 MMCore 的理由与
// `SystemSampler` 一样：磁盘页要跑 `tmutil`、守护页要跑 `launchctl`，各抄一份的话，
// 抄错的那一份不一定在本机发作。
//
// 纪律：**读管道和等退出必须分占两条队列。** `Pipe` 的内核缓冲只有 64 KB，
// 子进程写满就卡在 `write()`，父进程若先 `waitUntilExit()` 就卡在 `wait()`，谁也不动。
// 所以"先等再读"的写法对不对，取决于**这台机器上这条命令当时输出多少字节**——
// 在开发机上它可以永远不出现。P11 实吃过一次：守护页显示"近 5 分钟没有活动事件"，
// 真实情况是一行都没读出来（判据见 `docs/analysis/hook-ledger.md` §5，
// 复现件 `Scripts/p11-pipe-deadlock-repro.swift` 的 ① 那支就是这一形状）。
//
// 现测余量（2026-10-05 本机同日多处现读）：`launchctl list` 18,541–19,540 字节
// ≈ 缓冲的三成（浮动本身就是要记的一条：单次量到的数不能抄进下一轮）；
// `tmutil listlocalsnapshots /` 21–22 字节。
// 这两个数是"离 64 KB 有多远"的量尺，不是安全证明——写这一族代码时要防的是它涨上去那天。

public enum CommandRunner {

    public struct Output: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String

        /// 只去掉首尾空白，不改内容——调用方要靠这个原文判断成败。
        public var stdoutTrimmed: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
        public var stderrTrimmed: String { stderr.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public enum Failure: Error, Hashable, Sendable {
        case notExecutable(String)
        case launchFailed(String)
        case timedOut(TimeInterval)
    }

    /// 跑一条命令取输出。
    ///
    /// `timeout` 传 nil = 不设时限：写侧（`launchctl disable`）用这一档，
    /// 宁可等也不能把"没等到回话"说成"没改成"。传时限则到点杀进程并抛 `.timedOut`，
    /// **已读到的部分不返回**——对"数几项"这类只读命令，半截输出会被解析成
    /// "这台机器就是少几项"，那比"没读到"更接近假话。
    public static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) throws -> Output {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw Failure.notExecutable(executable)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            throw Failure.launchFailed((error as NSError).localizedDescription)
        }

        let out = DataBox()
        let err = DataBox()
        let group = DispatchGroup()
        // 两条管道各占一条队列，在子进程运行期间读空；父进程这边只管等退出。
        readerQueue.async(group: group) { out.fill(from: outPipe.fileHandleForReading) }
        readerQueue.async(group: group) { err.fill(from: errPipe.fileHandleForReading) }

        if let timeout {
            let exited = DispatchSemaphore(value: 0)
            readerQueue.async {
                process.waitUntilExit()
                exited.signal()
            }
            if exited.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                // terminate 之后管道才会 EOF；给两条读队列一个收尾窗口，
                // 不让它们挂在后台无人认领。
                _ = group.wait(timeout: .now() + 2)
                throw Failure.timedOut(timeout)
            }
        }
        process.waitUntilExit()
        group.wait()

        return Output(
            status: process.terminationStatus,
            // 不解 UTF-8 就整体丢弃：命令输出里混进一个坏字节时，
            // `String(data:encoding:)` 返回 nil 会让我们交出"没有输出"。
            stdout: String(decoding: out.data, as: UTF8.self),
            stderr: String(decoding: err.data, as: UTF8.self)
        )
    }

    private static let readerQueue = DispatchQueue(
        label: "com.macmaster.commandrunner.readers",
        attributes: .concurrent
    )
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// 读到 EOF 为止。子进程退出（或被杀）后写端关闭，这里就返回。
    func fill(from handle: FileHandle) {
        let read = handle.readDataToEndOfFile()
        lock.lock()
        storage.append(read)
        lock.unlock()
    }
}
