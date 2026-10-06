//
//  HookValueTests.swift — 取证钩子取值解析的单测
//
//  钉住的是"写错值时到底说什么"：钩子的错误只反映在 stderr 那一行上，
//  照片本身看不出破绽，所以这一层必须由测试保证，不能靠肉眼。
//  全程零文件写入（只有留痕测试会开一个临时文件接 stderr）、零系统调用。
//

import XCTest
@testable import MMCore

private enum DemoTab: String, MMHookKeyed, CaseIterable {
    case cache, folders, system, dev
    var hookKey: String { rawValue }
}

final class HookValueTests: XCTestCase {

    private let cases = DemoTab.allCases

    // MARK: - 未设置：生产路径，不许留痕

    func testUnsetFallsBackSilently() {
        let r = MMHookValue.resolve(raw: nil, fallback: DemoTab.cache, cases: cases)
        XCTAssertEqual(r.selected, .cache)
        XCTAssertNil(r.rejected)
        XCTAssertNil(r.note(key: "MM_OPEN_TAB"))
    }

    func testEmptyAndBlankCountAsUnset() {
        for raw in ["", "   ", "\n"] {
            let r = MMHookValue.resolve(raw: raw, fallback: DemoTab.cache, cases: cases)
            XCTAssertEqual(r.selected, .cache, "空值 \(raw.debugDescription) 应当按未设置处理")
            XCTAssertNil(r.note(key: "MM_OPEN_TAB"))
        }
    }

    // MARK: - 命中

    func testExactKeySelectsThatCase() {
        XCTAssertEqual(MMHookValue.resolve(raw: "system", fallback: .cache, cases: cases).selected, .system)
        XCTAssertEqual(MMHookValue.resolve(raw: "dev", fallback: .cache, cases: cases).selected, .dev)
    }

    func testSurroundingBlankAndCaseAreNormalized() {
        // 与 Guardian/Monitor/Optimizer 的 parse 同一口径：trim + 小写。
        let r = MMHookValue.resolve(raw: "  System ", fallback: .cache, cases: cases)
        XCTAssertEqual(r.selected, .system)
        XCTAssertNil(r.rejected)
    }

    // MARK: - 写错值：必须留痕，且文案要说清落到了哪一档

    func testTypoFallsBackAndRejects() {
        let r = MMHookValue.resolve(raw: "sytem", fallback: .cache, cases: cases)
        XCTAssertEqual(r.selected, .cache)
        XCTAssertEqual(r.rejected, "sytem")
    }

    func testNoteNamesKeyRawValueAcceptedListAndLandedCase() {
        let r = MMHookValue.resolve(raw: "sytem", fallback: .cache, cases: cases)
        let note = r.note(key: "MM_OPEN_TAB") ?? ""
        XCTAssertTrue(note.contains("MM_OPEN_TAB"), note)
        XCTAssertTrue(note.contains("sytem"), note)
        XCTAssertTrue(note.contains("cache|folders|system|dev"), "可接受集合要由档位表现算：\(note)")
        XCTAssertTrue(note.contains("已回落 cache"), note)
    }

    func testNoteKeepsTheOriginalSpellingNotTheNormalizedToken() {
        // 核对的人在日志里要认出自己敲的那几个字母，所以报原文。
        let r = MMHookValue.resolve(raw: "SYTEM", fallback: .cache, cases: cases)
        XCTAssertTrue((r.note(key: "MM_OPEN_TAB") ?? "").contains("SYTEM"))
    }

    func testAcceptedListCoversEveryCaseEvenTheNonDefault() {
        let r = MMHookValue.resolve(raw: "x", fallback: .system, cases: cases)
        for tab in cases {
            XCTAssertTrue(r.accepts.contains(tab.hookKey))
        }
        XCTAssertTrue((r.note(key: "K") ?? "").contains("已回落 system"))
    }

    // MARK: - 数字档

