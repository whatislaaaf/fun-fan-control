import Foundation

/// One point on a fan curve. `level` is a fraction (0…1) of the fan's own min…max RPM range,
/// so a shared curve drives fans with different maximum speeds at the same relative effort.
public struct CurvePoint: Equatable, Hashable, Identifiable {
    public var id: UUID
    public var temp: Double    // °C
    public var level: Double   // 0…1 of the fan's range
    /// Set only when decoding an old settings file that stored absolute RPM; cleared by `FanCurve.migrate`.
    public var legacyRPM: Double?

    public init(temp: Double, level: Double) {
        id = UUID()
        self.temp = temp
        self.level = min(max(level, 0), 1)
    }

    public var percent: Double {
        get { level * 100 }
        set { level = min(max(newValue / 100, 0), 1) }
    }
}

extension CurvePoint: Codable {
    enum CodingKeys: String, CodingKey { case id, temp, level, rpm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        temp = try c.decode(Double.self, forKey: .temp)
        if let l = try c.decodeIfPresent(Double.self, forKey: .level) {
            level = min(max(l, 0), 1)
        } else {
            level = 0
            legacyRPM = try c.decodeIfPresent(Double.self, forKey: .rpm)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(temp, forKey: .temp)
        try c.encode(level, forKey: .level)
    }
}

/// A piecewise-linear temperature → fan level mapping.
public struct FanCurve: Codable, Equatable {
    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points
        normalize()
    }

    public var sortedPoints: [CurvePoint] { points.sorted { $0.temp < $1.temp } }

    public mutating func normalize() { points.sort { $0.temp < $1.temp } }

    /// Linear interpolation between points; flat beyond the first and last point. Returns 0…1.
    public func level(at temp: Double) -> Double {
        let pts = sortedPoints
        guard let first = pts.first, let last = pts.last else { return 0 }
        if temp <= first.temp { return first.level }
        if temp >= last.temp { return last.level }
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            if temp <= b.temp {
                let span = b.temp - a.temp
                if span <= 0 { return b.level }
                return a.level + (b.level - a.level) * ((temp - a.temp) / span)
            }
        }
        return last.level
    }

    /// The RPM a particular fan should run at for this temperature.
    public func rpm(at temp: Double, minRPM: Double, maxRPM: Double) -> Double {
        FanCurve.rpm(forLevel: level(at: temp), minRPM: minRPM, maxRPM: maxRPM)
    }

    public static func rpm(forLevel level: Double, minRPM: Double, maxRPM: Double) -> Double {
        minRPM + (max(maxRPM, minRPM) - minRPM) * min(max(level, 0), 1)
    }

    public static func level(forRPM rpm: Double, minRPM: Double, maxRPM: Double) -> Double {
        let range = max(maxRPM, minRPM) - minRPM
        guard range > 0 else { return 0 }
        return min(max((rpm - minRPM) / range, 0), 1)
    }

    // MARK: Migration from RPM-based curves

    public var needsMigration: Bool { points.contains { $0.legacyRPM != nil } }

    /// Converts points that were stored as absolute RPM into levels using the given fan range.
    public mutating func migrate(minRPM: Double, maxRPM: Double) {
        for i in points.indices {
            if let rpm = points[i].legacyRPM {
                points[i].level = FanCurve.level(forRPM: rpm, minRPM: minRPM, maxRPM: maxRPM)
                points[i].legacyRPM = nil
            }
        }
    }

    // MARK: Presets

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

    public static func preset(_ p: Preset) -> FanCurve {
        let shape: [(Double, Double)]
        switch p {
        case .quiet:    shape = [(45, 0), (62, 0), (75, 0.3), (88, 0.65), (98, 1)]
        case .balanced: shape = [(40, 0), (55, 0.12), (70, 0.4), (85, 0.8), (95, 1)]
        case .cool:     shape = [(35, 0.1), (50, 0.35), (65, 0.65), (80, 0.9), (90, 1)]
        }
        return FanCurve(points: shape.map { CurvePoint(temp: $0.0, level: $0.1) })
    }
}
