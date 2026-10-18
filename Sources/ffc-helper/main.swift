import Foundation
import FanKit

// ffc-helper: the only part of Fun Fan Control that writes to the SMC.
// It is installed setuid root by the app and accepts a deliberately tiny command set.

let usage = """
usage: ffc-helper set <fan> <rpm> [<fan> <rpm> ...]   force fans to a target RPM
       ffc-helper auto                                return all fans to automatic control
       ffc-helper status                              print fan modes and targets
"""

func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { fail(usage, code: 2) }

if cmd == "status" || geteuid() == 0 {
    if geteuid() == 0 { setuid(0) }
} else {
    fail("ffc-helper must run as root. Install it from the app (Settings → Install helper) or run it with sudo.", code: 3)
}

let smc: SMC
let fanCount: Int
do {
    smc = try SMC()
    fanCount = Int(try smc.readDouble("FNum"))
} catch {
    fail("SMC unavailable: \(error)", code: 4)
}

func setMode(_ i: Int, forced: Bool) throws {
    let md = "F\(i)Md"
    if smc.hasKey(md) {
        try smc.writeDouble(md, forced ? 1 : 0)
    } else if smc.hasKey("FS! ") {
        // Older Intel Macs use a bitmask instead of a per-fan mode key.
        var bits = Int(try smc.readDouble("FS! "))
        if forced { bits |= 1 << i } else { bits &= ~(1 << i) }
        try smc.writeDouble("FS! ", Double(bits))
    } else {
        throw SMCError.keyNotFound(md)
    }
}

func printStatus() {
    for i in 0..<fanCount {
        let forced = SensorReader.isForced(smc: smc, fan: i)
        let actual = (try? smc.readDouble("F\(i)Ac")) ?? 0
        let target = (try? smc.readDouble("F\(i)Tg")) ?? 0
        print("fan \(i): mode=\(forced ? "forced" : "auto") actual=\(Int(actual)) target=\(Int(target))")
    }
}

do {
    switch cmd {
    case "set":
        let rest = Array(args.dropFirst())
        guard !rest.isEmpty, rest.count % 2 == 0 else { fail(usage, code: 2) }
        var pairs: [(Int, Double)] = []
        for i in stride(from: 0, to: rest.count, by: 2) {
            guard let fan = Int(rest[i]), fan >= 0, fan < fanCount else { fail("invalid fan index \(rest[i]) (have \(fanCount) fans)", code: 2) }
            guard let rpm = Double(rest[i + 1]), rpm.isFinite, rpm >= 0 else { fail("invalid rpm \(rest[i + 1])", code: 2) }
            pairs.append((fan, rpm))
        }
        for (fan, rpm) in pairs {
            let mn = (try? smc.readDouble("F\(fan)Mn")) ?? 0
            let mx = (try? smc.readDouble("F\(fan)Mx")) ?? 10000
            let clamped = min(max(rpm, mn), mx)
            try setMode(fan, forced: true)
            try smc.writeDouble("F\(fan)Tg", clamped)
            print("fan \(fan): forced target=\(Int(clamped))")
        }
    case "auto":
        for i in 0..<fanCount { try setMode(i, forced: false) }
        print("all fans: auto")
    case "status":
        printStatus()
    default:
        fail(usage, code: 2)
    }
} catch {
    fail("error: \(error)", code: 1)
}
