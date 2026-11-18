import SwiftUI
import NoorKit

@main
struct NoorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task { _ = Quran.shared }   // build the mushaf index once, off the UI path
        }
    }
}
