# Decisions

Every non-obvious technical decision, with the reasoning. Open questions for the owner are at the end.

## Project structure

**D1 · Logic in a static library (`SlapNoteCore`), tests without a host app.**
Everything that can be expressed without windows (shapes, geometry, scroll interpretation, persistence,
display placement, reminders, aging, strike-through mapping, launch classification, crumple geometry)
lives in `SlapNoteCore`. The test bundle links only that library, so `xcodebuild test` never launches
the app, registers global shortcuts or opens windows. A *static* library instead of a dynamic framework
avoids library-validation problems when a hardened-runtime app loads an ad-hoc signed framework.

**D2 · Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for the app target.**
AppKit is main-thread code; default main-actor isolation removes hundreds of annotations. Swift 6
strict mode would turn every AppKit callback (timers, notification observers, `UNUserNotificationCenter`
delegate) into a hard error for no practical gain in a single-threaded UI app. The core library stays
nonisolated (pure value types). Build has zero warnings in project code.

**D3 · `SWIFT_INSTALL_OBJC_HEADER = NO` for the core library.** XcodeGen adds a "Copy Swift
Objective-C Interface Header" script phase to static Swift libraries; with user script sandboxing on,
that phase fails. No Objective-C code consumes the header, so it is switched off.

**D4 · Hardened runtime is applied by Xcode in Release builds only.** `ENABLE_HARDENED_RUNTIME = YES`
is set, but Xcode omits `-o runtime` for Debug builds (debug dylib / previews). Verified:
`codesign -dv` on a Release build shows `flags=0x10002(adhoc,runtime)`.

**D5 · Work happens on branch `feature/v1`.** The owner's project rules forbid working directly on the
default branch. `main` holds only the specification commit. Merge `feature/v1` into `main` before publishing.

**D6 · Bundle identifier `io.github.normanaugscheller.SlapNote`.** Reverse-DNS IDs should belong to a domain
the author controls; for a project without its own domain the GitHub Pages domain is the free, conventional
choice. Settings live in that `UserDefaults` domain. Changing it later would reset settings and the
Accessibility grant, so it was fixed before the first release (Q3).

## Windows, layers and focus

