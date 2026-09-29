import SwiftUI

/// 系统清理模块的三页容器：缓存清理（原有能力）/ 用户文件夹（Task 1）/ 系统分析（Task 2）。
/// 只有当前选中的页会被实例化，其余页不会触发扫描。
struct CleanerContainerView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case cache = "缓存清理"
        case userFolders = "用户文件夹"
        case system = "系统分析"

        var id: String { rawValue }
    }

    @State private var tab: Tab = .cache

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("系统清理")
                    .font(.headline)
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()

            switch tab {
            case .cache:
                CleanerView()
            case .userFolders:
                UserFolderCleanView()
            case .system:
                SystemAnalysisView()
            }
        }
    }
}
