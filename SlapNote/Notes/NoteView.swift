import AppKit
import QuartzCore
import SlapNoteCore

/// Text view that never draws a background and reports Esc / ⌘T to its note.
final class NoteTextView: NSTextView {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override var acceptsFirstResponder: Bool { isEditable }
}

/// Draws the paper: glow, shadow, shape, shading, texture and the curled corner. Layers only.
final class PaperView: LayerView {
    let glowLayer = CAShapeLayer()
    let shadowLayer = CALayer()
    let paperLayer = CAShapeLayer()
    let shadeLayer = CAGradientLayer()
    let shadeMask = CAShapeLayer()
    let textureLayer = CALayer()
    let textureMask = CAShapeLayer()
    let flapShadowLayer = CAShapeLayer()
    let flapLayer = CAGradientLayer()
    let flapMask = CAShapeLayer()
    let creaseLayer = CAShapeLayer()

    static let texture: NSImage? = {
        guard let url = Bundle.main.url(forResource: "paper_texture", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        guard let root = layer else { return }
        root.masksToBounds = false

        glowLayer.fillColor = NSColor.clear.cgColor
        glowLayer.shadowColor = NSColor(srgbRed: 1, green: 0.78, blue: 0.2, alpha: 1).cgColor
        glowLayer.shadowRadius = 16
        glowLayer.shadowOpacity = 0
        glowLayer.shadowOffset = .zero

        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.28
        shadowLayer.shadowRadius = 5
        shadowLayer.shadowOffset = CGSize(width: 0, height: -3)

        shadeLayer.colors = [NSColor(white: 1, alpha: 0.18).cgColor, NSColor(white: 0, alpha: 0.06).cgColor]
        shadeLayer.startPoint = CGPoint(x: 0.3, y: 1)
        shadeLayer.endPoint = CGPoint(x: 0.7, y: 0)
        shadeLayer.mask = shadeMask

        textureLayer.mask = textureMask
        textureLayer.opacity = 0.16
        textureLayer.compositingFilter = "multiplyBlendMode"

        flapShadowLayer.fillColor = NSColor.clear.cgColor
        flapShadowLayer.shadowColor = NSColor.black.cgColor
        flapShadowLayer.shadowOpacity = 0.3
        flapShadowLayer.shadowRadius = 3
        flapShadowLayer.shadowOffset = CGSize(width: -1.5, height: 1.5)
        flapLayer.mask = flapMask
        flapLayer.startPoint = CGPoint(x: 1, y: 0)
        flapLayer.endPoint = CGPoint(x: 0.4, y: 0.6)

        creaseLayer.fillColor = NSColor.clear.cgColor
        creaseLayer.strokeColor = NSColor(white: 0, alpha: 0.18).cgColor
        creaseLayer.lineWidth = 0.8
        creaseLayer.lineJoin = .round
        creaseLayer.opacity = 0

        for l in [glowLayer, shadowLayer, paperLayer, shadeLayer, textureLayer, flapShadowLayer, flapLayer, creaseLayer] as [CALayer] {
            root.addSublayer(l)
        }
    }

    func configure(shapePath: CGPath, color: NoteColor, texture: Bool, curl: Double) {
        Motion.setWithoutAnimation {
            for l in [glowLayer, shadowLayer, paperLayer, shadeLayer, textureLayer, flapShadowLayer, flapLayer, creaseLayer] as [CALayer] {
                l.frame = bounds
            }
            glowLayer.path = shapePath
            glowLayer.shadowPath = shapePath
            shadowLayer.shadowPath = shapePath
            paperLayer.fillColor = NSColor(color.rgb).cgColor
            shadeMask.frame = bounds
            textureMask.frame = bounds
            flapMask.frame = bounds
            if texture, let image = Self.texture {
                textureLayer.backgroundColor = NSColor(patternImage: image).cgColor
                textureLayer.isHidden = false
            } else {
                textureLayer.isHidden = true
            }
            let base = color.rgb
            flapLayer.colors = [NSColor(base.darkened(by: 0.16)).cgColor, NSColor(base.darkened(by: 0.02)).cgColor]
            applyCurl(shapePath: shapePath, curl: curl)
        }
    }

    func applyCurl(shapePath: CGPath, curl: Double) {
        let geometry = CurlGeometry.make(shapePath: shapePath, rect: bounds, curl: curl)
        paperLayer.path = geometry.remaining
        shadeMask.path = geometry.remaining
        textureMask.path = geometry.remaining
        if let flap = geometry.flap, !flap.isEmpty {
            flapMask.path = flap
            flapShadowLayer.shadowPath = flap
            flapLayer.isHidden = false
            flapShadowLayer.isHidden = false
        } else {
            flapLayer.isHidden = true
            flapShadowLayer.isHidden = true
        }
    }

    func setShadow(radius: CGFloat, offsetY: CGFloat, opacity: Float, duration: CFTimeInterval) {
        let changes: [(String, Any, Any)] = [
            ("shadowRadius", shadowLayer.shadowRadius, radius),
            ("shadowOffset", NSValue(size: shadowLayer.shadowOffset), NSValue(size: CGSize(width: 0, height: offsetY))),
            ("shadowOpacity", shadowLayer.shadowOpacity, opacity),
        ]
        Motion.setWithoutAnimation {
            shadowLayer.shadowRadius = radius
            shadowLayer.shadowOffset = CGSize(width: 0, height: offsetY)
            shadowLayer.shadowOpacity = opacity
        }
        guard duration > 0 else { return }
        for (key, from, to) in changes {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = shadowLayer.presentation()?.value(forKeyPath: key) ?? from
            a.toValue = to
            a.duration = duration
            a.timingFunction = Motion.easeOut
            shadowLayer.add(a, forKey: key)
        }
    }
}

/// The complete note: transparent margin around nested transform containers.
///
/// body (static rotation, sway, wiggle) → lift (scale: summon, slap, hover, bump) → flutter (3D edge
/// flutter) → paper + text + reminder label.
final class NoteView: NSView {
    /// Room around the note for shadow, glow, rotation and hover lift.
    static let margin: CGFloat = 40
    static let textPadding: CGFloat = 6
    static let reminderLabelHeight: CGFloat = 16

