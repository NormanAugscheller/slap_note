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
        /// No change before the timeout. Nothing to read; keep watching for a late copy.
        case timedOut
    }

    public static let timeout: TimeInterval = 1.0
    /// How long after a timeout a late copy from the target app is still undone.
    public static let lateCopyWindow: TimeInterval = 2.0

    public static func outcome(before: Int, current: Int, elapsed: TimeInterval, timeout: TimeInterval = timeout) -> Outcome {
        switch current - before {
        case 0: return elapsed >= timeout ? .timedOut : .waiting
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
