import Foundation
import Darwin

// MARK: - 开发产物跨目录聚合（只读扫描层）
//
// 这一层**只读、只返回事实**：在开发目录里找出可重建的构建产物目录
// （node_modules、.build、DerivedData、.venv、target…），按项目根分组，
// 并对每一处给出"多久没碰过"与"能不能删"的判定。删除由 UI 侧走
// FileTrashService，不归这里管。
//
// 三条口径纪律（照 CacheScanner / SystemSpaceReport 的写法）：
// 1. **不执行任何第三方二进制**。Mole 用 `git ls-files` 判断产物里是否混着已跟踪
//    源码，我们不学它——跑用户装的 git 等于信任任意版本的可执行文件。代替方案是
//    只用纯目录证据，且证据不足时宁可判为 protected，不硬凑"可回收"结论。
// 2. 体积测量**复用 FileTreeWalker.stats**（单次 lstat、不跟随符号链接、目录大小由
//    子项求和），否则同一目录在清理页与磁盘分析页显示的数字会互相矛盾。
// 3. 深浅失败要区别：目录不存在 / 没有读权限 / 扫到一半超时是三种不同的事，
//    分别进 missingRoots / inaccessibleRoots / truncatedRoots，都不能折成 0 字节
//    或"很干净"。nil 体积显示"—"，探测失败就是 unknown，绝不写成"很久没碰"。

// MARK: - 名单常量

/// 名单放在 actor 之外的 enum：静态存储属性在 actor 里的隔离语义随编译器版本
/// 漂移，enum 常量最稳；`ProjectArtifactRules.default` 与 `verdict` 都从这里取，
/// 两处永远是同一份，不各抄一套。
enum ProjectArtifactNames {
    /// 名字本身就是产物、不需要邻居证据的名单。
    static let nameIsEnough: Set<String> = [
        "node_modules", ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache",
        ".ruff_cache", ".tox", ".nox", ".gradle", ".terragrunt-cache", ".next", ".nuxt",
        ".output", ".turbo", ".parcel-cache", ".dart_tool", ".zig-cache", "zig-out",
        ".angular", ".svelte-kit", ".astro", ".expo", ".build", "Pods", ".cxx",
    ]

    /// 在产物名单里、但必须拿邻居证据才能删的名字。
    static let contextRequired: Set<String> = [
        "bin", "obj", "vendor", "target", "build", "dist", "coverage", "DerivedData",
    ]

    /// 目录发现要跳过的系统目录。Desktop 不在名单里：用户真会把项目放桌面。
    static let nonContainerDirectories: Set<String> = [
        "Library", "Applications", "Movies", "Music", "Pictures", "Public",
    ]

    static let cacheDirectoryTagSignature = "Signature: 8a477f597d28d172789f06886806bc55"
    static let cacheDirectoryTagName = "CACHEDIR.TAG"
}

// MARK: - 规则与预算

/// 扫描规则。所有预算（深度上下限、每根时限、"久未触碰"天数、项目根上溯上限）
/// 都是可注入字段，测试里改成小值、真机用 `default`，不在逻辑里写死数字。
public struct ProjectArtifactRules: Sendable {
    /// 可重建产物名单（Mole `MOLE_PURGE_TARGETS` 的同源清单）。
    /// 注意：名单里的每一个名字都要过 `ProjectArtifactScanner.verdict` 的证据关，
    /// 名字本身不等于"可删"。
    public var artifactNames: Set<String>
    /// 项目根邻居清单文件（package.json / Cargo.toml / go.mod …）。
    /// monorepo 名单也包含在内：Mole 的容器发现直接把两份名单合起来用。
    public var projectIndicators: Set<String>
    /// monorepo 边界标志：找到则整个 workspace 归一组，优先级高于普通项目根。
    public var monorepoIndicators: Set<String>
    /// 搜索根（绝对路径）。默认按 home 拼出来；测试注入临时目录。
    public var searchRoots: [String]
    /// 候选相对搜索根的最小深度。**深度口径照 Mole**：搜索根的直接子项算深度 0，
    /// `根/项目/node_modules` 算深度 1。深度 0 只有当根本身就是项目根时允许
    /// （单项目模式：用户把一个项目目录配成搜索根）。
    public var minDepth: Int
    /// 相对搜索根的最大深度，超出就不再往下找。
    public var maxDepth: Int
    /// "久未触碰"阈值（天）。产物目录或其中任何文件在此之内被改过就不算久未触碰。
    public var minAgeDays: Int
    /// 每个搜索根的时限：发现遍历 + 活动探测 + 体积测量共享这一份预算。
    /// 根被时间截断会如实写进 `truncatedRoots`，绝不静默。
    public var rootBudgetSeconds: Double
    /// 整轮扫描的总时限。只有 `rootBudgetSeconds` 是不够的：根可以十几个，
    /// 每个 20 秒就是几分钟的白屏；只给一个总时限更糟——排在后面的根
    /// （真机上正是 ~/Documents 这种项目最密集的位置）会一秒都拿不到。
    /// 所以每个根拿自己的预算，但整体不超过这一份，超出的根如实算截断。
    public var totalBudgetSeconds: Double
    /// 从产物目录向上找项目根的最大层数。
    public var projectRootMaxUp: Int

    public init(artifactNames: Set<String>,
                projectIndicators: Set<String>,
                monorepoIndicators: Set<String>,
                searchRoots: [String],
                minDepth: Int = 1,
                maxDepth: Int = 6,
                minAgeDays: Int = 7,
                rootBudgetSeconds: Double,
                totalBudgetSeconds: Double = 60,
                projectRootMaxUp: Int = 8) {
        self.artifactNames = artifactNames
        self.projectIndicators = projectIndicators
        self.monorepoIndicators = monorepoIndicators
        self.searchRoots = searchRoots
        self.minDepth = minDepth
        self.maxDepth = maxDepth
        self.minAgeDays = minAgeDays
        self.rootBudgetSeconds = rootBudgetSeconds
        self.totalBudgetSeconds = totalBudgetSeconds
        self.projectRootMaxUp = projectRootMaxUp
    }

    /// Mole 的默认搜索根 + 两个 AI agent worktree 容器 + 本机实测补上的两处。
    /// `~/.codex/worktrees`、`~/.claude/worktrees` 必须显式列出来：它们在点目录下，
    /// 常规发现（只扫 home 深度 1 的非隐藏目录）进不去，而里面的 checkout 恰恰是
    /// 可重建产物最集中的地方。worktree 本身永远不动。
    ///
    /// 为什么要加 `Desktop` 与 `Documents`：Mole 那八个根在这台开发机上**一个都不存在**
    /// （`docs/analysis/feature-roadmap.md` P5.1 落档了这次实测），而真项目全在
    /// `~/Desktop/*` 与 `~/Documents/*` 下面。它们本来也会被 home 深度 1 的容器探测
    /// 捞到，但根的**先后顺序就是预算的分配顺序**——排在容器探测后面，就等于把
    /// 时限让给了 `~/Applications (Parallels)`、`~/Downloads` 这些没有项目的目录。
    public static func `default`(home: String) -> ProjectArtifactRules {
        let plainRoots = [
            "www", "dev", "Projects", "GitHub", "Code", "Workspace", "Repos", "Development",
            "Desktop", "Documents",
        ].map { "\(home)/\($0)" }
        return ProjectArtifactRules(
            artifactNames: ProjectArtifactNames.nameIsEnough.union(ProjectArtifactNames.contextRequired),
            projectIndicators: [
                "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "pom.xml",
                "build.gradle", "Gemfile", "composer.json", "pubspec.yaml", "Package.swift",
                "requirements.txt", "build.zig",
                // monorepo 标志同时是项目标志（容器发现只消费这一份名单）。
                "lerna.json", "pnpm-workspace.yaml", "nx.json", "rush.json",
            ],
            monorepoIndicators: ["lerna.json", "pnpm-workspace.yaml", "nx.json", "rush.json"],
            searchRoots: plainRoots + [
                "\(home)/Library/CloudStorage",
                "\(home)/.codex/worktrees",
                "\(home)/.claude/worktrees",
            ],
            rootBudgetSeconds: 15,
            totalBudgetSeconds: 60
        )
    }
}

