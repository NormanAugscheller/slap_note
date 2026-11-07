import AppKit
import QuartzCore
import SlapNoteCore

protocol PlacementSessionDelegate: AnyObject {
    func placementDidSlap(_ session: PlacementSession)
    func placementDidDiscard(_ session: PlacementSession)
    func placementDidCycleStyle(_ session: PlacementSession, color steps: Int)
    func placementDidCycleShape(_ session: PlacementSession, shape steps: Int)
}

/// Placement mode: the note hangs ghosted on the cursor, one transparent capture window per screen
/// swallows clicks and scrolls so nothing reaches the apps underneath.
final class PlacementSession: NSObject {
    let note: NoteController
    weak var delegate: PlacementSessionDelegate?
    private var captureWindows: [CaptureWindow] = []
    private var displayLink: CADisplayLink?
    private var interpreter: ScrollInterpreter
    private var sway = PendulumSway()
    private var lastMouse: CGPoint
    private var lastTimestamp: CFTimeInterval = 0
    private var smoothedVelocity: Double = 0
    /// While the reminder picker is open the note stops following the cursor.
    var isFrozen = false
    private(set) var isActive = false
    private var screenObserver: NSObjectProtocol?

    init(note: NoteController, bindings: ScrollBindings) {
        self.note = note
        interpreter = ScrollInterpreter(bindings: bindings)
        lastMouse = NSEvent.mouseLocation
        super.init()
    }

    func begin() {
        isActive = true
        note.setMode(.placement)
        note.window.level = NoteLevels.hanging
        note.window.ignoresMouseEvents = true
        note.window.alphaValue = 0.5
        note.window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        note.view.paper.setShadow(radius: 14, offsetY: -9, opacity: 0.3, duration: 0)
        note.setNoteCenter(NSEvent.mouseLocation)
        rebuildCaptureWindows()
        note.window.orderFrontRegardless()
        note.window.makeKey()
        note.window.makeFirstResponder(note.view.textView)
        NoteAnimator.summon(note.view)

        let link = note.view.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildCaptureWindows() }
        }
    }

    func end() {
        guard isActive else { return }
        isActive = false
        displayLink?.invalidate()
        displayLink = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for w in captureWindows {
            w.orderOut(nil)
            w.close()
        }
        captureWindows.removeAll()
        note.window.ignoresMouseEvents = false
        note.window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenDisallowsTiling]
    }

    private func rebuildCaptureWindows() {
        for w in captureWindows { w.orderOut(nil); w.close() }
        captureWindows = NSScreen.screens.map { screen in
            let w = CaptureWindow(screen: screen)
            w.session = self
            w.orderFrontRegardless()
            return w
        }
    }

    var currentSwayAngle: CGFloat { CGFloat(sway.angle) }

    @objc private func frame(_ link: CADisplayLink) {
        guard isActive, !isFrozen else { return }
        let now = link.timestamp
        let mouse = NSEvent.mouseLocation
        let dt = lastTimestamp > 0 ? now - lastTimestamp : 1.0 / 60
        lastTimestamp = now
        let vx = dt > 0 ? Double(mouse.x - lastMouse.x) / dt : 0
        smoothedVelocity = smoothedVelocity * 0.75 + vx * 0.25
        lastMouse = mouse
        note.setNoteCenter(mouse)
        if !Motion.reduced {
            sway.step(dt: dt, cursorVelocityX: smoothedVelocity)
            note.applyRotation(CGFloat(sway.angle))
        }
    }

    /// Re-centers the note under the cursor right away (after resizing).
    func recenter() {
        note.setNoteCenter(NSEvent.mouseLocation)
    }

    // MARK: Input from capture windows

    func handleLeftClick() {
        guard isActive, !isFrozen else { return }
        delegate?.placementDidSlap(self)
    }

    func handleRightClick() {
        guard isActive, !isFrozen else { return }
        delegate?.placementDidDiscard(self)
    }

    func handleScroll(_ event: NSEvent) {
        guard isActive, !isFrozen else { return }
        interpreter.bindings = note.settings.scrollBindings
        let flags = event.modifierFlags
        let mods = ModifierState(shift: flags.contains(.shift), option: flags.contains(.option),
                                 command: flags.contains(.command), control: flags.contains(.control))
        let input = ScrollInput(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                hasPreciseDeltas: event.hasPreciseScrollingDeltas,
                                gestureBegan: event.phase.contains(.began))
        guard let output = interpreter.interpret(input, modifiers: mods) else { return }
        switch output {
        case let .resize(mode, factor):
            note.applyResize(factor: factor, mode: mode)
            recenter()
        case let .cycleColor(steps):
            delegate?.placementDidCycleStyle(self, color: steps)
        case let .cycleShape(steps):
            delegate?.placementDidCycleShape(self, shape: steps)
            recenter()
        }
    }
}

/// Invisible full-screen window that captures clicks and scrolls during placement mode.
final class CaptureWindow: NSPanel {
    weak var session: PlacementSession?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        // Not fully clear: guarantees the window server routes clicks to this window everywhere.
        backgroundColor = NSColor(white: 0, alpha: 0.002)
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = NoteLevels.capture
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        let view = CaptureView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.owner = self
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class CaptureView: NSView {
    weak var owner: CaptureWindow?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { owner?.session?.handleLeftClick() }
    override func rightMouseDown(with event: NSEvent) { owner?.session?.handleRightClick() }
    override func scrollWheel(with event: NSEvent) { owner?.session?.handleScroll(event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}
