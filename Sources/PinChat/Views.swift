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
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .background {
                    ZStack {
                        BehindWindowGlass(material: .popover, opacity: 0.96)
                            .clipShape(shape)
                        shape.fill(
                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18)
                        )
                    }
                }
                .glassEffect(
                    .regular.tint(
                        Color.white.opacity(colorScheme == .dark ? 0.11 : 0.16)
                    ),
                    in: shape
                )
                .overlay { hoverSheen(shape: shape) }
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
                    ZStack {
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
                        hoverSheen(shape: shape)
                    }
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

    private func hoverSheen(shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.055 : 0.14),
                        Color.accentColor.opacity(colorScheme == .dark ? 0.025 : 0.035),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.strokeBorder(
                Color.white.opacity(colorScheme == .dark ? 0.17 : 0.36),
                lineWidth: 0.75
            )
        }
        .opacity(isHovered ? 1 : 0)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isHovered
        )
        .allowsHitTesting(false)
    }
}

private extension View {
    func compactFloatingSurface(cornerRadius: CGFloat, isHovered: Bool = false) -> some View {
        modifier(CompactFloatingSurface(cornerRadius: cornerRadius, isHovered: isHovered))
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

enum AttachmentDropSupport {
    static let acceptedTypeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.image.identifier
    ]

    @MainActor
    static func load(
        providers: [NSItemProvider],
        receive: @escaping @MainActor @Sendable ([URL]) -> Void
    ) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier,
                    options: nil
                ) { item, _ in
                    guard let url = fileURL(from: item) else { return }
                    Task { @MainActor in receive([url]) }
                }
                continue
            }

            guard let imageType = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            }) else { continue }
            accepted = true
            let suggestedName = provider.suggestedName
            provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
                guard let data,
                      let url = try? persistDroppedImage(
                        data,
                        typeIdentifier: imageType,
                        suggestedName: suggestedName
                      ) else { return }
                Task { @MainActor in receive([url]) }
            }
        }
        return accepted
    }

    static func fileURL(from item: NSSecureCoding?) -> URL? {
        let candidate: URL?
        switch item {
        case let url as URL:
            candidate = url
        case let url as NSURL:
            candidate = url as URL
        case let data as Data:
            candidate = URL(dataRepresentation: data, relativeTo: nil)
                ?? String(data: data, encoding: .utf8).flatMap(URL.init(string:))
        case let string as String:
            candidate = URL(string: string)
        case let string as NSString:
            candidate = URL(string: string as String)
        default:
            candidate = nil
        }
        guard let candidate, candidate.isFileURL else { return nil }
        return candidate.standardizedFileURL
    }

    static func persistDroppedImage(
        _ data: Data,
        typeIdentifier: String,
        suggestedName: String?,
        cacheRoot: URL? = nil
    ) throws -> URL {
        let root = cacheRoot ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        let directory = root
            .appendingPathComponent("PinChat", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let type = UTType(typeIdentifier)
        let fileExtension = type?.preferredFilenameExtension ?? "png"
        let rawName = suggestedName.map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        }
        let baseName = rawName?.isEmpty == false ? rawName! : "拖入截图"
        let output = directory.appendingPathComponent(
            "\(baseName)-\(UUID().uuidString).\(fileExtension)"
        )
        try data.write(to: output, options: .atomic)
        return output
    }
}

private struct AttachmentStrip: View {
    @Binding var attachments: [ChatAttachment]

    var body: some View {
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
}

struct PetRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController

