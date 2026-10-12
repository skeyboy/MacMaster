import Foundation
import XCTest
@testable import MMOptimizer

/// P34b 的判据与文案合同。
///
/// 为什么这一族单测要**造真文件**而不是喂合成值：判据读的是文件系统状态，
/// 合成值只能证明界面会写字，证明不了写的是真话
/// （口径同 `docs/analysis/optimizer-corrupt-preferences.md` §12 第 1 条）。
/// 所以下面这 12 条是 P34a 夹具档的等价物，走的是生产的那一条采集+读取路径。
final class PreferencesAuditTests: XCTestCase {

    private var fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("mm-prefs-audit-\(UUID().uuidString)")
        try fm.createDirectory(at: prefs.appendingPathComponent("ByHost"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // perm-000 那条先把权限放开，否则 removeItem 会失败并把下一跑也带坏。
        try? fm.setAttributes([.posixPermissions: 0o600],
                              ofItemAtPath: prefs.appendingPathComponent("perm-000.plist").path)
        try? fm.removeItem(at: root)
    }

    private var prefs: URL { root.appendingPathComponent("Library/Preferences") }

    /// 写一个文件进夹具树，返回它的 URL。
    @discardableResult
    private func write(_ relative: String, _ data: Data, mode: Int32? = nil) throws -> URL {
        let url = prefs.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let mode { try fm.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: url.path) }
        return url
    }

    private func dictData(_ format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        let dict: [String: Any] = ["enabled": true, "count": 3, "name": "MacMaster"]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
    }

    // MARK: - 12 条判据矩阵（P34a `synth-cases.log` 的等价物）

    func testVerdictMatrixAgainstRealFiles() throws {
        let bin = try dictData(.binary)
        let xml = try dictData(.xml)
        // OpenStep 只能手写：`PropertyListSerialization` 不支持写这一格式（P34a 当场撞死的）。
        let ascii = Data("{\n  enabled = 1;\n  count = 3;\n  name = MacMaster;\n}\n".utf8)
        let emptyDict = try PropertyListSerialization
            .data(fromPropertyList: [String: Any](), format: .binary, options: 0)
        let arrayRoot = try PropertyListSerialization
            .data(fromPropertyList: ["a", 1], format: .binary, options: 0)
        let stringRoot = try PropertyListSerialization
            .data(fromPropertyList: "just a string", format: .xml, options: 0)

        try write("valid-binary.plist", bin)
        try write("valid-xml.plist", xml)
        try write("valid-openstep.plist", ascii)
        try write("empty-dict.plist", emptyDict)
        try write("root-array.plist", arrayRoot)
        try write("root-string.plist", stringRoot)
        try write("zero-byte.plist", Data())
        try write("truncated-binary.plist", bin.prefix(12))
        try write("garbage-text.plist", Data("这不是 plist，是一段随便的文本\n".utf8))
        try write("xml-unclosed.plist", xml.prefix(xml.count - 20))
        try write("perm-000.plist", bin, mode: 0o000)
        try write("ByHost/byhost-truncated.plist", bin.prefix(8))

        let scan = PreferencesAuditor.liveScan(home: root.path)
        XCTAssertEqual(scan.inspectedCount, 12, "采集路径应当把顶层 11 条 + ByHost 1 条都收进来")
        XCTAssertTrue(scan.skippedRoots.isEmpty)
        XCTAssertFalse(scan.isPartial)

        func verdict(of name: String) -> PrefsVerdict? {
            scan.rows.first { $0.name == name }?.verdict
        }
        for name in ["valid-binary.plist", "valid-xml.plist", "valid-openstep.plist", "empty-dict.plist"] {
            XCTAssertEqual(verdict(of: name), .parsed(root: "dict"), "\(name) 应当解析成字典根")
        }
        XCTAssertEqual(verdict(of: "root-array.plist"), .parsed(root: "array"))
        XCTAssertEqual(verdict(of: "root-string.plist"), .parsed(root: "string"))
        XCTAssertEqual(verdict(of: "zero-byte.plist"), .zeroByte)
        if case .unparsable? = verdict(of: "truncated-binary.plist") {} else {
            XCTFail("截断的二进制要判成解析失败，实际：\(String(describing: verdict(of: "truncated-binary.plist")))")
        }
        if case .unparsable? = verdict(of: "garbage-text.plist") {} else { XCTFail("乱码文本要判成解析失败") }
        if case .unparsable? = verdict(of: "xml-unclosed.plist") {} else { XCTFail("截尾的 XML 要判成解析失败") }

        if geteuid() == 0 {
            print("以 root 身份跑：perm-000 那条读得到，跳过该断言（000 档只对非 root 成立）")
        } else if case .unreadable? = verdict(of: "perm-000.plist") {
            // 读不到 ≠ 损坏：它进的是另一栏。
            XCTAssertTrue(scan.badRows.allSatisfy { $0.name != "perm-000.plist" })
            XCTAssertTrue(scan.unreadableRows.contains { $0.name == "perm-000.plist" })
        } else {
            XCTFail("mode 000 的文件在普通用户下必须读不到，实际：\(String(describing: verdict(of: "perm-000.plist")))")
        }
    }

