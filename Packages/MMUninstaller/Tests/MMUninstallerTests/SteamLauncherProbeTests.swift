import XCTest
import Foundation
@testable import MMUninstaller

/// 启动器判定的测试分两层：**纯判定**在快照值上跑（不碰磁盘），**只读读取**在临时目录的
/// 假 bundle 上跑。判定层的每一条都是合同（`docs/analysis/uninstaller-steam-launcher.md` §5.1），
/// 少钉一条，下一轮就有人把它放宽成"看起来像就行"。
final class SteamLauncherProbeTests: XCTestCase {

    private func snapshot(name: String = "SteamGame",
                          source: LauncherScriptSnapshot.Source = .bundleExecutable,
                          size: Int = 120,
                          executable: Bool = true,
                          text: String?) -> LauncherScriptSnapshot {
        LauncherScriptSnapshot(name: name, source: source, size: size,
                               isExecutable: executable, text: text)
    }

    private func resolve(_ text: String?, size: Int = 120,
                         executable: Bool = true) -> SteamLauncherInfo? {
        SteamLauncherProbe.resolve(candidates: [snapshot(size: size, executable: executable, text: text)])
    }

    // MARK: 成立的那一档

    func testSingleOpenLineIsRecognised() throws {
        let info = try XCTUnwrap(resolve("#!/bin/sh\nopen steam://run/220\n"))
        XCTAssertEqual(info.appID, "220")
        XCTAssertEqual(info.verb, .run)
        XCTAssertEqual(info.scriptName, "SteamGame")
        XCTAssertEqual(info.scriptSource, .bundleExecutable)
    }

    func testAllThreeVerbsAreAccepted() {
        for verb in ["run", "rungameid", "launch"] {
            let info = resolve("#!/bin/bash\nopen steam://\(verb)/12345\n")
            XCTAssertEqual(info?.verb.rawValue, verb, "\(verb) 在合同里")
        }
    }

    /// shebang 只认解释器脚本：sh/bash/zsh，加 `env` 是为了 `#!/usr/bin/env bash` 这种写法。
    func testShebangMustBeKnownInterpreter() {
        for line in ["#!/bin/sh", "#!/bin/bash", "#!/bin/zsh", "#!/usr/bin/env bash"] {
            XCTAssertTrue(SteamLauncherProbe.isShebang(line), line)
        }
        for line in ["#!/usr/bin/python3", "#!/usr/bin/perl", "#!/bin/dash",
                     "# open steam://run/220", "open steam://run/220"] {
            XCTAssertFalse(SteamLauncherProbe.isShebang(line), "「\(line)」不是解释器 shebang")
        }
    }

    /// 注释行与空行不算有效行，所以"shebang + 一行 open + 注释"仍然成立。
    func testCommentsAndBlankLinesDoNotCount() {
        XCTAssertNotNil(resolve("#!/bin/sh\n\n# Steam 生成\nopen steam://rungameid/440   \n"))
    }

    // MARK: 一条就不成立的形状

    /// 有效行必须是**正好一行**：两行意味着这不是"只用来拉起游戏"的壳。
    func testMoreThanOneActiveLineIsRejected() {
        XCTAssertNil(resolve("#!/bin/sh\nopen steam://run/220\nopen steam://store/220\n"))
    }

    /// 只有 shebang 的脚本没有说任何事，不能算启动器。
    func testZeroActiveLinesIsRejected() {
        XCTAssertNil(resolve("#!/bin/sh\n# 什么都没干\n"))
    }

    /// 权限位是合同的一部分：真的启动器由 Steam 写成可执行，普通资源文件不是。
    func testNotExecutableIsRejected() {
        XCTAssertNil(resolve("#!/bin/sh\nopen steam://run/220\n", executable: false))
    }

    func testTooLargeIsRejected() {
        XCTAssertNil(resolve("#!/bin/sh\nopen steam://run/220\n",
                             size: SteamLauncherProbe.maxScriptBytes + 1))
    }

    /// 读不到正文（不是合法 UTF-8）就没有凭据可言。
    func testMissingTextIsRejected() {
        XCTAssertNil(SteamLauncherProbe.resolve(candidates: [snapshot(text: nil)]))
    }

