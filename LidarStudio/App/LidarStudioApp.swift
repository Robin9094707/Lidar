import SwiftUI

@main
struct LidarStudioApp: App {
    @State private var store = ScanStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum AppTab: Hashable {
    case scan, library, settings
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .scan
    var activeScan: ScanMode?

    func start(_ mode: ScanMode) {
        Haptics.tap()
        activeScan = mode
    }
}
