import SwiftUI
import AppKit
import MMCore

// MARK: - 设计令牌
//
// 全站唯一的颜色、栅格、圆角与行高来源。规则：文字、分隔线、风险色一律取 AppKit 动态
// 语义色，不写死 RGBA——强调色变更、辅助功能高对比度都能自动跟随。
// 唯一的破例是下面三个"面"（卡片底 / 次级底 / 页面底），它们按 tokens.css 的明暗两档钉死，
// 理由写在各自注释里。旧的 ThemeColor 保留只是为了不破坏未迁移的调用点，新代码一律用 MM*。

public enum MMColor {
    public static let accent = Color(nsColor: .controlAccentColor)
    public static let label = Color(nsColor: .labelColor)
    public static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    public static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)

    public static let contentBackground = Color(nsColor: .textBackgroundColor)
    public static let controlBackground = Color(nsColor: .windowBackgroundColor)

    /// 按明暗两档取值的面色。对应 tokens.css 里同名的一对十六进制值。
    private static func surface(lightHex: Int, darkHex: Int) -> Color {
        func gray(_ v: Int) -> NSColor {
            NSColor(srgbRed: CGFloat(v) / 255, green: CGFloat(v) / 255, blue: CGFloat(v) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? gray(darkHex) : gray(lightHex)
        })
    }

    /// 卡片面（`--c-card-bg`：浅 #FFFFFF / 深 #2A2A2A）。
    ///
    /// 为什么不复用语义色：实测量对不上稿。MM_APPEARANCE 钩子逐屏截图（见
    /// docs/analysis/fidelity-light-dark.md）——概览卡片用 windowBackgroundColor 渲染成
    /// #E9E9E9，稿要 #FFFFFF；语义色在命令行/位图里解析还会整体退化成一个值，
    /// 只能靠截图逐点量，所以这里把两档钉死。深色档取的是此前已验收的实测近似值。
    /// 代价：增强对比度模式不自动跟随，需要时在这里补分支。
    public static let cardSurface = surface(lightHex: 0xFF, darkHex: 0x2A)

    /// 次级面（`--c-card-bg-alt`：浅 #F7F7F7 / 深 #232323）：底部操作栏、分组表头、
    /// 详情侧栏、行内 chip。名字刻意不叫 card——上一版它叫 cardBackground，
    /// 于是"卡片该用什么底"被这个名字误导，监控页整页灰卡就是这么来的。
    public static let recessedSurface = surface(lightHex: 0xF7, darkHex: 0x23)

    /// 页面底/凹陷面（`--c-under-page`：浅 #E4E4E4 / 深 #161616）：监控页的指标卡和
    /// 磁盘 Treemap 画布，设计稿里就是沉在内容底之下的一档。
    public static let underPageSurface = surface(lightHex: 0xE4, darkHex: 0x16)

    public static let separator = Color(nsColor: .separatorColor)
    public static let hairline = Color(nsColor: .gridColor)
    public static let fillHover = Color.primary.opacity(0.04)
    public static let fillActive = Color.primary.opacity(0.07)

    /// 风险三档只允许用这三个语义色；橙色不再兼作"进行中/最后扫描"。
    public static let safe = Color(nsColor: .systemGreen)
    public static let caution = Color(nsColor: .systemOrange)
    public static let destructive = Color(nsColor: .systemRed)
    public static let informational = Color(nsColor: .systemBlue)

    public static func soft(_ color: Color, _ alpha: Double = 0.13) -> Color { color.opacity(alpha) }

    /// Treemap / 存储条的分类色。颜色只回答"这是什么数据"，
    /// 是否可回收由斜纹与徽章回答——两个维度不能混用同一套色。
    public static let categoryPalette: [MMCategory: Color] = [
        .developer: Color(red: 0.69, green: 0.32, blue: 0.87),
        .appData: Color(red: 0.37, green: 0.36, blue: 0.90),
        .media: Color(red: 0.19, green: 0.69, blue: 0.78),
        .documents: Color(red: 0.16, green: 0.78, blue: 0.28),
        .cache: Color(red: 0.56, green: 0.56, blue: 0.58),
        .log: Color(red: 1.00, green: 0.58, blue: 0.00),
        .other: Color(red: 0.63, green: 0.51, blue: 0.37),
    ]
}

