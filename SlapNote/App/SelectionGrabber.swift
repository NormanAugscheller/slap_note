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
    ///
    /// The target is the app that is frontmost when the shortcut fires. The Accessibility read runs off
    /// the main thread (a hanging app cannot freeze SlapNote), and the ⌘C fallback only runs if that app
    /// is still frontmost afterwards, so a focus change cannot grab — or copy in — another app.
    @discardableResult
    static func grabSelection(completion: @escaping (Result) -> Void) -> Bool {
        guard !inProgress else { return false }
        inProgress = true
        let finish: (Result) -> Void = { result in
            inProgress = false
            completion(result)
        }
        guard let target = NSWorkspace.shared.frontmostApplication else {
            finish(.failed)
            return true
        }
        if target.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // SlapNote itself is in front (for example while editing a note): read its own text view.
            // Asking our own process through Accessibility would wait on the main thread we block.
            let textView = NSApp.keyWindow?.firstResponder as? NSTextView
            let selected = textView.map { tv in (tv.string as NSString).substring(with: tv.selectedRange()) } ?? ""
            finish(selected.isEmpty ? .nothing : .text(selected))
            return true
        }
        let pid = target.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let text = accessibilitySelectedText(pid: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let text {
                        finish(.text(text))
                    } else if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                        copyFallback(completion: finish)
                    } else {
                        finish(.failed)
                    }
                }
            }
        }
        return true
    }

    // MARK: Accessibility

    /// The selected text of the focused element of the app `pid`, or nil if the app does not provide it
    /// (or it is empty, which many apps also report when they simply do not support the attribute).
    /// Runs on a background queue; each Accessibility message waits at most 0.5 s.
    nonisolated private static func accessibilitySelectedText(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
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
        let before = pasteboard.changeCount
        guard let saved = snapshot(pasteboard), pasteboard.changeCount == before else {
            // Some contents (for example promised data of an app that quit) cannot be read back, or the
            // clipboard changed while it was being saved. Copying would destroy them, so do not copy at all.
            NSLog("SlapNote: note from selection skipped, the clipboard could not be saved completely")
            completion(.failed)
            return
        }
        guard postCopyShortcut() else {
            completion(.failed)
            return
        }
        // Monotonic clock: a system clock set back cannot stretch the wait.
        let start = ProcessInfo.processInfo.systemUptime
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
                // No copy within the timeout. A copy arriving later cannot be told apart from one the
                // user makes, so it is left alone rather than possibly wiping the user's own copy.
                completion(.nothing)
            }
        }
    }

    private static func poll(_ pasteboard: NSPasteboard, before: Int, start: TimeInterval, done: @escaping (CopyFallback.Outcome) -> Void) {
        let outcome = CopyFallback.outcome(before: before, current: pasteboard.changeCount,
                                           elapsed: ProcessInfo.processInfo.systemUptime - start)
        guard outcome == .waiting else {
            done(outcome)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            poll(pasteboard, before: before, start: start, done: done)
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
