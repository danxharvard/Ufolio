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
    /// Ends the page straight away (what Safari does when a tab closes): its memory and web
    /// process are given back even if something still holds on to the web view.
    static func close(_ webView: WKWebView) { call(webView, "_close") }
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
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            // Atomic write also replaces a damaged/empty key file. createFile() silently fails
            // when that path already exists, which previously made every launch invent a new key.
            try key.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            NSLog("Ufolio: couldn't persist its WebCrypto key: \\(error)")
        }
        return key
    }()

    static func key(privately: Bool) -> Data { privately ? sessionKey : saved }

    private static func random() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Keep a cryptographically secure system-RNG fallback rather than silently returning
            // an all-zero or partially filled key if Security.framework reports an error.
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes)
    }
}
