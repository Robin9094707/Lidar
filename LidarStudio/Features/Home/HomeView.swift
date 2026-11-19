import SwiftUI

struct HomeView: View {
    @Environment(ScanStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var appeared = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                        .staggered(appeared, index: 0)

                    heroCard
                        .staggered(appeared, index: 1)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array([ScanMode.object, .mesh, .pointCloud, .measure].enumerated()), id: \.element) { index, mode in
                            ModeTile(mode: mode) { router.start(mode) }
                                .staggered(appeared, index: index + 2)
                        }
                    }

                    if !store.items.isEmpty {
                        recentSection
                            .staggered(appeared, index: 6)
                    }

                    capabilityCard
                        .staggered(appeared, index: 7)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background(AuroraBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                ScanDetailView(itemID: id)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.3).delay(0.15)) { appeared = true }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("LiDAR Studio")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.titleGradient)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(DeviceCapabilities.hasLiDAR ? Theme.mint : Theme.orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: DeviceCapabilities.hasLiDAR ? Theme.mint : Theme.orange, radius: 4)
                Text(DeviceCapabilities.hasLiDAR ? "LiDAR" : "Kein LiDAR")
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.top, 12)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<18: return "Guten Tag"
        default: return "Guten Abend"
        }
    }

    private var heroCard: some View {
        Button {
            router.start(.room)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoomIllustration()
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "house.fill")
                        Text("RoomPlan")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.2)), in: .capsule)

                    Text("Raum scannen")
                        .font(.title.weight(.bold))
                    Text(ScanMode.room.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .bottomLeading)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.right")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(16)
            }
            .contentShape(.rect(cornerRadius: 32))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.accent.opacity(0.12)).interactive(), in: .rect(cornerRadius: 32))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Zuletzt")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Alle") { router.selectedTab = .library }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.items.prefix(10)) { item in
                        NavigationLink(value: item.id) {
                            ScanCard(item: item)
                                .frame(width: 190)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Dein Gerät", systemImage: "iphone.gen3")
                .font(.headline)
            CapabilityRow(title: "LiDAR-Scanner", available: DeviceCapabilities.hasLiDAR)
            CapabilityRow(title: "Tiefenkarte (Scene Depth)", available: DeviceCapabilities.supportsSceneDepth)
            CapabilityRow(title: "RoomPlan", available: DeviceCapabilities.supportsRoomPlan)
            CapabilityRow(title: "Object Capture", available: DeviceCapabilities.supportsObjectCapture)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

struct CapabilityRow: View {
    let title: String
    let available: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? Theme.mint : .secondary)
        }
    }
}

struct ModeTile: View {
    let mode: ScanMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(mode.tint)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.tint(mode.tint.opacity(0.25)), in: .circle)
                Spacer(minLength: 0)
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(mode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            .padding(18)
            .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(mode.tint.opacity(0.10)).interactive(), in: .rect(cornerRadius: 28))
    }
}

