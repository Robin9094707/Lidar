import SceneKit
import UIKit

/// Eine vorbereitete Szene inklusive Kamera, die das Modell einrahmt.
struct PreparedScene {
    let scene: SCNScene
    let cameraNode: SCNNode
    let center: SIMD3<Float>
    let radius: Float
}

enum SceneLoader {
    /// Lädt USDZ / OBJ / PLY / Messungs-JSON und bereitet Kamera & Licht vor.
    static func prepare(url: URL) -> PreparedScene? {
        guard let scene = loadScene(url: url) else { return nil }
        return prepare(scene: scene)
    }

    static func loadScene(url: URL) -> SCNScene? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        switch url.pathExtension.lowercased() {
        case "ply":
            guard let cloud = try? PLYIO.read(url: url) else { return nil }
            let scene = SCNScene()
            scene.rootNode.addChildNode(PointCloudGeometry.node(positions: cloud.positions, colors: cloud.colors, pointSize: 2.5))
            return scene
        case "json":
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(MeasurementRecord.self, from: data) else { return nil }
            let scene = SCNScene()
            scene.rootNode.addChildNode(MeasureSceneBuilder.build(points: record.points.map(\.position), tool: record.tool, labelScale: 1.4))
            return scene
        default:
            return try? SCNScene(url: url, options: nil)
        }
    }

    static func prepare(scene: SCNScene) -> PreparedScene {
        let bounds = worldBounds(of: scene.rootNode) ?? (SIMD3<Float>(repeating: -0.5), SIMD3<Float>(repeating: 0.5))
        let center = (bounds.0 + bounds.1) / 2
        let radius = max(simd_length(bounds.1 - bounds.0) / 2, 0.05)

        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.zNear = Double(max(radius * 0.01, 0.001))
        camera.zFar = Double(radius * 30 + 10)
        camera.wantsHDR = false

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "viewerCamera"
        let direction = simd_normalize(SIMD3<Float>(0.75, 0.85, 1.15))
        cameraNode.simdPosition = center + direction * radius * 2.6
        cameraNode.simdLook(at: center)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 450
        ambient.light?.color = UIColor(white: 0.9, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.simdPosition = center + SIMD3<Float>(1, 3, 2) * radius
        key.simdLook(at: center)
        scene.rootNode.addChildNode(key)

        return PreparedScene(scene: scene, cameraNode: cameraNode, center: center, radius: radius)
    }

    static func worldBounds(of root: SCNNode) -> (SIMD3<Float>, SIMD3<Float>)? {
        var minV = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            let (a, b) = geometry.boundingBox
            let lo = SIMD3<Float>(a.x, a.y, a.z)
            let hi = SIMD3<Float>(b.x, b.y, b.z)
            if lo.x > hi.x { return }
            let transform = node.simdWorldTransform
            for i in 0..<8 {
                let corner = SIMD3<Float>(
                    i & 1 == 0 ? lo.x : hi.x,
                    i & 2 == 0 ? lo.y : hi.y,
                    i & 4 == 0 ? lo.z : hi.z
                )
                let world = (transform * SIMD4<Float>(corner, 1)).xyz
                minV = simd_min(minV, world)
                maxV = simd_max(maxV, world)
                found = true
            }
        }
        return found ? (minV, maxV) : nil
    }
}

enum ThumbnailRenderer {
    @MainActor
    static func render(_ prepared: PreparedScene, size: CGSize = CGSize(width: 640, height: 480)) -> UIImage {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        prepared.scene.background.contents = UIColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1)
        renderer.scene = prepared.scene
        renderer.pointOfView = prepared.cameraNode
        renderer.autoenablesDefaultLighting = true
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        prepared.scene.background.contents = nil
        return image
    }
}

/// SwiftUI-Wrapper um SCNView mit Orbit-Steuerung und transparentem Hintergrund.
struct ModelViewer: UIViewRepresentable {
    let prepared: PreparedScene
    var autoRotate: Bool = false

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = prepared.scene
        view.pointOfView = prepared.cameraNode
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.target = SCNVector3(prepared.center)
        view.defaultCameraController.maximumVerticalAngle = 89
        view.defaultCameraController.minimumVerticalAngle = -89
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
