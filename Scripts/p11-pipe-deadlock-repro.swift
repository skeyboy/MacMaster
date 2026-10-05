// P11 取证：`ActivityScanner.scanUnifiedLog()` 那套"先等子进程退出、再读管道"的写法
// 会不会自己把自己卡死。三种读法跑同一条 `log show`，各自打印耗时、字节数与可用事件条数：
// ① 落地时的写法 ② 修死锁的中间态 ③ 现在仓库里跑的实装。
//
//   swift Scripts/p11-pipe-deadlock-repro.swift
//
// 为什么要有这个文件：界面上「系统日志事件」一行都没出现过，两档签名（ad-hoc / ad-hoc+runtime）
// 同一副样子。只看照片分不清"这台机器没有事件"和"我们没把子进程的输出读出来"，
// 而这两种情况在界面上是同一句话。这个复现把两者分开——它不启动 MacMaster，
// 只用同样的 API 形状跑同一条命令。
// 它同时是这一条的**回归哨兵**：③ 那行的耗时如果长期贴着 8 秒，说明预算该重估了。
import Foundation

let arguments = ["show", "--last", "5m", "--predicate",
                 "eventMessage contains \"login\" OR eventMessage contains \"auth\""]

func makeProcess() -> (Process, Pipe) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    proc.arguments = arguments
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    return (proc, pipe)
}

// 每一支各计自己的耗时。**不能用一个全局起点**：第一版就是那么写的，
// 于是 ② 打印的 "8.90s" 其实是"从脚本开始到现在"，把 ① 那 8 秒的死锁算进了自己的账，
// 读起来像"这条命令要 8.9 秒、超了应用侧 8 秒的预算"——而它自己只跑了 0.9 秒。
func elapsed(from t0: CFAbsoluteTime) -> String { String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - t0) }

// ① 现状：waitUntilExit() 先返回，才去 readDataToEndOfFile()
func currentShape(timeout: TimeInterval) {
    let t0 = CFAbsoluteTimeGetCurrent()
    let (proc, pipe) = makeProcess()
    do { try proc.run() } catch { print("① 现状：启动失败 \(error)"); return }
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        proc.waitUntilExit()
        finished.signal()
    }
    if finished.wait(timeout: .now() + timeout) == .timedOut {
        proc.terminate()
        print("① 现状：\(elapsed(from: t0))（\(timeout)s 内没退出）→ terminate()，输出丢弃，读到 \(pipe.fileHandleForReading.readDataToEndOfFile().count) 字节")
        return
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    print("① 现状：\(elapsed(from: t0)) 退出，读到 \(data.count) 字节")
}

// ② 修法（中间态）：一启动就开始读，但**一超时就整批丢掉**
func fixedShape(timeout: TimeInterval) {
    let t0 = CFAbsoluteTimeGetCurrent()
    let (proc, pipe) = makeProcess()
    do { try proc.run() } catch { print("② 修法：启动失败 \(error)"); return }
    let readDone = DispatchSemaphore(value: 0)
    var count = 0
    DispatchQueue.global(qos: .utility).async {
        count = pipe.fileHandleForReading.readDataToEndOfFile().count
        readDone.signal()
    }
    let exitDone = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        proc.waitUntilExit()
        exitDone.signal()
    }
    if exitDone.wait(timeout: .now() + timeout) == .timedOut || readDone.wait(timeout: .now() + timeout) == .timedOut {
        proc.terminate()
        print("② 修法：\(elapsed(from: t0))（\(timeout)s 超时）→ 输出丢弃（界面上一行事件都不会出现）")
        return
    }
    print("② 修法：\(elapsed(from: t0)) 读完 \(count) 字节")
}

// ③ 实装：边读边攒，超时只杀子进程、**已读到的部分照常解析**——仓库里跑的是这一支。
// 为什么要走到第三支：② 修好了死锁，但它一超时就把已经拿到手的整批丢掉，
// 而这条命令**在带沙盒的取证环境里整条挂住过**（`sandbox_extension_issue_file_to_process`，
// 见 `docs/analysis/fidelity-guardian.md` §6.6.3）。挂住的那一刻，② 交出空卡片、③ 交出
// 截止那一刻读到的真事件——后者和"这台机器没有事件"仍是两句话，前者与它长得一样。
// 现测（本机、无沙盒、5 轮）：②/③ 都在 0.9 秒内正常结束，**没有**触发超时。
final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    func append(_ chunk: Data) { lock.lock(); storage.append(chunk); lock.unlock() }
    func snapshot() -> Data { lock.lock(); defer { lock.unlock() }; return storage }
}

func shippedShape(timeout: TimeInterval) {
    let t0 = CFAbsoluteTimeGetCurrent()
    let (proc, pipe) = makeProcess()
    do { try proc.run() } catch { print("③ 实装：启动失败 \(error)"); return }
    let box = Box()
    let handle = pipe.fileHandleForReading
    DispatchQueue.global(qos: .utility).async {
        while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
            box.append(chunk)
        }
    }
    let exitDone = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        proc.waitUntilExit()
        exitDone.signal()
    }
    let timedOut = exitDone.wait(timeout: .now() + timeout) == .timedOut
    if timedOut { proc.terminate() }
    let data = box.snapshot()
    let text = String(data: data, encoding: .utf8) ?? ""
    let events = text.split(separator: "\n").filter { line in
        line.count >= 5 && Array(line.prefix(4)).allSatisfy(\.isNumber) && line[line.index(line.startIndex, offsetBy: 4)] == "-"
    }.count
    print("③ 实装：\(elapsed(from: t0)) \(timedOut ? "（\(timeout)s 超时，已杀）" : "正常退出")，"
        + "攒到 \(data.count) 字节 / \(events) 条事件行可用")
}

currentShape(timeout: 8)
fixedShape(timeout: 8)
// ③ 可以连跑多轮：这一条命令的耗时和输出量都随本机这几分钟在写什么日志而变，
// 单跑一轮报出来的数不能当"预算够不够"的依据。`swift Scripts/p11-pipe-deadlock-repro.swift 5`
let repeatCount = max(1, Int(CommandLine.arguments.dropFirst().first ?? "") ?? 1)
for _ in 0..<repeatCount { shippedShape(timeout: 8) }
