import AppKit
import SlapNoteCore
import UserNotifications

/// Schedules macOS notifications for reminders and fires the in-app "due" behavior.
final class ReminderCoordinator: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main actor when the user clicks a reminder notification.
    var onNotificationClicked: ((UUID) -> Void)?
    /// Called when reminders become due while the app runs (or were missed while it was closed).
    var onDue: (([UUID]) -> Void)?

    private var timer: Timer?
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    private var authorizationRequested = false

    func start() {
        center.delegate = self
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Asks for permission the first time a reminder is set (never at launch).
    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// What is currently scheduled with the system, so unchanged reminders are left alone.
    private var scheduled: [String: (date: Date, title: String)] = [:]

    /// Brings the scheduled notifications in line with the pending reminders of `notes`. Only changed
    /// reminders are removed and re-added, so a save right before a reminder is due cannot drop it.
    func sync(notes: [NoteRecord]) {
        let now = Date()
        var wanted: [String: (date: Date, title: String)] = [:]
        for note in notes {
            guard let r = note.reminder, !r.fired, r.date > now else { continue }
            wanted[note.id.uuidString] = (r.date, Self.title(for: note))
        }
        let stale = scheduled.keys.filter { id in
            guard let w = wanted[id], let s = scheduled[id] else { return true }
            return w.date != s.date || w.title != s.title
        }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(stale)) }
        for id in stale { scheduled[id] = nil }
        for (id, item) in wanted where scheduled[id] == nil {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.sound = .default
            content.userInfo = ["noteID": id]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            scheduled[id] = item
        }
        // Reminders that fired or were removed are no longer pending with the system.
        for id in scheduled.keys where wanted[id] == nil { scheduled[id] = nil }
    }

    func cancel(noteID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [noteID.uuidString])
        scheduled[noteID.uuidString] = nil
    }

    static func title(for note: NoteRecord) -> String {
        let line = note.firstLine
        return line.isEmpty ? "SlapNote: Reminder" : "SlapNote: \(line.prefix(80))"
    }

    /// Arms one timer for the earliest pending reminder and reports reminders that are already due.
    func rearm(notes: [NoteRecord]) {
        timer?.invalidate()
        timer = nil
        let now = Date()
        let due = ReminderSchedule.dueNoteIDs(in: notes, now: now)
        if !due.isEmpty { onDue?(due) }
        guard let next = ReminderSchedule.nextPendingDate(in: notes, now: now) else { return }
        let t = Timer(fire: next.addingTimeInterval(0.2), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var notesProvider: (() -> [NoteRecord])?

    private func timerFired() {
        rearm(notes: notesProvider?() ?? [])
    }

    @objc private func systemDidWake() {
        rearm(notes: notesProvider?() ?? [])
    }

    /// Posts the notification for reminders the system did not deliver itself (passed while SlapNote
    /// was not running, or the scheduled request went missing). Checks the delivered list first so the
    /// user never gets the same reminder twice.
    func postMissed(_ notes: [NoteRecord], after delay: TimeInterval = 0) {
        guard !notes.isEmpty else { return }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.postMissed(notes)
            }
            return
        }
        let items = notes.map { (id: $0.id.uuidString, title: Self.title(for: $0)) }
        center.getDeliveredNotifications { delivered in
            let deliveredIDs = Set(delivered.map(\.request.identifier))
            let center = UNUserNotificationCenter.current()
            for item in items where !deliveredIDs.contains(item.id) {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.sound = .default
                content.userInfo = ["noteID": item.id]
                center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.identifier
        guard let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            self.onNotificationClicked?(id)
        }
    }
}

/// Small time picker attached to a note (⌘T).
final class ReminderPicker: NSViewController {
    var onSet: ((Date) -> Void)?
    var onRemove: (() -> Void)?
    var onCancel: (() -> Void)?

    private let existing: Date?
    private let timePicker = NSDatePicker()
    private let dayPicker = NSDatePicker()
    private let dayCheckbox = NSButton(checkboxWithTitle: "On a specific day", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "")

    init(existing: Date?) {
        self.existing = existing
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let initial = existing ?? Self.defaultTime()
        timePicker.datePickerElements = [.hourMinute]
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.dateValue = initial
        timePicker.target = self
        timePicker.action = #selector(updateHint)
        timePicker.setAccessibilityLabel("Reminder time")

        dayPicker.datePickerElements = [.yearMonthDay]
        dayPicker.datePickerStyle = .textFieldAndStepper
        dayPicker.dateValue = initial
        dayPicker.minDate = Calendar.current.startOfDay(for: Date())
        dayPicker.target = self
        dayPicker.action = #selector(updateHint)
        dayPicker.setAccessibilityLabel("Reminder day")

        dayCheckbox.target = self
        dayCheckbox.action = #selector(toggleDay)
        if let existing, !Calendar.current.isDate(existing, inSameDayAs: ReminderSchedule.nextOccurrence(
            hour: Calendar.current.component(.hour, from: existing),
            minute: Calendar.current.component(.minute, from: existing), after: Date())) {
            dayCheckbox.state = .on
        }

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let title = NSTextField(labelWithString: "Remind me at")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let set = NSButton(title: existing == nil ? "Set Reminder" : "Update", target: self, action: #selector(setTapped))
        set.keyEquivalent = "\r"
        set.bezelStyle = .push
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        var buttons: [NSView] = [cancel, set]
        if existing != nil {
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeTapped))
            remove.hasDestructiveAction = true
            buttons.insert(remove, at: 0)
        }
        let buttonRow = NSStackView(views: buttons)
        buttonRow.spacing = 8

        let stack = NSStackView(views: [title, timePicker, dayCheckbox, dayPicker, hint, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.setCustomSpacing(16, after: hint)
        view = stack
        toggleDay()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(timePicker)
    }

    static func defaultTime() -> Date {
        let soon = Date().addingTimeInterval(3600)
        let cal = Calendar.current
        let minute = (cal.component(.minute, from: soon) / 5) * 5
        return cal.date(bySettingHour: cal.component(.hour, from: soon), minute: minute, second: 0, of: soon) ?? soon
    }

    var chosenDate: Date {
        let cal = Calendar.current
        let h = cal.component(.hour, from: timePicker.dateValue)
        let m = cal.component(.minute, from: timePicker.dateValue)
        if dayCheckbox.state == .on {
            return ReminderSchedule.date(on: dayPicker.dateValue, hour: h, minute: m)
        }
        return ReminderSchedule.nextOccurrence(hour: h, minute: m, after: Date())
    }

    @objc private func toggleDay() {
        dayPicker.isHidden = dayCheckbox.state != .on
        updateHint()
    }

    @objc private func updateHint() {
        let date = chosenDate
        if date <= Date() {
            hint.stringValue = "That time has already passed."
            hint.textColor = .systemRed
        } else {
            hint.stringValue = "Shows as \(ReminderSchedule.label(for: date, now: Date())) on the note."
            hint.textColor = .secondaryLabelColor
        }
    }

    @objc private func setTapped() {
        let date = chosenDate
        guard date > Date() else {
            NSSound.beep()
            return
        }
        onSet?(date)
    }

    @objc private func removeTapped() { onRemove?() }
    @objc private func cancelTapped() { onCancel?() }
}
