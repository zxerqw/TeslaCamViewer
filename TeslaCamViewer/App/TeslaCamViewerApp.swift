import SwiftUI

@main
struct TeslaCamViewerApp: App {
    @State private var deps = AppDependencies()

    var body: some Scene {
        WindowGroup { RootView(deps: deps) }
    }
}
