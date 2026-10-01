import SwiftUI
import MMCore
import MMFileScanner
import MMUI

/// 4.6：APFS 可清除空间与 Time Machine 本地快照的**只读**报告区块。
///
/// 两件事都不提供删除入口：清 purgeable 空间要系统自己决定，删本地快照需要 root
/// 且会改变备份语义（见 `docs/analysis/feature-roadmap.md` 的「明确不采纳」）。
/// 读不到就整块说明原因，绝不显示 0 或"没有快照"来冒充一个已知的事实。
struct ReadOnlySpaceReportSection: View {
    let readout: SystemSpaceReadout?
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            HStack(spacing: MMGap.sm) {
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundStyle(MMColor.secondaryLabel)
                Text("磁盘空间只读报告").font(.callout.weight(.semibold))
                MMBadge("只读 · 不会修改", tint: MMColor.informational)
                Spacer()
                if let readAt = readout?.readAt {
                    Text(MMFormat.dateTime(readAt))
                        .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                }
                Button(isLoading ? "读取中…" : "刷新", action: onRefresh)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(isLoading)
            }

            purgeableRows
            snapshotRows

            HStack(alignment: .top, spacing: MMGap.xs) {
                Image(systemName: "info.circle").font(.caption2)
                    .foregroundStyle(MMColor.tertiaryLabel)
                Text("这两项都需要管理员权限才能改动，MacMaster 不执行任何 sudo 操作，也不删除快照。"
                     + "要腾出可清除空间，交给系统在需要时自行回收；要清本地快照请到「系统设置 › 通用 › 储存空间」。")
                    .font(.caption2)
                    .foregroundStyle(MMColor.secondaryLabel)
            }
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.soft(MMColor.informational, 0.06))
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var purgeableRows: some View {
        if isLoading && readout == nil {
            Text("正在读取卷容量信息…")
                .font(.caption).foregroundStyle(MMColor.secondaryLabel)
        } else if let report = readout?.purgeable, report.isAvailable {
            // 口径写死在文案里：这两个 available 是不同 key，混着说会对不上访达。
            MMKeyRow("可清除", MMFormat.bytes(report.purgeable) + "（估算）", monospaced: true)
            MMKeyRow("访达可用", MMFormat.bytes(report.availableForImportantUsage), monospaced: true)
            MMKeyRow("程序可用", MMFormat.bytes(report.availableCapacity), monospaced: true)
            MMKeyRow("卷", "\(report.volumeName) · \(report.volumePath)")
        } else {
            unavailableRow(title: "可清除空间", reason: readout?.purgeable.reason ?? "尚未读取")
        }
    }

    @ViewBuilder
    private var snapshotRows: some View {
        if isLoading && readout == nil {
            Text("正在读取本地快照…")
                .font(.caption).foregroundStyle(MMColor.secondaryLabel)
        } else if let listing = readout?.snapshots, listing.isAvailable {
            let snapshots = listing.snapshots
            MMKeyRow("本地快照", "\(snapshots.count) 个" + kindSummary(listing), monospaced: true)
            if snapshots.isEmpty {
                Text("这台 Mac 目前没有本地快照。")
                    .font(.caption).foregroundStyle(MMColor.secondaryLabel)
            } else {
                // 只列前若干条：快照数量可以很多，全列出来这块就没完没了了。
                ForEach(snapshots.prefix(6)) { snapshot in
                    HStack(spacing: MMGap.sm) {
                        Image(systemName: snapshot.kind == .timeMachine
                              ? "clock.arrow.circlepath" : "shippingbox")
                            .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                        Text(snapshot.name)
                            .font(.caption.monospaced())
                            .lineLimit(1).truncationMode(.middle)
                        Text(snapshot.kind.label)
                            .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                        Spacer(minLength: MMGap.sm)
                        Text(snapshot.volumePath ?? "—")
                            .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                            .lineLimit(1)
                    }
                }
                if snapshots.count > 6 {
                    Text("另有 \(snapshots.count - 6) 个快照")
                        .font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                }
            }
            // 这里只有条数、没有 GB，是刻意的：APFS 不按快照单独计量占用，
            // 无管理员权限读不到。拿"容器已用 − 各卷已用合计"去凑，凑出来的是
            // 元数据和预留空间（本机实测约 1.4 GB），不是快照足迹。
            Text("只报条数：APFS 不给单个快照的独立占用，无管理员权限读不到，"
                 + "所以这里没有一个「快照占了 X GB」的数字。第三方工具报的那个 GB "
                 + "多半是拿容器差值凑的，别照着它判断要不要删。")
                .font(.caption2)
                .foregroundStyle(MMColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            unavailableRow(title: "本地快照", reason: readout?.snapshots.reason ?? "尚未读取")
        }
    }

    /// 条数后面的来历拆分。全是一类时不啰嗦，混着才列——
    /// 把系统更新快照说成 Time Machine 快照会指错方向（动了影响更新回滚）。
    private func kindSummary(_ listing: LocalSnapshotListing) -> String {
        let kinds: [LocalSnapshot.Kind] = [.timeMachine, .systemUpdate, .other]
        let parts = kinds.compactMap { kind -> String? in
            let count = listing.count(of: kind)
            return count > 0 ? "\(kind.label) \(count)" : nil
        }
        return parts.count > 1 ? "（" + parts.joined(separator: " · ") + "）" : ""
    }

    private func unavailableRow(title: String, reason: String) -> some View {
        HStack(alignment: .top, spacing: MMGap.sm) {
            Image(systemName: "questionmark.circle")
                .font(.caption).foregroundStyle(MMColor.caution)
            Text("\(title)：不可用").font(.caption.weight(.semibold))
            Text(reason)
                .font(.caption2)
                .foregroundStyle(MMColor.secondaryLabel)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
