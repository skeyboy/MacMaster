import Foundation
import MMFileScanner
import MMUI

struct CleanerSelectionPlan {
    struct Group: Identifiable {
        let id: String
        let name: String
        let paths: [String]
        let knownSize: UInt64
        let unmeasuredCount: Int

        var sizeSummary: String {
            unmeasuredCount == 0
                ? MMFormat.bytes(knownSize)
                : "已测 \(MMFormat.bytes(knownSize)) · \(unmeasuredCount) 项未测"
        }
    }

    let paths: [String]
    let groups: [Group]
    let knownSize: UInt64
    let unmeasuredCount: Int

    var size: UInt64? { unmeasuredCount == 0 ? knownSize : nil }
    var sizeSummary: String {
        unmeasuredCount == 0
            ? MMFormat.bytes(knownSize)
            : "已测 \(MMFormat.bytes(knownSize)) · \(unmeasuredCount) 项未测"
    }

    init(categories: [CacheCategory], selectedIDs: Set<String>, isExcluded: (String) -> Bool) {
        let selected = categories.enumerated().filter {
            selectedIDs.contains($0.element.id) && $0.element.risk.allowsDeletion
        }
        let candidates = selected.flatMap { index, category in
            category.subItems.filter { $0.isAccessible && !isExcluded($0.path) }
                .map { (index: index, category: category, item: $0) }
        }.sorted { lhs, rhs in
            if lhs.item.path.count != rhs.item.path.count { return lhs.item.path.count < rhs.item.path.count }
            if lhs.item.path != rhs.item.path { return lhs.item.path < rhs.item.path }
            return lhs.index < rhs.index
        }

        var roots: [(index: Int, category: CacheCategory, item: CacheSubItem)] = []
        for candidate in candidates {
            guard !roots.contains(where: {
                candidate.item.path == $0.item.path || candidate.item.path.hasPrefix($0.item.path + "/")
            }) else { continue }
            roots.append(candidate)
        }

        paths = roots.map { $0.item.path }
        groups = selected.compactMap { index, category in
            let items = roots.filter { $0.index == index }.map(\.item)
            guard !items.isEmpty else { return nil }
            return Group(id: category.id, name: category.name, paths: items.map(\.path),
                         knownSize: items.reduce(0) { $0 + ($1.size ?? 0) },
                         unmeasuredCount: items.filter { $0.size == nil }.count)
        }
        knownSize = groups.reduce(0) { $0 + $1.knownSize }
        unmeasuredCount = groups.reduce(0) { $0 + $1.unmeasuredCount }
    }
}
