//
//  GuardianFixtureHooks.swift — 登录项档与首帧定格两个截图钩子的纯逻辑层
//
//  还原度审计（fidelity-guardian）补的缺口：登录项卡的空态、三类异常徽章、
//  不可核对脚注、读取失败横幅，以及整页"还在测"的首帧，此前都没有实机可达路径
//  （本机 17 项登录项只有 plistNotLoaded 一种异常自然出现；空态/骨架只活一帧抢不到）。
//
//  铁律（照 DeviceUsageFixture / TCCFixture 的口径）：
//  - 钩子只在环境变量存在且取值合法时生效，未设置时生产路径逐字节不变；
//  - 只顶替**展示数据**：不写盘、不注册登录项、不碰系统状态，也不落任何夹具文件；
//    合成条目全部 com.example.*，一眼可与真实数据区分；
//  - 含非法取值时整个钩子作废并写 stderr——半生效夹具 = 假通过。
//

import Foundation

// MARK: - 登录项档（MM_GUARDIAN_LOGIN_FIXTURE）

enum LoginFixtureStage: String, Equatable, Sendable {
    /// 合成清单 + 确定核对结果：覆盖三类异常徽章与孤儿脚注。
    case rows
    /// 空清单：走「未检测到登录项」空态档。
    case empty
    /// 合成清单 + 不可核对脚注（模拟 launchctl 不可用那一档）。
    case indeterminate
    /// 合成清单 + 读取失败横幅（scanErrors 非空，页面顶部黄条）。
    case scanerror
}

enum LoginItemFixture {
    struct Result: Equatable, Sendable {
        let stage: LoginFixtureStage?
        /// 被拒绝的原始值；非空时调用方必须写 stderr 并忽略整个钩子。
        let rejected: String?
    }

    static func parse(_ raw: String?) -> Result {
        guard let raw, !raw.isEmpty else { return Result(stage: nil, rejected: nil) }
        let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard let stage = LoginFixtureStage(rawValue: token) else {
            return Result(stage: nil, rejected: raw)
        }
        return Result(stage: stage, rejected: nil)
    }

    /// 合成清单：域、开关形态、fileKind 三个维度凑齐设计稿画过的每一种行。
    /// 用户域条目挂在真实家目录路径下（launchd 域判定与开关渲染需要真实前缀），
    /// 但文件名一律 com.example.*——本机这些路径上并没有文件，任何写尝试都会
    /// 在 LoginItemStore 的读取一步以 ENOENT 如实失败，不会落盘。
    static func items(home: String = NSHomeDirectory()) -> [LoginItem] {
        [
            // 启用、没在会话里加载 → plistNotLoaded 徽章 + 用户域开关
            LoginItem(name: "com.example.backup-agent",
                      path: "\(home)/Library/LaunchAgents/com.example.backup-agent.plist",
                      domain: .user, enabled: true, icon: "gear"),
            // 写着 Disabled=true 却仍在会话里 → disabledButLoaded 徽章
            LoginItem(name: "com.example.syncclient",
                      path: "\(home)/Library/LaunchAgents/com.example.syncclient.plist",
                      domain: .user, enabled: false, icon: "gear"),
            // 正常启用且已加载 → 无异常徽章
            LoginItem(name: "com.example.clipper",
                      path: "\(home)/Library/LaunchAgents/com.example.clipper.plist",
                      domain: .user, enabled: true, icon: "gear"),
            // 改名停用 → 「改名停用」徽章，不参与核对
            LoginItem(name: "com.example.telemetry",
                      path: "\(home)/Library/LaunchAgents/com.example.telemetry.disabled",
                      domain: .user, enabled: false, icon: "gear", fileKind: .renamedDisabled),
            // 系统 LaunchAgents（可核对域）→ 未加载徽章 + 只读
            LoginItem(name: "com.example.viewer",
                      path: "/Library/LaunchAgents/com.example.viewer.plist",
                      domain: .system, enabled: true, icon: "gearshape.2"),
            // 系统 LaunchDaemons（不核对域）→ 只有只读徽章
            LoginItem(name: "com.example.daemon",
                      path: "/Library/LaunchDaemons/com.example.daemon.plist",
                      domain: .system, enabled: true, icon: "gearshape.2"),
            // 旧版用户登录项兼容条目 → 不可写
            LoginItem(name: "Example OldApp",
                      path: "/Applications/Example OldApp.app",
                      domain: .userPreferences, enabled: true, icon: "person"),
        ]
    }

