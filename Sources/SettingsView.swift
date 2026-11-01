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

    func configure(name: String, model: String, format: ModelAPIFormat, active: Bool) {
        nameLabel.stringValue = name
        let modelText = model.isEmpty ? "未填写模型标识" : model
        modelLabel.stringValue = "\(modelText)  ·  \(format.shortTitle)"
        activeDot.isHidden = !active
    }
}

final class ModelSettingsWindowController: NSWindowController, NSWindowDelegate,
                                           NSTableViewDataSource, NSTableViewDelegate {
    var onClose: (() -> Void)?

    private let store: ModelStore
    private let tableView = NSTableView()
    private let nameField = NSTextField()
    private let modelCombo = NSComboBox()
    private let baseURLField = NSTextField()
    // Deliberately a plain NSTextField: NSSecureTextField triggers the system
    // Passwords AutoFill menu, which can ask for the macOS login password.
    private let keyField = NSTextField()
    private let formatPopUp = NSPopUpButton()
    private let activeCheck = NSButton(checkboxWithTitle: "设为当前预测模型", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "选择一套模型配置")
    private let statusLabel = NSTextField(labelWithString: "")
    private let clearKeyButton = NSButton(title: "清除 Key", target: nil, action: nil)
    private let fetchButton = NSButton(title: "获取模型", target: nil, action: nil)
    private let testButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let deleteButton = NSButton(title: "−", target: nil, action: nil)
    private var selectedID: String?
    private var isLoading = false
    private var fetchInFlight = false
    private var testInFlight = false

    init(store: ModelStore = .shared) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "模型配置 · IG 应援"
        window.isReleasedWhenClosed = false
        // Keep the configuration window alive while the user switches to a
        // browser to fetch a token. Only the title-bar close button should
        // dismiss it; deactivation must not hide or close it.
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

        let formatLabel = NSTextField(labelWithString: "API 格式")
        formatLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        formatLabel.frame = NSRect(x: 250, y: 441, width: 60, height: 15)
        editor.addSubview(formatLabel)

        formatPopUp.frame = NSRect(x: 312, y: 436, width: 190, height: 24)
        formatPopUp.font = NSFont.systemFont(ofSize: 11)
        formatPopUp.controlSize = .small
        formatPopUp.addItems(withTitles: ModelAPIFormat.allCases.map(\.title))
        formatPopUp.target = self
        formatPopUp.action = #selector(formatChanged)
        formatPopUp.toolTip = "OpenAI 兼容接口使用 /chat/completions；Anthropic 使用 /v1/messages"
        editor.addSubview(formatPopUp)

        addFieldLabel("显示名称", hint: "面板上展示的模型型号", y: 407, to: editor)
        configureField(nameField, placeholder: "例如 DeepSeek V3.2", y: 379, in: editor)
        nameField.toolTip = "面板上展示的模型型号"

        addFieldLabel("模型标识", hint: "可下拉选择，或点「获取模型」请求 /models", y: 347, to: editor)
        modelCombo.frame = NSRect(x: 24, y: 319, width: 330, height: 25)
        modelCombo.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        modelCombo.placeholderString = "deepseek-chat"
        modelCombo.isEditable = true
        modelCombo.completes = true
        modelCombo.numberOfVisibleItems = 12
        modelCombo.usesDataSource = false
        modelCombo.toolTip = "可手动输入任意模型 ID；点右侧按钮从当前 Base URL 获取列表"
        editor.addSubview(modelCombo)

        fetchButton.target = self
        fetchButton.action = #selector(fetchModels)
        fetchButton.bezelStyle = .rounded
        fetchButton.controlSize = .small
        fetchButton.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        fetchButton.frame = NSRect(x: 362, y: 317, width: 122, height: 27)
        fetchButton.toolTip = "GET {Base URL}/models；需要时使用当前 Key"
        editor.addSubview(fetchButton)

        addFieldLabel("Base URL", hint: "OpenAI 兼容或 Anthropic 的 API 根地址，通常以 /v1 结尾", y: 287, to: editor)
        configureField(baseURLField, placeholder: ModelAPIFormat.openai.defaultBaseURL, y: 259, in: editor)

        let keyLabel = NSTextField(labelWithString: "API Key / Token")
        keyLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        keyLabel.frame = NSRect(x: 24, y: 229, width: 120, height: 15)
        keyLabel.toolTip = "留空保留现有 Key；远程服务需填写，本地可留空；不使用系统钥匙串。"
        editor.addSubview(keyLabel)

        keyField.placeholderString = "粘贴 API Key"
        keyField.isAutomaticTextCompletionEnabled = false
        keyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        keyField.frame = NSRect(x: 24, y: 199, width: 460, height: 25)
        keyField.toolTip = "留空保留现有 Key；远程服务需填写，本地可留空；不使用系统钥匙串。"
        editor.addSubview(keyField)

        clearKeyButton.target = self
        clearKeyButton.action = #selector(clearKey)
        clearKeyButton.bezelStyle = .inline
        clearKeyButton.font = NSFont.systemFont(ofSize: 9)
        clearKeyButton.contentTintColor = .systemRed
        clearKeyButton.frame = NSRect(x: 24, y: 148, width: 90, height: 20)
        editor.addSubview(clearKeyButton)

        let saveButton = NSButton(title: "保存配置", target: self, action: #selector(saveModel))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 24, y: 78, width: 104, height: 28)
        editor.addSubview(saveButton)

        let folderButton = NSButton(title: "打开配置文件夹", target: self, action: #selector(openFolder))
        folderButton.bezelStyle = .rounded
        folderButton.frame = NSRect(x: 136, y: 78, width: 126, height: 28)
        editor.addSubview(folderButton)

        testButton.target = self
        testButton.action = #selector(testConnection)
        testButton.bezelStyle = .rounded
        testButton.controlSize = .regular
        testButton.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        testButton.frame = NSRect(x: 270, y: 78, width: 100, height: 28)
        testButton.toolTip = "向真实消息接口发送一条最小请求（最多 1 个输出 Token），验证是否真正连上大模型"
        editor.addSubview(testButton)

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.frame = NSRect(x: 24, y: 54, width: 500, height: 16)
        editor.addSubview(statusLabel)
    }

    private func addFieldLabel(_ title: String, hint: String, y: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.frame = NSRect(x: 24, y: y, width: 110, height: 15)
        // Keep the editor quiet: hints live in tooltips instead of a second
        // permanent line of small text.
        label.toolTip = hint
        view.addSubview(label)
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

    private var currentFormat: ModelAPIFormat {
        let index = formatPopUp.indexOfSelectedItem
        let formats = ModelAPIFormat.allCases
        return (0..<formats.count).contains(index) ? formats[index] : .openai
    }

    private func updateFormatPlaceholders() {
        let format = currentFormat
        baseURLField.placeholderString = format.defaultBaseURL
        modelCombo.placeholderString = format.defaultModel
    }

    private func setModelChoices(_ ids: [String], preserving current: String) {
        var seen = Set<String>()
        var choices = ids.filter { id in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seen.insert(trimmed).inserted
        }
        if !current.isEmpty && !choices.contains(current) {
            choices.insert(current, at: 0)
        }
        modelCombo.removeAllItems()
        modelCombo.addItems(withObjectValues: choices)
        modelCombo.stringValue = current
    }

    private func loadDraft(for config: ModelConfig) {
        isLoading = true
        selectedID = config.id
        titleLabel.stringValue = config.name
        nameField.stringValue = config.name
        if let index = ModelAPIFormat.allCases.firstIndex(of: config.apiFormat) {
            formatPopUp.selectItem(at: index)
        } else {
            formatPopUp.selectItem(at: 0)
        }
        updateFormatPlaceholders()
        setModelChoices(ModelCatalogClient.suggestions(for: config), preserving: config.model)
        baseURLField.stringValue = config.baseURL
        keyField.stringValue = ""
        keyField.placeholderString = config.hasKey ? "已保存（留空不修改）" : "粘贴 API Key"
        keyField.toolTip = config.hasKey
            ? "已加密保存；留空保持不变。留空也会保留现有 Key；不使用系统钥匙串。"
            : "尚未配置 Key；本地服务可留空。远程服务需填写；不使用系统钥匙串。"
        activeCheck.state = store.activeModelID == config.id ? .on : .off
        clearKeyButton.isEnabled = config.hasKey
        statusLabel.stringValue = ""
        statusLabel.toolTip = nil
        fetchButton.title = "获取模型"
        fetchButton.isEnabled = true
        fetchInFlight = false
        testButton.title = "测试连接"
        testButton.isEnabled = true
        testInFlight = false
        isLoading = false
        tableView.reloadData()
        deleteButton.isEnabled = true
    }

    private func clearEditor() {
        isLoading = true
        titleLabel.stringValue = "选择或添加一套模型配置"
        nameField.stringValue = ""
        formatPopUp.selectItem(at: 0)
        updateFormatPlaceholders()
        setModelChoices(ModelCatalogClient.suggestions(for: ModelConfig(
            id: "", name: "", model: "", baseURL: ModelAPIFormat.openai.defaultBaseURL
        )), preserving: "")
        baseURLField.stringValue = ""
        keyField.stringValue = ""
        keyField.toolTip = "留空保留现有 Key；远程服务需填写，本地可留空；不使用系统钥匙串。"
        activeCheck.state = .off
        clearKeyButton.isEnabled = false
        statusLabel.stringValue = ""
        statusLabel.toolTip = nil
        fetchButton.title = "获取模型"
        fetchButton.isEnabled = false
        testButton.title = "测试连接"
        testButton.isEnabled = false
        testInFlight = false
        isLoading = false
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
                       format: config.apiFormat,
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

    @objc private func formatChanged(_ sender: NSButton) {
        guard !isLoading else { return }
        updateFormatPlaceholders()
        let previousDefaults = ModelAPIFormat.allCases.map(\.defaultBaseURL)
        let currentBase = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentBase.isEmpty || previousDefaults.contains(currentBase) {
            baseURLField.stringValue = currentFormat.defaultBaseURL
        }
        if modelCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modelCombo.stringValue = currentFormat.defaultModel
        }
        var draft = selectedConfig ?? ModelConfig(
            id: "", name: nameField.stringValue,
            model: modelCombo.stringValue, baseURL: baseURLField.stringValue
        )
        draft.baseURL = baseURLField.stringValue
        draft.apiFormat = currentFormat
        setModelChoices(ModelCatalogClient.suggestions(for: draft),
                        preserving: modelCombo.stringValue)
        statusLabel.stringValue = "已切换 API 格式"
        statusLabel.toolTip = nil
    }

    @objc private func saveModel() {
        guard let id = selectedID else { return }
        do {
            try store.update(id: id,
                             name: nameField.stringValue,
                             model: modelCombo.stringValue,
                             baseURL: baseURLField.stringValue,
                             apiFormat: currentFormat,
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
                             apiFormat: config.apiFormat,
                             keyDraft: "")
            loadDraft(for: store.models.first(where: { $0.id == id }) ?? config)
            tableView.reloadData()
            statusLabel.stringValue = "Key 已清除"
        } catch {
            showError(error)
        }
    }

    @objc private func fetchModels() {
        guard !fetchInFlight, let id = selectedID,
              let config = store.models.first(where: { $0.id == id }) else { return }
        let base = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            statusLabel.stringValue = "请先填写 Base URL"
            statusLabel.toolTip = nil
            return
        }

        var draft = config
        draft.baseURL = base
        draft.apiFormat = currentFormat
        draft.model = modelCombo.stringValue

        var apiKey: String?
        do {
            apiKey = try resolvedAPIKey(for: config)
        } catch {
            showError(error, title: "读取加密 Key 失败")
            return
        }

        // Do not send an unauthenticated /models request to a remote
        // provider: DeepSeek and most hosted APIs answer with a confusing
        // "missing key" error. Keep the built-in suggestions usable instead.
        if apiKey == nil && !Self.isLocalEndpoint(base) {
            let fallback = ModelCatalogClient.suggestions(for: draft)
            setModelChoices(fallback, preserving: modelCombo.stringValue)
            statusLabel.stringValue = "未配置 Key · 已显示内置模型"
            statusLabel.toolTip = "DeepSeek 等远程服务的 /models 需要 API Key；填写后再点「获取模型」。"
            showAlert(title: "需要 API Key",
                      message: "远程服务的 /models 需要鉴权。请先在上方填写 API Key；本地服务可以留空。")
            return
        }

        fetchInFlight = true
        fetchButton.isEnabled = false
        fetchButton.title = "获取中…"
        statusLabel.stringValue = "正在请求 /models…"
        statusLabel.toolTip = nil

        ModelCatalogClient.fetch(model: draft, apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            self.fetchInFlight = false
            self.fetchButton.title = "获取模型"
            self.fetchButton.isEnabled = true
            guard self.selectedID == id else { return }
            switch result {
            case .success(let models):
                let ids = models.map(\.id)
                self.setModelChoices(ids, preserving: self.modelCombo.stringValue)
                self.statusLabel.stringValue = "已获取 \(models.count) 个模型"
                self.statusLabel.toolTip = ids.prefix(12).joined(separator: "\n")
            case .failure(let error):
                self.statusLabel.stringValue = "获取失败"
                self.statusLabel.toolTip = error.localizedDescription
                self.showError(error, title: "获取模型列表失败")
            }
        }
    }

    @objc private func testConnection() {
        guard !testInFlight, !fetchInFlight, let id = selectedID,
              let config = store.models.first(where: { $0.id == id }) else { return }
        let base = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            statusLabel.stringValue = "请先填写 Base URL"
            statusLabel.toolTip = nil
            return
        }

        var draft = config
        draft.baseURL = base
        draft.apiFormat = currentFormat
        draft.model = modelCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.model.isEmpty else {
            statusLabel.stringValue = "请先填写模型标识"
            statusLabel.toolTip = nil
            return
        }

        var apiKey: String?
        do {
            apiKey = try resolvedAPIKey(for: config)
        } catch {
            showError(error, title: "读取加密 Key 失败")
            return
        }

        if apiKey == nil && !Self.isLocalEndpoint(base) {
            statusLabel.stringValue = "未配置 Key · 无法发送真实请求"
            statusLabel.toolTip = "真实请求需要鉴权；请填写 API Key 后再测试。"
            showAlert(title: "需要 API Key",
                      message: "真实请求会调用消息接口，远程服务必须携带 API Key。请先填写 Key；本地服务可以留空。")
            return
        }

        testInFlight = true
        testButton.title = "测试中…"
        testButton.isEnabled = false
        fetchButton.isEnabled = false
        statusLabel.stringValue = "正在连接模型（真实请求，最多 1 个输出 Token）…"
        statusLabel.toolTip = nil

        PredictionClient.testConnection(model: draft, apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            self.testInFlight = false
            self.testButton.title = "测试连接"
            self.testButton.isEnabled = true
            self.fetchButton.isEnabled = true
            guard self.selectedID == id else { return }
            switch result {
            case .success(let probe):
                let latency = String(format: "%.0f ms", probe.elapsed * 1000)
                let usage = probe.usageTokens.map { "约 \($0) tokens" } ?? "Token 用量未返回"
                self.statusLabel.stringValue = "模型已连通 · HTTP \(probe.status) · \(latency) · \(usage)"
                var tips = ["已调用 \(draft.endpoint?.absoluteString ?? "真实消息接口")",
                            "返回 HTTP \(probe.status)，说明地址、鉴权、API 格式与模型均可用。"]
                if let finish = probe.finishReason {
                    tips.append("finish: \(finish)")
                }
                if probe.usageTokens == nil {
                    tips.append("服务端未返回 usage；本次仍可能产生少量 Token 消耗。")
                }
                self.statusLabel.toolTip = tips.joined(separator: "\n")
            case .failure(let error):
                self.statusLabel.stringValue = "模型连接失败"
                self.statusLabel.toolTip = error.localizedDescription
                var alertTitle = "模型连接失败"
                var alertMessage = error.localizedDescription
                if let predictionError = error as? PredictionClientError {
                    switch predictionError {
                    case .http(let status, _):
                        if status == 401 || status == 403 {
                            self.statusLabel.stringValue = "鉴权失败 · HTTP \(status)"
                            alertTitle = "鉴权失败"
                            alertMessage = "真实请求被服务端拒绝（HTTP \(status)）。请检查 API Key、模型权限和 Base URL 是否属于同一个环境。"
                        } else if status == 404 {
                            self.statusLabel.stringValue = "消息接口路径不存在 · HTTP 404"
                            alertTitle = "接口路径不存在"
                        } else if status == 429 {
                            self.statusLabel.stringValue = "请求被限流 · HTTP 429"
                            alertTitle = "请求被限流"
                            alertMessage = "服务端返回 HTTP 429。请稍后重试，或检查账号额度与速率限制。"
                        } else {
                            self.statusLabel.stringValue = "接口返回 HTTP \(status)"
                        }
                    case .transport:
                        self.statusLabel.stringValue = "无法连接 · 检查地址和网络"
                        alertTitle = "无法连接"
                    case .malformedJSON:
                        self.statusLabel.stringValue = "接口有响应，但不是有效 JSON"
                        alertTitle = "响应格式异常"
                    case .invalidEndpoint:
                        self.statusLabel.stringValue = "Base URL 无效"
                    case .badResponse:
                        self.statusLabel.stringValue = "接口响应异常"
                    case .noSchedule, .noPredictions:
                        break
                    }
                }
                self.showAlert(title: alertTitle, message: alertMessage)
            }
        }
    }

    @objc private func openFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.modelsURL])
    }

    private var selectedConfig: ModelConfig? {
        guard let id = selectedID else { return nil }
        return store.models.first(where: { $0.id == id })
    }

    private static func isLocalEndpoint(_ baseURL: String) -> Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func resolvedAPIKey(for config: ModelConfig) throws -> String? {
        let typed = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        guard config.hasKey else { return nil }
        return try store.apiKey(for: config)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func showError(_ error: Error, title: String = "操作失败") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
