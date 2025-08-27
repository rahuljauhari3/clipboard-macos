import SwiftUI

struct ChatbotView: View {
    @State private var models: [GroqModel] = []
    @State private var selectedModel: GroqModel?
    @State private var useWebSearch: Bool = false
    @State private var input: String = ""
    @State private var messages: [GroqChatMessage] = []
    @State private var loading: Bool = false
    @State private var errorText: String?

    // Inline API key handling when missing
    @State private var hasAPIKey: Bool = (GroqSession.shared.apiKey?.isEmpty == false) || (ProcessInfo.processInfo.environment["GROQ_API_KEY"]?.isEmpty == false)
    @State private var newAPIKey: String = ""
    @State private var saveFeedback: String?

    var body: some View {
        VStack(spacing: 12) {
            if !hasAPIKey {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Groq API Key Required").font(.headline)
                    Text("Enter your GROQ_API_KEY to use the chatbot. You can also set this in Preferences.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("GROQ_API_KEY", text: $newAPIKey)
                            .onSubmit { saveAPIKeyInline() }
                        Button("Save") { saveAPIKeyInline() }
                            .disabled(newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let saveFeedback { Text(saveFeedback).font(.caption).foregroundStyle(.secondary) }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                Spacer()
            } else {
                HStack(spacing: 8) {
                    Picker("Model", selection: Binding(
                        get: { selectedModel?.id ?? "" },
                        set: { id in selectedModel = models.first { $0.id == id } }
                    )) {
                        ForEach(filteredModels(), id: \.id) { m in
                            Text(m.id).tag(m.id)
                        }
                    }
                    .frame(maxWidth: 280)

                    Toggle("Search Web", isOn: $useWebSearch)
                        .onChange(of: useWebSearch) { _, _ in
                            // If currently selected model doesn't support web search while enabled, clear selection
                            if useWebSearch, let sel = selectedModel, !sel.supportsWebSearch {
                                selectedModel = filteredModels().first
                            }
                        }

                    Spacer()
                    Button("Clear Chat") { messages.removeAll() }
                        .disabled(messages.isEmpty)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            HStack(alignment: .top) {
                                Text(msg.role == .user ? "You:" : "Bot:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                markdownText(msg.content)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                        }
                        if let errorText { Text(errorText).foregroundStyle(.red).font(.caption) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

            HStack(alignment: .center) {
                    TextField("Ask something...", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }
                    Button(action: send) {
                        if loading { ProgressView() } else { Text("Send") }
                    }
                    .disabled(loading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedModel == nil)
                }
            }
        }
        .padding()
        .onAppear { Task { await loadModelsIfPossible() } }
    }

    private func filteredModels() -> [GroqModel] {
        if useWebSearch { return models.filter { $0.supportsWebSearch } }
        return models
    }

    private func loadModelsIfPossible() async {
        guard hasAPIKey else { return }
        do {
            let fetched = try await GroqClient.shared.fetchModels()
            await MainActor.run {
                self.models = fetched
                if selectedModel == nil { self.selectedModel = fetched.first }
            }
        } catch {
            await MainActor.run { self.errorText = error.localizedDescription }
        }
    }

    private func send() {
        guard hasAPIKey else { return }
        guard let modelId = selectedModel?.id else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMsg = GroqChatMessage(role: .user, content: trimmed)
        let newMessages = messages + [userMsg]
        messages = newMessages
        input = ""
        loading = true
        errorText = nil
        Task {
            do {
                let reply = try await GroqClient.shared.chat(messages: newMessages, model: modelId, useWebSearch: useWebSearch)
                await MainActor.run {
                    messages.append(GroqChatMessage(role: .assistant, content: reply))
                    loading = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    loading = false
                }
            }
        }
    }

    private func saveAPIKeyInline() {
        let trimmed = newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        GroqSession.shared.apiKey = trimmed
        hasAPIKey = true
        saveFeedback = "Saved for this session"
        Task { await loadModelsIfPossible() }
    }

    // Lightweight helper to parse Markdown once, reducing type-checker complexity in the body
    private func markdownText(_ content: String) -> Text {
        var options = AttributedString.MarkdownParsingOptions()
        options.allowsExtendedAttributes = true
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let attributed = try? AttributedString(markdown: content, options: options) {
            return Text(attributed)
        } else {
            return Text(content)
        }
    }
}

