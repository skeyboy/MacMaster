#!/usr/bin/xcrun swift
// I16 前置量：`VolumeIdentities.mountedUUIDs()` 那一趟枚举到底要多久。
//
// 这一条决定了挂载集合能不能进 `DashboardModel.sampleOnce()` 的 2 秒循环，
// 还是必须像候选根名单（本机 73 ms）那样挪到后台、只在载入与重新测量时刷。
// 差别对用户可见：放在循环里，拔掉盘之后那一格自己就变成「盘已取下」；
// 放在循环外，它得等用户点一次「重新测量」，中间说的是拔盘之前的成因。
//
// 口径与生产代码逐字相同（`Packages/MMCore/Sources/MMCore/UndoAvailability.swift`
// 的 `VolumeIdentities.mountedUUIDs`）：`options: []`，不吃 `.browsableVolumeOnly`。
// 第一趟含 Foundation 首次调用的一次性开销，看后面几趟。
import Foundation

func uuids() -> Set<String> {
    let urls = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? []
    var result: Set<String> = []
    for url in urls {
        if let uuid = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString {
            result.insert(uuid)
        }
    }
    return result
}

for index in 0..<5 {
    let start = Date()
    let set = uuids()
    print("run \(index): uuids=\(set.count) ms=\(Int(Date().timeIntervalSince(start) * 1000))")
}
