import SwiftUI

@main @MainActor
struct LinkAffApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Brand.accent)
                .onChange(of: scenePhase, initial: true) { _, phase in model.setForeground(phase == .active) }
        }
    }
}
