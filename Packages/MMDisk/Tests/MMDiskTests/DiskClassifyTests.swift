import XCTest
import Foundation
import MMUI
@testable import MMDisk

/// 分类与可清理判定是磁盘页上唯一的"颜色/斜纹为什么长这样"的依据，
/// 所以它的误判是要命的：把用户源码标成可清理，就等于在图上撒谎。
final class DiskClassifyTests: XCTestCase {
    private func dir(_ name: String, size: UInt64 = 1_000, children: [DiskTreeNode] = []) -> DiskTreeNode {
        DiskTreeNode(id: name, name: name, path: "/" + name, size: size,
                     isDirectory: true, children: children)
    }
    private func file(_ name: String, size: UInt64 = 1_000) -> DiskTreeNode {
        DiskTreeNode(id: name, name: name, path: "/" + name, size: size,
                     isDirectory: false, children: [])
    }

    private func classified(_ nodes: [DiskTreeNode]) -> [DiskTreeNode] {
        DiskClassify.classify(nodes, inheritedCategory: .other, inheritedReclaim: nil)
    }

    func testCategoryFollowsOwnNameNotParent() {
        let tree = classified([dir("Developer", children: [dir("Xcode"), dir("Caches")])])
        XCTAssertEqual(tree.first?.category, .developer)
        let children = tree.first?.children ?? []
        XCTAssertEqual(children.first { $0.name == "Xcode" }?.category, .developer)
        // 名字自证的优先：开发者目录下的 Caches 仍然归到缓存。
        XCTAssertEqual(children.first { $0.name == "Caches" }?.category, .cache)
    }

    func testUnrecognisedChildInheritsParentCategory() {
        let tree = classified([dir("Developer", children: [dir("XCDeviceArtifacts")])])
        XCTAssertEqual(tree.first?.children.first?.category, .developer)
    }

    func testBuildDirsNeedManifestEvidence() {
        // 没有 Cargo.toml 的 target 只是同名目录，不是构建产物。
        let bare = classified([dir("target"), dir("src")])
        XCTAssertNil(bare.first { $0.name == "target" }?.reclaim)

        let rust = classified([dir("Cargo.toml", size: 10), dir("target"), dir("src")])
        XCTAssertEqual(rust.first { $0.name == "target" }?.reclaim, .buildOutput)

        let js = classified([dir("package.json"), dir("node_modules")])
        XCTAssertEqual(js.first { $0.name == "node_modules" }?.reclaim, .dependency)

        let orphanModules = classified([dir("node_modules")])
        XCTAssertNil(orphanModules.first?.reclaim, "缺 package.json 时不能断定它是依赖目录")

        // DerivedData 的名字本身就是 Xcode 构建目录，不需要清单旁证。
        let xcode = classified([dir("DerivedData")])
        XCTAssertEqual(xcode.first?.reclaim, .buildOutput)
    }

    func testReclaimInheritsDownwardsSoWholeSubtreeIsHatched() {
        let tree = classified([dir("Caches", children: [dir("org.swift.dan", children: [file("db.sqlite")])])])
        let caches = tree.first
        XCTAssertEqual(caches?.reclaim, .cache)
        let inner = caches?.children.first
        XCTAssertEqual(inner?.reclaim, .inherited)
        XCTAssertEqual(inner?.children.first?.reclaim, .inherited)
    }

    func testCategoryColorsAreTheDesignLegendColors() {
        // 图例、方块、列表三处共用一个色源；这里锁住设计稿的取值。
        let expected: [NodeCategory: UInt32] = [
            .developer: 0xAF52DE, .appData: 0x5E5CE6, .media: 0x30B0C7,
            .documents: 0x28CD41, .cache: 0x8E8E93, .log: 0xFF9500, .other: 0xA2845E,
        ]
        for (category, hex) in expected {
            XCTAssertEqual(category.color, TreemapPalette.hex(hex), category.displayName)
        }
    }

    func testRootContextSeedsInheritance() {
        // 直接扫 ~/Library/Caches 和在全盘扫描里看到它，必须长成同一个样子。
        let (category, reclaim) = DiskClassify.context(forPath: "/Users/lee/Library/Caches")
        XCTAssertEqual(category, .cache)
        XCTAssertEqual(reclaim, .cache)
    }

    func testAndroidSDKFamilyIsDeveloperNotOther() {
        // ~/Library/Android 有 19 GB，认不出来就整片渲染成"其他"，图例就废了。
        // sdk/ndk/emulator 这些名字太通用，只能靠 Android 这一层往下传。
        let nodes = ["sdk", "ndk", "emulator", "platforms"].map { dir($0) }
        let classified = DiskClassify.classify(nodes, inheritedCategory: .developer, inheritedReclaim: nil)
        XCTAssertEqual(classified.map(\.category), Array(repeating: NodeCategory.developer, count: 4))
        // SDK 是装好的工具链，不是构建产物，不该带斜纹。
        XCTAssertEqual(classified.map(\.reclaim), Array(repeating: ReclaimReason?.none, count: 4))
    }
}
