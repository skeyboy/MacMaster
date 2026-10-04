//
//  OptimizerFixtureHooks.swift — MM_OPTIMIZER_FIXTURE 统一夹具入口
//
//  还原度审计（fidelity-optimizer）补的缺口：四 tab 内「空/失败/超大列表/PROTECTED 拒绝态」
//  此前都只有 MM_OPEN_TAB 一个入口，无法无头截图核对（§5 #1–7）。
//
//  铁律（照 GuardianFixtureHooks / MonitorFixtureHooks 的口径）：
//  - 钩子只在环境变量存在且取值合法时生效，未设置时生产路径逐字节不变；
//  - 只顶替**展示数据**：不写盘、不 spawn、不读 /tmp；合成条目一眼可辨；
//  - 含非法取值时整个钩子作废并写 stderr——半生效夹具 = 假通过。
//

import Foundation
import MMCore
import MMFileScanner

// MARK: - 档位解析（MM_OPTIMIZER_FIXTURE）

/// 取值逗号分隔，每项 `key[:arg]`。key 决定哪张卡被顶替，arg 决定档位细节。
/// 覆盖 fidelity-optimizer §5 的 #1、#3–#7。#2（扫描中态）**不需要钩子**：
/// 真实 SHA-256 比对本来就慢，启动后 3 秒截图就停在骨架态（`Scripts/p66-optimizer-capture.sh` 第 01 档），
/// 所以这里没有 HOLD 档位——别照着旧注释再补一个。
enum OptimizerFixture {
    struct Result: Sendable {
        let duplicates: DuplicatesTier?
        let browser: BrowserTier?
        let status: StatusTier?
        let devtools: DevToolsTier?
        let caveat: CaveatCounts?
        let protected: Bool
        let rejected: [String]
    }

    /// 「部分文件没能参与判定」横幅的两个计数。它们不是布尔档位而是两个数，
    /// 因为横幅文案本身就是按这两个数拼句子的（只有一类时不出现分号）。
    struct CaveatCounts: Sendable, Equatable {
        var unreadable = 0
        var dataless = 0
    }

    enum DuplicatesTier: Sendable, Equatable {
        case groups(count: Int)
        case empty          // 未扫过：还未开始检测
        case scannedEmpty   // 扫过但没有结果：没有发现内容完全相同的文件
    }

    enum BrowserTier: Sendable, Equatable {
        case rows
        case empty
    }

    enum StatusTier: Sendable, Equatable {
        case allReadOnly
    }

    enum DevToolsTier: Sendable, Equatable {
        case notInstalled
        case unreadable
    }

    static func parse(_ raw: String?) -> Result {
        guard let raw, !raw.isEmpty else {
            return Result(duplicates: nil, browser: nil, status: nil, devtools: nil, caveat: nil,
                          protected: false, rejected: [])
        }
        var duplicates: DuplicatesTier?
        var browser: BrowserTier?
        var status: StatusTier?
        var devtools: DevToolsTier?
        var caveat: CaveatCounts?
        var protected = false
        var rejected: [String] = []

        for token in raw.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if token == "protected" {
                protected = true
            } else if token == "duplicates:empty" {
                duplicates = .empty
            } else if token == "duplicates:scannedEmpty" {
                duplicates = .scannedEmpty
            } else if token.hasPrefix("duplicates:") {
                let arg = String(token.dropFirst("duplicates:".count))
                if let n = Int(arg), n > 0 { duplicates = .groups(count: n) }
                else { rejected.append(token) }
            } else if token.hasPrefix("caveat:") {
                let arg = String(token.dropFirst("caveat:".count))
                // caveat:unreadable:3 / caveat:dataless:2 —— 两类各给一个正整数
                let parts = arg.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2, let n = Int(parts[1]), n > 0 else {
                    rejected.append(token); continue
                }
                if parts[0] == "unreadable" {
                    caveat = CaveatCounts(unreadable: n, dataless: caveat?.dataless ?? 0)
                } else if parts[0] == "dataless" {
                    caveat = CaveatCounts(unreadable: caveat?.unreadable ?? 0, dataless: n)
                } else {
                    rejected.append(token)
                }
            } else if token == "browser:rows" {
                browser = .rows
            } else if token == "browser:empty" {
                browser = .empty
            } else if token.hasPrefix("browser:") {
                rejected.append(token)
            } else if token == "status:allReadOnly" {
                status = .allReadOnly
            } else if token.hasPrefix("status:") {
                rejected.append(token)
            } else if token == "devtools:notInstalled" {
                devtools = .notInstalled
            } else if token == "devtools:unreadable" {
                devtools = .unreadable
            } else if token.hasPrefix("devtools:") {
                rejected.append(token)
            } else {
                rejected.append(token)
            }
        }

