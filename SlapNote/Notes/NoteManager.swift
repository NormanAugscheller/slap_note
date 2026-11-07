import AppKit
import SlapNoteCore

/// Owns all notes: creation (placement), slapping, discarding/restoring, layers, persistence,
/// reminders, aging and display changes.
final class NoteManager: NSObject, NoteControllerDelegate, PlacementSessionDelegate {
    let settings: AppSettings
    let store: NoteStore
    let reminders = ReminderCoordinator()

    private(set) var notes: [NoteController] = []
    private(set) var placement: PlacementSession?
    private(set) var lastDiscarded: NoteRecord?
    private var previousApp: NSRunningApplication?
    private var lastStyle: NoteStyle?
    private var saveWorkItem: DispatchWorkItem?
    private(set) var isPeeking = false
    private var peekState = PeekState()
    private var peekHighlightEnd: DispatchWorkItem?
    static let peekHighlightDuration: TimeInterval = 3
    private var editingNote: NoteController?
    private var editMonitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    private var agingTimer: Timer?
    private var reminderPopover: NSPopover?
    private var accessibilityWindow: AccessibilityExplanationWindow?
    private var observers: [NSObjectProtocol] = []
    private var rng = SystemRandomNumberGenerator()

    /// Lets the manager avoid handing focus away while the settings window is in use.
    var isSettingsWindowKey: () -> Bool = { false }
    /// Notifies the menu bar icon about hidden state changes.
    var onHiddenChanged: ((Bool) -> Void)?

    static let saveDelay: TimeInterval = 0.5
    static let slapVisibilityDuration: TimeInterval = 1.2

    init(settings: AppSettings, store: NoteStore) {
        self.settings = settings
        self.store = store
        super.init()
    }

    var canRestore: Bool { lastDiscarded != nil }
    var isPlacing: Bool { placement != nil }
    var isEditing: Bool { editingNote != nil }

    // MARK: Startup

