import XCTest
@testable import MMCore

/// 硬保护清单的判据测试。全部是纯字符串判断 + 一个 /tmp 符号链接夹具，
/// 不碰真实用户文件，也不调用 `moveToTrash`（那条路会把东西真扔进废纸篓）。
final class DeletionGuardTests: XCTestCase {

    private var symlinkDirectory: URL!

    override func setUpWithError() throws {
        symlinkDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMDeletionGuard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: symlinkDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: symlinkDirectory)
        super.tearDown()
    }

    private func assertProtected(_ path: String, _ explain: String = "",
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(DeletionGuard.rejection(for: path),
                        "应当挡下：\(path)\(explain.isEmpty ? "" : "（\(explain)）")", file: file, line: line)
    }

    private func assertAllowed(_ path: String, _ explain: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        guard let rejection = DeletionGuard.rejection(for: path) else { return }
        XCTFail("不该挡：\(path)\(explain.isEmpty ? "" : "（\(explain)）")，理由是「\(rejection.reason)」",
                file: file, line: line)
    }

    func testSystemRootsAreProtected() {
        assertProtected("/")
        assertProtected("/System/Library/CoreServices")
        assertProtected("/Library/LaunchDaemons/com.example.helper.plist")
        assertProtected("/usr/local/bin/tool")
        assertProtected("/sbin/init")
        assertProtected("/private/etc/hosts")
        assertProtected("/private/var/db/receipts/com.example.bom")
    }

    /// P21 补的两条根。`/dev` 从来没有别名可剥；`/private` 剥完 `etc`/`var`/`tmp` 之后
    /// 还剩 `tftpboot`、`wireless` 这一类，磁盘页早就把它们对外说成"系统树"，闸门这边此前反而没有。
    func testDevAndRemainingPrivateTreeAreProtected() {
        assertProtected("/dev")
        assertProtected("/dev/null")
        assertProtected("/dev/disk0s1")
        assertProtected("/DEV/random", "大小写变体")
        assertProtected("/private")
        assertProtected("/private/tftpboot")
        assertProtected("/private/wireless/x")
        // 归一化把 `..` 也算进来：绕一圈仍然落在 /dev 上。
        assertProtected("/System/../dev/null")
    }

    /// 补根不能顺手把清理功能的靶子挡掉：临时目录在 `/private/var/folders/…` 下，
    /// 归一之后是 `/var/folders/…`，与 `/private` 那条根无关。
    func testTempAndDevToolTargetsStayAllowed() {
        assertAllowed(FileManager.default.temporaryDirectory.path + "mm-guard-sub")
        assertAllowed("/private/var/folders/aa/bb16/C/com.apple.cache_displacement")
        assertAllowed("/opt/homebrew/Cellar/foo/1.0/bin/foo")
    }

    /// 界面那一问（`literalRejection`）少了符号链接那一遍，别的判据必须完全一致，
    /// 否则"标签与闸门同源"这句话只在这一半路径上成立。
    func testLiteralPassAgreesWithFullPassOnPlainPaths() {
        let home = NSHomeDirectory()
        for path in ["/", "/etc/hosts", "/private/var/db/receipts/x", "/dev/null", "/private/tftpboot",
                     "/LibraryFoo/x", home, "\(home)/Documents", "\(home)/Documents/a.txt",
                     "\(home)/.ssh/id_ed25519", "\(home)/Library/Caches/com.example.app", "  "] {
            XCTAssertEqual(DeletionGuard.literalRejection(for: path)?.reason,
                           DeletionGuard.rejection(for: path)?.reason,
                           "两遍口径在 \(path) 上给了不同结论")
        }
    }

    /// APFS 默认大小写不敏感，`/system` 与 `/System` 是同一个 inode。
    /// 区分大小写的前缀匹配等于漏判 —— 这是参考项目的真实回归之一。
    func testCaseVariantsOfSystemRootsAreProtected() {
        assertProtected("/system/Library/Fonts")
        assertProtected("/LIBRARY/Preferences")
        assertProtected("/USR/local/bin/tool")
    }

    /// 按路径组件边界比较，`/Library` 不能顺手把 `/LibraryFoo` 也吞了。
    func testPrefixMatchRespectsPathComponentBoundary() {
        assertAllowed("/LibraryFoo/not-really-system")
        assertAllowed("/SystemVolumeLike/somewhere")
        assertAllowed("/Users/lee/DownloadsX/file.txt")
    }

    /// `/etc`、`/var`、`/tmp` 在盘上是符号链接，同一个目录有两种写法。
    /// 归一化不稳定就等于清单什么时候生效看运气 —— 这一组锁住两种写法。
    func testPrivateAliasesResolveToTheSameRoot() {
        assertProtected("/etc/hosts")
        assertProtected("/private/etc/hosts")
        assertProtected("/var/db/receipts/com.example.bom")
        assertProtected("/private/var/db/receipts/com.example.bom")
        XCTAssertEqual(DeletionGuard.canonicalize("/private/etc/hosts"), "/etc/hosts")
        XCTAssertEqual(DeletionGuard.canonicalize("/private/tmp/x"), "/tmp/x")
        // 只有这三个别名会剥前缀，其他 /private 内容原样保留。
        XCTAssertEqual(DeletionGuard.canonicalize("/private/wireless/x"), "/private/wireless/x")
        XCTAssertEqual(DeletionGuard.canonicalize("/System/./Fonts/../Fonts"), "/System/Fonts")
        XCTAssertEqual(DeletionGuard.canonicalize("/.."), "/")
    }

    /// 凭证与活数据：整棵子树都不碰。
    func testCredentialsAndLiveDataSubtreesAreProtected() {
        let home = NSHomeDirectory()
        assertProtected("\(home)/.ssh/id_ed25519")
        assertProtected("\(home)/.gnupg/secring.gpg")
        assertProtected("\(home)/Library/Keychains/login.keychain-db")
        assertProtected("\(home)/Library/CloudStorage/iCloud Drive/重要文件夹")
        assertProtected("\(home)/Library/Mail/V10/MailData/Envelope Index")
        assertProtected("\(home)/Library/Application Support/MobileSync/Backup/abcdef")
        assertProtected("\(home)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        assertProtected("\(home)/Library/Group Containers/HUAQ24HBR6.dev.orbstack/Data/vms/ubuntu/disk.raw")
    }

    /// 六个用户目录：目录本身挡，内容放行 —— 「用户文件夹清理」页就是逐项勾选这一层
    /// 下面的文件来工作的，子树全挡等于把已上线的功能废掉。
    func testUserDataDirectoriesAreProtectedButTheirContentsAreNot() {
        let home = NSHomeDirectory()
        for relative in ["Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"] {
            assertProtected("\(home)/\(relative)", "\(relative) 目录本身不该被整体移走")
            assertAllowed("\(home)/\(relative)/报告.docx")
        }
        // 大小写不敏感：少按一个 shift 不该绕过"目录本身"这条线。
        assertProtected("\(home)/documents")
        // 尾部斜杠与 `..` 归一之后仍是同一个目录。
        assertProtected("\(home)/Downloads/")
        assertProtected("\(home)/Public/../Downloads")
    }

    /// 沙盒容器缓存这一类别的目标就在 `Data/Library/Caches`，闸门只能挡住 `Data/vms`
    /// 里的镜像文件，不能顺手把容器的正常缓存一起否掉。
    func testContainerCachesStayAllowedWhileVMImagesAreProtected() {
        let home = NSHomeDirectory()
        assertAllowed("\(home)/Library/Containers/com.docker.docker/Data/Library/Caches")
        assertAllowed("\(home)/Library/Containers/com.apple.Safari/Data/Library/Caches")
    }

    /// Docker/OrbStack 未安装时这些路径并不存在，闸门照样按字面判 —— 保护不能依赖
    /// "这台机器上恰好有这个东西"。
    func testProtectedSubtreeMatchesEvenWhenNothingIsInstalled() {
        assertProtected("\(NSHomeDirectory())/Library/Application Support/CallHistoryDB/CallHistory.storekit")
    }

    /// 清理模块的主战场必须一路放行，否则硬保护会把功能本身废掉。
    func testLegitimateCleanupTargetsStayAllowed() {
        let home = NSHomeDirectory()
        assertAllowed("\(home)/Library/Caches/com.example.app")
        assertAllowed("\(home)/Library/Application Support/com.example.app/Cache")
        assertAllowed("\(home)/Library/Developer/CoreSimulator/Caches")
        assertAllowed("\(home)/.npm/_cacache")
        assertAllowed("\(home)/Downloads/../Library/Caches/com.example.app")
        assertAllowed("/Applications/Example.app")
        assertAllowed("/tmp/mmtrash/Foo.app")
    }

    func testTrashDirectoryItselfIsProtectedButNotItsContents() {
        let home = NSHomeDirectory()
        assertProtected("\(home)/.Trash")
        assertAllowed("\(home)/.Trash/Foo.app")
    }

    func testEmptyPathIsRejected() {
        assertProtected("")
        assertProtected("   ")
    }

    /// 主目录里的一个链接指向系统目录：逻辑路径看着无害，物理路径才是真相。
    /// 这一条同时证明"两个口径都过"不是多余的。
    func testSymlinkIntoSystemRootIsProtected() throws {
        let link = symlinkDirectory.appendingPathComponent("looks-harmless")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System/Library/Fonts"))
        assertProtected(link.path)
    }

    /// 链接指向 home 里的用户数据，同样要挡。
    func testSymlinkIntoUserDataIsProtected() throws {
        let link = symlinkDirectory.appendingPathComponent("cache-thing")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL:
            URL(fileURLWithPath: NSHomeDirectory() + "/Documents"))
        assertProtected(link.path)
    }

    /// 链接目标不存在（断链）时怎么办，取决于 `realpath` 到底会不会返回结果。
    /// 本机实测（`swift Scripts/realpath-probe.swift`）：macOS 的 C `realpath` 要求**全路径都存在**，
    /// 末段缺失直接 ENOENT=2 —— 和 glibc 那套"允许最后一段不存在"不一样。
    /// 所以断链解析不出来，只能退回链接自身的位置判断：它在 /tmp 的临时目录下，放行。
    /// 这不是漏判 —— 把断链移进废纸篓动的是链接这个 inode，目标文件本来就不存在。
    /// 目标存在的链接另有两条测试覆盖（分别指向 `/System` 与 `~/Documents`）。
    func testDanglingSymlinkFallsBackToItsOwnLocation() throws {
        let dangling = symlinkDirectory.appendingPathComponent("etc-link")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL:
            URL(fileURLWithPath: "/private/etc/hosts.deny-removed"))
        assertAllowed(dangling.path)

        // 目标目录整体不存在，同样解析失败、同样按链接位置放行。
        let unreachable = symlinkDirectory.appendingPathComponent("nowhere-link")
        try FileManager.default.createSymbolicLink(at: unreachable, withDestinationURL:
            URL(fileURLWithPath: "/private/definitely-not-here-\(UUID().uuidString)/inner"))
        assertAllowed(unreachable.path)
    }

    func testPhysicalPathResolutionHandlesPrivatePrefix() {
        // /tmp 是 /private/tmp 的别名。解析不出来就说明 physicalPath 是空转。
        XCTAssertEqual(DeletionGuard.physicalPath("/tmp"), "/private/tmp")
        XCTAssertEqual(DeletionGuard.physicalPath("/does-not-exist-at-all"), "/does-not-exist-at-all")
    }
}
