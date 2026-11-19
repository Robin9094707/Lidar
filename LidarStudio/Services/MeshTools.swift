import ARKit
import SceneKit
import simd

enum MeshPalette {
    static func color(for raw: UInt8) -> SIMD4<Float> {
        switch ARMeshClassification(rawValue: Int(raw)) {
        case .wall?: return SIMD4<Float>(0.31, 0.82, 1.00, 1)
        case .floor?: return SIMD4<Float>(0.35, 0.95, 0.75, 1)
        case .ceiling?: return SIMD4<Float>(0.58, 0.45, 1.00, 1)
        case .table?: return SIMD4<Float>(1.00, 0.62, 0.30, 1)
        case .seat?: return SIMD4<Float>(1.00, 0.42, 0.70, 1)
        case .window?: return SIMD4<Float>(0.45, 0.60, 1.00, 1)
        case .door?: return SIMD4<Float>(1.00, 0.84, 0.35, 1)
        default: return SIMD4<Float>(0.85, 0.92, 1.00, 1)
        }
    }

    static let neutral = SIMD4<Float>(0.31, 0.82, 1.00, 1)

    static let legend: [(String, SIMD4<Float>)] = [
        ("Wand", color(for: UInt8(ARMeshClassification.wall.rawValue))),
        ("Boden", color(for: UInt8(ARMeshClassification.floor.rawValue))),
        ("Decke", color(for: UInt8(ARMeshClassification.ceiling.rawValue))),
        ("Tisch", color(for: UInt8(ARMeshClassification.table.rawValue))),
        ("Sitz", color(for: UInt8(ARMeshClassification.seat.rawValue))),
        ("Fenster", color(for: UInt8(ARMeshClassification.window.rawValue))),
        ("Tür", color(for: UInt8(ARMeshClassification.door.rawValue)))
    ]
}

/// Hilfsfunktionen zum Auslesen von ARMeshGeometry.
enum MeshReader {
    static func positions(_ geometry: ARMeshGeometry) -> [SIMD3<Float>] {
        let source = geometry.vertices
        let base = source.buffer.contents().advanced(by: source.offset)
        var result = [SIMD3<Float>](repeating: .zero, count: source.count)
        for i in 0..<source.count {
            let p = base.advanced(by: i * source.stride).assumingMemoryBound(to: Float.self)
            result[i] = SIMD3<Float>(p[0], p[1], p[2])
        }
        return result
    }

    static func indices(_ geometry: ARMeshGeometry) -> [UInt32] {
        let faces = geometry.faces
        let n = faces.count * faces.indexCountPerPrimitive
        var result = [UInt32](repeating: 0, count: n)
        let ptr = faces.buffer.contents()
        if faces.bytesPerIndex == 4 {
            let p = ptr.assumingMemoryBound(to: UInt32.self)
            for i in 0..<n { result[i] = p[i] }
        } else {
            let p = ptr.assumingMemoryBound(to: UInt16.self)
            for i in 0..<n { result[i] = UInt32(p[i]) }
        }
        return result
    }

    static func faceClassifications(_ geometry: ARMeshGeometry) -> [UInt8]? {
        guard let source = geometry.classification else { return nil }
        let base = source.buffer.contents().advanced(by: source.offset)
        var result = [UInt8](repeating: 0, count: source.count)
        for i in 0..<source.count {
            result[i] = base.load(fromByteOffset: i * source.stride, as: UInt8.self)
        }
        return result
    }

    /// Farbe je Vertex aus der Flächenklassifizierung.
    static func vertexColors(_ geometry: ARMeshGeometry, indices: [UInt32], colored: Bool) -> [SIMD4<Float>] {
        var colors = [SIMD4<Float>](repeating: MeshPalette.neutral, count: geometry.vertices.count)
        guard colored, let classes = faceClassifications(geometry) else { return colors }
        let perFace = geometry.faces.indexCountPerPrimitive
        for face in 0..<min(classes.count, indices.count / perFace) {
            let color = MeshPalette.color(for: classes[face])
            for k in 0..<perFace {
                let idx = Int(indices[face * perFace + k])
                if idx < colors.count { colors[idx] = color }
            }
        }
        return colors
    }
}

enum MeshGeometryBuilder {
    static let fillMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        m.transparency = 0.22
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .add
        return m
    }()

    static let wireMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        m.fillMode = .lines
        m.transparency = 0.85
        m.isDoubleSided = true
        return m
    }()

    /// Live-Geometrie (lokale Anker-Koordinaten) mit Klassifizierungsfarben.
    static func liveGeometry(from geometry: ARMeshGeometry, colored: Bool) -> SCNGeometry {
        let vertices = geometry.vertices
        let vertexData = Data(
            bytes: vertices.buffer.contents().advanced(by: vertices.offset),
            count: vertices.stride * vertices.count
        )
        let vertexSource = SCNGeometrySource(
            data: vertexData, semantic: .vertex, vectorCount: vertices.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: vertices.stride
        )

        let indices = MeshReader.indices(geometry)
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles,
            primitiveCount: geometry.faces.count, bytesPerIndex: 4
        )

        let colors = MeshReader.vertexColors(geometry, indices: indices, colored: colored)
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: colors.count,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        return SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
    }
}

struct MeshExportResult {
    var vertexCount: Int
    var faceCount: Int
    var files: [String]
    var primaryFile: String
    var surfaceArea: Float
    var bounds: SIMD3<Float>
    var classCounts: [String: Int]
}

/// Exportiert gesammelte Mesh-Anker als OBJ (mit Vertex-Farben), PLY und USDZ.
enum MeshExporter {
    enum ExportError: LocalizedError {
        case empty
        var errorDescription: String? { "Es wurde noch keine Geometrie erfasst." }
    }

