import Foundation
import Darwin

// MARK: - Steam 启动器型 bundle（只认，不说）
//
// 这类 bundle 里没有游戏，只有一个几十行不到的 shell 脚本，内容是 `open steam://run/<数字>`。
// 于是它的「本体」量出来是启动器的大小：P32a 的夹具里那一行是 593 字节，而同一份夹具的
// 游戏本体在 `Application Support/Steam/steamapps/common/<游戏>/` 有 25,165,832 字节
// （详数与照片见 `docs/analysis/uninstaller-steam-launcher.md`）。
//
// 参考项目里只有 Mole 做了这一档，而它认定之后**只改显示、不碰删除**
// （`lib/uninstall/steam.sh` 出结论，`bin/uninstall.sh` 把大小换成 `N/A (Steam-managed)`）。
// 我们照同一边界：这一层只产出「它是什么 + 凭据」，删除集合一行都不改。
//
// 为什么不进 `AppProvenance.Source`：那一档答的是"谁把它装上来的"，这一档答的是"它是什么"。
// 一个 brew 装的 Steam 启动器两句同时成立，把正交的两个维度塞进一个枚举就会互相覆盖。
//
// 两条入口的分歧也是有意的：Mole 读 `CFBundleExecutable`（取不到退回 bundle 文件名），
// Pearcleaner 写死 `Contents/MacOS/run.sh`。所以 `candidates` 按优先级收两条，
// 判定层逐条试，不是选一边。
//
// 措辞全在 `MMUninstaller.swift` 的呈现层；本文件除了 `SteamGameLibraryCaveat`
// 那一小节（它产出的是 `ResidualItem.reason` 的一部分，与 `ResidualNameMatcher` 的证据短句同族）
// 没有一个用户可见字符串。

/// 一个候选启动脚本的只读快照。值类型，好把判定与读取分开测。
public struct LauncherScriptSnapshot: Sendable, Equatable {
    public enum Source: String, Sendable {
        /// `Contents/Info.plist` 的 `CFBundleExecutable` 指过去的那个文件。
        case bundleExecutable
        /// Pearcleaner 写死的那个名字 `run.sh`。
        case fixedName
    }
    public let name: String
    public let source: Source
    /// `lstat` 报出的字节数。
    public let size: Int
    public let isExecutable: Bool
    /// 脚本正文；读不到（不可执行、超过成本闸门、或不是合法 UTF-8）时为 nil。
    public let text: String?

    public init(name: String, source: Source, size: Int, isExecutable: Bool, text: String?) {
        self.name = name
        self.source = source
        self.size = size
        self.isExecutable = isExecutable
        self.text = text
    }
}

/// `steam://` 里那三个动词。Mole 的正则也只收这三个。
public enum SteamLaunchVerb: String, Sendable, Equatable {
    case run
    case rungameid
    case launch
}

/// 认定成立时的凭据：哪个脚本、哪个动词、哪个 appid。
public struct SteamLauncherInfo: Sendable, Equatable {
    public let appID: String
    public let verb: SteamLaunchVerb
    public let scriptName: String
    public let scriptSource: LauncherScriptSnapshot.Source

    public init(appID: String, verb: SteamLaunchVerb, scriptName: String,
                scriptSource: LauncherScriptSnapshot.Source) {
        self.appID = appID
        self.verb = verb
        self.scriptName = scriptName
        self.scriptSource = scriptSource
    }
}

public enum SteamLauncherProbe {
    /// 合同上限，也是读内容的成本闸门：真的启动脚本只有几十行，超了就不是这一族。
    public static let maxScriptBytes = 4096
    /// 写死的第二条入口名（Pearcleaner 的那个形状）。
    public static let fixedScriptName = "run.sh"
    static let shebangInterpreters: Set<String> = ["sh", "bash", "zsh", "env"]
    static let urlScheme = "steam://"

    // MARK: 纯判定

