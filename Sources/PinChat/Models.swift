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

struct CodexTaskActivity: Equatable, Sendable {
    var threadID: String
    var title: String
    var state: CodexTaskState
    var updatedAt: Date

    var id: String { threadID }
}

enum CodexTaskActivityOrdering {
    static let completedVisibilityDuration: TimeInterval = 30

    static func visible(
        from activities: [CodexTaskActivity],
        limit: Int,
        now: Date = Date()
    ) -> [CodexTaskActivity] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        let unique = activities
            .filter { seen.insert($0.threadID).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }

        let active = unique.filter { $0.state.isInProgress }
        let failures = unique.filter { $0.state == .failed }
        let recentlyResolved = unique.filter {
            ($0.state == .completed || $0.state == .stopped) &&
            now.timeIntervalSince($0.updatedAt) <= completedVisibilityDuration
        }

        // Active work is the useful persistent signal. A failure remains visible for
        // attention, while completed/stopped work is a short-lived receipt rather than
        // an ever-growing history list.
        return Array((active + failures.prefix(1) + recentlyResolved.prefix(1)).prefix(limit))
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
