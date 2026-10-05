//
//  LoginItemStore.swift — 登录项扫描与安全写入
//
//  写路径的三条硬规则（对应任务 B）：
//  1. 系统域（/Library/LaunchAgents、/Library/LaunchDaemons）直接拒绝写，
//     返回一条给 UI 展示的失败记录（含引导文案），不做任何磁盘触碰；
//  2. 用户域写 Disabled 键用 throwing API（PropertyListSerialization + Data.write），
//     任何一步失败都把错误原文（NSPOSIXErrorDomain 时附 strerror 文本与 errno）带回；
//  3. launchctl 不再 try? 吞掉：非零退出码与 stderr 原文都要上报。
//

import Foundation
import MMCore

// MARK: - 数据模型

/// 条目是以什么形态停用的。`renamedDisabled` = 文件被改名成 `<label>.disabled`：
/// launchd 只加载 `*.plist`，改名本身就是一种停用手段（第三方清理工具常见做法），
/// 但它绕过了 Disabled 键，界面上必须和"正常关着"区分开——恢复方式完全不同。
public enum LoginItemFileKind: String, Sendable, Equatable {
    case plist
    case renamedDisabled
}

public struct LoginItem: Identifiable, Equatable, Sendable {
    public let id: String        // = path
    public let name: String
    public let path: String
    public let domain: LaunchDomain
    public let enabled: Bool
    public let icon: String
    public let fileKind: LoginItemFileKind

    public init(name: String, path: String, domain: LaunchDomain, enabled: Bool, icon: String,
                fileKind: LoginItemFileKind = .plist) {
        self.id = path
        self.name = name
        self.path = path
        self.domain = domain
        self.enabled = enabled
        self.icon = icon
        self.fileKind = fileKind
    }

    /// Equatable 只比 id + enabled：扫描后同名项的开关状态变化要能被 diff 到。
    public static func == (lhs: LoginItem, rhs: LoginItem) -> Bool {
        lhs.id == rhs.id && lhs.enabled == rhs.enabled
    }

    public var isWritable: Bool { domain.isWritable }
}

public struct LoginItemScanReport: Sendable {
    public var items: [LoginItem]
    /// 读取失败目录的原文错误（"不允许静默失败"同样适用于读侧的降级说明）。
    public var readErrors: [String]

    public init(items: [LoginItem], readErrors: [String]) {
        self.items = items
        self.readErrors = readErrors
    }
}

// MARK: - 扫描

public enum LoginItemScanner {

    /// 扫描三个目录 + 旧版用户登录项 plist。目录/解析错误不吞：
    /// 收进 readErrors，UI 用副标题展示。
    public static func scan(home: String = NSHomeDirectory()) -> LoginItemScanReport {
        var items: [LoginItem] = []
        var readErrors: [String] = []
        let fm = FileManager.default

        let dirs: [(String, LaunchDomain)] = [
            ("\(home)/Library/LaunchAgents", .user),
            ("/Library/LaunchAgents", .system),
            ("/Library/LaunchDaemons", .system),
        ]

        for (dir, domain) in dirs {
            let files: [String]
            do {
                files = try fm.contentsOfDirectory(atPath: dir)
            } catch {
                // 目录不存在（ENOENT）是常态，不算错误；其余原因要说明。
                let nsError = error as NSError
                if !(nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)) {
                    readErrors.append("读取 \(dir) 失败：\(LoginItemStore.posixText(nsError))")
                }
                continue
            }
            // 已知坑：目录枚举逐项取，路径比较先归一化符号链接。
            for file in files where file.hasSuffix(".plist") || file.hasSuffix(".disabled") {
                let path = "\(dir)/\(file)"
                let isRenamedDisabled = file.hasSuffix(".disabled")
                do {
                    let dict = try readPlist(at: path)
                    let keySaysDisabled = dict["Disabled"] as? Bool ?? false
                    items.append(LoginItem(
                        name: dict["Label"] as? String ?? file,
                        path: path,
                        domain: domain,
                        // 改名停用一律算"停用"：launchd 根本不会加载它，
                        // 哪怕 plist 里的 Disabled 键还是 false。
                        enabled: isRenamedDisabled ? false : !keySaysDisabled,
                        icon: iconForDomain(domain),
                        fileKind: isRenamedDisabled ? .renamedDisabled : .plist
                    ))
                } catch {
                    readErrors.append("解析 \(path) 失败：\(error.localizedDescription)")
                }
            }
        }

