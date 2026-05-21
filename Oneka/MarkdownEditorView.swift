import SwiftUI
import AppKit
import Combine

final class MarkdownEditorController: ObservableObject {
    fileprivate weak var textView: NSTextView?

    @MainActor
    var hasEditableTextView: Bool {
        textView != nil
    }

    @MainActor
    var currentText: String? {
        textView?.string
    }

    @MainActor
    func insertMarkdownImage(altText: String, path: String, colorScheme: EditorColorScheme) -> Bool {
        let markdown = { (selectedText: String) in
            let resolvedAltText = selectedText.isEmpty ? altText : selectedText
            return "![\(Self.escapedMarkdownLinkText(resolvedAltText))](\(path))"
        }

        return insertMarkdown(markdown, style: .block, colorScheme: colorScheme)
    }

    @MainActor
    func insertMarkdownLink(title: String, path: String, colorScheme: EditorColorScheme) -> Bool {
        let markdown = { (selectedText: String) in
            let resolvedTitle = selectedText.isEmpty ? title : selectedText
            return "[\(Self.escapedMarkdownLinkText(resolvedTitle))](\(path))"
        }

        return insertMarkdown(markdown, style: .inline, colorScheme: colorScheme)
    }

    @MainActor
    func insertDetailsShortcode(colorScheme: EditorColorScheme) -> Bool {
        let markdown = { (selectedText: String) in
            let body = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Add the details here."
                : selectedText
            return "{{< details summary=\"Summary\" >}}\n\(body)\n{{< /details >}}"
        }

        return insertMarkdown(markdown, style: .block, colorScheme: colorScheme)
    }

    @MainActor
    func insertFigureShortcode(src: String, altText: String, colorScheme: EditorColorScheme) -> Bool {
        let markdown = { (selectedText: String) in
            let caption = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Add a caption."
                : selectedText
            return "{{< figure\n  src=\"\(Self.escapedShortcodeArgument(src))\"\n  alt=\"\(Self.escapedShortcodeArgument(altText))\"\n  caption=\"\(Self.escapedShortcodeArgument(caption))\"\n>}}"
        }

        return insertMarkdown(markdown, style: .block, colorScheme: colorScheme)
    }

    @MainActor
    func insertHighlightShortcode(colorScheme: EditorColorScheme) -> Bool {
        let markdown = { (selectedText: String) in
            let code = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Add code here."
                : selectedText
            return "{{< highlight text >}}\n\(code)\n{{< /highlight >}}"
        }

        return insertMarkdown(markdown, style: .block, colorScheme: colorScheme)
    }

    @MainActor
    func insertInstagramShortcode(colorScheme: EditorColorScheme) -> Bool {
        let markdown = { (selectedText: String) in
            let postID = Self.instagramPostID(from: selectedText) ?? "INSTAGRAM_POST_ID"
            return "{{< instagram \(postID) >}}"
        }

        return insertMarkdown(markdown, style: .block, colorScheme: colorScheme)
    }

    @MainActor
    func insertParamShortcode(colorScheme: EditorColorScheme) -> Bool {
        let markdown = { (selectedText: String) in
            let parameterName = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "parameter_name"
                : selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return "{{% param \"\(Self.escapedShortcodeArgument(parameterName))\" %}}"
        }

        return insertMarkdown(markdown, style: .inline, colorScheme: colorScheme)
    }

    @MainActor
    func insertQRShortcode(colorScheme: EditorColorScheme) -> Bool {
        let markdown = { (selectedText: String) in
            let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "https://example.com"
                : selectedText
            return "{{< qr >}}\n\(text)\n{{< /qr >}}"
        }

        return insertMarkdown(markdown, style: .block, colorScheme: colorScheme)
    }

    @MainActor
    func replaceTextUsingUndo(_ value: String, colorScheme: EditorColorScheme) -> Bool {
        guard let textView else {
            return false
        }

        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        let selectedRanges = textView.selectedRanges

        guard textView.shouldChangeText(in: fullRange, replacementString: value) else {
            return false
        }

        textView.textStorage?.replaceCharacters(in: fullRange, with: value)
        guard let textStorage = textView.textStorage else {
            return false
        }

        MarkdownHighlighter.configureAppearance(of: textView, using: colorScheme)
        MarkdownHighlighter.highlight(textStorage: textStorage, using: colorScheme)
        textView.didChangeText()
        textView.selectedRanges = selectedRanges.map { value in
            let range = value.rangeValue
            let clampedLocation = min(range.location, textView.string.utf16.count)
            let clampedLength = min(range.length, textView.string.utf16.count - clampedLocation)
            return NSValue(range: NSRange(location: clampedLocation, length: clampedLength))
        }
        return true
    }

