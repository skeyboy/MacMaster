import Foundation

// MARK: - 「最近操作」那一行的档位判定（I16）
//
// 旧实现只问一句「废纸篓里那个文件还在不在」，然后把"不在"统一说成「废纸篓已清空」。
// P53 实测到第二条成因：本体在第二块卷上时，`trashItem` 的落点是那块卷自己的
// `.Trashes/<uid>/`，把盘拔掉之后那个路径同样读不到——而全程没人倒过垃圾。
// 所以"读不到"是一个问句、两种（实际三种）答案，措辞必须按答案分派，
// 不然界面就在替我们说一件没发生过的事。
//
// 判据一律是**现读**：卷身份在删除那一刻记进台账（`TrashRecord.trashVolumeUUID`），
// 呈现时拿它对照当前挂载集合。为什么不能到时候再问路径——拔盘之后那个挂载点目录还在，
// 只是变成主卷上的一个空目录，报的是主卷的 UUID（P55 读数：档 B 枚举 15 条变 14 条，
// 挂载点 `fileExists` 仍为真而 UUID 换成了 Macintosh HD 那一条）。

/// 一行「最近操作」右侧那一格的五档。
public enum UndoTier: Equatable, Sendable {
    /// 落点读得到，按钮该在。
    case restorable
    /// 已经撤回过。
    case undone
    /// 落点所在那块卷不在当前挂载集合里：盘被取走了，谁也没倒垃圾。
    case volumeDetached
    /// 卷还挂着，落点却读不到：这一档才轮到「废纸篓已清空」。
    case trashEmptied
    /// 台账里没有卷身份（新增字段之前的老记录），或压根没有落点：不指认成因。
    case unknown
}

/// 判定要看的两条事实：落点路径 + **删除当时**记下的落点卷 UUID。
public struct UndoRecordEvidence: Equatable, Sendable {
    public let trashPath: String?
    public let volumeUUID: String?

    public init(trashPath: String?, volumeUUID: String?) {
        self.trashPath = trashPath
        self.volumeUUID = volumeUUID
    }
}

public enum UndoTierResolver {
    /// 纯函数：不碰 FileManager，所以五档都能在单测里钉住。
    /// - `trashReadable`：呈现那一刻问一次「这个路径还在不在」。
    ///   拔盘与倒垃圾都答"不在"，分开它们靠的是下面那两条，不是这一条。
    /// - `mountedVolumeUUIDs`：当前挂载卷的 UUID 集合（`VolumeIdentities.mountedUUIDs()`）；
    ///   **nil = 这一趟没读到挂载表**，此时"落点读不到"只能进 `unknown`。
    ///   不能图省事代空集：空集等于宣称"每一条的落点卷都不在了"，而我们只是没量到。
    ///   不能拿候选根那一路的 `browsable` 滤过的结果代入：`-nobrowse` 挂上的真卷
    ///   `browsable=假` 却实实在在在挂载集合里（P55 实测）。
    public static func tier(isUndone: Bool,
                            records: [UndoRecordEvidence],
                            trashReadable: (String) -> Bool,
                            mountedVolumeUUIDs: Set<String>?) -> UndoTier {
        guard isUndone == false else { return .undone }

        // 有落点、且落点此刻读得到：撤回凭据是活的。
        let landingPoints = records.compactMap(\.trashPath)
        guard landingPoints.isEmpty == false, landingPoints.contains(where: trashReadable) else {
            return notReadable(records: records, mounted: mountedVolumeUUIDs)
        }
        return .restorable
    }

    /// 落点读不到时的三种答案，按"有没有证据指认成因"排序：
    /// 先认那块卷不在了（有身份、身份不在挂载集合），再认垃圾被倒了（有身份、卷还挂着），
    /// 两者都给不出就只说"撤不回来"——不知道成因就不指认成因。
    private static func notReadable(records: [UndoRecordEvidence],
                                    mounted: Set<String>?) -> UndoTier {
        guard let mounted else { return .unknown }
        let identities = records.filter { $0.trashPath != nil }.map(\.volumeUUID)
        guard identities.isEmpty == false else { return .unknown }
        if identities.contains(where: { $0 != nil && !mounted.contains($0!) }) { return .volumeDetached }
        if identities.allSatisfy({ $0 != nil }) { return .trashEmptied }
        return .unknown
    }
}

/// 卷身份的来源：零权限、零子进程，`URLResourceKey.volumeUUIDStringKey` 一条就够。
public enum VolumeIdentities {
    /// 当前挂载卷的 UUID 集合。
    ///
    /// `options` 传空数组，**不传 `.browsableVolumeOnly`**：那一道滤会把以 `-nobrowse`
    /// 挂上的卷挡掉，而它明明挂着——盘一拔就"读不到落点"却报「废纸篓已清空」正是这一档
    /// 要抓的事，滤掉了就永远抓不到。
    public static func mountedUUIDs() -> Set<String> {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []
        ) ?? []
        var result: Set<String> = []
        for url in urls {
            if let uuid = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString {
                result.insert(uuid)
            }
        }
        return result
    }

    /// 删除那一刻给落点取卷身份。取不到就返回 nil——台账随后落到 `unknown` 档，
    /// 宁可不指认成因，也不猜一个"这块卷"出来。
    public static func volumeUUID(ofPath path: String) -> String? {
        try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
}

extension TrashOperation {
    /// 呈现层用的证据：每条落点路径 + 删除当时记下的卷身份。
    public var undoEvidence: [UndoRecordEvidence] {
        files.map { UndoRecordEvidence(trashPath: $0.trashPath, volumeUUID: $0.trashVolumeUUID) }
    }

    /// 一次文件系统枚举换一行措辞，所以挂载集合由调用方给（见 `MainWindow` 那一行）；
    /// nil = 调用方这一趟没量到挂载表，落点读不到时只说「无法撤回」。
    public func tier(mountedVolumeUUIDs: Set<String>?,
                     trashReadable: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> UndoTier {
        UndoTierResolver.tier(isUndone: isUndone,
                              records: undoEvidence,
                              trashReadable: trashReadable,
                              mountedVolumeUUIDs: mountedVolumeUUIDs)
    }
}
