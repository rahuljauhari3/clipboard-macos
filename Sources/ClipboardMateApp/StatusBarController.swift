import AppKit
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let database: ClipboardDatabase

    init(database: ClipboardDatabase) {
        self.database = database
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipboardMate")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 520, height: 560)
        popover.contentViewController = NSHostingController(rootView: MainTabView(database: database, onClose: { [weak self] in
            self?.closePopover(nil)
        }))
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover(_ sender: Any?) {
        popover.performClose(sender)
    }
}

struct MainTabView: View {
    let database: ClipboardDatabase
    let onClose: () -> Void

    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HistoryTab(database: database, onClose: onClose, isActive: Binding(get: { selectedTab == 0 }, set: { _ in }))
                .tabItem { Label("History", systemImage: "list.bullet") }
                .tag(0)
            ChatbotView()
                .tabItem { Label("Chatbot", systemImage: "bubble.left.and.bubble.right") }
                .tag(1)
        }
        .frame(width: 520, height: 560)
    }
}

private struct HistoryTab: View {
    let database: ClipboardDatabase
    let onClose: () -> Void
    @Binding var isActive: Bool

    init(database: ClipboardDatabase, onClose: @escaping () -> Void, isActive: Binding<Bool>) {
        self.database = database
        self.onClose = onClose
        self._isActive = isActive
    }

    var body: some View {
        ContentView(database: database, onClose: onClose, isActiveTab: $isActive)
    }
}

