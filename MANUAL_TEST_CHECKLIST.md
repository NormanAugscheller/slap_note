# Manual test checklist

Everything here cannot be verified by the unit tests or the debug self-test: the feel of animations, real
mouse/trackpad input, Spaces, multiple displays, permissions and login items. Run it on the MacBook with an
external monitor attached. Tick each box; note anything that feels off next to it.

**Preparation**

```bash
xcodegen generate
```
```bash
xcodebuild -scheme SlapNote -configuration Release -derivedDataPath build build
```
```bash
cp -R build/Build/Products/Release/SlapNote.app /Applications/
```

For a clean first launch, quit SlapNote and reset its data first:
`rm -rf ~/Library/Application\ Support/SlapNote` and `defaults delete io.github.normanaugscheller.SlapNote`.

## A. Launch and settings window (criteria 1, 2, 16)

- [ ] A1. Open `/Applications/SlapNote.app` for the first time. **Expected:** settings window opens in front with the
  "Welcome to SlapNote" intro; no Dock icon; no menu bar icon.
- [ ] A2. Close the settings window. **Expected:** app keeps running (`⌃⌥N` still works).
- [ ] A3. Open the app again from Finder/Spotlight while it runs. **Expected:** settings window opens and comes to the
  front, without the intro.
- [ ] A4. Quit and launch again. **Expected:** settings open, no intro.
- [ ] A5. Settings › Notes: click each color swatch and shape. **Expected:** preview updates instantly; selected
  swatch shows a checkmark. Toggle Random style. **Expected:** swatches dim; preview explains random.
- [ ] A6. Settings › Text: change font, size, text color, alignment, line spacing while a note is on the desktop.
  **Expected:** every note updates instantly.
- [ ] A7. Settings › Behavior: toggle Always on top, aging, days, menu bar icon. **Expected:** applies instantly
  (menu bar icon appears/disappears).
- [ ] A8. Settings › Shortcuts: every shortcut and gesture from the README table is listed, grouped
  Global / Placement / Stuck notes / Edit. Record a different New note shortcut; it works at once. Set a placement
  modifier to one already used. **Expected:** the two swap. Click Reset to Defaults. **Expected:** everything back.
- [ ] A9. Settings › About: version shown, GitHub link opens the repository in the browser, Quit quits.
- [ ] A10. Turn on dark mode. **Expected:** settings window readable, note colors unchanged.

## B. Placement mode (criteria 3, 4, 5, 6)

- [ ] B1. Press `⌃⌥N`. **Expected:** note pops in at the cursor (≈70 % → 100 %, slight overshoot), half transparent.
- [ ] B2. Move the mouse slowly and fast, also onto the external display and back. **Expected:** the note stays exactly
  under the cursor with no lag or jitter; a very slight sway (±1°) reacting to speed.
- [ ] B3. Type text with umlauts, ⌫, arrows, ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z. **Expected:** all work on the hanging note.
- [ ] B4. With the note hanging, click on another app's window, a Dock icon and the menu bar area.
  **Expected:** the click slaps the note; the app underneath does **not** react.
- [ ] B5. Slap a note on an empty desktop area. **Expected:** quick press (≈160 ms), full opacity, shadow flattens, small
  settle wobble; keyboard focus returns to the app you were using before.
- [ ] B6. Slap a note on top of a Safari window. **Expected:** note stays visible above the window ~1.2 s, then dips
  slightly and disappears behind the window (desktop layer). Move Safari away: the note is there.
- [ ] B7. Summon, then right click. **Expected:** note crumples into a paper ball (≈250 ms) and the ball arcs down off
  the screen with gravity (≈450 ms). Repeat with Esc.
- [ ] B8. Mouse wheel: scroll up/down. **Expected:** note grows/shrinks proportionally in clear steps, text scales by
  the same factor. Trackpad two-finger scroll: smooth.
