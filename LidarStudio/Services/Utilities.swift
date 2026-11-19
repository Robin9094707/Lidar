import SwiftUI
import ARKit
import RoomPlan
import RealityKit

enum Units {
    static var imperial: Bool { UserDefaults.standard.bool(forKey: "useImperial") }

    static func length(_ meters: Float) -> String {
        let m = Double(meters)
        if imperial {
            let inches = m * 39.3701
            if inches < 12 {
                return "\(inches.formatted(.number.precision(.fractionLength(1)))) in"
            }
            let feet = Int(inches / 12)
            let rest = inches - Double(feet) * 12
            return "\(feet)′ \(rest.formatted(.number.precision(.fractionLength(1))))″"
        }
        if m < 1 {
            return "\((m * 100).formatted(.number.precision(.fractionLength(1)))) cm"
        }
        return "\(m.formatted(.number.precision(.fractionLength(2)))) m"
    }

    static func area(_ squareMeters: Float) -> String {
        let a = Double(squareMeters)
        if imperial {
            return "\((a * 10.7639).formatted(.number.precision(.fractionLength(1)))) ft²"
        }
        if a < 0.1 {
            return "\((a * 10_000).formatted(.number.precision(.fractionLength(0)))) cm²"
        }
        return "\(a.formatted(.number.precision(.fractionLength(2)))) m²"
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func coordinate(_ v: SIMD3<Float>) -> String {
        let f: (Float) -> String = { Double($0).formatted(.number.precision(.fractionLength(3))) }
        return "x \(f(v.x))  y \(f(v.y))  z \(f(v.z))"
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

@MainActor
enum Haptics {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true }

    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func light() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

@MainActor
enum DeviceCapabilities {
    static var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    static var supportsSceneDepth: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    static var supportsRoomPlan: Bool {
        RoomCaptureSession.isSupported
    }

    static var supportsObjectCapture: Bool {
        ObjectCaptureSession.isSupported
    }

    static var supportsPhotogrammetry: Bool {
        PhotogrammetrySession.isSupported
    }
}

enum TrackingText {
    static func message(for state: ARCamera.TrackingState) -> String? {
        switch state {
        case .normal:
            return nil
        case .notAvailable:
            return "Tracking nicht verfügbar"
        case .limited(let reason):
            switch reason {
            case .initializing: return "Initialisiere – bewege das iPhone langsam"
            case .excessiveMotion: return "Bitte langsamer bewegen"
            case .insufficientFeatures: return "Zu wenig Details – mehr Licht oder Struktur"
            case .relocalizing: return "Relokalisierung …"
            @unknown default: return "Tracking eingeschränkt"
            }
        @unknown default:
            return nil
        }
    }
}

/// UIViewRepresentable für eine vom Controller gehaltene AR-Ansicht.
struct ARSCNContainer: UIViewRepresentable {
    let view: ARSCNView

    func makeUIView(context: Context) -> ARSCNView { view }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

extension simd_float4x4 {
    var translation: SIMD3<Float> { SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z) }
}

extension String {
    var sanitizedFileName: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Scan" : cleaned
    }
}

extension Date {
    var scanDefaultName: String {
        formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}
