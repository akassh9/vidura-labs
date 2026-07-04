//
//  MarkdownContentView.swift
//  Physics Companion
//
//  Renders Markdown-formatted text from the chatbot in chat bubbles.
//  Supports: headings, bold, italic, inline code, fenced code blocks,
//  unordered/ordered lists, and links.
//

import SwiftUI

/// A view that renders a Markdown string with block-level formatting.
struct MarkdownContentView: View {
    let content: String

    private var blocks: [MarkdownBlock] {
        Self.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)
        case .unorderedList(let items):
            unorderedListView(items: items)
        case .orderedList(let items):
            orderedListView(items: items)
        case .paragraph(let text):
            inlineMarkdownText(text)
        }
    }

    // MARK: - Heading

    private func headingView(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.bold()
        }
        return inlineMarkdownText(text)
            .font(font)
            .padding(.top, level <= 2 ? 4 : 2)
    }

    // MARK: - Code Block

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, language.isEmpty ? 8 : 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Lists

    private func unorderedListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    inlineMarkdownText(item)
                }
            }
        }
        .padding(.leading, 4)
    }

    private func orderedListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    inlineMarkdownText(item)
                }
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Inline Markdown

    /// Renders inline markdown (bold, italic, code, links) using AttributedString.
    private func inlineMarkdownText(_ text: String) -> Text {
        let sanitized = Self.sanitizeLaTeX(text)
        if let attributed = try? AttributedString(
            markdown: sanitized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    /// Converts inline LaTeX math (`$...$`) to inline code spans so that
    /// underscores, backslashes, and braces aren't misinterpreted by the
    /// Markdown parser.
    private static func sanitizeLaTeX(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\\)\$(?!\$)(.+?)(?<!\\)\$"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "`$1`")
    }

    // MARK: - Parser

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case codeBlock(language: String, code: String)
        case unorderedList(items: [String])
        case orderedList(items: [String])
        case paragraph(text: String)
    }

    /// Parses a Markdown string into an array of blocks.
    private static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // skip closing ```
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Heading
            if let match = line.range(of: #"^(#{1,4})\s+(.+)$"#, options: .regularExpression) {
                let full = String(line[match])
                let hashCount = full.prefix(while: { $0 == "#" }).count
                let text = String(full.drop(while: { $0 == "#" }).dropFirst()) // drop the space
                blocks.append(.heading(level: hashCount, text: text))
                i += 1
                continue
            }

            // Unordered list
            if line.matches(of: /^\s*[-*+]\s+/).first != nil {
                var items: [String] = []
                while i < lines.count, lines[i].matches(of: /^\s*[-*+]\s+/).first != nil {
                    let item = lines[i].replacing(/^\s*[-*+]\s+/, with: "")
                    items.append(item)
                    i += 1
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // Ordered list
            if line.matches(of: /^\s*\d+[.)]\s+/).first != nil {
                var items: [String] = []
                while i < lines.count, lines[i].matches(of: /^\s*\d+[.)]\s+/).first != nil {
                    let item = lines[i].replacing(/^\s*\d+[.)]\s+/, with: "")
                    items.append(item)
                    i += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Empty line — skip
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Paragraph: accumulate contiguous non-blank, non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let current = lines[i]
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty
                    || trimmed.hasPrefix("```")
                    || trimmed.matches(of: /^#{1,4}\s+/).first != nil
                    || trimmed.matches(of: /^\s*[-*+]\s+/).first != nil
                    || trimmed.matches(of: /^\s*\d+[.)]\s+/).first != nil {
                    break
                }
                paraLines.append(current)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(text: paraLines.joined(separator: "\n")))
            }
        }

        return blocks
    }
}
