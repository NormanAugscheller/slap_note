import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let newNote = Self("newNote", default: .init(.n, modifiers: [.control, .option]))
    static let noteFromSelection = Self("noteFromSelection", default: .init(.s, modifiers: [.control, .option]))
    static let peek = Self("peek", default: .init(.space, modifiers: [.control, .option]))
    static let toggleHidden = Self("toggleHidden", default: .init(.h, modifiers: [.control, .option]))
    static let restoreLastNote = Self("restoreLastNote", default: .init(.z, modifiers: [.control, .option]))

    static let allGlobal: [KeyboardShortcuts.Name] = [.newNote, .noteFromSelection, .peek, .toggleHidden, .restoreLastNote]
}
