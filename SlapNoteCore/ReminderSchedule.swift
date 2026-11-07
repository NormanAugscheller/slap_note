import Foundation

public enum ReminderSchedule {
    /// Next occurrence of hour:minute strictly after `now` (today if still ahead, otherwise tomorrow).
    public static func nextOccurrence(hour: Int, minute: Int, after now: Date, calendar: Calendar = .current) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime, direction: .forward)
            ?? now.addingTimeInterval(60)
    }

    /// Combines an explicit day with a time of day.
    public static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps) ?? day
    }

    public static func isDue(_ reminder: ReminderRecord?, now: Date) -> Bool {
        guard let r = reminder else { return false }
        return !r.fired && r.date <= now
    }

    /// Notes whose reminder is due — including reminders that passed while the app was not running.
    public static func dueNoteIDs(in notes: [NoteRecord], now: Date) -> [UUID] {
        notes.filter { isDue($0.reminder, now: now) }.map(\.id)
    }

    /// Notes that fired but were not acknowledged yet (they keep wiggling, also after a restart).
    public static func attentionNoteIDs(in notes: [NoteRecord]) -> [UUID] {
        notes.filter { ($0.reminder?.fired ?? false) && !($0.reminder?.acknowledged ?? true) }.map(\.id)
    }

    /// The earliest pending reminder date, used to arm a single timer.
    public static func nextPendingDate(in notes: [NoteRecord], now: Date) -> Date? {
        notes.compactMap { n -> Date? in
            guard let r = n.reminder, !r.fired, r.date > now else { return nil }
            return r.date
        }.min()
    }

    /// Notification identifier of one reminder instance: the note plus the reminder time. A new time is
    /// a new instance, so an old delivered notification never hides a new one.
    public static func notificationIdentifier(noteID: UUID, date: Date) -> String {
        "\(noteID.uuidString)@\(Int(date.timeIntervalSince1970.rounded(.down)))"
    }

    /// The note a notification identifier belongs to (also accepts the bare UUID used before).
    public static func noteID(fromNotificationIdentifier identifier: String) -> UUID? {
        UUID(uuidString: String(identifier.split(separator: "@", maxSplits: 1).first ?? ""))
    }

    /// Date components for the system's one-time calendar trigger.
    public static func triggerComponents(for date: Date, calendar: Calendar = .current) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    /// Due reminders SlapNote has to announce itself: only those macOS never accepted a scheduled
    /// notification for. Everything else the system already delivered (or is delivering).
    public static func needsOwnNotification(_ reminder: ReminderRecord?) -> Bool {
        guard let r = reminder else { return false }
        return !r.scheduledWithSystem
    }

    /// English (the UI language) with the user's region and 12/24-hour preference.
    public static var displayLocale: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(languageCode: .english)
        return Locale(components: components)
    }

    /// Short label for the note corner, following the user's 12/24-hour setting via `locale`:
    /// time only today ("14:30" / "2:30 PM"), weekday + time within the next 6 days ("Fri 14:30"),
    /// otherwise day + month + time ("20 Nov 14:30").
    public static func label(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = ReminderSchedule.displayLocale) -> String {
        func format(_ template: String) -> String {
            let f = DateFormatter()
            f.locale = locale
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate(template)
            return f.string(from: date).replacingOccurrences(of: ",", with: "")
        }
        let time = format("jmm")
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let startNow = calendar.startOfDay(for: now)
        let startDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startNow, to: startDate).day ?? 0
        // Date and time are formatted separately so locales cannot insert words like "at".
        return format((days > 0 && days <= 6) ? "EEE" : "dMMM") + " " + time
    }
}
