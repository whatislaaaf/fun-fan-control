import SwiftUI
import ServiceManagement
import FanKit

enum EditorPage: String, CaseIterable, Identifiable {
    case curve, sensors, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .curve: return "chart.xyaxis.line"
        case .sensors: return "thermometer.medium"
        case .settings: return "gearshape"
        }
    }
}

struct CurveEditorWindow: View {
    @EnvironmentObject private var engine: FanEngine
    @State private var page: EditorPage = .curve

    var body: some View {
        NavigationSplitView {
            List(EditorPage.allCases, selection: $page) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
            .safeAreaInset(edge: .bottom) { sidebarStatus }
        } detail: {
            Group {
                switch page {
                case .curve: CurveTab()
                case .sensors: SensorsTab()
                case .settings: SettingsTab()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 920, minHeight: 600)
        .onAppear { engine.refreshHelperStatus() }
    }

    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(engine.controlling ? Color.accentColor : Color.secondary).frame(width: 7, height: 7)
                Text(engine.controlling ? "Custom curve active" : "macOS in control")
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            if let t = engine.sourceTemp {
                Text(String(format: "Input %.0f °C", t)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

// MARK: - Curve page

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

    /// -1 = one linked curve for all fans, otherwise a fan index with its own curve.
    private var scope: Binding<Int> {
        Binding(
            get: { engine.settings.sharedCurve ? -1 : fanIndex },
            set: { v in
                if v < 0 { engine.settings.sharedCurve = true; fanIndex = 0 }
                else { engine.settings.sharedCurve = false; fanIndex = v }
                selected = nil
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar
            HStack(alignment: .top, spacing: 14) {
                Card(padding: 10) {
                    CurveChart(
                        curve: curveBinding,
                        selected: $selected,
                        minRPM: fan?.minRPM ?? 0,
                        maxRPM: fan?.maxRPM ?? 5000,
                        liveTemp: engine.sourceTemp,
                        liveRPM: fan?.actualRPM,
                        safetyTemp: engine.settings.safetyTemp,
                        fanOffAtZero: engine.settings.allowFanOff
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 14) {
                    nowCard
                    pointsCard
                }
                .frame(width: 250)
            }
            HStack {
                Text("Drag points · double-click to add · ⌫ removes the selected point")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if !engine.settings.controlEnabled {
                    Label("Custom control is off", systemImage: "info.circle").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: scope) {
                Text("All fans").tag(-1)
                ForEach(engine.fans) { f in Text(f.name).tag(f.index) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("One linked curve for every fan, or a separate curve per fan")

            Spacer()

            HStack(spacing: 6) {
                SectionLabel(text: "Preset")
                ForEach(FanCurve.Preset.allCases) { p in
                    Button(p.rawValue) { applyPreset(p) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(p.summary)
                }
            }
            Button {
                removeSelected()
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(selected == nil || (engine.settings.curve(for: fanIndex)?.points.count ?? 0) <= 2)
                .help("Remove the selected point")
        }
    }

    private var nowCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Now")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(engine.sourceTemp.map { String(format: "%.0f", $0) } ?? "–")
                        .font(Theme.rounded(.largeTitle, weight: .bold).monospacedDigit())
                        .foregroundStyle(engine.sourceTemp.map(Theme.temperature) ?? .secondary)
                    Text("°C").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("curve says").font(.caption2).foregroundStyle(.secondary)
                        Text(curveSaysText).font(Theme.rounded(.title3, weight: .bold).monospacedDigit())
                    }
                }
                Divider()
                ForEach(engine.fans) { f in
                    HStack {
                        Text(f.name).font(.caption.weight(.medium))
                        Spacer()
                        let lvl = FanCurve.level(forRPM: f.actualRPM, minRPM: f.minRPM, maxRPM: f.maxRPM)
                        Text(f.actualRPM < 1 ? "off" : "\(Int(f.actualRPM)) RPM · \(Int(lvl * 100)) %")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(f.actualRPM < 1 ? .secondary : Theme.heat(lvl))
                    }
                }
            }
        }
    }

    private var curveSaysText: String {
        guard let t = engine.sourceTemp, let c = engine.settings.curve(for: fanIndex) else { return "–" }
        let lvl = c.level(at: t)
        if engine.settings.allowFanOff && lvl <= 0 { return "off" }
        let rpm = Int(FanCurve.rpm(forLevel: lvl, minRPM: fan?.minRPM ?? 0, maxRPM: fan?.maxRPM ?? 0))
        return "\(Int(lvl * 100)) % · \(rpm)"
    }

    private var pointsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "Points")
                    Spacer()
                    Button {
                        addPoint()
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help("Add a point")
                }
                HStack(spacing: 6) {
                    Text("°C").frame(width: 54)
                    Text("%").frame(width: 54)
                    Text("≈ RPM").frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer().frame(width: 18)
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(curveBinding.points) { $p in
                            HStack(spacing: 6) {
                                TextField("°C", value: $p.temp, format: .number.precision(.fractionLength(0)))
                                    .frame(width: 54)
                                TextField("%", value: $p.percent, format: .number.precision(.fractionLength(0)))
                                    .frame(width: 54)
                                Text(engine.settings.allowFanOff && p.level <= 0 ? "off" : "\(Int(FanCurve.rpm(forLevel: p.level, minRPM: fan?.minRPM ?? 0, maxRPM: fan?.maxRPM ?? 0)))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.heat(p.level))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Button {
                                    selected = p.id
                                    removeSelected()
                                } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.borderless).controlSize(.mini)
                                    .disabled(curveBinding.wrappedValue.points.count <= 2)
                                    .frame(width: 18)
                            }
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .padding(3)
                            .background(selected == p.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .onTapGesture { selected = p.id }
                        }
                    }
                }
                .frame(maxHeight: 190)
                .onSubmit { clampAndSort() }
            }
        }
    }

    private func applyPreset(_ p: FanCurve.Preset) {
        engine.applyPreset(p, to: fanIndex)
        selected = nil
    }

    private func addPoint() {
        var c = curveBinding.wrappedValue
        let pts = c.sortedPoints
        var temp = 65.0, level = 0.5
        if pts.count >= 2 {
            // Insert into the widest temperature gap.
            var best = (gap: 0.0, idx: 1)
            for i in 1..<pts.count where pts[i].temp - pts[i - 1].temp > best.gap { best = (pts[i].temp - pts[i - 1].temp, i) }
            temp = ((pts[best.idx - 1].temp + pts[best.idx].temp) / 2).rounded()
            level = c.level(at: temp)
        }
        let p = CurvePoint(temp: temp, level: level)
        c.points.append(p); c.normalize()
        curveBinding.wrappedValue = c
        selected = p.id
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
        for i in c.points.indices {
            c.points[i].temp = min(max(c.points[i].temp, 0), 120)
            c.points[i].level = min(max(c.points[i].level, 0), 1)
        }
        c.normalize()
        curveBinding.wrappedValue = c
    }
}

// MARK: - Sensors page

struct SensorsTab: View {
    @EnvironmentObject private var engine: FanEngine

