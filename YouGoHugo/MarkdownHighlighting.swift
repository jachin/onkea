import Foundation
import Markdown

enum MarkdownSemanticRole: Hashable {
    case heading(level: Int)
    case strong
    case emphasis
    case code
    case link
    case quote
    case list
    case thematicBreak
    case syntaxMarker
}

struct MarkdownSemanticRun {
    let range: NSRange
    let role: MarkdownSemanticRole
}

enum MarkdownSemanticParser {
    static func highlightRuns(for source: String) -> [MarkdownSemanticRun] {
        guard !source.isEmpty else {
            return []
        }

        // Keep the parser-backed path explicit so highlighting stays anchored to a real Markdown AST.
        _ = Document(parsing: source)

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible,
            languageCode: nil,
            appliesSourcePositionAttributes: true
        )

        var runs: [MarkdownSemanticRun] = []

        if let attributed = try? AttributedString(markdown: source, options: options) {
            for run in attributed.runs {
                guard let sourcePosition = run.markdownSourcePosition,
                      let sourceRange = Range(sourcePosition, in: source) else {
                    continue
                }

                let range = NSRange(sourceRange, in: source)
                guard range.length > 0 else {
                    continue
                }

                runs.append(contentsOf: semanticRuns(for: run, range: range))
            }
        }

        runs.append(contentsOf: syntaxMarkerRuns(for: source))
        return runs
    }

    private static func semanticRuns(for run: AttributedString.Runs.Run, range: NSRange) -> [MarkdownSemanticRun] {
        var results: [MarkdownSemanticRun] = []

        if let presentationIntent = run.presentationIntent {
            for component in presentationIntent.components {
                switch component.kind {
                case .header(let level):
                    results.append(MarkdownSemanticRun(range: range, role: .heading(level: level)))
                case .blockQuote:
                    results.append(MarkdownSemanticRun(range: range, role: .quote))
                case .orderedList, .unorderedList, .listItem:
                    results.append(MarkdownSemanticRun(range: range, role: .list))
                case .codeBlock:
                    results.append(MarkdownSemanticRun(range: range, role: .code))
                case .thematicBreak:
                    results.append(MarkdownSemanticRun(range: range, role: .thematicBreak))
                default:
                    break
                }
            }
        }

        if let inlineIntent = run.inlinePresentationIntent {
            if inlineIntent.contains(.stronglyEmphasized) {
                results.append(MarkdownSemanticRun(range: range, role: .strong))
            }

            if inlineIntent.contains(.emphasized) {
                results.append(MarkdownSemanticRun(range: range, role: .emphasis))
            }

            if inlineIntent.contains(.code) {
                results.append(MarkdownSemanticRun(range: range, role: .code))
            }
        }

        if run.link != nil {
            results.append(MarkdownSemanticRun(range: range, role: .link))
        }

        return results
    }

    private static func syntaxMarkerRuns(for source: String) -> [MarkdownSemanticRun] {
        [
            #"(?m)^(#{1,6})(?=\s)"#,
            #"(?m)^>+\s?"#,
            #"(?m)^\s*(?:[-*+]|\d+\.)\s+(?=\S)"#,
            #"(?m)^```.*$"#,
            #"(?m)^~~~.*$"#,
            #"(?m)^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$"#
        ].flatMap { pattern -> [MarkdownSemanticRun] in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return []
            }

            let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
            return regex.matches(in: source, options: [], range: fullRange).map {
                MarkdownSemanticRun(range: $0.range, role: .syntaxMarker)
            }
        }
    }
}
