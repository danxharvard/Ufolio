import SwiftUI

/// Settings › AI: connect models for Ask Hush, test them, choose the default.
struct AISettings: View {
    @ObservedObject private var store = AIStore.shared
    @State private var editing: AIModel?
    @State private var key = ""
    @State private var available: [String] = []
    @State private var testing: UUID?
    @State private var results: [UUID: String] = [:]

    var body: some View {
        Form {
            Section {
                SettingsHeader(tab: .ai, subtitle: "Connect your own AI model for Ask Hush: one on this Mac, Claude, or any OpenAI-compatible service.")
            }

            Section {
                if store.models.isEmpty {
                    Text("No models yet. Add one below.").foregroundStyle(.secondary)
                }
                ForEach(store.models) { model in
                    HStack(spacing: 12) {
                        IconTile(symbol: model.kind.symbol, colors: model.isLocal
                                 ? [Color(red: 0.36, green: 0.80, blue: 0.52), Color(red: 0.14, green: 0.58, blue: 0.40)]
                                 : [Color(red: 0.62, green: 0.49, blue: 1.0), Color(red: 0.38, green: 0.26, blue: 0.86)], size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(model.name).font(.system(size: 13, weight: .medium))
                                if store.selected?.id == model.id {
                                    Text("Default").font(.system(size: 9.5, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.18))).foregroundStyle(Color.accentColor)
                                }
                            }
                            Text("\(model.model.isEmpty ? "No model chosen" : model.model) · \(model.isLocal ? "On this Mac" : URL(string: model.endpoint)?.host ?? "")")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            if let result = results[model.id] {
                                Text(result).font(.system(size: 11))
                                    .foregroundStyle(result.hasPrefix("✓") ? Color.green : Color.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        if testing == model.id { ProgressView().controlSize(.small) }
                        Menu {
                            Button("Test") { test(model) }
                            if store.selected?.id != model.id { Button("Make Default") { store.selectedID = model.id } }
                            Button("Edit…") { startEditing(model) }
                            Divider()
                            Button("Remove", role: .destructive) { store.remove(model) }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                }
            } header: { SectionTitle("Your models") }

            Section {
                if let draft = editing {
                    editor(draft)
                } else {
                    HStack(spacing: 8) {
                        ForEach(AIModel.Kind.allCases) { kind in
                            Button { startNew(kind) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: kind.symbol).font(.system(size: 16))
                                    Text(kind.label).font(.system(size: 11)).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: { SectionTitle(editing == nil ? "Add a model" : (store.models.contains { $0.id == editing?.id } ? "Edit model" : "New model")) } footer: {
                Footnote(footnote)
            }
        }
        .formStyle(SafariFormStyle())
    }

    private var footnote: String {
        switch editing?.kind {
        case .ollama: return "Install Ollama from ollama.com, then run a model once (for example “ollama run llama3.2”). Everything stays on this Mac. Large models need a fast Mac."
        case .lmStudio: return "In LM Studio, load a model and start its local server (Developer › Start Server). Everything stays on this Mac."
        case .claude: return "Create an API key at console.anthropic.com. Your questions, and pages you choose to share, go to Anthropic. Your key is kept in your Mac’s keychain."
        case .openAICompatible: return "Any service with an OpenAI-compatible chat API works. Your key is kept in your Mac’s keychain, and only sent over https."
        case nil: return "Ask Hush only shares a page when you ask about it. Conversations aren’t saved."
        }
    }

    @ViewBuilder private func editor(_ draft: AIModel) -> some View {
        let binding = Binding<AIModel>(get: { editing ?? draft }, set: { editing = $0 })
        LabeledContent("Name") { TextField("", text: binding.name).textFieldStyle(.roundedBorder).frame(width: 260) }
        LabeledContent("Address") { TextField("", text: binding.endpoint).textFieldStyle(.roundedBorder).frame(width: 260) }
        LabeledContent("Model") {
            HStack(spacing: 6) {
                if available.isEmpty {
                    TextField(draft.kind == .claude ? "claude-opus-5-5" : "model name", text: binding.model)
                        .textFieldStyle(.roundedBorder).frame(width: 200)
                } else {
                    Picker("", selection: binding.model) {
                        ForEach(available, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                }
                if draft.kind != .claude {
                    Button { Task { available = await AIClient.availableModels(endpoint: binding.wrappedValue.endpoint, key: key) ; if binding.wrappedValue.model.isEmpty, let first = available.first { editing?.model = first } } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("List the models this server offers")
                }
            }
        }
        if draft.kind.needsKey || draft.kind == .openAICompatible {
            LabeledContent("API key") { SecureField(draft.kind == .claude ? "sk-ant-…" : "Key", text: $key).textFieldStyle(.roundedBorder).frame(width: 260) }
        }
        if let problem = (editing ?? draft).endpointProblem {
            Label(problem, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5)).foregroundStyle(.orange)
        }
        HStack {
            Button("Cancel") { editing = nil; key = ""; available = [] }
            Spacer()
            Button("Save") {
                guard let model = editing else { return }
                store.save(model, key: key.isEmpty ? nil : key)
                editing = nil; key = ""; available = []
                test(model)
            }
            .buttonStyle(.borderedProminent)
            .disabled((editing ?? draft).endpointProblem != nil || (editing ?? draft).name.trimmingCharacters(in: .whitespaces).isEmpty
                      || ((editing ?? draft).kind == .claude && key.isEmpty && AIKeys.key(for: editing ?? draft) == nil))
        }
    }

    private func startNew(_ kind: AIModel.Kind) {
        let name: String
        switch kind {
        case .claude: name = "Claude"
        case .ollama: name = "Ollama"
        case .lmStudio: name = "LM Studio"
        case .openAICompatible: name = "My model"
        }
        editing = AIModel(name: name, kind: kind, endpoint: kind.defaultEndpoint, model: kind.defaultModel)
        key = ""
        available = []
        if kind == .ollama || kind == .lmStudio {
            Task {
                available = await AIClient.availableModels(endpoint: kind.defaultEndpoint, key: nil)
                if let first = available.first, editing?.model.isEmpty == true || !(available.contains(editing?.model ?? "")) { editing?.model = first }
            }
        }
    }

    private func startEditing(_ model: AIModel) {
        editing = model
        key = ""
        available = []
    }

    private func test(_ model: AIModel) {
        testing = model.id
        results[model.id] = nil
        Task { @MainActor in
            let problem = await AIClient.test(model)
            results[model.id] = problem.map { "⚠︎ " + $0 } ?? "✓ Working"
            testing = nil
        }
    }
}
