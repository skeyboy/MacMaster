// 量一件事：同一卷上"移入废纸篓"到底回不回收磁盘空间。
//
// 起因是磁盘页的确认面板写着"卷可用 X → Y"，那个 Y 是按被标记体积直接加上去的。
// 如果 trashItem 在同一卷上只是改名挪进 ~/.Trash，字节一个都没走，这行字就是错的。
//
// 取数口径用应用自己在用的那两个 key（MMDisk 的 freeSize 读
// volumeAvailableCapacityForImportantUsage，回退 volumeAvailableCapacity），
// 这样量到的差值就是界面上会显示出来的差值，不是 df 的另一种口径。
//
// 用法：swift Scripts/trash-space-measure.swift [体积MiB，默认 200]
// 只在 $HOME 下一个点开的临时目录里写文件，结束（含出错）都会清掉自己那一支；
// 废纸篓里那条也按 resultingItemURL 精确删除，不碰用户原有的垃圾。
import Foundation

let mebibytes = 1024 * 1024
let sizeMiB = CommandLine.arguments.count > 1 ? (Int(CommandLine.arguments[1]) ?? 200) : 200
let scratch = (NSHomeDirectory() as NSString).appendingPathComponent(".mm-trash-measure")
let filePath = scratch + "/big.bin"

func fail(_ message: String) -> Never {
    print(message)
    try? FileManager.default.removeItem(atPath: scratch)
    exit(1)
}

func snapshot(_ label: String) {
    let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
    ])
    let important = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / Double(mebibytes)
    let plain = Double(values?.volumeAvailableCapacity ?? 0) / Double(mebibytes)
    print("\(label)：important \(String(format: "%.1f", important)) MiB · plain \(String(format: "%.1f", plain)) MiB")
}

try? FileManager.default.removeItem(atPath: scratch)
do {
    try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
} catch {
    fail("准备测试文件失败：\(error)")
}
// 写真实字节而不是稀疏文件：稀疏文件的"标称大小"和实际占用的块数差两个量级，
// 那样量出来的回收量对不上被删文件的体积。
guard FileManager.default.createFile(atPath: filePath,
                                     contents: Data(repeating: 0x41, count: sizeMiB * mebibytes))
else { fail("写入测试文件失败：\(filePath)") }

let url = URL(fileURLWithPath: filePath)
let onDisk = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
    .totalFileAllocatedSize ?? 0
print("写入 \(sizeMiB) MiB，实测占用 \(String(format: "%.1f", Double(onDisk) / Double(mebibytes))) MiB")
snapshot("① 删除前")

var resulting: NSURL?
do {
    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
} catch {
    fail("trashItem 失败：\(error)")
}
snapshot("② trashItem 之后（同一卷）")

guard let movedPath = resulting?.path else {
    fail("trashItem 没给出落点，无法清理自己产生的文件")
}
try? FileManager.default.removeItem(atPath: movedPath)
snapshot("③ 从废纸篓彻底删掉之后")
try? FileManager.default.removeItem(atPath: scratch)

print("落点：\(movedPath)")
print("判读：② 与 ① 的差是噪声，③ 与 ② 的差才是被删文件真正释放的量。")
