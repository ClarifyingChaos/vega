// Licensed under GPL-3.0. See LICENSE.
//
//  NoteStore.swift
//  Nook
//
//  FORK: Arc-style notes. Plain text notes, one list per space, saved as JSON beside the tab
//  files. Kept out of the tab tree on purpose: a new item kind there would touch the shared
//  model and its sync code.
//

import Foundation
import Observation
import OSLog

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var spaceID: UUID
    var title = ""
    var body = ""
    var createdAt = Date()
    var modifiedAt = Date()

    /// The title, or the first line of the body, or a placeholder.
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        let first = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.isEmpty ? "Untitled Note" : first
    }
}

@MainActor
@Observable
final class NoteStore {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    /// The note each window is showing, by window ID. Not saved: a relaunch starts on a page.
    var openNote: [UUID: UUID] = [:]

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.nook.browser", category: "Notes")

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.gstudios.nook").appendingPathComponent("Notes")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("notes.json")
        if let data = try? Data(contentsOf: url) {
            do { notes = try JSONDecoder().decode([Note].self, from: data) }
            // A file that does not decode is kept aside, never overwritten, so nothing is lost.
            catch {
                log.error("notes.json unreadable: \(error.localizedDescription)")
                try? FileManager.default.moveItem(at: url, to: base.appendingPathComponent("notes-unreadable-\(Int(Date().timeIntervalSince1970)).json"))
            }
        }
    }

    func notes(in spaceID: UUID?) -> [Note] {
        notes.filter { $0.spaceID == spaceID }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func add(in spaceID: UUID) -> Note {
        let note = Note(spaceID: spaceID)
        notes.append(note)
        save()
        return note
    }

    func update(_ id: UUID, title: String? = nil, body: String? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let title, title != notes[index].title { notes[index].title = title; notes[index].modifiedAt = Date() }
        if let body, body != notes[index].body { notes[index].body = body; notes[index].modifiedAt = Date() }
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        for (window, open) in openNote where open == id { openNote[window] = nil }
        save()
    }

    /// Writes after a short pause, so typing is not a write per key.
    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    func writeNow() {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("notes save failed: \(error.localizedDescription)")
        }
    }
}
