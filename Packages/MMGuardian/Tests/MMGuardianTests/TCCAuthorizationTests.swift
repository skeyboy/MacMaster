//
//  TCCAuthorizationTests.swift — P3.2 判定表 / 视图状态机 / 夹具的纯函数测试
//
//  只打 TCCAuthorization.swift；真正 sqlite3_open_v2 的 TCCProbe.swift 不假测
//  （夹具 db 测它只能证明 sqlite 能用，证明不了真 TCC 库可读性——见
//  docs/analysis/guardian-tcc.md）。全程零文件写入、零系统调用。
//

import XCTest
@testable import MMGuardian

final class TCCAuthorizationTests: XCTestCase {

    private func row(
        _ service: String = "kTCCServiceMicrophone",
        client: String = "com.example.app",
        authValue: Int = 2,
        source: TCCSource = .user,
        name: String? = nil,
        modified: Date? = nil
    ) -> TCCTranslation {
        TCCTranslation(service: service, client: client, clientType: 0,
                       authValue: authValue, lastModified: modified, source: source,
                       resolvedAppName: name)
    }

    // MARK: - auth_value 判定表（法则 1：未知值不猜"允许"）

    func testKnownAuthValuesMapPerSpec() {
        XCTAssertEqual(TCCAuthStatus.from(authValue: 0), .denied)
        XCTAssertEqual(TCCAuthStatus.from(authValue: 2), .allowed)
        XCTAssertEqual(TCCAuthStatus.from(authValue: 3), .limited)
        XCTAssertEqual(TCCAuthStatus.from(authValue: 4), .disabled)
    }

    func testUnknownAuthValuesNeverClaimAllowed() {
        // 1 在旧系统曾是"允许"，但按任务口径不采纳旧表：1 与一切表外值都是未知档。
        for value in [1, 5, 6, 9, -1, 99] {
            let status = TCCAuthStatus.from(authValue: value)
            XCTAssertEqual(status, .unknown(value: value), "auth_value=\(value) 应为未知档")
            let copy = TCCCopyTable.copy(for: status)
            XCTAssertFalse(copy.grantsAccess, "未知值 \(value) 绝不能表达「拿到了权限」")
            XCTAssertTrue(copy.badge.contains("未知"), copy.badge)
            XCTAssertFalse(copy.badge.contains("允许"), "未知值徽章不得含「允许」：\(copy.badge)")
        }
    }

    func testStatusBadgesAreChineseAndDistinct() {
        XCTAssertEqual(TCCCopyTable.copy(for: .allowed).badge, "已允许")
        XCTAssertEqual(TCCCopyTable.copy(for: .limited).badge, "部分允许")
        XCTAssertEqual(TCCCopyTable.copy(for: .denied).badge, "已拒绝")
        XCTAssertEqual(TCCCopyTable.copy(for: .disabled).badge, "已禁用")
        XCTAssertEqual(TCCCopyTable.copy(for: .unknown(value: 7)).badge, "未知值 (7)")
        // 只有 allowed/limited 表达"拿到了权限"。
        XCTAssertTrue(TCCCopyTable.copy(for: .allowed).grantsAccess)
        XCTAssertTrue(TCCCopyTable.copy(for: .limited).grantsAccess)
    }

    // MARK: - 服务名映射（法则 2：解析不到显示原始串）

    func testKnownServicesGetChineseNames() {
        XCTAssertEqual(TCCServiceCatalog.displayName("kTCCServiceMicrophone"), "麦克风")
        XCTAssertEqual(TCCServiceCatalog.displayName("kTCCServiceScreenCapture"), "屏幕录制")
    }

    func testUnknownServiceFallsBackToRawString() {
        XCTAssertEqual(TCCServiceCatalog.displayName("kTCCServiceMystery"), "kTCCServiceMystery")
    }

    func testDisplayRowNameFallsBackToRawClient() {
        // 解析不到应用名 → 原样显示 client 串，不编名字。
        let display = TCCDisplayRow(row(client: "/opt/weird/tool", name: nil))
        XCTAssertEqual(display.appName, "/opt/weird/tool")
        let named = TCCDisplayRow(row(client: "com.example.app", name: "Example App"))
        XCTAssertEqual(named.appName, "Example App")
    }

    // MARK: - 清洗与排序

    func testCleanedRowsDeduplicatesAndSorts() {
        let dup = row(client: "com.example.a", authValue: 2)
        let rows = [
            row("kTCCServiceScreenCapture", client: "com.example.b", authValue: 2),
            dup,
            row(client: "com.example.c", authValue: 0),
            dup, // 同 (source,service,client) 重复行只留一条
        ]
        let cleaned = TCCViewer.cleanedRows(rows)
        XCTAssertEqual(cleaned.count, 3)
        // 服务在前（tracked 顺序：麦克风→摄像头→屏幕录制），同服务内"已允许"排在"已拒绝"前。
        XCTAssertEqual(cleaned.map(\.id), [
            "user|kTCCServiceMicrophone|com.example.a",
            "user|kTCCServiceMicrophone|com.example.c",
            "user|kTCCServiceScreenCapture|com.example.b",
        ])
    }

