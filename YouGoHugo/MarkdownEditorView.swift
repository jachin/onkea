import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor

        context.coordinator.applyText(text, to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            context.coordinator.applyText(text, to: textView)
        }
    }
}

extension MarkdownEditorView {
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private var isApplyingText = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingText,
                  let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
            highlight(textView)
        }

        func applyText(_ value: String, to textView: NSTextView) {
            isApplyingText = true
            textView.string = value
            highlight(textView)
            isApplyingText = false
        }

        private func highlight(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else {
                return
            }

            let selectedRanges = textView.selectedRanges
            MarkdownHighlighter.highlight(textStorage: textStorage)
            textView.selectedRanges = selectedRanges
        }
    }
}

enum MarkdownHighlighter {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    private static let headingColor = NSColor.systemBlue
    private static let codeColor = NSColor.systemOrange
    private static let linkColor = NSColor.systemTeal
    private static let strongColor = NSColor.systemPink
    private static let emphasisColor = NSColor.systemPurple
    private static let quoteColor = NSColor.systemGreen
    private static let listColor = NSColor.secondaryLabelColor
    private static let markerColor = NSColor.tertiaryLabelColor
    private static let frontMatterKeyColor = NSColor.systemBlue
    private static let frontMatterValueColor = NSColor.systemOrange
    private static let frontMatterBooleanColor = NSColor.systemRed
    private static let frontMatterDateColor = NSColor.systemBrown
    private static let shortcodeColor = NSColor.systemIndigo
    private static let templateActionColor = NSColor.systemCyan
    private static let baseColor = NSColor.labelColor

    static func highlight(textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor
        ]

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: fullRange)
        applySemanticRuns(MarkdownSemanticParser.highlightRuns(for: textStorage.string), to: textStorage)
        textStorage.endEditing()
    }

    private static func applySemanticRuns(_ runs: [MarkdownSemanticRun], to textStorage: NSTextStorage) {
        guard !runs.isEmpty else {
            return
        }

        for segment in segmentedRuns(from: runs, textLength: textStorage.length) where segment.range.length > 0 {
            textStorage.addAttributes(attributes(for: segment.roles), range: segment.range)
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

    private static func attributes(for roles: Set<MarkdownSemanticRole>) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: roles),
            .foregroundColor: color(for: roles)
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

    private static func color(for roles: Set<MarkdownSemanticRole>) -> NSColor {
        if roles.contains(.syntaxMarker) {
            return markerColor
        }

        if roles.contains(.shortcode) {
            return shortcodeColor
        }

        if roles.contains(.templateAction) {
            return templateActionColor
        }

        if roles.contains(.frontMatterKey) {
            return frontMatterKeyColor
        }

        if roles.contains(.frontMatterBoolean) {
            return frontMatterBooleanColor
        }

        if roles.contains(.frontMatterDate) {
            return frontMatterDateColor
        }

        if roles.contains(.frontMatterString) || roles.contains(.frontMatterNumber) {
            return frontMatterValueColor
        }

        if roles.contains(.code) {
            return codeColor
        }

        if roles.contains(.link) || roles.contains(.linkDefinition) {
            return linkColor
        }

        if roles.contains(.strong) {
            return strongColor
        }

        if roles.contains(.emphasis) {
            return emphasisColor
        }

        if roles.contains(.quote) {
            return quoteColor
        }

        if roles.contains(.list) || roles.contains(.thematicBreak) {
            return listColor
        }

        for role in roles {
            if headingLevelValue(from: role) != nil {
                return headingColor
            }
        }

        return baseColor
    }

    private static func headingLevelValue(from role: MarkdownSemanticRole) -> Int? {
        guard case .heading(let level) = role else {
            return nil
        }

        return level
    }
}
