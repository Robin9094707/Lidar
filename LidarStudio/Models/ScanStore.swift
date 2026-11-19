import SwiftUI
import SceneKit

/// Verwaltet alle gespeicherten Scans in Documents/Scans (auch in der Dateien-App sichtbar).
@MainActor
@Observable
final class ScanStore {
    private(set) var items: [ScanItem] = []
    private(set) var thumbnailVersion = 0
    let rootURL: URL

    private var indexURL: URL { rootURL.appending(path: "index.json") }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = docs.appending(path: "Scans", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ScanItem].self, from: data) {
            items = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: Pfade

    func folderURL(for id: UUID) -> URL {
        let url = rootURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fileURL(_ item: ScanItem, _ name: String) -> URL {
        folderURL(for: item.id).appending(path: name)
    }

    func primaryURL(_ item: ScanItem) -> URL {
        fileURL(item, item.primaryFile)
    }

    func thumbnailURL(_ item: ScanItem) -> URL {
        fileURL(item, "thumbnail.jpg")
    }

    func fileURLs(_ item: ScanItem) -> [URL] {
        item.files.map { fileURL(item, $0) }
    }

    // MARK: Bearbeiten

    func add(_ item: ScanItem) {
        var item = item
        if item.environment == nil {
            item.environment = SensorHub.shared.snapshot()
        }
        items.insert(item, at: 0)
        persist()
    }

    func update(_ item: ScanItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        persist()
    }

    func rename(_ item: ScanItem, to name: String) {
        var copy = item
        copy.name = name
        update(copy)
    }

    func toggleFavorite(_ item: ScanItem) {
        var copy = item
        copy.isFavorite.toggle()
        update(copy)
    }

    func delete(_ item: ScanItem) {
        try? FileManager.default.removeItem(at: rootURL.appending(path: item.id.uuidString, directoryHint: .isDirectory))
        items.removeAll { $0.id == item.id }
        persist()
    }

    func deleteAll() {
        for item in items {
            try? FileManager.default.removeItem(at: rootURL.appending(path: item.id.uuidString, directoryHint: .isDirectory))
        }
        items.removeAll()
        persist()
    }

    func item(with id: UUID) -> ScanItem? {
        items.first { $0.id == id }
    }

    // MARK: Größe

    func totalSize() -> Int64 {
        Self.directorySize(rootURL)
    }

    func size(of item: ScanItem) -> Int64 {
        Self.directorySize(rootURL.appending(path: item.id.uuidString, directoryHint: .isDirectory))
    }

    nonisolated static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    nonisolated static func fileSize(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Int64(size)
    }

    // MARK: Vorschaubilder

    func saveThumbnail(_ image: UIImage, for id: UUID) {
        let url = folderURL(for: id).appending(path: "thumbnail.jpg")
        if let data = image.jpegData(compressionQuality: 0.82) {
            try? data.write(to: url, options: .atomic)
            thumbnailVersion += 1
        }
    }

    /// Rendert ein 3D-Vorschaubild aus der Primärdatei.
    func generateThumbnail(forID id: UUID, primaryFile: String) async {
        let url = folderURL(for: id).appending(path: primaryFile)
        let prepared = await Task.detached(priority: .utility) {
            SceneLoader.prepare(url: url)
        }.value
        guard let prepared else { return }
        let image = ThumbnailRenderer.render(prepared)
        saveThumbnail(image, for: id)
    }
}
