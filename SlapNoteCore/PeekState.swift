import Foundation

/// Peek has two independent reasons: the shortcut is held, or a clicked reminder notification
/// highlights the notes for a few seconds. Peek is on while at least one reason holds, so neither
/// can end the other early.
public struct PeekState: Equatable, Sendable {
    public var held = false
    public var highlighted = false

    public init() {}

    public var isActive: Bool { held || highlighted }
}
