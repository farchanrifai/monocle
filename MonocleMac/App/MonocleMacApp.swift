import SwiftUI

@main
struct MonocleMacApp: App {
    @State private var state = MacAppState(model: .shared)

    var body: some Scene {
        WindowGroup(id: "main") {
            MacRootView(state: state)
                .preferredColorScheme(state.model.preferredColorScheme)
                .modifier(SettingsOpener(state: state))
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands { MonocleMacCommands(state: state) }

        Settings { MacSettingsView(state: state).preferredColorScheme(state.model.preferredColorScheme) }
    }
}

/// Hands the environment's openSettings to MacAppState so commands outside a view (command bar, buttons) can use it.
private struct SettingsOpener: ViewModifier {
    let state: MacAppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View { content.onAppear { state.openSettings = openSettings; state.openWindow = openWindow } }
}