    func testEmptyClientRowIsDropped() {
        XCTAssertEqual(TCCViewer.cleanedRows([row(client: "")]).count, 0)
    }

    // MARK: - 视图状态机（"读不到"是三档里第一等公民）

    func testBothUnreadableIsUnreadableNotEmptyList() {
        // 核心诚实断言：两库打不开 → .unreadable，绝不落入 emptyRead/loaded([])。
        let state = TCCViewer.build(outcomes: [
            .user: .unreadable(reason: "open 返回 ENOENT（errno 2）"),
            .system: .unreadable(reason: "sqlite rc=23 authorization denied"),
        ], rows: [])
        guard case .unreadable(let detail) = state else {
            return XCTFail("两库都读不到时必须走 unreadable 档，实得 \(state)")
        }
        XCTAssertTrue(detail.contains("ENOENT"), detail)
        XCTAssertTrue(detail.contains("authorization denied"), detail)
        XCTAssertTrue(detail.contains("用户级"), detail)
        XCTAssertTrue(detail.contains("系统级"), detail)
    }

    func testOneUnreadableSourceYieldsPartialEvenWithZeroRows() {
        // 用户级可读 0 行 + 系统级读不到 → 不许说"没有授权记录"，降为 partial。
        let state = TCCViewer.build(outcomes: [
            .user: .readable(rowCount: 0),
            .system: .unreadable(reason: "EPERM"),
        ], rows: [])
        guard case .partial(let rows, let note) = state else {
            return XCTFail("应为 partial 档，实得 \(state)")
        }
        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(note.contains("系统级"), note)
        XCTAssertTrue(note.contains("不完整"), note)
    }

    func testAllReadableWithRowsIsLoaded() {
        let state = TCCViewer.build(outcomes: [
            .user: .readable(rowCount: 2),
            .system: .readable(rowCount: 1),
        ], rows: [
            row(client: "com.example.a", authValue: 2),
            row("kTCCServiceCamera", client: "com.example.b", authValue: 3, source: .system),
            row("kTCCServiceCamera", client: "com.example.c", authValue: 0, source: .user),
        ])
        guard case .loaded(let rows) = state else {
            return XCTFail("全可读且有行应为 loaded，实得 \(state)")
        }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.first?.id, "user|kTCCServiceMicrophone|com.example.a")
    }

    func testAllReadableZeroRowsIsTheOnlyEmptyRead() {
        let state = TCCViewer.build(outcomes: [
            .user: .readable(rowCount: 0),
            .system: .readable(rowCount: 0),
        ], rows: [])
        XCTAssertEqual(state, .emptyRead)
    }

    func testPartialReadableRowsStillFlagUnreadableSource() {
        let state = TCCViewer.build(outcomes: [
            .user: .readable(rowCount: 1),
            .system: .unreadable(reason: "rc=23 authorization denied"),
        ], rows: [row(client: "com.example.a", authValue: 2)])
        guard case .partial(let rows, let note) = state else {
            return XCTFail("应为 partial，实得 \(state)")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(note.contains("系统级"), note)
    }

    func testNoOutcomesIsUnreadableNotEmpty() {
        // 探针什么都没给 = 什么都没测到，与"测到 0 行"是两种承诺。
        let state = TCCViewer.build(outcomes: [:], rows: [])
        guard case .unreadable = state else { return XCTFail("实得 \(state)") }
    }

    // MARK: - 夹具钩子（默认安全）

    func testFixtureAcceptsOnlyWhitelistedTokens() {
        XCTAssertNotNil(TCCFixture.parse("rows").state)
        XCTAssertNotNil(TCCFixture.parse("unreadable").state)
        XCTAssertNotNil(TCCFixture.parse("empty").state)
        XCTAssertEqual(TCCFixture.parse("rows").rejected, [])
    }

    func testFixtureRejectsWholeHookOnBadValue() {
        for bad in ["camera=inuse", "home=/Users/lee", "rows;rm", ""] {
            let r = TCCFixture.parse(bad)
            XCTAssertNil(r.state, "非法值 \(bad) 不该产生任何注入")
            XCTAssertEqual(r.rejected, [bad])
        }
    }

    func testFixtureSampleRowsAreObviouslySynthetic() {
        // 夹具行全部 com.example.* / /opt/example/，与真实数据一眼可分。
        for row in TCCFixture.sampleRows {
            XCTAssertTrue(row.client.contains("example"), row.client)
        }
        // 覆盖每一档状态，截图才验得出渲染。
        let statuses = Set(TCCFixture.sampleDisplayRows.map(\.status))
        XCTAssertEqual(statuses, [.allowed, .limited, .unknown(value: 1), .disabled, .denied])
        // 含一条"解析不到名字"的行，验证原始 client 回退渲染。
        XCTAssertTrue(TCCFixture.sampleDisplayRows.contains { $0.appName == $0.client })
    }
}
