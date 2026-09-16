import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct BehindWindowGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var opacity: CGFloat = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.material = material
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.material = material
        view.alphaValue = opacity
    }
}

private struct CompactFloatingSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(
                        Color.white.opacity(colorScheme == .dark ? 0.06 : 0.12)
                    ),
                    in: shape
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.045),
                    radius: 1.5,
                    y: 1
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16),
                    radius: 7,
                    y: 3.5
                )
        } else {
            content
                .background {
                    ZStack {
                        BehindWindowGlass()
                            .clipShape(shape)
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.10),
                                    Color.white.opacity(colorScheme == .dark ? 0.035 : 0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.40 : 0.66),
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18),
                                Color.black.opacity(colorScheme == .dark ? 0.12 : 0.045)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.045),
                    radius: 1.5,
                    y: 1
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16),
                    radius: 7,
                    y: 3.5
                )
        }
    }
}

private extension View {
    func compactFloatingSurface(cornerRadius: CGFloat) -> some View {
        modifier(CompactFloatingSurface(cornerRadius: cornerRadius))
    }
}

private struct CaretScreenPositionReader: NSViewRepresentable {
    let onChange: (CGPoint?) -> Void

    func makeNSView(context: Context) -> CaretObserverView {
        let view = CaretObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: CaretObserverView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: CaretObserverView, coordinator: Void) {
        view.stopObserving()
        view.report(nil)
    }
}

private final class CaretObserverView: NSView {
    var onChange: ((CGPoint?) -> Void)?
    private var timer: Timer?
    private var lastPoint: CGPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopObserving()
            report(nil)
        } else {
            startObserving()
        }
    }

    func stopObserving() {
        timer?.invalidate()
        timer = nil
    }

    func report(_ point: CGPoint?) {
        guard point != lastPoint else { return }
        lastPoint = point
        onChange?(point)
    }

    private func startObserving() {
        guard timer == nil else { return }
        let interval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? 0.10
            : 1.0 / 30.0
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(sampleCaret),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sampleCaret()
    }

    @objc private func sampleCaret() {
        guard let window,
              window.isVisible,
              window.isKeyWindow,
              let editor = activeTextEditor(in: window) else {
            report(nil)
            return
        }
        let selection = editor.selectedRange()
        let rect = editor.firstRect(
            forCharacterRange: NSRange(location: selection.location, length: 0),
            actualRange: nil
        )
        guard rect.height > 0,
              rect.midX.isFinite,
              rect.midY.isFinite else {
            report(nil)
            return
        }
        report(CGPoint(x: rect.midX, y: rect.midY))
    }

    private func activeTextEditor(in window: NSWindow) -> NSTextView? {
        if let editor = window.firstResponder as? NSTextView { return editor }
        if let field = window.firstResponder as? NSTextField {
            return field.currentEditor() as? NSTextView
        }
        return nil
    }
}

