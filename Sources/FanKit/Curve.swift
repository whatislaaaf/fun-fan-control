import Foundation

public struct CurvePoint: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var temp: Double   // °C
    public var rpm: Double
    public init(temp: Double, rpm: Double) {
        id = UUID()
        self.temp = temp
        self.rpm = rpm
    }
}

/// A piecewise-linear temperature → RPM mapping.
public struct FanCurve: Codable, Equatable {
    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points
        normalize()
    }

    public var sortedPoints: [CurvePoint] { points.sorted { $0.temp < $1.temp } }

    public mutating func normalize() { points.sort { $0.temp < $1.temp } }

    /// Linear interpolation between points; flat beyond the first and last point.
    public func rpm(at temp: Double) -> Double {
        let pts = sortedPoints
        guard let first = pts.first, let last = pts.last else { return 0 }
        if temp <= first.temp { return first.rpm }
        if temp >= last.temp { return last.rpm }
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            if temp <= b.temp {
                let span = b.temp - a.temp
                if span <= 0 { return b.rpm }
                return a.rpm + (b.rpm - a.rpm) * ((temp - a.temp) / span)
            }
        }
        return last.rpm
    }

    public enum Preset: String, CaseIterable, Identifiable {
        case quiet = "Quiet", balanced = "Balanced", cool = "Cool to the touch"
        public var id: String { rawValue }
        public var summary: String {
            switch self {
            case .quiet: return "Fans stay at minimum until the chip is genuinely hot."
            case .balanced: return "Gentle ramp from 55 °C, full speed near 95 °C."
            case .cool: return "Starts spinning up early to keep the chassis cool."
            }
        }
    }

    /// Builds a preset scaled to a fan's RPM range.
    public static func preset(_ p: Preset, minRPM: Double, maxRPM: Double) -> FanCurve {
        let shape: [(Double, Double)]
        switch p {
        case .quiet:    shape = [(45, 0), (62, 0), (75, 0.3), (88, 0.65), (98, 1)]
        case .balanced: shape = [(40, 0), (55, 0.12), (70, 0.4), (85, 0.8), (95, 1)]
        case .cool:     shape = [(35, 0.1), (50, 0.35), (65, 0.65), (80, 0.9), (90, 1)]
        }
        let range = max(0, maxRPM - minRPM)
        return FanCurve(points: shape.map { CurvePoint(temp: $0.0, rpm: (minRPM + range * $0.1).rounded()) })
    }
}