- [ ] B9. `⇧` + mouse wheel and `⇧` + trackpad. **Expected:** only width changes, font size stays.
- [ ] B10. `⌥` + scroll. **Expected:** only height changes.
- [ ] B11. Shrink to the minimum and grow to the maximum. **Expected:** stops at 80 pt / 600 pt with a small elastic bump.
- [ ] B12. `⌘` + wheel: **one color per notch**. `⌘` + trackpad: changes about every 30 pt of scrolling, no flicker.
- [ ] B13. `⌘⌥` + scroll cycles the six shapes; text stays inside each shape.
- [ ] B14. `⌃` + scroll. **Expected:** SlapNote ignores it (system zoom may react if enabled).
- [ ] B15. Turn on Random style, summon ten notes. **Expected:** varied color/shape, never the same combination twice
  in a row.

## C. Stuck notes (criteria 7, 8)

- [ ] C1. Move the pointer over a note. **Expected:** lifts to ~103 %, shadow grows and softens, bottom edge flutters
  gently; reverts when the pointer leaves (≈150 ms).
- [ ] C2. Click a text line. **Expected:** line gets struck through and dimmed instantly; click again removes it. Clicking
  empty space below the text does nothing.
- [ ] C3. Press, move less than 4 pt, release. **Expected:** counts as a click (strike), not a move.
- [ ] C4. Drag a note, also onto the external display. **Expected:** follows smoothly; does not strike a line.
- [ ] C5. Double click a word. **Expected:** edit mode, caret at the click position, no strike toggled.
- [ ] C6. In edit mode type several lines. **Expected:** the note grows downward (width fixed); strike-throughs stay
  attached to their lines when you insert lines above.
- [ ] C7. Keep typing until the note reaches the screen height. **Expected:** stops 40 pt short of the visible height,
  then the text scrolls inside the note.
- [ ] C8. Delete most text. **Expected:** note shrinks back, never below the size set while it was hanging.
- [ ] C9. Repeat C6–C8 for circle, heart, cloud and speech bubble. **Expected:** shapes stretch (circle → oval); text
  never leaves the shape.
- [ ] C10. End editing with Esc, then again by clicking the desktop, another app and another note. **Expected:** all end
  editing; text is kept; focus returns to the previous app after Esc.
- [ ] C11. Scroll while editing. **Expected:** nothing happens to size/style.
- [ ] C12. Right click a stuck note (and a note in edit mode). **Expected:** crumple and throw, no confirmation.
- [ ] C13. Clicking/dragging a stuck note while typing in TextEdit. **Expected:** TextEdit keeps keyboard focus.

## D. Undo, layers, peek, hide (criteria 9, 10)

- [ ] D1. Throw a stuck note away, press `⌃⌥Z` in any app. **Expected:** ball flies in from below and unfolds at the old
  place with the old text, style, tilt and reminder.
- [ ] D2. Throw away a note, open SlapNote settings (SlapNote active), press `⌘Z`. **Expected:** restored. In TextEdit,
  `⌘Z` must still undo TextEdit, not restore a note.
- [ ] D3. `⌃⌥Z` with nothing to restore. **Expected:** system beep, nothing else.
- [ ] D4. Summon and immediately Esc an empty note after D1-style discard. **Expected:** `⌃⌥Z` still restores the earlier
  real note.
- [ ] D5. Turn on Always on top. **Expected:** all notes float above app windows at once; never above a full-screen app.
- [ ] D6. With notes covered by windows, hold `⌃⌥Space`. **Expected:** notes fade in above everything (~150 ms); release:
  they return to their layer.
- [ ] D7. Press `⌃⌥H`. **Expected:** all notes fade out; menu bar icon (if on) changes to the crossed-out eye. Quit and
  relaunch: still hidden. `⌃⌥H` again shows them.