struct PetRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    private var animation: PetAnimation {
        PetAnimation.resolve(
            isDragging: controller.isDraggingPet,
            isGenerating: model.isGenerating
                || model.desktopActivities.contains(where: { $0.state.isInProgress }),
            hasError: model.lastTurnError != nil,
            hasAnswer: !model.latestAssistantText.isEmpty
        )
    }

    var body: some View {
        PetSpriteView(
            store: controller.spriteStore,
            animation: animation,
            lookDirection: animation.allowsDirectionalPose
                ? controller.petLookDirection
                : nil
        )
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
    @State private var attachments: [ChatAttachment] = []
    @State private var showsAttachmentMenu = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                supplementaryStrip
            }

            HStack(spacing: 7) {
                attachmentMenu
                permissionMenu

                TextField(placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1...2)
                    .focused($focused)
                    .disabled(!model.canSend || model.isGenerating)
                    .onSubmit(send)
                    .background {
                        CaretScreenPositionReader { point in
                            controller.updatePetCaret(
                                screenPoint: point,
                                context: .composer
                            )
                        }
                    }

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
                        tint: canSubmit
                            ? Color(red: 0.18, green: 0.47, blue: 1.0)
                            : Color(red: 0.59, green: 0.74, blue: 1.0),
                        foreground: .white,
                        help: "发送",
                        size: PinChatVisualMetrics.composerActionSize,
                        action: send
                    )
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.62)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: PinChatVisualMetrics.composerContentHeight)
        }
        .frame(width: PinChatVisualMetrics.composerSurfaceSize.width)
        .compactFloatingSurface(cornerRadius: 20)
        .padding(PinChatVisualMetrics.composerSurfaceOuterInset)
        .padding(PinChatVisualMetrics.composerShadowOutset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusSoon() }
        .onChange(of: controller.isComposerVisible) {
            if controller.isComposerVisible { focusSoon() }
        }
        .onChange(of: attachments.isEmpty) {
            updateComposerHeight()
        }
        .onExitCommand { controller.hideComposer() }
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(PinChatPermissionMode.allCases) { mode in
                Button {
                    model.permissionMode = mode
                } label: {
                    Label {
                        Text(mode.title)
                    } icon: {
                        Image(systemName: model.permissionMode == mode
                            ? "checkmark"
                            : mode.systemImage)
                    }
                }
            }
        } label: {
            composerLeadingIcon(systemName: model.permissionMode.systemImage)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("权限：\(model.permissionMode.title)")
        .accessibilityLabel("Codex 权限：\(model.permissionMode.title)")
    }

    @ViewBuilder
    private var attachmentMenu: some View {
        if model.account == nil {
            Button(action: model.signIn) {
                composerLeadingIcon(systemName: "person.crop.circle")
            }
            .buttonStyle(.plain)
            .help("登录 ChatGPT")
        } else {
            Button {
                showsAttachmentMenu.toggle()
            } label: {
                composerLeadingIcon(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("添加附件")
            .accessibilityLabel("添加附件")
            .popover(isPresented: $showsAttachmentMenu, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    attachmentAction("添加文件和文件夹…", systemName: "doc.badge.plus") {
                        showsAttachmentMenu = false
                        chooseAttachments(photosOnly: false)
                    }
                    attachmentAction("添加照片…", systemName: "photo.on.rectangle") {
                        showsAttachmentMenu = false
                        chooseAttachments(photosOnly: true)
                    }
                    attachmentAction("截屏…", systemName: "camera.viewfinder") {
                        showsAttachmentMenu = false
                        controller.captureInteractiveScreenshot { url in
                            if let url { addAttachments([url]) }
                        }
                    }
                }
                .padding(7)
                .frame(width: 260)
            }
        }
    }

    private func attachmentAction(
        _ title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .frame(height: 31)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func composerLeadingIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.primary)
            .frame(
                width: PinChatVisualMetrics.composerActionSize,
                height: PinChatVisualMetrics.composerActionSize
            )
            .background(Color.primary.opacity(0.055), in: Circle())
    }

    private var supplementaryStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 5) {
                        Image(systemName: attachment.kind == .image ? "photo" : "doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(attachment.displayName)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除 \(attachment.displayName)")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.primary.opacity(0.055), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden)
        .frame(height: 38)
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

    private var canSubmit: Bool {
        model.canSend && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    private func updateComposerHeight() {
        controller.setComposerHasAttachments(!attachments.isEmpty)
    }

    private func chooseAttachments(photosOnly: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = !photosOnly
        panel.resolvesAliases = true
        panel.prompt = "添加"
        panel.message = photosOnly ? "选择要发送给 Codex 的照片" : "选择要提供给 Codex 的文件或文件夹"
        if photosOnly {
            panel.allowedContentTypes = [.image]
        }
        panel.begin { response in
            guard response == .OK else { return }
            addAttachments(panel.urls)
        }
    }

    private func addAttachments(_ urls: [URL]) {
        let knownPaths = Set(attachments.map(\.path))
        let additions = urls
            .map { ChatAttachment(url: $0) }
            .filter { !knownPaths.contains($0.path) }
        attachments.append(contentsOf: additions)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit, !model.isGenerating else { return }
        let selectedAttachments = attachments
        draft = ""
        attachments = []
        controller.sendMessage(
            text,
            attachments: selectedAttachments
        )
    }
}

