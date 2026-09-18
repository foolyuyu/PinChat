import Foundation
import UniformTypeIdentifiers

enum PinChatConversationWorkspace {
    static func directoryURL(baseDirectory: URL? = nil) -> URL {
        let root = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("PinChat", isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    static func prepare(baseDirectory: URL? = nil) -> String {
        let url = directoryURL(baseDirectory: baseDirectory)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url.path
    }
}

enum CodexPermissionConfiguration: Equatable, Sendable {
    case serverDefault
    case readOnly
    case askForApproval
    case approveForMe
    case fullAccess
    case profile(String)

    var title: String {
        switch self {
        case .serverDefault: return "Codex 默认设置"
        case .readOnly: return "只读"
        case .askForApproval: return "询问批准"
        case .approveForMe: return "自动审查"
        case .fullAccess: return "完全访问"
        case .profile: return "自定义权限"
        }
    }

    var detail: String {
        switch self {
        case .serverDefault:
            return "由本机 Codex App Server 使用当前默认权限。"
        case .readOnly:
            return "跟随本机 Codex：仅允许读取，执行或修改时由 Codex 决定是否询问。"
        case .askForApproval:
            return "跟随本机 Codex：可在工作区内读写，越界操作会先询问你。"
        case .approveForMe:
            return "跟随本机 Codex：符合条件的越界请求由 Codex 自动审查。"
        case .fullAccess:
            return "跟随本机 Codex：不使用文件与网络沙箱，也不显示普通越界审批。"
        case .profile(let id):
            return "跟随本机 Codex 自定义权限配置：\(id)"
        }
    }

    var approvalPolicy: String? {
        switch self {
        case .serverDefault, .profile: return nil
        case .readOnly: return "on-request"
        case .askForApproval, .approveForMe: return "on-request"
        case .fullAccess: return "never"
        }
    }

    var approvalsReviewer: String? {
        switch self {
        case .serverDefault, .profile: return nil
        case .approveForMe: return "auto_review"
        case .readOnly, .askForApproval, .fullAccess: return "user"
        }
    }

    var sandboxMode: String? {
        switch self {
        case .serverDefault, .profile: return nil
        case .readOnly: return "read-only"
        case .askForApproval, .approveForMe: return "workspace-write"
        case .fullAccess: return "danger-full-access"
        }
    }

    var permissionProfileID: String? {
        guard case .profile(let id) = self else { return nil }
        return id
    }

    func sandboxPolicy(workingDirectory: String) -> [String: Any]? {
        switch self {
        case .serverDefault, .profile:
            return nil
        case .readOnly:
            return ["type": "readOnly", "networkAccess": false]
        case .askForApproval, .approveForMe:
            return [
                "type": "workspaceWrite",
                "writableRoots": [workingDirectory],
                "networkAccess": true,
                "excludeTmpdirEnvVar": false,
                "excludeSlashTmp": false
            ]
        case .fullAccess:
            return ["type": "dangerFullAccess"]
        }
    }
}

enum CodexDesktopPermissionSettings {
    static func readCurrent(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CodexPermissionConfiguration? {
        let url = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent(".codex-global-state.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return configuration(from: data)
    }

    static func configuration(from data: Data) -> CodexPermissionConfiguration? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["electron-persisted-atom-state"] as? [String: Any] else {
            return nil
        }

        if let selection = state["permission-selection-by-host-id:local"] as? [String: Any],
           let kind = selection["kind"] as? String {
            switch kind {
            case "agent-mode":
                if let mode = selection["agentMode"] as? String,
                   let configuration = configuration(agentMode: mode) {
                    return configuration
                }
            case "profile":
                if let profileID = selection["profileId"] as? String, !profileID.isEmpty {
                    return .profile(profileID)
                }
            case "server-default":
                return .serverDefault
            default:
                break
            }
        }

        if let modes = state["agent-mode-by-host-id"] as? [String: Any],
           let mode = modes["local"] as? String {
            return configuration(agentMode: mode)
        }
        return .serverDefault
    }

    private static func configuration(agentMode: String) -> CodexPermissionConfiguration? {
        switch agentMode {
        case "read-only": return .readOnly
        case "auto": return .askForApproval
        case "guardian-approvals": return .approveForMe
        case "full-access": return .fullAccess
        case "custom", "granular": return .serverDefault
        default: return nil
        }
    }
}

enum CodexServerRequestID: Hashable, Sendable {
    case number(Int)
    case string(String)

    init?(jsonValue: Any) {
        if let value = jsonValue as? Int {
            self = .number(value)
        } else if let value = jsonValue as? NSNumber {
            self = .number(value.intValue)
        } else if let value = jsonValue as? String {
            self = .string(value)
        } else {
            return nil
        }
    }

    var jsonValue: Any {
        switch self {
        case .number(let value): return value
        case .string(let value): return value
        }
    }

    var stableValue: String {
        switch self {
        case .number(let value): return "number:\(value)"
        case .string(let value): return "string:\(value)"
        }
    }
}

enum CodexApprovalKind: String, Equatable, Sendable {
    case commandExecution
    case fileChange
    case permissions
}

enum CodexApprovalDecision: Equatable, Sendable {
    case decline
    case allowOnce
    case allowForSession
}

struct CodexApprovalRequest: Identifiable, Equatable, Sendable {
    var requestID: CodexServerRequestID
    var threadID: String
    var turnID: String
    var itemID: String
    var kind: CodexApprovalKind
    var title: String
    var detail: String
    var reason: String?
    var workingDirectory: String?
    var requestedPermissionsData: Data?
    var canAllowForSession: Bool

    var id: String { requestID.stableValue }
}

enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

enum ChatAttachmentKind: String, Codable, Equatable, Sendable {
    case image
    case file
}

struct ChatAttachment: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var path: String
    var displayName: String
    var kind: ChatAttachmentKind

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        path = url.standardizedFileURL.path
        displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let contentType = resourceType ?? UTType(filenameExtension: url.pathExtension)
        kind = contentType?.conforms(to: .image) == true ? .image : .file
    }

    var url: URL { URL(fileURLWithPath: path) }

    static func merging(
        _ existing: [ChatAttachment],
        urls: [URL]
    ) -> [ChatAttachment] {
        var result = existing
        var knownPaths = Set(existing.map(\.path))
        for url in urls where url.isFileURL {
            let attachment = ChatAttachment(url: url)
            guard knownPaths.insert(attachment.path).inserted else { continue }
            result.append(attachment)
        }
        return result
    }
}

enum CodexTaskState: String, Equatable, Sendable {
    case thinking
    case waiting
    case completed
    case stopped
    case failed

