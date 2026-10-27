import Foundation

/// Coarse grouping of temperature sensor keys, used to pick which sensors drive a curve.
public enum SensorGroup: String, Codable, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case battery = "Battery"
    case skin = "Chassis / skin"
    case ambient = "Ambient"
    case other = "Other"
}

public enum SensorClassifier {
    /// Classifies an SMC temperature key by its naming convention.
    /// Covers Intel (TC*/TG*), M1/M2 (Tp*/Tg*), M3 (Te*/Tf*), M4 (Te*/Tp*/Tg*).
    public static func group(for key: String) -> SensorGroup {
        guard key.count == 4, key.hasPrefix("T") else { return .other }
        let c = Array(key)
        switch c[1] {
        case "g", "G": return .gpu
        case "f":
            // M3: Tf1x / Tf2x are GPU clusters, Tf0x / Tf4x are CPU clusters.
            return (c[2] == "1" || c[2] == "2") ? .gpu : .cpu
        case "p", "C", "e", "c": return .cpu
        case "m", "M": return .memory
        case "B", "b": return .battery
        case "s", "S":
            // Ts0P / Ts1P / TS0P style keys are palm-rest / skin proximity sensors.
            return c[3] == "P" ? .skin : .other
        case "A", "a": return .ambient
        default: return .other
        }
    }
}

/// Which temperature drives a fan curve.
public enum TempSource: String, Codable, CaseIterable, Identifiable {
    case cpu, gpu, cpuOrGpu, custom
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .cpuOrGpu: return "Hottest of CPU / GPU"
        case .custom: return "Custom sensors"
        }
    }
}

/// How several sensors in a group are combined into one number.
public enum Aggregation: String, Codable, CaseIterable, Identifiable {
    case max, average
    public var id: String { rawValue }
    public var label: String { self == .max ? "Hottest sensor" : "Average" }
}

public extension Array where Element == TemperatureReading {
    func aggregate(_ readings: [TemperatureReading], _ agg: Aggregation) -> Double? {
        guard !readings.isEmpty else { return nil }
        switch agg {
        case .max: return readings.map(\.celsius).max()
        case .average: return readings.map(\.celsius).reduce(0, +) / Double(readings.count)
        }
    }
    func value(for group: SensorGroup, aggregation: Aggregation) -> Double? {
        aggregate(filter { $0.group == group }, aggregation)
    }
    func value(keys: [String], aggregation: Aggregation) -> Double? {
        let set = Set(keys)
        return aggregate(filter { set.contains($0.key) }, aggregation)
    }
}

public struct TemperatureReading: Identifiable, Equatable {
    public let key: String
    public let group: SensorGroup
    public let celsius: Double
    public var id: String { key }
}

public struct FanReading: Identifiable, Equatable {
    public let index: Int
    public let name: String
    public let actualRPM: Double
    public let minRPM: Double
    public let maxRPM: Double
    public let targetRPM: Double?
    /// true when the fan is under manual (forced) control.
    public let forced: Bool
    public var id: Int { index }
}

/// Reads fans and temperatures from the SMC. Create on a background queue and keep using it there.
public final class SensorReader {
    public let smc: SMC
    public let fanCount: Int
    private let fanNames: [String]
    /// Temperature keys that returned a plausible value at startup.
    public private(set) var temperatureKeys: [String]

    public init() throws {
        smc = try SMC()
        fanCount = (try? smc.readDouble("FNum")).map { Int($0) } ?? 0

        var names: [String] = []
        for i in 0..<fanCount {
            let idKey = "F\(i)ID"
            var name = ""
            if smc.hasKey(idKey), let s = try? smc.readString(idKey), !s.isEmpty {
                // Intel stores a 16-byte descriptor: 4 bytes of metadata then the name.
                name = String(s.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { name = s }
            }
            if name.isEmpty {
                name = fanCount == 2 ? (i == 0 ? "Left fan" : "Right fan") : "Fan \(i + 1)"
            }
            names.append(name)
        }
        fanNames = names

        let smc = self.smc
        let keys = (try? smc.allKeys()) ?? []
        temperatureKeys = keys.filter { k in
            guard k.hasPrefix("T"), let info = smc.info(for: k) else { return false }
            guard info.type == "flt " || info.type == "sp78" || info.type.hasPrefix("sp") || info.type.hasPrefix("fp") else { return false }
            guard let v = try? smc.readDouble(k) else { return false }
            return v > 5 && v < 125
        }.sorted()
    }

    public func readFans() -> [FanReading] {
        (0..<fanCount).map { i in
            let actual = (try? smc.readDouble("F\(i)Ac")) ?? 0
            let mn = (try? smc.readDouble("F\(i)Mn")) ?? 0
            let mx = (try? smc.readDouble("F\(i)Mx")) ?? 0
            let tg = try? smc.readDouble("F\(i)Tg")
            let forced = Self.isForced(smc: smc, fan: i)
            return FanReading(index: i, name: fanNames[i], actualRPM: actual, minRPM: mn, maxRPM: mx, targetRPM: tg, forced: forced)
        }
    }

    /// True only when the fan is under manual control (mode 1). Apple Silicon firmware uses
    /// other non-zero mode values for its own states, e.g. 3 while it has idled the fan to 0 RPM.
    public static func isForced(smc: SMC, fan i: Int) -> Bool {
        if smc.hasKey("F\(i)Md"), let md = try? smc.readDouble("F\(i)Md") { return Int(md) == 1 }
        if smc.hasKey("FS! "), let fs = try? smc.readDouble("FS! ") { return (Int(fs) & (1 << i)) != 0 }
        return false
    }

    public func readTemperatures() -> [TemperatureReading] {
        temperatureKeys.compactMap { k in
            guard let v = try? smc.readDouble(k), v > -20, v < 150 else { return nil }
            return TemperatureReading(key: k, group: SensorClassifier.group(for: k), celsius: v)
        }
    }
}
