import SwiftUI
import Foundation

struct ChatbotView: View {
    @Binding var isActiveTab: Bool

    // Chat input history navigation state
    @FocusState private var inputFocused: Bool
    @State private var historyCursor: Int = -1 // -1 = not navigating history
    @State private var draftBeforeHistory: String = "" // store current input before entering history

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

    init(isActiveTab: Binding<Bool>) {
        self._isActiveTab = isActiveTab
    }

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
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("Model", selection: Binding(
                            get: { selectedModel?.id ?? "" },
                            set: { id in 
                                selectedModel = filteredModels().first { $0.id == id }
                            }
                        )) {
                            Text("Select Model").tag("")
                            ForEach(filteredModels(), id: \.id) { m in
                                Text(m.id).tag(m.id)
                            }
                        }
                        .frame(maxWidth: 280)
                        .disabled(filteredModels().isEmpty)

                        Toggle("Search Web", isOn: $useWebSearch)
                            .onChange(of: useWebSearch) { _, newValue in
                                let filtered = filteredModels()
                                // If currently selected model doesn't support web search while enabled, switch to first available
                                if newValue {
                                    if let sel = selectedModel, !sel.supportsWebSearch {
                                        selectedModel = filtered.first
                                    }
                                } else {
                                    // When disabling web search, keep selection if still valid
                                    if let sel = selectedModel, !filtered.contains(where: { $0.id == sel.id }) {
                                        selectedModel = filtered.first
                                    }
                                }
                            }

