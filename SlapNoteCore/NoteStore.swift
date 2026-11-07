import Foundation

/// On-disk container. `version` enables future migrations.
public struct NotesFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var notes: [NoteRecord]

    public init(version: Int = NotesFile.currentVersion, notes: [NoteRecord]) {
        self.version = version
        self.notes = notes
    }
}

/// One schema migration step operating on the raw JSON object, from `fromVersion` to `fromVersion + 1`.
public struct NotesMigration: Sendable {
    public var fromVersion: Int
    public var migrate: @Sendable ([String: Any]) throws -> [String: Any]

    public init(fromVersion: Int, migrate: @escaping @Sendable ([String: Any]) throws -> [String: Any]) {
        self.fromVersion = fromVersion
        self.migrate = migrate
    }
}

public enum NotesMigrator {
    /// Registered migrations. Version 1 is the first released format, so there are none yet.
    /// When the format changes: bump `NotesFile.currentVersion` and append a step here.
    public static let builtIn: [NotesMigration] = []

    public enum MigrationError: Error { case notAnObject }

    /// The `version` stored in the file (1 if missing), or nil if the data is not a JSON object.
    public static func storedVersion(of data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["version"] as? Int) ?? 1
    }

    /// Decodes file data, running migrations from the stored version up to `targetVersion`.
    /// A missing `version` key is treated as version 1. Files from a *newer* app version are
    /// decoded as far as possible (unknown fields are ignored).
    public static func decode(_ data: Data, migrations: [NotesMigration] = builtIn,
                              targetVersion: Int = NotesFile.currentVersion) throws -> NotesFile {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MigrationError.notAnObject
        }
        var version = (object["version"] as? Int) ?? 1
        while version < targetVersion {
            guard let step = migrations.first(where: { $0.fromVersion == version }) else { break }
            object = try step.migrate(object)
            version += 1
            object["version"] = version
        }
        object["version"] = max(version, (object["version"] as? Int) ?? version)
        let migrated = try JSONSerialization.data(withJSONObject: object)
        let file = try NoteStore.makeDecoder().decode(NotesFile.self, from: migrated)
        return NotesFile(version: targetVersion, notes: file.notes)
    }
}

public enum NoteLoadSource: Equatable, Sendable {
    case main
    case backup
    case empty
}

public struct NoteLoadResult: Sendable {
    public var notes: [NoteRecord]
    public var source: NoteLoadSource
    /// The main file existed but could not be read; it was moved aside.
    public var recoveredFromCorruption: Bool
}

