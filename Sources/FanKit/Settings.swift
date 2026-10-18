import Foundation

public struct AppSettings: Codable, Equatable {
    public var controlEnabled = false
    public var sharedCurve = true
    /// One curve per fan index. With `sharedCurve` only index 0 is used.
    public var curves: [FanCurve] = []
    public var source: TempSource = .cpuOrGpu
    public var customKeys: [String] = []
    public var aggregation: Aggregation = .max
    public var intervalSeconds: Double = 2
    /// Largest RPM change per tick when speeding up / slowing down (smooths out fan noise).
    public var maxStepUp: Double = 400
    public var maxStepDown: Double = 150
    /// Changes smaller than this are not sent to the fan.
    public var deadbandRPM: Double = 50
    /// Above this source temperature every fan is forced to its maximum, whatever the curve says.
    public var safetyTemp: Double = 98
    /// When on, a curve level of exactly 0 % switches the fan off instead of running it at its minimum.
    public var allowFanOff = false
    public var showTempInMenuBar = true
    public var showRPMInMenuBar = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case controlEnabled, sharedCurve, curves, source, customKeys, aggregation, intervalSeconds
        case maxStepUp, maxStepDown, deadbandRPM, safetyTemp, allowFanOff, showTempInMenuBar, showRPMInMenuBar
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        controlEnabled = try c.decodeIfPresent(Bool.self, forKey: .controlEnabled) ?? controlEnabled
        sharedCurve = try c.decodeIfPresent(Bool.self, forKey: .sharedCurve) ?? sharedCurve
        curves = try c.decodeIfPresent([FanCurve].self, forKey: .curves) ?? curves
        source = try c.decodeIfPresent(TempSource.self, forKey: .source) ?? source
        customKeys = try c.decodeIfPresent([String].self, forKey: .customKeys) ?? customKeys
        aggregation = try c.decodeIfPresent(Aggregation.self, forKey: .aggregation) ?? aggregation
        intervalSeconds = try c.decodeIfPresent(Double.self, forKey: .intervalSeconds) ?? intervalSeconds
        maxStepUp = try c.decodeIfPresent(Double.self, forKey: .maxStepUp) ?? maxStepUp
        maxStepDown = try c.decodeIfPresent(Double.self, forKey: .maxStepDown) ?? maxStepDown
        deadbandRPM = try c.decodeIfPresent(Double.self, forKey: .deadbandRPM) ?? deadbandRPM
        safetyTemp = try c.decodeIfPresent(Double.self, forKey: .safetyTemp) ?? safetyTemp
        allowFanOff = try c.decodeIfPresent(Bool.self, forKey: .allowFanOff) ?? allowFanOff
        showTempInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showTempInMenuBar) ?? showTempInMenuBar
        showRPMInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showRPMInMenuBar) ?? showRPMInMenuBar
    }

    // MARK: Curves

    public func curve(for fan: Int) -> FanCurve? {
        let idx = sharedCurve ? 0 : fan
        return curves.indices.contains(idx) ? curves[idx] : nil
    }

    public mutating func setCurve(_ curve: FanCurve, for fan: Int) {
        let idx = sharedCurve ? 0 : fan
        while curves.count <= idx { curves.append(curve) }
        curves[idx] = curve
    }

    /// Makes sure there is a curve for every fan, seeding missing ones with the Balanced preset,
    /// and converts curves saved by older versions (absolute RPM) into percent-of-range curves.
    public mutating func ensureCurves(for fans: [FanReading]) {
        for fan in fans where !curves.indices.contains(fan.index) {
            curves.append(FanCurve.preset(.balanced))
        }
        for i in curves.indices where curves[i].needsMigration {
            let fan = fans.first(where: { $0.index == i }) ?? fans.first
            curves[i].migrate(minRPM: fan?.minRPM ?? 0, maxRPM: fan?.maxRPM ?? 1)
        }
    }

    public var curvesNeedMigration: Bool { curves.contains { $0.needsMigration } }

    /// The temperature that drives the curve, according to `source`.
    public func sourceTemperature(from temps: [TemperatureReading]) -> Double? {
        switch source {
        case .cpu: return temps.value(for: .cpu, aggregation: aggregation)
        case .gpu: return temps.value(for: .gpu, aggregation: aggregation)
        case .cpuOrGpu:
            let vals = [temps.value(for: .cpu, aggregation: aggregation), temps.value(for: .gpu, aggregation: aggregation)].compactMap { $0 }
            return vals.max()
        case .custom: return temps.value(keys: customKeys, aggregation: aggregation)
        }
    }
}

public enum SettingsStore {
    public static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Fun Fan Control", isDirectory: true).appendingPathComponent("settings.json")
    }

    public static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    public static func save(_ settings: AppSettings) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Fun Fan Control: could not save settings: \(error)")
        }
    }
}