    /// 只有魔数的 8 字节 `bplist00`：`plutil -lint` 给 OK、Foundation 解析出一个非字典根。
    /// 把它算进"损坏"会造出一条对照判据不认的假故障——这一条就是那件事的回归锁。
    func testMagicOnlyFileIsParsedNotBad() throws {
        let bin = try dictData(.binary)
        try write("ByHost/magic-only.plist", bin.prefix(8))
        let scan = PreferencesAuditor.liveScan(home: root.path)
        guard let row = scan.rows.first, case .parsed(let root) = row.verdict else {
            return XCTFail("8 字节魔数文件两把尺子都说正常，不该落到坏的那一栏")
        }
        XCTAssertNotEqual(root, "dict")
        XCTAssertFalse(row.verdict.isBad)
        XCTAssertTrue(scan.badRows.isEmpty)
        XCTAssertEqual(scan.nonDictRootCount, 1)
    }

    // MARK: - 四态本体

    func testIsBadCoversExactlyThreeStates() {
        XCTAssertTrue(PrefsVerdict.unreadable(reason: "x").isBad)
        XCTAssertTrue(PrefsVerdict.zeroByte.isBad)
        XCTAssertTrue(PrefsVerdict.unparsable(reason: "x").isBad)
        XCTAssertFalse(PrefsVerdict.parsed(root: "dict").isBad)
        XCTAssertFalse(PrefsVerdict.parsed(root: "array").isBad)
        XCTAssertTrue(PrefsVerdict.unreadable(reason: "x").isUnreadable)
        XCTAssertFalse(PrefsVerdict.zeroByte.isUnreadable)
    }

    func testVerdictFromInjectedReadResult() {
        XCTAssertEqual(PreferencesAuditor.verdict(from: .success(Data())), .zeroByte)
        if case .unreadable = PreferencesAuditor.verdict(
            from: .failure(NSError(domain: NSCocoaErrorDomain, code: 257))) {
            // reason 里带 localizedDescription，各系统版本措辞不同，所以只钉类别。
        } else {
            XCTFail("读取抛错必须判成读不到，而不是「0 字节」或「没这个文件」")
        }
        if case .unparsable = PreferencesAuditor.verdict(from: .success(Data("{ <garbage 断不掉\n".utf8))) {} else {
            XCTFail("残缺的 openStep 片段要判成解析失败")
        }
        // 本轮现读到的一条边界（不是查来的）：**全是 ASCII 单词的垃圾会被 openStep 读成一个字符串根**。
        // `plutil -lint /tmp/…（内容 "nonsense"）` 同样给 OK，所以两把尺子在这一条上仍然不分家；
        // 界面不能把它说成损坏——它走的是「根不是字典」那一支（不列行）。
        XCTAssertEqual(PreferencesAuditor.verdict(from: .success(Data("nonsense".utf8))),
                       .parsed(root: "string"))
    }

    // MARK: - 采集边界

