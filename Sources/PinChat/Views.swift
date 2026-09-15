import AppKit
import SwiftUI

struct CompactChatView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    var body: some View {
        ChatSurface(model: model, controller: controller, compact: true)
            .frame(minWidth: 360, minHeight: 440)
            .background(.regularMaterial)
            .alert(
                "PinChat",
                isPresented: Binding(
                    get: { model.alertMessage != nil },
                    set: { if !$0 { model.alertMessage = nil } }
                ),
                actions: { Button("好") { model.alertMessage = nil } },
                message: { Text(model.alertMessage ?? "") }
            )
    }
}

private struct ChatSurface: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController
    let compact: Bool

    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CompactToolbar(model: model, controller: controller)

            ConversationBody(model: model)

            Composer(
                draft: $draft,
                isFocused: $composerFocused,
                isGenerating: model.isGenerating,
                canSend: model.account != nil,
                send: send,
                stop: model.stopGenerating
            )
            .padding(.horizontal, compact ? 16 : 24)
            .padding(.bottom, compact ? 16 : 22)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            if compact {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    composerFocused = true
                }
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        model.send(text)
    }
}

private struct CompactToolbar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    var body: some View {
        HStack(spacing: 12) {
            ToolbarIcon(systemName: "minus", help: "收起小窗") {
                controller.hideCompactWindow()
            }
            ToolbarIcon(
                systemName: controller.alwaysOnTop ? "pin.fill" : "pin",
                help: controller.alwaysOnTop ? "取消置顶" : "置顶"
            ) {
                controller.alwaysOnTop.toggle()
            }
            .foregroundStyle(controller.alwaysOnTop ? Color.accentColor : Color.primary)

            Spacer()

            AccountDot(model: model)
            ToolbarIcon(systemName: "square.and.pencil", help: "新建对话") {
                model.newConversation()
            }
            ToolbarIcon(systemName: "macwindow.on.rectangle", help: "在 Codex 中打开") {
                controller.openCurrentConversationInCodex()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }
}

private struct AccountDot: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let account = model.account {
                Text(account.displayPlan)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.14), in: Capsule())
                    .foregroundStyle(.green)
                    .help(account.email ?? "已登录 ChatGPT")
            } else if model.connectionStatus == .starting {
                ProgressView()
                    .controlSize(.small)
            }
        }
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
                VStack(alignment: .leading, spacing: 20) {
                    if model.account == nil {
                        LoginPrompt(model: model)
                    } else if let session = model.selectedSession, !session.messages.isEmpty {
                        ForEach(session.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    } else {
                        EmptyConversation()
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
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

private struct LoginPrompt: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 50)
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("使用你的 ChatGPT 账号")
                .font(.headline)
            Text("通过官方登录使用 Free、Plus 或 Pro 计划额度，无需 API Key。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            switch model.connectionStatus {
            case .starting:
                ProgressView("正在连接…")
            case .signingIn:
                ProgressView("等待浏览器登录完成…")
                Button("重新打开登录页面") { model.signIn() }
                    .buttonStyle(.link)
            case .unavailable:
                Button("重新连接") { model.retryConnection() }
                    .buttonStyle(.borderedProminent)
                Text(model.connectionStatus.label)
                    .font(.caption)
                    .foregroundStyle(.red)
            default:
                Button("使用 ChatGPT 登录") { model.signIn() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EmptyConversation: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 80)
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("有什么可以帮你？")
                .font(.title3.weight(.semibold))
            Text("直接输入问题，回答会在这里流式显示。")
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
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(
                            Color.primary.opacity(0.065),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
            } else {
                if message.text.isEmpty {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("正在思考…")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    MarkdownContentView(source: message.text)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Composer: View {
    @Binding var draft: String
    let isFocused: FocusState<Bool>.Binding
    let isGenerating: Bool
    let canSend: Bool
    let send: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                canSend ? "询问任何问题…" : "登录后开始对话",
                text: $draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .focused(isFocused)
            .disabled(!canSend || isGenerating)
            .onSubmit(send)

            HStack {
                Label("本机 Codex", systemImage: "sparkles")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("使用 Codex 当前模型、人格和推理设置")
                Spacer()
                if isGenerating {
                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .help("停止生成")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("发送")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.84),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        }
        .shadow(color: .black.opacity(0.055), radius: 12, y: 4)
    }
}

private struct ToolbarIcon: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct FloatingButtonView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.34))
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .onTapGesture { controller.toggleCompactWindow() }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { controller.moveFloatingButton(translation: $0.translation) }
                .onEnded { _ in controller.finishFloatingButtonDrag() }
        )
        .padding(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("显示或隐藏 PinChat")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.toggleCompactWindow() }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    var body: some View {
        ScrollView {
            Form {
                Section("小窗") {
                Toggle("默认置顶", isOn: $controller.alwaysOnTop)
                Toggle("显示常驻悬浮按钮", isOn: $controller.floatingButtonEnabled)
                LabeledContent("全局快捷键") {
                    Text("⌥ Space")
                        .foregroundStyle(.secondary)
                }
                Text("小窗和悬浮按钮会加入所有桌面空间，并可显示在普通全屏应用上方。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

                Section("ChatGPT 账号") {
                if let account = model.account {
                    LabeledContent("计划", value: account.displayPlan)
                    if let email = account.email {
                        LabeledContent("账号", value: email)
                    }
                    Text("登录由本机 Codex 管理；PinChat 不会单独保存或退出该账号。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.connectionStatus.label)
                        .foregroundStyle(.secondary)
                    Button("使用 ChatGPT 登录") { model.signIn() }
                        .disabled(model.connectionStatus == .starting)
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

                Section("初版说明") {
                Text("PinChat 是 Codex 的轻量置顶伴随组件，没有独立主页面。右上角按钮会在 Codex 中打开当前会话。其他 AI API、附件和语音将在后续版本中考虑。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(8)
        .frame(minWidth: 420, idealWidth: 440, minHeight: 420, idealHeight: 500)
    }
}
