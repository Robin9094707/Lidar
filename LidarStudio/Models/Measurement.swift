import SceneKit
import UIKit
import simd

enum MeasureTool: String, Codable, CaseIterable, Identifiable {
    case distance, path, area, points

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: "Strecke"
        case .path: "Pfad"
        case .area: "Fläche"
        case .points: "Punkte"
        }
    }

    var icon: String {
        switch self {
        case .distance: "ruler"
        case .path: "point.topleft.down.to.point.bottomright.curvepath"
        case .area: "skew"
        case .points: "mappin.and.ellipse"
        }
    }

    var hint: String {
        switch self {
        case .distance: "Setze Start- und Endpunkt"
        case .path: "Setze Punkte entlang eines Weges"
        case .area: "Setze die Eckpunkte der Fläche"
        case .points: "Markiere Punkte im Raum"
        }
    }
}

struct MeasurePoint: Codable, Hashable, Identifiable {
    var id = UUID()
    var position: SIMD3<Float>
}

struct MeasureSegment: Identifiable {
    let id: Int
    let a: SIMD3<Float>
    let b: SIMD3<Float>
    var length: Float { simd_distance(a, b) }
    var midpoint: SIMD3<Float> { (a + b) / 2 }
}

struct MeasurementRecord: Codable {
    var tool: MeasureTool
    var points: [MeasurePoint]
    var createdAt: Date
}

enum MeasureMath {
    static func segments(tool: MeasureTool, points: [SIMD3<Float>]) -> [MeasureSegment] {
        var result: [MeasureSegment] = []
        switch tool {
        case .distance:
            var i = 0
            while i + 1 < points.count {
                result.append(MeasureSegment(id: result.count, a: points[i], b: points[i + 1]))
                i += 2
            }
        case .path:
            for i in 0..<max(points.count - 1, 0) {
                result.append(MeasureSegment(id: result.count, a: points[i], b: points[i + 1]))
            }
        case .area:
            for i in 0..<max(points.count - 1, 0) {
                result.append(MeasureSegment(id: result.count, a: points[i], b: points[i + 1]))
            }
            if points.count >= 3, let first = points.first, let last = points.last {
                result.append(MeasureSegment(id: result.count, a: last, b: first))
            }
        case .points:
            break
        }
        return result
    }

    static func totalLength(tool: MeasureTool, points: [SIMD3<Float>]) -> Float {
        segments(tool: tool, points: points).reduce(0) { $0 + $1.length }
    }

    /// Fläche eines (annähernd ebenen) 3D-Polygons nach Newell.
    static func polygonArea(_ points: [SIMD3<Float>]) -> Float {
        guard points.count >= 3 else { return 0 }
        var normal = SIMD3<Float>.zero
        for i in 0..<points.count {
            let p = points[i]
            let q = points[(i + 1) % points.count]
            normal += simd_cross(p, q)
        }
        return simd_length(normal) / 2
    }

    static func polygonCentroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        return points.reduce(.zero, +) / Float(points.count)
    }
}

/// Baut die SceneKit-Darstellung einer Messung (Punkte, Linien, Beschriftungen).
enum MeasureSceneBuilder {
    static func build(points: [SIMD3<Float>], tool: MeasureTool, labelScale: Float = 1) -> SCNNode {
        let root = SCNNode()
        let accent = Theme.uiAccent

        for (index, p) in points.enumerated() {
            root.addChildNode(sphere(at: p, color: index == 0 && tool == .area ? Theme.uiViolet : .white))
            if tool == .points {
                root.addChildNode(label("P\(index + 1)", at: p + SIMD3<Float>(0, 0.04, 0), scale: labelScale))
            }
        }

        for segment in MeasureMath.segments(tool: tool, points: points) {
            root.addChildNode(line(from: segment.a, to: segment.b, color: accent))
            root.addChildNode(label(Units.length(segment.length), at: segment.midpoint + SIMD3<Float>(0, 0.03, 0), scale: labelScale))
        }

        if tool == .area, points.count >= 3 {
            root.addChildNode(polygonFill(points))
            let area = MeasureMath.polygonArea(points)
            root.addChildNode(label(Units.area(area), at: MeasureMath.polygonCentroid(points) + SIMD3<Float>(0, 0.05, 0), scale: labelScale * 1.3, highlight: true))
        }
        return root
    }

    static func sphere(at position: SIMD3<Float>, color: UIColor) -> SCNNode {
        let sphere = SCNSphere(radius: 0.007)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.simdPosition = position

        let halo = SCNSphere(radius: 0.014)
        let haloMat = SCNMaterial()
        haloMat.lightingModel = .constant
        haloMat.diffuse.contents = Theme.uiAccent.withAlphaComponent(0.35)
        haloMat.writesToDepthBuffer = false
        halo.materials = [haloMat]
        node.addChildNode(SCNNode(geometry: halo))
        return node
    }

    static func line(from a: SIMD3<Float>, to b: SIMD3<Float>, color: UIColor, radius: CGFloat = 0.0022) -> SCNNode {
        let vector = b - a
        let length = simd_length(vector)
        guard length > 0.0001 else { return SCNNode() }
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        cylinder.materials = [material]
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: vector / length)
        return node
    }

    static func polygonFill(_ points: [SIMD3<Float>]) -> SCNNode {
        let centroid = MeasureMath.polygonCentroid(points)
        var vertices: [SIMD3<Float>] = [centroid]
        vertices.append(contentsOf: points)
        var indices: [UInt32] = []
        for i in 0..<points.count {
            indices.append(0)
            indices.append(UInt32(i + 1))
            indices.append(UInt32((i + 1) % points.count + 1))
        }
        let source = SCNGeometrySource(
            data: vertices.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .vertex, vectorCount: vertices.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let element = SCNGeometryElement(
            data: indices.withUnsafeBufferPointer { Data(buffer: $0) },
            primitiveType: .triangles, primitiveCount: points.count, bytesPerIndex: 4
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Theme.uiViolet.withAlphaComponent(0.3)
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    static func label(_ text: String, at position: SIMD3<Float>, scale: Float = 1, highlight: Bool = false) -> SCNNode {
        let image = LabelImage.render(text, highlight: highlight)
        let aspect = image.size.width / max(image.size.height, 1)
        let height = CGFloat(0.03 * scale)
        let plane = SCNPlane(width: height * aspect, height: height)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.simdPosition = position
        node.renderingOrder = 100
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        return node
    }
}

enum LabelImage {
    static func render(_ text: String, highlight: Bool) -> UIImage {
        let font = UIFont.systemFont(ofSize: 44, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 30, height: 14)
        let size = CGSize(width: ceil(textSize.width + padding.width * 2), height: ceil(textSize.height + padding.height * 2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            (highlight ? Theme.uiViolet.withAlphaComponent(0.9) : UIColor(white: 0.05, alpha: 0.78)).setFill()
            path.fill()
            Theme.uiAccent.withAlphaComponent(0.9).setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: size.height / 2 - 2)
            border.lineWidth = 3
            border.stroke()
            (text as NSString).draw(at: CGPoint(x: padding.width, y: padding.height), withAttributes: attributes)
        }
    }
}