    func testListIncludesHiddenGlobalPreferencesAndSkipsNonRegular() throws {
        let bin = try dictData(.binary)
        try write(".GlobalPreferences.plist", bin)
        try write("normal.plist", bin)
        try write("not-a-plist.txt", bin)
        try fm.createDirectory(at: prefs.appendingPathComponent("some-dir.plist"),
                               withIntermediateDirectories: true)
        // 软链到同层的一个真文件：下不了判据，也不能被数进"检查过 N 个"。
        try fm.createSymbolicLink(atPath: prefs.appendingPathComponent("link.plist").path,
                                  withDestinationPath: prefs.appendingPathComponent("normal.plist").path)

        let listing = PreferencesAuditor.list(prefs: prefs)
        let names = Set(listing.files.map { $0.lastPathComponent })
        XCTAssertEqual(names, ["normal.plist", ".GlobalPreferences.plist"])
        XCTAssertEqual(listing.skippedNonRegular, 2, "目录 + 软链各一条")
    }

    /// ByHost 递归不跟随目录软链：本机实测过一条指向父目录的环和一条指向外部的链，
    /// 两种都停在原地。这一条是"检查过 N 个"不数到这一族外面的回归锁。
    func testListDoesNotEscapeThroughSymlinkedDirectories() throws {
        let bin = try dictData(.binary)
        try write("ByHost/real.plist", bin)
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try bin.write(to: outside.appendingPathComponent("escaped.plist"))
        try fm.createSymbolicLink(atPath: prefs.appendingPathComponent("ByHost/esc").path,
                                  withDestinationPath: outside.path)
        try fm.createSymbolicLink(atPath: prefs.appendingPathComponent("ByHost/loop").path,
                                  withDestinationPath: prefs.appendingPathComponent("ByHost").path)

        let listing = PreferencesAuditor.list(prefs: prefs)
        XCTAssertEqual(listing.files.map { $0.lastPathComponent }, ["real.plist"])
        XCTAssertFalse(listing.files.contains { $0.lastPathComponent == "escaped.plist" })
    }

    func testListReportsUnreadableTopLevelAsSkippedRoot() {
        let listing = PreferencesAuditor.list(prefs: root.appendingPathComponent("没有这一层"))
        XCTAssertTrue(listing.files.isEmpty)
        XCTAssertEqual(listing.skippedRoots.count, 1, "整层没读到必须能说话，不许渲染成「没有发现」")
    }

    // MARK: - 预算与截断

    func testBudgetTruncatesAndCountsTheRemaining() throws {
        let bin = try dictData(.binary)
        let files = (0..<10).map { URL(fileURLWithPath: "/fake/f\($0).plist") }
        var tick = 0.0
        let scan = PreferencesAuditor.scan(
            prefs: URL(fileURLWithPath: "/fake/Library/Preferences"),
            budgetMillis: 5,
            listing: { _ in PrefsListing(files: files, skippedRoots: [], skippedNonRegular: 0) },
            read: { _ in .success(bin) },
            attributes: { _ in (bin.count, nil) },
            clock: { tick += 1; return tick }
        )
        XCTAssertTrue(scan.isPartial)
        XCTAssertLessThan(scan.inspectedCount, files.count)
        XCTAssertEqual(scan.notInspectedCount, files.count - scan.rows.count)
        XCTAssertEqual(scan.parsedCount, scan.rows.count)
    }

    func testGenerousBudgetScansEverything() throws {
        let bin = try dictData(.binary)
        let files = (0..<10).map { URL(fileURLWithPath: "/fake/f\($0).plist") }
        let scan = PreferencesAuditor.scan(
            prefs: URL(fileURLWithPath: "/fake/Library/Preferences"),
            budgetMillis: 1_000_000,
            listing: { _ in PrefsListing(files: files, skippedRoots: [], skippedNonRegular: 0) },
            read: { _ in .success(bin) },
            attributes: { _ in (bin.count, nil) },
            clock: { 0 }
        )
        XCTAssertFalse(scan.isPartial)
        XCTAssertEqual(scan.inspectedCount, 10)
        XCTAssertEqual(scan.notInspectedCount, 0)
    }

