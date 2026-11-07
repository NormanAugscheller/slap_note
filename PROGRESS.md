# Progress

Status of every acceptance criterion from SPEC.md §12. "Done" means implemented and verified as far as an
automated check can go. Evidence types:

- **unit test** — XCTest in `SlapNoteTests/`, run with `xcodebuild -scheme SlapNote test` (74 tests, 0 failures)
- **self-test** — the debug-only runtime test in `SlapNote/Debug/SelfTest.swift`, which drives the real note
  windows (`SlapNote -SlapNoteSelfTest YES -SlapNoteDataDirectory <dir>`; 27 checks, `SELFTEST PASSED`)
- **command** — command output recorded during the build session
- **manual** — needs a human at the Mac (feel, real input devices, Spaces, displays, permissions, login);
  see the referenced section of [MANUAL_TEST_CHECKLIST.md](MANUAL_TEST_CHECKLIST.md)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Builds from a clean checkout with `xcodegen generate` + `xcodebuild`; background agent without Dock icon | Done | command: `xcodegen generate` → "Created project"; `xcodebuild -scheme SlapNote build` → `** BUILD SUCCEEDED **`, exit 0. `LSUIElement = true` in `project.yml` / `Info.plist`, activation policy `.accessory`. Manual A1 (no Dock icon) |
