import XCTest
import MMCore
import MMFileScanner
@testable import MMCleaner

/// 排除名单（白名单）的两条命门：
/// 1. **真的落盘**——重启后还在，而且读回来的是同一批条目与来源；
/// 2. **真的被消费**——扫描与删除两条链路都按它减字节。
///
/// 所有用例只碰 `MMCleaner.ExclusionStoreTests.<uuid>` 这个隔离 suite 和 /tmp 下的假路径，
/// 绝不写真实的 UserDefaults 域，也不碰真实用户文件。
final class CleanerExclusionStoreTests: XCTestCase {
    /// 固定的隔离 suite 名：XCTest 同类用例串行执行，所以整个类共用一份就够，
    /// 既不会写进真实域，也不会每次跑测都在 ~/Library/Preferences 攒一批新 plist。
    private static let suiteName = "MMCleaner.ExclusionStoreTests"

    private var suiteName: String { Self.suiteName }
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        // 撤掉本用例写的持久化域，真实域从头到尾没被登记过。
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - 持久化

    func testEntriesPersistAcrossStoreInstances() throws {
        let store = CleanerExclusionStore(defaults: defaults)
        XCTAssertTrue(store.add(path: "/tmp/mm-excl/a", source: .scannedItem))
        XCTAssertTrue(store.add(path: "/tmp/mm-excl/b", source: .chosenFolder))
        XCTAssertFalse(store.add(path: "/tmp/mm-excl/a", source: .scannedItem), "同一路径不该记两次")
        XCTAssertFalse(store.add(path: "", source: .scannedItem), "空路径不是合法的排除")

        // 「重启」在单测里能证到的最强形态：换一个 store、换一个 UserDefaults 实例，
        // 重新从持久化域把名单读回来。
        let revived = CleanerExclusionStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(Set(revived.paths()), ["/tmp/mm-excl/a", "/tmp/mm-excl/b"])
        XCTAssertEqual(revived.entries().count, 2)
        XCTAssertEqual(revived.entries().first { $0.path == "/tmp/mm-excl/b" }?.source, .chosenFolder)
        XCTAssertEqual(revived.entries().first { $0.path == "/tmp/mm-excl/a" }?.source, .scannedItem)
        let addedAt = try XCTUnwrap(revived.entries().first?.addedAt)
        XCTAssertTrue(abs(addedAt.timeIntervalSinceNow) < 60, "时间戳要真的落盘，来源说明才有意义")
        XCTAssertTrue(revived.contains(path: "/tmp/mm-excl/a"))
    }

    func testPersistedBlobIsDecodableJSONUnderModuleKey() throws {
        let store = CleanerExclusionStore(defaults: defaults)
        store.add(path: "/tmp/mm-excl/keep", source: .migrated)

        // 键名带模块前缀，避免和别的模块撞；解得开才谈得上"重启后还在"。
        XCTAssertEqual(CleanerExclusionStore.storageKey, "mmcleaner.exclusions.v1")
        let data = try XCTUnwrap(defaults.data(forKey: CleanerExclusionStore.storageKey))
        let decoded = try JSONDecoder().decode([CleanerExclusionEntry].self, from: data)
        XCTAssertEqual(decoded.map(\.path), ["/tmp/mm-excl/keep"])
        XCTAssertEqual(decoded.first?.source, .migrated)
        XCTAssertEqual(defaults.integer(forKey: CleanerExclusionStore.schemaKey), 1)
    }

    /// 解不开时可以把名单当成空，但不能把原始字节抹掉：
    /// 那等于用户升级一次就永久丢了自己的白名单。
    func testUndecodablePayloadIsLeftIntact() throws {
        let garbage = Data("not-a-whitelist".utf8)
        defaults.set(garbage, forKey: CleanerExclusionStore.storageKey)

        let store = CleanerExclusionStore(defaults: defaults)
        XCTAssertTrue(store.entries().isEmpty)
        XCTAssertEqual(Data(defaults.data(forKey: CleanerExclusionStore.storageKey) ?? Data()), garbage)
    }

    // MARK: - 匹配口径

    func testExclusionCoversItselfAndDescendantsOnly() {
        XCTAssertTrue(CleanerExclusionStore.matches("/tmp/mm-excl/Google", exclusion: "/tmp/mm-excl/Google"))
        XCTAssertTrue(CleanerExclusionStore.matches("/tmp/mm-excl/Google/Chrome", exclusion: "/tmp/mm-excl/Google"))
        XCTAssertTrue(CleanerExclusionStore.matches("/tmp/mm-excl/Google/Chrome/a.bin", exclusion: "/tmp/mm-excl/Google/"))
        // 只按字面量前缀切的话，Google 会把 GoogleAnalytics 一起挡掉——那是误伤。
        XCTAssertFalse(CleanerExclusionStore.matches("/tmp/mm-excl/GoogleAnalytics", exclusion: "/tmp/mm-excl/Google"))
        XCTAssertFalse(CleanerExclusionStore.matches("/tmp/mm-excl", exclusion: "/tmp/mm-excl/Google"))
    }

    func testContainsFollowsTheSameDescendantRule() {
        let store = CleanerExclusionStore(defaults: defaults)
        store.add(path: "/tmp/mm-excl/Safari", source: .scannedItem)
        XCTAssertTrue(store.contains(path: "/tmp/mm-excl/Safari/History.db-wal"))
        XCTAssertFalse(store.contains(path: "/tmp/mm-excl/SafariPlus"))
    }

