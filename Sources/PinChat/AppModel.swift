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
    @Published private(set) var sessions: [ChatSession]
    @Published var selectedSessionID: UUID?
    @Published private(set) var account: ChatAccount?
    @Published private(set) var codexConfiguration: CodexConfiguration?
    @Published private(set) var connectionStatus: ConnectionStatus = .starting
    @Published private(set) var isGenerating = false
    @Published private(set) var lastTurnError: String?
    @Published private(set) var desktopActivity: CodexTaskActivity?
    @Published var alertMessage: String?

    private let chatService: CodexAppServer
    private let activityService: CodexAppServer
    private let store: SessionStore
    private var activeSessionID: UUID?
    private var activeAssistantMessageID: UUID?
    private var syncTask: Task<Void, Never>?
    private var syncInFlight = false
    private var desktopActivitySyncInFlight = false
    private var externalHandoffLifecycle = CodexExternalHandoffLifecycle()

    var selectedSession: ChatSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

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
        store: SessionStore = SessionStore()
    ) {
        precondition(chatService.purpose == .conversation)
        precondition(activityService.purpose == .desktopActivityObserver)
        self.chatService = chatService
        self.activityService = activityService
        self.store = store
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
            Task { @MainActor in self?.syncLatestDesktopTask() }
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

    func send(_ rawText: String, attachments: [ChatAttachment] = []) {
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
            attachments: attachments.isEmpty ? nil : attachments
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
        isGenerating = true
        sortSessionsKeepingSelection()
        persist()

        chatService.sendMessage(
            text: text,
            attachments: attachments,
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

    func releaseCurrentConversationForCodex(
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let threadID = selectedSession?.codexThreadID else {
            completion()
            return
        }
        externalHandoffLifecycle.beginHandoff()
        connectionStatus = .starting
        chatService.releaseThreadForExternalClient(threadID: threadID) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncInFlight = false
                completion()
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
            self?.syncLatestDesktopTask()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.25))
                guard !Task.isCancelled else { break }
                self?.syncCurrentConversation()
                self?.syncLatestDesktopTask()
            }
        }
    }

    private func syncLatestDesktopTask() {
        guard !desktopActivitySyncInFlight else { return }
        desktopActivitySyncInFlight = true
        activityService.readLatestDesktopTask { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.desktopActivitySyncInFlight = false
                if case .success(let activity) = result {
                    self.desktopActivity = activity
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
        sessions[sessionIndex].messages[messageIndex].sourceID = itemID
        sessions[sessionIndex].messages[messageIndex].text = CodexAppServer.authoritativeAgentText(
            streamedText: sessions[sessionIndex].messages[messageIndex].text,
            completedText: text
        )
        sessions[sessionIndex].updatedAt = Date()
        persist()
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
