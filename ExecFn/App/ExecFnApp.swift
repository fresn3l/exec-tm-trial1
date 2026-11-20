import SwiftUI

@main
struct ExecFnApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            DayScreen(model: model)
        }
        .defaultSize(width: 920, height: 760)
        Settings {
            SettingsScreen(model: model)
        }
    }
}