- [ ] D8. While hidden, press `⌃⌥N`. **Expected:** notes become visible again (decision D22).
- [ ] D9. Click a reminder notification, then press and hold `⌃⌥Space` for 5 s. **Expected:** notes stay raised until
  you let go, not only for 3 s (D49).

## E. Reminders (criterion 11)

- [ ] E1. Summon a note, type "Call Anna", press `⌘T`. **Expected:** picker attached to the note; the note stops following
  the cursor while it is open. Set a time 2 minutes ahead. **Expected:** first time only: macOS asks for notification
  permission. Time appears at the top right, e.g. `14:30` (or `2:30 PM` with the 12-hour setting in System Settings › General › Date & Time).
- [ ] E2. Set a reminder for tomorrow with the day option. **Expected:** label like `Sat 09:00`.
- [ ] E3. Wait until due. **Expected:** note wiggles (±4°, 3 cycles) and glows, repeating about every 8 s; notification
  "SlapNote: Call Anna" appears. Clicking the note stops the wiggle.
- [ ] E4. Click the notification. **Expected:** notes are raised for ~3 s and the note glows.
- [ ] E5. Double click a note with a reminder, `⌘T`, Remove. **Expected:** label disappears; no notification later.
- [ ] E6. Set a reminder 2 minutes ahead, quit SlapNote, wait until it has passed, launch again. **Expected:** the note
  wiggles; exactly one notification in Notification Center (not two).
- [ ] E6b. As E6, but dismiss the notification (close it in Notification Center) before launching again. **Expected:**
  the note wiggles; no new notification appears (D45).
- [ ] E7. Set a reminder, quit and relaunch before it is due. **Expected:** label still there and it fires on time.
- [ ] E8. Set a reminder 5 minutes ahead, then change the time zone in System Settings › General › Date & Time.
  **Expected:** the label shows the new local time; wiggle and notification still come at the same moment (D46).
- [ ] E9. Set a reminder 3 minutes ahead, right click the note away, wait until the time has passed, press `⌃⌥Z`.
  **Expected:** the restored note wiggles and exactly one notification appears (D53).

## F. Aging (criterion 12)

- [ ] F1. Settings › Behavior: aging after 1 day. Quit SlapNote, edit `notes.json` of a test note: set `lastTouched` to
  3 days ago (ISO date), launch. **Expected:** that note shows a curled bottom-right corner with a light gradient.
- [ ] F2. Drag, click a line or edit that note. **Expected:** the corner animates back flat.
- [ ] F3. Turn aging off. **Expected:** all curls disappear.

## G. Note from selection (criterion 13)

- [ ] G1. Without Accessibility permission, select text in Safari, press `⌃⌥S`. **Expected:** short explanation window,
  nothing else happens. Button opens System Settings › Privacy & Security › Accessibility (SlapNote listed).
- [ ] G2. Grant the permission, select text, put something recognizable on the clipboard beforehand, press `⌃⌥S`.
  **Expected:** a hanging note with the selected text; the clipboard still contains the old content (paste to check).
  Repeat in an app that does not expose its selection to Accessibility (for example a web page in a Chromium
  browser or an Electron app). **Expected:** same result through the ⌘C fallback.
- [ ] G3. Press `⌃⌥S` with nothing selected. **Expected:** empty hanging note; clipboard unchanged.
- [ ] G3b. Press `⌃⌥S` twice quickly in such an app. **Expected:** one note; clipboard still has the old content.
- [ ] G3c. In an app that does not expose its selection (see G2), press `⌃⌥S` and copy something yourself right
  after. **Expected:** your copy stays on the clipboard when you paste a few seconds later (D54).
- [ ] G5. Select text in an app, press `⌃⌥S` and immediately switch apps with ⌘Tab. **Expected:** SlapNote never
  freezes; the note has the text of the first app or SlapNote beeps — never text of the other app (D55).
- [ ] G4. Rebuild the app (ad-hoc signature changes) and try again. **Expected (known limitation):** permission may need
  to be removed and re-added.

