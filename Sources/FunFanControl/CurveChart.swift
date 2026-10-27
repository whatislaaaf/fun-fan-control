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
    private let inset = EdgeInsets(top: 22, leading: 44, bottom: 30, trailing: 58)

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
                    let isSel = selected == p.id
                    Circle()
                        .fill(Theme.heat(p.level))
                        .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: isSel ? 3 : 2))
                        .frame(width: isSel ? 16 : 13, height: isSel ? 16 : 13)
                        .shadow(color: Theme.heat(p.level).opacity(isSel ? 0.8 : 0.45), radius: isSel ? 8 : 4)
                        .contentShape(Circle().inset(by: -8))
                        .position(position(of: p, in: plot))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    selected = p.id
                                    move(p.id, to: v.location, in: plot)
                                }
                        )
                        .help("\(Int(p.temp)) °C → \(Int(p.percent)) % (\(Int(FanCurve.rpm(forLevel: p.level, minRPM: minRPM, maxRPM: maxRPM))) RPM)")
                        .animation(.easeOut(duration: 0.15), value: isSel)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { loc in add(at: loc, in: plot) }
            .onDeleteCommand { removeSelected() }
        }
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
        let grid = Color.primary.opacity(0.07)
        let axisText = Color.secondary
        let heatGradient = Gradient(stops: [
            .init(color: Theme.cool, location: 0),
            .init(color: Theme.warm, location: 0.62),
            .init(color: Theme.hot, location: 1),
        ])

        // Plot background
        ctx.fill(Path(roundedRect: plot.insetBy(dx: -6, dy: -6), cornerRadius: 10), with: .color(Color.primary.opacity(0.03)))

        // Horizontal grid: every 10 %, labels every 20 % (percent left, this fan's RPM right).
        for step in stride(from: 0, through: 100, by: 10) {
            let l = Double(step) / 100
            let py = y(l, plot)
            var line = Path(); line.move(to: CGPoint(x: plot.minX, y: py)); line.addLine(to: CGPoint(x: plot.maxX, y: py))
            ctx.stroke(line, with: .color(grid), style: StrokeStyle(lineWidth: 1, dash: step % 20 == 0 ? [] : [2, 4]))
            if step % 20 == 0 {
                let off = fanOffAtZero && step == 0
                ctx.draw(Text(off ? "off" : "\(step) %").font(.caption2.weight(.medium)).foregroundColor(axisText), at: CGPoint(x: plot.minX - 8, y: py), anchor: .trailing)
                let rpm = Int(FanCurve.rpm(forLevel: l, minRPM: minRPM, maxRPM: maxRPM))
                ctx.draw(Text(off ? "off" : "\(rpm)").font(.caption2.monospacedDigit()).foregroundColor(axisText), at: CGPoint(x: plot.maxX + 10, y: py), anchor: .leading)
            }
        }
        ctx.draw(Text("RPM").font(.caption2.weight(.semibold)).foregroundColor(axisText), at: CGPoint(x: plot.maxX + 10, y: plot.minY - 12), anchor: .leading)

        // Vertical grid (°C)
        var t = tempRange.lowerBound
        while t <= tempRange.upperBound {
            let px = x(t, plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(grid), lineWidth: 1)
            ctx.draw(Text("\(Int(t))°").font(.caption2.weight(.medium)).foregroundColor(axisText), at: CGPoint(x: px, y: plot.maxY + 13), anchor: .center)
            t += 10
        }

        // Safety line
        if tempRange.contains(safetyTemp) {
            let px = x(safetyTemp, plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(Theme.hot.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ctx.draw(Text("full speed").font(.caption2.weight(.semibold)).foregroundColor(Theme.hot), at: CGPoint(x: px, y: plot.minY - 10), anchor: .center)
        }

        // Curve: area fill and stroke, both coloured by temperature along the x axis.
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
            let shading = GraphicsContext.Shading.linearGradient(
                heatGradient, startPoint: CGPoint(x: plot.minX, y: 0), endPoint: CGPoint(x: plot.maxX, y: 0))
            var area = ctx
            area.opacity = 0.22
            area.fill(fill, with: shading)
            ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }

        // Live marker: where this fan is right now.
        if let lt = liveTemp {
            let px = x(min(max(lt, tempRange.lowerBound), tempRange.upperBound), plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(Color.primary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            let label = Text(String(format: "now %.0f°", lt)).font(.caption2.weight(.bold)).foregroundColor(.primary)
            ctx.draw(label, at: CGPoint(x: px, y: plot.minY - 10), anchor: .center)
            if let lr = liveRPM {
                let ll = FanCurve.level(forRPM: lr, minRPM: minRPM, maxRPM: maxRPM)
                let c = CGPoint(x: px, y: y(ll, plot))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)), with: .color(Theme.heat(ll).opacity(0.25)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(Theme.heat(ll)))
                let txt = lr < 1 ? "fan off" : "\(Int(lr)) RPM · \(Int(ll * 100)) %"
                ctx.draw(Text(txt).font(.caption2.weight(.semibold)).foregroundColor(.primary), at: CGPoint(x: c.x + 12, y: c.y), anchor: .leading)
            }
        }
    }
}
