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
    /// LiDAR-Tiefe in der Bildmitte und deren Konfidenz (0 niedrig … 2 hoch)
    var depthConfidence: Int?
    /// Steigung der Live-Strecke in Grad (0 = waagrecht, 90 = senkrecht)
    var liveSlope: Float?

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
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            // Zeitlich geglättete LiDAR-Tiefe: rauschärmer für Einzelmessungen
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.isLightEstimationEnabled = true
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
        MainActor.assumeIsolated { SensorHub.shared.reportAR(frame: frame) }
        let every = SensorHub.throttleFactor > 2 ? 4 : 2
        guard frameCounter % every == 0 else { return }
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

        // LiDAR-Tiefe direkt in der Bildmitte (Median 5×5) als Präzisionsangabe
        // und als Rückfallebene, wenn der Raycast nichts trifft.
        let centerDepth = Self.centerDepth(frame)
        depthConfidence = centerDepth?.confidence
        if hit == nil, let d = centerDepth, d.confidence >= 1 {
            hit = (frame.camera.transform * SIMD4<Float>(0, 0, -d.depth, 1)).xyz
        }

        target = hit
        if hasTarget != (hit != nil) { hasTarget = hit != nil }
        targetDistanceFromCamera = centerDepth?.depth ?? hit.map { simd_distance($0, frame.camera.transform.translation) }

        liveNode.childNodes.forEach { $0.removeFromParentNode() }
        if let hit, let start = pendingStart {
            liveDistance = simd_distance(start, hit)
            let v = hit - start
            let horizontal = simd_length(SIMD2<Float>(v.x, v.z))
            liveSlope = abs(atan2(v.y, horizontal)) * 180 / .pi
            let line = MeasureSceneBuilder.line(from: start, to: hit, color: UIColor.white.withAlphaComponent(0.85), radius: 0.0015)
            liveNode.addChildNode(line)
        } else {
            liveDistance = nil
            liveSlope = nil
        }
        if let hit {
            let dot = MeasureSceneBuilder.sphere(at: hit, color: Theme.uiAccent)
            dot.opacity = 0.8
            liveNode.addChildNode(dot)
        }
    }

    private static func centerDepth(_ frame: ARFrame) -> (depth: Float, confidence: Int)? {
        guard let data = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let map = data.depthMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)
        let row = CVPixelBufferGetBytesPerRow(map)
        var values: [Float] = []
        values.reserveCapacity(25)
        for dy in -2...2 {
            for dx in -2...2 {
                let x = w / 2 + dx
                let y = h / 2 + dy
                let d = base.load(fromByteOffset: y * row + x * 4, as: Float32.self)
                if d.isFinite && d > 0 { values.append(d) }
            }
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        let depth = values[values.count / 2]

        var confidence = 2
        if let conf = data.confidenceMap {
            CVPixelBufferLockBaseAddress(conf, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(conf, .readOnly) }
            if let cb = CVPixelBufferGetBaseAddress(conf) {
                let cRow = CVPixelBufferGetBytesPerRow(conf)
                let cw = CVPixelBufferGetWidth(conf)
                let ch = CVPixelBufferGetHeight(conf)
                confidence = Int(cb.load(fromByteOffset: (ch / 2) * cRow + cw / 2, as: UInt8.self))
            }
        }
        return (depth, confidence)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message = TrackingText.message(for: camera.trackingState)
        DispatchQueue.main.async { self.trackingMessage = message }
    }
}
