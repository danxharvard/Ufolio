import SwiftUI
import WebKit

/// Hushlist (hushlist.online): a free blocklist of about 240,000 ad, tracker, phishing and malware
/// domains. Hush Guard can use it directly, and hushlist.online can offer to connect it when
/// you visit in Hush.

// MARK: - The box in Settings › Hush Guard

struct HushlistCard: View {
    @ObservedObject private var blocker = ContentBlocker.shared
    @State private var showingSetup = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.40, blue: 1.0), Color(red: 0.25, green: 0.20, blue: 0.75)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: blocker.hushlist == nil ? "shield.lefthalf.filled.badge.checkmark" : "checkmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                if let list = blocker.hushlist {
                    Text("Hushlist is connected").font(.system(size: 13.5, weight: .semibold))
                    Text("\(list.ruleCount.formatted()) domains blocked on top of Force Field. Updates itself every week.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Get maximum blocking with Hushlist").font(.system(size: 13.5, weight: .semibold))
                    Text("Connect Ufolio to Hushlist, a free list of about 240,000 ad, tracker, phishing and malware domains. No sign-up.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button(blocker.hushlist == nil ? "Set Up…" : "Options…") { showingSetup = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .sheet(isPresented: $showingSetup) { HushlistSetup { showingSetup = false } }
    }
}

// MARK: - The mini setup

struct HushlistSetup: View {
    let onDone: () -> Void
    @ObservedObject private var blocker = ContentBlocker.shared
    enum Step { case intro, choose, connecting, done }
    enum Scope { case hush, wholeMac }
    @State private var step: Step = .intro
    @State private var scope: Scope = .hush
    @State private var copied = false