    private func insertMarkdown(
        _ makeMarkdown: (String) -> String,
        style: MarkdownInsertionStyle,
        colorScheme: EditorColorScheme
    ) -> Bool {
        guard let textView else {
            return false
        }

        let selectedRange = textView.selectedRange()
        let selectedText = (textView.string as NSString).substring(with: selectedRange)
        let markdown = makeMarkdown(selectedText)
        let insertion = switch style {
        case .inline:
            markdown
        case .block:
            Self.blockInsertionText(markdown, in: textView.string, at: selectedRange)
        }

        guard textView.shouldChangeText(in: selectedRange, replacementString: insertion) else {
            return false
        }

        textView.textStorage?.replaceCharacters(in: selectedRange, with: insertion)
        guard let textStorage = textView.textStorage else {
            return false
        }

        MarkdownHighlighter.configureAppearance(of: textView, using: colorScheme)
        MarkdownHighlighter.highlight(textStorage: textStorage, using: colorScheme)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: selectedRange.location + (insertion as NSString).length, length: 0))
        textView.window?.makeFirstResponder(textView)
        return true
    }

    private static func escapedMarkdownLinkText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func escapedShortcodeArgument(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func instagramPostID(from value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmedValue), let host = url.host, host.contains("instagram.com") {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let markerIndex = pathComponents.firstIndex(where: { ["p", "reel", "tv"].contains($0) }),
               pathComponents.indices.contains(markerIndex + 1) {
                return sanitizedInstagramPostID(pathComponents[markerIndex + 1])
            }
        }

        return sanitizedInstagramPostID(trimmedValue)
    }

    private static func sanitizedInstagramPostID(_ value: String) -> String? {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let sanitizedValue = value.unicodeScalars.filter { allowedCharacters.contains($0) }.map(String.init).joined()
        return sanitizedValue.isEmpty ? nil : sanitizedValue
    }

    private static func blockInsertionText(_ markdown: String, in text: String, at range: NSRange) -> String {
        let nsText = text as NSString
        let needsLeadingBreak = range.location > 0 && nsText.substring(with: NSRange(location: range.location - 1, length: 1)) != "\n"
        let rangeEnd = range.location + range.length
        let needsTrailingBreak = rangeEnd < nsText.length && nsText.substring(with: NSRange(location: rangeEnd, length: 1)) != "\n"

        var insertion = markdown
        if needsLeadingBreak {
            insertion = "\n\n" + insertion
        }
        if needsTrailingBreak {
            insertion += "\n\n"
        }

        return insertion
    }
}

private enum MarkdownInsertionStyle {
    case inline
    case block
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    let colorScheme: EditorColorScheme
    let controller: MarkdownEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, colorScheme: colorScheme, controller: controller)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.font = MarkdownHighlighter.baseFont
        MarkdownHighlighter.configureAppearance(of: textView, using: colorScheme)

        context.coordinator.applyText(text, to: textView, colorScheme: colorScheme)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        context.coordinator.updateColorScheme(colorScheme, for: textView)

        if textView.string != text {
            context.coordinator.applyText(text, to: textView, colorScheme: colorScheme)
        }
    }
}

extension MarkdownEditorView {
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private var colorScheme: EditorColorScheme
        private let controller: MarkdownEditorController
        private var isApplyingText = false

        init(text: Binding<String>, colorScheme: EditorColorScheme, controller: MarkdownEditorController) {
            _text = text
            self.colorScheme = colorScheme
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingText,
                  let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
            highlight(textView)
        }

        func applyText(_ value: String, to textView: NSTextView, colorScheme: EditorColorScheme) {
            isApplyingText = true
            self.colorScheme = colorScheme
            controller.textView = textView
            textView.string = value
            highlight(textView)
            isApplyingText = false
        }

        func updateColorScheme(_ colorScheme: EditorColorScheme, for textView: NSTextView) {
            guard self.colorScheme != colorScheme else {
                controller.textView = textView
                return
            }

            self.colorScheme = colorScheme
            controller.textView = textView
            MarkdownHighlighter.configureAppearance(of: textView, using: colorScheme)
            highlight(textView)
        }

        private func highlight(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else {
                return
            }

            let selectedRanges = textView.selectedRanges
            MarkdownHighlighter.highlight(textStorage: textStorage, using: colorScheme)
            textView.selectedRanges = selectedRanges
        }
    }
}

enum MarkdownHighlighter {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    static func configureAppearance(of textView: NSTextView, using colorScheme: EditorColorScheme) {
        textView.backgroundColor = colorScheme.backgroundColor
        textView.insertionPointColor = colorScheme.insertionPointColor
    }