| 2 | Settings window opens on manual launch and on reopen, not on login-item launch | Done | unit test: `LaunchContextTests.testAppleEventFlagWins`, `testEnabledLoginItemShortlyAfterSessionStart`, `testSettingsVisibility`. command: manual launch opened the settings window (window server list showed the 640 pt settings window). Reopen: `applicationShouldHandleReopen`. Manual A1–A4, J1–J4 (real login not testable in session, see DECISIONS D38) |
| 3 | ⌃⌥N summons a ghosted note that follows the cursor on all displays; typing writes on it | Done | self-test: "placement mode starts", "hanging note is above everything", "hanging note is ghosted at 50 %", "clicks go to the capture windows". Default shortcut in `Shortcuts.swift`. Manual B1–B3 (cursor following, typing, second display) |
| 4 | Left click slaps (animation, full opacity, desktop layer with 1.2 s mitigation); right click/Esc discards (crumple) | Done | self-test: "slap creates a stuck note", "slapped note stays visible above windows", "note sinks to the desktop layer after 1.2 s", "Esc discards the hanging note". unit test: `CrumpleTests` (3). Manual B4–B7 (animation feel, clicks never reach other apps) |
| 5 | Scroll resizes proportionally with font scaling; ⇧/⌥ + scroll width/height only; mouse and trackpad; limits enforced | Done | unit test: `GeometryTests.testProportionalResizeScalesFontBySameFactor`, `testProportionalResizeKeepsAspectAtMaximum`, `testProportionalResizeKeepsAspectAtMinimum`, `testWidthOnlyLeavesHeightAndFont`, `testHeightOnlyClampsToLimits`; `ScrollAndStyleTests.testEffectiveDeltaUsesHorizontalWhenShiftConvertedTheWheel`, `testShiftWheelResizesWidthViaHorizontalDelta`, `testShiftTrackpadResizesWidth`, `testWheelResizeIsSteppedAndCapped`, `testPreciseResizeIsSmoothAndSymmetric`, `testDefaultBindings`. self-test: "proportional resize scales size and font", "height clamps at 600 pt". Manual B8–B11, B14 |
| 6 | ⌘+scroll and ⌘⌥+scroll cycle color and shape in placement mode; random style works | Done | unit test: `ScrollAndStyleTests.testWheelCyclesOneStepPerNotch`, `testTrackpadCyclingAccumulatesThirtyPoints`, `testAccumulatorResetsOnNewGesture`, `testColorAndShapeCyclingWraps`, `testRandomStyleNeverRepeatsPrevious`, `testAssigningModifierSwapsInsteadOfConflicting`; `GeometryTests.testShapeSwitchKeepsWidthAndUsesShapeAspect`. Manual B12, B13, B15 |
| 7 | Stuck notes: hover, drag, click line to strike, double click to edit, Esc/click outside ends, right click discards | Done | unit test: `StrikeMapperTests` (8, incl. `testLineRangesAndIndexUseUTF16`, `testToggle`). self-test: "right click discards and remembers the note". Manual C1–C5, C10–C13 (hover feel, drag threshold, double click, ending edit mode) |
| 8 | Auto-grow in height works for all shapes; text stays inside the shape | Done | unit test: `GeometryTests.testAutoGrowGrowsInHeightForEveryShape`, `testAutoGrowMayExceedManualMaximumButNotScreen`, `testAutoGrowShrinksBackButNotBelowManualHeight`, `testAutoGrowKeepsManualHeightWhenTextFits`, `testSafeTextRectCornersAreInsideEveryShape`, `testShapesFillTheirRect`. self-test: "auto-grow increases the height", "auto-grow keeps the width". Manual C6–C9 |
| 9 | Undo restores the last discarded note via ⌃⌥Z and ⌘Z (app active only) | Done | self-test: "restore brings the note back", "restored note keeps its text". ⌘Z: local event monitor only (`AppDelegate.installUndoMonitor`), never a global registration. Manual D1–D4 |
| 10 | Always-on-top setting, Peek (hold) and Hide/show all work | Done | self-test: "always-on-top applies instantly", "peek raises notes", "releasing peek restores the layer", "hide all hides notes", "show all shows notes". Manual D5–D8 (hidden state across restart, menu bar icon) |
| 11 | Reminders: ⌘T picker, time shown top-right, wiggle + glow + notification when due, survive restart | Done | unit test: `ReminderTests` (9: next occurrence today/tomorrow/exact time, explicit day, fired-while-closed, attention after restart, labels in 24-hour and 12-hour locales, English display locale). self-test: "reminder fires when due", "due note wiggles and glows", "reminder time is shown on the note", "reminder state is persisted". Manual E1–E7 (picker, notification, permission prompt, missed reminder) |
| 12 | Aging curl after N days, reset on touch | Done | unit test: `AgingTests.testNoCurlBeforeThreshold`, `testCurlGrowsMonotonicallyToMaximum`, `testDisabledAndCustomThreshold`, `testTouchResetsAge`, `testCurlGeometryConservesPaperAndFoldsInward`, `testReflectionIsAnInvolution`. Manual F1–F3 |
| 13 | Note from selection works with Accessibility permission and explains how to grant it otherwise | Done | Implementation `SelectionGrabber.swift` + `AccessibilityExplanationWindow`; never prompts at launch. Manual G1–G4 (needs granting the permission, which only the owner can do) |
| 14 | Notes persist across restarts (text, style, size, rotation, position, strike-through, reminders); corrupt-file recovery | Done | unit test: `PersistenceTests` (11: `testNewerVersionFileIsPreservedBeforeOverwrite`, `testCurrentVersionFileMakesNoExtraCopy`, `testRoundTripKeepsEveryField`, `testFileHasVersionField`, `testCorruptMainFileFallsBackToBackup`, `testCorruptMainAndBackupGivesEmptyWithoutCrash`, `testMissingDirectoryLoadsEmpty`, `testOldFileWithoutVersionAndOptionalFieldsLoads`, `testMigrationStepsRunInOrder`, `testNewerFileWithUnknownFieldsStillLoads`, `testSanitizeRepairsBrokenValues`). self-test: "notes.json contains the stuck note". command: relaunch with the self-test data directory restored the note window at the desktop level (window level −2147483602) and `notes.json` + `notes.json.bak` existed. Manual H1–H3 |
| 15 | Multi-display reassignment works; Space behavior as in §5.6 | Done | unit test: `DisplayTests` (6: relative position, own display, missing display → main inside visible frame, return of display, oversized note, no displays). Manual I1–I5 (needs unplugging the monitor and switching Spaces) |
| 16 | Settings window contains all sections of §8 incl. the complete shortcut list; settings apply instantly | Done | `SettingsView.swift`: Notes (swatches, shape icons, random, preview), Text, Behavior, Shortcuts (Global / Placement / Stuck / Edit, recorders, modifier pickers, Reset to Defaults), About. Instant apply: `AppSettings.didChange` → `NoteManager.settingsChanged`; self-test "always-on-top applies instantly". Manual A5–A10 |
| 17 | Respects Reduce Motion | Done | Every animation in `NoteAnimator` / `ThrowAnimator` checks `Motion.reduced` and falls back to fades; sway off in `PlacementSession`; live updates via `accessibilityDisplayOptionsDidChangeNotification`. Manual K1–K2 |
| 18 | All unit tests pass; build has no warnings in project code | Done | command: `xcodebuild -scheme SlapNote test` → `Executed 74 tests, with 0 failures`, `** TEST SUCCEEDED **`, exit 0. `xcodebuild -scheme SlapNote build` → exit 0; `grep warning:` over the log finds no warning in a file under the project (only xcodebuild's own "multiple matching destinations" notice and Apple's appintents metadata note) |
| 19 | README.md, DECISIONS.md, PROGRESS.md, MANUAL_TEST_CHECKLIST.md, ASSETS_NEEDED.md exist and are complete | Done | Files in the repository root. The owner later chose to publish under MIT, so `LICENSE` exists too (DECISIONS, Q2) |
| 20 | REVIEW_PROMPT.md exists: ready-to-paste prompt for Codex (bugs, security: permissions, pasteboard, file writes; macOS API misuse) | Done | `REVIEW_PROMPT.md` |

## Milestones

| Milestone | Status | Commit |
|---|---|---|
| 1 · XcodeGen skeleton, agent app, settings shell, persistence | Done | `M1: XcodeGen project, core library, persistence and settings window` |
| 2 · Placement mode, slap/discard, scroll controls | Done | `M2-M5: note windows, placement, …` |
| 3 · Stuck-note interactions, edit mode, auto-grow, shapes | Done | same commit |
| 4 · Layers, peek, hide/show, undo | Done | same commit |
| 5 · Reminders, aging, note from selection, multi-display | Done | same commit |
| 6 · Animation polish | Done (automated part) | `M6: …` — the feel itself needs the manual checklist |
| 7 · Docs, checklists, review prompt | Done | `M7: …` |

Milestones 2–5 landed in one commit because the note window, placement session and manager were written as one
unit and only build together.

## Not verifiable in this session

These need the owner at the Mac and are covered by the manual checklist: animation feel and frame rate, real
mouse-wheel/trackpad input, clicks not reaching apps under the capture windows, Spaces, unplugging a display,
granting Accessibility and notification permissions, a real login-item launch after logging in.
