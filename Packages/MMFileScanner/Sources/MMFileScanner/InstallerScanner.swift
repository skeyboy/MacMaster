import Foundation
import Darwin

// MARK: - 安装包残留查找（路线图 P4.4）
//
// 找的是用户"早晚会想扔"的安装介质：桌面/下载/文稿/公开 四个用户目录（含一层嵌套）下的
// .dmg / .pkg / .mpkg / .xip，外加按内容嗅探出来的"其实是个应用安装包"的 .zip。
// 证据口径来自 Mole bin/installer.sh:41-119，但这里全部用只读嗅探实现：
// 只读文件头/尾的 magic bytes 与 ZIP 中央目录里的条目名，
// 绝不解压、绝不写任何文件、绝不执行被扫描对象。
//
// 测量诚实（本项目第一红线）：
// 1. 每一项判定都带证据档位——verified（内容签名吻合）或 nameOnly（只按扩展名认出，
//    内容没能核实）。读不到、认不出，绝不渲染成"这不是安装包"，也绝不静默丢弃。
// 2. .zip 是唯一的例外：普通 zip 太常见，判断不了就整条不列（宁可漏报，不可错报），
//    只有中央目录里找到明确的安装包条目（顶层 <App>.app/ 或顶层 .pkg/.dmg/.xip 文件）才算。
// 3. 体积测不出来就是 nil，由界面渲染成"测量中"，绝不写 0。

// MARK: - 判定结果

public enum InstallerEvidence: String, Sendable {
    /// 内容签名与安装介质格式吻合（koly / xar! / 中央目录里有 .app/ 等）
    case verified
    /// 只有扩展名对得上，内容没能核实（太小、读不动、或签名不认识的格式变体）
    case nameOnly
}

public struct InstallerFinding: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    /// 介质类别，如 "DMG 磁盘映像"、"应用安装包 ZIP"。
    public let formatLabel: String
    public let evidence: InstallerEvidence
    /// 给人看的证据说明，如 "UDIF 尾签名 koly"、"内含 Demo.app/"。
    public let evidenceDetail: String
    /// nil = 没量到；界面必须显示"测量中"，不许显示 0。
    public let size: UInt64?
    public let modificationDate: Date?
    public let isDirectory: Bool

    public init(
        path: String,
        name: String,
        formatLabel: String,
        evidence: InstallerEvidence,
        evidenceDetail: String,
        size: UInt64?,
        modificationDate: Date?,
        isDirectory: Bool
    ) {
        self.path = path
        self.name = name
        self.formatLabel = formatLabel
        self.evidence = evidence
        self.evidenceDetail = evidenceDetail
        self.size = size
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }
}

public struct InstallerScanReport: Sendable {
    public let findings: [InstallerFinding]
    public let scannedRoots: [String]
    /// 存在但读不动（多半是 TCC）的根目录：这一轮没看过它们，不能装作扫过了。
    public let inaccessibleRoots: [String]
    /// 检查过的候选条目数（含按口径未列出的普通 zip），供 UI 说"嗅了 N 个候选"。
    public let inspectedCount: Int
    /// false = 中途取消，结果不完整，UI 不能再把它当"全量结论"。
    public let isComplete: Bool
    public let duration: TimeInterval

    public init(
        findings: [InstallerFinding],
        scannedRoots: [String],
        inaccessibleRoots: [String],
        inspectedCount: Int,
        isComplete: Bool,
        duration: TimeInterval
    ) {
        self.findings = findings
        self.scannedRoots = scannedRoots
        self.inaccessibleRoots = inaccessibleRoots
        self.inspectedCount = inspectedCount
        self.isComplete = isComplete
        self.duration = duration
    }
}

// MARK: - 扫描器

