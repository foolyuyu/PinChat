import AppKit
import SwiftUI

struct PetRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    private var animation: PetAnimation {
        PetAnimation.resolve(
            isDragging: controller.isDraggingPet,
            isGenerating: model.isGenerating || model.desktopActivity?.state.isInProgress == true,
            hasError: model.lastTurnError != nil,
            hasAnswer: !model.latestAssistantText.isEmpty
        )
    }

    var body: some View {
        PetSpriteView(store: controller.spriteStore, animation: animation)
            .frame(
                width: PinChatVisualMetrics.petArtworkSize.width,
                height: PinChatVisualMetrics.petArtworkSize.height
            )
            .contentShape(Rectangle())
            .onHover(perform: controller.petHoverChanged)
            .onTapGesture { controller.activatePet() }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in controller.movePet(to: NSEvent.mouseLocation) }
                    .onEnded { _ in controller.finishPetDrag() }
            )
        .frame(
            width: PinChatVisualMetrics.petSize.width,
            height: PinChatVisualMetrics.petSize.height,
            alignment: .center
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("打开 PinChat")
    }
}

struct MiniComposerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.primary.opacity(0.055))
                .frame(
                    width: PinChatVisualMetrics.composerActionSize,
                    height: PinChatVisualMetrics.composerActionSize
                )
                .overlay {
                    Image(systemName: model.account == nil ? "person.crop.circle" : "plus")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .onTapGesture {
                    if model.account == nil { model.signIn() }
                }
                .help(model.account == nil ? "登录 ChatGPT" : "附件将在后续版本提供")

            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1...2)
                .focused($focused)
                .disabled(!model.canSend || model.isGenerating)
                .onSubmit(send)

            if model.account == nil {
                Button("登录") { model.signIn() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            } else if model.isGenerating {
                ActionCircleButton(
                    systemName: "stop.fill",
                    tint: .primary.opacity(0.10),
                    foreground: .primary,
                    help: "停止生成",
                    size: PinChatVisualMetrics.composerActionSize,
                    action: model.stopGenerating
                )
            } else {
                ActionCircleButton(
                    systemName: "arrow.up",
                    tint: Color(red: 0.59, green: 0.74, blue: 1.0),
                    foreground: .white,
                    help: "发送",
                    size: PinChatVisualMetrics.composerActionSize,
                    action: send
                )
                .disabled(!model.canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(!model.canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.62 : 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(4)
        .onAppear { focusSoon() }
        .onChange(of: controller.isComposerVisible) {
            if controller.isComposerVisible { focusSoon() }
        }
        .onExitCommand { controller.hideComposer() }
    }

    private var placeholder: String {
        switch model.connectionStatus {
        case .starting: "正在连接本机 Codex…"
        case .signingIn: "请在浏览器完成登录…"
        case .unavailable: "连接失败，请在设置中重试"
        default: model.account == nil ? "登录后开始提问" : "开始新聊天"
        }
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, model.canSend, !model.isGenerating else { return }
        draft = ""
        controller.sendMessage(text)
    }
}

struct TaskStatusCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    private var showsDesktopActivity: Bool { controller.isDesktopActivityStatus }
    private var desktopState: CodexTaskState? { model.desktopActivity?.state }
    private var isWorking: Bool {
        showsDesktopActivity ? desktopState?.isInProgress == true : model.isGenerating
    }
    private var isFailed: Bool {
        showsDesktopActivity ? desktopState == .stopped : model.lastTurnError != nil
    }
    private var isComplete: Bool {
        showsDesktopActivity
            ? desktopState == .completed
            : !model.isGenerating && !model.latestAssistantText.isEmpty && !isFailed
    }

    var body: some View {
        HStack(spacing: 8) {
            statusGlyph

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDesktopActivity {
                if model.desktopActivity != nil {
                    ActionCircleButton(
                        systemName: "arrow.up.right",
                        tint: .primary.opacity(0.075),
                        foreground: .secondary,
                        help: "在 Codex 中打开",
                        action: controller.openDesktopActivityInCodex
                    )
                }
            } else if model.isGenerating {
                ActionCircleButton(
                    systemName: "stop.fill",
                    tint: .primary.opacity(0.075),
                    foreground: .secondary,
                    help: "停止生成",
                    action: model.stopGenerating
                )
            } else if isFailed {
                ActionCircleButton(
                    systemName: "square.and.pencil",
                    tint: .primary.opacity(0.075),
                    foreground: .primary,
                    help: "重新提问",
                    action: controller.showComposer
                )
                ActionCircleButton(
                    systemName: "checkmark",
                    tint: Color.green.opacity(0.16),
                    foreground: .green,
                    help: "关闭",
                    action: controller.confirmCompleted
                )
            } else if isComplete {
                ActionCircleButton(
                    systemName: "arrow.up.right",
                    tint: .primary.opacity(0.075),
                    foreground: .secondary,
                    help: "在 Codex 中打开",
                    action: controller.openCurrentConversationInCodex
                )
                ActionCircleButton(
                    systemName: "checkmark",
                    tint: Color.green.opacity(0.17),
                    foreground: .green,
                    help: "确认完成",
                    action: controller.confirmCompleted
                )
                ActionCircleButton(
                    systemName: expansionSymbol,
                    tint: .primary.opacity(0.075),
                    foreground: .primary,
                    help: controller.isAnswerVisible ? "折叠回答" : "展开回答",
                    action: controller.toggleAnswer
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.12), radius: 9, y: 4)
        .padding(4)
        .onHover(perform: controller.statusHoverChanged)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isWorking)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        if isWorking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        } else if isFailed {
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 24, height: 24)
                .background(Color.red.opacity(0.12), in: Circle())
        } else {
            Image(systemName: isComplete ? "checkmark" : "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isComplete ? Color.green : Color.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    isComplete ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.11),
                    in: Circle()
                )
        }
    }

    private var title: String {
        if showsDesktopActivity {
            switch desktopState {
            case .thinking: return "正在思考"
            case .waiting: return "等待你的操作"
            case .completed: return "已完成"
            case .stopped: return "已停止"
            case .none: return "Codex 已就绪"
            }
        }
        if model.isGenerating { return "正在处理" }
        if isFailed { return "未能完成" }
        return model.selectedSession?.title ?? "已完成"
    }

    private var detail: String {
        if showsDesktopActivity {
            return model.desktopActivity?.title ?? "在 Codex 中开始任务后会显示在这里"
        }
        if let error = model.lastTurnError { return error }
        if model.isGenerating {
            return model.latestUserText.isEmpty ? "Codex 正在思考…" : model.latestUserText
        }
        return model.latestAssistantText.isEmpty ? "等待回答…" : model.latestAssistantText
    }

    private var expansionSymbol: String {
        if controller.isAnswerVisible {
            return controller.expansionDirection == .below ? "chevron.up" : "chevron.down"
        }
        return controller.expansionDirection == .below ? "chevron.down" : "chevron.up"
    }
}

