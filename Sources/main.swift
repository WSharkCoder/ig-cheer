import Cocoa

// MARK: - Constants

private let slogan = "IG 加油，冲冲冲！"
private let loginLabel = "com.wsharkcoder.igcheer"
private let panelSize = NSSize(width: 400, height: 380)

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
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("IGCheer", isDirectory: true)
            .appendingPathComponent("quotes.txt")
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
        // One forced break is enough for the two-line card; fold any extra
        // separators back into the second line instead of dropping text.
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

private extension NSColor {
    static let igGreen = NSColor(calibratedRed: 0.247, green: 0.561, blue: 0.310, alpha: 1.0)
    static let igRed = NSColor(calibratedRed: 0.851, green: 0.220, blue: 0.173, alpha: 1.0)
    static let ink = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)
    static let caption = NSColor(calibratedWhite: 0.52, alpha: 1.0)
    static let hairline = NSColor(calibratedRed: 0.906, green: 0.882, blue: 0.839, alpha: 1.0)
    static let faint = NSColor(calibratedRed: 0.655, green: 0.631, blue: 0.584, alpha: 1.0)
    static let navy = NSColor(calibratedRed: 0.082, green: 0.102, blue: 0.125, alpha: 1.0)
    static let mutedInk = NSColor(calibratedRed: 0.459, green: 0.427, blue: 0.384, alpha: 1.0)
}

private func resourceImage(_ name: String) -> NSImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
    return NSImage(contentsOf: url)
}

