import CoreGraphics
import Foundation

/// Position of a note's center relative to a display's visible frame (0...1 on both axes,
/// origin bottom-left, AppKit convention).
public struct DisplayPosition: Codable, Equatable, Sendable {
    public var displayUUID: String
    public var relativeX: Double
    public var relativeY: Double

    public init(displayUUID: String, relativeX: Double, relativeY: Double) {
        self.displayUUID = displayUUID
        self.relativeX = relativeX
        self.relativeY = relativeY
    }
}

public struct ReminderRecord: Codable, Equatable, Sendable {
    public var date: Date
    /// The reminder time has passed and the "due" behavior was triggered.
    public var fired: Bool
    /// The user interacted with the note after it fired (stops wiggling).
    public var acknowledged: Bool

    public init(date: Date, fired: Bool = false, acknowledged: Bool = false) {
        self.date = date
        self.fired = fired
        self.acknowledged = acknowledged
    }

    private enum CodingKeys: String, CodingKey { case date, fired, acknowledged }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        fired = try c.decodeIfPresent(Bool.self, forKey: .fired) ?? false
        acknowledged = try c.decodeIfPresent(Bool.self, forKey: .acknowledged) ?? fired
    }
}

public struct NoteRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    /// Indices of struck-through lines (lines are separated by "\n").
    public var struckLines: [Int]
    public var color: NoteColor
    public var shape: NoteShape
    /// User-set (manual) size. The displayed height may be larger because of auto-grow.
    public var width: Double
    public var height: Double
    public var fontScale: Double
    /// Rotation in degrees, −2...+2, chosen once when the note is slapped.
    public var rotation: Double
    public var position: DisplayPosition
    public var created: Date
    public var modified: Date
    /// Last edit, move, strike-through or reminder change. Drives aging.
    public var lastTouched: Date
    public var reminder: ReminderRecord?

    public init(id: UUID = UUID(), text: String = "", struckLines: [Int] = [], color: NoteColor, shape: NoteShape,
                width: Double, height: Double, fontScale: Double = 1, rotation: Double = 0,
                position: DisplayPosition, created: Date = Date(), modified: Date? = nil,
                lastTouched: Date? = nil, reminder: ReminderRecord? = nil) {
        self.id = id
        self.text = text
        self.struckLines = struckLines
        self.color = color
        self.shape = shape
        self.width = width
        self.height = height
        self.fontScale = fontScale
        self.rotation = rotation
        self.position = position
        self.created = created
        self.modified = modified ?? created
        self.lastTouched = lastTouched ?? created
        self.reminder = reminder
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, struckLines, color, shape, width, height, fontScale, rotation, position
        case created, modified, lastTouched, reminder
    }

    /// Tolerant decoding: every field except `id` and `position` has a default, so files written
    /// by older versions (with fewer fields) still load. Unknown keys are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        struckLines = try c.decodeIfPresent([Int].self, forKey: .struckLines) ?? []
        color = try c.decodeIfPresent(NoteColor.self, forKey: .color) ?? .classicYellow
        shape = try c.decodeIfPresent(NoteShape.self, forKey: .shape) ?? .square
        let def = shape.defaultSize
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? Double(def.width)
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? Double(def.height)
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        position = try c.decode(DisplayPosition.self, forKey: .position)
        let now = Date()
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? now
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? created
        lastTouched = try c.decodeIfPresent(Date.self, forKey: .lastTouched) ?? modified
        reminder = try c.decodeIfPresent(ReminderRecord.self, forKey: .reminder)
        sanitize()
    }

    /// Repairs values that would break layout (e.g. a hand-edited or partially corrupt file).
    public mutating func sanitize() {
        let clamped = NoteGeometry.clampToManualLimits(CGSize(width: width.finiteOr(Double(shape.defaultSize.width)),
                                                              height: height.finiteOr(Double(shape.defaultSize.height))))
        width = Double(clamped.width)
        height = Double(clamped.height)
        let range = SizeLimits.fontScaleRange
        fontScale = min(max(fontScale.finiteOr(1), Double(range.lowerBound)), Double(range.upperBound))
        rotation = min(max(rotation.finiteOr(0), -2), 2)
        position.relativeX = min(max(position.relativeX.finiteOr(0.5), 0), 1)
        position.relativeY = min(max(position.relativeY.finiteOr(0.5), 0), 1)
        let lineCount = text.components(separatedBy: "\n").count
        struckLines = Array(Set(struckLines.filter { $0 >= 0 && $0 < lineCount })).sorted()
    }

    public var style: NoteStyle {
        get { NoteStyle(color: color, shape: shape) }
        set { color = newValue.color; shape = newValue.shape }
    }

    public var manualSize: CGSize {
        get { CGSize(width: width, height: height) }
        set { width = Double(newValue.width); height = Double(newValue.height) }
    }

    public var firstLine: String {
        text.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
    }

    public mutating func touch(at date: Date = Date()) {
        modified = date
        lastTouched = date
    }
}

extension Double {
    func finiteOr(_ fallback: Double) -> Double { isFinite ? self : fallback }
}
