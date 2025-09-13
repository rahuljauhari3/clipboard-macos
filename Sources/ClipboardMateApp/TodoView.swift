import SwiftUI

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
}

final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = [] {
        didSet { save() }
    }
    
    private let storageKey = "todoItems"
    
    init() {
        load()
    }
    
    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = TodoItem(id: UUID(), title: trimmed, isDone: false)
        items.insert(item, at: 0)
    }
    
    func set(_ id: UUID, done: Bool) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isDone = done
        }
    }
    
    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
    }
    
    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }
    
    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            self.items = decoded
        }
    }
    
    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

struct TodoView: View {
    @StateObject private var store = TodoStore()
    @State private var newTitle: String = ""
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("New to-do…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Add") { add() }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.top, .horizontal])
            
            List {
                ForEach(store.items) { item in
                    TodoRow(
                        item: item,
                        onToggle: { isOn in store.set(item.id, done: isOn) },
                        onDelete: { store.delete(item.id) }
                    )
                }
                .onDelete { offsets in store.delete(at: offsets) }
            }
            .listStyle(.inset)
            .frame(minHeight: 380)
            
            Spacer(minLength: 0)
        }
        .frame(width: 420, height: 520)
        .padding(.bottom)
    }
    
    private func add() {
        let t = newTitle
        newTitle = ""
        store.add(title: t)
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { item.isDone }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Text(item.title)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .textSelection(.enabled)
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
