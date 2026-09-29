//
//  LoginItemAudit.swift — 登录项的"完整度"交叉核对（路线图 P3.3）
//
//  列表页原来只说"磁盘上有这个 plist"，可这跟"它到底有没有在跑"是两件事。
//  这一层把磁盘清单和 launchd 的当前会话对一遍，标出三类不一致：
//
//  1. `.plistNotLoaded`   —— plist 在、也没被标 Disabled，但当前会话里查不到这个标签。
//     注意这一条**不是**"它坏了"：按需加载的 Agent 在触发之前本来就不在 `launchctl list` 里。
//     所以文案是"没在当前会话里加载"，把可能性说全，不写成结论。
//  2. `.disabledButLoaded` —— plist 写着 Disabled=true，会话里却确实加载着：停用没生效。
//  3. `.orphanLoaded`      —— 会话里有这个标签，五个已知目录里都没有对应的 plist 文件。
//
//  判定铁律（本项目第一红线）：
//  - `launchctl list` 没跑成、或输出解析不出表头 → 整批降级成"无法核对"，
//    **绝不**把"没查到"渲染成"没加载"。空集合也按不可用处理：一个标签都解析不出来
//    的 `launchctl list` 说明的是解析失败，不是这台机器什么都没跑。
//  - 只核对能确定的域：用户 LaunchAgents 与 /Library/LaunchAgents 会进 GUI 域的
//    `launchctl list`；/Library/LaunchDaemons 属于 system 域，无 root 查不到，
//    整类不参与判定（宁可少说，不可瞎说）。
//  - 孤儿标签要排掉那些本来就没有 plist 文件的任务族（`application.*` / `pid.*` 等
//    app 生命周期任务、以及 `com.apple.cua.*` 这类系统托管项），否则一屏全是苹果自家条目。
//

import Foundation

// MARK: - launchd 快照

public enum LaunchdSnapshot: Equatable, Sendable {
    /// 成功解析出的标签集合。
    case labels(Set<String>)
    /// 没跑成 / 读不懂 —— 带着原因，UI 要原样展示。
    case unavailable(reason: String)

    public var labelSet: Set<String>? {
        if case .labels(let s) = self { return s }
        return nil
    }
}

// MARK: - 异常类型

public enum LoginItemAnomaly: String, Equatable, Sendable {
    case plistNotLoaded
    case disabledButLoaded
    case orphanLoaded
}

public struct LoginItemAudit: Equatable, Sendable {
    /// 按 item.path 索引的行内异常。
    public var anomalies: [String: LoginItemAnomaly]
    /// 查到了 plist 文件却没人认领的标签（界面单独一卡列出来）。
    public var orphanLabels: [String]
    /// false = 这一轮根本没核对成（launchctl 不可用），界面不许显示"一切正常"。
    public var determinate: Bool
    /// 不可核对时的原因原文。
    public var reason: String?

    public init(anomalies: [String: LoginItemAnomaly] = [:], orphanLabels: [String] = [],
                determinate: Bool = false, reason: String? = nil) {
        self.anomalies = anomalies
        self.orphanLabels = orphanLabels
        self.determinate = determinate
        self.reason = reason
    }

    public static let indeterminate = LoginItemAudit(
        determinate: false, reason: "未执行核对"
    )
}

// MARK: - `launchctl list` 解析

public enum LaunchctlListParser {

    /// 输出形如：
    ///   PID\tStatus\tLabel
    ///   67556\t-9\tcom.apple.cloudphotod
    ///   -\t0\tcom.tencent.Lemon.trash
    /// 表头认不出来、或一行标签都没解析出来，都算不可用：这两种情况都说明
    /// 我们读到的不是预期里的东西，此时"某个 Agent 不在表里"推不出任何结论。
    public static func parse(_ output: String) -> LaunchdSnapshot {
        let lines = output.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let header = lines.first else {
            return .unavailable(reason: "launchctl list 没有任何输出")
        }
        let headerCells = header.split(whereSeparator: { $0 == "\t" || $0 == " " })
            .map { $0.lowercased() }
        guard headerCells.count >= 3, headerCells[0] == "pid", headerCells[2] == "label" else {
            return .unavailable(reason: "launchctl list 表头不认识：\(String(header.prefix(60)))")
        }
        var labels = Set<String>()
        for line in lines.dropFirst() {
            let cells = line.split(whereSeparator: { $0 == "\t" })
            guard cells.count >= 3 else { continue }
            let label = cells[2].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            labels.insert(label)
        }
        guard !labels.isEmpty else {
            return .unavailable(reason: "launchctl list 一个标签都没解析出来（多半是输出格式变了），不敢据此判定")
        }
        return .labels(labels)
    }
}

// MARK: - 判定

public enum LoginItemAuditor {

