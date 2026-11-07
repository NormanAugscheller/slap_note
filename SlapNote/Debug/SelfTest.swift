#if DEBUG
import AppKit
import SlapNoteCore

/// Debug-only runtime smoke test. Not part of Release builds; delete this file to remove it.
///
///     SlapNote.app/Contents/MacOS/SlapNote -SlapNoteSelfTest YES -SlapNoteDataDirectory /tmp/slapnote-selftest
///
/// Drives the real note windows through placement, slap, layers, reminder, discard, restore and
/// persistence, prints PASS/FAIL lines and quits with exit code 0 (all passed) or 1.
@MainActor
final class SelfTest {
    private let manager: NoteManager
    private var failures: [String] = []
    private var steps: [(String, TimeInterval, () -> Void)] = []

    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "SlapNoteSelfTest") }

    static var dataDirectoryOverride: URL? {
        UserDefaults.standard.string(forKey: "SlapNoteDataDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    init(manager: NoteManager) {
        self.manager = manager
    }

    private func check(_ condition: Bool, _ message: String) {
        print(condition ? "PASS \(message)" : "FAIL \(message)")
        if !condition { failures.append(message) }
    }

    private func step(_ name: String, after delay: TimeInterval, _ body: @escaping () -> Void) {
        steps.append((name, delay, body))
    }

    func run() {
        let m = manager
        step("summon", after: 0.3) {
            m.newNote(text: "Self test\nsecond line")
            self.check(m.isPlacing, "placement mode starts")
            let w = m.placement?.note.window
            self.check(w?.level == NoteLevels.hanging, "hanging note is above everything")
            self.check(abs((w?.alphaValue ?? 0) - 0.5) < 0.01, "hanging note is ghosted at 50 %")
            self.check(w?.ignoresMouseEvents == true, "clicks go to the capture windows")
        }
        step("resize", after: 0.4) {
            guard let c = m.placement?.note else { return self.check(false, "placement note exists") }
            let before = c.record.manualSize
            c.applyResize(factor: 1.2, mode: .proportional)
            self.check(c.record.manualSize.width > before.width && abs(c.record.fontScale - 1.2) < 0.001,
                       "proportional resize scales size and font")
            c.applyResize(factor: 50, mode: .heightOnly)
            self.check(c.record.height == 600, "height clamps at 600 pt")
        }
        step("slap", after: 0.4) {
            guard let s = m.placement else { return self.check(false, "placement session exists") }
            m.placementDidSlap(s)
            self.check(!m.isPlacing && m.notes.count == 1, "slap creates a stuck note")
            self.check(m.notes.first?.window.level == NoteLevels.justSlapped, "slapped note stays visible above windows")
            self.check(abs(m.notes.first?.record.rotation ?? 9) <= 2, "rotation within ±2°")
        }
        step("sink", after: 1.8) {
            self.check(m.notes.first?.window.level == NoteLevels.desktop, "note sinks to the desktop layer after 1.2 s")
            self.check(m.notes.first?.window.isVisible == true, "stuck note window is visible")
        }
        step("grow", after: 0.2) {
            guard let c = m.notes.first else { return }
            let h = c.displayedSize.height
            c.view.textView.string = Array(repeating: "line", count: 60).joined(separator: "\n")
            c.textDidChange(Notification(name: NSText.didChangeNotification))
            self.check(c.displayedSize.height > h, "auto-grow increases the height")
            self.check(c.displayedSize.width == CGFloat(c.record.width), "auto-grow keeps the width")
            c.view.textView.string = "Self test\nsecond line"
            c.textDidChange(Notification(name: NSText.didChangeNotification))
        }
        step("peek on", after: 0.3) {
            m.setPeek(true)
            self.check(m.notes.first?.window.level == NoteLevels.peek, "peek raises notes")
        }
        step("peek off", after: 0.3) {
            m.setPeek(false)
        }
        step("peek restored", after: 0.4) {
            self.check(m.notes.first?.window.level == NoteLevels.desktop, "releasing peek restores the layer")
            m.settings.alwaysOnTop = true
        }
        step("always on top", after: 0.2) {
            self.check(m.notes.first?.window.level == NoteLevels.alwaysOnTop, "always-on-top applies instantly")
            m.settings.alwaysOnTop = false
            m.toggleHidden()
        }
        step("hidden", after: 0.4) {
            self.check(m.settings.notesHidden && m.notes.first?.window.isVisible == false, "hide all hides notes")
            m.toggleHidden()
        }
        step("shown", after: 0.4) {
            self.check(!m.settings.notesHidden && m.notes.first?.window.isVisible == true, "show all shows notes")
            m.notes.first?.setReminder(ReminderRecord(date: Date().addingTimeInterval(1)))
            m.saveNow()
        }
        step("reminder", after: 2.0) {
            let c = m.notes.first
            self.check(c?.record.reminder?.fired == true, "reminder fires when due")
            self.check(c?.isAttentionActive == true, "due note wiggles and glows")
            self.check(c?.view.reminderLabel.isHidden == false, "reminder time is shown on the note")
        }
        step("discard", after: 0.3) {
            guard let c = m.notes.first else { return }
            m.noteRequestsDiscard(c)
            self.check(m.notes.isEmpty && m.canRestore, "right click discards and remembers the note")
        }
        step("restore", after: 1.0) {
            m.restoreLastNote()
            self.check(m.notes.count == 1 && !m.canRestore, "restore brings the note back")
            self.check(m.notes.first?.record.text == "Self test\nsecond line", "restored note keeps its text")
        }
        step("escape placement", after: 1.0) {
            m.newNote(text: "throw me")
            if let c = m.placement?.note { m.noteRequestsCancelPlacement(c) }
            self.check(!m.isPlacing && m.notes.count == 1, "Esc discards the hanging note")
        }
        step("save failure", after: 1.0) {
            let fm = FileManager.default
            let path = m.store.directory.path
            try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
            m.scheduleSave()
            let saved = m.saveNow()
            if case .failed = m.saveProblem { self.check(!saved, "failed save is reported") } else {
                self.check(false, "failed save is reported")
            }
            self.check(m.hasUnsavedChanges && !m.prepareForTermination(), "quitting with unsaved changes is held back")
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            self.check(m.saveNow() && m.saveProblem == nil && !m.hasUnsavedChanges, "next save clears the problem")
        }
        step("persist", after: 1.0) {
            m.saveNow()
            let loaded = NoteStore(directory: m.store.directory).load()
            self.check(loaded.source == .main && loaded.notes.count == 1, "notes.json contains the stuck note")
            self.check(loaded.notes.first?.reminder?.fired == true, "reminder state is persisted")
            self.finish()
        }
        runNext(0)
    }

    private func runNext(_ index: Int) {
        guard index < steps.count else { return }
        let (_, delay, body) = steps[index]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            body()
            self.runNext(index + 1)
        }
    }

    private func finish() {
        print(failures.isEmpty ? "SELFTEST PASSED" : "SELFTEST FAILED: \(failures.count) check(s)")
        fflush(stdout)
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif
