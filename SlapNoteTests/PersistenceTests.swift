import XCTest
@testable import SlapNoteCore

final class PersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SlapNoteTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleNote(text: String = "Buy milk\nCall Anna") -> NoteRecord {
        NoteRecord(text: text, struckLines: [1], color: .lavender, shape: .heart, width: 250, height: 230,
                   fontScale: 1.4, rotation: -1.3,
                   position: DisplayPosition(displayUUID: "DISPLAY-A", relativeX: 0.25, relativeY: 0.75),
                   created: Date(timeIntervalSince1970: 1_700_000_000),
                   reminder: ReminderRecord(date: Date(timeIntervalSince1970: 1_700_003_600)))
    }

    func testRoundTripKeepsEveryField() throws {
        let store = NoteStore(directory: directory)
        let notes = [sampleNote(), sampleNote(text: "Second")]
        try store.save(notes)
        let loaded = store.load()
        XCTAssertEqual(loaded.source, .main)
        XCTAssertEqual(loaded.notes.count, 2)
        let a = loaded.notes[0]
        XCTAssertEqual(a.id, notes[0].id)
        XCTAssertEqual(a.text, "Buy milk\nCall Anna")
        XCTAssertEqual(a.struckLines, [1])
        XCTAssertEqual(a.color, .lavender)
        XCTAssertEqual(a.shape, .heart)
        XCTAssertEqual(a.width, 250)
        XCTAssertEqual(a.height, 230)
        XCTAssertEqual(a.fontScale, 1.4)
        XCTAssertEqual(a.rotation, -1.3)
        XCTAssertEqual(a.position, notes[0].position)
        XCTAssertEqual(a.created, notes[0].created)
        XCTAssertEqual(a.reminder, notes[0].reminder)
        XCTAssertEqual(loaded.notes[1].struckLines, [], "out-of-range strike index is sanitized away")
    }

    func testFileHasVersionField() throws {
        let store = NoteStore(directory: directory)
        try store.save([sampleNote()])
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        XCTAssertEqual(object?["version"] as? Int, NotesFile.currentVersion)
    }

    func testCorruptMainFileFallsBackToBackup() throws {
        let store = NoteStore(directory: directory)
        let note = sampleNote()
        try store.save([note])
        try Data("{ this is not json".utf8).write(to: store.fileURL)
        let loaded = store.load()
        XCTAssertEqual(loaded.source, .backup)
        XCTAssertTrue(loaded.recoveredFromCorruption)
        XCTAssertEqual(loaded.notes.map(\.id), [note.id])
        // The corrupt file is kept aside and the main file is repaired.
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("notes.corrupt-") })
        XCTAssertEqual(store.load().source, .main)
    }

    func testCorruptMainAndBackupGivesEmptyWithoutCrash() throws {
        let store = NoteStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0xFF, 0x00]).write(to: store.fileURL)
        try Data("[]".utf8).write(to: store.backupURL)
        let loaded = store.load()
        XCTAssertEqual(loaded.source, .empty)
        XCTAssertTrue(loaded.recoveredFromCorruption)
    }

    func testMissingDirectoryLoadsEmpty() {
        let loaded = NoteStore(directory: directory).load()
        XCTAssertEqual(loaded.source, .empty)
        XCTAssertFalse(loaded.recoveredFromCorruption)
    }

    func testOldFileWithoutVersionAndOptionalFieldsLoads() throws {
        let json = """
        {"notes":[{"id":"7B0E6A0C-5E64-4A43-9C55-52B3F1A4E111","text":"legacy",
          "position":{"displayUUID":"X","relativeX":0.5,"relativeY":0.5}}]}
        """
        let file = try NotesMigrator.decode(Data(json.utf8))
        XCTAssertEqual(file.notes.count, 1)
        XCTAssertEqual(file.notes[0].color, .classicYellow)
        XCTAssertEqual(file.notes[0].shape, .square)
        XCTAssertEqual(file.notes[0].fontScale, 1)
        XCTAssertNil(file.notes[0].reminder)
    }

    func testMigrationStepsRunInOrder() throws {
        let json = """
        {"version":1,"notes":[{"id":"7B0E6A0C-5E64-4A43-9C55-52B3F1A4E111","legacyText":"moved",
          "position":{"displayUUID":"X","relativeX":0.5,"relativeY":0.5}}]}
        """
        // Synthetic v1 -> v2 step that renames a field, the way a real future migration would.
        let step = NotesMigration(fromVersion: 1) { object in
            var o = object
            let notes = (o["notes"] as? [[String: Any]] ?? []).map { n -> [String: Any] in
                var n = n
                n["text"] = n.removeValue(forKey: "legacyText")
                return n
            }
            o["notes"] = notes
            return o
        }
        let file = try NotesMigrator.decode(Data(json.utf8), migrations: [step], targetVersion: 2)
        XCTAssertEqual(file.version, 2)
        XCTAssertEqual(file.notes[0].text, "moved")
    }

    func testNewerFileWithUnknownFieldsStillLoads() throws {
        let json = """
        {"version":99,"futureThing":true,"notes":[{"id":"7B0E6A0C-5E64-4A43-9C55-52B3F1A4E111","text":"hi",
          "color":"neonGreen","shape":"star","newField":[1,2],
          "position":{"displayUUID":"X","relativeX":0.5,"relativeY":0.5}}]}
        """
        let file = try NotesMigrator.decode(Data(json.utf8))
        XCTAssertEqual(file.notes[0].text, "hi")
        XCTAssertEqual(file.notes[0].color, .classicYellow, "unknown color falls back")
        XCTAssertEqual(file.notes[0].shape, .square, "unknown shape falls back")
    }

    func testNewerVersionFileIsPreservedBeforeOverwrite() throws {
        let store = NoteStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"version":7,"notes":[{"id":"7B0E6A0C-5E64-4A43-9C55-52B3F1A4E111","text":"from the future","futureField":42,
          "position":{"displayUUID":"X","relativeX":0.5,"relativeY":0.5}}]}
        """
        try Data(json.utf8).write(to: store.fileURL)
        let loaded = store.load()
        XCTAssertEqual(loaded.notes.first?.text, "from the future")
        try store.save(loaded.notes)
        let copy = try String(contentsOf: store.newerVersionCopyURL(version: 7), encoding: .utf8)
        XCTAssertTrue(copy.contains("futureField"), "untouched copy keeps fields this version does not know")
        XCTAssertEqual(NotesMigrator.storedVersion(of: try Data(contentsOf: store.fileURL)), NotesFile.currentVersion)
    }

    private func futureJSON(_ text: String) -> String {
        """
        {"version":7,"notes":[{"id":"7B0E6A0C-5E64-4A43-9C55-52B3F1A4E111","text":"\(text)","futureField":42,
          "position":{"displayUUID":"X","relativeX":0.5,"relativeY":0.5}}]}
        """
    }

    func testNewerFileIsNeverOverwrittenWhenCopyCannotBeMade() throws {
        let store = NoteStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data(futureJSON("keep me").utf8)
        try original.write(to: store.fileURL)
        try original.write(to: store.backupURL)
        // Make every copy location unwritable: the directory itself becomes read-only after setup.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        let loaded = store.load()
        XCTAssertEqual(loaded.notes.first?.text, "keep me")
        XCTAssertEqual(store.writeBlock, .newerVersionNotPreserved(version: 7))
        XCTAssertThrowsError(try store.save(loaded.notes)) { error in
            XCTAssertEqual(error as? NoteStore.StoreError, .writesBlocked(.newerVersionNotPreserved(version: 7)))
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        XCTAssertEqual(try Data(contentsOf: store.backupURL), original)
    }

    func testDirectoryAtCopyPathFallsBackToAnotherName() throws {
        let store = NoteStore(directory: directory)
        try FileManager.default.createDirectory(at: store.newerVersionCopyURL(version: 7), withIntermediateDirectories: true)
        let original = Data(futureJSON("dir in the way").utf8)
        try original.write(to: store.fileURL)
        _ = store.load()
        XCTAssertNil(store.writeBlock)
        let copy = try XCTUnwrap(store.preservedCopyURL)
        XCTAssertNotEqual(copy, store.newerVersionCopyURL(version: 7))
        XCTAssertEqual(try Data(contentsOf: copy), original)
    }

    func testOlderCopyWithSameNameIsKeptAndLoadedStateIsCopiedToo() throws {
        let store = NoteStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let older = Data(futureJSON("older").utf8)
        try older.write(to: store.newerVersionCopyURL(version: 7))
        let current = Data(futureJSON("current").utf8)
        try current.write(to: store.fileURL)
        _ = store.load()
        XCTAssertEqual(try Data(contentsOf: store.newerVersionCopyURL(version: 7)), older, "earlier copy untouched")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.preservedCopyURL)), current)
    }

    func testNewerBackupIsPreservedBeforeItRepairsTheMainFile() throws {
        let store = NoteStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = Data(futureJSON("from backup").utf8)
        try backup.write(to: store.backupURL)
        let loaded = store.load()
        XCTAssertEqual(loaded.source, .backup)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.preservedCopyURL)), backup)
        XCTAssertEqual(NotesMigrator.storedVersion(of: try Data(contentsOf: store.fileURL)), NotesFile.currentVersion)
    }

    func testCurrentVersionFileMakesNoExtraCopy() throws {
        let store = NoteStore(directory: directory)
        try store.save([sampleNote()])
        _ = store.load()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(files, ["notes.json", "notes.json.bak"])
    }

    func testSanitizeRepairsBrokenValues() throws {
        let json = """
        {"version":1,"notes":[{"id":"7B0E6A0C-5E64-4A43-9C55-52B3F1A4E111","text":"a","width":5000,"height":-3,
          "fontScale":100,"rotation":45,"struckLines":[0,0,7,-1],
          "position":{"displayUUID":"X","relativeX":4,"relativeY":-2}}]}
        """
        let n = try NotesMigrator.decode(Data(json.utf8)).notes[0]
        XCTAssertEqual(n.width, 600)
        XCTAssertEqual(n.height, 80)
        XCTAssertEqual(n.fontScale, 6)
        XCTAssertEqual(n.rotation, 2)
        XCTAssertEqual(n.struckLines, [0])
        XCTAssertEqual(n.position.relativeX, 1)
        XCTAssertEqual(n.position.relativeY, 0)
    }
}
