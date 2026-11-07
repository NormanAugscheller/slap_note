import CoreGraphics
import Foundation

public struct DisplayInfo: Equatable, Sendable {
    public var uuid: String
    /// Visible frame in global AppKit coordinates (excludes menu bar and Dock).
    public var visibleFrame: CGRect
    public var isMain: Bool

    public init(uuid: String, visibleFrame: CGRect, isMain: Bool) {
        self.uuid = uuid
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }
}

public struct ResolvedPlacement: Equatable, Sendable {
    /// Note center in global coordinates.
    public var center: CGPoint
    /// The display the note is shown on right now.
    public var displayUUID: String
    /// True when the note's own display is missing and it was moved to the main display.
    public var isFallback: Bool
}

public enum DisplayResolver {
    /// Stores the note center relative to the display that contains it (or the nearest one).
    public static func position(forCenter center: CGPoint, displays: [DisplayInfo]) -> DisplayPosition? {
        guard let display = display(containing: center, in: displays) else { return nil }
        let f = display.visibleFrame
        let rx = f.width > 0 ? Double((center.x - f.minX) / f.width) : 0.5
        let ry = f.height > 0 ? Double((center.y - f.minY) / f.height) : 0.5
        return DisplayPosition(displayUUID: display.uuid, relativeX: min(max(rx, 0), 1), relativeY: min(max(ry, 0), 1))
    }

    public static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let hit = displays.first(where: { $0.visibleFrame.contains(point) }) { return hit }
        return displays.min { distance(point, $0.visibleFrame) < distance(point, $1.visibleFrame) }
    }

    /// Where a note should be shown. A note whose display is missing goes onto the main display
    /// (same relative position, kept inside the visible frame); its stored display UUID is kept so
    /// it moves back when that display returns.
    public static func resolve(_ position: DisplayPosition, noteSize: CGSize, displays: [DisplayInfo]) -> ResolvedPlacement? {
        let own = displays.first { $0.uuid == position.displayUUID }
        guard let target = own ?? displays.first(where: { $0.isMain }) ?? displays.first else { return nil }
        let f = target.visibleFrame
        let raw = CGPoint(x: f.minX + CGFloat(position.relativeX) * f.width,
                          y: f.minY + CGFloat(position.relativeY) * f.height)
        return ResolvedPlacement(center: clampCenter(raw, size: noteSize, into: f),
                                 displayUUID: target.uuid, isFallback: own == nil)
    }

    /// Moves a center so that a note of `size` lies fully inside `frame`. A note larger than the
    /// frame is aligned to the frame's top-left corner.
    public static func clampCenter(_ center: CGPoint, size: CGSize, into frame: CGRect) -> CGPoint {
        let halfW = size.width / 2
        let halfH = size.height / 2
        let x: CGFloat
        if size.width >= frame.width {
            x = frame.minX + halfW
        } else {
            x = min(max(center.x, frame.minX + halfW), frame.maxX - halfW)
        }
        let y: CGFloat
        if size.height >= frame.height {
            y = frame.maxY - halfH
        } else {
            y = min(max(center.y, frame.minY + halfH), frame.maxY - halfH)
        }
        return CGPoint(x: x, y: y)
    }

    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
