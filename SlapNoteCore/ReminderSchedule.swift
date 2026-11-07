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

    /// Short label for the note corner: "14:30" today, "Fri 14:30" within the next 6 days,
    /// otherwise "12 Nov 14:30".
    public static func label(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            f.dateFormat = "HH:mm"
        } else {
            let startNow = calendar.startOfDay(for: now)
            let startDate = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: startNow, to: startDate).day ?? 0
            f.dateFormat = (days > 0 && days <= 6) ? "EEE HH:mm" : "d MMM HH:mm"
        }
        return f.string(from: date)
    }
}
