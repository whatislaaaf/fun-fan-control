import SwiftUI
import FanKit

/// Interactive temperature → fan level chart. The vertical axis is percent of the fan's own
/// min…max range, with the matching RPM for the selected fan shown on the right.
/// Drag points to move them, double-click empty space to add one, Delete removes the selection.
struct CurveChart: View {
    @Binding var curve: FanCurve
    @Binding var selected: UUID?
    let minRPM: Double
    let maxRPM: Double
    let liveTemp: Double?
    let liveRPM: Double?
    let safetyTemp: Double
    /// When true a level of 0 % means the fan is switched off, and the axis says so.
    var fanOffAtZero = false

    private let tempRange: ClosedRange<Double> = 20...110
    private let levelRange: ClosedRange<Double> = 0...1
    private let inset = EdgeInsets(top: 16, leading: 44, bottom: 30, trailing: 60)

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(
                x: inset.leading, y: inset.top,
                width: max(1, geo.size.width - inset.leading - inset.trailing),
                height: max(1, geo.size.height - inset.top - inset.bottom)
            )
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(ctx, plot: plot) }
                ForEach(curve.points) { p in
                    Circle()
                        .fill(selected == p.id ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: 13, height: 13)
                        .contentShape(Circle().inset(by: -6))
                        .position(position(of: p, in: plot))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    selected = p.id
                                    move(p.id, to: v.location, in: plot)
                                }
                        )
                        .help("\(Int(p.temp)) °C → \(Int(p.percent)) % (\(Int(FanCurve.rpm(forLevel: p.level, minRPM: minRPM, maxRPM: maxRPM))) RPM)")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { loc in add(at: loc, in: plot) }
            .onDeleteCommand { removeSelected() }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Editing

    func removeSelected() {
        guard let sel = selected, curve.points.count > 2 else { return }
        curve.points.removeAll { $0.id == sel }
        selected = nil
    }

    private func add(at loc: CGPoint, in plot: CGRect) {
        let t = min(max(temp(atX: loc.x, in: plot).rounded(), tempRange.lowerBound), tempRange.upperBound)
        let l = (level(atY: loc.y, in: plot) * 100).rounded() / 100
        let p = CurvePoint(temp: t, level: l)
        curve.points.append(p)
        curve.normalize()
        selected = p.id
    }

    private func move(_ id: UUID, to loc: CGPoint, in plot: CGRect) {
        let sorted = curve.sortedPoints
        guard let si = sorted.firstIndex(where: { $0.id == id }),
              let i = curve.points.firstIndex(where: { $0.id == id }) else { return }
        var lo = tempRange.lowerBound, hi = tempRange.upperBound
        if si > 0 { lo = sorted[si - 1].temp + 1 }
        if si < sorted.count - 1 { hi = sorted[si + 1].temp - 1 }
        curve.points[i].temp = min(max(temp(atX: loc.x, in: plot).rounded(), lo), hi)
        curve.points[i].level = min(max((level(atY: loc.y, in: plot) * 100).rounded() / 100, 0), 1)
    }

    // MARK: Coordinate mapping

    private func x(_ t: Double, _ plot: CGRect) -> CGFloat {
        plot.minX + CGFloat((t - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * plot.width
    }
    private func y(_ level: Double, _ plot: CGRect) -> CGFloat {
        plot.maxY - CGFloat(level) * plot.height
    }
    private func temp(atX px: CGFloat, in plot: CGRect) -> Double {
        tempRange.lowerBound + Double((px - plot.minX) / plot.width) * (tempRange.upperBound - tempRange.lowerBound)
    }
    private func level(atY py: CGFloat, in plot: CGRect) -> Double {
        Double((plot.maxY - py) / plot.height)
    }
    private func position(of p: CurvePoint, in plot: CGRect) -> CGPoint {
        CGPoint(x: x(p.temp, plot), y: y(p.level, plot))
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, plot: CGRect) {
        let grid = Color.secondary.opacity(0.18)
        let axisText = Color.secondary

        // Horizontal grid: every 10 % with a percent label on the left and the fan's RPM on the right.
        for step in stride(from: 0, through: 100, by: 10) {
            let l = Double(step) / 100
            let py = y(l, plot)
            var line = Path(); line.move(to: CGPoint(x: plot.minX, y: py)); line.addLine(to: CGPoint(x: plot.maxX, y: py))
            ctx.stroke(line, with: .color(grid), lineWidth: 1)
            if step % 20 == 0 {
                let off = fanOffAtZero && step == 0
                ctx.draw(Text(off ? "off" : "\(step) %").font(.caption2).foregroundColor(axisText), at: CGPoint(x: plot.minX - 6, y: py), anchor: .trailing)
                let rpm = Int(FanCurve.rpm(forLevel: l, minRPM: minRPM, maxRPM: maxRPM))
                ctx.draw(Text(off ? "off" : "\(rpm)").font(.caption2.monospacedDigit()).foregroundColor(axisText), at: CGPoint(x: plot.maxX + 6, y: py), anchor: .leading)
            }
        }
        ctx.draw(Text("RPM").font(.caption2).foregroundColor(axisText), at: CGPoint(x: plot.maxX + 6, y: plot.minY - 8), anchor: .leading)

        // Vertical grid (°C)
        var t = tempRange.lowerBound
        while t <= tempRange.upperBound {
            let px = x(t, plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(grid), lineWidth: 1)
            ctx.draw(Text("\(Int(t))°").font(.caption2).foregroundColor(axisText), at: CGPoint(x: px, y: plot.maxY + 12), anchor: .center)
            t += 10
        }

        // Safety line
        if tempRange.contains(safetyTemp) {
            let px = x(safetyTemp, plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(.red.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ctx.draw(Text("max").font(.caption2).foregroundColor(.red), at: CGPoint(x: px, y: plot.minY - 8), anchor: .center)
        }

        // Curve
        let pts = curve.sortedPoints
        if let first = pts.first, let last = pts.last {
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y(first.level, plot)))
            for p in pts { path.addLine(to: position(of: p, in: plot)) }
            path.addLine(to: CGPoint(x: plot.maxX, y: y(last.level, plot)))

            var fill = path
            fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
            ctx.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }

        // Live marker: where this fan is right now
        if let lt = liveTemp {
            let px = x(min(max(lt, tempRange.lowerBound), tempRange.upperBound), plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(.orange.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            ctx.draw(Text(String(format: "now %.0f°", lt)).font(.caption2.weight(.semibold)).foregroundColor(.orange),
                     at: CGPoint(x: px, y: plot.minY + 8), anchor: .center)
            if let lr = liveRPM {
                let ll = FanCurve.level(forRPM: lr, minRPM: minRPM, maxRPM: maxRPM)
                let dot = CGRect(x: px - 5, y: y(ll, plot) - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: dot), with: .color(.orange))
                ctx.draw(Text("\(Int(lr)) RPM · \(Int(ll * 100)) %").font(.caption2).foregroundColor(.orange),
                         at: CGPoint(x: dot.midX + 10, y: dot.midY), anchor: .leading)
            }
        }
    }
}
