import WebKit

/// Element Zapper: click anything on a page to hide it, for good. Hidden elements are saved
/// per site and turned into WebKit content rules, so they're gone before the page even draws.
final class ElementZapper: NSObject, ObservableObject, WKScriptMessageHandler {
    static let shared = ElementZapper()
    static let handlerName = "hushZapper"
    static let ruleIdentifier = "hush-zapper"

    /// site → CSS selectors hidden on it
    @Published private(set) var hidden: [String: [String]]
    /// Hidden from a Stealth window: until Ufolio quits only, never written down.
    private var sessionHidden: [String: [String]] = [:]

    /// The last Stealth window closed: what it hid goes with it.
    func stealthEnded() {
        guard !sessionHidden.isEmpty else { return }
        sessionHidden = [:]
        ContentBlocker.shared.installZapperRules(rulesJSON)
    }

    private let tabs = NSMapTable<WKWebView, BrowserTab>.weakToWeakObjects()
    private let registered = NSHashTable<WKUserContentController>.weakObjects()

    private override init() {
        hidden = UserDefaults.standard.dictionary(forKey: "zappedElements") as? [String: [String]] ?? [:]
        super.init()
    }

    func register(_ tab: BrowserTab) {
        tabs.setObject(tab, forKey: tab.webView)
        let controller = tab.webView.configuration.userContentController
        if !registered.contains(controller) {
            registered.add(controller)
            controller.add(self, contentWorld: .defaultClient, name: Self.handlerName)
        }
    }

