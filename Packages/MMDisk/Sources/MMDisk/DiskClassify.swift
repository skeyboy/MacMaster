import SwiftUI
import MMUI

/// 方块图的色相回答"这是什么东西"，斜纹回答"这份东西能不能清"。
/// 这是两个独立的问题，所以判定链也必须独立：一个目录可以是"开发者"
/// 分类却不可清理（比如用户的 Xcode 工程），也可以是"其他"分类却是
/// 构建产物。把它们绑死在一起，图上就只剩一种信息了。
///
/// 分类词条面向 macOS 的目录语义（DerivedData、iOS DeviceSupport、
/// Containers、Application Support…），判定思路参考 disktree (MIT)，
/// 表内容为本项目自行整理。
enum NodeCategory: String, CaseIterable, Sendable {
    case developer, appData, media, documents, cache, log, other

    var displayName: String {
        switch self {
        case .developer: return "开发者"
        case .appData: return "应用数据"
        case .media: return "媒体"
        case .documents: return "文档"
        case .cache: return "缓存"
        case .log: return "日志"
        case .other: return "其他"
        }
    }

    /// 取自设计稿 docs/design-system/screens/04-disk.html 的图例色。
    var color: Color {
        switch self {
        case .developer: return TreemapPalette.hex(0xAF52DE)
        case .appData: return TreemapPalette.hex(0x5E5CE6)
        case .media: return TreemapPalette.hex(0x30B0C7)
        case .documents: return TreemapPalette.hex(0x28CD41)
        case .cache: return TreemapPalette.hex(0x8E8E93)
        case .log: return TreemapPalette.hex(0xFF9500)
        case .other: return TreemapPalette.hex(0xA2845E)
        }
    }
}

/// 可清理的原因。原因要能写成一句人话，因为详情面板和确认弹窗都要引用它。
enum ReclaimReason: String, Sendable {
    case buildOutput
    case dependency
    case cache
    case log
    case inherited

    var note: String {
        switch self {
        case .buildOutput: return "构建产物，工具链可以随时重新生成；删除后首次构建会变慢。"
        case .dependency: return "依赖缓存，下次安装会重新下载；网络或私有源不可用时将无法构建。"
        case .cache: return "缓存内容会在使用中自动重建，删除不丢数据，只是回到冷启动速度。"
        case .log: return "日志与诊断记录，只影响事后排查，不影响任何功能。"
        case .inherited: return "位于上面这个可清理目录之内，随父目录一起可清理。"
        }
    }
}

enum DiskClassify {
    private static let developerNames: Set<String> = [
        "Developer", "DerivedData", "Xcode", "iOS DeviceSupport", "Archives",
        "CoreSimulator", "node_modules", "Pods", "Carthage", ".cargo", ".rustup",
        ".gradle", ".m2", ".cocoapods", ".pub-cache", ".npm", ".yarn", ".pnpm-store",
        ".gvm", ".nvm", ".rbenv", ".pyenv", ".virtualenvs", ".sbt", ".ivy2", ".deno",
        ".android", "Android",
    ]
    private static let appDataNames: Set<String> = [
        "Application Support", "Containers", "Group Containers", "Saved Application State",
        "Application Scripts", "Application Preferences", "HTTPStorages", "Cookies",
        "WebKit", "Storage", "databases", "Mail", "Messages", "Passkeys", "Biome",
    ]
    private static let mediaNames: Set<String> = [
        "Movies", "Music", "Pictures", "Photos Library.photoslibrary", "Podcasts",
        "Screenshots", "TV", "Video", "Audio",
    ]
    private static let documentNames: Set<String> = [
        "Documents", "Desktop", "Downloads", "Sites", "Public", "iCloud Drive",
    ]
    private static let cacheNames: Set<String> = [
        "Caches", "Cache", ".cache", "Code Cache", "GPUCache", "ShaderCache", "blob_storage",
    ]
    private static let logNames: Set<String> = ["Logs", "logs", "DiagnosticReports", "CrashReporter"]

