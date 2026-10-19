//
//  UndoTierTests.swift — 「最近操作」右侧那一格的五档判定（I16）
//
//  立项依据是 P53/P55 的实测：旧实现只问"废纸篓里那个文件还在不在"，然后把"不在"统一
//  说成「废纸篓已清空」。而本体在第二块卷上时落点在那块卷自己的 `.Trashes/<uid>/`，
//  盘一拔同样"不在"，全程却没人倒过垃圾（`docs/verification/p55-undo-badge-criterion/`）。
//  措辞是界面替我们说的一句话，所以每一档都钉在这里——尤其是"不指认成因"那两档：
//  它们的存在就是为了防止我们在没量到的时候猜。
//
//  读这台机器的那两句（`mountedUUIDs` / `volumeUUID(ofPath:)`）只测"能不能取到一个形状"，
//  不测"这台机器有几个卷"——后者明天插一块盘就红。
//

import XCTest
@testable import MMCore

final class UndoTierTests: XCTestCase {

    private func record(_ trashPath: String?, uuid: String?) -> UndoRecordEvidence {
        UndoRecordEvidence(trashPath: trashPath, volumeUUID: uuid)
    }

    /// 现读那一句在单测里换成假函数：这里只关心档位，不关心废纸篓真的能不能读。
    private func tier(isUndone: Bool = false,
                      _ records: [UndoRecordEvidence],
                      readable: [String] = [],
                      mounted: Set<String>?) -> UndoTier {
        UndoTierResolver.tier(isUndone: isUndone,
                              records: records,
                              trashReadable: { readable.contains($0) },
                              mountedVolumeUUIDs: mounted)
    }

    // MARK: - 活着的两档

