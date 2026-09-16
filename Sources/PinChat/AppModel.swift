import AppKit
import Foundation

enum MessageReconciler {
    static func merge(
        remoteMessages: [CodexAppServer.RemoteMessage],
        existing: [ChatMessage]
    ) -> [ChatMessage]? {
        guard !remoteMessages.isEmpty else { return nil }
        // Codex threads are append-only for this surface. Start with the local sequence so
        // an interrupted agent message that App Server omits remains visible, then update
        // known messages or append genuinely new remote items.
        var merged = existing
        for remote in remoteMessages {
            if let knownIndex = merged.firstIndex(where: { $0.sourceID == remote.sourceID }) {
                merged[knownIndex].text = remote.text
                merged[knownIndex].role = remote.role
                continue
            }

            if let localIndex = merged.firstIndex(where: {
                $0.sourceID == nil &&
                $0.role == remote.role &&
                ($0.text == remote.text || (
                    remote.role == .assistant &&
                    !$0.text.isEmpty &&
                    remote.text.hasPrefix($0.text)
                ))
            }) {
                merged[localIndex].sourceID = remote.sourceID
                merged[localIndex].text = remote.text
                continue
            }

            merged.append(ChatMessage(
                sourceID: remote.sourceID,
                role: remote.role,
                text: remote.text
            ))
        }

        return merged == existing ? nil : merged
    }
}

struct CodexExternalHandoffLifecycle: Equatable, Sendable {
    private(set) var chatNeedsRestart = false

    mutating func beginHandoff() {
        chatNeedsRestart = true
    }

    mutating func chatDidStart() {
        chatNeedsRestart = false
    }

