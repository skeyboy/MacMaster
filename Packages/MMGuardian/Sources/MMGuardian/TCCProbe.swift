//
//  TCCProbe.swift — 真正打开 TCC.db 的一层（P3.2）
//
//  只读铁律：sqlite3_open_v2 只带 SQLITE_OPEN_READONLY；查询是 prepared SELECT；
//  本文件不存在任何写路径，也不 sudo/不提权。打不开就把 errno 与 sqlite 原文
//  原样交给 TCCSourceOutcome.unreadable，由判定层渲染"读不到"档。
//
//  本机实测（两个库都打不开，报错原文见 docs/analysis/guardian-tcc.md 第 1 节）：
//  - 用户级：open 报 ENOENT（目录被系统隐藏，无 FDA 进程连"存在"都断言不了）；
//  - 系统级：open 报 EPERM，sqlite rc=23 "authorization denied"。
//
//  与 DeviceUsageProbe 同理，本文件刻意不被单测覆盖：拿夹具 db 测它只能证明
//  sqlite 能用，证明不了真 TCC 库的可读性——那种测试装上就是假绿。
//  判定/清洗/文案全部在 TCCAuthorization.swift，那边有测试。
//

import Foundation
import AppKit
import SQLite3

/// 探针产物：每个来源的可读性结论 + 读到的原始行。
struct TCCProbeReport: Sendable {
    var outcomes: [TCCSource: TCCSourceOutcome]
    var rows: [TCCTranslation]
}

enum TCCProbe {

    /// 路径默认值即真机位置；测试/夹具可注入替换（虽然本层不假测，接口先立住）。
    static func defaultUserPath() -> String {
        "\(NSHomeDirectory())/Library/Application Support/com.apple.TCC/TCC.db"
    }
    static let defaultSystemPath = "/Library/Application Support/com.apple.TCC/TCC.db"

    static func snapshot(
        userPath: String = TCCProbe.defaultUserPath(),
        systemPath: String = TCCProbe.defaultSystemPath
    ) -> TCCProbeReport {
        var outcomes: [TCCSource: TCCSourceOutcome] = [:]
        var rows: [TCCTranslation] = []
        for (source, path) in [(TCCSource.user, userPath), (.system, systemPath)] {
            let (outcome, sourceRows) = query(path: path, source: source)
            outcomes[source] = outcome
            rows.append(contentsOf: sourceRows)
        }
        return TCCProbeReport(outcomes: outcomes, rows: rows)
    }

    // MARK: - 单库查询

    /// 服务清单与 TCCServiceCatalog.trackedServices 保持一致（那边是单一来源）。
    private static let serviceListSQL = """
        'kTCCServiceMicrophone','kTCCServiceCamera','kTCCServiceScreenCapture',\
        'kTCCServiceAccessibility','kTCCServiceListenEvent'
        """

