import AppKit

/// Text view that saves on ⌘↩ and dismisses on Escape.
final class NoteTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Quick notes: jot something down, save it, copy it back later.
final class NotesPaneView: NSView, NSTextViewDelegate {
    var onDismiss: (() -> Void)?

    private static let draftKey = "NoteDraft"

    private let isCompact: Bool
    private let editor = NoteTextView()
    private let editorScroll = NSScrollView()
    private let placeholder = Style.label("Type a note — ⌘↩ saves", size: 12, color: nil)
    private let statusLabel = Style.label("", size: 10, color: nil)
    private lazy var saveButton = Style.pushButton("Save", prominent: true, target: self, action: #selector(handleSave))
    private lazy var copyButton = Style.pushButton("Copy", prominent: false, target: self, action: #selector(handleCopy))
    private lazy var newButton = Style.pushButton("New", prominent: false, target: self, action: #selector(handleNew))
    private let listStack = NSStackView()
    private var editingID: UUID?
    private var observer: UUID?

    init(isCompact: Bool = false) {
        self.isCompact = isCompact
        super.init(frame: .zero)
        configure()
        observer = NotesStore.shared.addObserver { [weak self] in self?.reloadList() }
        reloadList()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer { NotesStore.shared.removeObserver(observer) }
    }

    private func configure() {
        placeholder.textColor = Style.tertiaryText
        statusLabel.textColor = Style.tertiaryText

        editor.delegate = self
        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = .systemFont(ofSize: Style.scaled(12))
        editor.textColor = Style.primaryText
        editor.insertionPointColor = Style.primaryText
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.onSubmit = { [weak self] in self?.handleSave() }
        editor.onCancel = { [weak self] in self?.onDismiss?() }
        editor.string = UserDefaults.standard.string(forKey: Self.draftKey) ?? ""

        editorScroll.documentView = editor
        editorScroll.hasVerticalScroller = true
        editorScroll.drawsBackground = false
        editorScroll.wantsLayer = true
        editorScroll.layer?.cornerRadius = 8
        editorScroll.layer?.backgroundColor = Style.controlFill.cgColor
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.addSubview(placeholder)

        let buttons = NSStackView(views: isCompact ? [saveButton, copyButton] : [saveButton, copyButton, newButton, statusLabel])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 6

        let editorColumn = NSStackView(views: [editorScroll, buttons])
        editorColumn.orientation = .vertical
        editorColumn.alignment = .leading
        editorColumn.spacing = 6
        editorColumn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editorColumn)

        var constraints = [
            placeholder.leadingAnchor.constraint(equalTo: editorScroll.leadingAnchor, constant: 11),
            placeholder.topAnchor.constraint(equalTo: editorScroll.topAnchor, constant: 6),
            editorScroll.leadingAnchor.constraint(equalTo: editorColumn.leadingAnchor),
            editorScroll.trailingAnchor.constraint(equalTo: editorColumn.trailingAnchor),
            editorColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            editorColumn.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            editorColumn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ]

        if isCompact {
            constraints.append(editorColumn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10))
        } else {
            listStack.orientation = .vertical
            listStack.alignment = .leading
            listStack.spacing = 2

            let document = FlippedView()
            document.translatesAutoresizingMaskIntoConstraints = false
            listStack.translatesAutoresizingMaskIntoConstraints = false
            document.addSubview(listStack)

            let listScroll = NSScrollView()
            listScroll.documentView = document
            listScroll.hasVerticalScroller = true
            listScroll.drawsBackground = false
            listScroll.translatesAutoresizingMaskIntoConstraints = false
            addSubview(listScroll)

            constraints += [
                editorColumn.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.55),
                listScroll.leadingAnchor.constraint(equalTo: editorColumn.trailingAnchor, constant: 12),
                listScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                listScroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                listScroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
                document.leadingAnchor.constraint(equalTo: listScroll.contentView.leadingAnchor),
                document.trailingAnchor.constraint(equalTo: listScroll.contentView.trailingAnchor),
                document.topAnchor.constraint(equalTo: listScroll.contentView.topAnchor),
                listStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                listStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
                listStack.topAnchor.constraint(equalTo: document.topAnchor),
                listStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
            ]
        }

        NSLayoutConstraint.activate(constraints)
        updatePlaceholder()
    }

