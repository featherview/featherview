import SwiftUI

// Scaffold only: replaced in Task 10 of docs/superpowers/plans/2026-10-15-featherview-v1.md.
@main
struct FeatherviewApp: App {
    var body: some Scene {
        Window("Featherview", id: "viewer") {
            Text("Featherview")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
