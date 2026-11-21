import SwiftUI
import WebKit
import Translation
import NaturalLanguage

/// Quick translation: Hush notices pages in another language and translates them in place,
/// on your Mac, with Apple's Translation framework. The page's text never leaves your Mac.
enum TranslationState: Equatable {
    case none                  // same language as you, or not supported
    case available             // can be translated
    case translating
    case translated
    case failed(String)
}

@MainActor
final class PageTranslator: ObservableObject {
    static let shared = PageTranslator()

    /// Drives the hidden SwiftUI view that owns the translation session.
    @Published var configuration: TranslationSession.Configuration?
    private weak var pendingTab: BrowserTab?

    /// The language pages are translated into: your Mac's first preferred language.
    static var target: Locale.Language {
        Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
    }

    static func name(of language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier else { return "another language" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    // MARK: Detecting

    private static let sampleScript = """
    const text = (document.body ? document.body.innerText : '').slice(0, 3000);
    return { lang: document.documentElement.lang || '', text };
    """

    /// Works out the page's language after it loads, and offers translation if it isn't yours.
    func detect(in tab: BrowserTab) {
        guard tab.translation == .none || tab.translation == .available else { return }
        Task { @MainActor in
            guard let result = try? await tab.webView.callAsyncJavaScript(Self.sampleScript, arguments: [:], in: nil, contentWorld: .defaultClient) as? [String: Any] else { return }
            let text = result["text"] as? String ?? ""
            let declared = result["lang"] as? String ?? ""
            var language: Locale.Language?
            if text.count >= 60 {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(text)
                if let found = recognizer.dominantLanguage, found != .undetermined,
                   (recognizer.languageHypotheses(withMaximum: 1)[found] ?? 0) > 0.6 {
                    language = Locale.Language(identifier: found.rawValue)
                }
            }
            if language == nil, !declared.isEmpty { language = Locale.Language(identifier: declared) }
            guard let language, let code = language.languageCode,
                  code != Self.target.languageCode else { tab.setTranslation(.none, language: nil); return }
            let status = await LanguageAvailability().status(from: language, to: Self.target)
            guard status != .unsupported else { tab.setTranslation(.none, language: nil); return }
            tab.setTranslation(.available, language: language)
        }
    }

    // MARK: Translating

    func translate(_ tab: BrowserTab) {
        guard let source = tab.pageLanguage, tab.translation != .translating else { return }
        pendingTab = tab
        tab.setTranslation(.translating, language: source)
        if let configuration, configuration.source == source, configuration.target == Self.target {
            self.configuration?.invalidate()   // same languages: run the session again
        } else {
            configuration = TranslationSession.Configuration(source: source, target: Self.target)
        }
    }

    func showOriginal(_ tab: BrowserTab) {
        Task { @MainActor in
            _ = try? await tab.webView.callAsyncJavaScript(Self.restoreScript, arguments: [:], in: nil, contentWorld: .defaultClient)
            tab.setTranslation(.available, language: tab.pageLanguage)
        }
    }

    /// Called by the translation session with permission to translate (after any language
    /// download the system asks you about).
    func run(_ session: TranslationSession) async {
        guard let tab = pendingTab, tab.translation == .translating else { return }
        pendingTab = nil
        do {
            guard let texts = try await tab.webView.callAsyncJavaScript(Self.collectScript, arguments: ["limit": 4000],
                                                                         in: nil, contentWorld: .defaultClient) as? [String],
                  !texts.isEmpty else {
                tab.setTranslation(.failed("There’s no text to translate on this page."), language: tab.pageLanguage)
                return
            }
            try await session.prepareTranslation()
            // In batches from the top of the page, so what you're looking at changes first.
            var start = 0
            while start < texts.count {
                guard tab.translation == .translating else { return }   // navigated away or cancelled
                let end = min(start + 150, texts.count)
                let requests = (start..<end).map {
                    TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0))
                }
                let responses = try await session.translations(from: requests)
                var updates: [String: String] = [:]
                for response in responses {
                    if let id = response.clientIdentifier { updates[id] = response.targetText }
                }
                _ = try await tab.webView.callAsyncJavaScript(Self.applyScript, arguments: ["updates": updates],
                                                              in: nil, contentWorld: .defaultClient)
                start = end
            }
            tab.setTranslation(.translated, language: tab.pageLanguage)
        } catch {
            tab.setTranslation(.failed("Hush couldn’t translate this page."), language: tab.pageLanguage)
        }
    }

    // Runs in Hush's own script world: the page can't see or tamper with it. Text is only
    // ever set as plain text (nodeValue), never as HTML.
    private static let collectScript = """
    const skip = new Set(['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','TEXTAREA','INPUT','SELECT','OPTION','SVG','MATH','KBD','SAMP','VAR','TEMPLATE']);
    const ok = new Map();
    function allowed(el) {
      if (!el) return true;
      if (ok.has(el)) return ok.get(el);
      const bad = skip.has(el.tagName) || el.isContentEditable || el.getAttribute('translate') === 'no' || el.classList.contains('notranslate');
      const result = !bad && allowed(el.parentElement);
      ok.set(el, result);
      return result;
    }
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const nodes = [];
    let n;
    while ((n = walker.nextNode()) && nodes.length < limit) {
      const t = n.nodeValue;
      if (t && /\\p{L}/u.test(t) && allowed(n.parentElement)) nodes.push(n);
    }
    window.__hushTranslation = { nodes, originals: nodes.map(x => x.nodeValue), lang: document.documentElement.lang };
    return nodes.map(x => x.nodeValue.trim());
    """

    private static let applyScript = """
    const s = window.__hushTranslation;
    if (!s) return;
    for (const [key, text] of Object.entries(updates)) {
      const i = Number(key), node = s.nodes[i], original = s.originals[i];
      if (!node || typeof text !== 'string') continue;
      node.nodeValue = original.match(/^\\s*/)[0] + text + original.match(/\\s*$/)[0];
    }
    """

    private static let restoreScript = """
    const s = window.__hushTranslation;
    if (!s) return;
    s.nodes.forEach((node, i) => { node.nodeValue = s.originals[i]; });
    window.__hushTranslation = null;
    """
}

/// Invisible view that hosts the translation session (Apple only hands sessions to SwiftUI views).
struct TranslationHost: View {
    @ObservedObject private var translator = PageTranslator.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(translator.configuration) { session in
                await translator.run(session)
            }
    }
}

/// The translate button in the address bar.
struct TranslateButton: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        if tab.translation != .none, let language = tab.pageLanguage {
            let from = PageTranslator.name(of: language)
            let to = PageTranslator.name(of: PageTranslator.target)
            Menu {
                switch tab.translation {
                case .translated:
                    Button("Show Original (\(from))") { PageTranslator.shared.showOriginal(tab) }
                case .translating:
                    Text("Translating from \(from)…")
                default:
                    Button("Translate to \(to)") { PageTranslator.shared.translate(tab) }
                }
                if case .failed(let message) = tab.translation {
                    Divider()
                    Text(message)
                }
                Divider()
                Text("Translated on your Mac. The page never leaves it.")
            } label: {
                Group {
                    if tab.translation == .translating {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tab.translation == .translated ? Color.accentColor : Color.secondary)
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
            } primaryAction: {
                switch tab.translation {
                case .translated: PageTranslator.shared.showOriginal(tab)
                case .translating: break
                default: PageTranslator.shared.translate(tab)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tab.translation == .translated ? "Show the original \(from)" : "Translate this \(from) page to \(to)")
        }
    }
}
