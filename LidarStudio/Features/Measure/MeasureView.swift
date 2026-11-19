import SwiftUI

struct MeasureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScanStore.self) private var store
    @State private var controller = MeasureController()
    @State private var showSave = false
    @State private var name = ""
    @State private var showList = false
    @Namespace private var glassNamespace

    var body: some View {
        ZStack {
            if controller.isSupported {
                ARSCNContainer(view: controller.sceneView)
                    .ignoresSafeArea()
                Reticle(hasTarget: controller.hasTarget)
                    .allowsHitTesting(false)
                hud
            } else {
                UnsupportedFeatureView(
                    title: "AR nicht verfügbar",
                    message: "Dieses Gerät unterstützt kein ARKit-Welttracking.",
                    onClose: { dismiss() }
                )
            }
        }
        .statusBarHidden()
        .onAppear { controller.start() }
        .onDisappear { controller.pause() }
        .sheet(isPresented: $showSave) {
            SaveScanSheet(kind: .measurement, name: $name, onSave: save, onCancel: { showSave = false })
        }
        .sheet(isPresented: $showList) {
            MeasurementListSheet(controller: controller)
        }
    }

    private var hud: some View {
        VStack(spacing: 12) {
            CaptureTopBar(title: "Messen", systemImage: "ruler.fill", tint: Theme.pink, onClose: { dismiss() })

            HintBanner(
                text: controller.trackingMessage ?? (controller.points.isEmpty ? controller.tool.hint : nil),
                systemImage: controller.trackingMessage == nil ? "scope" : "exclamationmark.triangle.fill"
            )

            if !controller.hasLiDAR {
                Label("Ohne LiDAR – Genauigkeit eingeschränkt", systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glassEffect(.regular.tint(.orange.opacity(0.3)), in: .capsule)
            }

            Spacer()

            readout

            toolPicker

            controls
                .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: controller.points.count)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: controller.tool)
    }

    // Live-Anzeige der aktuellen Werte
    private var readout: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let live = controller.liveDistance {
                    GlassPill(systemImage: "arrow.left.and.right", text: Units.length(live), tint: Theme.accent)
                        .glassEffectID("live", in: glassNamespace)
                } else if let d = controller.targetDistanceFromCamera {
                    GlassPill(systemImage: "camera.metering.spot", text: Units.length(d), tint: .white)
                        .glassEffectID("live", in: glassNamespace)
                }
                switch controller.tool {
                case .distance, .path:
                    if controller.totalLength > 0 {
                        GlassPill(systemImage: "sum", text: Units.length(controller.totalLength), tint: Theme.pink)
                            .glassEffectID("total", in: glassNamespace)
                    }
                case .area:
                    if controller.points.count >= 3 {
                        GlassPill(systemImage: "skew", text: Units.area(controller.area), tint: Theme.violet)
                            .glassEffectID("area", in: glassNamespace)
                        GlassPill(systemImage: "sum", text: Units.length(controller.totalLength), tint: Theme.pink)
                            .glassEffectID("total", in: glassNamespace)
                    }
                case .points:
                    if !controller.points.isEmpty {
                        GlassPill(systemImage: "mappin", text: "\(controller.points.count)", tint: Theme.pink)
                            .glassEffectID("total", in: glassNamespace)
                    }
                }
            }
        }
    }

    private var toolPicker: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(MeasureTool.allCases) { tool in
                    let selected = controller.tool == tool
                    Button {
                        Haptics.light()
                        withAnimation(.spring(duration: 0.35)) { controller.setTool(tool) }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 17, weight: .semibold))
                            Text(tool.title)
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(selected ? .white : .white.opacity(0.7))
                        .frame(width: 70, height: 52)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        selected ? Glass.regular.tint(Theme.pink.opacity(0.45)).interactive() : Glass.regular.interactive(),
                        in: .capsule
                    )
                }
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 22) {
            HStack(spacing: 22) {
                GlassIconButton(systemName: "arrow.uturn.backward", size: 54, isEnabled: !controller.points.isEmpty) {
                    controller.undo()
                }
                GlassIconButton(systemName: "list.bullet", size: 54, isEnabled: !controller.points.isEmpty) {
                    showList = true
                }

                Button {
                    controller.addPoint()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 86, height: 86)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.pink.opacity(controller.hasTarget ? 0.55 : 0.15)).interactive(), in: .circle)

                GlassIconButton(systemName: "trash", size: 54, isEnabled: !controller.points.isEmpty) {
                    controller.clear()
                }
                GlassIconButton(
                    systemName: "square.and.arrow.down.fill",
                    size: 54,
                    tint: controller.canSave ? Theme.accent : nil,
                    isEnabled: controller.canSave
                ) {
                    name = "\(controller.tool.title) \(Date().scanDefaultName)"
                    showSave = true
                }
            }
        }
    }

    private func save() {
        showSave = false
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let scanName = trimmed.isEmpty ? "Messung" : trimmed
        let id = UUID()
        let folder = store.folderURL(for: id)
        let record = MeasurementRecord(tool: controller.tool, points: controller.points, createdAt: Date())

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: folder.appending(path: "measurement.json"))

            var csv = "index;x;y;z\n"
            for (i, p) in controller.points.enumerated() {
                csv += "\(i + 1);\(p.position.x);\(p.position.y);\(p.position.z)\n"
            }
            try csv.write(to: folder.appending(path: "punkte.csv"), atomically: true, encoding: .utf8)

            var segmentsCSV = "segment;laenge_m\n"
            for s in controller.segments {
                segmentsCSV += "\(s.id + 1);\(s.length)\n"
            }
            try segmentsCSV.write(to: folder.appending(path: "strecken.csv"), atomically: true, encoding: .utf8)

            var stats: [ScanStat] = [
                ScanStat(label: "Werkzeug", icon: controller.tool.icon, value: 0, unit: .text, text: controller.tool.title),
                ScanStat(label: "Punkte", icon: "mappin.and.ellipse", value: Double(controller.points.count), unit: .count)
            ]
            if controller.tool != .points {
                stats.append(ScanStat(label: "Gesamtlänge", icon: "sum", value: Double(controller.totalLength), unit: .length))
                stats.append(ScanStat(label: "Strecken", icon: "line.diagonal", value: Double(controller.segments.count), unit: .count))
            }
            if controller.tool == .area {
                stats.append(ScanStat(label: "Fläche", icon: "skew", value: Double(controller.area), unit: .area))
            }

            store.saveThumbnail(controller.snapshot(), for: id)
            store.add(ScanItem(
                id: id, name: scanName, kind: .measurement, createdAt: Date(),
                primaryFile: "measurement.json",
                files: ["measurement.json", "punkte.csv", "strecken.csv"],
                stats: stats
            ))
            Haptics.success()
            controller.clear()
        } catch {
            Haptics.error()
        }
    }
}

