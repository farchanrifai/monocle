import SwiftUI

@main
struct MonocleMacApp: App {
    @State private var state = MacAppState(model: .shared)

    var body: some Scene {
        WindowGroup {
            MacRootView(state: state)
                .preferredColorScheme(state.model.preferredColorScheme)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands { MonocleMacCommands(state: state) }

        Settings { MacSettingsView(state: state) }
    }
}
