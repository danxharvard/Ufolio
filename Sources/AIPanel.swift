import SwiftUI

/// One window's conversation with Ask Hush (kept in memory only, never saved).
@MainActor
final class AIChat: ObservableObject {
    @Published private(set) var messages: [AIMessage] = []
    @Published private(set) var isAnswering = false
    @Published var error: String?
    @Published var note: String?
    private var task: Task<Void, Never>?

    /// Asks a question, optionally sharing the page you're on.
    func ask(_ question: String, display: String? = nil, includePage: Bool, tab: BrowserTab?) {
        guard !isAnswering, let model = AIStore.shared.selected else { return }
        error = nil
        note = nil
        isAnswering = true
        task = Task {
            var prompt = question
            if includePage, let tab, let page = await PageText.read(from: tab) {
                prompt = """
                Here is the web page I'm looking at (\(tab.url?.host?.strippingWWW ?? "unknown site")).
                <page title="\(page.title.replacingOccurrences(of: "\"", with: "'"))">
                \(page.text)
                </page>

                \(question)
                """
                if page.trimmed { note = "This page is very long, so Hush shared its first \(PageText.limit / 1000)k characters." }
            }
            messages.append(AIMessage(role: .user, text: prompt, display: display ?? question))
            messages.append(AIMessage(role: .assistant, text: ""))
            let history = Array(messages.dropLast())
            do {
                try await AIClient.stream(model, messages: history) { [weak self] piece in
                    guard let self, var last = self.messages.last, last.role == .assistant else { return }
                    last.text += piece
                    self.messages[self.messages.count - 1] = last
                }
                if messages.last?.text.isEmpty == true { messages.removeLast(); error = "The model didn’t reply." }
            } catch is CancellationError {
                // Stopped by you.
            } catch {
                if messages.last?.role == .assistant, messages.last?.text.isEmpty == true { messages.removeLast() }
                if (error as? URLError)?.code == .cannotConnectToHost, model.isLocal {
                    self.error = "Nothing is answering at \(model.endpoint). Is \(model.kind == .lmStudio ? "LM Studio’s server" : "Ollama") running?"
                } else if (error as? URLError)?.code != .cancelled {
                    self.error = error.localizedDescription
                }
            }
            isAnswering = false
        }
    }

    func stop() {
        task?.cancel()
        isAnswering = false
    }

    func clear() {
        stop()
        messages = []
        error = nil
        note = nil
    }
}