/// Fadenkreuz in der Bildmitte.
struct Reticle: View {
    let hasTarget: Bool
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 1)
                .frame(width: 64, height: 64)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(hasTarget ? Theme.accent : .white.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 2.4).repeatForever(autoreverses: false), value: spin)
            Circle()
                .fill(hasTarget ? Theme.accent : .white)
                .frame(width: hasTarget ? 10 : 6, height: hasTarget ? 10 : 6)
                .shadow(color: Theme.accent, radius: hasTarget ? 8 : 0)
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.8))
                    .frame(width: 2, height: 10)
                    .offset(y: -42)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
        .animation(.spring(duration: 0.3), value: hasTarget)
        .onAppear { spin = true }
    }
}

struct MeasurementListSheet: View {
    let controller: MeasureController

    var body: some View {
        NavigationStack {
            List {
                if !controller.segments.isEmpty {
                    Section("Strecken") {
                        ForEach(controller.segments) { segment in
                            HStack {
                                Label("Strecke \(segment.id + 1)", systemImage: "line.diagonal")
                                Spacer()
                                Text(Units.length(segment.length))
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
                Section("Punkte") {
                    ForEach(Array(controller.points.enumerated()), id: \.element.id) { index, point in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("P\(index + 1)").font(.headline)
                            Text(Units.coordinate(point.position))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Messwerte")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
