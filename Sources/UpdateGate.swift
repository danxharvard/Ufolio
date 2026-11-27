import SwiftUI
import AppKit

/// Stops very old versions of Ufolio from being used (after a security fix, say).
///
/// A small file in Ufolio's repository says the lowest version still allowed on each channel and
/// when that was set. It only counts if it carries Ufolio's own signature (the key that signs
/// updates) and is at least as new as the last one seen, so nobody else can lock people out, or
/// undo a lock by replaying an old file. A version below the minimum gets three days' warning
/// (a banner); after that, an update screen covers the window until it updates.
///
/// If the file can't be fetched (no internet, GitHub down), Ufolio always lets you in.
final class UpdateGate: ObservableObject {
    static let shared = UpdateGate()

    enum State: Equatable {
        case ok
        case warning(until: Date)   // below the minimum, still in the grace period
        case blocked
    }

    @Published private(set) var state: State = .ok
    @Published var bannerClosed = false   // the warning can be put away until next launch
    @Published private(set) var updateProblem: String?
    @Published private(set) var updating = false

    static let gracePeriod: TimeInterval = 3 * 86_400
    static let signingPrefix = Data("ufolio-minimum-version\n".utf8)
    private static let remote = URL(string: "https://raw.githubusercontent.com/danxharvard/Ufolio/main/rules/minimum-version.json")!
    static let releasesPage = URL(string: "https://github.com/danxharvard/Ufolio/releases")!
    private static let issuedKey = "minimumVersionIssued"

    /// Test copies (another bundle ID) only: UFOLIO_MINIMUM_URL points at a local file instead.
    private static var source: URL {
        if Bundle.main.bundleIdentifier != "com.danxharvard.hushbrowser",
           let path = ProcessInfo.processInfo.environment["UFOLIO_MINIMUM_URL"], let url = URL(string: path) { return url }
        return remote
    }

    private var timer: Timer?

    /// Checks a few seconds after launch, then every 6 hours.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Task { await self.check() } }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3_600, repeats: true) { _ in Task { await self.check() } }
        timer?.tolerance = 600
    }

    struct Minimum: Decodable {
        let issued: Int        // goes up every time the file changes
        let stable: String
        let beta: String
        let since: Date        // when this minimum was set: the grace period starts here
    }

    @MainActor
    func check() async {
        var request = URLRequest(url: Self.source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Ufolio", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true, data.count < 10_000,
              let (sigData, _) = try? await URLSession.shared.data(from: Self.source.appendingPathExtension("sig")),
              let sig = Data(base64Encoded: String(decoding: sigData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
              Updater.isSigned(Self.signingPrefix + data, signature: sig) else { return }   // can't tell: let them in
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let minimum = try? decoder.decode(Minimum.self, from: data) else { return }
        // An older file than one already seen is ignored (it could be replayed to lift a lock).
        let seen = UserDefaults.standard.integer(forKey: Self.issuedKey)
        guard minimum.issued >= seen else { return }
        UserDefaults.standard.set(minimum.issued, forKey: Self.issuedKey)

        let required = Prefs.bool(Prefs.betaUpdates) ? minimum.beta : minimum.stable
        let current = Updater.shared.currentVersion
        let next: State
        if !Updater.isNewer(required, than: current) {
            next = .ok
        } else {
            let deadline = minimum.since.addingTimeInterval(Self.gracePeriod)
            next = Date() < deadline ? .warning(until: deadline) : .blocked
        }
        if next != state { state = next }
    }

    /// Downloads and installs the newest version, then restarts Ufolio.
    @MainActor
    func updateNow() async {
        guard !updating else { return }
        updating = true; updateProblem = nil
        defer { updating = false }
        let updater = Updater.shared
        if case .ready = updater.state { updater.restartToUpdate(); return }
        await updater.check(userInitiated: true)
        if case .available = updater.state { await updater.download() }
        switch updater.state {
        case .ready: updater.restartToUpdate()
        case .failed(let message): updateProblem = message
        default: updateProblem = "Ufolio couldn’t download the update just now."
        }
    }

    static func deadlineText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// The three-day warning, under the toolbar.
struct UpdateGateBanner: View {
    @ObservedObject private var gate = UpdateGate.shared

    var body: some View {
        if case .warning(let until) = gate.state, !gate.bannerClosed {
            VStack(spacing: 0) {
                Hairline()
                HStack(spacing: 12) {
                    Button { withAnimation(.smooth(duration: 0.25)) { gate.bannerClosed = true } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remind me next time Ufolio opens")
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This version of Ufolio needs updating")
                            .font(.system(size: 13, weight: .semibold))
                        Text(gate.updateProblem ?? "Update by \(UpdateGate.deadlineText(until)) to keep using Ufolio. It takes a moment, and your tabs come back.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    if gate.updating {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Update Now") { Task { await gate.updateNow() } }
                            .controlSize(.regular)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// After the grace period: covers the window until Ufolio is updated.
struct UpdateGateOverlay: View {
    @ObservedObject private var gate = UpdateGate.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if gate.state == .blocked {
            ZStack {
                // Frosted all over: the pages behind can't be seen or used.
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                LaunchCardOverlay {
                    VStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable().frame(width: 72, height: 72)
                        Text("Time to update Ufolio")
                            .font(.system(size: 20, weight: .semibold))
                        Text("This version is too old to keep using safely. Update to carry on: it only takes a moment, and your tabs come back.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if let problem = gate.updateProblem {
                            Text(problem)
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if case .downloading(_, let progress) = updater.state {
                            ProgressView(value: progress).frame(width: 220)
                        }
                        HStack(spacing: 10) {
                            Button("Quit") { NSApp.terminate(nil) }
                                .controlSize(.large)
                            if gate.updateProblem != nil {
                                // The updater can't do it here (not in Applications, say): the website can.
                                Button("Download from Website") { NSWorkspace.shared.open(UpdateGate.releasesPage) }
                                    .controlSize(.large)
                            }
                            Button(gate.updateProblem == nil ? "Update Now" : "Try Again") { Task { await gate.updateNow() } }
                                .controlSize(.large)
                                .keyboardShortcut(.defaultAction)
                                .disabled(gate.updating)
                        }
                        .padding(.top, 4)
                    }
                    .padding(28)
                    .frame(width: 400)
                }
            }
            .transition(.opacity)
        }
    }
}
