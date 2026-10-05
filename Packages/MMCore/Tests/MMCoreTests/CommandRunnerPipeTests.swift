import XCTest
@testable import MMCore

/// `CommandRunner` 的管道纪律：**读和等分占两条队列**。
///
/// 这一族测试钉的不是"解析对不对"，是"大输出能不能整批拿回来"。`Pipe` 的内核缓冲
/// 只有 64 KB，先 `waitUntilExit()` 再 `readDataToEndOfFile()` 的写法一旦遇到超过
/// 缓冲的输出就自己卡死：子进程卡在 `write()`，父进程卡在 `wait()`。
/// 这个形状错不错取决于本机那条命令当时输出多少字节（P11 实测过一次，判据在
/// `docs/analysis/hook-ledger.md` §5），所以这里用一条**必定超过缓冲**的命令来测，
/// 而不是靠开发机上恰好没发作。
///
/// 否证：把 `CommandRunner.run` 改回"退出后才读"，下面第 1、2 条会在 10 秒后
/// 抛 `.timedOut` 而红——不会静默跳过，因为每条都显式传了 timeout。
final class CommandRunnerPipeTests: XCTestCase {

    /// 512 KB，是 64 KB 缓冲的 8 倍：无论内核缓冲按什么口径算都必定溢出。
    private let bigByteCount = 524_288

    func testStdoutBiggerThanPipeBufferIsReadInFull() throws {
        let t0 = CFAbsoluteTimeGetCurrent()
        let output = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes A | head -c \(bigByteCount)"],
            timeout: 10
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - t0

        XCTAssertEqual(output.status, 0, "sh 退出码 \(output.status)，stderr：\(output.stderrTrimmed)")
        XCTAssertEqual(output.stdout.count, bigByteCount,
                       "stdout 只拿回 \(output.stdout.count) 字节（应为 \(bigByteCount)）——"
                     + "读与等若在同一条队列上，超过 64 KB 的部分永远出不来")
        // 超时保护会把死锁伪装成"命令太慢"，所以耗时也要钉：正常应是百毫秒级。
        XCTAssertLessThan(elapsed, 5, "跑了 \(String(format: "%.2f", elapsed))s，接近超时——像是被管道卡住后又杀的")
    }

    /// stderr 那一侧同样不能漏：`launchctl` 之类的命令出错时报的是 stderr，
    /// 如果只在 stdout 上做了并发读，stderr 写满 64 KB 一样卡死。
    /// `1>&2` 把 head 的输出整股改道到 stderr，stdout 保持为空。
    func testStderrBiggerThanPipeBufferIsReadInFull() throws {
        let output = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes B | head -c 300000 1>&2"],
            timeout: 10
        )
        XCTAssertEqual(output.status, 0, "sh 退出码 \(output.status)")
        XCTAssertEqual(output.stdout.count, 0, "stdout 不该有内容")
        XCTAssertEqual(output.stderr.count, 300_000,
                       "stderr 只拿回 \(output.stderr.count) 字节（应为 300000）")
    }

    func testTimeoutTerminatesAndReports() {
        let t0 = CFAbsoluteTimeGetCurrent()
        XCTAssertThrowsError(try CommandRunner.run(
            executable: "/bin/sleep",
            arguments: ["30"],
            timeout: 0.2
        )) { error in
            XCTAssertEqual(error as? CommandRunner.Failure, .timedOut(0.2))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        XCTAssertLessThan(elapsed, 3,
                          "\(String(format: "%.2f", elapsed))s 才返回——超时之后没收干净，子进程还挂着")
    }

    func testNonZeroExitKeepsStderrText() throws {
        let output = try CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo boom >&2; exit 3"],
            timeout: 5
        )
        XCTAssertEqual(output.status, 3)
        XCTAssertEqual(output.stderrTrimmed, "boom")
    }

    func testMissingExecutableIsNotSilentlyEmpty() {
        XCTAssertThrowsError(try CommandRunner.run(
            executable: "/usr/bin/mm-definitely-not-here",
            arguments: []
        )) { error in
            guard case .notExecutable(let path)? = error as? CommandRunner.Failure else {
                return XCTFail("应报 .notExecutable，实际 \(error)")
            }
            XCTAssertEqual(path, "/usr/bin/mm-definitely-not-here")
        }
    }
}
