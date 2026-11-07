import KeyboardShortcuts
import SlapNoteCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case notes, text, behavior, shortcuts, about
    var id: String { rawValue }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State var showIntro: Bool
    @State private var tab: SettingsTab = .notes

    var body: some View {
        VStack(spacing: 0) {
            if showIntro {
                IntroBanner { withAnimation(.easeOut(duration: 0.2)) { showIntro = false } }
                    .padding([.horizontal, .top], 16)
            }
            TabView(selection: $tab) {
                NotesSettingsView(settings: settings)
                    .tabItem { Label("Notes", systemImage: "note.text") }.tag(SettingsTab.notes)
                TextSettingsView(settings: settings)
                    .tabItem { Label("Text", systemImage: "textformat") }.tag(SettingsTab.text)
                BehaviorSettingsView(settings: settings)
                    .tabItem { Label("Behavior", systemImage: "gearshape") }.tag(SettingsTab.behavior)
                ShortcutsSettingsView(settings: settings)
                    .tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(SettingsTab.shortcuts)
                AboutSettingsView()
                    .tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
            }
            .padding(16)
        }
        .frame(width: 640, height: showIntro ? 640 : 540)
    }
}

struct IntroBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to SlapNote").font(.headline)
                Text("Press ⌃⌥N to summon a note. Type on it, then left-click to slap it onto your desktop. Right-click or Esc throws it away; ⌃⌥Z brings the last one back.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("SlapNote runs in the background without a Dock icon. Open SlapNote again to get back to these settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Got it", action: onDismiss)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Notes

struct NotesSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Form {
                Section("Default color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 8), count: 4), spacing: 8) {
                        ForEach(NoteColor.allCases, id: \.self) { color in
                            Button {
                                settings.defaultColor = color
                            } label: {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: NSColor(color.rgb)))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(settings.defaultColor == color ? Color.accentColor : Color.black.opacity(0.25),
                                                          lineWidth: settings.defaultColor == color ? 3 : 1)
                                    }
                                    .overlay {
                                        if settings.defaultColor == color {
                                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Color(nsColor: NSColor(color.automaticTextColor)))
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(color.displayName)
                            .accessibilityLabel(color.displayName)
                            .accessibilityAddTraits(settings.defaultColor == color ? .isSelected : [])
                        }
                    }
                    .disabled(settings.randomStyle)
                }
                Section("Default shape") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 8), count: 6), spacing: 8) {
                        ForEach(NoteShape.allCases, id: \.self) { shape in
                            Button {
                                settings.defaultShape = shape
                            } label: {
                                Image(systemName: settings.defaultShape == shape ? shape.symbolName + ".fill" : shape.symbolName)
                                    .font(.system(size: 20))
                                    .frame(width: 48, height: 48)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .fill(settings.defaultShape == shape ? Color.accentColor.opacity(0.2) : Color.clear))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(shape.displayName)
                            .accessibilityLabel(shape.displayName)
                            .accessibilityAddTraits(settings.defaultShape == shape ? .isSelected : [])
                        }
                    }
                    .disabled(settings.randomStyle)
                }
                Section {
                    Toggle("Random style for every new note", isOn: $settings.randomStyle)
                    Toggle("Subtle paper texture", isOn: $settings.paperTexture)
                }
            }
            .formStyle(.grouped)
            VStack(spacing: 8) {
                Text("Preview").font(.subheadline).foregroundStyle(.secondary)
                NotePreview(settings: settings)
                    .frame(width: 200, height: 200)
                if settings.randomStyle {
                    Text("Random: every new note gets a different color and shape.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 200)
                }
            }
            .padding(.top, 16)
        }
    }
}

/// Live preview of the note that the current settings produce.
struct NotePreview: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let shape = settings.defaultShape
        let color = settings.defaultColor
        GeometryReader { geo in
            let size = shape.defaultSize
            let scale = min(geo.size.width / size.width, geo.size.height / size.height) * 0.9
            let w = size.width * scale, h = size.height * scale
            let rect = CGRect(x: (geo.size.width - w) / 2, y: (geo.size.height - h) / 2, width: w, height: h)
            let safe = shape.safeTextRect(in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
            ZStack(alignment: .topLeading) {
                FlippedShapePath(shape: shape)
                    .fill(Color(nsColor: NSColor(color.rgb)))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                Text("Buy oat milk\nCall the dentist")
                    .font(Font(settings.font(scale: scale)))
                    .lineSpacing(CGFloat(settings.lineSpacing))
                    .multilineTextAlignment(settings.alignment == .left ? .leading : .center)
                    .foregroundStyle(Color(nsColor: settings.textColor(for: color)))
                    .frame(width: safe.width - 8, alignment: settings.alignment == .left ? .leading : .center)
                    .offset(x: safe.minX + 4, y: h - safe.maxY + 4)
                    .lineLimit(3)
            }
            .frame(width: w, height: h)
            .rotationEffect(.degrees(-1))
            .position(x: rect.midX, y: rect.midY)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(color.displayName) \(shape.displayName) note")
    }
}

/// SwiftUI uses a y-down coordinate space; the note paths are y-up.
struct FlippedShapePath: Shape {
    var shape: NoteShape

    func path(in rect: CGRect) -> Path {
        var t = CGAffineTransform(translationX: 0, y: rect.height).scaledBy(x: 1, y: -1)
        let p = shape.path(in: CGRect(origin: .zero, size: rect.size))
        return Path(p.copy(using: &t) ?? p)
    }
}

// MARK: - Text