    /// Puts the cursor in the editor, for the keyboard shortcut.
    func focus() {
        window?.makeFirstResponder(editor)
    }

    // MARK: - List

    private func reloadList() {
        let notes = NotesStore.shared.notes
        statusLabel.stringValue = notes.isEmpty ? "" : "\(notes.count) saved"

        guard isCompact == false else { return }
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard notes.isEmpty == false else {
            let empty = Style.label("Saved notes appear here", size: 11, color: Style.tertiaryText)
            listStack.addArrangedSubview(empty)
            return
        }

        for note in notes.prefix(40) {
            let row = NoteRowView(note: note, isSelected: note.id == editingID)
            row.onOpen = { [weak self] in self?.open(note) }
            row.onCopy = { NotesStore.shared.copy(note) }
            row.onDelete = { [weak self] in
                if self?.editingID == note.id { self?.handleNew() }
                NotesStore.shared.delete(note.id)
            }
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    private func open(_ note: Note) {
        editingID = note.id
        editor.string = note.text
        updatePlaceholder()
        reloadList()
        focus()
    }

    // MARK: - Editing

    func textDidChange(_ notification: Notification) {
        updatePlaceholder()
        if let editingID {
            // An existing note saves as you type.
            NotesStore.shared.update(editingID, text: editor.string)
        } else {
            UserDefaults.standard.set(editor.string, forKey: Self.draftKey)
        }
    }

    private func updatePlaceholder() {
        placeholder.isHidden = editor.string.isEmpty == false
    }

    @objc private func handleSave() {
        if editingID != nil {
            handleNew()
            return
        }
        guard NotesStore.shared.add(editor.string) != nil else { return }
        editor.string = ""
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
        updatePlaceholder()
        flash("Saved")
    }

    @objc private func handleCopy() {
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ClipboardHistory.shared.ignoreNextChange()
        flash("Copied")
    }

    @objc private func handleNew() {
        editingID = nil
        editor.string = UserDefaults.standard.string(forKey: Self.draftKey) ?? ""
        updatePlaceholder()
        reloadList()
    }

    private func flash(_ message: String) {
        statusLabel.stringValue = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.reloadList()
        }
    }
}

/// One saved note in the list.
final class NoteRowView: NSView {
    var onOpen: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    init(note: Note, isSelected: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = isSelected ? Style.controlFill.cgColor : NSColor.clear.cgColor

        let title = Style.label(note.title, size: 11, weight: .medium)
        title.setContentCompressionResistancePriority(.init(200), for: .horizontal)
        let time = Style.label(RelativeTime.string(for: note.updated), size: 9, color: Style.tertiaryText)
        time.widthAnchor.constraint(greaterThanOrEqualToConstant: ceil(time.intrinsicContentSize.width) + 2).isActive = true
        let text = NSStackView(views: [title, time])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0

        let copy = Style.symbolButton("doc.on.doc", pointSize: 10, target: self, action: #selector(handleCopy))
        copy.toolTip = "Copy"
        let delete = Style.symbolButton("xmark", pointSize: 9, target: self, action: #selector(handleDelete))
        delete.toolTip = "Delete"
        [copy, delete].forEach { $0.contentTintColor = Style.tertiaryText }

        text.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [text, copy, delete])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onOpen?() }
    @objc private func handleCopy() { onCopy?() }
    @objc private func handleDelete() { onDelete?() }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func string(for date: Date) -> String {
        abs(date.timeIntervalSinceNow) < 45 ? "just now" : formatter.localizedString(for: date, relativeTo: Date())
    }
}
