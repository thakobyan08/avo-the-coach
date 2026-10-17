import SwiftUI

@main
struct AvoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(model.isPaused ? .menuBarIconPaused : .menuBarIcon)
                .accessibilityLabel(model.isPaused ? "Avo, paused" : "Avo")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
