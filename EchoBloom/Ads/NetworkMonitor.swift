import Combine
import Foundation
import Network

/// Publishes whether the device can actually reach the internet. The game is blocked
/// while offline so the ad flow cannot be skipped by turning off Wi-Fi.
///
/// A Wi-Fi network with no internet behind it still counts as connected to the
/// system, so every result is confirmed with a real request.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    // Starts out connected so the offline panel never flashes at launch before the
    // first check finishes.
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private var hasChecked = false
    private var isChecking = false

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 6
        return URLSession(configuration: config)
    }()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.pathChanged(satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
        Task { await pollForever() }
    }

    func recheck() {
        Task { await check() }
    }

    func waitUntilConnected() async {
        while !hasChecked || !isConnected {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func pathChanged(satisfied: Bool) {
        if satisfied {
            recheck()
        } else {
            hasChecked = true
            isConnected = false
        }
    }

    /// The path does not change when the internet drops behind a working Wi-Fi
    /// network, so keep checking: often while offline to notice the fix quickly,
    /// and less often while online.
    private func pollForever() async {
        while true {
            try? await Task.sleep(for: .seconds(isConnected ? 15 : 3))
            await check()
        }
    }

    private func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let reachable = monitor.currentPath.status == .satisfied
            ? await Self.canReachInternet()
            : false
        hasChecked = true
        if isConnected != reachable { isConnected = reachable }
    }

    /// Google first, Apple as a fallback for regions where Google is blocked. Both are
    /// HTTPS, so a captive portal login page cannot answer for them.
    private static func canReachInternet() async -> Bool {
        if await probe("https://www.google.com/generate_204", expecting: 204) { return true }
        return await probe("https://captive.apple.com/hotspot-detect.html", expecting: 200)
    }

    private static func probe(_ address: String, expecting status: Int) async -> Bool {
        guard let url = URL(string: address) else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == status
        } catch {
            return false
        }
    }
}