        // 计数没有分组可挂就等于给一张"没有结果"的列表配一句"有些文件没参与判定"，
        // 那是自相矛盾的照片。要拍横幅必须和 duplicates:<N> 同给。
        if caveat != nil, duplicates == nil {
            rejected.append("caveat 需要与 duplicates:<N> 同给")
        }

        // 任一项非法 → 整体作废：半真半假的夹具比没有更危险。
        if !rejected.isEmpty {
            return Result(duplicates: nil, browser: nil, status: nil, devtools: nil, caveat: nil,
                          protected: false, rejected: rejected)
        }
        return Result(duplicates: duplicates, browser: browser, status: status,
                      devtools: devtools, caveat: caveat, protected: protected, rejected: [])
    }

    // MARK: 合成数据

    /// 确定重复分组：每组 3 个文件，路径一眼可辨是夹具值（`/tmp/mm-optimizer-fixture/dup-i/copy-j.bin`）。
    /// 走真实 DuplicateGroup 构造器，wastedSpace 由 size × (n-1) 自动算，不手写。
    static func duplicateGroups(count: Int) -> [DuplicateGroup] {
        (0..<count).map { i in
            let files = (0..<3).map { j in
                DuplicateFile(
                    path: URL(fileURLWithPath: "/tmp/mm-optimizer-fixture/dup-\(i)/copy-\(j).bin"),
                    size: UInt64(1_048_576 * (i + 1)),  // 1 MiB、2 MiB…
                    modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(i * 3600 + j * 60))
                )
            }
            return DuplicateGroup(hash: "fixture-hash-\(i)", size: UInt64(1_048_576 * (i + 1)), files: files)
        }
    }

    /// 浏览器缓存合成行：根路径统一挂在 `/tmp/mm-optimizer-fixture/` 下，size 有确定值；
    /// 末位一个 size=nil 走「测量中」。稿上画四台浏览器，夹具只给三行（差异记在文档，不补行）。
    static func browserRows() -> [BrowserCacheRow] {
        [
            BrowserCacheRow(id: "/tmp/mm-optimizer-fixture/Safari", name: "Safari",
                            systemImage: "safari", path: "/tmp/mm-optimizer-fixture/Safari",
                            size: 128_000_000, kind: "网页缓存"),
            BrowserCacheRow(id: "/tmp/mm-optimizer-fixture/Chrome", name: "Chrome",
                            systemImage: "globe", path: "/tmp/mm-optimizer-fixture/Chrome",
                            size: 96_000_000, kind: "网页缓存"),
            BrowserCacheRow(id: "/tmp/mm-optimizer-fixture/Unknown", name: "示例浏览器",
                            systemImage: "globe", path: "/tmp/mm-optimizer-fixture/Unknown",
                            size: nil, kind: "网页缓存"),
        ]
    }

    /// devtools 未安装/读不到两档：复用 DevToolCacheEntry 的 caveat 文案口径，
    /// 标题都带「（夹具值）」、根路径统一在 `/tmp/mm-optimizer-fixture/` 下，与真实六行区分。
    static func devtoolsRows(tier: DevToolsTier) -> [DevToolCacheEntry] {
        switch tier {
        case .notInstalled:
            return [DevToolCacheEntry(
                id: "fixture-go-mod", title: "Go 模块缓存（夹具值）",
                root: "/tmp/mm-optimizer-fixture/go-mod", rootSource: .defaultPath,
                toolInstalled: false, toolName: "go", presence: .absent, bytes: nil,
                ownerCommand: "go clean -modcache",
                why: "夹具值：模拟 go 未安装。",
                caveat: "PATH 里没找到 go：位置是按默认规则算出来的，也没法跑 owner 命令。")]
        case .unreadable:
            return [DevToolCacheEntry(
                id: "fixture-npm", title: "npm 缓存（夹具值）",
                root: "/tmp/mm-optimizer-fixture/npm", rootSource: .defaultPath,
                toolInstalled: true, toolName: "npm", presence: .unreadable(reason: "夹具值：没有读权限"),
                bytes: nil, ownerCommand: "npm cache verify",
                why: "夹具值：模拟目录不可读。",
                caveat: "读不动这个位置，所以大小和状态都不知道；下面不显示数字。")]
        }
    }
}
