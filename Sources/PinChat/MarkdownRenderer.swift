import AppKit
import SwiftUI

enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case quote(String)
    case code(language: String?, value: String)
    case divider
}

enum MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listIsOrdered: Bool?
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var insideCodeFence = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty, let ordered = listIsOrdered else { return }
            blocks.append(ordered ? .orderedList(listItems) : .unorderedList(listItems))
            listItems.removeAll()
            listIsOrdered = nil
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(.quote(quoteLines.joined(separator: "\n")))
            quoteLines.removeAll()
        }

        func flushTextContainers() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if insideCodeFence {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(
                        language: codeLanguage?.isEmpty == false ? codeLanguage : nil,
                        value: codeLines.joined(separator: "\n")
                    ))
                    codeLines.removeAll()
                    codeLanguage = nil
                    insideCodeFence = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushTextContainers()
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                insideCodeFence = true
                continue
            }

            if trimmed.isEmpty {
                flushTextContainers()
                continue
            }

            if isDivider(trimmed) {
                flushTextContainers()
                blocks.append(.divider)
                continue
            }

            if let heading = heading(from: trimmed) {
                flushTextContainers()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let quote = quoteText(from: line) {
                flushParagraph()
                flushList()
                quoteLines.append(quote)
                continue
            }

            if let item = unorderedItem(from: line) {
                flushParagraph()
                flushQuote()
                if listIsOrdered == true { flushList() }
                listIsOrdered = false
                listItems.append(item)
                continue
            }

            if let item = orderedItem(from: line) {
                flushParagraph()
                flushQuote()
                if listIsOrdered == false { flushList() }
                listIsOrdered = true
                listItems.append(item)
                continue
            }

            flushList()
            flushQuote()
            paragraph.append(trimmed)
        }

        flushTextContainers()
        if insideCodeFence {
            blocks.append(.code(
                language: codeLanguage?.isEmpty == false ? codeLanguage : nil,
                value: codeLines.joined(separator: "\n")
            ))
        }
        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: markerCount)
        guard markerEnd < line.endIndex, line[markerEnd] == " " else { return nil }
        let text = line[line.index(after: markerEnd)...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (markerCount, text)
    }

    private static func unorderedItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let boundary = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let number = trimmed[..<boundary]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterBoundary = trimmed.index(after: boundary)
        guard afterBoundary < trimmed.endIndex, trimmed[afterBoundary] == " " else { return nil }
        return String(trimmed[trimmed.index(after: afterBoundary)...])
    }

    private static func quoteText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first else { return false }
        return ["-", "*", "_"].contains(first) && compact.allSatisfy { $0 == first }
    }

}

struct MarkdownContentView: View {
    let source: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            InlineMarkdownText(source: text)
                .font(headingFont(level))
                .foregroundStyle(.primary)
                .padding(.top, level <= 2 ? 5 : 2)
        case .paragraph(let text):
            InlineMarkdownText(source: text)
                .font(.system(size: 14.5))
                .lineSpacing(4.5)
        case .unorderedList(let items):
            MarkdownList(items: items, ordered: false)
        case .orderedList(let items):
            MarkdownList(items: items, ordered: true)
        case .quote(let text):
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 2)
                InlineMarkdownText(source: text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
        case .code(let language, let value):
            MarkdownCodeBlock(language: language, value: value)
        case .divider:
            Divider()
                .opacity(0.55)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 20, weight: .semibold)
        case 2: return .system(size: 18, weight: .semibold)
        case 3: return .system(size: 16, weight: .semibold)
        default: return .system(size: 14.5, weight: .semibold)
        }
    }
}

private struct InlineMarkdownText: View {
    let source: String

    private var value: AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }

    var body: some View {
        Text(value)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownList: View {
    let items: [String]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(size: 14.5, weight: ordered ? .medium : .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: ordered ? 22 : 12, alignment: .trailing)
                    InlineMarkdownText(source: item)
                        .font(.system(size: 14.5))
                        .lineSpacing(4)
                }
            }
        }
    }
}

private struct MarkdownCodeBlock: View {
    let language: String?
    let value: String

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(language?.isEmpty == false ? language! : "代码")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("复制代码")
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            Divider().opacity(0.55)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(value.isEmpty ? " " : value)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .onChange(of: value) {
            copied = false
        }
    }
}
