import SwiftUI
import WebKit

/// Reader: the article on its own, in calm type, without ads, menus or pop-ups.
/// Hush copies out only the text and pictures (as plain data) and lays them out itself,
/// so none of the page's own code runs inside Reader.
struct ReaderArticle: Equatable {
    struct Block: Equatable, Identifiable {
        enum Kind: String { case heading, subheading, paragraph, quote, item, code, image, caption }
        let id: Int
        let kind: Kind
        let text: String
        let image: URL?
    }
    let title: String
    let byline: String
    let site: String
    let blocks: [Block]

    var minutes: Int {
        let words = blocks.reduce(0) { $0 + $1.text.split(separator: " ").count }
        return max(1, Int((Double(words) / 230).rounded()))
    }
}

enum ReaderMode {
    /// Cheap check after a page loads: is there an article worth showing?
    static let detectScript = """
    const ps = Array.from(document.querySelectorAll('p')).filter(p => (p.textContent || '').trim().length > 80);
    const total = ps.reduce((n, p) => n + p.textContent.length, 0);
    return ps.length >= 4 && total > 1200;
    """

    static let extractScript = """
    const SKIP = 'nav, aside, footer, form, menu, dialog, [role=navigation], [role=complementary], [aria-hidden=true], .share, .social, .related, .comments, .advert, .ad, .newsletter';
    // The article is the smallest part of the page holding most of its long paragraphs.
    const paragraphs = Array.from(document.querySelectorAll('p')).filter(p => !p.closest(SKIP) && (p.textContent || '').trim().length > 60);
    const total = paragraphs.reduce((n, p) => n + p.textContent.length, 0);
    if (total < 800) return null;
    const held = new Map(), depth = new Map();
    for (const p of paragraphs) {
      let d = 0;
      for (let el = p.parentElement; el && el !== document.documentElement; el = el.parentElement) {
        held.set(el, (held.get(el) || 0) + p.textContent.length);
        d++;
      }
    }
    for (const el of held.keys()) { let d = 0, e = el; while (e) { d++; e = e.parentElement; } depth.set(el, d); }
    let best = null;
    for (const [el, n] of held) {
      if (n >= total * 0.75 && (!best || depth.get(el) > depth.get(best))) best = el;
    }
    if (!best) return null;
    const article = best.closest('article') || best;
    const TAGS = 'h1,h2,h3,h4,p,li,blockquote,pre,img,figcaption';
    const blocks = [];
    const clean = s => (s || '').replace(/\\s+/g, ' ').trim();
    for (const el of article.querySelectorAll(TAGS)) {
      if (blocks.length > 1500) break;
      if (el.closest(SKIP)) continue;
      const parent = el.parentElement && el.parentElement.closest('p,li,blockquote,pre,figcaption');
      if (parent && article.contains(parent)) continue;
      const tag = el.tagName;
      if (tag === 'IMG') {
        const src = el.currentSrc || el.src || '';
        const w = el.naturalWidth || el.width || 0;
        if (/^https?:/.test(src) && w >= 200) blocks.push({ kind: 'image', text: clean(el.alt), src });
        continue;
      }
      // innerText: only what's visible (no hidden notes or style code), only read when opening Reader.
      const text = tag === 'PRE' ? (el.textContent || '').trim() : clean(el.innerText);
      if (!text) continue;
      const kind = tag === 'H1' || tag === 'H2' ? 'heading' : (tag === 'H3' || tag === 'H4') ? 'subheading'
        : tag === 'BLOCKQUOTE' ? 'quote' : tag === 'LI' ? 'item' : tag === 'PRE' ? 'code'
        : tag === 'FIGCAPTION' ? 'caption' : 'paragraph';
      if (kind === 'paragraph' && text.length < 25 && !/[.!?]$/.test(text)) continue;
      blocks.push({ kind, text: text.slice(0, 20000), src: '' });
    }
    const meta = n => { const m = document.querySelector('meta[name="' + n + '"], meta[property="' + n + '"]'); return m ? clean(m.content) : ''; };
    const h1 = clean((document.querySelector('h1') || {}).textContent || '');
    const og = meta('og:title');
    return {
      title: (h1 && (!og || og.includes(h1))) ? h1 : (og || h1 || document.title),
      byline: meta('author') || clean((document.querySelector('[rel=author], .byline, .author') || {}).textContent || ''),
      site: meta('og:site_name') || location.hostname.replace(/^www\\./, ''),
      blocks
    };
    """

    static func detect(in tab: BrowserTab) {
        tab.webView.callAsyncJavaScript(detectScript, arguments: [:], in: nil, in: .defaultClient) { result in
            if case .success(let value) = result { tab.setReaderAvailable((value as? Bool) ?? false) }
        }
    }

