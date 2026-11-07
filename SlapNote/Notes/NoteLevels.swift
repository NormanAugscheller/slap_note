import AppKit
import QuartzCore

/// Window levels used by SlapNote. Order (low → high):
/// desktop notes < normal app windows < always-on-top notes < peek < capture < hanging note < effects.
enum NoteLevels {
    /// Just above the Finder's desktop icons, below every normal window.
    static let desktop = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    static let alwaysOnTop = NSWindow.Level.floating
    /// Used for ~1.2 s after slapping so the user sees where the note went.
    static let justSlapped = NSWindow.Level.floating
    static let peek = NSWindow.Level.statusBar
    static let capture = NSWindow.Level.popUpMenu
    static let hanging = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
    static let effects = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)

    static func resting(alwaysOnTop: Bool) -> NSWindow.Level {
        alwaysOnTop ? Self.alwaysOnTop : desktop
    }
}

enum Motion {
    /// "Reduce motion" in System Settings › Accessibility › Display.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func degrees(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

    /// A transform that rotates/scales around the center of `bounds` (independent of the layer's
    /// anchor point, which AppKit manages for layer-backed views) and then translates.
    static func transform(bounds: CGRect, anchorPoint: CGPoint, rotation: CGFloat = 0, scale: CGFloat = 1,
                          translation: CGPoint = .zero, pivot: CGPoint? = nil) -> CATransform3D {
        let anchor = CGPoint(x: bounds.width * anchorPoint.x, y: bounds.height * anchorPoint.y)
        let target = pivot ?? CGPoint(x: bounds.midX - bounds.minX, y: bounds.midY - bounds.minY)
        let d = CGPoint(x: target.x - anchor.x, y: target.y - anchor.y)
        var t = CATransform3DMakeTranslation(-d.x, -d.y, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(degrees(rotation), 0, 0, 1))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(d.x + translation.x, d.y + translation.y, 0))
        return t
    }

    static func transform(for layer: CALayer, rotation: CGFloat = 0, scale: CGFloat = 1,
                          translation: CGPoint = .zero, pivot: CGPoint? = nil) -> CATransform3D {
        transform(bounds: layer.bounds, anchorPoint: layer.anchorPoint, rotation: rotation, scale: scale,
                  translation: translation, pivot: pivot)
    }

    /// Rotation around the X axis through `pivotY` with perspective (paper edge fluttering).
    static func tilt(for layer: CALayer, degrees angle: CGFloat, pivotY: CGFloat) -> CATransform3D {
        let anchorY = layer.bounds.height * layer.anchorPoint.y
        let d = pivotY - anchorY
        var t = CATransform3DMakeTranslation(0, -d, 0)
        var r = CATransform3DIdentity
        r.m34 = -1 / 900
        r = CATransform3DRotate(r, degrees(angle), 1, 0, 0)
        t = CATransform3DConcat(t, r)
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(0, d, 0))
        return t
    }

    static func setWithoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    static let easeOut = CAMediaTimingFunction(name: .easeOut)
    static let easeIn = CAMediaTimingFunction(name: .easeIn)
    static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
}

/// A plain layer-backed view used as a transform container.
class LayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }
}
