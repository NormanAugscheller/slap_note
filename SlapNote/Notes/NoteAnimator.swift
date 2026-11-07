import AppKit
import QuartzCore
import SlapNoteCore

/// All note animations (spec §6). Every animation has a Reduce Motion variant that only fades.
enum NoteAnimator {
    // MARK: Summon / slap / hover / bump

    /// Pop in from ~70 % with a slight overshoot (≈180 ms).
    static func summon(_ view: NoteView) {
        let layer = view.lift.layer!
        if Motion.reduced {
            fade(layer, from: 0, to: 1, duration: 0.15)
            return
        }
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [0.7, 1.05, 0.99, 1.0].map { NSValue(caTransform3D: Motion.transform(for: layer, scale: $0)) }
        a.keyTimes = [0, 0.6, 0.85, 1]
        a.duration = 0.18
        a.timingFunctions = [Motion.easeOut, Motion.easeInOut, Motion.easeInOut]
        layer.add(a, forKey: "summon")
        fade(layer, from: 0, to: 1, duration: 0.1)
    }

    /// Quick press 100 → 94 → 100 %, shadow flattens, tiny settle wobble toward the final rotation.
    static func slap(_ view: NoteView, fromRotation: CGFloat, toRotation: CGFloat) {
        let lift = view.lift.layer!
        let body = view.body.layer!
        Motion.setWithoutAnimation {
            body.transform = Motion.transform(for: body, rotation: toRotation)
            lift.transform = CATransform3DIdentity
        }
        view.paper.setShadow(radius: 4, offsetY: -2.5, opacity: 0.3, duration: Motion.reduced ? 0 : 0.16)
        guard !Motion.reduced else { return }
        let press = CAKeyframeAnimation(keyPath: "transform")
        press.values = [1.0, 0.94, 1.0].map { NSValue(caTransform3D: Motion.transform(for: lift, scale: $0)) }
        press.keyTimes = [0, 0.4, 1]
        press.duration = 0.16
        press.timingFunctions = [Motion.easeOut, Motion.easeOut]
        lift.add(press, forKey: "slap")

        let wobble = CAKeyframeAnimation(keyPath: "transform")
        let delta = toRotation - fromRotation
        wobble.values = [fromRotation, toRotation + delta * 0.35 + 0.6, toRotation - 0.3, toRotation].map {
            NSValue(caTransform3D: Motion.transform(for: body, rotation: $0))
        }
        wobble.keyTimes = [0, 0.35, 0.7, 1]
        wobble.duration = 0.3
        wobble.timingFunctions = [Motion.easeOut, Motion.easeInOut, Motion.easeInOut]
        body.add(wobble, forKey: "wobble")
    }

    /// Lift ~103 %, softer and bigger shadow, gentle bottom-edge flutter.
    static func hover(_ view: NoteView, on: Bool) {
        let lift = view.lift.layer!
        let flutter = view.flutter.layer!
        let duration: CFTimeInterval = 0.15
        if on {
            view.paper.setShadow(radius: 10, offsetY: -7, opacity: 0.32, duration: duration)
        } else {
            view.paper.setShadow(radius: 4, offsetY: -2.5, opacity: 0.3, duration: duration)
        }
        guard !Motion.reduced else { return }
        let target = Motion.transform(for: lift, scale: on ? 1.03 : 1.0)
        animateTransform(lift, to: target, duration: duration, key: "hover")
        if on {
            let f = CAKeyframeAnimation(keyPath: "transform")
            let top = flutter.bounds.height
            f.values = [0, 3, -1.5, 2, 0].map { NSValue(caTransform3D: Motion.tilt(for: flutter, degrees: $0, pivotY: top)) }
            f.keyTimes = [0, 0.3, 0.55, 0.8, 1]
            f.duration = 1.6
            f.repeatCount = .infinity
            f.timingFunctions = [Motion.easeInOut, Motion.easeInOut, Motion.easeInOut, Motion.easeInOut]
            flutter.add(f, forKey: "flutter")
        } else {
            flutter.removeAnimation(forKey: "flutter")
        }
    }

