import AppKit
import ImageIO
import SwiftUI

enum PetAnimation: Int, CaseIterable, Sendable {
    case idle = 0
    case runningRight = 1
    case runningLeft = 2
    case waving = 3
    case jumping = 4
    case failed = 5
    case waiting = 6
    case working = 7
    case review = 8

    var frameInterval: TimeInterval {
        switch self {
        case .idle: 0.22
        case .working, .runningLeft, .runningRight: 0.09
        case .waving, .jumping: 0.11
        case .failed, .waiting, .review: 0.14
        }
    }

    var allowsDirectionalPose: Bool {
        switch self {
        case .idle, .working, .waving:
            true
        case .runningRight, .runningLeft, .jumping, .failed, .waiting, .review:
            false
        }
    }

    static func resolve(
        isDragging: Bool,
        isGenerating: Bool,
        hasError: Bool,
        hasAnswer: Bool
    ) -> PetAnimation {
        if isDragging { return .jumping }
        if isGenerating { return .working }
        if hasError { return .failed }
        if hasAnswer { return .waving }
        return .idle
    }
}

struct PetLookDirection: Hashable, Sendable {
    static let count = 16

    let index: Int

    init(index: Int) {
        self.index = ((index % Self.count) + Self.count) % Self.count
    }

    var columnIndex: Int { index % 8 }
    var rowIndex: Int { 9 + index / 8 }
    var angleDegrees: Double { Double(index) * 22.5 }

    static func resolve(
        mascotCenter: CGPoint,
        target: CGPoint,
        deadZoneRadius: CGFloat = 1
    ) -> PetLookDirection? {
        let dx = target.x - mascotCenter.x
        let dy = target.y - mascotCenter.y
        guard hypot(dx, dy) > deadZoneRadius else { return nil }

        // AppKit screen coordinates point upward. This is equivalent to the
        // official web implementation's atan2(dx, -dy) in downward-pointing DOM coordinates.
        let radians = atan2(dx, dy)
        let normalizedDegrees = (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalizedDegrees / 22.5).rounded()) % count
        return PetLookDirection(index: index)
    }
}

enum PetSpriteSheetLayout: Equatable, Sendable {
    case basic
    case directional

    static func detect(width: Int, height: Int) -> PetSpriteSheetLayout? {
        guard width == 1536 else { return nil }
        return switch height {
        case 1872: .basic
        case 2288: .directional
        default: nil
        }
    }

    var rowCount: Int {
        switch self {
        case .basic: 9
        case .directional: 11
        }
    }
}

enum CodexPetAssetExtractor {
    private struct Entry {
        let path: String
        let size: Int
        let offset: UInt64
        let version: Int
    }

