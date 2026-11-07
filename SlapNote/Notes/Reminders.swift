import AppKit
import SlapNoteCore
import UserNotifications

/// Schedules macOS notifications for reminders and fires the in-app "due" behavior.
final class ReminderCoordinator: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main actor when the user clicks a reminder notification.
    var onNotificationClicked: ((UUID) -> Void)?
    /// Called when reminders become due while the app runs (or were missed while it was closed).
    var onDue: (([UUID]) -> Void)?
    /// Called on the main actor when macOS accepted the notification for a note's reminder at a date.
    var onScheduled: ((UUID, Date) -> Void)?
    /// Called on the main actor when a still-pending reminder lost its system request (it was replaced
    /// after a change, or macOS refused it), so SlapNote has to announce it itself unless a new one is accepted.
    var onUnscheduled: ((UUID) -> Void)?

    private var timer: Timer?
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    private var authorizationRequested = false

    func start() {
        center.delegate = self
        removeLegacyRequests()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Development builds before the per-instance identifiers scheduled requests under the bare note UUID.
    /// The cache of this run does not know them, so they would fire next to the new request: remove them.
    private func removeLegacyRequests() {
        center.getPendingNotificationRequests { requests in
            let legacy = requests.map(\.identifier).filter { !$0.contains("@") && UUID(uuidString: $0) != nil }
            guard !legacy.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: legacy)
        }
    }

    /// Asks for permission the first time a reminder is set (never at launch).
    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private struct Scheduled: Equatable {
        var identifier: String
        var date: Date
        var title: String
    }

    /// What is currently scheduled with the system per note, so unchanged reminders are left alone.
    private var scheduled: [UUID: Scheduled] = [:]
    /// The registration each note's entry in `scheduled` belongs to; late answers of older ones are ignored.
    private var registrations: [UUID: Int] = [:]
    private var nextRegistration = 0

    /// Brings the scheduled notifications in line with the pending reminders of `notes`. Only changed
    /// reminders are removed and re-added, so a save right before a reminder is due cannot drop it.
    func sync(notes: [NoteRecord]) {
        let now = Date()
        var wanted: [UUID: Scheduled] = [:]
        for note in notes {
            guard let r = note.reminder, !r.fired, r.date > now else { continue }
            wanted[note.id] = Scheduled(identifier: ReminderSchedule.notificationIdentifier(noteID: note.id, date: r.date),
                                        date: r.date, title: Self.title(for: note))
        }
        let stale = scheduled.filter { id, s in wanted[id] != s }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale.values.map(\.identifier)) }
        for id in stale.keys {
            scheduled[id] = nil
            registrations[id] = nil
            // Still pending but changed: the old acceptance no longer counts. (Reminders that are due,
            // fired or removed keep their state: a due one was already delivered by the system.)
            if wanted[id] != nil { onUnscheduled?(id) }
        }
        for (id, item) in wanted where scheduled[id] == nil {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.sound = .default
            content.userInfo = ["noteID": id.uuidString]
            let trigger = UNCalendarNotificationTrigger(dateMatching: ReminderSchedule.triggerComponents(for: item.date),
                                                        repeats: false)
            nextRegistration += 1
            let registration = nextRegistration
            scheduled[id] = item
            registrations[id] = registration
            let date = item.date
            center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)) { [weak self] error in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.registrationFinished(id, registration: registration, date: date, error: error) }
                }
            }
        }
    }

    private func registrationFinished(_ id: UUID, registration: Int, date: Date, error: Error?) {
        guard registrations[id] == registration else { return }
        if let error {
            NSLog("SlapNote: scheduling a reminder notification failed: %@", error.localizedDescription)
            scheduled[id] = nil
            registrations[id] = nil
            onUnscheduled?(id)
        } else {
            onScheduled?(id, date)
        }
    }

    func cancel(noteID: UUID) {
        if let s = scheduled[noteID] { center.removePendingNotificationRequests(withIdentifiers: [s.identifier]) }
        scheduled[noteID] = nil
        registrations[noteID] = nil
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

    /// Posts the notification for due reminders macOS never accepted a scheduled request for.
    /// It uses the same identifier as the scheduled request would have, so if the system did deliver it
    /// after all (the acceptance callback had not arrived yet), the delivered check skips it, and a
    /// still-pending request is replaced instead of shown twice.
    func postMissed(_ notes: [NoteRecord]) {
        let items = notes.compactMap { note -> (id: String, noteID: String, title: String)? in
            guard let r = note.reminder else { return nil }
            return (ReminderSchedule.notificationIdentifier(noteID: note.id, date: r.date), note.id.uuidString,
                    Self.title(for: note))
        }
        guard !items.isEmpty else { return }
        center.getDeliveredNotifications { delivered in
            let deliveredIDs = Set(delivered.map(\.request.identifier))
            let center = UNUserNotificationCenter.current()
            for item in items where !deliveredIDs.contains(item.id) {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.sound = .default
                content.userInfo = ["noteID": item.noteID]
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
        guard let id = ReminderSchedule.noteID(fromNotificationIdentifier: raw) else { return }
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
