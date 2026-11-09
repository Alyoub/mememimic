import SwiftUI

struct RootView: View {
    @Environment(GameModel.self) private var game
    @EnvironmentObject private var ads: AdsManager
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    @State private var windowSize: CGSize = .zero

    /// 1 on iPhone and in narrow iPad windows; larger in full-size iPad windows.
    private var scale: CGFloat {
        .uiScale(for: windowSize, roomy: widthClass == .regular && heightClass == .regular)
    }

    /// Width of the controls column when a wide iPad window splits stage and controls
    /// side by side; nil keeps the stacked layout (always on iPhone).
    private var sidePanelWidth: CGFloat? {
        guard scale > 1, windowSize.width > windowSize.height * 1.15 else { return nil }
        return min(windowSize.width * 0.45, 560 * scale + 64)
    }

    var body: some View {
        @Bindable var game = game
        let side = sidePanelWidth
        ZStack {
            TheaterBackdrop().ignoresSafeArea()
            // One stage view in every layout, so rotating never reloads the cast. In the
            // side-by-side iPad layout it is wider than the window and shifted left: centered
            // in the free space, running on under the controls instead of ending in a hard
            // edge. With no side column both modifiers do nothing.
            Color.clear
                .overlay {
                    StageView()
                        .frame(width: side.map { windowSize.width + $0 })
                        .offset(x: -(side ?? 0) / 2)
                }
                .ignoresSafeArea()
            VStack {
                Spacer()
                BottomScrim().frame(height: 520)
            }
            .ignoresSafeArea()
            if let side {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SideScrim().frame(width: side + 120)
                }
                .ignoresSafeArea()
            }

            Vignette().ignoresSafeArea()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }

            screen
                .id(game.screen)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 40)),
                    removal: .opacity.combined(with: .offset(y: -12))
                ))
        }
        .overlay {
            if game.isConfirmingQuit { QuitPanel() }
        }
        .overlay {
            if game.isSplashing { SplashView() }
        }
        .overlay {
            if !network.isConnected { OfflinePanel() }
        }
        .animation(.spring(duration: 0.35), value: network.isConnected)
        .overlay(alignment: .top) {
            if let notice = game.notice {
                NoticeBanner(text: notice)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $game.showHowToPlay) { HowToPlaySheet().environment(\.uiScale, sheetScale) }
        .sheet(isPresented: $game.showSettings) { SettingsSheet().environment(\.uiScale, sheetScale) }
        .environment(\.uiScale, scale)
        .environment(\.sidePanelWidth, side)
        .animation(.spring(duration: 0.45), value: side)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .simultaneousGesture(TapGesture().onEnded {
            ads.recordTap(safeToPresent: isSafeAdBreak)
        })
        .onChange(of: game.screen) { _, _ in
            if isSafeAdBreak { ads.presentPendingInterstitial() }
        }
        .onChange(of: network.isConnected) { _, connected in
            if connected {
                ads.connectionRestored()
            } else {
                // Sheets sit above the offline panel, so close them.
                game.showSettings = false
                game.showHowToPlay = false
            }
        }
    }

    private var isSafeAdBreak: Bool {
        switch game.screen {
        case .home, .crew, .packs, .recap, .podium: true
        case .handoff, .turn, .reveal: false
        }
    }

    /// Sheets sit in a form-sized card on iPad, so they only grow a little.
    private var sheetScale: CGFloat { scale == 1 ? 1 : min(scale, 1.12) }

    @ViewBuilder private var screen: some View {
        switch game.screen {
        case .home: HomeScreen()
        case .crew: CrewScreen()
        case .packs: PacksScreen()
        case .handoff: HandoffScreen()
        case .turn: TurnScreen()
        case .reveal: RevealScreen()
        case .recap: RecapScreen()
        case .podium: PodiumScreen()
        }
    }
}

/// Shared layout: a top bar, open space for the 3D stage, and content pinned to the bottom.
struct Scaffold<Top: View, Bottom: View>: View {
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom
    @Environment(\.uiScale) private var scale
    @Environment(\.sidePanelWidth) private var sidePanelWidth

    var body: some View {
        if let sidePanelWidth {
            // Wide iPad: top bar across the window, controls in a column on the right
            // with the stage to their left.
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        bottom
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 46 * scale + 40)
                    .padding(.bottom, 28)
                    .frame(width: sidePanelWidth)
                }
                top
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
            }
        } else {
            stacked
        }
    }

    @ViewBuilder private var stacked: some View {
        // On iPad the margins open up and the panel grows with the type, so the screen
        // reads as a tablet layout rather than a phone column. At scale 1 these are the
        // original iPhone values.
        let roomy = scale > 1
        VStack(spacing: 0) {
            top
                .padding(.horizontal, roomy ? 32 : 20)
                .padding(.top, roomy ? 16 : 6)
            Spacer(minLength: 0)
            bottom
                .padding(.horizontal, roomy ? 32 : 20)
                .padding(.bottom, roomy ? 28 : 8)
                .frame(maxWidth: 560 * scale + (roomy ? 64 : 0))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Darkens the right edge behind the controls column in the side-by-side iPad layout.
private struct SideScrim: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Theme.ink.opacity(0.35), location: 0.35),
            .init(color: Theme.ink.opacity(0.62), location: 1),
        ], startPoint: .leading, endPoint: .trailing)
        .allowsHitTesting(false)
    }
}
