import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var viewModel: ContentViewModel
    let onClose: () -> Void

    @State private var search: String = ""

    init(database: ClipboardDatabase, onClose: @escaping () -> Void) {
        self.viewModel = ContentViewModel(database: database)
        self.onClose = onClose
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

            List {
                ForEach(viewModel.items) { item in
                    ClipboardRow(item: item)
                        .contentShape(Rectangle())
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
    }

    private func openPreferences() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
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

