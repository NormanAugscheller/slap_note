import CoreGraphics
import Foundation

public enum ResizeMode: Equatable, Sendable {
    case proportional
    case widthOnly
    case heightOnly
}

public struct SizeLimits: Equatable, Sendable {
    public var minSide: CGFloat
    public var maxSide: CGFloat

    public init(minSide: CGFloat = 80, maxSide: CGFloat = 600) {
        self.minSide = minSide
        self.maxSide = maxSide
    }

    public static let manual = SizeLimits()
    public static let fontScaleRange: ClosedRange<CGFloat> = 0.3...6
}

public struct ResizeResult: Equatable, Sendable {
    public var size: CGSize
    public var fontScale: CGFloat
    /// True when the requested change was cut off by a size limit.
    public var hitLimit: Bool
}

public enum NoteGeometry {
    /// Applies a manual resize (scroll in placement mode) to the user-set size.
    /// Proportional resizing scales the font by exactly the same factor that was applied to the size.
    public static func resize(size: CGSize, fontScale: CGFloat, factor: CGFloat, mode: ResizeMode,
                              limits: SizeLimits = .manual) -> ResizeResult {
        guard factor > 0, factor.isFinite else {
            return ResizeResult(size: size, fontScale: fontScale, hitLimit: false)
        }
        switch mode {
        case .proportional:
            let lower = max(limits.minSide / size.width, limits.minSide / size.height)
            let upper = min(limits.maxSide / size.width, limits.maxSide / size.height)
            var f = min(max(factor, lower), upper)
            if lower > upper { f = 1 }
            // Keep the font inside its range too, without breaking the "same factor" rule.
            let fontLower = SizeLimits.fontScaleRange.lowerBound / fontScale
            let fontUpper = SizeLimits.fontScaleRange.upperBound / fontScale
            f = min(max(f, fontLower), fontUpper)
            let hit = abs(f - factor) > 0.0001
            return ResizeResult(size: CGSize(width: size.width * f, height: size.height * f),
                                fontScale: fontScale * f, hitLimit: hit)
        case .widthOnly:
            let (w, hit) = clamp(size.width * factor, limits)
            return ResizeResult(size: CGSize(width: w, height: size.height), fontScale: fontScale, hitLimit: hit)
        case .heightOnly:
            let (h, hit) = clamp(size.height * factor, limits)
            return ResizeResult(size: CGSize(width: size.width, height: h), fontScale: fontScale, hitLimit: hit)
        }
    }

    static func clamp(_ value: CGFloat, _ limits: SizeLimits) -> (CGFloat, Bool) {
        if value < limits.minSide { return (limits.minSide, true) }
        if value > limits.maxSide { return (limits.maxSide, true) }
        return (value, false)
    }

    /// Clamps any size into the manual limits (used when loading or switching shapes).
    public static func clampToManualLimits(_ size: CGSize, limits: SizeLimits = .manual) -> CGSize {
        CGSize(width: clamp(size.width, limits).0, height: clamp(size.height, limits).0)
    }

    /// Size used when switching to `shape` while keeping the current width.
    public static func size(switchingTo shape: NoteShape, from size: CGSize) -> CGSize {
        clampToManualLimits(CGSize(width: size.width, height: size.width * shape.aspectRatio))
    }
}

public struct AutoGrowResult: Equatable, Sendable {
    public var height: CGFloat
    /// True when even the maximum height is not enough and the text must scroll inside the note.
    public var needsInternalScrolling: Bool
}

public enum AutoGrow {
    /// Extra space the auto-grow keeps below the visible screen height.
    public static let screenMargin: CGFloat = 40

    /// Note height needed so that `textHeight` fits into the shape's safe text area.
    /// `padding` is the constant inner padding (applied on top and bottom) inside the safe rect.
    public static func requiredHeight(textHeight: CGFloat, shape: NoteShape, padding: CGFloat) -> CGFloat {
        (textHeight + 2 * padding) / shape.verticalTextFraction
    }

    /// Displayed note height: grows (never shrinks below the manual height) up to the
    /// visible screen height minus the margin; beyond that the text scrolls internally.
    public static func displayedHeight(manualHeight: CGFloat, textHeight: CGFloat, shape: NoteShape,
                                       padding: CGFloat, visibleScreenHeight: CGFloat) -> AutoGrowResult {
        let needed = requiredHeight(textHeight: textHeight, shape: shape, padding: padding)
        let cap = max(manualHeight, visibleScreenHeight - screenMargin)
        if needed <= manualHeight {
            return AutoGrowResult(height: manualHeight, needsInternalScrolling: false)
        }
        if needed > cap {
            return AutoGrowResult(height: cap, needsInternalScrolling: true)
        }
        return AutoGrowResult(height: ceil(needed), needsInternalScrolling: false)
    }
}
