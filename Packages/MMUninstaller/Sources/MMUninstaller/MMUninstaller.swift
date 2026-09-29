import SwiftUI
import Security
import Darwin
import MMCore
import MMFileScanner

public struct UninstallerModule: ModuleRegistrable {
    public var moduleID: String { "uninstaller" }
    public var moduleName: String { "应用卸载" }
    public var moduleIcon: String { "xmark.circle" }
    public var modulePriority: Int { 2 }

    public init() {}

    public func createView() -> AnyView {
        AnyView(UninstallerView())
    }
}

public struct UninstallerView: View {
    @State private var apps: [AppInfo] = []
    @State private var searchText = ""
    @State private var selectedAppID: String?
    @State private var isLoading = false
    @State private var showDeleteConfirm = false
    @State private var lastResult: TrashResult?
    @State private var showUndoToast = false

    private var selectedApp: AppInfo? {
        apps.first { $0.id == selectedAppID }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                appList
                    .frame(width: 320)
                Divider()
                detailPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadApps() }
        .alert("确认卸载", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                Task { await uninstallSelected() }
            }
        } message: {
            if let app = selectedApp {
                Text("将卸载 \(app.name) 及其 \(app.residuals.count) 个残留文件（共 \(formatByteSize(app.residualSize))）")
            }
        }
        .overlay(alignment: .bottom) {
            if showUndoToast, let result = lastResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("已卸载 \(result.successCount) 个文件")
                    Spacer()
                    Button("撤回") { Task { await undoUninstall() } }
                        .buttonStyle(.bordered).tint(.orange)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 12))
                .shadow(radius: 8)
                .padding(.horizontal)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring, value: showUndoToast)
    }

    private var header: some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text("应用卸载")
                    .font(.title2.bold())
                Text("彻底卸载应用程序，清理残留文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(apps.count) 个应用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { Task { await loadApps() } } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
        .padding()
    }

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索应用...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
            .padding(8)

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("扫描应用...").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(filteredApps, selection: Binding(
                    get: { selectedAppID },
                    set: { selectedAppID = $0 }
                )) { app in
                    AppListRow(app: app)
                        .tag(app.id)
                        .contextMenu {
                            Button {
                                revealInFinder(app.path)
                            } label: {
                                Label("打开所在文件夹", systemImage: "folder")
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
    }

    private var detailPanel: some View {
        Group {
            if let app = selectedApp {
                AppDetailView(app: app, onUninstall: { showDeleteConfirm = true })
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "app.dashed")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary.opacity(0.6))
                    VStack(spacing: 8) {
                        Text("未选择应用")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("从左侧列表选择一个应用\n查看详细信息和残留文件")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
            }
        }
    }

    private func loadApps() async {
        isLoading = true
        apps = []
        selectedAppID = nil

        // 视图本身是 MainActor 隔离的，文件系统遍历必须放到 detached 任务里，否则主线程会被卡住。
        let discovered = await Task.detached(priority: .userInitiated) {
            AppCatalog.discover()
        }.value

        apps = discovered
        isLoading = false

        let limit = max(2, AppCatalog.workerLimit)
        await withTaskGroup(of: AppInfo.self) { group in
            var next = 0
            while next < min(limit, discovered.count) {
                let app = discovered[next]
                next += 1
                group.addTask { await AppCatalog.measure(app: app) }
            }
            while let measured = await group.next() {
                await MainActor.run {
                    if let index = self.apps.firstIndex(where: { $0.id == measured.id }) {
                        self.apps[index] = measured
                    }
                }
                if next < discovered.count {
                    let app = discovered[next]
                    next += 1
                    group.addTask { await AppCatalog.measure(app: app) }
                }
            }
        }
    }

    private func uninstallSelected() async {
        guard let app = selectedApp else { return }
        var pathsToDelete = [app.path]
        for residual in app.residuals {
            pathsToDelete.append(residual.path)
        }

        let trashService = FileTrashService.shared
        let result = await trashService.moveToTrash(paths: pathsToDelete)
        lastResult = result
        showUndoToast = true
        apps.removeAll { $0.id == app.id }
        selectedAppID = nil

        try? await Task.sleep(for: .seconds(15))
        showUndoToast = false
    }

    private func undoUninstall() async {
        let trashService = FileTrashService.shared
        _ = await trashService.undoLastOperation()
        showUndoToast = false
        await loadApps()
    }

    /// 在访达中选中该路径（即打开其所在文件夹并高亮），只读操作，不改动任何文件。
    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// 大小尚未测出时显示占位文案，而不是误导性的 "0 字节"。
func formatByteSize(_ bytes: UInt64?) -> String {
    guard let bytes else { return "测量中" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

/// 应用清单的发现与度量。全部是非隔离的自由函数，避免 SwiftUI View 的 MainActor 隔离
/// 把文件遍历拽回主线程；真实大小交给 MMFileScanner 的统一遍历口径，保证和磁盘分析一致。
enum AppCatalog {

    static var workerLimit: Int { ProcessInfo.processInfo.activeProcessorCount }

    static func discover() -> [AppInfo] {
        let appDirs = ["/Applications", "\(NSHomeDirectory())/Applications"]
        var found: [AppInfo] = []

        for dir in appDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let path = "\(dir)/\(item)"
                let folderName = String(item.dropLast(4))
                let bundle = Bundle(path: path)
                let bundleID = bundle?.bundleIdentifier ?? bundleIDForApp(at: path)
                found.append(AppInfo(
                    id: path,
                    name: displayName(of: bundle, fallback: folderName),
                    path: path,
                    bundleID: bundleID,
                    version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                    build: bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                    minSystemVersion: bundle?.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "",
                    executable: bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "",
                    developer: developerName(of: path),
                    modificationDate: modificationDate(of: path),
                    size: nil,
                    fileCount: nil,
                    residuals: findResiduals(appName: folderName, bundleID: bundleID),
                    residualSize: nil
                ))
            }
        }

        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 回填真实占用：app 本体一次遍历，残留逐个遍历，失败时按 0 计而不是让整条记录消失。
    static func measure(app: AppInfo) async -> AppInfo {
        var measured = app
        let bundleMetrics = await DirectoryMetrics.measure(path: app.path)
        measured.size = bundleMetrics.size
        measured.fileCount = bundleMetrics.fileCount

        var residuals = app.residuals
        var total: UInt64 = 0
        for index in residuals.indices {
            let metrics = await DirectoryMetrics.measure(path: residuals[index].path)
            residuals[index].size = metrics.size
            total += metrics.size
        }
        measured.residuals = residuals
        measured.residualSize = total
        return measured
    }

    private static func displayName(of bundle: Bundle?, fallback: String) -> String {
        if let bundle {
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty { return name }
        }
        return fallback
    }

    /// 从代码签名的叶子证书取开发者名称，无需联网。
    /// 证书主题形如 "Developer ID Application: Google LLC (EQHXZ8M8AV)"，冒号后、括号前即开发者。
    private static func developerName(of path: String) -> String {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return "" }

        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any],
              let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first,
              let subject = SecCertificateCopySubjectSummary(leaf) as String? else { return "" }

        guard let colon = subject.firstIndex(of: ":") else { return subject }
        let remainder = subject[subject.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let paren = remainder.lastIndex(of: "(") else { return remainder }
        return String(remainder[remainder.startIndex..<paren]).trimmingCharacters(in: .whitespaces)
    }

    private static func modificationDate(of path: String) -> Date? {
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
            + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }
}

struct AppInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let bundleID: String
    let version: String
    let build: String
    let minSystemVersion: String
    let executable: String
    let developer: String
    let modificationDate: Date?
    var size: UInt64?
    var fileCount: Int?
    var residuals: [ResidualFile]
    var residualSize: UInt64?
}

