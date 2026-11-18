import SwiftUI

@main
struct PipApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsScreen()
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 560)
        .windowResizability(.contentSize)
        #endif
    }
}
