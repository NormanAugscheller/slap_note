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
            updateIcon()
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func updateIcon() {
        guard let button = item?.button else { return }
        let hidden = manager.settings.notesHidden
        let symbol: String
        let description: String
        if manager.saveProblem != nil {
            symbol = "exclamationmark.triangle"
            description = "SlapNote — notes are not saved"
        } else if hidden {
            symbol = "eye.slash"
            description = "SlapNote — notes are hidden"
        } else {
            symbol = "note.text"
            description = "SlapNote"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.toolTip = description
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if manager.saveProblem != nil {
            menu.addItem(withTitle: "Notes Not Saved — Try Again", action: #selector(retrySave), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Show Notes Folder", action: #selector(showFolder), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
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

    @objc private func retrySave() { manager.saveNow() }
    @objc private func showFolder() { SaveProblemAlert.showFolder(manager.store.directory) }
    @objc private func toggleHidden() { manager.toggleHidden() }
    @objc private func restore() { manager.restoreLastNote() }
    @objc private func settings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