struct ResidualFile: Identifiable, Sendable {
    var id: String { path }
    let path: String
    var size: UInt64?
}

func bundleIDForApp(at path: String) -> String {
    let plistPath = "\(path)/Contents/Info.plist"
    guard let data = FileManager.default.contents(atPath: plistPath),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let id = plist["CFBundleIdentifier"] as? String else { return "" }
    return id
}

func findResiduals(appName: String, bundleID: String) -> [ResidualFile] {
    let home = NSHomeDirectory()
    var candidates: [String] = []

    if !bundleID.isEmpty {
        candidates.append(contentsOf: [
            "\(home)/Library/Caches/\(bundleID)",
            "\(home)/Library/Preferences/\(bundleID).plist",
            "\(home)/Library/Application Support/\(bundleID)",
            "\(home)/Library/Saved Application State/\(bundleID).savedState",
            "\(home)/Library/Logs/\(bundleID)",
            "\(home)/Library/WebKit/\(bundleID)",
            "\(home)/Library/HTTPStorages/\(bundleID)",
        ])
    }

    candidates.append(contentsOf: [
        "\(home)/Library/Caches/\(appName)",
        "\(home)/Library/Application Support/\(appName)",
        "\(home)/Library/Preferences/\(appName).plist",
        "\(home)/Library/Logs/\(appName)",
        "\(home)/Library/Saved Application State/com.\(appName.lowercased()).savedState",
    ])

    var results: [ResidualFile] = []
    var seenPaths = Set<String>()
    for path in candidates {
        guard !seenPaths.contains(path),
              FileManager.default.fileExists(atPath: path) else { continue }
        seenPaths.insert(path)
        results.append(ResidualFile(path: path, size: nil))
    }
    return results
}