/// The Ask Hush sidebar.
struct AIPanel: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var chat: AIChat
    @ObservedObject private var store = AIStore.shared
    @State private var input = ""
    @State private var includePage = true
    @FocusState private var focused: Bool

    init(model: BrowserModel) {
        self.model = model
        chat = model.aiChat
    }

    private static let purple = [Color(red: 0.62, green: 0.49, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.models.isEmpty {
                setup
            } else if chat.messages.isEmpty {
                welcome
            } else {
                conversation
            }
            if !store.models.isEmpty { composer }
        }
        .frame(width: 370)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 9) {
            IconTile(symbol: "sparkles", colors: Self.purple, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("Ask Hush").font(.system(size: 13.5, weight: .semibold))
                if let selected = store.selected {
                    Menu {
                        ForEach(store.models) { m in
                            Button { store.selectedID = m.id } label: {
                                if m.id == selected.id { Label(m.name, systemImage: "checkmark") } else { Text(m.name) }
                            }
                        }
                        Divider()
                        Button("Manage Models…") { SettingsOpener.open(tab: .ai) }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: selected.isLocal ? "lock.fill" : "cloud").font(.system(size: 8.5))
                            Text(selected.name).font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(selected.isLocal ? "Runs on this Mac: nothing leaves it" : "Your questions go to \(URL(string: selected.endpoint)?.host ?? "the service")")
                }
            }
            Spacer()
            if !chat.messages.isEmpty {
                Button { chat.clear() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless).help("New Chat")
            }
            Button { model.aiOpen = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("Close")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    // MARK: First run

    private var setup: some View {
        ScrollView {
            VStack(spacing: 14) {
                DialogScene(art: .symbol("sparkles"), badge: "cpu", colors: Self.purple, motion: .sparkle)
                    .frame(height: 120)
                Text("Bring your own AI").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Connect a model and Ask Hush can summarise pages, explain them and answer your questions about them.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                VStack(spacing: 8) {
                    SetupOption(symbol: "desktopcomputer", title: "A model on this Mac",
                                detail: "Free and completely private, with Ollama or LM Studio.") { SettingsOpener.open(tab: .ai) }
                    SetupOption(symbol: "sparkle", title: "Claude",
                                detail: "Fast and capable, with your own Anthropic API key.") { SettingsOpener.open(tab: .ai) }
                    SetupOption(symbol: "cloud.fill", title: "Another service",
                                detail: "Any OpenAI-compatible API, with your own key.") { SettingsOpener.open(tab: .ai) }
                }
                .padding(.top, 4)
                Label("Pages are only shared when you ask about them.", systemImage: "hand.raised.fill")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 6)
            }
            .padding(20)
        }
    }

    // MARK: Ready

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("What would you like to know?")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .padding(.top, 6)
                if let tab = model.selectedTab, tab.url != nil {
                    Text("About \(tab.url?.host?.strippingWWW ?? "this page")")
                        .font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                    VStack(spacing: 7) {
                        QuickAction(symbol: "text.alignleft", title: "Summarise this page") {
                            chat.ask("Summarise this page in a short paragraph, then list the key points.", display: "Summarise this page", includePage: true, tab: tab)
                        }
                        QuickAction(symbol: "list.bullet", title: "Key takeaways") {
                            chat.ask("What are the 5 most important takeaways from this page?", display: "Key takeaways", includePage: true, tab: tab)
                        }
                        QuickAction(symbol: "graduationcap", title: "Explain it simply") {
                            chat.ask("Explain what this page is about simply, as if to someone new to the topic.", display: "Explain it simply", includePage: true, tab: tab)
                        }
                        QuickAction(symbol: "checkmark.seal", title: "Is this trustworthy?") {
                            chat.ask("Assess this page: who wrote it, what it's trying to do, and anything that seems misleading, one-sided or unsupported.", display: "Is this trustworthy?", includePage: true, tab: tab)
                        }
                    }
                } else {
                    Text("Open a page to ask about it, or just ask anything below.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                if let error = chat.error { ErrorLine(text: error) }
            }
            .padding(16)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.messages) { message in
                        MessageView(message: message, answering: chat.isAnswering && message.id == chat.messages.last?.id)
                            .id(message.id)
                    }
                    if let note = chat.note {
                        Label(note, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let error = chat.error { ErrorLine(text: error) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
            }
            .onChange(of: chat.messages.last?.text) { _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: chat.messages.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask anything…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit(send)
                if chat.isAnswering {
                    Button { chat.stop() } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 22)).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain).help("Stop")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
                            .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(focused ? 0.5 : 0), lineWidth: 1.5))
            HStack {
                Toggle(isOn: $includePage) {
                    Text("Include this page").font(.system(size: 11))
                }
                .toggleStyle(.checkbox)
                .disabled(model.selectedTab?.url == nil)
                .help("Shares the page’s text with the model along with your question")
                Spacer()
                if let selected = store.selected {
                    Text(selected.isLocal ? "Stays on this Mac" : "Sent to \(URL(string: selected.endpoint)?.host ?? "the service")")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onAppear { focused = true }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isAnswering else { return }
        input = ""
        // The page is attached to the first question only; follow-ups build on the conversation.
        let firstQuestion = !chat.messages.contains { $0.role == .user }
        chat.ask(text, includePage: includePage && model.selectedTab?.url != nil && firstQuestion, tab: model.selectedTab)
    }
}

private struct MessageView: View {
    let message: AIMessage
    let answering: Bool

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.display ?? message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if message.text.isEmpty && answering {
                    ThinkingDots()
                } else {
                    MarkdownText(text: message.text)
                }
                if !answering && !message.text.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc").font(.system(size: 10.5)) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Renders a reply's Markdown (headings, lists, bold, code) as native text: never as HTML.
private struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let t):
                    Text(inline(t)).font(.system(size: 14, weight: .bold)).padding(.top, 2)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•").foregroundStyle(Color.accentColor)
                        Text(inline(t)).fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let t):
                    Text(t).font(.system(size: 11.5, design: .monospaced))
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                case .paragraph(let t):
                    Text(inline(t)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 13))
        .lineSpacing(2.5)
        .textSelection(.enabled)
    }

    private enum Block { case heading(String), bullet(String), code(String), paragraph(String) }

    private var blocks: [Block] {
        var result: [Block] = []
        var code: [String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code { result.append(.code(open.joined(separator: "\n"))); code = nil } else { code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { continue }
            if line.hasPrefix("#") { result.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { result.append(.bullet(String(line.dropFirst(2)))) }
            else if let r = line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) { result.append(.bullet(String(line[r.upperBound...]))) }
            else { result.append(.paragraph(line)) }
        }
        if let open = code { result.append(.code(open.joined(separator: "\n"))) }
        return result
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .opacity(0.3 + 0.7 * (sin(t * 5 - Double(i) * 0.8) + 1) / 2)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct QuickAction: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor).frame(width: 18)
                Text(title).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0.045)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SetupOption: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Color.accentColor).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0.045)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ErrorLine: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11.5)).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The toolbar button that opens Ask Hush.
struct AskHushButton: View {
    @ObservedObject var model: BrowserModel
    @State private var hovering = false

    var body: some View {
        Button { model.aiOpen.toggle() } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.aiOpen ? Color.accentColor : Color.primary.opacity(0.75))
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering || model.aiOpen ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Ask Hush (⌥⌘A)")
    }
}