## H. Persistence (criterion 14)

- [ ] H1. Create notes with different text, styles, sizes, strikes and a reminder; quit with ⌘Q from settings. Launch.
  **Expected:** everything identical (text, style, size, tilt, position, strike-throughs, reminder).
- [ ] H2. Force-quit SlapNote (Activity Monitor) one second after changing a note. **Expected:** after relaunch the change
  is there (saved after 0.5 s).
- [ ] H3. Quit, write garbage into `~/Library/Application Support/SlapNote/notes.json`, launch. **Expected:** notes from
  the backup appear; a `notes.corrupt-….json` file exists.
- [ ] H4. Make the data folder read-only (`chmod 555 ~/Library/Application\ Support/SlapNote`), change a note.
  **Expected:** within a second an alert "SlapNote can’t save your notes"; menu bar icon (if on) shows a warning.
  Quit with ⌘Q. **Expected:** "Quit without saving your latest changes?" with Try Again / Show in Finder / Quit
  Anyway. `chmod 755` the folder, choose Try Again. **Expected:** SlapNote quits; the change is there after relaunch.
- [ ] H5. Quit, set `"version": 99` in `notes.json`, make the folder read-only, launch. **Expected:** notes appear and
  an alert says changes are not saved; `notes.json` is unchanged after quitting (D43). Restore permissions after.

- [ ] H6. Press `⌃⌥N`, type a few words, and press `⌘Q` while the note still hangs.
  **Expected:** after relaunch the note is stuck where it hung (D52).

## I. Displays and Spaces (criterion 15)

- [ ] I1. Slap notes on the external display. Unplug it. **Expected:** those notes move to the built-in display, fully
  visible. Plug it back in. **Expected:** they move back to their places.
- [ ] I2. Quit, unplug the external display, launch, plug it back in. **Expected:** same as I1.
- [ ] I2b. On a tall external display make a note so long it nearly fills the screen height, then unplug the display.
  **Expected:** on the smaller display the note is fully visible and scrolls inside (D48).
- [ ] I2c. Make a note so long it nearly fills a tall display, then drag it onto a smaller display. **Expected:**
  after letting go it fits the smaller display and scrolls inside (D56).
- [ ] I3. Slap a note on Space 1, switch to Space 2. **Expected:** the note is not visible on Space 2. Back on Space 1 it is.
- [ ] I4. Relaunch on Space 2. **Expected (known limitation):** all notes appear on Space 2.
- [ ] I5. Mission Control. **Expected:** notes stay in place like desktop items; they are not ⌘\`-cycled.

## J. Launch at login (criterion 2)

- [ ] J1. Settings › Behavior: turn on Launch at login. **Expected:** status says it starts at login (or asks for approval
  in System Settings › General › Login Items).
- [ ] J2. Log out and log in. **Expected:** SlapNote runs (shortcuts work, notes visible), settings window does **not** open.
- [ ] J3. Within the first minute after login open SlapNote from Finder. **Expected:** settings window opens (reopen event).
- [ ] J4. Turn Launch at login off, log out/in. **Expected:** SlapNote does not start.

## K. Reduce Motion and accessibility (criterion 17)

- [ ] K1. System Settings › Accessibility › Display › Reduce motion on. **Expected:** summon, slap, throw-away and restore
  become simple fades; no sway, no hover lift/flutter, no wiggle (glow only); curl changes without animation.
- [ ] K2. Turn it off again while SlapNote runs. **Expected:** animations come back without relaunch.
- [ ] K3. VoiceOver on the settings window. **Expected:** swatches and shape buttons are announced by name.

## L. Performance

- [ ] L1. With 20 notes, move a hanging note around quickly and hover notes. **Expected:** no dropped frames (Quartz
  Debug / Instruments › Animation Hitches if in doubt).
- [ ] L2. Leave SlapNote running for a day. **Expected:** memory in Activity Monitor stays roughly flat.
