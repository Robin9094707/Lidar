import SwiftUI
import QuickLook

struct ScanDetailView: View {
    let itemID: UUID
    @Environment(ScanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var prepared: PreparedScene?
    @State private var loadFailed = false
    @State private var quickLookURL: URL?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var measurement: MeasurementRecord?
    @State private var viewerExpanded = false

    private var item: ScanItem? { store.item(with: itemID) }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                ContentUnavailableView("Scan nicht gefunden", systemImage: "questionmark.folder")
            }
        }
        .background(AuroraBackground())
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($quickLookURL)
        .task(id: itemID) { await load() }
    }

    @ViewBuilder
    private func content(_ item: ScanItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                viewer(item)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: item.kind.icon)
                        Text(item.kind.title)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.kind.tint)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassEffect(.regular.tint(item.kind.tint.opacity(0.2)), in: .capsule)

                    Text(item.name)
                        .font(.largeTitle.weight(.bold))
                    Text(item.createdAt, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                actionBar(item)

                if !item.stats.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(item.stats) { stat in
                            StatTile(stat: stat)
                        }
                    }
                }

                if let measurement {
                    measurementSection(measurement)
                }

                if !item.details.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.kind == .room ? "Erkannte Objekte" : "Details")
                            .font(.headline)
                        ForEach(item.details, id: \.self) { line in
                            Label(line, systemImage: "smallcircle.filled.circle")
                                .font(.subheadline)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                }

                filesSection(item)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.light()
                    store.toggleFavorite(item)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(item.isFavorite ? Theme.yellow : .white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = item.name
                        renaming = true
                    } label: {
                        Label("Umbenennen", systemImage: "pencil")
                    }
                    ShareLink(items: store.fileURLs(item)) {
                        Label("Alle Dateien teilen", systemImage: "square.and.arrow.up.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert("Umbenennen", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { store.rename(item, to: trimmed) }
            }
        }
        .confirmationDialog("Scan löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                store.delete(item)
                dismiss()
            }
        } message: {
            Text("Dieser Vorgang kann nicht rückgängig gemacht werden.")
        }
    }

    // MARK: 3D-Ansicht

    private func viewer(_ item: ScanItem) -> some View {
        ZStack {
            if let prepared {
                ModelViewer(prepared: prepared)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if loadFailed {
                ThumbnailView(url: store.thumbnailURL(item), kind: item.kind)
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("3D-Ansicht wird geladen …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: viewerExpanded ? 520 : 360)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 32))
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .overlay(alignment: .bottomTrailing) {
            GlassIconButton(systemName: viewerExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", size: 40) {
                withAnimation(.spring(duration: 0.5, bounce: 0.25)) { viewerExpanded.toggle() }
            }
            .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            if prepared != nil {
                Label("Drehen · Zoomen", systemImage: "hand.draw")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(14)
            }
        }
        .animation(.smooth, value: prepared != nil)
    }

    private func actionBar(_ item: ScanItem) -> some View {
        let usdz = item.files.first { $0.lowercased().hasSuffix(".usdz") }
        return GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if let usdz {
                    Button {
                        Haptics.tap()
                        quickLookURL = store.fileURL(item, usdz)
                    } label: {
                        Label("In AR ansehen", systemImage: "arkit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                ShareLink(items: store.fileURLs(item)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: usdz == nil ? .infinity : nil)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }

    private func measurementSection(_ record: MeasurementRecord) -> some View {
        let positions = record.points.map(\.position)
        let segments = MeasureMath.segments(tool: record.tool, points: positions)
        return VStack(alignment: .leading, spacing: 12) {
            if !segments.isEmpty {
                Text("Strecken").font(.headline)
                ForEach(segments) { segment in
                    HStack {
                        Label("Strecke \(segment.id + 1)", systemImage: "line.diagonal")
                        Spacer()
                        Text(Units.length(segment.length))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Divider()
            }
            Text("Gespeicherte Punkte").font(.headline)
            ForEach(Array(record.points.enumerated()), id: \.element.id) { index, point in
                HStack(alignment: .firstTextBaseline) {
                    Text("P\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.pink)
                        .frame(width: 36, alignment: .leading)
                    Text(Units.coordinate(point.position))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func filesSection(_ item: ScanItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dateien").font(.headline)
            ForEach(item.files, id: \.self) { file in
                let url = store.fileURL(item, file)
                HStack(spacing: 12) {
                    Image(systemName: icon(for: file))
                        .foregroundStyle(item.kind.tint)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(Units.bytes(ScanStore.fileSize(url)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass)
                }
            }
            Text("Gesamt: \(Units.bytes(store.size(of: item)))  ·  Auch in der Dateien-App unter „LiDAR Studio“")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func icon(for file: String) -> String {
        switch (file as NSString).pathExtension.lowercased() {
        case "usdz": return "arkit"
        case "obj", "ply": return "cube.transparent"
        case "json": return "curlybraces"
        case "csv", "xyz": return "tablecells"
        default: return "doc"
        }
    }

    // MARK: Laden

    private func load() async {
        guard let item else { return }
        if item.kind == .measurement,
           let data = try? Data(contentsOf: store.primaryURL(item)) {
            measurement = try? JSONDecoder().decode(MeasurementRecord.self, from: data)
        }
        let url = store.primaryURL(item)
        let result = await Task.detached(priority: .userInitiated) {
            SceneLoader.prepare(url: url)
        }.value
        if let result {
            withAnimation(.smooth) { prepared = result }
        } else {
            loadFailed = true
        }
    }
}
