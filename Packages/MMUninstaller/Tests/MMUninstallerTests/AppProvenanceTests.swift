import XCTest
import Foundation
@testable import MMUninstaller

/// 来源识别的评估口径和孤儿扫描同一条：**没有凭据就是没有凭据**。
/// 所以这里"不该报"的断言比"该报"的更重要——把一份手装的应用说成
/// "Homebrew cask"，用户下一步就是 `brew uninstall`，然后发现什么都没发生。
final class AppProvenanceTests: XCTestCase {
    private var fixture: ProvenanceFixture!

    override func setUpWithError() throws {
        fixture = try ProvenanceFixture()
    }

    override func tearDown() {
        fixture?.cleanup()
        fixture = nil
        super.tearDown()
    }

    private func provenance(for app: DiscoveredApp,
                            packageIdentifiers: Set<String> = []) -> AppProvenance {
        AppProvenanceScanner.provenance(for: app,
                                        index: fixture.index(),
                                        packageIdentifiers: packageIdentifiers)
    }

    // MARK: - 强证据：设备号同一

    func testStagedLinkResolvingToTheBundleIsStrongCask() throws {
        try fixture.app("Highball")
        try fixture.cask(token: "highball", version: "0.9.39",
                         stagedApps: ["Highball.app"], declaredApps: ["Highball.app"])
        let result = provenance(for: fixture.discovered("Highball"))
        XCTAssertEqual(result.source, .homebrewCask)
        XCTAssertEqual(result.cask?.token, "highball")
        XCTAssertEqual(result.cask?.version, "0.9.39")
        XCTAssertEqual(result.cask?.tap, "homebrew/cask")
        XCTAssertTrue(result.cask?.receiptPath.hasSuffix("highball/.metadata/INSTALL_RECEIPT.json") ?? false)
    }

    func testStagedLinkKeepsTheReceiptSpellingWhileNamesMatchCaseInsensitively() throws {
        try fixture.app("wailbrew")
        try fixture.cask(token: "WailBrew", stagedApps: ["wailbrew.app"], declaredApps: ["WailBrew.app"])
        let result = provenance(for: fixture.discovered("wailbrew"))
        XCTAssertEqual(result.source, .homebrewCask)
        XCTAssertEqual(result.cask?.token, "WailBrew")
    }

    /// 设备号同一是"这份 bundle 就是 brew 摆在这里的那份"的直接证据；
    /// `_MASReceipt` 跟着 bundle 走，拷一份也带着，所以排在它后面。
    func testDeviceIdentityBeatsAppStoreReceipt() throws {
        try fixture.app("Highball", masReceipt: true)
        try fixture.cask(token: "highball", stagedApps: ["Highball.app"], declaredApps: ["Highball.app"])
        XCTAssertEqual(provenance(for: fixture.discovered("Highball")).source, .homebrewCask)
    }

    func testTwoCasksStagingTheSameBundleIsAmbiguous() throws {
        try fixture.app("Highball")
        try fixture.cask(token: "highball", stagedApps: ["Highball.app"], declaredApps: ["Highball.app"])
        try fixture.cask(token: "highball-beta", stagedApps: ["Highball.app"], declaredApps: ["Highball.app"])
        let result = provenance(for: fixture.discovered("Highball"))
        XCTAssertEqual(result.source, .unknown)
        XCTAssertEqual(result.ambiguousCaskTokens, ["highball", "highball-beta"])
        XCTAssertTrue(result.ambiguousByDeviceIdentity, "抢的是同一份文件，不是同一个名字")
    }

    // MARK: - 中证据：只有名字对上

    func testNameOnlyMatchWhenStagedLinkPointsElsewhere() throws {
        try fixture.app("Highball")
        try fixture.app("HighballCopy")
        try fixture.cask(token: "highball", stagedApps: ["HighballCopy.app"], declaredApps: ["Highball.app"])
        let result = provenance(for: fixture.discovered("Highball"))
        XCTAssertEqual(result.source, .homebrewCaskNameOnly)
        XCTAssertEqual(result.cask?.token, "highball")
    }

    func testAppStoreReceiptBeatsNameOnlyMatch() throws {
        try fixture.app("Highball", masReceipt: true)
        try fixture.app("HighballCopy")
        try fixture.cask(token: "highball", stagedApps: ["HighballCopy.app"], declaredApps: ["Highball.app"])
        XCTAssertEqual(provenance(for: fixture.discovered("Highball")).source, .appStore)
    }

    func testTwoCasksDeclaringTheSameNameIsAmbiguous() throws {
        try fixture.app("Firefox")
        try fixture.cask(token: "firefox", stagedApps: [], declaredApps: ["Firefox.app"])
        try fixture.cask(token: "firefox-beta", stagedApps: [], declaredApps: ["Firefox.app"])
        let result = provenance(for: fixture.discovered("Firefox"))
        XCTAssertEqual(result.source, .unknown)
        XCTAssertEqual(result.ambiguousCaskTokens, ["firefox", "firefox-beta"])
        XCTAssertFalse(result.ambiguousByDeviceIdentity)
    }

