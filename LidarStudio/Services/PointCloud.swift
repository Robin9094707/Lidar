import ARKit
import SceneKit
import CoreVideo
import simd

/// Momentaufnahme eines AR-Frames, die für die Punktwolken-Integration benötigt wird.
/// (Wir halten bewusst nicht das ganze ARFrame fest.)
struct DepthFrameSample {
    let depth: CVPixelBuffer
    let confidence: CVPixelBuffer?
    let image: CVPixelBuffer
    let intrinsics: simd_float3x3
    let imageResolution: CGSize
    let cameraTransform: simd_float4x4

    init?(frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth else { return nil }
        depth = sceneDepth.depthMap
        confidence = sceneDepth.confidenceMap
        image = frame.capturedImage
        intrinsics = frame.camera.intrinsics
        imageResolution = frame.camera.imageResolution
        cameraTransform = frame.camera.transform
    }
}

/// Sammelt farbige Weltpunkte aus LiDAR-Tiefenkarten mit Voxel-Deduplizierung.
/// Nicht threadsicher – nur von einer seriellen Queue aus verwenden.
final class PointCloudAccumulator {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var colors: [SIMD3<UInt8>] = []
    private var occupied = Set<SIMD3<Int32>>()

    var voxelSize: Float = 0.02
    var maxPoints = 3_000_000
    var minConfidence: UInt8 = 1
    var maxDepth: Float = 5.0
    var pixelStep = 2

    var count: Int { positions.count }
    var isFull: Bool { positions.count >= maxPoints }

    func reset() {
        positions.removeAll()
        colors.removeAll()
        occupied.removeAll()
    }

    @discardableResult
    func integrate(_ sample: DepthFrameSample) -> Int {
        guard !isFull else { return 0 }
        let depth = sample.depth
        let image = sample.image

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        CVPixelBufferLockBaseAddress(image, .readOnly)
        if let conf = sample.confidence { CVPixelBufferLockBaseAddress(conf, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(depth, .readOnly)
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            if let conf = sample.confidence { CVPixelBufferUnlockBaseAddress(conf, .readOnly) }
        }

        guard let depthBase = CVPixelBufferGetBaseAddress(depth),
              CVPixelBufferGetPlaneCount(image) >= 2,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(image, 0),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(image, 1) else { return 0 }

        let dw = CVPixelBufferGetWidth(depth)
        let dh = CVPixelBufferGetHeight(depth)
        let depthRow = CVPixelBufferGetBytesPerRow(depth)

        var confBase: UnsafeMutableRawPointer? = nil
        var confRow = 0
        if let conf = sample.confidence {
            confBase = CVPixelBufferGetBaseAddress(conf)
            confRow = CVPixelBufferGetBytesPerRow(conf)
        }

        let iw = CVPixelBufferGetWidthOfPlane(image, 0)
        let ih = CVPixelBufferGetHeightOfPlane(image, 0)
        let yRow = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let uvRow = CVPixelBufferGetBytesPerRowOfPlane(image, 1)

        let sx = Float(sample.imageResolution.width) / Float(dw)
        let sy = Float(sample.imageResolution.height) / Float(dh)
        let fx = sample.intrinsics.columns.0.x
        let fy = sample.intrinsics.columns.1.y
        let cx = sample.intrinsics.columns.2.x
        let cy = sample.intrinsics.columns.2.y
        let transform = sample.cameraTransform
        let inv = 1 / voxelSize
        var added = 0

        outer: for v in stride(from: 0, to: dh, by: pixelStep) {
            let depthLine = depthBase.advanced(by: v * depthRow).assumingMemoryBound(to: Float32.self)
            for u in stride(from: 0, to: dw, by: pixelStep) {
                let d = depthLine[u]
                guard d.isFinite, d > 0.15, d < maxDepth else { continue }
                if let confBase {
                    let c = confBase.load(fromByteOffset: v * confRow + u, as: UInt8.self)
                    if c < minConfidence { continue }
                }
                let px = (Float(u) + 0.5) * sx
                let py = (Float(v) + 0.5) * sy
                let xc = (px - cx) * d / fx
                let yc = (py - cy) * d / fy
                let world = (transform * SIMD4<Float>(xc, -yc, -d, 1)).xyz

                let key = SIMD3<Int32>(
                    Int32((world.x * inv).rounded(.down)),
                    Int32((world.y * inv).rounded(.down)),
                    Int32((world.z * inv).rounded(.down))
                )
                guard occupied.insert(key).inserted else { continue }

                let ix = min(max(Int(px), 0), iw - 1)
                let iy = min(max(Int(py), 0), ih - 1)
                let yValue = Float(yBase.load(fromByteOffset: iy * yRow + ix, as: UInt8.self))
                let uvOffset = (iy / 2) * uvRow + (ix / 2) * 2
                let cb = Float(uvBase.load(fromByteOffset: uvOffset, as: UInt8.self)) - 128
                let cr = Float(uvBase.load(fromByteOffset: uvOffset + 1, as: UInt8.self)) - 128
                let r = yValue + 1.402 * cr
                let g = yValue - 0.344136 * cb - 0.714136 * cr
                let b = yValue + 1.772 * cb

                positions.append(world)
                colors.append(SIMD3<UInt8>(
                    UInt8(min(max(r, 0), 255)),
                    UInt8(min(max(g, 0), 255)),
                    UInt8(min(max(b, 0), 255))
                ))
                added += 1
                if positions.count >= maxPoints { break outer }
            }
        }
        return added
    }

    /// Geometrie für die Live-Vorschau (ausgedünnt).
    func previewGeometry(maxPoints limit: Int) -> SCNGeometry? {
        guard !positions.isEmpty else { return nil }
        let step = max(1, positions.count / limit)
        var pos: [SIMD3<Float>] = []
        var col: [SIMD3<Float>] = []
        pos.reserveCapacity(positions.count / step + 1)
        col.reserveCapacity(positions.count / step + 1)
        var i = 0
        while i < positions.count {
            pos.append(positions[i])
            let c = colors[i]
            col.append(SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)) / 255)
            i += step
        }
        return PointCloudGeometry.geometry(positions: pos, colors: col, pointSize: 3)
    }
}