struct AnswerPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            answerToolbar
            Divider().opacity(0.45)
            ConversationBody(model: model)
            Divider().opacity(0.40)
            followUpComposer
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: controller.isAnswerVisible) {
            if controller.isAnswerVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { focused = true }
            }
        }
    }

    private var answerToolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            Text(model.selectedSession?.title ?? "Codex 回答")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Text(controller.answerDetached ? "自由窗口" : "已吸附")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.055), in: Capsule())
            Spacer()
            ToolbarIcon(systemName: "arrow.up.right", help: "在 Codex 中打开") {
                controller.openCurrentConversationInCodex()
            }
            ToolbarIcon(systemName: "xmark", help: "关闭回答") {
                controller.closeAnswer()
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .contentShape(Rectangle())
    }

    private var followUpComposer: some View {
        HStack(spacing: 10) {
            TextField("继续提问…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .lineLimit(1...4)
                .focused($focused)
                .disabled(model.isGenerating)
                .onSubmit(send)
            if model.isGenerating {
                ActionCircleButton(
                    systemName: "stop.fill",
                    tint: .primary.opacity(0.09),
                    foreground: .primary,
                    help: "停止生成",
                    size: PinChatVisualMetrics.followUpActionSize,
                    action: model.stopGenerating
                )
            } else {
                ActionCircleButton(
                    systemName: "arrow.up",
                    tint: Color.accentColor,
                    foreground: .white,
                    help: "发送追问",
                    size: PinChatVisualMetrics.followUpActionSize,
                    action: send
                )
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.40))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isGenerating else { return }
        draft = ""
        controller.sendMessage(text)
    }
}

