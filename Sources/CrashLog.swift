import AppKit
import Darwin

/// Crash and hang log: kept on your Mac only, never sent anywhere, and built so it costs nothing
/// while Ufolio runs.
/// - Crashes: everything is prepared once at launch (an open file, a buffer for the call stack,
///   the header text). The crash handler itself only writes those, with no memory allocated, then
///   lets macOS end Ufolio as usual.
/// - Hangs: a background timer pings the main thread about once a second (with slack, so macOS can
///   batch it with other wake-ups) and does nothing unless the main thread is more than two
///   seconds late. No logging otherwise.
/// After a crash, the next launch says so and offers the details.
enum CrashLog {
    static var folder: URL {
        if let test = ProcessInfo.processInfo.environment["UFOLIO_LOG_DIR"] { return URL(fileURLWithPath: test, isDirectory: true) }
        // Test copies (another bundle ID) keep their own, like their own data folder.
        let id = Bundle.main.bundleIdentifier ?? ""
        let name = id == "com.danxharvard.hushbrowser" || id.isEmpty ? "Ufolio Browser" : "Ufolio Browser (\(id))"
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(name)", isDirectory: true)
    }
    static var logFile: URL { folder.appendingPathComponent("Crashes and hangs.log") }
    private static var pendingFile: URL { folder.appendingPathComponent(".last-crash") }

    private static var installed = false
    private static var unexpected: String?

    /// At launch: collects the record of a crash last time (if any), then gets ready for the next.
    static func install() {
        guard !installed, ProcessInfo.processInfo.environment["UFOLIO_NO_WATCHDOG"] == nil else { return }
        installed = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: pendingFile), !data.isEmpty, let text = String(data: data, encoding: .utf8) {
            unexpected = text
            append(text)
        }
        // A fresh, empty file, held open for the crash handler.
        let fd = open(pendingFile.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return }
        crashFD = fd
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        // Where Ufolio itself was loaded in memory, so the raw addresses below can be turned into
        // names afterwards (with `atos`), never at crash time.
        let base = UInt(bitPattern: _dyld_get_image_header(0))
        let header = Array("\n=== Ufolio \(version) quit unexpectedly ===\nloaded at 0x\(String(base, radix: 16))\n".utf8)
        crashHeader = UnsafeMutablePointer<UInt8>.allocate(capacity: header.count)
        crashHeader?.initialize(from: header, count: header.count)
        crashHeaderLength = header.count
        crashFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 128)
        _ = backtrace(crashFrames, 1)   // loads the unwinder now, never inside the handler
        for signal in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = crashHandler
            sigemptyset(&action.sa_mask)
            action.sa_flags = SA_RESETHAND
            sigaction(signal, &action, nil)
        }
        NSSetUncaughtExceptionHandler { exception in
            let text = "Exception: \(exception.name.rawValue): \(exception.reason ?? "")\n" + exception.callStackSymbols.prefix(40).joined(separator: "\n") + "\n"
            if crashFD >= 0 { _ = text.withCString { write(crashFD, $0, strlen($0)) } }
        }
        HangWatch.start()
        // Testing only: crash on purpose, or freeze the main thread for 3 seconds.
        let env = ProcessInfo.processInfo.environment
        if env["UFOLIO_TEST_CRASH"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { let nothing: Int? = Int(env["UFOLIO_TEST_CRASH"] ?? "") ; _ = nothing! }
        }
        if env["UFOLIO_TEST_HANG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { Thread.sleep(forTimeInterval: 3.2) }
        }
    }

    /// A clean quit: nothing to report next time.
    static func quittingNormally() {
        guard crashFD >= 0 else { return }
        ftruncate(crashFD, 0)
    }

    /// After a crash last time: "Ufolio quit unexpectedly", with the details a click away.
    static func offerReportIfNeeded() {
        guard unexpected != nil else { return }
        unexpected = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            DialogHost.show(HushDialog(
                art: .symbol("exclamationmark.triangle.fill"), theme: .caution, motion: .pulse,
                title: "Ufolio quit unexpectedly last time",
                message: "Sorry about that. A note of what happened was kept on your Mac (it’s never sent anywhere). Your tabs from last time are back if you chose to restore them.",
                choices: [.init(title: "View Details"), .init(title: "OK", role: .primary)],
                completion: { choice, _ in if choice == 0 { NSWorkspace.shared.open(logFile) } }), in: nil)
        }
    }

    /// Adds to the log (only when something actually happened), keeping it to a sensible size.
    static func append(_ text: String) {
        let stamp = Date().formatted(.iso8601)
        var all = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        all += "\n[\(stamp)] " + text
        if all.utf8.count > 400_000 { all = String(all.suffix(300_000)) }
        try? all.write(to: logFile, atomically: true, encoding: .utf8)
    }
}