enum PointCloudGeometry {
    static func geometry(positions: [SIMD3<Float>], colors: [SIMD3<Float>], pointSize: CGFloat) -> SCNGeometry {
        let count = positions.count
        let positionData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let stride = MemoryLayout<SIMD3<Float>>.stride

        let vertexSource = SCNGeometrySource(
            data: positionData, semantic: .vertex, vectorCount: count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: stride
        )
        let colorSource = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: stride
        )
        let indices = (0..<UInt32(count)).map { $0 }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: indexData, primitiveType: .point, primitiveCount: count, bytesPerIndex: 4)
        element.pointSize = pointSize
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = pointSize * 2

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        geometry.materials = [material]
        return geometry
    }

    static func node(positions: [SIMD3<Float>], colors: [SIMD3<Float>], pointSize: CGFloat) -> SCNNode {
        SCNNode(geometry: geometry(positions: positions, colors: colors, pointSize: pointSize))
    }
}

/// Binäres PLY (little endian) lesen/schreiben.
enum PLYIO {
    enum PLYError: Error { case invalidHeader, unsupportedFormat }

    static func write(positions: [SIMD3<Float>], colors: [SIMD3<UInt8>], to url: URL) throws {
        let n = positions.count
        let header = """
        ply
        format binary_little_endian 1.0
        comment Created with LiDAR Studio
        element vertex \(n)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """
        var data = Data(header.utf8)
        var body = [UInt8](repeating: 0, count: n * 15)
        body.withUnsafeMutableBytes { raw in
            for i in 0..<n {
                let o = i * 15
                let p = positions[i]
                raw.storeBytes(of: p.x.bitPattern.littleEndian, toByteOffset: o, as: UInt32.self)
                raw.storeBytes(of: p.y.bitPattern.littleEndian, toByteOffset: o + 4, as: UInt32.self)
                raw.storeBytes(of: p.z.bitPattern.littleEndian, toByteOffset: o + 8, as: UInt32.self)
                let c = i < colors.count ? colors[i] : SIMD3<UInt8>(255, 255, 255)
                raw[o + 12] = c.x
                raw[o + 13] = c.y
                raw[o + 14] = c.z
            }
        }
        data.append(contentsOf: body)
        try data.write(to: url, options: .atomic)
    }