    var isInProgress: Bool {
        self == .thinking || self == .waiting
    }
}

enum ConversationTurnPresentation: String, Equatable, Sendable {
    case undetermined
    case conversation
    case work

    func observing(_ event: Event) -> ConversationTurnPresentation {
        switch event {
        case .workActivity:
            return .work
        case .answer:
            return self == .undetermined ? .conversation : self
        }
    }

    enum Event: Equatable, Sendable {
        case answer
        case workActivity
    }
}

struct CodexTaskActivity: Equatable, Sendable {
    var threadID: String
    var title: String
    var state: CodexTaskState
    var updatedAt: Date

    var id: String { threadID }

    var resolvedReceiptID: String? {
        guard state == .completed || state == .stopped else { return nil }
        return "\(threadID)|\(updatedAt.timeIntervalSinceReferenceDate.bitPattern)"
    }
}

enum CodexTaskActivityOrdering {
    static let completedVisibilityDuration: TimeInterval = 30

    static func visible(
        from activities: [CodexTaskActivity],
        limit: Int,
        viewedResolvedReceiptIDs: Set<String> = [],
        acknowledgedResolvedReceiptIDs: Set<String> = [],
        trackedUnviewedThreadIDs: Set<String> = [],
        now: Date = Date()
    ) -> [CodexTaskActivity] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        let unique = activities
            .filter { seen.insert($0.threadID).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }

        let active = unique.filter { $0.state.isInProgress }
        let failures = unique.filter { $0.state == .failed }
        let resolvedReceipts = unique.filter {
            guard let receiptID = $0.resolvedReceiptID else { return false }
            guard !acknowledgedResolvedReceiptIDs.contains(receiptID) else { return false }
            let hasBeenViewed = viewedResolvedReceiptIDs.contains(receiptID)
            let isTrackedAndUnviewed = trackedUnviewedThreadIDs.contains($0.threadID)
                && !hasBeenViewed
            let isWithinMinimumVisibility = now.timeIntervalSince($0.updatedAt)
                <= completedVisibilityDuration
            return isTrackedAndUnviewed || isWithinMinimumVisibility
        }

