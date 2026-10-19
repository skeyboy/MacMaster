import Foundation

// MARK: - 取证钩子的取值解析
//
// 这一层存在的理由只有一条：钩子写错了不会让界面报错，只会让照片安静地停在另一档上，
// 然后那张"看上去没问题"的截图被登记成"某一档已核对"——这是取证里最贵的一类错误（假通过）。
// 所以规则是：**对不上任何档就必须留痕**，而且留痕文案由纯函数生成，能被单测钉住。
//
// 约定（与 hook-ledger.md 一致）：
// - 未设置 / 空串 = 按未设置处理，生产路径，不留痕；
// - 有值但对不上 = 回落默认档 + 写 stderr 一行，说明实际落在哪；
// - 比较前统一 trim + 转小写，档位名一律小写。

/// 单值档位钩子（`MM_OPEN_TAB`、`MM_SETTINGS_TAB`、`MM_UNINSTALL_PANE`…）的档位协议。
public protocol MMHookKeyed: CaseIterable, Sendable {
    /// env 里写这个名字就命中该档；小写、不含空格。
    var hookKey: String { get }
}

public enum MMHookValue {
    public struct Resolution<Case: MMHookKeyed>: Sendable {
        public let selected: Case
        /// 非 nil = env 给了值但对不上任何档，`selected` 是回落的默认档。
        public let rejected: String?
        /// 由档位表现算，所以文档与实现不会各说一套。
        public let accepts: String

        /// 留痕文案；未设置或命中时返回 nil。
        public func note(key: String) -> String? {
            guard let rejected else { return nil }
            return "\(key) 含非法取值（\(rejected)），只接受 \(accepts)，已回落 \(selected.hookKey) 档"
        }
    }

    /// 纯解析：不读环境变量、不落 stderr，便于单测。
    public static func resolve<Case: MMHookKeyed>(raw: String?, fallback: Case,
                                                  cases: [Case]) -> Resolution<Case> {
        let accepts = cases.map(\.hookKey).joined(separator: "|")
        let token = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty else {
            return Resolution(selected: fallback, rejected: nil, accepts: accepts)
        }
        guard let match = cases.first(where: { $0.hookKey == token }) else {
            // 报原文而不是报 token：核对的人要能在日志里认出自己写的那几个字母。
            return Resolution(selected: fallback, rejected: raw ?? "", accepts: accepts)
        }
        return Resolution(selected: match, rejected: nil, accepts: accepts)
    }

    /// 读 env + 解析 + 留痕，返回档位。视图的 `@State` 初始化直接用它。
    public static func selected<Case: MMHookKeyed>(
        key: String,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fallback: Case,
        cases: [Case]? = nil
    ) -> Case {
        let resolution = resolve(raw: env[key], fallback: fallback, cases: cases ?? Array(Case.allCases))
        if let note = resolution.note(key: key) { emit(note) }
        return resolution.selected
    }

    // MARK: 数字档

    public struct NumberResolution: Sendable {
        public let value: Int
        public let rejected: String?
        public let accepts: String

        public func note(key: String) -> String? {
            guard let rejected else { return nil }
            return "\(key) 含非法取值（\(rejected)），只接受 \(accepts)，已回落 \(value)"
        }
    }

    public static func resolveInt(raw: String?, fallback: Int,
                                  bounds: ClosedRange<Int>) -> NumberResolution {
        let accepts = "\(bounds.lowerBound)~\(bounds.upperBound)"
        let token = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return NumberResolution(value: fallback, rejected: nil, accepts: accepts)
        }
        guard let parsed = Int(token), bounds.contains(parsed) else {
            return NumberResolution(value: fallback, rejected: raw ?? "", accepts: accepts)
        }
        return NumberResolution(value: parsed, rejected: nil, accepts: accepts)
    }

    // MARK: 单 token 开关（`== "hold"` 那一类）

    public struct FlagResolution: Sendable {
        public let on: Bool
        public let rejected: String?

        public func note(key: String, token: String) -> String? {
            guard let rejected else { return nil }
            return "\(key) 含非法取值（\(rejected)），只接受 \(token)，钩子已忽略"
        }
    }

    public static func resolveFlag(raw: String?, token: String) -> FlagResolution {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return FlagResolution(on: false, rejected: nil) }
        guard trimmed == token.lowercased() else {
            return FlagResolution(on: false, rejected: raw ?? "")
        }
        return FlagResolution(on: true, rejected: nil)
    }

    /// 读 env + 解析 + 留痕，返回数值。视图与 `.task` 里用它，纯解析留给单测。
    public static func int(key: String,
                           env: [String: String] = ProcessInfo.processInfo.environment,
                           fallback: Int, bounds: ClosedRange<Int>) -> Int {
        let resolution = resolveInt(raw: env[key], fallback: fallback, bounds: bounds)
        if let note = resolution.note(key: key) { emit(note) }
        return resolution.value
    }

    /// 读 env + 解析 + 留痕，返回开关。
    public static func flag(key: String, token: String,
                            env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let resolution = resolveFlag(raw: env[key], token: token)
        if let note = resolution.note(key: key, token: token) { emit(note) }
        return resolution.on
    }

    /// 留痕的唯一出口：stderr 一行。取证脚本都从 stderr 收日志，写别处等于没写。
    public static func emit(_ text: String) {
        if let data = (text + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

// MARK: - 启动钩子（外观 / 窗口尺寸）

/// `MM_APPEARANCE` 的两档。不带 AppKit 类型：这一层要能在单测里跑，
/// `NSAppearance.Name` 的映射留在壳层那一行做。
public enum MMColorScheme: String, Sendable, CaseIterable {
    case light
    case dark
}

public struct MMWindowSizeRequest: Sendable, Equatable {
    public let width: Double
    public let height: Double

    public var text: String { "\(Int(width))x\(Int(height))" }
}

public enum MMLaunchHook {
    /// `light|aqua` → 浅色，`dark|darkaqua` → 深色；其余一律视为非法。
    public static func resolveAppearance(raw: String?) -> MMColorScheme? {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "light", "aqua": return .light
        case "dark", "darkaqua": return .dark
        default: return nil
        }
    }

    /// `900x600` 之类；下限是防呆（写成 1x1 只会拍到一块什么都没有的画布）。
    public static func resolveWindowSize(raw: String?, minWidth: Double = 320,
                                         minHeight: Double = 200) -> MMWindowSizeRequest? {
        let token = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = token.split(separator: "x").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
              width >= minWidth, height >= minHeight else { return nil }
        return MMWindowSizeRequest(width: width, height: height)
    }

    public struct LanguageResolution: Sendable, Equatable {
        /// nil = env 没给值，按当前档位（UserDefaults）处理。
        public let selected: Localization.Language?
        public let rejected: String?
    }

    /// `MM_LANGUAGE`：`zh|zh-hans` → 中文，`en` → 英文；其余视为非法，交回调用方留痕。
    /// `zh-CN`/`zh-Hans-CN` 这类带地区的写法不吃：双语取证脚本只有两档，
    /// 吃下别名等于允许同一张照片有两种读法，核对的人无法从日志判断实际落在哪。
    public static func resolveLanguage(raw: String?) -> LanguageResolution {
        let token = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch token {
        case "": return LanguageResolution(selected: nil, rejected: nil)
        case "zh", "zh-hans": return LanguageResolution(selected: .chinese, rejected: nil)
        case "en": return LanguageResolution(selected: .english, rejected: nil)
        default: return LanguageResolution(selected: nil, rejected: raw ?? "")
        }
    }
}