    private static func query(path: String, source: TCCSource) -> (TCCSourceOutcome, [TCCTranslation]) {
        // 先裸 open 一次：sqlite 的 CANTOPEN 不区分"不存在/被隐藏/被拒"，
        // errno 是第一手原因，必须抓下来进文案（见调研文档 1.2）。
        var posixHint: String?
        let fd = Darwin.open(path, O_RDONLY)
        if fd < 0 {
            let code = errno
            posixHint = "open 被拒：\(String(cString: strerror(code)))（errno \(code)）"
            if code == ENOENT {
                // 无 FDA 进程对 TCC 目录拿到的是 ENOENT（隐藏），不是文件真不存在——
                // 文案不许把系统隐藏谎报成"没有这个库"。
                posixHint = "open 返回 ENOENT（errno 2）——路径不存在或被系统对无「完全磁盘访问」的进程隐藏"
            }
        } else {
            close(fd)
        }

        var db: OpaquePointer?
        // 只读打开：没有 SQLITE_OPEN_CREATE/READWRITE，物理上写不了这个库。
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, db != nil else {
            let sqliteText = sqliteErrorText(db)
            sqlite3_close(db)
            // 两段都留：errno 是第一手原因，sqlite 码是它的下游证词（调研文档 1.3）。
            let reason = posixHint.map { "\($0)；\(sqliteText)" } ?? sqliteText
            return (.unreadable(reason: reason), [])
        }
        defer { sqlite3_close(db) }

        // 显式列名 + WHERE IN：schema 漂移时宁可 prepare 失败报"读不到"，
        // 不 SELECT * 拿错位列猜数据（Pearcleaner 同款防御思路）。
        let sql = """
            SELECT service, client, client_type, auth_value, last_modified
            FROM access
            WHERE service IN (\(serviceListSQL))
            ORDER BY service ASC, client ASC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, statement != nil else {
            let text = sqliteErrorText(db)
            sqlite3_finalize(statement)
            return (.unreadable(reason: "查询准备失败（表结构可能随系统版本变化）：\(text)"), [])
        }
        defer { sqlite3_finalize(statement) }

        var rows: [(service: String, client: String, clientType: Int, authValue: Int, lastModified: Date?)] = []
        var stepError: String?
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                rows.append(readRow(statement))
            } else if rc == SQLITE_DONE {
                break
            } else {
                stepError = sqliteErrorText(db)
                break
            }
        }
        if let stepError {
            // 读到一半失败：半截清单比没有清单更危险，整库按读不到处理。
            return (.unreadable(reason: "读取中断：\(stepError)"), [])
        }
        let resolved = rows.map { raw in
            TCCTranslation(service: raw.service, client: raw.client, clientType: raw.clientType,
                           authValue: raw.authValue, lastModified: raw.lastModified,
                           source: source, resolvedAppName: resolveAppName(client: raw.client, clientType: raw.clientType))
        }
        return (.readable(rowCount: resolved.count), resolved)
    }

    private static func readRow(_ statement: OpaquePointer?)
        -> (service: String, client: String, clientType: Int, authValue: Int, lastModified: Date?) {
        let service = columnText(statement, 0) ?? ""
        let client = columnText(statement, 1) ?? ""
        let clientType = Int(sqlite3_column_int(statement, 2))
        let authValue = Int(sqlite3_column_int(statement, 3))
        var lastModified: Date?
        if sqlite3_column_type(statement, 4) != SQLITE_NULL {
            let ts = sqlite3_column_int64(statement, 4)
            if ts > 0 { lastModified = Date(timeIntervalSince1970: TimeInterval(ts)) }
        }
        return (service, client, clientType, authValue, lastModified)
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: ptr)
    }

    private static func sqliteErrorText(_ db: OpaquePointer?) -> String {
        let raw = db.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } } ?? "无错误信息"
        let rc = sqlite3_open_error_code(db)
        return "sqlite3: \(raw)（rc=\(rc)）"
    }

    /// open 失败时 errmsg 可能挂在已失效的句柄上，退到 errstr(常量码)。
    private static func sqlite3_open_error_code(_ db: OpaquePointer?) -> Int32 {
        guard let db else { return SQLITE_CANTOPEN }
        return sqlite3_extended_errcode(db)
    }

    // MARK: - client → 应用名（解析不到返回 nil，由显示层回退原始串）

    private static func resolveAppName(client: String, clientType: Int) -> String? {
        switch clientType {
        case 0:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) else { return nil }
            guard let info = Bundle(url: url)?.infoDictionary else { return nil }
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            return (name?.isEmpty == false) ? name : url.deletingPathExtension().lastPathComponent
        case 1:
            // 路径型 client： bundle 还在就取名字；已经不在了也只用"末段名"，
            // 它仍然是从路径本身来的，不是编的。
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: client, isDirectory: &isDir), isDir.boolValue else { return nil }
            return ((client as NSString).deletingPathExtension as NSString).lastPathComponent
        default:
            return nil
        }
    }
}