    static func writeXYZ(positions: [SIMD3<Float>], colors: [SIMD3<UInt8>], to url: URL) throws {
        var text = ""
        text.reserveCapacity(positions.count * 40)
        for i in 0..<positions.count {
            let p = positions[i]
            let c = i < colors.count ? colors[i] : SIMD3<UInt8>(255, 255, 255)
            text += "\(p.x) \(p.y) \(p.z) \(c.x) \(c.y) \(c.z)\n"
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Liest binäre little-endian PLY-Dateien mit float/double/uchar-Eigenschaften.
    static func read(url: URL, maxPoints: Int = 2_000_000) throws -> (positions: [SIMD3<Float>], colors: [SIMD3<Float>]) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let marker = "end_header\n".data(using: .utf8),
              let range = data.range(of: marker) else { throw PLYError.invalidHeader }
        guard let header = String(data: data[data.startIndex..<range.lowerBound], encoding: .ascii) else { throw PLYError.invalidHeader }
        guard header.contains("binary_little_endian") else { throw PLYError.unsupportedFormat }

        var vertexCount = 0
        var inVertex = false
        var offsets: [String: (Int, String)] = [:]
        var stride = 0
        for line in header.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard let first = parts.first else { continue }
            if first == "element" {
                inVertex = parts.count >= 3 && parts[1] == "vertex"
                if inVertex { vertexCount = Int(parts[2]) ?? 0 }
            } else if first == "property", inVertex, parts.count >= 3 {
                let type = parts[1]
                let name = parts[2]
                let size: Int
                switch type {
                case "float", "float32", "int", "int32", "uint", "uint32": size = 4
                case "double", "float64": size = 8
                case "uchar", "uint8", "char", "int8": size = 1
                case "short", "ushort", "int16", "uint16": size = 2
                default: throw PLYError.unsupportedFormat
                }
                offsets[name] = (stride, type)
                stride += size
            }
        }
        guard vertexCount > 0, let xo = offsets["x"], let yo = offsets["y"], let zo = offsets["z"] else { throw PLYError.invalidHeader }

        let step = max(1, vertexCount / maxPoints)
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD3<Float>] = []
        positions.reserveCapacity(vertexCount / step + 1)
        colors.reserveCapacity(vertexCount / step + 1)
        let bodyStart = range.upperBound - data.startIndex

        data.withUnsafeBytes { raw in
            func float(_ base: Int, _ prop: (Int, String)) -> Float {
                switch prop.1 {
                case "double", "float64": return Float(raw.loadUnaligned(fromByteOffset: base + prop.0, as: Double.self))
                case "uchar", "uint8": return Float(raw[base + prop.0])
                default: return raw.loadUnaligned(fromByteOffset: base + prop.0, as: Float.self)
                }
            }
            var i = 0
            while i < vertexCount {
                let base = bodyStart + i * stride
                if base + stride > raw.count { break }
                positions.append(SIMD3<Float>(float(base, xo), float(base, yo), float(base, zo)))
                if let r = offsets["red"], let g = offsets["green"], let b = offsets["blue"] {
                    let scale: Float = r.1.hasPrefix("u") ? 1 / 255 : 1
                    colors.append(SIMD3<Float>(float(base, r), float(base, g), float(base, b)) * scale)
                } else {
                    colors.append(SIMD3<Float>(0.5, 0.85, 1.0))
                }
                i += step
            }
        }
        return (positions, colors)
    }
}
