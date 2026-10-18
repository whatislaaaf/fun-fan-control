import SwiftUI
import FanKit

/// The dropdown shown when the menu bar item is clicked.
struct StatusPopover: View {
    @EnvironmentObject private var engine: FanEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fun Fan Control").font(.headline)
                Spacer()
                modeBadge
            }

            if let err = engine.smcError {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }

            if engine.fans.isEmpty {
                Text("No fans found").foregroundStyle(.secondary)
            } else {
                ForEach(engine.fans) { fan in FanRow(fan: fan) }
            }

            Divider()

            temperatureGrid

            Divider()

            controlToggle

            if let err = engine.lastError {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(3)
            }

            HStack {
                Button {
                    openWindow(id: "curves")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Fan curves & settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var modeBadge: some View {
        let custom = engine.settings.controlEnabled && engine.helperInstalled
        return Text(custom ? "Custom curve" : "Auto (macOS)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(custom ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
    }

    private var temperatureGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                TempTile(title: "CPU", value: engine.cpuTemp, symbol: "cpu")
                TempTile(title: "GPU", value: engine.gpuTemp, symbol: "cpu.fill")
            }
            if engine.settings.source == .custom || engine.settings.source == .cpuOrGpu {
                GridRow {
                    Text("Curve input (\(engine.settings.source == .custom ? "custom" : "hottest"))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(engine.sourceTemp.map { String(format: "%.1f °C", $0) } ?? "–")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private var controlToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { engine.settings.controlEnabled },
                set: { engine.settings.controlEnabled = $0 }
            )) {
                Text("Custom fan curve")
            }
            .toggleStyle(.switch)
            .disabled(!engine.helperInstalled)

            if !engine.helperInstalled {
                HStack(spacing: 6) {
                    Text("Needs the root helper to change fan speed.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Install…") { engine.installHelper() }
                        .controlSize(.small)
                }
            }
        }
    }
}

struct FanRow: View {
    let fan: FanReading

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(fan.name).font(.subheadline)
                Spacer()
                Text("\(Int(fan.actualRPM))")
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text("RPM").font(.caption).foregroundStyle(.secondary)
            }
            Gauge(value: min(max(fan.actualRPM, fan.minRPM), fan.maxRPM), in: fan.minRPM...max(fan.maxRPM, fan.minRPM + 1)) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(fan.forced ? Color.accentColor : .secondary)
            HStack {
                Text("\(Int(fan.minRPM)) – \(Int(fan.maxRPM))").font(.caption2).foregroundStyle(.secondary)
                Text("· \(Int(FanCurve.level(forRPM: fan.actualRPM, minRPM: fan.minRPM, maxRPM: fan.maxRPM) * 100)) %")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if fan.forced, let t = fan.targetRPM {
                    Text("target \(Int(t))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct TempTile: View {
    let title: String
    let value: Double?
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f°", $0) } ?? "–")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    private var color: Color {
        guard let v = value else { return .secondary }
        if v >= 90 { return .red }
        if v >= 75 { return .orange }
        return .primary
    }
}
