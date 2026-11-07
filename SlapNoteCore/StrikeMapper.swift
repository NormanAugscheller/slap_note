import Foundation

/// Line bookkeeping for the to-do style strike-through. A "line" is a paragraph separated by "\n".
public enum StrikeMapper {
    public static func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    /// UTF-16 ranges (NSString semantics) of each line, excluding the newline.
    public static func lineRanges(of text: String) -> [NSRange] {
        let ns = text as NSString
        var ranges: [NSRange] = []
        var start = 0
        for i in 0..<ns.length where ns.character(at: i) == 0x0A {
            ranges.append(NSRange(location: start, length: i - start))
            start = i + 1
        }
        ranges.append(NSRange(location: start, length: ns.length - start))
        return ranges
    }

    /// Line index containing the UTF-16 offset `offset`.
    public static func lineIndex(forUTF16Offset offset: Int, in text: String) -> Int {
        let ranges = lineRanges(of: text)
        for (i, r) in ranges.enumerated() where offset <= r.location + r.length {
            return i
        }
        return max(ranges.count - 1, 0)
    }

    public static func toggle(_ index: Int, in struck: Set<Int>) -> Set<Int> {
        var s = struck
        if s.contains(index) { s.remove(index) } else { s.insert(index) }
        return s
    }

    /// Moves strike-through marks along with their lines when the text changes.
    /// Unchanged lines keep their state. A block of removed lines that is replaced by a block of
    /// the same size at the same place counts as edited in place and keeps the state line by line.
    public static func remap(struck: Set<Int>, from oldText: String, to newText: String) -> Set<Int> {
        guard !struck.isEmpty else { return [] }
        let old = lines(of: oldText)
        let new = lines(of: newText)
        if old == new { return struck.filter { $0 < new.count } }

        let diff = new.difference(from: old)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in diff {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var result = Set<Int>()
        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            // Collect the next run of removals and insertions between unchanged anchors.
            var removedRun: [Int] = []
            while i < old.count && removed.contains(i) { removedRun.append(i); i += 1 }
            var insertedRun: [Int] = []
            while j < new.count && inserted.contains(j) { insertedRun.append(j); j += 1 }
            if !removedRun.isEmpty && removedRun.count == insertedRun.count {
                for (o, n) in zip(removedRun, insertedRun) where struck.contains(o) {
                    result.insert(n)
                }
            }
            if i < old.count && j < new.count && !removed.contains(i) && !inserted.contains(j) {
                if struck.contains(i) { result.insert(j) }
                i += 1
                j += 1
            } else if removedRun.isEmpty && insertedRun.isEmpty {
                // Safety: should not happen with a consistent diff, but never loop forever.
                if i < old.count { i += 1 }
                if j < new.count { j += 1 }
            }
        }
        return result
    }
}
