import SwiftUI
import AppKit
import MMCore

/// 全树名称过滤的两级表态（对齐 disktree 的"匹配保色、祖先退色"）：
/// 命中块保留原始分类色，含命中的祖先退色。色相回答"这是什么"，
/// 保色/退色回答"它是不是命中本身"——两个维度不能互相污染。
public enum TreemapMatchTier: Sendable {
    /// 名称直接命中（或位于命中目录之内）：保色。
    case matched
    /// 自身未命中、子树里含命中：退色，面积按命中体积而非自身占用。
    case containsMatch
}

public struct TreemapItem: Identifiable {
    public let id: String
    public let name: String
    public let value: Double
    public let color: Color
    public let children: [TreemapItem]
    public let isDirectory: Bool
    /// 斜纹通道：这一块（或它所在的祖先）被判定为可清理。
    public let reclaimable: Bool
    /// nil = 名称过滤未启用，按常规画法；非 nil = 过滤布局里的两级之一。
    public let matchTier: TreemapMatchTier?
    /// 合并出来的"其余"块：面积守恒但不下钻。判据必须是这个标志，
    /// 不能看名字——名字现在跟着界面语言走，切英文后前缀判断会静默失效，
    /// 那块变成可下钻的空目录。
    public let isOthers: Bool

    public init(id: String, name: String, value: Double, color: Color = .blue,
                children: [TreemapItem] = [], isDirectory: Bool = false,
                reclaimable: Bool = false, matchTier: TreemapMatchTier? = nil,
                isOthers: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.color = color
        self.children = children
        self.isDirectory = isDirectory
        self.reclaimable = reclaimable
        self.matchTier = matchTier
        self.isOthers = isOthers
    }
}

public struct TreemapRect {
    public let item: TreemapItem
    /// 该块占据的完整矩形（含内缩前的外框）。
    public let rect: CGRect
    /// 目录名所在的顶部色带；nil 表示该块不再细分。
    public let header: CGRect?
    public let depth: Int
    /// 由多个尾部小块合并出来的"其余"块——面积守恒，但不能下钻。
    public let isOthers: Bool

    public init(item: TreemapItem, rect: CGRect, header: CGRect? = nil,
                depth: Int = 0, isOthers: Bool = false) {
        self.item = item
        self.rect = rect
        self.header = header
        self.depth = depth
        self.isOthers = isOthers
    }
}

/// 图例里的斜纹小样。线距按块内斜纹等比缩小，保证图例和图形对得上——
/// 图例画成另一种密度，用户就会怀疑自己看错了纹。
public struct TreemapHatchSwatch: View {
    let base: Color

    public init(base: Color = Color(red: 0.85, green: 0.85, blue: 0.85)) {
        self.base = base
    }

    public var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            var hatch = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                hatch.move(to: CGPoint(x: x, y: size.height))
                hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 3
            }
            context.stroke(hatch, with: .color(.black.opacity(0.4)), lineWidth: 1)
        }
        .frame(width: 10, height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// 色相 = 这块属于哪一类（由调用方给出），明度 = 这块嵌在第几层。
/// 两个维度各占一个视觉通道，才不会互相污染。
public enum TreemapPalette {
    public static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }

    /// 越深越浅：每下一层往白色方向提 22%，最多提到 66%，
    /// 保证第六层和第一层仍然看得出是同一支颜色。
    public static func shade(_ base: Color, depth: Int) -> Color {
        guard depth > 0 else { return base }
        guard let rgb = NSColor(base).usingColorSpace(.sRGB) else { return base }
        let t = min(0.66, CGFloat(depth) * 0.22)
        func lift(_ c: CGFloat) -> Double { Double(c + (1 - c) * t) }
        return Color(red: lift(rgb.redComponent), green: lift(rgb.greenComponent),
                     blue: lift(rgb.blueComponent))
    }
}

public struct TreemapLayoutOptions {
    /// 默认画 3 层：再深的目录对"哪里占地方"这个问题已经没有信息量了。
    public var maxDepth: Int = 3
    public var outerPadding: CGFloat = 3
    public var innerPadding: CGFloat = 1
    /// 小于这条边的块直接丢弃，画出来只是噪点。
    public var minTile: CGFloat = 5
    /// 每层最多展开的子块数，其余合并成一个"其余 N 项"块以保证面积守恒。
    public var maxChildren: Int = 96
    public var headerHeight: CGFloat = 14
    /// 窄于此宽度就不画目录名，避免文字溢出成糊状。
    public var minHeaderWidth: CGFloat = 44
    /// 全局瓦片预算。面积足够小时再细分已经没有信息量，却会让 hover
    /// 期间的重算变成万级循环；超预算就停止下钻，父块照常显示。
    public var maxTiles: Int = 1200

