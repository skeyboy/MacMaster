//
//  LaunchItemPolicy.swift — 登录项域的读写边界（3.5：去掉无权限时的静默失败）
//
//  规则只有一条：/Library 域（LaunchAgents/LaunchDaemons）一律只读展示，
//  永远不尝试写 Disabled 键——无 root 时 write() 会静默返回 false，UI 却报成功。
//  只有 ~/Library/LaunchAgents 下的 plist 允许写；写失败必须把错误原文
//  （含 POSIX 码文本）交回 UI 展示。
//

import Foundation

public enum LaunchDomain: String, Sendable, Equatable {
    /// ~/Library/LaunchAgents —— 可读可写。
    case user
    /// /Library/LaunchAgents 与 /Library/LaunchDaemons —— 只读展示 + 引导到系统设置。
    case system
    /// 兼容旧的"用户登录项 plist"（Preferences/loginitems.plist）只读条目。
    case userPreferences

    public var isWritable: Bool { self == .user }

    public var badgeText: String {
        switch self {
        case .user: "用户"
        case .system: "系统"
        case .userPreferences: "登录项"
        }
    }
}

public enum LaunchItemPolicy {

    /// 路径归一化后再比较：/var 与 /private/var 这类符号链接别名会让裸字符串比较
    /// 把同一个目录认成两个（也可能反过来误判）。
    /// 前缀匹配必须带目录分隔符，防 `~/Library/LaunchAgentsEvil` 混进来。
    public static func isUserLaunchAgent(path: String, home: String) -> Bool {
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let dir = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/LaunchAgents")
            .resolvingSymlinksInPath()
            .path
        return resolvedPath.hasPrefix(dir + "/") && resolvedPath != dir
    }

    public static func domain(for path: String, home: String = NSHomeDirectory()) -> LaunchDomain {
        if isUserLaunchAgent(path: path, home: home) { return .user }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        for dir in ["/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            if resolved.hasPrefix(dir + "/") { return .system }
        }
        return .userPreferences
    }
}