    /// 按优先级排好的候选快照 → 启动器凭据。不碰磁盘、不 spawn 进程。
    ///
    /// 一条不合格就试下一条（两条候选是不同来源的写法，不是同一文件的两种读法）。
    /// 判定顺序照 Mole 的边界，逐条钉在单测里：普通文件、可执行、≤4096、
    /// 首行是 sh/bash/zsh/env 的 shebang、非空非注释的有效行**正好一行**、
    /// 那一行是 `open steam://(run|rungameid|launch)/<纯数字>`。
    public static func resolve(candidates: [LauncherScriptSnapshot]) -> SteamLauncherInfo? {
        for snapshot in candidates {
            guard snapshot.isExecutable,
                  snapshot.size <= maxScriptBytes,
                  let text = snapshot.text else { continue }
            let lines = text.components(separatedBy: .newlines)
            guard let first = lines.first, isShebang(first) else { continue }
            let active = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty == false && trimmed.hasPrefix("#") == false
            }
            guard active.count == 1, let parsed = parse(active[0]) else { continue }
            return SteamLauncherInfo(appID: parsed.appID, verb: parsed.verb,
                                     scriptName: snapshot.name, scriptSource: snapshot.source)
        }
        return nil
    }

    /// 首行必须是解释器脚本。`#!/usr/bin/env bash` 走 `env` 这一档。
    static func isShebang(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#!") else { return false }
        let tokens = trimmed.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let interpreter = tokens.first else { return false }
        return shebangInterpreters.contains((String(interpreter) as NSString).lastPathComponent.lowercased())
    }

    /// 有效行 → 动词 + appid。只接受 `open <URL>` 这一种写法（多一个参数就不是这一族），
    /// 尾部的 `&` 与引号允许；appid 必须是 ASCII 数字。
    static func parse(_ line: String) -> (verb: SteamLaunchVerb, appID: String)? {
        let tokens = line.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "&" })
            .map(String.init)
        guard tokens.count == 2, tokens[0].lowercased() == "open" else { return nil }
        let target = tokens[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard target.lowercased().hasPrefix(urlScheme) else { return nil }
        let tail = target.dropFirst(urlScheme.count)
        guard let slash = tail.firstIndex(of: "/") else { return nil }
        let verbText = String(tail[..<slash]).lowercased()
        let idText = String(tail[tail.index(after: slash)...])
        guard let verb = SteamLaunchVerb(rawValue: verbText) else { return nil }
        guard idText.isEmpty == false, idText.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        return (verb, idText)
    }

    // MARK: 只读读取

    /// 这个 bundle 里可能存在的启动脚本，按优先级排好（先 plist 指的那个，再 `run.sh`）。
    /// **只读**：`lstat` + 至多一次小文件读取，不解析符号链接、不执行任何东西。
    public static func read(appPath: String, bundleExecutable: String) -> [LauncherScriptSnapshot] {
        var out: [LauncherScriptSnapshot] = []
        var seen = Set<String>()
        for candidate in scriptCandidates(bundleExecutable: bundleExecutable) {
            let path = "\(appPath)/Contents/MacOS/\(candidate.name)"
            guard seen.insert(ResidualCollector.canonicalPath(path)).inserted else { continue }
            if let snapshot = snapshot(path: path, name: candidate.name, source: candidate.source) {
                out.append(snapshot)
            }
        }
        return out
    }

    /// 候选名字与来源。plist 里的值是外部输入，带 `/` 或 `..` 的一律不拼进路径——
    /// 这一层不产生命名能力，只读一个已知目录下的一个已知文件。
    static func scriptCandidates(bundleExecutable: String)
        -> [(name: String, source: LauncherScriptSnapshot.Source)] {
        var candidates: [(String, LauncherScriptSnapshot.Source)] = []
        let trimmed = bundleExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false, trimmed.contains("/") == false {
            candidates.append((trimmed, .bundleExecutable))
        }
        candidates.append((fixedScriptName, .fixedName))
        return candidates
    }

    private static func snapshot(path: String, name: String,
                                 source: LauncherScriptSnapshot.Source) -> LauncherScriptSnapshot? {
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { return nil }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let size = Int(info.st_size)
        let isExecutable = (info.st_mode & S_IXUSR) != 0
        // 只有可能是启动器的形状才值得读正文：可执行 + ≤4096。合同本身在 `resolve` 里再判一次，
        // 这一处纯粹是成本闸门——不然每个应用都要为读一个几十兆的 Mach-O 买单。
        var text: String?
        if isExecutable, size <= maxScriptBytes, let data = FileManager.default.contents(atPath: path) {
            text = String(data: data, encoding: .utf8)
        }
        return LauncherScriptSnapshot(name: name, source: source, size: size,
                                      isExecutable: isExecutable, text: text)
    }
}

// MARK: - 反方向：`Application Support/Steam` 这一行到底装着什么
//
// P32a 的第二条发现比启动器本身更要紧：卸载 **Steam 本体**时，
// `~/Library/Application Support/Steam` 会以「名称与包名对应」的身份进残留清单，
// 而真机上那一个目录里装着全部已装游戏。默认不勾这一道挡住了误删，
// 但行上原本只有分组那句"可能包含登录态或未同步数据"——说的是账号，不是游戏库。
//
// 这里不猜、不数、不算大小：只看这个目录的**直接子项**里有没有 `steamapps` 这一个名字。
// 有就在那一行下方单起一句（"这一项内含 steamapps 目录，已装游戏通常在它下面；删掉这一项会连游戏一起删。"），
// 没有就一个字不说。

public enum SteamGameLibraryCaveat {
    public static let directoryName = "steamapps"

    /// 这一行自己的提醒。命中条件由调用方给：这条候选是个目录，
    /// 且它的直接子项里有 `steamapps`。
    ///
    /// 它是**独立一行**，不是接在证据短句后面：照片
    /// `docs/verification/p32b-steam/11a-narrow-window-truncation-before-fix.png` 现读，
    /// 窗口硬最小宽度 1000 时这一行的副标题在画面上只剩 `~/Library/Application` 与
    /// `已装游戏通常在其下` 两段，中间那一段（连 `steamapps` 这个词本身）被省略号吃掉，
    /// 而光路径就有 35 个字符——接在后面等于没写。
    public static func note(children: [String]?) -> String? {
        guard let children, children.contains(directoryName) else { return nil }
        return "这一项内含 \(directoryName) 目录，已装游戏通常在它下面；删掉这一项会连游戏一起删。"
    }
}
