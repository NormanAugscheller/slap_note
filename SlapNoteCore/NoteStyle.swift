import CoreGraphics
import Foundation

/// An sRGB color with components in 0...1. Kept free of AppKit so it can be unit tested.
public struct NoteRGB: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0)
    }

    public static let darkText = NoteRGB(hex: 0x222222)
    public static let lightText = NoteRGB(hex: 0xFFFFFF)

    /// WCAG 2.x relative luminance.
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colors (1...21).
    public static func contrastRatio(_ a: NoteRGB, _ b: NoteRGB) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    public func darkened(by amount: Double) -> NoteRGB {
        NoteRGB(red: red * (1 - amount), green: green * (1 - amount), blue: blue * (1 - amount))
    }
}

/// The note colors. Add new cases here; everything else (settings swatches, cycling,
/// random style) picks them up automatically via `allCases`.
public enum NoteColor: String, CaseIterable, Codable, Sendable {
    case classicYellow
    case pink
    case orange
    case skyBlue
    case mintGreen
    case lavender
    case coral
    case paperWhite

    public var displayName: String {
        switch self {
        case .classicYellow: return "Classic Yellow"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .skyBlue: return "Sky Blue"
        case .mintGreen: return "Mint Green"
        case .lavender: return "Lavender"
        case .coral: return "Coral"
        case .paperWhite: return "Paper White"
        }
    }

    public var rgb: NoteRGB {
        switch self {
        case .classicYellow: return NoteRGB(hex: 0xFFF17A)
        case .pink: return NoteRGB(hex: 0xFFBCD8)
        case .orange: return NoteRGB(hex: 0xFFCF8A)
        case .skyBlue: return NoteRGB(hex: 0xAEDCFF)
        case .mintGreen: return NoteRGB(hex: 0xB8F0CB)
        case .lavender: return NoteRGB(hex: 0xDCCBFF)
        case .coral: return NoteRGB(hex: 0xFFAE9C)
        case .paperWhite: return NoteRGB(hex: 0xFAF8F0)
        }
    }

    /// Text color with the higher contrast against this note color.
    public var automaticTextColor: NoteRGB {
        let dark = NoteRGB.contrastRatio(rgb, .darkText)
        let light = NoteRGB.contrastRatio(rgb, .lightText)
        return dark >= light ? .darkText : .lightText
    }

    public func next(steps: Int = 1) -> NoteColor {
        NoteColor.allCases.cycled(from: self, steps: steps)
    }

    /// Decodes unknown raw values (e.g. a color added in a newer version) as the default.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NoteColor(rawValue: raw) ?? .classicYellow
    }
}

public enum NoteShape: String, CaseIterable, Codable, Sendable {
    case square
    case rectangle
    case circle
    case heart
    case cloud
    case speechBubble

    public var displayName: String {
        switch self {
        case .square: return "Square"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .heart: return "Heart"
        case .cloud: return "Cloud"
        case .speechBubble: return "Speech Bubble"
        }
    }

    /// SF Symbol used for the shape picker in settings.
    public var symbolName: String {
        switch self {
        case .square: return "square"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .heart: return "heart"
        case .cloud: return "cloud"
        case .speechBubble: return "bubble.left"
        }
    }

    /// Default note size for a newly created note with this shape.
    public var defaultSize: CGSize {
        switch self {
        case .square: return CGSize(width: 220, height: 220)
        case .rectangle: return CGSize(width: 280, height: 190)
        case .circle: return CGSize(width: 240, height: 240)
        case .heart: return CGSize(width: 250, height: 230)
        case .cloud: return CGSize(width: 280, height: 210)
        case .speechBubble: return CGSize(width: 260, height: 220)
        }
    }

    public var aspectRatio: CGFloat { defaultSize.height / defaultSize.width }

    public func next(steps: Int = 1) -> NoteShape {
        NoteShape.allCases.cycled(from: self, steps: steps)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NoteShape(rawValue: raw) ?? .square
    }

    // MARK: Geometry (unit space, y axis pointing up, origin bottom-left)

    /// Fractions of the note rect (left, bottom, right, top) that are reserved so the text
    /// stays inside the visible shape. Defined in the unit square the shape fills.
    public var safeInsets: (left: CGFloat, bottom: CGFloat, right: CGFloat, top: CGFloat) {
        switch self {
        case .square: return (0.07, 0.07, 0.07, 0.07)
        case .rectangle: return (0.06, 0.08, 0.06, 0.08)
        case .circle: return (0.16, 0.16, 0.16, 0.16)
        case .heart: return (0.23, 0.33, 0.23, 0.25)
        case .cloud: return (0.21, 0.22, 0.21, 0.36)
        case .speechBubble: return (0.07, 0.25, 0.07, 0.07)
        }
    }

