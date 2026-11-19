import SwiftUI

enum Theme {
    static let accent = Color(red: 0.31, green: 0.82, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.45, blue: 1.0)
    static let mint = Color(red: 0.35, green: 0.95, blue: 0.75)
    static let pink = Color(red: 1.0, green: 0.42, blue: 0.70)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.30)
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.35)

    static let titleGradient = LinearGradient(
        colors: [.white, accent, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let laserGradient = LinearGradient(
        colors: [accent, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let uiAccent = UIColor(red: 0.31, green: 0.82, blue: 1.0, alpha: 1)
    static let uiViolet = UIColor(red: 0.58, green: 0.45, blue: 1.0, alpha: 1)
}

/// Langsam fließender Mesh-Gradient als Hintergrund hinter dem Liquid Glass.
struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            let leftY: Float = 0.45 + 0.10 * sin(t * 0.40)
            let midX: Float = 0.50 + 0.18 * sin(t * 0.27)
            let midY: Float = 0.50 + 0.14 * cos(t * 0.33)
            let rightY: Float = 0.55 + 0.10 * cos(t * 0.45)
            let topX: Float = 0.50 + 0.12 * cos(t * 0.21)

            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0, 0), SIMD2<Float>(topX, 0), SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, leftY), SIMD2<Float>(midX, midY), SIMD2<Float>(1, rightY),
                    SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
                ],
                colors: [
                    Color(red: 0.02, green: 0.03, blue: 0.08),
                    Color(red: 0.04, green: 0.10, blue: 0.22),
                    Color(red: 0.03, green: 0.03, blue: 0.10),
                    Color(red: 0.00, green: 0.17, blue: 0.27),
                    Color(red: 0.13, green: 0.07, blue: 0.32),
                    Color(red: 0.02, green: 0.11, blue: 0.20),
                    Color(red: 0.01, green: 0.02, blue: 0.05),
                    Color(red: 0.07, green: 0.03, blue: 0.16),
                    Color(red: 0.01, green: 0.02, blue: 0.05)
                ]
            )
        }
        .ignoresSafeArea()
    }
}