    // MARK: - 文案合同（§5 那张表）

    func testUnreadableAndBadAreSeparateColumns() {
        let rows: [PreferenceFileCheck] = [
            check("empty.plist", .zeroByte),
            check("broken.plist", .unparsable(reason: "夹具")),
            check("vault.plist", .unreadable(reason: "夹具")),
            check("ok.plist", .parsed(root: "dict")),
        ]
        let scan = PreferencesScan(rows: rows, skippedRoots: [], skippedNonRegular: 0,
                                   foundFiles: 4, isPartial: false,
                                   millis: PrefsMillis(enumerate: 1, read: 2, parse: 3))
        XCTAssertEqual(scan.badRows.map { $0.name }.sorted(), ["broken.plist", "empty.plist"])
        XCTAssertEqual(scan.unreadableRows.map { $0.name }, ["vault.plist"])
        XCTAssertEqual(scan.inspectedCount, 4)
        XCTAssertEqual(scan.parsedCount, 1)
        XCTAssertEqual(scan.unreadableCount, 1)
    }

    func testHeadlineSentences() {
        let mixed = PreferencesScan(
            rows: [check("a.plist", .unreadable(reason: "x")), check("b.plist", .parsed(root: "dict")),
                   check("c.plist", .unreadable(reason: "x"))],
            skippedRoots: [], skippedNonRegular: 0, foundFiles: 3, isPartial: false, millis: PrefsMillis())
        XCTAssertEqual(PreferencesCopy.headline(mixed), "检查过 3 个偏好文件；其中 2 个我们没能读。")

        let truncated = PreferencesScan(
            rows: [check("a.plist", .parsed(root: "dict"))],
            skippedRoots: [], skippedNonRegular: 0, foundFiles: 1_042, isPartial: true, millis: PrefsMillis())
        XCTAssertEqual(PreferencesCopy.headline(truncated),
                       "检查过 1 个偏好文件就到了时间预算，剩下的 1041 个没看。")
    }

    /// §5 的「禁止说」那一列：这一族的文案里不许出现"已损坏 / 建议删除 / 已修复 / 都是健康的"。
    func testCopyNeverOverclaims() {
        let forbidden = ["已损坏", "损坏", "建议删除", "已修复", "修好", "都是健康的", "健康"]
        let samples = [
            PreferencesCopy.advice(check("z.plist", .zeroByte)),
            PreferencesCopy.advice(check("u.plist", .unparsable(reason: "x"))),
            PreferencesCopy.advice(check("r.plist", .unreadable(reason: "x"))),
            PreferencesCopy.unreadableNote(11),
            PreferencesCopy.footnote,
            PreferencesCopy.nonDictRootNote(3),
            PreferencesCopy.badSection, PreferencesCopy.unreadableSection,
        ]
        for text in samples {
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "「\(text)」里不许出现「\(word)」")
            }
        }
        XCTAssertTrue(PreferencesCopy.advice(check("z.plist", .zeroByte)).contains("可能是上次写入中断"))
        XCTAssertTrue(PreferencesCopy.advice(check("u.plist", .unparsable(reason: "x"))).contains("MacMaster 不动它"))
    }

    func testProtectedNameFamily() {
        XCTAssertTrue(PreferencesAuditor.isProtectedName("com.apple.TV.plist"))
        XCTAssertTrue(PreferencesAuditor.isProtectedName(".GlobalPreferences.plist"))
        XCTAssertTrue(PreferencesAuditor.isProtectedName("loginwindow.plist"))
        XCTAssertFalse(PreferencesAuditor.isProtectedName("com.example.app.plist"))
        XCTAssertFalse(PreferencesAuditor.isProtectedName("MyApp.plist"))
    }

    private func check(_ name: String, _ verdict: PrefsVerdict) -> PreferenceFileCheck {
        PreferenceFileCheck(id: name, name: name, path: "/tmp/mm-optimizer-fixture/\(name)",
                            inByHost: false, bytes: nil, modified: nil, verdict: verdict)
    }
}
