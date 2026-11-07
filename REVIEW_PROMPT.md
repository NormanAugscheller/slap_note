# Review prompt for a second coding agent (Codex)

Copy everything inside the box into Codex (or use `/review` with these instructions).

```text
Code review only — report findings, do not change any files.

Project: SlapNote, a native macOS 14+ background agent app (Swift + AppKit, SwiftUI only for the settings
window) at ~/Docs/Programmieren/slap_note. Read SPEC.md first (the product specification), then
DECISIONS.md (why things are the way they are; open questions at the end). Branch: feature/v1.
Review the whole codebase: git diff main..feature/v1 (everything after the specification commit).

Build and test:
  xcodegen generate
  xcodebuild -scheme SlapNote build
  xcodebuild -scheme SlapNote test
Debug runtime smoke test (optional):
  <DerivedData>/Build/Products/Debug/SlapNote.app/Contents/MacOS/SlapNote -SlapNoteSelfTest YES -SlapNoteDataDirectory /tmp/slapnote-review

Files:
  SlapNoteCore/      testable logic (styles/shapes, geometry, scroll interpretation, persistence and
                     migrations, display placement, reminders, aging/curl, strike-through mapping,
                     launch classification, crumple geometry)
  SlapNote/App/      AppDelegate, global shortcuts, login-item detection, SelectionGrabber (pasteboard +
                     synthesized Cmd-C), menu bar icon
  SlapNote/Notes/    NoteManager (central controller), NoteController (one note), NoteView (layers),
                     PlacementSession (capture windows, cursor following), NoteAnimator/ThrowAnimator,
                     Reminders (UNUserNotificationCenter + picker), NoteLevels
  SlapNote/Settings/ AppSettings (UserDefaults), SwiftUI settings window
  SlapNote/Debug/    debug-only self-test
  SlapNoteTests/     XCTest

Check especially:
1. Permissions: Accessibility is only checked/requested on first use of "note from selection", never at launch.
   Notification permission only when a reminder is first set. Any path that prompts earlier?
2. Pasteboard handling (SelectionGrabber): is the user's clipboard always restored, including multiple items and
   all types? What happens if the frontmost app copies slowly (>0.5 s), copies nothing, or the user copies something
   during the polling window? Can clipboard contents end up in logs? Is the synthesized Cmd-C correct while the user
   still holds Ctrl-Opt from the shortcut?
3. File writes (NoteStore): atomic main + backup writes, corrupt-file recovery, a crash between the two writes,
   newer-version files, directory missing, disk full. Can a note ever be lost silently? Is anything written outside
   ~/Library/Application Support/SlapNote?
4. macOS API misuse: window levels and collection behaviors, non-activating panels becoming key, cooperative
   activation (NSApp.activate / yieldActivation), NSEvent global/local monitors (are all removed?), CADisplayLink
   lifetime, timers and NotificationCenter observers that are never invalidated, retain cycles between
   NoteManager / NoteController / PlacementSession / NSPopover, SMAppService usage, UNUserNotificationCenter delegate
   isolation (nonisolated async methods hopping to the main actor), CGEvent posting.
5. Main-actor correctness: the app target uses SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor with Swift 5 mode. Any
   MainActor.assumeIsolated that can run off the main thread?
6. Spec conformance of interactions: Cmd-Z must never be registered globally; Ctrl+scroll must be ignored; Shift+wheel
   (converted to horizontal by macOS) must change the width; clicks in placement mode must never reach other apps;
   strike-through must not trigger on drag; single vs. double click.
7. Reminders: duplicate notifications for reminders missed while the app was closed; reminders surviving restart;
   timer re-arming after sleep; time zone / DST changes.
8. Display reassignment when displays disappear/return, and notes larger than the screen.
9. No network access anywhere in the app; no private APIs; no dependency besides KeyboardShortcuts.
Also: edge cases, error handling, tests that are missing.

For each finding: file:line, severity (high/medium/low), a concrete failure scenario (what has to happen for it to go
wrong), and a suggested fix. No style remarks. If nothing solid stands out in an area, say so.
```
