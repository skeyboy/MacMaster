import Foundation
import AppKit

// MARK: - 运行中检测（纯判定 + 只读快照）
//
// 参考项目的做法是**动手前先把应用结束掉**（Pearcleaner `Logic/Utilities.swift` 的
// `killApp(appId:)` 遍历 `runningApplications` 逐个 `terminate()`；Mole 的卸载批处理里
// 那段 "Best-effort termination" 还带一套强杀阶梯）。我们只做到"看见并说出来"为止：
// 结束别人的进程是一项改动系统状态的能力，一旦有了它就要回答"杀不动怎么办""未保存的
// 文档谁负责"，而这些本模块一行代码都不用处理——因为 macOS 允许把正在运行的 .app
// 移到废纸篓（进程继续用已经载入的代码跑），所以这条信息只值得作为提醒，不值得作为能力。
//
// 判据分两半（与 `TrashWatcher`、`AppProvenance` 同一套规矩）：
// `AppRunningState.resolve` 是纯函数，只吃快照值类型，单测在里面钉规则；
// `RunningAppProbe.snapshot()` 才是那句 `NSWorkspace` 调用，它不假装单测能读到系统状态。
// 存与刷由 `UninstallerModel` 负责；颜色与措辞全部在 `MMUninstaller.swift`
// 的「运行状态的呈现口径」一节——本文件一个用户可见字符串都没有。

/// 一条"此刻有一个应用实例在跑"的可读快照。值类型，方便把判定与读取分开测。
public struct RunningAppInfo: Sendable, Equatable {
    public let pid: Int32
    /// 进程报出的包标识，没注册进 LaunchServices 时为 nil。别按 activationPolicy 猜它：
    /// 本机现读（2026-10-10）19 条报不出包名的实例里 `.accessory` 12 条、`.prohibited` 6 条、
    /// `.regular` 也有 1 条（`ADB Link` 包里的 scrcpy——照片上那一行的「运行中」靠的就是位置对上）。
    public let bundleIdentifier: String?
    /// 进程报出的 bundle 位置。换过安装目录、或经 App Translocation 在临时副本里
    /// 运行时，它会和磁盘上那一份不同——这正是要在界面上说出来的差别。
    public let bundlePath: String?
    public let displayName: String?

    public init(pid: Int32, bundleIdentifier: String?, bundlePath: String?, displayName: String?) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.displayName = displayName
    }

    /// 既报不出包名也报不出位置：这一条进程无法归因到任何一个应用。
    var isUnattributable: Bool {
        bundleIdentifier?.isEmpty != false && bundlePath?.isEmpty != false
    }
}

/// 命中的证据是哪一条。两档的差别会在界面上换措辞：同一份文件在跑，
/// 和"包名对上但那份进程说它在别处"，用户要做的事不一样。
public enum AppRunningEvidence: String, Sendable, Equatable {
    /// 快照里那份进程的 bundle 路径就是候选这个文件。
    case sameBundle
    /// 只有包名对上，位置对不上。
    case bundleIdentifierOnly
}

public struct RunningAppMatch: Sendable, Equatable {
    public let pid: Int32
    public let evidence: AppRunningEvidence
    /// 命中的那条快照自己报出的位置；`sameBundle` 时它就是候选路径，可能为 nil
    /// （包名对上而位置报不出）。
    public let bundlePath: String?
    public let displayName: String?
}

public enum AppRunningState: Sendable, Equatable {
    /// pids 升序。多个进程是真实可能（同一份 bundle 起两份、或多份拷贝共用一个包名）。
    case running(matches: [RunningAppMatch])
    case notRunning
    /// 没正对上，但快照里有 `unattributableCount` 条既报不出包名也报不出位置的进程。
    /// 这一档不写成"没在运行"：那是把"我没看到"说成"没有"，
    /// 与来源识别里 `unknown` 不写成"手动安装"是同一条纪律。
    case undetermined(unattributableCount: Int)
}

