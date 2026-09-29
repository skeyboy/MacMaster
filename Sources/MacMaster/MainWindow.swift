import SwiftUI
import MMCore
import MMUI

struct MainWindow: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            DetailView()
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .onAppear {
            LaunchMinimizeHandler.applyOnceIfEnabled(settings: settings)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // App Header
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ThemeColor.primary, ThemeColor.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("MacMaster")
                    .font(.title3.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Module List
            List(selection: $appState.selectedModuleID) {
                ForEach(moduleRegistry.modules) { module in
                    NavigationLink(value: module.id) {
                        Label(module.name, systemImage: module.iconName)
                            .font(.body)
                    }
                    .tag(module.id)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Settings
            Button {
                appState.showSettings = true
            } label: {
                Label("设置", systemImage: "gear")
                    .font(.body)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    @EnvironmentObject var moduleRegistry: ModuleRegistry
    @EnvironmentObject var appState: AppState

    // 已访问过的模块保持常驻视图树，避免 SwiftUI 回收其 @State
    @State private var visitedModuleIDs: Set<String> = []

    var body: some View {
        content
            .onAppear {
                if let id = appState.selectedModuleID { visitedModuleIDs.insert(id) }
            }
            .onChange(of: appState.selectedModuleID) { _, newID in
                if let id = newID { visitedModuleIDs.insert(id) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if visitedModuleIDs.isEmpty {
            DashboardView()
        } else {
            ZStack {
                ForEach(moduleRegistry.modules) { module in
                    if visitedModuleIDs.contains(module.id) {
                        let isActive = module.id == appState.selectedModuleID
                        module.viewBuilder()
                            .opacity(isActive ? 1 : 0)
                            .allowsHitTesting(isActive)
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // System Overview
                HStack(spacing: 20) {
                    CircularProgressGauge(value: 23, label: "CPU Usage", color: ThemeColor.primary)
                    CircularProgressGauge(value: 45, label: "Memory", color: ThemeColor.accent)
                    CircularProgressGauge(value: 49, label: "Disk", color: ThemeColor.success)
                }
                .padding(.top, 24)

                // Quick Actions
                HStack(spacing: 16) {
                    CategoryCard(title: "Quick Clean", subtitle: "8.2 GB available") {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(ThemeColor.accent)
                            Text("Scan and clean system cache")
                                .font(.subheadline)
                                .foregroundStyle(ThemeColor.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    CategoryCard(title: "Recent Activity", subtitle: nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Cleaned 2.3 GB yesterday", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(ThemeColor.success)
                            Label("Uninstalled 1 app", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(ThemeColor.success)
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer()
            }
            .padding(24)
        }
        .background(ThemeColor.background)
    }
}