    func start() {
        let result = store.load()
        if result.recoveredFromCorruption {
            NSLog("SlapNote: notes file was unreadable; recovered from %@", result.source == .backup ? "backup" : "nothing")
        }
        for record in result.notes {
            let controller = NoteController(record: record, mode: .stuck, delegate: self)
            controller.setMode(.stuck)
            notes.append(controller)
            place(controller)
            controller.window.level = restingLevel
            controller.setCurl(Aging.curl(lastTouched: record.lastTouched, now: Date(), policy: settings.agingPolicy), animated: false)
            if !settings.notesHidden { controller.window.orderFrontRegardless() }
        }
        for id in ReminderSchedule.attentionNoteIDs(in: records) {
            controller(for: id)?.startAttention()
        }

        reminders.notesProvider = { [weak self] in self?.records ?? [] }
        reminders.onDue = { [weak self] ids in self?.remindersDue(ids) }
        reminders.onNotificationClicked = { [weak self] id in self?.notificationClicked(id) }
        reminders.onScheduled = { [weak self] id, date in self?.controller(for: id)?.markReminderScheduled(for: date) }
        reminders.start()
        reminders.rearm(notes: records)
        reminders.sync(notes: records)

        let agingTimer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAging(animated: true) }
        }
        RunLoop.main.add(agingTimer, forMode: .common)
        self.agingTimer = agingTimer

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AppSettings.didChange, object: settings, queue: .main) { [weak self] note in
            let key = note.userInfo?["key"] as? String
            MainActor.assumeIsolated { self?.settingsChanged(key: key) }
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.motionPreferenceChanged() }
        })
        if let block = store.writeBlock {
            saveProblem = .blocked(block)
        } else if result.recoveredFromCorruption || result.source == .backup {
            saveNow()
        }
    }

    var records: [NoteRecord] { notes.map(\.record) }

    func controller(for id: UUID) -> NoteController? {
        notes.first { $0.record.id == id }
    }

    private var restingLevel: NSWindow.Level {
        NoteLevels.resting(alwaysOnTop: settings.alwaysOnTop)
    }

    // MARK: Displays

    static func currentDisplays() -> [DisplayInfo] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let uuid = screen.displayUUID else { return nil }
            return DisplayInfo(uuid: uuid, visibleFrame: screen.visibleFrame, isMain: index == 0)
        }
    }

    /// Puts a note where its record says (falls back to the main display if its display is missing).
    /// The target display is found first; height and internal scrolling are computed for its visible
    /// area, and only then is the note positioned with that size.
    private func place(_ controller: NoteController) {
        let displays = Self.currentDisplays()
        guard let target = DisplayResolver.resolve(controller.record.position, noteSize: controller.displayedSize,
                                                   displays: displays) else { return }
        if let screen = NSScreen.screens.first(where: { $0.displayUUID == target.displayUUID }) {
            controller.fit(to: screen)
        }
        guard let resolved = DisplayResolver.resolve(controller.record.position, noteSize: controller.displayedSize,
                                                     displays: displays) else { return }
        controller.setNoteCenter(resolved.center)
    }

    private func screensChanged() {
        for c in notes where c.mode == .stuck || c.mode == .editing {
            place(c)
        }
    }

    /// Records the display + relative position of the note's current center.
    private func recordPosition(of controller: NoteController) {
        if let pos = DisplayResolver.position(forCenter: controller.noteCenter, displays: Self.currentDisplays()) {
            controller.updatePosition(pos)
        }
    }

    // MARK: Creating notes (placement mode)

    func newNote(text: String = "") {
        guard placement == nil else { return }
        editingNote?.endEditing()
        if settings.notesHidden { setHidden(false) }
        rememberFrontmostApp()

        let style: NoteStyle
        if settings.randomStyle {
            style = StylePicker.random(excluding: lastStyle, using: &rng)
        } else {
            style = NoteStyle(color: settings.defaultColor, shape: settings.defaultShape)
        }
        lastStyle = style
        let size = style.shape.defaultSize
        let mouse = NSEvent.mouseLocation
        let position = DisplayResolver.position(forCenter: mouse, displays: Self.currentDisplays())
            ?? DisplayPosition(displayUUID: "", relativeX: 0.5, relativeY: 0.5)
        let record = NoteRecord(text: text, color: style.color, shape: style.shape,
                                width: Double(size.width), height: Double(size.height), position: position)
        let controller = NoteController(record: record, mode: .placement, delegate: self)
        let session = PlacementSession(note: controller, bindings: settings.scrollBindings)
        session.delegate = self
        placement = session
        NSApp.activate()
        session.begin()
    }

    func noteFromSelection() {
        guard placement == nil else { return }
        guard SelectionGrabber.isTrusted else {
            let window = accessibilityWindow ?? AccessibilityExplanationWindow()
            accessibilityWindow = window
            window.present()
            return
        }
        SelectionGrabber.grabSelection { [weak self] result in
            switch result {
            case .text(let text):
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.newNote(text: String(cleaned.prefix(10_000)))
            case .nothing:
                self?.newNote()
            case .failed:
                // The clipboard could not be protected, so SlapNote did not copy.
                NSSound.beep()
            }
        }
    }

    func placementDidSlap(_ session: PlacementSession) {
        let c = session.note
        let swayAngle = session.currentSwayAngle
        session.end()
        placement = nil
        closeReminderPopover()

        let rotation = Double.random(in: -2...2)
        c.setRotation(rotation)
        recordPosition(of: c)
        c.setMode(.stuck)
        c.window.makeFirstResponder(nil)
        c.window.resignKey()
        c.touch()
        notes.append(c)

        c.window.level = isPeeking ? NoteLevels.peek : NoteLevels.justSlapped
        NoteAnimator.slap(c.view, fromRotation: swayAngle, toRotation: CGFloat(rotation))
        c.applyRotation(CGFloat(rotation))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.reduced ? 0.15 : 0.12
            c.window.animator().alphaValue = 1
        }
        // The note stays above windows briefly so the user sees where it went, then sinks.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.slapVisibilityDuration) { [weak self, weak c] in
            guard let self, let c, c.mode != .leaving, !self.isPeeking else { return }
            let target = self.restingLevel
            guard c.window.level != target else { return }
            NoteAnimator.sink(c.window, view: c.view) {
                c.window.level = target
                if self.settings.notesHidden { c.window.orderOut(nil) }
            }
        }
        scheduleSave()
        returnFocus()
    }

    func placementDidDiscard(_ session: PlacementSession) {
        let c = session.note
        session.end()
        placement = nil
        closeReminderPopover()
        c.setMode(.leaving)
        recordPosition(of: c)
        c.window.makeFirstResponder(nil)
        // An empty note thrown away right after summoning does not replace a real discarded note.
        if Self.isWorthKeeping(c.record) {
            var r = c.record
            r.rotation = Double.random(in: -2...2)
            lastDiscarded = r
        }
        ThrowAnimator.throwAway(c.view, window: c.window, color: c.record.color) {
            c.close()
        }
        returnFocus()
    }

    /// A note with text or a reminder; an empty one is not worth restoring or saving on quit.
    static func isWorthKeeping(_ record: NoteRecord) -> Bool {
        !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || record.reminder != nil
    }

    func noteRequestsCancelPlacement(_ note: NoteController) {
        guard let placement, placement.note === note else { return }
        placementDidDiscard(placement)
    }

    func placementDidCycleStyle(_ session: PlacementSession, color steps: Int) {
        let c = session.note
        c.setStyle(NoteStyle(color: c.record.color.next(steps: steps), shape: c.record.shape), keepSize: true)
        lastStyle = c.record.style
    }

    func placementDidCycleShape(_ session: PlacementSession, shape steps: Int) {
        let c = session.note
        c.setStyle(NoteStyle(color: c.record.color, shape: c.record.shape.next(steps: steps)), keepSize: false)
        lastStyle = c.record.style
    }

    // MARK: Discard / restore

    func noteRequestsDiscard(_ note: NoteController) {
        if note.mode == .editing { note.endEditing() }
        guard note.mode == .stuck else { return }
        note.setMode(.leaving)
        notes.removeAll { $0 === note }
        lastDiscarded = note.record
        reminders.cancel(noteID: note.record.id)
        if note.isHovered { NoteAnimator.hover(note.view, on: false) }
        note.stopAttention()
        // Throw from above other windows so the crumple is visible even for desktop-level notes.
        note.window.level = NoteLevels.hanging
        ThrowAnimator.throwAway(note.view, window: note.window, color: note.record.color) {
            note.close()
        }
        scheduleSave()
    }

    func restoreLastNote() {
        guard placement == nil, let record = lastDiscarded else {
            NSSound.beep()
            return
        }
        lastDiscarded = nil
        if settings.notesHidden { setHidden(false) }
        let c = NoteController(record: record, mode: .stuck, delegate: self)
        c.setMode(.stuck)
        c.setCurl(Aging.curl(lastTouched: record.lastTouched, now: Date(), policy: settings.agingPolicy), animated: false)
        place(c)
        notes.append(c)
        c.window.level = NoteLevels.hanging
        ThrowAnimator.restore(c.view, window: c.window, color: record.color) { [weak self, weak c] in
            guard let self, let c else { return }
            c.window.level = self.isPeeking ? NoteLevels.peek : self.restingLevel
            if ReminderSchedule.attentionNoteIDs(in: [c.record]).contains(c.record.id) { c.startAttention() }
        }
        scheduleSave()
    }

    // MARK: Visibility

    func toggleHidden() {
        setHidden(!settings.notesHidden)
    }

    func setHidden(_ hidden: Bool) {
        if settings.notesHidden != hidden { settings.notesHidden = hidden }
        for c in notes where c.mode != .leaving {
            if hidden {
                if c.mode == .editing { c.endEditing() }
                fadeOut(c.window) { if self.settings.notesHidden && !self.isPeeking { c.window.orderOut(nil) } }
            } else {
                c.window.alphaValue = 0
                c.window.orderFrontRegardless()
                fadeIn(c.window)
            }
        }
        onHiddenChanged?(hidden)
    }

    /// Peek: while held, raise every note above all windows; on release, return them.
    /// The Peek shortcut is pressed (true) or released (false).
    func setPeek(_ on: Bool) {
        peekState.held = on
        applyPeek()
    }

    /// Raises the notes for a few seconds, independently of the held shortcut. Calling it again
    /// restarts the time.
    private func highlightWithPeek() {
        peekHighlightEnd?.cancel()
        peekState.highlighted = true
        applyPeek()
        let end = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.peekState.highlighted = false
                self.applyPeek()
            }
        }
        peekHighlightEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekHighlightDuration, execute: end)
    }

    private func applyPeek() {
        let on = peekState.isActive
        guard on != isPeeking else { return }
        isPeeking = on
        for c in notes where c.mode == .stuck || c.mode == .editing {
            if on {
                c.window.alphaValue = 0
                c.window.level = NoteLevels.peek
                c.window.orderFrontRegardless()
                fadeIn(c.window)
            } else {
                fadeOut(c.window) {
                    guard !self.isPeeking else { return }
                    c.window.level = self.restingLevel
                    if self.settings.notesHidden {
                        c.window.orderOut(nil)
                    }
                    c.window.alphaValue = 1
                }
            }
        }
    }

    private func fadeIn(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = Motion.easeOut
            window.animator().alphaValue = 1
        }
    }

    private func fadeOut(_ window: NSWindow, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = Motion.easeIn
            window.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    // MARK: Editing

    func noteWillBeginEditing(_ note: NoteController) {
        if let other = editingNote, other !== note { other.endEditing() }
        editingNote = note
        rememberFrontmostApp()
        NSApp.activate()
        // Clicking outside ends editing: other apps / the desktop (global) and our other windows (local).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.editingNote?.endEditing() }
        }) {
            editMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self, let editing = self.editingNote else { return event }
            if event.window !== editing.window && event.window !== self.reminderPopover?.contentViewController?.view.window {
                editing.endEditing()
            }
            return event
        }) {
            editMonitors.append(local)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.reminderPopover == nil else { return }
                self.editingNote?.endEditing()
            }
        }
    }

    func noteDidEndEditing(_ note: NoteController) {
        guard editingNote === note else { return }
        editingNote = nil
        for m in editMonitors { NSEvent.removeMonitor(m) }
        editMonitors.removeAll()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        closeReminderPopover()
        scheduleSave()
        returnFocus()
    }

    // MARK: Focus

    private func rememberFrontmostApp() {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
    }

    /// Gives keyboard focus back to the app the user was in before SlapNote took it.
    private func returnFocus() {
        defer { previousApp = nil }
        guard NSApp.isActive, !isSettingsWindowKey(), editingNote == nil, placement == nil else { return }
        // No previous app means SlapNote itself was in front (e.g. the settings window): stay active.
        guard let app = previousApp, !app.isTerminated else { return }
        NSApp.yieldActivation(to: app)
        app.activate()
    }

    // MARK: NoteControllerDelegate

    func noteDidChange(_ note: NoteController) {
        if placement?.note === note { placement?.recenter() }
        scheduleSave()
    }

    func noteDidMove(_ note: NoteController) {
        recordPosition(of: note)
        scheduleSave()
    }

    func noteWasInteractedWith(_ note: NoteController) {
        scheduleSave()
    }

    func noteRequestsReminderPicker(_ note: NoteController) {
        closeReminderPopover()
        let picker = ReminderPicker(existing: note.record.reminder?.date)
        let popover = NSPopover()
        popover.contentViewController = picker
        popover.behavior = .transient
        popover.animates = !Motion.reduced
        let isPlacement = placement?.note === note
        placement?.isFrozen = true
        picker.onSet = { [weak self, weak note] date in
            guard let self, let note else { return }
            self.reminders.requestAuthorizationIfNeeded()
            note.setReminder(ReminderRecord(date: date))
            self.closeReminderPopover()
            self.reminders.rearm(notes: self.records + (isPlacement ? [note.record] : []))
        }
        picker.onRemove = { [weak self, weak note] in
            guard let self, let note else { return }
            note.setReminder(nil)
            self.reminders.cancel(noteID: note.record.id)
            self.closeReminderPopover()
            self.reminders.rearm(notes: self.records)
        }
        picker.onCancel = { [weak self] in self?.closeReminderPopover() }
        reminderPopover = popover
        NotificationCenter.default.addObserver(self, selector: #selector(popoverDidClose(_:)),
                                               name: NSPopover.didCloseNotification, object: popover)
        popover.show(relativeTo: note.view.noteRect, of: note.view, preferredEdge: .maxY)
    }

    @objc private func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSPopover.didCloseNotification, object: notification.object)
        if (notification.object as? NSPopover) === reminderPopover { reminderPopover = nil }
        placement?.isFrozen = false
        if let placement {
            placement.note.window.makeKey()
            placement.note.window.makeFirstResponder(placement.note.view.textView)
        } else if let editing = editingNote {
            editing.window.makeKey()
            editing.window.makeFirstResponder(editing.view.textView)
        }
    }

    private func closeReminderPopover() {
        reminderPopover?.performClose(nil)
        reminderPopover = nil
        placement?.isFrozen = false
    }

    // MARK: Reminders

    private func remindersDue(_ ids: [UUID]) {
        var unannounced: [NoteRecord] = []
        for id in ids {
            guard let c = controller(for: id) else { continue }
            // A reminder macOS accepted is delivered by the system, also while SlapNote was closed —
            // even if the user has dismissed it since. Only the others need a notification from us.
            if ReminderSchedule.needsOwnNotification(c.record.reminder) { unannounced.append(c.record) }
            c.markReminderFired()
            c.startAttention()
        }
        reminders.postMissed(unannounced)
        scheduleSave()
    }

    func notificationClicked(_ id: UUID) {
        guard let c = controller(for: id) else { return }
        highlightWithPeek()
        c.startAttention()
    }

    // MARK: Aging, settings, motion

    private func updateAging(animated: Bool) {
        let now = Date()
        for c in notes where c.mode == .stuck {
            c.setCurl(Aging.curl(lastTouched: c.record.lastTouched, now: now, policy: settings.agingPolicy), animated: animated)
        }
    }

    private func settingsChanged(key: String?) {
        switch key.flatMap(AppSettings.Key.init(rawValue:)) {
        case .alwaysOnTop:
            if !isPeeking {
                for c in notes where c.mode == .stuck || c.mode == .editing { c.window.level = restingLevel }
            }
        case .agingEnabled, .agingDays:
            updateAging(animated: true)
        case .notesHidden:
            onHiddenChanged?(settings.notesHidden)
        case .fontFamily, .baseFontSize, .textColorMode, .alignment, .lineSpacing, .paperTexture:
            for c in notes + [placement?.note].compactMap({ $0 }) {
                c.applyAppearance()
                c.relayout(anchor: c.mode == .placement ? .center : .top)
            }
        default:
            break
        }
    }

    private func motionPreferenceChanged() {
        if Motion.reduced {
            for c in notes { c.view.flutter.layer?.removeAllAnimations() }
        }
    }

    // MARK: Persistence

    enum SaveProblem: Equatable {
        /// Writing failed (disk full, folder not writable, …). Retried automatically.
        case failed(message: String)
        /// The store refuses writes to protect a file from a newer SlapNote version.
        case blocked(NoteStore.WriteBlock)
    }

    /// Set while the notes on screen are not on disk. Cleared by the next successful save.
    private(set) var saveProblem: SaveProblem? {
        didSet { if saveProblem != oldValue { onSaveProblemChanged?(saveProblem) } }
    }
    /// Notifies the app (alert, menu bar icon) when saving starts or stops failing.
    var onSaveProblemChanged: ((SaveProblem?) -> Void)?
    /// Something changed since the last successful save.
    private(set) var hasUnsavedChanges = false
    private var retryWorkItem: DispatchWorkItem?
    private var retryDelay: TimeInterval = NoteManager.firstRetryDelay
    static let firstRetryDelay: TimeInterval = 5
    static let maxRetryDelay: TimeInterval = 300

    func scheduleSave() {
        hasUnsavedChanges = true
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { _ = self?.saveNow() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: item)
    }

    /// Writes all notes now. Returns false if they are not on disk.
    @discardableResult
    func saveNow() -> Bool {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        let all = records
        let saved: Bool
        do {
            try store.save(all)
            saved = true
            hasUnsavedChanges = false
            retryDelay = Self.firstRetryDelay
            saveProblem = nil
        } catch NoteStore.StoreError.writesBlocked(let block) {
            saved = false
            saveProblem = .blocked(block)
        } catch {
            saved = false
            NSLog("SlapNote: saving notes failed: %@", error.localizedDescription)
            saveProblem = .failed(message: error.localizedDescription)
            scheduleRetry()
        }
        reminders.sync(notes: all)
        reminders.rearm(notes: all)
        return saved
    }

    /// Retries a failed save with a growing delay (5 s, 10 s, 20 s, … up to 5 min).
    private func scheduleRetry() {
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { _ = self?.saveNow() }
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: item)
        retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
    }

    /// Called before quitting: finishes editing and writes synchronously.
    /// Returns true if nothing would be lost by quitting now.
    ///
    /// A note still hanging at the cursor is not in `records`. If it holds text or a reminder it is
    /// slapped where it hangs, so it is saved (and stays if the quit is cancelled); an empty one is thrown away.
    func prepareForTermination() -> Bool {
        editingNote?.endEditing()
        if let placement {
            if Self.isWorthKeeping(placement.note.record) {
                placementDidSlap(placement)
            } else {
                placementDidDiscard(placement)
            }
        }
        guard hasUnsavedChanges || saveProblem != nil else { return true }
        return saveNow() || !hasUnsavedChanges
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Stable identifier of the physical display (survives reboots and re-plugging).
    var displayUUID: String? {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
