import AppKit
import CryptoKit

/// Keeps Hush up to date from the project's GitHub releases.
///
/// 1. Asks GitHub for the latest release of `repo`.
/// 2. If its tag (v0.3.0) is newer than this copy, downloads `HushBrowser-<version>.zip`.
/// 3. Checks the download's signature against Hush's own public key (only the holder of the
///    private key can sign an update), then its SHA-256, unzips it, and confirms it's a valid
///    Hush of the expected version.
/// 4. Swaps it in when you restart (or the next time you quit).
///
/// Apple's own update mechanisms need a paid Developer ID, so Hush swaps the app itself.
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "danxharvard/Ufolio"
    /// Every update must be signed with the matching private key (kept off GitHub's code, as a
    /// release secret). Even someone who could publish a release can't make Hush install it.
    static let updatePublicKey = "FKLwuCcTXRyR9HdUM16PNY49xl0lftz0B4qAoWgHkVY="

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(version: String, progress: Double)
        case ready(version: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var releaseNotes: String?
    @Published private(set) var releasePage: URL?

    private var latest: (version: String, asset: URL, digest: String?)?
    private var signatureURL: URL?
    private var pending: (version: String, newApp: URL, workDir: URL)?
    private var timer: Timer?

    var currentVersion: String {
        if let fake = Self.testEnv("UFOLIO_FAKE_VERSION") { return fake }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Testing switches, honoured only in test copies (another bundle ID), never in Ufolio itself.
    private static func testEnv(_ name: String) -> String? {
        guard Bundle.main.bundleIdentifier != "com.danxharvard.hushbrowser" else { return nil }
        return ProcessInfo.processInfo.environment[name]
    }

    /// Testing only (test copies): what github.com's pages say for each channel, then a full check
    /// through them as if the API were limiting this network.
    @MainActor
    func runTestsIfAsked() {
        guard Self.testEnv("UFOLIO_UPDATE_PROBE") != nil else { return }
        Task { @MainActor in
            for beta in [false, true] {
                let found = try? await Self.fromWebsite(beta: beta, experimental: false)
                FileHandle.standardError.write("probe \(beta ? "beta" : "regular"): \(found.map { "\($0.version) zip=\($0.asset?.absoluteString ?? "not ready") sig=\($0.signature != nil)" } ?? "nothing")\n".data(using: .utf8)!)
            }
            apiPausedUntil = Date().addingTimeInterval(3600)   // as if the API had said no
            await check(userInitiated: true)
            for _ in 0..<120 {
                if case .downloading = state { try? await Task.sleep(nanoseconds: 500_000_000); continue }
                if case .checking = state { try? await Task.sleep(nanoseconds: 500_000_000); continue }
                break
            }
            FileHandle.standardError.write("probe check: \(state)\n".data(using: .utf8)!)
        }
    }

    private init() {
        lastChecked = UserDefaults.standard.object(forKey: "updates.lastChecked") as? Date
    }

    func start() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.installOnQuit()
        }
        Task { @MainActor in self.runTestsIfAsked() }
        if Prefs.bool(Prefs.autoCheckUpdates) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                Task { @MainActor in await Updater.shared.check(userInitiated: false) }
            }
        }
        // Always running, checking the setting each time: turning automatic checks on later
        // used to do nothing until Ufolio restarted.
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { _ in
            guard Prefs.bool(Prefs.autoCheckUpdates) else { return }
            Task { @MainActor in await Updater.shared.check(userInitiated: false) }
        }
    }

    // MARK: Checking

    @MainActor
    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading, .ready: return
        default: break
        }
        state = .checking
        do {
            // HUSH_UPDATE_API lets a test point Hush at a local fake server; normal users never set it.
            let api = Self.apiBase
            // The beta channel (Settings, off by default) looks at every recent release, early
            // test builds included; otherwise only the latest finished release. Either way the
            // download has to pass exactly the same signature and fingerprint checks.
            // Experimental builds (the hidden developer area) are a channel above beta: they see
            // every release; the beta channel never offers an experimental build.
            let experimental = Self.experimentalChannel
            let beta = experimental || Prefs.bool(Prefs.betaUpdates)
            var found: Found?
            // GitHub's API allows 60 questions an hour per network; when it's said no, it isn't
            // asked again until it said it would answer (github.com itself answers meanwhile).
            if Date() >= apiPausedUntil || api != "https://api.github.com" {
                var request = URLRequest(url: URL(string: beta ? "\(api)/repos/\(Self.repo)/releases?per_page=15"
                                                             : "\(api)/repos/\(Self.repo)/releases/latest")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                if status == 403 || status == 429 {
                    let reset = http?.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init)
                    apiPausedUntil = reset.map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(3600)
                } else {
                    lastChecked = Date()
                    UserDefaults.standard.set(lastChecked, forKey: "updates.lastChecked")
                    if status == 404 { state = .upToDate; return } // nothing published yet
                    guard status == 200 else { throw UpdateError("GitHub didn’t answer properly (error \(status)).") }
                    found = try Self.fromAPI(data, beta: beta, experimental: experimental)
                    if found == nil { state = .upToDate; return }
                }
            }
            if found == nil {
                // Limited by the API: the same answer from github.com's own pages.
                guard api == "https://api.github.com" else { throw UpdateError("GitHub didn’t answer properly.") }
                guard let fallback = try await Self.fromWebsite(beta: beta, experimental: experimental) else {
                    throw UpdateError("GitHub is limiting update checks from your network right now. Ufolio will try again later.")
                }
                lastChecked = Date()
                UserDefaults.standard.set(lastChecked, forKey: "updates.lastChecked")
                found = fallback
            }
            guard let found else { state = .upToDate; return }
            let version = found.version
            guard Self.isNewer(version, than: currentVersion) else { state = .upToDate; return }
            // A version that didn't start and was rolled back is skipped until a newer one is out.
            if UserDefaults.standard.string(forKey: Rollback.skipKey) == version {
                state = .upToDate
                return
            }
            guard let link = found.asset, Self.isTrustedDownload(link) else {
                throw UpdateError("Version \(version) is out, but its download isn’t ready yet.")
            }
            guard let sigLink = found.signature, Self.isTrustedDownload(sigLink) else {
                throw UpdateError("Version \(version) is out, but it isn’t signed, so Ufolio won’t install it.")
            }
            latest = (version, link, found.digest)
            signatureURL = sigLink
            releaseNotes = found.notes
            releasePage = found.page
            state = .available(version: version)

            if Prefs.bool(Prefs.autoInstallUpdates) || userInitiated {
                await download()
            }
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    // MARK: Where the latest release is

    /// The newest release worth installing, however it was found.
    private struct Found {
        let version: String
        let asset: URL?
        let signature: URL?
        let digest: String?
        let notes: String?
        let page: URL?
    }

    /// When GitHub's API said it would answer again, after limiting this network.
    private var apiPausedUntil = Date.distantPast

    /// From the API's answer: the newest release, with its files' addresses and fingerprint.
    private static func fromAPI(_ data: Data, beta: Bool, experimental: Bool) throws -> Found? {
        let decoded = try JSONSerialization.jsonObject(with: data)
        func versionOf(_ release: [String: Any]) -> String? {
            (release["tag_name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        }
        let candidates: [[String: Any]] = beta
            ? ((decoded as? [[String: Any]]) ?? []).filter { ($0["draft"] as? Bool) != true }
                .filter { experimental || !isExperimental(versionOf($0) ?? "") }
            : (decoded as? [String: Any]).map { [$0] } ?? []
        guard let json = candidates.max(by: { a, b in
                  guard let va = versionOf(a), let vb = versionOf(b) else { return versionOf(a) == nil }
                  return isNewer(vb, than: va)
              }),
              let version = versionOf(json) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        func link(_ name: String) -> (URL?, String?) {
            let asset = assets.first { ($0["name"] as? String) == name }
            return ((asset?["browser_download_url"] as? String).flatMap(URL.init(string:)), asset?["digest"] as? String)
        }
        let (zip, digest) = link("HushBrowser-\(version).zip")
        let (sig, _) = link("HushBrowser-\(version).zip.sig")
        return Found(version: version, asset: zip, signature: sig, digest: digest,
                     notes: (json["body"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                     page: (json["html_url"] as? String).flatMap(URL.init(string:)))
    }

    /// From github.com's own pages, which aren't limited like the API: the latest release from
    /// where /releases/latest points (or, for betas, the newest tag in the releases feed). The
    /// files' addresses follow GitHub's fixed pattern; the download still has to pass the same
    /// signature check. (No fingerprint here: the signature is what proves it genuine.)
    private static func fromWebsite(beta: Bool, experimental: Bool) async throws -> Found? {
        let site = "https://github.com/\(repo)"
        var version: String?
        if beta {
            var request = URLRequest(url: URL(string: "\(site)/releases.atom")!, timeoutInterval: 20)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000,
                  let feed = String(data: data, encoding: .utf8) else { return nil }
            let pattern = try NSRegularExpression(pattern: #"Repository/\d+/v([0-9A-Za-z.\-]+)</id>"#)
            let tags = pattern.matches(in: feed, range: NSRange(feed.startIndex..., in: feed)).compactMap {
                Range($0.range(at: 1), in: feed).map { String(feed[$0]) }
            }
            version = tags.filter { isVersion($0) && (experimental || !isExperimental($0)) }.max { isNewer($1, than: $0) }
        } else {
            var request = URLRequest(url: URL(string: "\(site)/releases/latest")!, timeoutInterval: 20)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (_, response) = try? await URLSession.shared.data(for: request, delegate: NoRedirects()),
                  let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let target = URL(string: location, relativeTo: URL(string: site)),
                  target.host?.lowercased() == "github.com",
                  target.path.hasPrefix("/\(repo)/releases/tag/v") else { return nil }
            version = String(target.lastPathComponent.dropFirst())
        }
        // Only a plain version number goes into the download address.
        guard let version, isVersion(version) else { return nil }
        let asset = URL(string: "\(site)/releases/download/v\(version)/HushBrowser-\(version).zip")
        let signature = URL(string: "\(site)/releases/download/v\(version)/HushBrowser-\(version).zip.sig")
        // Its files might still be uploading: only announced once the signature is there.
        var head = URLRequest(url: signature!, timeoutInterval: 20)
        head.httpMethod = "HEAD"
        let ready = ((try? await URLSession.shared.data(for: head))?.1 as? HTTPURLResponse)?.statusCode == 200
        return Found(version: version, asset: ready ? asset : nil, signature: ready ? signature : nil, digest: nil,
                     notes: nil, page: URL(string: "\(site)/releases/tag/v\(version)"))
    }

    /// An experimental build ("0.53.0-exp.1"): only offered on the experimental channel.
    static func isExperimental(_ version: String) -> Bool { version.contains("-exp") }

    /// Experimental builds: switched on in the developer area, after agreeing to the terms.
    static var experimentalChannel: Bool {
        Prefs.bool(Prefs.developerUnlocked) && Prefs.bool(Prefs.experimentalUpdates)
    }

    /// "0.51.4" or "0.52.0-beta.4", and nothing else.
    private static func isVersion(_ text: String) -> Bool {
        text.count <= 32 && text.range(of: #"\A[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?\z"#, options: .regularExpression) != nil
    }

    /// Stops at the first answer, so /releases/latest says where it points instead of going there.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    // MARK: Downloading

    @MainActor
    func download() async {
        guard let latest else { return }
        guard canInstallInPlace else {
            state = .failed("Move Ufolio into your Applications folder so it can update itself.")
            return
        }
        state = .downloading(version: latest.version, progress: 0)
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hush-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let zip = workDir.appendingPathComponent("update.zip")

            let version = latest.version
            try await FileDownload.fetch(latest.asset, to: zip) { progress in
                Task { @MainActor in
                    // Whole-percent steps only: every network tick redrew Settings for nothing.
                    if case .downloading(_, let shown) = Updater.shared.state,
                       Int(progress * 100) != Int(shown * 100) {
                        Updater.shared.state = .downloading(version: version, progress: progress)
                    }
                }
            }
            // The signature: made with Hush's private key, or it isn't installed. Ever.
            guard let sigURL = signatureURL else { throw UpdateError("This update isn’t signed.") }
            var sigRequest = URLRequest(url: sigURL)
            sigRequest.timeoutInterval = 20
            let (sigData, sigResponse) = try await URLSession.shared.data(for: sigRequest)
            guard (sigResponse as? HTTPURLResponse)?.statusCode == 200, sigData.count < 1024,
                  let sigText = String(data: sigData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let signature = Data(base64Encoded: sigText) else { throw UpdateError("This update’s signature couldn’t be read.") }
            let genuine = try await Task.detached(priority: .utility) {
                let data = try Data(contentsOf: zip, options: .mappedIfSafe)
                return Updater.isSigned(data, signature: signature)
            }.value
            guard genuine else { throw UpdateError("This update isn’t signed by Ufolio, so it wasn’t installed.") }

            // GitHub publishes a SHA-256 for every release file; refuse anything that doesn't match.
            // (Hashed off the main thread, so the window never stalls.)
            if let digest = latest.digest, digest.hasPrefix("sha256:") {
                let actual = try await Task.detached(priority: .utility) {
                    let data = try Data(contentsOf: zip, options: .mappedIfSafe)
                    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                }.value
                guard actual == digest.dropFirst(7).lowercased() else { throw UpdateError("The download was damaged. Try again.") }
            }

            let unpacked = workDir.appendingPathComponent("unpacked", isDirectory: true)
            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            guard let appName = try FileManager.default.contentsOfDirectory(atPath: unpacked.path)
                    .first(where: { $0.hasSuffix(".app") }) else { throw UpdateError("The download didn’t contain Ufolio.") }
            let newApp = unpacked.appendingPathComponent(appName)

            let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
                throw UpdateError("The download isn’t Ufolio Browser.")
            }
            guard info?["CFBundleShortVersionString"] as? String == latest.version else {
                throw UpdateError("The download is the wrong version.")
            }
            // Never install a version this Mac can't open.
            if let minimum = info?["LSMinimumSystemVersion"] as? String {
                let parts = minimum.split(separator: ".").compactMap { Int($0) }
                let needed = OperatingSystemVersion(majorVersion: parts.first ?? 0,
                                                    minorVersion: parts.count > 1 ? parts[1] : 0,
                                                    patchVersion: parts.count > 2 ? parts[2] : 0)
                guard ProcessInfo.processInfo.isOperatingSystemAtLeast(needed) else {
                    throw UpdateError("Ufolio \(latest.version) needs macOS \(minimum) or later. Update macOS in System Settings › General › Software Update to get it.")
                }
            }
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            try? FileManager.default.removeItem(at: zip)

            pending = (latest.version, newApp, workDir)
            state = .ready(version: latest.version)
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Installing

    /// Installs the downloaded version and reopens Hush.
    func restartToUpdate() {
        guard pending != nil else { return }
        launchSwap(relaunch: true)
        NSApp.terminate(nil)
        // Still here: quitting was cancelled, so the installer stands down; offer it again.
        if let latest { state = .available(version: latest.version) }
    }

    private func installOnQuit() {
        guard pending != nil else { return }
        launchSwap(relaunch: false)
    }

    private var currentBundle: URL { Bundle.main.bundleURL }

    /// GitHub, or a local test server (HUSH_UPDATE_API, accepted only on this Mac).
    private static var apiBase: String {
        if let test = ProcessInfo.processInfo.environment["HUSH_UPDATE_API"],
           let host = URL(string: test)?.host, host == "127.0.0.1" || host == "localhost" {
            return test
        }
        return "https://api.github.com"
    }

    /// Release files must come from GitHub over HTTPS (or the local test server).
    private static func isTrustedDownload(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if apiBase != "https://api.github.com" { return host == "127.0.0.1" || host == "localhost" }
        return url.scheme == "https" && (host == "github.com" || host.hasSuffix(".githubusercontent.com"))
    }

    var canInstallInPlace: Bool {
        let bundle = currentBundle
        guard bundle.pathExtension == "app", !bundle.path.hasPrefix("/Volumes/") else { return false }
        return FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    /// A tiny script waits for Hush to quit, swaps the app (keeping a backup until the
    /// new one is in place) and optionally reopens it.
    private func launchSwap(relaunch: Bool) {
        guard let pending else { return }
        self.pending = nil
        // The installer's log only ever grew: keep its last couple of hundred lines.
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Ufolio Browser Update.log")
        if let size = (try? log.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 200_000,
           let text = try? String(contentsOf: log, encoding: .utf8) {
            try? text.split(separator: "\n", omittingEmptySubsequences: false).suffix(200).joined(separator: "\n")
                .write(to: log, atomically: true, encoding: .utf8)
        }
        let target = currentBundle.path
        let backup = target + ".old-\(Int(Date().timeIntervalSince1970))"
        let script = pending.workDir.appendingPathComponent("install.sh")
        let source = """
        #!/bin/bash
        PID="$1"; NEW="$2"; TARGET="$3"; BACKUP="$4"; RELAUNCH="$5"; WORK="$6"
        PREVDIR="$7"; BUNDLEID="$8"; NEWVERSION="$9"; OLDVERSION="${10}"
        PREV="$PREVDIR/Ufolio Browser.app"
        exec >> "$HOME/Library/Logs/Ufolio Browser Update.log" 2>&1
        echo "$(date): installing $NEW over $TARGET"
        for i in $(seq 1 300); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        # Never swap the app while it's still running (quitting was cancelled): try another time.
        if kill -0 "$PID" 2>/dev/null; then echo "Ufolio is still open; not installing now"; rm -rf "$WORK"; exit 0; fi
        if mv "$TARGET" "$BACKUP" && mv "$NEW" "$TARGET"; then
          # The version it replaces is kept, so you can go back if the new one won't start.
          mkdir -p "$PREVDIR" && rm -rf "$PREV" && mv "$BACKUP" "$PREV" || rm -rf "$BACKUP"
        else
          [ -d "$BACKUP" ] && [ ! -d "$TARGET" ] && mv "$BACKUP" "$TARGET"
        fi
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        rm -rf "$WORK"
        [ "$RELAUNCH" = "1" ] || exit 0
        # Reopened straight away: watch that the new version actually starts.
        started() {
          sleep 3
          for i in $(seq 1 17); do pgrep -f "$TARGET/Contents/MacOS/" >/dev/null || return 1; sleep 1; done
          return 0
        }
        open "$TARGET"
        started && exit 0
        echo "Ufolio $NEWVERSION closed as it opened; trying once more"
        open "$TARGET"
        started && exit 0
        [ -d "$PREV" ] || exit 0
        echo "Ufolio $NEWVERSION closed again"
        ANSWER=$(osascript -e 'display dialog "Ufolio '"$NEWVERSION"' closed by itself twice as it opened. Go back to Ufolio '"$OLDVERSION"', which worked? Ufolio will skip '"$NEWVERSION"' until a newer version comes out." with title "Ufolio Browser" buttons {"Try Again", "Go Back"} default button "Go Back" with icon caution' -e 'button returned of result' 2>/dev/null)
        if [ "$ANSWER" = "Go Back" ]; then
          BROKEN="$TARGET.broken-$(date +%s)"
          if mv "$TARGET" "$BROKEN" && mv "$PREV" "$TARGET"; then rm -rf "$BROKEN"; else [ -d "$BROKEN" ] && [ ! -d "$TARGET" ] && mv "$BROKEN" "$TARGET"; fi
          xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
          defaults write "$BUNDLEID" updates.skipVersion "$NEWVERSION"
          defaults write "$BUNDLEID" launch.failures -int 0
          echo "went back to $OLDVERSION"
        fi
        open "$TARGET"
        """
        do {
            try source.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                                 pending.newApp.path, target, backup, relaunch ? "1" : "0", pending.workDir.path,
                                 Rollback.folder.path, Bundle.main.bundleIdentifier ?? "com.danxharvard.hushbrowser",
                                 pending.version, currentVersion]
            try process.run()
        } catch {
            NSLog("Ufolio: couldn't start the update: \(error)")
        }
    }

    // MARK: Helpers

    /// True when `signature` is Hush's own signature for `data`.
    static func isSigned(_ data: Data, signature: Data) -> Bool {
        guard let raw = Data(base64Encoded: updatePublicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: data)
    }

    /// "0.10.0" > "0.9.2". A test build ("0.50.0-beta.2") comes after 0.49.x and before
    /// 0.50.0 itself; between test builds, beta.10 > beta.2.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> (numbers: [Int], label: [Substring]?) {
            let halves = v.split(separator: "-", maxSplits: 1)
            let numbers = (halves.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
            return (numbers, halves.count > 1 ? halves[1].split(separator: ".") : nil)
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.numbers.count, y.numbers.count) {
            let l = i < x.numbers.count ? x.numbers[i] : 0, r = i < y.numbers.count ? y.numbers[i] : 0
            if l != r { return l > r }
        }
        switch (x.label, y.label) {
        case (nil, nil): return false
        case (nil, _): return true      // the finished version beats its test builds
        case (_, nil): return false
        case let (l?, r?):
            for i in 0..<max(l.count, r.count) {
                guard i < l.count else { return false }
                guard i < r.count else { return true }
                if let ln = Int(l[i]), let rn = Int(r[i]) {
                    if ln != rn { return ln > rn }
                } else if l[i] != r[i] {
                    return l[i] > r[i]
                }
            }
            return false
        }
    }

    /// Runs a system tool without blocking the main thread.
    private static func run(_ tool: String, _ args: [String]) async throws {
        guard try await ProcessRunner.run(tool, args).succeeded else {
            throw UpdateError("The downloaded app couldn’t be verified, so it wasn’t installed.")
        }
    }
}

/// Downloads a file straight to disk, reporting progress as it goes.
private final class FileDownload: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?

    private init(destination: URL, onProgress: @escaping (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    static func fetch(_ url: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let delegate = FileDownload(destination: destination, onProgress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            failure = UpdateError("The download failed.")
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? failure {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
