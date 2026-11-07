import AppKit
import ApplicationServices
import SlapNoteCore

/// Reads the selected text of the frontmost app. Needs the Accessibility permission.
///
/// 1. Directly through Accessibility (`kAXSelectedTextAttribute` of the focused element). This never
///    touches the pasteboard.
/// 2. Only if the app does not expose its selection that way: synthesize ⌘C and read the pasteboard,
///    then put the previous contents back. See `CopyFallback` for when it reads and restores.
///
/// Never logs selection or pasteboard contents.
enum SelectionGrabber {
    enum Result: Equatable {
        case text(String)
        /// Nothing is selected (or the app copied nothing).
        case nothing
        /// SlapNote could not grab the selection without risking the user's clipboard.
        case failed
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds SlapNote to the Accessibility list and links to System Settings.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// One grab at a time: a second shortcut press while the first waits for its copy is ignored,
    /// so it can never snapshot the first grab's copy and "restore" it.
    private static var inProgress = false

    /// Starts a grab. Returns false (and never calls `completion`) if one is already running.
    @discardableResult
    static func grabSelection(completion: @escaping (Result) -> Void) -> Bool {
        guard !inProgress else { return false }
        inProgress = true
        let finish: (Result) -> Void = { result in
            inProgress = false
            completion(result)
        }
        if let text = accessibilitySelectedText() {
            finish(.text(text))
            return true
        }
        copyFallback(completion: finish)
        return true
    }

    // MARK: Accessibility

    /// The focused element's selected text, or nil if the app does not provide it (or it is empty, which
    /// many apps also report when they simply do not support the attribute).
    private static func accessibilitySelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    // MARK: ⌘C fallback

    /// One pasteboard item with all of its representations.
    private struct SavedItem {
        var representations: [(NSPasteboard.PasteboardType, Data)]
    }

    private static func copyFallback(completion: @escaping (Result) -> Void) {
        let pasteboard = NSPasteboard.general
        guard let saved = snapshot(pasteboard) else {
            // Some contents (for example promised data of an app that quit) cannot be read back.
            // Copying would destroy them, so do not copy at all.
            NSLog("SlapNote: note from selection skipped, the clipboard could not be saved completely")
            completion(.failed)
            return
        }
        let before = pasteboard.changeCount
        guard postCopyShortcut() else {
            completion(.failed)
            return
        }
        let start = Date()
        poll(pasteboard, before: before, start: start) { outcome in
            switch outcome {
            case .copied:
                let text = pasteboard.string(forType: .string)
                if CopyFallback.mayRestore(before: before, current: pasteboard.changeCount) {
                    restore(saved, to: pasteboard)
                }
                completion(text.map { .text($0) } ?? .nothing)
            case .unclear:
                completion(.failed)
            case .timedOut, .waiting:
                completion(.nothing)
                undoLateCopy(pasteboard, before: before, saved: saved, until: Date().addingTimeInterval(CopyFallback.lateCopyWindow))
            }
        }
    }

    private static func poll(_ pasteboard: NSPasteboard, before: Int, start: Date, done: @escaping (CopyFallback.Outcome) -> Void) {
        let outcome = CopyFallback.outcome(before: before, current: pasteboard.changeCount,
                                           elapsed: Date().timeIntervalSince(start))
        guard outcome == .waiting else {
            done(outcome)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            poll(pasteboard, before: before, start: start, done: done)
        }
    }

    /// The target app answered after the timeout: its copy would replace the user's clipboard. If the
    /// next change is exactly that one copy, put the saved contents back. Any other change ends the watch.
    private static func undoLateCopy(_ pasteboard: NSPasteboard, before: Int, saved: [SavedItem], until deadline: Date) {
        let current = pasteboard.changeCount
        if current == before + 1 {
            restore(saved, to: pasteboard)
            return
        }
        guard current == before, Date() < deadline else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            undoLateCopy(pasteboard, before: before, saved: saved, until: deadline)
        }
    }

    /// All items with all representations, or nil if any representation cannot be read.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [SavedItem]? {
        let items = pasteboard.pasteboardItems ?? []
        var saved: [SavedItem] = []
        var typesPerItem: [Int] = []
        var readablePerItem: [Int] = []
        for item in items {
            let representations = item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
            typesPerItem.append(item.types.count)
            readablePerItem.append(representations.count)
            saved.append(SavedItem(representations: representations))
        }
        return CopyFallback.snapshotIsComplete(typesPerItem: typesPerItem, readablePerItem: readablePerItem) ? saved : nil
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
        let body = NSTextField(wrappingLabelWithString: "It only uses it for “Note from selection”: SlapNote reads the selected text. If an app does not share it, SlapNote presses ⌘C for you and puts your clipboard back. Turn on SlapNote in System Settings › Privacy & Security › Accessibility, then press the shortcut again.")
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
