import Foundation
import Testing
@testable import YouGoHugo

struct YouGoHugoTests {
    @Test
    func resolvesHugoFromConfiguredExecutable() async throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let executableURL = temporaryDirectory.appendingPathComponent("hugo")
        try Data().write(to: executableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let resolvedURL = hugoExecutableURL(environment: ["HUGO_EXECUTABLE": executableURL.path])

        #expect(resolvedURL == executableURL)
    }

    @Test
    func resolvesHugoFromFallbackPathWhenPathIsMissing() async throws {
        let executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/hugo")

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return
        }

        let resolvedURL = hugoExecutableURL(environment: [:])

        #expect(resolvedURL == executableURL)
    }

    @Test
    func parsesHugoListCSVRows() throws {
        let output = """
        path,slug,title,date,expiryDate,publishDate,draft,permalink,kind,section
        content/posts/hello.md,,Hello World,0001-01-01T00:00:00Z,0001-01-01T00:00:00Z,0001-01-01T00:00:00Z,false,https://example.org/posts/hello/,page,posts
        "content/notes/with,comma.md",,"Title, With Comma",0001-01-01T00:00:00Z,0001-01-01T00:00:00Z,0001-01-01T00:00:00Z,true,https://example.org/notes/with-comma/,page,notes
        """

        let items = try parseHugoContentList(output)

        #expect(items.count == 2)
        #expect(items[0].path == "content/posts/hello.md")
        #expect(items[0].displayTitle == "Hello World")
        #expect(items[0].sectionTitle == "posts")
        #expect(items[1].path == "content/notes/with,comma.md")
        #expect(items[1].title == "Title, With Comma")
        #expect(items[1].isDraft)
    }

    @Test
    func parsesYAMLMetadataForTagsCategoriesAndPublishDate() throws {
        let source = """
        ---
        title: "Corn Maze"
        publishDate: 2024-10-22
        tags: ["ios", "hugo"]
        categories:
          - Writing
          - Swift
        ---
        Body
        """

        let metadata = parseHugoContentMetadata(from: source)

        #expect(metadata.tags == ["ios", "hugo"])
        #expect(metadata.categories == ["Writing", "Swift"])
        #expect(metadata.publishDate != nil)
    }

    @Test
    func parsesTOMLMetadataForTagsAndCategory() throws {
        let source = """
        +++
        publishDate = "2024-01-05T12:00:00Z"
        tags = ["mac", "editor"]
        category = "Apps"
        +++
        Body
        """

        let metadata = parseHugoContentMetadata(from: source)

        #expect(metadata.tags == ["mac", "editor"])
        #expect(metadata.categories == ["Apps"])
        #expect(metadata.publishDate != nil)
    }

    @Test
    func parsesIndentedYAMLCategoryLists() throws {
        let source = """
        ---
        categories:
            - Essays
            - Books
        ---
        Body
        """

        let metadata = parseHugoContentMetadata(from: source)

        #expect(metadata.categories == ["Essays", "Books"])
    }

    @Test
    func parsesMultilineTOMLCategoryArrays() throws {
        let source = """
        +++
        categories = [
          "Essays",
          "Books",
        ]
        +++
        Body
        """

        let metadata = parseHugoContentMetadata(from: source)

        #expect(metadata.categories == ["Essays", "Books"])
    }

    @Test
    func buildsMetadataIndicesByNormalizedTagAndCategory() async throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let contentDirectory = temporaryDirectory.appendingPathComponent("content/posts", isDirectory: true)

        try fileManager.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let firstURL = contentDirectory.appendingPathComponent("first.md")
        let secondURL = contentDirectory.appendingPathComponent("second.md")

        try """
        ---
        tags: ["Swift", "Hugo"]
        categories: ["Notes"]
        publishDate: 2024-02-01
        ---
        First
        """.write(to: firstURL, atomically: true, encoding: .utf8)

        try """
        ---
        tags:
          - swift
        category: Notes
        publishDate: 2024-03-01
        ---
        Second
        """.write(to: secondURL, atomically: true, encoding: .utf8)

        let items = [
            HugoContentItem(
                path: "content/posts/first.md",
                slug: "",
                title: "First",
                date: "",
                expiryDate: "",
                publishDate: "",
                isDraft: false,
                permalink: "",
                kind: "page",
                section: "posts"
            ),
            HugoContentItem(
                path: "content/posts/second.md",
                slug: "",
                title: "Second",
                date: "",
                expiryDate: "",
                publishDate: "",
                isDraft: false,
                permalink: "",
                kind: "page",
                section: "posts"
            )
        ]

        let database = try await loadHugoContentMetadataDatabaseAsync(from: temporaryDirectory, items: items)
        let secondPublishDate = database.metadata(for: items[1].id)?.publishDate

        #expect(database.itemIDs(taggedWith: "swift") == Set(items.map(\.id)))
        #expect(database.itemIDs(inCategory: "notes") == Set(items.map(\.id)))
        #expect(secondPublishDate != nil)
    }

    @Test
    func tracksHugoServerRebuildLifecycle() throws {
        var state = HugoServerParseState()

        let initialBuild = nextHugoServerStatus(
            for: "Start building sites …",
            isError: false,
            state: &state
        )
        #expect(initialBuild?.phase == .building)
        #expect(initialBuild?.message == "Building site…")

        let serverURLLine = nextHugoServerStatus(
            for: "Web Server is available at http://localhost:54239/ (bind address 127.0.0.1)",
            isError: false,
            state: &state
        )
        #expect(serverURLLine?.phase == .building)
        #expect(serverURLLine?.serverURL == URL(string: "http://localhost:54239/"))
        #expect(serverURLLine?.message == "Building site…")

        let changeDetected = nextHugoServerStatus(
            for: "Change detected, rebuilding site (#1).",
            isError: false,
            state: &state
        )
        #expect(changeDetected?.phase == .building)
        #expect(changeDetected?.message == "Change detected, rebuilding site (#1).")

        let sourceChanged = nextHugoServerStatus(
            for: "Source changed /posts/best-books/2025s-best-books.md",
            isError: false,
            state: &state
        )
        #expect(sourceChanged?.phase == .building)
        #expect(sourceChanged?.message == "Source changed /posts/best-books/2025s-best-books.md")

        let rebuildURLLine = nextHugoServerStatus(
            for: "Web Server is available at http://localhost:54239/ (bind address 127.0.0.1)",
            isError: false,
            state: &state
        )
        #expect(rebuildURLLine?.phase == .building)
        #expect(rebuildURLLine?.message == "Source changed /posts/best-books/2025s-best-books.md")

        let total = nextHugoServerStatus(
            for: "Total in 29 ms",
            isError: false,
            state: &state
        )
        #expect(total?.phase == .serving)
        #expect(total?.message == "Total in 29 ms")
        #expect(total?.serverURL == URL(string: "http://localhost:54239/"))
    }
}
