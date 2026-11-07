# SlapNote

Paper sticky notes for the macOS desktop. Summon a note with a shortcut, it hangs ghosted on your cursor,
you type on it and slap it onto your desktop with a left click. Right click throws it away. Notes live on
the desktop layer, so you see them whenever no window covers that spot.

The point of SlapNote is the *feel*: summoning, slapping, hovering and throwing away should feel physical.
Functionality is deliberately small. No cloud, no accounts, no network access of any kind.

![Summoning and slapping a note](docs/media/slap.gif)
<!-- Placeholder: record a GIF of summon → type → slap and save it as docs/media/slap.gif -->

![Notes on the desktop](docs/media/desktop.png)
<!-- Placeholder: screenshot of several notes in different colors and shapes -->

## Features

- **Placement mode** — ⌃⌥N summons a ghosted note that follows the cursor across all displays. Type on it,
  left-click to slap it, right-click or Esc to throw it away.
- **Scroll controls while it hangs** — resize proportionally (the font scales with it), change only width or
  height, cycle colors and shapes. Mouse wheels and trackpads both work.
- **8 colors, 6 shapes** — Classic Yellow, Pink, Orange, Sky Blue, Mint Green, Lavender, Coral, Paper White;
  Square, Rectangle, Circle, Heart, Cloud, Speech Bubble. All drawn as vectors. Optional random style.
- **Stuck notes** — lift on hover, drag to move (also to another display), click a line to strike it through
  like a to-do, double-click to edit, right-click to throw away. Each note gets a small random tilt and a soft
  shadow.
- **Auto-grow** — notes grow in height when the text does not fit and shrink back when you delete text.
- **Undo** — the last thrown-away note comes back with ⌃⌥Z (or ⌘Z while SlapNote is active).
- **Layers** — notes sit on the desktop by default; optionally always on top. Hold ⌃⌥Space to peek at all
  notes above your windows. ⌃⌥H hides or shows all notes, e.g. for screen sharing.
- **Reminders** — ⌘T on a hanging or edited note sets a time. When it is due the note wiggles and glows and a
  macOS notification appears.
- **Aging** — notes untouched for a week (configurable) slowly curl up at one corner. Touch them and they flatten.
- **Note from selection** — ⌃⌥S turns the selected text in any app into a new note.
- **Launch at login**, optional menu bar icon, Reduce Motion support.

## Shortcuts and gestures

| Context | Action | Default |
|---|---|---|
| Global | New note | ⌃⌥N |
| Global | Note from selection | ⌃⌥S |
| Global | Peek (hold) | ⌃⌥Space |
| Global | Hide / show all notes | ⌃⌥H |
| Global | Restore last discarded note | ⌃⌥Z |
| SlapNote active | Restore last discarded note | ⌘Z |
| Placement | Slap / discard | Left click / right click or Esc |
| Placement | Resize proportionally (font scales too) | Scroll |
| Placement | Change width / height only | ⇧ + scroll / ⌥ + scroll |
| Placement | Next color / next shape | ⌘ + scroll / ⌘⌥ + scroll |
| Placement & edit | Reminder | ⌘T |
| Stuck note | Edit / move / strike line / discard | Double click / drag / click line / right click |
| Edit | Finish editing | Click outside or Esc |

Global shortcuts and the placement-mode modifiers can be changed in Settings › Shortcuts.
Size limits for manual resizing are 80–600 pt per side; auto-grow may go taller, up to the screen height.

## Requirements

- macOS 14 Sonoma or later (developed on macOS 26 Tahoe, Apple Silicon)
- Xcode 26 or later to build (Swift 6.2 toolchain; the code uses Swift 5 language mode)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

The only dependency, [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT), is fetched
by Swift Package Manager during the first build. That is the only time anything touches the network; the app
itself makes no network calls.

## Build and install

```bash
git clone https://github.com/NormanAugscheller/slap_note.git
cd slap_note
xcodegen generate
xcodebuild -scheme SlapNote -configuration Release -derivedDataPath build build
```

The app is at `build/Build/Products/Release/SlapNote.app`. Copy it to `/Applications`:

```bash
cp -R build/Build/Products/Release/SlapNote.app /Applications/
```

Run the unit tests:

```bash
xcodebuild -scheme SlapNote test
```

