import Foundation

/// Decisions for the ⌘C fallback of "Note from selection". SlapNote posts ⌘C and watches the
/// pasteboard's change count. Exactly one change is the target app's copy. Anything else is unclear,
/// and an unclear pasteboard is neither read nor restored, so another app's copy is never taken
/// as the note or wiped by the restore.
public enum CopyFallback {
    public enum Outcome: Equatable, Sendable {
        /// Nothing changed yet; keep polling.
        case waiting
        /// Exactly one change: the copy SlapNote asked for. Read it, then restore the snapshot.
        case copied
        /// More than one change: someone else wrote too. Do not read, do not restore.
        case unclear
        /// The timeout passed (whatever changed by then). Nothing to read, nothing to restore.
        case timedOut
    }

    public static let timeout: TimeInterval = 1.0

    /// The deadline wins: a change seen only after the timeout cannot be told apart from a copy by the
    /// user, so it is neither read nor restored over.
    public static func outcome(before: Int, current: Int, elapsed: TimeInterval, timeout: TimeInterval = timeout) -> Outcome {
        if elapsed >= timeout { return .timedOut }
        switch current - before {
        case 0: return .waiting
        case 1: return .copied
        default: return .unclear
        }
    }

    /// After reading the copy: restore only if nobody wrote to the pasteboard in between.
    public static func mayRestore(before: Int, current: Int) -> Bool {
        current == before + 1
    }

    /// The snapshot can only be restored faithfully if every type of every item could be read.
    public static func snapshotIsComplete(typesPerItem: [Int], readablePerItem: [Int]) -> Bool {
        typesPerItem == readablePerItem
    }
}