struct TaskStatusCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    private var showsDesktopActivity: Bool { controller.isDesktopActivityStatus }
    private var desktopTasks: [CodexTaskActivity] {
        Array(model.desktopActivities.prefix(PinChatVisualMetrics.maximumVisibleDesktopTasks))
    }
    private var isFailed: Bool { model.lastTurnError != nil }
    private var isComplete: Bool {
        !model.isGenerating && !model.latestAssistantText.isEmpty && !isFailed
    }

    var body: some View {
        Group {
            if showsDesktopActivity {
                desktopTaskList
            } else {
                conversationStatus
            }
        }
        .frame(width: PinChatVisualMetrics.statusSurfaceWidth)
        .frame(
            height: showsDesktopActivity
                ? PinChatVisualMetrics.desktopStatusContentHeight(taskCount: desktopTasks.count)
                : PinChatVisualMetrics.statusContentHeight
        )
        .compactFloatingSurface(cornerRadius: 18)
        .onHover(perform: controller.statusHoverChanged)
        .padding(PinChatVisualMetrics.statusShadowOutset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { noteDisplayedTasksIfNeeded() }
        .onChange(of: controller.statusContext) {
            noteDisplayedTasksIfNeeded()
        }
        .onChange(of: model.desktopActivities) {
            controller.refreshDesktopActivityPanelLayout()
            noteDisplayedTasksIfNeeded()
        }
        .animation(
            .spring(response: 0.34, dampingFraction: 0.82),
            value: model.desktopActivities
        )
    }

    private func noteDisplayedTasksIfNeeded() {
        guard showsDesktopActivity else { return }
        controller.noteDesktopActivitiesDisplayed(desktopTasks)
    }

    private var conversationStatus: some View {
        HStack(spacing: 8) {
            conversationStatusGlyph

            VStack(alignment: .leading, spacing: 3) {
                Text(conversationTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(1)
                Text(conversationDetail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.isGenerating {
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
    }

    @ViewBuilder
    private var conversationStatusGlyph: some View {
        if model.isGenerating {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        } else if isFailed {
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 24, height: 24)
                .background(Color.red.opacity(0.12), in: Circle())
        } else if isComplete {
            Button(action: controller.confirmCompleted) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .frame(width: 24, height: 24)
                    .background(Color.green.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("确认完成")
            .accessibilityLabel("确认完成")
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.11), in: Circle())
        }
    }

    private var desktopTaskList: some View {
        VStack(spacing: 0) {
            if desktopTasks.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Codex 已就绪")
                            .font(.system(size: 14, weight: .semibold))
                        Text("在 Codex 中开始任务后会显示在这里")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: PinChatVisualMetrics.desktopTaskRowHeight)
            } else {
                ForEach(Array(desktopTasks.enumerated()), id: \.element.id) { index, task in
                    desktopTaskRow(task)
                    if index < desktopTasks.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func desktopTaskRow(_ task: CodexTaskActivity) -> some View {
        HStack(spacing: 9) {
            desktopStatusGlyph(task.state)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(desktopStateLabel(task.state))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(desktopStateColor(task.state))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ActionCircleButton(
                systemName: "arrow.up.right",
                tint: .primary.opacity(0.075),
                foreground: .secondary,
                help: "在 Codex 中打开 \(task.title)",
                size: 26
            ) {
                controller.openDesktopActivityInCodex(task.threadID)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: PinChatVisualMetrics.desktopTaskRowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.title)，\(desktopStateLabel(task.state))")
    }

    @ViewBuilder
    private func desktopStatusGlyph(_ state: CodexTaskState) -> some View {
        if state == .thinking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: desktopStateSymbol(state))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(desktopStateColor(state))
                .frame(width: 24, height: 24)
                .background(desktopStateColor(state).opacity(0.12), in: Circle())
        }
    }

    private func desktopStateLabel(_ state: CodexTaskState) -> String {
        switch state {
        case .thinking: return "正在思考"
        case .waiting: return "等待你的操作"
        case .completed: return "已完成"
        case .stopped: return "已停止"
        case .failed: return "失败"
        }
    }

    private func desktopStateSymbol(_ state: CodexTaskState) -> String {
        switch state {
        case .thinking: return "sparkles"
        case .waiting: return "hand.raised.fill"
        case .completed: return "checkmark"
        case .stopped: return "stop.fill"
        case .failed: return "exclamationmark"
        }
    }

    private func desktopStateColor(_ state: CodexTaskState) -> Color {
        switch state {
        case .thinking: return .accentColor
        case .waiting: return .orange
        case .completed: return .green
        case .stopped: return .secondary
        case .failed: return .red
        }
    }

    private var conversationTitle: String {
        if model.isGenerating { return "正在处理" }
        if isFailed { return "未能完成" }
        return model.selectedSession?.title ?? "已完成"
    }

    private var conversationDetail: String {
        if let error = model.lastTurnError { return error }
        if let approval = model.pendingApproval {
            return "等待批准：\(approval.title)"
        }
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
            if let approval = model.pendingApproval {
                ApprovalRequestCard(model: model, request: approval)
                Divider().opacity(0.40)
            }
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
            ToolbarIcon(systemName: "square.and.pencil", help: "新建对话") {
                controller.startNewConversation()
            }
            .disabled(model.isGenerating)
            .opacity(model.isGenerating ? 0.45 : 1)
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
                .onSubmit(send)
                .background {
                    CaretScreenPositionReader { point in
                        controller.updatePetCaret(
                            screenPoint: point,
                            context: .answer
                        )
                    }
                }
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

private struct ApprovalRequestCard: View {
    @ObservedObject var model: AppModel
    let request: CodexApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .background(Color.orange.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(request.detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    if let reason = request.reason,
                       !reason.isEmpty,
                       reason != request.detail {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let directory = request.workingDirectory, !directory.isEmpty {
                        Text(directory)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("拒绝") {
                    model.resolveApproval(request, decision: .decline)
                }
                .keyboardShortcut(.cancelAction)
                Button("允许一次") {
                    model.resolveApproval(request, decision: .allowOnce)
                }
                if request.canAllowForSession {
                    Button("本次对话允许") {
                        model.resolveApproval(request, decision: .allowForSession)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.045))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex 请求授权：\(request.title)")
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
                    VStack(alignment: .leading, spacing: 7) {
                        if let attachments = message.attachments, !attachments.isEmpty {
                            ForEach(attachments) { attachment in
                                Label(
                                    attachment.displayName,
                                    systemImage: attachment.kind == .image ? "photo" : "doc"
                                )
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            }
                        }
                        if let capabilities = message.capabilities, !capabilities.isEmpty {
                            ForEach(capabilities) { capability in
                                Label(
                                    capability.name,
                                    systemImage: capability.kind == .skill ? "sparkles" : "app"
                                )
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            }
                        }
                        Text(message.text)
                            .font(.system(size: 14.5))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
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

                Section("任务权限") {
                    Picker("权限模式", selection: $model.permissionMode) {
                        ForEach(PinChatPermissionMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    Text(model.permissionMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("权限表示 Codex 可以使用的能力上限；简单问答不会因此自动读取文件。新选择会在下一次发送或继续对话时生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.permissionMode == .fullAccess {
                        Label(
                            "完全访问会移除 Codex 沙箱边界，请只在你信任当前任务时使用。macOS 保护目录仍可能需要“完全磁盘访问权限”。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    Button("打开完全磁盘访问设置…") {
                        controller.openFullDiskAccessSettings()
                    }
                }

                Section("PinChat 3.2") {
                    Text("点击桌宠提问；完成卡可展开回答、确认完成，或把同一任务交给 Codex 主应用继续。PinChat 不提供历史任务列表，也不接入其他 AI API。")
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
