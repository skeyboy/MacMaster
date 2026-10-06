import Foundation

// P21 探针：把磁盘页那一行的「风险标签」和删除闸门的「会不会拒」并排打出来。
//
// 为什么要有这个东西：这一档判定拍不到照片。磁盘页的扫描/选择钩子按红线只认 /tmp
// 下的夹具路径（`MMDisk.swift:171-176`、`:1080-1085`），也就是说没有任何钩子能把
// `/etc/hosts` 或 `~/.ssh/config` 摆到 treemap 的某一行上去拍。没有照片的时候，
// 证据只能是**代码自己算出来的表** —— 所以这个探针不抄任何判断逻辑，
// 它把 `DiskRisk.swift`、`DeletionGuard.swift`、`Risk.swift` 三个真源文件一起编译进来，
// 逐行调那两个真函数（编译命令在同名 `.sh` 里）。
//
//   ./Scripts/p21-disk-risk-probe.sh              # 写到 docs/verification/p21-disk-risk/risk-labels.log
//   ./Scripts/p21-disk-risk-probe.sh --stdout     # 只打到终端，不写证据目录
//
// 表里三列的含义：
//   标签      = `DiskRisk.risk(of:)`，决定界面上给不给"标进回收清单"这个按钮
//   字面闸门   = `DeletionGuard.literalRejection(for:)`，标签同源那一问用的就是它
//   闸门      = `DeletionGuard.rejection(for:)`，真正删除时走的那一遍（多一趟 realpath）
//
// 合同只有两条，都在末行的计数里：
//   1. 标签给了按钮、字面闸门却要拒 → 必须 0 行（界面不许承诺闸门做不到的事）
//   2. 标签给了按钮、完整闸门要拒（而字面那遍看不出）→ 残余缺口 = 符号链接那一类，
//      逐行点名打出来，不假装它是 0。它不致命：被标上的链接进不了删除清单，
//      `DiskRemoval.swift:98` 会先在确认面板里把它列成 `.guarded` 的"被拦下"行 ——
//      用户看到的是面板上的一句拒绝，不是删完之后的一条失败。

/// 在 /tmp 下现场造三条链接：两条目标存在、一条断链。
/// 只有真链接才能把 `realpath` 那一遍跑起来 —— 不然合同 2 那一栏永远是空的，
/// 而那恰好是标签这一路唯一看不见的东西。只删这个函数自己建的那个目录。
private func makeSymlinkFixtures(home: String) -> (directory: String, samples: [(path: String, note: String)]) {
    let dir = "/tmp/mm-p21-risk-probe-links"
    let fm = FileManager.default
    try? fm.removeItem(atPath: dir)
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let targets: [(name: String, to: String, note: String)] = [
        ("into-system", "/System/Library/Fonts", "链接指向系统域：字面那遍看不出，realpath 看得出"),
        ("into-documents", "\(home)/Documents", "链接指向六目录本身"),
        ("dangling", "/private/etc/hosts.does-not-exist-p21", "断链：realpath 解析不出来，只能按链接自身位置判"),
    ]
    var made: [(path: String, note: String)] = []
    for t in targets {
        let link = "\(dir)/\(t.name)"
        do {
            try fm.createSymbolicLink(atPath: link, withDestinationPath: t.to)
            made.append((link, t.note))
        } catch {
            print("⚠ 造不出链接 \(link)：\(error.localizedDescription)（这一档就少一行证据，不编造）")
        }
    }
    return (dir, made)
}

@main struct RiskLabelProbe {

