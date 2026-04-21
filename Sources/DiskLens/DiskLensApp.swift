import SwiftUI

@main
struct DiskLensApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
