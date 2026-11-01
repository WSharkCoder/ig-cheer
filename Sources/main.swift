import Cocoa

// MARK: - Constants

private let slogan = "IG 加油，冲冲冲！"
private let loginLabel = "com.wsharkcoder.igcheer"
private let autoHideInterval: TimeInterval = 20

private let defaultQuotes = [
    "天不生TheShy，\nLPL上单万古如长夜",
    "天神下凡一锤四",
    "剑气纵横三万里，\n一剑光寒十九州",
    "大莽夫带三尺剑立不世之志",
    "五花马千金裘，\n多喝几杯不算愁",
    "一半天使，一半恶魔"
]

/// User-editable quote list. Kept as a plain UTF-8 text file so adding a line
/// is enough; `|` forces a visual line break inside one quote.
private enum QuoteStore {
    static var configURL: URL {
        if let custom = ProcessInfo.processInfo.environment["IG_CHEER_QUOTES"],
           !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return AppPaths.supportDirectory.appendingPathComponent("quotes.txt")
    }

    static func ensureConfigExists() {
        let fm = FileManager.default
        let url = configURL
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: url.path) else { return }
        try? defaultFileText.write(to: url, atomically: true, encoding: .utf8)
    }

    static func load() -> [String] {
        ensureConfigExists()
        guard let data = try? Data(contentsOf: configURL),
              let raw = String(data: data, encoding: .utf8) else {
            return defaultQuotes
        }

        var loaded: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let quote = normalize(trimmed)
            if !quote.isEmpty { loaded.append(quote) }
        }
        return loaded.isEmpty ? defaultQuotes : loaded
    }

    private static func normalize(_ line: String) -> String {
        let pieces = line.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = pieces.first else { return "" }
        guard pieces.count > 1 else { return first }
        return first + "\n" + pieces.dropFirst().joined(separator: "，")
    }

    private static let defaultFileText = """
    # IG 应援 · 金句配置
    # 每行一句；空行和以 # 开头的行会被忽略。
    # 想强制分成两行显示，用 | 分隔，例如：
    # 天不生TheShy，|LPL上单万古如长夜
    #
    # 修改保存后，重新打开面板即可生效。
    天不生TheShy，|LPL上单万古如长夜
    天神下凡一锤四
    剑气纵横三万里，|一剑光寒十九州
    大莽夫带三尺剑立不世之志
    五花马千金裘，|多喝几杯不算愁
    一半天使，一半恶魔
    """
}

// MARK: - Login item (LaunchAgent)

enum LoginItem {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(loginLabel).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            let fm = FileManager.default
            try? fm.createDirectory(at: plistURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            let dict: [String: Any] = [
                "Label": loginLabel,
                "ProgramArguments": [Bundle.main.executablePath ?? ""],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
                "LimitLoadToSessionType": "Aqua"
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: dict,
                                                            format: .xml, options: 0) {
                try? data.write(to: plistURL)
            }
            runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        } else {
            runLaunchctl(["bootout", "gui/\(getuid())/\(loginLabel)"])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func runLaunchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}

// MARK: - Panel mode

enum PanelMode: String, CaseIterable {
    case vertical
    case horizontal

    var title: String {
        switch self {
        case .vertical: return "纵向长卡"
        case .horizontal: return "横向仪表盘"
        }
    }
}

enum PanelMetrics {
    static func initialSize(for mode: PanelMode) -> NSSize {
        switch mode {
        case .vertical: return NSSize(width: 440, height: 983)
        case .horizontal: return NSSize(width: 800, height: 502)
        }
    }

    static func minHeight(for mode: PanelMode) -> CGFloat {
        mode == .vertical ? 560 : 430
    }

    static func maxHeight(for mode: PanelMode) -> CGFloat {
        mode == .vertical ? 1240 : 760
    }
}

// MARK: - Dropdown controller

final class DropdownController {
    private var panel: NSPanel?
    private var surface: PanelWebSurface?
    private var hideToken = 0
    private var currentMode: PanelMode = .vertical
    private var currentHeight: CGFloat = 983
    private weak var anchorButton: NSStatusBarButton?
    private var panelTop: CGFloat = 0

    var onLike: (() -> Void)?
    var onNextQuote: (() -> Void)?
    var onOpenModels: (() -> Void)?
    var onRefreshPredictions: (() -> Void)?
    var onDismiss: (() -> Void)?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }
        let size = PanelMetrics.initialSize(for: currentMode)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.isMovable = false
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.animationBehavior = .none

