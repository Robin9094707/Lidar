import SwiftUI
import RoomPlan
import simd

@Observable
final class RoomCaptureController: NSObject, RoomCaptureViewDelegate {
    enum Phase { case ready, scanning, processing, finished, failed }

    let captureView: RoomCaptureView
    var phase: Phase = .ready
    var finalRoom: CapturedRoom?
    var errorText: String?

    override init() {
        captureView = RoomCaptureView(frame: .zero)
        super.init()
        captureView.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) wird nicht unterstützt")
    }

    func encode(with coder: NSCoder) {}

    func start() {
        finalRoom = nil
        errorText = nil
        phase = .scanning
        let configuration = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: configuration)
    }

    func stop() {
        guard phase == .scanning else { return }
        phase = .processing
        captureView.captureSession.stop()
    }

    func cancel() {
        captureView.captureSession.stop()
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        DispatchQueue.main.async {
            if let error {
                self.errorText = error.localizedDescription
                self.phase = .failed
            } else {
                self.finalRoom = processedResult
                self.phase = .finished
            }
        }
    }
}

struct RoomCaptureContainer: UIViewRepresentable {
    let controller: RoomCaptureController
    func makeUIView(context: Context) -> RoomCaptureView { controller.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

struct RoomScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScanStore.self) private var store
    @State private var controller = RoomCaptureController()
    @State private var showSave = false
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if DeviceCapabilities.supportsRoomPlan {
                RoomCaptureContainer(controller: controller)
                    .ignoresSafeArea()
                hud
            } else {
                UnsupportedFeatureView(
                    title: "RoomPlan nicht verfügbar",
                    message: "Raumscans benötigen ein Gerät mit LiDAR-Scanner (iPhone Pro / iPad Pro).",
                    onClose: { dismiss() }
                )
            }
            if isSaving {
                ProcessingOverlay(title: "Raummodell wird gespeichert …")
            }
        }
        .statusBarHidden()
        .onAppear {
            if DeviceCapabilities.supportsRoomPlan { controller.start() }
        }
        .onDisappear { controller.cancel() }
        .sheet(isPresented: $showSave) {
            SaveScanSheet(kind: .room, name: $name, onSave: save, onCancel: { showSave = false })
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var hud: some View {
        VStack(spacing: 14) {
            CaptureTopBar(title: "Raumscan", systemImage: "house.fill", tint: Theme.accent, onClose: {
                controller.cancel()
                dismiss()
            })

            if controller.phase == .finished, let room = controller.finalRoom {
                roomSummary(room)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    switch controller.phase {
                    case .ready, .scanning:
                        Button {
                            Haptics.tap()
                            controller.stop()
                        } label: {
                            Label("Fertig", systemImage: "checkmark")
                                .font(.headline)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    case .processing:
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Modell wird erstellt …").font(.headline)
                        }
                        .padding(.horizontal, 22).padding(.vertical, 14)
                        .glassEffect(.regular, in: .capsule)
                    case .finished:
                        Button {
                            Haptics.light()
                            controller.start()
                        } label: {
                            Label("Neu", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        Button {
                            name = "Raum \(Date().scanDefaultName)"
                            showSave = true
                        } label: {
                            Label("Speichern", systemImage: "square.and.arrow.down.fill")
                                .font(.headline)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    case .failed:
                        Button {
                            controller.start()
                        } label: {
                            Label(controller.errorText ?? "Erneut versuchen", systemImage: "arrow.clockwise")
                                .font(.headline)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: controller.phase)
    }

    private func roomSummary(_ room: CapturedRoom) -> some View {
        let summary = RoomSummary(room: room)
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                GlassPill(systemImage: "rectangle.portrait", text: "\(room.walls.count)", tint: Theme.accent)
                GlassPill(systemImage: "door.left.hand.open", text: "\(room.doors.count)", tint: Theme.yellow)
                GlassPill(systemImage: "window.vertical.closed", text: "\(room.windows.count)", tint: Theme.violet)
                GlassPill(systemImage: "sofa.fill", text: "\(room.objects.count)", tint: Theme.orange)
            }
        }
        .overlay(alignment: .bottom) {
            if summary.floorArea > 0 {
                GlassPill(systemImage: "square.dashed", text: Units.area(summary.floorArea), tint: Theme.mint)
                    .offset(y: 54)
            }
        }
    }

    private func save() {
        showSave = false
        guard let room = controller.finalRoom else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let scanName = trimmed.isEmpty ? "Raum" : trimmed
        let id = UUID()
        let folder = store.folderURL(for: id)
        let baseName = scanName.sanitizedFileName
        isSaving = true

        Task {
            do {
                let usdzName = "\(baseName).usdz"
                let jsonName = "\(baseName)-raumdaten.json"
                try room.export(to: folder.appending(path: usdzName), exportOptions: .parametric)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                try encoder.encode(room).write(to: folder.appending(path: jsonName))

                let summary = RoomSummary(room: room)
                SensorHub.shared.reportRoomPlan(height: summary.height)
                var stats: [ScanStat] = [
                    ScanStat(label: "Bodenfläche", icon: "square.dashed", value: Double(summary.floorArea), unit: .area),
                    ScanStat(label: "Wandlänge", icon: "ruler", value: Double(summary.wallLength), unit: .length),
                    ScanStat(label: "Raumhöhe", icon: "arrow.up.and.down", value: Double(summary.height), unit: .length),
                    ScanStat(label: "Wände", icon: "rectangle.portrait", value: Double(room.walls.count), unit: .count),
                    ScanStat(label: "Türen", icon: "door.left.hand.open", value: Double(room.doors.count), unit: .count),
                    ScanStat(label: "Fenster", icon: "window.vertical.closed", value: Double(room.windows.count), unit: .count),
                    ScanStat(label: "Öffnungen", icon: "rectangle.dashed", value: Double(room.openings.count), unit: .count),
                    ScanStat(label: "Objekte", icon: "sofa.fill", value: Double(room.objects.count), unit: .count)
                ]
                if summary.volume > 0 {
                    stats.insert(ScanStat(label: "Volumen", icon: "cube", value: Double(summary.volume), unit: .text, text: "\(Double(summary.volume).formatted(.number.precision(.fractionLength(1)))) m³"), at: 3)
                }

                let item = ScanItem(
                    id: id, name: scanName, kind: .room, createdAt: Date(),
                    primaryFile: usdzName, files: [usdzName, jsonName],
                    stats: stats, details: summary.objectDescriptions
                )
                await store.generateThumbnail(forID: id, primaryFile: usdzName)
                store.add(item)
                Haptics.success()
                isSaving = false
                dismiss()
            } catch {
                try? FileManager.default.removeItem(at: folder)
                isSaving = false
                Haptics.error()
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Kennzahlen eines RoomPlan-Ergebnisses.
struct RoomSummary {
    let floorArea: Float
    let wallLength: Float
    let height: Float
    let volume: Float
    let objectDescriptions: [String]

    init(room: CapturedRoom) {
        var area: Float = 0
        for floor in room.floors {
            let corners = floor.polygonCorners
            if corners.count >= 3 {
                area += MeasureMath.polygonArea(corners)
            } else {
                let d = floor.dimensions
                area += max(d.x * d.y, d.x * d.z)
            }
        }
        if area == 0 {
            // Fallback: Fläche aus Wandumriss abschätzen
            let lengths = room.walls.map { $0.dimensions.x }
            if lengths.count >= 2 {
                let sorted = lengths.sorted(by: >)
                area = sorted[0] * sorted[1]
            }
        }
        floorArea = area
        wallLength = room.walls.reduce(0) { $0 + $1.dimensions.x }
        height = room.walls.map { $0.dimensions.y }.max() ?? 0
        volume = floorArea * height

        var counts: [String: Int] = [:]
        for object in room.objects {
            counts[Self.name(for: object.category), default: 0] += 1
        }
        objectDescriptions = counts.sorted { $0.value > $1.value }.map { "\($0.value)× \($0.key)" }
    }

    static func name(for category: CapturedRoom.Object.Category) -> String {
        let key = String(describing: category)
        let names: [String: String] = [
            "storage": "Schrank", "refrigerator": "Kühlschrank", "stove": "Herd", "bed": "Bett",
            "sink": "Spüle", "washerDryer": "Waschmaschine", "toilet": "Toilette", "bathtub": "Badewanne",
            "oven": "Ofen", "dishwasher": "Geschirrspüler", "table": "Tisch", "sofa": "Sofa",
            "chair": "Stuhl", "fireplace": "Kamin", "television": "Fernseher", "stairs": "Treppe"
        ]
        return names[key] ?? key.capitalized
    }
}
