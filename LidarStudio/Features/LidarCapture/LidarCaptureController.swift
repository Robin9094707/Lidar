import ARKit
import SceneKit
import SwiftUI

@Observable
final class LidarCaptureController: NSObject, ARSCNViewDelegate, ARSessionDelegate {
    enum Mode { case mesh, pointCloud }

    let mode: Mode
    let isSupported: Bool

    var isRecording = false
    var hasCapture = false
    var trackingMessage: String?
    var anchorCount = 0
    var vertexCount = 0
    var pointCount = 0
    var recordingStart: Date?
    var recordedDuration: TimeInterval = 0
    var isFull = false

    let sceneView = ARSCNView(frame: .zero)
    @ObservationIgnored private var frozenAnchors: [ARMeshAnchor] = []
    private let colored: Bool
    private let accumulator = PointCloudAccumulator()
    private let processingQueue = DispatchQueue(label: "lidarstudio.pointcloud", qos: .userInitiated)
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var lastSampleTime: TimeInterval = 0
    @ObservationIgnored private var lastPreviewTime: TimeInterval = 0
    @ObservationIgnored private var lastStatsTime: TimeInterval = 0
    private let previewNode = SCNNode()

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .mesh:
            isSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        case .pointCloud:
            isSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }
        let defaults = UserDefaults.standard
        colored = defaults.object(forKey: "classificationColors") as? Bool ?? true
        super.init()

        let density = defaults.object(forKey: "pointDensity") as? Int ?? 1
        accumulator.voxelSize = [0.008, 0.015, 0.03][min(max(density, 0), 2)]
        accumulator.minConfidence = (defaults.object(forKey: "highConfidenceOnly") as? Bool ?? false) ? 2 : 1
        accumulator.maxDepth = Float(defaults.object(forKey: "maxDepth") as? Double ?? 4.0)

        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.rendersContinuously = true
        sceneView.scene.rootNode.addChildNode(previewNode)
    }

    // MARK: Session

    private func configuration(reconstruct: Bool) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .none
        if mode == .mesh, reconstruct {
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                config.sceneReconstruction = .meshWithClassification
            } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
        }
        if mode == .pointCloud, ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        return config
    }

    func start() {
        guard isSupported else { return }
        sceneView.session.run(configuration(reconstruct: false), options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() {
        sceneView.session.pause()
    }

    func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        recordingStart = Date()
        switch mode {
        case .mesh:
            if !hasCapture {
                sceneView.session.run(configuration(reconstruct: true), options: [.resetSceneReconstruction])
            } else {
                sceneView.session.run(configuration(reconstruct: true))
            }
        case .pointCloud:
            sceneView.session.run(configuration(reconstruct: false))
        }
    }

    private func stopRecording() {
        isRecording = false
        if let start = recordingStart {
            recordedDuration += Date().timeIntervalSince(start)
        }
        recordingStart = nil
        hasCapture = true
        if mode == .mesh {
            frozenAnchors = sceneView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? frozenAnchors
            sceneView.session.pause()
        }
    }

    func reset() {
        isRecording = false
        hasCapture = false
        recordingStart = nil
        recordedDuration = 0
        frozenAnchors = []
        anchorCount = 0
        vertexCount = 0
        pointCount = 0
        isFull = false
        processingQueue.async { [accumulator] in accumulator.reset() }
        previewNode.geometry = nil
        sceneView.session.run(configuration(reconstruct: false), options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
    }

    var currentDuration: TimeInterval {
        recordedDuration + (recordingStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    // MARK: Export

    func meshAnchorsForExport() -> [ARMeshAnchor] {
        if !frozenAnchors.isEmpty { return frozenAnchors }
        return sceneView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
    }

    func pointCloudSnapshot() async -> ([SIMD3<Float>], [SIMD3<UInt8>]) {
        await withCheckedContinuation { continuation in
            processingQueue.async { [accumulator] in
                continuation.resume(returning: (accumulator.positions, accumulator.colors))
            }
        }
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp

        if now - lastStatsTime > 0.4 {
            lastStatsTime = now
            if mode == .mesh {
                let meshes = frame.anchors.compactMap { $0 as? ARMeshAnchor }
                anchorCount = meshes.count
                vertexCount = meshes.reduce(0) { $0 + $1.geometry.vertices.count }
            }
        }

        guard mode == .pointCloud, isRecording, !isProcessing, now - lastSampleTime > 0.12,
              let sample = DepthFrameSample(frame: frame) else { return }
        lastSampleTime = now
        isProcessing = true
        let shouldPreview = now - lastPreviewTime > 0.6
        if shouldPreview { lastPreviewTime = now }

        processingQueue.async { [weak self, accumulator] in
            accumulator.integrate(sample)
            let total = accumulator.count
            let full = accumulator.isFull
            let geometry = shouldPreview ? accumulator.previewGeometry(maxPoints: 220_000) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.isProcessing = false
                self.pointCount = total
                if full && !self.isFull {
                    self.isFull = true
                    self.stopRecording()
                }
                if let geometry {
                    self.previewNode.geometry = geometry
                }
            }
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message = TrackingText.message(for: camera.trackingState)
        DispatchQueue.main.async { self.trackingMessage = message }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.trackingMessage = error.localizedDescription }
    }

    // MARK: ARSCNViewDelegate (läuft auf dem Render-Thread)

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard mode == .mesh, let meshAnchor = anchor as? ARMeshAnchor else { return nil }
        let node = SCNNode()
        updateMeshNode(node, with: meshAnchor)
        return node
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard mode == .mesh, let meshAnchor = anchor as? ARMeshAnchor else { return }
        updateMeshNode(node, with: meshAnchor)
    }

    private func updateMeshNode(_ node: SCNNode, with anchor: ARMeshAnchor) {
        let geometry = MeshGeometryBuilder.liveGeometry(from: anchor.geometry, colored: colored)
        geometry.materials = [MeshGeometryBuilder.fillMaterial]
        node.geometry = geometry

        guard let wire = geometry.copy() as? SCNGeometry else { return }
        wire.materials = [MeshGeometryBuilder.wireMaterial]
        if let child = node.childNodes.first {
            child.geometry = wire
        } else {
            node.addChildNode(SCNNode(geometry: wire))
        }
    }
}