    // MARK: - 账本在、应用不在 / 账本里没有应用

    func testDanglingStagedLinkProducesNoClaim() throws {
        try fixture.cask(token: "codeedit", stagedApps: ["CodeEdit.app"], declaredApps: ["CodeEdit.app"],
                         createStagedTarget: false)
        // 应用目录里根本没有 CodeEdit.app，清单不该凭空多一行；
        // 即便有人手工放了同名目录，设备号也对不上，最多落到名字档。
        try fixture.app("CodeEdit")
        XCTAssertEqual(provenance(for: fixture.discovered("CodeEdit")).source, .homebrewCaskNameOnly)
    }

    func testPkgStyleCaskWithoutAppEntriesIsNotAttributed() throws {
        try fixture.app("Temurin")
        try fixture.cask(token: "temurin@17", stagedApps: [], declaredApps: [],
                         rawArtifacts: [[ "pkgutil": ["com.adoptopenjdk.17.jdk"] ]])
        XCTAssertEqual(provenance(for: fixture.discovered("Temurin")).source, .unknown)
    }

    func testBinaryOnlyCaskIsNotAttributedToApps() throws {
        try fixture.app("adb")
        try fixture.cask(token: "android-platform-tools", stagedApps: [], declaredApps: [],
                         rawArtifacts: [["binary": ["/opt/homebrew/bin/adb"]]])
        XCTAssertEqual(provenance(for: fixture.discovered("adb")).source, .unknown)
    }

    // MARK: - 账本坏了 / 没有 brew

    func testMalformedReceiptIsIgnored() throws {
        try fixture.app("Highball")
        try fixture.writeRaw(receipt: "{ not json", token: "highball")
        XCTAssertEqual(provenance(for: fixture.discovered("Highball")).source, .unknown)
    }

    func testMissingPrefixIsEmptyIndex() {
        let index = AppProvenanceScanner.buildIndex(prefixes: [fixture.root + "/nope"],
                                                    fileManager: .default)
        XCTAssertEqual(index.records.count, 0)
    }

    // MARK: - 其它来源

    func testAppStoreReceipt() throws {
        try fixture.app("WeChat", masReceipt: true)
        XCTAssertEqual(provenance(for: fixture.discovered("WeChat")).source, .appStore)
    }

    func testInstallerPackageIdentifierMatch() throws {
        try fixture.app("iTools")
        let result = provenance(for: fixture.discovered("iTools", bundleID: "cn.i4tools.mac"),
                                packageIdentifiers: ["cn.i4tools.mac"])
        XCTAssertEqual(result.source, .installerPackage)
        XCTAssertEqual(result.packageIdentifier, "cn.i4tools.mac")
    }

    func testUnknownStaysUnknownAndNeverClaimsManual() throws {
        try fixture.app("Mystery")
        let result = provenance(for: fixture.discovered("Mystery"))
        XCTAssertEqual(result.source, .unknown)
        XCTAssertTrue(result.ambiguousCaskTokens.isEmpty)
        XCTAssertNil(result.cask)
    }

    func testZapEntryCountIsReportedAsAFact() throws {
        try fixture.app("Highball")
        try fixture.cask(token: "highball", stagedApps: ["Highball.app"], declaredApps: ["Highball.app"],
                         rawArtifacts: [
                            ["app": ["Highball.app"]],
                            ["zap": [["trash": ["~/Library/Caches/x.Highball", "~/Library/Preferences/x.Highball.plist"]]]],
                         ])
        XCTAssertEqual(provenance(for: fixture.discovered("Highball")).cask?.zapEntryCount, 2)
    }

    // MARK: - 接进列表

    /// 来源是在 `loadApps` 里贴到条目上的，注入点就是截图钩子那条线：
    /// 假 home 配假账本，绝不能让夹具截图去读真机的 /opt/homebrew。
    @MainActor
    func testLoadAppsAttachesProvenanceFromInjectedPrefixes() async throws {
        try fixture.app("Highball")
        try fixture.cask(token: "highball", stagedApps: ["Highball.app"], declaredApps: ["Highball.app"])
        let model = UninstallerModel()
        model.optionsFactory = { ResidualScanOptions(home: self.fixture.appsDirectory) }
        model.appDirectoriesFactory = { _ in [self.fixture.appsDirectory] }
        model.provenancePrefixesFactory = { _ in [self.fixture.root + "/brew"] }
        model.provenanceReceiptsRootFactory = { _ in nil }
        await model.loadApps()
        XCTAssertEqual(model.apps.first?.provenance.source, .homebrewCask)
        XCTAssertEqual(model.apps.first?.provenance.cask?.token, "highball")
    }

