import SwiftUI

@main
struct EchoBloomApp: App {
    @State private var game = GameModel()
    @StateObject private var ads = AdsManager.shared
    @StateObject private var network = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(game)
                .environmentObject(ads)
                .environmentObject(network)
                .task {
                    game.setRealSounds(ads.remote.realSound)
                    await ads.start()
                    game.setRealSounds(ads.remote.realSound)
                }
                .onChange(of: ads.remote.realSound) { _, enabled in
                    game.setRealSounds(enabled)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { ads.applicationDidBecomeActive() }
                }
        }
    }
}
