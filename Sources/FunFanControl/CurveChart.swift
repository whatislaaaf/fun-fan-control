import SwiftUI
import FanKit

/// Interactive temperature → RPM chart. Drag points to move them, double-click empty space to add one.
struct CurveChart: View {
    @Binding var curve: FanCurve
    @Binding var selected: UUID?
    let minRPM: Double
    let maxRPM: Double
    let liveTemp: Double?
    let liveRPM: Double?
    let safetyTemp: Double

    private let tempRange: ClosedRange<Double> = 20...110
    private var rpmRange: ClosedRange<Double> { 0...(ceil(maxRPM / 500) * 500 + 250) }
    private let inset = EdgeInsets(top: 14, leading: 52, bottom: 30, trailing: 18)

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
                        .help("\(Int(p.temp)) °C → \(Int(p.rpm)) RPM")
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
        let t = (temp(atX: loc.x, in: plot)).rounded()
        let r = ((rpm(atY: loc.y, in: plot)) / 10).rounded() * 10
        let p = CurvePoint(temp: min(max(t, tempRange.lowerBound), tempRange.upperBound),
                           rpm: min(max(r, minRPM), maxRPM))
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
        let t = min(max(temp(atX: loc.x, in: plot).rounded(), lo), hi)
        let r = min(max((rpm(atY: loc.y, in: plot) / 10).rounded() * 10, minRPM), maxRPM)
        curve.points[i].temp = t
        curve.points[i].rpm = r
    }

    // MARK: Coordinate mapping

    private func x(_ t: Double, _ plot: CGRect) -> CGFloat {
        plot.minX + CGFloat((t - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * plot.width
    }
    private func y(_ r: Double, _ plot: CGRect) -> CGFloat {
        plot.maxY - CGFloat((r - rpmRange.lowerBound) / (rpmRange.upperBound - rpmRange.lowerBound)) * plot.height
    }
    private func temp(atX px: CGFloat, in plot: CGRect) -> Double {
        tempRange.lowerBound + Double((px - plot.minX) / plot.width) * (tempRange.upperBound - tempRange.lowerBound)
    }
    private func rpm(atY py: CGFloat, in plot: CGRect) -> Double {
        rpmRange.lowerBound + Double((plot.maxY - py) / plot.height) * (rpmRange.upperBound - rpmRange.lowerBound)
    }
    private func position(of p: CurvePoint, in plot: CGRect) -> CGPoint {
        CGPoint(x: x(p.temp, plot), y: y(p.rpm, plot))
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, plot: CGRect) {
        let grid = Color.secondary.opacity(0.18)
        let axisText = Color.secondary

        // Horizontal grid (RPM)
        var r = rpmRange.lowerBound
        while r <= rpmRange.upperBound {
            let py = y(r, plot)
            var line = Path(); line.move(to: CGPoint(x: plot.minX, y: py)); line.addLine(to: CGPoint(x: plot.maxX, y: py))
            ctx.stroke(line, with: .color(grid), lineWidth: 1)
            ctx.draw(Text("\(Int(r))").font(.caption2).foregroundColor(axisText), at: CGPoint(x: plot.minX - 8, y: py), anchor: .trailing)
            r += 1000
        }
        // Vertical grid (°C)
        var t = tempRange.lowerBound
        while t <= tempRange.upperBound {
            let px = x(t, plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(grid), lineWidth: 1)
            ctx.draw(Text("\(Int(t))°").font(.caption2).foregroundColor(axisText), at: CGPoint(x: px, y: plot.maxY + 12), anchor: .center)
            t += 10
        }

        // Fan min / max bands
        let bandColor = Color.secondary.opacity(0.08)
        ctx.fill(Path(CGRect(x: plot.minX, y: y(minRPM, plot), width: plot.width, height: plot.maxY - y(minRPM, plot))), with: .color(bandColor))
        ctx.fill(Path(CGRect(x: plot.minX, y: plot.minY, width: plot.width, height: y(maxRPM, plot) - plot.minY)), with: .color(bandColor))
        ctx.draw(Text("fan min").font(.caption2).foregroundColor(axisText), at: CGPoint(x: plot.maxX - 4, y: y(minRPM, plot) + 8), anchor: .trailing)
        ctx.draw(Text("fan max").font(.caption2).foregroundColor(axisText), at: CGPoint(x: plot.maxX - 4, y: y(maxRPM, plot) - 8), anchor: .trailing)

        // Safety line
        if tempRange.contains(safetyTemp) {
            let px = x(safetyTemp, plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(.red.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ctx.draw(Text("max").font(.caption2).foregroundColor(.red), at: CGPoint(x: px, y: plot.minY - 6), anchor: .center)
        }

        // Curve
        let pts = curve.sortedPoints
        if let first = pts.first, let last = pts.last {
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y(first.rpm, plot)))
            for p in pts { path.addLine(to: position(of: p, in: plot)) }
            path.addLine(to: CGPoint(x: plot.maxX, y: y(last.rpm, plot)))

            var fill = path
            fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
            ctx.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }

        // Live marker: where the machine is right now
        if let lt = liveTemp {
            let px = x(min(max(lt, tempRange.lowerBound), tempRange.upperBound), plot)
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(.orange.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            ctx.draw(Text(String(format: "now %.0f°", lt)).font(.caption2.weight(.semibold)).foregroundColor(.orange),
                     at: CGPoint(x: px, y: plot.minY + 8), anchor: .center)
            if let lr = liveRPM {
                let dot = CGRect(x: px - 5, y: y(min(max(lr, rpmRange.lowerBound), rpmRange.upperBound), plot) - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: dot), with: .color(.orange))
                ctx.draw(Text("\(Int(lr)) RPM").font(.caption2).foregroundColor(.orange),
                         at: CGPoint(x: dot.midX + 10, y: dot.midY), anchor: .leading)
            }
        }
    }
}
