import Foundation

/// 风险三档是产品语义，不是样式，所以放在 MMCore 而不是 UI 包：
/// 扫描器给数据打级、页面按级决定默认勾选与是否提供删除入口，
/// 两边必须引用同一个定义，否则会出现"扫描器认为安全、界面显示谨慎"。
///
/// 语义固定，不可按页面重定义：safe=可安全清理，caution=谨慎（默认不勾选），
/// readOnly=只展示不提供删除入口。
public enum MMRisk: String, CaseIterable, Sendable {
    case safe
    case caution
    case readOnly

    public var label: String {
        switch self {
        case .safe: "安全"
        case .caution: "谨慎"
        case .readOnly: "只读"
        }
    }

    public var groupTitle: String {
        switch self {
        case .safe: "可安全清理"
        case .caution: "需谨慎"
        case .readOnly: "只读 · 不会修改"
        }
    }

    public var groupNote: String {
        switch self {
        case .safe: "删除后可由应用或系统重建"
        case .caution: "可能包含登录态或未同步数据，默认不勾选"
        case .readOnly: "仅供查看，MacMaster 不提供删除入口"
        }
    }

    /// 默认勾选状态是风险传达的主手段，比弹窗确认更有效也更不打扰。
    public var isDefaultSelected: Bool { self == .safe }

    public var allowsDeletion: Bool { self != .readOnly }
}