    /// Rect inside `rect` in which text is guaranteed to be inside the shape.
    public func safeTextRect(in rect: CGRect) -> CGRect {
        let i = safeInsets
        return CGRect(x: rect.minX + rect.width * i.left,
                      y: rect.minY + rect.height * i.bottom,
                      width: rect.width * (1 - i.left - i.right),
                      height: rect.height * (1 - i.bottom - i.top))
    }

    /// Fraction of the note height available for text.
    public var verticalTextFraction: CGFloat {
        let i = safeInsets
        return 1 - i.bottom - i.top
    }

    public var horizontalTextFraction: CGFloat {
        let i = safeInsets
        return 1 - i.left - i.right
    }

    /// Vector outline of the shape, stretched to fill `rect`.
    public func path(in rect: CGRect) -> CGPath {
        let unit = unitPath()
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width, y: rect.height)
        return unit.copy(using: &transform) ?? unit
    }

    /// Outline in the unit square (0...1 on both axes).
    public func unitPath() -> CGPath {
        switch self {
        case .square, .rectangle:
            // Paper notes have barely rounded corners. Radius is expressed in unit space; the
            // stretch makes it slightly elliptic, which is invisible at this size.
            return CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                          cornerWidth: 0.015, cornerHeight: 0.015, transform: nil)
        case .circle:
            return CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1), transform: nil)
        case .heart:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0.5, y: 0.0))
            p.addCurve(to: CGPoint(x: 0.0, y: 0.66), control1: CGPoint(x: 0.34, y: 0.12), control2: CGPoint(x: 0.0, y: 0.40))
            p.addCurve(to: CGPoint(x: 0.26, y: 1.0), control1: CGPoint(x: 0.0, y: 0.86), control2: CGPoint(x: 0.11, y: 1.0))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.82), control1: CGPoint(x: 0.40, y: 1.0), control2: CGPoint(x: 0.5, y: 0.92))
            p.addCurve(to: CGPoint(x: 0.74, y: 1.0), control1: CGPoint(x: 0.5, y: 0.92), control2: CGPoint(x: 0.60, y: 1.0))
            p.addCurve(to: CGPoint(x: 1.0, y: 0.66), control1: CGPoint(x: 0.89, y: 1.0), control2: CGPoint(x: 1.0, y: 0.86))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.0), control1: CGPoint(x: 1.0, y: 0.40), control2: CGPoint(x: 0.66, y: 0.12))
            p.closeSubpath()
            return p
        case .cloud:
            let base = CGPath(roundedRect: CGRect(x: 0.06, y: 0.0, width: 0.88, height: 0.42),
                              cornerWidth: 0.2, cornerHeight: 0.2, transform: nil)
            let circles: [(CGFloat, CGFloat, CGFloat)] = [
                (0.20, 0.38, 0.20), (0.45, 0.64, 0.33), (0.74, 0.58, 0.26), (0.86, 0.34, 0.14),
            ]
            var result: CGPath = base
            for (cx, cy, r) in circles {
                let circle = CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
                result = result.union(circle)
            }
            return Self.normalized(result)
        case .speechBubble:
            let body = CGPath(roundedRect: CGRect(x: 0, y: 0.18, width: 1, height: 0.82),
                              cornerWidth: 0.12, cornerHeight: 0.14, transform: nil)
            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: 0.16, y: 0.24))
            tail.addLine(to: CGPoint(x: 0.08, y: 0.0))
            tail.addLine(to: CGPoint(x: 0.40, y: 0.24))
            tail.closeSubpath()
            return body.union(tail)
        }
    }

    /// Scales a path so its bounding box is exactly the unit square.
    static func normalized(_ path: CGPath) -> CGPath {
        let box = path.boundingBoxOfPath
        guard box.width > 0, box.height > 0 else { return path }
        var t = CGAffineTransform(scaleX: 1 / box.width, y: 1 / box.height)
            .translatedBy(x: -box.minX, y: -box.minY)
        return path.copy(using: &t) ?? path
    }
}

public struct NoteStyle: Equatable, Hashable, Sendable {
    public var color: NoteColor
    public var shape: NoteShape

    public init(color: NoteColor, shape: NoteShape) {
        self.color = color
        self.shape = shape
    }

    public static var allCombinations: [NoteStyle] {
        NoteColor.allCases.flatMap { c in NoteShape.allCases.map { NoteStyle(color: c, shape: $0) } }
    }
}

public enum StylePicker {
    /// A random style that differs from `previous` (if given).
    public static func random<G: RandomNumberGenerator>(excluding previous: NoteStyle?, using rng: inout G) -> NoteStyle {
        let candidates = NoteStyle.allCombinations.filter { $0 != previous }
        return candidates.randomElement(using: &rng) ?? NoteStyle(color: .classicYellow, shape: .square)
    }
}

extension Array where Element: Equatable {
    /// Element `steps` positions after `element`, wrapping in both directions.
    func cycled(from element: Element, steps: Int) -> Element {
        guard let index = firstIndex(of: element), !isEmpty else { return element }
        let n = count
        let next = ((index + steps) % n + n) % n
        return self[next]
    }
}
