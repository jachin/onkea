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

    private static let headingFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
    private static let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    private static let boldItalicFont = NSFontManager.shared.convert(
        NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold),
        toHaveTrait: .italicFontMask
    )

    private static let baseColor = NSColor.labelColor
    private static let secondaryColor = NSColor.secondaryLabelColor
    private static let headingColor = NSColor.systemBlue
    private static let codeColor = NSColor.systemOrange
    private static let linkColor = NSColor.systemTeal
    private static let strongColor = NSColor.systemPink
    private static let emphasisColor = NSColor.systemPurple
    private static let quoteColor = NSColor.systemGreen

    private static let headingPattern = #"(?m)^(#{1,6})\s+.+$"#
    private static let emphasisPatterns: [(pattern: String, font: NSFont, color: NSColor)] = [
        (#"(?<!\*)\*\*\*[^*\n]+?\*\*\*(?!\*)"#, boldItalicFont, strongColor),
        (#"(?<!_)___[^_\n]+?___(?!_)"#, boldItalicFont, strongColor),
        (#"(?<!\*)\*\*[^*\n]+?\*\*(?!\*)"#, boldFont, strongColor),
        (#"(?<!_)__[^_\n]+?__(?!_)"#, boldFont, strongColor),
        (#"(?<!\*)\*[^*\n]+?\*(?!\*)"#, italicFont, emphasisColor),
        (#"(?<!_)_[^_\n]+?_(?!_)"#, italicFont, emphasisColor)
    ]
    private static let inlineCodePattern = #"(?<!`)`[^`\n]+`(?!`)"#
    private static let fencedCodePattern = #"(?s)```.*?```"#
    private static let linkPattern = #"\[[^\]]+\]\([^)]+\)"#
    private static let quotePattern = #"(?m)^>\s+.*$"#
    private static let listPattern = #"(?m)^\s*([-*+]|\d+\.)\s+.*$"#

    static func highlight(textStorage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor
        ]

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: fullRange)

        applyPattern(headingPattern, to: textStorage, color: headingColor, font: headingFont)
        applyPattern(fencedCodePattern, to: textStorage, color: codeColor)
        applyPattern(inlineCodePattern, to: textStorage, color: codeColor)
        applyPattern(linkPattern, to: textStorage, color: linkColor)
        applyPattern(quotePattern, to: textStorage, color: quoteColor)
        applyPattern(listPattern, to: textStorage, color: secondaryColor)

        for emphasis in emphasisPatterns {
            applyPattern(emphasis.pattern, to: textStorage, color: emphasis.color, font: emphasis.font)
        }

        textStorage.endEditing()
    }

    private static func applyPattern(
        _ pattern: String,
        to textStorage: NSTextStorage,
        color: NSColor,
        font: NSFont? = nil
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return
        }

        let range = NSRange(location: 0, length: textStorage.length)
        let matches = regex.matches(in: textStorage.string, options: [], range: range)
        let fontToApply = font ?? baseFont

        for match in matches {
            textStorage.addAttributes(
                [
                    .foregroundColor: color,
                    .font: fontToApply
                ],
                range: match.range
            )
        }
    }
}
