import AppKit
import KeyboardShortcuts
import SlapNoteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    private(set) var manager: NoteManager!
    private var settingsWindow: SettingsWindowController?
    private var statusItem: StatusItemController?
    private var undoMonitor: Any?
    private var launchAppleEventFlag: Bool?
    private var settingsObserver: NSObjectProtocol?
    #if DEBUG
    private var selfTest: SelfTest?
    #endif

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchAppleEventFlag = LaunchDetector.appleEventLoginItemFlag()
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if launchAppleEventFlag == nil { launchAppleEventFlag = LaunchDetector.appleEventLoginItemFlag() }

        var dataDirectory = NoteStore.defaultDirectory()
        #if DEBUG
        if let override = SelfTest.dataDirectoryOverride { dataDirectory = override }
        #endif
        manager = NoteManager(settings: settings, store: NoteStore(directory: dataDirectory))
        manager.isSettingsWindowKey = { [weak self] in self?.settingsWindow?.window?.isKeyWindow ?? false }
        manager.start()

        statusItem = StatusItemController(manager: manager) { [weak self] in self?.showSettings(intro: false) }
        statusItem?.setVisible(settings.showMenuBarIcon)
        manager.onHiddenChanged = { [weak self] hidden in self?.statusItem?.updateIcon(hidden: hidden) }
        settingsObserver = NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: settings, queue: .main) { [weak self] note in
            let key = note.userInfo?["key"] as? String
            MainActor.assumeIsolated {
                guard let self, key == AppSettings.Key.showMenuBarIcon.rawValue else { return }
                self.statusItem?.setVisible(self.settings.showMenuBarIcon)
            }
        }

        registerShortcuts()
        installUndoMonitor()

        #if DEBUG
        if SelfTest.isRequested {
            selfTest = SelfTest(manager: manager)
            selfTest?.run()
            return
        }
        #endif
        let isFirstLaunch = !settings.hasLaunchedBefore
        let kind = LaunchDetector.classify(appleEventFlag: launchAppleEventFlag)
        if LaunchContext.shouldShowSettings(kind: kind, isFirstLaunch: isFirstLaunch) {
            showSettings(intro: isFirstLaunch)
        }
        settings.hasLaunchedBefore = true
    }

    /// Re-launch while running (Finder, Dock, Spotlight, `open`) opens the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(intro: false)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.prepareForTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func showSettings(intro: Bool) {
        let controller = settingsWindow ?? SettingsWindowController(settings: settings)
        settingsWindow = controller
        controller.show(intro: intro)
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .newNote) { [weak self] in self?.manager.newNote() }
        KeyboardShortcuts.onKeyDown(for: .noteFromSelection) { [weak self] in self?.manager.noteFromSelection() }
        KeyboardShortcuts.onKeyDown(for: .peek) { [weak self] in self?.manager.setPeek(true) }
        KeyboardShortcuts.onKeyUp(for: .peek) { [weak self] in self?.manager.setPeek(false) }
        KeyboardShortcuts.onKeyDown(for: .toggleHidden) { [weak self] in self?.manager.toggleHidden() }
        KeyboardShortcuts.onKeyDown(for: .restoreLastNote) { [weak self] in self?.manager.restoreLastNote() }
    }

    /// ⌘Z restores the last discarded note while SlapNote is the active app. It is never registered
    /// globally. Inside a text view with something to undo, ⌘Z keeps its normal text meaning.
    private func installUndoMonitor() {
        undoMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.isActive else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.charactersIgnoringModifiers?.lowercased() == "z" else { return event }
            let textView = event.window?.firstResponder as? NSTextView
            if flags == [.command, .shift], let tv = textView, tv.isEditable, tv.undoManager?.canRedo == true {
                tv.undoManager?.redo()
                return nil
            }
            guard flags == .command else { return event }
            if let tv = textView, tv.isEditable, tv.undoManager?.canUndo == true {
                tv.undoManager?.undo()
                return nil
            }
            if self.manager.canRestore {
                self.manager.restoreLastNote()
                return nil
            }
            return event
        }
    }
}

/// Minimal main menu. It is never visible (agent app), but its key equivalents work while
/// SlapNote is active (⌘Q, ⌘W, standard text editing).
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "SlapNote")
        appMenu.addItem(withTitle: "Quit SlapNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}