    func testIntAcceptsInBoundsOnly() {
        XCTAssertEqual(MMHookValue.resolveInt(raw: "3", fallback: 2, bounds: 1...4).value, 3)
        XCTAssertNil(MMHookValue.resolveInt(raw: "3", fallback: 2, bounds: 1...4).rejected)
        XCTAssertEqual(MMHookValue.resolveInt(raw: " 4 ", fallback: 2, bounds: 1...4).value, 4)
    }

    func testIntRejectsOutOfRangeAndNonNumeric() {
        for raw in ["0", "5", "abc", "3.0", "1x4"] {
            let r = MMHookValue.resolveInt(raw: raw, fallback: 2, bounds: 1...4)
            XCTAssertEqual(r.value, 2, "\(raw) 不该被接受")
            XCTAssertNotNil(r.rejected, "\(raw) 必须留痕")
        }
        XCTAssertNil(MMHookValue.resolveInt(raw: "", fallback: 2, bounds: 1...4).rejected, "空串按未设置")
    }

    func testIntNoteWording() {
        let note = MMHookValue.resolveInt(raw: "9", fallback: 2, bounds: 1...4).note(key: "MM_DISK_DEPTH") ?? ""
        XCTAssertTrue(note.contains("MM_DISK_DEPTH"), note)
        XCTAssertTrue(note.contains("9"), note)
        XCTAssertTrue(note.contains("1~4"), note)
        XCTAssertTrue(note.contains("已回落 2"), note)
    }

    // MARK: - 单 token 开关（`== "hold"` 那一类）

    func testFlagMatchesSingleToken() {
        XCTAssertTrue(MMHookValue.resolveFlag(raw: "hold", token: "hold").on)
        XCTAssertTrue(MMHookValue.resolveFlag(raw: " HOLD ", token: "hold").on)
        XCTAssertFalse(MMHookValue.resolveFlag(raw: nil, token: "hold").on)
        XCTAssertNil(MMHookValue.resolveFlag(raw: nil, token: "hold").rejected)
    }

    func testFlagTypoIsNotSilent() {
        let r = MMHookValue.resolveFlag(raw: "holdon", token: "end")
        XCTAssertFalse(r.on)
        let note = r.note(key: "MM_DEV_SCROLL", token: "end") ?? ""
        XCTAssertTrue(note.contains("MM_DEV_SCROLL"), note)
        XCTAssertTrue(note.contains("holdon"), note)
        XCTAssertTrue(note.contains("只接受 end"), note)
    }

    // MARK: - 读 env 的那条路（视图 @State 用的就是它）

    private func demoSelected(_ env: [String: String], key: String = "MM_OPEN_TAB") -> DemoTab {
        MMHookValue.selected(key: key, env: env, fallback: .cache, cases: cases)
    }

    func testSelectedReadsEnvAndPrefersTheHookValue() {
        XCTAssertEqual(demoSelected(["MM_OPEN_TAB": "dev"]), .dev)
        XCTAssertEqual(demoSelected([:]), .cache)
        XCTAssertEqual(demoSelected(["MM_OPEN_TAB": "folders"]), .folders)
    }

    func testSelectedWritesTheNoteToStderr() throws {
        // 留痕只有落进 stderr 才算数：取证脚本一律从 stderr 收日志，
        // 写去别处（或忘了写）在照片上是完全看不出来的。
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("mm-hook-note-\(UUID().uuidString).log")
        let fd = open(file.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        XCTAssertGreaterThan(fd, 0)
        let saved = dup(2)
        // fd 不早关：提前 close 之后 XCTest 若在同名 fd 上开了别的文件，收尾会误关它。
        defer { dup2(saved, 2); close(saved); close(fd); try? FileManager.default.removeItem(at: file) }
        dup2(fd, 2)
        _ = demoSelected(["MM_OPEN_TAB": "sytem"])
        dup2(saved, 2)
        let written = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        XCTAssertTrue(written.contains("MM_OPEN_TAB 含非法取值（sytem）"), written)
    }
}
