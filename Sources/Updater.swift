import AppKit
import CryptoKit

/// Keeps Hush up to date from the project's GitHub releases.
///
/// 1. Asks GitHub for the latest release of `repo`.
/// 2. If its tag (v0.3.0) is newer than this copy, downloads `HushBrowser-<version>.zip`.
/// 3. Checks the download against GitHub's SHA-256 digest, unzips it, and confirms it's
///    a valid, signed Hush of the expected version.
/// 4. Swaps it in when you restart (or the next time you quit).
///
/// Apple's own update mechanisms need a paid Developer ID, so Hush swaps the app itself.
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "danxharvard/hushbrowser"

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
    private var pending: (version: String, newApp: URL, workDir: URL)?
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private init() {
        lastChecked = UserDefaults.standard.object(forKey: "updates.lastChecked") as? Date
    }

    func start() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.installOnQuit()
        }
        guard Prefs.bool(Prefs.autoCheckUpdates) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            Task { @MainActor in await Updater.shared.check(userInitiated: false) }
        }
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
            let api = ProcessInfo.processInfo.environment["HUSH_UPDATE_API"] ?? "https://api.github.com"
            var request = URLRequest(url: URL(string: "\(api)/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: "updates.lastChecked")

            if status == 404 { state = .upToDate; return } // nothing published yet
            guard status == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                throw UpdateError("GitHub didn’t answer properly (error \(status)).")
            }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard Self.isNewer(version, than: currentVersion) else { state = .upToDate; return }

            let assets = json["assets"] as? [[String: Any]] ?? []
            guard let asset = assets.first(where: { ($0["name"] as? String) == "HushBrowser-\(version).zip" }),
                  let link = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
                throw UpdateError("Version \(version) is out, but its download isn’t ready yet.")
            }
            latest = (version, link, asset["digest"] as? String)
            releaseNotes = (json["body"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            releasePage = (json["html_url"] as? String).flatMap(URL.init(string:))
            state = .available(version: version)

            if Prefs.bool(Prefs.autoInstallUpdates) || userInitiated {
                await download()
            }
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    // MARK: Downloading

    @MainActor
    func download() async {
        guard let latest else { return }
        guard canInstallInPlace else {
            state = .failed("Move Hush into your Applications folder so it can update itself.")
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
                    if case .downloading = Updater.shared.state {
                        Updater.shared.state = .downloading(version: version, progress: progress)
                    }
                }
            }
            let data = try Data(contentsOf: zip)

            // GitHub publishes a SHA-256 for every release file; refuse anything that doesn't match.
            if let digest = latest.digest, digest.hasPrefix("sha256:") {
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard actual == digest.dropFirst(7) else { throw UpdateError("The download was damaged. Try again.") }
            }

            let unpacked = workDir.appendingPathComponent("unpacked", isDirectory: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            guard let appName = try FileManager.default.contentsOfDirectory(atPath: unpacked.path)
                    .first(where: { $0.hasSuffix(".app") }) else { throw UpdateError("The download didn’t contain Hush.") }
            let newApp = unpacked.appendingPathComponent(appName)

            let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
                throw UpdateError("The download isn’t Hush Browser.")
            }
            guard info?["CFBundleShortVersionString"] as? String == latest.version else {
                throw UpdateError("The download is the wrong version.")
            }
            try run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])
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
    }

    private func installOnQuit() {
        guard pending != nil else { return }
        launchSwap(relaunch: false)
    }

    private var currentBundle: URL { Bundle.main.bundleURL }

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
        let target = currentBundle.path
        let backup = target + ".old-\(Int(Date().timeIntervalSince1970))"
        let script = pending.workDir.appendingPathComponent("install.sh")
        let source = """
        #!/bin/bash
        PID="$1"; NEW="$2"; TARGET="$3"; BACKUP="$4"; RELAUNCH="$5"; WORK="$6"
        exec >> "$HOME/Library/Logs/Hush Browser Update.log" 2>&1
        echo "$(date): installing $NEW over $TARGET"
        for i in $(seq 1 300); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        if mv "$TARGET" "$BACKUP" && mv "$NEW" "$TARGET"; then
          rm -rf "$BACKUP"
        else
          [ -d "$BACKUP" ] && [ ! -d "$TARGET" ] && mv "$BACKUP" "$TARGET"
        fi
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        [ "$RELAUNCH" = "1" ] && open "$TARGET"
        rm -rf "$WORK"
        """
        do {
            try source.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                                 pending.newApp.path, target, backup, relaunch ? "1" : "0", pending.workDir.path]
            try process.run()
        } catch {
            NSLog("Hush: couldn't start the update: \(error)")
        }
    }

    // MARK: Helpers

    /// "0.10.0" > "0.9.2"; pre-release suffixes are ignored.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
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
