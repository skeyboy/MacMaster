//
//  TCCAuthorization.swift — 「哪些应用拿到了敏感权限」(P3.2) 的纯逻辑层
//
//  本机可读性实测与降级口径见 docs/analysis/guardian-tcc.md：
//  这台机器上两个 TCC.db 都打不开（用户级 ENOENT 被系统隐藏、系统级 EPERM/rc=23），
//  所以"读不到"是常态档，不是边角情况——状态机把它当第一等公民设计。
//
//  测量诚实口径（项目法则 1）：
//  - 读不到 ≠ 没有授权。两库都打不开时视图状态是 .unreadable，UI 不画列表；
//    "查到了 0 行"只有确认库真被读到后才允许出现（.emptyRead）。
//  - auth_value 只映射 0/2/3/4（拒绝/允许/有限/已禁用），1 及一切表外值都是
//    "未知值 (N)"档——绝不猜成"允许"。
//  - client 解析不到应用名就显示原始串，不编名字（法则 2）。
//
//  真正 sqlite3_open_v2 的一层在 TCCProbe.swift，本文件不碰任何系统调用。
//

import Foundation

// MARK: - 数据来源

enum TCCSource: String, CaseIterable, Sendable {
    case user
    case system

    var displayName: String {
        switch self {
        case .user: "用户级"
        case .system: "系统级"
        }
    }
}

/// 一个库这次的可读性结论。reason 是错误原文（errno/strerror/sqlite 码），
/// 必须原样带到 UI，不许只留"未知错误"。
enum TCCSourceOutcome: Equatable, Sendable {
    /// 库打开且查询成功。rowCount==0 也是有信息量的确定结论。
    case readable(rowCount: Int)
    /// 打不开/查不动 —— 与"0 行"是两种承诺。
    case unreadable(reason: String)
}

// MARK: - 行数据（探针输出 = 纯数据）

struct TCCTranslation: Equatable, Sendable {
    let service: String        // kTCCServiceMicrophone …
    let client: String         // bundle id（clientType 0）或路径（clientType 1）
    let clientType: Int
    let authValue: Int
    let lastModified: Date?
    let source: TCCSource
    /// 探针解析出的应用名；nil = 没解析到，显示层必须回退到原始 client。
    let resolvedAppName: String?
}

// MARK: - auth_value 判定表

enum TCCAuthStatus: Hashable, Sendable {
    case denied
    case allowed
    case limited
    case disabled
    /// 不在 0/2/3/4 表内的一切值。徽章如实写"未知值 (N)"，表达不了任何"允许"含义。
    case unknown(value: Int)

    static func from(authValue: Int) -> TCCAuthStatus {
        switch authValue {
        case 0: .denied
        case 2: .allowed
        case 3: .limited
        case 4: .disabled
        default: .unknown(value: authValue)
        }
    }
}

// MARK: - 服务名映射（未知服务显示原始串，不编名字）

enum TCCServiceCatalog {
    /// 探针 WHERE IN 的清单与本表的键必须一致（那边有注释指向这里）。
    static let trackedServices: [String] = [
        "kTCCServiceMicrophone",
        "kTCCServiceCamera",
        "kTCCServiceScreenCapture",
        "kTCCServiceAccessibility",
        "kTCCServiceListenEvent",
    ]

    private static let names: [String: String] = [
        "kTCCServiceMicrophone": "麦克风",
        "kTCCServiceCamera": "摄像头",
        "kTCCServiceScreenCapture": "屏幕录制",
        "kTCCServiceAccessibility": "辅助功能",
        "kTCCServiceListenEvent": "键盘监听",
    ]

    private static let icons: [String: String] = [
        "kTCCServiceMicrophone": "mic.fill",
        "kTCCServiceCamera": "camera.fill",
        "kTCCServiceScreenCapture": "display",
        "kTCCServiceAccessibility": "accessibility",
        "kTCCServiceListenEvent": "keyboard",
    ]

    static func displayName(_ service: String) -> String { names[service] ?? service }
    static func systemImage(_ service: String) -> String { icons[service] ?? "questionmark.square.dashed" }

    /// tracked 清单内的排序权重；清单外的服务排最后（理论上探针不会带进来，防御性保留）。
    static func sortRank(_ service: String) -> Int {
        trackedServices.firstIndex(of: service) ?? trackedServices.count
    }
}

// MARK: - 展示行（判定 + 清洗后的产物）

