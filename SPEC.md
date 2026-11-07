# SlapNote — Product & Technical Specification

Version 1.0 · Status: ready for implementation
Owner: Norman Augscheller · Target: open source on GitHub (published by the owner at the very end)

---

## 1. What SlapNote is

SlapNote brings paper sticky notes to the macOS desktop. You summon a note with a shortcut, it hangs ghosted on your cursor, you type on it, and you slap it onto your desktop with a left click. Right click throws it away. Notes live on the desktop layer, so you see them whenever no window covers that spot.

The point of the app is the *feel*: summoning, slapping, hovering and throwing away must feel physical and satisfying. Functionality is deliberately small.

### Non-goals (do not build)
- No cloud sync, no accounts, no network access of any kind.
- No rich text (plain text only in v1).
- No archive or history of discarded notes.
- No user-visible storage files, no export, no Markdown files.
- No Windows or Linux support. macOS only.
- No sound effects.

---

## 2. Platform & tech stack

- **macOS 14 (Sonoma) or later.** Primary test machine: MacBook Air M5, macOS 26 Tahoe, plus an external monitor.
- **Swift + AppKit** for windows, events and animation (Core Animation). SwiftUI is allowed for the settings window only.
- **Project generation:** use XcodeGen (`project.yml`) so the project is reproducible from text. Install via Homebrew if missing. Commit `project.yml`, do not commit the generated `.xcodeproj` (add to `.gitignore`).
- **Dependencies:** keep to an absolute minimum. One allowed dependency: [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) for user-configurable global shortcuts and the recorder UI. Anything else needs a written justification in `DECISIONS.md`.
- **App type:** background agent app (`LSUIElement = YES`), no Dock icon while running, no main window at launch.
- **Not sandboxed** (global shortcuts, accessibility for "note from selection"). Hardened runtime on. Ad-hoc signing for local builds.
- **Language:** all code, comments, identifiers, UI strings, commit messages and documentation in English.

---

## 3. Core concepts

| Term | Meaning |
|---|---|
| **Placement mode** | A new note hangs on the cursor, ghosted (≈50 % opacity). Keyboard input goes to the note. |
| **Stuck note** | A note that has been slapped onto the desktop. Fully opaque. |
| **Edit mode** | A stuck note whose text is being edited (entered by double click). |
| **Style** | Color + shape of a note. |
| **Desktop layer** | Default: stuck notes sit just above the desktop wallpaper/icons and below all normal app windows. |

---

## 4. Interaction specification

### 4.1 Creating a note (placement mode)
1. Triggered by the global shortcut **New note** (default `⌃⌥N`) or the menu bar item (if the menu bar icon is enabled).
2. A new note appears centered on the cursor at ≈50 % opacity and follows the cursor smoothly (no lag, no jitter) across all connected displays.
3. Its style is taken from the settings: the chosen default color/shape, or a random combination if "Random style" is enabled.
4. **Typing** writes directly onto the hanging note (plain text, standard text editing keys work: arrows, delete, ⌘A, ⌘C/⌘V, etc.).
5. **Left click** slaps the note at the current position → becomes a stuck note with the *slap* animation (§6).
6. **Right click** or **Esc** discards it with the *throw away* animation (§6).
7. While in placement mode, clicks must not reach other apps underneath (implementation hint: a transparent, borderless capture window per screen during placement mode; no event tap needed).
8. If the note is slapped over an area currently covered by an app window, it would vanish instantly behind that window. Mitigation: after slapping, the note stays above windows for ~1.2 s, then fades/sinks to the desktop layer with a short, subtle animation, so the user sees where it went.

### 4.2 Scroll & modifier controls (placement mode only)
All of these only work while the note hangs on the cursor. All are configurable and listed in the settings (§8).

| Input | Effect |
|---|---|
| Scroll | Resize proportionally. Font size scales by exactly the same factor. |
| `⇧` + scroll | Change width only (font size unchanged). |
| `⌥` + scroll | Change height only (font size unchanged). |
| `⌘` + scroll | Cycle through colors. |
| `⌘⌥` + scroll | Cycle through shapes. |
| `⌘T` | Open reminder time picker (§5.3). |

Requirements:
- Works with mouse wheels and trackpad two-finger swipes. Use precise (trackpad) deltas smoothly; mouse wheel steps should feel stepped but not jumpy.
- **Important:** macOS converts `⇧` + vertical mouse wheel into horizontal scrolling. Read **both** `scrollingDeltaX` and `scrollingDeltaY` and use whichever is non-zero, so `⇧` + scroll works with mouse and trackpad.
- Do not use `⌃` + scroll (it collides with the macOS accessibility zoom gesture).
- Size limits: minimum 80 × 80 pt, maximum 600 × 600 pt for manual resizing. Clamp, with a tiny elastic "bump" animation when hitting a limit.
- Color/shape cycling via scroll: one step per wheel notch; on trackpads accumulate delta and switch every ~30 pt so it does not flicker.