    let body = LayerView()
    let lift = LayerView()
    let flutter = LayerView()
    let paper = PaperView()
    let scrollView = NSScrollView()
    let textView: NoteTextView
    let reminderLabel = NSTextField(labelWithString: "")

    /// When false, every mouse event inside the note goes to this view (stuck mode).
    var textInteractionEnabled = false {
        didSet {
            textView.isEditable = textInteractionEnabled
            textView.isSelectable = textInteractionEnabled
        }
    }

    var mouseHandler: NoteMouseHandling?
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        textView = NoteTextView(frame: .zero, textContainer: container)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        addSubview(body)
        body.addSubview(lift)
        lift.addSubview(flutter)
        flutter.addSubview(paper)
        flutter.addSubview(scrollView)
        flutter.addSubview(reminderLabel)
        for v in [body, lift, flutter, paper] as [NSView] { v.layer?.masksToBounds = false }

        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.focusRingType = .none
        textView.isEditable = false
        textView.isSelectable = false
        textView.setAccessibilityLabel("Note text")

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.contentView.drawsBackground = false

        reminderLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        reminderLabel.alignment = .right
        reminderLabel.isHidden = true
        reminderLabel.lineBreakMode = .byClipping
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    var noteRect: CGRect { bounds.insetBy(dx: Self.margin, dy: Self.margin) }

