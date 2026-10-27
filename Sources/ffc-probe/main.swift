import Foundation
import FanKit

// Dumps every fan key and every plausible temperature key the SMC exposes.
// Useful for finding the sensors that matter on a particular Mac.

do {
    let smc = try SMC()
    let keys = try smc.allKeys()
    print("SMC exposes \(keys.count) keys\n")

    let fanCount = (try? smc.readDouble("FNum")).map { Int($0) } ?? 0
    print("Fans: \(fanCount)")
    for k in keys.filter({ $0.hasPrefix("F") }).sorted() {
        guard let info = smc.info(for: k) else { continue }
        let value: String
        if let d = try? smc.readDouble(k) { value = String(format: "%.2f", d) }
        else if let (_, b) = try? smc.readBytes(k) { value = b.map { String(format: "%02x", $0) }.joined() }
        else { value = "?" }
        print("  \(k)  type=\(info.type) size=\(info.size)  \(value)")
    }

    print("\nTemperature-like keys (T*, numeric, 5...125):")
    for k in keys.filter({ $0.hasPrefix("T") }).sorted() {
        guard let info = smc.info(for: k), let d = try? smc.readDouble(k) else { continue }
        if d > 5, d < 125 {
            print("  \(k)  type=\(info.type)  \(String(format: "%6.1f", d))  \(SensorClassifier.group(for: k).rawValue)")
        }
    }
} catch {
    print("error: \(error)")
    exit(1)
}
