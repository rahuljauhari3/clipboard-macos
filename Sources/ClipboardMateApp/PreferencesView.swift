import SwiftUI

private let excludedBundleIDsKey = "excludedBundleIDs"

struct PreferencesView: View {
    @State private var excludedBundleIDs: [String] = []
    @State private var newBundleID: String = ""

    init() {
        // Load defaults
        let defaults = UserDefaults.standard
        if let arr = defaults.array(forKey: excludedBundleIDsKey) as? [String] {
            _excludedBundleIDs = State(initialValue: arr)
        } else {
            _excludedBundleIDs = State(initialValue: ["com.apple.keychainaccess"]) // default
        }
    }

    var body: some View {
        Form {
            Section("Global Shortcut") {
                HotkeyRecorderView()
                Text("Default: Command-Shift-C").font(.caption).foregroundStyle(.secondary)
            }

            Section("Excluded Applications") {
                HStack {
                    TextField("Bundle ID (e.g., com.agilebits.onepassword7)", text: $newBundleID)
                    Button("Add") { addBundle() }
                        .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                List {
                    ForEach(excludedBundleIDs, id: \.self) { bundle in
                        HStack {
                            Text(bundle)
                            Spacer()
                            Button(role: .destructive) { remove(bundle) } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                .frame(maxHeight: 160)
                Text("Items copied while these apps are frontmost will be ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: excludedBundleIDs) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: excludedBundleIDsKey)
        }
    }

    private func addBundle() {
        let b = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty, !excludedBundleIDs.contains(b) else { return }
        excludedBundleIDs.append(b)
        newBundleID = ""
    }

    private func remove(_ b: String) {
        excludedBundleIDs.removeAll { $0 == b }
    }
}

