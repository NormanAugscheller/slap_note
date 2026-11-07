import AppKit

/// Optional menu bar icon (off by default).
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let manager: NoteManager
    private let openSettings: () -> Void

    init(manager: NoteManager, openSettings: @escaping () -> Void) {
        self.manager = manager
        self.openSettings = openSettings
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
            updateIcon(hidden: manager.settings.notesHidden)
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func updateIcon(hidden: Bool) {
        guard let button = item?.button else { return }
        let name = hidden ? "note.text.badge.plus" : "note.text"
        let image = NSImage(systemSymbolName: hidden ? "eye.slash" : name,
                            accessibilityDescription: hidden ? "SlapNote (notes hidden)" : "SlapNote")
        image?.isTemplate = true
        button.image = image
        button.toolTip = hidden ? "SlapNote — notes are hidden" : "SlapNote"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Note from Selection", action: #selector(noteFromSelection), keyEquivalent: "").target = self
        let hideTitle = manager.settings.notesHidden ? "Show All Notes" : "Hide All Notes"
        menu.addItem(withTitle: hideTitle, action: #selector(toggleHidden), keyEquivalent: "").target = self
        let restore = menu.addItem(withTitle: "Restore Last Note", action: #selector(restore), keyEquivalent: "")
        restore.target = self
        restore.isEnabled = manager.canRestore
        menu.autoenablesItems = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit SlapNote", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func newNote() {
        // Let the menu close first so the note appears at the pointer, not in the menu.
        DispatchQueue.main.async { self.manager.newNote() }
    }

    @objc private func noteFromSelection() {
        DispatchQueue.main.async { self.manager.noteFromSelection() }
    }

    @objc private func toggleHidden() { manager.toggleHidden() }
    @objc private func restore() { manager.restoreLastNote() }
    @objc private func settings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
