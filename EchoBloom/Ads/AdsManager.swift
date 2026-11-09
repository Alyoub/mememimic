import AppTrackingTransparency
import Combine
import Foundation
@preconcurrency import GoogleMobileAds
import UIKit
import UserMessagingPlatform

struct RemoteAppConfig: Equatable {
    // Copyright-safe mode is the offline/malformed-config fallback.
    var realSound = false
    var interstitialEvery = 5
    var adsEnabled = true
    var appOpenEnabled = true
    var interstitialEnabled = true
    var rewardedEnabled = true
    var appLink: URL?
}

/// Owns privacy consent, remote ad frequency, and every full-screen ad format.
///
/// Debug builds deliberately use Google's test units. Production IDs are compiled
/// into Release builds only, which prevents accidental invalid traffic while testing.
@MainActor
final class AdsManager: NSObject, ObservableObject, FullScreenContentDelegate {
    static let shared = AdsManager()
    static let remoteConfigURL = URL(string: "https://alyoub.github.io/mimic-config.json")!

    private enum LiveID {
        static let appOpen = "ca-app-pub-3764968393873025/7669522204"
        static let rewarded = "ca-app-pub-3764968393873025/8515700019"
        static let interstitial = "ca-app-pub-3764968393873025/9337119254"
    }

    private enum TestID {
        static let appOpen = "ca-app-pub-3940256099942544/5575463023"
        static let rewarded = "ca-app-pub-3940256099942544/1712485313"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    }

    private static var appOpenID: String {
#if DEBUG
        TestID.appOpen
#else
        LiveID.appOpen
#endif
    }

    private static var rewardedID: String {
#if DEBUG
        TestID.rewarded
#else
        LiveID.rewarded
#endif
    }

    private static var interstitialID: String {
#if DEBUG
        TestID.interstitial
#else
        LiveID.interstitial
#endif
    }

    @Published private(set) var remote = RemoteAppConfig()
    @Published private(set) var isPrivacyOptionsRequired = false

    private var appOpenAd: AppOpenAd?
    private var appOpenLoadTime: Date?
    private var interstitialAd: InterstitialAd?
    private var rewardedAd: RewardedAd?
    private var isLoadingAppOpen = false
    private var isLoadingInterstitial = false
    private var isLoadingRewarded = false
    private var isPresenting = false
    private var isStarting = false
    private var hasStarted = false
    private var pendingInterstitial = false
    private var completionAfterAd: (() -> Void)?
    private var rewardedCompletion: ((Bool) -> Void)?
    private var rewardEarned = false
    private var tapCount = 0
    private var presentingKind: PresentedAd?

    private enum PresentedAd { case appOpen, interstitial, rewarded }

    private override init() {
        super.init()
        loadCachedRemoteConfig()
        log("Manager created. Cached config: \(remote.debugSummary)")
    }

    func start() async {
        log("Start requested. hasStarted=\(hasStarted), isStarting=\(isStarting), uiTesting=\(Self.isUITesting)")
        guard !hasStarted else { log("Start skipped: SDK flow already completed."); return }
        guard !isStarting else { log("Start skipped: initialization is already running."); return }
        guard !Self.isUITesting else { log("Start skipped: -ui-testing disables ads."); return }
        isStarting = true

        await NetworkMonitor.shared.waitUntilConnected()
        await refreshRemoteConfig()
        await waitUntilApplicationIsActive()
        await requestTrackingIfNeeded()
        await updateConsent()

        guard remote.adsEnabled else {
            log("Initialization stopped: remote adsEnabled is false.")
            isStarting = false
            hasStarted = true
            return
        }
        guard ConsentInformation.shared.canRequestAds else {
            log("Initialization stopped: UMP canRequestAds is false. consentStatus=\(ConsentInformation.shared.consentStatus.rawValue)")
            isStarting = false
            hasStarted = true
            return
        }

        log("Starting Google Mobile Ads SDK.")
        await MobileAds.shared.start()
        log("Google Mobile Ads SDK initialized.")
        hasStarted = true
        await loadInterstitial()
        await loadRewarded()
        await loadAppOpen()
        isStarting = false
        log("Initial load pass finished. interstitial=\(interstitialAd != nil), rewarded=\(rewardedAd != nil), appOpen=\(isAppOpenAvailable)")
        showAppOpenIfAvailable()
    }

