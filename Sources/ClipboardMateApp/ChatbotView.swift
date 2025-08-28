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
                            ChatMessageRow(
                                message: msg,
                                markdownRenderer: { content in markdownText(content) },
                                onCopyCode: { code in ClipboardService.copyTextToClipboard(code) }
                            )
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

// Renders a single chat message with Markdown text and code blocks that include a copy button
private struct ChatMessageRow: View {
    let message: GroqChatMessage
    let markdownRenderer: (String) -> Text
    let onCopyCode: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message.role == .user ? "You:" : "Bot:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segments.indices, id: \.self) { i in
                    let segment = segments[i]
                    switch segment {
                    case .text(let t):
                        markdownRenderer(t)
                            .textSelection(.enabled)
                            .lineSpacing(3)
                    case .code(let lang, let code):
                        CodeBlockView(code: code, language: lang) {
                            onCopyCode(code)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var segments: [Segment] {
        Self.parseSegments(message.content)
    }

    private enum Segment {
        case text(String)
        case code(language: String?, code: String)
    }

    private static func parseSegments(_ content: String) -> [Segment] {
        var result: [Segment] = []
        var rest = content[...]

        while let fenceStart = rest.range(of: "```") {
            let before = String(rest[..<fenceStart.lowerBound])
            if !before.isEmpty { result.append(.text(before)) }

            var after = rest[fenceStart.upperBound...]
            // Read language identifier (until first newline if present)
            var language: String? = nil
            if let newline = after.firstIndex(of: "\n") {
                let langToken = String(after[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
                language = langToken.isEmpty ? nil : langToken
                after = after[after.index(after.startIndex, offsetBy: after.distance(from: after.startIndex, to: newline) + 1)...]
            } else {
                // No newline after fence; treat remainder as code
                let code = String(after)
                result.append(.code(language: nil, code: code))
                rest = ""[...]
                break
            }

            if let fenceEnd = after.range(of: "```") {
                let code = String(after[..<fenceEnd.lowerBound])
                result.append(.code(language: language, code: code.trimmingCharacters(in: .whitespacesAndNewlines)))
                rest = after[fenceEnd.upperBound...]
            } else {
                // Unterminated code block -> take rest as code
                let code = String(after)
                result.append(.code(language: language, code: code.trimmingCharacters(in: .whitespacesAndNewlines)))
                rest = ""[...]
                break
            }
        }

        if !rest.isEmpty {
            result.append(.text(String(rest)))
        }
        return result
    }
}

private struct CodeBlockView: View {
    let code: String
    let language: String?
    var onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.06))
            )
            .cornerRadius(6)

            HStack(spacing: 6) {
                if copied {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: {
                    onCopy()
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeInOut(duration: 0.15)) { copied = false }
                    }
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .padding(6)
        }
    }
}

