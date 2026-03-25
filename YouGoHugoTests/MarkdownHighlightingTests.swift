import Foundation
import Testing
@testable import YouGoHugo

struct MarkdownHighlightingTests {
    @Test
    func parsesYAMLFrontMatter() {
        let source = """
        ---
        title: "Corn Maze"
        draft: true
        date: 2024-10-22
        tags: ["ios", "hugo"]
        ---
        # Heading
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .frontMatterDelimiter, in: source, runs: runs) == ["---", "---"])
        #expect(substrings(for: .frontMatterKey, in: source, runs: runs).contains("title"))
        #expect(substrings(for: .frontMatterString, in: source, runs: runs).contains("Corn Maze"))
        #expect(substrings(for: .frontMatterBoolean, in: source, runs: runs).contains("true"))
        #expect(substrings(for: .frontMatterDate, in: source, runs: runs).contains("2024-10-22"))
        #expect(substrings(for: .frontMatterString, in: source, runs: runs).contains("ios"))
        #expect(substrings(for: .heading(level: 1), in: source, runs: runs) == ["Heading"])
    }

    @Test
    func parsesTOMLFrontMatter() {
        let source = """
        +++
        title = "Corn Maze"
        weight = 7
        draft = false
        [params]
        +++
        Body
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .frontMatterDelimiter, in: source, runs: runs) == ["+++", "+++"])
        #expect(substrings(for: .frontMatterKey, in: source, runs: runs).contains("title"))
        #expect(substrings(for: .frontMatterKey, in: source, runs: runs).contains("[params]"))
        #expect(substrings(for: .frontMatterNumber, in: source, runs: runs).contains("7"))
        #expect(substrings(for: .frontMatterBoolean, in: source, runs: runs).contains("false"))
    }

    @Test
    func parsesJSONFrontMatter() {
        let source = """
        {
          "title": "Corn Maze",
          "draft": true,
          "weight": 5
        }
        # Heading
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .frontMatterDelimiter, in: source, runs: runs).contains("{"))
        #expect(substrings(for: .frontMatterDelimiter, in: source, runs: runs).contains("}"))
        #expect(substrings(for: .frontMatterKey, in: source, runs: runs).contains("title"))
        #expect(substrings(for: .frontMatterString, in: source, runs: runs).contains("Corn Maze"))
        #expect(substrings(for: .frontMatterBoolean, in: source, runs: runs).contains("true"))
        #expect(substrings(for: .frontMatterNumber, in: source, runs: runs).contains("5"))
        #expect(substrings(for: .heading(level: 1), in: source, runs: runs) == ["Heading"])
    }

    @Test
    func parsesMarkdownBlocks() {
        let source = """
        # Heading

        > Quoted text

        1. First item

        ---
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .heading(level: 1), in: source, runs: runs) == ["Heading"])
        #expect(substrings(for: .quote, in: source, runs: runs) == ["Quoted text"])
        #expect(substrings(for: .list, in: source, runs: runs) == ["First item"])
        #expect(substrings(for: .thematicBreak, in: source, runs: runs) == ["---"])
        #expect(substrings(for: .syntaxMarker, in: source, runs: runs).contains("#"))
        #expect(substrings(for: .syntaxMarker, in: source, runs: runs).contains("> "))
        #expect(substrings(for: .syntaxMarker, in: source, runs: runs).contains("1. "))
    }

    @Test
    func parsesInlineMarkdown() {
        let source = "**Bold** and *italic* with [link](https://example.com) plus `code`."
        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .strong, in: source, runs: runs) == ["Bold"])
        #expect(substrings(for: .emphasis, in: source, runs: runs) == ["italic"])
        #expect(substrings(for: .link, in: source, runs: runs) == ["link"])
        #expect(substrings(for: .code, in: source, runs: runs) == ["code"])
    }

    @Test
    func parsesShortcodesAndTemplateActions() {
        let source = """
        {{< youtube _Fip8OnygHU >}}
        {{% note %}}Hi{{% /note %}}
        {{ .Title }}
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .shortcode, in: source, runs: runs).contains("{{< youtube _Fip8OnygHU >}}"))
        #expect(substrings(for: .shortcode, in: source, runs: runs).contains("{{% note %}}"))
        #expect(substrings(for: .shortcode, in: source, runs: runs).contains("{{% /note %}}"))
        #expect(substrings(for: .templateAction, in: source, runs: runs) == ["{{ .Title }}"])
        #expect(substrings(for: .syntaxMarker, in: source, runs: runs).contains("{{<"))
        #expect(substrings(for: .syntaxMarker, in: source, runs: runs).contains(">}}"))
        #expect(substrings(for: .syntaxMarker, in: source, runs: runs).contains("{{"))
        #expect(substrings(for: .syntaxMarker, in: source, runs: runs).contains("}}"))
    }

    @Test
    func parsesLinkTextWhenDestinationContainsHugoShortcode() {
        let source = #"[previous post]({{< ref "2022-10-22-corn-maze-2022" >}})"#
        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .link, in: source, runs: runs) == ["previous post"])
        #expect(substrings(for: .shortcode, in: source, runs: runs) == [#"{{< ref "2022-10-22-corn-maze-2022" >}}"#])
    }

    @Test
    func parsesReferenceStyleLinksAndDefinitions() {
        let source = """
        [The Malazan Book of the Fallen][malazan] by Steven Erikson.
        [The Three Languages of Politics][] by Arnold Kling.
        [Ready Player One] is also linked.

        [malazan]: https://www.amazon.com/malazan
        [the three languages of politics]: https://www.amazon.com/three-languages
        [ready player one]: https://www.amazon.com/ready-player-one
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .link, in: source, runs: runs).contains("The Malazan Book of the Fallen"))
        #expect(substrings(for: .link, in: source, runs: runs).contains("The Three Languages of Politics"))
        #expect(substrings(for: .link, in: source, runs: runs).contains("Ready Player One"))
        #expect(substrings(for: .linkDefinition, in: source, runs: runs).contains("https://www.amazon.com/malazan"))
        #expect(substrings(for: .linkDefinition, in: source, runs: runs).contains("https://www.amazon.com/three-languages"))
        #expect(substrings(for: .linkDefinition, in: source, runs: runs).contains("https://www.amazon.com/ready-player-one"))
    }

    @Test
    func fencedCodeBlocksWinOverMarkdownAndHugoParsing() {
        let source = """
        ```go
        {{< youtube abc >}}
        **not bold**
        ```
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .code, in: source, runs: runs).count == 4)
        #expect(substrings(for: .shortcode, in: source, runs: runs).isEmpty)
        #expect(substrings(for: .strong, in: source, runs: runs).isEmpty)
        #expect(substrings(for: .syntaxMarker, in: source, runs: runs).filter { $0 == "```" }.count == 2)
    }

    @Test
    func frontMatterDoesNotLeakIntoBodyMarkdown() {
        let source = """
        ---
        title: "# Not A Heading"
        ---
        # Real Heading
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)

        #expect(substrings(for: .heading(level: 1), in: source, runs: runs) == ["Real Heading"])
        #expect(substrings(for: .frontMatterString, in: source, runs: runs).contains("# Not A Heading"))
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
        case (.strong, .strong),
             (.emphasis, .emphasis),
             (.code, .code),
             (.link, .link),
             (.quote, .quote),
             (.list, .list),
             (.thematicBreak, .thematicBreak),
             (.syntaxMarker, .syntaxMarker),
             (.frontMatterDelimiter, .frontMatterDelimiter),
             (.frontMatterKey, .frontMatterKey),
             (.frontMatterString, .frontMatterString),
             (.frontMatterNumber, .frontMatterNumber),
             (.frontMatterBoolean, .frontMatterBoolean),
             (.frontMatterDate, .frontMatterDate),
             (.shortcode, .shortcode),
             (.templateAction, .templateAction),
             (.linkDefinition, .linkDefinition):
            true
        default:
            false
        }
    }
}
