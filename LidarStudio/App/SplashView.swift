import SwiftUI

/// Öffnungsanimation: Ein Laser tastet ein Punktraster ab, danach materialisiert
/// sich das Liquid-Glass-Emblem mit pulsierenden Scan-Ringen und dem Schriftzug.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var start = Date()
    @State private var iconVisible = false
    @State private var ringsVisible = false
    @State private var titleVisible = false
    @State private var subtitleVisible = false
    @State private var pulse = false
    @State private var exit = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AuroraBackground()
                .opacity(iconVisible ? 1 : 0)

            LidarDotField(start: start)
                .ignoresSafeArea()
                .opacity(exit ? 0 : 1)

            VStack(spacing: 34) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(
                                AngularGradient(colors: [Theme.accent, Theme.violet, Theme.accent], center: .center),
                                lineWidth: 1.2
                            )
                            .frame(width: 150 + CGFloat(i) * 64, height: 150 + CGFloat(i) * 64)
                            .opacity(ringsVisible ? 0.55 - Double(i) * 0.15 : 0)
                            .scaleEffect(ringsVisible ? (pulse ? 1.04 : 1) : 0.3)
                            .animation(
                                .spring(duration: 1.1, bounce: 0.35).delay(Double(i) * 0.12),
                                value: ringsVisible
                            )
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(i) * 0.2),
                                value: pulse
                            )
                    }

                    SplashEmblem()
                        .frame(width: 128, height: 128)
                        .glassEffect(.regular.tint(Theme.accent.opacity(0.22)), in: .rect(cornerRadius: 36))
                        .shadow(color: Theme.accent.opacity(0.45), radius: 30)
                        .scaleEffect(iconVisible ? (exit ? 1.3 : 1) : 0.2)
                        .rotation3DEffect(.degrees(iconVisible ? 0 : 75), axis: (x: 1, y: 0.2, z: 0), perspective: 0.6)
                        .opacity(iconVisible ? 1 : 0)
                }
                .frame(height: 300)

                VStack(spacing: 10) {
                    Text("LiDAR Studio")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.titleGradient)
                        .opacity(titleVisible ? 1 : 0)
                        .blur(radius: titleVisible ? 0 : 12)
                        .offset(y: titleVisible ? 0 : 18)

                    Text("Räume · Objekte · Punktwolken · Messen")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .opacity(subtitleVisible ? 1 : 0)
                        .offset(y: subtitleVisible ? 0 : 10)
                }
            }
            .opacity(exit ? 0 : 1)
        }
        .task {
            start = Date()
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.spring(duration: 1.0, bounce: 0.4)) { iconVisible = true }
            ringsVisible = true
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.smooth(duration: 0.8)) { titleVisible = true }
            pulse = true
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.smooth(duration: 0.7)) { subtitleVisible = true }
            try? await Task.sleep(for: .milliseconds(1300))
            withAnimation(.easeIn(duration: 0.35)) { exit = true }
            try? await Task.sleep(for: .milliseconds(200))
            onFinish()
        }
    }
}

private struct SplashEmblem: View {
    @State private var sweep = false

    var body: some View {
        ZStack {
            Image(systemName: "viewfinder")
                .font(.system(size: 76, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.9))
            Image(systemName: "cube.transparent")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Theme.titleGradient)
                .symbolEffect(.pulse, options: .repeating)
            // Laserlinie über dem Emblem
            Capsule()
                .fill(Theme.accent)
                .frame(width: 84, height: 2)
                .shadow(color: Theme.accent, radius: 6)
                .offset(y: sweep ? 34 : -34)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: sweep)
        }
        .onAppear { sweep = true }
    }
}

/// Punktraster, das von einer Laserlinie von oben nach unten "eingescannt" wird.
struct LidarDotField: View {
    let start: Date

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { gc, size in
                let progress = min(max(t / 1.9, 0), 1)
                let eased = 1 - pow(1 - progress, 3)
                let laserY = (size.height + 40) * eased - 20
                let spacing: CGFloat = 22
                let cols = Int(size.width / spacing) + 2
                let rows = Int(size.height / spacing) + 2

                for r in 0..<rows {
                    let y = CGFloat(r) * spacing + 6
                    let dy = laserY - y
                    if dy < -2 { continue }
                    let glow = max(0, 1 - abs(dy) / 140)
                    for c in 0..<cols {
                        let x = CGFloat(c) * spacing + (r.isMultiple(of: 2) ? spacing / 2 : 0)
                        let wave = 0.5 + 0.5 * sin(Double(c) * 0.55 + Double(r) * 0.33 + t * 2.2)
                        let alpha = min(1, 0.08 + 0.16 * wave + glow * 0.9)
                        let radius = 1.1 + glow * 2.0
                        let mix = Double(x / max(size.width, 1))
                        let color = Color(hue: 0.54 + 0.17 * mix, saturation: 0.75, brightness: 1)
                        gc.fill(
                            Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(color.opacity(alpha))
                        )
                    }
                }

                if progress < 1 {
                    gc.drawLayer { layer in
                        layer.addFilter(.blur(radius: 16))
                        layer.fill(
                            Path(CGRect(x: 0, y: laserY - 10, width: size.width, height: 20)),
                            with: .color(Theme.accent.opacity(0.8))
                        )
                    }
                    gc.fill(
                        Path(CGRect(x: 0, y: laserY - 1, width: size.width, height: 2)),
                        with: .linearGradient(
                            Gradient(colors: [.clear, .white, Theme.accent, .white, .clear]),
                            startPoint: CGPoint(x: 0, y: laserY),
                            endPoint: CGPoint(x: size.width, y: laserY)
                        )
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
