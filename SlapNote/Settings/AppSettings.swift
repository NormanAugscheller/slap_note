import AppKit
import Combine
import SlapNoteCore

enum TextColorMode: String, CaseIterable, Identifiable {
    case automatic
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

enum TextAlignmentOption: String, CaseIterable, Identifiable {
    case left
    case center

    var id: String { rawValue }

    var nsAlignment: NSTextAlignment { self == .left ? .left : .center }
}

/// All user settings, stored in `UserDefaults` and applied instantly.
/// Observers either use Combine (`objectWillChange`, SwiftUI) or `AppSettings.didChange`.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let didChange = Notification.Name("SlapNoteSettingsDidChange")

    enum Key: String, CaseIterable {
        case defaultColor, defaultShape, randomStyle, paperTexture
        case fontFamily, baseFontSize, textColorMode, alignment, lineSpacing
        case alwaysOnTop, agingEnabled, agingDays, showMenuBarIcon, notesHidden
        case scrollBindings, hasLaunchedBefore
    }

    static let defaultFontSize: Double = 17
    static let fontSizeRange: ClosedRange<Double> = 10...40
    static let lineSpacingRange: ClosedRange<Double> = 0...12

    private let defaults: UserDefaults

    @Published var defaultColor: NoteColor { didSet { store(defaultColor.rawValue, .defaultColor) } }
    @Published var defaultShape: NoteShape { didSet { store(defaultShape.rawValue, .defaultShape) } }
    @Published var randomStyle: Bool { didSet { store(randomStyle, .randomStyle) } }
    @Published var paperTexture: Bool { didSet { store(paperTexture, .paperTexture) } }
    /// Empty string means the system font.
    @Published var fontFamily: String { didSet { store(fontFamily, .fontFamily) } }
    @Published var baseFontSize: Double { didSet { store(baseFontSize, .baseFontSize) } }
    @Published var textColorMode: TextColorMode { didSet { store(textColorMode.rawValue, .textColorMode) } }
    @Published var alignment: TextAlignmentOption { didSet { store(alignment.rawValue, .alignment) } }
    @Published var lineSpacing: Double { didSet { store(lineSpacing, .lineSpacing) } }
    @Published var alwaysOnTop: Bool { didSet { store(alwaysOnTop, .alwaysOnTop) } }
    @Published var agingEnabled: Bool { didSet { store(agingEnabled, .agingEnabled) } }
    @Published var agingDays: Int { didSet { store(agingDays, .agingDays) } }
    @Published var showMenuBarIcon: Bool { didSet { store(showMenuBarIcon, .showMenuBarIcon) } }
    @Published var notesHidden: Bool { didSet { store(notesHidden, .notesHidden) } }
    @Published var scrollBindings: ScrollBindings {
        didSet {
            let raw = Dictionary(uniqueKeysWithValues: scrollBindings.modifiers.map { ($0.key.rawValue, $0.value.rawValue) })
            store(raw, .scrollBindings)
        }
    }
    @Published var hasLaunchedBefore: Bool { didSet { store(hasLaunchedBefore, .hasLaunchedBefore) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultColor = NoteColor(rawValue: defaults.string(forKey: Key.defaultColor.rawValue) ?? "") ?? .classicYellow
        defaultShape = NoteShape(rawValue: defaults.string(forKey: Key.defaultShape.rawValue) ?? "") ?? .square
        randomStyle = defaults.object(forKey: Key.randomStyle.rawValue) as? Bool ?? false
        paperTexture = defaults.object(forKey: Key.paperTexture.rawValue) as? Bool ?? true
        fontFamily = defaults.string(forKey: Key.fontFamily.rawValue) ?? ""
        let size = defaults.object(forKey: Key.baseFontSize.rawValue) as? Double ?? Self.defaultFontSize
        baseFontSize = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        textColorMode = TextColorMode(rawValue: defaults.string(forKey: Key.textColorMode.rawValue) ?? "") ?? .automatic
        alignment = TextAlignmentOption(rawValue: defaults.string(forKey: Key.alignment.rawValue) ?? "") ?? .left
        let spacing = defaults.object(forKey: Key.lineSpacing.rawValue) as? Double ?? 2
        lineSpacing = min(max(spacing, Self.lineSpacingRange.lowerBound), Self.lineSpacingRange.upperBound)
        alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop.rawValue) as? Bool ?? false
        agingEnabled = defaults.object(forKey: Key.agingEnabled.rawValue) as? Bool ?? true
        let days = defaults.object(forKey: Key.agingDays.rawValue) as? Int ?? 7
        agingDays = min(max(days, AgingPolicy.dayRange.lowerBound), AgingPolicy.dayRange.upperBound)
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon.rawValue) as? Bool ?? false
        notesHidden = defaults.object(forKey: Key.notesHidden.rawValue) as? Bool ?? false
        let raw = defaults.dictionary(forKey: Key.scrollBindings.rawValue) as? [String: String] ?? [:]
        var map: [ScrollAction: ScrollModifier] = [:]
        for (k, v) in raw {
            if let a = ScrollAction(rawValue: k), let m = ScrollModifier(rawValue: v) { map[a] = m }
        }
        let bindings = ScrollBindings(modifiers: map)
        scrollBindings = bindings.conflictingActions.isEmpty ? bindings : .defaults
        hasLaunchedBefore = defaults.object(forKey: Key.hasLaunchedBefore.rawValue) as? Bool ?? false
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["key": key.rawValue])
    }

    var agingPolicy: AgingPolicy {
        AgingPolicy(enabled: agingEnabled, thresholdDays: agingDays)
    }

    func resetScrollBindings() {
        scrollBindings = .defaults
    }

    // MARK: Derived values

    func font(scale: CGFloat) -> NSFont {
        let size = CGFloat(baseFontSize) * scale
        if !fontFamily.isEmpty,
           let f = NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: size) {
            return f
        }
        return NSFont.systemFont(ofSize: size)
    }

    func textColor(for color: NoteColor) -> NSColor {
        switch textColorMode {
        case .automatic: return NSColor(color.automaticTextColor)
        case .dark: return NSColor(NoteRGB.darkText)
        case .light: return NSColor(NoteRGB.lightText)
        }
    }
}

extension NSColor {
    convenience init(_ rgb: NoteRGB, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: alpha)
    }
}
