// P55 前置量：拔盘之后「最近操作」那一行要说「盘已取下」，判据拿什么。
//
// 用法在 `Scripts/p55-undo-badge-criterion.sh`（它负责编译、驱动夹具的挂/卸、写归因头）。
// 这一支**全程只读**：不扫目录树、不写、不 mount/diskutil、不 spawn `mount`、不请求任何权限。
//
// 为什么这一族要先量四件事（顺序就是下面打印的顺序）：
// 1. **`volumeUUIDStringKey` 这个成员在不在**。不在就不该写进判据（本仓有过同一条教训：
//    `p35a-volumes-probe.sh` 现读编译核实过 `.includeHiddenVolumes` 这个成员**不存在**，
//    而它恰是那一轮原本打算用的写法）。
// 2. **能不能从落点路径反推卷身份**。拔盘之后 `canUndo` 里那一句 `fileExists(trashPath)`
//    已经是假（`FileTrashService.swift:294-300`，其中 `:298`），那时候再问这个路径
//    "你属于哪块卷"能得到什么——报错、nil、还是残留的旧值？这一条决定判据必须**在删除时就记录**，
//    还是可以在呈现时现问。
// 3. **挂载点目录本身在 detach 之后还在不在**。夹具那支脚本的 usage 写着"保留挂载点空目录"，
//    所以"看那个目录在不在"很可能**不是**判据——目录一直在，只是变成主卷上的一个空目录
//    （`st_dev` 那一格就是量这一句的）。
// 4. **对照档**：主卷的 UUID 一定在枚举里。用户真倒了垃圾时落点在主卷上、卷也挂着，
//    判据这时候必须说"废纸篓已清空"，别把两种成因压成一种。
//
// 判据不在这里落地：本轮只出**稿面与后端配合清单**，`Sources/` 一个字没动
// （`MainWindow.swift:684` 那四个字要改属实现轮，需单独授权）。
import Foundation

@main struct DetachCriterionProbe {

    static func main() {
        let args = CommandLine.arguments
        guard let target = value(args, "--target"), let marker = value(args, "--mountpoint") else {
            FileHandle.standardError.write("用法: probe --target <落点路径> --mountpoint <挂载点目录>\n".data(using: .utf8)!)
            exit(2)
        }

        print("---- ① `volumeUUIDStringKey` 在不在 SDK 里（在才有下面这些读数）----")
        print("成员存在：是（编译期就核实了——编不过就不会有这一行）")
        print("")

        print("---- ② 落点路径能不能自己报出卷身份（这就是台账里 `trashPath` 那一格）----")
        print("fileExists(落点)=\(FileManager.default.fileExists(atPath: target))")
        ask(target, label: "落点路径")
        print("")

        print("---- ③ 挂载点目录本身（detach 之后它还在不在）----")
        print("fileExists(挂载点)=\(FileManager.default.fileExists(atPath: marker))")
        print("挂载点目录内容=\(listing(marker))")
        ask(marker, label: "挂载点目录")
        print("")

        print("---- ④ 现在挂着哪些卷：Foundation 默认档的 path / volumeUUIDString / name ----")
        enumerate()
        print("")

        print("---- ⑤ 对照：主目录所在那卷（用户真倒了垃圾那一档，判据这里该说废纸篓已清空）----")
        let home = NSHomeDirectory()
        print("fileExists(主目录)=\(FileManager.default.fileExists(atPath: home))")
        ask(home, label: "主目录 \(home)")
        print("")

        print("---- ⑥ st_dev 交叉对读（同一条问句：这块存储设备还是不是那块卷）----")
        for (label, path) in [("落点路径", target), ("挂载点目录", marker), ("/", "/"), ("主目录", home)] {
            print("  \(label) \(path)：st_dev=\(statDev(path))")
        }
        print("  注：st_dev 与 UUID 回答的是同一个问题，但设备号在重挂之后不保证还是同一个，"
              + "UUID 才跨挂/卸稳定——所以判据取 UUID，设备号只在这里当交叉验证。")
    }

    // MARK: - 读数

    static func value(_ args: [String], _ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func ask(_ path: String, label: String) {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.volumeUUIDStringKey, .volumeNameKey, .volumeIsRemovableKey]
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else {
            print("  \(label)：resourceValues 直接抛错（读不到任何卷身份）")
            return
        }
        print("  \(label)：uuid=\(v.volumeUUIDString ?? "nil")  name=\(v.volumeName ?? "nil")  removable=\(yn(v.volumeIsRemovable))")
    }

    static func enumerate() {
        let keys: [URLResourceKey] = [.volumeUUIDStringKey, .volumeNameKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        print("  条数=\(urls.count)")
        for url in urls.sorted(by: { $0.path < $1.path }) {
            let v = try? url.resourceValues(forKeys: Set(keys))
            print("    \(url.path)  uuid=\(v?.volumeUUIDString ?? "nil")  name=\(v?.volumeName ?? "nil")  browsable=\(yn(v?.volumeIsBrowsable))")
        }
    }

    static func listing(_ path: String) -> String {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return "读不到" }
        return items.isEmpty ? "空目录" : "\(items.count) 项：\(items.sorted().prefix(6).map { String($0) }.joined(separator: " "))"
    }

    static func statDev(_ path: String) -> String {
        var s = stat()
        guard stat(path, &s) == 0 else { return "读不到（路径不存在）" }
        return String(s.st_dev)
    }

    static func yn(_ b: Bool?) -> String { b.map { $0 ? "真" : "假" } ?? "nil" }
}
