import Foundation
import WebKit
import CryptoKit

/// Blocks YouTube's video ads. They come from YouTube's own servers, so blocking ad servers
/// can't catch them: a small script on youtube.com mutes and skips an ad the moment it starts,
/// and hides ad boxes and sponsored results. It runs in Ufolio's own script world: YouTube's
/// page can't see it or change it.
///
/// YouTube changes how ads arrive every few weeks, so the script updates itself without waiting
/// for an Ufolio release: a newer copy is fetched from Ufolio's GitHub repository once a day. It's
/// only used if it carries Ufolio's own signature (the same key that signs updates) and is newer
/// than the copy already in use. It runs on YouTube's pages only, nowhere else.
final class YouTubeAds {
    static let shared = YouTubeAds()

    private static let remote = URL(string: "https://raw.githubusercontent.com/danxharvard/Ufolio/main/rules/youtube-ads.js")!
    private static let remoteSignature = URL(string: "https://raw.githubusercontent.com/danxharvard/Ufolio/main/rules/youtube-ads.js.sig")!
    /// Signed together with the script, so a script signature can never pass as an update's (or the reverse).
    static let signingPrefix = Data("ufolio-youtube-ads\n".utf8)

    private static var savedFile: URL { AppPaths.support.appendingPathComponent("youtube-ads.js") }
    private static var savedSignature: URL { AppPaths.support.appendingPathComponent("youtube-ads.js.sig") }

    private static let hosts: Set<String> = ["youtube.com", "m.youtube.com", "music.youtube.com"]

    /// True for YouTube's own pages (not other sites with a YouTube video on them).
    static func applies(to host: String?) -> Bool {
        guard let host else { return false }
        return hosts.contains(host.lowercased().strippingWWW)
    }

    private(set) var script: WKUserScript?
    private var version = 0
    private var timer: Timer?

    private init() {
        let bundled = Bundle.main.url(forResource: "youtube-ads", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        var best = bundled.map { (source: $0, version: Self.version(of: $0)) }
        // A downloaded copy is checked again every launch: a file changed on disk isn't trusted.
        if let data = try? Data(contentsOf: Self.savedFile),
           let sig = try? String(contentsOf: Self.savedSignature, encoding: .utf8),
           Self.isSigned(data, signature: sig), let source = String(data: data, encoding: .utf8),
           Self.version(of: source) > (best?.version ?? 0) {
            best = (source, Self.version(of: source))
        }
        if let best { use(best.source, version: best.version) }
    }

    private func use(_ source: String, version: Int) {
        self.version = version
        script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient)
    }

    /// "// Ufolio: YouTube ad blocking. Version: 2026112701" → 2026112701.
    static func version(of source: String) -> Int {
        guard let line = source.split(separator: "\n", maxSplits: 3).first(where: { $0.contains("Version:") }),
              let number = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) else { return 0 }
        return Int(number) ?? 0
    }

    static func isSigned(_ data: Data, signature: String) -> Bool {
        guard let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return Updater.isSigned(signingPrefix + data, signature: sig)
    }

    // MARK: Updating

    /// Checks a couple of minutes after launch, then once a day while Ufolio stays open.
    /// (Static, so launching doesn't load the script: the first YouTube page does.)
    static func startUpdates() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            shared.checkForUpdate()
            shared.timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in
                shared.checkForUpdate()
            }
            shared.timer?.tolerance = 3_600
        }
    }

    private var checking = false

    func checkForUpdate() {
        guard !checking, Prefs.bool(Prefs.adBlockEnabled) else { return }
        checking = true
        Task { @MainActor in
            defer { checking = false }
            var request = URLRequest(url: Self.remote, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("Ufolio", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 200_000,
                  let source = String(data: data, encoding: .utf8) else { return }
            let newVersion = Self.version(of: source)
            guard newVersion > version else { return }   // nothing newer (an older copy is never taken back)
            var sigRequest = URLRequest(url: Self.remoteSignature, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            sigRequest.setValue("Ufolio", forHTTPHeaderField: "User-Agent")
            guard let (sigData, sigResponse) = try? await URLSession.shared.data(for: sigRequest),
                  (sigResponse as? HTTPURLResponse)?.statusCode == 200,
                  let signature = String(data: sigData, encoding: .utf8),
                  Self.isSigned(data, signature: signature) else {
                NSLog("Ufolio: a YouTube ad-blocking update wasn't signed by Ufolio, so it was ignored")
                return
            }
            try? data.write(to: Self.savedFile, options: .atomic)
            try? sigData.write(to: Self.savedSignature, options: .atomic)
            use(source, version: newVersion)
            ContentBlocker.shared.reconfigure(where: Self.applies(to:))   // open YouTube tabs get it on their next page
        }
    }
}
