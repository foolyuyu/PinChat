import AppKit
import SwiftUI

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
}

enum PanelPresentationPolicy {
    static let crossSpaceBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary
    ]
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
            updatePanelLevel()
        }
    }
    @Published var floatingButtonEnabled: Bool {
        didSet {
            defaults.set(floatingButtonEnabled, forKey: Keys.floatingButtonEnabled)
            updateFloatingButtonVisibility()
        }
    }

    let model = AppModel()

    private let defaults = UserDefaults.standard
    private var compactPanel: ChatPanel?
    private var floatingButtonPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var globalHotKey: GlobalHotKey?
    private var buttonDragStart: NSPoint?
    private var screenParametersObserver: NSObjectProtocol?

    private enum Keys {
        static let alwaysOnTop = "alwaysOnTop"
        static let floatingButtonEnabled = "floatingButtonEnabled"
        static let compactFrame = "compactFrame"
        static let floatingButtonFrame = "floatingButtonFrame"
        static let hasLaunched = "hasLaunched"
    }

    private override init() {
        if defaults.object(forKey: Keys.alwaysOnTop) == nil {
            alwaysOnTop = true
        } else {
            alwaysOnTop = defaults.bool(forKey: Keys.alwaysOnTop)
        }
        if defaults.object(forKey: Keys.floatingButtonEnabled) == nil {
            floatingButtonEnabled = true
        } else {
            floatingButtonEnabled = defaults.bool(forKey: Keys.floatingButtonEnabled)
        }
        super.init()
    }

    func launch() {
        NSApp.setActivationPolicy(.accessory)
        createCompactPanel()
        createFloatingButtonPanel()
        createStatusItem()
        registerGlobalHotKey()
        observeScreenChanges()
        model.start()

        if defaults.bool(forKey: Keys.hasLaunched) {
            compactPanel?.orderOut(nil)
        } else {
            defaults.set(true, forKey: Keys.hasLaunched)
            showCompactWindow()
        }
        updateFloatingButtonVisibility()
    }

    func terminate() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        NSApp.terminate(nil)
    }

    func toggleCompactWindow() {
        if compactPanel?.isVisible == true {
            hideCompactWindow()
        } else {
            showCompactWindow()
        }
    }

    func showCompactWindow() {
        guard let panel = compactPanel else { return }
        ensureWindowIsOnScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideCompactWindow() {
        compactPanel?.orderOut(nil)
    }

    func openCurrentConversationInCodex() {
        guard let threadID = model.selectedSession?.codexThreadID else {
            model.alertMessage = "请先发送一条消息，创建 Codex 会话后再打开。"
            return
        }
        guard let encodedID = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            model.alertMessage = "无法创建 Codex 会话链接。"
            return
        }
        let deepLink = "codex://threads/\(encodedID)"
        guard let url = URL(string: deepLink) else {
            model.alertMessage = "无法创建 Codex 会话链接。"
            return
        }
        guard NSWorkspace.shared.open(url) else {
            model.alertMessage = "无法打开 Codex。请确认 ChatGPT 桌面应用已安装。"
            return
        }
        hideCompactWindow()
    }

    func showSettings() {
        model.refreshAccount()
        model.refreshConfiguration()
        if settingsWindow == nil {
            let content = SettingsView(model: model, controller: self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "PinChat 设置"
            window.minSize = NSSize(width: 420, height: 420)
            window.contentViewController = NSHostingController(rootView: content)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func moveFloatingButton(translation: CGSize) {
        guard let panel = floatingButtonPanel else { return }
        if buttonDragStart == nil { buttonDragStart = panel.frame.origin }
        guard let start = buttonDragStart else { return }
        var origin = NSPoint(
            x: start.x + translation.width,
            y: start.y - translation.height
        )
        let screen = screen(containing: NSPoint(
            x: origin.x + panel.frame.width / 2,
            y: origin.y + panel.frame.height / 2
        )) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        }
        panel.setFrameOrigin(origin)
    }

    func finishFloatingButtonDrag() {
        guard let panel = floatingButtonPanel else { return }
        buttonDragStart = nil
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let visible = (screen(containing: center) ?? NSScreen.main)?.visibleFrame else { return }
        let frame = WindowPlacement.snappedFloatingButton(panel.frame, to: visible)
        panel.setFrame(frame, display: true, animate: true)
        saveFrame(panel.frame, key: Keys.floatingButtonFrame)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === compactPanel {
            saveFrame(window.frame, key: Keys.compactFrame)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === compactPanel {
            saveFrame(window.frame, key: Keys.compactFrame)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === compactPanel {
            hideCompactWindow()
            return false
        }
        return true
    }

    private func createCompactPanel() {
        let defaultFrame = NSRect(x: 0, y: 0, width: 420, height: 560)
        let frame = restoredFrame(key: Keys.compactFrame) ?? defaultFrame
        let panel = ChatPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 360, height: 440)
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = PanelPresentationPolicy.crossSpaceBehavior
        panel.contentViewController = NSHostingController(
            rootView: CompactChatView(model: model, controller: self)
        )
        panel.delegate = self
        compactPanel = panel
        updatePanelLevel()
        ensureWindowIsOnScreen(panel)
        if restoredFrame(key: Keys.compactFrame) == nil { panel.center() }
    }

    private func createFloatingButtonPanel() {
        let size = NSSize(width: 68, height: 68)
        let fallback = defaultFloatingButtonFrame(size: size)
        let frame = restoredFrame(key: Keys.floatingButtonFrame) ?? fallback
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = PanelPresentationPolicy.crossSpaceBehavior
        panel.contentViewController = NSHostingController(rootView: FloatingButtonView(controller: self))
        floatingButtonPanel = panel
        ensureWindowIsOnScreen(panel)
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "bubble.left.and.sparkles", accessibilityDescription: "PinChat")
        let menu = NSMenu()
        menu.addItem(withTitle: "显示/隐藏小窗", action: #selector(toggleFromMenu), keyEquivalent: "")
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
        if !hotKey.registerOptionSpace() {
            model.alertMessage = "无法注册 ⌥ Space，全局快捷键可能已被其他应用占用。"
        }
    }

    private func updatePanelLevel() {
        compactPanel?.level = alwaysOnTop ? .floating : .normal
    }

    private func updateFloatingButtonVisibility() {
        guard let panel = floatingButtonPanel else { return }
        if floatingButtonEnabled {
            ensureWindowIsOnScreen(panel)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func observeScreenChanges() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let compactPanel = self.compactPanel {
                    self.ensureWindowIsOnScreen(compactPanel)
                }
                if let floatingButtonPanel = self.floatingButtonPanel {
                    self.ensureWindowIsOnScreen(floatingButtonPanel)
                    self.saveFrame(floatingButtonPanel.frame, key: Keys.floatingButtonFrame)
                }
            }
        }
    }

    private func ensureWindowIsOnScreen(_ window: NSWindow) {
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        guard let visible = (screen(containing: center) ?? NSScreen.main)?.visibleFrame else { return }
        let frame = WindowPlacement.clamped(window.frame, to: visible)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: false)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func defaultFloatingButtonFrame(size: NSSize) -> NSRect {
        guard let visible = NSScreen.main?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }
        return NSRect(
            x: visible.maxX - size.width - 8,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
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
