import CoreGraphics
import XCTest
import UserNotifications
@testable import SlapNoteCore

final class DisplayTests: XCTestCase {
    let main = DisplayInfo(uuid: "MAIN", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875), isMain: true)
    let external = DisplayInfo(uuid: "EXT", visibleFrame: CGRect(x: 1440, y: -200, width: 2560, height: 1415), isMain: false)

    func testPositionIsRelativeToContainingDisplay() {
        let pos = DisplayResolver.position(forCenter: CGPoint(x: 1440 + 1280, y: -200 + 707.5), displays: [main, external])
        XCTAssertEqual(pos?.displayUUID, "EXT")
        XCTAssertEqual(pos?.relativeX ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(pos?.relativeY ?? 0, 0.5, accuracy: 0.001)
    }

    func testResolveOnOwnDisplay() {
        let pos = DisplayPosition(displayUUID: "EXT", relativeX: 0.5, relativeY: 0.5)
        let r = DisplayResolver.resolve(pos, noteSize: CGSize(width: 200, height: 200), displays: [main, external])
        XCTAssertEqual(r?.displayUUID, "EXT")
        XCTAssertEqual(r?.isFallback, false)
        XCTAssertEqual(r?.center.x ?? 0, 2720, accuracy: 0.001)
    }

    func testMissingDisplayMovesNoteToMainInsideVisibleFrame() {
        let pos = DisplayPosition(displayUUID: "EXT", relativeX: 1.0, relativeY: 1.0)
        let size = CGSize(width: 300, height: 200)
        guard let r = DisplayResolver.resolve(pos, noteSize: size, displays: [main]) else { return XCTFail() }
        XCTAssertEqual(r.displayUUID, "MAIN")
        XCTAssertTrue(r.isFallback)
        let frame = CGRect(x: r.center.x - 150, y: r.center.y - 100, width: 300, height: 200)
        XCTAssertTrue(main.visibleFrame.contains(frame), "note must be fully inside the visible frame")
    }

    func testNoteReturnsWhenDisplayComesBack() {
        let pos = DisplayPosition(displayUUID: "EXT", relativeX: 0.2, relativeY: 0.3)
        let size = CGSize(width: 200, height: 200)
        XCTAssertEqual(DisplayResolver.resolve(pos, noteSize: size, displays: [main])?.displayUUID, "MAIN")
        // The stored position is untouched, so it resolves to the external display again.
        XCTAssertEqual(DisplayResolver.resolve(pos, noteSize: size, displays: [main, external])?.displayUUID, "EXT")
    }

    func testOversizedNoteAlignsTopLeft() {
        let c = DisplayResolver.clampCenter(CGPoint(x: 0, y: 0), size: CGSize(width: 2000, height: 2000), into: main.visibleFrame)
        XCTAssertEqual(c.x, 1000)
        XCTAssertEqual(c.y, 875 - 1000)
    }

    func testNoDisplaysResolvesNil() {
        XCTAssertNil(DisplayResolver.resolve(DisplayPosition(displayUUID: "A", relativeX: 0, relativeY: 0), noteSize: .zero, displays: []))
    }
}

