import Foundation

public enum LaunchKind: Equatable, Sendable {
    case manual
    case loginItem
}

/// Decides whether a launch came from the login item (see DECISIONS.md, "Login-item launch detection").
public enum LaunchContext {
    /// Seconds after the user session started within which an enabled login item launch is assumed.
    public static let sessionWindow: TimeInterval = 90

    /// - Parameters:
    ///   - appleEventSaysLoginItem: `true` if the launch Apple event carried `keyAELaunchedAsLogInItem`,
    ///     `false` if an event was present without it, `nil` if there was no launch event.
    ///   - loginItemEnabled: `SMAppService.mainApp.status == .enabled`.
    ///   - secondsSinceSessionStart: time since the user's login session started, if known.
    public static func classify(appleEventSaysLoginItem: Bool?, loginItemEnabled: Bool,
                                secondsSinceSessionStart: TimeInterval?) -> LaunchKind {
        if appleEventSaysLoginItem == true { return .loginItem }
        guard loginItemEnabled, let s = secondsSinceSessionStart, s >= 0 else { return .manual }
        return s <= sessionWindow ? .loginItem : .manual
    }

    /// The settings window opens on a manual launch and always on the very first launch.
    public static func shouldShowSettings(kind: LaunchKind, isFirstLaunch: Bool) -> Bool {
        isFirstLaunch || kind == .manual
    }
}

/// Spring that makes the hanging note sway like paper held at its top edge.
public struct PendulumSway: Sendable {
    /// Maximum sway in degrees.
    public static let maxAngle: Double = 1
    public var angle: Double = 0
    public var velocity: Double = 0
    public var stiffness: Double = 90
    public var damping: Double = 9
    /// Degrees of target angle per point/second of horizontal cursor speed.
    public var gain: Double = 0.0025

    public init() {}

    /// Advances the simulation. `cursorVelocityX` in points per second.
    public mutating func step(dt: Double, cursorVelocityX: Double) {
        guard dt > 0, dt.isFinite else { return }
        let dt = min(dt, 1.0 / 20)
        // Moving right drags the bottom left: a counter-clockwise tilt is a positive angle.
        let target = min(max(-cursorVelocityX * gain, -Self.maxAngle), Self.maxAngle)
        let accel = -stiffness * (angle - target) - damping * velocity
        velocity += accel * dt
        angle += velocity * dt
        angle = min(max(angle, -Self.maxAngle), Self.maxAngle)
    }
}
