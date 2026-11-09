import SwiftUI

/// Covers the whole game while the device is offline. It closes on its own as soon
/// as a connection comes back.
struct OfflinePanel: View {
    @Environment(\.uiScale) private var scale
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 16 * scale) {
                Image(systemName: "wifi.slash")
                    .scaledFont(size: 30, weight: .bold, design: .default)
                    .foregroundStyle(Theme.danger)
                VStack(spacing: 6 * scale) {
                    Text("No internet connection")
                        .scaledFont(size: 26)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Text("Meme Mimic needs Wi-Fi or mobile data. Connect and the game picks up right where you left off.")
                        .scaledFont(.body, weight: .medium)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                Button("Try again") {
                    Haptics.select()
                    network.recheck()
                }
                .buttonStyle(ChunkyButtonStyle(height: 56))
                .accessibilityIdentifier("offline.retry")
            }
            .padding(24 * scale)
            .glassPanel()
            .padding(.horizontal, 28 * scale)
            .frame(maxWidth: 440 * scale)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
    }
}
