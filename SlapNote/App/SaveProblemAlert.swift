import AppKit
import SlapNoteCore

/// Tells the user that notes are not on disk. Shown once per problem (not on every retry) and
/// again before quitting with unsaved changes.
enum SaveProblemAlert {
    enum QuitChoice { case retry, showFolder, quitAnyway }

    static func showFolder(_ directory: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        } else {
            NSWorkspace.shared.open(directory.deletingLastPathComponent())
        }
    }

    private static func text(for problem: NoteManager.SaveProblem, directory: URL) -> (title: String, body: String) {
        switch problem {
        case .failed(let message):
            return ("SlapNote can’t save your notes",
                    "Your latest changes are only on screen. SlapNote keeps trying to save them to “\(directory.path)”.\n\nCheck that the disk has free space and that the folder is writable.\n\n\(message)")
        case .blocked(.newerVersionNotPreserved(let version)):
            return ("SlapNote doesn’t save changes right now",
                    "Your notes were last saved by a newer version of SlapNote (format \(version)). SlapNote could not make a safety copy of that file, so it does not overwrite it — changes you make now are only on screen.\n\nUse the newer version of SlapNote, or make the folder “\(directory.path)” writable. SlapNote tries again by itself.")
        case .blocked(.unreadableFile(let name)):
            return ("SlapNote doesn’t save changes right now",
                    "SlapNote can’t read “\(name)” in “\(directory.path)”. Saving would replace that file without knowing what is in it, so changes you make now are only on screen.\n\nCheck that the file is readable. SlapNote tries again by itself.")
        }
    }

    /// Non-blocking warning while SlapNote keeps running. Returns true if the user asked to retry.
    static func present(_ problem: NoteManager.SaveProblem, directory: URL) -> Bool {
        let (title, body) = text(for: problem, directory: directory)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = body
        enum Choice { case retry, folder, ok }
        var choices: [Choice] = []
        alert.addButton(withTitle: "Try Again")
        choices.append(.retry)
        alert.addButton(withTitle: "Show in Finder")
        choices.append(.folder)
        alert.addButton(withTitle: "OK")
        choices.append(.ok)
        NSApp.activate()
        switch choices[safe: alert.runModal()] ?? .ok {
        case .retry: return true
        case .folder: showFolder(directory)
        case .ok: break
        }
        return false
    }

    /// Asked when quitting would lose changes.
    static func askBeforeQuit(_ problem: NoteManager.SaveProblem?, directory: URL) -> QuitChoice {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Quit without saving your latest changes?"
        let reason = problem.map { text(for: $0, directory: directory).body } ?? ""
        alert.informativeText = "SlapNote could not save your notes. If you quit now, changes since the last successful save are lost.\n\n" + reason
        var choices: [QuitChoice] = []
        alert.addButton(withTitle: "Try Again")
        choices.append(.retry)
        alert.addButton(withTitle: "Show in Finder")
        choices.append(.showFolder)
        alert.addButton(withTitle: "Quit Anyway")
        choices.append(.quitAnyway)
        NSApp.activate()
        return choices[safe: alert.runModal()] ?? .quitAnyway
    }
}

private extension Array {
    /// Element for an NSAlert response, counting from the first button.
    subscript(safe response: NSApplication.ModalResponse) -> Element? {
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return indices.contains(index) ? self[index] : nil
    }
}
