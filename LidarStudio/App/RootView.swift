import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    var body: some View {
        @Bindable var router = router

        ZStack {
            MainTabView()
                .opacity(showSplash ? 0 : 1)
                .scaleEffect(showSplash ? 0.92 : 1)
                .blur(radius: showSplash ? 16 : 0)

            if showSplash {
                SplashView {
                    withAnimation(.smooth(duration: 0.9)) {
                        showSplash = false
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.12)))
                .zIndex(1)
            }
        }
        .background(Color.black)
        .fullScreenCover(item: $router.activeScan) { mode in
            ScanModeContainer(mode: mode)
                .onAppear { SensorHub.shared.acquirePrecision() }
                .onDisappear { SensorHub.shared.releasePrecision() }
        }
        .onAppear { SensorHub.shared.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                SensorHub.shared.start()
            } else if phase == .background {
                SensorHub.shared.stop()
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ScanStore.self) private var store

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Scannen", systemImage: "viewfinder", value: AppTab.scan) {
                HomeView()
            }
            Tab("Bibliothek", systemImage: "square.stack.3d.up.fill", value: AppTab.library) {
                LibraryView()
            }
            .badge(store.items.count)
            Tab("Sensoren", systemImage: "sensor.fill", value: AppTab.sensors) {
                SensorsView()
            }
            Tab("Einstellungen", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            QuickScanAccessory()
        }
    }
}

/// Liquid-Glass-Zubehör über der Tab-Bar: Schnellstart für die häufigsten Modi.
struct QuickScanAccessory: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(Theme.accent)
            if placement != .inline {
                Text(DeviceCapabilities.hasLiDAR ? "LiDAR bereit" : "Kein LiDAR")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 4)
            Button {
                router.start(.measure)
            } label: {
                Image(systemName: "ruler")
            }
            Button {
                router.start(.room)
            } label: {
                Label("Raum", systemImage: "house.fill")
                    .labelStyle(.titleAndIcon)
            }
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
    }
}

struct ScanModeContainer: View {
    let mode: ScanMode

    var body: some View {
        switch mode {
        case .room:
            RoomScanView()
        case .object:
            ObjectCaptureFlowView()
        case .mesh:
            LidarCaptureView(mode: .mesh)
        case .pointCloud:
            LidarCaptureView(mode: .pointCloud)
        case .measure:
            MeasureView()
        }
    }
}
