import XCTest
import Foundation
@testable import MMFileScanner

/// ProjectArtifactScanner 的判定核心必须是纯函数——这一屏能不能上线
/// 取决于每条 protected/reclaimable 规则都在单测里被正面打过，
/// 而不是靠真机扫一遍"看起来对"。最后一个真机临时目录集成测试
/// 防的是"夹具全对、真机全废"（样例用旧格式写、真机输出从没进过测试的坑）。
final class ProjectArtifactScannerTests: XCTestCase {

    // MARK: - 测试脚手架

    private let now = Date(timeIntervalSince1970: 1_800_000_000) // 固定"现在"，age 可精确断言

    private func verdict(name: String,
                         path: String = "/u/dev/app/x",
                         siblings: Set<String> = [],
                         ownChildren: Set<String> = [],
                         hasTag: Bool = false,
                         projectRoot: String? = "/u/dev/app",
                         rails: Bool = false) -> ArtifactVerdict {
        ProjectArtifactScanner.verdict(name: name, path: path, siblings: siblings,
                                       ownChildren: ownChildren, ancestors: [],
                                       hasCacheDirectoryTag: hasTag, projectRoot: projectRoot,
                                       hasRailsApplicationFile: rails)
    }

    private func expectProtected(_ verdict: ArtifactVerdict, containing needle: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard case .protected(let reason) = verdict else {
            XCTFail("期望 protected（含\"\(needle)\"），实际 \(verdict)", file: file, line: line)
            return
        }
        XCTAssertTrue(reason.contains(needle), "理由 \(reason) 不含 \(needle)", file: file, line: line)
    }

    private func expectReclaimable(_ verdict: ArtifactVerdict, _ evidence: ArtifactEvidence,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(verdict, .reclaimable(evidence), file: file, line: line)
    }

    private func artifact(path: String, root: String,
                          searchRoot: String? = nil,
                          verdict: ArtifactVerdict = .reclaimable(.nameIsEnough),
                          size: UInt64? = 100, nested: Bool = false,
                          monorepo: String? = nil,
                          activity: ArtifactActivity = .untouchedForDays(30)) -> ProjectArtifact {
        ProjectArtifact(path: path, name: (path as NSString).lastPathComponent,
                        projectRoot: root, relativeToProject: String(path.dropFirst(root.count + 1)),
                        monorepoIndicator: monorepo, size: size, fileCount: size == nil ? 0 : 1,
                        lastTouched: nil, verdict: verdict,
                        activity: activity, isNestedInAnotherArtifact: nested,
                        // 默认取"前三段"当搜索根：/u/dev/app/x → /u/dev。注意别漏掉
                        // 开头那个斜杠——split 会把空首段丢掉，拼出来就成了相对路径。
                        sourceRoot: searchRoot ?? "/" + path.split(separator: "/").prefix(3).joined(separator: "/"))
    }

    private func reportOf(_ artifacts: [ProjectArtifact], home: String = "/u",
                          scanned: [String] = [], truncated: [String] = [],
                          inaccessible: [String] = [], missing: [String] = [],
                          outOfRoot: Int = 0,
                          duration: TimeInterval = 1) -> ProjectArtifactReport {
        ProjectArtifactReport(
            groups: ProjectArtifactScanner.group(artifacts: artifacts, home: home),
            scannedRoots: scanned, truncatedRoots: truncated,
            inaccessibleRoots: inaccessible, missingRoots: missing,
            outOfSearchRootCandidateCount: outOfRoot,
            isComplete: truncated.isEmpty && inaccessible.isEmpty,
            duration: duration)
    }

    // MARK: - verdict：名字档

    func testNameIsEnoughForPlainArtifactNames() {
        for name in ["node_modules", ".venv", "venv", "__pycache__", ".build", "Pods", ".turbo"] {
            expectReclaimable(verdict(name: name), .nameIsEnough)
        }
    }

    func testGitInsideArtifactOutweighsEvenNodeModules() {
        // 名字规则之上还有作者内容规则：产物目录里的 .git 可能是签出的源码。
        let v = verdict(name: "node_modules", ownChildren: ["lib", ".git"])
        expectProtected(v, containing: ".git")
    }

    func testKeypairFileProtectsArtifact() {
        let v = verdict(name: ".next", ownChildren: ["static", "deploy-keypair.json"])
        expectProtected(v, containing: "keypair")
    }

    // MARK: - verdict：CACHEDIR.TAG

    func testValidCacheTagIsReclaimableForUnknownName() {
        expectReclaimable(verdict(name: "stuff", hasTag: true), .cacheDirectoryTag)
    }

    func testGitOutweighsCacheTag() {
        // fail closed：目录主说是缓存、但里面有 .git——保护规则压过最强可回收证据。
        expectProtected(verdict(name: "stuff", ownChildren: [".git"], hasTag: true), containing: ".git")
    }

    func testCacheTagSignatureMustMatchExactly() {
        let signature = "Signature: 8a477f597d28d172789f06886806bc55"
        XCTAssertTrue(ProjectArtifactScanner.hasValidCacheDirectoryTag(firstLine: signature))
        XCTAssertFalse(ProjectArtifactScanner.hasValidCacheDirectoryTag(firstLine: String(signature.dropLast())))
        XCTAssertFalse(ProjectArtifactScanner.hasValidCacheDirectoryTag(firstLine: "Signature: deadbeef"))
        XCTAssertFalse(ProjectArtifactScanner.hasValidCacheDirectoryTag(firstLine: nil))
    }

    // MARK: - verdict：bin / obj（.NET）

    func testBinWithCsprojAndConfigDirIsDotnetOutput() {
        let v = verdict(name: "bin", siblings: ["App.csproj", "App.sln"],
                        ownChildren: ["Debug", "net8.0"])
        expectReclaimable(v, .contextProven(".NET 构建输出：旁边有 csproj/fsproj/vbproj，且内含 Debug/Release"))
    }

    func testBinWithoutCsprojIsProtected() {
        expectProtected(verdict(name: "bin", ownChildren: ["Debug"]), containing: "无法确定它是构建输出")
    }

    func testBinWithCsprojButNoConfigDirStaysProtected() {
        // 两个证据缺一不可：只有 .csproj、bin/ 里没有 Debug/Release，不能断定是构建输出。
        expectProtected(verdict(name: "bin", siblings: ["App.csproj"], ownChildren: ["data"]),
                        containing: "无法确定它是构建输出")
    }

    func testObjFollowsSameDotnetRule() {
        expectReclaimable(verdict(name: "obj", siblings: ["Lib.fsproj"], ownChildren: ["Release"]),
                          .contextProven(".NET 构建输出：旁边有 csproj/fsproj/vbproj，且内含 Debug/Release"))
        expectProtected(verdict(name: "obj", ownChildren: ["Debug"]), containing: "obj/")
    }

    // MARK: - verdict：vendor 三种来历

    func testComposerVendorIsReclaimable() {
        let v = verdict(name: "vendor", siblings: ["composer.json"])
        expectReclaimable(v, .contextProven("PHP Composer 依赖，可 composer install 重建"))
    }

    func testGoVendorIsProtected() {
        expectProtected(verdict(name: "vendor", siblings: ["go.mod"]), containing: "Go/Rails")
    }

    func testRailsVendorIsProtected() {
        expectProtected(verdict(name: "vendor", siblings: ["Gemfile", "config"], rails: true),
                        containing: "Go/Rails")
        // 只有 Gemfile、没有 config/application.rb：不算 Rails 证据。
        expectProtected(verdict(name: "vendor", siblings: ["Gemfile"], rails: false),
                        containing: "来历不明")
    }

    func testUnknownVendorStaysProtected() {
        expectProtected(verdict(name: "vendor"), containing: "vendor/ 的来历不明，保守不动")
    }

    // MARK: - verdict：target

    func testTargetNeedsCargoOrPomSibling() {
        expectReclaimable(verdict(name: "target", siblings: ["Cargo.toml", "src"]),
                          .contextProven("Rust/Maven 构建输出：旁边有 Cargo.toml/pom.xml，可重新构建"))
        expectReclaimable(verdict(name: "target", siblings: ["pom.xml"]),
                          .contextProven("Rust/Maven 构建输出：旁边有 Cargo.toml/pom.xml，可重新构建"))
        expectProtected(verdict(name: "target", siblings: ["Makefile", "src"]),
                        containing: "target/ 旁没有 Cargo.toml/pom.xml")
    }

