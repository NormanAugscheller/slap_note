import AppKit
import SwiftUI

/// Hosts the SwiftUI settings in a normal window. Closing it keeps the app running.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "SlapNote Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SlapNoteSettings")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(intro: Bool) {
        guard let window else { return }
        let view = SettingsView(settings: settings, showIntro: intro)
        window.contentView = NSHostingView(rootView: view)
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
