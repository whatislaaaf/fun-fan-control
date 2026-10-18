import Foundation
import AppKit
import Combine
import FanKit

/// Owns the SMC connection, polls sensors on a background queue and drives the fans
/// along the user's curve. All published properties are updated on the main thread.
final class FanEngine: ObservableObject {
    static let shared = FanEngine()

    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var temperatures: [TemperatureReading] = []
    @Published private(set) var cpuTemp: Double?
    @Published private(set) var gpuTemp: Double?
    @Published private(set) var sourceTemp: Double?
    @Published private(set) var helperInstalled = HelperClient.isInstalled()
    @Published private(set) var helperPresent = HelperClient.exists()
    @Published private(set) var smcError: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdate: Date?
    /// True when the SMC reports a fan in forced mode while this app is not driving it
    /// (left over from a crash, an old build, or another tool) and we cannot release it.
    @Published private(set) var strayForcedFans = false
    /// True while this app is actively sending targets to the fans.
    @Published private(set) var controlling = false

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
            if settings.intervalSeconds != oldValue.intervalSeconds { restartTimer() }
            if oldValue.controlEnabled != settings.controlEnabled {
                queue.async { self.lastCommanded = [:] }
                tick()
            }
        }
    }

    private let queue = DispatchQueue(label: "com.funfancontrol.smc", qos: .utility)
    private var reader: SensorReader?
    private var timer: DispatchSourceTimer?
    private var saveWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    // Touched only on `queue`.
    private var lastCommanded: [Int: Double] = [:]
    private var forcing = false
    private var consecutiveFailures = 0

    private init() {
        settings = SettingsStore.load()
    }

    // MARK: Lifecycle

    func start() {
        queue.async {
            do {
                self.reader = try SensorReader()
            } catch {
                DispatchQueue.main.async { self.smcError = "\(error)" }
            }
        }
        restartTimer()

        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.releaseFans()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.queue.async { self?.lastCommanded = [:] }
            self?.tick()
        })
    }

    /// Returns fans to automatic control. Blocks until done; called when quitting.
    func shutdown() {
        timer?.cancel()
        timer = nil
        saveWork?.perform()
        queue.sync {
            if self.forcing {
                _ = try? HelperClient.setAuto()
                self.forcing = false
            }
        }
    }

    private func restartTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        let interval = max(1, min(10, settings.intervalSeconds))
        t.schedule(deadline: .now() + 0.2, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let s = settings
        let work = DispatchWorkItem { SettingsStore.save(s) }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Helper

    func refreshHelperStatus() {
        helperPresent = HelperClient.exists()
        helperInstalled = HelperClient.isInstalled()
    }

    func installHelper() {
        do {
            try HelperClient.install()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        refreshHelperStatus()
        tick()
    }

    /// Asks the helper to hand the fans back to macOS.
    func releaseFans() {
        queue.async {
            guard self.forcing else { return }
            do {
                try HelperClient.setAuto()
                self.forcing = false
                self.lastCommanded = [:]
            } catch {
                DispatchQueue.main.async { self.lastError = "\(error)" }
            }
        }
    }

    func applyPreset(_ preset: FanCurve.Preset, to fan: Int) {
        settings.setCurve(FanCurve.preset(preset), for: fan)
    }

    // MARK: Polling

    func tick() {
        let settings = self.settings
        let helperOK = helperInstalled
        queue.async { [weak self] in
            guard let self, let reader = self.reader else { return }
            let fans = reader.readFans()
            let temps = reader.readTemperatures()
            let cpu = temps.value(for: .cpu, aggregation: settings.aggregation)
            let gpu = temps.value(for: .gpu, aggregation: settings.aggregation)
            let source = settings.sourceTemperature(from: temps)

            var errorMessage: String?
            var stray = false
            let anyForced = fans.contains { $0.forced }
            if settings.controlEnabled, helperOK, let source, !settings.curves.isEmpty, !settings.curvesNeedMigration {
                errorMessage = self.drive(fans: fans, source: source, settings: settings)
            } else if self.forcing || anyForced {
                // Not controlling, yet a fan is forced: hand it back to macOS if we can.
                if helperOK {
                    do { try HelperClient.setAuto(); self.forcing = false } catch let e { errorMessage = "\(e)" }
                } else {
                    stray = true
                    errorMessage = "A fan is in forced mode but this app is not controlling it. Install the helper to return the fans to automatic control."
                }
            }
            let controlling = self.forcing

            DispatchQueue.main.async {
                self.fans = fans
                self.temperatures = temps
                self.cpuTemp = cpu
                self.gpuTemp = gpu
                self.sourceTemp = source
                self.lastUpdate = Date()
                self.strayForcedFans = stray
                self.controlling = controlling
                if let errorMessage { self.lastError = errorMessage } else { self.lastError = nil }
                if self.settings.curves.count < fans.count || self.settings.curves.isEmpty || self.settings.curvesNeedMigration {
                    self.settings.ensureCurves(for: fans)
                }
            }
        }
    }

    /// Computes a target for every fan from the curve and sends the ones that changed.
    /// Runs on `queue`. Returns an error message if the helper failed.
    private func drive(fans: [FanReading], source: Double, settings: AppSettings) -> String? {
        var commands: [(fan: Int, rpm: Double)] = []
        for fan in fans {
            guard let curve = settings.curve(for: fan.index) else { continue }
            // The curve yields a percent of this fan's own range, so fans with different
            // maximum speeds run at the same relative effort.
            var target = curve.rpm(at: source, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
            if source >= settings.safetyTemp { target = fan.maxRPM }
            target = min(max(target, fan.minRPM), fan.maxRPM)

            // Limit how fast the fan is allowed to change speed so it never surges.
            // A fan that macOS has switched off reads 0 RPM; ramp from its minimum instead.
            let base = lastCommanded[fan.index] ?? max(fan.actualRPM, fan.minRPM)
            target = min(max(target, base - settings.maxStepDown), base + settings.maxStepUp)
            target = (target / 10).rounded() * 10

            let previous = lastCommanded[fan.index]
            let needsResend = !fan.forced   // macOS took the fan back (sleep, reset, ...)
            if needsResend || previous == nil || abs(target - previous!) >= settings.deadbandRPM {
                commands.append((fan.index, target))
            }
        }
        guard !commands.isEmpty else { return nil }
        do {
            try HelperClient.setFans(commands)
            forcing = true
            consecutiveFailures = 0
            for c in commands { lastCommanded[c.fan] = c.rpm }
            return nil
        } catch {
            consecutiveFailures += 1
            if consecutiveFailures >= 5 {
                DispatchQueue.main.async { self.settings.controlEnabled = false }
                return "Helper failed repeatedly, custom control switched off. \(error)"
            }
            return "\(error)"
        }
    }
}