    /// 这一项能不能拿来和 GUI 域对表。
    /// LaunchDaemons 属 system 域，无 root 的 `launchctl list` 里本来就没有它——
    /// 拿"查不到"说它"没加载"就是假话，所以整类排除。
    public static func isJudgable(_ item: LoginItem) -> Bool {
        guard item.fileKind == .plist else { return false }   // 改名停用的本来就不该加载
        switch item.domain {
        case .user:
            return true
        case .system:
            return item.path.hasPrefix("/Library/LaunchAgents/")
        case .userPreferences:
            return false
        }
    }

    /// 没有 plist 文件、由 launchd 自己管的任务族前缀。这些不是"孤儿"，列出来只会淹掉屏幕。
    static let nonPlistLabelPrefixes: [String] = [
        "application.", "pid.", "gui/", "system/",
    ]

    /// `com.apple.*` 单独排除，理由和上面不同：苹果自己的条目大量住在
    /// `/System/Library/Launch*` 之外的地方（本机的 101 个候选里 99 个是苹果的），
    /// 我们枚举不全它们的落盘位置，列出来只会把真正该看的两三条埋掉。
    /// 这是"少说"，不是"说错"——脚注里会写明只核对非苹果标签。
    static let unenumerableLabelPrefixes: [String] = ["com.apple.", "com.apple.cua."]

    public static func isPlistBackedLabel(_ label: String) -> Bool {
        !nonPlistLabelPrefixes.contains { label.hasPrefix($0) }
    }

    /// 值得报成"找不到 plist"的标签：排掉任务族，也排掉苹果的落盘位置。
    public static func isOrphanCandidate(_ label: String) -> Bool {
        isPlistBackedLabel(label) && !unenumerableLabelPrefixes.contains { label.hasPrefix($0) }
    }

    /// `plistExists` 由探针层提供（真实文件系统）；测试注入字典。
    public static func audit(
        items: [LoginItem],
        snapshot: LaunchdSnapshot,
        plistExists: (String) -> Bool
    ) -> LoginItemAudit {
        guard let labels = snapshot.labelSet else {
            let reason: String
            if case .unavailable(let r) = snapshot { reason = r } else { reason = "未执行核对" }
            return LoginItemAudit(determinate: false, reason: reason)
        }

        var anomalies: [String: LoginItemAnomaly] = [:]
        for item in items where isJudgable(item) {
            let loaded = labels.contains(item.name)
            if item.enabled && !loaded {
                anomalies[item.path] = .plistNotLoaded
            } else if !item.enabled && loaded {
                anomalies[item.path] = .disabledButLoaded
            }
        }

        // 孤儿：会话里有标签，但五个已知目录都没有 <label>.plist。
        // 已知目录清单和扫描目录同源 + /System 两处（不扫但必须排掉，否则苹果自家条目全中）。
        let orphans = labels.filter { label in
            guard isOrphanCandidate(label) else { return false }
            return !knownPlistPaths(forLabel: label).contains(where: plistExists)
        }
        return LoginItemAudit(anomalies: anomalies, orphanLabels: orphans.sorted(), determinate: true, reason: nil)
    }

    static func knownPlistPaths(forLabel label: String) -> [String] {
        [
            "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist",
            "/Library/LaunchAgents/\(label).plist",
            "/Library/LaunchDaemons/\(label).plist",
            "/System/Library/LaunchAgents/\(label).plist",
            "/System/Library/LaunchDaemons/\(label).plist",
        ]
    }
}

// MARK: - 文案

public enum LoginItemAnomalyCopy {
    public static func badge(_ anomaly: LoginItemAnomaly) -> (text: String, tintName: String) {
        switch anomaly {
        case .plistNotLoaded:
            return ("没在当前会话里加载", "caution")
        case .disabledButLoaded:
            return ("标着停用但其实还加载着", "caution")
        case .orphanLoaded:
            return ("launchd 里有、找不到 plist", "caution")
        }
    }

    /// 逐条解释为什么这不算判决。列表页脚用。
    public static let footnote = "「没在当前会话里加载」不等于坏了：按需启动的 Agent 在第一次被触发之前本来就不在 launchctl 列表里。"
        + "这里只报「磁盘上有什么」和「launchd 当前认了什么」对不上的地方，不替你下结论。"

    /// 孤儿标签的补充说明。SMAppService 注册的现代登录项长得和残留一模一样——
    /// 磁盘上确实没有传统 plist，但它不是垃圾。把这条写在旁边，
    /// 免得用户拿它当"清理线索"去删一个正在用的应用。
    /// 只写"这条读数该怎么理解"：事实本身由 UI 那行陈述句给出，两处不重复。
    public static let orphanNote = "不一定是残留：新版 SMAppService 注册的登录项本来就不落这些目录。"
        + "只列非苹果自家的标签（苹果的落盘位置枚举不全，列出来会把该看的埋掉）。"

    public static func indeterminateNote(_ reason: String) -> String {
        "这一轮没能和 launchd 对表（\(reason)），所以下面不标注加载状态——"
        + "「没查到」不会被写成「没加载」。"
    }
}