    func testURLMustBeSteamSchemeWithNumericAppID() {
        for line in ["open steam://run/220a", "open steam://run/", "open steam://install/220",
                     "open http://store.steampowered.com/app/220", "open -a Steam steam://run/220",
                     "steamservice://run/220", "open steam://run"] {
            XCTAssertNil(SteamLauncherProbe.parse(line), "「\(line)」不在合同里")
        }
        // appid 只认 ASCII 数字：别的数字体系一律拒绝。
        XCTAssertNil(SteamLauncherProbe.parse("open steam://run/２２０"))
    }

    /// 尾部允许 `&` 与引号——把它判成"不是"才是假阴性。
    func testTrailingAmpersandAndQuotesAreTolerated() {
        XCTAssertEqual(SteamLauncherProbe.parse("open steam://run/220 &")?.appID, "220")
        XCTAssertEqual(SteamLauncherProbe.parse("open \"steam://launch/730\"")?.verb, .launch)
    }

    func testVerbAndSchemeAreCaseInsensitive() {
        XCTAssertEqual(SteamLauncherProbe.parse("open STEAM://RUN/220")?.verb, .run)
        XCTAssertEqual(SteamLauncherProbe.parse("Open steam://run/220")?.verb, .run)
    }

    // MARK: 两条入口

    /// 第一条不合格就试第二条：plist 指的文件与写死的 `run.sh` 是两个不同来源，
    /// 不是同一文件的两种读法。
    func testFallsThroughToSecondCandidate() throws {
        let bad = snapshot(name: "SteamGame", text: "#!/bin/sh\n./real-binary \"$@\"\n")
        let good = snapshot(name: SteamLauncherProbe.fixedScriptName, source: .fixedName,
                            text: "#!/bin/sh\nopen steam://run/220\n")
        let info = try XCTUnwrap(SteamLauncherProbe.resolve(candidates: [bad, good]))
        XCTAssertEqual(info.scriptName, SteamLauncherProbe.fixedScriptName)
        XCTAssertEqual(info.scriptSource, .fixedName)
    }

    /// 两条都成立时按优先级：plist 指的那个赢。
    func testFirstCandidateWins() {
        let plist = snapshot(name: "MyLauncher", text: "#!/bin/sh\nopen steam://run/1\n")
        let fixed = snapshot(name: SteamLauncherProbe.fixedScriptName, source: .fixedName,
                             text: "#!/bin/sh\nopen steam://run/2\n")
        XCTAssertEqual(SteamLauncherProbe.resolve(candidates: [plist, fixed])?.appID, "1")
    }

    func testEmptyCandidateList() {
        XCTAssertNil(SteamLauncherProbe.resolve(candidates: []))
    }

    /// plist 的值是外部输入：带 `/` 的一律不拼进路径（这一层不产生命名能力）。
    func testPathSeparatorsInExecutableAreRejected() {
        XCTAssertEqual(SteamLauncherProbe.scriptCandidates(bundleExecutable: "../../run.sh").count, 1)
        XCTAssertEqual(SteamLauncherProbe.scriptCandidates(bundleExecutable: "").count, 1)
        let both = SteamLauncherProbe.scriptCandidates(bundleExecutable: "SteamGame")
        XCTAssertEqual(both.count, 2)
        XCTAssertEqual(both.first?.source, .bundleExecutable)
        XCTAssertEqual(both.last?.name, SteamLauncherProbe.fixedScriptName)
    }

    // MARK: 只读读取（临时目录里的假 bundle）

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMSteamProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 造一个 `Contents/MacOS/<name>`，权限可控。
    @discardableResult
    private func writeScript(_ name: String, contents: String, permissions: UInt16 = 0o755) throws -> String {
        let dir = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        return url.path
    }

    func testReadResolvesLauncherFromDisk() throws {
        try writeScript("SteamGame", contents: "#!/bin/sh\nopen steam://run/220\n")
        let candidates = SteamLauncherProbe.read(appPath: root.path, bundleExecutable: "SteamGame")
        let info = try XCTUnwrap(SteamLauncherProbe.resolve(candidates: candidates))
        XCTAssertEqual(info.appID, "220")
        XCTAssertEqual(info.scriptSource, .bundleExecutable)
    }

