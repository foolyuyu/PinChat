import Foundation

struct SessionStore {
    private let fileURL: URL

    init(baseDirectory: URL? = nil) {
        let root = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        fileURL = root
            .appendingPathComponent("PinChat", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    func load() -> [ChatSession] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.pinChat.decode([ChatSession].self, from: data)) ?? []
    }

    func save(_ sessions: [ChatSession]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.pinChat.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pinChat: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var pinChat: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
