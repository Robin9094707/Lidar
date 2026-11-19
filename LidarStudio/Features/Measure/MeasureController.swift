import ARKit
import SceneKit
import SwiftUI

@Observable
final class MeasureController: NSObject, ARSCNViewDelegate, ARSessionDelegate {
    let sceneView = ARSCNView(frame: .zero)
    let isSupported: Bool
    let hasLiDAR: Bool

    private(set) var tool: MeasureTool = .distance
    private(set) var points: [MeasurePoint] = []
    var hasTarget = false
    var liveDistance: Float?
    var trackingMessage: String?
    var targetDistanceFromCamera: Float?

    private let contentNode = SCNNode()
    private let liveNode = SCNNode()
    @ObservationIgnored private var target: SIMD3<Float>?
    @ObservationIgnored private var frameCounter = 0

    override init() {
        isSupported = ARWorldTrackingConfiguration.isSupported
        hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        super.init()
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene.rootNode.addChildNode(contentNode)
        sceneView.scene.rootNode.addChildNode(liveNode)
    }

    // MARK: Session

    func start() {
        guard isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() {
        sceneView.session.pause()
    }

    // MARK: Bearbeiten

    func setTool(_ newTool: MeasureTool) {
        guard newTool != tool else { return }
        tool = newTool
        points.removeAll()
        rebuild()
    }

    @MainActor
    func addPoint() {
        guard var position = target else {
            Haptics.error()
            return
        }
        // Fläche schließen: Einrasten am ersten Punkt
        if tool == .area, points.count >= 3, let first = points.first, simd_distance(first.position, position) < 0.03 {
            position = first.position
            Haptics.success()
            rebuild()
            return
        }
        points.append(MeasurePoint(position: position))
        Haptics.tap()
        rebuild()
    }

    @MainActor
    func undo() {
        guard !points.isEmpty else { return }
        points.removeLast()
        Haptics.light()
        rebuild()
    }

    @MainActor
    func clear() {
        points.removeAll()
        Haptics.light()
        rebuild()
    }

    private func rebuild() {
        contentNode.childNodes.forEach { $0.removeFromParentNode() }
        contentNode.addChildNode(MeasureSceneBuilder.build(points: points.map(\.position), tool: tool))
    }

    // MARK: Ergebnisse

    var segments: [MeasureSegment] {
        MeasureMath.segments(tool: tool, points: points.map(\.position))
    }

    var totalLength: Float {
        MeasureMath.totalLength(tool: tool, points: points.map(\.position))
    }

    var area: Float {
        tool == .area ? MeasureMath.polygonArea(points.map(\.position)) : 0
    }

    var canSave: Bool {
        switch tool {
        case .distance: points.count >= 2
        case .path: points.count >= 2
        case .area: points.count >= 3
        case .points: points.count >= 1
        }
    }

    func snapshot() -> UIImage {
        sceneView.snapshot()
    }

    // MARK: Live-Ziel

    private var pendingStart: SIMD3<Float>? {
        switch tool {
        case .distance: return points.count % 2 == 1 ? points.last?.position : nil
        case .path, .area: return points.last?.position
        case .points: return nil
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
        guard frameCounter % 2 == 0 else { return }
        updateTarget(frame: frame)
    }

    private func updateTarget(frame: ARFrame) {
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        var hit: SIMD3<Float>?
        if let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any),
           let result = sceneView.session.raycast(query).first {
            hit = result.worldTransform.translation
        } else if let query = sceneView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .any),
                  let result = sceneView.session.raycast(query).first {
            hit = result.worldTransform.translation
        }

        target = hit
        if hasTarget != (hit != nil) { hasTarget = hit != nil }
        targetDistanceFromCamera = hit.map { simd_distance($0, frame.camera.transform.translation) }

        liveNode.childNodes.forEach { $0.removeFromParentNode() }
        if let hit, let start = pendingStart {
            liveDistance = simd_distance(start, hit)
            let line = MeasureSceneBuilder.line(from: start, to: hit, color: UIColor.white.withAlphaComponent(0.85), radius: 0.0015)
            liveNode.addChildNode(line)
        } else {
            liveDistance = nil
        }
        if let hit {
            let dot = MeasureSceneBuilder.sphere(at: hit, color: Theme.uiAccent)
            dot.opacity = 0.8
            liveNode.addChildNode(dot)
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message = TrackingText.message(for: camera.trackingState)
        DispatchQueue.main.async { self.trackingMessage = message }
    }
}
