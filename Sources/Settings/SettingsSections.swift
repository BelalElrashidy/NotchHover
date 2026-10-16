import AppKit

/// A list of name/value rows with add and remove, drawn from the theme.
final class KeyValueSection: NSView {
    /// Called whenever a row is added, removed, or edited — there is no Save button.
    var onChange: (() -> Void)?
    var entries: [(key: String, value: String)] = []
    var rowCount: Int { rowsStack.arrangedSubviews.count }

    private let rowsStack = NSStackView()
    private let keyPlaceholder: String
    private let valuePlaceholder: String

    init(title: String, hint: String, keyPlaceholder: String, valuePlaceholder: String) {
        self.keyPlaceholder = keyPlaceholder
        self.valuePlaceholder = valuePlaceholder
        super.init(frame: .zero)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6

        let stack = NSStackView(views: [
            SettingsStyle.heading(title),
            SettingsStyle.label(hint, size: 11, secondary: true),
            rowsStack,
            SettingsStyle.capsule("Add", target: self, action: #selector(handleAdd))
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadRows() {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, entry) in entries.enumerated() {
            let keyField = SettingsStyle.field(entry.key, placeholder: keyPlaceholder)
            keyField.tag = index
            keyField.target = self
            keyField.action = #selector(handleFieldCommitted)

            let valueField = SettingsStyle.field(entry.value, placeholder: valuePlaceholder)
            valueField.tag = index
            valueField.target = self
            valueField.action = #selector(handleFieldCommitted)

            let remove = SettingsStyle.capsule("−", target: self, action: #selector(handleRemove(_:)))
            remove.tag = index

            let row = NSStackView(views: [keyField, valueField, remove])
            row.orientation = .horizontal
            row.spacing = 8
            keyField.widthAnchor.constraint(equalToConstant: 130).isActive = true
            valueField.widthAnchor.constraint(equalToConstant: 300).isActive = true
            remove.widthAnchor.constraint(equalToConstant: 30).isActive = true
            rowsStack.addArrangedSubview(row)
        }
    }

    /// Fields have no live binding — their values are read here, in one pass, so that
    /// editing can never mutate the model while the rows are being rebuilt.
    func commitEdits() {
        var collected = entries
        for (index, row) in rowsStack.arrangedSubviews.enumerated() {
            guard let stack = row as? NSStackView,
                  let keyField = stack.arrangedSubviews.first as? NSTextField,
                  stack.arrangedSubviews.count > 1,
                  let valueField = stack.arrangedSubviews[1] as? NSTextField,
                  collected.indices.contains(index) else { continue }
            collected[index] = (keyField.stringValue, valueField.stringValue)
        }
        entries = collected
    }

    func addRow() {
        commitEdits()
        entries.append(("", ""))
        reloadRows()
        onChange?()
    }

    func removeRow(at index: Int) {
        commitEdits()
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        reloadRows()
        onChange?()
    }

    @objc private func handleAdd() {
        addRow()
    }

    @objc private func handleFieldCommitted() {
        commitEdits()
        onChange?()
    }

    @objc private func handleRemove(_ sender: NSButton) {
        let index = sender.tag
        // Let the click finish before the button is torn out from under it.
        DispatchQueue.main.async { [weak self] in
            self?.removeRow(at: index)
        }
    }
}

/// A list of single-field rows.
final class SingleFieldSection: NSView {
    var onChange: (() -> Void)?
    var entries: [String] = []
    var rowCount: Int { rowsStack.arrangedSubviews.count }

    private let rowsStack = NSStackView()
    private let placeholder: String

    init(title: String, hint: String, placeholder: String) {
        self.placeholder = placeholder
        super.init(frame: .zero)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6

        let stack = NSStackView(views: [
            SettingsStyle.heading(title),
            SettingsStyle.label(hint, size: 11, secondary: true),
            rowsStack,
            SettingsStyle.capsule("Add", target: self, action: #selector(handleAdd))
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadRows() {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, entry) in entries.enumerated() {
            let field = SettingsStyle.field(entry, placeholder: placeholder)
            field.tag = index
            field.target = self
            field.action = #selector(handleFieldCommitted)

            let remove = SettingsStyle.capsule("−", target: self, action: #selector(handleRemove(_:)))
            remove.tag = index

            let row = NSStackView(views: [field, remove])
            row.orientation = .horizontal
            row.spacing = 8
            field.widthAnchor.constraint(equalToConstant: 300).isActive = true
            remove.widthAnchor.constraint(equalToConstant: 30).isActive = true
            rowsStack.addArrangedSubview(row)
        }
    }

    func commitEdits() {
        var collected = entries
        for (index, row) in rowsStack.arrangedSubviews.enumerated() {
            guard let stack = row as? NSStackView,
                  let field = stack.arrangedSubviews.first as? NSTextField,
                  collected.indices.contains(index) else { continue }
            collected[index] = field.stringValue
        }
        entries = collected
    }

    func addRow() {
        commitEdits()
        entries.append("")
        reloadRows()
        onChange?()
    }

    func removeRow(at index: Int) {
        commitEdits()
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        reloadRows()
        onChange?()
    }

    @objc private func handleAdd() {
        addRow()
    }

    @objc private func handleFieldCommitted() {
        commitEdits()
        onChange?()
    }

    @objc private func handleRemove(_ sender: NSButton) {
        let index = sender.tag
        DispatchQueue.main.async { [weak self] in
            self?.removeRow(at: index)
        }
    }
}

/// Picks which apps appear in the launcher row.
final class AppListSection: NSView {
    var onChange: (() -> Void)?

    private let rowsStack = NSStackView()
    private var identifiers: [String] = []

    init() {
        super.init(frame: .zero)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6

        let stack = NSStackView(views: [
            SettingsStyle.heading("Apps in the launcher"),
            rowsStack,
            SettingsStyle.capsule("Add app…", target: self, action: #selector(handleAdd))
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        identifiers = UserDefaults.standard.stringArray(forKey: AppShortcutStore.defaultsKey)
            ?? AppShortcutStore.shortcuts().map(\.bundleIdentifier)
        reloadRows()
    }

    private func reloadRows() {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, identifier) in identifiers.enumerated() {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            let iconView = NSImageView()
            if let url {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 18, height: 18)
                iconView.image = icon
            }

            let name = SettingsStyle.label(url.map {
                FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
            } ?? "\(identifier) (not installed)")

            let remove = SettingsStyle.capsule("−", target: self, action: #selector(handleRemove(_:)))
            remove.tag = index

            let row = NSStackView(views: [iconView, name, remove])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
            name.widthAnchor.constraint(equalToConstant: 240).isActive = true
            remove.widthAnchor.constraint(equalToConstant: 30).isActive = true
            rowsStack.addArrangedSubview(row)
        }
    }

    private func save() {
        UserDefaults.standard.set(identifiers, forKey: AppShortcutStore.defaultsKey)
        onChange?()
    }

    @objc private func handleAdd() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              identifiers.contains(identifier) == false else { return }

        identifiers.append(identifier)
        reloadRows()
        save()
    }

    @objc private func handleRemove(_ sender: NSButton) {
        let index = sender.tag
        DispatchQueue.main.async { [weak self] in
            guard let self, self.identifiers.indices.contains(index) else { return }
            self.identifiers.remove(at: index)
            self.reloadRows()
            self.save()
        }
    }
}