    // MARK: - verdict：build / dist / coverage

    func testBuildWithPackageJsonIsReclaimable() {
        let v = verdict(name: "build", path: "/u/dev/app/build", siblings: ["package.json"])
        expectReclaimable(v, .contextProven("JS 构建输出：项目里有 package.json，可重新构建"))
    }

    func testCloudSyncedBuildIsProtected() {
        // iCloud 那一层由 DeletionGuard 硬挡，扫描器必须提前给出同一个结论，
        // 否则 UI 上就是一个"能勾、删不掉"的假选项。
        let cloud = "/u/Library/CloudStorage/OneDrive/proj/dist"
        expectProtected(verdict(name: "dist", path: cloud, siblings: ["package.json"]),
                        containing: "iCloud 同步目录")
        expectProtected(verdict(name: "coverage", path: "/u/Library/Mobile Documents/proj/coverage",
                                siblings: ["package.json"]),
                        containing: "iCloud 同步目录")
    }

    func testCloudSyncedOutweighsNameAndCacheTag() {
        // 名字本身就够（node_modules）也不给过：这些目录在多个设备之间同步，
        // 在一台机器上删掉等于替所有设备删。带 CACHEDIR.TAG 同理。
        let cloudNM = "/u/Library/CloudStorage/Dropbox/team-site/node_modules"
        expectProtected(verdict(name: "node_modules", path: cloudNM), containing: "iCloud 同步目录")
        expectProtected(verdict(name: ".gradle", path: "/u/Library/CloudStorage/Dropbox/x/.gradle",
                                hasTag: true), containing: "iCloud 同步目录")
    }

    func testBuildWithoutPackageJsonIsProtected() {
        expectProtected(verdict(name: "build", siblings: ["README.md"]),
                        containing: "可能是签入仓库的目录")
    }

    // MARK: - verdict：DerivedData

    func testGlobalDerivedDataIsXcodeOwned() {
        expectProtected(verdict(name: "DerivedData",
                                path: "/u/Library/Developer/Xcode/DerivedData/App-abc123"),
                        containing: "由 Xcode 自己管")
    }

    func testProjectLocalDerivedDataIsReclaimable() {
        let v = verdict(name: "DerivedData", path: "/u/dev/app/DerivedData",
                        projectRoot: "/u/dev/app")
        expectReclaimable(v, .contextProven("项目目录内的 DerivedData，Xcode 可重建"))
        expectProtected(verdict(name: "DerivedData", path: "/u/dev/app/DerivedData",
                                projectRoot: nil),
                        containing: "找不到项目根")
    }

    func testUnknownNameNeverFabricatesVerdict() {
        // 名单被改宽时的兜底：没有专门证据就不硬凑"可回收"。
        expectProtected(verdict(name: "out"), containing: "仅凭目录名 out")
    }

    // MARK: - activity

    func testActivityOldWithCompleteProbeIsUntouched() {
        let old = now.addingTimeInterval(-40 * 86_400)
        XCTAssertEqual(ProjectArtifactScanner.activity(rootModified: old, probe: .noRecentFile,
                                                       now: now, minAgeDays: 7),
                       .untouchedForDays(40))
    }

    func testActivityRecentRootNeedsNoProbe() {
        let recent = now.addingTimeInterval(-2 * 86_400)
        XCTAssertEqual(ProjectArtifactScanner.activity(rootModified: recent, probe: .noRecentFile,
                                                       now: now, minAgeDays: 7),
                       .touchedDaysAgo(2))
    }

    func testActivityRecentFileInsideOldDirCountsAsRecent() {
        let old = now.addingTimeInterval(-40 * 86_400)
        XCTAssertEqual(ProjectArtifactScanner.activity(rootModified: old, probe: .recentFileFound,
                                                       now: now, minAgeDays: 7),
                       .touchedDaysAgo(0))
    }

    func testIncompleteProbeNeverBecomesUntouched() {
        // 这条是本枚举存在的意义：探测失败 ≠ 很久没碰。
        let old = now.addingTimeInterval(-40 * 86_400)
        let activity = ProjectArtifactScanner.activity(rootModified: old,
                                                       probe: .incomplete("探测超时"),
                                                       now: now, minAgeDays: 7)
        guard case .unknown(let reason) = activity else {
            return XCTFail("incomplete 必须映射为 unknown，实际 \(activity)")
        }
        XCTAssertTrue(reason.contains("超时"))
        // 读不到目录时间同样必须 unknown，不许借完整探测折成"没碰过"。
        if case .untouchedForDays = ProjectArtifactScanner.activity(
            rootModified: nil, probe: .noRecentFile, now: now, minAgeDays: 7) {
            XCTFail("nil 时间 + 完整探测也不能报 untouchedForDays")
        }
    }

    // MARK: - 项目根与容器

    func testIsProjectRoot() {
        XCTAssertTrue(ProjectArtifactScanner.isProjectRoot(entries: ["package.json", "src"],
                                                           indicators: ["package.json"]))
        XCTAssertFalse(ProjectArtifactScanner.isProjectRoot(entries: ["photos", "notes.txt"],
                                                            indicators: ["package.json"]))
    }

    func testResolveProjectRootPrefersMonorepoBoundary() {
        let dirs: [String: Set<String>] = [
            "/repo": ["pnpm-workspace.yaml", "package.json"],
            "/repo/pkg": ["package.json", "node_modules"],
        ]
        let result = ProjectArtifactScanner.resolveProjectRoot(
            forArtifactPath: "/repo/pkg/node_modules",
            indicators: ["package.json"], monorepoIndicators: ["pnpm-workspace.yaml"],
            listDir: { dirs[$0] ?? [] }, maxUp: 5)
        XCTAssertEqual(result.root, "/repo")
        XCTAssertEqual(result.monorepo, "pnpm-workspace.yaml")
    }

    func testResolveProjectRootFallsBackToNearestProject() {
        let dirs: [String: Set<String>] = ["/solo": ["Cargo.toml", "src"]]
        let result = ProjectArtifactScanner.resolveProjectRoot(
            forArtifactPath: "/solo/target/debug",
            indicators: ["Cargo.toml"], monorepoIndicators: ["nx.json"],
            listDir: { dirs[$0] ?? [] }, maxUp: 5)
        XCTAssertEqual(result.root, "/solo")
        XCTAssertNil(result.monorepo)
    }

    func testResolveProjectRootGivesUpWithinBudget() {
        let result = ProjectArtifactScanner.resolveProjectRoot(
            forArtifactPath: "/deep/a/b/c/bin",
            indicators: ["go.mod"], monorepoIndicators: ["nx.json"],
            listDir: { _ in [] }, maxUp: 3)
        XCTAssertNil(result.root)
        XCTAssertNil(result.monorepo)
    }

    func testContainerDiscoverySkipsHiddenSystemAndArtifactNamedDirs() {
        let artifacts = ProjectArtifactRules.default(home: "/u").artifactNames
        XCTAssertFalse(ProjectArtifactScanner.isDiscoverableContainer(name: ".hidden", artifactNames: artifacts))
        XCTAssertFalse(ProjectArtifactScanner.isDiscoverableContainer(name: "Library", artifactNames: artifacts))
        // Mole #1459：stray 的 ~/node_modules 绝不能当容器扫。
        XCTAssertFalse(ProjectArtifactScanner.isDiscoverableContainer(name: "node_modules", artifactNames: artifacts))
        XCTAssertFalse(ProjectArtifactScanner.isDiscoverableContainer(name: "vendor", artifactNames: artifacts))
        // Desktop 不跳：用户真会把项目放桌面。
        XCTAssertTrue(ProjectArtifactScanner.isDiscoverableContainer(name: "Desktop", artifactNames: artifacts))
        XCTAssertTrue(ProjectArtifactScanner.isDiscoverableContainer(name: "Code", artifactNames: artifacts))
    }

    // MARK: - 深度 / 包含 / 去重 / 嵌套

