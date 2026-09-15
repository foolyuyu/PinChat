import AppKit
import QuartzCore
import SwiftUI

enum AttachmentDirection: String, Equatable, Sendable {
    case above
    case below
}

enum AnswerAttachmentState: Equatable, Sendable {
    case attached
    case detached

    func afterWindowMove(isProgrammatic: Bool) -> AnswerAttachmentState {
        isProgrammatic ? self : .detached
    }
}

enum WindowPlacement {
    static func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(result.width, visibleFrame.width)
        result.size.height = min(result.height, visibleFrame.height)
        result.origin.x = min(max(result.origin.x, visibleFrame.minX), visibleFrame.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visibleFrame.minY), visibleFrame.maxY - result.height)
        return result
    }

    static func snappedFloatingButton(
        _ frame: NSRect,
        to visibleFrame: NSRect,
        margin: CGFloat = 8
    ) -> NSRect {
        var result = clamped(frame, to: visibleFrame)
        result.origin.x = result.midX < visibleFrame.midX
            ? visibleFrame.minX + margin
            : visibleFrame.maxX - result.width - margin
        result.origin.y = min(
            max(result.origin.y, visibleFrame.minY + margin),
            visibleFrame.maxY - result.height - margin
        )
        return result
    }

    static func floatingButtonOrigin(
        pointerLocation: NSPoint,
        grabOffset: NSSize
    ) -> NSPoint {
        NSPoint(
            x: pointerLocation.x - grabOffset.width,
            y: pointerLocation.y - grabOffset.height
        )
    }

    static func preferredAttachmentDirection(
        anchor: NSRect,
        in visibleFrame: NSRect,
        requiredHeight: CGFloat,
        gap: CGFloat = 10
    ) -> AttachmentDirection {
        let below = anchor.minY - visibleFrame.minY - gap
        let above = visibleFrame.maxY - anchor.maxY - gap
        if below >= requiredHeight { return .below }
        if above >= requiredHeight { return .above }
        return below >= above ? .below : .above
    }

    static func stackedFrames(
        sizes: [NSSize],
        attachedTo anchor: NSRect,
        in visibleFrame: NSRect,
        direction: AttachmentDirection,
        gap: CGFloat = 10
    ) -> [NSRect] {
        guard !sizes.isEmpty else { return [] }
        var frames: [NSRect] = []
        var cursor = direction == .below ? anchor.minY - gap : anchor.maxY + gap

        for size in sizes {
            let width = min(size.width, visibleFrame.width)
            let height = min(size.height, visibleFrame.height)
            let x = min(
                max(anchor.midX - width / 2, visibleFrame.minX),
                visibleFrame.maxX - width
            )
            let y: CGFloat
            if direction == .below {
                y = cursor - height
                cursor = y - gap
            } else {
                y = cursor
                cursor = y + height + gap
            }
            frames.append(NSRect(x: x, y: y, width: width, height: height))
        }

        guard let minY = frames.map(\.minY).min(),
              let maxY = frames.map(\.maxY).max() else { return frames }
        let shift: CGFloat
        if minY < visibleFrame.minY {
            shift = visibleFrame.minY - minY
        } else if maxY > visibleFrame.maxY {
            shift = visibleFrame.maxY - maxY
        } else {
            shift = 0
        }
        return frames.map { frame in
            var shifted = frame
            shifted.origin.y += shift
            return clamped(shifted, to: visibleFrame)
        }
    }
}

enum PanelPresentationPolicy {
    static let crossSpaceBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary
    ]
}

enum PinChatVisualMetrics {
    static let petSize = NSSize(width: 96, height: 96)
    static let petArtworkSize = NSSize(width: 52, height: 56)
    static let petLauncherSize: CGFloat = 28
    static let composerSize = NSSize(width: 360, height: 50)
    static let composerActionSize: CGFloat = 30
    static let statusSize = NSSize(width: 410, height: 66)
    static let statusActionSize: CGFloat = 28
    static let answerSize = NSSize(width: 520, height: 420)
    static let answerToolbarActionSize: CGFloat = 24
    static let followUpActionSize: CGFloat = 30
    static let attachmentGap: CGFloat = 3
    static let launcherOverlap: CGFloat = 32
}