    private var animation: PetAnimation {
        PetAnimation.resolve(
            isDragging: controller.isDraggingPet,
            isGenerating: model.isGenerating
                || model.taskActivities.contains(where: { $0.state.isInProgress }),
            hasError: model.lastTurnError != nil,
            hasAnswer: !model.latestAssistantText.isEmpty,
            hasCompletionSignal: model.hasUnviewedCompletionSignal
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
        .accessibilityLabel(
            model.hasUnviewedCompletionSignal
                ? "PinChat 有已完成的任务"
                : "打开 PinChat"
        )
    }
}

struct MiniComposerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController
    @State private var draft = ""
    @State private var attachments: [ChatAttachment] = []
    @State private var showsAttachmentMenu = false
    @State private var isDropTargeted = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                AttachmentStrip(attachments: $attachments)
            }

            HStack(spacing: 7) {
                attachmentMenu

                TextField(placeholder, text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1...2)
                    .focused($focused)
                    // Drafting remains available while the local Codex service
                    // connects. Submission still waits for `canSubmit` below.
                    .disabled(model.isGenerating)
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
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.5)
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: AttachmentDropSupport.acceptedTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: acceptDroppedItems
        )
        .padding(PinChatVisualMetrics.composerSurfaceOuterInset)
        .padding(PinChatVisualMetrics.composerShadowOutset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.refreshCodexPermissionConfiguration()
            focusSoon()
        }
        .onChange(of: controller.isComposerVisible) {
            if controller.isComposerVisible {
                model.refreshCodexPermissionConfiguration()
                focusSoon()
            }
        }
        .onChange(of: attachments.isEmpty) {
            updateComposerHeight()
        }
        .onExitCommand { controller.hideComposer() }
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

    private var placeholder: String {
        switch model.connectionStatus {
        case .starting: "正在连接本机 Codex…"
        case .signingIn: "请在浏览器完成登录…"
        case .unavailable: "连接失败，请在设置中重试"
        default: model.account == nil ? "登录后开始提问" : "开始新聊天"
        }
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PinChatVisualMetrics.composerFocusDelay
        ) {
            // Let the expanding surface establish its initial centered target
            // before the mascot begins following the insertion caret.
            focused = true
        }
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
        attachments = ChatAttachment.merging(attachments, urls: urls)
    }

    private func acceptDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        AttachmentDropSupport.load(providers: providers) { urls in
            addAttachments(urls)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit, !model.isGenerating else { return }
        let selectedAttachments = attachments
        draft = ""
        attachments = []
        controller.sendMessage(
            text,
            attachments: selectedAttachments,
            startsNewConversation: true
        )
    }
}