struct TCCDisplayRow: Identifiable, Equatable, Sendable {
    let id: String     // source|service|client —— 三列拼主键，两库同 client 不互相顶掉
    let appName: String
    let client: String
    let clientType: Int
    let service: String
    let serviceName: String
    let serviceImage: String
    let status: TCCAuthStatus
    let lastModified: Date?
    let source: TCCSource

    init(_ row: TCCTranslation) {
        self.id = "\(row.source.rawValue)|\(row.service)|\(row.client)"
        // 法则 2：解析不到就显示原始 client 串，别编一个名字。
        self.appName = row.resolvedAppName ?? row.client
        self.client = row.client
        self.clientType = row.clientType
        self.service = row.service
        self.serviceName = TCCServiceCatalog.displayName(row.service)
        self.serviceImage = TCCServiceCatalog.systemImage(row.service)
        self.status = TCCAuthStatus.from(authValue: row.authValue)
        self.lastModified = row.lastModified
        self.source = row.source
    }
}

// MARK: - 卡片视图状态机（三档 + 测量中）

enum TCCViewerState: Equatable, Sendable {
    /// 两个库都没打开。detail 逐库带错误原文——这一档绝不允许塌缩成空列表。
    case unreadable(detail: String)
    /// 至少一个库可读，且有行；unreadableNote 点名没读到的库（清单可能不完整）。
    case partial(rows: [TCCDisplayRow], unreadableNote: String)
    /// 可读的库都查了、0 行，且没有任何库没读到 —— 才允许说"没有授权记录"。
    case emptyRead
    /// 全部库可读且有行。
    case loaded(rows: [TCCDisplayRow])
}

enum TCCViewer {

    static func build(outcomes: [TCCSource: TCCSourceOutcome], rows: [TCCTranslation]) -> TCCViewerState {
        let unreadable = TCCSource.allCases.compactMap { source -> String? in
            guard case .unreadable(let reason)? = outcomes[source] else { return nil }
            return "\(source.displayName)库读不到：\(reason)"
        }
        let cleaned = cleanedRows(rows)

        if outcomes.isEmpty {
            // 探针没给出任何结论 = 什么都没测到，与"测到两个都读不到"同档处理。
            return .unreadable(detail: "未获得任何数据库的读取结果")
        }
        if unreadable.count == outcomes.count {
            return .unreadable(detail: unreadable.joined(separator: "；"))
        }
        if cleaned.isEmpty {
            // 有库没读到就不许说"0 行 = 没有授权"：降成 partial（空列表 + 不完整警示）。
            if unreadable.isEmpty { return .emptyRead }
            return .partial(rows: [], unreadableNote: unreadable.joined(separator: "；") + "——清单可能不完整")
        }
        let note = unreadable.isEmpty ? "" : unreadable.joined(separator: "；") + "——清单可能不完整"
        return note.isEmpty
            ? .loaded(rows: cleaned)
            : .partial(rows: cleaned, unreadableNote: note)
    }

    /// 清洗：按 (source, service, client) 去重 + 稳定排序（服务、再状态、再名称）。
    static func cleanedRows(_ rows: [TCCTranslation]) -> [TCCDisplayRow] {
        var seen = Set<String>()
        var kept: [TCCDisplayRow] = []
        for row in rows {
            // client 为空的行没有来源可指认，整条丢弃（sqlite 理论上不产生，防御）。
            guard !row.client.isEmpty else { continue }
            let display = TCCDisplayRow(row)
            guard seen.insert(display.id).inserted else { continue }
            kept.append(display)
        }
        return kept.sorted {
            let lhsRank = TCCServiceCatalog.sortRank($0.service)
            let rhsRank = TCCServiceCatalog.sortRank($1.service)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if $0.service != $1.service { return $0.service < $1.service }
            if statusRank($0.status) != statusRank($1.status) { return statusRank($0.status) < statusRank($1.status) }
            if $0.appName != $1.appName { return $0.appName < $1.appName }
            return $0.id < $1.id
        }
    }

    /// 用户最该先看到的排前：允许/有限 → 未知 → 已禁用 → 拒绝。
    private static func statusRank(_ status: TCCAuthStatus) -> Int {
        switch status {
        case .allowed: 0
        case .limited: 1
        case .unknown: 2
        case .disabled: 3
        case .denied: 4
        }
    }
}

// MARK: - 文案映射（用户可见口径的唯一来源）

struct TCCStatusCopy: Equatable, Sendable {
    let badge: String
    /// true = 该档表达"确实拿到了权限"，UI 才允许用信息蓝；其余一律中性灰。
    let grantsAccess: Bool
}

