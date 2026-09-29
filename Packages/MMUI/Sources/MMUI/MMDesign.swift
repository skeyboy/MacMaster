import SwiftUI
import AppKit
import MMCore

// MARK: - 设计令牌
//
// 全站唯一的颜色、栅格、圆角与行高来源。规则：一律取 AppKit 动态语义色，
// 不写死 RGBA —— 这样深色模式、强调色变更、辅助功能高对比度都能自动跟随。
// 旧的 ThemeColor 保留只是为了不破坏未迁移的调用点，新代码一律用 MM*。

public enum MMColor {
    public static let accent = Color(nsColor: .controlAccentColor)
    public static let label = Color(nsColor: .labelColor)
    public static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    public static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)

    public static let contentBackground = Color(nsColor: .textBackgroundColor)
    public static let controlBackground = Color(nsColor: .windowBackgroundColor)
    public static let cardBackground = Color(nsColor: .underPageBackgroundColor)

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
    public static let sidebar: CGFloat = 216
    public static let inspector: CGFloat = 268
    public static let iconSmall: CGFloat = 16
    public static let iconRow: CGFloat = 28
    public static let iconApp: CGFloat = 32
}

// MARK: - 格式化（全站唯一实现）

public enum MMFormat {
    private static let byte: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    /// 大小未测出时显示"测量中"，绝不显示误导性的 "0 字节"。
    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "测量中" }
        return byte.string(fromByteCount: Int64(value))
    }

    public static func bytes(_ value: Int64?) -> String {
        guard let value else { return "测量中" }
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

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    public static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = Date().timeIntervalSince(date)
        // RelativeDateTimeFormatter 会把刚刚发生的事说成"0 秒后"，读起来像 bug。
        if abs(seconds) < 5 { return "刚刚" }
        return relative.localizedString(for: date, relativeTo: Date())
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
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(MMColor.secondaryLabel)
                        .monospacedDigit()
                }
            }
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
        .background(MMColor.cardBackground)
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
        .background(MMColor.cardBackground, in: RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
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
    var settingsPane: String? = nil

    public init(title: String, detail: String, settingsPane: String? = nil) {
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
    public static func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
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

/// 撤回回执。统一实现，取代此前 4 处手写 toast。
/// 撤回的长期入口是操作历史，这个 toast 只是事后兜底。
public struct MMUndoToast: View {
    let message: String
    let detail: String?
    let onUndo: () -> Void
    var onRevealTrash: (() -> Void)? = nil
    var secondsRemaining: Int? = nil

    public init(
        message: String,
        detail: String? = nil,
        secondsRemaining: Int? = nil,
        onUndo: @escaping () -> Void,
        onRevealTrash: (() -> Void)? = nil
    ) {
        self.message = message
        self.detail = detail
        self.secondsRemaining = secondsRemaining
        self.onUndo = onUndo
        self.onRevealTrash = onRevealTrash
    }

    public var body: some View {
        HStack(spacing: MMGap.sm) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(MMColor.safe)
            Text(message).font(.callout.weight(.medium))
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: MMGap.md)
            Button("撤回", action: onUndo).buttonStyle(.plain).foregroundStyle(.white)
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
public struct MMFailurePanel: View {
    let summary: String?
    let failures: [TrashFailure]
    var onDismiss: (() -> Void)?

    public init(summary: String? = nil, _ failures: [TrashFailure], onDismiss: (() -> Void)? = nil) {
        self.summary = summary
        self.failures = failures
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
                MMBadge("\(failures.count) 项失败", tint: MMColor.caution)
                Spacer()
                if let onDismiss {
                    Button("忽略", action: onDismiss)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
            ForEach(failures.prefix(4)) { failure in
                HStack(spacing: MMGap.sm) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(MMColor.destructive)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(failure.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(failure.message)
                            .font(.caption2)
                            .foregroundStyle(MMColor.secondaryLabel)
                            .lineLimit(1)
                    }
                    Spacer(minLength: MMGap.sm)
                    if let code = failure.code {
                        Text(code).font(.caption2.monospaced()).foregroundStyle(MMColor.tertiaryLabel)
                    }
                }
            }
            if failures.count > 4 {
                Text("另有 \(failures.count - 4) 项失败")
                    .font(.caption2)
                    .foregroundStyle(MMColor.tertiaryLabel)
            }
        }
        .padding(.horizontal, MMGap.lg)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.caution, 0.10))
        .overlay(alignment: .top) { Divider() }
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
            if let risk { MMBadge(risk: risk) }
            accessory
            Text(value).font(.callout.monospaced()).monospacedDigit()
                .foregroundStyle(isSelected ? MMColor.label : MMColor.secondaryLabel)
                .frame(minWidth: 72, alignment: .trailing)
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
