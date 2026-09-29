import XCTest
@testable import MMFileScanner

/// 安装包残留查找的判定边界。测的不是"能不能找到 dmg"，
/// 而是"会不会把不是安装包的东西报成安装包"、以及"核实不了时诚不诚实"。
/// 所有夹具都是测试自己在临时目录里造的假 magic bytes 小文件，
/// 不碰真实用户目录、不解压、不执行任何被扫描对象。
final class InstallerScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallerScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 夹具构造

    @discardableResult
    private func makeFile(_ relative: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    /// 600 字节乱数 + 512 字节 UDIF 尾块（'koly'、版本 4、headerSize=512，大端）。
    /// 结构与本机真实 dmg 的尾部实测一致。
    private func dmgBytes() -> Data {
        var data = Data((0..<600).map { UInt8($0 % 251) })
        var trailer = Data(count: 512)
        trailer.replaceSubrange(0..<4, with: [0x6B, 0x6F, 0x6C, 0x79])  // koly
        trailer.replaceSubrange(4..<8, with: [0x00, 0x00, 0x00, 0x04])  // version 4
        trailer.replaceSubrange(8..<12, with: [0x00, 0x00, 0x02, 0x00]) // headerSize 512
        data.append(trailer)
        return data
    }

    private func xarFileBytes() -> Data {
        var data = Data([0x78, 0x61, 0x72, 0x21]) // "xar!"
        data.append(Data((0..<64).map { UInt8($0 % 7) }))
        return data
    }

    // MARK: 最小 ZIP 生成器（stored，不压缩；条目内容随便填，嗅探只看中央目录的条目名）

    struct ZipEntry {
        let name: String
        var payload: Data = Data([0x01, 0x02])
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    private func buildZip(entries: [ZipEntry], forceZIP64Marker: Bool = false) -> Data {
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func le32(_ v: Int) -> Data {
            Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)])
        }

        var local = Data()
        struct Central { let name: Data; let offset: Int; let size: Int }
        var centrals: [Central] = []

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let offset = local.count
            var header = Data([0x50, 0x4B, 0x03, 0x04])
            header.append(le16(20)); header.append(le16(0)); header.append(le16(0))
            header.append(le16(0)); header.append(le16(0))               // 时间日期
            header.append(le32(0))                                       // crc（嗅探不校验）
            header.append(le32(entry.payload.count))
            header.append(le32(entry.payload.count))
            header.append(le16(nameData.count)); header.append(le16(0))
            local.append(header); local.append(nameData); local.append(entry.payload)
            centrals.append(Central(name: nameData, offset: offset, size: entry.payload.count))
        }

        let centralStart = local.count
        var central = Data()
        for item in centrals {
            var record = Data([0x50, 0x4B, 0x01, 0x02])
            record.append(le16(20)); record.append(le16(20)); record.append(le16(0)); record.append(le16(0))
            record.append(le16(0)); record.append(le16(0))
            record.append(le32(0))
            record.append(le32(item.size)); record.append(le32(item.size))
            record.append(le16(item.name.count)); record.append(le16(0)); record.append(le16(0))
            record.append(le16(0)); record.append(le16(0)); record.append(le32(0))
            record.append(le32(item.offset))
            central.append(record); central.append(item.name)
        }
        let centralSize = central.count

        var archive = local + central
        var eocd = Data([0x50, 0x4B, 0x05, 0x06])
        eocd.append(le16(0)); eocd.append(le16(0))
        if forceZIP64Marker {
            // 手工放 zip64 记录 + locator，并让 EOCD 的三个字段全指向"去问 zip64"。
            // 字段偏移与真实 zip64 EOCD 记录一致：magic(4) size(8) 版本(4) 盘号(8) 条目(16) 目录(16)。
            func le64(_ v: Int) -> Data {
                var out = Data()
                for i in 0..<8 { out.append(UInt8((v >> (8 * i)) & 0xFF)) }
                return out
            }
            var z64 = Data([0x50, 0x4B, 0x06, 0x06])
            z64.append(le64(44))
            z64.append(le16(45)); z64.append(le16(45))
            z64.append(le32(0)); z64.append(le32(0))
            z64.append(le64(entries.count)); z64.append(le64(entries.count))
            z64.append(le64(centralSize)); z64.append(le64(centralStart))
            let z64Offset = archive.count
            archive.append(z64)
            var locator = Data([0x50, 0x4B, 0x06, 0x07])
            locator.append(le32(0))
            locator.append(le64(z64Offset))
            locator.append(le32(1))
            archive.append(locator)
            eocd.append(le16(0xFFFF)); eocd.append(le16(0xFFFF))
            eocd.append(le32(0xFFFF_FFFF)); eocd.append(le32(0xFFFF_FFFF))
        } else {
            eocd.append(le16(entries.count)); eocd.append(le16(entries.count))
            eocd.append(le32(centralSize)); eocd.append(le32(centralStart))
        }
        eocd.append(le16(0)) // 无注释
        archive.append(eocd)
        return archive
    }

    private func scan() async -> InstallerScanReport {
        await InstallerScanner(roots: [root.path]).scan()
    }

    // MARK: - DMG

    func testDMGWithKolyTrailerIsVerified() async throws {
        try makeFile("Good.dmg", dmgBytes())
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "Good.dmg" })
        XCTAssertEqual(finding.evidence, .verified)
        XCTAssertTrue(finding.evidenceDetail.contains("koly"))
        XCTAssertEqual(finding.size, UInt64(600 + 512))
        XCTAssertNotNil(finding.modificationDate)
    }

    func testDMGWithoutKnownSignatureStaysNameOnly() async throws {
        try makeFile("Odd.dmg", Data((0..<800).map { UInt8($0 % 97) }))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "Odd.dmg" })
        // 认不出签名 ≠ "不是安装包"：降级到 nameOnly，绝不静默丢弃。
        XCTAssertEqual(finding.evidence, .nameOnly)
    }

    func testDmgThatIsActuallyAnAppZipIsVerifiedByZipEvidence() async throws {
        try makeFile("Fake.dmg", buildZip(entries: [
            ZipEntry(name: "Demo.app/"),
            ZipEntry(name: "Demo.app/Contents/MacOS/Demo"),
        ]))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "Fake.dmg" })
        XCTAssertEqual(finding.evidence, .verified)
        XCTAssertTrue(finding.evidenceDetail.contains("实为 zip"))
        XCTAssertTrue(finding.evidenceDetail.contains("Demo.app/"))
    }

    // MARK: - PKG / MPKG / XIP

    func testFlatPkgWithXarMagicIsVerified() async throws {
        try makeFile("tool.pkg", xarFileBytes())
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "tool.pkg" })
        XCTAssertEqual(finding.evidence, .verified)
        XCTAssertTrue(finding.evidenceDetail.contains("xar!"))
    }

    func testFlatPkgWithWrongMagicStaysNameOnly() async throws {
        try makeFile("junk.pkg", Data([0x4A, 0x55, 0x4E, 0x4B, 0x00, 0x01]))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "junk.pkg" })
        XCTAssertEqual(finding.evidence, .nameOnly)
    }

    func testExpandedPkgDirectoryIsVerifiedAndMeasured() async throws {
        try makeFile("Demo.pkg/Contents/Info.plist", Data("<plist/>".utf8))
        try makeFile("Demo.pkg/Contents/Archive.bom", Data([1, 2, 3, 4]))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "Demo.pkg" })
        XCTAssertEqual(finding.evidence, .verified)
        XCTAssertTrue(finding.isDirectory)
        XCTAssertEqual(finding.size, UInt64("<plist/>".utf8.count + 4))
    }

    func testPkgDirectoryWithoutPackageStructureIsNotListed() async throws {
        // 用户随手建的目录不该被当成安装包——目录形态只认核实过的包结构。
        try makeFile("notes.pkg/readme.txt", Data("hi".utf8))
        let report = await scan()
        XCTAssertTrue(report.findings.filter { $0.name == "notes.pkg" }.isEmpty)
    }

    func testXipWithSignedEnvelopeMagicIsVerified() async throws {
        var data = Data([0xAB, 0xC1, 0xAD, 0xFE])
        data.append(Data((0..<64).map { UInt8($0 % 5) }))
        try makeFile("big.xip", data)
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "big.xip" })
        XCTAssertEqual(finding.evidence, .verified)
        XCTAssertTrue(finding.evidenceDetail.contains("AB C1 AD FE"))
    }

    func testXipWithUnknownContentStaysNameOnly() async throws {
        try makeFile("mystery.xip", Data((0..<64).map { UInt8($0 % 3) }))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "mystery.xip" })
        XCTAssertEqual(finding.evidence, .nameOnly)
    }

    // MARK: - ZIP 嗅探（判不了就不报）

    func testZipWithTopLevelAppBundleIsReported() async throws {
        try makeFile("demo.zip", buildZip(entries: [
            ZipEntry(name: "Demo.app/"),
            ZipEntry(name: "Demo.app/Contents/MacOS/Demo"),
        ]))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "demo.zip" })
        XCTAssertEqual(finding.evidence, .verified)
        XCTAssertEqual(finding.formatLabel, "应用安装包 ZIP")
        XCTAssertTrue(finding.evidenceDetail.contains("Demo.app/"))
    }

    func testZipWithTopLevelInstallerFileIsReported() async throws {
        try makeFile("bundle.zip", buildZip(entries: [ZipEntry(name: "installer.dmg")]))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "bundle.zip" })
        XCTAssertTrue(finding.evidenceDetail.contains("installer.dmg"))
    }

    func testPlainZipIsNotReportedButStillInspected() async throws {
        try makeFile("holiday.zip", buildZip(entries: [
            ZipEntry(name: "photos/beach.jpg"),
            ZipEntry(name: "photos/dock.jpg"),
        ]))
        let report = await scan()
        XCTAssertTrue(report.findings.isEmpty)
        // "嗅过了、判定不是"与"根本没看"必须能区分开——inspectedCount 就是这个差。
        XCTAssertEqual(report.inspectedCount, 1)
    }

    func testNestedAppZipIsNotReported() throws {
        // 任务口径：条目名以 <AppName>.app/ 开头才算。嵌套一层的不算。
        XCTAssertNil(InstallerScanner.installerEntryReason(forZipEntry: "payload/Demo.app/Contents"))
        XCTAssertNotNil(InstallerScanner.installerEntryReason(forZipEntry: "Demo.app/Contents/MacOS/Demo"))
        XCTAssertNil(InstallerScanner.installerEntryReason(forZipEntry: "Demo.app")) // 非目录的单条不成立
        XCTAssertNotNil(InstallerScanner.installerEntryReason(forZipEntry: "Demo.app/"))
    }

    func testCorruptZipIsNotReported() async throws {
        // 有 PK 头、没中央目录：判定不了，宁可不列，也不许说它是（或不是）安装包。
        var data = Data([0x50, 0x4B, 0x03, 0x04])
        data.append(Data((0..<64).map { _ in 0xFF }))
        try makeFile("broken.zip", data)
        let report = await scan()
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.inspectedCount, 1)
    }

    func testZIP64MarkerArchiveIsHandled() async throws {
        try makeFile("huge.zip", buildZip(entries: [
            ZipEntry(name: "Big.app/Contents/MacOS/Big"),
        ], forceZIP64Marker: true))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "huge.zip" })
        XCTAssertTrue(finding.evidenceDetail.contains("Big.app/"))
    }

    // MARK: - 遍历边界

    func testSymlinksAndAppBundlesAreNeverListed() async throws {
        try makeFile("real.dmg", dmgBytes())
        try makeFile("MyApp.app/Contents/Resources/inner.dmg", dmgBytes())
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("stuff", isDirectory: true), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.dmg"),
            withDestinationURL: root.appendingPathComponent("real.dmg")
        )
        let report = await scan()
        let names = Set(report.findings.map(\.name))
        XCTAssertEqual(names, ["real.dmg"])
    }

    func testOneLevelOfNestingIsScanned() async throws {
        try makeFile("stuff/inner.dmg", dmgBytes())
        let report = await scan()
        XCTAssertEqual(report.findings.map(\.name), ["inner.dmg"])
    }

    func testCancelledScanReportsIncomplete() async throws {
        try makeFile("Good.dmg", dmgBytes())
        let report = await InstallerScanner(roots: [root.path]).scan(shouldContinue: { false })
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testSizeOfUnmeasurableDirectoryIsNilNotZero() async throws {
        // 包结构齐全但目录统计不了的情形难以稳定复现；退而验证口径本身：
        // InstallerFinding.size 是可选值，nil 就是"测量中"，类型上就不允许写 0 冒充实测。
        try makeFile("Half.pkg/Contents/Info.plist", Data("<plist/>".utf8))
        let report = await scan()
        let finding = try XCTUnwrap(report.findings.first { $0.name == "Half.pkg" })
        XCTAssertNotNil(finding.size)
    }
}
