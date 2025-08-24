import SwiftUI
import AppKit

@main
struct ClipboardMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
        .commands {
            // Add Command+Q to quit the app even though we're an LSUIElement app
            CommandGroup(replacing: .appTermination) {
                Button("Quit ClipboardMate") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var database: ClipboardDatabase!
    private var monitor: ClipboardMonitor!

    func applicationWillTerminate(_ notification: Notification) {
        // Clear in-memory Groq API key on exit
        GroqSession.shared.apiKey = nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        database = try? ClipboardDatabase()
        statusBarController = StatusBarController(database: database)
        monitor = ClipboardMonitor(database: database)
        monitor.start()

        HotkeyManager.shared.onToggle = { [weak self] in
            self?.statusBarController.togglePopover(self)
        }
        HotkeyManager.shared.registerDefaultToggleShortcut()
    }
}