/// 22 pt grayscale bust with white/gray texture. PNG reps only; the grain is
/// raster by design, so 1x/2x/3x cover the menu bar without a blurry upscale.
private func grayBustMenuImage() -> NSImage? {
    guard let base = Bundle.main.url(forResource: "MenuIconGrayBust", withExtension: "png") else {
        return nil
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
    guard !image.representations.isEmpty else { return nil }
    image.isTemplate = true
    return image
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

// MARK: - Dropdown view (V1 名片式)

final class DropdownView: NSView {
    var tailX: CGFloat = 190
    var onDismiss: (() -> Void)?
    var onInteraction: (() -> Void)?

    private let avatar = resourceImage("avatar_bust_white")
    private var quotes = defaultQuotes
    private var quoteIndex = 0
    private var liked = false
    private var toastVisible = false
    private var toastToken = 0
    private var ctaRect = NSRect.zero
    private var nextRect = NSRect.zero

    func reloadQuotes() {
        quotes = QuoteStore.load()
        if quoteIndex >= quotes.count {
            quoteIndex = 0
        }
        needsDisplay = true
    }

    func resetInteraction() {
        liked = false
        toastVisible = false
        quoteIndex = 0
        toastToken += 1
        needsDisplay = true
    }

    private func drawText(_ text: String,
                          in rect: NSRect,
                          font: NSFont,
                          color: NSColor,
                          alignment: NSTextAlignment = .left,
                          lineSpacing: CGFloat = 0,
                          kern: CGFloat = 0) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if kern != 0 { attrs[.kern] = kern }
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func cycleQuote() {
        guard quotes.count > 1 else { return }
        quoteIndex = (quoteIndex + 1) % quotes.count
        needsDisplay = true
        onInteraction?()
    }

    private func like() {
        guard !liked else { return }
        liked = true
        toastVisible = true
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toastVisible = false
            self.needsDisplay = true
        }
        needsDisplay = true
        onInteraction?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let card = NSRect(x: 10, y: 8, width: bounds.width - 20, height: bounds.height - 16)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 24, yRadius: 24)

        // upward tail, so the popup feels attached to the menu bar icon
        let tx = min(max(tailX, 34), bounds.width - 34)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tx - 13, y: card.maxY - 1))
        tail.line(to: NSPoint(x: tx, y: bounds.maxY - 0.5))
        tail.line(to: NSPoint(x: tx + 13, y: card.maxY - 1))
        tail.close()

        let shape = NSBezierPath()
        shape.append(cardPath)
        shape.append(tail)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 18,
                      color: NSColor.black.withAlphaComponent(0.22).cgColor)
        NSColor.white.setFill()
        shape.fill()
        ctx.restoreGState()

        NSColor.black.withAlphaComponent(0.05).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        let contentX: CGFloat = 32
        let contentW = card.width - 44
        let top = card.maxY - 22
        let avatarRect = NSRect(x: contentX, y: top - 104, width: 104, height: 104)

        // dark rounded avatar tile with the full gray flag-bearer
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12,
                      color: NSColor.black.withAlphaComponent(0.18).cgColor)
        NSColor.navy.setFill()
        NSBezierPath(roundedRect: avatarRect, xRadius: 24, yRadius: 24).fill()
        ctx.restoreGState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: avatarRect, xRadius: 24, yRadius: 24).addClip()
        if let avatar {
            avatar.draw(in: avatarRect.insetBy(dx: 3, dy: 3),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.13).setStroke()
        let avatarBorder = NSBezierPath(roundedRect: avatarRect.insetBy(dx: 0.5, dy: 0.5),
                                        xRadius: 23.5, yRadius: 23.5)
        avatarBorder.lineWidth = 1
        avatarBorder.stroke()

        NSColor.igRed.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: avatarRect.maxX - 18, y: avatarRect.maxY - 18,
                                    width: 12, height: 12)).fill()
        NSColor.igRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: avatarRect.maxX - 15, y: avatarRect.maxY - 15,
                                    width: 6, height: 6)).fill()

        let copyX = avatarRect.maxX + 16
        let copyW = card.maxX - 22 - copyX

        drawText("THE SHY · 应援模式",
                 in: NSRect(x: copyX, y: top - 12, width: copyW, height: 12),
                 font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                 color: .igRed, kern: 1.25)

        drawText("IG 加油，\n冲冲冲！",
                 in: NSRect(x: copyX, y: top - 76, width: copyW, height: 60),
                 font: NSFont.systemFont(ofSize: 27, weight: .heavy),
                 color: .ink)

        let statusY = top - 96
        NSColor.igGreen.setFill()
        NSBezierPath(ovalIn: NSRect(x: copyX, y: statusY + 3, width: 6, height: 6)).fill()
        drawText("应援中",
                 in: NSRect(x: copyX + 12, y: statusY - 1, width: 40, height: 12),
                 font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                 color: .igGreen)
        drawText("/",
                 in: NSRect(x: copyX + 52, y: statusY - 1, width: 8, height: 12),
                 font: NSFont.systemFont(ofSize: 10, weight: .regular),
                 color: .hairline)
        drawText("INVICTUS GAMING",
                 in: NSRect(x: copyX + 62, y: statusY, width: 145, height: 11),
                 font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
                 color: .caption, kern: 1.2)

        let ruleY = top - 122
        NSColor.hairline.setFill()
        NSRect(x: contentX, y: ruleY, width: contentW, height: 1).fill()

        let sectionY = ruleY - 26
        drawText("今日金句",
                 in: NSRect(x: contentX, y: sectionY, width: 160, height: 12),
                 font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                 color: NSColor(calibratedRed: 0.549, green: 0.518, blue: 0.467, alpha: 1),
                 kern: 1.4)
        drawText(String(format: "%02d / %02d", quoteIndex + 1, quotes.count),
                 in: NSRect(x: card.maxX - 22 - 108, y: sectionY, width: 108, height: 12),
                 font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                 color: NSColor(calibratedRed: 0.698, green: 0.663, blue: 0.604, alpha: 1),
                 alignment: .right, kern: 0.6)

        let quoteRect = NSRect(x: contentX, y: sectionY - 70, width: contentW,
                               height: quotes[quoteIndex].contains("\n") ? 60 : 44)
        drawText(quotes[quoteIndex],
                 in: quoteRect,
                 font: NSFont(name: "Songti SC Bold", size: 19)
                    ?? NSFont.systemFont(ofSize: 19, weight: .semibold),
                 color: .ink, lineSpacing: 4)

        let footY = quoteRect.minY - 22
        if quotes.count > 1 {
            if quotes.count <= 12 {
                var dotX = contentX
                for index in quotes.indices {
                    let active = index == quoteIndex
                    let width: CGFloat = active ? 14 : 4
                    (active ? NSColor.igRed : NSColor(calibratedWhite: 0.85, alpha: 1)).setFill()
                    NSBezierPath(roundedRect: NSRect(x: dotX, y: footY + 6, width: width, height: 4),
                                 xRadius: 2, yRadius: 2).fill()
                    dotX += width + 5
                }
            }

            nextRect = NSRect(x: card.maxX - 22 - 96, y: footY - 2, width: 96, height: 22)
            drawText("换一句  ↻",
                     in: NSRect(x: nextRect.minX, y: footY + 5, width: 96, height: 14),
                     font: NSFont.systemFont(ofSize: 10, weight: .regular),
                     color: .mutedInk, alignment: .right)
        } else {
            nextRect = .zero
        }

        ctaRect = NSRect(x: contentX, y: 42, width: contentW, height: 51)
        let ctaColor = liked ? NSColor.igGreen : NSColor.ink
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12,
                      color: NSColor.black.withAlphaComponent(0.18).cgColor)
        ctaColor.setFill()
        NSBezierPath(roundedRect: ctaRect, xRadius: 14, yRadius: 14).fill()
        ctx.restoreGState()

        drawText(liked ? "点赞成功" : "点赞应援",
                 in: NSRect(x: ctaRect.minX + 15, y: ctaRect.minY + 21, width: 220, height: 17),
                 font: NSFont.systemFont(ofSize: 14, weight: .bold),
                 color: .white)
        drawText(liked ? "IG 加油！" : "给 IG 加油",
                 in: NSRect(x: ctaRect.minX + 15, y: ctaRect.minY + 10, width: 220, height: 11),
                 font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
                 color: NSColor.white.withAlphaComponent(0.62))

        let plusRect = NSRect(x: ctaRect.maxX - 42, y: ctaRect.minY + 12,
                              width: 27, height: 27)
        (liked ? NSColor.white : NSColor.igRed).setFill()
        NSBezierPath(ovalIn: plusRect).fill()
        drawText("+1",
                 in: plusRect.insetBy(dx: 0, dy: 6),
                 font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                 color: liked ? NSColor.igGreen : NSColor.white,
                 alignment: .center)

        if !toastVisible {
            drawText("点一下，为 The Shy 加一份士气",
                     in: NSRect(x: contentX, y: 24, width: contentW, height: 11),
                     font: NSFont.systemFont(ofSize: 9, weight: .regular),
                     color: .faint, alignment: .center)
        }

        if toastVisible {
            let toastFont = NSFont.systemFont(ofSize: 10, weight: .medium)
            let toastText = "点赞成功 · IG 加油！"
            let textWidth = (toastText as NSString).size(withAttributes: [.font: toastFont]).width
            let toastRect = NSRect(x: bounds.midX - (textWidth + 24) / 2,
                                   y: 10, width: textWidth + 24, height: 22)
            NSColor.navy.setFill()
            NSBezierPath(roundedRect: toastRect, xRadius: 11, yRadius: 11).fill()
            drawText(toastText,
                     in: NSRect(x: toastRect.minX + 12, y: toastRect.minY + 6,
                                width: textWidth, height: 12),
                     font: toastFont, color: .white, alignment: .center)
        }

        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if ctaRect.contains(point) {
            like()
            return
        }
        if nextRect.contains(point) {
            cycleQuote()
            return
        }
        onDismiss?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !ctaRect.isEmpty { addCursorRect(ctaRect, cursor: .pointingHand) }
        if !nextRect.isEmpty { addCursorRect(nextRect, cursor: .pointingHand) }
    }
}

