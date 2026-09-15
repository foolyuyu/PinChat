@preconcurrency import Foundation
import AppKit

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

    var onLoginCompleted: (@Sendable (Result<Void, Error>) -> Void)?
    var onAccountUpdated: (@Sendable () -> Void)?
    var onAgentDelta: (@Sendable (_ threadID: String, _ delta: String) -> Void)?
    var onTurnCompleted: (@Sendable (_ threadID: String, _ error: String?) -> Void)?
    var onProcessStopped: (@Sendable (_ message: String) -> Void)?

    private let queue = DispatchQueue(label: "app.pinchat.codex-app-server")
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: @Sendable (Result<JSON, Error>) -> Void] = [:]
    private(set) var activeTurn: ActiveTurn?
    private var isInitialized = false

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
                            "name": "pinchat_macos",
                            "title": "PinChat",
                            "version": "0.1.0"
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
                            if let text = item["text"] as? String, !text.isEmpty {
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

    func sendMessage(
        text: String,
        existingThreadID: String?,
        onThreadReady: @escaping @Sendable (String) -> Void,
        onTurnStarted: @escaping @Sendable (ActiveTurn) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        prepareThread(existingThreadID: existingThreadID) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let threadID):
                onThreadReady(threadID)
                self.sendRequest(
                    method: "turn/start",
                    params: [
                        "threadId": threadID,
                        "input": [["type": "text", "text": text]],
                        "turnTrigger": "user"
                    ]
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

    func stop() {
        queue.sync {
            guard let process else { return }
            process.terminationHandler = nil
            if process.isRunning { process.terminate() }
            self.process = nil
            input = nil
            isInitialized = false
            activeTurn = nil
        }
    }

    private func prepareThread(
        existingThreadID: String?,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        if let existingThreadID {
            sendRequest(
                method: "thread/resume",
                params: [
                    "threadId": existingThreadID,
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "excludeTurns": true
                ]
            ) { result in
                completion(result.map { _ in existingThreadID })
            }
            return
        }

        sendRequest(
            method: "thread/start",
            params: [
                "approvalPolicy": "never",
                "sandbox": "read-only",
                "ephemeral": false
            ]
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
        if let id = message["id"] as? Int, let completion = pending.removeValue(forKey: id) {
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
        case "item/agentMessage/delta":
            if let threadID = params["threadId"] as? String,
               let delta = params["delta"] as? String {
                onAgentDelta?(threadID, delta)
            }
        case "turn/completed":
            guard let threadID = params["threadId"] as? String else { return }
            var errorText: String?
            if let turn = params["turn"] as? JSON,
               let error = turn["error"] as? JSON {
                errorText = error["message"] as? String
            }
            activeTurn = nil
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
        callbacks.forEach { $0(.failure(PinChatError.server(message))) }
        onProcessStopped?(message)
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