### 4.3 Stuck notes
| Input | Effect |
|---|---|
| Hover | *Hover* animation (§6). |
| Single click on a text line | Toggle strike-through for that line (to-do checkbox behavior). Must not trigger on drag. |
| Drag (left button) | Move the note. Movement threshold ≈4 pt to distinguish from click. Moving is possible across displays. |
| Double click | Enter edit mode (caret at click position). |
| Right click | Discard with *throw away* animation. No confirmation dialog. |

### 4.4 Edit mode
- Text is editable like in placement mode. Strike-through state stays attached to its line where possible.
- **Ends with** a click outside the note **or** `Esc`. Changes are saved immediately (no "cancel" semantics).
- `⌘T` opens the reminder picker for this note.
- Scroll in edit mode does nothing (scroll controls are placement-only).

### 4.5 Auto-grow
- When the text does not fit, the note grows **in height** (width stays). Font size never shrinks automatically.
- Auto-grow may exceed the 600 pt manual maximum up to the visible height of the current screen minus 40 pt. Only beyond that the text area scrolls internally (last resort).
- When text is deleted, the note shrinks back, but never below the size the user set manually.
- Shapes (circle, heart, cloud, …) stretch with the note: a growing circle becomes an oval. Text must always stay inside the shape's safe text area (define an inset rect per shape).

### 4.6 Undo discard
- SlapNote remembers **only the last** discarded note (including position, style, text, reminder), in memory, until the app quits.
- Restore via global shortcut **Restore last note** (default `⌃⌥Z`) and via `⌘Z` while SlapNote is the active app. Never register `⌘Z` globally (it would hijack undo in every other app).
- Restored note reappears at its old place with a reverse throw-away animation.

---

## 5. Features

### 5.1 Styles
**Colors (8):** Classic Yellow, Pink, Orange, Sky Blue, Mint Green, Lavender, Coral, Paper White. Soft pastel, close to real paper notes. Define them in one place so more can be added later.

**Shapes (6):** Square, Rectangle (landscape), Circle, Heart, Cloud, Speech Bubble. Shapes are **drawn in code** as vector paths (`CGPath`) so they scale and stretch cleanly in any color. Do not use per-color or per-shape bitmaps.

**Random style:** settings toggle. When on, every new note gets a random color + shape (avoid giving the same combination twice in a row).

**Realism:** every stuck note gets a random rotation between −2° and +2° (stored, stays stable), a soft drop shadow, and an optional subtle paper texture (see §10).

### 5.2 Visibility layers
- **Default:** desktop layer — notes are visible whenever no app window covers them, hidden in full-screen apps.
- **Setting "Always on top" (applies to all notes):** notes float above normal app windows (still not above full-screen apps). Changing the setting applies immediately to all notes.
- **Peek (hold shortcut, default `⌃⌥Space`):** while held, all notes on the current Space are temporarily raised above all windows; on release they return to their normal layer. Smooth 150 ms fade/raise.
- **Hide/show all (toggle shortcut, default `⌃⌥H`):** hides or shows all notes (e.g. for screen sharing). State persists across restarts. Menu bar icon (if enabled) shows the hidden state.

### 5.3 Reminders
- `⌘T` in placement or edit mode opens a small time picker attached to the note (hours/minutes, optional date; default = next occurrence of the chosen time, i.e. today if still ahead, otherwise tomorrow).
- Once set, the time is shown in small text in the **top-right corner** of the note (e.g. `14:30`; if not today: `Fri 14:30`). A reminder can be removed from the same picker.
- When due: the note wiggles and glows (repeating gently every few seconds until the user interacts with the note), and a macOS notification is posted ("SlapNote: <first line of text>"). Clicking the notification triggers Peek for that note's Space and highlights it.
- Request notification permission on first use of a reminder, not at launch.
- Reminders must survive app restarts; reminders that fired while the app was not running trigger on next launch.

### 5.4 Aging
- A note that has not been touched (edited, moved, struck through, reminder changed) for **N days** (default 7, configurable 1–60, or off) starts curling at one corner. The curl increases gradually over the following days up to a maximum.
- Any touch resets the age and the curl animates back flat.

### 5.5 Note from selection
- Global shortcut **Note from selection** (default `⌃⌥S`): takes the currently selected text in the frontmost app and creates a new note in placement mode with that text.
- Implementation: requires Accessibility permission. Save the current pasteboard, synthesize `⌘C`, read the text, restore the original pasteboard contents.
- If Accessibility permission is missing, show a short explanation window with a button to open the right pane in System Settings. Never prompt at launch, only on first use.
- If nothing is selected, create an empty note.