// MARK: - Dropdown controller

final class DropdownController {
    private var panel: NSPanel?
    private var view: DropdownView?
    private var hideToken = 0

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.animationBehavior = .none

        let v = DropdownView(frame: NSRect(origin: .zero, size: panelSize))
        v.wantsLayer = true
        v.onDismiss = { [weak self] in self?.hide() }
        v.onInteraction = { [weak self] in self?.keepAlive() }
        p.contentView = v
        panel = p
        view = v
        return p
    }

    func show(anchor button: NSStatusBarButton?) {
        let panel = makePanelIfNeeded()
        guard let screen = button?.window?.screen ?? NSScreen.main else { return }

        var originX = screen.visibleFrame.midX - panelSize.width / 2
        var originY = screen.visibleFrame.maxY - panelSize.height - 4
        var anchorMidX = screen.visibleFrame.midX
        if let button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            anchorMidX = rect.midX
            originX = rect.midX - panelSize.width / 2
            originY = rect.minY - panelSize.height - 4
        }
        let minX = screen.visibleFrame.minX + 8
        let maxX = screen.visibleFrame.maxX - panelSize.width - 8
        originX = min(max(originX, minX), max(minX, maxX))

        view?.tailX = min(max(anchorMidX - originX, 34), panelSize.width - 34)
        view?.reloadQuotes()
        view?.resetInteraction()
        view?.needsDisplay = true

        panel.setFrame(NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height),
                       display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        if let layer = panel.contentView?.layer {
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.94, 1.012, 1.0]
            pop.keyTimes = [0, 0.7, 1]
            pop.duration = 0.26
            pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(pop, forKey: "pop")
        }

        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            guard let self, self.hideToken == token else { return }
            self.hide()
        }
    }

    func keepAlive() {
        guard let panel, panel.isVisible else { return }
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            guard let self, self.hideToken == token else { return }
            self.hide()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        hideToken += 1
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dropdown = DropdownController()
    private var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        QuoteStore.ensureConfigExists()
        buildStatusItem()
        buildMenu()

        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.cheer()
            }
        }
        handleLaunchArguments()
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
        guard let button = statusItem.button, let image = grayBustMenuImage() else { return }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        button.image = image
        button.imageScaling = .scaleProportionallyDown
    }

    private func buildMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        let cheerItem = NSMenuItem(title: "再喊一次：\(slogan)", action: #selector(cheerAction), keyEquivalent: "")
        cheerItem.target = self
        menu.addItem(cheerItem)
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
            menu.item(withTag: 102)?.state = LoginItem.isEnabled ? .on : .off
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: sender.bounds.height + 5),
                       in: sender)
        } else {
            cheer()
        }
    }

    @objc private func cheerAction() { cheer() }

    func cheer() {
        dropdown.show(anchor: statusItem.button)
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        menu.item(withTag: 102)?.state = LoginItem.isEnabled ? .on : .off
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

        左键点击菜单栏图标：打开应援卡，读金句、点赞应援
        右键 / Control-点击：更多选项
        金句配置：右键菜单 →「打开金句配置…」

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
                    menu.item(withTag: 102)?.state = LoginItem.isEnabled ? .on : .off
                    menu.popUp(positioning: nil,
                               at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
                }
            } else {
                cheer()
            }
        }
    }

    private func renderPreview(to path: String) {
        let v = DropdownView(frame: NSRect(origin: .zero, size: panelSize))
        v.tailX = panelSize.width / 2
        v.reloadQuotes()
        let scale = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(panelSize.width) * scale,
                                         pixelsHigh: Int(panelSize.height) * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = panelSize
        v.cacheDisplay(in: v.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        if args.contains("--diagnose") {
            let button = statusItem.button
            let message = "STATUS_ITEM button=\(button != nil) frame=\(button?.frame ?? .zero) window=\(String(describing: button?.window?.frame)) image=\(String(describing: button?.image?.size)) template=\(button?.image?.isTemplate ?? false) reps=\(button?.image?.representations.count ?? 0)\n"
            FileHandle.standardOutput.write(message.data(using: .utf8)!)
            NSApp.terminate(nil)
            return
        }
        if let idx = args.firstIndex(of: "--render-preview"), idx + 1 < args.count {
            renderPreview(to: args[idx + 1])
            NSApp.terminate(nil)
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
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
