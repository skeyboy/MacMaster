//
//  PreferencesView.swift — 「偏好文件」tab（P34b）
//
//  这一屏没有任何写盘入口：它只回答"这一族里有没有读不出来的文件、在哪、我们没看到哪几个"。
//  两栏分开画是硬要求（`optimizer-corrupt-preferences.md` §5）——
//  「读不出来或空的那些」用 caution，「这一族我们没看到」用中性色 + `eye.slash`，
//  共用车图标就等于把"我们没看"说成"它们坏了"。
//

import SwiftUI
import Foundation
import MMCore
import MMUI

@MainActor
final class PreferenceFilesModel: ObservableObject {
    @Published var scan: PreferencesScan?
    @Published var updatedAt: String?
    /// 夹具注入后钉住：见 `DuplicateScanModel.fixturePinned`（`MMOptimizer.swift`）那条说明。
    private var fixturePinned = false

    func refresh() async {
        guard !fixturePinned else { return }
        let measured = await Task.detached(priority: .utility) {
            PreferencesAuditor.liveScan(home: NSHomeDirectory())
        }.value
        if fixturePinned { return }   // 夹具优先，真实那一趟整批丢弃
        scan = measured
        updatedAt = "上次检查 " + MMFormat.dateTime(Date())
    }

    /// 进场即检查（生产路径）。
    func refreshIfNeeded() async {
        guard scan == nil, !fixturePinned else { return }
        await refresh()
    }

    /// 夹具注入：broken/unreadable/empty/partial 四档（`optimizer-corrupt-preferences.md` §12 第 4 条），
    /// 只顶替展示数据、不写盘不 spawn。
    func applyFixture(_ tier: OptimizerFixture.PrefsTier) {
        fixturePinned = true
        scan = OptimizerFixture.prefsScan(tier: tier)
        updatedAt = "上次检查 " + MMFormat.dateTime(Date())
    }
}

struct PreferencesFilesView: View {
    @ObservedObject var model: PreferenceFilesModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: MMGap.sm) {
                Text(headline)
                    .font(.callout).foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(2)
                Spacer(minLength: MMGap.md)
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, MMGap.lg)
            .frame(height: MMMetric.rowRegular)
            Divider()

            if let scan = model.scan {
                if !scan.skippedRoots.isEmpty {
                    MMPermissionBanner(title: "这一族我们整层没看到",
                                       detail: PreferencesCopy.skippedRootsNote(scan.skippedRoots))
                }
                content(scan)
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in MMSkeletonRow() }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task { await model.refreshIfNeeded() }
    }

    private var headline: String {
        guard let scan = model.scan else { return "正在读 ~/Library/Preferences…" }
        return PreferencesCopy.headline(scan)
    }

    @ViewBuilder
    private func content(_ scan: PreferencesScan) -> some View {
        if scan.badRows.isEmpty && scan.unreadableRows.isEmpty {
            // 脚注不能和空态并成同一个 VStack 的兄弟。`MMEmptyState` 自带
            // `.frame(maxWidth:.infinity, maxHeight:.infinity)`（`MMDesign.swift:476`），
            // 站内空态的"居中"就是它自己撑满实现的；再挂一个 `fixedSize(vertical:)` 的
            // 长文本当兄弟，SwiftUI 算理想尺寸时按极窄宽度折行，整组理想高度炸到 1183 pt
            // （窗口 900），host 变成 1183@Y-115，页头和页脚同时被裁出画面。
            // 证据：`00-probe-prefs-empty-before-fix.log`（炸）对照
            // `00-probe-browser-empty-control.log`（同一张空态、没有兄弟：900@Y0）。
            // 改成 overlay 贴底部：overlay 不参与基准视图的理想尺寸，贪心视图单独存在。
            MMEmptyState(
                systemImage: "doc.text",
                // 截断那一趟没说"没有"，只说"看到的那些里没有"——两者是不同的话。
                title: scan.isPartial ? "时间预算内没有发现" : "没有发现读不出来的偏好文件",
                detail: "这一句只说明这一台机器、这一条判据下没抓到，不代表偏好文件都是健康的。"
            )
            .overlay(alignment: .bottom) {
                // 空态也要留脚注：那一栏是"这一趟里 N 个根不是字典"的唯一出口，
                // 只在有行时才说会变成"数没了对不上页头"。
                footnote(scan)
                    .padding(.horizontal, MMGap.lg)
                    .padding(.bottom, MMGap.md)
            }
        } else {
            ScrollView {
                // alignment 必须是 leading：默认 center 会让那句 caveat 和脚注飘到中间，
                // 读起来像另一栏的内容（P34b 实拍第一版）。
                LazyVStack(alignment: .leading, spacing: MMGap.xs) {
                    if !scan.badRows.isEmpty {
                        SectionHeader(title: PreferencesCopy.badSection, count: scan.badRows.count,
                                      systemImage: "exclamationmark.triangle", tint: MMColor.caution)
                        ForEach(scan.badRows) { check in
                            PreferenceFileRow(check: check)
                            Divider()
                        }
                    }
                    if !scan.unreadableRows.isEmpty {
                        // 独立成栏：自己的标题、自己的图标、中性色。
                        SectionHeader(title: PreferencesCopy.unreadableSection, count: scan.unreadableRows.count,
                                      systemImage: "eye.slash", tint: MMColor.secondaryLabel)
                        Text(PreferencesCopy.unreadableNote(scan.unreadableCount))
                            .font(.caption).foregroundStyle(MMColor.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, MMGap.md)
                        ForEach(scan.unreadableRows) { check in
                            PreferenceFileRow(check: check)
                            Divider()
                        }
                    }
                    footnote(scan)
                }
                .padding(MMGap.sm)
            }
        }
    }

    @ViewBuilder
    private func footnote(_ scan: PreferencesScan) -> some View {
        VStack(alignment: .leading, spacing: MMGap.xs) {
            if scan.nonDictRootCount > 0 {
                Text(PreferencesCopy.nonDictRootNote(scan.nonDictRootCount))
            }
            Text(PreferencesCopy.footnote)
        }
        .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: MMGap.xs) {
            Image(systemName: systemImage).font(.caption).foregroundStyle(tint)
            Text("\(title)（\(count)）")
                .font(.caption.weight(.semibold)).foregroundStyle(tint)
            Spacer(minLength: MMGap.sm)
        }
        .padding(.horizontal, MMGap.md)
        .padding(.top, MMGap.xs)
    }
}

