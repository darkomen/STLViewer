import SwiftUI

@main
struct STLViewerApp: App {
    @StateObject private var library = ViewerLibraryModel()

    var body: some Scene {
        WindowGroup("STLViewer", id: "main") {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