        let s = PanelWebSurface(frame: NSRect(origin: .zero, size: size))
        s.onLike = { [weak self] in self?.onLike?() }
        s.onNextQuote = { [weak self] in self?.onNextQuote?() }
        s.onOpenModels = { [weak self] in self?.onOpenModels?() }
        s.onRefreshPredictions = { [weak self] in self?.onRefreshPredictions?() }
        s.onDismiss = { [weak self] in self?.onDismiss?() }
        s.onResize = { [weak self] height in self?.resize(to: height) }
        p.contentView = s
        panel = p
        surface = s
        return p
    }

    func show(anchor button: NSStatusBarButton?, mode: PanelMode, state: PanelState) {
        let panel = makePanelIfNeeded()
        currentMode = mode
        anchorButton = button
        currentHeight = PanelMetrics.initialSize(for: mode).height
        let frame = frameForCurrentPanel()
        panel.setFrame(frame, display: false)
        panelTop = frame.maxY
        panel.alphaValue = 0
        surface?.setState(state)
        updateTail()

        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        if let layer = panel.contentView?.layer {
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.96, 1.008, 1.0]
            pop.keyTimes = [0, 0.72, 1]
            pop.duration = 0.24
            pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(pop, forKey: "pop")
        }
        keepAlive()
    }

    func update(state: PanelState) {
        surface?.setState(state)
    }

    func keepAlive() {
        guard isVisible else { return }
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideInterval) { [weak self] in
            guard let self, self.hideToken == token else { return }
            self.hide()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        hideToken += 1
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func resize(to height: CGFloat) {
        guard let panel else { return }
        let clamped = min(max(height, PanelMetrics.minHeight(for: currentMode)),
                          PanelMetrics.maxHeight(for: currentMode))
        guard abs(clamped - currentHeight) > 0.5 else { return }
        currentHeight = clamped
        var frame = panel.frame
        frame.origin.y = panelTop - clamped
        frame.size.height = clamped
        if let screen = anchorButton?.window?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if frame.minY < visible.minY + 4 {
                frame.origin.y = visible.minY + 4
            }
            if frame.maxY > visible.maxY - 4 {
                frame.origin.y = visible.maxY - 4 - clamped
            }
        }
        panel.setFrame(frame, display: true)
        panelTop = frame.maxY
        updateTail()
    }

    private func frameForCurrentPanel() -> NSRect {
        let size = NSSize(width: PanelMetrics.initialSize(for: currentMode).width,
                          height: currentHeight)
        guard let screen = anchorButton?.window?.screen ?? NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        var originX = screen.visibleFrame.midX - size.width / 2
        var originY = screen.visibleFrame.maxY - size.height - 4
        if let button = anchorButton, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            originX = rect.midX - size.width / 2
            originY = rect.minY - size.height - 4
        }
        let visible = screen.visibleFrame
        let minX = visible.minX + 8
        let maxX = visible.maxX - size.width - 8
        originX = min(max(originX, minX), max(minX, maxX))
        originY = max(originY, visible.minY + 4)
        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private func updateTail() {
        guard let panel, let button = anchorButton, let window = button.window else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        // The CSS card starts 20 px inside the transparent window; tail is
        // positioned relative to the card itself.
        let tail = rect.midX - panel.frame.minX - 20
        surface?.setTail(x: min(max(tail, 28), panel.frame.width - 48))
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dropdown = DropdownController()
    private var menu: NSMenu!
    private var quotes = defaultQuotes
    private var quoteIndex = 0
    private var currentMode: PanelMode = .vertical
    private var currentSchedule: LoadedSchedule?
    private var toastText: String?
    private var toastToken = 0
    private var predictionRefreshInFlight = false
    private var modelSettingsWindow: ModelSettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppPaths.ensureSupportDirectory()
        QuoteStore.ensureConfigExists()
        currentMode = PanelMode(rawValue: UserDefaults.standard.string(forKey: "panelMode") ?? "")
            ?? .vertical
        buildStatusItem()
        buildMenu()
        configureDropdown()

        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.cheer()
            }
        }
        handleLaunchArguments()
    }

    private func configureDropdown() {
        dropdown.onLike = { [weak self] in self?.handleLike() }
        dropdown.onNextQuote = { [weak self] in self?.cycleQuote() }
        dropdown.onOpenModels = { [weak self] in self?.openModelSettings() }
        dropdown.onRefreshPredictions = { [weak self] in self?.refreshPredictions() }
        dropdown.onDismiss = { [weak self] in self?.dropdown.hide() }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "IG 应援 — 点我喊口号"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            applyMenuIcon()
        }
    }

    private func applyMenuIcon() {
        guard let button = statusItem.button,
              let base = Bundle.main.url(forResource: "MenuIconGrayBust", withExtension: "png") else {
            return
        }
        let directory = base.deletingLastPathComponent()
        let image = NSImage(size: NSSize(width: 22, height: 22))
        for scale in 1...3 {
            let name = scale == 1 ? "MenuIconGrayBust.png" : "MenuIconGrayBust@\(scale)x.png"
            let url = directory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) {
                rep.size = NSSize(width: 22, height: 22)
                image.addRepresentation(rep)
            }
        }
        guard !image.representations.isEmpty else { return }
        image.isTemplate = true
        button.image = image
        image.size = NSSize(width: 22, height: 22)
        button.imageScaling = .scaleProportionallyDown
    }

    private func buildMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        let cheerItem = NSMenuItem(title: "打开应援面板", action: #selector(cheerAction), keyEquivalent: "")
        cheerItem.target = self
        menu.addItem(cheerItem)
        menu.addItem(.separator())

        let modeItem = NSMenuItem(title: "展示模式", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in PanelMode.allCases {
            let item = NSMenuItem(title: mode.title,
                                  action: #selector(selectMode(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = currentMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let modelsItem = NSMenuItem(title: "预测模型", action: nil, keyEquivalent: "")
        let modelsMenu = NSMenu()
        for config in ModelStore.shared.models {
            let item = NSMenuItem(title: "\(config.name)  ·  \(config.model)",
                                  action: #selector(selectModel(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = config.id
            item.state = ModelStore.shared.activeModelID == config.id ? .on : .off
            modelsMenu.addItem(item)
        }
        if modelsMenu.items.isEmpty {
            let empty = NSMenuItem(title: "尚未配置模型", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            modelsMenu.addItem(empty)
        }
        modelsMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "模型配置…", action: #selector(openModelSettingsAction), keyEquivalent: "")
        settingsItem.target = self
        modelsMenu.addItem(settingsItem)
        modelsItem.submenu = modelsMenu
        menu.addItem(modelsItem)

        menu.addItem(.separator())

        let scheduleItem = NSMenuItem(title: "刷新赛程（官网 · 无需 Token）",
                                      action: #selector(refreshScheduleAction), keyEquivalent: "")
        scheduleItem.target = self
        menu.addItem(scheduleItem)

        let predictionItem = NSMenuItem(title: "刷新 AI 比分预测",
                                        action: #selector(refreshPredictionAction), keyEquivalent: "")
        predictionItem.target = self
        menu.addItem(predictionItem)
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        loginItem.tag = 102
        menu.addItem(loginItem)

        let quotesItem = NSMenuItem(title: "打开金句配置…", action: #selector(openQuoteConfig), keyEquivalent: "")
        quotesItem.target = self
        menu.addItem(quotesItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "关于 IG 应援", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "退出 IG 应援", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true
        if wantsMenu {
            buildMenu()
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: sender.bounds.height + 5),
                       in: sender)
        } else {
            if dropdown.isVisible { dropdown.hide() } else { cheer() }
        }
    }

    @objc private func cheerAction() { cheer() }

    private func cheer() {
        quotes = QuoteStore.load()
        if quoteIndex >= quotes.count { quoteIndex = 0 }
        currentSchedule = ScheduleStore.load()
        let state = buildState(toast: nil)
        dropdown.show(anchor: statusItem.button, mode: currentMode, state: state)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = PanelMode(rawValue: raw), mode != currentMode else { return }
        currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "panelMode")
        let wasVisible = dropdown.isVisible
        dropdown.hide()
        if wasVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.cheer()
            }
        }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ModelStore.shared.setActive(id)
        buildMenu()
        if dropdown.isVisible {
            toastText = "已切换模型 · 点击「刷新 AI 比分预测」"
            dropdown.update(state: buildState(toast: toastText))
            clearToast(after: 2.5)
        }
    }

    @objc private func openModelSettingsAction() { openModelSettings() }

    private func openModelSettings() {
        dropdown.hide()
        if modelSettingsWindow == nil {
            let controller = ModelSettingsWindowController()
            controller.onClose = { [weak self] in
                guard let self else { return }
                self.buildMenu()
                if self.dropdown.isVisible {
                    self.dropdown.update(state: self.buildState(toast: nil))
                }
            }
            modelSettingsWindow = controller
        }
        modelSettingsWindow?.show()
    }

    @objc private func refreshScheduleAction() {
        refreshSchedule()
    }

    @objc private func refreshPredictionAction() {
        if !dropdown.isVisible { cheer() }
        refreshPredictions()
    }

    private func refreshSchedule() {
        let script = Bundle.main.path(forResource: "fetch_schedule", ofType: "py")
            ?? "\(FileManager.default.currentDirectoryPath)/tools/fetch_schedule.py"
        guard FileManager.default.fileExists(atPath: script) else {
            showAlert(title: "找不到赛程脚本", message: "打包资源中缺少 fetch_schedule.py。")
            return
        }
        AppPaths.ensureSupportDirectory()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["python3", script, "--out", AppPaths.scheduleURL.path]
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe
        task.terminationHandler = { [weak self] process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                if process.terminationStatus == 0 {
                    self.currentSchedule = ScheduleStore.load()
                    if self.dropdown.isVisible {
                        self.dropdown.update(state: self.buildState(toast: "赛程已刷新 · 点击「刷新 AI 比分预测」"))
                        self.clearToast(after: 2.5)
                    } else {
                        self.cheer()
                    }
                } else {
                    self.showAlert(title: "刷新赛程失败",
                                   message: output.isEmpty ? "官网暂时不可用，请稍后再试。" : output)
                }
            }
        }
        do {
            try task.run()
        } catch {
            showAlert(title: "无法运行赛程脚本", message: error.localizedDescription)
        }
    }

    private func refreshPredictions() {
        guard let model = ModelStore.shared.activeModel else {
            showAlert(title: "还没有模型", message: "请先在「模型配置」中添加一套模型。")
            return
        }
        let schedule = currentSchedule ?? ScheduleStore.load()
        let upcoming = ScheduleStore.upcoming(from: schedule, limit: 3)
        guard !upcoming.isEmpty else {
            showAlert(title: "暂无待预测赛程", message: "官网赛程里还没有 IG 的下一场比赛。")
            return
        }
        let local = Self.isLocalEndpoint(model.baseURL)
        var apiKey: String? = nil
        if !local {
            do {
                apiKey = try ModelStore.shared.apiKey(for: model)
            } catch {
                showAlert(title: "读取加密 Key 失败", message: error.localizedDescription)
                return
            }
        }
        guard local || apiKey != nil else {
            showAlert(title: "尚未配置 API Key",
                      message: "右键「模型配置…」填写 Key 后，才能请求真实模型。当前展示示例预测。")
            return
        }
        guard !predictionRefreshInFlight else {
            if dropdown.isVisible {
                dropdown.update(state: buildState(toast: "预测请求进行中…"))
            }
            return
        }

        predictionRefreshInFlight = true
        if dropdown.isVisible {
            dropdown.update(state: buildState(toast: "正在请求 AI 预测…"))
        }
        PredictionClient.fetch(model: model, apiKey: apiKey, matches: upcoming) { [weak self] result in
            guard let self else { return }
            self.predictionRefreshInFlight = false
            switch result {
            case .success(let predictions):
                PredictionStore.save(predictions, model: model)
                if self.dropdown.isVisible {
                    self.toastText = "AI 预测已更新"
                    self.dropdown.update(state: self.buildState(toast: self.toastText))
                    self.clearToast(after: 2.0)
                }
            case .failure(let error):
                NSLog("IGCheer prediction error: \(error.localizedDescription)")
                self.showAlert(title: "AI 预测失败", message: error.localizedDescription)
            }
        }
    }

    private func handleLike() {
        if CheerStore.markToday() {
            toastText = "点赞成功 · IG 加油！"
        } else {
            toastText = "今天已经应援过了"
        }
        dropdown.update(state: buildState(toast: toastText))
        dropdown.keepAlive()
        clearToast(after: 2.0)
    }

    private func cycleQuote() {
        guard quotes.count > 1 else { return }
        quoteIndex = (quoteIndex + 1) % quotes.count
        dropdown.update(state: buildState(toast: toastText))
        dropdown.keepAlive()
    }

    private func clearToast(after delay: TimeInterval) {
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toastText = nil
            if self.dropdown.isVisible {
                self.dropdown.update(state: self.buildState(toast: nil))
            }
        }
    }

    private func buildState(toast: String?) -> PanelState {
        let dates = CheerStore.load()
        let now = AppClock.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        let today = components.day ?? 1
        let likedDays = CheerStore.monthLikedDays(year: year, month: month, dates: dates)
        let likedToday = dates.contains(CheerStore.dateKey(for: now))

        let schedule = currentSchedule ?? ScheduleStore.load()
        let upcoming = ScheduleStore.upcoming(from: schedule, limit: 3)
        let recent = ScheduleStore.recentCompleted(from: schedule, limit: 3)
        var scheduleMatches = upcoming + recent
        if scheduleMatches.count > 3 { scheduleMatches = Array(scheduleMatches.prefix(3)) }
        var scheduleRows: [PanelScheduleRow] = []
        for (index, match) in scheduleMatches.enumerated() {
            let parts = DisplayFormat.dateParts(match.startDate)
            scheduleRows.append(PanelScheduleRow(
                id: match.id,
                dateText: parts.date,
                weekday: parts.weekday,
                timeText: parts.time,
                opponent: match.opponent?.code ?? "TBD",
                stage: DisplayFormat.stage(match.stage),
                bestOf: max(match.bestOf, 1),
                next: index == 0 && !match.isCompleted,
                completed: match.isCompleted,
                scoreText: match.scoreText
            ))
        }

        let model = ModelStore.shared.activeModel
        let cached = PredictionStore.load()
        let ids = Set(upcoming.map(\.id))
        let cacheUsable = cached != nil
            && cached?.modelID == model?.model
            && (cached?.predictions.isEmpty == false)
            && ids.allSatisfy { id in cached?.predictions.contains(where: { $0.matchID == id }) == true }
        let predictionSeed = cacheUsable ? (cached?.predictions ?? []) : PredictionStore.sample(
            for: upcoming,
            modelName: model?.name ?? "示例预测"
        )
        let predictionSample = !cacheUsable
        var predictionRows: [PanelPredictionRow] = []
        for match in upcoming {
            guard let prediction = predictionSeed.first(where: { $0.matchID == match.id }) else { continue }
            let parts = DisplayFormat.dateParts(match.startDate)
            predictionRows.append(PanelPredictionRow(
                matchID: match.id,
                opponent: match.opponent?.code ?? "TBD",
                stage: DisplayFormat.stage(match.stage),
                dateText: parts.date,
                igScore: prediction.igScore,
                opponentScore: prediction.opponentScore,
                confidence: prediction.confidence
            ))
        }

        let configured = model.map { $0.hasKey || Self.isLocalEndpoint($0.baseURL) } ?? false
        let source = schedule.isSample
            ? "lolesports.com · 示例"
            : "lolesports.com · 官网"
        return PanelState(
            mode: currentMode.rawValue,
            quote: quotes.isEmpty ? "" : quotes[min(quoteIndex, quotes.count - 1)],
            quoteIndex: quotes.isEmpty ? 0 : min(quoteIndex, quotes.count - 1),
            quoteCount: quotes.count,
            likedToday: likedToday,
            streak: CheerStore.streak(dates: dates),
            calendar: PanelCalendarState(year: year, month: month, today: today, likedDays: likedDays),
            schedule: scheduleRows,
            predictions: predictionRows,
            modelName: model?.name ?? "未配置模型",
            modelID: model?.model ?? "sample",
            modelConfigured: configured,
            predictionSample: predictionSample,
            scheduleSample: schedule.isSample,
            scheduleSource: source,
            scheduleUpdated: schedule.isSample ? "示例数据" : DisplayFormat.relativeUpdated(schedule.fetchedAt),
            toast: toast
        )
    }

    private static func isLocalEndpoint(_ baseURL: String) -> Bool {
        guard let url = URL(string: baseURL), let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        buildMenu()
    }

    @objc private func openQuoteConfig() {
        QuoteStore.ensureConfigExists()
        if !NSWorkspace.shared.open(QuoteStore.configURL) {
            NSSound.beep()
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "IG 应援"
        alert.informativeText = """
        \(slogan)

        左键点击菜单栏图标：打开应援面板
        右键 / Control-点击：展示模式、模型、赛程与预测
        每日只能点赞应援一次；日历会记录连续天数。

        模型 Key 使用 AES-GCM 加密后写入本地配置；不需要输入 Mac 密码。
        API Key 不会以明文写入配置文件。

        为 Invictus Gaming 打 Call！
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "冲！")
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "igcheer" {
            if url.host == "menu" {
                if let button = statusItem.button {
                    buildMenu()
                    menu.popUp(positioning: nil,
                               at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
                }
            } else if url.host == "mode" {
                let value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let mode = PanelMode(rawValue: value), mode != currentMode {
                    currentMode = mode
                    UserDefaults.standard.set(mode.rawValue, forKey: "panelMode")
                    if dropdown.isVisible { dropdown.hide() }
                }
            } else {
                cheer()
            }
        }
    }

    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        if args.contains("--diagnose") {
            let schedule = ScheduleStore.load()
            let cheer = CheerStore.load()
            let message = """
            MODE=\(currentMode.rawValue)
            QUOTES=\(QuoteStore.load().count)
            MODELS=\(ModelStore.shared.models.count) ACTIVE=\(ModelStore.shared.activeModelID)
            CHEER_DAYS=\(cheer.count) STREAK=\(CheerStore.streak(dates: cheer))
            SCHEDULE_MATCHES=\(schedule.matches.count) SAMPLE=\(schedule.isSample)
            STATUS_ITEM=\(statusItem.button != nil)
            """
            FileHandle.standardOutput.write((message + "\n").data(using: .utf8)!)
            NSApp.terminate(nil)
            return
        }
        if args.contains("--print-models") {
            var lines = ["COUNT=\(ModelStore.shared.models.count) ACTIVE=\(ModelStore.shared.activeModelID)"]
            for model in ModelStore.shared.models {
                lines.append("\(model.name) | \(model.model) | key=\(model.hasKey ? "encrypted" : "none") | \(model.baseURL)")
            }
            FileHandle.standardOutput.write((lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
            NSApp.terminate(nil)
            return
        }
        if args.contains("--print-schedule") {
            let schedule = ScheduleStore.load()
            var lines = ["SAMPLE=\(schedule.isSample) SOURCE=\(schedule.source) COUNT=\(schedule.matches.count)"]
            for match in schedule.matches {
                let opponent = match.opponent?.code ?? "TBD"
                lines.append("\(match.startTime) | \(match.stage) | \(match.state) | IG vs \(opponent) | BO\(match.bestOf)")
            }
            FileHandle.standardOutput.write((lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
            NSApp.terminate(nil)
            return
        }
        if args.contains("--crypto-test") {
            do {
                let cipher = try SecretBox.encrypt("ig-cheer-roundtrip")
                let plain = try SecretBox.decrypt(cipher)
                let message = plain == "ig-cheer-roundtrip"
                    ? "ENCRYPTION_OK ciphertext_prefix=\(cipher.prefix(3))"
                    : "ENCRYPTION_FAILED"
                FileHandle.standardOutput.write((message + "\n").data(using: .utf8)!)
            } catch {
                FileHandle.standardOutput.write(("ENCRYPTION_FAILED \(error.localizedDescription)\n").data(using: .utf8)!)
            }
            NSApp.terminate(nil)
            return
        }
        if args.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.openModelSettings()
            }
            return
        }
        if args.contains("--refresh-prediction") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.refreshPredictions()
            }
            return
        }
        if let idx = args.firstIndex(of: "--render-preview"), idx + 1 < args.count {
            let path = args[idx + 1]
            var mode = currentMode
            if let modeIndex = args.firstIndex(of: "--mode"), modeIndex + 1 < args.count,
               let requested = PanelMode(rawValue: args[modeIndex + 1]) {
                mode = requested
            }
            renderPreview(to: path, mode: mode)
            return
        }
        if args.contains("--print-quotes") {
            let loaded = QuoteStore.load()
            var lines = ["COUNT=\(loaded.count)"]
            for (index, quote) in loaded.enumerated() {
                lines.append("\(index + 1): \(quote.replacingOccurrences(of: "\n", with: " ⏎ "))")
            }
            FileHandle.standardOutput.write((lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
            NSApp.terminate(nil)
            return
        }
        if args.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.cheer()
            }
        }
    }

    private func renderPreview(to path: String, mode: PanelMode) {
        quotes = QuoteStore.load()
        currentSchedule = ScheduleStore.load()
        currentMode = mode
        let size = PanelMetrics.initialSize(for: mode)
        let surface = PanelWebSurface(frame: NSRect(origin: .zero, size: size))
        surface.setState(buildState(toast: nil))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = surface
        surface.onResize = { height in
            window.setContentSize(NSSize(width: size.width, height: max(400, height)))
        }
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            surface.snapshot { image in
                defer { NSApp.terminate(nil) }
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let data = rep.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write("preview snapshot failed\n".data(using: .utf8)!)
                    return
                }
                try? data.write(to: URL(fileURLWithPath: path))
                print("WROTE \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
            }
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String(message.prefix(1200))
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