public actor InstallerScanner {
    /// 与 Mole 的 INSTALLER_SCAN_MAX_DEPTH_DEFAULT=2 同口径：根目录 + 一层嵌套。
    static let maxDepth = 2
    /// ZIP 中央目录最多翻这么多条目就收手（Mole 上限 50 条，这里放宽到 3000 仍远小于全量）。
    static let maxZipEntries = 3000
    /// 默认扫描的用户目录（相对家目录）。Mole 清单里去掉系统味重的 Library 子树，
    /// 保留 Desktop/Downloads/Documents/Public 四个最常被"晚点再扔"的位置。
    public static let defaultRelativeRoots = ["Desktop", "Downloads", "Documents", "Public"]

    private let roots: [String]

    /// roots == nil 时使用默认用户目录清单；测试与截图钩子传显式目录。
    public init(roots: [String]? = nil) {
        self.roots = roots ?? Self.defaultRoots(home: NSHomeDirectory())
    }

    public static func defaultRoots(home: String) -> [String] {
        defaultRelativeRoots.map { home + "/" + $0 }
    }

    public func scan(shouldContinue: @escaping @Sendable () -> Bool = { true }) async -> InstallerScanReport {
        let started = Date()
        var findings: [InstallerFinding] = []
        var inaccessible: [String] = []
        var inspected = 0
        var stopped = false

        outer: for root in roots {
            guard shouldContinue() else { stopped = true; break }
            guard FileManager.default.fileExists(atPath: root) else { continue }
            guard FileTreeWalker.canEnumerate(path: root) else {
                inaccessible.append(root)
                continue
            }
            // BFS：根目录深度 0，其普通子目录到 maxDepth-1 为止仍会被枚举。
            var pending: [(path: String, depth: Int)] = [(root, 0)]
            while !pending.isEmpty {
                let (dir, depth) = pending.removeFirst()
                for entry in FileTreeWalker.readEntries(path: dir) {
                    guard shouldContinue() else { stopped = true; break outer }
                    switch await classify(entry: entry) {
                    case .listed(let finding):
                        inspected += 1
                        findings.append(finding)
                    case .candidateNotListed:
                        // 看过、像候选、但按口径不列（判不了的 zip 之类）。计数是为了
                        // UI 能说"嗅了 N 个候选"，而不是让空结果读起来像"这里没查过"。
                        inspected += 1
                    case .irrelevant:
                        if entry.isDirectory, depth + 1 < Self.maxDepth,
                           !Self.isOpaquePackage(entry.name), !entry.name.hasPrefix(".") {
                            pending.append((entry.path, depth + 1))
                        }
                    }
                    if Task.isCancelled { stopped = true; break outer }
                }
            }
        }

        findings.sort {
            if ($0.size ?? 0) != ($1.size ?? 0) { return ($0.size ?? 0) > ($1.size ?? 0) }
            return $0.path < $1.path
        }
        return InstallerScanReport(
            findings: findings,
            scannedRoots: roots.filter { !inaccessible.contains($0) },
            inaccessibleRoots: inaccessible,
            inspectedCount: inspected,
            isComplete: !stopped,
            duration: Date().timeIntervalSince(started)
        )
    }

    // MARK: 分类

    enum Outcome {
        case listed(InstallerFinding)
        /// 扩展形态像安装包，但内容嗅探按口径不列（普通 zip / 无结构的 .pkg 目录）
        case candidateNotListed
        case irrelevant
    }

    private func classify(entry: FileTreeWalker.Entry) async -> Outcome {
        // 符号链接一律跳过：必须是真的普通文件或目录（Mole 同口径，防外链把别处文件带进清单）。
        var info = stat()
        guard Darwin.lstat(entry.path, &info) == 0 else { return .irrelevant }
        let type = info.st_mode & S_IFMT
        guard type == S_IFREG || type == S_IFDIR else { return .irrelevant }

        let ext = (entry.name as NSString).pathExtension.lowercased()
        let fileSize = type == S_IFREG ? UInt64(info.st_size) : nil
        let mtime = FileTreeWalker.modificationDate(ofPath: entry.path)
        let url = URL(fileURLWithPath: entry.path)

        switch ext {
        case "dmg":
            guard type == S_IFREG else { return .irrelevant }
            let verdict = Self.sniffDMG(url: url)
            return .listed(InstallerFinding(
                path: entry.path, name: entry.name, formatLabel: "DMG 磁盘映像",
                evidence: verdict.evidence, evidenceDetail: verdict.detail,
                size: fileSize, modificationDate: mtime, isDirectory: false
            ))
        case "xip":
            guard type == S_IFREG else { return .irrelevant }
            let verdict = Self.sniffSignedXar(url: url, label: "XIP")
            return .listed(InstallerFinding(
                path: entry.path, name: entry.name, formatLabel: "XIP 签名归档",
                evidence: verdict.evidence, evidenceDetail: verdict.detail,
                size: fileSize, modificationDate: mtime, isDirectory: false
            ))
        case "pkg", "mpkg":
            let label = ext == "pkg" ? "PKG 安装包" : "MPKG 安装包组"
            if type == S_IFDIR {
                // 解包形态的 .pkg/.mpkg 目录：必须有包结构。认不出结构的目录不列——
                // 用户随手建的文件夹比损坏的安装包常见得多。
                guard let detail = Self.verifyExpandedPackage(entry.path) else { return .irrelevant }
                // 目录体积当场统计；统计不动就是 nil（界面显示"测量中"），绝不报 0。
                let dirSize: UInt64? = FileTreeWalker.canEnumerate(path: entry.path)
                    ? await FileTreeWalker.stats(path: entry.path).size
                    : nil
                return .listed(InstallerFinding(
                    path: entry.path, name: entry.name, formatLabel: label,
                    evidence: .verified, evidenceDetail: detail,
                    size: dirSize,
                    modificationDate: mtime, isDirectory: true
                ))
            }
            guard type == S_IFREG else { return .irrelevant }
            let verdict = Self.sniffSignedXar(url: url, label: "PKG")
            return .listed(InstallerFinding(
                path: entry.path, name: entry.name, formatLabel: label,
                evidence: verdict.evidence, evidenceDetail: verdict.detail,
                size: fileSize, modificationDate: mtime, isDirectory: false
            ))
        case "zip":
            guard type == S_IFREG else { return .irrelevant }
            // 普通 zip 太多：只有嗅出明确安装包证据才列，判不了就不报，绝不凑数。
            switch Self.sniffInstallerZip(url: url) {
            case .applicationInstaller(let reason):
                return .listed(InstallerFinding(
                    path: entry.path, name: entry.name, formatLabel: "应用安装包 ZIP",
                    evidence: .verified, evidenceDetail: reason,
                    size: fileSize, modificationDate: mtime, isDirectory: false
                ))
            case .plainArchive:
                return .candidateNotListed
            case .undecided:
                return .candidateNotListed
            }
        default:
            return .irrelevant
        }
    }

    /// 不透明包形态的目录绝不进入：Foo.app 里面全是 .pkg/.dmg 资源，
    /// 报出来就是把别人的应用内部文件当成"安装包残留"。
    static func isOpaquePackage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["app", "framework", "bundle", "xcassets", "pkg", "mpkg", "disk",
                "sparsebundle", "backupdb", "keychain", "plugin", "prefpane"].contains(ext)
    }

    // MARK: 内容嗅探（只读 magic bytes，绝不解压、绝不执行）

    struct SniffVerdict: Sendable {
        let evidence: InstallerEvidence
        let detail: String
    }

    enum ZipVerdict: Sendable {
        case applicationInstaller(reason: String)
        case plainArchive
        case undecided
    }

    static let xarMagic: [UInt8] = [0x78, 0x61, 0x72, 0x21]        // "xar!"
    static let zipLocalMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]   // "PK\x03\x04"
    /// Xcode .xip 签名信封的开头魔数（公开格式资料口径；本机没有 .xip 样本实证。
    /// 若某个变体对不上，只会降级为 nameOnly——安全方向的误差，
    /// 不会把非安装包报成安装包，也不会把安装包渲染成"不是安装包"）。
    static let signedXipMagic: [UInt8] = [0xAB, 0xC1, 0xAD, 0xFE]

    /// DMG：UDIF 尾块固定在文件末尾 512 字节，开头 'koly'、headerSize=512（本机 Apple 样本实测吻合）。
    /// 老式"读写映像"的 koly 头在文件开头，两处都认。
    static func sniffDMG(url: URL) -> SniffVerdict {
        if hasKoly(atEndOf: url) || hasKoly(atStartOf: url) {
            return SniffVerdict(evidence: .verified, detail: "UDIF 签名 koly")
        }
        if hasMagic(zipLocalMagic, atStartOf: url) {
            // 假 .dmg（实为 zip）：走 zip 嗅探，认出应用包就以 zip 证据列出，认不出仍是 nameOnly。
            switch sniffInstallerZip(url: url) {
            case .applicationInstaller(let reason):
                return SniffVerdict(evidence: .verified, detail: "扩展名实为 zip：\(reason)")
            case .plainArchive:
                return SniffVerdict(evidence: .nameOnly, detail: "内容是普通 ZIP，未嗅出安装包条目")
            case .undecided:
                return SniffVerdict(evidence: .nameOnly, detail: "内容未能核实，仅按扩展名识别")
            }
        }
        if headBytes(of: url) == nil {
            return SniffVerdict(evidence: .nameOnly, detail: "内容读不动（权限？），仅按扩展名识别")
        }
        return SniffVerdict(evidence: .nameOnly, detail: "未嗅出已知签名，仅按扩展名识别")
    }

    /// PKG / MPKG（文件形态）与 XIP：xar 头 "xar!"；XIP 另有签名信封魔数。
    static func sniffSignedXar(url: URL, label: String) -> SniffVerdict {
        guard let head = headBytes(of: url) else {
            return SniffVerdict(evidence: .nameOnly, detail: "内容读不动（权限？），仅按扩展名识别")
        }
        if matchMagic(head, xarMagic) {
            return SniffVerdict(evidence: .verified, detail: "xar 头签名 xar!")
        }
        if matchMagic(head, signedXipMagic) {
            return SniffVerdict(evidence: .verified, detail: "XIP 签名信封 AB C1 AD FE")
        }
        if matchMagic(head, zipLocalMagic) {
            switch sniffInstallerZip(url: url) {
            case .applicationInstaller(let reason):
                return SniffVerdict(evidence: .verified, detail: "扩展名实为 zip：\(reason)")
            case .plainArchive:
                return SniffVerdict(evidence: .nameOnly, detail: "内容是普通 ZIP，未嗅出安装包条目")
            case .undecided:
                return SniffVerdict(evidence: .nameOnly, detail: "内容未能核实，仅按扩展名识别")
            }
        }
        return SniffVerdict(evidence: .nameOnly, detail: "未嗅出已知签名，仅按扩展名识别")
    }

    /// 解包目录形态的 .pkg/.mpkg：Contents/Info.plist 或 Contents/Archive.bom 才算包结构。
    static func verifyExpandedPackage(_ path: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: path + "/Contents/Info.plist") { return "包结构 Contents/Info.plist" }
        if fm.fileExists(atPath: path + "/Contents/Archive.bom") { return "包结构 Contents/Archive.bom" }
        return nil
    }

    // MARK: ZIP 中央目录嗅探
    //
    // 只解析 EOCD → 中央目录条目名，不解压任何数据：
    //   - 顶层条目 `<Name>.app/...`（含目录条目本身）→ 应用安装包；
    //   - 顶层单个 `.pkg/.mpkg/.dmg/.xip` 文件条目 → 安装介质容器；
    //   - 其余 → 普通归档；结构读到一半坏了 → undecided（两者都不列出）。
    static func sniffInstallerZip(url: URL) -> ZipVerdict {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .undecided }
        defer { try? handle.close() }
        guard let fileSize = Self.fileSize(of: url), fileSize >= 22 else { return .undecided }
        guard matchMagic(headBytes(of: url), zipLocalMagic) else { return .undecided }
        guard let eocd = readEOCD(handle: handle, fileSize: fileSize) else { return .undecided }

        var offset = eocd.centralDirectoryOffset
        let limit = min(eocd.entryCount, UInt64(maxZipEntries))
        var index: UInt64 = 0
        while index < limit {
            index += 1
            guard offset + 46 <= fileSize,
                  let header = read(handle, at: offset, length: 46),
                  matchMagic(header, [0x50, 0x4B, 0x01, 0x02]) else { return .undecided }
            let nameLength = Int(u16(header, 28))
            let extraLength = Int(u16(header, 30))
            let commentLength = Int(u16(header, 32))
            guard nameLength > 0, nameLength <= 1024,
                  let nameData = read(handle, at: offset + 46, length: nameLength) else {
                return .undecided
            }
            let name = String(decoding: nameData, as: UTF8.self)
            if let reason = installerEntryReason(forZipEntry: name) {
                return .applicationInstaller(reason: reason)
            }
            offset += UInt64(46 + nameLength + extraLength + commentLength)
        }
        return .plainArchive
    }

    /// 条目名 → 安装包证据。只认"顶层"：路径首段就是 X.app，或根上单个安装文件。
    static func installerEntryReason(forZipEntry name: String) -> String? {
        let normalized = name.hasPrefix("/") ? String(name.dropFirst()) : name
        let isDirectoryEntry = normalized.hasSuffix("/")
        let body = isDirectoryEntry ? String(normalized.dropLast()) : normalized
        guard !body.isEmpty else { return nil }
        let segments = body.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = segments.first else { return nil }
        let lowered = first.lowercased()
        // 顶层 .app：既认 "Demo.app/Contents/…"，也认目录条目本身 "Demo.app/"。
        if lowered.hasSuffix(".app"), segments.count >= 2 || isDirectoryEntry {
            return "内含 \(String(first))/"
        }
        // 顶层单个安装文件条目（目录条目要再嵌一层才有内容，不在此列）。
        if segments.count == 1, !isDirectoryEntry {
            let ext = (String(first) as NSString).pathExtension.lowercased()
            if ["pkg", "mpkg", "dmg", "xip"].contains(ext) {
                return "内含 \(String(first))"
            }
        }
        return nil
    }

    // MARK: EOCD / ZIP64

    struct EOCDInfo {
        let entryCount: UInt64
        let centralDirectoryOffset: UInt64
    }

    static func readEOCD(handle: FileHandle, fileSize: UInt64) -> EOCDInfo? {
        // EOCD = 22 字节定长 + 至多 65535 字节注释。
        let window = Int(min(fileSize, UInt64(22 + 65_535)))
        let base = fileSize - UInt64(window)
        guard let tail = read(handle, at: base, length: window) else { return nil }
        guard let eocdAt = lastIndex(of: [0x50, 0x4B, 0x05, 0x06], in: tail, recordSize: 22) else { return nil }
        let total16 = u16(tail, eocdAt + 10)
        let size32 = u32LE(tail, eocdAt + 12)
        let offset32 = u32LE(tail, eocdAt + 16)

        if total16 == 0xFFFF || size32 == 0xFFFF_FFFF || offset32 == 0xFFFF_FFFF {
            return readZIP64EOCD(handle: handle, eocdFileOffset: base + UInt64(eocdAt))
        }
        return EOCDInfo(entryCount: UInt64(total16), centralDirectoryOffset: UInt64(offset32))
    }

    static func readZIP64EOCD(handle: FileHandle, eocdFileOffset: UInt64) -> EOCDInfo? {
        // zip64 EOCD locator 紧贴 EOCD 之前，20 字节。
        guard eocdFileOffset >= 20,
              let locator = read(handle, at: eocdFileOffset - 20, length: 20),
              matchMagic(locator, [0x50, 0x4B, 0x06, 0x07]) else { return nil }
        let recordOffset = u64LE(locator, 8)
        guard let record = read(handle, at: recordOffset, length: 56),
              matchMagic(record, [0x50, 0x4B, 0x06, 0x06]) else { return nil }
        return EOCDInfo(entryCount: u64LE(record, 32), centralDirectoryOffset: u64LE(record, 48))
    }

    // MARK: 字节工具（全部定点只读，不整档读入内存）

    static func fileSize(of url: URL) -> UInt64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return values.fileSize.map(UInt64.init)
    }

    static func headBytes(of url: URL) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return read(handle, at: 0, length: 4)
    }

    static func hasMagic(_ magic: [UInt8], atStartOf url: URL) -> Bool {
        matchMagic(headBytes(of: url), magic)
    }

    static func hasKoly(atEndOf url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let size = fileSize(of: url), size >= 512 else { return false }
        guard let trailer = read(handle, at: size - 512, length: 512) else { return false }
        return isKolyTrailer(trailer)
    }

    static func hasKoly(atStartOf url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let block = read(handle, at: 0, length: 512) else { return false }
        return isKolyTrailer(block)
    }

    /// 'koly' + 版本(1...8) + headerSize=512，大端。只认这三项，别的一概不猜。
    static func isKolyTrailer(_ block: [UInt8]) -> Bool {
        guard block.count >= 12 else { return false }
        guard matchMagic(block, [0x6B, 0x6F, 0x6C, 0x79]) else { return false }
        let version = u32BE(block, 4)
        let headerSize = u32BE(block, 8)
        return (1...8).contains(version) && headerSize == 512
    }

    @discardableResult
    private static func seekForRead(_ handle: FileHandle, to offset: UInt64) -> Bool {
        // 抛错（越界等）时让 read 统一返回 nil。
        (try? handle.seek(toOffset: offset)) != nil
    }

    static func read(_ handle: FileHandle, at offset: UInt64, length: Int) -> [UInt8]? {
        guard seekForRead(handle, to: offset) else { return nil }
        guard let data = try? handle.read(upToCount: length), data.count == length else { return nil }
        return [UInt8](data)
    }

    static func matchMagic(_ bytes: [UInt8]?, _ magic: [UInt8]) -> Bool {
        guard let bytes, bytes.count >= magic.count else { return false }
        return Array(bytes.prefix(magic.count)) == magic
    }

    static func u16(_ b: [UInt8], _ at: Int) -> UInt16 {
        UInt16(b[at]) | UInt16(b[at + 1]) << 8
    }

    static func u32LE(_ b: [UInt8], _ at: Int) -> UInt32 {
        UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }

    static func u32BE(_ b: [UInt8], _ at: Int) -> UInt32 {
        UInt32(b[at]) << 24 | UInt32(b[at + 1]) << 16 | UInt32(b[at + 2]) << 8 | UInt32(b[at + 3])
    }

    static func u64LE(_ b: [UInt8], _ at: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 { value |= UInt64(b[at + i]) << (8 * i) }
        return value
    }

    static func lastIndex(of magic: [UInt8], in haystack: [UInt8], recordSize: Int) -> Int? {
        guard haystack.count >= magic.count else { return nil }
        var i = haystack.count - magic.count
        while i >= 0 {
            if Array(haystack[i..<(i + magic.count)]) == magic, (haystack.count - i) >= recordSize {
                return i
            }
            i -= 1
        }
        return nil
    }
}