/// Reads and writes `notes.json` atomically, keeping `notes.json.bak` as the last good version.
public final class NoteStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("notes.json") }
    public var backupURL: URL { directory.appendingPathComponent("notes.json.bak") }
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// `~/Library/Application Support/SlapNote`
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SlapNote", isDirectory: true)
    }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func load() -> NoteLoadResult {
        writeBlock = nil
        preservedCopies = []
        // Both files are checked, whichever of them is loaded: a save replaces both.
        for url in [fileURL, backupURL] {
            if let data = try? Data(contentsOf: url) { preserveIfNewer(data) }
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL), let file = try? NotesMigrator.decode(data) {
                return NoteLoadResult(notes: file.notes, source: .main, recoveredFromCorruption: false)
            }
            // Corrupt main file: keep it for inspection, never overwrite the backup with it.
            moveCorruptFileAside()
            if let notes = loadBackup() {
                if writeBlock == nil { try? save(notes) }
                return NoteLoadResult(notes: notes, source: .backup, recoveredFromCorruption: true)
            }
            return NoteLoadResult(notes: [], source: .empty, recoveredFromCorruption: true)
        }
        if let notes = loadBackup() {
            if writeBlock == nil { try? save(notes) }
            return NoteLoadResult(notes: notes, source: .backup, recoveredFromCorruption: false)
        }
        return NoteLoadResult(notes: [], source: .empty, recoveredFromCorruption: false)
    }

    public enum WriteBlock: Equatable, Sendable {
        /// A file was written with this newer format version and no verified copy of it exists.
        case newerVersionNotPreserved(version: Int)
    }

    public enum StoreError: Error, Equatable {
        case writesBlocked(WriteBlock)
    }

    /// Why saving is refused, if it is. Set by `load()` (or re-checked by `save`) when a file from a newer
    /// SlapNote version could not be preserved: saving would destroy fields this version cannot represent.
    public private(set) var writeBlock: WriteBlock?

    /// Verified untouched copies of newer-version files found by the last `load()`, with their bytes.
    private var preservedCopies: [(url: URL, data: Data, version: Int)] = []

    /// The copy of the main file (or, if only the backup was newer, of the backup).
    public var preservedCopyURL: URL? { preservedCopies.first?.url }
    public var preservedCopyURLs: [URL] { preservedCopies.map(\.url) }

    /// Preferred name of the untouched copy kept when a file written by a newer SlapNote version is opened.
    public func newerVersionCopyURL(version: Int) -> URL {
        directory.appendingPathComponent("notes.v\(version).json")
    }

    /// A file from a newer app version may hold fields this version does not know; saving would drop
    /// them. Before anything is written, keep a copy of exactly those bytes and read it back.
    /// If that fails, every write is refused until the next `load()`.
    private func preserveIfNewer(_ data: Data) {
        guard let version = NotesMigrator.storedVersion(of: data), version > NotesFile.currentVersion else { return }
        if preservedCopies.contains(where: { $0.data == data }) { return }
        if let url = writeVerifiedCopy(data, version: version) {
            preservedCopies.append((url, data, version))
        } else {
            writeBlock = .newerVersionNotPreserved(version: version)
        }
    }

    /// A copy only counts if it is an independent regular file with exactly the expected bytes:
    /// a symbolic or hard link to the notes file would change with the next save.
    private func isIntactCopy(_ url: URL, of data: Data) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.referenceCount] as? Int ?? 1) == 1 else { return false }
        return (try? Data(contentsOf: url)) == data
    }

    /// Reuses an identical existing copy, otherwise writes a new file that never replaces an existing one.
    /// Returns nil if no verified copy could be made.
    private func writeVerifiedCopy(_ data: Data, version: Int) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let candidates = [newerVersionCopyURL(version: version)] + (0..<20).map { n in
            directory.appendingPathComponent("notes.v\(version)-\(stamp)" + (n == 0 ? "" : "-\(n)") + ".json")
        }
        for url in candidates {
            // attributesOfItem does not follow symbolic links, so a link (even a dangling one) is "taken".
            if (try? fileManager.attributesOfItem(atPath: url.path)) != nil {
                if isIntactCopy(url, of: data) { return url }
                continue
            }
            do {
                try data.write(to: url, options: [.withoutOverwriting])
                return isIntactCopy(url, of: data) ? url : nil
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Right before a save replaces the files: every preserved copy must still be intact. A copy that was
    /// removed or replaced in the meantime is made again; if that fails, the save is refused.
    private func recheckPreservedCopies() {
        for (index, copy) in preservedCopies.enumerated() where !isIntactCopy(copy.url, of: copy.data) {
            if let url = writeVerifiedCopy(copy.data, version: copy.version) {
                preservedCopies[index].url = url
            } else {
                writeBlock = .newerVersionNotPreserved(version: copy.version)
                return
            }
        }
    }

    private func loadBackup() -> [NoteRecord]? {
        guard let data = try? Data(contentsOf: backupURL), let file = try? NotesMigrator.decode(data) else {
            return nil
        }
        return file.notes
    }

    private func moveCorruptFileAside() {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = directory.appendingPathComponent("notes.corrupt-\(stamp).json")
        try? fileManager.removeItem(at: target)
        try? fileManager.moveItem(at: fileURL, to: target)
    }

    /// Atomic write (temporary file + rename) of the main file, then of the backup.
    /// The data is encoded once and verified to decode before anything is replaced.
    /// Throws `StoreError.writesBlocked` while `writeBlock` is set.
    public func save(_ notes: [NoteRecord]) throws {
        if writeBlock == nil { recheckPreservedCopies() }
        if let writeBlock { throw StoreError.writesBlocked(writeBlock) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(NotesFile(notes: notes))
        _ = try NotesMigrator.decode(data)
        try data.write(to: fileURL, options: [.atomic])
        try data.write(to: backupURL, options: [.atomic])
    }
}
