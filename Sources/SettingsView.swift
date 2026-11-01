import Cocoa

private final class ModelCellView: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let modelLabel = NSTextField(labelWithString: "")
    private let activeDot = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        modelLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        modelLabel.textColor = .secondaryLabelColor
        modelLabel.lineBreakMode = .byTruncatingTail
        activeDot.wantsLayer = true
        activeDot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        activeDot.layer?.cornerRadius = 3

        [nameLabel, modelLabel, activeDot].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            activeDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            activeDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            activeDot.widthAnchor.constraint(equalToConstant: 6),
            activeDot.heightAnchor.constraint(equalToConstant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: activeDot.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            modelLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            modelLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            modelLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, model: String, active: Bool) {
        nameLabel.stringValue = name
        modelLabel.stringValue = model.isEmpty ? "未填写模型标识" : model
        activeDot.isHidden = !active
    }
}

final class ModelSettingsWindowController: NSWindowController, NSWindowDelegate,
                                           NSTableViewDataSource, NSTableViewDelegate {
    var onClose: (() -> Void)?

    private let store: ModelStore
    private let tableView = NSTableView()
    private let nameField = NSTextField()
    private let modelField = NSTextField()
    private let baseURLField = NSTextField()
    private let keyField = NSSecureTextField()
    private let activeCheck = NSButton(checkboxWithTitle: "设为当前预测模型", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "选择一套模型配置")
    private let keyHint = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let clearKeyButton = NSButton(title: "清除 Key", target: nil, action: nil)
    private let deleteButton = NSButton(title: "−", target: nil, action: nil)
    private var selectedID: String?
    private var isLoading = false

    init(store: ModelStore = .shared) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "模型配置 · IG 应援"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
        selectCurrentModel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nameField)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        // Left rail
        let rail = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 520))
        rail.autoresizingMask = [.height]
        rail.wantsLayer = true
        rail.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        content.addSubview(rail)

        let railTitle = NSTextField(labelWithString: "预测模型")
        railTitle.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        railTitle.frame = NSRect(x: 16, y: 478, width: 190, height: 20)
        rail.addSubview(railTitle)
        let railSubtitle = NSTextField(labelWithString: "支持多套 API，Key 只存密文")
        railSubtitle.font = NSFont.systemFont(ofSize: 9)
        railSubtitle.textColor = .secondaryLabelColor
        railSubtitle.frame = NSRect(x: 16, y: 458, width: 196, height: 14)
        rail.addSubview(railSubtitle)

        let scroll = NSScrollView(frame: NSRect(x: 10, y: 52, width: 210, height: 392))
        scroll.autoresizingMask = [.height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        tableView.headerView = nil
        tableView.rowHeight = 46
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("model"))
        column.width = 200
        tableView.addTableColumn(column)
        scroll.documentView = tableView
        rail.addSubview(scroll)

        let addButton = NSButton(title: "+", target: self, action: #selector(addModel))
        addButton.bezelStyle = .roundRect
        addButton.frame = NSRect(x: 12, y: 14, width: 34, height: 26)
        rail.addSubview(addButton)
        deleteButton.target = self
        deleteButton.action = #selector(deleteModel)
        deleteButton.bezelStyle = .roundRect
        deleteButton.frame = NSRect(x: 50, y: 14, width: 34, height: 26)
        rail.addSubview(deleteButton)
        let countLabel = NSTextField(labelWithString: "")
        countLabel.tag = 901
        countLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.frame = NSRect(x: 120, y: 18, width: 96, height: 14)
        rail.addSubview(countLabel)

        // Right editor
        let editor = NSView(frame: NSRect(x: 230, y: 0, width: 550, height: 520))
        editor.autoresizingMask = [.width, .height]
        content.addSubview(editor)

        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.frame = NSRect(x: 24, y: 468, width: 500, height: 26)
        editor.addSubview(titleLabel)

        activeCheck.target = self
        activeCheck.action = #selector(toggleActive)
        activeCheck.font = NSFont.systemFont(ofSize: 11)
        activeCheck.frame = NSRect(x: 24, y: 440, width: 220, height: 20)
        editor.addSubview(activeCheck)

        addFieldLabel("显示名称", hint: "面板上展示的模型型号", y: 407, to: editor)
        configureField(nameField, placeholder: "例如 DeepSeek V3.2", y: 379, in: editor)
        addFieldLabel("模型标识", hint: "请求体里的 model，例如 deepseek-chat", y: 347, to: editor)
        configureField(modelField, placeholder: "deepseek-chat", y: 319, in: editor)
        addFieldLabel("Base URL", hint: "OpenAI 兼容接口，通常以 /v1 结尾", y: 287, to: editor)
        configureField(baseURLField, placeholder: "https://api.deepseek.com/v1", y: 259, in: editor)

        let keyLabel = NSTextField(labelWithString: "API Key / Token")
        keyLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        keyLabel.frame = NSRect(x: 24, y: 229, width: 120, height: 15)
        editor.addSubview(keyLabel)
        let keyHintLabel = NSTextField(labelWithString: "留空保留现有 Key；保存时加密")
        keyHintLabel.font = NSFont.systemFont(ofSize: 9)
        keyHintLabel.textColor = .secondaryLabelColor
        keyHintLabel.frame = NSRect(x: 145, y: 229, width: 300, height: 15)
        editor.addSubview(keyHintLabel)

        keyField.placeholderString = "粘贴 API Key"
        keyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        keyField.frame = NSRect(x: 24, y: 199, width: 460, height: 25)
        editor.addSubview(keyField)

        keyHint.font = NSFont.systemFont(ofSize: 9)
        keyHint.textColor = .secondaryLabelColor
        keyHint.frame = NSRect(x: 24, y: 176, width: 460, height: 16)
        editor.addSubview(keyHint)

        clearKeyButton.target = self
        clearKeyButton.action = #selector(clearKey)
        clearKeyButton.bezelStyle = .inline
        clearKeyButton.font = NSFont.systemFont(ofSize: 9)
        clearKeyButton.contentTintColor = .systemRed
        clearKeyButton.frame = NSRect(x: 24, y: 148, width: 90, height: 20)
        editor.addSubview(clearKeyButton)

        let lockNote = NSTextField(labelWithString: "AES-GCM 加密后写入 models.json；主密钥保存在 macOS 钥匙串，配置文件权限 0600。")
        lockNote.font = NSFont.systemFont(ofSize: 9)
        lockNote.textColor = .secondaryLabelColor
        lockNote.frame = NSRect(x: 24, y: 120, width: 490, height: 16)
        editor.addSubview(lockNote)

        let saveButton = NSButton(title: "保存配置", target: self, action: #selector(saveModel))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 24, y: 78, width: 104, height: 28)
        editor.addSubview(saveButton)

        let folderButton = NSButton(title: "打开配置文件夹", target: self, action: #selector(openFolder))
        folderButton.bezelStyle = .rounded
        folderButton.frame = NSRect(x: 136, y: 78, width: 126, height: 28)
        editor.addSubview(folderButton)

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 274, y: 84, width: 250, height: 16)
        editor.addSubview(statusLabel)

        let footnote = NSTextField(labelWithString: "AI 徽章显示「显示名称」；支持同时保存多套配置，预测时使用标记为当前使用的那一套。")
        footnote.font = NSFont.systemFont(ofSize: 9)
        footnote.textColor = .secondaryLabelColor
        footnote.frame = NSRect(x: 24, y: 42, width: 500, height: 16)
        editor.addSubview(footnote)
    }

    private func addFieldLabel(_ title: String, hint: String, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.frame = NSRect(x: 24, y: y, width: 110, height: 15)
        view.addSubview(label)
        let hintLabel = NSTextField(labelWithString: hint)
        hintLabel.font = NSFont.systemFont(ofSize: 9)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = NSRect(x: 145, y: y, width: 380, height: 15)
        view.addSubview(hintLabel)
    }

    private func configureField(_ field: NSTextField, placeholder: String, y: CGFloat, in view: NSView) {
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 12)
        field.frame = NSRect(x: 24, y: y, width: 460, height: 24)
        field.lineBreakMode = .byTruncatingTail
        view.addSubview(field)
    }

    private func selectCurrentModel() {
        let id = store.activeModel?.id ?? store.models.first?.id
        if let id, let index = store.models.firstIndex(where: { $0.id == id }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            selectedID = id
            loadDraft(for: store.models[index])
        } else {
            selectedID = nil
            clearEditor()
        }
        tableView.reloadData()
        updateCount()
        deleteButton.isEnabled = selectedID != nil
    }

    private func updateCount() {
        if let label = window?.contentView?.viewWithTag(901) as? NSTextField {
            label.stringValue = "\(store.models.count) 套"
        }
    }

    private func loadDraft(for config: ModelConfig) {
        isLoading = true
        selectedID = config.id
        titleLabel.stringValue = config.name
        nameField.stringValue = config.name
        modelField.stringValue = config.model
        baseURLField.stringValue = config.baseURL
        keyField.stringValue = ""
        keyField.placeholderString = config.hasKey ? "已保存（留空不修改）" : "粘贴 API Key"
        keyHint.stringValue = config.hasKey
            ? "已加密保存；留空保持不变。"
            : "尚未配置 Key；本地服务可留空。"
        activeCheck.state = store.activeModelID == config.id ? .on : .off
        clearKeyButton.isEnabled = config.hasKey
        statusLabel.stringValue = ""
        isLoading = false
        tableView.reloadData()
        deleteButton.isEnabled = true
    }

    private func clearEditor() {
        titleLabel.stringValue = "选择或添加一套模型配置"
        nameField.stringValue = ""
        modelField.stringValue = ""
        baseURLField.stringValue = ""
        keyField.stringValue = ""
        keyHint.stringValue = ""
        activeCheck.state = .off
        clearKeyButton.isEnabled = false
        statusLabel.stringValue = ""
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.models.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < store.models.count else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ModelCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ModelCellView
            ?? ModelCellView(frame: .zero)
        cell.identifier = identifier
        let config = store.models[row]
        cell.configure(name: config.name,
                       model: config.model,
                       active: config.id == store.activeModelID)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isLoading, tableView.selectedRow >= 0,
              tableView.selectedRow < store.models.count else { return }
        loadDraft(for: store.models[tableView.selectedRow])
    }

    // MARK: - Actions

    @objc private func addModel() {
        let config = store.addModel()
        tableView.reloadData()
        if let index = store.models.firstIndex(where: { $0.id == config.id }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        }
        loadDraft(for: config)
        updateCount()
        window?.makeFirstResponder(nameField)
        statusLabel.stringValue = "已添加"
    }

    @objc private func deleteModel() {
        guard let id = selectedID else { return }
        do {
            try store.delete(id: id)
            selectCurrentModel()
            statusLabel.stringValue = "已删除"
        } catch {
            showError(error)
        }
    }

    @objc private func toggleActive(_ sender: NSButton) {
        guard let id = selectedID else { return }
        if sender.state == .on {
            store.setActive(id)
            statusLabel.stringValue = "已设为当前使用"
        } else {
            // An active model is required; clicking off simply restores it.
            sender.state = .on
        }
        tableView.reloadData()
    }

    @objc private func saveModel() {
        guard let id = selectedID else { return }
        do {
            try store.update(id: id,
                             name: nameField.stringValue,
                             model: modelField.stringValue,
                             baseURL: baseURLField.stringValue,
                             keyDraft: keyField.stringValue.isEmpty ? nil : keyField.stringValue)
            keyField.stringValue = ""
            if let config = store.models.first(where: { $0.id == id }) {
                loadDraft(for: config)
            }
            tableView.reloadData()
            updateCount()
            statusLabel.stringValue = "已保存"
        } catch {
            showError(error)
        }
    }

    @objc private func clearKey() {
        guard let id = selectedID,
              let config = store.models.first(where: { $0.id == id }) else { return }
        do {
            try store.update(id: id,
                             name: config.name,
                             model: config.model,
                             baseURL: config.baseURL,
                             keyDraft: "")
            loadDraft(for: store.models.first(where: { $0.id == id }) ?? config)
            tableView.reloadData()
            statusLabel.stringValue = "Key 已清除"
        } catch {
            showError(error)
        }
    }

    @objc private func openFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.modelsURL])
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
