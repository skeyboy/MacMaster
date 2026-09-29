import Foundation

// MARK: - 启动项（LaunchAgent / LaunchDaemon）

/// 卸载时把 app 关联的启动项**列出来**，但默认不勾选：
/// 1. 系统域的 plist 属 root，普通用户删不掉（显示只读，不给删除入口）；
/// 2. 删除启动项会改变自启动行为，属于"用户可能有意保留"的范畴。
///
/// 匹配两轮：
/// A. 文件名与包名对应（LaunchAgents 惯例用 label = bundleID 命名）；
/// B. plist 内容里的 `Program` / `ProgramArguments` 指向这个 app 的路径（含其 Contents/MacOS）。
/// Mole（GPLv3）的分批卸载也做这两轮匹配，思路参考，实现独立。
enum LaunchServiceScanner {

    static func scan(context: ResidualScanner.ResidualScanContext,
                     appPath: String,
                     collector: inout ResidualCollector) {
        let resolvedAppPath = ResidualCollector.physicalPath(appPath)
        for directory in domains(for: context.options) {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            // 不存在 ≠ 读不动。这台机器上多半就没有系统域的两个 LaunchAgents 目录，
            // 把它们一律报成"无法访问"会在面板上堆一堆假警告，真正的 TCC 拒绝反而被淹没。
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: []
                )
            } catch {
                collector.addInaccessible(root.path)
                continue
            }

            for child in children where child.pathExtension.lowercased() == "plist" {
                // 第一轮：文件名与包名对应。
                if let reason = context.matcher.reason(for: child, bundleID: context.bundleID,
                                                      allowContains: context.sensitivity.rank > 0) {
                    record(child, reason: "启动项文件名：\(reason)",
                           resolvedAppPath: resolvedAppPath, collector: &collector)
                    continue
                }
                // 第二轮：plist 里的 Program / ProgramArguments 指向这个 app。
                if let reason = executableReason(for: child, resolvedAppPath: resolvedAppPath,
                                                 bundleID: context.bundleID) {
                    record(child, reason: reason, resolvedAppPath: resolvedAppPath, collector: &collector)
                }
            }
        }
    }

    /// 三个域：用户 LaunchAgents、系统 LaunchAgents、系统 LaunchDaemons。
    /// `/Library/LaunchDaemons` 需要 root 才能写，扫描是只读的，风险档交给收集器判定。
    private static func domains(for options: ResidualScanOptions) -> [String] {
        guard let systemLibrary = options.systemLibrary else {
            return ["\(options.home)/Library/LaunchAgents"]
        }
        return [
            "\(options.home)/Library/LaunchAgents",
            "\(systemLibrary)/LaunchAgents",
            "\(systemLibrary)/LaunchDaemons",
        ]
    }

    private static func record(_ url: URL,
                               reason: String,
                               resolvedAppPath: String,
                               collector: inout ResidualCollector) {
        var note = reason
        // 路径比较必须先解析符号链接，否则 /var 与 /private/var 会静默不等。
        if url.path.contains(resolvedAppPath) { note += "（指向 app 本体路径）" }
        if ResidualCollector.isDeletableByCurrentUser(url.path) == false {
            note += " · root 属主或不可写，仅供查看"
        }
        collector.add(url: url, category: .launchService, reason: note)
    }

    /// 读 plist 内容判断它是否为本 app 的启动项。用 PropertyListSerialization，不做字符串硬解析。
    private static func executableReason(for url: URL,
                                         resolvedAppPath: String,
                                         bundleID: String) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        // label 与包名对应也算命中：文件名与 label 经常不一致。
        if bundleID.isEmpty == false, let label = plist["Label"] as? String {
            let lowered = label.lowercased()
            let owner = bundleID.lowercased()
            if lowered == owner || lowered.hasPrefix(owner + ".") || owner.hasPrefix(lowered + ".") {
                return "启动项 Label 对应包名 \(label)"
            }
        }

        var candidates: [String] = []
        if let program = plist["Program"] as? String { candidates.append(program) }
        if let arguments = plist["ProgramArguments"] as? [Any] {
            for argument in arguments {
                if let value = argument as? String { candidates.append(value) }
            }
        }
        // Program 未必是第一个参数，逐个比对；两侧都走同一个物理路径口径，
        // 否则"存在的 app"与"已不存在的可执行文件"会因 /private 前缀而失配。
        for candidate in candidates {
            let resolved = ResidualCollector.physicalPath(candidate)
            guard resolved.isEmpty == false else { continue }
            if resolved == resolvedAppPath || resolved.hasPrefix(resolvedAppPath + "/") {
                return "启动项指向 app 内可执行文件 \(candidate)"
            }
        }
        return nil
    }
}