public enum MMCategory: String, CaseIterable, Sendable {
    case developer, appData, media, documents, cache, log, other

    public var color: Color { MMColor.categoryPalette[self] ?? MMColor.categoryPalette[.other]! }
    public var displayName: String {
        switch self {
        case .developer: "开发者"
        case .appData: "应用数据"
        case .media: "媒体"
        case .documents: "文档"
        case .cache: "缓存"
        case .log: "日志"
        case .other: "其他"
        }
    }
}

/// 4pt 栅格。SwiftUI 里写裸数字是本轮 UI 不一致的根因之一。
public enum MMGap {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum MMRadius {
    public static let control: CGFloat = 6
    public static let badge: CGFloat = 4
    public static let card: CGFloat = 8
    public static let overlay: CGFloat = 10
}

public enum MMMetric {
    public static let rowCompact: CGFloat = 28
    public static let rowRegular: CGFloat = 44
    public static let rowApp: CGFloat = 56
    public static let toolbar: CGFloat = 46
    public static let actionBar: CGFloat = 52
    /// 稿 `--sidebar-w` = 220pt。**这个常量没有代码在读**：真正决定屏幕宽度的是
    /// `MainWindow` 的 `navigationSplitViewColumnWidth(min:)`（首屏取 min，ideal 不参与），
    /// 所以它只是给审计文档一个可对账的出处；改这里不会改到任何东西。
    public static let sidebar: CGFloat = 220
    public static let inspector: CGFloat = 268
    public static let iconSmall: CGFloat = 16
    public static let iconRow: CGFloat = 28
    /// 稿 06 `.urow .ring` 那枚状态圆环，比 `iconRow` 大一档。**取 36 不是稿上的 34**：
    /// `screen.css` 没有 box-sizing reset，`width:34px` 是**内容盒**，加 2px 描边后渲染出来的
    /// 外圈是 38px（实测稿子 PNG 环宽 76px@2x = 38pt）；而 SwiftUI 的 `Circle().stroke` 骑在
    /// 路径中线上、向框外溢一半线宽，所以 38pt 外圈要由 36pt 的 frame 承载。
    public static let iconRing: CGFloat = 36
    public static let iconApp: CGFloat = 32
    /// 设计稿 dial 的直径与迷你柱状图的行高。
    public static let gauge: CGFloat = 46
    public static let sparkline: CGFloat = 26
}

// MARK: - 格式化（全站唯一实现）

public enum MMFormat {
    private static let byte: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        // 必须有 useBytes：否则几百字节的真实体积会被四舍五入成 "0 KB"，
        // 在清理工具里读起来等于"这里没有东西"，而它明明占着空间。
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return f
    }()

    /// 大小未测出时显示"测量中"，绝不显示误导性的 "0 字节"。
    /// 真量到 0 也要说清：ByteCountFormatter 会把它写成 "Zero KB"，
    /// 中文界面里读起来像坏了。
    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return L("format.measuring") }
        guard value >= 1000 else { return LF("format.bytes", String(value)) }
        return byte.string(fromByteCount: Int64(value))
    }

    public static func bytes(_ value: Int64?) -> String {
        guard let value else { return L("format.measuring") }
        guard value >= 1000 else { return LF("format.bytes", String(value)) }
        return byte.string(fromByteCount: value)
    }

    /// 带单位的紧凑值，用于图表轴与菜单栏这类宽度敏感的位置。
    public static func compactBytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(value)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(Int(v)) B" : String(format: "%.1f %@", v, units[i])
    }

    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    public static func count(_ value: Int) -> String { grouping.string(from: NSNumber(value: value)) ?? "\(value)" }

    /// 百分比统一一位小数；0.4% 不能塌成 "0%"。入参是 0~1 的比值。
    public static func percent(_ ratio: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", max(0, ratio) * 100)
    }

    /// 入参已是百分数（如进度条回传的 0~100）时用它，避免和上面那个混淆。
    public static func percentValue(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", max(0, value))
    }

    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    public static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateTime.string(from: date)
    }

    /// `RelativeDateTimeFormatter` 的 locale 在取用时才生效，而这里是个共享的静态实例，
    /// 所以两档各留一个、按当前语言挑：改共享实例的 locale 会跟视图重画抢顺序。
    private static func makeRelative(_ locale: Locale) -> RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = locale
        return f
    }

    private static let relativeChinese = makeRelative(Locale(identifier: "zh_CN"))
    private static let relativeEnglish = makeRelative(Locale(identifier: "en_US"))

    public static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = Date().timeIntervalSince(date)
        // RelativeDateTimeFormatter 会把刚刚发生的事说成"0 秒后"，读起来像 bug。
        if abs(seconds) < 5 { return L("format.justNow") }
        let formatter = Localization.shared.currentLanguage == .english ? relativeEnglish : relativeChinese
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 速率：调用方负责传"每秒"的字节数，这里只管拼箭头与单位。
    public static func rate(_ bytesPerSecond: Double, up: Bool) -> String {
        "\(up ? "↑" : "↓") \(compactBytes(UInt64(max(0, bytesPerSecond))))/s"
    }
}

