//
//  DevToolCacheAudit.swift — 开发工具缓存的只读盘点（P4.3）
//
//  这一屏的本体是"该由 owner 命令清的缓存"。MacMaster 不执行任何第三方二进制：
//  跑 `go clean -modcache` 意味着信任用户机器上任意版本的 go，还要在它执行前的
//  最后一跳复查符号链接与路径身份（参考实现 Mole dev.sh:845-905 就是干这个的）。
//  我们只报三件独立的事实——装没装、在不在、多大——外加一条可拷贝的命令。
//  没有执行，就不需要"进程状态未知时拒绝执行"那套判据。
//

import Foundation

// MARK: - 档位

/// 缓存根是从哪儿定出来的。两档必须分开显示：`defaultPath` 是"没问过工具"，
/// 不能让用户读成"这就是它实际在用的那个"。
public enum DevCacheRootSource: Equatable, Sendable {
    case environment(key: String)
    case defaultPath

    public var badgeText: String {
        switch self {
        case .environment(let key): "按 \(key) 定位"
        case .defaultPath: "按默认位置 · 未向工具求证"
        }
    }
}

/// 根目录本身的状态。`absent` 与"空"是两回事：目录不存在时写 0 字节可清理，
/// 是把"没看过/没有这个地方"渲染成"干净"。
public enum DevCachePresence: Equatable, Sendable {
    case present
    case absent
    case unreadable(reason: String)
}

public struct DevToolCacheEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let root: String
    public let rootSource: DevCacheRootSource
    /// PATH 里能不能解析到可执行文件（只 stat，不执行）。
    public let toolInstalled: Bool
    public let toolName: String
    public let presence: DevCachePresence
    /// nil = 没量到，渲染成"—"，绝不折成 0。
    public let bytes: UInt64?
    /// 只给文本 + 拷贝入口，MacMaster 不代跑。nil = 没有 owner 命令。
    public let ownerCommand: String?
    public let why: String
    /// 工具没装 / 目录不存在时，命令与大小都失去意义，脚注要说清楚。
    public let caveat: String?

    public init(id: String, title: String, root: String, rootSource: DevCacheRootSource,
                toolInstalled: Bool, toolName: String, presence: DevCachePresence,
                bytes: UInt64?, ownerCommand: String?, why: String, caveat: String?) {
        self.id = id
        self.title = title
        self.root = root
        self.rootSource = rootSource
        self.toolInstalled = toolInstalled
        self.toolName = toolName
        self.presence = presence
        self.bytes = bytes
        self.ownerCommand = ownerCommand
        self.why = why
        self.caveat = caveat
    }
}

// MARK: - 审计

public enum DevToolCacheAuditor {

    /// 环境变量的值只有"绝对路径、不含 ..、不含换行"才敢拿来当根。
    /// 判据照 Mole `resolve_tool_home`（dev.sh:1070-1082）抄：
    /// 一个 `GOMODCACHE=../../etc` 就足以把一次"清理"变成越界删除。
    public static func usableEnvPath(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard raw.hasPrefix("/") else { return nil }
        guard !raw.contains("\n"), !raw.contains("\r") else { return nil }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.contains("..") else { return nil }
        return String(raw.hasSuffix("/") && raw.count > 1 ? raw.dropLast() : raw[...])
    }

    /// 只 stat，绝不执行。
    public static func toolPath(name: String, env: [String: String],
                                fileProbe: (String) -> Bool) -> String? {
        let path = env["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if fileProbe(candidate) { return candidate }
        }
        return nil
    }

