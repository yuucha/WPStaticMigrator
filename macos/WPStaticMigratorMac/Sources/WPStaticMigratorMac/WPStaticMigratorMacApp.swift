import SwiftUI

@main
struct WPStaticMigratorMacApp: App {
    @StateObject private var model = MigratorModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommandButton()
            }
            CommandGroup(replacing: .newItem) { }
        }

        Window("WPStaticMigratorについて", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