    private var grouped: [(SensorGroup, [TemperatureReading])] {
        SensorGroup.allCases.compactMap { g in
            let rows = engine.temperatures.filter { $0.group == g }.sorted { $0.celsius > $1.celsius }
            return rows.isEmpty ? nil : (g, rows)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 118, maximum: 160), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sensors").font(Theme.rounded(.title2, weight: .bold))
                Spacer()
                Pill(text: "\(engine.settings.customKeys.count) selected as custom input", color: engine.settings.customKeys.isEmpty ? .secondary : .accentColor, filled: !engine.settings.customKeys.isEmpty)
            }
            Text("Every temperature the SMC reports, live. Click a tile to use that sensor as the “Custom sensors” curve input, for example a palm-rest sensor if the goal is a laptop that stays cool to the touch.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(grouped, id: \.0) { group, rows in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                SectionLabel(text: group.rawValue)
                                Text("· \(rows.count)").font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                                if let hottest = rows.first {
                                    Text(String(format: "max %.0f°", hottest.celsius)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(rows) { r in SensorTile(reading: r, selected: engine.settings.customKeys.contains(r.key)) { toggle(r.key) } }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func toggle(_ key: String) {
        if engine.settings.customKeys.contains(key) { engine.settings.customKeys.removeAll { $0 == key } }
        else { engine.settings.customKeys.append(key) }
    }
}

struct SensorTile: View {
    let reading: TemperatureReading
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(reading.key).font(.caption.monospaced().weight(.semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                Text(String(format: "%.1f°", reading.celsius))
                    .font(Theme.rounded(.title3, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.temperature(reading.celsius))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.accentColor.opacity(0.14) : Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? Color.accentColor.opacity(0.6) : Theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings page

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
                Toggle("Allow fans to stop at 0 %", isOn: s.allowFanOff)
                Text("With this on, a curve point at exactly 0 % switches the fan off instead of running it at its minimum speed. The fan comes back on, ramping from its minimum, as soon as the curve rises above 0 %.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Switch fans off while the lid is closed", isOn: s.fansOffWhenLidClosed)
                Text("When the lid is closed and the Mac stays awake (an external display, for example), every fan is stopped regardless of the curve. The fans ramp back up from their minimum when the lid opens. The safety threshold below still applies.")
                    .font(.caption).foregroundStyle(.secondary)
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
