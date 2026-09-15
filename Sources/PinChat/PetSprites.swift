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

@MainActor
final class PetSpriteStore: ObservableObject {
    static let officialAssetURL = URL(
        string: "https://persistent.oaistatic.com/codex/pets/v1/codex-spritesheet-v4.webp"
    )!

    @Published private(set) var frames: [PetAnimation: [NSImage]] = [:]
    @Published private(set) var isUsingFallback = true

    init() {
        Task { await load() }
    }

    func frame(for animation: PetAnimation, at date: Date) -> NSImage? {
        guard let images = frames[animation], !images.isEmpty else { return nil }
        let tick = Int(date.timeIntervalSinceReferenceDate / animation.frameInterval)
        return images[tick % images.count]
    }

    private func load() async {
        if let data = Self.firstCachedAsset(), install(data: data) {
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.officialAssetURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  install(data: data) else { return }
            try? Self.persist(data: data)
        } catch {
            // The vector fallback remains available offline.
        }
    }

    @discardableResult
    private func install(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              sheet.width == 1536,
              sheet.height == 1872 else { return false }

        let frameWidth = sheet.width / 8
        let frameHeight = sheet.height / 9
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
        frames = decoded
        isUsingFallback = false
        return true
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

    private static func firstCachedAsset() -> Data? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let codexCache = home
            .appendingPathComponent(".codex/cache/tui-pets/v1/assets", isDirectory: true)
            .appendingPathComponent("codex-spritesheet-v4.webp")
        let pinChatCache = cacheURL()
        for url in [codexCache, pinChatCache] where manager.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    private static func persist(data: Data) throws {
        let url = cacheURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("PinChat/Pets", isDirectory: true)
            .appendingPathComponent("codex-spritesheet-v4.webp")
    }
}

struct PetSpriteView: View {
    @ObservedObject var store: PetSpriteStore
    let animation: PetAnimation

    var body: some View {
        TimelineView(.animation(minimumInterval: animation.frameInterval)) { context in
            if let image = store.frame(for: animation, at: context.date) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(192.0 / 208.0, contentMode: .fit)
            } else {
                FallbackCodexPet(animation: animation)
            }
        }
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