struct PreferenceFileRow: View {
    let check: PreferenceFileCheck

    var body: some View {
        HStack(alignment: .center, spacing: MMGap.md) {
            Image(systemName: systemImage)
                .font(.system(size: MMMetric.iconSmall))
                .foregroundStyle(tint)
                .frame(width: MMMetric.iconRow)
            VStack(alignment: .leading, spacing: MMGap.xxs) {
                HStack(spacing: MMGap.xs) {
                    Text(check.name).font(.body.weight(.medium)).lineLimit(1)
                    Text(check.verdict.badgeText)
                        .font(.caption).foregroundStyle(tint)
                    if check.inByHost {
                        Text("ByHost").font(.caption2).foregroundStyle(MMColor.tertiaryLabel)
                    }
                }
                Text((check.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(MMColor.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(check.path)
                // 建议进这一行（换行不截），不进上面那句路径——口径同 DevToolCacheRow 的 caveat。
                Text(PreferencesCopy.advice(check))
                    .font(.caption)
                    .foregroundStyle(MMColor.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: MMGap.sm)
            VStack(alignment: .trailing, spacing: MMGap.xxs) {
                Text(check.bytes.map { MMFormat.bytes(Int64($0)) } ?? "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(check.bytes == nil ? MMColor.secondaryLabel : MMColor.label)
                Text(MMFormat.dateTime(check.modified))
                    .font(.caption).foregroundStyle(MMColor.tertiaryLabel)
                MMRevealButton(path: check.path, title: "显示")
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, MMGap.md)
        .padding(.vertical, MMGap.sm)
    }

    /// 「读不到」用 `eye.slash` + 中性色，其余坏态用 `exclamationmark.triangle` + caution。
    /// 这两套不许合并——合并就等于宣称"没看到的那些是坏的"。
    private var systemImage: String {
        check.verdict.isUnreadable ? "eye.slash" : "exclamationmark.triangle"
    }

    private var tint: Color {
        check.verdict.isUnreadable ? MMColor.secondaryLabel : MMColor.caution
    }
}
