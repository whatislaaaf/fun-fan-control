import SwiftUI
import ServiceManagement
import FanKit

struct CurveEditorWindow: View {
    @EnvironmentObject private var engine: FanEngine

    var body: some View {
        TabView {
            CurveTab().tabItem { Label("Curve", systemImage: "chart.xyaxis.line") }
            SensorsTab().tabItem { Label("Sensors", systemImage: "thermometer.medium") }
            SettingsTab().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { engine.refreshHelperStatus() }
    }
}

// MARK: - Curve tab

struct CurveTab: View {
    @EnvironmentObject private var engine: FanEngine
    @State private var fanIndex = 0
    @State private var selected: UUID?

    private var fan: FanReading? {
        engine.fans.first(where: { $0.index == fanIndex }) ?? engine.fans.first
    }

    private var curveBinding: Binding<FanCurve> {
        Binding(
            get: { engine.settings.curve(for: fanIndex) ?? FanCurve(points: []) },
            set: { engine.settings.setCurve($0, for: fanIndex) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Toggle("Same curve for all fans", isOn: Binding(
                    get: { engine.settings.sharedCurve },
                    set: { engine.settings.sharedCurve = $0; if $0 { fanIndex = 0 } }
                ))
                if !engine.settings.sharedCurve {
                    Picker("Fan", selection: $fanIndex) {
                        ForEach(engine.fans) { f in Text(f.name).tag(f.index) }
                    }
                    .frame(maxWidth: 220)
                }
                Spacer()
                Menu("Load preset") {
                    ForEach(FanCurve.Preset.allCases) { p in
                        Button(p.rawValue) { applyPreset(p) }
                    }
                }
                .frame(width: 130)
                Button("Remove point") { removeSelected() }
                    .disabled(selected == nil || (engine.settings.curve(for: fanIndex)?.points.count ?? 0) <= 2)
            }

            CurveChart(
                curve: curveBinding,
                selected: $selected,
                minRPM: fan?.minRPM ?? 0,
                maxRPM: fan?.maxRPM ?? 5000,
                liveTemp: engine.sourceTemp,
                liveRPM: fan?.actualRPM,
                safetyTemp: engine.settings.safetyTemp
            )
            .frame(minHeight: 280)

            HStack(alignment: .top, spacing: 16) {
                pointsTable
                VStack(alignment: .leading, spacing: 6) {
                    Text("How to use").font(.caption.weight(.semibold))
                    Text("Drag a point to move it. Double-click empty space to add one. Select a point and press Delete to remove it. The orange marker shows where the machine is right now, so you can watch how a change feels before deciding.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Curve input: \(engine.settings.source.label) (\(engine.settings.aggregation.label.lowercased()))")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    if !engine.settings.controlEnabled {
                        Label("Custom control is off. Turn it on in the menu or in Settings.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: 300, alignment: .leading)
            }
        }
    }

    private var pointsTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("°C").frame(width: 60); Text("RPM").frame(width: 70)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(curveBinding.points) { $p in
                        HStack(spacing: 6) {
                            TextField("°C", value: $p.temp, format: .number.precision(.fractionLength(0)))
                                .frame(width: 60)
                            TextField("RPM", value: $p.rpm, format: .number.precision(.fractionLength(0)))
                                .frame(width: 70)
                            Button {
                                selected = p.id
                                removeSelected()
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .disabled(curveBinding.wrappedValue.points.count <= 2)
                        }
                        .textFieldStyle(.roundedBorder)
                        .background(selected == p.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .onTapGesture { selected = p.id }
                    }
                }
            }
            .frame(maxHeight: 130)
            .onSubmit { clampAndSort() }
        }
    }

    private func applyPreset(_ p: FanCurve.Preset) {
        engine.applyPreset(p, to: fanIndex)
        selected = nil
    }

    private func removeSelected() {
        guard let sel = selected else { return }
        var c = curveBinding.wrappedValue
        guard c.points.count > 2 else { return }
        c.points.removeAll { $0.id == sel }
        curveBinding.wrappedValue = c
        selected = nil
    }

    private func clampAndSort() {
        var c = curveBinding.wrappedValue
        let lo = fan?.minRPM ?? 0, hi = fan?.maxRPM ?? 10000
        for i in c.points.indices {
            c.points[i].temp = min(max(c.points[i].temp, 0), 120)
            c.points[i].rpm = min(max(c.points[i].rpm, lo), hi)
        }
        c.normalize()
        curveBinding.wrappedValue = c
    }
}

// MARK: - Sensors tab

struct SensorsTab: View {
    @EnvironmentObject private var engine: FanEngine