    /// 本层名字优先，认不出来才继承父类——这样 `Developer/Xcode` 仍然是开发者，
    /// 而 `Containers/…/Caches` 会被自己的名字改写成缓存。
    static func category(ofName name: String, isDirectory: Bool, inherited: NodeCategory) -> NodeCategory {
        if developerNames.contains(name) { return .developer }
        if cacheNames.contains(name) { return .cache }
        if logNames.contains(name) { return .log }
        if mediaNames.contains(name) { return .media }
        if documentNames.contains(name) { return .documents }
        if appDataNames.contains(name) { return .appData }
        if !isDirectory && name.lowercased().hasSuffix(".log") { return .log }
        if !isDirectory {
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "jpg", "jpeg", "png", "heic", "gif", "mov", "mp4", "m4a", "mp3", "wav", "tiff":
                return .media
            case "pdf", "docx", "pages", "txt", "md", "key", "xlsx", "numbers", "csv":
                return .documents
            case "app", "dmg", "pkg", "framework":
                return .appData
            default:
                break
            }
        }
        return inherited
    }

    /// 兄弟证据：`target` 只有在 `Cargo.toml` 旁边才是构建产物，否则它就是某个
    /// 同名无关目录。没有这层约束，"target" 会把用户的项目源码标成可清理。
    private static let buildManifests: Set<String> = [
        "Cargo.toml", "package.json", "pyproject.toml", "CMakeLists.txt", "go.mod",
    ]
    private static let jsLockfiles: Set<String> = [
        "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb",
    ]

    static func reclaimReason(ofName name: String, isDirectory: Bool,
                              siblings: Set<String>) -> ReclaimReason? {
        guard isDirectory else {
            return name.lowercased().hasSuffix(".log") ? .log : nil
        }
        switch name {
        case "DerivedData":
            // 名字本身就是 Xcode 的构建目录，不需要旁证。
            return .buildOutput
        case "build", "target":
            // 这两个名字太常见：没有清单文件在旁边就不能断定是构建产物。
            guard siblings.contains(where: { buildManifests.contains($0) }) else { return nil }
            return .buildOutput
        case "node_modules":
            return siblings.contains(where: { jsLockfiles.contains($0) }) ? .dependency : nil
        case "Pods":
            return siblings.contains("Podfile") ? .dependency : nil
        case "Carthage":
            return siblings.contains("Cartfile") ? .dependency : nil
        case "Caches", "Cache", ".cache", "Code Cache", "GPUCache", "ShaderCache",
             ".npm", ".yarn", ".pnpm-store", ".cargo", ".gradle", ".m2", "iOS DeviceSupport":
            return .cache
        case "Logs", "logs", "DiagnosticReports":
            return .log
        default:
            return name.lowercased().hasSuffix(".log") ? .log : nil
        }
    }

    /// 一个目录自身的结论，用作它子层的继承起点。
    /// 扫 `~/Library/Caches` 时，里面认不出名字的子目录也应当是缓存、
    /// 也应当带斜纹，否则同一个盘子在全盘扫描和单独扫描里会长得不一样。
    static func context(forPath path: String) -> (NodeCategory, ReclaimReason?) {
        let name = (path as NSString).lastPathComponent
        return (
            category(ofName: name, isDirectory: true, inherited: .other),
            reclaimReason(ofName: name, isDirectory: true, siblings: [])
        )
    }

    /// 就地把分类和可清理标记挂到整棵树上。父类结论向下传递，
    /// 于是缓存目录底下整片都是斜纹——这正是设计稿要表达的"这一块都可清"。
    static func classify(_ nodes: [DiskTreeNode], inheritedCategory: NodeCategory,
                         inheritedReclaim: ReclaimReason?) -> [DiskTreeNode] {
        let siblings = Set(nodes.map(\.name))
        return nodes.map { node in
            let category = category(ofName: node.name, isDirectory: node.isDirectory,
                                    inherited: inheritedCategory)
            var reclaim = reclaimReason(ofName: node.name, isDirectory: node.isDirectory,
                                        siblings: siblings)
            if reclaim == nil, let parent = inheritedReclaim {
                reclaim = parent == .inherited ? parent : .inherited
            }
            let children = classify(node.children, inheritedCategory: category,
                                    inheritedReclaim: reclaim)
            var classified = node
            classified.category = category
            classified.reclaim = reclaim
            classified.children = children
            return classified
        }
    }
}
