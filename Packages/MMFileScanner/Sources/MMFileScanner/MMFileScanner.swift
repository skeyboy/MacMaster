import Foundation

// MARK: - File Entry

public struct FileEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let path: URL
    public let name: String
    public let size: UInt64
    public let isDirectory: Bool
    public let modificationDate: Date

    public init(path: URL, name: String, size: UInt64, isDirectory: Bool, modificationDate: Date) {
        self.id = UUID()
        self.path = path
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
    }
}

// MARK: - Scan Progress

public struct ScanProgress {
    public let scannedFiles: Int
    public let scannedSize: UInt64
    public let totalFiles: Int?
    public let totalSize: UInt64?
    public let currentPath: String?

    public var percentage: Double? {
        guard let total = totalSize, total > 0 else { return nil }
        return Double(scannedSize) / Double(total) * 100
    }
}

// MARK: - Scan Result

public struct ScanResult {
    public let entries: [FileEntry]
    public let totalSize: UInt64
    public let totalCount: Int
    public let scanDuration: TimeInterval

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}

// MARK: - File Scanner Engine

public actor FileScanner {
    private let excludedPaths: Set<String>
    private let minFileSize: UInt64
    private let maxConcurrency: Int

    public init(
        excludedPaths: Set<String> = [
            "/System/Volumes",
            "/Volumes",
            "/private/tmp/msu-",
            "/.Spotlight-V100",
            "/.Trashes",
            "/.fseventsd"
        ],
        minFileSize: UInt64 = 1024,
        maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount
    ) {
        self.excludedPaths = excludedPaths
        self.minFileSize = minFileSize
        self.maxConcurrency = maxConcurrency
    }

    public func scanDirectory(
        _ directory: URL,
        progressHandler: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        let startTime = Date()
        var entries: [FileEntry] = []
        var totalSize: UInt64 = 0

        await scanRecursively(
            directory: directory,
            entries: &entries,
            totalSize: &totalSize,
            progressHandler: progressHandler
        )

        let duration = Date().timeIntervalSince(startTime)
        return ScanResult(
            entries: entries,
            totalSize: totalSize,
            totalCount: entries.count,
            scanDuration: duration
        )
    }

    private func scanRecursively(
        directory: URL,
        entries: inout [FileEntry],
        totalSize: inout UInt64,
        progressHandler: (@Sendable (ScanProgress) -> Void)?
    ) async {
        let path = directory.path

        guard !isExcluded(path) else { return }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        // 逐条 nextObject 而不是 for-in：快速枚举会预取一批，
        // skipDescendants() 对已在批次里的条目不生效，排除的目录会被照样扫进去。
        while let fileURL = enumerator.nextObject() as? URL {
            let filePath = fileURL.path

            guard !isExcluded(filePath) else {
                enumerator.skipDescendants()
                continue
            }

            let resourceValues: [URLResourceKey: Any]
            do {
                resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]).allValues
            } catch {
                continue
            }

            let isDirectory = (resourceValues[.isDirectoryKey] as? Bool) ?? false
            let fileSize = (resourceValues[.fileSizeKey] as? UInt64) ?? 0
            let modDate = (resourceValues[.contentModificationDateKey] as? Date) ?? Date.distantPast

            guard !isDirectory && fileSize >= minFileSize else { continue }

            let entry = FileEntry(
                path: fileURL,
                name: fileURL.lastPathComponent,
                size: fileSize,
                isDirectory: false,
                modificationDate: modDate
            )

            entries.append(entry)
            totalSize += fileSize

            if let handler = progressHandler {
                let progress = ScanProgress(
                    scannedFiles: entries.count,
                    scannedSize: totalSize,
                    totalFiles: nil,
                    totalSize: nil,
                    currentPath: filePath
                )
                handler(progress)
            }
        }
    }

    private func isExcluded(_ path: String) -> Bool {
        excludedPaths.contains { excluded in
            path == excluded || path.hasPrefix(excluded.hasSuffix("/") ? excluded : excluded + "/")
        }
    }
}