    /// 固定样本 31 条 = `DiskRiskTests.testLabelNeverContradictsTheGuard` 里那一条抽样，
    /// 注释列写"这一条在锁什么"，让日志自己能被读成一份判据表，而不是一堆字符串。
    /// 末尾再拼上现场造的链接样本。
    private static func fixedSamples(home: String) -> [(path: String, note: String)] {
        return [
            ("/", "根目录本身"),
            ("/etc", "别名归一后的系统根"),
            ("/etc/hosts", "标签清单从前只写 /private/etc"),
            ("/var/db", "安装包收据那一层"),
            ("/var/root/.ssh", "另一个用户的凭证"),
            ("/tmp", "清理主战场，必须放行"),
            ("/tmp/x/y", "夹具路径的普通形态"),
            ("/System", "系统域"),
            ("/system", "大小写变体：APFS 上它就是 /System"),
            ("/Library", "系统域"),
            ("/LibraryFoo/x", "组件边界：不该被 /Library 吞掉"),
            ("/usr", "系统域"),
            ("/bin", "系统域"),
            ("/sbin", "系统域"),
            ("/private", "P21 新收的那条"),
            ("/private/etc/passwd", "别名前缀"),
            ("/private/var/folders/aa/bb16/C/com.apple.x", "系统临时目录的真实形态"),
            ("/dev", "P21 新收的那条"),
            ("/dev/null", "以前只靠 DiskRemoval 第一层挡"),
            ("/opt/homebrew/Cellar/foo/1.0/bin/foo", "第三方前缀，不该误挡"),
            (home, "主目录本身"),
            ("\(home)/Documents", "六目录：本身挡"),
            ("\(home)/Documents/报告.docx", "六目录：闸门放行内容，标签仍按子树严"),
            ("\(home)/Desktop", "六目录：本身挡"),
            ("\(home)/Downloads/x.dmg", "闸门放行、标签按子树严"),
            ("\(home)/.gnupg/private-keys-v1.d/key.key", "凭证子树"),
            ("\(home)/Library/Keychains/login.keychain-db", "钥匙串"),
            ("\(home)/Library/Mail/V10/MailData", "不是缓存，是邮件本体"),
            ("\(home)/Library/Application Support/MobileSync/Backup/abc", "设备备份"),
            ("\(home)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", "虚拟磁盘镜像"),
            ("\(home)/Library/Containers/com.docker.docker/Data/Library/Caches", "容器缓存：正常清理目标"),
        ]
    }

    /// 中文按双宽算太麻烦，这一列固定字符数、超出不截断 —— 日志是给人 grep 的。
    private static func cell(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    static func main() {
        let home = NSHomeDirectory()
        let fixtures = makeSymlinkFixtures(home: home)
        defer { try? FileManager.default.removeItem(atPath: fixtures.directory) }
        let samples = fixedSamples(home: home) + fixtures.samples

        print("# 逐路径判定表：每一格都是 DiskRisk.risk(of:) 与 DeletionGuard 两个真函数的返回值")
        print("# home=\(home)")
        print("# 链接夹具目录=\(fixtures.directory)（现场造 \(fixtures.samples.count) 条，跑完即删）")
        print("")
        print(cell("路径", 62) + cell("标签", 10) + cell("字面闸门", 12) + cell("闸门", 10) + "说明 / 理由")
        print(String(repeating: "-", count: 150))

        var contradiction = 0        // 合同 1 的违例
        var realpathOnlyGap = 0      // 合同 2：只有 realpath 那遍才拒
        var refusedByGate = 0

        for sample in samples {
            let path = sample.path
            let risk = DiskRisk.risk(of: path)
            let literal = DeletionGuard.literalRejection(for: path)
            let full = DeletionGuard.rejection(for: path)

            if full != nil { refusedByGate += 1 }
            let offeredByLabel = risk.allowsDeletion
            if offeredByLabel && literal != nil { contradiction += 1 }
            if offeredByLabel && full != nil && literal == nil { realpathOnlyGap += 1 }

            // 理由取闸门那份原文，一个字都不改写 —— 这张表的价值就在于文案也是真的。
            let reason = (literal ?? full)?.reason ?? ""
            print(cell(path, 62) + cell(risk.label, 10)
                  + cell(literal == nil ? "放行" : "拒绝", 12)
                  + cell(full == nil ? "放行" : "拒绝", 10)
                  + "\(sample.note)\(reason.isEmpty ? "" : " ｜闸门原话：\(reason)")")
        }

        print("")
        print("样本 \(samples.count) 条（固定 \(fixedSamples(home: home).count) + 链接 \(fixtures.samples.count)）："
              + "闸门（含解析）拒 \(refusedByGate) 条。")
        print("合同 1（标签给按钮 && 字面闸门拒绝）违例：\(contradiction) 条 —— 必须为 0。")
        print("合同 2（标签给按钮 && 只有 realpath 那遍才拒）残余：\(realpathOnlyGap) 条 —— "
              + "这一类界面上确实还给按钮，但它进不了删除清单：DiskRemoval 先在确认面板里列成"
              + "「被拦下」行（.guarded），删除那一步是第二道。")
        if contradiction != 0 {
            print("❌ 标签承诺了闸门做不到的事")
            exit(1)
        }
        print("✅ 没有一行标签承诺了字面闸门做不到的事")
    }
}