        // Resolved work stays until it has actually been shown to the user. Once viewed,
        // it remains eligible for at least the normal 30-second completion window.
        return Array((active + Array(failures.prefix(1)) + resolvedReceipts).prefix(limit))
    }
}

enum CodexTaskEventReducer {
    static func state(
        eventTypes: [String],
        serverStatus: String? = nil,
        activeFlags: [String] = []
    ) -> CodexTaskState {
        if serverStatus == "active" {
            return activeFlags.isEmpty ? .thinking : .waiting
        }
        if serverStatus == "systemError" { return .failed }

        for event in eventTypes.reversed() {
            switch event {
            case "task_started": return .thinking
            case "task_complete": return .completed
            case "turn_aborted": return .stopped
            case "turn_failed", "error": return .failed
            default: continue
            }
        }
        return .completed
    }
}

enum CodexComposerCapabilityKind: String, Codable, Hashable, Sendable {
    case skill
    case app
}

struct CodexComposerCapability: Identifiable, Codable, Hashable, Sendable {
    var kind: CodexComposerCapabilityKind
    var name: String
    var summary: String
    var path: String
    var invocationName: String
    var iconPath: String?
    var brandColorHex: String?

    var id: String { "\(kind.rawValue):\(path)" }

    init(
        kind: CodexComposerCapabilityKind,
        name: String,
        summary: String,
        path: String,
        invocationName: String,
        iconPath: String? = nil,
        brandColorHex: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.summary = summary
        self.path = path
        self.invocationName = invocationName
        self.iconPath = iconPath
        self.brandColorHex = brandColorHex
    }
}

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var sourceID: String?
    var role: ChatRole
    var text: String
    var createdAt: Date
    var attachments: [ChatAttachment]?
    var capabilities: [CodexComposerCapability]?

    init(
        id: UUID = UUID(),
        sourceID: String? = nil,
        role: ChatRole,
        text: String,
        createdAt: Date = Date(),
        attachments: [ChatAttachment]? = nil,
        capabilities: [CodexComposerCapability]? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.attachments = attachments
        self.capabilities = capabilities
    }
}

struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var codexThreadID: String?
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        codexThreadID: String? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.codexThreadID = codexThreadID
        self.messages = messages
    }
}

struct ChatAccount: Equatable, Sendable {
    var email: String?
    var plan: String

    var displayPlan: String {
        switch plan.lowercased() {
        case "free": return "Free"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team", "business": return "Business"
        case "enterprise": return "Enterprise"
        default: return plan.capitalized
        }
    }
}

struct CodexConfiguration: Equatable, Sendable {
    var model: String?
    var reasoningEffort: String?
    var personality: String?

    var displayModel: String {
        model ?? "Codex 默认"
    }

    var displayReasoningEffort: String {
        switch reasoningEffort?.lowercased() {
        case "minimal": return "极低"
        case "low": return "低"
        case "medium": return "中"
        case "high": return "高"
        case "xhigh": return "很高"
        case "max": return "最大"
        case "ultra": return "超高"
        case .some(let value): return value
        case .none: return "Codex 默认"
        }
    }

    var displayPersonality: String {
        guard let personality, !personality.isEmpty else { return "Codex 默认" }
        return personality
    }
}

enum ConnectionStatus: Equatable, Sendable {
    case starting
    case signedOut
    case signingIn
    case ready
    case unavailable(String)

    var label: String {
        switch self {
        case .starting: return "正在连接 ChatGPT…"
        case .signedOut: return "需要登录 ChatGPT"
        case .signingIn: return "请在浏览器中完成登录"
        case .ready: return "已连接"
        case .unavailable(let message): return message
        }
    }
}

enum PinChatError: LocalizedError {
    case codexNotFound
    case processStopped
    case invalidResponse
    case server(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "未找到 Codex 组件。请安装 ChatGPT 桌面应用或 Codex CLI。"
        case .processStopped:
            return "本地 ChatGPT 服务已停止，请重新打开应用。"
        case .invalidResponse:
            return "ChatGPT 返回了无法识别的数据。"
        case .server(let message):
            return message
        case .notSignedIn:
            return "请先使用 ChatGPT 账号登录。"
        }
    }
}