        items.append(contentsOf: scanUserLoginItems(home: home))
        return LoginItemScanReport(items: items.sorted { $0.name < $1.name }, readErrors: readErrors)
    }

    private static func scanUserLoginItems(home: String) -> [LoginItem] {
        var items: [LoginItem] = []
        let prefsPath = "\(home)/Library/Preferences/loginitems.plist"
        guard let dict = try? readPlist(at: prefsPath),
              let autoItems = dict["AutoLaunchedApplicationDictionary"] as? [[String: Any]]
        else { return [] }
        for entry in autoItems {
            let name = entry["Name"] as? String ?? "Unknown"
            let path = entry["Path"] as? String ?? ""
            let enabled = entry["Enabled"] as? Bool ?? true
            items.append(LoginItem(name: name, path: path, domain: .userPreferences, enabled: enabled, icon: "app"))
        }
        return items
    }

    private static func readPlist(at path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw GuardianWriteError(path: path, message: "plist 根对象不是字典", code: nil)
        }
        return plist
    }

    private static func iconForDomain(_ domain: LaunchDomain) -> String {
        switch domain {
        case .user: "gear"
        case .system: "gearshape.2"
        case .userPreferences: "person"
        }
    }
}

// MARK: - 写入（仅用户域）

/// 写操作失败：message 是给用户的原文说明，code 是 POSIX 码文本（EACCES…）。
/// 直接复用 MMCore.TrashFailure 的形状，喂给 MMUI 的 MMFailurePanel。
public struct GuardianWriteError: Error, Sendable {
    public let path: String
    public let message: String
    public let code: String?

    public init(path: String, message: String, code: String?) {
        self.path = path
        self.message = message
        self.code = code
    }

    public var asFailure: TrashFailure {
        TrashFailure(path: path, message: message, code: code)
    }
}

public enum LoginItemStore {

    /// 切换登录项开关 = 写 Disabled 键（旧值取反）。
    /// launchctlRunner 可注入（单测不真动 launchd；生产用 .launchctl）。
    /// 返回 nil = 成功；返回 TrashFailure = 把错误原文交给 UI，绝不静默。
    public static func toggle(
        _ item: LoginItem,
        home: String = NSHomeDirectory(),
        launchctlRunner: @escaping @Sendable (String, String) -> String? = { command, path in
            LaunchctlRunner.disable(command: command, path: path)
        }
    ) -> TrashFailure? {
        // 1) 域判定：系统域一律拒绝，连读都不必读第二遍。
        guard item.isWritable else {
            return TrashFailure(
                path: item.path,
                message: "系统域 plist 只读：MacMaster 不写 /Library 下的 LaunchAgents/Daemons。请到「系统设置 › 登录项」调整。",
                code: "READ-ONLY"
            )
        }
        guard LaunchItemPolicy.isUserLaunchAgent(path: item.path, home: home) else {
            return TrashFailure(
                path: item.path,
                message: "路径不在用户 LaunchAgents 目录内，拒绝写入（疑似伪装前缀或符号链接逃逸）。",
                code: "POLICY"
            )
        }
        // 改名停用的条目不走"写 Disabled 键"这条路：它压根不是 .plist，
        // 写进去 launchd 也不会看，反而留下一个"以为开了其实没开"的假状态。
        guard item.fileKind == .plist else {
            return TrashFailure(
                path: item.path,
                message: "这个条目是靠把文件改名成 .disabled 停用的，launchd 只看 *.plist。"
                    + "恢复需要把文件名改回去（\(item.path) 去掉结尾的 .disabled），MacMaster 不代做改名。",
                code: "RENAME-MANAGED"
            )
        }

        // 2) 读 → 改 → 写，任何一步失败都转成可见失败。
        //    读写走 POSIX 裸 fd：Foundation 的 Data.write(.atomic) 会把 EACCES
        //    包成 Cocoa 513 丢掉 errno 原文，这里必须给用户"错误原文 + POSIX 码"。
        let url = URL(fileURLWithPath: item.path)
        let desiredDisabled = item.enabled // 开着 → 关掉写 Disabled=true；关着 → 打开写 false
        do {
            let data = try POSIXFileIO.read(url)
            guard var dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw GuardianWriteError(path: item.path, message: "plist 根对象不是字典，无法安全改写", code: nil)
            }
            dict["Disabled"] = desiredDisabled
            let out = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try POSIXFileIO.atomicWrite(out, to: url)
        } catch let error as GuardianWriteError {
            return error.asFailure
        } catch {
            return posixFailure(path: item.path, action: "写入 Disabled 键", error: error)
        }

        // 3) launchctl：写成功后才尝试；失败原文上报（plist 已改，状态提示"下次登录生效"）。
        let command = desiredDisabled ? "unload" : "load"
        if let stderr = launchctlRunner(command, item.path) {
            return TrashFailure(
                path: item.path,
                message: "plist 已更新为 Disabled=\(desiredDisabled)，但 launchctl \(command) 未生效：\(stderr)。变更将在下次登录生效。",
                code: "LAUNCHCTL"
            )
        }
        return nil
    }

    /// NSError → "原文说明 + POSIX 码文本"。strerror 入参是 Int32（Swift 坑）。
    static func posixFailure(path: String, action: String, error: Error) -> TrashFailure {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            let errno = Int32(nsError.code)
            let text = String(cString: strerror(errno))
            return TrashFailure(
                path: path,
                message: "\(action)失败：\(text)（errno \(nsError.code)），路径 \(path)",
                code: posixName(errno) ?? "errno \(nsError.code)"
            )
        }
        return TrashFailure(
            path: path,
            message: "\(action)失败：\(nsError.localizedDescription)",
            code: "Cocoa \(nsError.code)"
        )
    }

    static func posixText(_ nsError: NSError) -> String {
        if nsError.domain == NSPOSIXErrorDomain {
            let errno = Int32(nsError.code)
            return "\(String(cString: strerror(errno)))（errno \(nsError.code)）"
        }
        return nsError.localizedDescription
    }

    private static func posixName(_ code: Int32) -> String? {
        switch code {
        case EPERM: return "EPERM"
        case ENOENT: return "ENOENT"
        case EACCES: return "EACCES"
        case EISDIR: return "EISDIR"
        case ENOSPC: return "ENOSPC"
        case EROFS: return "EROFS"
        case ETXTBSY: return "ETXTBSY"
        default: return nil
        }
    }
}