Or open `SlapNote.xcodeproj` in Xcode (after `xcodegen generate`) and press ⌘R. The `.xcodeproj` is generated
and not committed; `project.yml` is the source of truth.

### First launch (Gatekeeper)

Local builds are ad-hoc signed, not notarized. If you copy a build to another Mac, or download one, macOS may
refuse to open it ("cannot be opened because the developer cannot be verified"). Right-click the app in
Finder → **Open** → **Open**, or allow it under System Settings › Privacy & Security. Builds you make yourself
on the same Mac usually open directly.

On the first launch the settings window opens with a short intro. SlapNote has no Dock icon; open it again
(Finder, Spotlight, Launchpad) to get back to the settings, or turn on the menu bar icon.

## Permissions

SlapNote asks for permissions only when a feature needs them, never at launch:

- **Accessibility** — only for *Note from selection*. SlapNote presses ⌘C for you in the frontmost app, reads the
  copied text and puts your clipboard contents back. Nothing is stored or sent anywhere. Without the permission
  SlapNote shows a short explanation and a button that opens System Settings › Privacy & Security ›
  Accessibility.
- **Notifications** — only for reminders, requested the first time you set one. Without it, due notes still
  wiggle and glow.

Global shortcuts need no permission.

## Known limitations

- **Spaces after relaunch.** A note belongs to the Space where it was slapped while SlapNote runs. macOS offers no
  public API to put a window on a specific Space, so after quitting and relaunching, all notes appear on the Space
  that is active at launch. Clicking a reminder notification raises the notes of the current Space only.
- **Accessibility after rebuilding.** Ad-hoc signed builds get a new code signature with every build, so macOS
  may silently stop honoring the Accessibility permission after you rebuild or update. If *Note from selection*
  stops working, remove SlapNote from System Settings › Privacy & Security › Accessibility (− button) and add it
  again.
- **⌘Z** restores a note only while SlapNote is the active app (settings window open, a note hanging or being
  edited). Clicking a stuck note intentionally does not take focus from your current app. ⌃⌥Z always works.
- **⌃⌥Space (Peek) can collide with macOS input sources.** If you use more than one keyboard layout, macOS may
  use ⌃⌥Space for "Select next source in Input menu" (System Settings › Keyboard › Keyboard Shortcuts › Input
  Sources). Then Peek does not fire; pick another Peek shortcut in SlapNote's settings or turn off the system one.
- Notes are hidden in full-screen apps (they live in their own Space).
- Plain text only.

## Where data lives and how to uninstall

- Notes: `~/Library/Application Support/SlapNote/notes.json` plus `notes.json.bak` (last good copy). If the main
  file is ever unreadable, SlapNote loads the backup and keeps the broken file as `notes.corrupt-<time>.json`.
- Settings and shortcuts: `~/Library/Preferences/com.normanaugscheller.SlapNote.plist`

To uninstall:

1. Turn off *Launch at login* in SlapNote's settings (or remove SlapNote under System Settings › General ›
   Login Items), then quit SlapNote (Settings › About › Quit SlapNote, or the menu bar icon).
2. Delete `SlapNote.app`.
3. Delete the data:
   ```bash
   rm -rf ~/Library/Application\ Support/SlapNote
   ```
   ```bash
   defaults delete com.normanaugscheller.SlapNote
   ```
4. Optionally remove SlapNote from System Settings › Privacy & Security › Accessibility and from
   System Settings › Notifications.

## Project layout

| Path | Contents |
|---|---|
| `project.yml` | XcodeGen project definition |
| `SlapNoteCore/` | Testable logic: styles, shapes, geometry, scrolling, persistence, displays, reminders, aging |
| `SlapNote/App/` | App delegate, shortcuts, launch detection, selection grabbing, menu bar icon |
| `SlapNote/Notes/` | Note windows, placement mode, animations, reminders UI, note manager |
| `SlapNote/Settings/` | Settings model (`UserDefaults`) and SwiftUI settings window |
| `SlapNote/Debug/` | Debug-only runtime self-test |
| `SlapNoteTests/` | XCTest unit tests |
| `scripts/` | Placeholder asset generator |

More: [DECISIONS.md](DECISIONS.md) (technical decisions and open questions),
[MANUAL_TEST_CHECKLIST.md](MANUAL_TEST_CHECKLIST.md), [ASSETS_NEEDED.md](ASSETS_NEEDED.md),
[PROGRESS.md](PROGRESS.md).