    nonisolated static func directionalSpriteData() -> Data? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let archives = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/app.asar"),
            home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/app.asar")
        ]

        for archive in archives where manager.fileExists(atPath: archive.path) {
            guard let candidates = try? spriteCandidates(in: archive) else { continue }
            for data in candidates where PetSpriteStore.layout(for: data) == .directional {
                return data
            }
        }
        return nil
    }

    private nonisolated static func spriteCandidates(in archiveURL: URL) throws -> [Data] {
        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }

        let prefix = try requireData(handle.read(upToCount: 16), count: 16)
        let pickleSize = try littleEndianUInt32(in: prefix, at: 4)
        let headerSize = try littleEndianUInt32(in: prefix, at: 12)
        guard headerSize > 0, headerSize <= 32 * 1024 * 1024 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let headerData = try requireData(
            handle.read(upToCount: Int(headerSize)),
            count: Int(headerSize)
        )
        guard let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }

        var entries: [Entry] = []
        collectEntries(node: header, path: "", result: &entries)
        entries.sort {
            if $0.version != $1.version { return $0.version > $1.version }
            return $0.path > $1.path
        }

        let contentOffset = UInt64(8) + UInt64(pickleSize)
        var result: [Data] = []
        for entry in entries {
            guard entry.size > 0, entry.size <= 16 * 1024 * 1024 else { continue }
            try handle.seek(toOffset: contentOffset + entry.offset)
            if let data = try? requireData(
                handle.read(upToCount: entry.size),
                count: entry.size
            ) {
                result.append(data)
            }
        }
        return result
    }

    private nonisolated static func collectEntries(
        node: [String: Any],
        path: String,
        result: inout [Entry]
    ) {
        guard let files = node["files"] as? [String: Any] else { return }
        for (name, value) in files {
            guard let child = value as? [String: Any] else { continue }
            let childPath = path.isEmpty ? name : "\(path)/\(name)"
            if child["files"] != nil {
                collectEntries(node: child, path: childPath, result: &result)
                continue
            }
            guard name.hasPrefix("codex-spritesheet-v"),
                  name.hasSuffix(".webp"),
                  let size = child["size"] as? Int,
                  let offsetString = child["offset"] as? String,
                  let offset = UInt64(offsetString) else { continue }
            result.append(Entry(
                path: childPath,
                size: size,
                offset: offset,
                version: spriteVersion(from: name)
            ))
        }
    }

    private nonisolated static func spriteVersion(from filename: String) -> Int {
        guard let marker = filename.range(of: "codex-spritesheet-v") else { return 0 }
        let suffix = filename[marker.upperBound...]
        return Int(suffix.prefix { $0.isNumber }) ?? 0
    }

    private nonisolated static func littleEndianUInt32(in data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data[offset..<(offset + 4)].enumerated().reduce(UInt32(0)) { partial, pair in
            partial | UInt32(pair.element) << UInt32(pair.offset * 8)
        }
    }

    private nonisolated static func requireData(_ data: Data?, count: Int) throws -> Data {
        guard let data, data.count == count else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
}

@MainActor
final class PetSpriteStore: ObservableObject {
    static let officialAssetURL = URL(
        string: "https://persistent.oaistatic.com/codex/pets/v1/codex-spritesheet-v4.webp"
    )!

    @Published private(set) var frames: [PetAnimation: [NSImage]] = [:]
    @Published private(set) var lookFrames: [PetLookDirection: NSImage] = [:]
    @Published private(set) var isUsingFallback = true

    var supportsDirectionalLook: Bool { lookFrames.count == PetLookDirection.count }

    init() {
        Task { await load() }
    }

    func frame(for animation: PetAnimation, at date: Date) -> NSImage? {
        guard let images = frames[animation], !images.isEmpty else { return nil }
        let tick = Int(date.timeIntervalSinceReferenceDate / animation.frameInterval)
        return images[tick % images.count]
    }

    func frame(for direction: PetLookDirection) -> NSImage? {
        lookFrames[direction]
    }

    private func load() async {
        if let data = Self.cachedDirectionalAsset(), install(data: data) {
            return
        }

        if let data = await Task.detached(priority: .utility, operation: {
            CodexPetAssetExtractor.directionalSpriteData()
        }).value,
           install(data: data) {
            try? Self.persist(data: data, filename: "codex-spritesheet-directional.webp")
            return
        }

        if let data = Self.firstBasicAsset(), install(data: data) { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.officialAssetURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  install(data: data) else { return }
            try? Self.persist(data: data, filename: "codex-spritesheet-v4.webp")
        } catch {
            // The vector fallback remains available offline.
        }
    }

    @discardableResult
    private func install(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let layout = PetSpriteSheetLayout.detect(
                width: sheet.width,
                height: sheet.height
              ) else { return false }

        let frameWidth = sheet.width / 8
        let frameHeight = sheet.height / layout.rowCount
        var decoded: [PetAnimation: [NSImage]] = [:]
        for animation in PetAnimation.allCases {
            let row = animation.rawValue
            decoded[animation] = (0..<8).compactMap { column in
                let rect = CGRect(
                    x: column * frameWidth,
                    y: row * frameHeight,
                    width: frameWidth,
                    height: frameHeight
                )
                guard let image = sheet.cropping(to: rect),
                      Self.hasVisibleContent(image) else { return nil }
                return NSImage(
                    cgImage: image,
                    size: NSSize(width: frameWidth, height: frameHeight)
                )
            }
        }
        var decodedLookFrames: [PetLookDirection: NSImage] = [:]
        if layout == .directional {
            for index in 0..<PetLookDirection.count {
                let direction = PetLookDirection(index: index)
                let rect = CGRect(
                    x: direction.columnIndex * frameWidth,
                    y: direction.rowIndex * frameHeight,
                    width: frameWidth,
                    height: frameHeight
                )
                guard let image = sheet.cropping(to: rect),
                      Self.hasVisibleContent(image) else { continue }
                decodedLookFrames[direction] = NSImage(
                    cgImage: image,
                    size: NSSize(width: frameWidth, height: frameHeight)
                )
            }
        }
        frames = decoded
        lookFrames = decodedLookFrames
        isUsingFallback = false
        return true
    }

