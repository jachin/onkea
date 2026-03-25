import Foundation
import Testing
@testable import YouGoHugo

struct MarkdownHighlightingTests {
    @Test
    func capturesInlineMarkdownRuns() {
        let source = "**Bold** and *italic* with [link](https://example.com) plus `code`."
        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .strong, in: source, runs: runs).contains("Bold"))
        #expect(substrings(for: .emphasis, in: source, runs: runs).contains("italic"))
        #expect(substrings(for: .link, in: source, runs: runs).contains("link"))
        #expect(substrings(for: .code, in: source, runs: runs).contains("code"))
    }

    @Test
    func capturesBlockMarkdownRuns() {
        let source = "# Heading\n\n> Quoted text\n\n- Item one\n\n```swift\nlet value = 1\n```\n"
        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .heading(level: 1), in: source, runs: runs).contains("Heading"))
        #expect(substrings(for: .quote, in: source, runs: runs).contains("Quoted text"))
        #expect(substrings(for: .list, in: source, runs: runs).contains("Item one"))
        #expect(substrings(for: .code, in: source, runs: runs).contains("```swift\nlet value = 1\n```"))
    }

    @Test
    func capturesSyntaxMarkersSeparately() {
        let source = "## Heading\n> Quote\n1. Item\n"
        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        let markers = substrings(for: .syntaxMarker, in: source, runs: runs)
        #expect(markers.contains("##"))
        #expect(markers.contains("> "))
        #expect(markers.contains("1. "))
    }

    private func substrings(for role: MarkdownSemanticRole, in source: String, runs: [MarkdownSemanticRun]) -> [String] {
        runs.compactMap { run in
            guard matches(run.role, role),
                  let range = Range(run.range, in: source) else {
                return nil
            }

            return String(source[range])
        }
    }

    private func matches(_ lhs: MarkdownSemanticRole, _ rhs: MarkdownSemanticRole) -> Bool {
        switch (lhs, rhs) {
        case (.heading(let lhsLevel), .heading(let rhsLevel)):
            lhsLevel == rhsLevel
        case (.strong, .strong), (.emphasis, .emphasis), (.code, .code), (.link, .link), (.quote, .quote), (.list, .list), (.thematicBreak, .thematicBreak), (.syntaxMarker, .syntaxMarker):
            true
        default:
            false
        }
    }
}
