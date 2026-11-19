import SwiftUI
import CoreLocation
import CoreMotion

struct SensorsView: View {
    @State private var hub = SensorHub.shared
    @State private var showCalibration = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    placeCard
                    floorCard
                    LazyVGrid(columns: columns, spacing: 12) {
                        barometerTile
                        altitudeTile
                        gpsTile
                        compassTile
                        levelTile
                        magnetTile
                        motionTile
                        lightTile
                        lidarTile
                        systemTile
                    }
                    if hub.authorization == .denied || hub.authorization == .restricted {
                        permissionHint
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background(AuroraBackground())
            .navigationTitle("Sensoren")
            .sheet(isPresented: $showCalibration) {
                FloorCalibrationSheet(hub: hub)
            }
        }
        .onAppear {
            hub.acquireMotion()
            hub.acquirePrecision()
        }
        .onDisappear {
            hub.releaseMotion()
            hub.releasePrecision()
        }
    }

    // MARK: Drinnen / Draußen

    private var placeCard: some View {
        let a = hub.assessment
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: a.place.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(a.place.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 64, height: 64)
                    .glassEffect(.regular.tint(a.place.tint.opacity(0.25)), in: .circle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Umgebung")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(a.place.title)
                        .font(.title.weight(.bold))
                        .contentTransition(.numericText())
                    ProgressView(value: a.confidence)
                        .tint(a.place.tint)
                    Text("Sicherheit \(Int(a.confidence * 100)) %")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if a.evidence.isEmpty {
                Text("Noch keine Hinweise. Öffne einen Scan oder das Messwerkzeug – der LiDAR-Sensor erkennt Decken sofort.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(a.evidence) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .frame(width: 22)
                                .foregroundStyle(item.weight > 0 ? Theme.accent : Theme.yellow)
                            Text(item.text)
                                .font(.footnote)
                            Spacer(minLength: 0)
                            Image(systemName: item.weight > 0 ? "building.2" : "tree")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Picker("Modus", selection: Binding(get: { hub.placeOverride }, set: { hub.setPlaceOverride($0) })) {
                ForEach(PlaceOverride.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .animation(.spring(duration: 0.5), value: a.place)
    }

    // MARK: Etage

    private var floorCard: some View {
        let f = hub.floorEstimate
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Etage")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(f.floor.map(FloorName.name) ?? "Unbekannt")
                        .font(.title.weight(.bold))
                        .contentTransition(.numericText())
                    Text(f.source)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Text(f.floor.map(FloorName.short) ?? "?")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular.tint(Theme.violet.opacity(0.35)), in: .rect(cornerRadius: 22))
            }

            HStack(spacing: 8) {
                if let h = f.heightAboveReference {
                    GlassPill(systemImage: "arrow.up.and.down", text: "\(h >= 0 ? "+" : "")\(h.formatted(.number.precision(.fractionLength(1)))) m")
                }
                GlassPill(systemImage: "ruler", text: "\(hub.floorHeight.formatted(.number.precision(.fractionLength(2)))) m/Etage")
            }

            if let warning = f.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.orange)
            }

            Button {
                showCalibration = true
            } label: {
                Label(hub.calibration == nil ? "Etage kalibrieren" : "Neu kalibrieren", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!hub.hasBarometer)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    // MARK: Kacheln

    private var barometerTile: some View {
        SensorTile(title: "Luftdruck", icon: "barometer", tint: Theme.accent) {
            if let p = hub.pressureKPa {
                Text("\((p * 10).formatted(.number.precision(.fractionLength(1)))) hPa")
            } else {
                Text(hub.hasBarometer ? "…" : "n. v.")
            }
        } detail: {
            if let r = hub.relativeAltitude {
                Text("Δ seit Start \(r >= 0 ? "+" : "")\(r.formatted(.number.precision(.fractionLength(2)))) m")
            }
        }
    }

    private var altitudeTile: some View {
        SensorTile(title: "Höhe ü. NN", icon: "mountain.2.fill", tint: Theme.mint) {
            if let alt = hub.absoluteAltitude ?? hub.location?.altitude {
                Text("\(Int(alt.rounded())) m")
            } else {
                Text("…")
            }
        } detail: {
            if let acc = hub.absoluteAccuracy {
                Text("±\(acc.formatted(.number.precision(.fractionLength(1)))) m · Höhenmesser")
            } else if let v = hub.location?.verticalAccuracy, v > 0 {
                Text("±\(Int(v)) m · GPS")
            }
        }
    }

    private var gpsTile: some View {
        SensorTile(title: "GPS", icon: "location.fill", tint: Theme.accent) {
            if let loc = hub.location {
                Text("±\(Int(loc.horizontalAccuracy.rounded())) m")
            } else {
                Text(hub.authorization == .denied ? "Aus" : "Suche …")
            }
        } detail: {
            if let loc = hub.location {
                Text("\(loc.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(loc.coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
            }
        }
    }

    private var compassTile: some View {
        SensorTile(title: "Kompass", icon: "safari.fill", tint: Theme.pink) {
            if let h = hub.compassHeading {
                HStack(spacing: 8) {
                    Text("\(Int(h.rounded()))° \(Self.direction(h))")
                    Image(systemName: "location.north.fill")
                        .foregroundStyle(Theme.pink)
                        .rotationEffect(.degrees(-h))
                        .animation(.smooth(duration: 0.3), value: h)
                }
            } else {
                Text("n. v.")
            }
        } detail: {
            if let acc = hub.heading?.headingAccuracy, acc >= 0 {
                Text("±\(Int(acc))° · \(hub.heading?.trueHeading ?? -1 >= 0 ? "geografisch" : "magnetisch")")
            }
        }
    }

    private var levelTile: some View {
        let t = hub.tilt
        return SensorTile(title: "Wasserwaage", icon: "level.fill", tint: Theme.mint) {
            HStack(spacing: 10) {
                BubbleLevel(x: t.flat ? t.x : t.x, y: t.flat ? t.y : 0)
                    .frame(width: 34, height: 34)
                Text("\(abs(t.x).formatted(.number.precision(.fractionLength(1))))°")
            }
        } detail: {
            Text(t.flat ? "Flach · Y \(abs(t.y).formatted(.number.precision(.fractionLength(1))))°" : "Hochkant · Neigung \(abs(t.y).formatted(.number.precision(.fractionLength(1))))°")
        }
    }

    private var magnetTile: some View {
        SensorTile(title: "Magnetfeld", icon: "dot.radiowaves.left.and.right", tint: Theme.violet) {
            if let f = hub.magneticField {
                Text("\(Int(f.rounded())) µT")
            } else {
                Text("kalibriere …")
            }
        } detail: {
            if let f = hub.magneticField {
                Text(f > 80 ? "Metall in der Nähe" : "Erdmagnetfeld normal")
            }
        }
    }

    private var motionTile: some View {
        SensorTile(title: "Bewegung", icon: "figure.walk", tint: Theme.orange) {
            Text(hub.activity ?? "…")
        } detail: {
            if CMPedometer.isFloorCountingAvailable() {
                Text("↑ \(hub.floorsAscended)  ↓ \(hub.floorsDescended) Etagen · \(hub.steps) Schritte")
            } else {
                Text("Gyro \(hub.rotationRate.formatted(.number.precision(.fractionLength(2)))) rad/s")
            }
        }
    }

    private var lightTile: some View {
        SensorTile(title: "Licht", icon: "sun.max.fill", tint: Theme.yellow) {
            if let k = hub.colorTemperature {
                Text("\(Int(k)) K")
            } else {
                Text("—")
            }
        } detail: {
            if let i = hub.ambientIntensity {
                Text("\(Int(i)) lm · Kamera")
            } else {
                Text("Aktiv während AR-Scans")
            }
        }
    }

    private var lidarTile: some View {
        SensorTile(title: "LiDAR", icon: "dot.radiowaves.right", tint: Theme.accent) {
            Text(DeviceCapabilities.hasLiDAR ? (hub.lastLiDARActivity.map { Date().timeIntervalSince($0) < 10 } == true ? "Aktiv" : "Bereit") : "n. v.")
        } detail: {
            if let h = hub.measuredRoomHeight {
                Text("Raumhöhe \(Units.length(h))")
            } else {
                Text("Decke/Boden werden beim Scannen erkannt")
            }
        }
    }

    private var systemTile: some View {
        SensorTile(title: "System", icon: "thermometer.medium", tint: thermalColor) {
            Text(thermalText)
        } detail: {
            Text("\(hub.batteryLevel >= 0 ? "Akku \(Int(hub.batteryLevel * 100)) %" : "Akku —")\(hub.lowPowerMode ? " · Stromsparen" : "")")
        }
    }

    private var thermalText: String {
        switch hub.thermalState {
        case .nominal: "Kühl"
        case .fair: "Warm"
        case .serious: "Heiß – gedrosselt"
        case .critical: "Kritisch"
        @unknown default: "—"
        }
    }

    private var thermalColor: Color {
        switch hub.thermalState {
        case .nominal: Theme.mint
        case .fair: Theme.yellow
        default: .red
        }
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Standortzugriff ist deaktiviert", systemImage: "location.slash.fill")
                .font(.headline)
            Text("Ohne GPS ist die Drinnen/Draußen-Erkennung ungenauer. Erlaube den Zugriff in den Einstellungen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.glass)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Theme.orange.opacity(0.2)), in: .rect(cornerRadius: 24))
    }

    static func direction(_ degrees: Double) -> String {
        let names = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
        let index = Int(((degrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return names[max(0, min(7, index))]
    }
}

struct SensorTile<Value: View, Detail: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let value: () -> Value
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            value()
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            detail()
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

struct BubbleLevel: View {
    let x: Double
    let y: Double

    var body: some View {
        GeometryReader { geo in
            let r = geo.size.width / 2
            let dx = max(-1, min(1, x / 20)) * (r - 6)
            let dy = max(-1, min(1, y / 20)) * (r - 6)
            let level = abs(x) < 1 && abs(y) < 1
            ZStack {
                Circle().stroke(.white.opacity(0.4), lineWidth: 1)
                Circle().stroke(.white.opacity(0.25), lineWidth: 1).frame(width: 12, height: 12)
                Circle()
                    .fill(level ? Theme.mint : .white)
                    .frame(width: 10, height: 10)
                    .offset(x: dx, y: -dy)
                    .animation(.interactiveSpring, value: dx)
            }
        }
    }
}

struct FloorCalibrationSheet: View {
    let hub: SensorHub
    @Environment(\.dismiss) private var dismiss
    @State private var floor = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.titleGradient)
                .frame(width: 76, height: 76)
                .glassEffect(.regular.tint(Theme.violet.opacity(0.3)), in: .circle)
            Text("In welcher Etage bist du gerade?")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Der Luftdruck wird jetzt als Referenz gespeichert. Danach erkennt die App jeden Etagenwechsel über Barometer, Höhenmesser und Stockwerkzähler.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                GlassIconButton(systemName: "minus", size: 52) { floor -= 1; Haptics.light() }
                Text(FloorName.name(floor))
                    .font(.title2.weight(.bold))
                    .contentTransition(.numericText(value: Double(floor)))
                    .frame(minWidth: 170)
                    .animation(.spring(duration: 0.3), value: floor)
                GlassIconButton(systemName: "plus", size: 52) { floor += 1; Haptics.light() }
            }

            Button {
                hub.calibrate(floor: floor)
                Haptics.success()
                dismiss()
            } label: {
                Label("Hier kalibrieren", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(hub.pressureKPa == nil)

            if hub.calibration != nil {
                Button("Kalibrierung zurücksetzen", role: .destructive) {
                    hub.resetCalibration()
                    dismiss()
                }
                .font(.footnote)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            floor = hub.floorEstimate.floor ?? hub.calibration?.floor ?? 0
        }
    }
}