    func testReadableLandingPointIsRestorable() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: "AAA")],
                            readable: ["/T/1.txt"], mounted: ["AAA", "BBB"]),
                       .restorable)
    }

    func testAlreadyUndoneWinsOverEverythingElse() {
        // 撤回过之后落点当然不在废纸篓了，但那不是"垃圾被倒了"，更不是"盘被取走了"。
        XCTAssertEqual(tier(isUndone: true, [record("/T/1.txt", uuid: "AAA")], mounted: ["AAA"]), .undone)
    }

    /// 多条落点里只要有一条还读得到，撤回就还有意义——按钮不该因为别的项失败而消失。
    func testOneReadableLandingAmongSeveralIsStillRestorable() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: "AAA"), record("/T/2.txt", uuid: "AAA")],
                            readable: ["/T/2.txt"], mounted: ["AAA"]),
                       .restorable)
    }

    // MARK: - 读不到落点时的三种答案

    func testVolumeStillMountedMeansTrashWasEmptied() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: "AAA")], mounted: ["AAA", "BBB"]), .trashEmptied)
    }

    func testLandingVolumeAbsentFromMountedSetMeansDiskRemoved() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: "CCC")], mounted: ["AAA", "BBB"]), .volumeDetached)
    }

    /// 混合记录：一条的卷还挂着、一条的卷不在了。取"更近的事实"——盘被取走，
    /// 因为那句解释了为什么这一行现在撤不回来；挂着那条的落点没被读到才是次要信息。
    func testMixedRecordsReportDetachmentWhenAnyVolumeIsGone() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: "AAA"), record("/T/2.txt", uuid: "CCC")],
                            mounted: ["AAA"]),
                       .volumeDetached)
    }

    // MARK: - 不指认成因的两档（本轮改动存在的理由）

    /// **nil ≠ 空集**：挂载表没量到时，"落点读不到"什么都解释不了。
    /// 代入空集等于指着每一条记录说"那块盘被取走了"，而我们其实只是没读到挂载表。
    func testMissingMountTableFallsBackToUnknownNotDetached() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: "CCC")], mounted: nil), .unknown)
    }

    /// 反面对照：同一份证据，量到了挂载表就敢报「盘已取下」。
    /// 这两条放在一起才构成"空集与 nil 必须分家"的合同（`DashboardModel` 把空集换成 nil）。
    func testEmptyMountSetDoesClaimDetachmentWhichIsWhyNilIsUsed() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: "CCC")], mounted: []), .volumeDetached)
    }

    /// 老台账（新增字段之前落盘的）没有卷身份：谁也不知道落点在哪块卷上，只能说不撤回。
    func testRecordWithoutVolumeIdentityNeverGuesses() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: nil)], mounted: ["AAA"]), .unknown)
    }

    /// 混合：一条有身份（卷还挂着）、一条没身份。有身份那条只能说"垃圾倒了"，
    /// 没身份那条却连成因都没有——整行退回不指认。宁可少说一句，不要多猜一句。
    func testPartialIdentitySetFallsBackToUnknown() {
        XCTAssertEqual(tier([record("/T/1.txt", uuid: "AAA"), record("/T/2.txt", uuid: nil)],
                            mounted: ["AAA"]),
                       .unknown)
    }

    func testRecordWithoutLandingPointIsUnknown() {
        // 永久删除那一类记录本来就没有落点，撤回无从谈起，也不该说"废纸篓被清空了"。
        XCTAssertEqual(tier([record(nil, uuid: nil)], mounted: ["AAA"]), .unknown)
        XCTAssertEqual(tier([], mounted: ["AAA"]), .unknown)
    }

    // MARK: - 台账向后兼容

    /// 一份**新增字段之前**落盘的 trash-history.json（外层 `{"version":1,"operation":{…}}`
    /// 是 `TrashHistoryStore` 的封装形状；`timestamp` 在默认策略下是 Double，不是 ISO8601）。
    /// 缺 `trashVolumeUUID` 要解码成 nil、档位随之落 `unknown`，历史记录一条都不许丢——
    /// 这一条红了，后果是升级把用户的撤回历史读没了。
    func testLegacyLedgerFileStillLoadsAndNeverGuesses() throws {
        let legacy = """
        [{"version":1,"operation":
          {"id":"\(UUID().uuidString)","timestamp":0,
           "files":[{"originalPath":"/tmp/a.txt","trashPath":"/tmp/.Trashes/501/a.txt","size":12}],
           "failures":[],"isUndone":false}}]
        """
        let operations = try decodeLedger(legacy)
        XCTAssertEqual(operations.count, 1)
        let operation = try XCTUnwrap(operations.first)
        XCTAssertNil(operation.files[0].trashVolumeUUID)
        XCTAssertEqual(operation.undoEvidence,
                       [UndoRecordEvidence(trashPath: "/tmp/.Trashes/501/a.txt", volumeUUID: nil)])
        XCTAssertEqual(operation.tier(mountedVolumeUUIDs: ["AAA"], trashReadable: { _ in false }), .unknown)
        XCTAssertEqual(operation.tier(mountedVolumeUUIDs: ["AAA"], trashReadable: { _ in true }), .restorable)
    }

    /// 新增的那个字段必须真的能过一遍落盘：只在内存里活着的身份，重启后就没了，
    /// 而「盘已取下」这一档要的恰恰是"当初那块卷"的记忆。
    func testVolumeIdentitySurvivesTheLedger() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mm-undo-ledger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TrashHistoryStore(url: dir.appendingPathComponent("trash-history.json"))
        let operation = TrashOperation(id: UUID(), timestamp: .now,
                                       files: [TrashRecord(originalPath: "/tmp/a.txt",
                                                           trashPath: "/Volumes/Ext/.Trashes/501/a.txt",
                                                           size: 12,
                                                           trashVolumeUUID: "CCC")],
                                       failures: [])
        store.save([operation])
        let restored = try XCTUnwrap(store.load().first)
        XCTAssertEqual(restored.files[0].trashVolumeUUID, "CCC")
        XCTAssertEqual(restored.tier(mountedVolumeUUIDs: ["AAA"], trashReadable: { _ in false }),
                       .volumeDetached)
    }

    private func decodeLedger(_ json: String) throws -> [TrashOperation] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mm-undo-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("trash-history.json")
        try Data(json.utf8).write(to: url)
        return TrashHistoryStore(url: url).load()
    }

    /// `undoEvidence` 是逐条映射的：呈现层拿到的证据数量必须跟台账一致，
    /// 少了任何一条都可能让"全部有身份"这个判据被错误地满足。
    func testEvidenceCoversEveryFile() {
        let operation = TrashOperation(id: UUID(), timestamp: .now,
                                       files: [TrashRecord(originalPath: "/a", trashPath: "/t/a", size: 1, trashVolumeUUID: "A"),
                                               TrashRecord(originalPath: "/b", trashPath: "/t/b", size: 1, trashVolumeUUID: "B"),
                                               TrashRecord(originalPath: "/c", size: 1)],
                                       failures: [])
        XCTAssertEqual(operation.undoEvidence.count, 3)
        XCTAssertEqual(operation.undoEvidence.map(\.volumeUUID), ["A", "B", nil])
    }

    // MARK: - 取卷身份那两句

    func testVolumeUUIDResolvesTheVolumeThePathSitsOn() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path
        let file = "\(dir)/mm-undo-tier-\(UUID().uuidString)"
        try Data("x".utf8).write(to: URL(fileURLWithPath: file))
        defer { try? FileManager.default.removeItem(atPath: file) }

        guard let fileUUID = VolumeIdentities.volumeUUID(ofPath: file) else {
            return XCTFail("刚写出来的文件读不到卷身份：\(file)")
        }
        XCTAssertEqual(fileUUID, VolumeIdentities.volumeUUID(ofPath: dir),
                       "落点与它所在目录应当同一块卷——判据比的是卷，不是路径")
    }

    /// 这块盘现在挂着——`mountedUUIDs()` 至少要把它自己算进来，
    /// 否则界面上的「盘已取下」会常年为真（那才是真正的假话）。
    func testMountedSetContainsTheVolumeOfTheHomeDirectory() {
        let mounted = VolumeIdentities.mountedUUIDs()
        XCTAssertFalse(mounted.isEmpty, "本机连一块卷都没枚举到，说明这一句的调用方式已经变了")
        if let uuid = VolumeIdentities.volumeUUID(ofPath: NSHomeDirectory()) {
            XCTAssertTrue(mounted.contains(uuid), "家目录所在的卷不在挂载集合里：判据会把每条记录都说成「盘已取下」")
        }
    }

    /// 口径写在 `VolumeIdentities` 的注释里，这里钉住它的实现后果：
    /// 这个 SDK 的 `VolumeEnumerationOptions` 只有 `.skipHiddenVolumes`（现读编译核实，
    /// 见 `Scripts/p35a-volumes-probe.swift` 第 4 条），而 `-nobrowse` 那道滤走的是
    /// `volumeIsBrowsable` 资源键——`/Volumes/Recovery` 这类卷 browsable=假却实实在在挂着（P55 读数）。
    /// 谁将来把这两道滤加进 `mountedUUIDs()`，「盘已取下」就永远抓不到，所以两个都钉住。
    func testEnumerationKeepsHiddenAndNonBrowsableVolumes() {
        let production = VolumeIdentities.mountedUUIDs()
        let skippingHidden = Set((FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey], options: [.skipHiddenVolumes]
        ) ?? []).compactMap { try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString })
        XCTAssertTrue(skippingHidden.isSubset(of: production),
                      "默认档应当至少不比 skipHiddenVolumes 少：\(skippingHidden.subtracting(production))")

        let browsable = Set((FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey, .volumeIsBrowsableKey], options: []
        ) ?? []).filter { (try? $0.resourceValues(forKeys: [.volumeIsBrowsableKey]).volumeIsBrowsable) == true }
            .compactMap { try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString })
        XCTAssertTrue(browsable.isSubset(of: production),
                      "生产口径漏了 browsable 卷：\(browsable.subtracting(production))")
    }
}