**D7 · One borderless, transparent `NSPanel` per note, non-activating.** Clicking, dragging or striking
through a stuck note must not steal keyboard focus from the app the user works in, so note panels use
`.nonactivatingPanel`. A note can still become the key window when it needs the keyboard (placement,
edit mode). Collection behavior `.stationary` + `.ignoresCycle`: notes behave like desktop items in
Mission Control and are skipped by ⌘\`. No `.canJoinAllSpaces` (spec §5.6).

**D8 · Window levels** (`NoteLevels.swift`): desktop notes at `CGWindowLevelForKey(.desktopIconWindow) + 1`
(above the Finder's icons, below every app window); always-on-top and the 1.2 s "just slapped" state at
`.floating`; Peek at `.statusBar`; placement capture windows at `.popUpMenu`; the hanging note one above;
the paper-ball overlay one above that. Full-screen apps live in their own Space, so notes never show there.

**D9 · Focus is taken only for typing and handed back afterwards.** Placement mode and edit mode call
`NSApp.activate()` (the hotkey / double click is user input, so macOS 14+ cooperative activation allows it)
and remember the previously frontmost app. On slap, discard or end of editing SlapNote calls
`NSApp.yieldActivation(to:)` and activates that app again, so the user can keep typing where they were.
The note panel can receive keystrokes even if activation were refused (non-activating panels can be key).

**D10 · ⌘Z works only while SlapNote is the active app — by design that is rare.** The spec forbids a
global ⌘Z. Because stuck notes are non-activating (D7), SlapNote is active only while the settings window,
a hanging note or a note in edit mode has focus. In a text view with something to undo, ⌘Z undoes text
(and ⌘⇧Z redoes); otherwise it restores the last discarded note. ⌃⌥Z works everywhere. See Q6.

**D11 · Placement capture windows** are one non-activating panel per screen with a background alpha of
0.002 (fully clear windows can let clicks fall through), so clicks and scrolls never reach other apps
(spec §4.1.7). The hanging note itself has `ignoresMouseEvents = true`, so the click under the cursor
reaches the capture window. The note follows the cursor from a `CADisplayLink` (`NSView.displayLink`,
macOS 14) that reads `NSEvent.mouseLocation` each frame — no lag, no event tap, works across displays.
Capture windows are rebuilt when screens change.

**D12 · Clicking outside ends edit mode** via three signals: a global mouse-down monitor (other apps,
desktop), a local monitor (our other windows, except the reminder popover) and `didResignActive`.

**D13 · The hanging note gets `.fullScreenAuxiliary`** so a note summoned while a full-screen app is in
front is visible. Which Space the resulting stuck note belongs to in that case is decided by macOS; see Q7.

## Rendering and animation

**D14 · Nested transform containers.** `body` (static rotation, sway, wiggle) → `lift` (scale: summon,
slap, hover, bump, crumple turn) → `flutter` (3D edge flutter) → paper layers + text view + reminder label.
Independent animations never fight over one `transform`. All transforms are computed around the layer's
center explicitly (`Motion.transform`), independent of the anchor point AppKit chooses for layer-backed views.

**D15 · Shapes, shadows, curl, glow and the paper ball are vector paths** (`CGPath`, including the
macOS 13 boolean operations `union`, `subtracting`, `intersection`). The curl is a 45° dog-ear at the
bottom-right: the corner beyond the fold line is cut away and its mirror image is drawn as the flap with a
gradient. For round shapes the fold starts where the outline is closest to the corner, so it works for all
six shapes.

**D16 · Crumple is a path morph between polygons with the same point count** (96 points, outline sampled
by arc length and aligned by angle, mid-frames get random wrinkles). The flight happens in a transparent
click-through overlay window per screen so the ball can leave the note's window bounds.

**D17 · Sway rotates around the note center**, driven by a damped spring toward an angle proportional to
the smoothed horizontal cursor speed, clamped to ±1°.

**D18 · Reduce Motion** replaces summon, slap, throw-away and restore with fades, disables sway, hover scale
and flutter, wiggle (glow stays), and curl transitions jump.

**D19 · The text keeps the note's rotation; strike-through hit-testing un-rotates the click point** before
asking the layout manager for the line (±2° would otherwise hit the wrong line at the far edges). Caret
placement in edit mode uses the same conversion.

**D20 · Single click toggles strike-through immediately; a double click reverts that toggle** and enters
edit mode. Waiting for the double-click interval would delay feedback by up to half a second.

**D21 · Shape cycling in placement mode keeps the width and applies the new shape's aspect ratio**, so
"Square" and "Rectangle (landscape)" are actually different while cycling. Color cycling keeps the size.

## Behavior choices the spec left open

**D22 · Summoning or restoring a note while all notes are hidden shows all notes again.** Creating a note
is an explicit request to see notes; a new note that immediately disappeared would be confusing.

**D23 · Peek also reveals hidden notes temporarily.** Holding the shortcut is explicit.

**D24 · An empty note thrown away right after summoning does not replace the remembered discarded note**,
so an accidental ⌃⌥N + Esc does not destroy the undo of a real note.

**D25 · Hovering does not acknowledge a due reminder.** Click, drag, double click or discard do. A pointer
passing over the note by accident should not silence it.

**D26 · Reminder times follow the user's 12/24-hour preference** (`14:30` or `2:30 PM`; `Fri 14:30` within
six days; `20 Nov 14:30` beyond). Weekday and month names stay English like the rest of the UI
(`ReminderSchedule.displayLocale` = English + the user's region settings). Date and time are formatted
separately so locales cannot insert words such as "at" (Q4).

**D27 · Placement-mode scroll modifiers are configurable per action**; choosing a combination that is in use
swaps the two actions so no action becomes unreachable. Control is never offered (accessibility zoom).

**D28 · Font family is chosen from a menu of installed families** (plus "System") instead of the floating
NSFontPanel, which does not fit a settings form and would also allow picking size and style.

**D29 · Paper texture is a bundle resource (`paper_texture.png`), not an asset catalog image**, so the build
never warns about a missing file, and there is a settings toggle for it (default on). A generated grain
placeholder ships until the real asset exists.

**D30 · About links to `https://github.com/NormanAugscheller/slap_note`** (given by the owner).

## Persistence

**D31 · Two atomic files.** `save` encodes once, verifies the data decodes, then writes `notes.json` and
`notes.json.bak` with `Data.write(options: .atomic)` (temporary file + rename). A crash mid-write leaves
the previous file intact. If `notes.json` cannot be decoded at launch it is moved to
`notes.corrupt-<timestamp>.json` (never overwriting the backup) and the backup is loaded and written back.

**D32 · Saving is debounced by 500 ms** and done synchronously in `applicationWillTerminate`.

**D33 · Schema version 1; migrations operate on the raw JSON object** (`NotesMigrator`). A file without
`version` is treated as version 1. All fields except `id` and `position` have defaults (tolerant decoding),
unknown colors/shapes fall back to yellow/square, and values are sanitized (sizes clamped, strike indices
filtered). Fields are only ever added; renames need a migration step. See Q5 for newer files.

**D34 · `ReminderRecord.acknowledged` was added** next to `fired` so a reminder that fired but was not
noticed keeps wiggling after a restart. Missing in a file → defaults to `fired`.

## Reminders, permissions, launch