    /// 歧义也是事实：它落在 `unknown` 这一档，早先"unknown 不入表"的省法把它一起丢了，
    /// 于是页面上只剩一句空白的"无法判定"，看不出是两个 cask 在打架。
    @MainActor
    func testLoadAppsKeepsAmbiguousCaskTokensOnAnUnknownSource() async throws {
        try fixture.app("Firefox")
        try fixture.cask(token: "firefox", stagedApps: ["Firefox.app"], declaredApps: ["Firefox.app"])
        try fixture.cask(token: "firefox-beta", stagedApps: ["Firefox.app"], declaredApps: ["Firefox.app"])
        let model = UninstallerModel()
        model.optionsFactory = { ResidualScanOptions(home: self.fixture.appsDirectory) }
        model.appDirectoriesFactory = { _ in [self.fixture.appsDirectory] }
        model.provenancePrefixesFactory = { _ in [self.fixture.root + "/brew"] }
        model.provenanceReceiptsRootFactory = { _ in nil }
        await model.loadApps()
        let firefox = model.apps.first { $0.bundleName == "Firefox" }
        XCTAssertEqual(firefox?.provenance.source, .unknown)
        XCTAssertEqual(firefox?.provenance.ambiguousCaskTokens, ["firefox", "firefox-beta"])
        XCTAssertEqual(firefox?.sourceValue, "无法判定（firefox、firefox-beta 两份账本把同一个 .app 摆到了这里）")
    }
}

/// 夹具：一棵假的 `<prefix>/Caskroom` + 一个假的应用目录。
/// 全部在临时目录里造，staged `.app` 用真符号链接——设备号同一这条判据
/// 用假数据是测不出来的。
final class ProvenanceFixture {
    let root: String
    let appsDirectory: String
    private let fileManager = FileManager.default

    init() throws {
        root = NSTemporaryDirectory() + "mm-provenance-\(UUID().uuidString)"
        appsDirectory = root + "/Applications"
        try fileManager.createDirectory(atPath: root + "/brew/Caskroom",
                                        withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: appsDirectory, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(atPath: root)
    }

    func index() -> CaskIndex {
        AppProvenanceScanner.buildIndex(prefixes: [root + "/brew"], fileManager: fileManager)
    }

    func discovered(_ name: String, bundleID: String = "com.example.\(UUID().uuidString)") -> DiscoveredApp {
        DiscoveredApp(path: "\(appsDirectory)/\(name).app", bundleName: name, bundleID: bundleID)
    }

    /// 造一个真应用目录。
    func app(_ name: String, masReceipt: Bool = false) throws {
        let path = "\(appsDirectory)/\(name).app"
        try fileManager.createDirectory(atPath: path + "/Contents", withIntermediateDirectories: true)
        if masReceipt {
            try fileManager.createDirectory(atPath: path + "/Contents/_MASReceipt",
                                            withIntermediateDirectories: true)
            fileManager.createFile(atPath: path + "/Contents/_MASReceipt/receipt", contents: Data())
        }
    }

    func cask(token: String, version: String = "1.0",
              stagedApps: [String], declaredApps: [String],
              createStagedTarget: Bool = true,
              rawArtifacts: [[String: Any]]? = nil) throws {
        let tokenRoot = root + "/brew/Caskroom/\(token)"
        try fileManager.createDirectory(atPath: tokenRoot + "/.metadata", withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: tokenRoot + "/\(version)", withIntermediateDirectories: true)

        var artifacts: [[String: Any]] = rawArtifacts ?? []
        if rawArtifacts == nil {
            if !declaredApps.isEmpty { artifacts.append(["app": declaredApps]) }
        }
        let receipt: [String: Any] = [
            "homebrew_version": "6.0.10",
            "installed_on_request": true,
            "time": 1_784_024_063,
            "source": ["tap": "homebrew/cask", "version": version, "path": "/tmp/api.jws.json"],
            "uninstall_artifacts": artifacts,
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt)
        try data.write(to: URL(fileURLWithPath: tokenRoot + "/.metadata/INSTALL_RECEIPT.json"))

        for staged in stagedApps {
            let link = tokenRoot + "/\(version)/\(staged)"
            let targetName = String(staged.dropLast(4))
            // createStagedTarget=false 要的是真断链：链接指向一个永远不存在的路径。
            // 早先写的是"不造目标、链还是指向 appsDirectory"，结果后面 fixture.app()
            // 一把目标造出来，这条链当场又活了，测的其实是一条正常链。
            let target = createStagedTarget
                ? "\(appsDirectory)/\(targetName).app"
                : "\(root)/removed-before-this-run/\(targetName).app"
            if createStagedTarget {
                try fileManager.createDirectory(atPath: target + "/Contents", withIntermediateDirectories: true)
            }
            try fileManager.createSymbolicLink(atPath: link, withDestinationPath: target)
        }
    }

    func writeRaw(receipt: String, token: String) throws {
        let tokenRoot = root + "/brew/Caskroom/\(token)"
        try fileManager.createDirectory(atPath: tokenRoot + "/.metadata", withIntermediateDirectories: true)
        try Data(receipt.utf8).write(to: URL(fileURLWithPath: tokenRoot + "/.metadata/INSTALL_RECEIPT.json"))
    }
}