final class ReminderTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testNextOccurrenceTodayWhenStillAhead() {
        let now = date(2026, 11, 6, 10, 0)
        XCTAssertEqual(ReminderSchedule.nextOccurrence(hour: 14, minute: 30, after: now, calendar: calendar), date(2026, 11, 6, 14, 30))
    }

    func testNextOccurrenceTomorrowWhenPassed() {
        let now = date(2026, 11, 6, 15, 0)
        XCTAssertEqual(ReminderSchedule.nextOccurrence(hour: 14, minute: 30, after: now, calendar: calendar), date(2026, 11, 7, 14, 30))
    }

    func testNextOccurrenceAtExactTimeIsTomorrow() {
        let now = date(2026, 11, 6, 14, 30)
        XCTAssertEqual(ReminderSchedule.nextOccurrence(hour: 14, minute: 30, after: now, calendar: calendar), date(2026, 11, 7, 14, 30))
    }

    func testExplicitDay() {
        XCTAssertEqual(ReminderSchedule.date(on: date(2026, 12, 24, 0, 0), hour: 18, minute: 5, calendar: calendar), date(2026, 12, 24, 18, 5))
    }

    private func note(reminder: ReminderRecord?) -> NoteRecord {
        NoteRecord(color: .pink, shape: .square, width: 200, height: 200,
                   position: DisplayPosition(displayUUID: "A", relativeX: 0.5, relativeY: 0.5), reminder: reminder)
    }

    func testReminderThatFiredWhileClosedIsDueOnLaunch() {
        let launch = date(2026, 11, 7, 9, 0)
        let missed = note(reminder: ReminderRecord(date: date(2026, 11, 6, 20, 0)))
        let future = note(reminder: ReminderRecord(date: date(2026, 11, 7, 12, 0)))
        let done = note(reminder: ReminderRecord(date: date(2026, 11, 6, 8, 0), fired: true, acknowledged: true))
        XCTAssertEqual(ReminderSchedule.dueNoteIDs(in: [missed, future, done, note(reminder: nil)], now: launch), [missed.id])
        XCTAssertEqual(ReminderSchedule.nextPendingDate(in: [missed, future, done], now: launch), date(2026, 11, 7, 12, 0))
    }

    func testFiredButUnacknowledgedKeepsAttention() {
        let a = note(reminder: ReminderRecord(date: Date(), fired: true, acknowledged: false))
        let b = note(reminder: ReminderRecord(date: Date(), fired: true, acknowledged: true))
        XCTAssertEqual(ReminderSchedule.attentionNoteIDs(in: [a, b]), [a.id])
    }

    func testLabelsIn24HourLocale() {
        let now = date(2026, 11, 6, 10, 0) // Friday
        let gb = Locale(identifier: "en_GB")
        XCTAssertEqual(ReminderSchedule.label(for: date(2026, 11, 6, 14, 30), now: now, calendar: calendar, locale: gb), "14:30")
        XCTAssertEqual(ReminderSchedule.label(for: date(2026, 11, 7, 9, 5), now: now, calendar: calendar, locale: gb), "Sat 09:05")
        XCTAssertEqual(ReminderSchedule.label(for: date(2026, 11, 20, 9, 5), now: now, calendar: calendar, locale: gb), "20 Nov 09:05")
    }

    func testLabelsFollow12HourLocale() {
        let now = date(2026, 11, 6, 10, 0)
        let us = Locale(identifier: "en_US")
        let label = ReminderSchedule.label(for: date(2026, 11, 6, 14, 30), now: now, calendar: calendar, locale: us)
        XCTAssertTrue(label.hasPrefix("2:30") && label.hasSuffix("PM"), label)
        XCTAssertFalse(ReminderSchedule.label(for: date(2026, 11, 7, 9, 5), now: now, calendar: calendar, locale: us).contains(","))
    }

    func testDisplayLocaleIsEnglish() {
        XCTAssertEqual(ReminderSchedule.displayLocale.language.languageCode, .english)
    }

    func testOnlyRemindersTheSystemNeverAcceptedNeedOwnNotification() {
        // Scheduled with macOS, passed while SlapNote was closed, dismissed by the user: not posted again.
        XCTAssertFalse(ReminderSchedule.needsOwnNotification(ReminderRecord(date: date(2026, 11, 6, 20, 0), scheduledWithSystem: true)))
        XCTAssertTrue(ReminderSchedule.needsOwnNotification(ReminderRecord(date: date(2026, 11, 6, 20, 0))))
        XCTAssertFalse(ReminderSchedule.needsOwnNotification(nil))
    }

    func testScheduledFlagRoundTripsAndDefaultsToFalse() throws {
        let record = ReminderRecord(date: date(2026, 11, 6, 20, 0), scheduledWithSystem: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(ReminderRecord.self, from: encoder.encode(record)), record)
        let old = try decoder.decode(ReminderRecord.self, from: Data(#"{"date":"2026-11-06T19:00:00Z"}"#.utf8))
        XCTAssertFalse(old.scheduledWithSystem)
    }

    func testTriggerComponentsPinTheAbsoluteTime() throws {
        // 2026-10-25 02:30 happens twice in Vienna; take the second one (after the clocks went back).
        let firstPass = date(2026, 10, 25, 2, 30)
        let secondPass = firstPass.addingTimeInterval(3600)
        for reminder in [firstPass, secondPass, date(2026, 11, 20, 9, 5)] {
            let comps = ReminderSchedule.triggerComponents(for: reminder)
            XCTAssertEqual(comps.timeZone?.secondsFromGMT(for: reminder), 0)
            // Read with any other calendar the components still name the same instant.
            var tokyo = Calendar(identifier: .gregorian)
            tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            XCTAssertEqual(tokyo.date(from: comps), reminder)
        }
    }

    func testSystemTriggerFiresAtTheStoredTime() throws {
        let reminder = Date().addingTimeInterval(3 * 24 * 3600).rounded(toSeconds: 1)
        let comps = ReminderSchedule.triggerComponents(for: reminder)
        XCTAssertEqual(UNCalendarNotificationTrigger(dateMatching: comps, repeats: false).nextTriggerDate(), reminder)
        // The Mac moves to another time zone after the reminder was scheduled.
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(UNCalendarNotificationTrigger(dateMatching: comps, repeats: false).nextTriggerDate(), reminder)
    }

    func testFractionalReminderTimeIsNormalizedEverywhere() throws {
        let raw = Date().addingTimeInterval(2 * 24 * 3600).rounded(toSeconds: 1).addingTimeInterval(0.75)
        var reminder = ReminderRecord(date: raw)
        XCTAssertEqual(reminder.date.timeIntervalSince1970, raw.timeIntervalSince1970.rounded(.down))
        let comps = ReminderSchedule.triggerComponents(for: reminder.date)
        XCTAssertEqual(UNCalendarNotificationTrigger(dateMatching: comps, repeats: false).nextTriggerDate(), reminder.date)
        reminder.date = raw.addingTimeInterval(60)
        XCTAssertEqual(reminder.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0)
        let encoded = try NoteStore.makeEncoder().encode(reminder)
        XCTAssertEqual(try NoteStore.makeDecoder().decode(ReminderRecord.self, from: encoded), reminder)
    }

    func testNotificationIdentifierIsPerReminderInstance() {
        let id = UUID()
        let a = ReminderSchedule.notificationIdentifier(noteID: id, date: date(2026, 11, 6, 20, 0))
        let b = ReminderSchedule.notificationIdentifier(noteID: id, date: date(2026, 11, 7, 20, 0))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(ReminderSchedule.noteID(fromNotificationIdentifier: a), id)
        XCTAssertEqual(ReminderSchedule.noteID(fromNotificationIdentifier: id.uuidString), id, "identifiers from before")
        XCTAssertNil(ReminderSchedule.noteID(fromNotificationIdentifier: "nonsense"))
    }
}

final class AgingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func days(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    func testNoCurlBeforeThreshold() {
        XCTAssertEqual(Aging.curl(lastTouched: days(6.9), now: now, policy: AgingPolicy()), 0)
        XCTAssertEqual(Aging.curl(lastTouched: days(7), now: now, policy: AgingPolicy()), 0)
    }

    func testCurlGrowsMonotonicallyToMaximum() {
        var last = 0.0
        for d in stride(from: 7.0, through: 20, by: 0.5) {
            let c = Aging.curl(lastTouched: days(d), now: now, policy: AgingPolicy())
            XCTAssertGreaterThanOrEqual(c, last)
            last = c
        }
        XCTAssertEqual(last, 1)
        XCTAssertEqual(Aging.curl(lastTouched: days(400), now: now, policy: AgingPolicy()), 1)
    }

    func testDisabledAndCustomThreshold() {
        XCTAssertEqual(Aging.curl(lastTouched: days(100), now: now, policy: AgingPolicy(enabled: false)), 0)
        XCTAssertGreaterThan(Aging.curl(lastTouched: days(2), now: now, policy: AgingPolicy(thresholdDays: 1)), 0)
        XCTAssertEqual(AgingPolicy(thresholdDays: 500).thresholdDays, 60)
        XCTAssertEqual(AgingPolicy(thresholdDays: 0).thresholdDays, 1)
    }

    func testTouchResetsAge() {
        var n = NoteRecord(color: .pink, shape: .square, width: 200, height: 200,
                           position: DisplayPosition(displayUUID: "A", relativeX: 0.5, relativeY: 0.5), created: days(30))
        XCTAssertEqual(Aging.curl(lastTouched: n.lastTouched, now: now, policy: AgingPolicy()), 1)
        n.touch(at: now)
        XCTAssertEqual(Aging.curl(lastTouched: n.lastTouched, now: now, policy: AgingPolicy()), 0)
    }

    func testCurlGeometryConservesPaperAndFoldsInward() {
        for shape in NoteShape.allCases {
            let rect = CGRect(x: 0, y: 0, width: 220, height: 220)
            let path = shape.path(in: rect)
            let flat = CurlGeometry.make(shapePath: path, rect: rect, curl: 0)
            XCTAssertNil(flat.flap, "\(shape)")
            let curled = CurlGeometry.make(shapePath: path, rect: rect, curl: 1)
            guard let flap = curled.flap else { return XCTFail("\(shape) has no flap") }
            XCTAssertFalse(flap.isEmpty, "\(shape)")
            let remainingBox = curled.remaining.boundingBoxOfPath
            XCTAssertLessThanOrEqual(remainingBox.maxX, rect.maxX + 0.5)
            // The flap is folded toward the note center, so it lies inside the original bounds.
            let flapBox = flap.boundingBoxOfPath
            XCTAssertGreaterThanOrEqual(flapBox.minY, rect.minY - 0.5, "\(shape)")
            XCTAssertLessThanOrEqual(flapBox.maxX, rect.maxX + 0.5, "\(shape)")
        }
    }

    func testReflectionIsAnInvolution() {
        let u = CGPoint(x: -1 / 2.0.squareRoot(), y: 1 / 2.0.squareRoot())
        let l = CGPoint(x: 180, y: 40)
        let p = CGPoint(x: 210, y: 5)
        let once = CurlGeometry.reflect(p, lineCenter: l, normal: u)
        let twice = CurlGeometry.reflect(once, lineCenter: l, normal: u)
        XCTAssertEqual(twice.x, p.x, accuracy: 0.0001)
        XCTAssertEqual(twice.y, p.y, accuracy: 0.0001)
    }
}

final class StrikeMapperTests: XCTestCase {
    func testUnchangedTextKeepsStrikes() {
        XCTAssertEqual(StrikeMapper.remap(struck: [0, 2], from: "a\nb\nc", to: "a\nb\nc"), [0, 2])
    }

    func testInsertingLineAboveShiftsStrike() {
        XCTAssertEqual(StrikeMapper.remap(struck: [1], from: "a\nb\nc", to: "new\na\nb\nc"), [2])
    }

    func testDeletingStruckLineDropsStrike() {
        XCTAssertEqual(StrikeMapper.remap(struck: [1, 2], from: "a\nb\nc", to: "a\nc"), [1])
    }

    func testEditingStruckLineInPlaceKeepsStrike() {
        XCTAssertEqual(StrikeMapper.remap(struck: [1], from: "milk\neggs\nbread", to: "milk\neggs x12\nbread"), [1])
    }

    func testSplittingLineDropsAmbiguousStrike() {
        XCTAssertEqual(StrikeMapper.remap(struck: [0], from: "ab\nc", to: "a\nb\nc"), [])
    }

    func testAppendingTypedCharactersKeepsEarlierStrikes() {
        XCTAssertEqual(StrikeMapper.remap(struck: [0], from: "done\n", to: "done\nnext"), [0])
    }

    func testLineRangesAndIndexUseUTF16() {
        let text = "😀a\nbc\n"
        XCTAssertEqual(StrikeMapper.lineRanges(of: text), [NSRange(location: 0, length: 3), NSRange(location: 4, length: 2), NSRange(location: 7, length: 0)])
        XCTAssertEqual(StrikeMapper.lineIndex(forUTF16Offset: 2, in: text), 0)
        XCTAssertEqual(StrikeMapper.lineIndex(forUTF16Offset: 5, in: text), 1)
        XCTAssertEqual(StrikeMapper.lineIndex(forUTF16Offset: 99, in: text), 2)
    }

    func testToggle() {
        XCTAssertEqual(StrikeMapper.toggle(1, in: [1, 2]), [2])
        XCTAssertEqual(StrikeMapper.toggle(0, in: [2]), [0, 2])
    }
}

final class LaunchContextTests: XCTestCase {
    func testAppleEventFlagWins() {
        XCTAssertEqual(LaunchContext.classify(appleEventSaysLoginItem: true, loginItemEnabled: false, secondsSinceSessionStart: 9999), .loginItem)
    }

    func testEnabledLoginItemShortlyAfterSessionStart() {
        XCTAssertEqual(LaunchContext.classify(appleEventSaysLoginItem: false, loginItemEnabled: true, secondsSinceSessionStart: 12), .loginItem)
        XCTAssertEqual(LaunchContext.classify(appleEventSaysLoginItem: false, loginItemEnabled: true, secondsSinceSessionStart: 3600), .manual)
        XCTAssertEqual(LaunchContext.classify(appleEventSaysLoginItem: nil, loginItemEnabled: false, secondsSinceSessionStart: 5), .manual)
        XCTAssertEqual(LaunchContext.classify(appleEventSaysLoginItem: nil, loginItemEnabled: true, secondsSinceSessionStart: nil), .manual)
    }

    func testSettingsVisibility() {
        XCTAssertTrue(LaunchContext.shouldShowSettings(kind: .manual, isFirstLaunch: false))
        XCTAssertFalse(LaunchContext.shouldShowSettings(kind: .loginItem, isFirstLaunch: false))
        XCTAssertTrue(LaunchContext.shouldShowSettings(kind: .loginItem, isFirstLaunch: true))
    }
}

final class CrumpleTests: XCTestCase {
    func testFramesHaveEqualPointCounts() {
        let path = NoteShape.heart.path(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let outline = Crumple.outline(of: path)
        let ball = Crumple.ball(center: CGPoint(x: 100, y: 100), radius: 30, seed: 1)
        XCTAssertEqual(outline.count, Crumple.pointCount)
        XCTAssertEqual(ball.count, Crumple.pointCount)
        let mid = Crumple.frame(from: outline, to: ball, t: 0.5, seed: 1)
        XCTAssertEqual(mid.count, Crumple.pointCount)
        XCTAssertGreaterThan(PathSampler.signedArea(outline), 0, "outline is counter-clockwise")
    }

    func testFrameEndpoints() {
        let a = Crumple.outline(of: NoteShape.square.path(in: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let b = Crumple.ball(center: CGPoint(x: 50, y: 50), radius: 10, seed: 3)
        let end = Crumple.frame(from: a, to: b, t: 1, seed: 3)
        for (p, q) in zip(end, b) {
            XCTAssertEqual(p.x, q.x, accuracy: 0.001)
            XCTAssertEqual(p.y, q.y, accuracy: 0.001)
        }
    }

    func testSamplerSpacingAndArea() {
        let pts = PathSampler.points(of: CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil), count: 40)
        XCTAssertEqual(pts.count, 40)
        XCTAssertEqual(abs(PathSampler.signedArea(pts)), 10_000, accuracy: 1)
    }
}

private extension Date {
    func rounded(toSeconds step: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 / step).rounded(.down) * step)
    }
}

final class CopyFallbackTests: XCTestCase {
    func testExactlyOneChangeIsTheRequestedCopy() {
        XCTAssertEqual(CopyFallback.outcome(before: 10, current: 10, elapsed: 0.1), .waiting)
        XCTAssertEqual(CopyFallback.outcome(before: 10, current: 11, elapsed: 0.1), .copied)
        XCTAssertEqual(CopyFallback.outcome(before: 10, current: 10, elapsed: CopyFallback.timeout), .timedOut)
    }

    func testChangeAfterTheTimeoutIsNotTakenAsTheCopy() {
        XCTAssertEqual(CopyFallback.outcome(before: 10, current: 11, elapsed: 1.2), .timedOut)
        XCTAssertEqual(CopyFallback.outcome(before: 10, current: 11, elapsed: CopyFallback.timeout), .timedOut)
        XCTAssertEqual(CopyFallback.outcome(before: 10, current: 12, elapsed: 1.2), .timedOut)
    }

    func testAnotherWriterMakesThePasteboardUnclear() {
        XCTAssertEqual(CopyFallback.outcome(before: 10, current: 12, elapsed: 0.1), .unclear)
        XCTAssertFalse(CopyFallback.mayRestore(before: 10, current: 12), "someone wrote after the copy: keep theirs")
        XCTAssertTrue(CopyFallback.mayRestore(before: 10, current: 11))
    }

    func testIncompleteSnapshotIsRejected() {
        XCTAssertTrue(CopyFallback.snapshotIsComplete(typesPerItem: [3, 1], readablePerItem: [3, 1]))
        XCTAssertFalse(CopyFallback.snapshotIsComplete(typesPerItem: [3, 1], readablePerItem: [2, 1]))
        XCTAssertTrue(CopyFallback.snapshotIsComplete(typesPerItem: [], readablePerItem: []))
    }
}

final class PeekStateTests: XCTestCase {
    func testHeldShortcutOutlastsTheHighlight() {
        var state = PeekState()
        state.highlighted = true
        state.held = true
        state.highlighted = false // the 3-second highlight ends while the shortcut is still held
        XCTAssertTrue(state.isActive)
        state.held = false
        XCTAssertFalse(state.isActive)
    }

    func testReleasingTheShortcutKeepsTheHighlight() {
        var state = PeekState()
        state.highlighted = true
        state.held = true
        state.held = false
        XCTAssertTrue(state.isActive)
    }
}
