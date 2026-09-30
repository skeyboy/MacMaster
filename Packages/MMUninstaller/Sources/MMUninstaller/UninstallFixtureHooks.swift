import Foundation
import Darwin

enum UninstallFixtureHooks {
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