struct TextSettingsView: View {
    @ObservedObject var settings: AppSettings
    private let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Picker("Font", selection: $settings.fontFamily) {
                Text("System").tag("")
                Divider()
                ForEach(families, id: \.self) { Text($0).tag($0) }
            }
            HStack {
                Slider(value: $settings.baseFontSize, in: AppSettings.fontSizeRange, step: 1) {
                    Text("Base font size")
                }
                Text("\(Int(settings.baseFontSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
            }
            Picker("Text color", selection: $settings.textColorMode) {
                ForEach(TextColorMode.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Automatic picks dark or light text with the best contrast for each note color.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Alignment", selection: $settings.alignment) {
                Label("Left", systemImage: "text.alignleft").tag(TextAlignmentOption.left)
                Label("Center", systemImage: "text.aligncenter").tag(TextAlignmentOption.center)
            }
            .pickerStyle(.segmented)
            HStack {
                Slider(value: $settings.lineSpacing, in: AppSettings.lineSpacingRange, step: 1) {
                    Text("Line spacing")
                }
                Text("\(Int(settings.lineSpacing)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
            }
            Text("Scrolling in placement mode scales each note's text on top of the base size.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behavior

struct BehaviorSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginStatus = LoginItem.statusDescription
    @State private var loginError: String?
    @State private var accessibilityGranted = SelectionGrabber.isTrusted

    var body: some View {
        Form {
            Section("Visibility") {
                Toggle("Always on top (all notes)", isOn: $settings.alwaysOnTop)
                Text("Off: notes sit on the desktop, below all app windows. On: notes float above app windows (never above full-screen apps).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            }
            Section("Aging") {
                Toggle("Curl the corner of untouched notes", isOn: $settings.agingEnabled)
                Stepper(value: $settings.agingDays, in: AgingPolicy.dayRange) {
                    Text("Start curling after \(settings.agingDays) \(settings.agingDays == 1 ? "day" : "days")")
                }
                .disabled(!settings.agingEnabled)
            }
            Section("System") {
                Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { newValue in
                    loginError = LoginItem.setEnabled(newValue)
                    loginEnabled = LoginItem.isEnabled
                    loginStatus = LoginItem.statusDescription
                }))
                Text(loginError ?? loginStatus).font(.caption).foregroundStyle(loginError == nil ? Color.secondary : Color.red)
                HStack {
                    Text("Accessibility (only for Note from Selection)")
                    Spacer()
                    Text(accessibilityGranted ? "Granted" : "Not granted")
                        .foregroundStyle(.secondary)
                    if !accessibilityGranted {
                        Button("Open System Settings") {
                            SelectionGrabber.requestTrust()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = SelectionGrabber.isTrusted
            loginEnabled = LoginItem.isEnabled
            loginStatus = LoginItem.statusDescription
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Global") {
                KeyboardShortcuts.Recorder("New note", name: .newNote)
                KeyboardShortcuts.Recorder("Note from selection", name: .noteFromSelection)
                KeyboardShortcuts.Recorder("Peek (hold)", name: .peek)
                KeyboardShortcuts.Recorder("Hide / show all notes", name: .toggleHidden)
                KeyboardShortcuts.Recorder("Restore last discarded note", name: .restoreLastNote)
                FixedShortcutRow(action: "Restore last discarded note (while SlapNote is active)", keys: "⌘Z")
            }
            Section("Placement mode (note hangs on the cursor)") {
                FixedShortcutRow(action: "Type on the note", keys: "Keyboard")
                FixedShortcutRow(action: "Slap onto the desktop", keys: "Left click")
                FixedShortcutRow(action: "Throw away", keys: "Right click or Esc")
                ForEach(ScrollAction.allCases, id: \.self) { action in
                    Picker(action.displayName, selection: Binding(
                        get: { settings.scrollBindings.modifier(for: action) },
                        set: { newValue in
                            var b = settings.scrollBindings
                            b.assign(newValue, to: action)
                            settings.scrollBindings = b
                        })) {
                        ForEach(ScrollModifier.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                FixedShortcutRow(action: "Set reminder", keys: "⌘T")
                Text("Mouse wheels and trackpads both work. Control + scroll is left to the macOS zoom feature. Picking a combination that is already used swaps the two.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Stuck notes") {
                FixedShortcutRow(action: "Lift (hover)", keys: "Move the pointer over a note")
                FixedShortcutRow(action: "Strike through a line", keys: "Click the line")
                FixedShortcutRow(action: "Move", keys: "Drag")
                FixedShortcutRow(action: "Edit", keys: "Double click")
                FixedShortcutRow(action: "Throw away", keys: "Right click")
            }
            Section("Edit mode") {
                FixedShortcutRow(action: "Finish editing", keys: "Click outside or Esc")
                FixedShortcutRow(action: "Set reminder", keys: "⌘T")
                FixedShortcutRow(action: "Standard text editing", keys: "Arrows, ⌫, ⌘A, ⌘C, ⌘X, ⌘V, ⌘Z")
            }
            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        KeyboardShortcuts.reset(KeyboardShortcuts.Name.allGlobal)
                        settings.resetScrollBindings()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FixedShortcutRow: View {
    var action: String
    var keys: String

    var body: some View {
        LabeledContent(action) {
            Text(keys).foregroundStyle(.secondary)
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    static let repositoryURL = URL(string: "https://github.com/NormanAugscheller/slap_note")!

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("SlapNote").font(.title)
            Text(version).foregroundStyle(.secondary)
            Text("Paper sticky notes for your Mac desktop.")
            Link("Source code on GitHub", destination: Self.repositoryURL)
            Spacer()
            Button("Quit SlapNote") { NSApp.terminate(nil) }
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