                        Spacer()
                        Button("Clear Chat") { messages.removeAll() }
                            .disabled(messages.isEmpty)
                    }
                    
                    if useWebSearch && filteredModels().isEmpty {
                        Text("No models with web search available. Only 'compound-beta' and 'compound-beta-mini' support web search.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                    ChatMessageRow(
                                    message: msg,
                                    markdownRenderer: { content in markdownText(content) },
                                    onCopyCode: { code in ClipboardService.copyTextToClipboard(code) },
                                    onCopyMessage: { if msg.role == .assistant { ClipboardService.copyTextToClipboard(msg.content) } }
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
                        .focused($inputFocused)
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
        .background(
            KeyboardHandlerRepresentable(
                isEnabled: isActiveTab && inputFocused,
                onUp: { navigateInputHistoryUp() },
                onDown: { navigateInputHistoryDown() }
            )
        )
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
                // Set initial selection based on current web search state
                if selectedModel == nil || !fetched.contains(where: { $0.id == selectedModel?.id }) {
                    self.selectedModel = filteredModels().first
                }
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
        // Reset history navigation after sending
        historyCursor = -1
        draftBeforeHistory = ""
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
        // Normalize minor LLM formatting quirks (paragraph breaks, conservative punctuation),
        // then parse with full Markdown to improve headings/lists/paragraphs rendering.
        let normalized = normalizeMarkdown(content)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: normalized, options: options) {
            return Text(attributed)
        }
        return Text(verbatim: normalized)
    }

    // Heuristic normalizer for bot replies to improve paragraph breaks and missing terminal punctuation
    private func normalizeMarkdown(_ content: String) -> String {
        // Leave fenced code blocks intact; only normalize plain text around them.
        let s = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var output: [String] = []
        var cursor = s.startIndex
        while cursor < s.endIndex {
            if let fenceRange = s[cursor...].range(of: "```") {
                // Normalize text before the fence
                let before = String(s[cursor..<fenceRange.lowerBound])
                output.append(normalizeParagraphs(before))
                // Capture fenced block verbatim (including trailing fence)
                var after = s[fenceRange.upperBound...]
                if let fenceEnd = after.range(of: "```") {
                    output.append("```" + String(after[..<fenceEnd.lowerBound]) + "```")
                    cursor = fenceEnd.upperBound
                } else {
                    // Unterminated fence: take the rest as code
                    output.append("```" + String(after))
                    cursor = s.endIndex
                }
            } else {
                // No more fences: normalize the rest
                let tail = String(s[cursor...])
                output.append(normalizeParagraphs(tail))
                cursor = s.endIndex
            }
        }
        // Collapse 3+ blank lines into max 2
        let joined = output.joined()
        let lines = joined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var compact: [String] = []
        var emptyStreak = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyStreak += 1
                if emptyStreak <= 2 { compact.append("") }
            } else {
                emptyStreak = 0
                compact.append(line)
            }
        }
        return compact.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeParagraphs(_ text: String) -> String {
        // Build paragraphs by joining adjacent non-special lines; insert blank lines between paragraphs.
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var result: [String] = []
        var para: [String] = []

        func flushParagraph() {
            guard !para.isEmpty else { return }
            var joined = para.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            joined = ensureSpaceAfterPunctuation(joined)
            joined = ensureTerminalPunctuation(joined)
            result.append(joined)
            result.append("") // blank line between paragraphs
            para.removeAll()
        }

        for line in rawLines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                flushParagraph()
                continue
            }
            if isSpecialMarkdownLine(t) {
                flushParagraph()
                result.append(t)
                result.append("")
            } else {
                para.append(t)
            }
        }
        flushParagraph()

        // Remove trailing blank line if present
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty { result.removeLast() }
        return result.joined(separator: "\n") + (result.isEmpty ? "" : "\n")
    }

    private func isSpecialMarkdownLine(_ t: String) -> Bool {
        return isHeading(t) || isListStart(t) || isBlockquote(t) || looksLikeTableRow(t) || isHorizontalRule(t)
    }

    private func isHeading(_ t: String) -> Bool { t.hasPrefix("#") }
    private func isBlockquote(_ t: String) -> Bool { t.hasPrefix(">") }
    private func isHorizontalRule(_ t: String) -> Bool {
        let trimmed = t.replacingOccurrences(of: " ", with: "")
        return trimmed.allSatisfy { $0 == "-" } && trimmed.count >= 3
    }
    private func isListStart(_ t: String) -> Bool {
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
        // Numbered lists: 1. or 1)
        var digits = 0
        for ch in t { if ch.isNumber { digits += 1 } else { break } }
        if digits > 0 && t.count > digits {
            let idx = t.index(t.startIndex, offsetBy: digits)
            let ch = t[idx]
            if ch == "." || ch == ")" { return true }
        }
        return false
    }
    private func looksLikeTableRow(_ t: String) -> Bool {
        // A conservative check: treat pipe-separated lines as table candidates.
        // Avoid matching inline code by skipping lines that start with four spaces or a tab.
        if t.hasPrefix("    ") || t.hasPrefix("\t") { return false }
        return t.contains("|")
    }

    private func ensureTerminalPunctuation(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return s }
        // Skip if the line already ends with obvious punctuation or a closing pair after punctuation
        let terminalPunct: Set<Character> = [".", "!", "?", ";", ":", "…"]
        if let last = trimmed.last, terminalPunct.contains(last) { return trimmed }
        // Avoid adding punctuation to lines that likely aren't sentences
        if isHeading(trimmed) || isListStart(trimmed) || isBlockquote(trimmed) || looksLikeTableRow(trimmed) { return trimmed }
        // Require at least one alphabetic character
        if trimmed.rangeOfCharacter(from: .letters) == nil { return trimmed }
        // If ends with a closing bracket/quote, inspect preceding char
        let closers: Set<Character> = [")", "]", "}", "\"", "'", "”", "’"]
        if let last = trimmed.last, closers.contains(last) {
            let before = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
            if let b = before.last, terminalPunct.contains(b) { return trimmed }
            return trimmed + "."
        }
        // Ends with alphanumeric -> add a period
        if let scalar = trimmed.unicodeScalars.last, CharacterSet.alphanumerics.contains(scalar) {
            return trimmed + "."
        }
        return trimmed
    }

    // Ensure a single space after sentence punctuation inside a paragraph, without touching URLs, numbers, or code.
    private func ensureSpaceAfterPunctuation(_ s: String) -> String {
        let closers: Set<Character> = [")", "]", "}", "\"", "'", "”", "’"]
        let punctuation: Set<Character> = [".", "!", "?", ";", ":"]
        let skipNext: Set<Character> = [".", "!", "?", ";", ":", ","]
        
        var result = s
        
        // First pass: handle punctuation marks
        let chars = Array(result)
        var out: String = ""
        out.reserveCapacity(chars.count + 16)
        for i in chars.indices {
            let c = chars[i]
            out.append(c)
            guard punctuation.contains(c) else { continue }
            let hasNext = i < chars.count - 1
            if !hasNext { continue }
            let next = chars[i + 1]
            // If already spaced or followed by a closing mark or another punctuation, skip
            if next.isWhitespace || closers.contains(next) || skipNext.contains(next) { continue }
            // Special cases
            if c == "." {
                // Avoid decimals like 3.14 and ellipsis ...
                let hasPrev = i > 0
                if hasPrev {
                    let prev = chars[i - 1]
                    if prev.isNumber && next.isNumber { continue }
                    if prev == "." { continue } // part of ellipsis
                }
            } else if c == ":" {
                // Avoid URLs like http:// and times like 10:30
                if i + 2 < chars.count && chars[i + 1] == "/" && chars[i + 2] == "/" { continue }
                let hasPrev = i > 0
                if hasPrev {
                    let prev = chars[i - 1]
                    if prev.isNumber && next.isNumber { continue }
                }
            }
            out.append(" ")
        }
        result = out
        
        // Second pass: ensure space after emoji if followed by text
        // This handles cases like "👋What's" -> "👋 What's"
        var finalResult = ""
        finalResult.reserveCapacity(result.count + 8)
        var lastWasEmoji = false
        for scalar in result.unicodeScalars {
            let isEmoji = scalar.properties.isEmoji && scalar.properties.isEmojiPresentation
            if lastWasEmoji && !scalar.properties.isWhitespace && !isEmoji {
                // Previous was emoji, current is non-whitespace non-emoji -> add space
                finalResult.append(" ")
            }
            finalResult.append(Character(scalar))
            lastWasEmoji = isEmoji
        }
        
        return finalResult
    }

    // MARK: - Input history navigation
    private var userQuestionsRecentFirst: [String] {
        // Most recent user messages first
        let users = messages.compactMap { $0.role == .user ? $0.content : nil }
        return Array(users.reversed())
    }

    private func navigateInputHistoryUp() {
        let history = userQuestionsRecentFirst
        guard !history.isEmpty else { return }
        if historyCursor == -1 { draftBeforeHistory = input }
        let next = min(historyCursor + 1, history.count - 1)
        guard next != historyCursor else { return }
        historyCursor = next
        input = history[next]
    }

    private func navigateInputHistoryDown() {
        let history = userQuestionsRecentFirst
        guard !history.isEmpty else { return }
        if historyCursor > 0 {
            historyCursor -= 1
            input = history[historyCursor]
        } else if historyCursor == 0 {
            historyCursor = -1
            input = draftBeforeHistory
        } else {
            // Not in history; nothing to do
        }
    }
}