    nonisolated static func layout(for data: Data) -> PetSpriteSheetLayout? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return PetSpriteSheetLayout.detect(width: width, height: height)
    }

    nonisolated static func hasVisibleContent(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var visiblePixels = 0
        let threshold = max(100, width * height / 20)
        for alphaIndex in stride(from: 3, to: pixels.count, by: 4) {
            if pixels[alphaIndex] > 8 {
                visiblePixels += 1
                if visiblePixels > threshold { return true }
            }
        }
        return false
    }

    private static func cachedDirectionalAsset() -> Data? {
        let url = cacheURL(filename: "codex-spritesheet-directional.webp")
        return try? Data(contentsOf: url)
    }

    private static func firstBasicAsset() -> Data? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let codexCache = home
            .appendingPathComponent(".codex/cache/tui-pets/v1/assets", isDirectory: true)
            .appendingPathComponent("codex-spritesheet-v4.webp")
        let pinChatCache = cacheURL(filename: "codex-spritesheet-v4.webp")
        for url in [codexCache, pinChatCache] where manager.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    private static func persist(data: Data, filename: String) throws {
        let url = cacheURL(filename: filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func cacheURL(filename: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PinChat/Pets", isDirectory: true)
            .appendingPathComponent(filename)
    }
}

struct PetSpriteView: View {
    @ObservedObject var store: PetSpriteStore
    let animation: PetAnimation
    let lookDirection: PetLookDirection?

    var body: some View {
        Group {
            if let lookDirection,
               let image = store.frame(for: lookDirection) {
                spriteImage(image)
            } else {
                TimelineView(.animation(minimumInterval: animation.frameInterval)) { context in
                    if let image = store.frame(for: animation, at: context.date) {
                        spriteImage(image)
                    } else {
                        FallbackCodexPet(animation: animation)
                    }
                }
            }
        }
    }

    private func spriteImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.none)
            .aspectRatio(192.0 / 208.0, contentMode: .fit)
    }
}

private struct FallbackCodexPet: View {
    let animation: PetAnimation

    private var tilt: Angle {
        switch animation {
        case .failed: .degrees(-7)
        case .jumping: .degrees(5)
        default: .zero
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: -3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.40, green: 0.64, blue: 1.0),
                                         Color(red: 0.24, green: 0.42, blue: 0.94)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 25, style: .continuous)
                                .stroke(Color(red: 0.10, green: 0.23, blue: 0.63), lineWidth: 3)
                        }
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.03, green: 0.13, blue: 0.31))
                        .frame(width: 60, height: 34)
                        .overlay {
                            HStack(spacing: 22) {
                                Text(">")
                                RoundedRectangle(cornerRadius: 1).frame(width: 11, height: 2)
                            }
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.cyan.opacity(0.9))
                        }
                }
                .frame(width: 102, height: 83)

                HStack(spacing: 7) {
                    Capsule().fill(Color.blue).frame(width: 13, height: 37).rotationEffect(.degrees(12))
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.24, green: 0.48, blue: 0.98))
                            .frame(width: 55, height: 38)
                            .overlay(Text("›_").font(.system(size: 17, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.85)))
                        HStack(spacing: 22) {
                            Capsule().fill(Color(red: 0.18, green: 0.33, blue: 0.80)).frame(width: 13, height: 23)
                            Capsule().fill(Color(red: 0.18, green: 0.33, blue: 0.80)).frame(width: 13, height: 23)
                        }
                    }
                    Capsule().fill(Color.blue).frame(width: 13, height: 37).rotationEffect(.degrees(-12))
                }
            }
        }
        .rotationEffect(tilt)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .accessibilityLabel("Codex 桌宠")
    }
}