enum TCCCopyTable {
    static func copy(for status: TCCAuthStatus) -> TCCStatusCopy {
        switch status {
        case .denied: TCCStatusCopy(badge: "已拒绝", grantsAccess: false)
        case .allowed: TCCStatusCopy(badge: "已允许", grantsAccess: true)
        case .limited: TCCStatusCopy(badge: "部分允许", grantsAccess: true)
        case .disabled: TCCStatusCopy(badge: "已禁用", grantsAccess: false)
        // 未知值：徽章里带原值，文案不承诺任何方向。1 在旧系统曾是"允许"，
        // 但我们不按旧表猜（映射依据与理由见 docs/analysis/guardian-tcc.md 第 2 节）。
        case .unknown(let value): TCCStatusCopy(badge: "未知值 (\(value))", grantsAccess: false)
        }
    }

    /// "读不到"档的固定标题：把原因直说在标题里，而不是藏在详情里。
    static let unreadableTitle = "读不到 · 需要完全磁盘访问"
    static let unreadableGuide = "本卡片只读查询 TCC 数据库，绝不写入、绝不申请提权。" +
        "给 MacMaster 授予「完全磁盘访问」后刷新可尝试读取用户级库；系统级库另受系统保护，可能始终读不到。"

    /// auth_value 语义脚注（口径小字，与判定表同一来源）。
    static let valueLegend = "状态取自 TCC 数据库 auth_value：0 拒绝 / 2 允许 / 3 部分允许 / 4 已禁用；表外值如实标「未知值」，不当成允许。"
}

// MARK: - 截图夹具钩子（MM_TCC_FIXTURE）

/// 仅供无头截图逐档核对渲染（照 MM_GUARDIAN_FIXTURE 的写法）：
/// 取值只接受 `rows|unreadable|empty` 的单值组合；含任何非法项时整体作废并写 stderr。
/// `rows` 注入的全是 com.example.* 合成行——与真实数据一眼可分，不会伪造"你机器上的授权"。
enum TCCFixture {
    struct Result: Equatable, Sendable {
        let state: TCCViewerState?
        /// 被拒绝的原始 token；非空时调用方必须往 stderr 写一句说明并忽略整个钩子。
        let rejected: [String]
    }

    static func parse(_ raw: String) -> Result {
        let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
        switch token {
        case "rows": return Result(state: .loaded(rows: TCCFixture.sampleDisplayRows), rejected: [])
        case "unreadable": return Result(state: .unreadable(detail: "夹具：模拟两库均读不到（open 被拒：Operation not permitted（EPERM）；sqlite rc=23 authorization denied）"), rejected: [])
        case "empty": return Result(state: .emptyRead, rejected: [])
        default:
            return Result(state: nil, rejected: [raw])
        }
    }

    /// 每档状态一个样例行：允许/有限/未知值/禁用/拒绝 + 解析失败回退原始 client。
    static let sampleRows: [TCCTranslation] = [
        TCCTranslation(service: "kTCCServiceMicrophone", client: "com.example.denoise", clientType: 0,
                       authValue: 2, lastModified: Date(timeIntervalSince1970: 1_759_000_000),
                       source: .user, resolvedAppName: "Example Denoise"),
        TCCTranslation(service: "kTCCServiceCamera", client: "com.example.classroom", clientType: 0,
                       authValue: 3, lastModified: Date(timeIntervalSince1970: 1_758_900_000),
                       source: .user, resolvedAppName: "Example Classroom"),
        TCCTranslation(service: "kTCCServiceScreenCapture", client: "com.example.recorder", clientType: 0,
                       authValue: 1, lastModified: nil,
                       source: .system, resolvedAppName: "Example Recorder"),
        TCCTranslation(service: "kTCCServiceAccessibility", client: "com.example.autoclicker", clientType: 0,
                       authValue: 4, lastModified: Date(timeIntervalSince1970: 1_758_800_000),
                       source: .system, resolvedAppName: "Example AutoClicker"),
        TCCTranslation(service: "kTCCServiceListenEvent", client: "com.example.keycounter", clientType: 0,
                       authValue: 0, lastModified: Date(timeIntervalSince1970: 1_758_700_000),
                       source: .system, resolvedAppName: "Example KeyCounter"),
        // 解析不到名字的条目：必须原样显示 client 路径，不编应用名。
        TCCTranslation(service: "kTCCServiceMicrophone", client: "/opt/example/bin/ghost", clientType: 1,
                       authValue: 2, lastModified: nil, source: .user, resolvedAppName: nil),
    ]

    static var sampleDisplayRows: [TCCDisplayRow] { TCCViewer.cleanedRows(sampleRows) }
}