    func testDepthZeroOnlyAllowedWhenRootIsProjectRoot() {
        XCTAssertTrue(ProjectArtifactScanner.isDepthAllowed(
            candidate: "/root/proj/node_modules", searchRoot: "/root", minDepth: 1, rootIsProject: false))
        XCTAssertFalse(ProjectArtifactScanner.isDepthAllowed(
            candidate: "/root/node_modules", searchRoot: "/root", minDepth: 1, rootIsProject: false))
        XCTAssertTrue(ProjectArtifactScanner.isDepthAllowed(
            candidate: "/root/node_modules", searchRoot: "/root", minDepth: 1, rootIsProject: true))
        XCTAssertTrue(ProjectArtifactScanner.isDepthAllowed(
            candidate: "/root/a/b/c/d/e/f/node_modules", searchRoot: "/root", minDepth: 1, rootIsProject: false))
    }

    func testContainmentRejectsSymlinkEscape() {
        let identity: (String) -> String = { $0 }
        XCTAssertTrue(ProjectArtifactScanner.validateContainment(
            candidate: "/root/proj/node_modules", searchRoot: "/root", resolving: identity))
        // 词面在根内、物理在 /etc：GOMODCACHE=../../etc 式越界，必须拒。
        XCTAssertFalse(ProjectArtifactScanner.validateContainment(
            candidate: "/root/link", searchRoot: "/root",
            resolving: { $0.hasPrefix("/root/link") ? "/etc/secret" : $0 }))
        // /var → /private/var 这类别名两侧同规则，不算越界。
        XCTAssertTrue(ProjectArtifactScanner.validateContainment(
            candidate: "/var/www/proj/node_modules", searchRoot: "/var/www",
            resolving: { "/private" + $0 }))
        // 根是 / 时任何前缀校验形同虚设，直接拒。
        XCTAssertFalse(ProjectArtifactScanner.validateContainment(
            candidate: "/etc/x", searchRoot: "/",
            resolving: identity))
        // 词面就不在根内。
        XCTAssertFalse(ProjectArtifactScanner.validateContainment(
            candidate: "/other/proj/node_modules", searchRoot: "/root", resolving: identity))
    }

    func testCaseInsensitiveRootDedupe() {
        // APFS 大小写不敏感：~/Code 与 ~/code 是同一个目录（Mole #1416 的坑）。
        // 去重键必须来自文件系统真实拼写，这里用注入的解析器模拟。
        let resolved: (String) -> String = { path in
            switch path {
            case "/h/Code", "/h/code", "/h/CODE": return "/h/Code"
            default: return path
            }
        }
        let unique = ProjectArtifactScanner.dedupeRoots(["/h/Code", "/h/code", "/h/Repos", "/h/CODE"],
                                                        resolving: resolved)
        XCTAssertEqual(unique, ["/h/Code", "/h/Repos"])
    }

    func testNestedArtifactFlag() {
        let nested = ProjectArtifactScanner.nestedFlags(paths: [
            "/p/node_modules",
            "/p/node_modules/dep/node_modules",   // 祖先本身是候选 → 标 nested
            "/p/pkg/node_modules",                // 不是 /p/node_modules 的后代
            "/a/bin",
            "/a/bin2",                            // 只是词面前缀，不是目录包含
        ])
        XCTAssertEqual(nested, ["/p/node_modules/dep/node_modules"])
    }

    // MARK: - group

    func testGroupAggregationKeepsNilSizeWhenAnyReclaimableUnmeasured() {
        let measured = artifact(path: "/home/p1/node_modules", root: "/home/p1", size: 2048)
        let unknown = artifact(path: "/home/p1/.build", root: "/home/p1", size: nil)
        let groups = ProjectArtifactScanner.group(artifacts: [measured, unknown], home: "/home")
        XCTAssertEqual(groups.count, 1)
        let group = try! XCTUnwrap(groups.first)
        // 有一个没测到 → 整组 nil，绝不把 2048 说成组的全部可释放量。
        XCTAssertNil(group.reclaimableSize)
        XCTAssertEqual(group.relativeToHome, "~/p1")
        XCTAssertEqual(group.displayName, "p1")
    }

    func testGroupExcludesProtectedAndNestedFromSize() {
        let plain = artifact(path: "/home/p2/node_modules", root: "/home/p2", size: 1000)
        let protected = artifact(path: "/home/p2/vendor", root: "/home/p2",
                                 verdict: .protected(reason: "来历不明"), size: 9_999)
        let nested = artifact(path: "/home/p2/node_modules/x/node_modules", root: "/home/p2",
                              size: nil, nested: true)
        let group = ProjectArtifactScanner.group(artifacts: [plain, protected, nested],
                                                 home: "/home")[0]
        XCTAssertEqual(group.reclaimableSize, 1000)
        XCTAssertEqual(group.artifacts.count, 3)
    }

    func testGroupKeepsSortedOrderAcrossRoots() {
        let b = artifact(path: "/home/beta/node_modules", root: "/home/beta")
        let a = artifact(path: "/home/alpha/node_modules", root: "/home/alpha")
        let groups = ProjectArtifactScanner.group(artifacts: [b, a], home: "/home")
        XCTAssertEqual(groups.map(\.projectRoot), ["/home/alpha", "/home/beta"])
    }

    func testGroupMonorepoFlagPropagatesFromArtifacts() {
        let first = artifact(path: "/repo/pkg/a/node_modules", root: "/repo",
                             monorepo: "pnpm-workspace.yaml")
        let second = artifact(path: "/repo/pkg/b/node_modules", root: "/repo",
                              monorepo: "pnpm-workspace.yaml")
        let group = ProjectArtifactScanner.group(artifacts: [first, second], home: "/repo")[0]
        XCTAssertTrue(group.isMonorepo)
        XCTAssertEqual(group.monorepoIndicator, "pnpm-workspace.yaml")
    }

    func testGroupCloudSyncedFlag() {
        let a = artifact(path: "/u/Library/CloudStorage/Dropbox/proj/node_modules",
                         root: "/u/Library/CloudStorage/Dropbox/proj")
        let group = ProjectArtifactScanner.group(artifacts: [a], home: "/u")[0]
        XCTAssertTrue(group.isCloudSynced)
    }

    // MARK: - 默认规则

    func testDefaultRulesShape() {
        let rules = ProjectArtifactRules.default(home: "/u")
        XCTAssertEqual(rules.minDepth, 1)
        XCTAssertEqual(rules.maxDepth, 6)
        XCTAssertEqual(rules.minAgeDays, 7)
        XCTAssertGreaterThan(rules.rootBudgetSeconds, 0)
        XCTAssertGreaterThan(rules.totalBudgetSeconds, rules.rootBudgetSeconds)
        XCTAssertTrue(rules.artifactNames.contains("node_modules"))
        XCTAssertTrue(rules.projectIndicators.contains("Package.swift"))
        XCTAssertTrue(rules.monorepoIndicators.contains("nx.json"))
        // AI agent worktree 容器在点目录下，常规发现进不去，必须显式列。
        XCTAssertTrue(rules.searchRoots.contains("/u/.codex/worktrees"))
        XCTAssertTrue(rules.searchRoots.contains("/u/.claude/worktrees"))
        XCTAssertTrue(rules.searchRoots.contains("/u/Library/CloudStorage"))
        // 本机实测：Mole 那八个默认根一个都不存在，真项目全在 ~/Desktop 与
        // ~/Documents 下面。它们也会被 home 深度 1 的容器探测捞到，但根的**顺序**
        // 就是预算的分配顺序——排后面就等于把时限让给 ~/Downloads。
        XCTAssertTrue(rules.searchRoots.contains("/u/Desktop"))
        XCTAssertTrue(rules.searchRoots.contains("/u/Documents"))
    }

    func testRootDeadlineTakesTheEarlierOfTwoBudgets() {
        let started = Date(timeIntervalSince1970: 1_000)
        var rules = ProjectArtifactRules.default(home: "/u")
        rules.rootBudgetSeconds = 10
        rules.totalBudgetSeconds = 100
        // 刚开工：这一根该拿满自己那份 per-root 预算。
        let early = ProjectArtifactScanner.rootDeadline(now: started, started: started, rules: rules)
        XCTAssertEqual(early.timeIntervalSince(started), 10, accuracy: 0.001)
        // 整轮只剩 3 秒：这一根只能拿 3 秒，不能把后面的根全饿死。
        let late = ProjectArtifactScanner.rootDeadline(now: started.addingTimeInterval(97),
                                                       started: started, rules: rules)
        XCTAssertEqual(late.timeIntervalSince(started), 100, accuracy: 0.001)
    }