    func testRemoveOnlyDropsTheExactPath() {
        let store = CleanerExclusionStore(defaults: defaults)
        store.add(path: "/tmp/mm-excl/a", source: .scannedItem)
        store.add(path: "/tmp/mm-excl/b", source: .chosenFolder)

        XCTAssertTrue(store.remove(path: "/tmp/mm-excl/a"))
        XCTAssertFalse(store.remove(path: "/tmp/mm-excl/a"), "已经没了还报告成功，界面计数会飘")
        XCTAssertEqual(store.paths(), ["/tmp/mm-excl/b"])
        XCTAssertTrue(store.remove(paths: ["/tmp/mm-excl/b", "/tmp/mm-excl/ghost"]))
        XCTAssertTrue(store.paths().isEmpty)
    }

    // MARK: - 扫描/删除链路真的消费

    @MainActor
    func testScanExclusionsMergeStoreAndSettingsPaths() throws {
        let store = CleanerExclusionStore(defaults: defaults)
        store.add(path: "/tmp/mm-excl/from-cleaner-page", source: .scannedItem)

        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        settings.excludedFolderPaths = [
            "/tmp/mm-excl/from-settings-page",
            "/tmp/mm-excl/from-cleaner-page",   // 两边都有的只留一份
        ]

        let model = CleanerModel(exclusionStore: store)
        let merged = model.excludedPathsForScan(settings: settings)
        XCTAssertEqual(merged, [
            "/tmp/mm-excl/from-cleaner-page",
            "/tmp/mm-excl/from-settings-page",
        ], "合并后必须去重且有序，否则每一轮扫描传给缓存器的清单都在抖")
    }

    /// 重启后的模型（新实例）必须立刻带着上次的排除名单去扫描——
    /// 这条就是"排除只是会话内存"那个缺陷的回归测试。
    @MainActor
    func testRelaunchedModelStillHonoursPersistedExclusions() throws {
        let written = CleanerExclusionStore(defaults: defaults)
        written.add(path: "/tmp/mm-excl/persisted", source: .chosenFolder)

        let reopened = CleanerExclusionStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let model = CleanerModel(exclusionStore: reopened)
        XCTAssertEqual(model.excludedEntries.map(\.path), ["/tmp/mm-excl/persisted"])
        XCTAssertTrue(model.excludedPathsForScan(settings: AppSettings(defaults: defaults))
            .contains("/tmp/mm-excl/persisted"))
    }

    @MainActor
    func testExcludingASubItemRemovesItsBytesFromTheReclaimableNumbers() {
        let store = CleanerExclusionStore(defaults: defaults)
        let model = CleanerModel(exclusionStore: store)

        var userCache = CacheCategory(id: "user_cache", name: "用户缓存", subtitle: "~/Library/Caches",
                                      iconName: "internaldrive", risk: .safe, scope: .appCache,
                                      paths: ["~/Library/Caches"])
        userCache.subItems = [
            CacheSubItem(name: "Google", path: "/tmp/mm-excl/Google", size: 400, fileCount: 2),
            CacheSubItem(name: "Other", path: "/tmp/mm-excl/Other", size: 100, fileCount: 1),
        ]
        userCache.scannedSize = 500

        // 只读档：没有任何删除入口，也就一分都不能算进"可释放"。
        var privileged = CacheCategory(id: "privileged_cache", name: "系统缓存", subtitle: "/Library/Caches",
                                       iconName: "lock", risk: .readOnly, scope: .systemCache,
                                       paths: ["/Library/Caches"])
        privileged.subItems = [CacheSubItem(name: "com.apple.x", path: "/tmp/mm-excl/privileged", size: 900, fileCount: 3)]
        privileged.scannedSize = 900

        model.categories = [userCache, privileged]
        model.selectedIDs = [userCache.id]

        XCTAssertEqual(model.measuredTotal, 500)
        XCTAssertEqual(model.readOnlyTotal, 900)
        XCTAssertEqual(model.selectedSize, 500)
        XCTAssertEqual(model.selectedPaths.count, 2)

        model.toggleSelection(privileged)
        XCTAssertFalse(model.selectedIDs.contains(privileged.id), "只读档不能进选择集")
        XCTAssertTrue(model.selectedIDs.contains(userCache.id))

        model.toggleExclusion("/tmp/mm-excl/Google")
        XCTAssertTrue(store.contains(path: "/tmp/mm-excl/Google/Chrome"))
        XCTAssertEqual(model.excludedEntries.count, 1)
        XCTAssertEqual(model.selectedSize, 100, "排除的子项必须真的从待回收字节里掉出去")
        XCTAssertEqual(model.selectedPaths, ["/tmp/mm-excl/Other"])

        model.removeExclusion("/tmp/mm-excl/Google")
        XCTAssertTrue(model.excludedEntries.isEmpty)
        XCTAssertEqual(model.selectedSize, 500)
    }

    /// 明细被删掉之后，排除记录要跟着消失，否则名单里全是点不开的历史路径。
    @MainActor
    func testToggleExclusionFallsBackToAddWhenAbsent() {
        let store = CleanerExclusionStore(defaults: defaults)
        let model = CleanerModel(exclusionStore: store)
        model.toggleExclusion("/tmp/mm-excl/toggle")
        XCTAssertEqual(model.excludedEntries.map(\.source), [.scannedItem])
        model.toggleExclusion("/tmp/mm-excl/toggle")
        XCTAssertTrue(model.excludedEntries.isEmpty)
    }
}