// MARK: - 判定分档

/// "可回收"的证据从哪来。分档不是为了打分，是为了让 UI 能如实解释
/// "凭什么说这个能删"。
public enum ArtifactEvidence: Hashable, Sendable {
    /// 名字本身就是产物（node_modules、.venv、__pycache__…），不需要邻居证据。
    case nameIsEnough
    /// 靠邻居清单文件证明（"旁边有 .csproj 且含 Debug/Release"）。关联值就是证据描述。
    case contextProven(String)
    /// 目录里有合法签名的 CACHEDIR.TAG——可回收证据里最强的一档，
    /// 目录主亲口声明这里全是缓存。
    case cacheDirectoryTag
}

/// 每一处产物的能不能删判定。protected 的条目 UI 上不给勾选框。
public enum ArtifactVerdict: Hashable, Sendable {
    case reclaimable(ArtifactEvidence)
    case protected(reason: String)
}

/// "多久没碰过"。三态，且 `unknown` 绝不能被 UI 读成"很久没碰"：
/// 探测失败/超时不是"旧"的证据，把失败折成"旧"就是替用户按下删除键。
public enum ArtifactActivity: Hashable, Sendable {
    /// 明确超过阈值天数没碰过。
    case untouchedForDays(Int)
    /// 近期用过（阈值之内）。
    case touchedDaysAgo(Int)
    /// 探测失败/超时/读不到时间：未知。
    case unknown(String)
}

/// 有界活动探测的结果。只有**完整跑完**的遍历才许 `noRecentFile`；
/// 超时、读不动一律 `incomplete`（fail closed）。
public enum ActivityProbe: Hashable, Sendable {
    case recentFileFound
    case noRecentFile
    case incomplete(String)
}

// MARK: - 结果模型

public struct ProjectArtifact: Identifiable, Hashable, Sendable {
    public let id: String            // = path
    public let path: String
    public let name: String          // node_modules
    /// 归属的项目根。解析不到时回落到产物目录的父目录——上下文类规则因此
    /// 拿不到证据、verdict 落到 protected，但分组不丢条目。
    public let projectRoot: String
    public let relativeToProject: String
    /// 归属根是由 monorepo 标志（pnpm-workspace.yaml…）认定时记录具体标志，
    /// 分组用它把整个 workspace 归到一组。
    public let monorepoIndicator: String?
    /// nil = 没测到（读不进 / 已消失 / 预算耗尽 / 嵌套在另一产物里没单独量），
    /// 显示"—"，绝不折成 0。
    public var size: UInt64?
    public let fileCount: Int
    public let lastTouched: Date?
    public let verdict: ArtifactVerdict
    public let activity: ArtifactActivity
    /// 见"嵌套去重"：祖先目录本身也是候选时，这里只标不量、不重复计体积。
    public let isNestedInAnotherArtifact: Bool
    /// 发现这一行的搜索根。合并两批报表要按根分区
    /// （`docs/analysis/dev-artifact-continuation.md` §4.1）：续扫**整区替换**被重跑的那个根，
    /// 其余根逐行原样保留——没有这个字段就分不出"哪些行属于被续扫的根"。
    public let sourceRoot: String

    public init(path: String, name: String, projectRoot: String, relativeToProject: String,
                monorepoIndicator: String?, size: UInt64?, fileCount: Int, lastTouched: Date?,
                verdict: ArtifactVerdict, activity: ArtifactActivity,
                isNestedInAnotherArtifact: Bool, sourceRoot: String) {
        self.id = path
        self.path = path
        self.name = name
        self.projectRoot = projectRoot
        self.relativeToProject = relativeToProject
        self.monorepoIndicator = monorepoIndicator
        self.size = size
        self.fileCount = fileCount
        self.lastTouched = lastTouched
        self.verdict = verdict
        self.activity = activity
        self.isNestedInAnotherArtifact = isNestedInAnotherArtifact
        self.sourceRoot = sourceRoot
    }

    /// 只改"嵌套标注"，观测字段一个都不动。合并两批时要在**候选全集**上重算
    /// `nestedFlags`（§4.3）：第一批量完的父和第二批才发现的子凑到一起，
    /// 不重算就是同一坨体积计两遍。改成嵌套后体积写 nil 而不是保留原值——
    /// "只标不量"是扫描器一贯的口径，留着原值会让这一行看上去还在被合计。
    public func withNestedFlag(_ nested: Bool) -> ProjectArtifact {
        guard nested != isNestedInAnotherArtifact else { return self }
        return ProjectArtifact(path: path, name: name, projectRoot: projectRoot,
                               relativeToProject: relativeToProject,
                               monorepoIndicator: monorepoIndicator,
                               size: nested ? nil : size,
                               fileCount: nested ? 0 : fileCount,
                               lastTouched: lastTouched, verdict: verdict, activity: activity,
                               isNestedInAnotherArtifact: nested, sourceRoot: sourceRoot)
    }
}

public struct ProjectArtifactGroup: Identifiable, Hashable, Sendable {
    public let id: String            // = projectRoot
    public let projectRoot: String
    public let displayName: String
    public let relativeToHome: String
    public let isMonorepo: Bool
    public let monorepoIndicator: String?
    /// 落在 ~/Library/CloudStorage 或 ~/Library/Mobile Documents 之下：
    /// 云同步目录里的 build/dist 可能是仓库签入的内容，判定更保守。
    public let isCloudSynced: Bool
    public var artifacts: [ProjectArtifact]
    /// 可回收（非嵌套）产物体积之和。**有任何一个没测到就是 nil**，
    /// 不折成 0——"可释放 X GB"宁可少说也不能编。
    public var reclaimableSize: UInt64?

    public init(projectRoot: String, displayName: String, relativeToHome: String,
                isMonorepo: Bool, monorepoIndicator: String?, isCloudSynced: Bool,
                artifacts: [ProjectArtifact], reclaimableSize: UInt64?) {
        self.id = projectRoot
        self.projectRoot = projectRoot
        self.displayName = displayName
        self.relativeToHome = relativeToHome
        self.isMonorepo = isMonorepo
        self.monorepoIndicator = monorepoIndicator
        self.isCloudSynced = isCloudSynced
        self.artifacts = artifacts
        self.reclaimableSize = reclaimableSize
    }
}