    // MARK: - 真机临时目录集成测试
    //
    // 上面的纯函数用例证明"规则本身对"；这一条证明**扫描器真的能产出
    // 让这些规则吃进去的形状**（发现、深度、符号链接、mtime、分组、预算）。
    // 本仓库刚被"夹具全对、真机全废"烧过一次，这条不许删。

    private func makeDir(_ parent: URL, _ name: String) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeFile(_ parent: URL, _ name: String, size: Int,
                           daysAgo: Int? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let url = parent.appendingPathComponent(name)
        try Data(count: size).write(to: url)
        if let daysAgo {
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-Double(daysAgo) * 86_400)],
                ofItemAtPath: url.path)
        }
        return url
    }

    private func setOld(_ url: URL, days daysAgo: Int) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-Double(daysAgo) * 86_400)],
            ofItemAtPath: url.path)
    }

    func testIntegrationScanOverRealTempTree() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-scan-\(UUID().uuidString)", isDirectory: true)
        defer {
            // 造龄用 mtime，不涉及权限；整棵删掉即可。
            try? FileManager.default.removeItem(at: sandbox)
        }
        // 先真的建出来再取物理拼写：realpath 对不存在的路径会失败，
        // /var → /private/var 这层别名就解析不出来了。
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        // realpath 口径注入：扫描器内部的搜索根会被解析成物理拼写，
        // home 也统一用它，断言才对得上（/var → /private/var）。
        let home = ProjectArtifactScanner.physicalPath(of: sandbox.path)
        let code = home + "/Code"
        let fm = FileManager.default

        // 1) 老产物：目录和内部文件都 40 天前 → untouchedForDays + nameIsEnough。
        let oldNM = URL(fileURLWithPath: code + "/oldproj/node_modules")
        try writeFile(oldNM, "left-pad.js", size: 2048, daysAgo: 40)
        try writeFile(oldNM, "right-pad.js", size: 2048, daysAgo: 40)
        try writeFile(oldNM.deletingLastPathComponent(), "package.json", size: 10, daysAgo: 40)
        try setOld(oldNM, days: 40)

        // 2) 近期产物：目录 1 天前动过 → touchedDaysAgo。
        let freshNM = URL(fileURLWithPath: code + "/freshproj/node_modules")
        try writeFile(freshNM, "dep.js", size: 512)
        try writeFile(freshNM.deletingLastPathComponent(), "package.json", size: 10)
        try setOld(freshNM, days: 1)

        // 3) Go 的 vendor：受保护，不给勾选框。
        let vendor = URL(fileURLWithPath: code + "/goprog/vendor")
        try fm.createDirectory(at: vendor, withIntermediateDirectories: true)
        try writeFile(vendor.deletingLastPathComponent(), "go.mod", size: 10)

        // 4) 符号链接的 node_modules：发现遍历不跟随，候选里不许出现。
        let weird = try makeDir(URL(fileURLWithPath: code), "weird")
        try setOld(weird, days: 40)
        let link = weird.appendingPathComponent("node_modules")
        try fm.createSymbolicLink(at: link, withDestinationURL: oldNM)

        var rules = ProjectArtifactRules.default(home: home)
        rules.rootBudgetSeconds = 30

        final class ProgressBox: @unchecked Sendable {
            let lock = NSLock()
            var paths: [String] = []
            func report(_ path: String) { lock.withLock { paths.append(path) } }
            var count: Int { lock.withLock { paths.count } }
        }
        let progress = ProgressBox()
        let scanner = ProjectArtifactScanner(home: home, rules: rules, now: now)
        let report = await scanner.scan { progress.report($0) }

        // 不存在 ≠ 读不动 ≠ 截断：~/www 这类缺根如实进 missingRoots。
        XCTAssertTrue(report.missingRoots.contains(home + "/www"))
        XCTAssertTrue(report.truncatedRoots.isEmpty)
        XCTAssertTrue(report.inaccessibleRoots.isEmpty)
        XCTAssertTrue(report.isComplete)
        XCTAssertTrue(report.scannedRoots.contains(code))
        XCTAssertGreaterThan(progress.count, 0, "进度必须真的被上报过")

        // Code 由 home 深度 1 的容器发现带进来（不在显式根名单里也会出现在
        // 显式根 ~/Code 上，去重后只有一份）。
        let allArtifacts = report.groups.flatMap(\.artifacts)
        XCTAssertEqual(allArtifacts.count, 3, "实际条目：\(allArtifacts.map(\.path))")
        XCTAssertFalse(allArtifacts.contains { $0.path.contains("/weird/") },
                       "符号链接的 node_modules 被跟随了")

        // 分组：三个项目根各一组。
        XCTAssertEqual(Set(report.groups.map(\.projectRoot)),
                       [code + "/oldproj", code + "/freshproj", code + "/goprog"])

        let old = try XCTUnwrap(allArtifacts.first { $0.path == oldNM.path })
        XCTAssertEqual(old.verdict, .reclaimable(.nameIsEnough))
        XCTAssertEqual(old.size, 4096, "体积必须由 FileTreeWalker 求和实测")
        XCTAssertEqual(old.fileCount, 2)
        XCTAssertEqual(old.relativeToProject, "node_modules")
        if case .untouchedForDays(let days) = old.activity {
            XCTAssertGreaterThanOrEqual(days, 39)
            XCTAssertLessThanOrEqual(days, 41)
        } else {
            XCTFail("40 天未动的产物应判 untouchedForDays，实际 \(old.activity)")
        }

        let fresh = try XCTUnwrap(allArtifacts.first { $0.path == freshNM.path })
        XCTAssertEqual(fresh.verdict, .reclaimable(.nameIsEnough))
        if case .touchedDaysAgo = fresh.activity {
            // 近期用过，UI 不该给默认勾选。
        } else {
            XCTFail("刚动过的产物应判 touchedDaysAgo，实际 \(fresh.activity)")
        }

        let vendorItem = try XCTUnwrap(allArtifacts.first { $0.path == vendor.path })
        guard case .protected(let reason) = vendorItem.verdict else {
            return XCTFail("Go 的 vendor 必须 protected，实际 \(vendorItem.verdict)")
        }
        XCTAssertTrue(reason.contains("Go/Rails"))
        // 受保护条目不进可释放量：goprog 组 reclaimableSize 为 0（没有漏测的可回收项）。
        let goprog = try XCTUnwrap(report.groups.first { $0.projectRoot == code + "/goprog" })
        XCTAssertEqual(goprog.reclaimableSize, 0)
        let oldGroup = try XCTUnwrap(report.groups.first { $0.projectRoot == code + "/oldproj" })
        XCTAssertEqual(oldGroup.reclaimableSize, 4096)
    }

    func testIntegrationUnreadableRootIsNotSilentlyClean() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let locked = sandbox.appendingPathComponent("Locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: sandbox)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let home = ProjectArtifactScanner.physicalPath(of: sandbox.path)
        let rules = ProjectArtifactRules(
            artifactNames: ["node_modules"],
            projectIndicators: ["package.json"],
            monorepoIndicators: [],
            searchRoots: [ProjectArtifactScanner.physicalPath(of: locked.path)],
            rootBudgetSeconds: 10
        )
        let report = await ProjectArtifactScanner(home: home, rules: rules, now: now).scan()

        // 读不进去的根单独列出来、整轮承认不完整——绝不折成"0 字节、很干净"。
        XCTAssertEqual(report.inaccessibleRoots, [ProjectArtifactScanner.physicalPath(of: locked.path)])
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.groups.isEmpty)
    }

    // MARK: - 分批续扫：复用与合并（P6.1）
    //
    // 合并这一步是续扫唯一"能说谎"的地方：分区没替干净、嵌套没重算、根同时占两个
    // 账本，报表看着都对但数字是假的。所以下面每条断言都在核对数字，而不是"有没有报错"。

    func testMergedReportReplacesTheContinuedRootWholesale() {
        let kept = artifact(path: "/u/dev/a/node_modules", root: "/u/dev/a", searchRoot: "/u/dev", size: 30)
        let stale = artifact(path: "/u/dev/b/node_modules", root: "/u/dev/b", searchRoot: "/u/dev/b", size: 50)
        let fresh = artifact(path: "/u/dev/b/app2/node_modules", root: "/u/dev/b/app2",
                             searchRoot: "/u/dev/b", size: 80)
        let merged = ProjectArtifactScanner.mergedReport(
            base: reportOf([kept, stale], truncated: ["/u/dev/b"]),
            continuation: reportOf([fresh], scanned: ["/u/dev/b"], duration: 2),
            home: "/u")

        XCTAssertEqual(Set(merged.groups.flatMap(\.artifacts).map(\.path)),
                       ["/u/dev/a/node_modules", "/u/dev/b/app2/node_modules"],
                       "被续扫的根整区替换：旧行留着就是拿上一批的观测冒充这一批")
        // 耗时是两批之和，不是"最近一批"——副标题写的必须是总共等了多久。
        XCTAssertEqual(merged.duration, 3)
    }

    func testMergedReportRecomputesNestedFlagsOverTheUnion() throws {
        // 第一批从 /u/x 扫到父产物，第二批从单独配成根的 /u/x/proj 扫到子产物。
        // 不在候选全集上重算嵌套，同一坨体积就计两遍。
        let parent = artifact(path: "/u/x/proj/build", root: "/u/x/proj", searchRoot: "/u/x", size: 4000)
        let child = artifact(path: "/u/x/proj/build/node_modules", root: "/u/x/proj",
                             searchRoot: "/u/x/proj", size: 900)
        let merged = ProjectArtifactScanner.mergedReport(
            base: reportOf([parent], scanned: ["/u/x"]),
            continuation: reportOf([child], scanned: ["/u/x/proj"]),
            home: "/u")

        let group = try XCTUnwrap(merged.groups.first { $0.projectRoot == "/u/x/proj" })
        let childRow = try XCTUnwrap(group.artifacts.first { $0.path == child.path })
        XCTAssertTrue(childRow.isNestedInAnotherArtifact, "跨批的父子关系没人补标，体积就会重复计")
        XCTAssertNil(childRow.size, "嵌套行只标不量")
        XCTAssertEqual(group.reclaimableSize, 4000, "合计里只能有父那一行")
    }

    func testMergedReportRerunsGroupingInsteadOfConcatenatingGroups() {
        // 同一个项目根的行分散在两批里：直接拼 groups 会出两张卡片、
        // monorepo 标志只在其中一张上，workspace 在清单里裂成两个项目。
        let first = artifact(path: "/u/r/ws/a/node_modules", root: "/u/r/ws", searchRoot: "/u/r", size: 100)
        let second = artifact(path: "/u/r/ws/b/node_modules", root: "/u/r/ws",
                              searchRoot: "/u/r/ws", size: 200, monorepo: "nx.json")
        let merged = ProjectArtifactScanner.mergedReport(
            base: reportOf([first], scanned: ["/u/r"]),
            continuation: reportOf([second], scanned: ["/u/r/ws"]),
            home: "/u")

        let wsGroups = merged.groups.filter { $0.projectRoot == "/u/r/ws" }
        XCTAssertEqual(wsGroups.count, 1)
        XCTAssertEqual(wsGroups[0].artifacts.count, 2)
        XCTAssertEqual(wsGroups[0].monorepoIndicator, "nx.json")
        XCTAssertEqual(wsGroups[0].reclaimableSize, 300)
    }

    func testMergedReportKeepsOneRootInExactlyOneLedger() {
        // base：a 扫完、b/e 截断、c 读不动、d 不存在。第二批跑 b 和 e：b 扫完、e 又截断。
        let base = reportOf([], scanned: ["/u/a"], truncated: ["/u/b", "/u/e"],
                            inaccessible: ["/u/c"], missing: ["/u/d"])
        let continuation = reportOf([], scanned: ["/u/b"], truncated: ["/u/e"])
        let merged = ProjectArtifactScanner.mergedReport(base: base, continuation: continuation, home: "/u")

        XCTAssertEqual(merged.scannedRoots, ["/u/a", "/u/b"])
        XCTAssertEqual(merged.truncatedRoots, ["/u/e"], "b 扫完之后不能再挂在截断账上，否则点名条永远少不了")
        XCTAssertEqual(merged.inaccessibleRoots, ["/u/c"], "读不动不是超时，续扫不该替它重试")
        XCTAssertEqual(merged.missingRoots, ["/u/d"])
        XCTAssertFalse(merged.isComplete)

        let ledgers: [[String]] = [merged.scannedRoots, merged.truncatedRoots,
                                   merged.inaccessibleRoots, merged.missingRoots]
        var seen = Set<String>()
        for ledger in ledgers {
            for root in ledger where seen.contains(root) {
                XCTFail("\(root) 同时占了两个账本，UI 就无从判断该不该说「完整」")
            }
            seen.formUnion(ledger)
        }
    }

    func testMergedReportCountsOutOfRootCandidatesFromBothBatches() {
        let merged = ProjectArtifactScanner.mergedReport(
            base: reportOf([], scanned: ["/u/a"], outOfRoot: 2),
            continuation: reportOf([], scanned: ["/u/b"], outOfRoot: 5),
            home: "/u")
        XCTAssertEqual(merged.outOfSearchRootCandidateCount, 7,
                       "越界候选是证据丢失量，两批都得报，取最大值就是把第一批丢掉的说成没发生")
    }

    func testIsCompleteObservationIsTheReuseGate() {
        XCTAssertTrue(ProjectArtifactScanner.isCompleteObservation(
            artifact(path: "/u/dev/a/node_modules", root: "/u/dev/a")))
        XCTAssertFalse(ProjectArtifactScanner.isCompleteObservation(
            artifact(path: "/u/dev/a/node_modules", root: "/u/dev/a", size: nil)),
            "体积没量到的行不叫看完证据，复用它就是让「读不到」永远留在清单上")
        XCTAssertFalse(ProjectArtifactScanner.isCompleteObservation(
            artifact(path: "/u/dev/a/node_modules", root: "/u/dev/a", activity: .unknown("探测超时"))))
        // 受保护但证据看完的行照样可复用：结论已经成立，重测只烧预算。
        XCTAssertTrue(ProjectArtifactScanner.isCompleteObservation(
            artifact(path: "/u/dev/a/vendor", root: "/u/dev/a", verdict: .protected(reason: "Go 的 vendor 是源码"))))
    }

    func testRowsCompletedByBatchMarksTheBadgeInsteadOfTheRootRerun() {
        // 首批：a 组两行都看完了证据，b 组那行体积没量到。
        let base = reportOf([
            artifact(path: "/u/dev/a/node_modules", root: "/u/dev/a"),
            artifact(path: "/u/dev/a/dist", root: "/u/dev/a"),
            artifact(path: "/u/dev/b/target", root: "/u/dev/b", size: nil),
        ], scanned: ["/u/dev/a"], truncated: ["/u/dev/b"])
        // 续扫：a 组整行复用（一行都没多出来），b 组那行补上了体积，c 组是新报的，
        // d 组那行是新报的但**还是**没量到体积。
        let merged = reportOf([
            artifact(path: "/u/dev/a/node_modules", root: "/u/dev/a"),
            artifact(path: "/u/dev/a/dist", root: "/u/dev/a"),
            artifact(path: "/u/dev/b/target", root: "/u/dev/b"),
            artifact(path: "/u/dev/c/.next", root: "/u/dev/c"),
            artifact(path: "/u/dev/d/build", root: "/u/dev/d", size: nil),
        ], scanned: ["/u/dev/a", "/u/dev/b", "/u/dev/c"], truncated: ["/u/dev/d"])
        let completed = ProjectArtifactScanner.rowsCompletedByBatch(base: base, merged: merged)
        XCTAssertEqual(completed, ["/u/dev/b/target", "/u/dev/c/.next"],
            "「第 N 批补全」只能点在真的补上了证据的组上：a 组的根被重跑过，可它每一行都是复用的")
    }

    func testRootsToContinuePicksOnlyTruncatedRoots() {
        let report = reportOf([], scanned: ["/u/a"], truncated: ["/u/b"],
                              inaccessible: ["/u/c"], missing: ["/u/d"])
        XCTAssertEqual(ProjectArtifactScanner.rootsToContinue(report: report), ["/u/b"],
                       "读不动是权限事实、不存在是没这个东西，重试两者都只烧预算")
    }

    func testAttemptCountsOnlyMoveForRootsActuallyRerun() {
        let once = ProjectArtifactScanner.attemptCounts(rootsRun: ["/u/b"], stillTruncated: ["/u/b"],
                                                        previous: [:])
        XCTAssertEqual(once, ["/u/b": 1])
        let twice = ProjectArtifactScanner.attemptCounts(rootsRun: ["/u/b"], stillTruncated: ["/u/b"],
                                                         previous: once)
        XCTAssertEqual(twice, ["/u/b": 2])
        // 没跑过的根计数必须原样留着：否则每续扫一次别的根，它就白捡一次重试机会。
        let mixed = ProjectArtifactScanner.attemptCounts(rootsRun: ["/u/b"], stillTruncated: [],
                                                         previous: ["/u/a": 1, "/u/b": 2])
        XCTAssertEqual(mixed, ["/u/a": 1], "扫完了的根退出计数，没跑过的不许被顺手清零")
    }

    func testSurvivingSelectionDropsRowsThatLostTheirCheckbox() {
        let stillGood = artifact(path: "/u/dev/a/node_modules", root: "/u/dev/a")
        let becameNested = artifact(path: "/u/dev/b/node_modules", root: "/u/dev/b", nested: true)
        let becameProtected = artifact(path: "/u/dev/c/vendor", root: "/u/dev/c",
                                       verdict: .protected(reason: "Go 的 vendor 是源码"))
        let merged = reportOf([stillGood, becameNested, becameProtected])
        let trimmed = ProjectArtifactScanner.survivingSelection(
            Set([stillGood.path, becameNested.path, becameProtected.path]), report: merged) { $0.isSelectableStub }
        XCTAssertEqual(trimmed, [stillGood.path],
                       "续扫只修剪不清空：勾着一个已经没有勾选框的行报「已选 X GB」就是虚高")
    }

    func testSurvivingSelectionDropsRowsThatLeftTheReport() {
        let merged = reportOf([artifact(path: "/u/dev/a/node_modules", root: "/u/dev/a")])
        let trimmed = ProjectArtifactScanner.survivingSelection(["/u/dev/gone/node_modules"], report: merged) { _ in true }
        XCTAssertTrue(trimmed.isEmpty, "清单里已经没有这一行了，勾选不能凭空留着")
    }

    // MARK: - 续扫的扫描器入口（真机临时目录）

    /// 复用行必须**真的不重测**：夹具里的文件写成今天动过、体积 2 KB，
    /// 上一批的观测写 30 天没碰、999 KB。两批数字对不上的那一侧才是被复用的。
    func testReuseCarriesThePriorObservationInsteadOfReMeasuring() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-reuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let home = ProjectArtifactScanner.physicalPath(of: sandbox.path)
        let proj = home + "/Other/proj"
        let artifactPath = proj + "/node_modules"
        try writeFile(URL(fileURLWithPath: artifactPath), "a.js", size: 2048)
        try writeFile(URL(fileURLWithPath: proj), "package.json", size: 10)

        var rules = ProjectArtifactRules.default(home: home)
        rules.searchRoots = [home + "/Other"]
        let scanner = ProjectArtifactScanner(home: home, rules: rules, now: now)

        let prior = artifact(path: artifactPath, root: proj, searchRoot: home + "/Other", size: 999_999)
        let reused = await scanner.scan(roots: [home + "/Other"], reuse: [artifactPath: prior])
        let reusedRow = try XCTUnwrap(reused.groups.flatMap(\.artifacts).first { $0.path == artifactPath })
        XCTAssertEqual(reusedRow.size, 999_999, "复用了却还在重测，等于续扫一行都没省下")
        XCTAssertEqual(reusedRow.activity, .untouchedForDays(30))

        // 同一份 reuse 里塞一行"读不到"的旧观测：扫描器自己筛掉它，不靠调用方守规矩。
        let incomplete = artifact(path: artifactPath, root: proj, searchRoot: home + "/Other", size: nil)
        let remeasured = await scanner.scan(roots: [home + "/Other"], reuse: [artifactPath: incomplete])
        let freshRow = try XCTUnwrap(remeasured.groups.flatMap(\.artifacts).first { $0.path == artifactPath })
        XCTAssertEqual(freshRow.size, 2048, "体积没量到的旧行不许占着位置不回磁盘重测")
    }

    /// 续扫**不重新发现顶层容器**（§3.4）：显式传根时，home 一级目录不再被捞进清单，
    /// 否则"哪些根要重试"会有两个答案，点名条上的数字就跟着漂。
    func testExplicitRootsSkipHomeContainerDiscovery() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-explicit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let home = ProjectArtifactScanner.physicalPath(of: sandbox.path)
        let code = home + "/Code"
        let other = home + "/Other"
        for container in [code, other] {
            let proj = container + "/proj"
            try writeFile(URL(fileURLWithPath: proj + "/node_modules"), "a.js", size: 1024, daysAgo: 30)
            try writeFile(URL(fileURLWithPath: proj), "package.json", size: 10, daysAgo: 30)
            try setOld(URL(fileURLWithPath: proj + "/node_modules"), days: 30)
        }

        var rules = ProjectArtifactRules.default(home: home)
        rules.searchRoots = [other]
        let scanner = ProjectArtifactScanner(home: home, rules: rules, now: now)

        let continued = await scanner.scan(roots: [other])
        XCTAssertEqual(continued.scannedRoots, [other], "显式根模式下不许再把 home 一级容器捞进来")
        XCTAssertFalse(continued.groups.contains { $0.projectRoot == code + "/proj" })

        // 对照：不给显式根（= 重新扫描）时容器探测照旧，Code 那组仍在。
        let full = await scanner.scan()
        XCTAssertTrue(full.groups.contains { $0.projectRoot == code + "/proj" },
                      "「重新扫描」才是发现新顶层项目的入口")
    }

    // MARK: - P6.3b 合并遍历：纯派生表（调研 §4.3，六行映射逐行钉死；无 IO）

    private func walkDone(size: UInt64 = 0, count: Int = 0, recent: Bool = false,
                          unreadable: [String] = [],
                          stop: FileTreeWalker.SubtreeWalk.Stop? = nil,
                          depthTruncated: Bool = false) -> FileTreeWalker.SubtreeWalk {
        var w = FileTreeWalker.SubtreeWalk()
        w.size = size
        w.fileCount = count
        w.sawRecentFile = recent
        w.unreadableDirectories = unreadable
        w.stopReason = stop
        w.sizeDepthTruncated = depthTruncated
        return w
    }

    /// 行 1：候选完整跑完、无近期文件 → noRecentFile + 体积有值 + 根不截断。
    func testWalkDerivationCompletedWalkWithoutRecent() throws {
        let w = walkDone(size: 123, count: 5)
        XCTAssertEqual(ProjectArtifactScanner.activityProbeResult(from: w, path: "/p"), .noRecentFile)
        let measured = try XCTUnwrap(ProjectArtifactScanner.measuredSize(from: w, isNested: false))
        XCTAssertEqual(measured.size, 123)
        XCTAssertEqual(measured.fileCount, 5)
        XCTAssertFalse(ProjectArtifactScanner.budgetIncomplete(from: w))
    }

    /// 行 2/3：中途超时（活动侧与体积侧从此是**同一个字段**，不再有两套竞速）
    /// → incomplete（文案与旧 activityProbe 逐字相同）+ 体积 nil + 根进 truncated。
    func testWalkDerivationDeadlineAndCancellationShareOneConclusion() {
        for stop in [FileTreeWalker.SubtreeWalk.Stop.deadline, .cancelled] {
            let w = walkDone(size: 999, count: 3, recent: true, stop: stop)
            XCTAssertEqual(ProjectArtifactScanner.activityProbeResult(from: w, path: "/p"),
                           .incomplete("活动探测超时/被取消：/p"), "stop=\(stop)")
            XCTAssertNil(ProjectArtifactScanner.measuredSize(from: w, isNested: false),
                         "预算内没量完的部分和不许冒充完整数字（纪律 3），stop=\(stop)")
            XCTAssertTrue(ProjectArtifactScanner.budgetIncomplete(from: w), "根必须进 truncated：\(stop)")
        }
    }

    /// 行 4：目录读不进（TCC/权限）→ incomplete("读不动…")，但**不是**预算问题：
    /// 体积按现口径照给（§4.2(b) 的收紧待拍板，本轮不并），根不进 truncated。
    func testWalkDerivationUnreadableIsAConclusionNotATruncation() throws {
        let w = walkDone(size: 4096, count: 2, unreadable: ["/p/locked", "/p/x"])
        XCTAssertEqual(ProjectArtifactScanner.activityProbeResult(from: w, path: "/p"),
                       .incomplete("读不动：/p/locked"))
        let measured = try XCTUnwrap(ProjectArtifactScanner.measuredSize(from: w, isNested: false))
        XCTAssertEqual(measured.size, 4096)
        XCTAssertFalse(ProjectArtifactScanner.budgetIncomplete(from: w),
                       "权限性读不进是已出的 fail-closed 结论，不许把根拖进截断账（§8.6 对齐）")
    }

    /// 行 5：深于 23 层 → 数值与今天的 stats 逐位一致，只是截断从静默变显式。
    func testWalkDerivationDepthTruncationKeepsNumbers() throws {
        let w = walkDone(size: 7, count: 1, depthTruncated: true)
        XCTAssertEqual(ProjectArtifactScanner.activityProbeResult(from: w, path: "/p"), .noRecentFile)
        let measured = try XCTUnwrap(ProjectArtifactScanner.measuredSize(from: w, isNested: false))
        XCTAssertEqual(measured.size, 7)
        XCTAssertTrue(w.sizeDepthTruncated)
    }

    /// 行 6：嵌套候选（needSize=false，带早退）→ 活动结论照常出，体积恒 nil；
    /// 若早退前就撞线，与行 2 同——进截断。
    func testWalkDerivationNestedRowNeverReportsSize() {
        let early = walkDone(recent: true)
        XCTAssertEqual(ProjectArtifactScanner.activityProbeResult(from: early, path: "/p"),
                       .recentFileFound)
        XCTAssertNil(ProjectArtifactScanner.measuredSize(from: early, isNested: true))
        XCTAssertFalse(ProjectArtifactScanner.budgetIncomplete(from: early))

        let stopped = walkDone(recent: true, stop: .deadline)
        XCTAssertTrue(ProjectArtifactScanner.budgetIncomplete(from: stopped))
    }

    /// fail-closed 优先级：deadline > 读不进 > 近期文件。
    /// "没扫到"不许混成"没有"——三态里最保守的那个压过所有乐观结论。
    func testWalkDerivationFailClosedPrecedence() {
        let unreadableBeatsRecent = walkDone(size: 10, count: 1, recent: true, unreadable: ["/p/l"])
        XCTAssertEqual(ProjectArtifactScanner.activityProbeResult(from: unreadableBeatsRecent, path: "/p"),
                       .incomplete("读不动：/p/l"))
        let deadlineBeatsEverything = walkDone(size: 10, recent: true, unreadable: ["/p/l"], stop: .deadline)
        XCTAssertEqual(ProjectArtifactScanner.activityProbeResult(from: deadlineBeatsEverything, path: "/p"),
                       .incomplete("活动探测超时/被取消：/p"))
    }

    // MARK: - P6.3b 双跑对拍（调研 §7 第 2 步：合并结果与两趟旧遍历**逐字段相等**是硬闸）

    /// 在 /tmp 造一棵同时踩中四套集合规则差异源的子树（本仓约定：动文件的夹具只放 /tmp，
    /// 测试自清理）：①点目录/点条目 ②符号链接（文件链 + 指向候选外新鲜目录的目录链 + 点链）
    /// ③深于 23 层的链（第 23 层文件必须还计入、第 24/26 层必须静默不计——与 stats 同死线）
    /// ④chmod 000 子目录（读不进：stats 静默计 0、probe fail closed，两路来源必须合流）。
    ///
    /// `allRecent=false`：整棵 40 天前 → 活动侧结论是"读不动（挂在唯一读不进的目录上）"；
    /// `allRecent=true`：全部刚动过且锁目录恢复可读 → 活动侧结论是 recentFileFound。
    /// 两种都要：体积 == stats、活动派生 == 旧 activityProbe（连 reason 里的目录路径都相等）。
    private func runMergedWalkParity(allRecent: Bool) async throws {
        let sandbox = URL(fileURLWithPath: "/tmp/walk-parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let fm = FileManager.default
        let candidate = try makeDir(sandbox, "node_modules")
        let locked = candidate.appendingPathComponent("locked", isDirectory: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? fm.removeItem(at: sandbox)
        }
        let age = allRecent ? 0 : 40

        // ① 点条目与点目录：体积侧整条排除（含子树），活动侧照查照下潜。
        try writeFile(candidate, "a.txt", size: 2048, daysAgo: age)
        try writeFile(candidate, ".hidden.txt", size: 512, daysAgo: age)
        let sub = try makeDir(candidate, "sub")
        try writeFile(sub, "b.bin", size: 1024, daysAgo: age)
        let dotDir = try makeDir(candidate, ".dotdir")
        try writeFile(dotDir, "c.txt", size: 256, daysAgo: age)

        // ② 符号链接：体积侧按链接自身 st_size 计入（readEntries 的既成事实），
        //    活动侧完全不可见、更不下潜。link-dir 指向候选**外**一棵新鲜目录——
        //    任何一路要是跟了链接，本对拍立刻崩，所以它同时是"不跟随"的断言。
        let elsewhere = try makeDir(sandbox, "elsewhere")
        try writeFile(elsewhere, "fresh.txt", size: 4096, daysAgo: 0)
        try fm.createSymbolicLink(at: candidate.appendingPathComponent("link-file"),
                                  withDestinationURL: candidate.appendingPathComponent("a.txt"))
        try fm.createSymbolicLink(at: candidate.appendingPathComponent("link-dir"),
                                  withDestinationURL: elsewhere)
        try fm.createSymbolicLink(at: candidate.appendingPathComponent(".link-dot"),
                                  withDestinationURL: sub)

        // ③ 深度：候选直接子项为第 0 层；chain/dK 在第 K 层，stats 主遍历计到 20 层、
        //    fallbackStats 补到 23 层，24 层起静默 0——合并口必须在同一条线上少加同样的数。
        let chain = try makeDir(candidate, "chain")
        try writeFile(chain, "level1.txt", size: 16, daysAgo: age)
        var dirs: [URL] = []
        var cursor = chain
        for k in 1...25 {
            cursor = try makeDir(cursor, "d\(k)")
            dirs.append(cursor)
        }
        try writeFile(dirs[21], "level23.txt", size: 32, daysAgo: age)   // 第 23 层：计入
        try writeFile(dirs[22], "level24.txt", size: 64, daysAgo: age)   // 第 24 层：不计
        try writeFile(dirs[24], "level26.txt", size: 128, daysAgo: age)  // 第 26 层：不计
        // 链深处的点目录：stats 从不进去（无体积也无所谓截断），活动侧照走。
        let deepDot = try makeDir(dirs[5], ".deepdot")
        try writeFile(deepDot, "old.txt", size: 8, daysAgo: age)

        // ④ 宽扇出给耗时样本一点肉（3200 个条目），也让并行/串行合并路径都被压到。
        for f in 0..<50 {
            let fan = try makeDir(candidate, "fan\(f)")
            for i in 0..<20 {
                try writeFile(fan, "pkg-\(i).js", size: 32, daysAgo: age)
            }
        }

        // ⑤ chmod 000 子目录。以 root 跑测试时 000 拦不住读——那两路旧遍历同样看得见内容，
        //    对拍照跑，只是"读不进"分支自然退化为空集，不豁免断言。
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try writeFile(locked, "secret.txt", size: 8192, daysAgo: age)
        try fm.setAttributes([.posixPermissions: allRecent ? 0o755 : 0o000],
                             ofItemAtPath: locked.path)
        let lockedIsUnreadable = allRecent ? false : !FileTreeWalker.canEnumerate(path: locked.path)

        let rules = ProjectArtifactRules(
            artifactNames: ["node_modules"], projectIndicators: ["package.json"],
            monorepoIndicators: [], searchRoots: [], rootBudgetSeconds: 60)
        let scanner = ProjectArtifactScanner(home: sandbox.path, rules: rules, now: now)
        // 宽裕预算：对拍要证的是集合规则等价，不是预算行为（预算各有专职用例）。
        let deadline = Date().addingTimeInterval(600)
        let threshold = now.addingTimeInterval(-7 * 86_400)

        // —— 两趟旧参考实现的耗时（stats 全趟 + activityProbe 全趟）。
        let twoPassStart = Date()
        let stats = await FileTreeWalker.stats(path: candidate.path)
        let legacy = await scanner.activityProbe(in: candidate.path, deadline: deadline)
        let twoPassSeconds = Date().timeIntervalSince(twoPassStart)

        // —— 合并口一趟（非嵌套档：needSize=true，全程走完不早退）。
        let oneStart = Date()
        let walk = await FileTreeWalker.walkForArtifact(path: candidate.path, deadline: deadline,
                                                        recentThreshold: threshold, needSize: true)
        let onePassSeconds = Date().timeIntervalSince(oneStart)

        // 调研 §8 欠的应用内实测样本：打印，**不**断言阈值（换台机器就翻车的数不配当闸）。
        print(String(format: "[walk-merge 对拍 allRecent=%@] 两趟(stats+probe)=%.4fs 一趟(walk)=%.4fs "
                     + "size=%llu files=%d",
                     allRecent ? "true" : "false", twoPassSeconds, onePassSeconds,
                     stats.size, stats.fileCount))

        // 硬闸①：体积/文件数与 FileTreeWalker.stats 逐字段相等（差一个字节都算不等价）。
        XCTAssertEqual(walk.size, stats.size,
                       "合并口与 stats 体积不等价——同目录两页数字打架，纪律 2 事故口径")
        XCTAssertEqual(walk.fileCount, stats.fileCount,
                       "合并口与 stats 文件数不等价")
        XCTAssertGreaterThan(walk.size, 0)
        XCTAssertNil(walk.stopReason, "宽裕预算下合并口不许自己判超时")
        XCTAssertFalse(ProjectArtifactScanner.budgetIncomplete(from: walk))
        XCTAssertTrue(walk.sizeDepthTruncated, "夹具里有第 24 层起的文件，静默截断必须显式化")
        if lockedIsUnreadable {
            XCTAssertEqual(walk.unreadableDirectories, [locked.path], "读不进通道只认这一棵锁目录")
        } else {
            XCTAssertTrue(walk.unreadableDirectories.isEmpty)
        }

        // 硬闸②：活动侧派生结论与旧 activityProbe 相等（含 reason 里的目录路径）。
        let derived = ProjectArtifactScanner.activityProbeResult(from: walk, path: candidate.path)
        XCTAssertEqual(derived, legacy, "合并口的活动结论与旧 activityProbe 不等价")
        XCTAssertEqual(walk.sawRecentFile, allRecent,
                       "sawRecentFile 必须恰为『存在近期文件』——链诱饵/点条目都不能把它翻掉")

        // 嵌套档（needSize=false，早退保留）：同一棵树上结论仍与旧 probe 逐字相等。
        let nestedWalk = await FileTreeWalker.walkForArtifact(path: candidate.path, deadline: deadline,
                                                              recentThreshold: threshold, needSize: false)
        XCTAssertEqual(ProjectArtifactScanner.activityProbeResult(from: nestedWalk, path: candidate.path),
                       legacy, "needSize=false 必须复刻旧 activityProbe，含早退顺序")
        XCTAssertNil(ProjectArtifactScanner.measuredSize(from: nestedWalk, isNested: true),
                     "嵌套候选体积恒 nil（体积已在祖先处整体计入）")
    }

    func testMergedWalkParityOnAgedTree() async throws {
        try await runMergedWalkParity(allRecent: false)
    }

    func testMergedWalkParityOnRecentlyTouchedTree() async throws {
        try await runMergedWalkParity(allRecent: true)
    }

    // MARK: - P6.3b §8.6 不变式（接线后的根账本）

    /// 不变式：根进了 scannedRoots ⇒ 该根所有非嵌套行要么结论完整（isCompleteObservation），
    /// 要么结论是"读不到（非预算）"。超时落在最后一个候选**中间**也必须把根记进截断，
    /// 「已扫完的根 + 预算用尽的读不到行」这组矛盾不许再同屏。
    /// 截止线落在候选中间没法掐毫秒确定，所以这是性质断言：小预算 + 足量夹具，
    /// 无论预算咬在哪一步，违规组合出现即失败。
    func testScannedRootNeverCarriesBudgetUnfinishedRows() async throws {
        let sandbox = URL(fileURLWithPath: "/tmp/walk-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let home = ProjectArtifactScanner.physicalPath(of: sandbox.path)
        let proj = home + "/Code/proj"
        let nm = proj + "/node_modules"
        // 3200 条目 + 40 天龄：0.05 s 的根预算大概率咬在成案中途——正是旧的出事位置。
        for d in 0..<80 {
            for f in 0..<40 {
                try writeFile(URL(fileURLWithPath: "\(nm)/pkg\(d)"), "f\(f).js", size: 64, daysAgo: 40)
            }
        }
        try writeFile(URL(fileURLWithPath: nm), "index.js", size: 64, daysAgo: 40)
        try writeFile(URL(fileURLWithPath: proj), "package.json", size: 10, daysAgo: 40)
        try setOld(URL(fileURLWithPath: nm), days: 40)

        let rules = ProjectArtifactRules(
            artifactNames: ["node_modules"], projectIndicators: ["package.json"],
            monorepoIndicators: [], searchRoots: [home + "/Code"],
            rootBudgetSeconds: 0.05)
        let report = await ProjectArtifactScanner(home: home, rules: rules, now: now).scan()

        let scanned = Set(report.scannedRoots)
        for item in report.groups.flatMap(\.artifacts) where !item.isNestedInAnotherArtifact {
            guard scanned.contains(item.sourceRoot) else { continue }
            if ProjectArtifactScanner.isCompleteObservation(item) { continue }
            guard case .unknown(let reason) = item.activity else {
                XCTFail("根 \(item.sourceRoot) 已扫完，行 \(item.path) 却没出完整结论，"
                        + "活动度还不是 unknown（\(item.activity)）——预算性未完成必须进截断账")
                continue
            }
            XCTAssertFalse(reason.contains("超时") || reason.contains("取消"),
                           "§8.6 复现：根报「已扫完」，行挂着「读不到（预算用尽）」：\(reason)")
        }

        // 阳性对照（防上面那条性质断言空转）：同一夹具在宽裕预算下必须扫得完——
        // 根进 scannedRoots，且每一行都是完整结论。合并遍历要是把不该 fail-closed
        // 的场景折成了读不到，这里会先红。
        let generous = ProjectArtifactRules(
            artifactNames: ["node_modules"], projectIndicators: ["package.json"],
            monorepoIndicators: [], searchRoots: [home + "/Code"],
            rootBudgetSeconds: 120)
        let done = await ProjectArtifactScanner(home: home, rules: generous, now: now).scan()
        let root = home + "/Code"
        XCTAssertTrue(done.scannedRoots.contains(root),
                      "宽裕预算下 \(root) 应进 scannedRoots；truncated=\(done.truncatedRoots)")
        let rows = done.groups.flatMap(\.artifacts).filter {
            $0.sourceRoot == root && !$0.isNestedInAnotherArtifact
        }
        XCTAssertFalse(rows.isEmpty, "夹具必须真的产出候选行")
        for row in rows {
            XCTAssertTrue(ProjectArtifactScanner.isCompleteObservation(row),
                          "宽裕预算下每行都该看完证据：\(row.path) activity=\(row.activity) size=\(String(describing: row.size))")
        }
    }
}

private extension ProjectArtifact {
    /// `isSelectable` 住在 MMCleaner（只有 UI 知道"有勾选框"的口径），
    /// 这里放一个同规则的本地替身，避免扫描层为了测试反过来依赖 UI 包。
    var isSelectableStub: Bool {
        guard !isNestedInAnotherArtifact, size != nil else { return false }
        if case .reclaimable = verdict { return true }
        return false
    }
}