    /// 输入全部注入（环境、探针、量数），所以这一层可以完整单测。
    public static func entries(env: [String: String],
                               home: String,
                               presenceProbe: (String) -> DevCachePresence,
                               sizeProbe: (String) -> UInt64?,
                               toolProbe: (String) -> Bool) -> [DevToolCacheEntry] {
        let h = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        // 有的环境变量直接指向缓存根（GOMODCACHE），有的是指向工具的"家"
        // （CARGO_HOME → ~/.cargo/registry）。两档不能一样处理：拼错这一段，
        // 报出去的位置就不是 owner 实际在用的那个。
        func root(envKey: String?, envSubpath: String?, fallback: String) -> (String, DevCacheRootSource) {
            if let key = envKey, let fromEnv = usableEnvPath(env[key]) {
                let joined = envSubpath.map { "\(fromEnv)/\($0)" } ?? fromEnv
                return (joined, .environment(key: key))
            }
            return (fallback, .defaultPath)
        }

        let specs: [(id: String, title: String, tool: String, envKey: String?, envSubpath: String?,
                     fallback: String, command: String?, why: String)] = [
            ("go-mod", "Go 模块缓存", "go", "GOMODCACHE", nil, "\(h)/go/pkg/mod", "go clean -modcache",
             "里面的包是只读的、还互相共享硬链接，删掉之后 go 自己的视图不会同步。这条命令删的是根目录本身，所以跑之前要确认根不是符号链接——否则它会顺着链接删到别处。"),
            ("go-build", "Go 构建缓存", "go", "GOCACHE", nil, "\(h)/Library/Caches/go-build", "go clean -cache",
             "owner 有按时间保留最近用过的条目的能力（-trim），整目录 rm 会把热缓存一起清掉，下次全量重编。"),
            ("cargo-registry", "Cargo 包缓存", "cargo", "CARGO_HOME", "registry", "\(h)/.cargo/registry", "cargo cache -O",
             "registry 里的 .crate 是可重下的下载缓存；但 cargo 自带并没有清缓存的子命令，cargo-cache 是第三方扩展。"),
            ("homebrew", "Homebrew 下载缓存", "brew", "HOMEBREW_CACHE", nil, "\(h)/Library/Caches/Homebrew", "brew cleanup -n",
             "这个目录只是瓶子的下载缓存，rm 是安全的；但真正占空间的多半是旧版本 formula，只有 brew 自己知道哪些还在依赖链上。先 -n 预览再决定。"),
            ("npm", "npm 缓存", "npm", "npm_config_cache", nil, "\(h)/.npm/_cacache", "npm cache verify",
             "verify 会校验内容寻址存储并回收失效项，比整目录 rm 准；rm 之后首次安装要全量重下。"),
            ("pip", "pip HTTP 缓存", "pip3", nil, nil, "\(h)/Library/Caches/pip", nil,
             "pip 没有清理子命令，删目录是安全的；下次装包重新下载。"),
        ]

        return specs.map { spec in
            let (rootPath, source) = root(envKey: spec.envKey, envSubpath: spec.envSubpath,
                                          fallback: spec.fallback)
            let installed = toolProbe(spec.tool)
            let presence = presenceProbe(rootPath)
            let bytes: UInt64?
            switch presence {
            case .present: bytes = sizeProbe(rootPath)
            case .absent, .unreadable: bytes = nil
            }
            let caveat: String?
            if !installed {
                caveat = "PATH 里没找到 \(spec.tool)：位置是按默认规则算出来的，也没法跑 owner 命令。"
            } else if case .absent = presence {
                caveat = "这个位置不存在——不是「0 字节可清理」，是这台机器上它还没被写过。"
            } else if case .unreadable = presence {
                caveat = "读不动这个位置，所以大小和状态都不知道；下面不显示数字。"
            } else {
                caveat = spec.command == nil
                    ? "没有 owner 清理命令，这一条只能按目录处理。"
                    : nil
            }
            return DevToolCacheEntry(
                id: spec.id, title: spec.title, root: rootPath, rootSource: source,
                toolInstalled: installed, toolName: spec.tool,
                presence: presence, bytes: bytes,
                ownerCommand: spec.command, why: spec.why, caveat: caveat
            )
        }
    }

    /// 真机入口：环境取 ProcessInfo，探针取 FileManager，量数交给调用方注入
    /// （MMFormat/SystemSampler 在 UI 侧，这里不反向依赖）。
    public static func liveEntries(sizeProbe: (String) -> UInt64?) -> [DevToolCacheEntry] {
        let env = ProcessInfo.processInfo.environment
        let fm = FileManager.default
        return entries(
            env: env,
            home: NSHomeDirectory(),
            presenceProbe: { path in
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return .absent }
                guard isDir.boolValue else { return .unreadable(reason: "路径存在但不是目录") }
                // 能 stat 不等于能枚举：真正的读权限用 canChangeDirectory 判。
                guard fm.isReadableFile(atPath: path) else {
                    return .unreadable(reason: "没有读权限")
                }
                return .present
            },
            sizeProbe: sizeProbe,
            toolProbe: { name in toolPath(name: name, env: env) { candidate in
                fm.isExecutableFile(atPath: candidate)
            } != nil }
        )
    }
}

// MARK: - 文案

public enum DevToolCacheCopy {
    public static let footnote = "这一屏不删任何东西：MacMaster 不执行第三方二进制，只报位置和命令。"
        + "命令拷进终端由你决定跑不跑。"

    public static let absentBadge = "位置不存在"
    public static let unreadableBadge = "读不到"
    public static let presentBadge = "在用"
    public static let notInstalledBadge = "未安装"

    public static func presenceBadge(_ entry: DevToolCacheEntry) -> String {
        if !entry.toolInstalled { return notInstalledBadge }
        switch entry.presence {
        case .present: return presentBadge
        case .absent: return absentBadge
        case .unreadable: return unreadableBadge
        }
    }
}
