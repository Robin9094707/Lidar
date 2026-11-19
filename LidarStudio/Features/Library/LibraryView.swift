import SwiftUI

struct LibraryView: View {
    @Environment(ScanStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var filter: ScanKind?
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var sortNewestFirst = true
    @State private var itemToDelete: ScanItem?

    private var filtered: [ScanItem] {
        var result = store.items
        if let filter { result = result.filter { $0.kind == filter } }
        if favoritesOnly { result = result.filter(\.isFavorite) }
        if !search.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.kind.title.localizedCaseInsensitiveContains(search) }
        }
        return result.sorted { sortNewestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filterBar

                    if filtered.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                            ForEach(filtered) { item in
                                NavigationLink(value: item.id) {
                                    ScanCard(item: item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        store.toggleFavorite(item)
                                    } label: {
                                        Label(item.isFavorite ? "Favorit entfernen" : "Als Favorit", systemImage: item.isFavorite ? "star.slash" : "star")
                                    }
                                    ShareLink(item: store.primaryURL(item)) {
                                        Label("Teilen", systemImage: "square.and.arrow.up")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                            }
                        }
                        .animation(.spring(duration: 0.45), value: filtered.map(\.id))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(AuroraBackground())
            .navigationTitle("Bibliothek")
            .searchable(text: $search, prompt: "Scans durchsuchen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sortierung", selection: $sortNewestFirst) {
                            Label("Neueste zuerst", systemImage: "arrow.down").tag(true)
                            Label("Älteste zuerst", systemImage: "arrow.up").tag(false)
                        }
                        Toggle(isOn: $favoritesOnly) {
                            Label("Nur Favoriten", systemImage: "star.fill")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ScanDetailView(itemID: id)
            }
            .confirmationDialog(
                "Scan löschen?",
                isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    if let item = itemToDelete {
                        withAnimation { store.delete(item) }
                    }
                    itemToDelete = nil
                }
            } message: {
                Text("Alle Dateien dieses Scans werden entfernt.")
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    FilterChip(title: "Alle", icon: "square.grid.2x2.fill", tint: .white, isSelected: filter == nil) {
                        filter = nil
                    }
                    ForEach(ScanKind.allCases) { kind in
                        FilterChip(title: kind.pluralTitle, icon: kind.icon, tint: kind.tint, isSelected: filter == kind) {
                            filter = filter == kind ? nil : kind
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
        .animation(.spring(duration: 0.35), value: filter)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(Theme.titleGradient)
                .frame(width: 110, height: 110)
                .glassEffect(.regular, in: .circle)
            Text(store.items.isEmpty ? "Noch keine Scans" : "Keine Treffer")
                .font(.title3.weight(.bold))
            Text(store.items.isEmpty ? "Starte deinen ersten LiDAR-Scan – Räume, Objekte, Punktwolken oder Messungen." : "Passe Filter oder Suche an.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if store.items.isEmpty {
                Button {
                    router.start(.room)
                } label: {
                    Label("Ersten Raum scannen", systemImage: "viewfinder")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.top, 30)
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? Glass.regular.tint(tint.opacity(0.45)).interactive() : Glass.regular.interactive(), in: .capsule)
    }
}

struct ScanCard: View {
    let item: ScanItem
    @Environment(ScanStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThumbnailView(url: store.thumbnailURL(item), kind: item.kind)
                .id(store.thumbnailVersion)
                .frame(height: 128)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) {
                    Image(systemName: item.kind.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.kind.tint)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular, in: .circle)
                        .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.yellow)
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular, in: .circle)
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack {
                    Text(item.kind.title)
                        .foregroundStyle(item.kind.tint)
                    Spacer()
                    Text(item.createdAt, format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
                if let stat = item.stats.first {
                    Text("\(stat.label): \(stat.formattedValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .clipShape(.rect(cornerRadius: 24))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }
}

struct ThumbnailView: View {
    let url: URL
    let kind: ScanKind

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [kind.tint.opacity(0.35), Theme.violet.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: kind.icon)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