public struct ProjectArtifactReport: Sendable {
    public let groups: [ProjectArtifactGroup]
    /// 从头到尾走完、没有截断也没有读不动的根。
    public let scannedRoots: [String]
    /// 超时或被取消而截断的根，UI 要如实播报"这几个目录没扫完"。
    public let truncatedRoots: [String]
    /// 存在但读不进去的根（TCC 拒绝 / 权限不足）。不计入总量，也不说成 0。
    public let inaccessibleRoots: [String]
    /// 压根不存在的根。开发机 ~/www 没有很正常，与"读不动"是两种事实，分开列。
    public let missingRoots: [String]
    /// 通过词面前缀、却在解析符号链接后越出搜索根的候选数
    /// （`GOMODCACHE=../../etc` 式越界的量化信号；这些候选被丢弃，不进分组）。
    public let outOfSearchRootCandidateCount: Int
    /// 没有截断、没有读不动的根才算完整。缺这个标志，"未发现产物"就会
    /// 冒充"你的磁盘很干净"。
    public let isComplete: Bool
    public let duration: TimeInterval

    public init(groups: [ProjectArtifactGroup], scannedRoots: [String], truncatedRoots: [String],
                inaccessibleRoots: [String], missingRoots: [String],
                outOfSearchRootCandidateCount: Int, isComplete: Bool, duration: TimeInterval) {
        self.groups = groups
        self.scannedRoots = scannedRoots
        self.truncatedRoots = truncatedRoots
        self.inaccessibleRoots = inaccessibleRoots
        self.missingRoots = missingRoots
        self.outOfSearchRootCandidateCount = outOfSearchRootCandidateCount
        self.isComplete = isComplete
        self.duration = duration
    }
}

// MARK: - 扫描器

