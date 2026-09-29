import SwiftUI

// MARK: - Theme Colors

public enum ThemeColor {
    public static let primary = Color(red: 0.29, green: 0.56, blue: 0.85)
    public static let accent = Color(red: 0.48, green: 0.41, blue: 0.93)
    public static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
    public static let warning = Color(red: 1.00, green: 0.58, blue: 0.00)
    public static let danger = Color(red: 1.00, green: 0.23, blue: 0.19)

    public static let background = Color(nsColor: .windowBackgroundColor)
    public static let sidebarBackground = Color(nsColor: .controlBackgroundColor)
    public static let cardBackground = Color(nsColor: .textBackgroundColor)
    public static let secondaryText = Color.secondary
}

// MARK: - Circular Progress Gauge

public struct CircularProgressGauge: View {
    public let value: Double
    public let label: String
    public let color: Color
    public let lineWidth: CGFloat

    public init(value: Double, label: String, color: Color = ThemeColor.primary, lineWidth: CGFloat = 12) {
        self.value = min(max(value, 0), 100)
        self.label = label
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: value / 100)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.7), color]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: value)

                VStack(spacing: 2) {
                    Text("\(Int(value))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(ThemeColor.primary)
                }
            }
            .frame(width: 120, height: 120)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(ThemeColor.secondaryText)
        }
    }
}

// MARK: - Storage Bar

public struct StorageBar: View {
    public let used: Double
    public let total: Double

    public init(used: Double, total: Double) {
        self.used = used
        self.total = total
    }

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return (used / total) * 100
    }

    private var barColor: Color {
        switch percentage {
        case ..<60: return ThemeColor.success
        case ..<80: return ThemeColor.warning
        default: return ThemeColor.danger
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(formattedSize(used)) used of \(formattedSize(total))")
                    .font(.footnote)
                    .foregroundStyle(ThemeColor.secondaryText)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(barColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.8), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * percentage / 100, height: 8)
                        .animation(.easeInOut(duration: 0.6), value: percentage)
                }
            }
            .frame(height: 8)
        }
    }

    private func formattedSize(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Category Card

public struct CategoryCard<Content: View>: View {
    public let title: String
    public let subtitle: String?
    @ViewBuilder public let content: () -> Content

    public init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Spacer()
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ThemeColor.secondaryText)
                }
            }
            content()
        }
        .padding(16)
        .background(ThemeColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - Section Header

public struct SectionHeader: View {
    public let title: String
    public let systemIcon: String?

    public init(title: String, systemIcon: String? = nil) {
        self.title = title
        self.systemIcon = systemIcon
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let systemIcon {
                Image(systemName: systemIcon)
                    .foregroundStyle(ThemeColor.primary)
            }
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }
}
