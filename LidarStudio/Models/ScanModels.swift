import SwiftUI

enum ScanKind: String, Codable, CaseIterable, Identifiable {
    case room, object, mesh, pointCloud, measurement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .room: "Raum"
        case .object: "Objekt"
        case .mesh: "3D-Mesh"
        case .pointCloud: "Punktwolke"
        case .measurement: "Messung"
        }
    }

    var pluralTitle: String {
        switch self {
        case .room: "Räume"
        case .object: "Objekte"
        case .mesh: "Meshes"
        case .pointCloud: "Punktwolken"
        case .measurement: "Messungen"
        }
    }

    var icon: String {
        switch self {
        case .room: "house.fill"
        case .object: "cube.fill"
        case .mesh: "cube.transparent"
        case .pointCloud: "aqi.medium"
        case .measurement: "ruler.fill"
        }
    }

    var tint: Color {
        switch self {
        case .room: Theme.accent
        case .object: Theme.orange
        case .mesh: Theme.violet
        case .pointCloud: Theme.mint
        case .measurement: Theme.pink
        }
    }
}

enum ScanMode: String, Identifiable, CaseIterable {
    case room, object, mesh, pointCloud, measure

    var id: String { rawValue }

    var kind: ScanKind {
        switch self {
        case .room: .room
        case .object: .object
        case .mesh: .mesh
        case .pointCloud: .pointCloud
        case .measure: .measurement
        }
    }

    var title: String {
        switch self {
        case .room: "Raum scannen"
        case .object: "Objekt erfassen"
        case .mesh: "3D-Mesh"
        case .pointCloud: "Punktwolke"
        case .measure: "Messen"
        }
    }

    var subtitle: String {
        switch self {
        case .room: "Grundriss, Wände, Türen, Fenster und Möbel automatisch als 3D-Modell"
        case .object: "Fotorealistisches 3D-Modell mit Texturen"
        case .mesh: "Live-Geometrie mit Klassifizierung"
        case .pointCloud: "Farbige Tiefenpunkte erfassen"
        case .measure: "Strecken, Flächen und Punkte"
        }
    }

    var icon: String { kind.icon }
    var tint: Color { kind.tint }
}

enum StatUnit: String, Codable {
    case count, length, area, duration, text
}

struct ScanStat: Codable, Hashable, Identifiable {
    var id: String { label }
    var label: String
    var icon: String
    var value: Double
    var unit: StatUnit
    var text: String? = nil

    var formattedValue: String {
        switch unit {
        case .count: return Int(value).formatted()
        case .length: return Units.length(Float(value))
        case .area: return Units.area(Float(value))
        case .duration: return Units.duration(value)
        case .text: return text ?? ""
        }
    }
}

struct ScanItem: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var kind: ScanKind
    var createdAt: Date
    var primaryFile: String
    var files: [String]
    var stats: [ScanStat]
    var isFavorite: Bool = false
    var details: [String] = []
    var environment: EnvironmentSnapshot? = nil
}