// MARK: - 风险分级
//
// 枚举本体在 MMCore（扫描器与界面共用同一真源），这里只补表现层属性。

extension MMRisk {
    public var color: Color {
        switch self {
        case .safe: MMColor.safe
        case .caution: MMColor.caution
        case .readOnly: MMColor.secondaryLabel
        }
    }
}

// MARK: - 组件

/// 状态徽章。淡底固定 13% 不透明度，全站只有这一档。
public struct MMBadge: View {
    let text: String
    let tint: Color
    let systemImage: String?

    public init(_ text: String, tint: Color, systemImage: String? = nil) {
        self.text = text
        self.tint = tint
        self.systemImage = systemImage
    }

    public init(risk: MMRisk) {
        self.init(risk.label, tint: risk.color, systemImage: risk == .readOnly ? "lock" : nil)
    }

    public var body: some View {
        HStack(spacing: MMGap.xs) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9))
            }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(MMColor.soft(tint), in: RoundedRectangle(cornerRadius: MMRadius.badge, style: .continuous))
    }
}

/// 页头：标题 + 一行"上次更新"副标题 + 右侧动作。取代此前 7 个页面各写一遍的 header。
public struct MMPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let actions: Actions

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: MMGap.md) {
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(title).font(.title3.weight(.semibold)).lineLimit(1)
                if let subtitle {
                    // 副标题常带完整路径，不限行就会在 46pt 的头部里换行并压到工具行上。
                    // 中间截断：开头认目录，结尾看数字，两头都比路径中段有用。
                    // `.help`：中间截断一定会吃掉点什么（P26 逐屏实拍：九屏里两屏被截，
                    // 见 docs/analysis/header-truncation-audit.md），挂上整句是被吃掉的那一段
                    // 唯一的找回途径。**它是兜底，不是免罪**——该被看见的东西仍要排在头尾。
                    Text(subtitle).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: MMGap.lg)
            actions
        }
        .padding(.horizontal, MMGap.lg)
        .frame(height: MMMetric.toolbar)
        .background(MMColor.contentBackground)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension MMPageHeader where Actions == EmptyView {
    public init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// 底部操作栏：左侧合计，右侧主操作。所有"会改动磁盘"的页面统一收口到这里。
public struct MMActionBar<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing
    let summary: String
    let note: String?

    public init(
        summary: String,
        note: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.summary = summary
        self.note = note
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: MMGap.md) {
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(summary).font(.title3.weight(.semibold)).monospacedDigit()
                if let note { Text(note).font(.caption).foregroundStyle(MMColor.secondaryLabel) }
            }
            leading
            Spacer(minLength: MMGap.lg)
            trailing
        }
        .padding(.horizontal, MMGap.lg)
        .frame(height: MMMetric.actionBar)
        .background(MMColor.recessedSurface)
        .overlay(alignment: .top) { Divider() }
    }
}

extension MMActionBar where Leading == EmptyView {
    public init(
        summary: String,
        note: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(summary: summary, note: note, leading: { EmptyView() }, trailing: trailing)
    }
}

