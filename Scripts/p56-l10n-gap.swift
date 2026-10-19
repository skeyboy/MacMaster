#!/usr/bin/env swift
//
//  p56-l10n-gap.swift — 多语言缺口的现读量尺（P56）
//
//  为什么要脚本而不是手敲 grep：这份数要写进 `docs/analysis/localization-coverage.md`，
//  那份文档会被下一轮引用。手敲的口径（谁剥了注释、Tests 算不算、"·" 算不算汉字）留不下来，
//  隔天再数一遍就是一组对不上的数。BSD grep 的 `[一-鿿]` 走字节序，会把 `·` 也认成汉字
//  （本轮在 MainWindow 现读到 3 行假阳性），所以改用 Unicode 标量区间自己扫。
//
//  口径：
//   1. 只扫 `Sources/` 下的 .swift——测试里断言中文原话是刻意的，不算缺口；
//   2. 逐字符扫，注释（`//` 与 `/* … */`）里的中文不计；
//   3. **缺口行** = 该行有含汉字（U+4E00–U+9FFF）的字符串字面量；
//   4. **已接行** = 该行出现 `L("` / `LF("` / `L(key` / `LF(key`。
//      键名是 ASCII，所以两列天然不重叠：一行里的中文要么是没接的文案，要么已经进了表。
//   5. 已知偏差：三引号跨行字面量按行独立扫描，开头的 `"""` 会被当成一个空串——
//      这一类在本仓的界面文件里几乎没有，量的是"先翻哪一面"的排序，不是对外主张。
//
//  用法：swift Scripts/p56-l10n-gap.swift
//

import Foundation

let surfaces: [(name: String, dir: String)] = [
    ("壳层", "Sources/MacMaster"),
    ("MMUI", "Packages/MMUI/Sources"),
    ("MMCore", "Packages/MMCore/Sources"),
    ("MMCleaner", "Packages/MMCleaner/Sources"),
    ("MMUninstaller", "Packages/MMUninstaller/Sources"),
    ("MMDisk", "Packages/MMDisk/Sources"),
    ("MMMonitor", "Packages/MMMonitor/Sources"),
    ("MMGuardian", "Packages/MMGuardian/Sources"),
    ("MMOptimizer", "Packages/MMOptimizer/Sources"),
    ("MMFileScanner", "Packages/MMFileScanner/Sources"),
]

let root = FileManager.default.currentDirectoryPath
let fm = FileManager.default

func swiftFiles(in dir: String) -> [String] {
    guard let walker = fm.enumerator(atPath: dir) else { return [] }
    return walker.compactMap { item in
        guard let relative = item as? String, relative.hasSuffix(".swift") else { return nil }
        return "\(dir)/\(relative)"
    }.sorted()
}

func isHan(_ scalar: Unicode.Scalar) -> Bool {
    (0x4E00...0x9FFF).contains(scalar.value)
}

/// 一行里有没有含汉字的字符串字面量；顺带回注释状态（块注释可以跨行）。
func scan(line: String, inBlock: inout Bool) -> Bool {
    let chars = Array(line)
    var index = 0
    var foundHan = false
    while index < chars.count {
        if inBlock {
            if chars[index] == "*", index + 1 < chars.count, chars[index + 1] == "/" {
                inBlock = false
                index += 2
                continue
            }
            index += 1
            continue
        }
        let ch = chars[index]
        if ch == "/", index + 1 < chars.count, chars[index + 1] == "/" {
            break                      // 行注释：后面全部不算
        }
        if ch == "/", index + 1 < chars.count, chars[index + 1] == "*" {
            inBlock = true
            index += 2
            continue
        }
        if ch == "\"" {
            var j = index + 1
            var inString = true
            var hanInThisString = false
            while j < chars.count, inString {
                let c = chars[j]
                if c == "\\" { j += 2; continue }
                if c == "\"" { inString = false; break }
                if let v = c.unicodeScalars.first, isHan(v) { hanInThisString = true }
                j += 1
            }
            if hanInThisString { foundHan = true }
            index = inString ? chars.count : j + 1   // 跨行字面量：这一行剩下的都不再判
            continue
        }
        index += 1
    }
    return foundHan
}

func countWired(_ line: String) -> Bool {
    for needle in ["L(\"", "LF(\"", "L(key", "LF(key"] where line.contains(needle) { return true }
    return false
}

print("面             文件   缺口行   已接行")
// `--by-file`：在每个面下面再列逐文件的两列。写文档时要指名道姓地说"哪一面还剩多少"，
// 只有小计的话，"壳层 95 行"会被读成"MainWindow 还没接完"。
let byFile = CommandLine.arguments.contains("--by-file")
var totalFiles = 0, totalGaps = 0, totalWired = 0
for surface in surfaces {
    let files = swiftFiles(in: surface.dir)
    var gaps = 0, wired = 0
    var rows: [(String, Int, Int)] = []
    for path in files {
        var fileGaps = 0, fileWired = 0
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            var inBlock = false
            for line in text.components(separatedBy: "\n") {
                if scan(line: line, inBlock: &inBlock) { fileGaps += 1 }
                // 注释行里出现的 L("…") 只是说明，不是真的接了文案。
                if inBlock == false,
                   line.trimmingCharacters(in: .whitespaces).hasPrefix("//") == false,
                   countWired(line) { fileWired += 1 }
            }
        }
        gaps += fileGaps
        wired += fileWired
        rows.append((path, fileGaps, fileWired))
    }
    print("\(surface.name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(String(files.count).padding(toLength: 6, withPad: " ", startingAt: 0))\(String(gaps).padding(toLength: 8, withPad: " ", startingAt: 0))\(String(wired).padding(toLength: 8, withPad: " ", startingAt: 0))")
    if byFile {
        for row in rows.sorted(by: { $0.1 > $1.1 }) {
            print("    \(String(row.1).padding(toLength: 5, withPad: " ", startingAt: 0))\(String(row.2).padding(toLength: 5, withPad: " ", startingAt: 0))  \(row.0)")
        }
    }
    totalFiles += files.count
    totalGaps += gaps
    totalWired += wired
}
print("合计            \(String(totalFiles).padding(toLength: 6, withPad: " ", startingAt: 0))\(String(totalGaps).padding(toLength: 8, withPad: " ", startingAt: 0))\(String(totalWired).padding(toLength: 8, withPad: " ", startingAt: 0))")