struct AppListRow: View {
    let app: AppInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(app.version.isEmpty ? "未知版本" : "版本 \(app.version)")
                    Text(formatByteSize(app.size))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if app.residuals.count > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(app.residuals.count) 个残留")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Text(formatByteSize(app.residualSize))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AppDetailView: View {
    let app: AppInfo
    let onUninstall: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.title2.bold())
                        Text(appSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        revealInFinder(app.path)
                    } label: {
                        Label("打开所在文件夹", systemImage: "folder")
                    }
                }

                Divider()

                Text("基本信息")
                    .font(.headline)
                VStack(spacing: 0) {
                    infoRow(title: "包名", value: app.bundleID)
                    infoRow(title: "版本", value: app.version)
                    infoRow(title: "构建", value: app.build)
                    infoRow(title: "开发者", value: app.developer)
                    infoRow(title: "最低系统", value: app.minSystemVersion)
                    infoRow(title: "可执行文件", value: app.executable)
                    infoRow(title: "修改时间", value: formattedDate(app.modificationDate))
                    infoRow(title: "所在文件夹", value: (app.path as NSString).deletingLastPathComponent)
                }
                .textSelection(.enabled)

                Divider()

                Text("空间占用")
                    .font(.headline)
                HStack(spacing: 24) {
                    statItem(title: "应用大小", value: formatByteSize(app.size))
                    statItem(title: "包含文件", value: app.fileCount.map { "\($0) 个" } ?? "测量中")
                    statItem(title: "残留文件", value: "\(app.residuals.count) 个")
                    statItem(title: "残留大小", value: formatByteSize(app.residualSize))
                }

                if !app.residuals.isEmpty {
                    Divider()
                    Text("残留文件")
                        .font(.headline)
                    ForEach(app.residuals) { residual in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((residual.path as NSString).lastPathComponent)
                                    .font(.body)
                                Text(residual.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(formatByteSize(residual.size))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                revealInFinder(residual.path)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("在访达中显示")
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button(role: .destructive) {
                    onUninstall()
                } label: {
                    Label("卸载应用", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    private var appSubtitle: String {
        var parts: [String] = []
        if !app.version.isEmpty { parts.append("版本 \(app.version)") }
        if let size = app.size { parts.append(formatByteSize(size)) }
        parts.append(app.path)
        return parts.joined(separator: " · ")
    }

    /// 值缺失时保留行占位，避免左侧标签参差不齐、也避免显示空白。
    @ViewBuilder
    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium))
        }
    }

    /// 在访达中选中该路径（即打开其所在文件夹并高亮），只读操作，不改动任何文件。
    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