    /// Lays out every container for a note of `size` (displayed size, including auto-grow).
    func layout(noteSize: CGSize, shape: NoteShape, hasReminder: Bool) {
        let rect = CGRect(x: Self.margin, y: Self.margin, width: noteSize.width, height: noteSize.height)
        Motion.setWithoutAnimation {
            body.frame = rect
            let inner = CGRect(origin: .zero, size: noteSize)
            lift.frame = inner
            flutter.frame = inner
            paper.frame = inner
            let text = Self.textRect(in: inner, shape: shape, hasReminder: hasReminder)
            scrollView.frame = text
            textView.minSize = NSSize(width: text.width, height: text.height)
            textView.maxSize = NSSize(width: text.width, height: .greatestFiniteMagnitude)
            textView.frame = NSRect(x: 0, y: 0, width: text.width, height: max(textView.frame.height, text.height))
            textView.textContainer?.size = NSSize(width: text.width, height: .greatestFiniteMagnitude)
            let safe = shape.safeTextRect(in: inner)
            reminderLabel.frame = CGRect(x: safe.minX, y: safe.maxY - Self.reminderLabelHeight, width: safe.width - 2,
                                         height: Self.reminderLabelHeight)
        }
        updateTrackingAreas()
    }

    static func textRect(in noteBounds: CGRect, shape: NoteShape, hasReminder: Bool) -> CGRect {
        var r = shape.safeTextRect(in: noteBounds).insetBy(dx: textPadding, dy: textPadding)
        if hasReminder { r.size.height -= reminderLabelHeight }
        r.size.height = max(r.height, 10)
        r.size.width = max(r.width, 10)
        return r.integral
    }

    // MARK: Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        let notePoint = CGPoint(x: local.x - Self.margin, y: local.y - Self.margin)
        guard paper.paperLayer.path?.contains(notePoint) ?? noteRect.contains(local) else { return nil }
        if textInteractionEnabled {
            return super.hitTest(point) ?? self
        }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: noteRect, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { mouseHandler?.noteMouseEntered() }
    override func mouseExited(with event: NSEvent) { mouseHandler?.noteMouseExited() }
    override func mouseDown(with event: NSEvent) { mouseHandler?.noteMouseDown(event) }
    override func mouseDragged(with event: NSEvent) { mouseHandler?.noteMouseDragged(event) }
    override func mouseUp(with event: NSEvent) { mouseHandler?.noteMouseUp(event) }
    override func rightMouseDown(with event: NSEvent) { mouseHandler?.noteRightMouseDown(event) }

    /// Converts a window point into text-view coordinates, undoing the note's small rotation so that
    /// line hit-testing matches what the user sees.
    func textViewPoint(fromWindow windowPoint: NSPoint, rotation: CGFloat) -> NSPoint {
        let local = convert(windowPoint, from: nil)
        let c = CGPoint(x: noteRect.midX, y: noteRect.midY)
        let a = -Motion.degrees(rotation)
        let dx = local.x - c.x, dy = local.y - c.y
        let unrotated = CGPoint(x: c.x + dx * cos(a) - dy * sin(a), y: c.y + dx * sin(a) + dy * cos(a))
        return textView.convert(unrotated, from: self)
    }
}

protocol NoteMouseHandling: AnyObject {
    func noteMouseEntered()
    func noteMouseExited()
    func noteMouseDown(_ event: NSEvent)
    func noteMouseDragged(_ event: NSEvent)
    func noteMouseUp(_ event: NSEvent)
    func noteRightMouseDown(_ event: NSEvent)
}

/// Borderless, transparent panel that hosts one note. Non-activating, so clicking or dragging a
/// stuck note does not steal focus from the app the user is working in.
final class NotePanel: NSPanel {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.stationary, .ignoresCycle, .fullScreenDisallowsTiling]
        level = NoteLevels.desktop
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        // Standard editing commands, also when SlapNote has no active menu bar.
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let chars = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector?
            switch chars {
            case "a": action = #selector(NSText.selectAll(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "x": action = #selector(NSText.cut(_:))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}
