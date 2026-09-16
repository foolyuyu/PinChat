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

enum TaskStatusContext: Equatable, Sendable {
    case conversation
    case desktopActivity
}

enum PetCaretContext: Equatable, Sendable {
    case composer
    case answer
}

enum ConversationSendPresentation: Equatable, Sendable {
    case statusOnly
    case expandedConversation

    static func resolve(
        answerIsVisible: Bool,
        answerWindowIsVisible: Bool
    ) -> ConversationSendPresentation {
        answerIsVisible && answerWindowIsVisible ? .expandedConversation : .statusOnly
    }
}

enum CodexThreadLink {
    static func makeURL(threadID: String) -> URL? {
        guard let encodedID = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "codex://threads/\(encodedID)")
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

    static func shadowContainerFrame(
        around contentFrame: NSRect,
        outset: CGFloat,
        in visibleFrame: NSRect
    ) -> NSRect {
        clamped(contentFrame.insetBy(dx: -outset, dy: -outset), to: visibleFrame)
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
    static let petSize = NSSize(width: 64, height: 64)
    static let petArtworkSize = NSSize(width: 52, height: 56)
    static let composerSurfaceSize = NSSize(width: 334, height: 40)
    static let composerAttachmentSurfaceSize = NSSize(width: 334, height: 78)
    static let composerContentHeight: CGFloat = 40
    static let composerSurfaceOuterInset: CGFloat = 0
    static let composerShadowOutset: CGFloat = 40
    static let composerSize = NSSize(
        width: composerSurfaceSize.width + composerShadowOutset * 2,
        height: composerSurfaceSize.height + composerShadowOutset * 2
    )
    static let composerAttachmentSize = NSSize(
        width: composerAttachmentSurfaceSize.width + composerShadowOutset * 2,
        height: composerAttachmentSurfaceSize.height + composerShadowOutset * 2
    )
    static let composerActionSize: CGFloat = 26
    static let statusSurfaceWidth: CGFloat = 346
    static let statusContentHeight: CGFloat = 58
    static let statusShadowOutset: CGFloat = 40
    static let statusSurfaceSize = NSSize(
        width: statusSurfaceWidth,
        height: statusContentHeight
    )
    static let statusSize = NSSize(
        width: statusSurfaceSize.width + statusShadowOutset * 2,
        height: statusSurfaceSize.height + statusShadowOutset * 2
    )
    static let desktopTaskRowHeight: CGFloat = 46
    static let maximumVisibleDesktopTasks = 5
    static let statusActionSize: CGFloat = 28
    static let answerSize = NSSize(width: 520, height: 420)
    static let answerToolbarActionSize: CGFloat = 24
    static let followUpActionSize: CGFloat = 30
    static let attachmentGap: CGFloat = 3
    static let hoverRevealDelay: TimeInterval = 0.32
    static let hoverDismissDelay: TimeInterval = 0.20

    static func desktopStatusSize(taskCount: Int) -> NSSize {
        let surface = desktopStatusSurfaceSize(taskCount: taskCount)
        return NSSize(
            width: surface.width + statusShadowOutset * 2,
            height: surface.height + statusShadowOutset * 2
        )
    }

    static func desktopStatusSurfaceSize(taskCount: Int) -> NSSize {
        NSSize(
            width: statusSurfaceWidth,
            height: desktopStatusContentHeight(taskCount: taskCount)
        )
    }

    static func desktopStatusContentHeight(taskCount: Int) -> CGFloat {
        let visibleCount = max(1, min(maximumVisibleDesktopTasks, taskCount))
        let dividerHeight = CGFloat(max(0, visibleCount - 1))
        return 10 + desktopTaskRowHeight * CGFloat(visibleCount) + dividerHeight
    }
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
            refreshPetLookDirection()
        }
    }
    @Published private(set) var isComposerVisible = false {
        didSet {
            if !isComposerVisible, activePetCaretContext == .composer {
                activePetCaretContext = nil
                activePetCaretScreenPoint = nil
            }
            refreshPetLookDirection()
        }
    }
    @Published private(set) var isStatusVisible = false
    @Published private(set) var isAnswerVisible = false {
        didSet {
            if !isAnswerVisible, activePetCaretContext == .answer {
                activePetCaretContext = nil
                activePetCaretScreenPoint = nil
            }
            refreshPetLookDirection()
        }
    }
    @Published private(set) var isDraggingPet = false {
        didSet { refreshPetLookDirection() }
    }
    @Published private(set) var petLookDirection: PetLookDirection?
    @Published private(set) var answerAttachment: AnswerAttachmentState = .attached
    @Published private(set) var expansionDirection: AttachmentDirection = .below
    @Published private(set) var statusContext: TaskStatusContext?

    var answerDetached: Bool { answerAttachment == .detached }
    var isDesktopActivityStatus: Bool { statusContext == .desktopActivity }

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
    private var hoverRevealTask: Task<Void, Never>?
    private var hoverDismissTask: Task<Void, Never>?
    private var petHovered = false
    private var statusHovered = false
    private var panelTransitionInProgress = false
    private var composerHasAttachments = false
    private var displayedDesktopReceiptIDs = Set<String>()
    private var activePetCaretContext: PetCaretContext?
    private var activePetCaretScreenPoint: CGPoint?

    private enum Keys {
        static let alwaysOnTop = "alwaysOnTop"
        static let floatingButtonEnabled = "floatingButtonEnabled"
        static let petFrame = "petFrameV22"
        static let legacyPetFrameV21 = "petFrameV21"
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
        model.onTurnPresentationChanged = { [weak self] presentation in
            self?.presentConversationTurn(presentation)
        }
        model.onApprovalRequested = { [weak self] in
            self?.presentApprovalRequest()
        }
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
        commitDisplayedDesktopReceiptsIfNeeded()
        hoverRevealTask?.cancel()
        hoverDismissTask?.cancel()
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        NSApp.terminate(nil)
    }

    func toggleCompactWindow() {
        if isDesktopActivityStatus, isStatusVisible {
            replaceStatusWithComposer()
        } else if isComposerVisible || isStatusVisible || isAnswerVisible {
            hideCompactWindow()
        } else {
            showComposer()
        }
    }

    func showCompactWindow() {
        showComposer()
    }

    func toggleComposer() {
        activatePet()
    }

    func activatePet() {
        guard !isDraggingPet, !panelTransitionInProgress else { return }
        cancelHoverTasks()
        if isComposerVisible {
            hideComposer()
        } else if isStatusVisible, !model.isGenerating, !isAnswerVisible {
            replaceStatusWithComposer()
        } else {
            showComposer()
        }
    }

    func hideCompactWindow() {
        commitDisplayedDesktopReceiptsIfNeeded()
        isComposerVisible = false
        isStatusVisible = false
        isAnswerVisible = false
        statusContext = nil
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
        statusContext = nil
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

    func sendMessage(
        _ text: String,
        attachments: [ChatAttachment] = [],
        capabilities: [CodexComposerCapability] = []
    ) {
        guard model.account != nil else {
            showComposer()
            model.alertMessage = PinChatError.notSignedIn.localizedDescription
            return
        }
        let presentation = ConversationSendPresentation.resolve(
            answerIsVisible: isAnswerVisible,
            answerWindowIsVisible: answerPanel?.isVisible == true
        )
        let keepsExpandedConversation = presentation == .expandedConversation
        isComposerVisible = false
        isAnswerVisible = keepsExpandedConversation
        isStatusVisible = true
        statusContext = .conversation
        composerPanel?.orderOut(nil)
        if !keepsExpandedConversation {
            answerPanel?.orderOut(nil)
        }
        model.send(text, attachments: attachments, capabilities: capabilities)
        positionAttachedPanels()
        if let statusPanel { revealWithLift(statusPanel) }
        if keepsExpandedConversation {
            answerPanel?.orderFrontRegardless()
        }
    }

    func setComposerHasAttachments(_ hasAttachments: Bool) {
        guard composerHasAttachments != hasAttachments else { return }
        composerHasAttachments = hasAttachments
        if isComposerVisible {
            positionAttachedPanels(animated: true)
        }
    }

    func refreshDesktopActivityPanelLayout() {
        guard isDesktopActivityStatus, isStatusVisible else { return }
        positionAttachedPanels(animated: true)
    }

    func captureInteractiveScreenshot(
        completion: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        guard let cacheRoot = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            model.alertMessage = "无法访问 PinChat 截屏缓存。"
            completion(nil)
            return
        }
        let directory = cacheRoot
            .appendingPathComponent("PinChat", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            model.alertMessage = "无法创建截屏缓存：\(error.localizedDescription)"
            completion(nil)
            return
        }

        let output = directory.appendingPathComponent("appshot-\(UUID().uuidString).png")
        Task { @MainActor in
            let captured = await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", output.path]
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus == 0
                        && FileManager.default.fileExists(atPath: output.path)
                } catch {
                    return false
                }
            }.value
            completion(captured ? output : nil)
        }
    }

    func showStatus() {
        isComposerVisible = false
        isStatusVisible = true
        statusContext = .conversation
        composerPanel?.orderOut(nil)
        positionAttachedPanels()
        if let statusPanel, !statusPanel.isVisible {
            revealWithLift(statusPanel)
        } else {
            statusPanel?.orderFrontRegardless()
        }
    }

    private func presentApprovalRequest() {
        isComposerVisible = false
        isStatusVisible = true
        isAnswerVisible = true
        statusContext = .conversation
        answerAttachment = .attached
        composerPanel?.orderOut(nil)
        positionAttachedPanels()
        statusPanel?.orderFrontRegardless()
        if let answerPanel, !answerPanel.isVisible {
            revealWithLift(answerPanel)
        } else {
            answerPanel?.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
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
            statusContext = .conversation
            answerAttachment = .attached
            positionAttachedPanels()
            statusPanel?.orderFrontRegardless()
            if let answerPanel { revealWithLift(answerPanel) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func presentConversationTurn(_ presentation: ConversationTurnPresentation) {
        guard statusContext == .conversation, isStatusVisible else { return }
        switch presentation {
        case .undetermined:
            break
        case .conversation:
            guard !isAnswerVisible else { return }
            isAnswerVisible = true
            answerAttachment = .attached
            positionAttachedPanels()
            statusPanel?.orderFrontRegardless()
            if let answerPanel, !answerPanel.isVisible {
                revealWithLift(answerPanel)
            } else {
                answerPanel?.orderFrontRegardless()
            }
        case .work:
            guard model.pendingApproval == nil else { return }
            guard isAnswerVisible else { return }
            isAnswerVisible = false
            answerPanel?.orderOut(nil)
            positionAttachedPanels(animated: true)
            statusPanel?.orderFrontRegardless()
        }
    }

    func closeAnswer() {
        isAnswerVisible = false
        answerPanel?.orderOut(nil)
        positionAttachedPanels()
    }

    func startNewConversation() {
        guard !model.isGenerating else { return }
        _ = model.newConversation()
        showComposer()
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
        guard let url = CodexThreadLink.makeURL(threadID: threadID) else {
            model.alertMessage = "无法创建 Codex 任务链接。"
            return
        }
        codexHandoffInProgress = true
        model.releaseCurrentConversationForCodex { [weak self] result in
            guard let self else { return }
            self.codexHandoffInProgress = false
            guard case .success = result else {
                self.model.recoverAfterExternalHandoffFailure()
                if case .failure(let error) = result {
                    self.model.alertMessage = "无法准备可续聊的 Codex 任务：\(error.localizedDescription)"
                }
                return
            }
            guard NSWorkspace.shared.open(url) else {
                self.model.recoverAfterExternalHandoffFailure()
                self.model.alertMessage = "无法打开 Codex。请确认 ChatGPT 桌面应用已安装。"
                return
            }
            self.model.completeExternalHandoff()
            self.hideCompactWindow()
        }
    }

    func openDesktopActivityInCodex(_ threadID: String) {
        if model.selectedSession?.codexThreadID == threadID {
            openCurrentConversationInCodex()
            return
        }
        openCodexThread(threadID)
    }

    func openDesktopActivityInCodex() {
        guard let threadID = model.desktopActivity?.threadID else { return }
        openDesktopActivityInCodex(threadID)
    }

    func petHoverChanged(_ hovering: Bool) {
        petHovered = hovering
        if hovering {
            hoverDismissTask?.cancel()
            model.refreshDesktopActivities()
            guard !isDraggingPet,
                  !isComposerVisible,
                  !isAnswerVisible,
                  statusContext != .conversation else { return }
            hoverRevealTask?.cancel()
            hoverRevealTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(PinChatVisualMetrics.hoverRevealDelay))
                guard !Task.isCancelled else { return }
                self?.showDesktopActivityStatusIfNeeded()
            }
        } else {
            hoverRevealTask?.cancel()
            scheduleHoverDismiss()
        }
    }

    func statusHoverChanged(_ hovering: Bool) {
        statusHovered = hovering
        if hovering {
            hoverDismissTask?.cancel()
        } else {
            scheduleHoverDismiss()
        }
    }

    func noteDesktopActivitiesDisplayed(_ activities: [CodexTaskActivity]) {
        guard isDesktopActivityStatus, isStatusVisible else { return }
        displayedDesktopReceiptIDs.formUnion(activities.compactMap(\.resolvedReceiptID))
    }

    func updatePetCaret(
        screenPoint: CGPoint?,
        context: PetCaretContext
    ) {
        if let screenPoint {
            guard caretContextIsVisible(context) else { return }
            activePetCaretContext = context
            activePetCaretScreenPoint = screenPoint
        } else if activePetCaretContext == context {
            activePetCaretContext = nil
            activePetCaretScreenPoint = nil
        }
        refreshPetLookDirection()
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

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func movePet(to pointerLocation: NSPoint) {
        guard let panel = petPanel else { return }
        if petDragOffset == nil {
            cancelHoverTasks()
            if isDesktopActivityStatus {
                commitDisplayedDesktopReceiptsIfNeeded()
                isStatusVisible = false
                statusContext = nil
                statusPanel?.orderOut(nil)
            }
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
            ?? restoredFrame(key: Keys.legacyPetFrameV21)
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

    private func showDesktopActivityStatusIfNeeded() {
        guard petHovered,
              !panelTransitionInProgress,
              !isComposerVisible,
              !isAnswerVisible,
              statusContext != .conversation else { return }
        statusContext = .desktopActivity
        isStatusVisible = true
        positionAttachedPanels()
        if let statusPanel, !statusPanel.isVisible {
            revealWithLift(statusPanel, makeKey: false)
        } else {
            statusPanel?.orderFrontRegardless()
        }
    }

    private func scheduleHoverDismiss() {
        guard isDesktopActivityStatus else { return }
        hoverDismissTask?.cancel()
        hoverDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PinChatVisualMetrics.hoverDismissDelay))
            guard !Task.isCancelled else { return }
            self?.dismissDesktopActivityStatusIfNeeded()
        }
    }

    private func dismissDesktopActivityStatusIfNeeded() {
        guard !petHovered, !statusHovered, isDesktopActivityStatus else { return }
        collapseStatusPanel(completion: nil)
    }

    private func replaceStatusWithComposer() {
        guard isStatusVisible, !panelTransitionInProgress else {
            showComposer()
            return
        }
        collapseStatusPanel { [weak self] in
            guard let self else { return }
            self.isComposerVisible = true
            self.positionAttachedPanels()
            if let composerPanel = self.composerPanel {
                self.revealHorizontally(composerPanel)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func collapseStatusPanel(
        completion: (@MainActor @Sendable () -> Void)?
    ) {
        commitDisplayedDesktopReceiptsIfNeeded()
        guard let panel = statusPanel, panel.isVisible else {
            isStatusVisible = false
            statusContext = nil
            completion?()
            return
        }
        panelTransitionInProgress = true
        isStatusVisible = false
        statusContext = nil
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
        } completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
                panel.setFrame(original, display: false)
                self?.panelTransitionInProgress = false
                completion?()
            }
        }
    }

    private func cancelHoverTasks() {
        hoverRevealTask?.cancel()
        hoverDismissTask?.cancel()
        hoverRevealTask = nil
        hoverDismissTask = nil
    }

    private func commitDisplayedDesktopReceiptsIfNeeded() {
        guard !displayedDesktopReceiptIDs.isEmpty else { return }
        model.markDesktopActivityReceiptsViewed(displayedDesktopReceiptIDs)
        displayedDesktopReceiptIDs.removeAll()
    }

    private func openCodexThread(_ threadID: String) {
        guard let url = CodexThreadLink.makeURL(threadID: threadID),
              NSWorkspace.shared.open(url) else {
            model.alertMessage = "无法打开 Codex 任务。"
            return
        }
    }

    private func revealWithLift(_ panel: NSPanel, makeKey: Bool = true) {
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
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
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

        if isComposerVisible, let composerPanel {
            let surfaceSize = composerHasAttachments
                ? PinChatVisualMetrics.composerAttachmentSurfaceSize
                : PinChatVisualMetrics.composerSurfaceSize
            let shadowOutset = PinChatVisualMetrics.composerShadowOutset
            expansionDirection = WindowPlacement.preferredAttachmentDirection(
                anchor: petPanel.frame,
                in: visible,
                requiredHeight: surfaceSize.height + shadowOutset,
                gap: PinChatVisualMetrics.attachmentGap
            )
            guard let surfaceFrame = WindowPlacement.stackedFrames(
                sizes: [surfaceSize],
                attachedTo: petPanel.frame,
                in: visible,
                direction: expansionDirection,
                gap: PinChatVisualMetrics.attachmentGap
            ).first else { return }
            let panelFrame = WindowPlacement.shadowContainerFrame(
                around: surfaceFrame,
                outset: shadowOutset,
                in: visible
            )
            positioningPanels = true
            composerPanel.setFrame(panelFrame, display: true, animate: animated)
            positioningPanels = false
            return
        }

        guard isStatusVisible, let statusPanel else { return }
        let statusSurfaceSize = isDesktopActivityStatus
            ? PinChatVisualMetrics.desktopStatusSurfaceSize(
                taskCount: model.desktopActivities.count
            )
            : PinChatVisualMetrics.statusSurfaceSize
        var panels: [NSPanel] = [statusPanel]
        var surfaceSizes: [NSSize] = [statusSurfaceSize]
        if isAnswerVisible, !answerDetached, let answerPanel {
            panels.append(answerPanel)
            surfaceSizes.append(answerPanel.frame.size)
        }

        let totalHeight = surfaceSizes.reduce(0) { $0 + $1.height }
            + PinChatVisualMetrics.attachmentGap * CGFloat(max(0, surfaceSizes.count - 1))
            + PinChatVisualMetrics.statusShadowOutset
        expansionDirection = WindowPlacement.preferredAttachmentDirection(
            anchor: petPanel.frame,
            in: visible,
            requiredHeight: totalHeight,
            gap: PinChatVisualMetrics.attachmentGap
        )
        var frames = WindowPlacement.stackedFrames(
            sizes: surfaceSizes,
            attachedTo: petPanel.frame,
            in: visible,
            direction: expansionDirection,
            gap: PinChatVisualMetrics.attachmentGap
        )
        guard !frames.isEmpty else { return }
        frames[0] = WindowPlacement.shadowContainerFrame(
            around: frames[0],
            outset: PinChatVisualMetrics.statusShadowOutset,
            in: visible
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

    private func caretContextIsVisible(_ context: PetCaretContext) -> Bool {
        switch context {
        case .composer: isComposerVisible
        case .answer: isAnswerVisible
        }
    }

    private func refreshPetLookDirection() {
        guard let panel = petPanel,
              floatingButtonEnabled,
              !isDraggingPet,
              let context = activePetCaretContext,
              caretContextIsVisible(context),
              let caretPoint = activePetCaretScreenPoint else {
            petLookDirection = nil
            return
        }
        let direction = PetLookDirection.resolve(
            mascotCenter: CGPoint(x: panel.frame.midX, y: panel.frame.midY),
            target: caretPoint
        )
        if petLookDirection != direction { petLookDirection = direction }
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