    /// 合成 launchd 会话：clipper/syncclient 在跑，另挂两个找不到 plist 的孤儿标签。
    static let snapshot = LaunchdSnapshot.labels([
        "com.example.clipper", "com.example.syncclient",
        "com.example.orphanhelper", "com.example.residuedaemon",
    ])

    /// rows/scanerror 两档的核对结果：走**真实判定函数** LoginItemAuditor.audit，
    /// 只把输入换成上面的合成清单与会话——测的是同一条判定管线，不是预制文案。
    static func audit(home: String = NSHomeDirectory()) -> LoginItemAudit {
        let items = items(home: home)
        let existing = Set(items.map(\.path))
        return LoginItemAuditor.audit(items: items, snapshot: snapshot) { path in
            // knownPlistPaths 用真实家目录拼路径，这里把同一 home 前缀的夹具项认下来。
            existing.contains(path)
        }
    }

    /// indeterminate 档：模拟 `launchctl list` 没跑成。reason 明示是夹具档，
    /// 免得截图被当成"这台机器上 launchctl 真的坏了"的证据。
    static let indeterminateAudit = LoginItemAudit(
        determinate: false,
        reason: "launchctl list 没有任何输出（夹具档：模拟 launchctl 不可用，非本机实况）"
    )

    /// scanerror 档：横幅文案照 LoginItemScanner 的真实拼接格式
    /// （"读取 <dir> 失败：<strerror>（errno N）"），并在句尾标明夹具值。
    static let scanErrorLines = [
        "读取 /Library/LaunchDaemons 失败：Operation not permitted（errno 1）（夹具值，模拟目录不可读）",
        "解析 /tmp/mmguardian-login-fixture/com.example.broken.plist 失败：plist 根对象不是字典（夹具值，模拟解析失败）",
    ]
}

// MARK: - 密钥与自启配置的改动时间卡（MM_GUARDIAN_ACTIVITY_FIXTURE；P11c 之前这一卡叫「系统活动」）

/// 这一卡此前没有任何钩子（fidelity-guardian G1）：空态与填充态都无法无头截图核对。
/// 这里补一个纯展示档位，口径与其它 fixture 一致：只顶替展示数据、不读 /tmp、不写盘、
/// 不 spawn 子进程；合成条目一眼可辨（com.example.* / 明确"夹具值"字样）。
enum GuardianActivityFixture {
    struct Result: Equatable, Sendable {
        /// nil = 钩子未设置；`.empty` = 显式空列表；`.rows` = 合成填充列表。
        let stage: Stage?
        let rejected: String?
    }

    enum Stage: String, Equatable, Sendable {
        case empty
        case rows
    }

    static func parse(_ raw: String?) -> Result {
        guard let raw, !raw.isEmpty else { return Result(stage: nil, rejected: nil) }
        let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard let stage = Stage(rawValue: token) else {
            return Result(stage: nil, rejected: raw)
        }
        return Result(stage: stage, rejected: nil)
    }

    /// rows 档：两族各一行（密钥目录 / LaunchAgent），用词与真机行同一形状
    /// （detail 是路径、time 是相对说法、tone 只有 caution|neutral），
    /// 但标识符全是 com.example.* 且标题带「（夹具值）」，一眼可辨。
    static func items() -> [ActivityItem] {
        [
            ActivityItem(title: "SSH 密钥目录（夹具值）",
                         detail: "/Users/example/.ssh",
                         time: "刚刚", icon: "key.fill", tone: .caution),
            ActivityItem(title: "com.example.backup-agent",
                         detail: "/Users/example/Library/LaunchAgents/com.example.backup-agent.plist",
                         time: "3 分钟前", icon: "gear", tone: .neutral),
        ]
    }
}

