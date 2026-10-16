import AppKit

struct Note: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    let created: Date
    var updated: Date
    var isPinned: Bool

    /// First line, for lists.
    var title: String {
        let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        return first.map(String.init) ?? "Empty note"
    }
}

/// Quick notes, saved to disk as you type.
final class NotesStore {
    static let shared = NotesStore()

    private static let fileName = "notes.json"
    private static let maximumNotes = 500

    private(set) var notes: [Note] = []
    private var observers: [UUID: () -> Void] = [:]
    private var pendingSave: DispatchWorkItem?

    /// Previews and tests fill the store without touching the user's real notes.
    var persists = true

    private init() {
        notes = LocalStore.load([Note].self, from: Self.fileName) ?? []
        sort()
    }

    /// Used by previews to show the widget with sample content.
    func loadSample(_ sample: [Note]) {
        persists = false
        notes = sample
        observers.values.forEach { $0() }
    }

    @discardableResult
    func addObserver(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    @discardableResult
    func add(_ text: String) -> Note? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let now = Date()
        let note = Note(id: UUID(), text: trimmed, created: now, updated: now, isPinned: false)
        notes.insert(note, at: 0)
        if notes.count > Self.maximumNotes {
            // Unpinned notes go first when the cap is reached.
            if let index = notes.lastIndex(where: { $0.isPinned == false }) {
                notes.remove(at: index)
            }
        }
        changed()
        return note
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        notes[index].updated = Date()
        changed(debounce: true)
    }

    func togglePin(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        changed()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        changed()
    }

    func copy(_ note: Note) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.text, forType: .string)
        // Copying our own note must not create a duplicate clipboard entry.
        ClipboardHistory.shared.ignoreNextChange()
    }

    private func sort() {
        notes.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updated > $1.updated
        }
    }

    /// Typing saves after a short pause rather than on every keystroke.
    private func changed(debounce: Bool = false) {
        if debounce == false { sort() }
        observers.values.forEach { $0() }
        guard persists else { return }

        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            LocalStore.save(self.notes, to: Self.fileName)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (debounce ? 0.6 : 0), execute: work)
    }
}