    func keepsRunning(_ purpose: CodexAppServerPurpose) -> Bool {
        purpose.staysRunningDuringConversationHandoff
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let viewedDesktopReceiptIDsKey = "viewedDesktopReceiptIDsV1"
    private static let trackedDesktopThreadIDsKey = "trackedDesktopThreadIDsV1"
    private static let maximumRememberedDesktopReceipts = 200

    @Published private(set) var sessions: [ChatSession]
    @Published var selectedSessionID: UUID?
    @Published private(set) var account: ChatAccount?
    @Published private(set) var codexConfiguration: CodexConfiguration?
    @Published private(set) var connectionStatus: ConnectionStatus = .starting
    @Published private(set) var isGenerating = false
    @Published private(set) var turnPresentation: ConversationTurnPresentation = .undetermined
    @Published private(set) var lastTurnError: String?
    @Published private(set) var desktopActivities: [CodexTaskActivity] = []
    @Published private(set) var composerCapabilities: [CodexComposerCapability] = []
    @Published private(set) var isLoadingComposerCapabilities = false
    @Published private(set) var composerCapabilitiesError: String?
    @Published var alertMessage: String?

    var onTurnPresentationChanged: (@MainActor @Sendable (ConversationTurnPresentation) -> Void)?

    private let chatService: CodexAppServer
    private let activityService: CodexAppServer
    private let store: SessionStore
    private let conversationWorkingDirectory: String
    private var activeSessionID: UUID?
    private var activeAssistantMessageID: UUID?
    private var syncTask: Task<Void, Never>?
    private var syncInFlight = false
    private var desktopActivitySyncInFlight = false
    private var composerCapabilitiesSyncInFlight = false
    private var hasLoadedComposerCapabilities = false
    private var externalHandoffLifecycle = CodexExternalHandoffLifecycle()
    private var viewedDesktopReceiptIDs: Set<String> = []
    private var viewedDesktopReceiptOrder: [String] = []
    private var trackedDesktopThreadIDs: Set<String> = []

    var selectedSession: ChatSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var desktopActivity: CodexTaskActivity? { desktopActivities.first }

    var latestUserText: String {
        selectedSession?.messages.last(where: { $0.role == .user })?.text ?? ""
    }

    var latestAssistantText: String {
        selectedSession?.messages.last(where: { $0.role == .assistant })?.text ?? ""
    }

    var hasCurrentConversation: Bool {
        selectedSession?.messages.isEmpty == false
    }

    var canSend: Bool {
        account != nil && connectionStatus == .ready
    }

    init(
        chatService: CodexAppServer = CodexAppServer(purpose: .conversation),
        activityService: CodexAppServer = CodexAppServer(purpose: .desktopActivityObserver),
        store: SessionStore = SessionStore(),
        conversationWorkingDirectory: String? = nil
    ) {
        precondition(chatService.purpose == .conversation)
        precondition(activityService.purpose == .desktopActivityObserver)
        self.chatService = chatService
        self.activityService = activityService
        self.store = store
        self.conversationWorkingDirectory = conversationWorkingDirectory
            ?? PinChatConversationWorkspace.prepare()
        let storedReceiptIDs = UserDefaults.standard.stringArray(
            forKey: Self.viewedDesktopReceiptIDsKey
        ) ?? []
        viewedDesktopReceiptOrder = storedReceiptIDs
        viewedDesktopReceiptIDs = Set(storedReceiptIDs)
        trackedDesktopThreadIDs = Set(
            UserDefaults.standard.stringArray(forKey: Self.trackedDesktopThreadIDsKey) ?? []
        )
        let loaded = store.load().sorted { $0.updatedAt > $1.updatedAt }
        sessions = loaded
        selectedSessionID = loaded.first?.id

        chatService.onLoginCompleted = { [weak self] result in
            Task { @MainActor in self?.handleLoginCompleted(result) }
        }
        chatService.onAccountUpdated = { [weak self] in
            Task { @MainActor in self?.refreshAccount() }
        }
        chatService.onAgentDelta = { [weak self] threadID, itemID, delta in
            Task {
                @MainActor in self?.appendAgentDelta(
                    threadID: threadID,
                    itemID: itemID,
                    delta: delta
                )
            }
        }
        chatService.onAgentMessageCompleted = { [weak self] threadID, itemID, text in
            Task {
                @MainActor in self?.completeAgentMessage(
                    threadID: threadID,
                    itemID: itemID,
                    text: text
                )
            }
        }
        chatService.onWorkActivity = { [weak self] threadID, _ in
            Task { @MainActor in self?.observeWorkActivity(threadID: threadID) }
        }
        chatService.onTurnCompleted = { [weak self] threadID, error in
            Task { @MainActor in self?.finishTurn(threadID: threadID, error: error) }
        }
        chatService.onProcessStopped = { [weak self] message in
            Task { @MainActor in
                self?.connectionStatus = .unavailable("本地服务已停止")
                self?.isGenerating = false
                self?.lastTurnError = message
                self?.alertMessage = message
            }
        }
        activityService.onProcessStopped = { [weak self] _ in
            Task { @MainActor in self?.desktopActivitySyncInFlight = false }
        }
        activityService.onAppCapabilitiesUpdated = { [weak self] apps in
            Task { @MainActor in
                guard let self else { return }
                let skills = self.composerCapabilities.filter { $0.kind == .skill }
                self.composerCapabilities = skills + apps
                self.hasLoadedComposerCapabilities = true
                self.isLoadingComposerCapabilities = false
                self.composerCapabilitiesError = nil
            }
        }
    }

    func start() {
        startSyncLoop()
        startActivityService()
        startChatService()
    }

    private func startChatService() {
        externalHandoffLifecycle.chatDidStart()
        connectionStatus = .starting
        chatService.start { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.connectionStatus = .unavailable(error.localizedDescription)
                case .success:
                    self.refreshAccount()
                    self.refreshConfiguration()
                }
            }
        }
    }

    private func startActivityService() {
        activityService.start { [weak self] result in
            guard case .success = result else { return }
            Task { @MainActor in self?.syncDesktopTasks() }
        }
    }

    deinit {
        syncTask?.cancel()
    }

    func refreshAccount() {
        chatService.readAccount { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let account):
                    self.account = account
                    self.connectionStatus = account == nil ? .signedOut : .ready
                case .failure(let error):
                    self.account = nil
                    self.connectionStatus = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    func signIn() {
        connectionStatus = .signingIn
        chatService.beginChatGPTLogin { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let url):
                    NSWorkspace.shared.open(url)
                case .failure(let error):
                    self.connectionStatus = .signedOut
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func refreshConfiguration() {
        chatService.readConfiguration { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case .success(let configuration) = result {
                    self.codexConfiguration = configuration
                }
            }
        }
    }

    @discardableResult
    func newConversation() -> UUID {
        if isGenerating { stopGenerating() }
        setTurnPresentation(.undetermined)
        lastTurnError = nil
        if let selectedSession,
           selectedSession.codexThreadID == nil,
           selectedSession.messages.isEmpty {
            return selectedSession.id
        }
        sessions.removeAll { $0.codexThreadID == nil && $0.messages.isEmpty }
        let session = ChatSession()
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
        persist()
        return session.id
    }

    func selectSession(_ id: UUID) {
        selectedSessionID = id
    }

    func deleteSessions(at offsets: IndexSet) {
        let ids = offsets.compactMap { sessions.indices.contains($0) ? sessions[$0].id : nil }
        sessions.removeAll { ids.contains($0.id) }
        if let selectedSessionID, ids.contains(selectedSessionID) {
            self.selectedSessionID = sessions.first?.id
        }
        persist()
    }

    func send(
        _ rawText: String,
        attachments: [ChatAttachment] = [],
        capabilities: [CodexComposerCapability] = []
    ) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, !isGenerating else { return }
        guard canSend else {
            if connectionStatus == .starting {
                alertMessage = "正在重新连接本机 Codex，请稍后再发送。"
                return
            }
            alertMessage = PinChatError.notSignedIn.localizedDescription
            return
        }

        lastTurnError = nil

        let sessionID = selectedSessionID ?? newConversation()
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let visibleText = text.isEmpty ? "查看附件" : text
        let userMessage = ChatMessage(
            role: .user,
            text: visibleText,
            attachments: attachments.isEmpty ? nil : attachments,
            capabilities: capabilities.isEmpty ? nil : capabilities
        )
        let assistantMessage = ChatMessage(role: .assistant, text: "")
        sessions[index].messages.append(contentsOf: [userMessage, assistantMessage])
        sessions[index].updatedAt = Date()
        if sessions[index].messages.filter({ $0.role == .user }).count == 1 {
            let titleSource = text.isEmpty
                ? "附件：\(attachments.first?.displayName ?? "新对话")"
                : text
            sessions[index].title = Self.makeTitle(from: titleSource)
        }

        let existingThreadID = sessions[index].codexThreadID
        activeSessionID = sessionID
        activeAssistantMessageID = assistantMessage.id
        setTurnPresentation(.undetermined)
        isGenerating = true
        sortSessionsKeepingSelection()
        persist()

        chatService.sendMessage(
            text: text,
            attachments: attachments,
            capabilities: capabilities,
            workingDirectory: conversationWorkingDirectory,
            existingThreadID: existingThreadID,
            onThreadReady: { [weak self] threadID in
                Task { @MainActor in self?.attach(threadID: threadID, to: sessionID) }
            },
            onTurnStarted: { _ in },
            completion: { [weak self] result in
                if case .failure(let error) = result {
                    Task { @MainActor in self?.failPendingTurn(error.localizedDescription) }
                }
            }
        )
    }

    func stopGenerating() {
        guard isGenerating else { return }
        chatService.interruptActiveTurn { [weak self] result in
            if case .failure(let error) = result {
                Task { @MainActor in self?.alertMessage = error.localizedDescription }
            }
        }
    }

    func retryConnection() {
        start()
    }

    func refreshDesktopActivities() {
        syncDesktopTasks()
    }

    func markDesktopActivityReceiptsViewed(_ receiptIDs: Set<String>) {
        let newReceiptIDs = receiptIDs.subtracting(viewedDesktopReceiptIDs).sorted()
        guard !newReceiptIDs.isEmpty else { return }
        viewedDesktopReceiptIDs.formUnion(newReceiptIDs)
        viewedDesktopReceiptOrder.append(contentsOf: newReceiptIDs)
        let viewedThreadIDs = Set(newReceiptIDs.compactMap { receiptID in
            receiptID.split(separator: "|", maxSplits: 1).first.map(String.init)
        })
        trackedDesktopThreadIDs.subtract(viewedThreadIDs)
        if viewedDesktopReceiptOrder.count > Self.maximumRememberedDesktopReceipts {
            let overflow = viewedDesktopReceiptOrder.count - Self.maximumRememberedDesktopReceipts
            let removed = viewedDesktopReceiptOrder.prefix(overflow)
            viewedDesktopReceiptOrder.removeFirst(overflow)
            viewedDesktopReceiptIDs.subtract(removed)
        }
        UserDefaults.standard.set(
            viewedDesktopReceiptOrder,
            forKey: Self.viewedDesktopReceiptIDsKey
        )
        UserDefaults.standard.set(
            trackedDesktopThreadIDs.sorted(),
            forKey: Self.trackedDesktopThreadIDsKey
        )
        syncDesktopTasks()
    }

    func refreshComposerCapabilities(force: Bool = false) {
        guard !composerCapabilitiesSyncInFlight else { return }
        guard force || !hasLoadedComposerCapabilities else { return }
        composerCapabilitiesSyncInFlight = true
        isLoadingComposerCapabilities = true
        composerCapabilitiesError = nil
        activityService.readComposerCapabilities(
            cwd: FileManager.default.homeDirectoryForCurrentUser.path
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.composerCapabilitiesSyncInFlight = false
                self.isLoadingComposerCapabilities = false
                switch result {
                case .success(let capabilities):
                    self.hasLoadedComposerCapabilities = true
                    self.composerCapabilities = capabilities
                case .failure(let error):
                    self.composerCapabilitiesError = error.localizedDescription
                }
            }
        }
    }

    func releaseCurrentConversationForCodex(
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
    ) {
        guard let threadID = selectedSession?.codexThreadID else {
            completion(.success(()))
            return
        }
        externalHandoffLifecycle.beginHandoff()
        connectionStatus = .starting
        chatService.releaseThreadForExternalClient(
            threadID: threadID,
            workingDirectory: conversationWorkingDirectory
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.syncInFlight = false
                completion(result)
            }
        }
    }

    func completeExternalHandoff() {
        _ = newConversation()
    }

    func recoverAfterExternalHandoffFailure() {
        restartAfterExternalHandoffIfNeeded()
    }

    func restartAfterExternalHandoffIfNeeded() {
        guard externalHandoffLifecycle.chatNeedsRestart else { return }
        startChatService()
    }

    private func handleLoginCompleted(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            refreshAccount()
        case .failure(let error):
            connectionStatus = .signedOut
            alertMessage = error.localizedDescription
        }
    }

    private func attach(threadID: String, to sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].codexThreadID = threadID
        persist()
    }

    private func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            self?.syncDesktopTasks()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.25))
                guard !Task.isCancelled else { break }
                self?.syncCurrentConversation()
                self?.syncDesktopTasks()
            }
        }
    }

    private func syncDesktopTasks() {
        guard !desktopActivitySyncInFlight else { return }
        desktopActivitySyncInFlight = true
        activityService.readDesktopTasks(
            limit: PinChatVisualMetrics.maximumVisibleDesktopTasks,
            viewedResolvedReceiptIDs: viewedDesktopReceiptIDs,
            trackedUnviewedThreadIDs: trackedDesktopThreadIDs
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.desktopActivitySyncInFlight = false
                if case .success(let activities) = result {
                    let trackedBeforeSync = self.trackedDesktopThreadIDs
                    for activity in activities {
                        if activity.state.isInProgress {
                            self.trackedDesktopThreadIDs.insert(activity.threadID)
                        } else if let receiptID = activity.resolvedReceiptID,
                                  !self.viewedDesktopReceiptIDs.contains(receiptID) {
                            self.trackedDesktopThreadIDs.insert(activity.threadID)
                        }
                    }
                    if self.trackedDesktopThreadIDs != trackedBeforeSync {
                        UserDefaults.standard.set(
                            self.trackedDesktopThreadIDs.sorted(),
                            forKey: Self.trackedDesktopThreadIDsKey
                        )
                    }
                    self.desktopActivities = activities
                }
            }
        }
    }

    private func syncCurrentConversation() {
        guard !isGenerating,
              !syncInFlight,
              let session = selectedSession,
              let threadID = session.codexThreadID else { return }
        syncInFlight = true
        chatService.readMessages(threadID: threadID) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.syncInFlight = false
                guard case .success(let remoteMessages) = result,
                      !self.isGenerating,
                      let index = self.sessions.firstIndex(where: { $0.codexThreadID == threadID })
                else { return }
                self.mergeRemoteMessages(remoteMessages, into: index)
            }
        }
    }

    private func mergeRemoteMessages(
        _ remoteMessages: [CodexAppServer.RemoteMessage],
        into sessionIndex: Int
    ) {
        let existing = sessions[sessionIndex].messages
        guard let merged = MessageReconciler.merge(
            remoteMessages: remoteMessages,
            existing: existing
        ) else { return }
        sessions[sessionIndex].messages = merged
        sessions[sessionIndex].updatedAt = Date()
        persist()
    }

    private func appendAgentDelta(threadID: String, itemID: String, delta: String) {
        guard isGenerating,
              let sessionID = activeSessionID,
              let messageID = activeAssistantMessageID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[sessionIndex].codexThreadID == threadID,
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        observeTurnEvent(.answer)
        if let sourceID = sessions[sessionIndex].messages[messageIndex].sourceID,
           sourceID != itemID {
            return
        }
        sessions[sessionIndex].messages[messageIndex].sourceID = itemID
        sessions[sessionIndex].messages[messageIndex].text += delta
        sessions[sessionIndex].updatedAt = Date()
    }

    private func completeAgentMessage(threadID: String, itemID: String, text: String) {
        guard isGenerating,
              let sessionID = activeSessionID,
              let messageID = activeAssistantMessageID,
              let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[sessionIndex].codexThreadID == threadID,
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        observeTurnEvent(.answer)
        sessions[sessionIndex].messages[messageIndex].sourceID = itemID
        sessions[sessionIndex].messages[messageIndex].text = CodexAppServer.authoritativeAgentText(
            streamedText: sessions[sessionIndex].messages[messageIndex].text,
            completedText: text
        )
        sessions[sessionIndex].updatedAt = Date()
        persist()
    }

    private func observeWorkActivity(threadID: String) {
        guard isGenerating,
              let sessionID = activeSessionID,
              let session = sessions.first(where: { $0.id == sessionID }),
              session.codexThreadID == nil || session.codexThreadID == threadID
        else { return }
        observeTurnEvent(.workActivity)
    }

    private func observeTurnEvent(_ event: ConversationTurnPresentation.Event) {
        setTurnPresentation(turnPresentation.observing(event))
    }

    private func setTurnPresentation(_ presentation: ConversationTurnPresentation) {
        guard turnPresentation != presentation else { return }
        turnPresentation = presentation
        onTurnPresentationChanged?(presentation)
    }

    private func finishTurn(threadID: String, error: String?) {
        guard let sessionID = activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].codexThreadID == threadID else { return }

        isGenerating = false
        activeSessionID = nil
        activeAssistantMessageID = nil
        if let error {
            lastTurnError = error
            alertMessage = error
            removeEmptyAssistantMessage(in: index)
        } else {
            lastTurnError = nil
        }
        persist()
    }

    private func failPendingTurn(_ message: String) {
        if let sessionID = activeSessionID,
           let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            removeEmptyAssistantMessage(in: index)
        }
        isGenerating = false
        activeSessionID = nil
        activeAssistantMessageID = nil
        lastTurnError = message
        alertMessage = message
        persist()
    }

    private func removeEmptyAssistantMessage(in sessionIndex: Int) {
        guard let messageID = activeAssistantMessageID,
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }),
              sessions[sessionIndex].messages[messageIndex].text.isEmpty else { return }
        sessions[sessionIndex].messages.remove(at: messageIndex)
    }

    private func sortSessionsKeepingSelection() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        do {
            try store.save(sessions)
        } catch {
            alertMessage = "无法保存对话记录：\(error.localizedDescription)"
        }
    }

    private static func makeTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 24 { return trimmed }
        return String(trimmed.prefix(24)) + "…"
    }
}
