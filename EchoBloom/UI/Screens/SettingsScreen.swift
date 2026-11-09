import StoreKit
import SwiftUI
import UIKit

/// Settings, opened from the gear on the home screen.
struct SettingsSheet: View {
    @Environment(\.uiScale) private var scale
    @Environment(GameModel.self) private var game
    @EnvironmentObject private var ads: AdsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var confirmingReset = false
    @State private var mic: AudioEngine.MicAccess = .unknown

    var body: some View {
        @Bindable var game = game
        VStack(spacing: 0 * scale) {
            HStack {
                Text("Settings")
                    .scaledFont(size: 30)
                    .foregroundStyle(Theme.text)
                Spacer()
                IconButton(symbol: "xmark", label: "Close settings") { dismiss() }
            }
            .padding(.horizontal, 20 * scale)
            .padding(.top, 22 * scale)
            .padding(.bottom, 12 * scale)

            ScrollView {
                VStack(spacing: 18 * scale) {
                    section("Sound & feel") {
                        ToggleRow(symbol: "speaker.wave.2.fill", title: "Sound effects",
                                  isOn: Binding(get: { !game.muted }, set: { game.muted = !$0 }))
                        Divider().overlay(Theme.stroke)
                        ToggleRow(symbol: "iphone.radiowaves.left.and.right", title: "Vibration", isOn: $game.hapticsOn)
                    }

                    section("Microphone") {
                        HStack {
                            RowLabel(symbol: "mic.fill", title: micTitle)
                            Spacer()
                            if mic != .granted {
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                }
                                .scaledFont(.subheadline, weight: .bold)
                                .foregroundStyle(Theme.accent)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.glow)
                            }
                        }
                        Text("Meme Mimic listens only while you record a take. Audio is scored on this phone and never uploaded.")
                            .scaledFont(.footnote)
                            .foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    section("Privacy") {
                        Button {
                            if let url = URL(string: "https://odd-resonance-a8b9.ayoublotfi1337.workers.dev/Mimic-Privacy") {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                RowLabel(symbol: "lock.shield.fill", title: "Privacy policy")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the Meme Mimic privacy policy in your browser")

                        if ads.isPrivacyOptionsRequired {
                            Divider().overlay(Theme.stroke)
                            Button {
                                Task { await ads.presentPrivacyOptions() }
                            } label: {
                                HStack {
                                    RowLabel(symbol: "hand.raised.fill", title: "Privacy choices")
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    section("Rate & share") {
                        Button {
                            requestReview()
                            Haptics.select()
                        } label: {
                            HStack {
                                RowLabel(symbol: "star.fill", title: "Rate us")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(Theme.stroke)

                        if let appLink = ads.remote.appLink {
                            ShareLink(
                                item: appLink,
                                subject: Text("Meme Mimic"),
                                message: Text("Play Meme Mimic with me!")
                            ) {
                                HStack {
                                    RowLabel(symbol: "square.and.arrow.up.fill", title: "Share the app")
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack {
                                RowLabel(symbol: "square.and.arrow.up.fill", title: "Share the app", tint: Theme.faint)
                                Spacer()
                                Text("Link unavailable")
                                    .scaledFont(.caption, weight: .bold)
                                    .foregroundStyle(Theme.faint)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    section("Crew") {
                        Button {
                            if confirmingReset {
                                game.resetCrew()
                                confirmingReset = false
                            } else {
                                withAnimation(.spring(duration: 0.3)) { confirmingReset = true }
                                Haptics.warning()
                                Task {
                                    try? await Task.sleep(for: .seconds(3))
                                    withAnimation { confirmingReset = false }
                                }
                            }
                        } label: {
                            HStack {
                                RowLabel(symbol: "arrow.counterclockwise", title: confirmingReset ? "Tap again to reset" : "Reset crew",
                                         tint: Theme.danger)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.reset")
                        Text("Back to one player with a new color, 3 rounds and every sound pack.")
                            .scaledFont(.footnote)
                            .foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: 4 * scale) {
                        Text("Meme Mimic \(version)")
                            .scaledFont(.footnote, weight: .bold)
                            .foregroundStyle(Theme.muted)
                        Text("Characters by Quaternius (CC0)")
                            .scaledFont(.caption)
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(.top, 6 * scale)
                    .padding(.bottom, 24 * scale)
                }
                .padding(.horizontal, 20 * scale)
            }
        }
        .background(
            LinearGradient(colors: [Theme.panel, Theme.ink, Color(red: 0.24, green: 0.01, blue: 0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .presentationDetents([.large])
        .presentationBackground(Theme.ink)
        .presentationCornerRadius(36)
        .onAppear { mic = game.micAccess }
    }

    private var micTitle: String {
        switch mic {
        case .granted: "Microphone allowed"
        case .denied: "Microphone is off"
        case .unknown: "Asked on your first take"
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Eyebrow(text: title, color: Theme.glow)
                .padding(.leading, 4 * scale)
            VStack(spacing: 14 * scale) { content() }
                .padding(16 * scale)
                .glassPanel(radius: 22)
        }
    }
}

private struct RowLabel: View {
    @Environment(\.uiScale) private var scale
    let symbol: String
    let title: String
    var tint: Color = Theme.text

    var body: some View {
        Label {
            Text(title).scaledFont(.headline, weight: .bold).foregroundStyle(tint)
        } icon: {
            Image(systemName: symbol)
                .scaledFont(size: 15, weight: .bold, design: .default)
                .foregroundStyle(tint == Theme.text ? Theme.glow : tint)
                .frame(width: 28 * scale)
        }
    }
}

private struct ToggleRow: View {
    @Environment(\.uiScale) private var scale
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { RowLabel(symbol: symbol, title: title) }
            .tint(Theme.accent)
    }
}
