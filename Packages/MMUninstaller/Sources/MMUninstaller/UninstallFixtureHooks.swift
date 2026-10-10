import Foundation
import Darwin

enum UninstallFixtureHooks {
    /// 假 home 的归一化路径：必须是 /tmp（或其合成前缀 /private/tmp）下真实存在的目录。
    /// 归一化不能省：`/tmp` 在 macOS 上是 `/private/tmp` 的符号链接，
    /// 而下游的扫描器拿到的必须是 realpath，否则同一份夹具会被算成两个前缀。
    static func canonicalHome(_ raw: String?) -> String? {
        guard let raw,
              raw.hasPrefix("/tmp/") || raw.hasPrefix("/private/tmp/"),
              let resolved = realpath(raw, nil) else { return nil }
        defer { free(resolved) }
        let home = String(cString: resolved)
        guard home.hasPrefix("/tmp/") || home.hasPrefix("/private/tmp/") else { return nil }
        return home
    }
}