final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AppController()

    @Published var alwaysOnTop: Bool {
        didSet {
            defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop)
            updatePanelLevels()
        }
    }
    @Published var floatingButtonEnabled: Bool {
        didSet {
            defaults.set(floatingButtonEnabled, forKey: Keys.floatingButtonEnabled)
            updatePetVisibility()
        }
    }
    @Published private(set) var isComposerVisible = false
    @Published private(set) var isStatusVisible = false
    @Published private(set) var isAnswerVisible = false
    @Published private(set) var isDraggingPet = false
    @Published private(set) var answerAttachment: AnswerAttachmentState = .attached
    @Published private(set) var expansionDirection: AttachmentDirection = .below

    var answerDetached: Bool { answerAttachment == .detached }
    var isPetLauncherVisible: Bool {
        !isComposerVisible && !isStatusVisible && !isAnswerVisible
    }

    let model = AppModel()
    let spriteStore = PetSpriteStore()

    private let defaults = UserDefaults.standard
    private var petPanel: NSPanel?
    private var composerPanel: ChatPanel?
    private var statusPanel: ChatPanel?
    private var answerPanel: ChatPanel?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var globalHotKey: GlobalHotKey?
    private var petDragOffset: NSSize?
    private var codexHandoffInProgress = false
    private var screenParametersObserver: NSObjectProtocol?
    private var positioningPanels = false

    private enum Keys {
        static let alwaysOnTop = "alwaysOnTop"
        static let floatingButtonEnabled = "floatingButtonEnabled"
        static let petFrame = "petFrameV21"
        static let legacyPetFrameV2 = "petFrameV2"
        static let legacyFloatingButtonFrame = "floatingButtonFrame"
        static let answerFrame = "answerFrameV2"
        static let hasLaunchedV2 = "hasLaunchedV2"
    }

    private override init() {
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) == nil
            ? true
            : defaults.bool(forKey: Keys.alwaysOnTop)
        floatingButtonEnabled = defaults.object(forKey: Keys.floatingButtonEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.floatingButtonEnabled)
        super.init()
    }

    func launch() {
        NSApp.setActivationPolicy(.accessory)
        createPetPanel()
        createComposerPanel()
        createStatusPanel()
        createAnswerPanel()
        createStatusItem()
        registerGlobalHotKey()
        observeScreenChanges()
        model.start()
        updatePanelLevels()
        updatePetVisibility()

        if !defaults.bool(forKey: Keys.hasLaunchedV2) {
            defaults.set(true, forKey: Keys.hasLaunchedV2)
            showComposer()
        }
    }

    func terminate() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        NSApp.terminate(nil)
    }

    func toggleCompactWindow() {
        if isComposerVisible || isStatusVisible || isAnswerVisible {
            hideCompactWindow()
        } else {
            showComposer()
        }
    }

    func showCompactWindow() {
        showComposer()
    }

    func toggleComposer() {
        if isComposerVisible {
            hideComposer()
        } else {
            showComposer()
        }
    }

    func hideCompactWindow() {
        isComposerVisible = false
        isStatusVisible = false
        isAnswerVisible = false
        composerPanel?.orderOut(nil)
        statusPanel?.orderOut(nil)
        answerPanel?.orderOut(nil)
    }

    func showComposer() {
        model.restartAfterExternalHandoffIfNeeded()
        if model.isGenerating {
            showStatus()
            return
        }
        isStatusVisible = false
        isAnswerVisible = false
        isComposerVisible = true
        statusPanel?.orderOut(nil)
        answerPanel?.orderOut(nil)
        positionAttachedPanels()
        if let composerPanel { revealHorizontally(composerPanel) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideComposer() {
        isComposerVisible = false
        guard let panel = composerPanel, panel.isVisible else { return }
        let original = panel.frame
        let collapsed = NSRect(
            x: original.midX - 18,
            y: original.minY,
            width: 36,
            height: original.height
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(collapsed, display: true)
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
                panel.setFrame(original, display: false)
            }
        }
    }

    func sendMessage(_ text: String) {
        guard model.account != nil else {
            showComposer()
            model.alertMessage = PinChatError.notSignedIn.localizedDescription
            return
        }
        isComposerVisible = false
        isAnswerVisible = false
        isStatusVisible = true
        composerPanel?.orderOut(nil)
        answerPanel?.orderOut(nil)
        model.send(text)
        positionAttachedPanels()
        if let statusPanel { revealWithLift(statusPanel) }
    }

    func showStatus() {
        isComposerVisible = false
        isStatusVisible = true
        composerPanel?.orderOut(nil)
        positionAttachedPanels()
        if let statusPanel, !statusPanel.isVisible {
            revealWithLift(statusPanel)
        } else {
            statusPanel?.orderFrontRegardless()
        }
    }

    func toggleAnswer() {
        guard !model.isGenerating, !model.latestAssistantText.isEmpty else { return }
        if isAnswerVisible {
            isAnswerVisible = false
            answerPanel?.orderOut(nil)
            positionAttachedPanels()
        } else {
            isStatusVisible = true
            isAnswerVisible = true
            answerAttachment = .attached
            positionAttachedPanels()
            statusPanel?.orderFrontRegardless()
            if let answerPanel { revealWithLift(answerPanel) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closeAnswer() {
        isAnswerVisible = false
        answerPanel?.orderOut(nil)
        positionAttachedPanels()
    }

    func confirmCompleted() {
        if model.isGenerating { model.stopGenerating() }
        _ = model.newConversation()
        hideCompactWindow()
    }

    func openCurrentConversationInCodex() {
        guard !codexHandoffInProgress else { return }
        guard !model.isGenerating else {
            model.alertMessage = "请先等待当前回答完成或停止生成，再在 Codex 中继续。"
            return
        }
        guard let threadID = model.selectedSession?.codexThreadID else {
            model.alertMessage = "请先发送一条消息，创建 Codex 任务后再打开。"
            return
        }
        guard let encodedID = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "codex://threads/\(encodedID)") else {
            model.alertMessage = "无法创建 Codex 任务链接。"
            return
        }
        codexHandoffInProgress = true
        model.releaseCurrentConversationForCodex { [weak self] in
            guard let self else { return }
            self.codexHandoffInProgress = false
            guard NSWorkspace.shared.open(url) else {
                self.model.recoverAfterExternalHandoffFailure()
                self.model.alertMessage = "无法打开 Codex。请确认 ChatGPT 桌面应用已安装。"
                return
            }
            self.model.completeExternalHandoff()
            self.hideCompactWindow()
        }
    }

    func showSettings() {
        model.refreshAccount()
        model.refreshConfiguration()
        if settingsWindow == nil {
            let content = SettingsView(model: model, controller: self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 510),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "PinChat 设置"
            window.minSize = NSSize(width: 420, height: 440)
            window.contentViewController = NSHostingController(rootView: content)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func movePet(to pointerLocation: NSPoint) {
        guard let panel = petPanel else { return }
        if petDragOffset == nil {
            isDraggingPet = true
            petDragOffset = NSSize(
                width: pointerLocation.x - panel.frame.minX,
                height: pointerLocation.y - panel.frame.minY
            )
        }
        guard let grabOffset = petDragOffset else { return }
        let requestedOrigin = WindowPlacement.floatingButtonOrigin(
            pointerLocation: pointerLocation,
            grabOffset: grabOffset
        )
        let requested = NSRect(origin: requestedOrigin, size: panel.frame.size)
        let center = NSPoint(x: requested.midX, y: requested.midY)
        guard let visible = (screen(containing: center) ?? NSScreen.main)?.visibleFrame else { return }
        positioningPanels = true
        panel.setFrame(
            WindowPlacement.clamped(requested, to: visible.insetBy(dx: 10, dy: 10)),
            display: true
        )
        positionAttachedPanels()
        positioningPanels = false
    }

    func finishPetDrag() {
        guard let panel = petPanel else { return }
        petDragOffset = nil
        isDraggingPet = false
        saveFrame(panel.frame, key: Keys.petFrame)
        positionAttachedPanels(animated: true)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, !positioningPanels else { return }
        if window === answerPanel {
            answerAttachment = answerAttachment.afterWindowMove(isProgrammatic: false)
            saveFrame(window.frame, key: Keys.answerFrame)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === answerPanel {
            saveFrame(window.frame, key: Keys.answerFrame)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === answerPanel else { return }
        if answerDetached {
            ensureWindowIsOnScreen(window)
        } else {
            positionAttachedPanels(animated: true)
        }
        saveFrame(window.frame, key: Keys.answerFrame)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === answerPanel {
            closeAnswer()
            return false
        }
        return true
    }

    private func createPetPanel() {
        var frame = restoredFrame(key: Keys.petFrame)
            ?? restoredFrame(key: Keys.legacyPetFrameV2)
            ?? migratedPetFrame()
            ?? defaultPetFrame()
        if frame.size != PinChatVisualMetrics.petSize {
            frame = NSRect(
                x: frame.midX - PinChatVisualMetrics.petSize.width / 2,
                y: frame.midY - PinChatVisualMetrics.petSize.height / 2,
                width: PinChatVisualMetrics.petSize.width,
                height: PinChatVisualMetrics.petSize.height
            )
        }
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureFloating(panel, hasShadow: false)
        install(PetRootView(model: model, controller: self), in: panel)
        petPanel = panel
        ensureWindowIsOnScreen(panel)
    }

    private func createComposerPanel() {
        let panel = ChatPanel(
            contentRect: NSRect(origin: .zero, size: PinChatVisualMetrics.composerSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureFloating(panel, hasShadow: false)
        install(MiniComposerView(model: model, controller: self), in: panel)
        composerPanel = panel
    }

    private func createStatusPanel() {
        let panel = ChatPanel(
            contentRect: NSRect(origin: .zero, size: PinChatVisualMetrics.statusSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureFloating(panel, hasShadow: false)
        install(TaskStatusCard(model: model, controller: self), in: panel)
        statusPanel = panel
    }

    private func createAnswerPanel() {
        let restored = restoredFrame(key: Keys.answerFrame)
            ?? NSRect(origin: .zero, size: PinChatVisualMetrics.answerSize)
        let panel = ChatPanel(
            contentRect: restored,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 400, height: 300)
        panel.maxSize = NSSize(width: 900, height: 900)
        configureFloating(panel, hasShadow: true)
        install(AnswerPanelView(model: model, controller: self), in: panel)
        panel.delegate = self
        answerPanel = panel
    }

    private func configureFloating(_ panel: NSPanel, hasShadow: Bool) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = hasShadow
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = PanelPresentationPolicy.crossSpaceBehavior
    }

    private func revealHorizontally(_ panel: NSPanel) {
        let target = panel.frame
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let collapsed = NSRect(
            x: target.midX - 18,
            y: target.minY,
            width: 36,
            height: target.height
        )
        panel.alphaValue = 0
        panel.setFrame(collapsed, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.17
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    private func revealWithLift(_ panel: NSPanel) {
        let target = panel.frame
        guard !panel.isVisible else {
            panel.orderFrontRegardless()
            return
        }
        let preservesAttachment = panel === answerPanel
        if preservesAttachment { positioningPanels = true }
        var start = target
        start.origin.y += expansionDirection == .below ? 10 : -10
        panel.alphaValue = 0
        panel.setFrame(start, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            guard preservesAttachment else { return }
            Task { @MainActor in self?.positioningPanels = false }
        }
    }

    private func install<V: View>(_ rootView: V, in panel: NSPanel) {
        let host = NSHostingController(rootView: rootView)
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = host
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "bubble.left.and.sparkles",
            accessibilityDescription: "PinChat"
        )
        let menu = NSMenu()
        menu.addItem(withTitle: "输入问题", action: #selector(toggleFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "在 Codex 中打开", action: #selector(openCodexFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 PinChat", action: #selector(quitFromMenu), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func registerGlobalHotKey() {
        let hotKey = GlobalHotKey { [weak self] in self?.toggleCompactWindow() }
        globalHotKey = hotKey
        if !hotKey.registerOptionShiftSpace() {
            model.alertMessage = "无法注册 ⌥⇧Space，全局快捷键可能已被其他应用占用。"
        }
    }

    private func updatePanelLevels() {
        let level: NSWindow.Level = alwaysOnTop ? .statusBar : .floating
        [petPanel, composerPanel, statusPanel, answerPanel].forEach { $0?.level = level }
    }

    private func updatePetVisibility() {
        guard let panel = petPanel else { return }
        if floatingButtonEnabled {
            ensureWindowIsOnScreen(panel)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func positionAttachedPanels(animated: Bool = false) {
        guard let petPanel else { return }
        let center = NSPoint(x: petPanel.frame.midX, y: petPanel.frame.midY)
        guard let visible = (screen(containing: center) ?? NSScreen.main)?.visibleFrame else { return }

        var panels: [NSPanel] = []
        var sizes: [NSSize] = []
        if isComposerVisible, let composerPanel {
            panels.append(composerPanel)
            sizes.append(PinChatVisualMetrics.composerSize)
        } else if isStatusVisible, let statusPanel {
            panels.append(statusPanel)
            sizes.append(PinChatVisualMetrics.statusSize)
            if isAnswerVisible, !answerDetached, let answerPanel {
                panels.append(answerPanel)
                sizes.append(answerPanel.frame.size)
            }
        }
        guard !panels.isEmpty else { return }

        let totalHeight = sizes.reduce(0) { $0 + $1.height }
            + PinChatVisualMetrics.attachmentGap * CGFloat(max(0, sizes.count - 1))
        expansionDirection = WindowPlacement.preferredAttachmentDirection(
            anchor: petPanel.frame,
            in: visible,
            requiredHeight: totalHeight,
            gap: PinChatVisualMetrics.attachmentGap
        )
        var attachmentAnchor = petPanel.frame
        if expansionDirection == .below {
            attachmentAnchor.origin.y += PinChatVisualMetrics.launcherOverlap
            attachmentAnchor.size.height -= PinChatVisualMetrics.launcherOverlap
        }
        let frames = WindowPlacement.stackedFrames(
            sizes: sizes,
            attachedTo: attachmentAnchor,
            in: visible,
            direction: expansionDirection,
            gap: PinChatVisualMetrics.attachmentGap
        )

        positioningPanels = true
        for (panel, frame) in zip(panels, frames) {
            panel.setFrame(frame, display: true, animate: animated)
        }
        positioningPanels = false
    }

    private func observeScreenChanges() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                [self.petPanel, self.composerPanel, self.statusPanel, self.answerPanel]
                    .compactMap { $0 }
                    .forEach(self.ensureWindowIsOnScreen)
                self.positionAttachedPanels()
            }
        }
    }

    private func ensureWindowIsOnScreen(_ window: NSWindow) {
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        guard let visible = (screen(containing: center) ?? NSScreen.main)?.visibleFrame else { return }
        let bounds = window === petPanel ? visible.insetBy(dx: 10, dy: 10) : visible
        let frame = WindowPlacement.clamped(window.frame, to: bounds)
        guard frame != window.frame else { return }
        positioningPanels = true
        window.setFrame(frame, display: false)
        positioningPanels = false
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func defaultPetFrame() -> NSRect {
        guard let visible = NSScreen.main?.visibleFrame else {
            return NSRect(origin: .zero, size: PinChatVisualMetrics.petSize)
        }
        return NSRect(
            x: visible.maxX - PinChatVisualMetrics.petSize.width - 28,
            y: visible.midY - PinChatVisualMetrics.petSize.height / 2,
            width: PinChatVisualMetrics.petSize.width,
            height: PinChatVisualMetrics.petSize.height
        )
    }

    private func migratedPetFrame() -> NSRect? {
        guard let legacy = restoredFrame(key: Keys.legacyFloatingButtonFrame) else { return nil }
        return NSRect(
            x: legacy.midX - PinChatVisualMetrics.petSize.width / 2,
            y: legacy.midY - PinChatVisualMetrics.petSize.height / 2,
            width: PinChatVisualMetrics.petSize.width,
            height: PinChatVisualMetrics.petSize.height
        )
    }

    private func restoredFrame(key: String) -> NSRect? {
        guard let string = defaults.string(forKey: key) else { return nil }
        let frame = NSRectFromString(string)
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }

    private func saveFrame(_ frame: NSRect, key: String) {
        defaults.set(NSStringFromRect(frame), forKey: key)
    }

    @objc private func toggleFromMenu() { toggleCompactWindow() }
    @objc private func openCodexFromMenu() { openCurrentConversationInCodex() }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func quitFromMenu() { terminate() }
}