// Prepared at launch for the crash handler, which may only use what's already there.
private var crashFD: Int32 = -1
private var crashHeader: UnsafeMutablePointer<UInt8>?
private var crashHeaderLength = 0
private var crashFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?

/// Runs when Ufolio crashes: writes the prepared header, the signal and the call stack, then lets
/// the crash carry on (SA_RESETHAND restored the default first).
private var crashHandling = false

/// Back to macOS's own handling, so returning from the handler finishes the crash. (macOS ignores
/// SA_RESETHAND for SIGILL and SIGTRAP, the signals Swift's own traps raise, which otherwise
/// sent Ufolio round the handler for ever instead of quitting.)
private func restoreDefault(_ signal: Int32) {
    var action = sigaction()
    action.__sigaction_u.__sa_handler = SIG_DFL
    sigemptyset(&action.sa_mask)
    sigaction(signal, &action, nil)
}

private let crashHandler: @convention(c) (Int32) -> Void = { signal in
    restoreDefault(signal)
    // Only ever once: anything going wrong in here just finishes the crash.
    guard !crashHandling else { raise(signal); return }
    crashHandling = true
    let fd = crashFD
    guard fd >= 0 else { raise(signal); return }
    if let header = crashHeader { _ = write(fd, header, crashHeaderLength) }
    // "signal 11\n", built on the stack without allocating.
    var buffer: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    withUnsafeMutableBytes(of: &buffer) { bytes in
        let prefix: [UInt8] = [115, 105, 103, 110, 97, 108, 32]   // "signal "
        var i = 0
        for b in prefix { bytes[i] = b; i += 1 }
        var n = Int(signal), digits = 0, tmp = n
        repeat { digits += 1; tmp /= 10 } while tmp > 0
        var j = i + digits - 1
        repeat { bytes[j] = UInt8(48 + n % 10); n /= 10; j -= 1 } while n > 0
        i += digits
        bytes[i] = 10
        _ = write(fd, bytes.baseAddress, i + 1)
    }
    // The call stack as raw addresses: names are looked up later, never here (doing it at crash
    // time could hang instead of finishing the crash).
    if let frames = crashFrames {
        let count = Int(backtrace(frames, 128))
        var line: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        for index in 0..<count {
            let address = UInt(bitPattern: frames[index])
            withUnsafeMutableBytes(of: &line) { bytes in
                bytes[0] = 48; bytes[1] = 120   // "0x"
                var i = 2
                for shift in stride(from: 60, through: 0, by: -4) {
                    let digit = Int((address >> UInt(shift)) & 0xF)
                    bytes[i] = UInt8(digit < 10 ? 48 + digit : 87 + digit)
                    i += 1
                }
                bytes[i] = 10
                _ = write(fd, bytes.baseAddress, i + 1)
            }
        }
    }
    raise(signal)
}

/// The hang watcher: a cheap ping of the main thread about once a second.
enum HangWatch {
    private static let queue = DispatchQueue(label: "ufolio.hangwatch", qos: .utility)
    private static var timer: DispatchSourceTimer?
    private static var waitingSince: UInt64 = 0     // when the unanswered ping was sent (0: none)
    private static var reported = false

    private static var running = false

    static func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: .seconds(1), leeway: .milliseconds(500))
        t.setEventHandler(handler: tick)
        timer = t
        // Only while Ufolio is the app in front: in the background macOS slows it on purpose
        // (App Nap), which isn't a hang, and there's no need to wake at all then.
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in setRunning(true) }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in setRunning(false) }
        setRunning(true)
    }

    private static func setRunning(_ on: Bool) {
        queue.async {
            guard let timer, on != running else { return }
            running = on
            if on { timer.resume() } else { timer.suspend(); waitingSince = 0; reported = false }
        }
    }

    private static func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        if waitingSince != 0 {
            // Still unanswered: note a hang once it passes two seconds (once per hang).
            if !reported, now - waitingSince > 2_000_000_000 { reported = true }
            return
        }
        waitingSince = now
        DispatchQueue.main.async {
            queue.async {
                let sent = waitingSince
                waitingSince = 0
                guard reported else { return }
                reported = false
                let seconds = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1e9
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                CrashLog.append(String(format: "Ufolio %@ stopped responding for %.1f seconds\n", version, seconds))
            }
        }
    }
}