    /// plist 指不到东西时，写死的那个名字仍然成立。
    func testReadFindsFixedNameWhenPlistPointsElsewhere() throws {
        try writeScript(SteamLauncherProbe.fixedScriptName, contents: "#!/bin/bash\nopen steam://launch/440\n")
        let candidates = SteamLauncherProbe.read(appPath: root.path, bundleExecutable: "NotThere")
        XCTAssertEqual(candidates.map(\.name), [SteamLauncherProbe.fixedScriptName])
        XCTAssertEqual(SteamLauncherProbe.resolve(candidates: candidates)?.scriptSource, .fixedName)
    }

    /// 同一个文件不因为两条入口而进两次。
    func testReadDeduplicatesSameFile() throws {
        try writeScript(SteamLauncherProbe.fixedScriptName, contents: "#!/bin/sh\nopen steam://run/220\n")
        XCTAssertEqual(SteamLauncherProbe.read(appPath: root.path,
                                              bundleExecutable: SteamLauncherProbe.fixedScriptName).count, 1)
    }

    /// 超限的文件只报大小、不 slurp 正文：不然每个应用都要为一个几十兆的 Mach-O 买单。
    func testReadSkipsBodyOfOversizedFile() throws {
        let body = "#!/bin/sh\nopen steam://run/220\n" + String(repeating: "x", count: 9_000)
        try writeScript("BigThing", contents: body)
        let candidates = SteamLauncherProbe.read(appPath: root.path, bundleExecutable: "BigThing")
        let snap = try XCTUnwrap(candidates.first { $0.name == "BigThing" })
        XCTAssertNil(snap.text)
        XCTAssertGreaterThan(snap.size, SteamLauncherProbe.maxScriptBytes)
        XCTAssertNil(SteamLauncherProbe.resolve(candidates: candidates))
    }

    /// 不可执行的文件不读正文（合同要求权限位，读它是白读）。
    func testReadSkipsBodyOfNonExecutableFile() throws {
        try writeScript("Plain", contents: "#!/bin/sh\nopen steam://run/220\n", permissions: 0o644)
        let candidates = SteamLauncherProbe.read(appPath: root.path, bundleExecutable: "Plain")
        XCTAssertEqual(candidates.first?.isExecutable, false)
        XCTAssertNil(candidates.first?.text)
        XCTAssertNil(SteamLauncherProbe.resolve(candidates: candidates))
    }

    /// 目录不算脚本；文件不存在返回空表。
    func testReadIgnoresDirectoriesAndMissingFiles() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents/MacOS/SteamGame",
                                                                               isDirectory: true),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(SteamLauncherProbe.read(appPath: root.path, bundleExecutable: "SteamGame"), [])
        XCTAssertEqual(SteamLauncherProbe.read(appPath: root.path, bundleExecutable: "NothingHere"), [])
    }

    /// 带 `/` 的 plist 值连路径都不拼。
    func testReadNeverLeavesMacOSDirectory() throws {
        try writeScript(SteamLauncherProbe.fixedScriptName, contents: "#!/bin/sh\nopen steam://run/220\n")
        let candidates = SteamLauncherProbe.read(appPath: root.path, bundleExecutable: "../run.sh")
        XCTAssertEqual(candidates.map(\.source), [.fixedName])
    }

    // MARK: 反方向那一行：steamapps 提醒

    func testGameLibraryCaveatOnlyWhenSteamAppsPresent() {
        XCTAssertEqual(SteamGameLibraryCaveat.note(children: ["config", "logs", "steamapps"]),
                       "这一项内含 steamapps 目录，已装游戏通常在它下面；删掉这一项会连游戏一起删。")
        XCTAssertNil(SteamGameLibraryCaveat.note(children: ["config", "logs"]))
        XCTAssertNil(SteamGameLibraryCaveat.note(children: []))
        XCTAssertNil(SteamGameLibraryCaveat.note(children: nil))
    }
}
