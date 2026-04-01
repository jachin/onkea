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
        #expect(substrings(for: .link, in: source, runs: runs) == ["[link]"])
        #expect(substrings(for: .linkDestination, in: source, runs: runs) == ["(https://example.com)"])
        #expect(substrings(for: .code, in: source, runs: runs) == ["code"])
    }

    @Test
    func parsesWrappedInlineLinksFromPostContent() {
        let source = """
        ---
        title: "2015's Best Books"
        Slug: 2015s-best-books
        date: 2016-01-28
        draft: false
        tags:
         - books
         - politics
         - theology
         - fantasy
         - science fiction
         - history
         - children
        categories:
         - Books
        ---

        The bad news is I only read 17 books in 2015. However I feel pretty good
        about that because I read all 10 of [The Malazan Book of the
        Fallen](https://www.amazon.com/gp/bookseries/B00CKD6UEU/ref=dp_st_0765348780?tag=jacrupsblo-20)
        by Steven Erikson, which are all massive.

        History: [The Last Battle - The Classic History of the Battle for
        Berlin](http://www.amazon.com/Last-Battle-Classic-History-Berlin/dp/0684803291/ref=sr_1_1?ie=UTF8&qid=1454049490&sr=8-1&keywords=The+Last+Battle+-+The+Classic+History+of+the+Battle+for+Berlin&tag=jacrupsblo-20)
        by Cornelius Ryan.

        Theology: [Celebration of Discipline - The Path to Spiritual
        Growth](http://www.amazon.com/Celebration-Discipline-Path-Spiritual-Growth/dp/0060628391/ref=sr_1_1?ie=UTF8&qid=1454049576&sr=8-1&keywords=Celebration+of+Discipline+-+The+Path+to+Spiritual+Growth&tag=jacrupsblo-20)
        by Richard J. Foster.

        Politics: [The Three Languages of
        Politics](http://www.amazon.com/Three-Languages-Politics-Arnold-Kling-ebook/dp/B00CCGF81Q/ref=sr_1_1?ie=UTF8&qid=1454049609&sr=8-1&keywords=The+Three+Languages+of+Politics&tag=jacrupsblo-20)
        by Arnold Kling.

        Autobiography: [The Diving Bell and the Butterfly - A Memoir of Life in
        Death](http://www.amazon.com/Diving-Bell-Butterfly-Memoir-Death/dp/0375701214/ref=sr_1_2?ie=UTF8&qid=1454049648&sr=8-2&keywords=The+Diving+Bell+and+the+Butterfly+-+A+Memoir+of+Life+in+Death&tag=jacrupsblo-20)
        by Jean-Dominique Bauby.

        Raising Children: [Brain Rules for Baby - How to Raise a Smart and Happy
        Child from Zero to
        Five](http://www.amazon.com/Brain-Rules-Baby-Updated-Expanded/dp/0983263388/ref=sr_1_2?ie=UTF8&qid=1454049733&sr=8-2&keywords=Brain+Rules+for+Baby+-+How+to+Raise+a+Smart+and+Happy+Child+from+Zero+to+Five&tag=jacrupsblo-20)
        by John Medina.

        Science Fiction: [Ready Player
        One](http://www.amazon.com/Ready-Player-One-Ernest-Cline/dp/0307887448/ref=sr_1_1?ie=UTF8&qid=1454049762&sr=8-1&keywords=Ready+Player+One&tag=jacrupsblo-20)
        by Ernest Cline.
        """

        let runs = MarkdownSemanticParser.highlightRuns(for: source)
        let links = substrings(for: .link, in: source, runs: runs)
        let destinations = substrings(for: .linkDestination, in: source, runs: runs)

        #expect(links.count == 7)
        #expect(destinations.count == 7)
        #expect(links.contains("[The Malazan Book of the\nFallen]"))
        #expect(destinations.contains("(https://www.amazon.com/gp/bookseries/B00CKD6UEU/ref=dp_st_0765348780?tag=jacrupsblo-20)"))
        #expect(links.contains("[The Last Battle - The Classic History of the Battle for\nBerlin]"))
        #expect(destinations.contains("(http://www.amazon.com/Last-Battle-Classic-History-Berlin/dp/0684803291/ref=sr_1_1?ie=UTF8&qid=1454049490&sr=8-1&keywords=The+Last+Battle+-+The+Classic+History+of+the+Battle+for+Berlin&tag=jacrupsblo-20)"))
        #expect(links.contains("[Celebration of Discipline - The Path to Spiritual\nGrowth]"))
        #expect(destinations.contains("(http://www.amazon.com/Celebration-Discipline-Path-Spiritual-Growth/dp/0060628391/ref=sr_1_1?ie=UTF8&qid=1454049576&sr=8-1&keywords=Celebration+of+Discipline+-+The+Path+to+Spiritual+Growth&tag=jacrupsblo-20)"))
        #expect(links.contains("[The Three Languages of\nPolitics]"))
        #expect(destinations.contains("(http://www.amazon.com/Three-Languages-Politics-Arnold-Kling-ebook/dp/B00CCGF81Q/ref=sr_1_1?ie=UTF8&qid=1454049609&sr=8-1&keywords=The+Three+Languages+of+Politics&tag=jacrupsblo-20)"))
        #expect(links.contains("[The Diving Bell and the Butterfly - A Memoir of Life in\nDeath]"))
        #expect(destinations.contains("(http://www.amazon.com/Diving-Bell-Butterfly-Memoir-Death/dp/0375701214/ref=sr_1_2?ie=UTF8&qid=1454049648&sr=8-2&keywords=The+Diving+Bell+and+the+Butterfly+-+A+Memoir+of+Life+in+Death&tag=jacrupsblo-20)"))
        #expect(links.contains("[Brain Rules for Baby - How to Raise a Smart and Happy\nChild from Zero to\nFive]"))
        #expect(destinations.contains("(http://www.amazon.com/Brain-Rules-Baby-Updated-Expanded/dp/0983263388/ref=sr_1_2?ie=UTF8&qid=1454049733&sr=8-2&keywords=Brain+Rules+for+Baby+-+How+to+Raise+a+Smart+and+Happy+Child+from+Zero+to+Five&tag=jacrupsblo-20)"))
        #expect(links.contains("[Ready Player\nOne]"))
        #expect(destinations.contains("(http://www.amazon.com/Ready-Player-One-Ernest-Cline/dp/0307887448/ref=sr_1_1?ie=UTF8&qid=1454049762&sr=8-1&keywords=Ready+Player+One&tag=jacrupsblo-20)"))
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

        #expect(substrings(for: .link, in: source, runs: runs) == ["[previous post]"])
        #expect(substrings(for: .linkDestination, in: source, runs: runs) == [#"({{< ref "2022-10-22-corn-maze-2022" >}})"#])
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

        #expect(substrings(for: .link, in: source, runs: runs).contains("[The Malazan Book of the Fallen]"))
        #expect(substrings(for: .link, in: source, runs: runs).contains("[The Three Languages of Politics]"))
        #expect(substrings(for: .link, in: source, runs: runs).contains("[Ready Player One]"))
        #expect(substrings(for: .linkDestination, in: source, runs: runs).contains("[malazan]"))
        #expect(substrings(for: .linkDestination, in: source, runs: runs).contains("[]"))
        #expect(substrings(for: .linkDestination, in: source, runs: runs).count == 2)
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
             (.linkDestination, .linkDestination),
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
