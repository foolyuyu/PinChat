import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
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

@Test func sessionStorePersistsOptionalAttachmentsWithoutBreakingMessages() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinChatAttachmentTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = SessionStore(baseDirectory: directory)
    let attachment = ChatAttachment(url: URL(fileURLWithPath: "/tmp/reference.png"))
    let capability = CodexComposerCapability(
        kind: .skill,
        name: "PDF",
        summary: "Read PDFs",
        path: "/tmp/pdf/SKILL.md",
        invocationName: "pdf:pdf"
    )
    let message = ChatMessage(
        role: .user,
        text: "查看附件",
        attachments: [attachment],
        capabilities: [capability]
    )
    try store.save([ChatSession(messages: [message])])

    let loaded = try #require(store.load().first?.messages.first)
    #expect(loaded.attachments == [attachment])
    #expect(loaded.capabilities == [capability])

    let legacyJSON = """
    [{"id":"00000000-0000-0000-0000-000000000001","title":"旧会话","createdAt":"2026-09-15T00:00:00Z","updatedAt":"2026-09-15T00:00:00Z","messages":[{"id":"00000000-0000-0000-0000-000000000002","role":"user","text":"旧消息","createdAt":"2026-09-15T00:00:00Z"}]}]
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let legacy = try decoder.decode([ChatSession].self, from: Data(legacyJSON.utf8))
    #expect(legacy.first?.messages.first?.attachments == nil)
    #expect(legacy.first?.messages.first?.capabilities == nil)
}

@Test func codexTurnInputMapsImagesAndFiles() throws {
    let image = ChatAttachment(url: URL(fileURLWithPath: "/tmp/design.png"))
    let file = ChatAttachment(url: URL(fileURLWithPath: "/tmp/notes.txt"))
    let items = CodexAppServer.turnInputItems(
        text: "解释附件",
        attachments: [image, file]
    )

    #expect(items.count == 2)
    let prompt = try #require(items[0]["text"] as? String)
    #expect(prompt.contains("解释附件"))
    #expect(prompt.contains("/tmp/notes.txt"))
    #expect(items[1]["type"] as? String == "localImage")
    #expect(items[1]["path"] as? String == "/tmp/design.png")
}

@Test func codexTurnInputAllowsImageOnlySubmission() throws {
    let image = ChatAttachment(url: URL(fileURLWithPath: "/tmp/screenshot.jpeg"))
    let items = CodexAppServer.turnInputItems(text: "", attachments: [image])

    #expect(items.count == 2)
    #expect(items[0]["text"] as? String == "请查看所附图片。")
    #expect(items[1]["type"] as? String == "localImage")
}

@Test func attachmentMergingAcceptsDroppedFilesAndDirectoriesOnce() {
    let existing = ChatAttachment(url: URL(fileURLWithPath: "/tmp/existing.txt"))
    let merged = ChatAttachment.merging(
        [existing],
        urls: [
            URL(fileURLWithPath: "/tmp/existing.txt"),
            URL(fileURLWithPath: "/tmp/new-file.pdf"),
            URL(fileURLWithPath: "/tmp/folder", isDirectory: true),
            URL(fileURLWithPath: "/tmp/new-file.pdf"),
            URL(string: "https://example.com/remote.pdf")!
        ]
    )

    #expect(merged.map(\.path) == [
        "/tmp/existing.txt",
        "/tmp/new-file.pdf",
        "/tmp/folder"
    ])
}

@Test func droppedAttachmentParsesNativeFileURLRepresentations() {
    let expected = URL(fileURLWithPath: "/tmp/截屏 2026-09-18.png")

    #expect(AttachmentDropSupport.fileURL(from: expected as NSURL) == expected)
    #expect(
        AttachmentDropSupport.fileURL(from: expected.dataRepresentation as NSData)
            == expected
    )
    #expect(
        AttachmentDropSupport.fileURL(
            from: "https://example.com/not-local.png" as NSString
        ) == nil
    )
}

@Test func droppedImageDataIsPersistedAsARealLocalAttachment() throws {
    let cacheRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinChatDropTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheRoot) }
    let imageData = Data([0x89, 0x50, 0x4E, 0x47])

    let url = try AttachmentDropSupport.persistDroppedImage(
        imageData,
        typeIdentifier: UTType.png.identifier,
        suggestedName: "截屏 2026-09-18.png",
        cacheRoot: cacheRoot
    )

    #expect(url.isFileURL)
    #expect(url.pathExtension == "png")
    #expect(url.lastPathComponent.hasPrefix("截屏 2026-09-18-"))
    #expect(try Data(contentsOf: url) == imageData)
    #expect(ChatAttachment(url: url).kind == .image)
}

@MainActor
@Test func screenshotImageProviderCompletesTheDropPipeline() async throws {
    let imageData = Data([0x89, 0x50, 0x4E, 0x47])
    let provider = NSItemProvider()
    provider.suggestedName = "拖放截图.png"
    provider.registerDataRepresentation(
        forTypeIdentifier: UTType.png.identifier,
        visibility: .all
    ) { completion in
        completion(imageData, nil)
        return nil
    }

    let urls = await withCheckedContinuation { continuation in
        let accepted = AttachmentDropSupport.load(providers: [provider]) { urls in
            continuation.resume(returning: urls)
        }
        #expect(accepted)
    }
    let url = try #require(urls.first)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(url.isFileURL)
    #expect(url.pathExtension == "png")
    #expect(try Data(contentsOf: url) == imageData)
    #expect(ChatAttachment(url: url).kind == .image)
}

@MainActor
@Test func appMenuProvidesStandardMacEditingShortcuts() throws {
    let mainMenu = PinChatMenuFactory.makeMainMenu()
    let editMenu = try #require(
        mainMenu.items.compactMap(\.submenu).first { $0.title == "编辑" }
    )
    let shortcuts: [String: String] = Dictionary(
        uniqueKeysWithValues: editMenu.items.compactMap { item in
            guard !item.keyEquivalent.isEmpty else { return nil }
            return (item.title, item.keyEquivalent) as (String, String)
        }
    )

    #expect(shortcuts["全选"] == "a")
    #expect(shortcuts["复制"] == "c")
    #expect(shortcuts["粘贴"] == "v")
    #expect(shortcuts["剪切"] == "x")
    #expect(shortcuts["撤销"] == "z")
}

@Test func codexTurnInputMapsSkillsAndAppsUsingOfficialItems() throws {
    let skill = CodexComposerCapability(
        kind: .skill,
        name: "PDF",
        summary: "Read PDFs",
        path: "/tmp/pdf/SKILL.md",
        invocationName: "pdf:pdf"
    )
    let app = CodexComposerCapability(
        kind: .app,
        name: "Sites",
        summary: "Build sites",
        path: "app://connector-sites",
        invocationName: "connector-sites"
    )

    let items = CodexAppServer.turnInputItems(
        text: "处理这个请求",
        attachments: [],
        capabilities: [skill, app]
    )

    #expect(items.count == 3)
    let text = try #require(items[0]["text"] as? String)
    #expect(text.hasPrefix("$pdf:pdf $connector-sites "))
    #expect(items[1]["type"] as? String == "skill")
    #expect(items[1]["name"] as? String == "pdf:pdf")
    #expect(items[1]["path"] as? String == "/tmp/pdf/SKILL.md")
    #expect(items[2]["type"] as? String == "mention")
    #expect(items[2]["path"] as? String == "app://connector-sites")
}

@Test func composerCapabilitiesParseOnlyUsableServerResults() {
    let skillsPayload: CodexAppServer.JSON = [
        "data": [[
            "cwd": "/tmp",
            "skills": [[
                "name": "pdf:pdf",
                "description": "Long description",
                "path": "/skills/pdf/SKILL.md",
                "enabled": true,
                "interface": [
                    "displayName": "PDF",
                    "shortDescription": "Read PDFs"
                ]
            ], [
                "name": "disabled",
                "path": "/skills/disabled/SKILL.md",
                "enabled": false
            ]]
        ]]
    ]
    let appsPayload: CodexAppServer.JSON = [
        "data": [[
            "id": "connector-sites",
            "name": "Sites",
            "description": "Build sites",
            "isAccessible": true,
            "isEnabled": true
        ], [
            "id": "connector-disabled",
            "name": "Disabled",
            "isAccessible": true,
            "isEnabled": false
        ]]
    ]

    let skills = CodexAppServer.skillCapabilities(from: skillsPayload)
    let apps = CodexAppServer.appCapabilities(from: appsPayload)
    #expect(skills.map(\.name) == ["PDF"])
    #expect(skills.map(\.invocationName) == ["pdf:pdf"])
    #expect(apps.map(\.name) == ["Sites"])
    #expect(apps.map(\.path) == ["app://connector-sites"])
}

@Test func installedAppsRequireEnabledAndCallableState() {
    let payload: CodexAppServer.JSON = [
        "apps": [[
            "id": "connector-ready",
            "runtimeName": "Ready",
            "enabled": true,
            "callable": true
        ], [
            "id": "connector-disabled",
            "runtimeName": "Disabled",
            "enabled": false,
            "callable": true
        ], [
            "id": "connector-blocked",
            "runtimeName": "Blocked",
            "enabled": true,
            "callable": false
        ]]
    ]

    let apps = CodexAppServer.installedAppCapabilities(from: payload)
    #expect(apps.map(\.name) == ["Ready"])
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

@Test func composerCollapseKeepsItsCenterAndVerticalGeometry() {
    let original = NSRect(x: 120, y: 240, width: 414, height: 120)
    let collapsed = WindowPlacement.horizontallyCollapsedFrame(from: original)

    #expect(collapsed.midX == original.midX)
    #expect(collapsed.minY == original.minY)
    #expect(collapsed.height == original.height)
    #expect(collapsed.width == 8)
}

@Test func answerSwitchCollapsesIntoTheToolbarClickPoint() {
    let original = NSRect(x: 100, y: 200, width: 520, height: 420)
    let clickPoint = NSPoint(x: 570, y: 590)
    let collapsed = WindowPlacement.pointCollapsedFrame(
        from: original,
        toward: clickPoint
    )

    #expect(collapsed.size == NSSize(width: 28, height: 28))
    #expect(collapsed.midX == clickPoint.x)
    #expect(collapsed.midY == clickPoint.y)
    #expect(PinChatVisualMetrics.answerSwitchCollapseDuration == 0.24)
}

@Test func floatingPanelsUseTheSystemInterfaceStyleInsteadOfBackdropDrift() {
    #expect(FloatingPanelAppearancePolicy.appearanceName(interfaceStyle: nil) == .aqua)
    #expect(FloatingPanelAppearancePolicy.appearanceName(interfaceStyle: "Light") == .aqua)
    #expect(FloatingPanelAppearancePolicy.appearanceName(interfaceStyle: "Dark") == .darkAqua)
}

@Test func interactionPolishUsesDeliberateAnimationTiming() {
    #expect(PinChatVisualMetrics.composerRevealDuration == 0.30)
    #expect(PinChatVisualMetrics.composerCollapseDuration == 0.22)
    #expect(PinChatVisualMetrics.floatingPanelRevealDuration == 0.28)
    #expect(PinChatVisualMetrics.statusCollapseDuration == 0.20)
    #expect(PinChatVisualMetrics.composerFocusDelay == 0.14)
    #expect(PinChatVisualMetrics.composerOutsideDismissGraceDuration == 0.55)
}

@Test func panelPolicySupportsNormalAndFullScreenSpaces() {
    let behavior = PanelPresentationPolicy.crossSpaceBehavior
    #expect(behavior.contains(.canJoinAllSpaces))
    #expect(behavior.contains(.fullScreenAuxiliary))
    #expect(behavior.contains(.stationary))
}

@Test func handoffOnlyKeepsDesktopActivityObserverRunning() {
    var lifecycle = CodexExternalHandoffLifecycle()
    #expect(!lifecycle.chatNeedsRestart)

    lifecycle.beginHandoff()
    #expect(lifecycle.chatNeedsRestart)
    #expect(!lifecycle.keepsRunning(.conversation))
    #expect(lifecycle.keepsRunning(.desktopActivityObserver))

    lifecycle.chatDidStart()
    #expect(!lifecycle.chatNeedsRestart)
}

@Test func codexHandoffURLKeepsTheOriginalThreadID() throws {
    let threadID = "0199a124-12ab-7def-8000-123456789abc"
    let url = try #require(CodexThreadLink.makeURL(threadID: threadID))

    #expect(url.scheme == "codex")
    #expect(url.host == "threads")
    #expect(url.lastPathComponent == threadID)
}

@Test func activeTurnSteeringTargetsTheCurrentTurn() throws {
    let turn = CodexAppServer.ActiveTurn(threadID: "thread-1", turnID: "turn-1")
    let parameters = CodexAppServer.turnSteerParameters(
        activeTurn: turn,
        text: "请优先检查配置文件。"
    )
    let input = try #require(parameters["input"] as? [[String: String]])

    #expect(parameters["threadId"] as? String == "thread-1")
    #expect(parameters["expectedTurnId"] as? String == "turn-1")
    #expect(input == [["type": "text", "text": "请优先检查配置文件。"]])
}

@Test func codexThreadsAlwaysCarryARealWorkingDirectory() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("PinChatWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let directory = PinChatConversationWorkspace.prepare(baseDirectory: base)
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)

    let start = CodexAppServer.threadStartParameters(workingDirectory: directory)
    let resume = CodexAppServer.threadResumeParameters(
        threadID: "thread-1",
        workingDirectory: directory
    )
    #expect(start["cwd"] as? String == directory)
    #expect(resume["cwd"] as? String == directory)
    #expect(resume["threadId"] as? String == "thread-1")
}

@Test func visualMetricsRemainSmallerThanOfficialPetReference() {
    #expect(PinChatVisualMetrics.petArtworkSize.width == 52)
    #expect(PinChatVisualMetrics.petArtworkSize.width < 60)
    #expect(PinChatVisualMetrics.petSize == NSSize(width: 64, height: 64))
    #expect(PinChatVisualMetrics.composerActionSize == 26)
    #expect(PinChatVisualMetrics.statusActionSize == 28)
    #expect(PinChatVisualMetrics.answerToolbarActionSize == 24)
}

@Test func desktopTaskEventsResolveRealCodexProgress() {
    #expect(CodexTaskEventReducer.state(eventTypes: ["task_started"]) == .thinking)
    #expect(CodexTaskEventReducer.state(
        eventTypes: ["task_started", "item_completed", "task_complete"]
    ) == .completed)
    #expect(CodexTaskEventReducer.state(
        eventTypes: ["task_complete", "task_started"]
    ) == .thinking)
    #expect(CodexTaskEventReducer.state(
        eventTypes: ["task_started", "turn_aborted"]
    ) == .stopped)
}

@Test func liveServerStatusOverridesPersistedRolloutEvents() {
    #expect(CodexTaskEventReducer.state(
        eventTypes: ["task_complete"],
        serverStatus: "active"
    ) == .thinking)
    #expect(CodexTaskEventReducer.state(
        eventTypes: ["task_complete"],
        serverStatus: "active",
        activeFlags: ["waitingOnUserInput"]
    ) == .waiting)
    #expect(CodexTaskEventReducer.state(
        eventTypes: ["task_started"],
        serverStatus: "systemError"
    ) == .failed)
}

@Test func desktopTasksKeepIndependentStatesAndPrioritizeActiveWork() {
    let now = Date()
    let activities = [
        CodexTaskActivity(
            threadID: "completed-newest",
            title: "最近完成",
            state: .completed,
            updatedAt: now
        ),
        CodexTaskActivity(
            threadID: "thinking",
            title: "仍在思考",
            state: .thinking,
            updatedAt: now.addingTimeInterval(-20)
        ),
        CodexTaskActivity(
            threadID: "waiting",
            title: "等待操作",
            state: .waiting,
            updatedAt: now.addingTimeInterval(-10)
        ),
        CodexTaskActivity(
            threadID: "completed-newest",
            title: "重复项",
            state: .failed,
            updatedAt: now.addingTimeInterval(10)
        )
    ]

    let visible = CodexTaskActivityOrdering.visible(from: activities, limit: 3, now: now)
    #expect(visible.map(\.threadID) == ["waiting", "thinking", "completed-newest"])
    #expect(visible.map(\.state) == [.waiting, .thinking, .completed])
}

@Test func unifiedTaskListUsesFreshInteractiveStateWithoutDuplicatingThread() {
    let now = Date()
    let observed = [
        CodexTaskActivity(
            threadID: "pinchat-thread",
            title: "旧观察状态",
            state: .completed,
            updatedAt: now.addingTimeInterval(-2)
        ),
        CodexTaskActivity(
            threadID: "desktop-thread",
            title: "桌面任务",
            state: .thinking,
            updatedAt: now.addingTimeInterval(-1)
        )
    ]
    let interactive = CodexTaskActivity(
        threadID: "pinchat-thread",
        title: "PinChat 新任务",
        state: .thinking,
        updatedAt: now
    )

    let merged = CodexTaskActivityUnifier.merge(
        currentConversation: interactive,
        observed: observed,
        limit: 5
    )

    #expect(merged.count == 2)
    #expect(merged.first == interactive)
    #expect(merged.filter { $0.threadID == "pinchat-thread" }.count == 1)
}

@Test func completionSignalPersistsUntilItsReceiptIsActuallySeen() throws {
    let completed = CodexTaskActivity(
        threadID: "finished-thread",
        title: "已完成",
        state: .completed,
        updatedAt: Date(timeIntervalSinceReferenceDate: 42)
    )
    let receiptID = try #require(completed.resolvedReceiptID)

    #expect(CodexCompletionSignalPolicy.hasUnseenCompletion(
        in: [completed],
        seenReceiptIDs: []
    ))
    #expect(!CodexCompletionSignalPolicy.hasUnseenCompletion(
        in: [completed],
        seenReceiptIDs: [receiptID]
    ))
}

@Test func completedDesktopTasksWaitForViewingAndMinimumAge() {
    let now = Date()
    let recentViewed = CodexTaskActivity(
        threadID: "recent-viewed",
        title: "刚刚完成且已查看",
        state: .completed,
        updatedAt: now.addingTimeInterval(-5)
    )
    let oldUnviewed = CodexTaskActivity(
        threadID: "old-unviewed",
        title: "较早完成但未查看",
        state: .completed,
        updatedAt: now.addingTimeInterval(-60)
    )
    let oldViewed = CodexTaskActivity(
        threadID: "old-viewed",
        title: "较早完成且已查看",
        state: .completed,
        updatedAt: now.addingTimeInterval(-70)
    )
    let viewedReceiptIDs = Set([
        recentViewed.resolvedReceiptID!,
        oldViewed.resolvedReceiptID!
    ])

    let visible = CodexTaskActivityOrdering.visible(
        from: [recentViewed, oldUnviewed, oldViewed],
        limit: 5,
        viewedResolvedReceiptIDs: viewedReceiptIDs,
        trackedUnviewedThreadIDs: [oldUnviewed.threadID],
        now: now
    )
    #expect(visible.map(\.threadID) == ["recent-viewed", "old-unviewed"])

    let afterMinimumWindow = CodexTaskActivityOrdering.visible(
        from: [recentViewed, oldUnviewed, oldViewed],
        limit: 5,
        viewedResolvedReceiptIDs: viewedReceiptIDs,
        trackedUnviewedThreadIDs: [oldUnviewed.threadID],
        now: now.addingTimeInterval(30)
    )
    #expect(afterMinimumWindow.map(\.threadID) == ["old-unviewed"])

    let historicalUntracked = CodexTaskActivityOrdering.visible(
        from: [oldUnviewed],
        limit: 5,
        now: now
    )
    #expect(historicalUntracked.isEmpty)
}

@Test func acknowledgedCompletedDesktopTaskDisappearsImmediatelyAndOnlyOnce() {
    let now = Date()
    let acknowledged = CodexTaskActivity(
        threadID: "acknowledged",
        title: "已确认任务",
        state: .completed,
        updatedAt: now.addingTimeInterval(-2)
    )
    let otherCompleted = CodexTaskActivity(
        threadID: "other-completed",
        title: "另一项完成任务",
        state: .completed,
        updatedAt: now.addingTimeInterval(-3)
    )
    let active = CodexTaskActivity(
        threadID: "active",
        title: "进行中任务",
        state: .thinking,
        updatedAt: now
    )

    let visible = CodexTaskActivityOrdering.visible(
        from: [acknowledged, otherCompleted, active],
        limit: 5,
        acknowledgedResolvedReceiptIDs: [acknowledged.resolvedReceiptID!],
        trackedUnviewedThreadIDs: [acknowledged.threadID, otherCompleted.threadID],
        now: now
    )

    #expect(visible.map(\.threadID) == ["active", "other-completed"])
}

@Test func hoverTimingAvoidsAccidentalFlyoversAndVisibleGaps() {
    #expect(PinChatVisualMetrics.hoverRevealDelay >= 0.30)
    #expect(PinChatVisualMetrics.hoverRevealDelay < 0.50)
    #expect(PinChatVisualMetrics.hoverDismissDelay >= 0.15)
}

@Test func compactPanelsMatchFrozenV21Targets() {
    #expect(PinChatVisualMetrics.composerSurfaceSize == NSSize(width: 334, height: 40))
    #expect(PinChatVisualMetrics.composerAttachmentSurfaceSize == NSSize(width: 334, height: 78))
    #expect(PinChatVisualMetrics.composerSize == NSSize(width: 414, height: 120))
    #expect(PinChatVisualMetrics.statusSurfaceSize == NSSize(width: 346, height: 58))
    #expect(PinChatVisualMetrics.statusSize == NSSize(width: 426, height: 138))
    #expect(PinChatVisualMetrics.attachmentGap == 3)
    #expect(PinChatVisualMetrics.composerAttachmentSize == NSSize(width: 414, height: 158))
    #expect(PinChatVisualMetrics.composerContentHeight == 40)
    #expect(PinChatVisualMetrics.composerSurfaceOuterInset == 0)
    #expect(PinChatVisualMetrics.composerShadowOutset == 40)
    #expect(PinChatVisualMetrics.statusShadowOutset == 40)
    #expect(PinChatVisualMetrics.desktopStatusSize(taskCount: 1).height == 136)
    #expect(PinChatVisualMetrics.desktopStatusSize(taskCount: 5).height == 324)
    #expect(PinChatVisualMetrics.desktopStatusSize(taskCount: 99).height == 324)
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

@Test func composerSurfaceIgnoresTransparentShadowMarginWhenAttached() {
    let screen = NSRect(x: 0, y: 0, width: 1280, height: 800)
    let pet = NSRect(x: 608, y: 500, width: 64, height: 64)
    let gap = PinChatVisualMetrics.attachmentGap
    let surface = WindowPlacement.stackedFrames(
        sizes: [PinChatVisualMetrics.composerSurfaceSize],
        attachedTo: pet,
        in: screen,
        direction: .below,
        gap: gap
    )[0]
    let panel = WindowPlacement.shadowContainerFrame(
        around: surface,
        outset: PinChatVisualMetrics.composerShadowOutset,
        in: screen
    )
    let visibleSurface = panel.insetBy(
        dx: PinChatVisualMetrics.composerShadowOutset,
        dy: PinChatVisualMetrics.composerShadowOutset
    )

    #expect(visibleSurface.size == PinChatVisualMetrics.composerSurfaceSize)
    #expect(abs(visibleSurface.maxY - (pet.minY - gap)) < 0.001)
}

@Test func statusSurfaceIgnoresTransparentShadowMarginWhenAttached() {
    let screen = NSRect(x: 0, y: 0, width: 1280, height: 800)
    let pet = NSRect(x: 608, y: 500, width: 64, height: 64)
    let gap = PinChatVisualMetrics.attachmentGap
    let surface = WindowPlacement.stackedFrames(
        sizes: [PinChatVisualMetrics.statusSurfaceSize],
        attachedTo: pet,
        in: screen,
        direction: .below,
        gap: gap
    )[0]
    let panel = WindowPlacement.shadowContainerFrame(
        around: surface,
        outset: PinChatVisualMetrics.statusShadowOutset,
        in: screen
    )
    let visibleSurface = panel.insetBy(
        dx: PinChatVisualMetrics.statusShadowOutset,
        dy: PinChatVisualMetrics.statusShadowOutset
    )

    #expect(visibleSurface.size == PinChatVisualMetrics.statusSurfaceSize)
    #expect(abs(visibleSurface.maxY - (pet.minY - gap)) < 0.001)
}

@Test func followUpSendKeepsExpandedConversationVisible() {
    #expect(ConversationSendPresentation.resolve(
        answerIsVisible: true,
        answerWindowIsVisible: true
    ) == .expandedConversation)
    #expect(ConversationSendPresentation.resolve(
        answerIsVisible: true,
        answerWindowIsVisible: false
    ) == .statusOnly)
    #expect(ConversationSendPresentation.resolve(
        answerIsVisible: false,
        answerWindowIsVisible: true
    ) == .statusOnly)
}

@Test func conversationPresentationExpandsForAnswersAndLocksToWork() {
    #expect(ConversationTurnPresentation.undetermined.observing(.answer) == .conversation)
    #expect(ConversationTurnPresentation.undetermined.observing(.workActivity) == .work)
    #expect(ConversationTurnPresentation.conversation.observing(.workActivity) == .work)
    #expect(ConversationTurnPresentation.work.observing(.answer) == .work)
}

@Test func appServerClassifiesExecutionEventsAsWork() {
    let workItems = [
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
    ]
    #expect(workItems.allSatisfy(CodexAppServer.isWorkItemType))
    #expect(!CodexAppServer.isWorkItemType("agentMessage"))
    #expect(!CodexAppServer.isWorkItemType("reasoning"))
    #expect(CodexAppServer.isWorkRequestMethod("item/fileChange/requestApproval"))
    #expect(CodexAppServer.isWorkRequestMethod("item/tool/requestUserInput"))
    #expect(!CodexAppServer.isWorkRequestMethod("account/updated"))
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
    #expect(PetAnimation.resolve(isDragging: false, isGenerating: false, hasError: false, hasAnswer: true) == .idle)
    #expect(PetAnimation.resolve(isDragging: false, isGenerating: false, hasError: false, hasAnswer: false) == .idle)
    #expect(PetAnimation.resolve(
        isDragging: false,
        isGenerating: false,
        hasError: false,
        hasAnswer: false,
        hasCompletionSignal: true
    ) == .review)
}

@Test func petIdleUsesOfficialSlowTimingAndStartsStill() {
    #expect(PetAnimation.idle.frameIndex(elapsed: 0, frameCount: 6) == 0)
    #expect(PetAnimation.idle.frameIndex(elapsed: 1.67, frameCount: 6) == 0)
    #expect(PetAnimation.idle.frameIndex(elapsed: 1.68, frameCount: 6) == 1)
    #expect(PetAnimation.idle.frameIndex(elapsed: 2.35, frameCount: 6) == 2)
    #expect(PetAnimation.idle.frameIndex(elapsed: 6.59, frameCount: 6) == 5)
    #expect(PetAnimation.idle.frameIndex(elapsed: 6.60, frameCount: 6) == 0)
}

@Test func petLookDirectionMatchesOfficialSixteenWayCompass() throws {
    let center = CGPoint(x: 200, y: 200)
    let samples: [(angle: Double, index: Int)] = [
        (0, 0),
        (22.5, 1),
        (45, 2),
        (90, 4),
        (180, 8),
        (270, 12),
        (337.5, 15),
        (359, 0)
    ]

    for sample in samples {
        let radians = sample.angle * .pi / 180
        let caretPosition = CGPoint(
            x: center.x + CGFloat(sin(radians) * 100),
            y: center.y + CGFloat(cos(radians) * 100)
        )
        let direction = try #require(PetLookDirection.resolve(
            mascotCenter: center,
            target: caretPosition
        ))
        #expect(direction.index == sample.index)
    }
}

@Test func petLookDirectionUsesIdleInsideCenterDeadZone() {
    let center = CGPoint(x: 100, y: 100)
    #expect(PetLookDirection.resolve(mascotCenter: center, target: center) == nil)
    #expect(PetLookDirection.resolve(
        mascotCenter: center,
        target: CGPoint(x: 100.5, y: 100.5)
    ) == nil)
    #expect(PetLookDirection.resolve(
        mascotCenter: center,
        target: CGPoint(x: 100, y: 102)
    ) == PetLookDirection(index: 0))
}

@Test func petLookFramesMapToTheTwoOfficialRows() {
    #expect(PetLookDirection(index: 0).columnIndex == 0)
    #expect(PetLookDirection(index: 0).rowIndex == 9)
    #expect(PetLookDirection(index: 7).columnIndex == 7)
    #expect(PetLookDirection(index: 7).rowIndex == 9)
    #expect(PetLookDirection(index: 8).columnIndex == 0)
    #expect(PetLookDirection(index: 8).rowIndex == 10)
    #expect(PetLookDirection(index: 15).columnIndex == 7)
    #expect(PetLookDirection(index: 15).rowIndex == 10)
}

@Test func petSpriteLayoutsKeepBasicAssetCompatibility() {
    #expect(PetSpriteSheetLayout.detect(width: 1536, height: 1872) == .basic)
    #expect(PetSpriteSheetLayout.detect(width: 1536, height: 2288) == .directional)
    #expect(PetSpriteSheetLayout.detect(width: 1024, height: 2288) == nil)
    #expect(PetSpriteSheetLayout.detect(width: 1536, height: 2048) == nil)
}

@Test func transientPetAnimationsOverrideCursorFacing() {
    #expect(PetAnimation.idle.allowsDirectionalPose)
    #expect(PetAnimation.working.allowsDirectionalPose)
    #expect(PetAnimation.waving.allowsDirectionalPose)
    #expect(!PetAnimation.jumping.allowsDirectionalPose)
    #expect(!PetAnimation.failed.allowsDirectionalPose)
    #expect(!PetAnimation.runningLeft.allowsDirectionalPose)
    #expect(!PetAnimation.runningRight.allowsDirectionalPose)
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

@Test func inheritedPermissionConfigurationsMatchOfficialCodexSemantics() {
    #expect(CodexPermissionConfiguration.askForApproval.approvalPolicy == "on-request")
    #expect(CodexPermissionConfiguration.askForApproval.approvalsReviewer == "user")
    #expect(CodexPermissionConfiguration.askForApproval.sandboxMode == "workspace-write")

    #expect(CodexPermissionConfiguration.approveForMe.approvalPolicy == "on-request")
    #expect(CodexPermissionConfiguration.approveForMe.approvalsReviewer == "auto_review")
    #expect(CodexPermissionConfiguration.approveForMe.sandboxMode == "workspace-write")

    #expect(CodexPermissionConfiguration.fullAccess.approvalPolicy == "never")
    #expect(CodexPermissionConfiguration.fullAccess.sandboxMode == "danger-full-access")
}

@Test func codexDesktopPermissionSelectionIsReadFromSharedState() throws {
    let fullAccess = try #require("""
    {
      "electron-persisted-atom-state": {
        "agent-mode-by-host-id": {"local": "auto"},
        "permission-selection-by-host-id:local": {
          "kind": "agent-mode",
          "agentMode": "full-access"
        }
      }
    }
    """.data(using: .utf8))
    #expect(CodexDesktopPermissionSettings.configuration(from: fullAccess) == .fullAccess)

    let profile = try #require("""
    {
      "electron-persisted-atom-state": {
        "permission-selection-by-host-id:local": {
          "kind": "profile",
          "profileId": "trusted-projects"
        }
      }
    }
    """.data(using: .utf8))
    #expect(
        CodexDesktopPermissionSettings.configuration(from: profile)
            == .profile("trusted-projects")
    )
}

@Test func appServerThreadsAndTurnsReceiveInheritedCodexPermissions() throws {
    let start = CodexAppServer.threadStartParameters(
        workingDirectory: "/tmp/workspace",
        permissionConfiguration: .approveForMe
    )
    #expect(start["approvalPolicy"] as? String == "on-request")
    #expect(start["approvalsReviewer"] as? String == "auto_review")
    #expect(start["sandbox"] as? String == "workspace-write")

    let resume = CodexAppServer.threadResumeParameters(
        threadID: "thread-1",
        workingDirectory: "/tmp/workspace",
        permissionConfiguration: .fullAccess
    )
    #expect(resume["threadId"] as? String == "thread-1")
    #expect(resume["approvalPolicy"] as? String == "never")
    #expect(resume["sandbox"] as? String == "danger-full-access")

    let turn = CodexAppServer.turnStartPermissionParameters(
        workingDirectory: "/tmp/workspace",
        permissionConfiguration: .fullAccess
    )
    #expect(turn["approvalPolicy"] as? String == "never")
    let sandboxPolicy = try #require(turn["sandboxPolicy"] as? [String: Any])
    #expect(sandboxPolicy["type"] as? String == "dangerFullAccess")

    let inherited = CodexAppServer.threadStartParameters(
        workingDirectory: "/tmp/workspace",
        permissionConfiguration: .serverDefault
    )
    #expect(inherited["approvalPolicy"] == nil)
    #expect(inherited["approvalsReviewer"] == nil)
    #expect(inherited["sandbox"] == nil)
}

@Test func commandApprovalSupportsOnceSessionAndDeclineDecisions() throws {
    let request = try #require(CodexAppServer.approvalRequest(
        method: "item/commandExecution/requestApproval",
        requestID: .string("approval-1"),
        params: [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "itemId": "item-1",
            "kind": "command",
            "command": "du -sh ~/Downloads",
            "cwd": "/Users/example",
            "reason": "需要检查下载目录",
            "availableDecisions": ["accept", "acceptForSession", "decline"]
        ]
    ))
    #expect(request.kind == .commandExecution)
    #expect(request.canAllowForSession)
    #expect(request.detail == "du -sh ~/Downloads")

    #expect(CodexAppServer.approvalResponse(
        for: request,
        decision: .allowOnce
    )?["decision"] as? String == "accept")
    #expect(CodexAppServer.approvalResponse(
        for: request,
        decision: .allowForSession
    )?["decision"] as? String == "acceptForSession")
    #expect(CodexAppServer.approvalResponse(
        for: request,
        decision: .decline
    )?["decision"] as? String == "decline")
}

@Test func permissionApprovalReturnsOnlyTheExplicitlyRequestedScope() throws {
    let request = try #require(CodexAppServer.approvalRequest(
        method: "item/permissions/requestApproval",
        requestID: .number(42),
        params: [
            "threadId": "thread-1",
            "turnId": "turn-1",
            "itemId": "item-1",
            "cwd": "/tmp/workspace",
            "reason": "读取资料并访问网络",
            "permissions": [
                "fileSystem": [
                    "read": ["/Users/example/Documents"],
                    "write": NSNull()
                ],
                "network": ["enabled": true]
            ]
        ]
    ))
    #expect(request.kind == .permissions)
    #expect(request.detail.contains("/Users/example/Documents"))
    #expect(request.detail.contains("访问网络"))

    let granted = try #require(CodexAppServer.approvalResponse(
        for: request,
        decision: .allowForSession
    ))
    #expect(granted["scope"] as? String == "session")
    let grantedPermissions = try #require(granted["permissions"] as? [String: Any])
    #expect(grantedPermissions["fileSystem"] != nil)
    #expect(grantedPermissions["network"] != nil)

    let declined = try #require(CodexAppServer.approvalResponse(
        for: request,
        decision: .decline
    ))
    #expect(declined["scope"] as? String == "turn")
    #expect((declined["permissions"] as? [String: Any])?.isEmpty == true)
}
