@preconcurrency import Foundation
import AppKit

enum CodexAppServerPurpose: String, Equatable, Sendable {
    case conversation
    case desktopActivityObserver

    var staysRunningDuringConversationHandoff: Bool {
        self == .desktopActivityObserver
    }
}

final class CodexAppServer: @unchecked Sendable {
    typealias JSON = [String: Any]

    private struct SendableJSON: @unchecked Sendable {
        let value: JSON
    }

    struct ActiveTurn: Sendable {
        let threadID: String
        let turnID: String
    }

    struct RemoteMessage: Equatable, Sendable {
        let sourceID: String
        let role: ChatRole
        let text: String
    }

    private struct IndexedThread {
        let id: String
        let title: String
        let rolloutPath: String?
        let updatedAt: Date
        let serverStatus: String?
        let activeFlags: [String]
    }

    private struct RolloutSnapshot {
        var offset: UInt64
        var state: CodexTaskState
    }

    var onLoginCompleted: (@Sendable (Result<Void, Error>) -> Void)?
    var onAccountUpdated: (@Sendable () -> Void)?
    var onAgentDelta: (@Sendable (_ threadID: String, _ itemID: String, _ delta: String) -> Void)?
    var onAgentMessageCompleted: (@Sendable (_ threadID: String, _ itemID: String, _ text: String) -> Void)?
    var onWorkActivity: (@Sendable (_ threadID: String, _ itemType: String) -> Void)?
    var onTurnCompleted: (@Sendable (_ threadID: String, _ error: String?) -> Void)?
    var onProcessStopped: (@Sendable (_ message: String) -> Void)?
    var onAppCapabilitiesUpdated: (@Sendable ([CodexComposerCapability]) -> Void)?
    var onApprovalRequested: (@Sendable (CodexApprovalRequest) -> Void)?
    var onApprovalResolved: (@Sendable (CodexServerRequestID) -> Void)?
    var onApprovalsCleared: (@Sendable () -> Void)?

    let purpose: CodexAppServerPurpose

