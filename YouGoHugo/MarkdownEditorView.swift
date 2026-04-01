import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    let colorScheme: EditorColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, colorScheme: colorScheme)
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
        private var isApplyingText = false

        init(text: Binding<String>, colorScheme: EditorColorScheme) {
            _text = text
            self.colorScheme = colorScheme
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
            textView.string = value
            highlight(textView)
            isApplyingText = false
        }

        func updateColorScheme(_ colorScheme: EditorColorScheme, for textView: NSTextView) {
            guard self.colorScheme != colorScheme else {
                return
            }

            self.colorScheme = colorScheme
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
