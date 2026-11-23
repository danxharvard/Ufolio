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
