import Foundation

// MARK: - 用户文件夹扫描（Task 1）
//
// 扫描当前用户的桌面/文稿/下载/图片/影片/音乐等个人文件夹。
// 这些目录受 TCC 隐私保护：访问被拒时一律降级为「不可访问」，返回空结果，绝不崩溃、绝不阻塞。
// 与系统缓存不同，用户文件夹内容默认【不自动选中】，选中逻辑全部在 UI 层完成，
// 扫描器只负责提供决策所需的明细（大小、文件数、修改时间、可钻取子项）。

public struct UserFolderInfo: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let iconName: String
    public var size: UInt64
    public var fileCount: Int
    public var modificationDate: Date?
    public var isAccessible: Bool

    public init(
        name: String,
        path: String,
        iconName: String,
        size: UInt64,
        fileCount: Int,
        modificationDate: Date?,
        isAccessible: Bool
    ) {
        self.name = name
        self.path = path
        self.iconName = iconName
        self.size = size
        self.fileCount = fileCount
        self.modificationDate = modificationDate
        self.isAccessible = isAccessible
    }
}

public struct UserFolderChild: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public var size: UInt64
    public var fileCount: Int
    public let modificationDate: Date
    public let isDirectory: Bool

    public init(
        name: String,
        path: String,
        size: UInt64,
        fileCount: Int,
        modificationDate: Date,
        isDirectory: Bool
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.fileCount = fileCount
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }
}

public actor UserFolderScanner {
    public struct FolderSpec: Sendable {
        public let displayName: String
        public let iconName: String
        public let relativePath: String

        public init(displayName: String, iconName: String, relativePath: String) {
            self.displayName = displayName
            self.iconName = iconName
            self.relativePath = relativePath
        }
    }

    public init() {}

    public static func folderSpecs() -> [FolderSpec] {
        [
            FolderSpec(displayName: "桌面", iconName: "desktopcomputer", relativePath: "Desktop"),
            FolderSpec(displayName: "文稿", iconName: "doc.on.doc.fill", relativePath: "Documents"),
            FolderSpec(displayName: "下载", iconName: "arrow.down.circle.fill", relativePath: "Downloads"),
            FolderSpec(displayName: "图片", iconName: "photo.fill", relativePath: "Pictures"),
            FolderSpec(displayName: "影片", iconName: "film.fill", relativePath: "Movies"),
            FolderSpec(displayName: "音乐", iconName: "music.note.list", relativePath: "Music"),
        ]
    }

    /// 扫描全部用户文件夹；被 TCC 拒绝的文件夹以 isAccessible=false 呈现。可取消。
    public func scan(tracker: FileScanProgressTracker? = nil) async -> [UserFolderInfo] {
        let home = NSHomeDirectory()
        var infos: [UserFolderInfo] = []

        for spec in Self.folderSpecs() {
            if Task.isCancelled { break }
            let path = home + "/" + spec.relativePath
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let modDate = FileTreeWalker.modificationDate(ofPath: path)

            guard FileTreeWalker.canEnumerate(path: path) else {
                infos.append(UserFolderInfo(
                    name: spec.displayName, path: path, iconName: spec.iconName,
                    size: 0, fileCount: 0, modificationDate: modDate, isAccessible: false
                ))
                continue
            }

            let stats = await FileTreeWalker.stats(path: path, tracker: tracker)
            infos.append(UserFolderInfo(
                name: spec.displayName, path: path, iconName: spec.iconName,
                size: stats.size, fileCount: stats.fileCount,
                modificationDate: modDate, isAccessible: true
            ))
        }

        return infos.sorted { $0.size > $1.size }
    }

    /// 重新统计单个文件夹（清理完成后局部刷新用）；不可访问返回 isAccessible=false，不存在返回 nil。
    public func scanFolder(
        atPath path: String,
        tracker: FileScanProgressTracker? = nil
    ) async -> UserFolderInfo? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let home = NSHomeDirectory()
        let spec = Self.folderSpecs().first { home + "/" + $0.relativePath == path }
        let displayName = spec?.displayName ?? (path as NSString).lastPathComponent
        let iconName = spec?.iconName ?? "folder.fill"
        let modDate = FileTreeWalker.modificationDate(ofPath: path)

        guard FileTreeWalker.canEnumerate(path: path) else {
            return UserFolderInfo(
                name: displayName, path: path, iconName: iconName,
                size: 0, fileCount: 0, modificationDate: modDate, isAccessible: false
            )
        }
        let stats = await FileTreeWalker.stats(path: path, tracker: tracker)
        return UserFolderInfo(
            name: displayName, path: path, iconName: iconName,
            size: stats.size, fileCount: stats.fileCount,
            modificationDate: modDate, isAccessible: true
        )
    }

    /// 钻取文件夹子项（扩展版 listChildren：附带文件数与修改时间，供用户决策）。
    /// 目录大小由子节点求和得出；无法访问的目录返回空数组。
    public func listChildren(of path: String, tracker: FileScanProgressTracker? = nil) async -> [UserFolderChild] {
        let entries = FileTreeWalker.readEntries(path: path)
        var children: [UserFolderChild] = []
        children.reserveCapacity(entries.count)

        for entry in entries {
            if Task.isCancelled { break }
            let stats: FileTreeWalker.Stats
            if entry.isDirectory {
                stats = await FileTreeWalker.stats(path: entry.path, depth: 1, tracker: tracker)
            } else {
                stats = FileTreeWalker.Stats(size: entry.size, fileCount: 1)
            }
            children.append(UserFolderChild(
                name: entry.name,
                path: entry.path,
                size: stats.size,
                fileCount: stats.fileCount,
                modificationDate: entry.modificationDate,
                isDirectory: entry.isDirectory
            ))
        }

        children.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
            return $0.size > $1.size
        }
        return Array(children.prefix(300))
    }
}
