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
