import WebKit

/// Small WebKit switches that Safari uses but that aren't in the public API. Every call
/// checks the method exists first, so if a future macOS removes one, the feature simply
/// stops working instead of crashing.
enum WebKitExtras {
    private static func bool(_ webView: WKWebView, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard webView.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(webView.method(for: selector), to: Getter.self)(webView, selector)
    }

    private static func call(_ webView: WKWebView, _ name: String) {
        let selector = NSSelectorFromString(name)
        guard webView.responds(to: selector) else { return }
        typealias Action = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(webView.method(for: selector), to: Action.self)(webView, selector)
    }

    static func isPlayingAudio(_ webView: WKWebView) -> Bool { bool(webView, "_isPlayingAudio") }

    /// Mutes or unmutes everything the page plays.
    static func setMuted(_ muted: Bool, _ webView: WKWebView) {
        let selector = NSSelectorFromString("_setPageMuted:")
        guard webView.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(webView.method(for: selector), to: Setter.self)(webView, selector, muted ? 1 : 0)  // 1 = audio muted
    }

    static func canPictureInPicture(_ webView: WKWebView) -> Bool { bool(webView, "_canTogglePictureInPicture") }
    static func togglePictureInPicture(_ webView: WKWebView) { call(webView, "_togglePictureInPicture") }
    static func isPictureInPictureActive(_ webView: WKWebView) -> Bool { bool(webView, "_isPictureInPictureActive") }
    /// Ends the page straight away (what Safari does when a tab closes): its memory and web
    /// process are given back even if something still holds on to the web view.
    static func close(_ webView: WKWebView) { call(webView, "_close") }
    /// Lets go of the earlier pages this tab keeps whole in memory for an instant Back (Back
    /// still works: it loads them again).
    static func clearBackForwardCache(_ webView: WKWebView) { call(webView, "_clearBackForwardCache") }

    /// The page's web process (0 if it hasn't one yet).
    static func processID(_ webView: WKWebView) -> pid_t {
        let selector = NSSelectorFromString("_webProcessIdentifier")
        guard webView.responds(to: selector) else { return 0 }
        typealias Getter = @convention(c) (AnyObject, Selector) -> pid_t
        return unsafeBitCast(webView.method(for: selector), to: Getter.self)(webView, selector)
    }

    /// Light sleep: the page's process gives back the memory it can rebuild (decoded pictures,
    /// caches, JavaScript garbage), as WebKit does before macOS suspends it, then carries on at
    /// once. The page stays exactly as it was, nothing reloads. Measured: about a quarter of a
    /// background tab's memory. Both halves are checked first; without them it does nothing.
    static func releaseMemory(_ webView: WKWebView) {
        let suspend = NSSelectorFromString("_processWillSuspendForTesting:")
        let resume = NSSelectorFromString("_processDidResumeForTesting")
        guard webView.responds(to: suspend), webView.responds(to: resume) else { return }
        typealias WithBlock = @convention(c) (AnyObject, Selector, Any) -> Void
        // Held strongly until it's done: other tabs can share this page's process, so if the tab
        // closed in between, skipping the resume would leave them paused.
        let done: @convention(block) () -> Void = { call(webView, "_processDidResumeForTesting") }
        unsafeBitCast(webView.method(for: suspend), to: WithBlock.self)(webView, suspend, done)
    }

    /// The auto-play rules for a page about to load, as Safari sets them (WebKit's per-page
    /// website policies). With only the web view's own "needs a click for sound" switch, a video
    /// you'd opened yourself (a YouTube link, say) sat waiting for a second click in Ufolio, where
    /// Safari and other browsers start it straight away. Policy: 1 allow, 2 allow without sound,
    /// 3 deny. Quirks: a page you opened yourself inherits your click, so its video may play.
    static func setAutoplay(policy: Int, quirks: Int, _ preferences: WKWebpagePreferences) {
        typealias SetInt = @convention(c) (AnyObject, Selector, Int) -> Void
        let setPolicy = NSSelectorFromString("_setAutoplayPolicy:")
        let setQuirks = NSSelectorFromString("_setAllowedAutoplayQuirks:")
        guard preferences.responds(to: setPolicy) else { return }
        unsafeBitCast(preferences.method(for: setPolicy), to: SetInt.self)(preferences, setPolicy, policy)
        if preferences.responds(to: setQuirks) {
            unsafeBitCast(preferences.method(for: setQuirks), to: SetInt.self)(preferences, setQuirks, quirks)
        }
    }

    /// Freezes a page completely (its scripts, timers and drawing), or lets it carry on.
    static func setPageSuspended(_ suspended: Bool, _ webView: WKWebView) {
        let selector = NSSelectorFromString(suspended ? "_suspendPage:" : "_resumePage:")
        guard webView.responds(to: selector) else {
            webView.setAllMediaPlaybackSuspended(suspended)   // at least the sound and video
            return
        }
        typealias Call = @convention(c) (AnyObject, Selector, @escaping @convention(block) (Bool) -> Void) -> Void
        unsafeBitCast(webView.method(for: selector), to: Call.self)(webView, selector) { _ in }
    }
}

/// The key WebKit uses to protect encryption keys that websites store (WebCrypto). Left to
/// itself, WebKit fetches it from your keychain on the main thread, and because Hush isn't
/// signed with an Apple Developer ID, macOS asks permission again after every update, freezing
/// the window until you answer. Hush keeps its own key instead: a private file only you can read.
/// Private windows get a throwaway key that's never saved.
enum WebCryptoKey {
    private static let sessionKey = random()

    private static let saved: Data = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hush Browser", isDirectory: true)
        let file = folder.appendingPathComponent("WebCrypto.key")
        if let data = try? Data(contentsOf: file), data.count == 16 { return data }
        let key = random()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: key, attributes: [.posixPermissions: 0o600])
        return key
    }()

    static func key(privately: Bool) -> Data { privately ? sessionKey : saved }

    private static func random() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