    static func highlight(textStorage: NSTextStorage, using colorScheme: EditorColorScheme) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: colorScheme.textColor
        ]

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: fullRange)
        applySemanticRuns(
            MarkdownSemanticParser.highlightRuns(for: textStorage.string),
            to: textStorage,
            colorScheme: colorScheme
        )
        textStorage.endEditing()
    }

    private static func applySemanticRuns(
        _ runs: [MarkdownSemanticRun],
        to textStorage: NSTextStorage,
        colorScheme: EditorColorScheme
    ) {
        guard !runs.isEmpty else {
            return
        }

        for segment in segmentedRuns(from: runs, textLength: textStorage.length) where segment.range.length > 0 {
            textStorage.addAttributes(attributes(for: segment.roles, colorScheme: colorScheme), range: segment.range)
        }
    }

    private static func segmentedRuns(from runs: [MarkdownSemanticRun], textLength: Int) -> [(range: NSRange, roles: Set<MarkdownSemanticRole>)] {
        var boundaries = Set([0, textLength])
        for run in runs where run.range.location != NSNotFound {
            boundaries.insert(run.range.location)
            boundaries.insert(run.range.location + run.range.length)
        }

        let sortedBoundaries = boundaries.sorted()
        guard sortedBoundaries.count > 1 else {
            return []
        }

        var segments: [(range: NSRange, roles: Set<MarkdownSemanticRole>)] = []
        for index in 0..<(sortedBoundaries.count - 1) {
            let lowerBound = sortedBoundaries[index]
            let upperBound = sortedBoundaries[index + 1]
            guard upperBound > lowerBound else {
                continue
            }

            let segmentRange = NSRange(location: lowerBound, length: upperBound - lowerBound)
            let roles = Set(runs.compactMap { run -> MarkdownSemanticRole? in
                NSIntersectionRange(run.range, segmentRange).length > 0 ? run.role : nil
            })

            guard !roles.isEmpty else {
                continue
            }

            segments.append((segmentRange, roles))
        }

        return segments
    }

    private static func attributes(
        for roles: Set<MarkdownSemanticRole>,
        colorScheme: EditorColorScheme
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: roles),
            .foregroundColor: color(for: roles, colorScheme: colorScheme)
        ]
    }

    private static func font(for roles: Set<MarkdownSemanticRole>) -> NSFont {
        if roles.contains(.code) {
            return baseFont
        }

        let isHeading = roles.contains { headingLevelValue(from: $0) != nil }
        let weight: NSFont.Weight = roles.contains(.strong) ? .bold : (isHeading ? .semibold : .regular)
        let base = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: weight)

        guard roles.contains(.emphasis) else {
            return base
        }

        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    private static func color(
        for roles: Set<MarkdownSemanticRole>,
        colorScheme: EditorColorScheme
    ) -> NSColor {
        if roles.contains(.syntaxMarker) {
            return colorScheme.markerColor
        }

        if roles.contains(.shortcode) {
            return colorScheme.shortcodeColor
        }

        if roles.contains(.templateAction) {
            return colorScheme.templateActionColor
        }

        if roles.contains(.frontMatterKey) {
            return colorScheme.frontMatterKeyColor
        }

        if roles.contains(.frontMatterBoolean) {
            return colorScheme.frontMatterBooleanColor
        }

        if roles.contains(.frontMatterDate) {
            return colorScheme.frontMatterDateColor
        }

        if roles.contains(.frontMatterString) || roles.contains(.frontMatterNumber) {
            return colorScheme.frontMatterValueColor
        }

        if roles.contains(.code) {
            return colorScheme.codeColor
        }

        if roles.contains(.linkDestination) {
            return colorScheme.linkDestinationColor
        }

        if roles.contains(.link) || roles.contains(.linkDefinition) {
            return colorScheme.linkColor
        }

        if roles.contains(.strong) {
            return colorScheme.strongColor
        }

        if roles.contains(.emphasis) {
            return colorScheme.emphasisColor
        }

        if roles.contains(.quote) {
            return colorScheme.quoteColor
        }

        if roles.contains(.list) || roles.contains(.thematicBreak) {
            return colorScheme.listColor
        }

        for role in roles {
            if headingLevelValue(from: role) != nil {
                return colorScheme.headingColor
            }
        }

        return colorScheme.textColor
    }

    private static func headingLevelValue(from role: MarkdownSemanticRole) -> Int? {
        guard case .heading(let level) = role else {
            return nil
        }

        return level
    }
}
