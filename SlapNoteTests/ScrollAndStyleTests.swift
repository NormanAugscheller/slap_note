import CoreGraphics
import XCTest
@testable import SlapNoteCore

final class ScrollAndStyleTests: XCTestCase {
    func testEffectiveDeltaUsesHorizontalWhenShiftConvertedTheWheel() {
        // Shift + vertical mouse wheel arrives as horizontal scroll.
        XCTAssertEqual(ScrollInput(deltaX: 3, deltaY: 0, hasPreciseDeltas: false).effectiveDelta, 3)
        XCTAssertEqual(ScrollInput(deltaX: 0, deltaY: -2, hasPreciseDeltas: false).effectiveDelta, -2)
        XCTAssertEqual(ScrollInput(deltaX: 1, deltaY: -4, hasPreciseDeltas: true).effectiveDelta, -4)
    }

    func testShiftWheelResizesWidthViaHorizontalDelta() {
        var interpreter = ScrollInterpreter()
        let out = interpreter.interpret(ScrollInput(deltaX: 1, deltaY: 0, hasPreciseDeltas: false),
                                        modifiers: ModifierState(shift: true))
        guard case let .resize(mode, factor)? = out else { return XCTFail("expected resize, got \(String(describing: out))") }
        XCTAssertEqual(mode, .widthOnly)
        XCTAssertGreaterThan(factor, 1)
    }

    func testShiftTrackpadResizesWidth() {
        var interpreter = ScrollInterpreter()
        let out = interpreter.interpret(ScrollInput(deltaX: 0, deltaY: -10, hasPreciseDeltas: true),
                                        modifiers: ModifierState(shift: true))
        guard case let .resize(mode, factor)? = out else { return XCTFail() }
        XCTAssertEqual(mode, .widthOnly)
        XCTAssertLessThan(factor, 1)
    }

    func testDefaultBindings() {
        let b = ScrollBindings.defaults
        XCTAssertEqual(b.action(for: ModifierState()), .resizeProportional)
        XCTAssertEqual(b.action(for: ModifierState(shift: true)), .resizeWidth)
        XCTAssertEqual(b.action(for: ModifierState(option: true)), .resizeHeight)
        XCTAssertEqual(b.action(for: ModifierState(command: true)), .cycleColor)
        XCTAssertEqual(b.action(for: ModifierState(option: true, command: true)), .cycleShape)
        XCTAssertNil(b.action(for: ModifierState(control: true)), "Control + scroll is reserved for zoom")
        XCTAssertTrue(b.conflictingActions.isEmpty)
    }

    func testAssigningModifierSwapsInsteadOfConflicting() {
        var b = ScrollBindings.defaults
        b.assign(.command, to: .resizeWidth)
        XCTAssertEqual(b.modifier(for: .resizeWidth), .command)
        XCTAssertEqual(b.modifier(for: .cycleColor), .shift)
        XCTAssertTrue(b.conflictingActions.isEmpty)
    }

    func testWheelResizeIsSteppedAndCapped() {
        var interpreter = ScrollInterpreter()
        guard case let .resize(_, one)? = interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 1, hasPreciseDeltas: false), modifiers: ModifierState()),
              case let .resize(_, many)? = interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 40, hasPreciseDeltas: false), modifiers: ModifierState())
        else { return XCTFail() }
        XCTAssertEqual(one, ScrollInterpreter.wheelStepFactor, accuracy: 0.0001)
        XCTAssertEqual(many, pow(ScrollInterpreter.wheelStepFactor, ScrollInterpreter.maxWheelStepsPerEvent), accuracy: 0.0001)
    }

    func testPreciseResizeIsSmoothAndSymmetric() {
        var interpreter = ScrollInterpreter()
        guard case let .resize(_, up)? = interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 5, hasPreciseDeltas: true), modifiers: ModifierState()),
              case let .resize(_, down)? = interpreter.interpret(ScrollInput(deltaX: 0, deltaY: -5, hasPreciseDeltas: true), modifiers: ModifierState())
        else { return XCTFail() }
        XCTAssertEqual(up * down, 1, accuracy: 0.0001)
        XCTAssertLessThan(up, 1.05)
    }

    func testWheelCyclesOneStepPerNotch() {
        var interpreter = ScrollInterpreter()
        let out = interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 7, hasPreciseDeltas: false), modifiers: ModifierState(command: true))
        XCTAssertEqual(out, .cycleColor(steps: 1))
        let back = interpreter.interpret(ScrollInput(deltaX: 0, deltaY: -1, hasPreciseDeltas: false), modifiers: ModifierState(command: true))
        XCTAssertEqual(back, .cycleColor(steps: -1))
    }

    func testTrackpadCyclingAccumulatesThirtyPoints() {
        var interpreter = ScrollInterpreter()
        let mods = ModifierState(option: true, command: true)
        XCTAssertNil(interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 12, hasPreciseDeltas: true), modifiers: mods))
        XCTAssertNil(interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 12, hasPreciseDeltas: true), modifiers: mods))
        XCTAssertEqual(interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 12, hasPreciseDeltas: true), modifiers: mods), .cycleShape(steps: 1))
        XCTAssertEqual(interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 70, hasPreciseDeltas: true), modifiers: mods), .cycleShape(steps: 2))
    }

    func testAccumulatorResetsOnNewGesture() {
        var interpreter = ScrollInterpreter()
        let mods = ModifierState(command: true)
        XCTAssertNil(interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 25, hasPreciseDeltas: true), modifiers: mods))
        XCTAssertNil(interpreter.interpret(ScrollInput(deltaX: 0, deltaY: 10, hasPreciseDeltas: true, gestureBegan: true), modifiers: mods))
    }

    func testColorAndShapeCyclingWraps() {
        XCTAssertEqual(NoteColor.paperWhite.next(), .classicYellow)
        XCTAssertEqual(NoteColor.classicYellow.next(steps: -1), .paperWhite)
        XCTAssertEqual(NoteColor.pink.next(steps: 2), .skyBlue)
        XCTAssertEqual(NoteShape.speechBubble.next(), .square)
        XCTAssertEqual(NoteShape.square.next(steps: -1), .speechBubble)
        XCTAssertEqual(NoteShape.square.next(steps: 13), .rectangle)
    }

    func testRandomStyleNeverRepeatsPrevious() {
        var rng = SplitMix64(seed: 42)
        var previous: NoteStyle?
        var seen = Set<NoteStyle>()
        for _ in 0..<500 {
            let s = StylePicker.random(excluding: previous, using: &rng)
            XCTAssertNotEqual(s, previous)
            seen.insert(s)
            previous = s
        }
        XCTAssertGreaterThan(seen.count, 30, "random style should spread over the combinations")
    }

    func testPendulumStaysWithinOneDegreeAndSettles() {
        var sway = PendulumSway()
        for _ in 0..<120 { sway.step(dt: 1.0 / 120, cursorVelocityX: 5000) }
        XCTAssertLessThanOrEqual(abs(sway.angle), PendulumSway.maxAngle)
        XCTAssertLessThan(sway.angle, 0, "moving right tilts clockwise")
        for _ in 0..<600 { sway.step(dt: 1.0 / 120, cursorVelocityX: 0) }
        XCTAssertEqual(sway.angle, 0, accuracy: 0.01)
    }
}