struct TaskStatusCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AppController
    @State private var hoveredDesktopTaskID: String?
    @State private var isCardHovered = false
    @State private var conversationFollowUpDraft = ""
    @FocusState private var conversationFollowUpFocused: Bool

    private var showsDesktopActivity: Bool { controller.isDesktopActivityStatus }
    private var desktopTasks: [CodexTaskActivity] {
        model.taskActivities
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
                ? PinChatVisualMetrics.desktopStatusContentHeight(
                    taskCount: desktopTasks.count,
                    showingFollowUp: controller.isConversationFollowUpVisible
                )
                : (controller.isConversationFollowUpVisible
                    ? PinChatVisualMetrics.statusFollowUpContentHeight
                    : PinChatVisualMetrics.statusContentHeight)
        )
        .compactFloatingSurface(
            cornerRadius: 18,
            isHovered: isCardHovered && showsDesktopActivity
        )
        .onHover { hovering in
            isCardHovered = hovering
            controller.statusHoverChanged(hovering)
        }
        .padding(PinChatVisualMetrics.statusShadowOutset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { noteDisplayedTasksIfNeeded() }
        .onChange(of: controller.statusContext) {
            noteDisplayedTasksIfNeeded()
        }
        .onChange(of: model.taskActivities) {
            controller.refreshDesktopActivityPanelLayout()
            noteDisplayedTasksIfNeeded()
        }
        .onChange(of: model.isGenerating) {
            if !model.isGenerating {
                closeConversationFollowUp()
            }
        }
        .animation(
            .spring(response: 0.34, dampingFraction: 0.82),
            value: model.taskActivities
        )
    }

    private func noteDisplayedTasksIfNeeded() {
        guard showsDesktopActivity else { return }
        controller.noteDesktopActivitiesDisplayed(desktopTasks)
    }

    private var conversationStatus: some View {
        VStack(spacing: 0) {
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
                        systemName: controller.isConversationFollowUpVisible
                            ? "text.bubble.fill"
                            : "text.bubble",
                        tint: controller.isConversationFollowUpVisible
                            ? Color.accentColor.opacity(0.16)
                            : Color.primary.opacity(0.075),
                        foreground: controller.isConversationFollowUpVisible
                            ? Color.accentColor
                            : .secondary,
                        help: controller.isConversationFollowUpVisible
                            ? "关闭补充"
                            : "补充当前任务",
                        action: toggleConversationFollowUp
                    )
                    .disabled(!model.canSteerActiveTurn)
                    .opacity(model.canSteerActiveTurn ? 1 : 0.45)
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
            .frame(height: PinChatVisualMetrics.statusContentHeight)

            if controller.isConversationFollowUpVisible {
                Divider().opacity(0.35).padding(.horizontal, 12)
                conversationFollowUpComposer
            }
        }
    }

    private var conversationFollowUpComposer: some View {
        HStack(spacing: 8) {
            TextField("补充引导…", text: $conversationFollowUpDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($conversationFollowUpFocused)
                .onSubmit(submitConversationFollowUp)
            if model.isSteeringActiveTurn {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 26, height: 26)
            } else {
                ActionCircleButton(
                    systemName: "arrow.up",
                    tint: canSubmitConversationFollowUp
                        ? Color.accentColor
                        : Color.primary.opacity(0.06),
                    foreground: canSubmitConversationFollowUp ? .white : .secondary,
                    help: "加入当前任务",
                    size: 26,
                    action: submitConversationFollowUp
                )
                .disabled(!canSubmitConversationFollowUp)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
    }

    private var canSubmitConversationFollowUp: Bool {
        !conversationFollowUpDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.canSteerActiveTurn
            && !model.isSteeringActiveTurn
    }

    private func toggleConversationFollowUp() {
        if controller.isConversationFollowUpVisible {
            closeConversationFollowUp()
        } else {
            conversationFollowUpDraft = ""
            controller.setConversationFollowUpVisible(true)
            DispatchQueue.main.async { conversationFollowUpFocused = true }
        }
    }

    private func closeConversationFollowUp() {
        conversationFollowUpFocused = false
        conversationFollowUpDraft = ""
        controller.setConversationFollowUpVisible(false)
    }

    private func submitConversationFollowUp() {
        let prompt = conversationFollowUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmitConversationFollowUp else { return }
        model.steerActiveTurn(prompt) { succeeded in
            if succeeded {
                closeConversationFollowUp()
            } else {
                conversationFollowUpFocused = true
            }
        }
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
            ActionCircleButton(
                systemName: "checkmark",
                tint: Color.green.opacity(0.12),
                foreground: .green,
                help: "确认完成",
                size: 24,
                action: controller.confirmCompleted
            )
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
                    desktopTaskRow(
                        task,
                        isFirst: index == 0,
                        isLast: index == desktopTasks.count - 1
                    )
                    if isCurrentInteractiveTask(task),
                       controller.isConversationFollowUpVisible {
                        taskSeparator
                        conversationFollowUpComposer
                    }
                    if index < desktopTasks.count - 1 {
                        taskSeparator
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func desktopTaskRow(
        _ task: CodexTaskActivity,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        Button {
            controller.openTaskActivity(task)
        } label: {
            HStack(spacing: 9) {
                desktopStatusGlyph(task)
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
            }
            .padding(.leading, 11)
            .padding(.trailing, showsTaskActions(task) ? 76 : 11)
            .frame(height: PinChatVisualMetrics.desktopTaskRowHeight)
            .padding(.top, isFirst ? 5 : 0)
            .padding(.bottom, isLast ? 5 : 0)
            .contentShape(Rectangle())
            .background {
                Rectangle().fill(
                    Color.primary.opacity(
                        hoveredDesktopTaskID == task.threadID ? 0.036 : 0
                    )
                )
            }
        }
        .buttonStyle(DesktopTaskPressStyle())
        .onHover { hovering in
            hoveredDesktopTaskID = hovering ? task.threadID : nil
        }
        .overlay(alignment: .leading) {
            if task.state == .completed {
                VStack(spacing: 0) {
                    if isFirst { Color.clear.frame(width: 24, height: 5) }
                    ActionCircleButton(
                        systemName: "checkmark",
                        tint: Color.green.opacity(0.12),
                        foreground: .green,
                        help: "确认并收起 \(task.title)",
                        size: 24
                    ) {
                        controller.acknowledgeDesktopActivity(task)
                    }
                    .frame(height: PinChatVisualMetrics.desktopTaskRowHeight)
                    if isLast { Color.clear.frame(width: 24, height: 5) }
                }
                .frame(width: 24)
                .padding(.leading, 11)
            }
        }
        .overlay(alignment: .trailing) {
            if showsTaskActions(task) {
                HStack(spacing: 5) {
                    ActionCircleButton(
                        systemName: controller.isConversationFollowUpVisible
                            ? "text.bubble.fill"
                            : "text.bubble",
                        tint: controller.isConversationFollowUpVisible
                            ? Color.accentColor.opacity(0.16)
                            : Color.primary.opacity(0.075),
                        foreground: controller.isConversationFollowUpVisible
                            ? Color.accentColor
                            : .secondary,
                        help: controller.isConversationFollowUpVisible
                            ? "关闭补充"
                            : (isCurrentInteractiveTask(task)
                                ? "补充当前任务"
                                : "在 Codex 中补充当前任务"),
                        size: 26,
                        action: {
                            if isCurrentInteractiveTask(task) {
                                toggleConversationFollowUp()
                            } else {
                                controller.openTaskActivity(task)
                            }
                        }
                    )
                    .disabled(
                        isCurrentInteractiveTask(task) && !model.canSteerActiveTurn
                    )
                    .opacity(
                        isCurrentInteractiveTask(task) && !model.canSteerActiveTurn
                            ? 0.45
                            : 1
                    )
                    ActionCircleButton(
                        systemName: "stop.fill",
                        tint: .primary.opacity(0.075),
                        foreground: .secondary,
                        help: isCurrentInteractiveTask(task)
                            ? "停止生成"
                            : "在 Codex 中停止任务",
                        size: 26,
                        action: {
                            if isCurrentInteractiveTask(task) {
                                model.stopGenerating()
                            } else {
                                controller.openTaskActivity(task)
                            }
                        }
                    )
                }
                .padding(.trailing, 10)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func isCurrentInteractiveTask(_ task: CodexTaskActivity) -> Bool {
        model.isGenerating
            && model.selectedSession?.codexThreadID == task.threadID
    }

    private func showsTaskActions(_ task: CodexTaskActivity) -> Bool {
        task.state.isInProgress
    }

    private var taskSeparator: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.primary.opacity(0.10),
                Color.primary.opacity(0.10),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 0.5)
        .padding(.horizontal, 18)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func desktopStatusGlyph(_ task: CodexTaskActivity) -> some View {
        if task.state == .thinking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        } else if task.state == .completed {
            Image(systemName: "checkmark")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.green)
                .frame(width: 24, height: 24)
                .background(Color.green.opacity(0.12), in: Circle())
        } else {
            Image(systemName: desktopStateSymbol(task.state))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(desktopStateColor(task.state))
                .frame(width: 24, height: 24)
                .background(desktopStateColor(task.state).opacity(0.12), in: Circle())
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
    @State private var attachments: [ChatAttachment] = []
    @State private var isDropTargeted = false
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
            Spacer()
            ToolbarIcon(systemName: "square.and.pencil", help: "新建对话") {
                controller.startNewConversation(collapseToward: NSEvent.mouseLocation)
            }
            .disabled(model.isGenerating)
            .opacity(model.isGenerating ? 0.45 : 1)
            ToolbarIcon(systemName: "xmark", help: "关闭回答") {
                controller.closeAnswer()
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .contentShape(Rectangle())
    }

    private var followUpComposer: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                AttachmentStrip(attachments: $attachments)
            }
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
                    .disabled(!canSubmitFollowUp)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.40))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.5)
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: AttachmentDropSupport.acceptedTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: acceptDroppedItems
        )
    }

    private var canSubmitFollowUp: Bool {
        !model.isGenerating
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty)
    }

    private func acceptDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        AttachmentDropSupport.load(providers: providers) { urls in
            attachments = ChatAttachment.merging(attachments, urls: urls)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmitFollowUp else { return }
        let selectedAttachments = attachments
        draft = ""
        attachments = []
        controller.sendMessage(text, attachments: selectedAttachments)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

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
                .overlay {
                    Circle()
                        .fill(Color.primary.opacity(isHovering ? 0.085 : 0))
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(isHovering ? 0.62 : 0.34),
                            lineWidth: isHovering ? 1.15 : 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(isHovering ? 0.18 : 0),
                    radius: isHovering ? 4 : 0,
                    y: isHovering ? 1.5 : 0
                )
                .scaleEffect(isHovering ? 1.065 : 1)
                .contentShape(Circle())
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.13),
                    value: isHovering
                )
        }
        .buttonStyle(StatusActionPressStyle())
        .onHover { hovering in
            isHovering = hovering && isEnabled
        }
        .onChange(of: isEnabled) {
            if !isEnabled { isHovering = false }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ToolbarIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let systemName: String
    let help: String
    var size: CGFloat = PinChatVisualMetrics.answerToolbarActionSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: size, height: size)
                .background(Color.primary.opacity(isHovering ? 0.075 : 0), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(isHovering ? 0.34 : 0), lineWidth: 0.8)
                }
                .scaleEffect(isHovering ? 1.055 : 1)
                .contentShape(Circle())
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.13),
                    value: isHovering
                )
        }
        .buttonStyle(StatusActionPressStyle())
        .onHover { hovering in
            isHovering = hovering && isEnabled
        }
        .onChange(of: isEnabled) {
            if !isEnabled { isHovering = false }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct StatusActionPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.91 : 1)
            .brightness(configuration.isPressed ? -0.045 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.085),
                value: configuration.isPressed
            )
    }
}

private struct DesktopTaskPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.09),
                value: configuration.isPressed
            )
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
                    LabeledContent(
                        "任务权限",
                        value: "\(model.codexPermissionConfiguration.title)（跟随）"
                    )
                    Text(model.codexPermissionConfiguration.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("PinChat 不单独保存权限；每次提问前都会重新读取 Codex 主应用在本机选择的权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开完全磁盘访问设置…") {
                        controller.openFullDiskAccessSettings()
                    }
                }

                Section("PinChat 3.3") {
                    Text("点击桌宠提问；完成卡可展开回答、确认完成，或把同一任务交给 Codex 主应用继续。PinChat 不提供历史任务列表，也不接入其他 AI API。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(8)
        .frame(minWidth: 420, idealWidth: 440, minHeight: 440, idealHeight: 510)
        .onAppear { model.refreshCodexPermissionConfiguration() }
    }
}
