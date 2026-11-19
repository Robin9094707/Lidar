import SwiftUI

struct SettingsView: View {
    @Environment(ScanStore.self) private var store
    @AppStorage("useImperial") private var useImperial = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("classificationColors") private var classificationColors = true
    @AppStorage("pointDensity") private var pointDensity = 1
    @AppStorage("highConfidenceOnly") private var highConfidenceOnly = false
    @AppStorage("maxDepth") private var maxDepth = 4.0
    @AppStorage("autoFloorCalibration") private var autoFloorCalibration = true
    @AppStorage("floorHeight") private var floorHeight = 0.0
    @State private var confirmDeleteAll = false
    @State private var storageSize: Int64 = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Theme.titleGradient)
                            .frame(width: 64, height: 64)
                            .glassEffect(.regular.tint(Theme.accent.opacity(0.2)), in: .rect(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LiDAR Studio")
                                .font(.title3.weight(.bold))
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Allgemein") {
                    Toggle(isOn: $useImperial) {
                        Label("Imperiale Einheiten (ft/in)", systemImage: "ruler")
                    }
                    Toggle(isOn: $hapticsEnabled) {
                        Label("Haptisches Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }

                Section {
                    Toggle(isOn: $classificationColors) {
                        Label("Klassifizierungsfarben", systemImage: "paintpalette")
                    }
                } header: {
                    Text("3D-Mesh")
                } footer: {
                    Text("Färbt Wände, Böden, Decken, Möbel, Fenster und Türen unterschiedlich ein.")
                }

                Section {
                    Picker(selection: $pointDensity) {
                        Text("Fein (8 mm)").tag(0)
                        Text("Standard (1,5 cm)").tag(1)
                        Text("Grob (3 cm)").tag(2)
                    } label: {
                        Label("Punktdichte", systemImage: "aqi.medium")
                    }
                    Toggle(isOn: $highConfidenceOnly) {
                        Label("Nur hohe Konfidenz", systemImage: "checkmark.shield")
                    }
                    VStack(alignment: .leading) {
                        Label("Maximale Tiefe: \(maxDepth.formatted(.number.precision(.fractionLength(1)))) m", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        Slider(value: $maxDepth, in: 1...5, step: 0.5)
                    }
                } header: {
                    Text("Punktwolke")
                } footer: {
                    Text("Feinere Dichte erzeugt mehr Details, aber größere Dateien. Der LiDAR-Sensor arbeitet bis ca. 5 m.")
                }

                Section {
                    Toggle(isOn: $autoFloorCalibration) {
                        Label("Auto-Kalibrierung draußen", systemImage: "figure.walk.departure")
                    }
                    Picker(selection: $floorHeight) {
                        Text("Automatisch (LiDAR)").tag(0.0)
                        Text("2,50 m").tag(2.5)
                        Text("2,80 m").tag(2.8)
                        Text("3,00 m").tag(3.0)
                        Text("3,30 m").tag(3.3)
                        Text("3,60 m").tag(3.6)
                        Text("4,00 m").tag(4.0)
                    } label: {
                        Label("Etagenhöhe", systemImage: "building.2")
                    }
                    Button(role: .destructive) {
                        SensorHub.shared.resetCalibration()
                        Haptics.light()
                    } label: {
                        Label("Etagen-Kalibrierung zurücksetzen", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Etage & Umgebung")
                } footer: {
                    Text("Die Etage wird aus Luftdruck, GPS-gestütztem Höhenmesser und Stockwerkzähler berechnet. Die Auto-Kalibrierung setzt nur bei eindeutig erkanntem Aufenthalt draußen (sehr gutes GPS, Gehen, keine Decke) das Erdgeschoss als Referenz.")
                }

                Section("Speicher") {
                    LabeledContent {
                        Text(Units.bytes(storageSize))
                    } label: {
                        Label("Belegt", systemImage: "internaldrive")
                    }
                    LabeledContent {
                        Text("\(store.items.count)")
                    } label: {
                        Label("Scans", systemImage: "square.stack.3d.up")
                    }
                    Button(role: .destructive) {
                        confirmDeleteAll = true
                    } label: {
                        Label("Alle Scans löschen", systemImage: "trash")
                    }
                    .disabled(store.items.isEmpty)
                }

                Section("Gerät") {
                    CapabilityRow(title: "LiDAR-Scanner", available: DeviceCapabilities.hasLiDAR)
                    CapabilityRow(title: "Scene Depth", available: DeviceCapabilities.supportsSceneDepth)
                    CapabilityRow(title: "RoomPlan", available: DeviceCapabilities.supportsRoomPlan)
                    CapabilityRow(title: "Object Capture", available: DeviceCapabilities.supportsObjectCapture)
                }

                Section("Exportformate") {
                    Label("USDZ – AR Quick Look, Reality Composer", systemImage: "arkit")
                    Label("OBJ / PLY – Blender, MeshLab, CloudCompare", systemImage: "cube.transparent")
                    Label("XYZ / CSV – Punkte & Koordinaten", systemImage: "tablecells")
                    Label("JSON – RoomPlan-Rohdaten", systemImage: "curlybraces")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Einstellungen")
            .onAppear { storageSize = store.totalSize() }
            .confirmationDialog("Alle Scans löschen?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Alle löschen", role: .destructive) {
                    store.deleteAll()
                    storageSize = store.totalSize()
                    Haptics.success()
                }
            } message: {
                Text("Alle \(store.items.count) Scans und ihre Dateien werden dauerhaft entfernt.")
            }
        }
    }
}
