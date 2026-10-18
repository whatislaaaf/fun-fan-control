import SwiftUI

/// Visual language shared by the dropdown and the curve window.
enum Theme {
    static let cardRadius: CGFloat = 14
    static let cardFill = Color.primary.opacity(0.055)
    static let cardStroke = Color.primary.opacity(0.08)

    static let cool = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let warm = Color(red: 1.0, green: 0.62, blue: 0.22)
    static let hot = Color(red: 1.0, green: 0.33, blue: 0.36)

    /// Blue → orange → red for a 0…1 effort level.
    static func heat(_ p: Double) -> Color {
        let p = min(max(p, 0), 1)
        if p < 0.6 { return mix(cool, warm, p / 0.6) }
        return mix(warm, hot, (p - 0.6) / 0.4)
    }

    /// Color for a temperature reading in °C.
    static func temperature(_ c: Double) -> Color {
        if c >= 88 { return hot }
        if c >= 72 { return warm }
        if c >= 55 { return mix(cool, warm, (c - 55) / 17) }
        return cool
    }

    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let t = min(max(t, 0), 1)
        let ca = NSColor(a).usingColorSpace(.sRGB) ?? .white
        let cb = NSColor(b).usingColorSpace(.sRGB) ?? .white
        return Color(red: Double(ca.redComponent) + (Double(cb.redComponent) - Double(ca.redComponent)) * t,
                     green: Double(ca.greenComponent) + (Double(cb.greenComponent) - Double(ca.greenComponent)) * t,
                     blue: Double(ca.blueComponent) + (Double(cb.blueComponent) - Double(ca.blueComponent)) * t)
    }

    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

/// Small uppercase caption used as a section heading.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Capsule status pill.
struct Pill: View {
    let text: String
    let color: Color
    var filled = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(filled ? 0.22 : 0.12)))
        .foregroundStyle(filled ? color : .primary)
    }
}

/// Compact stat chip: icon, label and a value in a rounded font.
struct StatChip: View {
    let label: String
    let value: String
    let color: Color
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.caption2) }
                Text(label).font(.caption2.weight(.medium))
            }
            .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.rounded(.title3, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.10)))
    }
}

/// 270° arc gauge with a glowing progress stroke and arbitrary centre content.
struct ArcGauge<Center: View>: View {
    let progress: Double      // 0…1
    var isOff = false
    var lineWidth: CGFloat = 9
    @ViewBuilder var center: () -> Center

    private let start = Angle.degrees(135)
    private let sweep = 270.0

    var body: some View {
        let p = min(max(progress, 0), 1)
        let tint = isOff ? Color.secondary : Theme.heat(p)
        ZStack {
            Circle()
                .trim(from: 0, to: sweep / 360)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(start)
            if p > 0.001 && !isOff {
                Circle()
                    .trim(from: 0, to: (sweep / 360) * p)
                    .stroke(
                        AngularGradient(colors: [Theme.cool, Theme.heat(p)], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(sweep * p)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(start)
                    .shadow(color: tint.opacity(0.55), radius: 6)
                    .animation(.easeOut(duration: 0.6), value: p)
            }
            center()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