// MARK: - POSIX 文件读写（errno 保真）

/// 裸 fd 读写：失败时 errno 就是第一手原因，不会被 Cocoa 错误码二次包装。
/// plist 都是小文件，顺序读干净即可；写采用 tmp + rename 的原子替换。
enum POSIXFileIO {

    static func read(_ url: URL) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else { throw posixNSError(action: "open(\(url.lastPathComponent))") }
        defer { close(fd) }

        var data = Data()
        let chunkSize = 65_536
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            // 闭包内不得再触碰 buffer（独占访问）；长度用常量。
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, chunkSize) }
            if n < 0 {
                if errno == EINTR { continue }
                throw posixNSError(action: "read(\(url.lastPathComponent))")
            }
            if n == 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        return data
    }

    static func atomicWrite(_ data: Data, to url: URL) throws {
        let tmpPath = url.path + ".macmaster-\(UUID().uuidString).tmp"
        let fd = Darwin.open(tmpPath, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw posixNSError(action: "open(临时文件)") }

        var offset = 0
        var writeErrno: Int32 = 0
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while offset < raw.count {
                let n = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    writeErrno = errno
                    return
                }
                offset += n
            }
        }
        if writeErrno == 0, fsync(fd) != 0 { writeErrno = errno }
        close(fd)

        if writeErrno != 0 {
            unlink(tmpPath)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(writeErrno),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(writeErrno))])
        }
        guard rename(tmpPath, url.path) == 0 else {
            let e = errno
            unlink(tmpPath)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(e),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(e))])
        }
    }

    private static func posixNSError(action: String) -> NSError {
        let code = errno
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey: "\(action) 失败：\(String(cString: strerror(code)))（errno \(code)）",
            ]
        )
    }
}

// MARK: - launchctl

public enum LaunchctlRunner {
    private static let launchctlPath = "/bin/launchctl"

    /// `launchctl list` 的时限。现测定时（本机 2026-10-05：毫秒级返回，五轮 3.0–5.6 ms；
    /// 同一天多处现读 18,541–19,540 字节）；10 s 相对那几毫秒是一千八到三千倍的余量，它存在的意义
    /// 不是"跑得快不快"，是把这一条从**永久卡住**变成界面上那句
    /// 「这一轮没能和 launchd 对表（原因），所以下面不标注加载状态」——改之前这里没有任何时限。
    private static let listTimeout: TimeInterval = 10

    /// 返回 nil = 成功；返回字符串 = 失败原文（stderr 或 exit 码）。不再 try? 吞。
    ///
    /// 不设时限：这是写侧，"没等到回话"不能说成"没改成"，宁可等。
    public static func disable(command: String, path: String) -> String? {
        let output: CommandRunner.Output
        do {
            output = try CommandRunner.run(executable: launchctlPath, arguments: [command, "-w", path])
        } catch {
            return "无法启动 launchctl：\((error as NSError).localizedDescription)"
        }
        let errText = output.stderrTrimmed
        guard output.status == 0 else {
            return errText.isEmpty
                ? "exit \(output.status)"
                : "exit \(output.status)：\(errText)"
        }
        return errText.isEmpty ? nil : "launchctl 警告：\(errText)"
    }

    /// 只读快照：跑 `launchctl list` 并把输出交给解析层。
    /// 这是纯查询——不 load/unload/enable/disable 任何东西。
    /// 任何一步失败都换成 `.unavailable(原因)`，让上层显式说"这一轮没能和 launchd 对表"。
    public static func listSnapshot() -> LaunchdSnapshot {
        let output: CommandRunner.Output
        do {
            output = try CommandRunner.run(executable: launchctlPath, arguments: ["list"], timeout: listTimeout)
        } catch {
            return .unavailable(reason: "无法启动 launchctl：\((error as NSError).localizedDescription)")
        }
        guard output.status == 0 else {
            let errText = output.stderrTrimmed
            return .unavailable(reason: "launchctl list exit \(output.status)"
                + (errText.isEmpty ? "" : "：\(errText)"))
        }
        return LaunchctlListParser.parse(output.stdout)
    }
}
