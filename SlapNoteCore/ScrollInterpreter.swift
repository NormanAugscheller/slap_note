import CoreGraphics
import Foundation

/// Modifier combinations that can be bound to a placement-mode scroll action.
/// Control is deliberately absent: Control + scroll is the macOS accessibility zoom gesture.
public enum ScrollModifier: String, CaseIterable, Codable, Sendable {
    case none
    case shift
    case option
    case command
    case commandOption
    case shiftOption
    case commandShift

    public var symbol: String {
        switch self {
        case .none: return "—"
        case .shift: return "⇧"
        case .option: return "⌥"
        case .command: return "⌘"
        case .commandOption: return "⌘⌥"
        case .shiftOption: return "⇧⌥"
        case .commandShift: return "⌘⇧"
        }
    }

    public var displayName: String {
        self == .none ? "Scroll" : "\(symbol) + Scroll"
    }

    public init?(shift: Bool, option: Bool, command: Bool) {
        switch (shift, option, command) {
        case (false, false, false): self = .none
        case (true, false, false): self = .shift
        case (false, true, false): self = .option
        case (false, false, true): self = .command
        case (false, true, true): self = .commandOption
        case (true, true, false): self = .shiftOption
        case (true, false, true): self = .commandShift
        case (true, true, true): return nil
        }
    }
}

public struct ModifierState: Equatable, Sendable {
    public var shift: Bool
    public var option: Bool
    public var command: Bool
    public var control: Bool

    public init(shift: Bool = false, option: Bool = false, command: Bool = false, control: Bool = false) {
        self.shift = shift
        self.option = option
        self.command = command
        self.control = control
    }
}

public enum ScrollAction: String, CaseIterable, Codable, Sendable {
    case resizeProportional
    case resizeWidth
    case resizeHeight
    case cycleColor
    case cycleShape

    public var displayName: String {
        switch self {
        case .resizeProportional: return "Resize proportionally (font scales too)"
        case .resizeWidth: return "Change width only"
        case .resizeHeight: return "Change height only"
        case .cycleColor: return "Next / previous color"
        case .cycleShape: return "Next / previous shape"
        }
    }

    public var defaultModifier: ScrollModifier {
        switch self {
        case .resizeProportional: return .none
        case .resizeWidth: return .shift
        case .resizeHeight: return .option
        case .cycleColor: return .command
        case .cycleShape: return .commandOption
        }
    }
}

public struct ScrollBindings: Equatable, Sendable {
    public var modifiers: [ScrollAction: ScrollModifier]

    public init(modifiers: [ScrollAction: ScrollModifier] = [:]) {
        var m: [ScrollAction: ScrollModifier] = [:]
        for action in ScrollAction.allCases {
            m[action] = modifiers[action] ?? action.defaultModifier
        }
        self.modifiers = m
    }

    public static let defaults = ScrollBindings()

    public func modifier(for action: ScrollAction) -> ScrollModifier {
        modifiers[action] ?? action.defaultModifier
    }

    public func action(for state: ModifierState) -> ScrollAction? {
        if state.control { return nil }
        guard let mod = ScrollModifier(shift: state.shift, option: state.option, command: state.command) else {
            return nil
        }
        return ScrollAction.allCases.first { modifier(for: $0) == mod }
    }

    /// Actions that share a modifier with another action (would make one unreachable).
    public var conflictingActions: Set<ScrollAction> {
        var seen: [ScrollModifier: [ScrollAction]] = [:]
        for a in ScrollAction.allCases { seen[modifier(for: a), default: []].append(a) }
        return Set(seen.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    /// Assigns `modifier` to `action`; an action that previously used it gets `action`'s old modifier (swap).
    public mutating func assign(_ modifier: ScrollModifier, to action: ScrollAction) {
        let old = self.modifier(for: action)
        if let other = ScrollAction.allCases.first(where: { $0 != action && self.modifier(for: $0) == modifier }) {
            modifiers[other] = old
        }
        modifiers[action] = modifier
    }
}

public struct ScrollInput: Equatable, Sendable {
    public var deltaX: CGFloat
    public var deltaY: CGFloat
    /// True for trackpads / Magic Mouse (pixel deltas), false for classic wheels (line deltas).
    public var hasPreciseDeltas: Bool
    /// True on the first event of a trackpad gesture.
    public var gestureBegan: Bool

    public init(deltaX: CGFloat, deltaY: CGFloat, hasPreciseDeltas: Bool, gestureBegan: Bool = false) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.hasPreciseDeltas = hasPreciseDeltas
        self.gestureBegan = gestureBegan
    }

    /// macOS turns Shift + vertical wheel into horizontal scrolling, so both axes are read and the
    /// dominant non-zero one is used.
    public var effectiveDelta: CGFloat {
        abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
    }
}

public enum ScrollOutput: Equatable, Sendable {
    case resize(ResizeMode, factor: CGFloat)
    case cycleColor(steps: Int)
    case cycleShape(steps: Int)
}

/// Turns raw scroll events into placement-mode actions. Stateful: it accumulates trackpad
/// deltas for color/shape cycling so the style does not flicker.
public struct ScrollInterpreter: Sendable {
    public var bindings: ScrollBindings
    /// Points of precise scrolling per color/shape step.
    public static let cycleThreshold: CGFloat = 30
    /// Size factor per point of precise scrolling (exponential so it feels uniform).
    public static let preciseResizePerPoint: CGFloat = 0.004
    /// Size factor per wheel notch.
    public static let wheelStepFactor: CGFloat = 1.06
    /// Accelerated wheels report several lines per event; cap so it never jumps.
    public static let maxWheelStepsPerEvent: CGFloat = 3

    private var accumulator: CGFloat = 0
    private var lastAction: ScrollAction?

    public init(bindings: ScrollBindings = .defaults) {
        self.bindings = bindings
    }

    public mutating func reset() {
        accumulator = 0
        lastAction = nil
    }

    public mutating func interpret(_ input: ScrollInput, modifiers: ModifierState) -> ScrollOutput? {
        guard let action = bindings.action(for: modifiers) else { return nil }
        if action != lastAction || input.gestureBegan {
            accumulator = 0
            lastAction = action
        }
        let delta = input.effectiveDelta
        guard delta != 0, delta.isFinite else { return nil }

        switch action {
        case .resizeProportional, .resizeWidth, .resizeHeight:
            let mode: ResizeMode = action == .resizeProportional ? .proportional : (action == .resizeWidth ? .widthOnly : .heightOnly)
            let factor: CGFloat
            if input.hasPreciseDeltas {
                factor = exp(delta * Self.preciseResizePerPoint)
            } else {
                let steps = min(abs(delta), Self.maxWheelStepsPerEvent).rounded(.up)
                factor = pow(Self.wheelStepFactor, delta > 0 ? steps : -steps)
            }
            return .resize(mode, factor: factor)
        case .cycleColor, .cycleShape:
            let steps: Int
            if input.hasPreciseDeltas {
                accumulator += delta
                var s = 0
                while abs(accumulator) >= Self.cycleThreshold {
                    let sign: CGFloat = accumulator > 0 ? 1 : -1
                    accumulator -= sign * Self.cycleThreshold
                    s += Int(sign)
                }
                steps = s
            } else {
                // One step per wheel notch, regardless of acceleration.
                steps = delta > 0 ? 1 : -1
            }
            guard steps != 0 else { return nil }
            return action == .cycleColor ? .cycleColor(steps: steps) : .cycleShape(steps: steps)
        }
    }
}
