// Licensed under GPL-3.0. See LICENSE.
//
//  swiftc Nook/Managers/NotesManager/NoteStore.swift scripts/tests/NoteStoreCheck.swift -o /tmp/ns && /tmp/ns
//
//  Notes: add, edit, save to disk, reload, a corrupt file moved aside (not overwritten), delete,
//  and the orphan purge.

import Foundation

@main
@MainActor
struct NoteStoreCheck {
    static func main() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notes-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let space = UUID(), gone = UUID()

        let store = NoteStore(directory: dir)
        let note = store.add(in: space)
        store.update(note.id, title: "Title", body: "Body text")
        store.writeNow()

        // Reload from disk.
        let again = NoteStore(directory: dir)
        precondition(again.notes(in: space).count == 1)
        precondition(again.note(note.id)?.title == "Title" && again.note(note.id)?.body == "Body text")
        precondition(again.note(note.id)?.displayTitle == "Title")
        let blank = again.add(in: space)
        precondition(again.note(blank.id)?.displayTitle == "Untitled Note")
        again.update(blank.id, body: "first line\nsecond")
        precondition(again.note(blank.id)?.displayTitle == "first line")

        // Delete closes it wherever it is open.
        let window = UUID()
        again.openNote[window] = blank.id
        again.delete(blank.id)
        precondition(again.note(blank.id) == nil && again.openNote[window] == nil)

        // A file that does not decode is kept aside, never overwritten.
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("notes-bad-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bad) }
        try? Data("not json".utf8).write(to: bad.appendingPathComponent("notes.json"))
        let recovered = NoteStore(directory: bad)
        precondition(recovered.notes.isEmpty)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: bad.path)) ?? []
        precondition(names.contains { $0.hasPrefix("notes-unreadable-") }, "the bad file is kept")

        // Orphans: only notes of missing spaces that are old; never when the space list is empty.
        let old = again.add(in: gone)
        let fresh = again.add(in: gone)
        let later = Date().addingTimeInterval(40 * 86_400)
        again.purgeOrphans(validSpaceIDs: [], now: later)
        precondition(again.note(old.id) != nil, "an empty space list deletes nothing")
        again.purgeOrphans(validSpaceIDs: [space], now: Date())
        precondition(again.note(old.id) != nil && again.note(fresh.id) != nil, "recent orphans stay")
        again.purgeOrphans(validSpaceIDs: [space], now: later)
        precondition(again.note(old.id) == nil && again.note(fresh.id) == nil, "old orphans go")
        precondition(again.note(note.id) != nil, "notes of a live space stay")
        print("NoteStoreCheck passed")
    }
}