/// Animierte isometrische Raum-Illustration mit Scan-Ebene.
struct RoomIllustration: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let s = min(size.width, size.height) * 0.42
                let cx = size.width * 0.62
                let cy = size.height * 0.62

                func iso(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                    CGPoint(x: cx + (x - z) * s * 0.866, y: cy + (x + z) * s * 0.5 - y * s)
                }

                let accent = Theme.accent
                let violet = Theme.violet

                // Bodenraster
                for i in 0...8 {
                    let f = -1 + Double(i) * 0.25
                    var p1 = Path(); p1.move(to: iso(f, 0, -1)); p1.addLine(to: iso(f, 0, 1))
                    var p2 = Path(); p2.move(to: iso(-1, 0, f)); p2.addLine(to: iso(1, 0, f))
                    gc.stroke(p1, with: .color(accent.opacity(0.15)), lineWidth: 0.8)
                    gc.stroke(p2, with: .color(accent.opacity(0.15)), lineWidth: 0.8)
                }

                // Wände
                var walls = Path()
                walls.move(to: iso(-1, 0, 1)); walls.addLine(to: iso(-1, 0, -1)); walls.addLine(to: iso(1, 0, -1))
                walls.move(to: iso(-1, 1, 1)); walls.addLine(to: iso(-1, 1, -1)); walls.addLine(to: iso(1, 1, -1))
                walls.move(to: iso(-1, 0, 1)); walls.addLine(to: iso(-1, 1, 1))
                walls.move(to: iso(-1, 0, -1)); walls.addLine(to: iso(-1, 1, -1))
                walls.move(to: iso(1, 0, -1)); walls.addLine(to: iso(1, 1, -1))
                gc.stroke(walls, with: .linearGradient(Gradient(colors: [accent, violet]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 2)

                // Tür und Fenster
                var door = Path()
                door.move(to: iso(-1, 0, 0.2)); door.addLine(to: iso(-1, 0.7, 0.2)); door.addLine(to: iso(-1, 0.7, 0.6)); door.addLine(to: iso(-1, 0, 0.6))
                gc.stroke(door, with: .color(Theme.yellow.opacity(0.9)), lineWidth: 1.5)
                var window = Path()
                window.move(to: iso(-0.3, 0.45, -1)); window.addLine(to: iso(0.4, 0.45, -1)); window.addLine(to: iso(0.4, 0.8, -1)); window.addLine(to: iso(-0.3, 0.8, -1)); window.closeSubpath()
                gc.stroke(window, with: .color(violet.opacity(0.9)), lineWidth: 1.5)

                // Möbel (Tisch)
                func box(_ x0: Double, _ x1: Double, _ y1: Double, _ z0: Double, _ z1: Double, _ color: Color) {
                    var p = Path()
                    p.move(to: iso(x0, y1, z0)); p.addLine(to: iso(x1, y1, z0)); p.addLine(to: iso(x1, y1, z1)); p.addLine(to: iso(x0, y1, z1)); p.closeSubpath()
                    p.move(to: iso(x0, 0, z1)); p.addLine(to: iso(x0, y1, z1))
                    p.move(to: iso(x1, 0, z1)); p.addLine(to: iso(x1, y1, z1))
                    p.move(to: iso(x1, 0, z0)); p.addLine(to: iso(x1, y1, z0))
                    gc.stroke(p, with: .color(color), lineWidth: 1.5)
                }
                box(-0.1, 0.5, 0.35, -0.1, 0.4, Theme.orange.opacity(0.9))
                box(-0.8, -0.45, 0.25, -0.85, -0.2, Theme.pink.opacity(0.9))

                // Scan-Ebene
                let phase = (sin(t * 0.9) + 1) / 2
                let x = -1 + phase * 2
                var plane = Path()
                plane.move(to: iso(x, 0, -1)); plane.addLine(to: iso(x, 1, -1)); plane.addLine(to: iso(x, 1, 1)); plane.addLine(to: iso(x, 0, 1)); plane.closeSubpath()
                gc.fill(plane, with: .color(accent.opacity(0.10)))
                gc.drawLayer { layer in
                    layer.addFilter(.blur(radius: 4))
                    layer.stroke(plane, with: .color(accent.opacity(0.9)), lineWidth: 2)
                }
                gc.stroke(plane, with: .color(.white.opacity(0.8)), lineWidth: 0.8)

                // Messpunkte
                for i in 0..<14 {
                    let fx = sin(Double(i) * 12.9898) * 0.5 + 0.5
                    let fz = sin(Double(i) * 78.233) * 0.5 + 0.5
                    let px = -1 + fx * 2
                    if px > x { continue }
                    let point = iso(px, 0, -1 + fz * 2)
                    gc.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)), with: .color(Theme.mint))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Gestaffeltes Einblenden beim ersten Erscheinen.
    func staggered(_ visible: Bool, index: Int) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 30)
            .scaleEffect(visible ? 1 : 0.96)
            .animation(.spring(duration: 0.7, bounce: 0.3).delay(Double(index) * 0.06), value: visible)
    }
}