    static func export(anchors: [ARMeshAnchor], to folder: URL, baseName: String, colored: Bool) throws -> MeshExportResult {
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        var indices: [UInt32] = []
        var classCounts: [String: Int] = [:]

        for anchor in anchors {
            let geometry = anchor.geometry
            let local = MeshReader.positions(geometry)
            let localIndices = MeshReader.indices(geometry)
            let localColors = MeshReader.vertexColors(geometry, indices: localIndices, colored: colored)
            let offset = UInt32(positions.count)
            let transform = anchor.transform
            for p in local {
                positions.append((transform * SIMD4<Float>(p, 1)).xyz)
            }
            colors.append(contentsOf: localColors)
            indices.append(contentsOf: localIndices.map { $0 + offset })

            if let classes = MeshReader.faceClassifications(geometry) {
                for c in classes {
                    let name = className(c)
                    classCounts[name, default: 0] += 1
                }
            }
        }

        guard !positions.isEmpty, !indices.isEmpty else { throw ExportError.empty }

        var minV = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in positions {
            minV = simd_min(minV, p)
            maxV = simd_max(maxV, p)
        }

        var area: Float = 0
        var i = 0
        while i + 2 < indices.count {
            let a = positions[Int(indices[i])]
            let b = positions[Int(indices[i + 1])]
            let c = positions[Int(indices[i + 2])]
            area += simd_length(simd_cross(b - a, c - a)) / 2
            i += 3
        }

        let objName = "\(baseName).obj"
        let plyName = "\(baseName)-mesh.ply"
        let usdzName = "\(baseName).usdz"
        var files: [String] = []

        try writeOBJ(positions: positions, colors: colors, indices: indices, to: folder.appending(path: objName))
        files.append(objName)

        try writePLY(positions: positions, colors: colors, indices: indices, to: folder.appending(path: plyName))
        files.append(plyName)

        var primary = objName
        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: worldGeometry(positions: positions, colors: colors, indices: indices)))
        let usdzURL = folder.appending(path: usdzName)
        if scene.write(to: usdzURL, options: nil, delegate: nil, progressHandler: nil),
           FileManager.default.fileExists(atPath: usdzURL.path) {
            files.insert(usdzName, at: 0)
            primary = usdzName
        }

        return MeshExportResult(
            vertexCount: positions.count,
            faceCount: indices.count / 3,
            files: files,
            primaryFile: primary,
            surfaceArea: area,
            bounds: maxV - minV,
            classCounts: classCounts
        )
    }

    static func className(_ raw: UInt8) -> String {
        switch ARMeshClassification(rawValue: Int(raw)) {
        case .wall?: return "Wand"
        case .floor?: return "Boden"
        case .ceiling?: return "Decke"
        case .table?: return "Tisch"
        case .seat?: return "Sitz"
        case .window?: return "Fenster"
        case .door?: return "Tür"
        default: return "Sonstiges"
        }
    }

    static func worldGeometry(positions: [SIMD3<Float>], colors: [SIMD4<Float>], indices: [UInt32]) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(
            data: positions.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .vertex, vectorCount: positions.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let colorSource = SCNGeometrySource(
            data: colors.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .color, vectorCount: colors.count,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let element = SCNGeometryElement(
            data: indices.withUnsafeBufferPointer { Data(buffer: $0) },
            primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: 4
        )
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.white
        material.roughness.contents = 0.8
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    private static func fmt(_ v: Float) -> String {
        String((v * 10_000).rounded() / 10_000)
    }

    static func writeOBJ(positions: [SIMD3<Float>], colors: [SIMD4<Float>], indices: [UInt32], to url: URL) throws {
        var text = "# LiDAR Studio Mesh Export\n# Vertices: \(positions.count)  Faces: \(indices.count / 3)\n"
        text.reserveCapacity(positions.count * 60 + indices.count * 10)
        for (i, p) in positions.enumerated() {
            let c = colors[i]
            text += "v \(fmt(p.x)) \(fmt(p.y)) \(fmt(p.z)) \(fmt(c.x)) \(fmt(c.y)) \(fmt(c.z))\n"
        }
        var i = 0
        while i + 2 < indices.count {
            text += "f \(indices[i] + 1) \(indices[i + 1] + 1) \(indices[i + 2] + 1)\n"
            i += 3
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writePLY(positions: [SIMD3<Float>], colors: [SIMD4<Float>], indices: [UInt32], to url: URL) throws {
        let faceCount = indices.count / 3
        let header = """
        ply
        format binary_little_endian 1.0
        comment Created with LiDAR Studio
        element vertex \(positions.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        element face \(faceCount)
        property list uchar uint vertex_indices
        end_header

        """
        var data = Data(header.utf8)
        var vertexBytes = [UInt8](repeating: 0, count: positions.count * 15)
        vertexBytes.withUnsafeMutableBytes { raw in
            for i in 0..<positions.count {
                let o = i * 15
                let p = positions[i]
                raw.storeBytes(of: p.x.bitPattern.littleEndian, toByteOffset: o, as: UInt32.self)
                raw.storeBytes(of: p.y.bitPattern.littleEndian, toByteOffset: o + 4, as: UInt32.self)
                raw.storeBytes(of: p.z.bitPattern.littleEndian, toByteOffset: o + 8, as: UInt32.self)
                let c = colors[i]
                raw[o + 12] = UInt8(min(max(c.x * 255, 0), 255))
                raw[o + 13] = UInt8(min(max(c.y * 255, 0), 255))
                raw[o + 14] = UInt8(min(max(c.z * 255, 0), 255))
            }
        }
        data.append(contentsOf: vertexBytes)
        var faceBytes = [UInt8](repeating: 0, count: faceCount * 13)
        faceBytes.withUnsafeMutableBytes { raw in
            for f in 0..<faceCount {
                let o = f * 13
                raw[o] = 3
                raw.storeBytes(of: indices[f * 3].littleEndian, toByteOffset: o + 1, as: UInt32.self)
                raw.storeBytes(of: indices[f * 3 + 1].littleEndian, toByteOffset: o + 5, as: UInt32.self)
                raw.storeBytes(of: indices[f * 3 + 2].littleEndian, toByteOffset: o + 9, as: UInt32.self)
            }
        }
        data.append(contentsOf: faceBytes)
        try data.write(to: url, options: .atomic)
    }
}
