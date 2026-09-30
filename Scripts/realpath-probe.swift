import Foundation
import Darwin

// 删除闸门的判据依据：macOS 的 C `realpath` 什么时候给得出结果、什么时候 NULL。
// DeletionGuard 的"符号链接要按目标判"依赖这里的答案，跑一遍就能复核：
//   swift Scripts/realpath-probe.swift
// 结论（macOS 27.0 beta / arm64）：realpath 要求全路径每一段都存在，
// 末段缺失或断链一律 NULL(errno=2)，与 glibc 的"容忍最后一段不存在"不同。

func probe(_ label: String, _ path: String) {
    if let resolved = realpath(path, nil) {
        defer { free(resolved) }
        print("\(label.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(String(cString: resolved))")
    } else {
        print("\(label.padding(toLength: 22, withPad: " ", startingAt: 0)) "
              + "-> NULL (errno=\(errno) \(String(cString: strerror(errno))))")
    }
}

let stage = NSTemporaryDirectory() + "mm-realpath-probe-\(UUID().uuidString)"
try? FileManager.default.createDirectory(atPath: stage, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(atPath: stage) }

// 目标存在与目标缺失的两种链接，各造一个。
try? FileManager.default.createSymbolicLink(atPath: stage + "/ok-link",
                                            withDestinationPath: "/private/etc/hosts")
try? FileManager.default.createSymbolicLink(atPath: stage + "/dangling-link",
                                            withDestinationPath: "/private/etc/hosts.deny-removed")

probe("existing dir", "/tmp")
probe("existing file", "/private/etc/hosts")
probe("missing last component", "/private/etc/hosts.deny-removed")
probe("missing parent", "/private/definitely-not-here/inner")
probe("link to existing", stage + "/ok-link")
probe("link to missing", stage + "/dangling-link")

// URL.standardizedFileURL 的归一结果：同一类前缀给两种答案，所以闸门不用它。
func standardized(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }
for path in ["/private/etc/hosts", "/private/var/db/receipts/x", "/private/tmp/x", "/System/./Fonts/../Fonts"] {
    print("standardizedFileURL \(path) -> \(standardized(path))")
}
