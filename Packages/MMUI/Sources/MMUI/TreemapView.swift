import SwiftUI

public struct TreemapItem: Identifiable {
    public let id: String
    public let name: String
    public let value: Double
    public let color: Color
    public let children: [TreemapItem]
    public let isDirectory: Bool

    public init(id: String, name: String, value: Double, color: Color = .blue,
                children: [TreemapItem] = [], isDirectory: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.color = color
        self.children = children
        self.isDirectory = isDirectory
    }
}

public struct TreemapRect {
    public let item: TreemapItem
    public let rect: CGRect

    public init(item: TreemapItem, rect: CGRect) {
        self.item = item
        self.rect = rect
    }
}

public enum TreemapLayout {
    public static func compute(items: [TreemapItem], in rect: CGRect) -> [TreemapRect] {
        let sorted = items.sorted { $0.value > $1.value }
        let totalValue = sorted.reduce(0) { $0 + $1.value }
        guard totalValue > 0 else { return [] }
        return squarify(items: sorted, rect: rect, totalValue: totalValue)
    }

    private static func squarify(items: [TreemapItem], rect: CGRect, totalValue: Double) -> [TreemapRect] {
        guard !items.isEmpty, rect.width > 1, rect.height > 1 else { return [] }

        var results: [TreemapRect] = []
        var remaining = items
        var currentRect = rect
        var currentValue = totalValue

        while !remaining.isEmpty {
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
                for rItem in testRow {
                    let itemFraction = rItem.value / testValue
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

            let rowFraction = rowValue / currentValue
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

public struct TreemapView: View {
    let items: [TreemapItem]
    let onSelect: ((TreemapItem) -> Void)?

    @State private var hoveredID: String?

    public init(items: [TreemapItem], onSelect: ((TreemapItem) -> Void)? = nil) {
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let layout = TreemapLayout.compute(items: items, in: rect)

            ZStack(alignment: .topLeading) {
                ForEach(layout, id: \.item.id) { cell in
                    treemapCell(cell)
                }
            }
        }
    }

    @ViewBuilder
    private func treemapCell(_ cell: TreemapRect) -> some View {
        let isHovered = hoveredID == cell.item.id
        let minSize: CGFloat = 40

        if cell.rect.width >= minSize && cell.rect.height >= minSize {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: cell.item.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.caption2)
                    Text(cell.item.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                Text(formatSize(cell.item.value))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Spacer(minLength: 0)
            }
            .padding(6)
            .foregroundStyle(.white)
            .frame(width: max(0, cell.rect.width - 2), height: max(0, cell.rect.height - 2))
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(cell.item.color.opacity(isHovered ? 0.95 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHovered ? .white : .clear, lineWidth: 2)
            )
            .offset(x: cell.rect.minX + 1, y: cell.rect.minY + 1)
            .onHover { hovering in
                hoveredID = hovering ? cell.item.id : nil
            }
            .onTapGesture {
                onSelect?(cell.item)
            }
        } else if cell.rect.width >= 4 && cell.rect.height >= 4 {
            RoundedRectangle(cornerRadius: 2)
                .fill(cell.item.color.opacity(0.6))
                .frame(width: max(0, cell.rect.width - 1), height: max(0, cell.rect.height - 1))
                .offset(x: cell.rect.minX + 0.5, y: cell.rect.minY + 0.5)
        }
    }

    private func formatSize(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