### 5.6 Spaces & displays
- A note belongs to the Space where it was slapped and only appears there.
- **Known macOS limitation:** public APIs cannot place a window on a specific Space after relaunch. Behavior for v1: within a session, notes stay on their Space (default window behavior, no `canJoinAllSpaces`). After a relaunch, all notes are restored on the Space that is active at launch. Document this in the README under "Known limitations". Do **not** use private CGS APIs unless the owner approves it later (record as an open question in `DECISIONS.md`).
- Multi-display: store positions per display (display UUID + relative position). If a display is missing at launch or gets disconnected, move its notes onto the main display, keep them inside the visible frame, and move them back when that display returns.

### 5.7 Launch at login
- Settings toggle (default off) using `SMAppService.mainApp`.

---

## 6. Animations (the heart of the app)

All animations: Core Animation, 60/120 fps, no dropped frames on an M-series Mac. Respect "Reduce motion" in macOS accessibility settings (then use simple fades).

| Moment | Animation |
|---|---|
| **Summon** | Note pops in at the cursor from ~70 % scale to 100 % with a slight overshoot (≈180 ms), ghosted. |
| **Hanging** | Very subtle pendulum sway (±1°) that reacts to cursor velocity, like paper held by one corner. |
| **Slap** | Quick scale 100 % → 94 % → 100 % (≈160 ms), opacity to 100 %, shadow shrinks (paper pressed flat), tiny screen-local "settle" wobble. |
| **Hover** | Note lifts slightly: scale to ~103 %, shadow grows and softens, bottom edge flutters gently. Reverts on exit. ≈150 ms ease-out. |
| **Throw away** | Note crumples into a paper ball (shape morph + shrink + slight rotation, ≈250 ms), then the ball arcs away downward off-screen with gravity (≈450 ms). |
| **Restore** | Reverse of throw away. |
| **Limit bump** | Elastic overshoot when hitting min/max size. |
| **Reminder due** | Wiggle (±4°, 3 cycles) + soft glow pulse, repeats every ~8 s until interaction. |
| **Aging** | Corner curl rendered as a folded/curled corner with a light gradient; transitions smoothly. |

---

## 7. Launch behavior & settings window

- **Manual launch** (Finder double click, Dock, Spotlight, `open`) **or re-launch while already running** (reopen event): open the settings window and bring it to the front.
- **Launch as login item:** do **not** open the settings window. The app works immediately in the background (shortcuts active, notes restored).
- Detecting login-item launch: research the reliable mechanism for `SMAppService` login items on macOS 14–26 and document the chosen method and its tests in `DECISIONS.md`. If no fully reliable method exists, choose the most robust option and document the trade-off.
- **First launch ever:** settings window opens with a short one-screen intro ("Press ⌃⌥N to summon a note…").
- Closing the settings window keeps the app running in the background.

---

## 8. Settings window

Small, native, clean macOS window (SwiftUI allowed), tabbed or sectioned:

1. **Notes:** default color (swatches), default shape (icons), Random style toggle, live preview of the resulting note.
2. **Text:** font family (system font picker), base font size, text color (default: automatic dark/light contrast against the note color), alignment (left/center), line spacing.
3. **Behavior:** Always on top (all notes), aging on/off + days, launch at login, show menu bar icon (**default off**).
4. **Shortcuts:** a complete list of **every** shortcut and mouse/scroll gesture in the app, grouped (Global / Placement mode / Stuck notes / Edit mode). Global shortcuts and placement-mode modifiers are editable (KeyboardShortcuts recorder for global ones). Include a "Reset to defaults" button.
5. **About:** version, link to GitHub repo (placeholder URL), Quit SlapNote button.

Settings are stored in `UserDefaults` and apply instantly.

### Menu bar icon (optional, default off)
Menu: New Note · Note from Selection · Hide/Show All Notes · Restore Last Note · Settings… · Quit SlapNote.

### Complete default shortcut table

| Context | Action | Default |
|---|---|---|
| Global | New note | `⌃⌥N` |
| Global | Note from selection | `⌃⌥S` |
| Global | Peek (hold) | `⌃⌥Space` |
| Global | Hide/show all notes | `⌃⌥H` |
| Global | Restore last discarded note | `⌃⌥Z` |
| App active | Restore last discarded note | `⌘Z` |
| Placement | Slap / discard | Left click / right click or `Esc` |
| Placement | Resize proportional / width / height | Scroll / `⇧`+scroll / `⌥`+scroll |
| Placement | Next color / next shape | `⌘`+scroll / `⌘⌥`+scroll |
| Placement & Edit | Reminder | `⌘T` |
| Stuck note | Edit / move / strike line / discard | Double click / drag / click line / right click |
| Edit | Finish editing | Click outside or `Esc` |

---

## 9. Persistence