// MARK: 纯判定

extension AppRunningState {
    /// 候选的两个标识 + 一份快照 → 状态。不碰文件系统、不碰 NSWorkspace，
    /// 所以每条分支都能在单测里跑完，包括真机上很难凑齐的那几档。
    ///
    /// 两条比对一律大小写不敏感：路径这边是 APFS 默认卷不区分大小写，
    /// 包名那边宁可多提醒一次也不要漏——漏掉的后果是"界面说没运行、其实开着文件"，
    /// 多出来的后果只是一句用不上的提醒。
    /// 不做 realpath：那是文件系统调用，放进纯函数就没法单测；
    /// 符号链接装的应用由包名那一档兜住。代价写在明处——**同一个文件的两种写法**
    /// 会落到"只有包名对上"那一档（`/tmp` 与 `/private/tmp` 就是这样，P31a 实拍抓到的），
    /// 所以呈现层那一档只说"写法不同"，不说"不是同一个文件"（见 `runningWarning`）。
    public static func resolve(bundleID: String, bundlePath: String,
                               running snapshots: [RunningAppInfo]) -> AppRunningState {
        let candidatePath = bundlePath.isEmpty ? nil : bundlePath.lowercased()
        let candidateID = bundleID.isEmpty ? nil : bundleID.lowercased()
        var matches: [RunningAppMatch] = []
        var unattributable = 0

        for info in snapshots {
            if info.isUnattributable {
                unattributable += 1
                continue
            }
            let path = info.bundlePath?.lowercased()
            let id = info.bundleIdentifier?.lowercased()
            let sameFile = candidatePath != nil && path == candidatePath
            let sameID = candidateID != nil && id == candidateID && path != candidatePath
            guard sameFile || sameID else { continue }
            matches.append(RunningAppMatch(pid: info.pid,
                                           evidence: sameFile ? .sameBundle : .bundleIdentifierOnly,
                                           bundlePath: info.bundlePath,
                                           displayName: info.displayName))
        }

        if matches.isEmpty {
            return unattributable > 0 ? .undetermined(unattributableCount: unattributable) : .notRunning
        }
        return .running(matches: matches.sorted { $0.pid < $1.pid })
    }

    /// 只有正对上进程才算。呈现层用它决定占不占列表那一格。
    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

// MARK: 只读快照

public enum RunningAppProbe {
    /// 现在有哪些应用实例在跑。**只读**：不启动、不结束、不轮询，也不需要任何权限。
    ///
    /// 这里没有假快照的钩子。取证脚本要拍"运行中"那一档，靠的是**真的把一个 /tmp 下的
    /// 夹具应用启动起来**（`Scripts/p31-running-capture.sh`），所以照片里那一行是
    /// `NSWorkspace` 给的真话，不是我们喂给界面的合成值；反过来说，
    /// `undetermined` 那一档在本机拍不出来：当日两次现读（2026-10-10，参与判定的分别是 163 条与 165 条，
    /// 这个数随机器状态在几小时内就会变）里，"包名与位置都报不出"的都是 **0 条**——
    /// 包名单独报不出的有 31 条、位置单独报不出的有 17 / 19 条，但没有一条两样都报不出。
    /// 所以这一档只有单测，这一条如实写在 roadmap 里。
    /// 同一次现读里还有一条 `pid = -1`：`com.apple.dt.Devices`（"Device Hub"，
    /// Xcode 的那份 helper bundle）。它在 LaunchServices 的账上、却不是一个进程。
    /// 这种条目必须在读取端就剔掉，不能留给判定：否则界面会说出"正在运行 · 进程 -1"，
    /// 而那是这一页唯一一种既看不见也摸不着的假话。
    public static func snapshot() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier > 0 else { return nil }
            return RunningAppInfo(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                                  bundlePath: app.bundleURL?.path, displayName: app.localizedName)
        }
    }
}
