import SwiftUI

@main
struct LLMStatusApp: App {
    @State private var monitor = StatusMonitor()

    var body: some Scene {
        MenuBarExtra {
            Text("LLM Status")
                .padding()
        } label: {
            Image(systemName: monitor.aggregatedStatus.sfSymbol)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 320, height: 400)
        .onChange(of: monitor.aggregatedStatus) { _, _ in }
        .task {
            monitor.startPolling()
        }
    }
}