    private let queue: DispatchQueue
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: @Sendable (Result<JSON, Error>) -> Void] = [:]
    private(set) var activeTurn: ActiveTurn?
    private var isInitialized = false
    private var agentMessagePhases: [String: String] = [:]
    private var rolloutSnapshots: [String: RolloutSnapshot] = [:]

    init(purpose: CodexAppServerPurpose = .conversation) {
        self.purpose = purpose
        queue = DispatchQueue(label: "app.pinchat.codex-app-server.\(purpose.rawValue)")
    }

    deinit {
        stop()
    }

    func start(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.process?.isRunning == true, self.isInitialized {
                completion(.success(()))
                return
            }

            guard let executable = Self.findCodexExecutable() else {
                completion(.failure(PinChatError.codexNotFound))
                return
            }

            let process = Process()
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = executable
            process.arguments = ["app-server"]
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let server = self else { return }
                server.queue.async { server.consumeOutput(data) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let server = self else { return }
                server.queue.async { server.consumeError(data) }
            }
            process.terminationHandler = { [weak self] process in
                guard let server = self else { return }
                let status = process.terminationStatus
                server.queue.async { server.handleTermination(status: status) }
            }

            do {
                try process.run()
                self.process = process
                self.input = stdinPipe.fileHandleForWriting
                self.sendRequest(
                    method: "initialize",
                    params: [
                        "clientInfo": [
                            "name": purpose == .conversation
                                ? "pinchat_macos"
                                : "pinchat_activity_observer",
                            "title": purpose == .conversation
                                ? "PinChat"
                                : "PinChat Activity Observer",
                            "version": "0.3.3"
                        ]
                    ]
                ) { result in
                    switch result {
                    case .success:
                        self.sendNotification(method: "initialized", params: [:])
                        self.isInitialized = true
                        completion(.success(()))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func readAccount(completion: @escaping @Sendable (Result<ChatAccount?, Error>) -> Void) {
        sendRequest(method: "account/read", params: ["refreshToken": false]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                guard let account = payload["account"] as? JSON else {
                    completion(.success(nil))
                    return
                }
                guard (account["type"] as? String) == "chatgpt" else {
                    completion(.success(nil))
                    return
                }
                completion(.success(ChatAccount(
                    email: account["email"] as? String,
                    plan: account["planType"] as? String ?? "unknown"
                )))
            }
        }
    }

    func beginChatGPTLogin(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        sendRequest(method: "account/login/start", params: ["type": "chatgpt"]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                guard let value = payload["authUrl"] as? String,
                      let url = URL(string: value) else {
                    completion(.failure(PinChatError.invalidResponse))
                    return
                }
                completion(.success(url))
            }
        }
    }

    func readConfiguration(
        completion: @escaping @Sendable (Result<CodexConfiguration, Error>) -> Void
    ) {
        sendRequest(method: "config/read", params: ["includeLayers": false]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                guard let config = payload["config"] as? JSON else {
                    completion(.failure(PinChatError.invalidResponse))
                    return
                }
                completion(.success(CodexConfiguration(
                    model: config["model"] as? String,
                    reasoningEffort: config["model_reasoning_effort"] as? String,
                    personality: config["personality"] as? String
                )))
            }
        }
    }

    func readMessages(
        threadID: String,
        completion: @escaping @Sendable (Result<[RemoteMessage], Error>) -> Void
    ) {
        sendRequest(
            method: "thread/turns/list",
            params: [
                "threadId": threadID,
                "limit": 100,
                "sortDirection": "asc",
                "itemsView": "full"
            ]
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                guard let turns = payload["data"] as? [JSON] else {
                    completion(.failure(PinChatError.invalidResponse))
                    return
                }
                var messages: [RemoteMessage] = []
                for turn in turns {
                    guard let items = turn["items"] as? [JSON] else { continue }
                    for item in items {
                        guard let type = item["type"] as? String,
                              let sourceID = item["id"] as? String else { continue }
                        switch type {
                        case "userMessage":
                            let content = item["content"] as? [JSON] ?? []
                            let text = content.compactMap { part -> String? in
                                guard (part["type"] as? String) == "text" else { return nil }
                                return part["text"] as? String
                            }.joined(separator: "\n")
                            if !text.isEmpty {
                                messages.append(RemoteMessage(
                                    sourceID: sourceID,
                                    role: .user,
                                    text: text
                                ))
                            }
                        case "agentMessage":
                            let phase = item["phase"] as? String
                            if Self.shouldDisplayAgentMessage(phase: phase),
                               let text = item["text"] as? String,
                               !text.isEmpty {
                                messages.append(RemoteMessage(
                                    sourceID: sourceID,
                                    role: .assistant,
                                    text: text
                                ))
                            }
                        default:
                            continue
                        }
                    }
                }
                completion(.success(messages))
            }
        }
    }

    func readDesktopTasks(
        limit: Int = 5,
        viewedResolvedReceiptIDs: Set<String> = [],
        trackedUnviewedThreadIDs: Set<String> = [],
        completion: @escaping @Sendable (Result<[CodexTaskActivity], Error>) -> Void
    ) {
        sendRequest(
            method: "thread/list",
            params: [
                "limit": 50,
                "sortKey": "recency_at",
                "sortDirection": "desc",
                "archived": false,
                "useStateDbOnly": true
            ]
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                guard let rawThreads = payload["data"] as? [JSON] else {
                    completion(.failure(PinChatError.invalidResponse))
                    return
                }
                let activities = rawThreads.compactMap(Self.indexedThread).map { thread in
                    let state = thread.rolloutPath.map {
                        self.readTaskState(
                            path: $0,
                            serverStatus: thread.serverStatus,
                            activeFlags: thread.activeFlags
                        )
                    } ?? CodexTaskEventReducer.state(
                        eventTypes: [],
                        serverStatus: thread.serverStatus,
                        activeFlags: thread.activeFlags
                    )
                    return CodexTaskActivity(
                        threadID: thread.id,
                        title: thread.title,
                        state: state,
                        updatedAt: thread.updatedAt
                    )
                }
                completion(.success(CodexTaskActivityOrdering.visible(
                    from: activities,
                    limit: limit,
                    viewedResolvedReceiptIDs: viewedResolvedReceiptIDs,
                    trackedUnviewedThreadIDs: trackedUnviewedThreadIDs
                )))
            }
        }
    }

    func readComposerCapabilities(
        cwd: String,
        completion: @escaping @Sendable (Result<[CodexComposerCapability], Error>) -> Void
    ) {
        sendRequest(
            method: "skills/list",
            params: ["cwds": [cwd], "forceReload": false]
        ) { [weak self] skillsResult in
            guard let self else { return }
            let skills: [CodexComposerCapability]
            let skillsError: String?
            switch skillsResult {
            case .success(let payload):
                skills = Self.skillCapabilities(from: payload)
                skillsError = nil
            case .failure(let error):
                skills = []
                skillsError = error.localizedDescription
            }
            self.sendRequest(
                method: "app/installed",
                params: ["forceRefresh": false]
            ) { installedResult in
                let apps: [CodexComposerCapability]
                let appsError: String?
                switch installedResult {
                case .success(let payload):
                    apps = Self.installedAppCapabilities(from: payload)
                    appsError = nil
                case .failure(let error):
                    apps = []
                    appsError = error.localizedDescription
                }
                if !skills.isEmpty || !apps.isEmpty {
                    completion(.success(skills + apps))
                } else if let message = skillsError ?? appsError {
                    completion(.failure(PinChatError.server(message)))
                } else {
                    completion(.success([]))
                }
                self.requestAppDirectoryRefresh()
            }
        }
    }

    private func requestAppDirectoryRefresh() {
        sendRequest(
            method: "app/list",
            params: ["limit": 50, "forceRefetch": false]
        ) { [weak self] result in
            guard let self, case .success(let payload) = result else { return }
            let apps = Self.appCapabilities(from: payload)
            if !apps.isEmpty { self.onAppCapabilitiesUpdated?(apps) }
        }
    }

    static func skillCapabilities(from payload: JSON) -> [CodexComposerCapability] {
        let groups = payload["data"] as? [JSON] ?? []
        var seen = Set<String>()
        return groups.flatMap { $0["skills"] as? [JSON] ?? [] }.compactMap { skill in
            guard skill["enabled"] as? Bool != false,
                  let invocationName = skill["name"] as? String,
                  let path = skill["path"] as? String,
                  seen.insert(path).inserted else { return nil }
            let interface = skill["interface"] as? JSON
            return CodexComposerCapability(
                kind: .skill,
                name: interface?["displayName"] as? String ?? invocationName,
                summary: interface?["shortDescription"] as? String
                    ?? skill["description"] as? String
                    ?? "Codex 技能",
                path: path,
                invocationName: invocationName,
                iconPath: interface?["iconSmall"] as? String,
                brandColorHex: interface?["brandColor"] as? String
            )
        }
    }

    static func appCapabilities(from payload: JSON) -> [CodexComposerCapability] {
        let apps = payload["data"] as? [JSON] ?? []
        return apps.compactMap { app in
            guard app["isAccessible"] as? Bool == true,
                  app["isEnabled"] as? Bool == true,
                  let id = app["id"] as? String,
                  let name = app["name"] as? String else { return nil }
            return CodexComposerCapability(
                kind: .app,
                name: name,
                summary: app["description"] as? String ?? "ChatGPT 应用",
                path: "app://\(id)",
                invocationName: id
            )
        }
    }

    static func installedAppCapabilities(from payload: JSON) -> [CodexComposerCapability] {
        let apps = payload["apps"] as? [JSON] ?? []
        return apps.compactMap { app in
            guard app["enabled"] as? Bool == true,
                  app["callable"] as? Bool == true,
                  let id = app["id"] as? String else { return nil }
            let name = app["runtimeName"] as? String ?? id
            return CodexComposerCapability(
                kind: .app,
                name: name,
                summary: "已连接并可由 Codex 调用",
                path: "app://\(id)",
                invocationName: id
            )
        }
    }

    func sendMessage(
        text: String,
        attachments: [ChatAttachment] = [],
        capabilities: [CodexComposerCapability] = [],
        workingDirectory: String,
        permissionConfiguration: CodexPermissionConfiguration,
        existingThreadID: String?,
        onThreadReady: @escaping @Sendable (String) -> Void,
        onTurnStarted: @escaping @Sendable (ActiveTurn) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        prepareThread(
            existingThreadID: existingThreadID,
            workingDirectory: workingDirectory,
            permissionConfiguration: permissionConfiguration
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let threadID):
                onThreadReady(threadID)
                var turnParameters: JSON = [
                    "threadId": threadID,
                    "input": Self.turnInputItems(
                        text: text,
                        attachments: attachments,
                        capabilities: capabilities
                    ),
                    "cwd": workingDirectory,
                    "turnTrigger": "user"
                ]
                Self.apply(
                    permissionConfiguration,
                    workingDirectory: workingDirectory,
                    toTurnParameters: &turnParameters
                )
                self.sendRequest(
                    method: "turn/start",
                    params: turnParameters
                ) { response in
                    switch response {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let payload):
                        guard let turn = payload["turn"] as? JSON,
                              let turnID = turn["id"] as? String else {
                            completion(.failure(PinChatError.invalidResponse))
                            return
                        }
                        let active = ActiveTurn(threadID: threadID, turnID: turnID)
                        self.queue.async { self.activeTurn = active }
                        onTurnStarted(active)
                        completion(.success(()))
                    }
                }
            }
        }
    }

    static func turnInputItems(
        text: String,
        attachments: [ChatAttachment],
        capabilities: [CodexComposerCapability] = []
    ) -> [JSON] {
        let fileAttachments = attachments.filter { $0.kind == .file }
        let imageAttachments = attachments.filter { $0.kind == .image }
        var prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !fileAttachments.isEmpty {
            let paths = fileAttachments.map { "- \($0.path)" }.joined(separator: "\n")
            let context = "已附加以下由用户选择的本机文件或文件夹，请按需读取：\n\(paths)"
            prompt = prompt.isEmpty ? context : "\(prompt)\n\n\(context)"
        } else if prompt.isEmpty, !imageAttachments.isEmpty {
            prompt = "请查看所附图片。"
        }

        let markers = capabilities.map { "$\($0.invocationName)" }.joined(separator: " ")
        if !markers.isEmpty {
            prompt = prompt.isEmpty ? markers : "\(markers) \(prompt)"
        }

        var items: [JSON] = []
        if !prompt.isEmpty {
            items.append(["type": "text", "text": prompt])
        }
        items.append(contentsOf: imageAttachments.map {
            ["type": "localImage", "path": $0.path]
        })
        items.append(contentsOf: capabilities.map { capability in
            switch capability.kind {
            case .skill:
                return [
                    "type": "skill",
                    "name": capability.invocationName,
                    "path": capability.path
                ]
            case .app:
                return [
                    "type": "mention",
                    "name": capability.name,
                    "path": capability.path
                ]
            }
        })
        return items
    }

    func resolveApproval(
        _ request: CodexApprovalRequest,
        decision: CodexApprovalDecision,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, self.process?.isRunning == true, let input = self.input else {
                completion(.failure(PinChatError.processStopped))
                return
            }
            guard let result = Self.approvalResponse(for: request, decision: decision) else {
                completion(.failure(PinChatError.invalidResponse))
                return
            }
            let message: JSON = ["id": request.requestID.jsonValue, "result": result]
            do {
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(0x0A)
                try input.write(contentsOf: data)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func approvalRequest(
        method: String,
        requestID: CodexServerRequestID,
        params: JSON
    ) -> CodexApprovalRequest? {
        guard let threadID = params["threadId"] as? String,
              let turnID = params["turnId"] as? String,
              let itemID = params["itemId"] as? String else { return nil }

        let reason = params["reason"] as? String
        let cwd = params["cwd"] as? String

        switch method {
        case "item/commandExecution/requestApproval":
            let command = params["command"] as? String
            let kind = params["kind"] as? String
            let decisions = params["availableDecisions"] as? [Any]
            let canAllowForSession = decisions?.contains(where: {
                ($0 as? String) == "acceptForSession"
            }) ?? true
            return CodexApprovalRequest(
                requestID: requestID,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                kind: .commandExecution,
                title: kind == "writeStdin" ? "向终端发送输入" : "运行工作区外操作",
                detail: command ?? reason ?? "Codex 请求执行一项需要额外权限的操作。",
                reason: reason,
                workingDirectory: cwd,
                requestedPermissionsData: nil,
                canAllowForSession: canAllowForSession
            )

        case "item/fileChange/requestApproval":
            let root = params["grantRoot"] as? String
            return CodexApprovalRequest(
                requestID: requestID,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                kind: .fileChange,
                title: "修改工作区外文件",
                detail: root.map { "允许写入：\($0)" }
                    ?? reason
                    ?? "Codex 请求修改当前工作区之外的文件。",
                reason: reason,
                workingDirectory: root ?? cwd,
                requestedPermissionsData: nil,
                canAllowForSession: true
            )

        case "item/permissions/requestApproval":
            guard let permissions = params["permissions"] as? JSON,
                  let data = try? JSONSerialization.data(withJSONObject: permissions) else {
                return nil
            }
            return CodexApprovalRequest(
                requestID: requestID,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                kind: .permissions,
                title: "扩展访问权限",
                detail: permissionSummary(permissions),
                reason: reason,
                workingDirectory: cwd,
                requestedPermissionsData: data,
                canAllowForSession: true
            )

        default:
            return nil
        }
    }

    static func approvalResponse(
        for request: CodexApprovalRequest,
        decision: CodexApprovalDecision
    ) -> JSON? {
        switch request.kind {
        case .commandExecution, .fileChange:
            let value: String
            switch decision {
            case .decline: value = "decline"
            case .allowOnce: value = "accept"
            case .allowForSession:
                value = request.canAllowForSession ? "acceptForSession" : "accept"
            }
            return ["decision": value]

        case .permissions:
            let permissions: JSON
            if decision == .decline {
                permissions = [:]
            } else if let data = request.requestedPermissionsData,
                      let decoded = try? JSONSerialization.jsonObject(with: data) as? JSON {
                permissions = decoded
            } else {
                return nil
            }
            return [
                "permissions": permissions,
                "scope": decision == .allowForSession ? "session" : "turn",
                "strictAutoReview": false
            ]
        }
    }

    private static func permissionSummary(_ permissions: JSON) -> String {
        var parts: [String] = []
        if let fileSystem = permissions["fileSystem"] as? JSON {
            let reads = fileSystem["read"] as? [String] ?? []
            let writes = fileSystem["write"] as? [String] ?? []
            if !reads.isEmpty { parts.append("读取：\(reads.joined(separator: "、"))") }
            if !writes.isEmpty { parts.append("写入：\(writes.joined(separator: "、"))") }
            if let entries = fileSystem["entries"] as? [JSON] {
                let descriptions = entries.compactMap { entry -> String? in
                    guard let access = entry["access"] as? String,
                          let path = entry["path"] as? JSON else { return nil }
                    if let value = path["path"] as? String { return "\(access)：\(value)" }
                    if let value = path["pattern"] as? String { return "\(access)：\(value)" }
                    if let value = path["value"] as? String { return "\(access)：\(value)" }
                    return nil
                }
                parts.append(contentsOf: descriptions)
            }
        }
        if let network = permissions["network"] as? JSON,
           network["enabled"] as? Bool == true {
            parts.append("访问网络")
        }
        return parts.isEmpty ? "Codex 请求临时扩大本轮任务的访问范围。" : parts.joined(separator: "\n")
    }

    func interruptActiveTurn(completion: (@Sendable (Result<Void, Error>) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, let turn = self.activeTurn else {
                completion?(.success(()))
                return
            }
            self.sendRequest(
                method: "turn/interrupt",
                params: ["threadId": turn.threadID, "turnId": turn.turnID]
            ) { result in
                completion?(result.map { _ in () })
            }
        }
    }

    func releaseThreadForExternalClient(
        threadID: String,
        workingDirectory: String,
        permissionConfiguration: CodexPermissionConfiguration,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        // Older PinChat threads were created without a cwd. Resuming with the
        // dedicated workspace repairs their persisted project context before Codex
        // Desktop takes ownership, so the composer remains usable after handoff.
        sendRequest(
            method: "thread/resume",
            params: Self.threadResumeParameters(
                threadID: threadID,
                workingDirectory: workingDirectory,
                permissionConfiguration: permissionConfiguration
            )
        ) { [weak self] resumeResult in
            guard let self else { return }
            guard case .success = resumeResult else {
                completion(resumeResult.map { _ in () })
                return
            }
            self.sendRequest(
                method: "thread/unsubscribe",
                params: ["threadId": threadID]
            ) { [weak self] unsubscribeResult in
                guard let self else { return }
                guard case .success = unsubscribeResult else {
                    completion(unsubscribeResult.map { _ in () })
                    return
                }
                // End the conversation process before launching Codex so the desktop
                // app can take ownership immediately. The activity observer stays alive.
                self.queue.async {
                    self.stopOnQueue()
                    completion(.success(()))
                }
            }
        }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    private func prepareThread(
        existingThreadID: String?,
        workingDirectory: String,
        permissionConfiguration: CodexPermissionConfiguration,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        if let existingThreadID {
            sendRequest(
                method: "thread/resume",
                params: Self.threadResumeParameters(
                    threadID: existingThreadID,
                    workingDirectory: workingDirectory,
                    permissionConfiguration: permissionConfiguration
                )
            ) { result in
                completion(result.map { _ in existingThreadID })
            }
            return
        }

        sendRequest(
            method: "thread/start",
            params: Self.threadStartParameters(
                workingDirectory: workingDirectory,
                permissionConfiguration: permissionConfiguration
            )
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                guard let thread = payload["thread"] as? JSON,
                      let threadID = thread["id"] as? String else {
                    completion(.failure(PinChatError.invalidResponse))
                    return
                }
                completion(.success(threadID))
            }
        }
    }

    static func threadStartParameters(
        workingDirectory: String,
        permissionConfiguration: CodexPermissionConfiguration = .serverDefault
    ) -> JSON {
        var parameters: JSON = [
            "cwd": workingDirectory,
            "ephemeral": false
        ]
        apply(permissionConfiguration, toThreadParameters: &parameters)
        return parameters
    }

    static func threadResumeParameters(
        threadID: String,
        workingDirectory: String,
        permissionConfiguration: CodexPermissionConfiguration = .serverDefault
    ) -> JSON {
        var parameters: JSON = [
            "threadId": threadID,
            "cwd": workingDirectory,
            "excludeTurns": true
        ]
        apply(permissionConfiguration, toThreadParameters: &parameters)
        return parameters
    }

    static func turnStartPermissionParameters(
        workingDirectory: String,
        permissionConfiguration: CodexPermissionConfiguration
    ) -> JSON {
        var parameters: JSON = [:]
        apply(
            permissionConfiguration,
            workingDirectory: workingDirectory,
            toTurnParameters: &parameters
        )
        return parameters
    }

    private static func apply(
        _ permissionConfiguration: CodexPermissionConfiguration,
        toThreadParameters parameters: inout JSON
    ) {
        if let approvalPolicy = permissionConfiguration.approvalPolicy {
            parameters["approvalPolicy"] = approvalPolicy
        }
        if let reviewer = permissionConfiguration.approvalsReviewer {
            parameters["approvalsReviewer"] = reviewer
        }
        if let sandbox = permissionConfiguration.sandboxMode {
            parameters["sandbox"] = sandbox
        }
        if let profileID = permissionConfiguration.permissionProfileID {
            parameters["permissions"] = profileID
        }
    }

    private static func apply(
        _ permissionConfiguration: CodexPermissionConfiguration,
        workingDirectory: String,
        toTurnParameters parameters: inout JSON
    ) {
        if let approvalPolicy = permissionConfiguration.approvalPolicy {
            parameters["approvalPolicy"] = approvalPolicy
        }
        if let reviewer = permissionConfiguration.approvalsReviewer {
            parameters["approvalsReviewer"] = reviewer
        }
        if let sandboxPolicy = permissionConfiguration.sandboxPolicy(
            workingDirectory: workingDirectory
        ) {
            parameters["sandboxPolicy"] = sandboxPolicy
        }
        if let profileID = permissionConfiguration.permissionProfileID {
            parameters["permissions"] = profileID
        }
    }

    private static func indexedThread(_ value: JSON) -> IndexedThread? {
        guard let id = value["id"] as? String,
              value["parentThreadId"] is NSNull || value["parentThreadId"] == nil else {
            return nil
        }
        let originator = value["originator"] as? String
        let source = value["source"] as? String
        guard originator == "Codex Desktop" || source == "vscode" else { return nil }

        let rawTitle = (value["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (value["preview"] as? String)
            ?? "Codex 任务"
        let title = rawTitle
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let timestamp = (value["recencyAt"] as? NSNumber)?.doubleValue
            ?? (value["updatedAt"] as? NSNumber)?.doubleValue
            ?? Date().timeIntervalSince1970
        let status = value["status"] as? JSON
        return IndexedThread(
            id: id,
            title: title.isEmpty ? "Codex 任务" : title,
            rolloutPath: value["path"] as? String,
            updatedAt: Date(timeIntervalSince1970: timestamp),
            serverStatus: status?["type"] as? String,
            activeFlags: status?["activeFlags"] as? [String] ?? []
        )
    }

    private func readTaskState(
        path: String,
        serverStatus: String?,
        activeFlags: [String]
    ) -> CodexTaskState {
        if serverStatus == "active" {
            return CodexTaskEventReducer.state(
                eventTypes: [],
                serverStatus: serverStatus,
                activeFlags: activeFlags
            )
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return .completed }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            if let cached = rolloutSnapshots[path], cached.offset <= end {
                if cached.offset == end { return cached.state }
                let overlap: UInt64 = 96
                let start = cached.offset > overlap ? cached.offset - overlap : 0
                try handle.seek(toOffset: start)
                let appended = try handle.readToEnd() ?? Data()
                let event = Self.lastTaskEvent(in: appended)
                let state = event.map { CodexTaskEventReducer.state(eventTypes: [$0]) }
                    ?? cached.state
                rolloutSnapshots[path] = RolloutSnapshot(offset: end, state: state)
                return state
            }

            let state = Self.scanBackwardsForTaskState(handle: handle, end: end)
            rolloutSnapshots[path] = RolloutSnapshot(offset: end, state: state)
            return state
        } catch {
            return rolloutSnapshots[path]?.state ?? .completed
        }
    }

    private static func scanBackwardsForTaskState(
        handle: FileHandle,
        end: UInt64
    ) -> CodexTaskState {
        let chunkSize: UInt64 = 256 * 1_024
        let overlapLength = 96
        var cursor = end
        var laterPrefix = Data()

        while cursor > 0 {
            let start = cursor > chunkSize ? cursor - chunkSize : 0
            do {
                try handle.seek(toOffset: start)
                guard var chunk = try handle.read(upToCount: Int(cursor - start)) else { break }
                chunk.append(laterPrefix)
                if let event = lastTaskEvent(in: chunk) {
                    return CodexTaskEventReducer.state(eventTypes: [event])
                }
                laterPrefix = chunk.prefix(overlapLength)
                cursor = start
            } catch {
                break
            }
        }
        return .completed
    }

    private static func lastTaskEvent(in data: Data) -> String? {
        let needles = ["task_started", "task_complete", "turn_aborted", "turn_failed", "error"]
        let text = String(decoding: data, as: UTF8.self)
        return needles.compactMap { event -> (String, String.Index)? in
            let marker = "\"type\":\"event_msg\",\"payload\":{\"type\":\"\(event)\""
            guard let range = text.range(of: marker, options: .backwards) else { return nil }
            return (event, range.lowerBound)
        }.max { $0.1 < $1.1 }?.0
    }

    private func sendRequest(
        method: String,
        params: JSON,
        completion: @escaping @Sendable (Result<JSON, Error>) -> Void
    ) {
        let paramsBox = SendableJSON(value: params)
        queue.async { [weak self] in
            guard let self, self.process?.isRunning == true, let input = self.input else {
                completion(.failure(PinChatError.processStopped))
                return
            }
            let id = self.nextRequestID
            self.nextRequestID += 1
            self.pending[id] = completion
            let message: JSON = ["method": method, "id": id, "params": paramsBox.value]
            do {
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(0x0A)
                try input.write(contentsOf: data)
            } catch {
                self.pending.removeValue(forKey: id)
                completion(.failure(error))
            }
        }
    }

    private func sendNotification(method: String, params: JSON) {
        guard process?.isRunning == true, let input else { return }
        let message: JSON = ["method": method, "params": params]
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line),
                  let message = object as? JSON else { continue }
            handleMessage(message)
        }
    }

    private func consumeError(_ data: Data) {
        errorBuffer.append(data)
        if errorBuffer.count > 16_384 {
            errorBuffer.removeFirst(errorBuffer.count - 16_384)
        }
    }

    private func handleMessage(_ message: JSON) {
        if message["method"] == nil,
           let id = (message["id"] as? Int) ?? (message["id"] as? NSNumber)?.intValue,
           let completion = pending.removeValue(forKey: id) {
            if let error = message["error"] as? JSON {
                let text = error["message"] as? String ?? "ChatGPT 服务请求失败"
                completion(.failure(PinChatError.server(text)))
            } else if let result = message["result"] as? JSON {
                completion(.success(result))
            } else {
                completion(.failure(PinChatError.invalidResponse))
            }
            return
        }

        guard let method = message["method"] as? String,
              let params = message["params"] as? JSON else { return }

        if Self.isWorkRequestMethod(method),
           let threadID = params["threadId"] as? String {
            onWorkActivity?(threadID, method)
        }

        if let rawID = message["id"],
           let requestID = CodexServerRequestID(jsonValue: rawID),
           let request = Self.approvalRequest(
               method: method,
               requestID: requestID,
               params: params
           ) {
            onApprovalRequested?(request)
            return
        }

        switch method {
        case "account/login/completed":
            let success = params["success"] as? Bool ?? false
            if success {
                onLoginCompleted?(.success(()))
            } else {
                onLoginCompleted?(.failure(PinChatError.server(
                    params["error"] as? String ?? "登录未完成"
                )))
            }
        case "account/updated":
            onAccountUpdated?()
        case "app/list/updated":
            let apps = Self.appCapabilities(from: params)
            if !apps.isEmpty { onAppCapabilitiesUpdated?(apps) }
        case "serverRequest/resolved":
            if let rawID = params["requestId"],
               let requestID = CodexServerRequestID(jsonValue: rawID) {
                onApprovalResolved?(requestID)
            }
        case "item/started":
            guard let threadID = params["threadId"] as? String,
                  let item = params["item"] as? JSON,
                  let itemType = item["type"] as? String else { return }
            if Self.isWorkItemType(itemType) {
                onWorkActivity?(threadID, itemType)
            }
            guard itemType == "agentMessage",
                  let itemID = item["id"] as? String else { return }
            if let phase = item["phase"] as? String {
                agentMessagePhases[itemID] = phase
            } else {
                agentMessagePhases.removeValue(forKey: itemID)
            }
        case "item/agentMessage/delta":
            if let threadID = params["threadId"] as? String,
               let itemID = params["itemId"] as? String,
               Self.shouldDisplayAgentMessage(phase: agentMessagePhases[itemID]),
               let delta = params["delta"] as? String {
                onAgentDelta?(threadID, itemID, delta)
            }
        case "item/completed":
            guard let threadID = params["threadId"] as? String,
                  let item = params["item"] as? JSON,
                  let itemType = item["type"] as? String else { return }
            if Self.isWorkItemType(itemType) {
                onWorkActivity?(threadID, itemType)
            }
            guard itemType == "agentMessage",
                  let itemID = item["id"] as? String else { return }
            let phase = item["phase"] as? String ?? agentMessagePhases[itemID]
            agentMessagePhases.removeValue(forKey: itemID)
            if Self.shouldDisplayAgentMessage(phase: phase),
               let text = item["text"] as? String,
               !text.isEmpty {
                onAgentMessageCompleted?(threadID, itemID, text)
            }
        case "turn/completed":
            guard let threadID = params["threadId"] as? String else { return }
            var errorText: String?
            if let turn = params["turn"] as? JSON,
               let error = turn["error"] as? JSON {
                errorText = error["message"] as? String
            }
            activeTurn = nil
            agentMessagePhases.removeAll()
            onTurnCompleted?(threadID, errorText)
        case "error":
            guard let threadID = params["threadId"] as? String else { return }
            let willRetry = params["willRetry"] as? Bool ?? false
            if !willRetry {
                let detail = params["error"] as? JSON
                onTurnCompleted?(threadID, detail?["message"] as? String ?? "生成失败")
            }
        default:
            break
        }
    }

    private func handleTermination(status: Int32) {
        let stderr = String(data: errorBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stderr?.isEmpty == false
            ? stderr!
            : "Codex App Server 已退出（状态码 \(status)）"
        let callbacks = pending.values
        pending.removeAll()
        process = nil
        input = nil
        isInitialized = false
        activeTurn = nil
        agentMessagePhases.removeAll()
        callbacks.forEach { $0(.failure(PinChatError.server(message))) }
        onApprovalsCleared?()
        onProcessStopped?(message)
    }

    private func stopOnQueue() {
        guard let process else {
            input = nil
            isInitialized = false
            activeTurn = nil
            agentMessagePhases.removeAll()
            onApprovalsCleared?()
            return
        }
        process.terminationHandler = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        let callbacks = pending.values
        pending.removeAll()
        self.process = nil
        input = nil
        isInitialized = false
        activeTurn = nil
        agentMessagePhases.removeAll()
        callbacks.forEach { $0(.failure(PinChatError.processStopped)) }
        onApprovalsCleared?()
    }

    static func shouldDisplayAgentMessage(phase: String?) -> Bool {
        phase?.lowercased() != "commentary"
    }

    static func isWorkItemType(_ itemType: String) -> Bool {
        [
            "commandExecution",
            "fileChange",
            "mcpToolCall",
            "dynamicToolCall",
            "collabAgentToolCall",
            "subAgentActivity",
            "webSearch",
            "imageView",
            "sleep",
            "imageGeneration"
        ].contains(itemType)
    }

    static func isWorkRequestMethod(_ method: String) -> Bool {
        [
            "item/commandExecution/requestApproval",
            "item/fileChange/requestApproval",
            "item/tool/requestUserInput",
            "item/permissions/requestApproval",
            "item/tool/call",
            "mcpServer/elicitation/request"
        ].contains(method)
    }

    static func authoritativeAgentText(streamedText: String, completedText: String) -> String {
        completedText
    }

    static func findCodexExecutable() -> URL? {
        var candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