    public init() {}

    /// 越深的层允许的兄弟块越少：外层要能比较大小，内层只是纹理。
    public func childCap(at depth: Int) -> Int {
        depth == 0 ? maxChildren : max(4, maxChildren >> (2 * depth))
    }
}

public enum TreemapLayout {
    public static func compute(items: [TreemapItem], in rect: CGRect,
                               options: TreemapLayoutOptions = TreemapLayoutOptions()) -> [TreemapRect] {
        var out: [TreemapRect] = []
        let inset = rect.insetBy(dx: options.outerPadding, dy: options.outerPadding)
        place(items: items, in: inset, depth: 0, options: options, into: &out)
        return out
    }

    private static func place(items: [TreemapItem], in rect: CGRect, depth: Int,
                              options: TreemapLayoutOptions, into out: inout [TreemapRect]) {
        let sorted = items.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let total = sorted.reduce(0) { $0 + $1.value }
        guard total > 0, rect.width >= options.minTile, rect.height >= options.minTile else { return }

        var tiles = Array(sorted.prefix(options.childCap(at: depth)))
        // 溢出必须按本层的 childCap 切，不是按 depth 0 的 maxChildren：
        // 深层 cap 更小（24、6、4…），用错基准会把 cap 与 maxChildren
        // 之间的块静默丢掉，"其余"块也不再面积守恒——全树过滤按命中体积
        // 重排后依赖这块面积诚实。
        let overflow = sorted.dropFirst(options.childCap(at: depth))
        if !overflow.isEmpty {
            let restValue = overflow.reduce(0) { $0 + $1.value }
            tiles.append(TreemapItem(
                id: "others:\(depth):\(rect.minX):\(rect.minY)",
                name: LF("ui.treemap.others", MMFormat.count(overflow.count)),
                value: restValue,
                color: MMColor.tertiaryLabel,
                isDirectory: true,
                isOthers: true
            ))
        }

        for cell in squarify(items: tiles, rect: rect, totalValue: total) {
            let item = cell.item
            var body = cell.rect.insetBy(dx: options.innerPadding, dy: options.innerPadding)
            var header: CGRect?

            let canSubdivide = depth + 1 < options.maxDepth
                && !item.children.isEmpty
                && body.width >= options.minHeaderWidth
                && body.height - options.headerHeight >= options.minTile * 3
                && out.count < options.maxTiles
            if canSubdivide {
                header = CGRect(x: body.minX, y: body.minY, width: body.width, height: options.headerHeight)
                // 子块从标题带下沿开始，而不是从整块的下沿开始——写成 body.maxY
                // 会把整棵子树推到画布外面，Canvas 一裁就什么都不剩了。
                body = CGRect(x: body.minX, y: body.minY + options.headerHeight,
                              width: body.width, height: max(0, body.height - options.headerHeight))
            }

            out.append(TreemapRect(
                item: item, rect: cell.rect, header: header, depth: depth,
                isOthers: item.isOthers
            ))
            if canSubdivide {
                place(items: item.children, in: body, depth: depth + 1, options: options, into: &out)
            }
        }
    }