    private var grouped: [(SensorGroup, [TemperatureReading])] {
        SensorGroup.allCases.compactMap { g in
            let rows = engine.temperatures.filter { $0.group == g }.sorted { $0.celsius > $1.celsius }
            return rows.isEmpty ? nil : (g, rows)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Every temperature sensor the SMC reports. Tick sensors to use them as the “Custom sensors” curve input, for example a palm-rest sensor if the goal is a laptop that stays cool to the touch.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(grouped, id: \.0) { group, rows in
                    Section(group.rawValue) {
                        ForEach(rows) { r in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { engine.settings.customKeys.contains(r.key) },
                                    set: { on in
                                        if on { engine.settings.customKeys.append(r.key) }
                                        else { engine.settings.customKeys.removeAll { $0 == r.key } }
                                    }
                                )) { Text(r.key).font(.body.monospaced()) }
                                Spacer()
                                Text(String(format: "%.1f °C", r.celsius)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            Text("\(engine.temperatures.count) sensors · \(engine.settings.customKeys.count) selected for custom input")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Settings tab

struct SettingsTab: View {
    @EnvironmentObject private var engine: FanEngine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var s: Binding<AppSettings> { $engine.settings }

    var body: some View {
        Form {
            Section("Control") {
                Toggle("Use custom fan curve", isOn: s.controlEnabled)
                    .disabled(!engine.helperInstalled)
                Picker("Curve input", selection: s.source) {
                    ForEach(TempSource.allCases) { Text($0.label).tag($0) }
                }
                Picker("Combine sensors by", selection: s.aggregation) {
                    ForEach(Aggregation.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Update every") {
                    HStack {
                        Slider(value: s.intervalSeconds, in: 1...5, step: 0.5)
                        Text(String(format: "%.1f s", engine.settings.intervalSeconds)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Smoothing") {
                LabeledContent("Max speed-up per update") {
                    HStack {
                        Slider(value: s.maxStepUp, in: 50...2000, step: 50)
                        Text("\(Int(engine.settings.maxStepUp)) RPM").monospacedDigit().frame(width: 76, alignment: .trailing)
                    }
                }
                LabeledContent("Max slow-down per update") {
                    HStack {
                        Slider(value: s.maxStepDown, in: 50...2000, step: 50)
                        Text("\(Int(engine.settings.maxStepDown)) RPM").monospacedDigit().frame(width: 76, alignment: .trailing)
                    }
                }
                LabeledContent("Ignore changes under") {
                    HStack {
                        Slider(value: s.deadbandRPM, in: 0...300, step: 10)
                        Text("\(Int(engine.settings.deadbandRPM)) RPM").monospacedDigit().frame(width: 76, alignment: .trailing)
                    }
                }
                Text("Slow ramps keep the fans from surging audibly every time the chip spikes for a second.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Safety") {
                LabeledContent("Force full speed above") {
                    HStack {
                        Slider(value: s.safetyTemp, in: 80...105, step: 1)
                        Text("\(Int(engine.settings.safetyTemp)) °C").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                Text("Fans return to macOS automatic control whenever the app quits, sleeps or custom control is switched off.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Show curve input temperature", isOn: s.showTempInMenuBar)
                Toggle("Show first fan RPM", isOn: s.showRPMInMenuBar)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in toggleLogin(on) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section("Root helper") {
                LabeledContent("Status") {
                    if engine.helperInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if engine.helperPresent {
                        Label("Not installed", systemImage: "xmark.circle").foregroundStyle(.orange)
                    } else {
                        Label("Helper binary missing", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
                HStack {
                    Button(engine.helperInstalled ? "Reinstall helper…" : "Install helper…") { engine.installHelper() }
                        .disabled(!engine.helperPresent)
                    Button("Refresh") { engine.refreshHelperStatus() }
                }
                Text("Changing fan speed requires root. The helper is a tiny separate program that only knows how to set a fan target or hand control back to macOS. Installing marks it setuid root; you will be asked for your password once. Rebuilding the app replaces the helper and needs a reinstall.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(HelperClient.helperURL.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                if let err = engine.lastError { Text(err).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private func toggleLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "\(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