/// 键值行：详情页元数据统一用这个，标签列固定宽、值右对齐可复制。
public struct MMKeyRow: View {
    let key: String
    let value: String
    let monospaced: Bool

    public init(_ key: String, _ value: String, monospaced: Bool = false) {
        self.key = key
        self.value = value.isEmpty ? "—" : value
        self.monospaced = monospaced
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MMGap.md) {
            Text(key).font(.callout).foregroundStyle(MMColor.secondaryLabel)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 统计块：一行四个的数字卡。
public struct MMStatItem: View {
    let title: String
    let value: String

    public init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MMGap.xxs) {
            Text(title).font(.caption).foregroundStyle(MMColor.secondaryLabel)
            Text(value).font(.title3).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, MMGap.sm)
        .padding(.horizontal, MMGap.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.underPageSurface, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous).stroke(MMColor.separator))
    }
}

/// 在访达中显示。此前 8 个页面各写了一遍，统一到这里。
public struct MMRevealButton: View {
    let path: String
    var title: String = "打开所在文件夹"

    public init(path: String, title: String = "打开所在文件夹") {
        self.path = path
        self.title = title
    }

    public var body: some View {
        Button {
            MMReveal.open(path)
        } label: {
            Label(title, systemImage: "folder")
        }
    }
}

public enum MMReveal {
    /// 只读操作：打开所在目录并高亮，不改动任何文件。
    public static func open(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func openDirectory(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}

// MARK: - 状态组件（当前实现里完全缺失的三态）

public struct MMEmptyState: View {
    let systemImage: String
    let title: String
    let detail: String?
    let action: AnyView?

    public init(systemImage: String, title: String, detail: String? = nil, action: AnyView? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.action = action
    }

    public init<A: View>(systemImage: String, title: String, detail: String? = nil, @ViewBuilder action: () -> A) {
        self.init(systemImage: systemImage, title: title, detail: detail, action: AnyView(action()))
    }

    public var body: some View {
        VStack(spacing: MMGap.md) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(MMColor.tertiaryLabel)
                .frame(width: 52, height: 52)
                .background(MMColor.fillActive, in: RoundedRectangle(cornerRadius: MMRadius.overlay, style: .continuous))
            Text(title).font(.headline)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(MMColor.secondaryLabel)
                    .multilineTextAlignment(.center).frame(maxWidth: 340)
            }
            if let action { action }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MMGap.xl)
    }
}

/// 权限被拒时的就地降级条：说明缺什么、缺了少算什么、怎么补。
/// 绝不用启动时连环 NSAlert 表达权限问题。
public struct MMPermissionBanner: View {
    let title: String
    let detail: String
    var settingsPane: MMSettingsPane? = nil

    public init(title: String, detail: String, settingsPane: MMSettingsPane? = nil) {
        self.title = title
        self.detail = detail
        self.settingsPane = settingsPane
    }