    /// Elastic overshoot when a size limit is hit.
    static func limitBump(_ view: NoteView, grew: Bool) {
        let lift = view.lift.layer!
        guard !Motion.reduced, lift.animation(forKey: "bump") == nil else { return }
        let a = CAKeyframeAnimation(keyPath: "transform")
        let values: [CGFloat] = grew ? [1, 1.035, 0.985, 1.005, 1] : [1, 0.965, 1.015, 0.995, 1]
        a.values = values.map { NSValue(caTransform3D: Motion.transform(for: lift, scale: $0)) }
        a.keyTimes = [0, 0.3, 0.6, 0.85, 1]
        a.duration = 0.24
        lift.add(a, forKey: "bump")
    }

    /// Wiggle (±4°, 3 cycles) and a soft glow pulse.
    static func attention(_ view: NoteView, baseRotation: CGFloat) {
        let glow = view.paper.glowLayer
        let pulse = CAKeyframeAnimation(keyPath: "shadowOpacity")
        pulse.values = [0, 0.9, 0.35, 0.8, 0]
        pulse.keyTimes = [0, 0.25, 0.5, 0.7, 1]
        pulse.duration = 1.6
        glow.add(pulse, forKey: "glow")
        guard !Motion.reduced else { return }
        let body = view.body.layer!
        let w = CAKeyframeAnimation(keyPath: "transform")
        w.values = [0, 4, -4, 4, -4, 4, -4, 0].map { NSValue(caTransform3D: Motion.transform(for: body, rotation: baseRotation + $0)) }
        w.duration = 0.75
        w.timingFunction = Motion.easeInOut
        body.add(w, forKey: "wiggle")
    }

    /// Slight dip while the note sinks from "just slapped" to its resting window level.
    static func sink(_ window: NSWindow, view: NoteView, changeLevel: @escaping () -> Void) {
        if Motion.reduced {
            changeLevel()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = Motion.easeIn
            window.animator().alphaValue = 0.55
        }, completionHandler: {
            changeLevel()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = Motion.easeOut
                window.animator().alphaValue = 1
            }
        })
        let lift = view.lift.layer!
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [1, 0.975, 1].map { NSValue(caTransform3D: Motion.transform(for: lift, scale: $0)) }
        a.duration = 0.3
        lift.add(a, forKey: "sink")
    }

    // MARK: Helpers

    static func animateTransform(_ layer: CALayer, to target: CATransform3D, duration: CFTimeInterval, key: String) {
        let from = layer.presentation()?.transform ?? layer.transform
        Motion.setWithoutAnimation { layer.transform = target }
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = NSValue(caTransform3D: from)
        a.toValue = NSValue(caTransform3D: target)
        a.duration = duration
        a.timingFunction = Motion.easeOut
        layer.add(a, forKey: key)
    }

    static func fade(_ layer: CALayer, from: Float, to: Float, duration: CFTimeInterval) {
        Motion.setWithoutAnimation { layer.opacity = to }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.timingFunction = to > from ? Motion.easeOut : Motion.easeIn
        layer.add(a, forKey: "fade")
    }
}

/// Crumple-and-throw (discard) and its reverse (restore).
enum ThrowAnimator {
    static let crumpleDuration: CFTimeInterval = 0.25
    static let flightDuration: CFTimeInterval = 0.45

