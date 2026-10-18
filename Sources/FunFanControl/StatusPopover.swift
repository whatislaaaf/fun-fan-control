import SwiftUI
import FanKit

/// The dropdown shown when the menu bar item is clicked.
struct StatusPopover: View {
    @EnvironmentObject private var engine: FanEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let err = engine.smcError {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }

            if engine.fans.isEmpty {
                Card { Text("No fans found").foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            } else {
                HStack(spacing: 10) {
                    ForEach(engine.fans) { fan in FanGaugeCard(fan: fan) }
                }
            }

            temperatureRow

            controlCard

            if let err = engine.lastError {
                Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(3)
            }

            footer
        }
        .padding(14)
        .frame(width: 330)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "fan.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(engine.controlling ? Theme.heat(0.5) : .secondary)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: engine.controlling)
            Text("Fun Fan Control").font(Theme.rounded(.headline, weight: .bold))
            Spacer()
            modePill
        }
    }

    private var modePill: some View {
        let anyForced = engine.fans.contains { $0.forced }
        if engine.controlling {
            return Pill(text: "Custom curve", color: .accentColor, filled: true)
        } else if anyForced {
            return Pill(text: "Forced · not by this app", color: .orange, filled: true)
        } else {
            return Pill(text: "Auto · macOS", color: .secondary)
        }
    }

    private var temperatureRow: some View {
        HStack(spacing: 8) {
            StatChip(label: "CPU", value: fmt(engine.cpuTemp), color: engine.cpuTemp.map(Theme.temperature) ?? .secondary, symbol: "cpu")
            StatChip(label: "GPU", value: fmt(engine.gpuTemp), color: engine.gpuTemp.map(Theme.temperature) ?? .secondary, symbol: "memorychip")
            StatChip(label: inputLabel, value: fmt(engine.sourceTemp), color: engine.sourceTemp.map(Theme.temperature) ?? .secondary, symbol: "target")
        }
    }

    private var inputLabel: String {
        switch engine.settings.source {
        case .cpu: return "Input · CPU"
        case .gpu: return "Input · GPU"
        case .cpuOrGpu: return "Input · hottest"
        case .custom: return "Input · custom"
        }
    }

    private func fmt(_ v: Double?) -> String {
        v.map { String(format: "%.0f°", $0) } ?? "–"
    }

    private var controlCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { engine.settings.controlEnabled },
                    set: { engine.settings.controlEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom fan curve").font(.subheadline.weight(.semibold))
                        Text(curveSummary).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!engine.helperInstalled)

                if !engine.helperInstalled {
                    HStack(spacing: 8) {
                        Image(systemName: engine.strayForcedFans ? "exclamationmark.triangle.fill" : "lock.fill")
                            .foregroundStyle(engine.strayForcedFans ? .orange : .secondary)
                        Text(engine.strayForcedFans
                             ? "Fans are stuck in forced mode. Install the helper to release them."
                             : "Changing fan speed needs a one-time root helper install.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button("Install…") { engine.installHelper() }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var curveSummary: String {
        guard let curve = engine.settings.curve(for: 0), let first = curve.sortedPoints.first, let last = curve.sortedPoints.last else {
            return "No curve yet"
        }
        let shared = engine.settings.sharedCurve ? "Linked fans" : "Per-fan curves"
        return "\(shared) · \(Int(first.percent)) % at \(Int(first.temp))° → \(Int(last.percent)) % at \(Int(last.temp))°"
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "curves")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Curves & settings", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power").font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: .command)
        }
        .foregroundStyle(.secondary)
    }
}

/// One fan: arc gauge with the RPM inside, name and effort below.
struct FanGaugeCard: View {
    let fan: FanReading

    private var level: Double { FanCurve.level(forRPM: fan.actualRPM, minRPM: fan.minRPM, maxRPM: fan.maxRPM) }
    private var isOff: Bool { fan.actualRPM < 1 }

    var body: some View {
        Card(padding: 10) {
            VStack(spacing: 6) {
                ArcGauge(progress: isOff ? 0 : max(level, 0.02), isOff: isOff) {
                    VStack(spacing: 0) {
                        if isOff {
                            Text("off").font(Theme.rounded(.title2, weight: .bold)).foregroundStyle(.secondary)
                        } else {
                            Text("\(Int(fan.actualRPM))")
                                .font(Theme.rounded(.title2, weight: .bold).monospacedDigit())
                                .contentTransition(.numericText())
                            Text("RPM").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 96, height: 96)
                .padding(.top, 2)

                Text(fan.name).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var detail: String {
        if isOff { return "idle · \(Int(fan.minRPM))–\(Int(fan.maxRPM))" }
        var s = "\(Int(level * 100)) %"
        if fan.forced, let t = fan.targetRPM { s += " · target \(Int(t))" }
        else { s += " · max \(Int(fan.maxRPM))" }
        return s
    }
}
