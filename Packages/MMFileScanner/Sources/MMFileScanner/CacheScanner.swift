import Foundation

public struct CacheCategory: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public let paths: [String]
    public var scannedSize: UInt64
    public var scannedFiles: Int
    public var subItems: [CacheSubItem]

    public init(id: String, name: String, description: String, iconName: String, paths: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.paths = paths
        self.scannedSize = 0
        self.scannedFiles = 0
        self.subItems = []
    }
}

public struct CacheSubItem: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public var size: UInt64
    public var fileCount: Int
}

public struct CacheFileEntry: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: UInt64
    public let isDirectory: Bool
}

public actor CacheScanner {
    public init() {}

    public func scanAll() async -> [CacheCategory] {
        let home = NSHomeDirectory()
        var categories = defaultCategories(home: home)
        for i in categories.indices {
            let result = await scanPaths(categories[i].paths)
            categories[i].scannedSize = result.totalSize
            categories[i].scannedFiles = result.totalFiles
            categories[i].subItems = result.subItems
        }
        return categories
    }

    public func scan(category: CacheCategory) async -> CacheCategory {
        var cat = category
        let result = await scanPaths(cat.paths)
        cat.scannedSize = result.totalSize
        cat.scannedFiles = result.totalFiles
        cat.subItems = result.subItems
        return cat
    }

    private func scanPaths(_ paths: [String]) async -> (totalSize: UInt64, totalFiles: Int, subItems: [CacheSubItem]) {
        var totalSize: UInt64 = 0
        var totalFiles = 0
        var subItems: [CacheSubItem] = []

        for path in paths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath) else { continue }

            let (size, count) = await directoryStats(path: expandedPath)
            if size > 0 {
                totalSize += size
                totalFiles += count
                let name = (expandedPath as NSString).lastPathComponent
                subItems.append(CacheSubItem(name: name, path: expandedPath, size: size, fileCount: count))
            }
        }

        return (totalSize, totalFiles, subItems)
    }

    private func directoryStats(path: String) async -> (size: UInt64, count: Int) {
        var size: UInt64 = 0
        var count = 0
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return (0, 0) }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else { continue }
            if values.isDirectory == true { continue }
            size += UInt64(values.fileSize ?? 0)
            count += 1
        }
        return (size, count)
    }

    public func listChildren(path: String) -> [CacheFileEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [CacheFileEntry] = []
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else { continue }
            let isDir = values.isDirectory == true
            let size: UInt64 = {
                if isDir {
                    return directorySize(url: url)
                }
                return UInt64(values.fileSize ?? 0)
            }()
            entries.append(CacheFileEntry(
                name: url.lastPathComponent,
                path: url.path,
                size: size,
                isDirectory: isDir
            ))
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.size > $1.size
        }
    }

    private func directorySize(url: URL) -> UInt64 {
        var size: UInt64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let s = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += UInt64(s)
            }
        }
        return size
    }

    private func defaultCategories(home: String) -> [CacheCategory] {
        [
            CacheCategory(
                id: "system_cache",
                name: "系统缓存",
                description: "应用程序缓存文件",
                iconName: "externaldrive.badge.icloud",
                paths: ["\(home)/Library/Caches"]
            ),
            CacheCategory(
                id: "app_logs",
                name: "应用日志",
                description: "系统和应用程序日志文件",
                iconName: "doc.text",
                paths: ["\(home)/Library/Logs", "/tmp"]
            ),
            CacheCategory(
                id: "browser_cache",
                name: "浏览器缓存",
                description: "Safari、Chrome 等浏览器缓存",
                iconName: "globe",
                paths: [
                    "\(home)/Library/Caches/com.apple.Safari",
                    "\(home)/Library/Caches/Google/Chrome",
                    "\(home)/Library/Caches/com.microsoft.edgemac",
                    "\(home)/Library/Caches/com.brave.Browser",
                ]
            ),
            CacheCategory(
                id: "xcode_cache",
                name: "Xcode 缓存",
                description: "DerivedData、Archives 等开发缓存",
                iconName: "hammer",
                paths: [
                    "\(home)/Library/Developer/Xcode/DerivedData",
                    "\(home)/Library/Developer/Xcode/Archives",
                    "\(home)/Library/Developer/CoreSimulator/Caches",
                ]
            ),
            CacheCategory(
                id: "mail_cache",
                name: "邮件缓存",
                description: "Mail 应用附件和下载缓存",
                iconName: "envelope",
                paths: [
                    "\(home)/Library/Mail",
                    "\(home)/Library/Caches/com.apple.mail",
                ]
            ),
            CacheCategory(
                id: "trash",
                name: "废纸篓",
                description: "已删除但未清空的文件",
                iconName: "trash",
                paths: ["\(home)/.Trash"]
            ),
            CacheCategory(
                id: "crash_reports",
                name: "崩溃报告",
                description: "系统和应用崩溃日志",
                iconName: "exclamationmark.triangle",
                paths: [
                    "\(home)/Library/Logs/DiagnosticReports",
                    "/Library/Logs/DiagnosticReports",
                ]
            ),
        ]
    }
}