// Renders a single chat message with Markdown text and code blocks that include a copy button
private struct ChatMessageRow: View {
    let message: GroqChatMessage
    let markdownRenderer: (String) -> Text
    let onCopyCode: (String) -> Void
    let onCopyMessage: () -> Void

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
                        // Split non-code text into sub-segments so Markdown tables render beautifully
                        let subs = parseNonCodeSubsegments(t)
                        ForEach(subs.indices, id: \.self) { j in
                            let s = subs[j]
                            switch s {
                            case .markdown(let md):
                                markdownRenderer(md)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                            case .table(let table):
                                MarkdownTableView(model: table)
                            }
                        }
                    case .code(let lang, let code):
                        CodeBlockView(code: code, language: lang) {
                            onCopyCode(code)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if message.role == .assistant {
                Button(action: onCopyMessage) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy entire answer")
            }
        }
    }

    private var segments: [Segment] {
        Self.parseSegments(message.content)
    }

    private enum Segment {
        case text(String)
        case code(language: String?, code: String)
    }

    // Sub-segments inside a text block: plain Markdown text or a parsed Markdown table
    private enum RichTextSegment {
        case markdown(String)
        case table(MarkdownTableModel)
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

    // Split a non-code text block into Markdown text and Markdown-style tables
    private func parseNonCodeSubsegments(_ text: String) -> [RichTextSegment] {
        var output: [RichTextSegment] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        var currentMarkdownChunk = ""

        func flushMarkdown() {
            if !currentMarkdownChunk.isEmpty {
                output.append(.markdown(currentMarkdownChunk))
                currentMarkdownChunk = ""
            }
        }

        while i < lines.count {
            // Detect a table: header line with pipes, followed by a delimiter line like ---|:---:|---
            if i + 1 < lines.count,
               lines[i].contains("|") && Self.isDelimiterLine(lines[i+1]) {
                // Gather table block
                let header = lines[i]
                let delimiter = lines[i+1]
                var rows: [String] = []
                var j = i + 2
                while j < lines.count, lines[j].contains("|") && !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(lines[j])
                    j += 1
                }
                flushMarkdown()
                let model = Self.parseTableBlock(headerLine: header, delimiterLine: delimiter, rowLines: rows)
                output.append(.table(model))
                i = j
            } else {
                currentMarkdownChunk += (currentMarkdownChunk.isEmpty ? "" : "\n") + lines[i]
                i += 1
            }
        }
        flushMarkdown()
        return output
    }
    // MARK: - Markdown table parsing helpers
    struct MarkdownTableModel: Identifiable {
        let id = UUID()
        var headers: [String]?
        var alignments: [MarkdownTableAlignment]
        var rows: [[String]]
    }

    enum MarkdownTableAlignment { case left, center, right }

    private static func isDelimiterLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") || trimmed.contains("-") else { return false }
        // Allowed chars: | - : and whitespace
        let allowed = CharacterSet(charactersIn: "|-: ")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) } && trimmed.contains("-")
    }

    private static func parseTableBlock(headerLine: String, delimiterLine: String, rowLines: [String]) -> MarkdownTableModel {
        func splitCells(_ s: String) -> [String] {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.split(separator: "|", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        func alignmentForSpec(_ spec: String) -> MarkdownTableAlignment {
            let t = spec.trimmingCharacters(in: .whitespaces)
            let left = t.hasPrefix(":")
            let right = t.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            return .left
        }

        let headers = splitCells(headerLine)
        let delims = splitCells(delimiterLine)
        let aligns: [MarkdownTableAlignment] = delims.map(alignmentForSpec)
        let rows = rowLines.map(splitCells)
        return MarkdownTableModel(headers: headers, alignments: aligns, rows: rows)
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

// Nicely styled renderer for Markdown tables
private struct MarkdownTableView: View {
    let model: ChatMessageRow.MarkdownTableModel

    private func alignment(_ a: ChatMessageRow.MarkdownTableAlignment) -> Alignment {
        switch a { case .left: return .leading; case .center: return .center; case .right: return .trailing }
    }

    private var columnCount: Int {
        max(model.headers?.count ?? 0, model.rows.map { $0.count }.max() ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let headers = model.headers {
                Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { c in
                            let text = c < headers.count ? headers[c] : ""
                            Text(text)
                                .font(.caption)
                                .bold()
                                .frame(maxWidth: .infinity, alignment: alignment(model.alignments.indices.contains(c) ? model.alignments[c] : .left))
                                .padding(.vertical, 6)
                        }
                    }
                }
                .background(Color.black.opacity(0.04))
            }

            // Rows
            Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(model.rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { c in
                            let text = c < model.rows[r].count ? model.rows[r][c] : ""
                            Text(text)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: alignment(model.alignments.indices.contains(c) ? model.alignments[c] : .left))
                                .padding(.vertical, 4)
                        }
                    }
                    .background(r.isMultiple(of: 2) ? Color.clear : Color.black.opacity(0.02))
                }
            }
        }
        .padding(8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(0.06))
        )
        .cornerRadius(6)
    }
}