// MARK: - 首帧定格（MM_GUARDIAN_LOAD=hold）

enum GuardianLoadHook {
    struct Result: Equatable, Sendable {
        let holdInitialFrame: Bool
        let rejected: String?
    }

    /// 只认 `hold`：loadAll 直接返回，页面停在"测量中 + 骨架"的首帧，
    /// 让折叠线以上抢拍不到的加载态变成可截图状态。纯展示闸门：什么都不查、
    /// 什么都不写，刷新按钮同样被它挡在原帧。
    static func parse(_ raw: String?) -> Result {
        guard let raw, !raw.isEmpty else { return Result(holdInitialFrame: false, rejected: nil) }
        if raw.trimmingCharacters(in: .whitespaces).lowercased() == "hold" {
            return Result(holdInitialFrame: true, rejected: nil)
        }
        return Result(holdInitialFrame: false, rejected: raw)
    }
}

// MARK: - 卡片取景（MM_GUARDIAN_CARDS）

/// 页面上四张卡的稳定标识，顺序即页面顺序。
enum GuardianCard: String, Equatable, Sendable, CaseIterable {
    case occupancy
    case tcc
    case login
    case activity
}

/// 只影响**渲染哪几张卡**，不影响任何一张卡里读什么、怎么排。
///
/// 加它的理由是一条实测出来的取景死角：第 4 张卡（密钥与自启配置的改动时间，P11c 之前叫「系统活动」）
/// 在 760pt 窗口里永远在折叠线下，
/// 而窗口拉高这条路走不通——屏高 1080pt、`MM_WINDOW_SIZE` 请求 1400 会被 AppKit 夹到 ~1050，
/// 夹取后的真实尺寸由 `LaunchBehavior` 回读凭据（不是我们请求的那个值）。
/// 压矮上面几张卡也只是缓解：`MM_GUARDIAN_LOGIN_FIXTURE=rows` 那 7 行本身就有 ~500pt，
/// 换成 `empty` 又比 3 行还高——第 4 张卡到底进不进画面，取决于三张卡的随机高度，
/// 这种"这次拍到了"的证据下一次就未必拍到。所以这一档把不相关的卡直接摘掉。
///
/// 代价写在照片旁边：被摘卡的截图证明的是**单张卡自身的排版**，不证明卡片顺序、
/// 卡间距与整页留白——那几条判据仍由 03/04/05/06 负责。
enum GuardianCardFilter {
    struct Result: Equatable, Sendable {
        /// nil = 钩子未设置，四张卡全在；非 nil = 只渲染列出的卡（保持页面原有顺序）。
        let keep: [GuardianCard]?
        /// 被拒绝的原始值；非空时调用方必须写 stderr 并忽略整个钩子。
        let rejected: String?
    }

    /// `occupancy,tcc,login,activity` 的逗号子集，顺序无关、可去空白、大小写不敏感。
    /// 任一项非法就整体作废：半生效会让"这一屏只有一张卡"被读成"这一屏本该只有一张卡"。
    static func parse(_ raw: String?) -> Result {
        guard let raw, !raw.isEmpty else { return Result(keep: nil, rejected: nil) }
        let tokens = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard tokens.isEmpty == false else { return Result(keep: nil, rejected: raw) }
        var picked: Set<GuardianCard> = []
        for token in tokens {
            guard let card = GuardianCard(rawValue: token) else {
                return Result(keep: nil, rejected: raw)
            }
            picked.insert(card)
        }
        let ordered = GuardianCard.allCases.filter { picked.contains($0) }
        return Result(keep: ordered, rejected: nil)
    }
}