    private static func squarify(items: [TreemapItem], rect: CGRect, totalValue: Double) -> [TreemapRect] {
        guard !items.isEmpty, rect.width > 1, rect.height > 1 else { return [] }

        var results: [TreemapRect] = []
        var remaining = items
        var currentRect = rect
        var currentValue = totalValue

        while !remaining.isEmpty, currentValue > 0 {
            let isWide = currentRect.width >= currentRect.height
            let sideLength = isWide ? currentRect.height : currentRect.width

            var row: [TreemapItem] = []
            var rowValue: Double = 0
            var bestAspect = Double.infinity

            for item in remaining {
                let testRow = row + [item]
                let testValue = rowValue + item.value
                let rowFraction = testValue / currentValue
                let rowLength = (isWide ? currentRect.width : currentRect.height) * CGFloat(rowFraction)

                guard rowLength > 0 else { continue }

                var worstAspect: Double = 0
                for rowItem in testRow {
                    let itemFraction = rowItem.value / testValue
                    let itemWidth = sideLength * CGFloat(itemFraction)
                    let aspect = max(rowLength / max(itemWidth, 0.001),
                                     itemWidth / max(rowLength, 0.001))
                    worstAspect = max(worstAspect, Double(aspect))
                }

                if worstAspect <= bestAspect || row.isEmpty {
                    row.append(item)
                    rowValue = testValue
                    bestAspect = worstAspect
                } else {
                    break
                }
            }

            // 一行都凑不出来 = 剩余块已经小于这条边。继续循环不会产生任何进展，
            // 只会把主线程钉死在 100% CPU（矩形被上一行吃干时就会走到这里）。
            guard !row.isEmpty, rowValue > 0 else { break }

            let rowFraction = min(1, rowValue / currentValue)
            let rowLength = (isWide ? currentRect.width : currentRect.height) * CGFloat(rowFraction)
            var offset: CGFloat = 0
            for item in row {
                let itemFraction = item.value / rowValue
                let itemSize = sideLength * CGFloat(itemFraction)

                let itemRect: CGRect
                if isWide {
                    itemRect = CGRect(x: currentRect.minX, y: currentRect.minY + offset,
                                      width: rowLength, height: itemSize)
                } else {
                    itemRect = CGRect(x: currentRect.minX + offset, y: currentRect.minY,
                                      width: itemSize, height: rowLength)
                }

                results.append(TreemapRect(item: item, rect: itemRect))
                offset += itemSize
            }

            if isWide {
                currentRect = CGRect(x: currentRect.minX + rowLength, y: currentRect.minY,
                                     width: currentRect.width - rowLength, height: currentRect.height)
            } else {
                currentRect = CGRect(x: currentRect.minX, y: currentRect.minY + rowLength,
                                     width: currentRect.width, height: currentRect.height - rowLength)
            }

            currentValue -= rowValue
            remaining.removeFirst(row.count)
        }

        return results
    }
}

/// 多层嵌套 treemap。用 Canvas 一次画完而不是拼视图：
/// 一个目录树动辄上千块，SwiftUI 元素数量本身就是瓶颈。
public struct TreemapView: View {
    let items: [TreemapItem]
    let options: TreemapLayoutOptions
    let markedIDs: Set<String>
    let selectedID: String?
    /// 单击 = 选中（给详情面板看），双击 = 下钻，⌘ 单击 = 标记。
    let onSelect: ((TreemapItem) -> Void)?
    let onDrill: ((TreemapItem) -> Void)?
    let onMark: ((TreemapItem) -> Void)?
    /// Esc = 返回上一层。下钻容易、回头难，键盘通路必须两头都有。
    let onBack: (() -> Void)?

    @State private var hoveredID: String?
    @FocusState private var isFocused: Bool

    public init(items: [TreemapItem], options: TreemapLayoutOptions = TreemapLayoutOptions(),
                markedIDs: Set<String> = [], selectedID: String? = nil,
                onSelect: ((TreemapItem) -> Void)? = nil,
                onDrill: ((TreemapItem) -> Void)? = nil,
                onMark: ((TreemapItem) -> Void)? = nil,
                onBack: (() -> Void)? = nil) {
        self.items = items
        self.options = options
        self.markedIDs = markedIDs
        self.selectedID = selectedID
        self.onSelect = onSelect
        self.onDrill = onDrill
        self.onMark = onMark
        self.onBack = onBack
    }