    /// Starts picking on the tab's page (Esc or Done to finish).
    func start(in tab: BrowserTab) {
        FeatureUsage.mark(.zapper)
        tab.webView.callAsyncJavaScript(Self.pickerScript, arguments: [:], in: nil, in: .defaultClient) { _ in }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], body["type"] as? String == "zap",
              let selector = body["selector"] as? String, !selector.isEmpty, selector.count < 500,
              // A selector can't end the rule or start another one.
              !selector.contains(where: { "{};\n\r".contains($0) }) else { return }
        let site = ContentBlocker.normalize(message.frameInfo.securityOrigin.host)
        guard !site.isEmpty else { return }
        if let webView = message.webView, let tab = tabs.object(forKey: webView), tab.isPrivate {
            var list = sessionHidden[site] ?? []
            guard !list.contains(selector), list.count < 200 else { return }
            list.append(selector)
            sessionHidden[site] = list
            ContentBlocker.shared.installZapperRules(rulesJSON)
            return
        }
        var list = hidden[site] ?? []
        // Kept to a sensible size, so the rules stay quick to build.
        guard !list.contains(selector), list.count < 200, hidden[site] != nil || hidden.count < 1000 else { return }
        list.append(selector)
        hidden[site] = list
        saveAndApply()
    }

    func showAgain(_ site: String) {
        hidden[site] = nil
        sessionHidden[site] = nil
        saveAndApply()
    }

    private func saveAndApply() {
        UserDefaults.standard.set(hidden, forKey: "zappedElements")
        ContentBlocker.shared.installZapperRules(rulesJSON)
    }

    /// One css-display-none rule per site; nil when nothing is hidden.
    var rulesJSON: String? {
        let all = hidden.merging(sessionHidden) { saved, session in saved + session.filter { !saved.contains($0) } }
        let rules: [[String: Any]] = all.sorted { $0.key < $1.key }.compactMap { site, selectors in
            guard !selectors.isEmpty else { return nil }
            return [
                "trigger": ["url-filter": ".*", "if-domain": ["*" + site]] as [String: Any],
                "action": ["type": "css-display-none", "selector": selectors.joined(separator: ", ")],
            ]
        }
        guard !rules.isEmpty, let data = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The picker: highlight what's under the pointer, click to hide it, Esc or Done to finish.
    /// Runs in WebKit's isolated world, so the page can't see or interfere with it.
    static let pickerScript = #"""
    if (window.__hushZapping) return;
    window.__hushZapping = true;
    var accent = '#7c5cff';
    var box = document.createElement('div');
    box.style.cssText = 'position:fixed;z-index:2147483646;pointer-events:none;border:2px solid ' + accent +
      ';background:rgba(124,92,255,.14);border-radius:5px;display:none;transition:all .07s ease-out';
    var bar = document.createElement('div');
    bar.style.cssText = 'position:fixed;z-index:2147483647;top:14px;left:50%;transform:translateX(-50%);' +
      'background:rgba(28,26,38,.94);color:#fff;font:500 13px -apple-system,system-ui;padding:8px 8px 8px 16px;' +
      'border-radius:999px;box-shadow:0 10px 34px rgba(0,0,0,.35);display:flex;gap:14px;align-items:center;' +
      'backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px)';
    var label = document.createElement('span');
    label.textContent = 'Click anything to hide it';
    var done = document.createElement('button');
    done.textContent = 'Done';
    done.style.cssText = 'font:600 12px -apple-system,system-ui;border:0;border-radius:999px;padding:6px 14px;' +
      'background:' + accent + ';color:#fff;cursor:pointer';
    bar.appendChild(label); bar.appendChild(done);
    document.documentElement.appendChild(box);
    document.documentElement.appendChild(bar);
    var current = null, count = 0;

    function stable(name) { return /^[A-Za-z][\w-]{1,40}$/.test(name) && !/\d{4,}/.test(name); }
    function selectorFor(el) {
      if (el.id && stable(el.id) && document.querySelectorAll('#' + CSS.escape(el.id)).length === 1) return '#' + CSS.escape(el.id);
      var parts = [], node = el;
      while (node && node.nodeType === 1 && node !== document.body && node !== document.documentElement && parts.length < 6) {
        if (node.id && stable(node.id)) { parts.unshift('#' + CSS.escape(node.id)); break; }
        var part = node.tagName.toLowerCase();
        var classes = Array.prototype.filter.call(node.classList, function (c) { return /^[A-Za-z][\w-]{1,30}$/.test(c) && !/\d{3,}/.test(c); }).slice(0, 2);
        if (classes.length) part += '.' + classes.map(function (c) { return CSS.escape(c); }).join('.');
        var parent = node.parentElement;
        if (parent) {
          var same = Array.prototype.filter.call(parent.children, function (c) { return c.tagName === node.tagName; });
          if (same.length > 1) part += ':nth-of-type(' + (same.indexOf(node) + 1) + ')';
        }
        parts.unshift(part);
        node = parent;
        var candidate = parts.join(' > ');
        try { if (document.querySelectorAll(candidate).length === 1) return candidate; } catch (e) {}
      }
      // Reached the top without anything unique: anchor it to the page, so a plain wrapper
      // straight inside <body> is saved as "body > div", not "div" (which hid every div on
      // the site, leaving it blank).
      if (node === document.body) parts.unshift('body');
      return parts.join(' > ');
    }
    function over(e) {
      if (!e.isTrusted) return;   // only the real pointer, never events a page script makes up
      if (bar.contains(e.target)) { box.style.display = 'none'; current = null; return; }
      current = e.target;
      var r = current.getBoundingClientRect();
      box.style.display = 'block';
      box.style.left = r.left + 'px'; box.style.top = r.top + 'px';
      box.style.width = r.width + 'px'; box.style.height = r.height + 'px';
    }
    function swallow(e) { if (!bar.contains(e.target)) { e.preventDefault(); e.stopPropagation(); } }
    function pick(e) {
      if (bar.contains(e.target)) return;
      e.preventDefault(); e.stopPropagation();
      if (!e.isTrusted) return;   // a page can fake clicks; only your own click hides something
      if (!current || current === document.body || current === document.documentElement) return;
      var sel = selectorFor(current);
      try { document.querySelectorAll(sel); } catch (err) { return; }
      current.style.setProperty('display', 'none', 'important');
      box.style.display = 'none';
      count++;
      label.textContent = count + (count === 1 ? ' element hidden' : ' elements hidden') + ' · click more, or Done';
      webkit.messageHandlers.hushZapper.postMessage({ type: 'zap', selector: sel });
    }
    function key(e) { if (e.isTrusted && e.key === 'Escape') { e.preventDefault(); finish(); } }
    function finish() {
      document.removeEventListener('mouseover', over, true);
      document.removeEventListener('mousedown', swallow, true);
      document.removeEventListener('mouseup', swallow, true);
      document.removeEventListener('click', pick, true);
      document.removeEventListener('keydown', key, true);
      box.remove(); bar.remove();
      window.__hushZapping = false;
    }
    done.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); finish(); });
    document.addEventListener('mouseover', over, true);
    document.addEventListener('mousedown', swallow, true);
    document.addEventListener('mouseup', swallow, true);
    document.addEventListener('click', pick, true);
    document.addEventListener('keydown', key, true);
    """#
}
