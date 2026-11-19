import SwiftUI
import ARKit

/// Aufnahmebildschirm für 3D-Mesh und Punktwolke.
struct LidarCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScanStore.self) private var store
    @State private var controller: LidarCaptureController
    @State private var showSave = false
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showLegend = false

    init(mode: LidarCaptureController.Mode) {
        _controller = State(initialValue: LidarCaptureController(mode: mode))
    }

    private var kind: ScanKind { controller.mode == .mesh ? .mesh : .pointCloud }

    var body: some View {
        ZStack {
            if controller.isSupported {
                ARSCNContainer(view: controller.sceneView)
                    .ignoresSafeArea()
                hud
            } else {
                UnsupportedFeatureView(
                    title: "LiDAR erforderlich",
                    message: "Dieser Modus benötigt ein iPhone oder iPad mit LiDAR-Scanner (z. B. iPhone Pro oder iPad Pro).",
                    onClose: { dismiss() }
                )
            }

            if isSaving {
                ProcessingOverlay(title: controller.mode == .mesh ? "3D-Modell wird exportiert …" : "Punktwolke wird gespeichert …")
            }
        }
        .statusBarHidden()
        .onAppear { controller.start() }
        .onDisappear { controller.pause() }
        .sheet(isPresented: $showSave) {
            SaveScanSheet(kind: kind, name: $name, onSave: save, onCancel: { showSave = false })
        }
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 14) {
            CaptureTopBar(
                title: kind.title,
                systemImage: kind.icon,
                tint: kind.tint,
                onClose: { dismiss() }
            )

            HintBanner(text: controller.trackingMessage ?? idleHint, systemImage: controller.trackingMessage == nil ? "hand.point.up.left.fill" : "exclamationmark.triangle.fill")

            Spacer()

            if showLegend && controller.mode == .mesh {
                legend
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            statsRow

            controls
                .padding(.bottom, 12)
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: controller.isRecording)
        .animation(.spring(duration: 0.45, bounce: 0.25), value: controller.hasCapture)
        .animation(.spring(duration: 0.45), value: showLegend)
    }

    private var idleHint: String? {
        if controller.isRecording {
            return controller.mode == .mesh ? "Langsam schwenken – Wände, Boden und Möbel erfassen" : "Ruhig über die Oberflächen bewegen"
        }
        if controller.isFull { return "Maximale Punktanzahl erreicht" }
        if controller.hasCapture { return nil }
        return "Tippe auf Aufnahme, um zu starten"
    }

    private var statsRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    GlassPill(systemImage: "timer", text: Units.duration(controller.currentDuration), tint: controller.isRecording ? .red : .white)
                }
                if controller.mode == .mesh {
                    GlassPill(systemImage: "square.grid.3x3.fill", text: "\(controller.anchorCount)", tint: Theme.violet)
                    GlassPill(systemImage: "triangle", text: compact(controller.vertexCount), tint: Theme.accent)
                } else {
                    GlassPill(systemImage: "aqi.medium", text: compact(controller.pointCount), tint: Theme.mint)
                }
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 28) {
                GlassIconButton(
                    systemName: "arrow.counterclockwise",
                    size: 56,
                    isEnabled: controller.hasCapture || controller.isRecording
                ) {
                    Haptics.light()
                    controller.reset()
                }

                RecordButton(isRecording: controller.isRecording, idleColor: kind.tint) {
                    controller.toggleRecording()
                }

                if controller.mode == .mesh && !controller.hasCapture {
                    GlassIconButton(systemName: "paintpalette.fill", size: 56, tint: showLegend ? Theme.violet : nil) {
                        showLegend.toggle()
                    }
                } else {
                    GlassIconButton(
                        systemName: "square.and.arrow.down.fill",
                        size: 56,
                        tint: controller.hasCapture && !controller.isRecording ? Theme.accent : nil,
                        isEnabled: controller.hasCapture && !controller.isRecording
                    ) {
                        name = "\(kind.title) \(Date().scanDefaultName)"
                        showSave = true
                    }
                }
            }
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(MeshPalette.legend.indices, id: \.self) { index in
                let entry = MeshPalette.legend[index]
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: Double(entry.1.x), green: Double(entry.1.y), blue: Double(entry.1.z)))
                        .frame(width: 10, height: 10)
                    Text(entry.0)
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 24)
    }

    private func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    // MARK: Speichern

    private func save() {
        showSave = false
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let scanName = trimmed.isEmpty ? kind.title : trimmed
        isSaving = true

        Task {
            let id = UUID()
            let folder = store.folderURL(for: id)
            let baseName = scanName.sanitizedFileName
            do {
                let item: ScanItem
                switch controller.mode {
                case .mesh:
                    let anchors = controller.meshAnchorsForExport()
                    let colored = UserDefaults.standard.object(forKey: "classificationColors") as? Bool ?? true
                    let result = try await Task.detached(priority: .userInitiated) {
                        try MeshExporter.export(anchors: anchors, to: folder, baseName: baseName, colored: colored)
                    }.value
                    var stats = [
                        ScanStat(label: "Vertices", icon: "circle.grid.cross.fill", value: Double(result.vertexCount), unit: .count),
                        ScanStat(label: "Dreiecke", icon: "triangle.fill", value: Double(result.faceCount), unit: .count),
                        ScanStat(label: "Oberfläche", icon: "square.dashed", value: Double(result.surfaceArea), unit: .area),
                        ScanStat(label: "Breite", icon: "arrow.left.and.right", value: Double(result.bounds.x), unit: .length),
                        ScanStat(label: "Höhe", icon: "arrow.up.and.down", value: Double(result.bounds.y), unit: .length),
                        ScanStat(label: "Tiefe", icon: "arrow.up.left.and.arrow.down.right", value: Double(result.bounds.z), unit: .length)
                    ]
                    stats.append(ScanStat(label: "Dauer", icon: "timer", value: controller.currentDuration, unit: .duration))
                    let details = result.classCounts
                        .sorted { $0.value > $1.value }
                        .map { "\($0.key): \($0.value.formatted()) Flächen" }
                    item = ScanItem(
                        id: id, name: scanName, kind: .mesh, createdAt: Date(),
                        primaryFile: result.primaryFile, files: result.files, stats: stats, details: details
                    )

                case .pointCloud:
                    let (positions, colors) = await controller.pointCloudSnapshot()
                    guard !positions.isEmpty else { throw MeshExporter.ExportError.empty }
                    let plyName = "\(baseName).ply"
                    let xyzName = "\(baseName).xyz"
                    let bounds = try await Task.detached(priority: .userInitiated) { () -> SIMD3<Float> in
                        try PLYIO.write(positions: positions, colors: colors, to: folder.appending(path: plyName))
                        try PLYIO.writeXYZ(positions: positions, colors: colors, to: folder.appending(path: xyzName))
                        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                        for p in positions { lo = simd_min(lo, p); hi = simd_max(hi, p) }
                        return hi - lo
                    }.value
                    let stats = [
                        ScanStat(label: "Punkte", icon: "aqi.medium", value: Double(positions.count), unit: .count),
                        ScanStat(label: "Breite", icon: "arrow.left.and.right", value: Double(bounds.x), unit: .length),
                        ScanStat(label: "Höhe", icon: "arrow.up.and.down", value: Double(bounds.y), unit: .length),
                        ScanStat(label: "Tiefe", icon: "arrow.up.left.and.arrow.down.right", value: Double(bounds.z), unit: .length),
                        ScanStat(label: "Dauer", icon: "timer", value: controller.currentDuration, unit: .duration)
                    ]
                    item = ScanItem(
                        id: id, name: scanName, kind: .pointCloud, createdAt: Date(),
                        primaryFile: plyName, files: [plyName, xyzName], stats: stats
                    )
                }

                await store.generateThumbnail(forID: id, primaryFile: item.primaryFile)
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