    static func open(_ tab: BrowserTab) {
        tab.webView.callAsyncJavaScript(extractScript, arguments: [:], in: nil, in: .defaultClient) { result in
            guard case .success(let value) = result, let dict = value as? [String: Any],
                  let raw = dict["blocks"] as? [[String: Any]], !raw.isEmpty else { NSSound.beep(); return }
            var title = (dict["title"] as? String) ?? tab.displayTitle
            let blocks: [ReaderArticle.Block] = raw.enumerated().compactMap { index, item in
                guard let kind = ReaderArticle.Block.Kind(rawValue: item["kind"] as? String ?? "") else { return nil }
                let src = (item["src"] as? String).flatMap(URL.init(string:))
                let image = ["http", "https"].contains(src?.scheme ?? "") ? src : nil
                return ReaderArticle.Block(id: index, kind: kind, text: item["text"] as? String ?? "", image: image)
            }
            // Don't repeat the title as the first heading.
            var trimmed = blocks
            if let first = trimmed.first, first.kind == .heading, first.text == title { trimmed.removeFirst() }
            if title.isEmpty { title = tab.displayTitle }
            tab.showReader(ReaderArticle(title: String(title.prefix(300)), byline: String(((dict["byline"] as? String) ?? "").prefix(120)),
                                         site: (dict["site"] as? String) ?? "", blocks: trimmed))
        }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark
    var id: String { rawValue }
    var background: Color {
        switch self {
        case .light: return Color(red: 0.99, green: 0.99, blue: 0.98)
        case .sepia: return Color(red: 0.97, green: 0.93, blue: 0.85)
        case .dark: return Color(red: 0.11, green: 0.11, blue: 0.13)
        }
    }
    var text: Color {
        switch self {
        case .light: return Color(white: 0.12)
        case .sepia: return Color(red: 0.28, green: 0.22, blue: 0.15)
        case .dark: return Color(white: 0.86)
        }
    }
}

struct ReaderView: View {
    let article: ReaderArticle
    let onClose: () -> Void
    @AppStorage("reader.theme") private var themeName = ReaderTheme.light.rawValue
    @AppStorage("reader.size") private var size = 19.0
    @AppStorage("reader.serif") private var serif = true

    private var theme: ReaderTheme { ReaderTheme(rawValue: themeName) ?? .light }

    var body: some View {
        ZStack(alignment: .top) {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: size * 0.9) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(article.site.uppercased())
                            .font(.system(size: 11, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(theme.text.opacity(0.55))
                        Text(article.title)
                            .font(.system(size: size * 1.75, weight: .bold, design: serif ? .serif : .default))
                        HStack(spacing: 6) {
                            if !article.byline.isEmpty { Text(article.byline) }
                            if !article.byline.isEmpty { Text("·") }
                            Text("\(article.minutes) min read")
                        }
                        .font(.system(size: 13)).foregroundStyle(theme.text.opacity(0.6))
                    }
                    .padding(.bottom, 8)
                    ForEach(article.blocks) { block in
                        ReaderBlockView(block: block, size: size, serif: serif, theme: theme)
                    }
                }
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 64)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity)
            }
            controls
        }
        .environment(\.colorScheme, theme == .dark ? .dark : .light)
        .onExitCommand(perform: onClose)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { size = max(14, size - 1) } label: { Image(systemName: "textformat.size.smaller") }.help("Smaller text")
            Button { size = min(30, size + 1) } label: { Image(systemName: "textformat.size.larger") }.help("Larger text")
            Divider().frame(height: 16)
            Button { serif.toggle() } label: { Text(serif ? "Aa" : "Aa").font(.system(size: 13, design: serif ? .serif : .default)) }
                .help(serif ? "Use a sans-serif font" : "Use a serif font")
            Divider().frame(height: 16)
            ForEach(ReaderTheme.allCases) { option in
                Button { themeName = option.rawValue } label: {
                    Circle().fill(option.background)
                        .overlay(Circle().strokeBorder(themeName == option.rawValue ? Color.accentColor : Color.primary.opacity(0.25),
                                                       lineWidth: themeName == option.rawValue ? 2 : 1))
                        .frame(width: 16, height: 16)
                }
                .help(option.rawValue.capitalized)
            }
            Divider().frame(height: 16)
            Button(action: onClose) { Image(systemName: "xmark") }.help("Leave Reader (Esc)")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .padding(.top, 12)
    }
}

private struct ReaderBlockView: View {
    let block: ReaderArticle.Block
    let size: Double
    let serif: Bool
    let theme: ReaderTheme

    var body: some View {
        let design: Font.Design = serif ? .serif : .default
        switch block.kind {
        case .heading:
            Text(block.text).font(.system(size: size * 1.35, weight: .bold, design: design)).padding(.top, size * 0.6)
        case .subheading:
            Text(block.text).font(.system(size: size * 1.12, weight: .semibold, design: design)).padding(.top, size * 0.4)
        case .paragraph:
            Text(block.text).font(.system(size: size, design: design)).lineSpacing(size * 0.45)
        case .item:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                Text(block.text).lineSpacing(size * 0.4)
            }
            .font(.system(size: size, design: design))
        case .quote:
            Text(block.text).font(.system(size: size * 1.05, design: design).italic()).lineSpacing(size * 0.4)
                .padding(.leading, 16)
                .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 3) }
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text).font(.system(size: size * 0.8, design: .monospaced)).padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.text.opacity(0.06)))
        case .caption:
            Text(block.text).font(.system(size: size * 0.75)).foregroundStyle(theme.text.opacity(0.6))
        case .image:
            if let url = block.image {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(block.text)
            }
        }
    }
}

/// The address-bar buttons for Reader and Picture in Picture.
struct ReaderButton: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        HStack(spacing: 2) {
            if tab.canPictureInPicture {
                SmallBarButton(symbol: "pip.enter", help: "Picture in Picture") { WebKitExtras.togglePictureInPicture(tab.webView) }
            }
            if tab.readerAvailable || tab.reader != nil {
                SmallBarButton(symbol: tab.reader != nil ? "doc.plaintext.fill" : "doc.plaintext",
                               help: tab.reader != nil ? "Leave Reader (⇧⌘R)" : "Show Reader (⇧⌘R)",
                               active: tab.reader != nil) { tab.toggleReader() }
            }
        }
    }
}

private struct SmallBarButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