    /// Counts meaningful taps. At N-1 the next interstitial is prepared; at N it is
    /// shown only on a safe break screen, or deferred until the next safe break.
    func recordTap(safeToPresent: Bool) {
        guard hasStarted, remote.adsEnabled, remote.interstitialEnabled, !isPresenting else { return }
        let interval = remote.interstitialEvery
        guard interval >= 2 else { log("Tap ads disabled: interstitialEvery=\(interval)."); return }

        tapCount += 1
        log("Tap counter \(tapCount)/\(interval), safeToPresent=\(safeToPresent).")
        if tapCount == interval - 1, interstitialAd == nil {
            log("Reached N-1; preloading interstitial.")
            Task { await loadInterstitial() }
        }
        guard tapCount >= interval else { return }

        tapCount = 0
        pendingInterstitial = true
        if safeToPresent { presentPendingInterstitial() }
    }

    func presentPendingInterstitial() {
        guard pendingInterstitial else { return }
        guard !isPresenting else { log("Pending interstitial deferred: another ad is presenting."); return }
        pendingInterstitial = false
        showInterstitial()
    }

    /// Used at explicit natural breaks, such as just before final results or Settings.
    func showInterstitial(completion: (() -> Void)? = nil) {
        guard remote.adsEnabled else { log("Interstitial skipped: adsEnabled=false."); completion?(); return }
        guard remote.interstitialEnabled else { log("Interstitial skipped: interstitial=false."); completion?(); return }
        guard !isPresenting else { log("Interstitial skipped: another ad is presenting."); completion?(); return }
        guard let ad = interstitialAd else {
            log("Interstitial skipped: no loaded ad is available; starting a reload.")
            completion?()
            Task { await loadInterstitial() }
            return
        }
        guard let controller = Self.topViewController() else { log("Interstitial skipped: no view controller."); completion?(); return }
        log("Presenting interstitial.")
        completionAfterAd = completion
        interstitialAd = nil
        isPresenting = true
        presentingKind = .interstitial
        ad.present(from: controller)
    }

    /// Shown before Settings and the winner reveal. The completion value reports
    /// whether the reward was earned; callers that gate nothing can ignore it.
    func showRewarded(completion: @escaping (Bool) -> Void) {
        guard remote.adsEnabled else { log("Rewarded skipped: adsEnabled=false."); completion(false); return }
        guard remote.rewardedEnabled else { log("Rewarded skipped: rewarded=false."); completion(false); return }
        guard !isPresenting else { log("Rewarded skipped: another ad is presenting."); completion(false); return }
        guard let ad = rewardedAd else {
            log("Rewarded skipped: no loaded ad is available; starting a reload.")
            completion(false)
            Task { await loadRewarded() }
            return
        }
        guard let controller = Self.topViewController() else { log("Rewarded skipped: no view controller."); completion(false); return }
        log("Presenting rewarded ad.")
        rewardedCompletion = completion
        rewardEarned = false
        rewardedAd = nil
        isPresenting = true
        presentingKind = .rewarded
        ad.present(from: controller) { [weak self] in self?.rewardEarned = true }
    }

    func applicationDidBecomeActive() {
        log("Application became active. hasStarted=\(hasStarted), isStarting=\(isStarting), isPresenting=\(isPresenting), adsEnabled=\(remote.adsEnabled)")
        guard hasStarted, !isStarting, !isPresenting, remote.adsEnabled, remote.appOpenEnabled else { return }
        if isAppOpenAvailable {
            showAppOpenIfAvailable()
        } else {
            Task { await loadAppOpen() }
        }
    }

    /// Loads made while offline fail, so fetch fresh config and refill every slot.
    func connectionRestored() {
        log("Connection restored. hasStarted=\(hasStarted), isStarting=\(isStarting)")
        guard hasStarted, !isStarting else { return }
        Task {
            await refreshRemoteConfig()
            await loadInterstitial()
            await loadRewarded()
            await loadAppOpen()
        }
    }

