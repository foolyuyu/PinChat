import AppKit
import Foundation
import Testing
@testable import PinChat

@Test func sessionStoreRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinChatTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = SessionStore(baseDirectory: directory)
    let session = ChatSession(
        title: "测试对话",
        codexThreadID: "thread-1",
        messages: [ChatMessage(role: .user, text: "你好")]
    )
    try store.save([session])

    let loaded = try #require(store.load().first)
    #expect(loaded.id == session.id)
    #expect(loaded.title == "测试对话")
    #expect(loaded.codexThreadID == "thread-1")
    #expect(loaded.messages.map(\.text) == ["你好"])
}

@Test func planNamesAreReadable() {
    #expect(ChatAccount(email: nil, plan: "plus").displayPlan == "Plus")
    #expect(ChatAccount(email: nil, plan: "business").displayPlan == "Business")
}

@Test func codexConfigurationUsesReadableInheritedValues() {
    let inherited = CodexConfiguration(
        model: "gpt-5.6-terra",
        reasoningEffort: "high",
        personality: nil
    )
    #expect(inherited.displayModel == "gpt-5.6-terra")
    #expect(inherited.displayReasoningEffort == "高")
    #expect(inherited.displayPersonality == "Codex 默认")
}

@Test func markdownBlocksPreserveCodexStyleStructure() {
    let source = """
    ## 标题

    一段包含 **重点** 和 `inline` 的正文。

    - 第一项
    - 第二项

    > 一段引用

    ```swift
    let answer = 42
    ```
    """

    #expect(MarkdownBlockParser.parse(source) == [
        .heading(level: 2, text: "标题"),
        .paragraph("一段包含 **重点** 和 `inline` 的正文。"),
        .unorderedList(["第一项", "第二项"]),
        .quote("一段引用"),
        .code(language: "swift", value: "let answer = 42")
    ])
}

@Test func unfinishedCodeFenceStillRendersDuringStreaming() {
    let blocks = MarkdownBlockParser.parse("```json\n{\"ready\": true}")
    #expect(blocks == [.code(language: "json", value: "{\"ready\": true}")])
}

@Test func windowPlacementKeepsRestoredFrameVisible() {
    let screen = NSRect(x: -1440, y: 0, width: 1440, height: 900)
    let restored = NSRect(x: 900, y: -200, width: 1800, height: 1200)
    let result = WindowPlacement.clamped(restored, to: screen)

    #expect(result == NSRect(x: -1440, y: 0, width: 1440, height: 900))
}

@Test func panelPolicySupportsNormalAndFullScreenSpaces() {
    let behavior = PanelPresentationPolicy.crossSpaceBehavior
    #expect(behavior.contains(.canJoinAllSpaces))
    #expect(behavior.contains(.fullScreenAuxiliary))
    #expect(behavior.contains(.stationary))
}

@Test func floatingButtonSnapsToNearestScreenEdge() {
    let screen = NSRect(x: 0, y: 0, width: 1200, height: 800)
    let left = WindowPlacement.snappedFloatingButton(
        NSRect(x: 150, y: 900, width: 68, height: 68),
        to: screen
    )
    let right = WindowPlacement.snappedFloatingButton(
        NSRect(x: 900, y: -40, width: 68, height: 68),
        to: screen
    )

    #expect(left.origin == NSPoint(x: 8, y: 724))
    #expect(right.origin == NSPoint(x: 1124, y: 8))
}

@Test func floatingButtonDragPreservesPointerGrabOffset() {
    let origin = WindowPlacement.floatingButtonOrigin(
        pointerLocation: NSPoint(x: 850, y: 620),
        grabOffset: NSSize(width: 18, height: 41)
    )

    #expect(origin == NSPoint(x: 832, y: 579))
}

@Test func answerExpandsTowardAvailableScreenSpace() {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let highPet = NSRect(x: 1000, y: 650, width: 184, height: 184)
    let lowPet = NSRect(x: 1000, y: 40, width: 184, height: 184)

    #expect(WindowPlacement.preferredAttachmentDirection(
        anchor: highPet,
        in: screen,
        requiredHeight: 500
    ) == .below)
    #expect(WindowPlacement.preferredAttachmentDirection(
        anchor: lowPet,
        in: screen,
        requiredHeight: 500
    ) == .above)
}

@Test func attachedStatusAndAnswerStayOrderedAndVisible() throws {
    let screen = NSRect(x: 0, y: 0, width: 1200, height: 800)
    let pet = NSRect(x: 900, y: 620, width: 184, height: 184)
    let frames = WindowPlacement.stackedFrames(
        sizes: [NSSize(width: 660, height: 104), NSSize(width: 620, height: 420)],
        attachedTo: pet,
        in: screen,
        direction: .below,
        gap: 8
    )

    #expect(frames.count == 2)
    let status = try #require(frames.first)
    let answer = try #require(frames.last)
    #expect(answer.maxY <= status.minY)
    #expect(screen.contains(status))
    #expect(screen.contains(answer))
}

