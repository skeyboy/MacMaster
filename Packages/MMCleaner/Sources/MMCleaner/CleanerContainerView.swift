import SwiftUI
import MMCore
import MMUI

/// 系统清理模块的四页容器：缓存清理 / 用户文件夹 / 系统分析 / 开发产物。
/// 只有当前选中的页会被实例化，其余页不会触发扫描。
struct CleanerContainerView: View {
    enum Tab: String, CaseIterable, Identifiable, MMHookKeyed {
        case cache = "缓存清理"
        case userFolders = "用户文件夹"
        case system = "系统分析"
        case dev = "开发产物"

        var id: String { rawValue }

        /// MM_OPEN_TAB=cache|folders|system|dev：只用于逐屏截图核对设计稿，
        /// 正常启动不会带这个变量。
        var hookKey: String {
            switch self {
            case .cache: "cache"
            case .userFolders: "folders"
            case .system: "system"
            case .dev: "dev"
            }
        }
    }

    /// 值写错时由 `MMHookValue` 落回默认档并往 stderr 写一行——
    /// 不然那张照片会被登记成"system 档已核对"，而它其实是缓存页。
    @State private var tab: Tab = MMHookValue.selected(key: "MM_OPEN_TAB", fallback: .cache)

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .cache:
                CleanerView()
            case .userFolders:
                UserFolderCleanView()
            case .system:
                SystemAnalysisView()
            case .dev:
                DevArtifactView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: MMGap.sm) {
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            .frame(height: 30)
            .background(MMColor.contentBackground)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}
