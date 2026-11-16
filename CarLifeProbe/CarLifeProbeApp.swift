import SwiftUI

@main
struct CarLifeProbeApp: App {
    @StateObject private var model = ProbeModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