- One internal file: `~/Library/Application Support/SlapNote/notes.json`. Never shown to the user, no UI to open it.
- Contents per note: id, text, struck-through line indices, color, shape, width, height, font scale, rotation, display UUID + relative position, created/modified/last-touched timestamps, reminder (date, fired state).
- Plus a schema `version` field for future migrations.
- Write atomically (temp file + rename), debounced (~500 ms after last change) and on quit. Never lose a note on crash: corrupted file → keep a `.bak` of the last good version and load that.
- Settings live in `UserDefaults`, not in this file.

---

## 10. Assets

All bitmap assets are created by the owner with ChatGPT (GPT Image). The app must **build and run without them** using placeholders, and swap in the real files without code changes.

Needed assets (create `ASSETS_NEEDED.md` with exact file names, pixel sizes, transparency requirements and a suggested image prompt for each):
- App icon (full `AppIcon.appiconset` size set, source 1024 × 1024).
- Optional subtle paper texture, tileable, grayscale, applied as a low-opacity overlay so it works on every color.
- Menu bar icon: prefer an SF Symbol or a hand-written vector template image instead of a generated PNG (generated PNGs rarely work as crisp template icons). Note this in `ASSETS_NEEDED.md`.

Note shapes, shadows, curls and the paper ball are drawn in code, not bitmaps.

---

## 11. Quality, testing & documentation

### Automated
- Unit tests (XCTest) for: geometry and clamping (resize, aspect, auto-grow, safe text areas per shape), scroll-delta handling incl. `⇧` horizontal conversion, style cycling, persistence (round-trip, migration, corrupt-file recovery), display reassignment, reminder scheduling (next occurrence, fired-while-closed), aging curve, strike-through line mapping when text changes.
- `xcodebuild build` and `xcodebuild test` must pass with zero warnings in project code.

### Manual
- `MANUAL_TEST_CHECKLIST.md`: step-by-step checklist the owner runs on his Mac for everything that cannot be tested automatically (feel of animations, cursor following, multi-display, Spaces, reminders, permissions). Each item with expected result.

### Documentation (English)
- `README.md`: what it is, GIF/screenshot placeholders, features, full shortcut table, build & install instructions (Xcode/XcodeGen steps, first-launch Gatekeeper note for unsigned builds), permissions explained (Accessibility only for "note from selection", Notifications only for reminders), known limitations (Spaces after relaunch, re-granting Accessibility after rebuilds of ad-hoc signed builds), uninstall instructions incl. where data lives.
- `DECISIONS.md`: every non-obvious technical decision with reasoning, plus open questions for the owner.
- `PROGRESS.md`: checklist of all acceptance criteria (§12) with status and evidence (test name, command output, or "manual").
- No LICENSE file yet; the owner chooses the license before publishing.

### Git
- Initialize a git repo, commit in small logical steps with clear English messages. **Never push** and never create a GitHub remote.

---

## 12. Acceptance criteria

1. App builds from a clean checkout with `xcodegen generate` + `xcodebuild`; runs as background agent without Dock icon.
2. Settings window opens on manual launch and on reopen, not on login-item launch.
3. `⌃⌥N` summons a ghosted note that follows the cursor on all displays; typing writes on it.
4. Left click slaps it (animation, full opacity, desktop layer with the 1.2 s visibility mitigation); right click/Esc discards it (crumple animation).
5. Scroll resizes proportionally with font scaling; `⇧`/`⌥` + scroll change width/height only; works with mouse and trackpad; limits enforced.
6. `⌘`+scroll and `⌘⌥`+scroll cycle color and shape in placement mode; random style works.
7. Stuck notes: hover animation, drag to move, click line to strike through, double click to edit, Esc/click outside ends editing, right click discards.
8. Auto-grow in height works for all shapes; text stays inside the shape.
9. Undo restores the last discarded note via `⌃⌥Z` and `⌘Z` (app active only).
10. Always-on-top setting, Peek (hold) and Hide/show all work.
11. Reminders: `⌘T` picker, time shown top-right, wiggle + glow + notification when due, survive restart.
12. Aging curl after N days, reset on touch.
13. Note from selection works with Accessibility permission and explains how to grant it otherwise.
14. Notes persist across restarts (text, style, size, rotation, position, strike-through, reminders); corrupt-file recovery works.
15. Multi-display reassignment works; Space behavior as specified in §5.6.
16. Settings window contains all sections of §8, including the complete shortcut list; all settings apply instantly.
17. Respects Reduce Motion.
18. All unit tests pass; build has no warnings in project code.
19. `README.md`, `DECISIONS.md`, `PROGRESS.md`, `MANUAL_TEST_CHECKLIST.md`, `ASSETS_NEEDED.md` exist and are complete.
20. `REVIEW_PROMPT.md` exists: a ready-to-paste prompt for a second coding agent (Codex) to review the whole codebase for bugs, security issues (permissions, pasteboard handling, file writes) and macOS API misuse.
