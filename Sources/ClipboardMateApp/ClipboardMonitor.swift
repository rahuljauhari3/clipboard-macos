import AppKit
import Combine
import CryptoKit

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var timer: Timer?
    private let database: ClipboardDatabase
    private let userDefaults = UserDefaults.standard

    // Keys
    private let excludedBundleIDsKey = "excludedBundleIDs"

    // Simple duplicate prevention: remember last seen signature
    private var lastSignature: String?

    init(database: ClipboardDatabase) {
        self.database = database
        self.changeCount = pasteboard.changeCount
        // Set default excluded apps
        if userDefaults.array(forKey: excludedBundleIDsKey) == nil {
            userDefaults.set(["com.apple.keychainaccess"], forKey: excludedBundleIDsKey)
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount

        // Skip if source app is excluded or is our own app
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if bundleID == Bundle.main.bundleIdentifier { return }
            if isExcluded(bundleIdentifier: bundleID) { return }
        }

        guard let types = pasteboard.types else { return }

        if types.contains(.png) || types.contains(.tiff) {
            if let image = NSImage(pasteboard: pasteboard), let data = image.pngData() {
                let sig = signatureForImage(data)
                guard sig != lastSignature else { return }
                lastSignature = sig
                try? database.addImage(data)
            }
        } else if types.contains(.string) {
            if let str = pasteboard.string(forType: .string), !str.isEmpty {
                let sig = signatureForText(str)
                guard sig != lastSignature else { return }
                lastSignature = sig
                try? database.addText(str)
            }
        }
    }

    private func isExcluded(bundleIdentifier: String) -> Bool {
        let list = userDefaults.array(forKey: excludedBundleIDsKey) as? [String] ?? []
        return list.contains(bundleIdentifier)
    }

    private func signatureForText(_ text: String) -> String {
        let data = Data(text.utf8)
        return signatureForData(data, prefix: "text:")
    }

    private func signatureForImage(_ data: Data) -> String {
        return signatureForData(data, prefix: "img:")
    }

    private func signatureForData(_ data: Data, prefix: String) -> String {
        let digest = SHA256.hash(data: data)
        return prefix + digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

