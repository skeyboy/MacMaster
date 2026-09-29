import Foundation

// MARK: - 沙盒容器反查
//
// 容器目录名经常不是包名（历史版本里是 UUID、是旧 bundleID、或者带后缀的 helper 标识），
// 所以"按名字猜"必须让位于"读元数据反查"：每个容器目录里都有
// `.com.apple.containermanagerd.metadata.plist`，它的 `MCMMetadataIdentifier`
// 才是"这个容器属于哪个 bundle"的权威答案。
//
// 容器里有用户文档（Data/Documents、Data/Library/Application Support），
// 因此**整个容器一律标为谨慎且默认不勾选**；只有其中可重建的缓存子目录默认可选。

enum ContainerScanner {
    /// 容器元数据文件名（以 `.` 开头，普通枚举会被隐藏文件规则跳过，这里显式读取）。
    static let metadataFileName = ".com.apple.containermanagerd.metadata.plist"
    /// 元数据里的主标识键；偏好文件反查也共用这个键名。
    static let metadataIdentifierKey = "MCMMetadataIdentifier"

    static func scan(context: ResidualScanner.ResidualScanContext, collector: inout ResidualCollector) {
        for (library, entries) in ResidualCatalog.libraryRoots(
            home: context.options.home, systemRoot: context.options.systemRoot
        ) {
            for entry in entries
            where entry.scope == .containers && context.sensitivity.rank >= entry.minSensitivity.rank {
                scan(directory: "\(library)/\(entry.subpath)", entry: entry,
                     context: context, collector: &collector)
            }
        }
    }

    private static func scan(directory: String,
                             entry: ResidualCatalog.Entry,
                             context: ResidualScanner.ResidualScanContext,
                             collector: inout ResidualCollector) {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }

        // 容器根自己就可能是包名形态（少见），先按通用规则过一次名称。
        if let reason = context.matcher.reason(for: root, bundleID: context.bundleID,
                                              allowContains: context.sensitivity.rank > 0) {
            collector.add(url: root, category: entry.category, reason: reason, riskOverride: .caution)
        }

        let children: [URL]
        do {
            // 隐藏文件不能跳：容器元数据本身就是点文件。
            children = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []
            )
        } catch {
            collector.addInaccessible(root.path)
            return
        }

        for child in children where ResidualScanner.isDirectory(child) {
            guard ownsContainer(child: child, context: context, entry: entry) else { continue }
            // 整个容器：谨慎、默认不勾选，用户必须自己确认里面没有需要保留的文档。
            // 类别跟着清单走：Group Containers 要标成共享容器，否则 UI 上
            // "可能被其他应用共用"这句提示就丢了。
            collector.add(url: child, category: entry.category,
                          reason: containerReason(child, context: context),
                          riskOverride: .caution)
            // 其中的缓存：可重建，默认可选。父目录不在删除根里就不重复计数。
            addRebuildableSubpaths(of: child, context: context, collector: &collector)
        }
    }

    /// 归属判定：元数据标识优先，其次才是目录名与包名的对应关系。
    private static func ownsContainer(child: URL,
                                      context: ResidualScanner.ResidualScanContext,
                                      entry: ResidualCatalog.Entry) -> Bool {
        guard context.bundleID.isEmpty == false else {
            // 没有包名就没有证据，宁可不报也不按目录名乱收。
            return false
        }
        if let identifier = metadataIdentifier(in: child) {
            return identifiersMatch(identifier, bundleID: context.bundleID)
        }
        // 元数据缺失（外来/损坏的容器）时退回名称匹配：Group Containers 的目录名
        // 本身就是 app group 标识，通常内嵌包名。
        // 必须走 identifiersMatch：把 normalize 后的 `group-com-example-myapp` 去
        // contains 一个带点的 `com.example.myapp` 永远为假，而裸 contains 又会让
        // `com.examp` 这种半截包名命中别人。
        if entry.category == .groupContainer {
            return identifiersMatch(child.lastPathComponent, bundleID: context.bundleID)
        }
        return context.matcher.matches(fileURL: child, bundleID: context.bundleID)
    }

    private static func containerReason(_ child: URL,
                                        context: ResidualScanner.ResidualScanContext) -> String {
        if let identifier = metadataIdentifier(in: child) {
            return "容器元数据标识 \(identifier)"
        }
        return context.matcher.reason(for: child, bundleID: context.bundleID, allowContains: true)
            ?? "容器目录名对应包名"
    }

    /// 只有可重建的子目录默认可选；Documents / Application Support 这些绝不自动勾。
    private static func addRebuildableSubpaths(of container: URL,
                                               context: ResidualScanner.ResidualScanContext,
                                               collector: inout ResidualCollector) {
        for subpath in ResidualCatalog.containerCacheSubpaths {
            let url = container.appendingPathComponent(subpath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            collector.add(url: url, category: .containerCache,
                          reason: "容器内可重建缓存（\(subpath)）")
        }
        // WebKit 的磁盘存储也在容器里，deep 档才收，风险仍由类别决定。
        if context.sensitivity == .deep {
            let webKit = container.appendingPathComponent("Data/Library/WebKit", isDirectory: true)
            guard FileManager.default.fileExists(atPath: webKit.path) else { return }
            collector.add(url: webKit, category: .webKit, reason: "容器内 WebKit 数据（\(webKit.lastPathComponent)）")
        }
    }

    // MARK: 元数据读取

    /// 用 PropertyListSerialization 读，不做任何字符串硬解析；读不出就返回 nil 交给名称回退。
    static func metadataIdentifier(in container: URL) -> String? {
        let url = container.appendingPathComponent(metadataFileName)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        guard let identifier = plist[metadataIdentifierKey] as? String else { return nil }
        return identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : identifier
    }

    /// 相等、或"本包名的派生标识"（helper / extension 容器）都算属于这个应用；
    /// 反向包含（容器标识是本包名的父级）不算，避免把宿主容器当成插件残留。
    ///
    /// 每条前缀规则都要带上分隔符边界：`group.com.example.MyAppSuite` 是**另一个**
    /// 应用的共享容器，不能因为字符串以 `group.com.example.MyApp` 开头就被收下。
    static func identifiersMatch(_ identifier: String, bundleID: String) -> Bool {
        let lhs = identifier.lowercased()
        let rhs = bundleID.lowercased()
        guard lhs.isEmpty == false, rhs.isEmpty == false else { return false }
        return lhs == rhs || lhs.hasPrefix(rhs + ".") || lhs.hasSuffix("." + rhs)
            || lhs == "group." + rhs || lhs.hasPrefix("group." + rhs + ".")
    }
}