**D35 · Reminders use the system scheduler plus an in-app timer.** A `UNCalendarNotificationTrigger` is
scheduled per pending reminder (delivered even if SlapNote is not running); one in-app timer armed for the
earliest pending reminder triggers wiggle + glow. At launch, reminders that passed while the app was closed
fire their wiggle, and their notification is posted only if the system has not already delivered it.
Permission is requested the first time a reminder is set, never at launch.

**D36 · Clicking a notification raises all notes (Peek) for 3 s and makes that note wiggle and glow.**
Public APIs cannot switch to another Space, so a note on a different Space is not brought into view.

**D37 · Note from selection** checks `AXIsProcessTrusted()`. Without permission it shows a short
explanation window; its button triggers the system prompt (which also adds SlapNote to the Accessibility
list) and opens the Privacy › Accessibility pane. With permission it snapshots every pasteboard item and
representation, posts ⌘C with only the Command flag (so the still-held ⌃⌥ does not leak in), polls the
pasteboard change count for up to 0.5 s, reads the string and restores the snapshot. If nothing changed,
the pasteboard is not touched and an empty note is created. Contents are never logged; text is capped at
10 000 characters.

**D38 · Login-item launch detection** (spec §7). There is no API that says "launched by
`SMAppService.mainApp`". SlapNote combines two signals (`LaunchDetector`, decision in
`LaunchContext.classify`, tested in `LaunchContextTests`):
1. the open-application Apple event's `keyAELaunchedAsLogInItem` property (set for classic login items;
   not documented for `SMAppService`), and
2. a heuristic: the login item is enabled **and** the user's `loginwindow` process (it restarts with each
   login session) started at most 90 s ago.
Trade-off: a manual launch within 90 s after logging in, with "Launch at login" on, is treated as a
login-item launch (the settings window stays closed; launching again opens it via the reopen event). A real
login could not be exercised in this session — see the manual checklist.

**D39 · First launch ever always opens the settings window** with a one-screen intro banner, whatever the
launch kind.

## Testing

**D40 · Debug-only runtime self-test** (`SlapNote/Debug/SelfTest.swift`, compiled only in Debug). Started
with `-SlapNoteSelfTest YES -SlapNoteDataDirectory <dir>`, it drives real windows through placement,
resize, slap, the 1.2 s sink, auto-grow, Peek, always-on-top, hide/show, a due reminder, discard, restore,
Esc in placement and persistence, and exits 0/1. Delete the file to remove it.

**D41 · Reminder scheduling is incremental.** `ReminderCoordinator.sync` remembers what it scheduled and
only removes/re-adds reminders whose date or title changed. Re-scheduling everything on every save could drop a
notification when a save landed in the second before it was due. As a second safety net, a reminder that fires
on time in the app is posted by SlapNote itself after 3 s if the system has not delivered it by then.

**D42 · The default Peek shortcut ⌃⌥Space is kept as specified**, although macOS can assign it to "Select next
source in Input menu" when several input sources are enabled. Documented in the README; see Q9.

## Former open questions — decided

The owner delegated these decisions ("choose the most sensible free option"; the repository is public).

- **Q1 · Spaces after relaunch → no private APIs.** Private CGS calls can break with any macOS update, would make
  the app unfit for notarized distribution and contradict the "no private APIs" rule of a public project. The
  limitation stays documented in the README.
- **Q2 · License → MIT** (`LICENSE`). A public repository without a license is legally "all rights reserved",
  so nobody could use or contribute. MIT is the simplest permissive license and matches the only dependency
  (KeyboardShortcuts, MIT).
- **Q3 · Bundle identifier → `io.github.normanaugscheller.SlapNote`** (D6).
- **Q4 · Time format → follow the system's 12/24-hour setting** (D26).
- **Q5 · Files from a newer version → keep an untouched copy.** When `notes.json` was written by a newer format
  version, SlapNote writes `notes.v<version>.json` once before it ever overwrites the file, then works normally.
  Going back to the newer app loses nothing; refusing to save would have been worse (every edit lost).
  Tested in `PersistenceTests.testNewerVersionFileIsPreservedBeforeOverwrite`.
- **Q6 · ⌘Z reach → unchanged.** Not stealing focus when the user clicks a note matters more than ⌘Z; ⌃⌥Z works
  everywhere.
- **Q7 · Full-screen Spaces → macOS default.** Blocking placement there would be surprising; the case is rare.
- **Q8 · Login-item window → 90 s, unchanged.** Covers slow logins with many login items; the only cost is that a
  manual launch in the first 90 s after login does not open the settings (opening the app again does).
- **Q9 · Peek default → ⌃⌥Space as specified**, documented in the README with how to change it. Most users have
  a single input source, where there is no conflict.

## Open questions for the owner

None at the moment.
