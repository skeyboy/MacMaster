//
//  DevToolCacheView.swift — 「开发工具缓存」tab（P4.3）
//
//  这一屏没有任何删除入口：它只回答"这个缓存归谁管、在哪、多大、该跑哪条命令"。
//

import SwiftUI
import AppKit
import MMCore
import MMUI

@MainActor
final class DevToolCacheModel: ObservableObject {
    @Published var entries: [DevToolCacheEntry] = []
    @Published var updatedAt: String?
    /// 拷贝过的命令，用来给按钮一点即时反馈（不弹全局提示）。
    @Published var copiedID: String?

    func refresh() async {
        let measured = await Task.detached(priority: .utility) {
            DevToolCacheAuditor.liveEntries { SystemSampler.directoryBytes($0) }
        }.value
        entries = measured
        updatedAt = "上次盘点 " + MMFormat.dateTime(Date())
    }

    func copy(_ entry: DevToolCacheEntry) {
        guard let command = entry.ownerCommand else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(command, forType: .string)
        copiedID = entry.id
    }
}

struct DevToolCacheView: View {
    @ObservedObject var model: DevToolCacheModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: MMGap.xs) {
                ForEach(model.entries) { entry in
                    DevToolCacheRow(entry: entry,
                                    copied: model.copiedID == entry.id,
                                    onCopy: { model.copy(entry) })
                    Divider()
                }
                HStack(alignment: .top, spacing: MMGap.xs) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                    Text(DevToolCacheCopy.footnote)
                        .font(.caption)
                        .foregroundStyle(MMColor.tertiaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, MMGap.md)
                .padding(.vertical, MMGap.sm)
            }
            .padding(MMGap.sm)
        }
        .overlay {
            if model.entries.isEmpty {
                ProgressView().controlSize(.small)
            }
        }
        .task {
            if model.entries.isEmpty { await model.refresh() }
        }
    }
}

struct DevToolCacheRow: View {
    let entry: DevToolCacheEntry
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MMGap.md) {
            Image(systemName: "hammer")
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(MMColor.secondaryLabel)
                .frame(width: MMMetric.iconRow)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                HStack(spacing: MMGap.xs) {
                    Text(entry.title).font(.body.weight(.medium))
                    Text(DevToolCacheCopy.presenceBadge(entry))
                        .font(.caption)
                        .foregroundStyle(MMColor.secondaryLabel)
                }
                Text(abbreviated)
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.why)
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat = entry.caveat {
                    Text(caveat)
                        .font(.caption)
                        .foregroundStyle(caveatTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: MMGap.sm)
            VStack(alignment: .trailing, spacing: MMGap.xxs) {
                Text(entry.bytes.map(MMFormat.bytes) ?? "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(entry.bytes == nil ? MMColor.secondaryLabel : MMColor.label)
                MMBadge(entry.rootSource.badgeText, tint: MMColor.secondaryLabel,
                        systemImage: entry.rootSource == .defaultPath ? "questionmark.circle" : nil)
                HStack(spacing: MMGap.xs) {
                    if let command = entry.ownerCommand {
                        Button(copied ? "已拷贝" : "拷贝 \(command)") { onCopy() }
                            .controlSize(.small)
                            .help(command)
                    }
                    MMRevealButton(path: entry.root, title: "显示")
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
    }

    private var abbreviated: String {
        (entry.root as NSString).abbreviatingWithTildeInPath
    }

    /// "目录不存在"是确定的事实，不是需要警惕的状态——全橙会把六行都染成告警，
    /// 用户就分不清哪一条真读不到了。只有"没装"和"读不动"才用 caution。
    private var caveatTint: Color {
        if !entry.toolInstalled { return MMColor.caution }
        if case .unreadable = entry.presence { return MMColor.caution }
        return MMColor.secondaryLabel
    }
}