public actor ProjectArtifactScanner {
    private let home: String
    private let rules: ProjectArtifactRules
    /// 可注入的"现在"：age/activity 全部相对它计算，单测不用 sleep。
    private let now: Date

    public init(home: String = NSHomeDirectory(), rules: ProjectArtifactRules, now: Date = Date()) {
        self.home = home
        self.rules = rules
        self.now = now
    }

    // MARK: - 扫描入口

    /// - Parameters:
    ///   - explicitRoots: 续扫批次传入的根集合。**给了显式根就不再探测 home 一级容器**
    ///     （§3.4：容器探测依赖当时的 home 状态，重探会让"哪些根要重试"有两个答案；
    ///     新出现的顶层项目属于「重新扫描」的语义，不属于续扫）。nil = 全量扫描。
    ///   - reuse: 上一批已经看完证据的行（`isCompleteObservation`）。命中即整行复用、
    ///     不再跑活动探测与体积测量——实测截断吃在成案阶段而不是遍历阶段（§2），
    ///     所以续扫省下来的预算正好落在"上一批没量完的行"上。
    public func scan(progress: (@Sendable (String) -> Void)? = nil,
                     roots explicitRoots: [String]? = nil,
                     reuse: [String: ProjectArtifact] = [:]) async -> ProjectArtifactReport {
        let started = Date()
        let roots = Self.dedupeRoots(explicitRoots ?? expandedSearchRoots()) { Self.physicalPath(of: $0) }

        var truncated: [String] = []
        var inaccessible: [String] = []
        var missing: [String] = []
        var walked: [String] = []
        // 每个候选记住它所属搜索根与时限：活动探测与体积测量共享这份预算。
        var found: [(path: String, root: String, deadline: Date)] = []
        var complete = true

        for root in roots {
            progress?(root)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir) else {
                missing.append(root)
                continue
            }
            guard isDir.boolValue else { continue }   // 同名文件不是错误，静默跳过
            guard FileTreeWalker.canEnumerate(path:root) else {
                inaccessible.append(root)
                complete = false
                continue
            }
            walked.append(root)

            let deadline = Self.rootDeadline(now: Date(), started: started, rules: rules)
            let outcome = await discoverCandidates(inRoot: root, deadline: deadline, progress: progress)
            switch outcome {
            case .root(let hits):
                found.append(contentsOf: hits.map { (path: $0.path, root: root, deadline: deadline) })
            case .truncated(let hits):
                complete = false
                truncated.append(root)
                found.append(contentsOf: hits.map { (path: $0.path, root: root, deadline: deadline) })
            case .inaccessible(let hits):
                complete = false
                inaccessible.append(root)
                found.append(contentsOf: hits.map { (path: $0.path, root: root, deadline: deadline) })
            }
        }

        // 去重后按深度升序处理：父先于子。嵌套标记照 Mole filter_nested_artifacts 的
        // 单次遍历口径——祖先本身也是候选时，子候选只标不量、不重复计体积。
        let uniquePaths = Array(Set(found.map(\.path)))
        let nested = Self.nestedFlags(paths: uniquePaths)
        var infoByPath: [String: (root: String, deadline: Date)] = [:]
        for hit in found where infoByPath[hit.path] == nil {
            infoByPath[hit.path] = (hit.root, hit.deadline)
        }

        let ordered = uniquePaths.sorted { lhs, rhs in
            let left = lhs.split(separator: "/").count
            let right = rhs.split(separator: "/").count
            return left != right ? left < right : lhs < rhs
        }

        var artifacts: [ProjectArtifact] = []
        var outOfRoot = 0
        for path in ordered {
            guard let info = infoByPath[path] else { continue }
            // 物理包含校验：词面前缀不算包含（抄 Mole is_safe_project_artifact 的
            // 动机）——一个指到根外的符号链接祖先就能把"清理产物"变成"清理 /etc"。
            // 发现遍历本身不跟随符号链接，这里是成案前的再验证，双保险。
            // 复用行也要过这一关：上次的安全不等于这次的安全，符号链接随时可能改指。
            guard Self.validateContainment(candidate: path, searchRoot: info.root,
                                           resolving: Self.physicalPath(of:)) else {
                outOfRoot += 1
                continue
            }
            // 复用放在时限检查**之前**：这一行不花预算，时限到了也照样把上一批量完的
            // 结果留下。反过来（先查时限）会让续扫把已经看到的行退回成"—"，
            // 用户按一次「继续」反而少了几行。
            // 完成度在这里再筛一遍，不信任调用方：漏筛的后果是"读不到"那行永远
            // 留在清单上，按多少次继续都不会有人去重测它。
            if let prior = reuse[path], Self.isCompleteObservation(prior) {
                artifacts.append(prior.withNestedFlag(nested.contains(path)))
                continue
            }
            if Task.isCancelled || Date() >= info.deadline {
                complete = false
                if !truncated.contains(info.root) { truncated.append(info.root) }
                continue
            }
            let processed = await process(path: path, searchRoot: info.root,
                                          deadline: info.deadline, isNested: nested.contains(path))
            artifacts.append(processed.artifact)
            // §8.6 的修法（调研 §4.2）：上面那条 deadline 前置检查只看"处理前已超时"，
            // 超时恰好落在最后一个候选的 process() 中间时，旧写法会让根进 scannedRoots、
            // 组里却挂着「读不到（预算用尽）」。合并遍历把"这一行有没有因预算没出结论"
            // 变成显式字段，就地补记进截断账本——"根扫完 = 每个候选都出了结论"。
            // 权限性读不进（unreadableDirectories 非空但 stopReason==nil）是已出的
            // fail-closed 结论，不走这条路，根不必因此截断。
            if processed.budgetIncomplete {
                complete = false
                if !truncated.contains(info.root) { truncated.append(info.root) }
            }
        }

        // 走完 = 被遍历过、且既没截断也没读不动。三个列表之间不允许同一根既
        // "已扫描"又"被截断"，否则 UI 无从判断该不该说"完整"。
        let compromised = Set(truncated).union(inaccessible)
        let honestScanned = Set(walked).subtracting(compromised)

        return ProjectArtifactReport(
            groups: Self.group(artifacts: artifacts, home: home),
            scannedRoots: roots.filter { honestScanned.contains($0) }.sorted(),
            truncatedRoots: truncated,
            inaccessibleRoots: inaccessible,
            missingRoots: missing,
            outOfSearchRootCandidateCount: outOfRoot,
            isComplete: complete,
            duration: Date().timeIntervalSince(started)
        )
    }

    // MARK: - 搜索根发现

    /// 显式配置的根 + home 深度 1 的容器目录。
    private func expandedSearchRoots() -> [String] {
        var roots = rules.searchRoots
        guard Self.directoryExists(home), FileTreeWalker.canEnumerate(path:home) else {
            return roots
        }
        for entry in Self.listAllEntries(path: home) where entry.isDirectory {
            if Task.isCancelled { break }
            if Self.isDiscoverableContainer(name: entry.name, artifactNames: rules.artifactNames) {
                roots.append(entry.path)
            }
        }
        return roots
    }

    /// 容器目录准入：隐藏目录、系统目录、以及**本身就是产物的名字**都拒绝。
    /// 最后一条是 Mole #1459 的教训：一个 stray 的 `~/node_modules` 若被当容器扫，
    /// 里面每个包都有 package.json（第一个项目标志），包内的 dist/build 会被列成
    /// "项目产物"——删掉它们留下 package.json，npm 却说一切正常，恢复要联网。
    public nonisolated static func isDiscoverableContainer(name: String, artifactNames: Set<String>) -> Bool {
        if name.hasPrefix(".") { return false }
        if ProjectArtifactNames.nonContainerDirectories.contains(name) { return false }
        if artifactNames.contains(name) { return false }
        return true
    }

    /// 大小写去重。macOS APFS 默认大小写不敏感，`~/Code` 与 `~/code` 是同一个目录，
    /// 列两遍就会让同一个项目在 UI 上出现两次（Mole #1416）。去重键必须来自
    /// 文件系统真实拼写（真机用 realpath），不能拿 String 自己比大小写。
    public nonisolated static func dedupeRoots(_ paths: [String], resolving: (String) -> String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            let resolved = resolving(path)
            if seen.insert(resolved).inserted {
                result.append(resolved)
            }
        }
        return result
    }

    // MARK: - 发现遍历

    private enum DiscoveryOutcome {
        case root([FileTreeWalker.Entry])
        case truncated([FileTreeWalker.Entry])
        case inaccessible([FileTreeWalker.Entry])
    }

    /// 从搜索根向下的有界遍历：深度 [minDepth, maxDepth]、时限 rootBudgetSeconds、
    /// 可取消。命中产物目录后**不再下潜**——它是候选整体，里面的嵌套物由
    /// nestedFlags 标注，不在这里二次枚举（也避开 node_modules 的百万小文件）。
    private func discoverCandidates(inRoot root: String, deadline: Date,
                                    progress: (@Sendable (String) -> Void)?) async -> DiscoveryOutcome {
        let rootEntries = Self.listAllEntries(path: root)
        // 深度 0 的唯一豁免条件：根本身就是项目根（单项目模式的搜索根）。
        let rootIsProject = Self.isProjectRoot(entries: Set(rootEntries.map(\.name)),
                                               indicators: rules.projectIndicators)
        var level = 0
        var current = rootEntries
        var hits: [FileTreeWalker.Entry] = []

        while true {
            level += 1
            // level 是"相对根的段数"，候选深度 = level - 1。
            if level - 1 > rules.maxDepth { return .root(hits) }
            var directories: [FileTreeWalker.Entry] = []
            for entry in current {
                if Task.isCancelled || Date() >= deadline { return .truncated(hits) }
                progress?(entry.path)
                if entry.isDirectory, rules.artifactNames.contains(entry.name),
                   Self.isDepthAllowed(candidate: entry.path, searchRoot: root,
                                       minDepth: rules.minDepth, rootIsProject: rootIsProject) {
                    hits.append(entry)
                } else if entry.isDirectory, level <= rules.maxDepth {
                    directories.append(entry)
                }
            }
            if directories.isEmpty { return .root(hits) }
            var next: [FileTreeWalker.Entry] = []
            for dir in directories {
                if Task.isCancelled || Date() >= deadline { return .truncated(hits) }
                guard FileTreeWalker.canEnumerate(path:dir.path) else { return .inaccessible(hits) }
                next.append(contentsOf: Self.listAllEntries(path: dir.path))
            }
            current = next
        }
    }

    // MARK: - 单候选成案

    /// 成案一个候选。返回的 `budgetIncomplete` 是 §8.6 修法的数据源：
    /// 该候选的合并遍历因预算（deadline/取消）没出结论——只有这种事把根记进截断；
    /// 权限性"读不到（非预算）"是已出的结论，不截断（调研 §4.2）。
    private func process(path: String, searchRoot root: String, deadline: Date,
                         isNested: Bool) async -> (artifact: ProjectArtifact, budgetIncomplete: Bool) {
        let name = (path as NSString).lastPathComponent
        let parent = (path as NSString).deletingLastPathComponent
        let siblings = Set(Self.listAllEntries(path: parent).map(\.name))

        // 项目根解析：monorepo 边界优先，让 workspace 里的产物归到同一个根。
        let resolved = Self.resolveProjectRoot(
            forArtifactPath: path,
            indicators: rules.projectIndicators,
            monorepoIndicators: rules.monorepoIndicators,
            listDir: { Self.directoryNames($0) },
            maxUp: rules.projectRootMaxUp
        )
        let projectRoot = resolved.root ?? parent
        let relative = path.hasPrefix(projectRoot + "/")
            ? String(path.dropFirst(projectRoot.count + 1))
            : name

        // 读不进候选目录本身：无法验证 .git / keypair 这类作者内容，
        // fail closed 成 protected，绝不默认"没读到就当没有"。
        let readable = FileTreeWalker.canEnumerate(path:path)
        let ownChildren = readable ? Set(Self.listAllEntries(path: path).map(\.name)) : []
        let verdict: ArtifactVerdict
        if readable {
            verdict = Self.verdict(
                name: name,
                path: path,
                siblings: siblings,
                ownChildren: ownChildren,
                ancestors: Self.ancestors(of: path),
                hasCacheDirectoryTag: Self.hasValidCacheDirectoryTag(
                    firstLine: cacheDirectoryTagFirstLine(in: path)
                ),
                projectRoot: resolved.root,
                hasRailsApplicationFile:
                    FileManager.default.fileExists(atPath: parent + "/config/application.rb")
            )
        } else {
            verdict = .protected(reason: "读不进产物目录，无法确认里面没有签入的源码")
        }

        let rootModified = FileTreeWalker.modificationDate(ofPath: path)
        // 两趟并一趟（调研 §3.3）：旧写法对同一候选跑 activityProbe 全趟 + stats 全趟，
        // 换成 FileTreeWalker.walkForArtifact 的一趟并两套记账。
        // 非嵌套 needSize=true（体积+活动同趟走完、不早退）；嵌套 needSize=false
        // （只要活动，保留旧 probe 的早退——§3.2：近期在用的大嵌套目录不许从近免费变全量）。
        // deadline 检查进了 walk 内部（每目录一次，沿用旧 probe 的粒度），
        // Self.bounded 的竞速对这条路径退役：不再出现"stats 白跑一段被丢弃"。
        let walk: FileTreeWalker.SubtreeWalk? = readable
            ? await FileTreeWalker.walkForArtifact(
                path: path,
                deadline: deadline,
                recentThreshold: now.addingTimeInterval(-Double(rules.minAgeDays) * 86_400),
                needSize: !isNested)
            : nil

        let probe: ActivityProbe
        if !readable {
            probe = .incomplete("产物目录读不进去：\(path)")
        } else if rootModified == nil {
            probe = .incomplete("产物目录时间读不到：\(path)")
        } else {
            probe = Self.activityProbeResult(from: walk!, path: path)
        }
        let activity = Self.activity(rootModified: rootModified, probe: probe,
                                     now: now, minAgeDays: rules.minAgeDays)

        var size: UInt64? = nil
        var fileCount = 0
        // 嵌套产物不单独量：体积已经在祖先候选那里整体计入，再量一遍就是重复计数。
        // 预算内没量完（stopReason 非空）→ nil 显示"—"，绝不拿部分和冒充完整数字；
        // 子树内部读不进仍按 stats 现口径静默计 0（§4.2(b) 的收紧待拍板，本轮不做）。
        if let walk, let measured = Self.measuredSize(from: walk, isNested: isNested) {
            size = measured.size
            fileCount = measured.fileCount
        }

        return (ProjectArtifact(
            path: path, name: name, projectRoot: projectRoot, relativeToProject: relative,
            monorepoIndicator: resolved.monorepo, size: size, fileCount: fileCount,
            lastTouched: rootModified, verdict: verdict, activity: activity,
            isNestedInAnotherArtifact: isNested, sourceRoot: root
        ), budgetIncomplete: walk.map { Self.budgetIncomplete(from: $0) } ?? false)
    }

    /// 有界活动遍历：时限 + 可取消，碰到一个阈值内改动过的文件就早退。
    /// 只有**完整跑完**才许 `.noRecentFile`；超时/读不动一律 `.incomplete`，
    /// 由 `activity` 映射成 unknown——unknown 不是"很久没碰"，UI 别读错。
    ///
    /// 保留说明（P6.3b）：成案路径已改走 `FileTreeWalker.walkForArtifact`（两趟并一趟），
    /// 本函数不再被 `process()` 调用，留作合并口**双跑对拍**的参考实现
    /// （调研 §7 第 2 步：合并结果必须与它逐字段相等，不等价就是纪律 2 的事故口径）。
    func activityProbe(in path: String, deadline: Date) async -> ActivityProbe {
        let threshold = now.addingTimeInterval(-Double(rules.minAgeDays) * 86_400)
        var stack = [path]
        while let dir = stack.popLast() {
            if Task.isCancelled || Date() >= deadline {
                return .incomplete("活动探测超时/被取消：\(path)")
            }
            let entries = Self.listAllEntries(path: dir)
            if entries.isEmpty, Self.directoryExists(dir), !FileTreeWalker.canEnumerate(path:dir) {
                // 目录存在却一条都列不出来：读不动，不是"没碰过"。
                return .incomplete("读不动：\(dir)")
            }
            for entry in entries {
                if entry.isDirectory {
                    stack.append(entry.path)
                } else if entry.modificationDate >= threshold {
                    return .recentFileFound
                }
            }
        }
        return .noRecentFile
    }

    /// 合并遍历 → 活动探测三态（调研 §4.3 映射表；步骤 1 的纯派生函数）。
    /// 优先级即 fail-closed 顺序：预算没走完 → 读不进 → 近期文件 → 完整无近期。
    /// 理由字符串与旧 `activityProbe` **逐字相同**——它们经 `activity` 进 UI 的
    /// unknown 文案，不许漂。
    nonisolated static func activityProbeResult(from walk: FileTreeWalker.SubtreeWalk,
                                                path: String) -> ActivityProbe {
        if walk.stopReason != nil {
            return .incomplete("活动探测超时/被取消：\(path)")
        }
        if let dir = walk.unreadableDirectories.first {
            return .incomplete("读不动：\(dir)")
        }
        return walk.sawRecentFile ? .recentFileFound : .noRecentFile
    }

    /// 合并遍历 → 体积结论。嵌套恒 nil（体积在祖先处整体计入）；
    /// stopReason 非空 = 预算内没量完 → nil 显示"—"，绝不拿部分和冒充完整数字。
    /// `unreadableDirectories` 非空但 stopReason==nil 时**照旧给数字**（读不进的
    /// 子目录静默计 0，与 stats/其它页一致）——§4.2(b) 的 size=nil 收紧是待拍板项，本轮不做。
    nonisolated static func measuredSize(from walk: FileTreeWalker.SubtreeWalk,
                                         isNested: Bool) -> (size: UInt64, fileCount: Int)? {
        guard !isNested, walk.stopReason == nil else { return nil }
        return (walk.size, walk.fileCount)
    }

    /// 该候选是否因预算（deadline/取消）没出结论——根账本据此进 truncated（§8.6 修法）。
    /// 权限性读不进（unreadableDirectories 非空但 stopReason==nil）**不算**：
    /// 那是已出的 fail-closed 结论"读不到（非预算）"，重试只烧预算。
    nonisolated static func budgetIncomplete(from walk: FileTreeWalker.SubtreeWalk) -> Bool {
        walk.stopReason != nil
    }

    /// CACHEDIR.TAG 首行读取。必须是**普通文件**（lstat，符号链接不算，照 Mole
    /// 的 `[[ -f && ! -L ]]`），只读前 256 字节；读不到返回 nil，交给
    /// `hasValidCacheDirectoryTag` 这个纯函数分档。
    private func cacheDirectoryTagFirstLine(in dir: String) -> String? {
        let tagPath = dir + "/" + ProjectArtifactNames.cacheDirectoryTagName
        var info = stat()
        guard Darwin.lstat(tagPath, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        guard let handle = FileHandle(forReadingAtPath: tagPath) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n", omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
    }

    // MARK: - 纯函数面（单测主要打这些；全部 nonisolated，同步调用即可覆盖）

    /// 单个根的截止时刻：它自己的预算与整轮上限里更早的那个。
    /// 只给 per-root 预算，十几个根能等到几分钟；只给总时限（改之前的写法）
    /// 则排在后面的根一秒都拿不到——真机上被饿死的正是项目最密集的 ~/Documents。
    public nonisolated static func rootDeadline(now: Date, started: Date,
                                                rules: ProjectArtifactRules) -> Date {
        min(now.addingTimeInterval(rules.rootBudgetSeconds),
            started.addingTimeInterval(rules.totalBudgetSeconds))
    }

    /// 判定核心：输入全是名字集合与路径字符串，无 IO、无进程，可完整覆盖。
    /// 规则顺序即优先级：作者内容 > CACHEDIR.TAG > 名字 > 邻居证据 > 兜底 protected。
    /// - Parameters:
    ///   - siblings: 产物目录父目录里的条目名（清单文件证据）。
    ///   - ownChildren: 产物目录自己的条目名（.git / keypair / Debug/Release 证据）。
    ///   - ancestors: 由近及远的祖先目录路径，为后续规则保留；当前规则只用
    ///     siblings/ownChildren 两级证据，宁窄勿宽。
    ///   - hasRailsApplicationFile: `<父目录>/config/application.rb` 是否存在，
    ///     由扫描器读取后传入——纯函数不碰文件系统。
    ///   - projectRoot: 已解析的项目根；nil 表示周围找不到任何项目标志。
    public nonisolated static func verdict(name: String, path: String,
                                           siblings: Set<String>,
                                           ownChildren: Set<String>,
                                           ancestors: [String],
                                           hasCacheDirectoryTag: Bool,
                                           projectRoot: String?,
                                           hasRailsApplicationFile: Bool = false) -> ArtifactVerdict {
        // 作者内容优先，压在上面所有名字规则之上（含 CACHEDIR.TAG）：
        // 产物目录里有 .git 就可能是签出的源码，不是产物。
        if ownChildren.contains(".git") {
            return .protected(reason: "产物目录内有 .git：可能是签出的源码，不是产物")
        }
        if ownChildren.contains(where: { $0.hasSuffix("-keypair.json") }) {
            return .protected(reason: "产物目录内有部署密钥文件（*-keypair.json），不是纯构建产物")
        }
        // 云同步目录整层不给删：删除会同步到其它设备，而且 `DeletionGuard` 本来就把
        // `~/Library/CloudStorage` 挡在门外。扫描器若在这里还判"可回收"，UI 就会摆出
        // 一个必然失败的勾选框——两道闸门必须说同一句话。
        if isCloudSyncedPath(path) {
            return .protected(reason: "位于 iCloud 同步目录：删除会同步到所有设备")
        }
        if hasCacheDirectoryTag {
            return .reclaimable(.cacheDirectoryTag)
        }

        if ProjectArtifactNames.nameIsEnough.contains(name) {
            return .reclaimable(.nameIsEnough)
        }

        switch name {
        case "bin", "obj":
            // .NET 构建输出 = 旁边有项目文件 且 内含 Debug/Release 子目录，缺一不可。
            let hasDotnetProject = siblings.contains { sibling in
                sibling.hasSuffix(".csproj") || sibling.hasSuffix(".fsproj") || sibling.hasSuffix(".vbproj")
            }
            let hasConfigDir = ownChildren.contains("Debug") || ownChildren.contains("Release")
            if hasDotnetProject, hasConfigDir {
                return .reclaimable(.contextProven(".NET 构建输出：旁边有 csproj/fsproj/vbproj，且内含 Debug/Release"))
            }
            return .protected(reason: "\(name)/ 旁边没有 .csproj：无法确定它是构建输出")

        case "vendor":
            if siblings.contains("composer.json") {
                return .reclaimable(.contextProven("PHP Composer 依赖，可 composer install 重建"))
            }
            if siblings.contains("go.mod")
                || (siblings.contains("Gemfile") && hasRailsApplicationFile) {
                return .protected(reason: "Go/Rails 的 vendor/ 是源码的一部分")
            }
            return .protected(reason: "vendor/ 的来历不明，保守不动")

        case "target":
            // Rust/Maven 的 target 永远与 Cargo.toml/pom.xml 同级，父目录证据足够。
            if siblings.contains("Cargo.toml") || siblings.contains("pom.xml") {
                return .reclaimable(.contextProven("Rust/Maven 构建输出：旁边有 Cargo.toml/pom.xml，可重新构建"))
            }
            return .protected(reason: "target/ 旁没有 Cargo.toml/pom.xml")

        case "build", "dist", "coverage":
            // 云同步的那部分在上面已经拦下了，这里只管"名字像产物但可能签入仓库"。
            if siblings.contains("package.json") {
                return .reclaimable(.contextProven("JS 构建输出：项目里有 package.json，可重新构建"))
            }
            return .protected(reason: "build/dist/coverage 可能是签入仓库的目录")

        case "DerivedData":
            if path.contains("/Library/Developer/Xcode/DerivedData") {
                return .protected(reason: "这是 Xcode 的全局缓存，由 Xcode 自己管")
            }
            if projectRoot != nil {
                return .reclaimable(.contextProven("项目目录内的 DerivedData，Xcode 可重建"))
            }
            return .protected(reason: "DerivedData 周围找不到项目根")

        default:
            // 名单被改宽时的兜底：没有专门规则的新名字拿不到可回收证据。
            return .protected(reason: "仅凭目录名 \(name) 无法确认它是可重建产物")
        }
    }

    /// 三态活动时间。`rootModified` 缺失、探测 `incomplete` 都归 unknown，
    /// 绝不折成 `untouchedForDays`——那是把"没查到"渲染成"建议删除"。
    public nonisolated static func activity(rootModified: Date?, probe: ActivityProbe,
                                            now: Date, minAgeDays: Int) -> ArtifactActivity {
        guard let rootModified else {
            return .unknown("读不到产物目录自身的修改时间")
        }
        let threshold = now.addingTimeInterval(-Double(minAgeDays) * 86_400)
        // 未来时间（时钟漂移）按"刚刚用过"处理，偏向不删。
        let daysOld = max(0, Int(now.timeIntervalSince(rootModified) / 86_400))
        if rootModified >= threshold {
            return .touchedDaysAgo(daysOld)
        }
        switch probe {
        case .recentFileFound:
            // 目录 mtime 旧但里面有近期改动的文件：近期用过（具体几天未知，取 0）。
            return .touchedDaysAgo(0)
        case .noRecentFile:
            return .untouchedForDays(daysOld)
        case .incomplete(let reason):
            return .unknown(reason)
        }
    }

    /// 按项目根分组。聚合口径：
    /// - 组按 projectRoot 字典序，组内产物按路径字典序；
    /// - 嵌套产物与 protected 产物不计入 `reclaimableSize`；
    /// - 计入范围内**任何一个没测到体积**，整组就是 nil，不折 0。
    public nonisolated static func group(artifacts: [ProjectArtifact], home: String) -> [ProjectArtifactGroup] {
        let buckets = Dictionary(grouping: artifacts, by: \.projectRoot)
        return buckets.keys.sorted().map { root in
            let items = buckets[root]!.sorted { $0.path < $1.path }
            let indicator = items.compactMap(\.monorepoIndicator).first
            var reclaimable: UInt64 = 0
            var unknownSize = false
            for item in items {
                guard !item.isNestedInAnotherArtifact, case .reclaimable = item.verdict else { continue }
                if let size = item.size {
                    reclaimable += size
                } else {
                    unknownSize = true
                }
            }
            return ProjectArtifactGroup(
                projectRoot: root,
                displayName: (root as NSString).lastPathComponent,
                relativeToHome: abbreviate(root, against: home),
                isMonorepo: indicator != nil,
                monorepoIndicator: indicator,
                isCloudSynced: isCloudSyncedPath(root),
                artifacts: items,
                reclaimableSize: unknownSize ? nil : reclaimable
            )
        }
    }

    public nonisolated static func isProjectRoot(entries: Set<String>, indicators: Set<String>) -> Bool {
        !entries.isDisjoint(with: indicators)
    }

    /// 由产物向上找归属项目根：monorepo 边界优先（workspace 里所有产物归同一个根，
    /// 对应 Mole find_purge_project_root_for_artifact），其次第一个带项目标志的祖先。
    /// 找不到返回 nil——上下文类规则拿不到根，判定自然落到 protected。
    public nonisolated static func resolveProjectRoot(forArtifactPath: String,
                                                      indicators: Set<String>,
                                                      monorepoIndicators: Set<String>,
                                                      listDir: (String) -> Set<String>,
                                                      maxUp: Int) -> (root: String?, monorepo: String?) {
        var current = (forArtifactPath as NSString).deletingLastPathComponent
        var projectRoot: String? = nil
        var step = 0
        while current != "/", !current.isEmpty, step < maxUp {
            let entries = listDir(current)
            if let mono = monorepoIndicators.sorted().first(where: { entries.contains($0) }) {
                return (current, mono)
            }
            if projectRoot == nil, indicators.contains(where: { entries.contains($0) }) {
                projectRoot = current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
            step += 1
        }
        return (projectRoot, nil)
    }

    /// 深度准入。口径照 Mole：搜索根直接子项为深度 0。
    /// 低于 `minDepth` 的唯一豁免是"根本身就是项目根"（单项目模式）——
    /// 否则一个 `~/Code/node_modules` 式的散置目录会被当普通项目产物扫掉。
    public nonisolated static func isDepthAllowed(candidate: String, searchRoot: String,
                                                  minDepth: Int, rootIsProject: Bool) -> Bool {
        let root = trimTrailingSlash(searchRoot)
        guard candidate.hasPrefix(root + "/") else { return false }
        let depth = candidate.dropFirst(root.count + 1).split(separator: "/").count - 1
        if depth >= minDepth { return true }
        return depth == 0 && rootIsProject
    }

    /// 词面 + 物理双重包含校验（抄 Mole `is_safe_project_artifact` 的动机）：
    /// lexical 前缀不算包含——一个 `GOMODCACHE=../../etc` 式越界就能把清理变成误删。
    /// 两侧都解析后仍互为包含才放行；搜索根不允许是 `/`——那让任何前缀校验形同虚设。
    public nonisolated static func validateContainment(candidate: String, searchRoot: String,
                                                       resolving: (String) -> String) -> Bool {
        let root = trimTrailingSlash(searchRoot)
        guard root.hasPrefix("/") else { return false }
        guard candidate.hasPrefix(root + "/") else { return false }
        let physicalRoot = resolving(root)
        let physicalCandidate = resolving(candidate)
        guard physicalRoot != "/" else { return false }
        return physicalCandidate.hasPrefix(physicalRoot + "/")
    }

    /// CACHEDIR.TAG 签名逐字符相等才算。差一个字符就不是这个协议，
    /// 前缀匹配会把用户随手写的一个文件当成"最强可回收证据"。
    public nonisolated static func hasValidCacheDirectoryTag(firstLine: String?) -> Bool {
        firstLine == ProjectArtifactNames.cacheDirectoryTagSignature
    }

    /// 嵌套去重（对应 Mole `filter_nested_artifacts`）：按路径字典序排
    /// （Swift String.compare 的 Unicode 标量序与 LC_COLLATE=C 的 ASCII 行为一致），
    /// 单次遍历：当前路径以"上一个保留项"为祖先目录则标 nested。
    /// `/a/bin` 与 `/a/bin2` 只是词面前缀不是祖先，用 `kept + "/"` 卡死边界。
    public nonisolated static func nestedFlags(paths: [String]) -> Set<String> {
        var lastKept: String? = nil
        var nested: Set<String> = []
        for path in paths.sorted() {
            if let kept = lastKept, path.hasPrefix(kept + "/") {
                nested.insert(path)
            } else {
                lastKept = path
            }
        }
        return nested
    }

    /// 云同步目录判定（词面口径，同 Mole 的 case 匹配）：iCloud Drive 与
    /// Mobile Documents。这两处的 build/dist 常常是仓库签入内容的一部分。
    nonisolated static func isCloudSyncedPath(_ path: String) -> Bool {
        path.contains("/Library/CloudStorage") || path.contains("/Library/Mobile Documents")
    }

    // MARK: - 分批续扫：合并与调度（纯函数；口径见 docs/analysis/dev-artifact-continuation.md §4）

    /// 一次观测是否"看完证据了"——续扫复用的准入判据。
    /// 只问这两条：体积没量到（预算耗尽或读不动）、活动探测没跑完（`.unknown`）。
    /// "读不进产物目录"那档兜底 protected 必然同时中这两条（`process` 里 readable=false
    /// 就不量体积、probe 直接 `.incomplete`），所以不必再比对理由字符串——那会很脆弱。
    public nonisolated static func isCompleteObservation(_ artifact: ProjectArtifact) -> Bool {
        guard artifact.size != nil else { return false }
        if case .unknown = artifact.activity { return false }
        return true
    }

    /// 下一批要重跑的根。**只挑被截断的**：读不动是权限事实，重试只烧预算；
    /// 压根不存在的根没什么可扫。顺序沿用报表里的根顺序（根的先后就是预算的分配先后）。
    public nonisolated static func rootsToContinue(report: ProjectArtifactReport) -> [String] {
        report.truncatedRoots
    }

    /// 每个根试过几次：**只有这一批真正跑过的根**才动计数。
    /// 上一批截断、这一批没续扫的根必须原样留着次数，否则每续扫一次别的根，
    /// 它就白捡一次重试机会，「两次就改口」的上限形同虚设。
    /// 计数只活在内存里，不跨启动——它唯一的作用是"这个根在预算内就是扫不完"那句改口。
    public nonisolated static func attemptCounts(rootsRun: [String], stillTruncated: Set<String>,
                                                 previous: [String: Int]) -> [String: Int] {
        var counts = previous
        for root in Set(rootsRun) {
            if stillTruncated.contains(root) { counts[root, default: 0] += 1 }
            else { counts[root] = nil }
        }
        return counts
    }

    /// 根账本的并：旧账里没被续扫的根先留下（**保持原顺序**，排序等于改掉预算分配顺序），
    /// 再接新账。`continued` 只从旧账里摘，不挡新账——新账里的根本来就都在 `continued` 里。
    nonisolated static func mergedRootList(_ previous: [String], continued: Set<String>,
                                           adding next: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for root in previous where continued.contains(root) == false && seen.insert(root).inserted {
            out.append(root)
        }
        for root in next where seen.insert(root).inserted {
            out.append(root)
        }
        return out
    }

    /// 合并两批报表。四条规矩，缺一条报表就假：
    /// 1. 被续扫的根**整区替换**（按 `sourceRoot` 分区）：这一区以第二批为准，
    ///    第二批没再发现的行（目录被删了、改名了）就此消失，不留旧行骗人；
    /// 2. `nestedFlags` 在**候选全集**上重算：第一批量完的父和第二批才发现的子凑到一起，
    ///    不重算就是同一坨体积计两遍（§4.3）；
    /// 3. `group` 重跑：monorepo 边界可能第二批才发现，同一 workspace 会裂成两组（§4.4）；
    /// 4. 根账本先摘掉被续扫的根再并，让"一个根只出现在 scanned / truncated /
    ///    inaccessible 之一"这条不变式在**合并这一步自己成立**，不依赖两张输入报表干净。
    ///    `missingRoots` 也要并进 `continued`：两批之间目录被删掉时，旧账里它还是
    ///    `truncated`，新账里是 `missing`——不摘就同一个根同时占两个账本。
    public nonisolated static func mergedReport(base: ProjectArtifactReport,
                                                continuation: ProjectArtifactReport,
                                                home: String) -> ProjectArtifactReport {
        let continued = Set(continuation.scannedRoots)
            .union(continuation.truncatedRoots)
            .union(continuation.inaccessibleRoots)
            .union(continuation.missingRoots)
        let kept = base.groups.flatMap(\.artifacts)
            .filter { continued.contains($0.sourceRoot) == false }

        // 同一个 path 只留一条，新观测覆盖旧观测：搜索根互相包含时（~/Repos 与
        // 单独配成根的 ~/Repos/app）同一目录会被两批各扫一次，留着两条就是同一行
        // 在清单上出现两遍。
        var byPath: [String: ProjectArtifact] = [:]
        for artifact in kept { byPath[artifact.path] = artifact }
        for artifact in continuation.groups.flatMap(\.artifacts) { byPath[artifact.path] = artifact }
        let nested = nestedFlags(paths: Array(byPath.keys))
        let artifacts = byPath.keys.sorted().map { path in
            byPath[path]!.withNestedFlag(nested.contains(path))
        }

        let truncated = mergedRootList(base.truncatedRoots, continued: continued,
                                       adding: continuation.truncatedRoots)
        let inaccessible = mergedRootList(base.inaccessibleRoots, continued: continued,
                                          adding: continuation.inaccessibleRoots)
        let compromised = Set(truncated).union(inaccessible)
        return ProjectArtifactReport(
            groups: group(artifacts: artifacts, home: home),
            scannedRoots: mergedRootList(base.scannedRoots, continued: continued,
                                         adding: continuation.scannedRoots)
                .filter { compromised.contains($0) == false },
            truncatedRoots: truncated,
            inaccessibleRoots: inaccessible,
            missingRoots: mergedRootList(base.missingRoots, continued: continued,
                                         adding: continuation.missingRoots)
                .filter { compromised.contains($0) == false },
            outOfSearchRootCandidateCount: base.outOfSearchRootCandidateCount
                + continuation.outOfSearchRootCandidateCount,
            isComplete: compromised.isEmpty,
            duration: base.duration + continuation.duration
        )
    }

    /// 最近一批**补全**的行：这一批看完证据（体积量到、活动度探到）、而上一批要么没报过
    /// 这一行、要么报过但没看全。组头的「第 N 批补全」按这个点名，不按"这一组的根有没有
    /// 被重跑"——根重跑过而组里每行都是整行复用，"补全"就是在报一件没发生过的事；
    /// 重测完还是「读不到」的那行也不算，它这批复刻的还是上一批的结论。
    public nonisolated static func rowsCompletedByBatch(base: ProjectArtifactReport,
                                                        merged: ProjectArtifactReport) -> Set<String> {
        func complete(_ report: ProjectArtifactReport) -> Set<String> {
            Set(report.groups.flatMap(\.artifacts)
                .filter { isCompleteObservation($0) }.map(\.id))
        }
        return complete(merged).subtracting(complete(base))
    }

    /// 续扫之后还剩什么可删：勾选要按"合并后仍然 `isSelectable`"修剪（§5.1）。
    /// 判据不是"路径还在"——被重标成"已计入上一行"的路径还在，但勾选框必须消失，
    /// 留着就是「已选 X GB」虚高。`isSelectable` 住在 MMCleaner（它才知道 UI 的口径），
    /// 所以这里只做"按 id 集合修剪"，谁可选由调用方给判据。
    public nonisolated static func survivingSelection(_ selected: Set<String>,
                                                      report: ProjectArtifactReport,
                                                      isSelectable: (ProjectArtifact) -> Bool) -> Set<String> {
        var kept = Set<String>()
        for artifact in report.groups.flatMap(\.artifacts) where selected.contains(artifact.id) {
            if isSelectable(artifact) { kept.insert(artifact.id) }
        }
        return kept
    }

    // MARK: - 遍历与路径工具

    /// 与 FileTreeWalker.readEntries **同一份 lstat 口径**（单次 lstat、不跟随符号
    /// 链接、目录不取大小），但保留 `.` 开头的条目：.venv、.build、node_modules 里的
    /// .bin 恰恰是目标，readEntries 的"跳过隐藏条目"规则在这里用不得。
    /// **体积测量一律走 FileTreeWalker.stats**，不另建第二套求和口径。
    nonisolated static func listAllEntries(path: String) -> [FileTreeWalker.Entry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [FileTreeWalker.Entry] = []
        entries.reserveCapacity(names.count)
        for name in names {
            if Task.isCancelled { break }
            let fullPath = path + "/" + name
            var info = stat()
            guard Darwin.lstat(fullPath, &info) == 0 else { continue }
            // 符号链接既不向下走也不计体积，直接跳过。
            if (info.st_mode & S_IFMT) == S_IFLNK { continue }
            let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            entries.append(FileTreeWalker.Entry(
                name: name,
                path: fullPath,
                isDirectory: isDirectory,
                size: isDirectory ? 0 : UInt64(info.st_size),
                modificationDate: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                                       + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
            ))
        }
        return entries
    }

    private nonisolated static func directoryNames(_ path: String) -> Set<String> {
        Set(listAllEntries(path: path).map(\.name))
    }

    /// realpath(3)：返回文件系统真实拼写并解全部符号链接。
    /// 路径不存在时回落词面标准化——调用方只在"存在性已确认"处用它做包含校验。
    nonisolated static func physicalPath(of path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil {
            return String(cString: buffer)
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .resolvingSymlinksInPath().path
    }

    private nonisolated static func ancestors(of path: String) -> [String] {
        var result: [String] = []
        var current = (path as NSString).deletingLastPathComponent
        while current != "/", !current.isEmpty {
            result.append(current)
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return result
    }

    private nonisolated static func trimTrailingSlash(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private nonisolated static func abbreviate(_ path: String, against home: String) -> String {
        let h = trimTrailingSlash(home)
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + String(path.dropFirst(h.count)) }
        return path
    }

    private nonisolated static func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
