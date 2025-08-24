import AppKit
import SwiftUI
import Carbon

final class HotkeyManager: NSObject {
    static let shared = HotkeyManager()

    // Use Carbon for global hotkeys
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x484b4d31)), id: UInt32(1)) // 'HKM1'

    // Stored shortcut (default: cmd+shift+C)
    private let shortcutUserDefaultsKey = "toggleShortcut"
    var onToggle: (() -> Void)?

    struct Shortcut: Codable, Equatable {
        var keyCode: UInt32 // kVK_ constants
        var modifiers: UInt32 // cmd/option/shift/control mask
    }

    override init() {
        super.init()
        installHandler()
    }

    func registerDefaultToggleShortcut() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: shortcutUserDefaultsKey),
           let sc = try? JSONDecoder().decode(Shortcut.self, from: data) {
            register(sc)
        } else {
            // Default: Command+Shift+C
            let sc = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey) | UInt32(shiftKey))
            save(sc)
            register(sc)
        }
    }

    func save(_ shortcut: Shortcut) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: shortcutUserDefaultsKey)
        }
        register(shortcut)
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (next, event, userData) -> OSStatus in
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if status == noErr {
                if hkID.id == HotkeyManager.shared.hotKeyID.id && hkID.signature == HotkeyManager.shared.hotKeyID.signature {
                    HotkeyManager.shared.handleHotKey()
                }
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
    }

    private func handleHotKey() {
        onToggle?()
    }

    private func register(_ shortcut: Shortcut) {
        // Unregister previous
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        var hotKeyRefLocal: EventHotKeyRef?
        RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRefLocal)
        self.hotKeyRef = hotKeyRefLocal
    }
}

// SwiftUI recorder view to capture a keystroke
struct HotkeyRecorderView: View {
    @State private var recording = false
    @State private var displayText: String = HotkeyRecorderView.currentShortcutDescription()

    var body: some View {
        HStack {
            Text("Toggle history")
            Spacer()
            Button(action: { recording.toggle() }) {
                Text(recording ? "Press keys..." : displayText)
            }
            .keyboardShortcut(.defaultAction)
            .background(KeyCaptureRepresentable(isRecording: $recording) { sc in
                HotkeyManager.shared.save(sc)
                displayText = HotkeyRecorderView.currentShortcutDescription()
                recording = false
            })
        }
    }

    static func currentShortcutDescription() -> String {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "toggleShortcut"),
           let sc = try? JSONDecoder().decode(HotkeyManager.Shortcut.self, from: data) {
            return shortcutToString(sc)
        }
        return "⌘⇧C"
    }

    static func shortcutToString(_ sc: HotkeyManager.Shortcut) -> String {
        var parts: [String] = []
        if sc.modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if sc.modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if sc.modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if sc.modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        let key = keyCodeToString(sc.keyCode)
        parts.append(key)
        return parts.joined()
    }

    static func keyCodeToString(_ keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_C): return "C"
        default: return String(format: "0x%02X", keyCode)
        }
    }
}

// NSViewRepresentable to capture next key combo when recording
struct KeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (HotkeyManager.Shortcut) -> Void

    func makeNSView(context: Context) -> NSView {
        return context.coordinator.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isRecording = isRecording
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject {
        let view = NSView(frame: .zero)
        var monitor: Any?
        var isRecording: Bool = false {
            didSet { updateMonitor() }
        }
        let onCapture: (HotkeyManager.Shortcut) -> Void
        init(onCapture: @escaping (HotkeyManager.Shortcut) -> Void) { self.onCapture = onCapture }

        func updateMonitor() {
            if isRecording {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let sc = HotkeyManager.Shortcut(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags.carbonFlags)
                    self.onCapture(sc)
                    return nil
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