    static let macCommand = "curl -fsSL https://hushlist.online/install/hushlist-mac.command | bash"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.40, blue: 1.0), Color(red: 0.25, green: 0.20, blue: 0.75)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Step \(stepNumber) of 3").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            content
            Spacer(minLength: 0)
            HStack {
                if step == .choose { Button("Back") { withAnimation { step = .intro } } }
                Spacer()
                if step != .done && step != .connecting { Button("Not Now", action: onDone).keyboardShortcut(.cancelAction) }
                primaryButton
            }
        }
        .padding(24)
        .frame(width: 480, height: 400)
        .onChange(of: blocker.isWorking) { _, working in
            if step == .connecting && !working { withAnimation { step = .done } }
        }
    }

    private var title: String {
        switch step {
        case .intro: return "Block even more with Hushlist"
        case .choose: return "Where should Hushlist block?"
        case .connecting: return "Connecting Hushlist…"
        case .done: return blocker.hushlist != nil ? "Hushlist is connected" : "That didn’t work"
        }
    }

    private var stepNumber: Int {
        switch step { case .intro: return 1; case .choose: return 2; default: return 3 }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .intro:
            VStack(alignment: .leading, spacing: 12) {
                point("hand.raised.slash.fill", "About 240,000 domains of ads, trackers, phishing and malware, blocked on top of Force Field.")
                point("checkmark.seal.fill", "Built not to break the sites you use.")
                point("arrow.triangle.2.circlepath", "Free, no sign-up, and Ufolio keeps it up to date every week.")
            }
        case .choose:
            VStack(spacing: 10) {
                choice(.hush, "In Ufolio (recommended)", "Force Field uses Hushlist for every page. Nothing to install.")
                choice(.wholeMac, "In Ufolio and every app on your Mac", "Also blocks in other apps and browsers, with Hushlist’s Mac installer.")
            }
        case .connecting:
            VStack(alignment: .leading, spacing: 10) {
                ProgressView().controlSize(.small)
                Text(blocker.status ?? "Downloading Hushlist…").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Text("Ufolio is turning about 240,000 domains into blocking rules. This only happens once and can take a minute.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .done:
            VStack(alignment: .leading, spacing: 12) {
                if let list = blocker.hushlist {
                    point("checkmark.circle.fill", "Force Field now blocks \(list.ruleCount.formatted()) more domains.")
                } else {
                    point("exclamationmark.triangle.fill", blocker.status ?? "Hushlist couldn’t be downloaded. Check your connection and try again.")
                }
                if scope == .wholeMac && blocker.hushlist != nil {
                    Text("To block in every app too, run Hushlist’s installer once:").font(.system(size: 12.5, weight: .semibold))
                    Text("1. Click Copy Installer Command below.\n2. Open the Terminal app (press ⌘Space, type Terminal, press Return).\n3. Paste with ⌘V, press Return, and type your Mac password when asked.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(copied ? "Copied" : "Copy Installer Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.macCommand, forType: .string)
                            copied = true
                        }
                        Button("Open the Guide") { NSWorkspace.shared.open(URL(string: "https://hushlist.online/#setup")!) }
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case .intro:
            Button("Continue") { withAnimation { step = .choose } }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        case .choose:
            Button(blocker.hushlist == nil ? "Connect Hushlist" : "Update Hushlist") {
                withAnimation { step = .connecting }
                blocker.connectHushlist()
            }
            .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        case .connecting:
            EmptyView()
        case .done:
            Button("Done", action: onDone).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 20)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice(_ value: Scope, _ title: String, _ detail: String) -> some View {
        Button { scope = value } label: {
            HStack(spacing: 12) {
                Image(systemName: scope == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(scope == value ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(scope == value ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(scope == value ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: scope == value ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - hushlist.online ⇄ Hush

/// On hushlist.online (and only there), Hush tells the page it's running in Hush, so the site can
/// offer one-click setup. The site asks; Hush always asks you before connecting anything.
final class HushlistLink: NSObject, WKScriptMessageHandler {
    static let shared = HushlistLink()
    static let handlerName = "hushlist"
    private static let hosts: Set<String> = ["hushlist.online", "www.hushlist.online"]
    private let registered = NSHashTable<WKUserContentController>.weakObjects()

    /// Rebuilt each time a page's protections are set, so the site sees whether Hushlist is connected.
    static var script: WKUserScript {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let connected = ContentBlocker.shared.hushlist != nil
        let source = """
        (function () {
          var h = location.hostname;
          if (location.protocol !== 'https:' || (h !== 'hushlist.online' && h !== 'www.hushlist.online')) return;
          window.hushBrowser = Object.freeze({
            name: 'Hush Browser', version: \(String(reflecting: version)), hushlistConnected: \(connected),
            connectHushlist: function () { window.webkit.messageHandlers.\(handlerName).postMessage('connect'); }
          });
          window.dispatchEvent(new Event('hushbrowser'));
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    func register(_ controller: WKUserContentController) {
        guard !registered.contains(controller) else { return }
        registered.add(controller)
        controller.add(self, contentWorld: .page, name: Self.handlerName)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // Only hushlist.online itself, over HTTPS, in the page's main frame. Anything else is ignored.
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == "https", Self.hosts.contains(origin.host),
              message.body as? String == "connect", let webView = message.webView else { return }
        let blocker = ContentBlocker.shared
        // One question at a time: the page asking again and again could stack them up.
        guard blocker.hushlist == nil, !blocker.isWorking, !DialogHost.isBusy(webView.window) else { return }
        DialogHost.show(HushDialog(
            art: .symbol("shield.lefthalf.filled.badge.checkmark"), theme: .hush, motion: .orbit,
            title: "Connect Hushlist to Force Field?",
            message: "Force Field will also block Hushlist’s 240,000 ad, tracker, phishing and malware domains, and keep the list up to date.",
            choices: [.init(title: "Not Now", role: .cancel), .init(title: "Connect", role: .primary)],
            completion: { choice, _ in
                guard choice == 1 else { return }
                blocker.connectHushlist()
                // Reload once Hushlist is actually set up (it takes a while), so the site can show
                // that it's connected; reloading straight away still showed "not connected".
                weak var page = webView
                func reloadWhenReady(_ tries: Int) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if !blocker.isWorking || tries > 180 { page?.reload() } else { reloadWhenReady(tries + 1) }
                    }
                }
                reloadWhenReady(0)
            }), in: webView.window)
    }
}