@Test func manuallyMovingAnswerDetachesIt() {
    #expect(AnswerAttachmentState.attached.afterWindowMove(isProgrammatic: true) == .attached)
    #expect(AnswerAttachmentState.attached.afterWindowMove(isProgrammatic: false) == .detached)
    #expect(AnswerAttachmentState.detached.afterWindowMove(isProgrammatic: true) == .detached)
}

@Test func petAnimationTracksConversationState() {
    #expect(PetAnimation.resolve(isDragging: true, isGenerating: true, hasError: false, hasAnswer: false) == .jumping)
    #expect(PetAnimation.resolve(isDragging: false, isGenerating: true, hasError: false, hasAnswer: false) == .working)
    #expect(PetAnimation.resolve(isDragging: false, isGenerating: false, hasError: true, hasAnswer: false) == .failed)
    #expect(PetAnimation.resolve(isDragging: false, isGenerating: false, hasError: false, hasAnswer: true) == .waving)
    #expect(PetAnimation.resolve(isDragging: false, isGenerating: false, hasError: false, hasAnswer: false) == .idle)
}

@Test func transparentSpriteCellsAreFilteredOut() throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let blankContext = try #require(CGContext(
        data: nil,
        width: 64,
        height: 64,
        bitsPerComponent: 8,
        bytesPerRow: 64 * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let blank = try #require(blankContext.makeImage())

    let filledContext = try #require(CGContext(
        data: nil,
        width: 64,
        height: 64,
        bitsPerComponent: 8,
        bytesPerRow: 64 * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    filledContext.setFillColor(NSColor.systemBlue.cgColor)
    filledContext.fill(CGRect(x: 8, y: 8, width: 48, height: 48))
    let filled = try #require(filledContext.makeImage())

    #expect(!PetSpriteStore.hasVisibleContent(blank))
    #expect(PetSpriteStore.hasVisibleContent(filled))
}

@Test func onlyFinalAgentMessagesAreDisplayed() {
    #expect(!CodexAppServer.shouldDisplayAgentMessage(phase: "commentary"))
    #expect(CodexAppServer.shouldDisplayAgentMessage(phase: "final_answer"))
    #expect(CodexAppServer.shouldDisplayAgentMessage(phase: nil))
}

@Test func completedAgentMessageReplacesDuplicatedStreamedText() {
    let text = CodexAppServer.authoritativeAgentText(
        streamedText: "最终回答\n\n最终回答",
        completedText: "最终回答"
    )

    #expect(text == "最终回答")
}

@Test func reconciliationDoesNotEraseInterruptedPartialAnswer() {
    let existing = [
        ChatMessage(sourceID: "user-1", role: .user, text: "问题"),
        ChatMessage(sourceID: nil, role: .assistant, text: "已经流式收到的局部回答")
    ]
    let remote = [
        CodexAppServer.RemoteMessage(sourceID: "user-1", role: .user, text: "问题")
    ]

    #expect(MessageReconciler.merge(remoteMessages: remote, existing: existing) == nil)
}

@Test func reconciliationAttachesRemoteSourceIDsWithoutChangingContent() throws {
    let user = ChatMessage(role: .user, text: "问题")
    let answer = ChatMessage(role: .assistant, text: "回答")
    let remote = [
        CodexAppServer.RemoteMessage(sourceID: "user-1", role: .user, text: "问题"),
        CodexAppServer.RemoteMessage(sourceID: "answer-1", role: .assistant, text: "回答")
    ]

    let merged = try #require(MessageReconciler.merge(
        remoteMessages: remote,
        existing: [user, answer]
    ))
    #expect(merged.map(\.id) == [user.id, answer.id])
    #expect(merged.map(\.sourceID) == ["user-1", "answer-1"])
    #expect(merged.map(\.text) == ["问题", "回答"])
}

@Test func reconciliationPreservesInterruptedAnswerWhenCodexAppAppends() throws {
    let question = ChatMessage(sourceID: "user-1", role: .user, text: "问题")
    let partial = ChatMessage(role: .assistant, text: "未被远端历史收录的中断片段")
    let remote = [
        CodexAppServer.RemoteMessage(sourceID: "user-1", role: .user, text: "问题"),
        CodexAppServer.RemoteMessage(sourceID: "answer-2", role: .assistant, text: "Codex 端的新回答")
    ]

    let merged = try #require(MessageReconciler.merge(
        remoteMessages: remote,
        existing: [question, partial]
    ))
    #expect(Array(merged.map(\.id).prefix(2)) == [question.id, partial.id])
    #expect(merged.map(\.text) == ["问题", "未被远端历史收录的中断片段", "Codex 端的新回答"])
}

@Test func reconciliationPromotesStreamedPrefixToCompletedRemoteAnswer() throws {
    let partial = ChatMessage(role: .assistant, text: "正在生成")
    let remote = [
        CodexAppServer.RemoteMessage(
            sourceID: "answer-1",
            role: .assistant,
            text: "正在生成并已经完成"
        )
    ]

    let merged = try #require(MessageReconciler.merge(
        remoteMessages: remote,
        existing: [partial]
    ))
    #expect(merged.count == 1)
    #expect(merged[0].id == partial.id)
    #expect(merged[0].sourceID == "answer-1")
    #expect(merged[0].text == "正在生成并已经完成")
}