private struct ConversationBody: View {
    @ObservedObject var model: AppModel

    private var scrollToken: String {
        let session = model.selectedSession
        return "\(session?.id.uuidString ?? "none")-\(session?.messages.last?.text.count ?? 0)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let session = model.selectedSession, !session.messages.isEmpty {
                        ForEach(session.messages) { message in
                            MessageBubble(message: message).id(message.id)
                        }
                    } else {
                        EmptyConversation()
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 18)
            }
            .onChange(of: scrollToken) {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct EmptyConversation: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 70)
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("有什么可以帮你？")
                .font(.title3.weight(.semibold))
            Text("回答将在这里以 Codex 风格排版显示。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        Group {
            if message.role == .user {
                HStack(alignment: .top) {
                    Spacer(minLength: 44)
                    Text(message.text)
                        .font(.system(size: 14.5))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(
                            Color(nsColor: .controlAccentColor),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
            } else if message.text.isEmpty {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Codex 正在思考…")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }
            } else {
                MarkdownContentView(source: message.text)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActionCircleButton: View {
    let systemName: String
    let tint: Color
    let foreground: Color
    let help: String
    var size: CGFloat = PinChatVisualMetrics.statusActionSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.39, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(tint, in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.34), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ToolbarIcon: View {
    let systemName: String
    let help: String
    var size: CGFloat = PinChatVisualMetrics.answerToolbarActionSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    var body: some View {
        ScrollView {
            Form {
                Section("桌宠与浮窗") {
                    Toggle("窗口保持置顶", isOn: $controller.alwaysOnTop)
                    Toggle("显示常驻 Codex 桌宠", isOn: $controller.floatingButtonEnabled)
                    LabeledContent("全局快捷键") {
                        Text("⌥⇧Space").foregroundStyle(.secondary)
                    }
                    Text("桌宠与浮窗会加入所有桌面空间，并可显示在普通全屏应用上方。关闭桌宠后仍可通过快捷键提问。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("ChatGPT 账号") {
                    if let account = model.account {
                        LabeledContent("计划", value: account.displayPlan)
                        if let email = account.email { LabeledContent("账号", value: email) }
                        Text("登录由本机 Codex 管理；PinChat 不保存密码或 API Key。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.connectionStatus.label).foregroundStyle(.secondary)
                        Button("使用 ChatGPT 登录") { model.signIn() }
                            .disabled(model.connectionStatus == .starting)
                        if case .unavailable = model.connectionStatus {
                            Button("重新连接") { model.retryConnection() }
                        }
                    }
                }

                Section("本机 Codex") {
                    if let configuration = model.codexConfiguration {
                        LabeledContent("模型", value: configuration.displayModel)
                        LabeledContent("推理强度", value: configuration.displayReasoningEffort)
                        LabeledContent("人格", value: configuration.displayPersonality)
                    } else {
                        Text("使用 Codex 当前默认模型、人格和推理设置")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("PinChat 2.0") {
                    Text("点击桌宠旁的铅笔提问；完成卡可展开回答、确认完成，或把同一任务交给 Codex 主应用继续。PinChat 不提供历史任务列表。语音、附件和其他 AI API 为未来候选项。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(8)
        .frame(minWidth: 420, idealWidth: 440, minHeight: 440, idealHeight: 510)
    }
}
