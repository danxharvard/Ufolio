import AppKit

/// Going back to the previous version when an update won't start.
///
/// When an update installs, the version it replaces is kept in Ufolio's support folder (it used
/// to be deleted). Two ways back:
/// - Straight after updating, the installer watches the new version: if it closes by itself
///   twice as it opens, the installer asks whether to go back.
/// - Ufolio counts launches that never got going (it closed within 20 seconds without quitting
///   properly). After two in a row it offers, before anything else, to go back.
/// Either way, the version that didn't work is skipped until a newer one comes out.
enum Rollback {
    static var folder: URL { AppPaths.support.appendingPathComponent("Previous Version", isDirectory: true) }
    static var previousApp: URL { folder.appendingPathComponent("Ufolio Browser.app", isDirectory: true) }
    static var previousVersion: String? {
        guard FileManager.default.fileExists(atPath: previousApp.path) else { return nil }
        return Bundle(url: previousApp)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    private static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static let failuresKey = "launch.failures"
    private static let versionKey = "launch.version"
    static let skipKey = "updates.skipVersion"

    /// First thing at launch, before any window: counts this launch as unfinished until it has
    /// run for 20 seconds (or quits properly), and offers to go back after two that never got going.
    static func checkAtLaunch() {
        let d = UserDefaults.standard
        if d.string(forKey: versionKey) != current {
            d.set(current, forKey: versionKey)
            d.set(0, forKey: failuresKey)
        }
        let failures = d.integer(forKey: failuresKey)
        d.set(failures + 1, forKey: failuresKey)
        d.synchronize()   // written now: a crash a moment later must still count
        if failures >= 2, let previous = previousVersion, previous != current, Updater.shared.canInstallInPlace {
            offer(previous)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { launchSucceeded() }
    }

    /// This launch got going (or Ufolio is quitting normally).
    static func launchSucceeded() {
        UserDefaults.standard.set(0, forKey: failuresKey)
    }

    /// A second copy of Ufolio that only brings the first forward doesn't count as a failed launch.
    static func launchWasDuplicate() {
        let d = UserDefaults.standard
        d.set(max(0, d.integer(forKey: failuresKey) - 1), forKey: failuresKey)
        d.synchronize()
    }

    private static func offer(_ previous: String) {
        // Asked before any window exists: bring Ufolio forward so the question isn't hidden
        // behind other apps.
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Ufolio \(current) didn’t start properly"
        alert.informativeText = "It closed by itself twice in a row as it opened. You can go back to Ufolio \(previous), which worked. Ufolio will skip \(current) until a newer version comes out."
        alert.addButton(withTitle: "Go Back to \(previous)")
        alert.addButton(withTitle: "Try Again")
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(0, forKey: failuresKey)
            return
        }
        UserDefaults.standard.set(current, forKey: skipKey)
        UserDefaults.standard.set(0, forKey: failuresKey)
        UserDefaults.standard.synchronize()
        if restoreAfterQuitting() { exit(0) }
    }

    /// Starts a small script that waits for Ufolio to quit, puts the previous version back and
    /// opens it.
    private static func restoreAfterQuitting() -> Bool {
        let target = Bundle.main.bundleURL.path
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("ufolio-rollback-\(UUID().uuidString).sh")
        let source = """
        #!/bin/bash
        PID="$1"; TARGET="$2"; PREV="$3"
        exec >> "$HOME/Library/Logs/Ufolio Browser Update.log" 2>&1
        echo "$(date): going back to the previous version"
        for i in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        BROKEN="$TARGET.broken-$(date +%s)"
        if mv "$TARGET" "$BROKEN" && mv "$PREV" "$TARGET"; then
          rm -rf "$BROKEN"
        else
          [ -d "$BROKEN" ] && [ ! -d "$TARGET" ] && mv "$BROKEN" "$TARGET"
        fi
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        open "$TARGET"
        rm -f "$0"
        """
        do {
            try source.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target, previousApp.path]
            try process.run()
            return true
        } catch {
            NSLog("Ufolio: couldn't start going back: \(error)")
            return false
        }
    }
}
