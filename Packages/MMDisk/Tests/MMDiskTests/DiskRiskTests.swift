import XCTest
@testable import MMDisk
import MMCore

/// treemap 风险标签的判据。`risk(of:)` 此前是 `DiskAnalyzerView` 的私有方法、
/// 一行测试都没有，于是它和 `DeletionGuard` 各存一份清单、口径漂了没人报警。
/// 这一组锁两件事：**闸门会拒的，标签不许说可以标**；**标签比闸门更保守的那几档照旧**。
final class DiskRiskTests: XCTestCase {

    private func assertReadOnly(_ path: String, _ explain: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(DiskRisk.risk(of: path), .readOnly,
                       "该上只读：\(path)\(explain.isEmpty ? "" : "（\(explain)）")", file: file, line: line)
    }

    private func assertMarkable(_ path: String, _ explain: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(DiskRisk.risk(of: path).allowsDeletion,
                      "不该上只读：\(path)（实得 \(String(describing: DiskRisk.risk(of: path)))）"
                      + "\(explain.isEmpty ? "" : "（\(explain)）")", file: file, line: line)
    }

    /// P21 补的那一段：这些路径以前在界面上都显示成"可标记"，标了之后由闸门在
    /// 最后一刻拒绝 —— 界面给出的是一个做不到的承诺。
    func testGuardRefusedPathsAreNoLongerOfferedAsMarkable() {
        let home = NSHomeDirectory()
        assertReadOnly("/etc/hosts", "清单从前只写 /private/etc")
        assertReadOnly("/var/db/receipts/com.example.bom")
        assertReadOnly("/private/var/db/receipts/com.example.bom")
        assertReadOnly("/system/Library/Fonts", "大小写变体：APFS 上它就是 /System")
        assertReadOnly("/DEV/null")
        assertReadOnly(home, "主目录本身")
        assertReadOnly("\(home)/.ssh/config", "凭证子树")
        assertReadOnly("\(home)/.Trash", "废纸篓目录本身")
        assertReadOnly("\(home)/Library/CloudStorage/iCloud Drive/Foo/Logs",
                       "'Logs' 虽是可再生组件，但整棵 CloudStorage 闸门就拒")
    }

    /// `/dev` 与 `/private` 进闸门清单之后，标签这边自动跟上——不需要再改第二份清单。
    func testNewSystemRootsShowAsReadOnly() {
        assertReadOnly("/dev")
        assertReadOnly("/dev/disk0s1")
        assertReadOnly("/private")
        assertReadOnly("/private/tftpboot")
    }

    /// 标签比闸门严的那几档是**故意**的，不能被"同源"这一步顺手放宽：
    /// 六个用户目录的内容、以及前缀误伤的那种保守。
    func testStricterThanGuardLabelsStay() {
        let home = NSHomeDirectory()
        XCTAssertNil(DeletionGuard.literalRejection(for: "\(home)/Documents/报告.docx"))
        assertReadOnly("\(home)/Documents/报告.docx", "磁盘页不是逐项清理用户文件的地方，那有专门一页")
        XCTAssertNil(DeletionGuard.literalRejection(for: "/LibraryFoo/not-really-system"))
        assertReadOnly("/LibraryFoo/not-really-system", "hasPrefix 的误伤照旧留着")
        assertReadOnly("\(home)/Desktop", "目录本身")
    }

    /// 清理主战场一个都不许多挡：标签与闸门在这一组上给同一个"可以"。
    func testCleanupTargetsStayMarkable() {
        let home = NSHomeDirectory()
        assertMarkable("\(home)/Library/Caches/com.example.app")
        assertMarkable("\(home)/.Trash/Old.app", "废纸篓里的条目本来就是要清掉的")
        assertMarkable("\(home)/Library/Developer/Xcode/DerivedData/Proj-abc")
        assertMarkable("/Applications/Example.app")
        assertMarkable("/tmp/mmtrash/Foo.app")
        assertMarkable("\(home)/.npm/_cacache/content-v2")
    }

    /// 性质测试，也是这一轮真正的"同源"合同：
    /// 只要闸门按字面路径拒绝，标签就必须是不给按钮的那一档；反方向**不要求**（标签允许更保守）。
    func testLabelNeverContradictsTheGuard() {
        let home = NSHomeDirectory()
        let sample = [
            "/", "/etc", "/etc/hosts", "/var/db", "/var/root/.ssh", "/tmp", "/tmp/x/y",
            "/System", "/system", "/Library", "/LibraryFoo/x", "/usr", "/bin", "/sbin",
            "/private", "/private/etc/passwd", "/private/var/folders/aa/bb16/C/com.apple.x",
            "/dev", "/dev/null", "/opt/homebrew/Cellar/foo/1.0/bin/foo",
            home, "\(home)/Documents", "\(home)/Documents/a.txt", "\(home)/Desktop",
            "\(home)/Downloads/x.dmg", "\(home)/.gnupg/private-keys-v1.d/key.key",
            "\(home)/Library/Keychains/login.keychain-db", "\(home)/Library/Mail/V10/MailData",
            "\(home)/Library/Application Support/MobileSync/Backup/abc",
            "\(home)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
            "\(home)/Library/Containers/com.docker.docker/Data/Library/Caches",
        ]
        for path in sample {
            let refusedByGuard = DeletionGuard.literalRejection(for: path) != nil
            let offeredByLabel = DiskRisk.risk(of: path).allowsDeletion
            XCTAssertFalse(refusedByGuard && offeredByLabel,
                           "标签承诺了闸门做不到的事：\(path)", file: #file, line: #line)
        }
    }

    /// 可注入的 home 只影响那两条前缀规则，不该把闸门那一问也带跑。
    func testInjectedHomeDoesNotRelaxTheGuardPass() {
        let fakeHome = "/tmp/mm-fake-home"
        XCTAssertEqual(DiskRisk.risk(of: "\(fakeHome)/Documents", home: fakeHome), .readOnly)
        // 真主目录下的凭证仍然被挡，哪怕传了别的 home 进来。
        assertReadOnly("\(NSHomeDirectory())/.ssh/id_ed25519")
        XCTAssertEqual(DiskRisk.risk(of: "\(fakeHome)/Library/Caches/x", home: fakeHome), .safe)
    }
}
