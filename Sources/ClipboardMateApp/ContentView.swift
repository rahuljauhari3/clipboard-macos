import SwiftUI
import AppKit
import Carbon

struct ContentView: View {
    @ObservedObject private var viewModel: ContentViewModel
    let onClose: () -> Void
    @Binding var isActiveTab: Bool

    @State private var search: String = ""
    @State private var selection: ClipboardItem.ID?

    init(database: ClipboardDatabase, onClose: @escaping () -> Void, isActiveTab: Binding<Bool>) {
        self.viewModel = ContentViewModel(database: database)
        self.onClose = onClose
        self._isActiveTab = isActiveTab
        self._selection = State(initialValue: nil)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search...", text: $search, onCommit: {
                    viewModel.refresh(query: search)
                }).textFieldStyle(.roundedBorder)
                Button("Clear All") {
                    viewModel.clearAll()
                }.disabled(viewModel.items.isEmpty)
            }
            .padding([.top, .horizontal])

            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(viewModel.items) { item in
                        ClipboardRow(item: item)
                            .contentShape(Rectangle())
                            .tag(item.id)
                            .id(item.id)
                            .onTapGesture {
                                viewModel.copy(item)
                                onClose()
                            }
                            .contextMenu {
                                Button("Copy") { viewModel.copy(item); onClose() }
                                Button(role: .destructive) { viewModel.delete(item) } label: { Text("Delete") }
                            }
                    }
                    .onDelete { indexSet in
                        indexSet.map { viewModel.items[$0] }.forEach(viewModel.delete)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 380)
                .onChange(of: selection) { _, newValue in
                    if let id = newValue {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Preferences...") { openPreferences() }
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 420, height: 520)
        .onAppear { viewModel.refresh(query: "") }
        .onChange(of: search) { oldValue, newValue in
            viewModel.refresh(query: newValue)
        }
        .onChange(of: viewModel.items) { _, newItems in
            // Maintain selection if possible; otherwise select first item
            if let sel = selection, newItems.contains(where: { $0.id == sel }) {
                // keep current selection
            } else {
                selection = newItems.first?.id
            }
        }
        .background(
            KeyboardHandlerRepresentable(
                isEnabled: isActiveTab,
                onUp: { moveSelection(-1) },
                onDown: { moveSelection(1) },
                onEnter: { copySelectionAndClose() }
            )
        )
    }

    private func openPreferences() {
        PreferencesWindowManager.shared.show()
    }

    private func moveSelection(_ delta: Int) {
        guard !viewModel.items.isEmpty else { return }
        if let current = selection, let idx = viewModel.items.firstIndex(where: { $0.id == current }) {
            let newIndex = max(0, min(viewModel.items.count - 1, idx + delta))
            selection = viewModel.items[newIndex].id
        } else {
            selection = viewModel.items.first?.id
        }
    }

    private func copySelectionAndClose() {
        guard let sel = selection, let item = viewModel.items.first(where: { $0.id == sel }) else { return }
        viewModel.copy(item)
        onClose()
    }
}

final class ContentViewModel: ObservableObject {
    private let database: ClipboardDatabase
    @Published var items: [ClipboardItem] = []
    private var currentQuery: String = ""
    private var observer: Any?

    init(database: ClipboardDatabase) {
        self.database = database
        observer = NotificationCenter.default.addObserver(forName: .clipboardDatabaseDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.items = (try? self.database.recentItems(matching: self.currentQuery)) ?? []
        }
        refresh(query: "")
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh(query: String) {
        currentQuery = query
        items = (try? database.recentItems(matching: query)) ?? []
    }

    func delete(_ item: ClipboardItem) {
        try? database.deleteItem(id: item.id)
    }

    func clearAll() {
        try? database.clearAll()
    }

    func copy(_ item: ClipboardItem) {
        ClipboardService.copyToClipboard(item: item)
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch item.contentType {
            case .text:
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                Text(item.text ?? "")
                    .lineLimit(3)
            case .image:
                if let data = item.imagePNG, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .cornerRadius(6)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.createdAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// Capture arrow/enter in history, and optionally Ctrl+Tab for tab switching
struct KeyboardHandlerRepresentable: NSViewRepresentable {
    var isEnabled: Bool
    // Optional handlers: if nil, the key will be ignored and passed through
    var onUp: (() -> Void)? = nil
    var onDown: (() -> Void)? = nil
    var onEnter: (() -> Void)? = nil
    // Optional tab switching handlers
    var onCtrlTab: (() -> Void)? = nil
    var onCtrlShiftTab: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        context.coordinator.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setEnabled(isEnabled)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUp: onUp, onDown: onDown, onEnter: onEnter, onCtrlTab: onCtrlTab, onCtrlShiftTab: onCtrlShiftTab)
    }

    final class Coordinator: NSObject {
        let view = NSView(frame: .zero)
        private var monitor: Any?
        private var enabled: Bool = false
        let onUp: (() -> Void)?
        let onDown: (() -> Void)?
        let onEnter: (() -> Void)?
        let onCtrlTab: (() -> Void)?
        let onCtrlShiftTab: (() -> Void)?

        init(onUp: (() -> Void)?, onDown: (() -> Void)?, onEnter: (() -> Void)?, onCtrlTab: (() -> Void)?, onCtrlShiftTab: (() -> Void)?) {
            self.onUp = onUp
            self.onDown = onDown
            self.onEnter = onEnter
            self.onCtrlTab = onCtrlTab
            self.onCtrlShiftTab = onCtrlShiftTab
            super.init()
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        func setEnabled(_ enabled: Bool) {
            guard self.enabled != enabled else { return }
            self.enabled = enabled
            if enabled {
                installMonitor()
            } else {
                if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            }
        }

        private func installMonitor() {
            if monitor != nil { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                // Only handle if app is active and a window is key
                guard NSApp.isActive, NSApp.keyWindow != nil else { return event }

                // Handle Ctrl+Tab / Ctrl+Shift+Tab for tab switching
                if Int(event.keyCode) == kVK_Tab && event.modifierFlags.contains(.control) {
                    if event.modifierFlags.contains(.shift) {
                        if let onCtrlShiftTab { onCtrlShiftTab(); return nil }
                    } else {
                        if let onCtrlTab { onCtrlTab(); return nil }
                    }
                    return event
                }

                // Allow arrow/enter keys to work even when focus is in a text field
                switch Int(event.keyCode) {
                case kVK_UpArrow:
                    if let onUp { onUp(); return nil } else { return event }
                case kVK_DownArrow:
                    if let onDown { onDown(); return nil } else { return event }
                case kVK_Return, kVK_ANSI_KeypadEnter:
                    if let onEnter { onEnter(); return nil } else { return event }
                default:
                    return event
                }
            }
        }
    }
}