    func presentPrivacyOptions() async {
        guard let controller = Self.topViewController() else { return }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: controller)
        } catch {
            log("Privacy options failed: \(Self.describe(error))")
        }
        updatePrivacyOptionsRequirement()
    }

    // MARK: Privacy

    private func requestTrackingIfNeeded() async {
        let current = ATTrackingManager.trackingAuthorizationStatus
        log("ATT status before request: \(current.rawValue).")
        guard current == .notDetermined else { return }
        let result: ATTrackingManager.AuthorizationStatus = await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        log("ATT request completed with status: \(result.rawValue).")
    }

    private func updateConsent() async {
        log("Requesting UMP consent information update.")
        let parameters = RequestParameters()
        let updateError: Error? = await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                continuation.resume(returning: error)
            }
        }
        do {
            if let updateError { throw updateError }
            try await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController())
        } catch {
            // A cached choice can still legally permit requests when the network is down.
            log("UMP consent update/form failed: \(Self.describe(error))")
        }
        updatePrivacyOptionsRequirement()
        log("UMP finished. canRequestAds=\(ConsentInformation.shared.canRequestAds), consentStatus=\(ConsentInformation.shared.consentStatus.rawValue), privacyOptionsStatus=\(ConsentInformation.shared.privacyOptionsRequirementStatus.rawValue)")
    }

    private func updatePrivacyOptionsRequirement() {
        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func waitUntilApplicationIsActive() async {
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Avoid colliding with the launch transition or another system permission alert.
        try? await Task.sleep(for: .milliseconds(350))
    }

    // MARK: Loading

    private func loadAppOpen() async {
        guard hasStarted, remote.adsEnabled, remote.appOpenEnabled, !isLoadingAppOpen, !isAppOpenAvailable else { return }
        log("Loading app-open ad using a \(Self.adUnitMode) unit.")
        isLoadingAppOpen = true
        defer { isLoadingAppOpen = false }
        do {
            let ad = try await AppOpenAd.load(with: Self.appOpenID, request: Request())
            ad.fullScreenContentDelegate = self
            appOpenAd = ad
            appOpenLoadTime = Date()
            log("App-open ad loaded successfully.")
        } catch {
            log("App-open load failed: \(Self.describe(error))")
        }
    }

    private func loadInterstitial() async {
        guard hasStarted, remote.adsEnabled, remote.interstitialEnabled, !isLoadingInterstitial, interstitialAd == nil else { return }
        log("Loading interstitial using a \(Self.adUnitMode) unit.")
        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }
        do {
            let ad = try await InterstitialAd.load(with: Self.interstitialID, request: Request())
            ad.fullScreenContentDelegate = self
            interstitialAd = ad
            log("Interstitial loaded successfully.")
        } catch {
            log("Interstitial load failed: \(Self.describe(error))")
        }
    }

    private func loadRewarded() async {
        guard hasStarted, remote.adsEnabled, remote.rewardedEnabled, !isLoadingRewarded, rewardedAd == nil else { return }
        log("Loading rewarded ad using a \(Self.adUnitMode) unit.")
        isLoadingRewarded = true
        defer { isLoadingRewarded = false }
        do {
            let ad = try await RewardedAd.load(with: Self.rewardedID, request: Request())
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            log("Rewarded ad loaded successfully.")
        } catch {
            log("Rewarded load failed: \(Self.describe(error))")
        }
    }

    private var isAppOpenAvailable: Bool {
        guard appOpenAd != nil, let appOpenLoadTime else { return false }
        return Date().timeIntervalSince(appOpenLoadTime) < 4 * 60 * 60
    }

    private func showAppOpenIfAvailable() {
        guard remote.appOpenEnabled else { log("App-open skipped: appOpen=false."); return }
        guard !isPresenting else { log("App-open skipped: another ad is presenting."); return }
        guard isAppOpenAvailable, let ad = appOpenAd else { log("App-open skipped: no fresh loaded ad."); return }
        guard let controller = Self.topViewController() else { log("App-open skipped: no view controller."); return }
        log("Presenting app-open ad.")
        appOpenAd = nil
        appOpenLoadTime = nil
        isPresenting = true
        presentingKind = .appOpen
        ad.present(from: controller)
    }

    // MARK: FullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        log("Full-screen ad dismissed. kind=\(String(describing: presentingKind))")
        finishPresentation(ad)
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        log("Full-screen presentation failed: \(Self.describe(error))")
        finishPresentation(ad)
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        log("Full-screen ad will present. kind=\(String(describing: presentingKind))")
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        log("Ad impression recorded. kind=\(String(describing: presentingKind))")
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        log("Ad click recorded. kind=\(String(describing: presentingKind))")
    }

    private func finishPresentation(_ ad: FullScreenPresentingAd) {
        isPresenting = false
        let kind = presentingKind
        presentingKind = nil
        if kind == .rewarded {
            let completion = rewardedCompletion
            rewardedCompletion = nil
            completion?(rewardEarned)
            rewardEarned = false
            Task { await loadRewarded() }
        } else if kind == .interstitial {
            let completion = completionAfterAd
            completionAfterAd = nil
            completion?()
            Task { await loadInterstitial() }
        } else {
            Task { await loadAppOpen() }
        }
    }

    // MARK: Remote config

    func refreshRemoteConfig() async {
        log("Fetching remote config from \(Self.remoteConfigURL.absoluteString)")
        var request = URLRequest(url: Self.remoteConfigURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { log("Remote config failed: response was not HTTP."); return }
            guard (200...299).contains(http.statusCode) else { log("Remote config failed with HTTP \(http.statusCode)."); return }
            let decoded = try Self.decodeRemoteConfig(data)
            remote = decoded
            cache(decoded)
            log("Remote config loaded: \(decoded.debugSummary)")
        } catch {
            log("Remote config unavailable; using \(remote.debugSummary). Error: \(Self.describe(error))")
        }
    }

    private static func decodeRemoteConfig(_ data: Data) throws -> RemoteAppConfig {
        let json = try JSONSerialization.jsonObject(with: data)
        var config = RemoteAppConfig()

        if let value = find(keys: ["realsound", "realaudio", "userealsounds"], in: json) as? Bool {
            config.realSound = value
        }
        if let value = find(keys: ["interstitialinterval", "interstitialevery", "interstitialtaps", "normaladtaps", "adtaps", "tapcount", "tapnumber", "numberoftaps", "n"], in: json) {
            if let number = value as? NSNumber { config.interstitialEvery = max(0, number.intValue) }
            if let string = value as? String, let number = Int(string) { config.interstitialEvery = max(0, number) }
        }
        if let value = find(keys: ["adsenabled", "showads"], in: json) as? Bool {
            config.adsEnabled = value
        }
        if let value = find(keys: ["appopen", "appopenenabled"], in: json) as? Bool {
            config.appOpenEnabled = value
        }
        if let value = find(keys: ["interstitial", "interstitialenabled"], in: json) as? Bool {
            config.interstitialEnabled = value
        }
        if let value = find(keys: ["rewarded", "rewardedenabled"], in: json) as? Bool {
            config.rewardedEnabled = value
        }
        if let value = find(keys: ["link", "applink", "sharelink", "storelink"], in: json) as? String,
           let url = URL(string: value),
           ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            config.appLink = url
        }
        return config
    }

    private static func find(keys: Set<String>, in value: Any) -> Any? {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary where keys.contains(normalize(key)) { return child }
            for child in dictionary.values {
                if let found = find(keys: keys, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = find(keys: keys, in: child) { return found }
            }
        }
        return nil
    }

    private static func normalize(_ key: String) -> String {
        key.lowercased().filter(\.isLetter)
    }

    private func cache(_ config: RemoteAppConfig) {
        UserDefaults.standard.set(config.realSound, forKey: "remote.realSound")
        UserDefaults.standard.set(config.interstitialEvery, forKey: "remote.interstitialEvery")
        UserDefaults.standard.set(config.adsEnabled, forKey: "remote.adsEnabled")
        UserDefaults.standard.set(config.appOpenEnabled, forKey: "remote.appOpenEnabled")
        UserDefaults.standard.set(config.interstitialEnabled, forKey: "remote.interstitialEnabled")
        UserDefaults.standard.set(config.rewardedEnabled, forKey: "remote.rewardedEnabled")
        UserDefaults.standard.set(config.appLink?.absoluteString, forKey: "remote.appLink")
        UserDefaults.standard.set(true, forKey: "remote.hasCache")
    }

    private func loadCachedRemoteConfig() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "remote.hasCache") else { return }
        remote = RemoteAppConfig(
            realSound: defaults.bool(forKey: "remote.realSound"),
            interstitialEvery: defaults.integer(forKey: "remote.interstitialEvery"),
            adsEnabled: defaults.bool(forKey: "remote.adsEnabled"),
            // Caches written before these switches existed have no value; keep them on.
            appOpenEnabled: defaults.object(forKey: "remote.appOpenEnabled") as? Bool ?? true,
            interstitialEnabled: defaults.object(forKey: "remote.interstitialEnabled") as? Bool ?? true,
            rewardedEnabled: defaults.object(forKey: "remote.rewardedEnabled") as? Bool ?? true,
            appLink: defaults.string(forKey: "remote.appLink").flatMap(URL.init(string:))
        )
    }

    // MARK: UIKit bridge

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private static var adUnitMode: String {
#if DEBUG
        "Google test"
#else
        "production"
#endif
    }

    private func log(_ message: String) {
#if DEBUG
        print("[MemeMimic Ads] \(message)")
#endif
    }

    private static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) code=\(error.code): \(error.localizedDescription) userInfo=\(error.userInfo)"
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return top(from: root)
    }

    private static func top(from controller: UIViewController?) -> UIViewController? {
        if let presented = controller?.presentedViewController { return top(from: presented) }
        if let navigation = controller as? UINavigationController { return top(from: navigation.visibleViewController) }
        if let tabs = controller as? UITabBarController { return top(from: tabs.selectedViewController) }
        return controller
    }
}

private extension RemoteAppConfig {
    var debugSummary: String {
        "adsEnabled=\(adsEnabled), appOpen=\(appOpenEnabled), interstitial=\(interstitialEnabled), rewarded=\(rewardedEnabled), interstitialEvery=\(interstitialEvery), realSound=\(realSound), appLink=\(appLink?.absoluteString ?? "nil")"
    }
}