    public var body: some View {
        HStack(alignment: .top, spacing: MMGap.sm) {
            Image(systemName: "lock.fill").foregroundStyle(MMColor.caution).padding(.top, 1)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(MMColor.secondaryLabel)
            }
            Spacer(minLength: MMGap.sm)
            if let settingsPane {
                Button("打开系统设置") { MMReveal.openSystemSettings(pane: settingsPane) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.caution, 0.10))
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension MMReveal {
    /// 深链到具体隐私面板，而不是把用户丢进"系统设置"首页。
    /// 参数是 `MMSettingsPane` 而不是 String：scheme 由 `settingsURL` 拼，
    /// 调用方传不进带前缀的整串 URL（那正是清理页横幅死了两轮的写法）。
    public static func openSystemSettings(pane: MMSettingsPane) {
        guard let url = pane.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}

/// 骨架行：扫描中不给假数字。
public struct MMSkeletonRow: View {
    var nameWidth: CGFloat = 120
    var valueWidth: CGFloat = 56

    public init(nameWidth: CGFloat = 120, valueWidth: CGFloat = 56) {
        self.nameWidth = nameWidth
        self.valueWidth = valueWidth
    }

    public var body: some View {
        HStack(spacing: MMGap.sm) {
            RoundedRectangle(cornerRadius: MMRadius.badge)
                .fill(MMColor.fillActive).frame(width: 15, height: 15)
            RoundedRectangle(cornerRadius: 3).fill(MMColor.fillActive)
                .frame(width: nameWidth, height: 10)
            Spacer(minLength: MMGap.sm)
            RoundedRectangle(cornerRadius: 3).fill(MMColor.fillActive)
                .frame(width: valueWidth, height: 10)
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: MMMetric.rowRegular)
    }
}

/// 扫描进度：动作 + 当前路径 + 已处理数 + 估算剩余，一行说完。
public struct MMScanProgress: View {
    let action: String
    let currentPath: String?
    let processedCount: Int
    let estimatedRemaining: TimeInterval?
    /// nil 表示无法确定进度，此时画不确定型进度条而不是假装有百分比。
    let progress: Double?

    public init(
        action: String,
        currentPath: String?,
        processedCount: Int,
        estimatedRemaining: TimeInterval?,
        progress: Double?
    ) {
        self.action = action
        self.currentPath = currentPath
        self.processedCount = processedCount
        self.estimatedRemaining = estimatedRemaining
        self.progress = progress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MMGap.sm) {
            HStack(spacing: MMGap.sm) {
                Text(action).font(.callout)
                Spacer(minLength: MMGap.sm)
                if let estimatedRemaining {
                    Text("剩余约 \(MMFormat.duration(estimatedRemaining))")
                        .font(.caption).foregroundStyle(MMColor.secondaryLabel).monospacedDigit()
                }
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 1)).controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
            HStack(spacing: MMGap.sm) {
                Text("已处理 \(MMFormat.count(processedCount)) 项")
                    .font(.caption).foregroundStyle(MMColor.secondaryLabel).monospacedDigit()
                if let currentPath {
                    Text("·").foregroundStyle(MMColor.tertiaryLabel)
                    Text((currentPath as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
    }
}

/// 操作回执条。统一实现，取代此前 4 处手写 toast。
/// 撤回的长期入口是操作历史，这个 toast 只是事后兜底。
///
/// `onUndo` 可空是因为有些操作**没有撤回**（磁盘页的永久删除）。给这种操作画一个
/// 点下去只会失败的"撤回"按钮，比不写回执更糟。图标/着色同理：不可恢复的事后
/// 通知不该顶着绿色对勾。
public struct MMUndoToast: View {
    let message: String
    let detail: String?
    var onUndo: (() -> Void)? = nil
    var onRevealTrash: (() -> Void)? = nil
    var secondsRemaining: Int? = nil
    var leadingSymbol: String = "checkmark.circle.fill"
    var leadingTint: Color = MMColor.safe

    public init(
        message: String,
        detail: String? = nil,
        secondsRemaining: Int? = nil,
        onUndo: (() -> Void)? = nil,
        onRevealTrash: (() -> Void)? = nil,
        leadingSymbol: String = "checkmark.circle.fill",
        leadingTint: Color = MMColor.safe
    ) {
        self.message = message
        self.detail = detail
        self.secondsRemaining = secondsRemaining
        self.onUndo = onUndo
        self.onRevealTrash = onRevealTrash
        self.leadingSymbol = leadingSymbol
        self.leadingTint = leadingTint
    }

    public var body: some View {
        HStack(spacing: MMGap.sm) {
            Image(systemName: leadingSymbol).foregroundStyle(leadingTint)
            Text(message).font(.callout.weight(.medium))
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: MMGap.md)
            if let onUndo {
                Button("撤回", action: onUndo).buttonStyle(.plain).foregroundStyle(.white)
            }
            if let onRevealTrash {
                Text("|").opacity(0.35)
                Button("打开废纸篓", action: onRevealTrash).buttonStyle(.plain).foregroundStyle(.white)
            }
            if let secondsRemaining {
                Text("\(secondsRemaining)s").font(.caption.monospacedDigit()).opacity(0.5)
            }
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: 460)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous)
            .stroke(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
    }
}

/// 部分失败回执。删除或撤回后有条目没成功，必须逐条列出来：
/// 只报"完成"等于把用户文件的下落不明藏起来，错误码原文保留便于搜索。
///
/// 05-states 规格要求回执带一行「计划 / 成功 / 失败 / 跳过」统计与
/// 「重试失败项 / 复制诊断信息」页脚。调用方若只传 failures（历史调用点），
/// 统计行与页脚自动省略，只渲染逐条失败清单——不破坏既有截图基线。
public struct MMFailurePanel: View {
    let summary: String?
    let failures: [TrashFailure]
    var onDismiss: (() -> Void)?
    var stats: Stats?
    var onRetry: (() -> Void)?
    var onCopyDiagnostics: (() -> Void)?

    /// 计划/成功/失败/跳过四格统计。planned 是"打算删的总数"，succeeded 是"已删数"，
    /// skipped 是"被闸门或风险规则主动放过的数"，failed 与 failures.count 一致。
    public struct Stats: Equatable {
        public let planned: Int
        public let succeeded: Int
        public let skipped: Int

        public init(planned: Int, succeeded: Int, skipped: Int) {
            self.planned = planned
            self.succeeded = succeeded
            self.skipped = skipped
        }
    }

    public init(summary: String? = nil, _ failures: [TrashFailure], onDismiss: (() -> Void)? = nil) {
        self.summary = summary
        self.failures = failures
        self.onDismiss = onDismiss
    }

    public init(
        summary: String? = nil,
        _ failures: [TrashFailure],
        stats: Stats,
        onRetry: (() -> Void)? = nil,
        onCopyDiagnostics: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.failures = failures
        self.stats = stats
        self.onRetry = onRetry
        self.onCopyDiagnostics = onCopyDiagnostics
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            HStack(spacing: MMGap.sm) {
                if let summary {
                    Text(summary)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(MMColor.safe)
                }
                MMBadge(LF("panel.failuresCount", MMFormat.count(failures.count)), tint: MMColor.caution)
                Spacer()
                if let onDismiss {
                    Button(L("panel.dismiss"), action: onDismiss)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
            if let stats {
                statsRow(stats)
            }
            ForEach(failures.prefix(4)) { failure in
                HStack(spacing: MMGap.sm) {
                    // 主动拒绝和被系统挡住不是一回事：前者是我们判断过后的决定（琥珀色），
                    // 后者是 errno（红色）。混成一个图标，用户就分不出该找谁。
                    Image(systemName: failure.code == "PROTECTED" ? "exclamationmark.shield" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(failure.code == "PROTECTED" ? MMColor.caution : MMColor.destructive)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(failure.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(failure.message)
                            .font(.caption2)
                            .foregroundStyle(MMColor.secondaryLabel)
                            // 拒绝的理由要读完才知道下一步该干什么（"逐项选择"），
                            // 一行截断正好把可操作的那半句切掉。errno 原文短，一行够。
                            .lineLimit(failure.code == "PROTECTED" ? 2 : 1)
                    }
                    Spacer(minLength: MMGap.sm)
                    if let code = failure.code {
                        Text(code).font(.caption2.monospaced()).foregroundStyle(MMColor.tertiaryLabel)
                    }
                }
            }
            if failures.count > 4 {
                Text(LF("panel.moreFailures", MMFormat.count(failures.count - 4)))
                    .font(.caption2)
                    .foregroundStyle(MMColor.tertiaryLabel)
            }
            if onRetry != nil || onCopyDiagnostics != nil {
                Divider()
                HStack(spacing: MMGap.md) {
                    Spacer()
                    if let onCopyDiagnostics {
                        Button(L("panel.copyDiagnostics"), action: onCopyDiagnostics)
                            .buttonStyle(.borderless).controlSize(.small)
                    }
                    if let onRetry {
                        Button(L("panel.retryFailed"), action: onRetry)
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.caution, 0.10))
        .overlay(alignment: .top) { Divider() }
    }

    private func statsRow(_ stats: Stats) -> some View {
        HStack(spacing: MMGap.lg) {
            statCell(L("panel.statPlanned"), stats.planned, tint: MMColor.secondaryLabel)
            statCell(L("panel.statSucceeded"), stats.succeeded, tint: MMColor.safe)
            statCell(L("panel.statFailed"), failures.count, tint: MMColor.destructive)
            statCell(L("panel.statSkipped"), stats.skipped, tint: MMColor.caution)
        }
        .padding(.vertical, MMGap.xs)
    }

    private func statCell(_ label: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: MMGap.xs) {
            Text(label).font(.caption).foregroundStyle(MMColor.secondaryLabel)
            Text("\(value)").font(.caption.monospacedDigit()).foregroundStyle(tint)
        }
    }
}

/// 列表行：勾选 + 图标 + 名称/路径双行 + 右对齐数值 + 风险徽章。
/// 清理项、大文件、残留清单共用这一个结构。
public struct MMItemRow<Accessory: View>: View {
    let title: String
    let subtitle: String
    let value: String
    let risk: MMRisk?
    let systemImage: String
    let isSelectable: Bool
    let accessory: Accessory

    @Binding var isSelected: Bool

    public init(
        title: String,
        subtitle: String,
        value: String,
        risk: MMRisk? = nil,
        systemImage: String = "doc",
        isSelectable: Bool = true,
        isSelected: Binding<Bool>,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.risk = risk
        self.systemImage = systemImage
        self.isSelectable = isSelectable
        self._isSelected = isSelected
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: MMGap.md) {
            if isSelectable {
                Toggle("", isOn: $isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(risk.map { !$0.allowsDeletion } ?? false)
            } else {
                // I2：只读行保留禁用框占位，列才对齐。此前整列消失导致标题/数值/徽章各列错位。
                Toggle("", isOn: .constant(false))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(true)
                    .opacity(0.35)
            }
            Image(systemName: systemImage)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(risk?.color ?? MMColor.secondaryLabel)
                .frame(width: MMMetric.iconSmall)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                Text(title).font(.body).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: MMGap.sm)
            Text(value).font(.callout.monospaced()).monospacedDigit()
                .foregroundStyle(isSelected ? MMColor.label : MMColor.secondaryLabel)
                .frame(minWidth: 72, alignment: .trailing)
            if let risk { MMBadge(risk: risk) }
            accessory
        }
        .padding(.horizontal, MMGap.md)
        .frame(height: MMMetric.rowRegular)
        .background(isSelected ? MMColor.soft(MMColor.accent, 0.08) : .clear)
        .contentShape(Rectangle())
    }
}

extension MMItemRow where Accessory == EmptyView {
    public init(
        title: String,
        subtitle: String,
        value: String,
        risk: MMRisk? = nil,
        systemImage: String = "doc",
        isSelectable: Bool = true,
        isSelected: Binding<Bool>
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            value: value,
            risk: risk,
            systemImage: systemImage,
            isSelectable: isSelectable,
            isSelected: isSelected
        ) { EmptyView() }
    }
}

// MARK: - 卡片与数据可视化

/// 卡片底色档（S4）：设计稿里"卡浮在哪一层"本来就有两档——概览/列表的卡是 `.card`
/// （内容底之上，#FFFFFF），监控页的指标卡是 `.mcard`（页面底之下，--c-under-page #E4E4E4）。
/// 之前两档都用语义色凑，浅色档实测分别是 #E9E9E9 和 #959595，两档都错，
/// 所以这里改接 MMColor 里按稿钉死的面色。
public enum MMCardStyle {
    /// 设计稿 `.card`：白底 + 1px 分隔描边，列表/表格区块默认档。
    case content
    /// 设计稿 `.mcard`：沉到页面底那一档，监控页指标卡用。
    case underPage

    var color: Color {
        switch self {
        case .content: MMColor.cardSurface
        case .underPage: MMColor.underPageSurface
        }
    }
}

/// 卡片容器。设计稿里所有区块都是同一张卡：控制底色 + 8pt 圆角 + 1px 分隔描边。
/// 之前每个页面各写一遍 background/overlay，圆角和描边迟早会漂。
public struct MMCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = MMGap.lg
    var style: MMCardStyle = .content

    public init(padding: CGFloat = MMGap.lg, style: MMCardStyle = .content, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.style = style
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.color, in: RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous).stroke(MMColor.separator))
    }
}

/// 堆叠条的一段。`value` 用调用方的原始单位（字节、百分比都行），
/// 组件只负责按占比分配宽度——换算成宽度这件事不该在三个页面各算一遍。
public struct MMBarSegment: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let value: Double
    public let color: Color

    public init(id: String, label: String, value: Double, color: Color) {
        self.id = id
        self.label = label
        self.value = value
        self.color = color
    }
}

/// 分段占比条（存储构成、内存构成共用）。
/// 零值段直接丢掉：留着会把 1px 间隙画成一条虚色，读起来像"这里有一点占用"。
public struct MMStackedBar: View {
    let segments: [MMBarSegment]
    var height: CGFloat = 6

    public init(segments: [MMBarSegment], height: CGFloat = 6) {
        self.segments = segments.filter { $0.value > 0 }
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            let total = segments.reduce(0) { $0 + $1.value }
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { _, segment in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(segment.color)
                        .frame(width: total > 0
                            ? max(1, (proxy.size.width - CGFloat(max(0, segments.count - 1))) * segment.value / total)
                            : 0)
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// 图例：色块 + 名称 + 数值。数值由调用方拼好传进来，这里不猜单位。
public struct MMLegend: View {
    public struct Item: Identifiable {
        public let id: String
        public let text: String
        public let color: Color

        public init(id: String, text: String, color: Color) {
            self.id = id
            self.text = text
            self.color = color
        }
    }

    let items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        HStack(spacing: MMGap.md) {
            ForEach(items) { item in
                HStack(spacing: MMGap.xs) {
                    RoundedRectangle(cornerRadius: 1).fill(item.color).frame(width: 8, height: 8)
                    Text(item.text).font(.caption).foregroundStyle(MMColor.secondaryLabel).monospacedDigit()
                }
                .fixedSize()
            }
            Spacer(minLength: MMGap.sm)
        }
    }
}

/// 环形仪表。中心数字是主角，环只是它的图形化重复——所以没量到时环也空着，
/// 不画一个 0% 的满圈假装"占用为零"。
public struct MMGauge: View {
    let ratio: Double?
    let text: String
    let tint: Color

    public init(ratio: Double?, text: String, tint: Color = MMColor.accent) {
        self.ratio = ratio.map { min(1, max(0, $0)) }
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle().stroke(MMColor.fillActive, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(ratio ?? 0))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(ratio == nil ? "—" : text)
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(ratio == nil ? MMColor.tertiaryLabel : MMColor.label)
        }
        .frame(width: MMMetric.gauge, height: MMMetric.gauge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// 迷你柱状图。`values` 里 nil 表示那一次没采到，画成空槽而不是 0——
/// 0 是"确实没流量"，空槽才是"不知道"，两者在设计稿里必须是两种形状。
///
/// 槽数固定、柱宽按容器等分（稿 `.spark i { flex:1 }`）：第 1 次采样和第 12 次采样占同一条横轴。
/// 以前每根钉死 10pt 靠左排，首帧只有一根细柱孤零零贴在左边，读起来像图坏了，
/// 而且柱子会随采样次数往右爬——同一张图前后拍出来宽度不一样，还原度也没法逐元素对照。
public struct MMSparkline: View {
    let values: [Double?]
    let slotCount: Int

    public init(values: [Double?], slotCount: Int = 12) {
        self.values = values
        self.slotCount = max(slotCount, 1)
    }

    public var body: some View {
        let peak = values.compactMap { $0 }.max() ?? 0
        let filled = Array(values.suffix(slotCount))
        HStack(alignment: .bottom, spacing: 3) {
            // 还没采到的槽留空（不是画一根 2pt 的矮柱）：空槽"这次读不到"
            // 与"还没轮到这次"得能分辨，前者有痕、后者无痕。
            ForEach(0..<(slotCount - filled.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: MMMetric.sparkline)
            }
            ForEach(Array(filled.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(value, peak: peak))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(value, peak: peak))
            }
        }
        .frame(height: MMMetric.sparkline, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func barHeight(_ value: Double?, peak: Double) -> CGFloat {
        guard let value, peak > 0 else { return 2 }
        return max(2, MMMetric.sparkline * CGFloat(min(1, value / peak)))
    }

    private func barColor(_ value: Double?, peak: Double) -> Color {
        guard let value, peak > 0, value / peak >= 0.6 else { return MMColor.accent.opacity(0.30) }
        return MMColor.accent
    }
}