    public var body: some View {
        GeometryReader { geo in
            let layout = TreemapLayout.compute(
                items: items, in: CGRect(origin: .zero, size: geo.size), options: options
            )

            Canvas { context, _ in
                for cell in layout {
                    draw(cell, in: &context)
                }
            }
            .highPriorityGesture(SpatialTapGesture(count: 2).onEnded { value in
                if let hit = deepest(at: value.location, in: layout), hit.item.isDirectory, !hit.isOthers {
                    onDrill?(hit.item)
                }
            })
            .gesture(SpatialTapGesture(count: 1).onEnded { value in
                guard let hit = deepest(at: value.location, in: layout), !hit.isOthers else { return }
                if NSEvent.modifierFlags.contains(.command) {
                    if hit.item.isDirectory { onMark?(hit.item) }
                } else {
                    onSelect?(hit.item)
                }
            })
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredID = deepest(at: location, in: layout)?.item.id
                case .ended:
                    hoveredID = nil
                }
            }
            // 键盘通路：鼠标不是浏览这张图的唯一方式，且块密集时键盘比
            // 精确点击快得多。四个方向只在同层兄弟块之间移动，跨层跳块
            // 会让人失去方位感。
            .focusable()
            .focused($isFocused)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                        .strokeBorder(MMColor.accent.opacity(0.55), lineWidth: 2)
                }
            }
            .onKeyPress(.upArrow) { moveSelection(.up, in: layout) }
            .onKeyPress(.downArrow) { moveSelection(.down, in: layout) }
            .onKeyPress(.leftArrow) { moveSelection(.left, in: layout) }
            .onKeyPress(.rightArrow) { moveSelection(.right, in: layout) }
            .onKeyPress(.return) { drillSelected(in: layout) }
            .onKeyPress(.space) { markSelected(in: layout) }
            .onKeyPress(.escape) {
                guard onBack != nil else { return .ignored }
                onBack?()
                return .handled
            }
        }
        .accessibilityLabel(L("ui.treemap.a11y"))
    }

    enum TreemapDirection { case up, down, left, right }

    private func selectedCell(in layout: [TreemapRect]) -> TreemapRect? {
        guard let id = selectedID else { return nil }
        return layout.last { $0.item.id == id }
    }

    @discardableResult
    private func moveSelection(_ direction: TreemapDirection, in layout: [TreemapRect]) -> KeyPress.Result {
        guard let target = Self.stepped(from: selectedCell(in: layout), toward: direction, in: layout) else {
            return .ignored
        }
        onSelect?(target)
        return .handled
    }

    @discardableResult
    private func drillSelected(in layout: [TreemapRect]) -> KeyPress.Result {
        guard let cell = selectedCell(in: layout), cell.item.isDirectory, !cell.isOthers else {
            return .ignored
        }
        onDrill?(cell.item)
        return .handled
    }

    @discardableResult
    private func markSelected(in layout: [TreemapRect]) -> KeyPress.Result {
        guard let cell = selectedCell(in: layout), cell.item.isDirectory, !cell.isOthers else {
            return .ignored
        }
        onMark?(cell.item)
        return .handled
    }

    /// 没选中任何东西时按最大块起步；之后每一步取"该方向上最近、
    /// 横向偏移最小"的同层兄弟块。块尺寸悬殊，严格的边相邻判定会在
    /// 大块旁边卡住，所以用中心点距离加横向惩罚来打分。
    static func stepped(from start: TreemapRect?, toward direction: TreemapDirection,
                        in layout: [TreemapRect]) -> TreemapItem? {
        let candidates = layout.filter { !$0.isOthers }
        guard let start else { return candidates.first?.item }

        let origin = CGPoint(x: start.rect.midX, y: start.rect.midY)
        var best: (item: TreemapItem, cost: Double)?
        for cell in candidates where cell.depth == start.depth && cell.item.id != start.item.id {
            let dx = cell.rect.midX - origin.x
            let dy = cell.rect.midY - origin.y
            let along: CGFloat
            let across: CGFloat
            switch direction {
            case .up:    guard dy < -0.5 else { continue }; along = -dy; across = abs(dx)
            case .down:  guard dy >  0.5 else { continue }; along =  dy; across = abs(dx)
            case .left:  guard dx < -0.5 else { continue }; along = -dx; across = abs(dy)
            case .right: guard dx >  0.5 else { continue }; along =  dx; across = abs(dy)
            }
            let cost = Double(along) + 3 * Double(across)
            if best == nil || cost < best!.cost { best = (cell.item, cost) }
        }
        return best?.item
    }

    /// 过滤两级的不透明度：「保色」就是常规分档亮度（匹配项与不过滤时长得一样，
    /// 不会引入第二种"命中色"）；「退色」把不透明度砍到约一半但保留色相，
    /// 让含命中的祖先明确低一级。hover 仍回到全亮——临时退色的块不该读不出内容。
    static func fillOpacity(for tier: TreemapMatchTier?, depth: Int, isHovered: Bool) -> Double {
        if isHovered { return 1 }
        switch tier {
        case nil, .matched: return depth == 0 ? 0.9 : 0.75
        case .containsMatch: return depth == 0 ? 0.38 : 0.30
        }
    }

    /// 45° 斜线铺满矩形，裁到块的圆角轮廓里。
    private func strokeHatch(in context: inout GraphicsContext, path: Path, rect: CGRect,
                             color: Color, spacing: CGFloat, lineWidth: CGFloat) {
        context.drawLayer { layer in
            layer.clip(to: path)
            var hatch = Path()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                hatch.move(to: CGPoint(x: x, y: rect.maxY))
                hatch.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += spacing
            }
            layer.stroke(hatch, with: .color(color), lineWidth: lineWidth)
        }
    }

    /// 命中的是"最深的那一块"，点击才等价于用户看到的下钻目标。
    private func deepest(at point: CGPoint, in layout: [TreemapRect]) -> TreemapRect? {
        layout.last { $0.rect.contains(point) && $0.rect.width >= options.minTile }
    }

    private func draw(_ cell: TreemapRect, in context: inout GraphicsContext) {
        let rect = cell.rect.insetBy(dx: options.innerPadding, dy: options.innerPadding)
        guard rect.width >= options.minTile, rect.height >= options.minTile else { return }

        let isHovered = hoveredID == cell.item.id
        let isMarked = markedIDs.contains(cell.item.id)
        let isSelected = selectedID == cell.item.id
        let path = Path(roundedRect: rect, cornerRadius: 3)
        context.fill(path, with: .color(cell.item.color.opacity(
            Self.fillOpacity(for: cell.item.matchTier, depth: cell.depth, isHovered: isHovered)
        )))

        // 可清理 = 斜纹（对应设计稿图例里的"可清理（斜纹）"）。用同色系暗纹，
        // 它是属性；标记用亮白斜纹 + 勾标，它是意图。两者不能撞车，所以
        // 一旦被标记，暗纹就让位给亮纹。
        if cell.item.reclaimable, !isMarked {
            strokeHatch(in: &context, path: path, rect: rect,
                        color: .black.opacity(0.20), spacing: 6, lineWidth: 1)
        }

        // 标记过的块：斜纹 + 右下角勾标，一眼能看出"这块我打算处理"
        if isMarked {
            strokeHatch(in: &context, path: path, rect: rect,
                        color: .white.opacity(0.4), spacing: 7, lineWidth: 1.5)
        }

        if let header = cell.header {
            context.fill(Path(roundedRect: header, cornerRadius: 2), with: .color(.black.opacity(0.16)))
            let nameWidth = header.width - 12 - sizeTextWidth(cell)
            let name = Text(ellipsize(cell.item.name, width: max(10, nameWidth), fontSize: 9))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
            context.draw(name, at: CGPoint(x: header.minX + 5, y: header.midY), anchor: .leading)
            if nameWidth > 24 {
                let size = Text(shortSize(cell.item.value))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
                context.draw(size, at: CGPoint(x: header.maxX - 5, y: header.midY), anchor: .trailing)
            }
        }

        // 标签按尺寸分级：放不下就宁可什么都不画，也不要用文字糊满整张图。
        // 有标题带的块已经在带里写过名字和大小，再在块顶画一遍就是重影。
        if cell.header == nil {
            if rect.width >= 68, rect.height >= 30 {
                let name = Text(ellipsize(cell.item.name, width: rect.width - 10, fontSize: 10))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                context.draw(name, at: CGPoint(x: rect.minX + 5, y: rect.minY + 5), anchor: .topLeading)
                let size = Text(MMFormat.bytes(UInt64(max(0, cell.item.value))))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
                context.draw(size, at: CGPoint(x: rect.minX + 5, y: rect.minY + 19), anchor: .topLeading)
            } else if rect.width >= 34, rect.height >= 16 {
                let name = Text(ellipsize(cell.item.name, width: rect.width - 6, fontSize: 8))
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.9))
                context.draw(name, at: CGPoint(x: rect.minX + 3, y: rect.midY), anchor: .leading)
            }
        }

        if isMarked && rect.width >= 44 {
            let badge = CGRect(x: rect.maxX - 18, y: rect.maxY - 18, width: 14, height: 14)
            context.fill(Path(ellipseIn: badge), with: .color(.black.opacity(0.35)))
            context.draw(
                Text("✓").font(.system(size: 8, weight: .bold)).foregroundColor(.white),
                at: CGPoint(x: badge.midX, y: badge.midY - 0.5)
            )
        }

        if isSelected {
            context.stroke(path, with: .color(MMColor.accent), lineWidth: 2)
        } else if isHovered {
            context.stroke(path, with: .color(.white), lineWidth: 1.5)
        }
    }

    /// Canvas 里的 Text 不会自动截断，超宽就直接压到邻居块上。
    /// 中文按整宽、拉丁按半宽估算，够用了——这是标签不是正文。
    private func ellipsize(_ text: String, width: CGFloat, fontSize: CGFloat) -> String {
        var used: CGFloat = 0
        var result = ""
        for character in text {
            let advance = character.isASCII ? fontSize * 0.55 : fontSize
            guard used + advance <= width else { return result + "…" }
            used += advance
            result.append(character)
        }
        return result
    }

    private func shortSize(_ value: Double) -> String {
        MMFormat.bytes(UInt64(max(0, value)))
    }

    /// 等宽数字按 0.6 字宽估，用来给右侧的容量留出空间。
    private func sizeTextWidth(_ cell: TreemapRect) -> CGFloat {
        CGFloat(shortSize(cell.item.value).count) * 9 * 0.6
    }
}
