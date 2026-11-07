import AppKit
import ApplicationServices

/// Reads the selected text of the frontmost app by synthesizing ⌘C, then restores the pasteboard.
/// Needs the Accessibility permission (posting keyboard events). Never logs pasteboard contents.
enum SelectionGrabber {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds SlapNote to the Accessibility list and links to System Settings.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// One pasteboard item with all of its representations.
    private struct SavedItem {
        var representations: [(NSPasteboard.PasteboardType, Data)]
    }

    /// Calls `completion` with the selected text, or nil if nothing was selected / copying failed.
    static func grabSelection(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount

        guard postCopyShortcut() else {
            completion(nil)
            return
        }
        // Poll for the copy to land (apps answer ⌘C asynchronously). Give up after ~0.5 s.
        poll(pasteboard: pasteboard, before: before, attempts: 25) { changed in
            var text: String?
            if changed {
                text = pasteboard.string(forType: .string)
                restore(saved, to: pasteboard)
            }
            completion(text)
        }
    }

    private static func poll(pasteboard: NSPasteboard, before: Int, attempts: Int, done: @escaping (Bool) -> Void) {
        if pasteboard.changeCount != before {
            done(true)
            return
        }
        guard attempts > 0 else {
            done(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            poll(pasteboard: pasteboard, before: before, attempts: attempts - 1, done: done)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [SavedItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            SavedItem(representations: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    private static func restore(_ items: [SavedItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { saved in
            let item = NSPasteboardItem()
            for (type, data) in saved.representations { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }

    /// Posts ⌘C with only the Command flag set, so the still-held ⌃⌥ of the shortcut does not leak in.
    private static func postCopyShortcut() -> Bool {
        let keyC: CGKeyCode = 8 // kVK_ANSI_C
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// Short explanation shown the first time "Note from selection" is used without the permission.
final class AccessibilityExplanationWindow: NSWindowController {
    convenience init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Allow Note from Selection"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let title = NSTextField(wrappingLabelWithString: "SlapNote needs the Accessibility permission to copy the selected text from the app you are using.")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: "It only uses it for “Note from selection”: SlapNote presses ⌘C for you, reads the text and puts your clipboard back. Turn on SlapNote in System Settings › Privacy & Security › Accessibility, then press the shortcut again.")
        body.textColor = .secondaryLabelColor
        let open = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        open.keyEquivalent = "\r"
        open.controlSize = .large
        let cancel = NSButton(title: "Not Now", target: self, action: #selector(dismiss))
        cancel.keyEquivalent = "\u{1b}"
        cancel.controlSize = .large

        let buttons = NSStackView(views: [cancel, open])
        buttons.spacing = 8
        let stack = NSStackView(views: [title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.setCustomSpacing(24, after: body)
        buttons.setHuggingPriority(.required, for: .vertical)
        window.contentView = stack
        title.preferredMaxLayoutWidth = 392
        body.preferredMaxLayoutWidth = 392
    }

    func present() {
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        SelectionGrabber.requestTrust()
        NSWorkspace.shared.open(SelectionGrabber.accessibilitySettingsURL)
        close()
    }

    @objc private func dismiss() {
        close()
    }
}