    /// Crumples the note in its window, then throws the paper ball off the bottom of the screen.
    static func throwAway(_ view: NoteView, window: NSWindow, color: NoteColor, completion: @escaping () -> Void) {
        if Motion.reduced {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                window.animator().alphaValue = 0
            }, completionHandler: completion)
            return
        }
        let seed = UInt64.random(in: 1...UInt64.max / 2)
        let spin: CGFloat = Bool.random() ? 1 : -1
        crumple(view, seed: seed, reverse: false, spin: spin)
        DispatchQueue.main.asyncAfter(deadline: .now() + crumpleDuration) {
            let ball = ballGeometry(view)
            let center = window.convertPoint(toScreen: view.convert(ball.center, from: view.paper))
            window.orderOut(nil)
            fly(color: color, ballPoints: ball.points.map { CGPoint(x: $0.x - ball.center.x, y: $0.y - ball.center.y) },
                start: center, reverse: false, spin: spin, seed: seed, completion: completion)
        }
    }

    /// Reverse of `throwAway`: the ball flies in from below and unfolds into the note.
    static func restore(_ view: NoteView, window: NSWindow, color: NoteColor, completion: @escaping () -> Void) {
        if Motion.reduced {
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                window.animator().alphaValue = 1
            }, completionHandler: completion)
            return
        }
        let seed = UInt64.random(in: 1...UInt64.max / 2)
        let spin: CGFloat = Bool.random() ? 1 : -1
        let ball = ballGeometry(view)
        let center = window.convertPoint(toScreen: view.convert(ball.center, from: view.paper))
        fly(color: color, ballPoints: ball.points.map { CGPoint(x: $0.x - ball.center.x, y: $0.y - ball.center.y) },
            start: center, reverse: true, spin: spin, seed: seed) {
            window.alphaValue = 1
            window.orderFrontRegardless()
            crumple(view, seed: seed, reverse: true, spin: spin)
            DispatchQueue.main.asyncAfter(deadline: .now() + crumpleDuration, execute: completion)
        }
    }

    private static func ballGeometry(_ view: NoteView) -> (center: CGPoint, points: [CGPoint]) {
        let b = view.paper.bounds
        let center = CGPoint(x: b.midX, y: b.midY)
        let radius = max(min(b.width, b.height) * 0.2, 18)
        return (center, Crumple.ball(center: center, radius: radius, seed: 7))
    }

    /// Morphs the paper into a ball (or back when `reverse`), shrinks and turns it.
    private static func crumple(_ view: NoteView, seed: UInt64, reverse: Bool, spin: CGFloat) {
        let paper = view.paper
        guard let shapePath = paper.paperLayer.path else { return }
        let outline = Crumple.outline(of: shapePath)
        let ball = ballGeometry(view).points
        let steps: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1]
        var frames = steps.map { PathSampler.polygonPath(Crumple.frame(from: outline, to: ball, t: $0, seed: seed)) }
        if reverse { frames.reverse() }
        let duration = crumpleDuration

        for layer in [paper.paperLayer, paper.glowLayer] as [CAShapeLayer] {
            let a = CAKeyframeAnimation(keyPath: "path")
            a.values = frames
            a.duration = duration
            a.timingFunction = reverse ? Motion.easeOut : Motion.easeIn
            a.fillMode = .forwards
            a.isRemovedOnCompletion = reverse
            layer.add(a, forKey: "crumple")
        }
        let shadow = CAKeyframeAnimation(keyPath: "shadowPath")
        shadow.values = frames
        shadow.duration = duration
        shadow.fillMode = .forwards
        shadow.isRemovedOnCompletion = reverse
        paper.shadowLayer.add(shadow, forKey: "crumple")

        // Text, shading, texture and curl disappear quickly while crumpling.
        let fadeTargets: [CALayer] = [view.scrollView.layer, view.reminderLabel.layer, paper.shadeLayer, paper.textureLayer,
                                      paper.flapLayer, paper.flapShadowLayer].compactMap { $0 }
        for l in fadeTargets {
            let f = CABasicAnimation(keyPath: "opacity")
            f.fromValue = reverse ? 0 : 1
            f.toValue = reverse ? 1 : 0
            f.duration = reverse ? duration : duration * 0.4
            f.beginTime = reverse ? CACurrentMediaTime() + duration * 0.3 : 0
            f.fillMode = .both
            f.isRemovedOnCompletion = reverse
            l.add(f, forKey: "crumpleFade")
        }
        // Creases appear on the ball.
        paper.creaseLayer.path = creasePath(center: CGPoint(x: paper.bounds.midX, y: paper.bounds.midY),
                                            radius: max(min(paper.bounds.width, paper.bounds.height) * 0.2, 18), seed: seed)
        let c = CABasicAnimation(keyPath: "opacity")
        c.fromValue = reverse ? 1 : 0
        c.toValue = reverse ? 0 : 1
        c.duration = duration
        c.fillMode = .forwards
        c.isRemovedOnCompletion = reverse
        paper.creaseLayer.add(c, forKey: "creases")

        let lift = view.lift.layer!
        let turn = CAKeyframeAnimation(keyPath: "transform")
        var values: [CGFloat] = [0, 0.5, 1]
        if reverse { values.reverse() }
        turn.values = values.map { NSValue(caTransform3D: Motion.transform(for: lift, rotation: 28 * spin * $0, scale: 1 - 0.15 * $0)) }
        turn.duration = duration
        turn.fillMode = .forwards
        turn.isRemovedOnCompletion = reverse
        lift.add(turn, forKey: "crumpleTurn")
    }

    static func creasePath(center: CGPoint, radius: CGFloat, seed: UInt64) -> CGPath {
        var rng = SplitMix64(seed: seed)
        let p = CGMutablePath()
        for _ in 0..<7 {
            let a = CGFloat(rng.nextUnit()) * 2 * .pi
            let r1 = radius * CGFloat(0.15 + rng.nextUnit() * 0.3)
            let r2 = radius * CGFloat(0.6 + rng.nextUnit() * 0.3)
            let bend = CGFloat(rng.nextUnit() - 0.5) * 0.9
            p.move(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
            p.addLine(to: CGPoint(x: center.x + cos(a + bend * 0.5) * (r1 + r2) / 2, y: center.y + sin(a + bend * 0.5) * (r1 + r2) / 2))
            p.addLine(to: CGPoint(x: center.x + cos(a + bend) * r2, y: center.y + sin(a + bend) * r2))
        }
        return p
    }

    /// Flies a paper ball along a gravity arc in a transparent full-screen overlay.
    private static func fly(color: NoteColor, ballPoints: [CGPoint], start: CGPoint, reverse: Bool, spin: CGFloat,
                            seed: UInt64, completion: @escaping () -> Void) {
        let screen = NSScreen.screens.first { $0.frame.contains(start) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            completion()
            return
        }
        let overlay = EffectsWindow(screen: screen)
        let origin = screen.frame.origin
        let local = CGPoint(x: start.x - origin.x, y: start.y - origin.y)

        let ball = CAShapeLayer()
        ball.path = PathSampler.polygonPath(ballPoints)
        ball.fillColor = NSColor(color.rgb).cgColor
        ball.shadowColor = NSColor.black.cgColor
        ball.shadowOpacity = 0.3
        ball.shadowRadius = 4
        ball.shadowOffset = CGSize(width: 0, height: -3)
        ball.shadowPath = ball.path
        let radius = ballPoints.map { hypot($0.x, $0.y) }.max() ?? 20
        let creases = CAShapeLayer()
        creases.path = creasePath(center: .zero, radius: radius, seed: seed)
        creases.strokeColor = NSColor(white: 0, alpha: 0.18).cgColor
        creases.fillColor = NSColor.clear.cgColor
        creases.lineWidth = 0.8
        ball.addSublayer(creases)
        ball.position = local
        overlay.rootLayer.addSublayer(ball)
        overlay.orderFrontRegardless()

        let dx = CGFloat.random(in: 90...220) * (Bool.random() ? 1 : -1)
        let end = CGPoint(x: local.x + dx, y: -radius * 2 - 40)
        let control = CGPoint(x: local.x + dx * 0.45, y: local.y + 110)
        let arc = CGMutablePath()
        if reverse {
            arc.move(to: end)
            arc.addQuadCurve(to: local, control: control)
        } else {
            arc.move(to: local)
            arc.addQuadCurve(to: end, control: control)
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            overlay.orderOut(nil)
            overlay.close()
            completion()
        }
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = arc
        move.duration = flightDuration
        // Gravity: slow at the top of the arc, accelerating downward.
        move.timingFunction = reverse ? CAMediaTimingFunction(controlPoints: 0.1, 0.6, 0.4, 1)
                                      : CAMediaTimingFunction(controlPoints: 0.5, 0, 0.9, 0.4)
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        ball.add(move, forKey: "flight")
        let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
        rotate.fromValue = reverse ? spin * .pi * 2 : 0
        rotate.toValue = reverse ? 0 : spin * .pi * 2
        rotate.duration = flightDuration
        rotate.fillMode = .forwards
        rotate.isRemovedOnCompletion = false
        ball.add(rotate, forKey: "spin")
        CATransaction.commit()
    }
}

/// Transparent, click-through overlay covering one screen for flying paper balls.
final class EffectsWindow: NSPanel {
    let rootLayer = CALayer()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NoteLevels.effects
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.addSublayer(rootLayer)
        rootLayer.frame = view.bounds
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
}
