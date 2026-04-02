import Foundation

enum MarkdownSemanticRole: Hashable {
    case heading(level: Int)
    case strong
    case emphasis
    case code
    case link
    case linkDestination
    case quote
    case list
    case thematicBreak
    case syntaxMarker
    case frontMatterDelimiter
    case frontMatterKey
    case frontMatterString
    case frontMatterNumber
    case frontMatterBoolean
    case frontMatterDate
    case shortcode
    case templateAction
    case linkDefinition
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

        var collector = HighlightCollector(source: source)
        let bodyRange = parseFrontMatter(in: source, collector: &collector) ?? source.startIndex..<source.endIndex
        parseBody(in: source, range: bodyRange, collector: &collector)
        return collector.runs.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }

            if lhs.range.length != rhs.range.length {
                return lhs.range.length < rhs.range.length
            }

            return String(describing: lhs.role) < String(describing: rhs.role)
        }
    }

    private static func parseFrontMatter(
        in source: String,
        collector: inout HighlightCollector
    ) -> Range<String.Index>? {
        let firstLineRange = lineRange(in: source, startingAt: source.startIndex, upperBound: source.endIndex)
        let firstLine = trimmedLineContent(for: firstLineRange, in: source)

        if firstLine == "---" || firstLine == "+++" {
            return parseDelimitedFrontMatter(
                in: source,
                openingDelimiterRange: firstLineRange,
                delimiter: firstLine,
                collector: &collector
            )
        }

        if firstLine == "{" {
            return parseJSONFrontMatter(in: source, collector: &collector)
        }

        return nil
    }

    private static func parseDelimitedFrontMatter(
        in source: String,
        openingDelimiterRange: Range<String.Index>,
        delimiter: String,
        collector: inout HighlightCollector
    ) -> Range<String.Index>? {
        let isYAML = delimiter == "---"
        collector.add(trimmedContentRange(for: openingDelimiterRange, in: source), role: .frontMatterDelimiter)

        var cursor = openingDelimiterRange.upperBound
        while cursor < source.endIndex {
            let currentLineRange = lineRange(in: source, startingAt: cursor, upperBound: source.endIndex)
            let currentLine = trimmedLineContent(for: currentLineRange, in: source)

            if currentLine == delimiter {
                collector.add(trimmedContentRange(for: currentLineRange, in: source), role: .frontMatterDelimiter)
                return currentLineRange.upperBound..<source.endIndex
            }

            parseFrontMatterLine(
                in: source,
                lineRange: currentLineRange,
                separator: isYAML ? ":" : "=",
                collector: &collector
            )

            cursor = currentLineRange.upperBound
        }

        return nil
    }

    private static func parseJSONFrontMatter(
        in source: String,
        collector: inout HighlightCollector
    ) -> Range<String.Index>? {
        var cursor = source.startIndex
        var depth = 0
        var inString = false
        var isEscaped = false

        while cursor < source.endIndex {
            let character = source[cursor]

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "{" {
                    depth += 1
                    collector.add(cursor..<source.index(after: cursor), role: .frontMatterDelimiter)
                } else if character == "}" {
                    collector.add(cursor..<source.index(after: cursor), role: .frontMatterDelimiter)
                    depth -= 1
                    if depth == 0 {
                        let jsonRange = source.startIndex..<source.index(after: cursor)
                        parseJSONFrontMatterMembers(in: source, range: jsonRange, collector: &collector)

                        let bodyStart = source.index(after: cursor)
                        if bodyStart < source.endIndex, source[bodyStart] == "\n" {
                            return source.index(after: bodyStart)..<source.endIndex
                        }

                        return bodyStart..<source.endIndex
                    }
                }
            }

            cursor = source.index(after: cursor)
        }

        return nil
    }

    private static func parseJSONFrontMatterMembers(
        in source: String,
        range: Range<String.Index>,
        collector: inout HighlightCollector
    ) {
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            guard let keyStart = source[cursor..<range.upperBound].firstIndex(of: "\""),
                  let keyEnd = findClosingQuote(in: source, from: source.index(after: keyStart), upperBound: range.upperBound) else {
                break
            }

            let keyContentStart = source.index(after: keyStart)
            collector.add(keyContentStart..<keyEnd, role: .frontMatterKey)

            guard let colonIndex = source[keyEnd..<range.upperBound].firstIndex(of: ":") else {
                break
            }

            let valueStart = skipWhitespace(in: source, from: source.index(after: colonIndex), upperBound: range.upperBound)
            guard valueStart < range.upperBound else {
                break
            }

            let valueEnd = endOfJSONValue(in: source, from: valueStart, upperBound: range.upperBound)
            tokenizeFrontMatterValue(in: source, range: valueStart..<valueEnd, collector: &collector)
            cursor = valueEnd
        }
    }

    private static func parseFrontMatterLine(
        in source: String,
        lineRange: Range<String.Index>,
        separator: Character,
        collector: inout HighlightCollector
    ) {
        let contentRange = trimmedContentRange(for: lineRange, in: source)
        guard !contentRange.isEmpty else {
            return
        }

        let text = source[contentRange]
        if text.hasPrefix("#") {
            return
        }

        if text.first == "[", text.last == "]" {
            collector.add(contentRange, role: .frontMatterKey)
            return
        }

        guard let separatorIndex = findSeparator(in: source, range: contentRange, separator: separator) else {
            return
        }

        let keyRange = trimWhitespace(in: source, range: contentRange.lowerBound..<separatorIndex)
        let valueRange = trimWhitespace(in: source, range: source.index(after: separatorIndex)..<contentRange.upperBound)

        collector.add(keyRange, role: .frontMatterKey)
        collector.add(separatorIndex..<source.index(after: separatorIndex), role: .syntaxMarker)
        tokenizeFrontMatterValue(in: source, range: valueRange, collector: &collector)
    }

    private static func tokenizeFrontMatterValue(
        in source: String,
        range: Range<String.Index>,
        collector: inout HighlightCollector
    ) {
        let trimmedRange = trimWhitespace(in: source, range: range)
        guard !trimmedRange.isEmpty else {
            return
        }

        let text = String(source[trimmedRange])

        if isQuotedString(text), text.count >= 2 {
            let contentStart = source.index(after: trimmedRange.lowerBound)
            let contentEnd = source.index(before: trimmedRange.upperBound)
            collector.add(trimmedRange.lowerBound..<contentStart, role: .syntaxMarker)
            collector.add(contentStart..<contentEnd, role: .frontMatterString)
            collector.add(contentEnd..<trimmedRange.upperBound, role: .syntaxMarker)
            return
        }

        if text.first == "[", text.last == "]" {
            collector.add(trimmedRange.lowerBound..<source.index(after: trimmedRange.lowerBound), role: .syntaxMarker)
            collector.add(source.index(before: trimmedRange.upperBound)..<trimmedRange.upperBound, role: .syntaxMarker)
            tokenizeFrontMatterArray(
                in: source,
                range: source.index(after: trimmedRange.lowerBound)..<source.index(before: trimmedRange.upperBound),
                collector: &collector
            )
            return
        }

        if text.first == "{", text.last == "}" {
            collector.add(trimmedRange, role: .frontMatterString)
            return
        }

        if text == "true" || text == "false" {
            collector.add(trimmedRange, role: .frontMatterBoolean)
            return
        }

        if isDateLike(text) {
            collector.add(trimmedRange, role: .frontMatterDate)
            return
        }

        if isNumeric(text) {
            collector.add(trimmedRange, role: .frontMatterNumber)
            return
        }

        collector.add(trimmedRange, role: .frontMatterString)
    }

    private static func tokenizeFrontMatterArray(
        in source: String,
        range: Range<String.Index>,
        collector: inout HighlightCollector
    ) {
        var cursor = range.lowerBound
        var valueStart = cursor
        var inQuotes = false
        var quoteCharacter: Character?

        while cursor < range.upperBound {
            let character = source[cursor]

            if inQuotes {
                if character == quoteCharacter {
                    inQuotes = false
                    quoteCharacter = nil
                }
            } else if character == "\"" || character == "'" {
                inQuotes = true
                quoteCharacter = character
            } else if character == "," {
                tokenizeFrontMatterValue(in: source, range: valueStart..<cursor, collector: &collector)
                collector.add(cursor..<source.index(after: cursor), role: .syntaxMarker)
                valueStart = source.index(after: cursor)
            }

            cursor = source.index(after: cursor)
        }

        tokenizeFrontMatterValue(in: source, range: valueStart..<range.upperBound, collector: &collector)
    }

    private static func parseBody(
        in source: String,
        range: Range<String.Index>,
        collector: inout HighlightCollector
    ) {
        let linkDefinitions = collectLinkDefinitions(in: source, range: range)
        var cursor = range.lowerBound
        var activeFence: FenceState?

        while cursor < range.upperBound {
            let currentLineRange = lineRange(in: source, startingAt: cursor, upperBound: range.upperBound)
            let contentRange = trimmedLineExcludingNewline(for: currentLineRange, in: source)

            if let currentFence = activeFence {
                collector.add(contentRange, role: .code)

                if let closingFenceRange = matchingFenceMarker(in: source, lineRange: contentRange, fence: currentFence) {
                    collector.add(closingFenceRange, role: .syntaxMarker)
                    activeFence = nil
                }

                cursor = currentLineRange.upperBound
                continue
            }

            if let fence = openingFence(in: source, lineRange: contentRange) {
                collector.add(contentRange, role: .code)
                collector.add(fence.range, role: .syntaxMarker)
                activeFence = fence.state
                cursor = currentLineRange.upperBound
                continue
            }

            if isThematicBreakLine(in: source, lineRange: contentRange) {
                collector.add(contentRange, role: .thematicBreak)
                collector.add(contentRange, role: .syntaxMarker)
                cursor = currentLineRange.upperBound
                continue
            }

            if parseLinkDefinitionLine(
                in: source,
                lineRange: contentRange,
                collector: &collector
            ) != nil {
                cursor = currentLineRange.upperBound
                continue
            }

            let block = parseBlockContext(in: source, lineRange: contentRange, collector: &collector)

            if block == nil,
               let paragraphRange = paragraphInlineRange(
                in: source,
                from: cursor,
                upperBound: range.upperBound
               ) {
                let protectedSpans = parseProtectedSpans(in: source, range: paragraphRange, collector: &collector)
                parseInlineMarkdown(
                    in: source,
                    range: paragraphRange,
                    linkDefinitions: linkDefinitions,
                    protectedSpans: protectedSpans,
                    collector: &collector
                )
                cursor = paragraphRange.upperBound
                continue
            }

            let inlineStart = block?.contentStart ?? contentRange.lowerBound
            if inlineStart < contentRange.upperBound {
                let protectedSpans = parseProtectedSpans(in: source, range: contentRange, collector: &collector)
                parseInlineMarkdown(
                    in: source,
                    range: inlineStart..<contentRange.upperBound,
                    linkDefinitions: linkDefinitions,
                    protectedSpans: protectedSpans,
                    collector: &collector
                )
            }

            cursor = currentLineRange.upperBound
        }
    }

    private static func paragraphInlineRange(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> Range<String.Index>? {
        var cursor = start
        var paragraphStart: String.Index?
        var paragraphEnd = start

        while cursor < upperBound {
            let currentLineRange = lineRange(in: source, startingAt: cursor, upperBound: upperBound)
            let contentRange = trimmedLineExcludingNewline(for: currentLineRange, in: source)

            if contentRange.isEmpty {
                break
            }

            if openingFence(in: source, lineRange: contentRange) != nil ||
                isThematicBreakLine(in: source, lineRange: contentRange) ||
                parseLinkDefinitionComponents(in: source, lineRange: contentRange) != nil ||
                isBlockContextLine(in: source, lineRange: contentRange) {
                break
            }

            if paragraphStart == nil {
                paragraphStart = contentRange.lowerBound
            }

            paragraphEnd = contentRange.upperBound
            cursor = currentLineRange.upperBound
        }

        guard let paragraphStart else {
            return nil
        }

        return paragraphStart..<paragraphEnd
    }

    private static func isBlockContextLine(
        in source: String,
        lineRange: Range<String.Index>
    ) -> Bool {
        var probeCollector = HighlightCollector(source: source)
        return parseBlockContext(in: source, lineRange: lineRange, collector: &probeCollector) != nil
    }

    private static func parseProtectedSpans(
        in source: String,
        range: Range<String.Index>,
        collector: inout HighlightCollector
    ) -> [ProtectedSpan] {
        var spans: [ProtectedSpan] = []
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            if let match = matchProtectedSpan(in: source, from: cursor, upperBound: range.upperBound) {
                spans.append(match.span)
                collector.add(match.span.range, role: match.span.role)
                collector.add(match.openerRange, role: .syntaxMarker)
                collector.add(match.closerRange, role: .syntaxMarker)
                cursor = match.span.range.upperBound
            } else {
                cursor = source.index(after: cursor)
            }
        }

        return spans
    }

    private static func parseBlockContext(
        in source: String,
        lineRange: Range<String.Index>,
        collector: inout HighlightCollector
    ) -> BlockContext? {
        guard !lineRange.isEmpty else {
            return nil
        }

        if let heading = parseHeading(in: source, lineRange: lineRange, collector: &collector) {
            return heading
        }

        if let quote = parseQuote(in: source, lineRange: lineRange, collector: &collector) {
            return quote
        }

        if let list = parseListItem(in: source, lineRange: lineRange, collector: &collector) {
            return list
        }

        return nil
    }

    private static func parseHeading(
        in source: String,
        lineRange: Range<String.Index>,
        collector: inout HighlightCollector
    ) -> BlockContext? {
        let indentation = leadingSpaces(in: source, range: lineRange)
        guard indentation <= 3 else {
            return nil
        }

        var cursor = source.index(lineRange.lowerBound, offsetBy: indentation)
        var level = 0

        while cursor < lineRange.upperBound, source[cursor] == "#", level < 6 {
            level += 1
            cursor = source.index(after: cursor)
        }

        guard level > 0, cursor < lineRange.upperBound, source[cursor].isMarkdownWhitespace else {
            return nil
        }

        let markerRange = source.index(lineRange.lowerBound, offsetBy: indentation)..<cursor
        let contentStart = skipMarkdownWhitespace(in: source, from: cursor, upperBound: lineRange.upperBound)

        collector.add(markerRange, role: .syntaxMarker)
        collector.add(contentStart..<lineRange.upperBound, role: .heading(level: level))
        return BlockContext(contentStart: contentStart)
    }

    private static func parseQuote(
        in source: String,
        lineRange: Range<String.Index>,
        collector: inout HighlightCollector
    ) -> BlockContext? {
        let indentation = leadingSpaces(in: source, range: lineRange)
        guard indentation <= 3 else {
            return nil
        }

        var cursor = source.index(lineRange.lowerBound, offsetBy: indentation)
        guard cursor < lineRange.upperBound, source[cursor] == ">" else {
            return nil
        }

        repeat {
            cursor = source.index(after: cursor)
            if cursor < lineRange.upperBound, source[cursor] == " " {
                cursor = source.index(after: cursor)
            }
        } while cursor < lineRange.upperBound && source[cursor] == ">"

        let markerRange = source.index(lineRange.lowerBound, offsetBy: indentation)..<cursor
        collector.add(markerRange, role: .syntaxMarker)
        collector.add(cursor..<lineRange.upperBound, role: .quote)
        return BlockContext(contentStart: cursor)
    }

    private static func parseListItem(
        in source: String,
        lineRange: Range<String.Index>,
        collector: inout HighlightCollector
    ) -> BlockContext? {
        let indentation = leadingSpaces(in: source, range: lineRange)
        guard indentation <= 3 else {
            return nil
        }

        var cursor = source.index(lineRange.lowerBound, offsetBy: indentation)
        guard cursor < lineRange.upperBound else {
            return nil
        }

        let markerStart = cursor
        if "-*+".contains(source[cursor]) {
            cursor = source.index(after: cursor)
        } else if source[cursor].isNumber {
            while cursor < lineRange.upperBound, source[cursor].isNumber {
                cursor = source.index(after: cursor)
            }

            guard cursor < lineRange.upperBound, source[cursor] == "." || source[cursor] == ")" else {
                return nil
            }
            cursor = source.index(after: cursor)
        } else {
            return nil
        }

        guard cursor < lineRange.upperBound, source[cursor].isMarkdownWhitespace else {
            return nil
        }

        let markerEnd = skipMarkdownWhitespace(in: source, from: cursor, upperBound: lineRange.upperBound)
        collector.add(markerStart..<markerEnd, role: .syntaxMarker)
        collector.add(markerEnd..<lineRange.upperBound, role: .list)
        return BlockContext(contentStart: markerEnd)
    }

    private static func parseInlineMarkdown(
        in source: String,
        range: Range<String.Index>,
        linkDefinitions: Set<String>,
        protectedSpans: [ProtectedSpan],
        collector: inout HighlightCollector
    ) {
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            if let span = protectedSpan(containing: cursor, spans: protectedSpans) {
                cursor = span.range.upperBound
                continue
            }

            let character = source[cursor]

            if character == "`", let codeSpan = parseCodeSpan(in: source, from: cursor, upperBound: range.upperBound) {
                collector.add(codeSpan.markerRange.lowerBound..<codeSpan.contentRange.lowerBound, role: .syntaxMarker)
                collector.add(codeSpan.contentRange, role: .code)
                collector.add(codeSpan.contentRange.upperBound..<codeSpan.markerRange.upperBound, role: .syntaxMarker)
                cursor = codeSpan.markerRange.upperBound
                continue
            }

            if character == "[", let linkSpan = parseLink(in: source, from: cursor, upperBound: range.upperBound) {
                collector.add(linkSpan.textRange, role: .link)
                if let destinationRange = linkSpan.destinationRange {
                    collector.add(destinationRange, role: .linkDestination)
                }
                cursor = linkSpan.fullRange.upperBound
                continue
            }

            if character == "[", let referenceLinkSpan = parseReferenceLink(
                in: source,
                from: cursor,
                upperBound: range.upperBound,
                linkDefinitions: linkDefinitions
            ) {
                collector.add(referenceLinkSpan.textRange, role: .link)
                if let destinationRange = referenceLinkSpan.destinationRange {
                    collector.add(destinationRange, role: .linkDestination)
                }
                cursor = referenceLinkSpan.fullRange.upperBound
                continue
            }

            if character == "*" || character == "_" {
                if let strongSpan = parseDelimitedInline(in: source, from: cursor, delimiter: String(repeating: character, count: 2), upperBound: range.upperBound) {
                    collector.add(strongSpan.contentRange, role: .strong)
                    cursor = strongSpan.fullRange.upperBound
                    continue
                }

                if let emphasisSpan = parseDelimitedInline(in: source, from: cursor, delimiter: String(character), upperBound: range.upperBound) {
                    collector.add(emphasisSpan.contentRange, role: .emphasis)
                    cursor = emphasisSpan.fullRange.upperBound
                    continue
                }
            }

            cursor = source.index(after: cursor)
        }
    }

    private static func parseCodeSpan(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> DelimitedSpan? {
        let contentStart = source.index(after: start)
        guard contentStart < upperBound,
              let closing = source[contentStart..<upperBound].firstIndex(of: "`"),
              closing > contentStart else {
            return nil
        }

        let fullRange = start..<source.index(after: closing)
        return DelimitedSpan(fullRange: fullRange, contentRange: contentStart..<closing)
    }

    private static func parseLink(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> LinkSpan? {
        guard let textEnd = source[start..<upperBound].firstIndex(of: "]") else {
            return nil
        }

        let afterTextEnd = source.index(after: textEnd)
        guard afterTextEnd < upperBound, source[afterTextEnd] == "(" else {
            return nil
        }

        let destinationStart = source.index(after: afterTextEnd)
        guard let destinationEnd = findClosingParenthesis(in: source, from: destinationStart, upperBound: upperBound) else {
            return nil
        }

        let textStart = source.index(after: start)
        guard textStart <= textEnd else {
            return nil
        }

        return LinkSpan(
            fullRange: start..<source.index(after: destinationEnd),
            textRange: start..<afterTextEnd,
            destinationRange: afterTextEnd..<source.index(after: destinationEnd)
        )
    }

    private static func parseReferenceLink(
        in source: String,
        from start: String.Index,
        upperBound: String.Index,
        linkDefinitions: Set<String>
    ) -> LinkSpan? {
        guard let textEnd = source[start..<upperBound].firstIndex(of: "]") else {
            return nil
        }

        let textStart = source.index(after: start)
        let afterTextEnd = source.index(after: textEnd)
        guard afterTextEnd <= upperBound else {
            return nil
        }

        if afterTextEnd < upperBound, source[afterTextEnd] == "[" {
            let labelStart = source.index(after: afterTextEnd)
            guard let labelEnd = source[labelStart..<upperBound].firstIndex(of: "]") else {
                return nil
            }

            let labelText = String(source[labelStart..<labelEnd])
            let resolvedLabel = normalizeLinkDefinitionLabel(labelText.isEmpty ? String(source[textStart..<textEnd]) : labelText)
            guard !resolvedLabel.isEmpty else {
                return nil
            }

            if !linkDefinitions.contains(resolvedLabel), !labelText.isEmpty {
                return nil
            }

            return LinkSpan(
                fullRange: start..<source.index(after: labelEnd),
                textRange: start..<afterTextEnd,
                destinationRange: afterTextEnd..<source.index(after: labelEnd)
            )
        }

        guard afterTextEnd == upperBound || source[afterTextEnd] != "(",
              afterTextEnd == upperBound || source[afterTextEnd] != ":" else {
            return nil
        }

        let shortcutLabel = normalizeLinkDefinitionLabel(String(source[textStart..<textEnd]))
        guard linkDefinitions.contains(shortcutLabel) else {
            return nil
        }

        return LinkSpan(
            fullRange: start..<afterTextEnd,
            textRange: start..<afterTextEnd,
            destinationRange: nil
        )
    }

    private static func collectLinkDefinitions(
        in source: String,
        range: Range<String.Index>
    ) -> Set<String> {
        var definitions: Set<String> = []
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            let currentLineRange = lineRange(in: source, startingAt: cursor, upperBound: range.upperBound)
            let contentRange = trimmedLineExcludingNewline(for: currentLineRange, in: source)

            if let parsed = parseLinkDefinitionComponents(in: source, lineRange: contentRange) {
                definitions.insert(normalizeLinkDefinitionLabel(parsed.label))
            }

            cursor = currentLineRange.upperBound
        }

        return definitions
    }

    private static func parseLinkDefinitionLine(
        in source: String,
        lineRange: Range<String.Index>,
        collector: inout HighlightCollector
    ) -> String? {
        guard let parsed = parseLinkDefinitionComponents(in: source, lineRange: lineRange) else {
            return nil
        }

        collector.add(parsed.openBracketRange, role: .syntaxMarker)
        collector.add(parsed.labelRange, role: .link)
        collector.add(parsed.closeBracketAndColonRange, role: .syntaxMarker)
        collector.add(parsed.destinationRange, role: .linkDefinition)
        return parsed.label
    }

    private static func parseLinkDefinitionComponents(
        in source: String,
        lineRange: Range<String.Index>
    ) -> LinkDefinitionComponents? {
        let indentation = leadingSpaces(in: source, range: lineRange)
        guard indentation <= 3 else {
            return nil
        }

        let cursor = source.index(lineRange.lowerBound, offsetBy: indentation)
        guard cursor < lineRange.upperBound, source[cursor] == "[" else {
            return nil
        }

        let openBracketRange = cursor..<source.index(after: cursor)
        let labelStart = source.index(after: cursor)
        guard let labelEnd = source[labelStart..<lineRange.upperBound].firstIndex(of: "]") else {
            return nil
        }

        let afterLabel = source.index(after: labelEnd)
        guard afterLabel < lineRange.upperBound, source[afterLabel] == ":" else {
            return nil
        }

        let destinationStart = skipWhitespace(in: source, from: source.index(after: afterLabel), upperBound: lineRange.upperBound)
        let destinationRange = trimWhitespace(in: source, range: destinationStart..<lineRange.upperBound)
        guard !destinationRange.isEmpty else {
            return nil
        }

        return LinkDefinitionComponents(
            label: String(source[labelStart..<labelEnd]),
            openBracketRange: openBracketRange,
            labelRange: labelStart..<labelEnd,
            closeBracketAndColonRange: labelEnd..<source.index(after: afterLabel),
            destinationRange: destinationRange
        )
    }

    private static func normalizeLinkDefinitionLabel(_ label: String) -> String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func parseDelimitedInline(
        in source: String,
        from start: String.Index,
        delimiter: String,
        upperBound: String.Index
    ) -> DelimitedSpan? {
        guard source[start..<upperBound].hasPrefix(delimiter) else {
            return nil
        }

        let contentStart = source.index(start, offsetBy: delimiter.count)
        guard contentStart < upperBound else {
            return nil
        }

        var searchStart = contentStart
        while searchStart < upperBound {
            guard let closing = source[searchStart..<upperBound].range(of: delimiter)?.lowerBound else {
                return nil
            }

            if closing > contentStart {
                let fullRange = start..<source.index(closing, offsetBy: delimiter.count)
                return DelimitedSpan(fullRange: fullRange, contentRange: contentStart..<closing)
            }

            searchStart = source.index(after: closing)
        }

        return nil
    }

    private static func openingFence(
        in source: String,
        lineRange: Range<String.Index>
    ) -> (range: Range<String.Index>, state: FenceState)? {
        let indentation = leadingSpaces(in: source, range: lineRange)
        guard indentation <= 3 else {
            return nil
        }

        var cursor = source.index(lineRange.lowerBound, offsetBy: indentation)
        guard cursor < lineRange.upperBound else {
            return nil
        }

        let marker = source[cursor]
        guard marker == "`" || marker == "~" else {
            return nil
        }

        let markerStart = cursor
        var count = 0
        while cursor < lineRange.upperBound, source[cursor] == marker {
            count += 1
            cursor = source.index(after: cursor)
        }

        guard count >= 3 else {
            return nil
        }

        return (
            range: markerStart..<cursor,
            state: FenceState(marker: marker, count: count)
        )
    }

    private static func matchingFenceMarker(
        in source: String,
        lineRange: Range<String.Index>,
        fence: FenceState
    ) -> Range<String.Index>? {
        let indentation = leadingSpaces(in: source, range: lineRange)
        guard indentation <= 3 else {
            return nil
        }

        var cursor = source.index(lineRange.lowerBound, offsetBy: indentation)
        guard cursor < lineRange.upperBound, source[cursor] == fence.marker else {
            return nil
        }

        let markerStart = cursor
        var count = 0
        while cursor < lineRange.upperBound, source[cursor] == fence.marker {
            count += 1
            cursor = source.index(after: cursor)
        }

        return count >= fence.count ? markerStart..<cursor : nil
    }

    private static func isThematicBreakLine(
        in source: String,
        lineRange: Range<String.Index>
    ) -> Bool {
        let compact = source[lineRange].filter { !$0.isMarkdownWhitespace }
        guard compact.count >= 3, let first = compact.first else {
            return false
        }

        return (first == "-" || first == "*" || first == "_") && compact.allSatisfy { $0 == first }
    }

    private static func matchProtectedSpan(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> ProtectedMatch? {
        let patterns: [(open: String, close: String, role: MarkdownSemanticRole)] = [
            ("{{<", ">}}", .shortcode),
            ("{{%", "%}}", .shortcode),
            ("{{", "}}", .templateAction)
        ]

        for pattern in patterns where source[start..<upperBound].hasPrefix(pattern.open) {
            let contentStart = source.index(start, offsetBy: pattern.open.count)
            guard let closeStart = source[contentStart..<upperBound].range(of: pattern.close)?.lowerBound else {
                continue
            }

            let spanRange = start..<source.index(closeStart, offsetBy: pattern.close.count)
            let openerRange = start..<contentStart
            let closerRange = closeStart..<spanRange.upperBound
            return ProtectedMatch(
                span: ProtectedSpan(range: spanRange, role: pattern.role),
                openerRange: openerRange,
                closerRange: closerRange
            )
        }

        return nil
    }

    private static func protectedSpan(
        containing index: String.Index,
        spans: [ProtectedSpan]
    ) -> ProtectedSpan? {
        spans.first { $0.range.contains(index) }
    }

    private static func findClosingParenthesis(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> String.Index? {
        var cursor = start
        var depth = 1

        while cursor < upperBound {
            let character = source[cursor]

            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }

            cursor = source.index(after: cursor)
        }

        return nil
    }

    private static func findClosingQuote(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> String.Index? {
        var cursor = start
        var isEscaped = false

        while cursor < upperBound {
            let character = source[cursor]

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return cursor
            }

            cursor = source.index(after: cursor)
        }

        return nil
    }

    private static func endOfJSONValue(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> String.Index {
        var cursor = start
        var inString = false
        var stringDelimiter: Character?
        var squareDepth = 0
        var curlyDepth = 0

        while cursor < upperBound {
            let character = source[cursor]

            if inString {
                if character == stringDelimiter {
                    inString = false
                    stringDelimiter = nil
                } else if character == "\\" {
                    cursor = source.index(after: cursor)
                }
            } else {
                if character == "\"" || character == "'" {
                    inString = true
                    stringDelimiter = character
                } else if character == "[" {
                    squareDepth += 1
                } else if character == "]" {
                    squareDepth -= 1
                } else if character == "{" {
                    curlyDepth += 1
                } else if character == "}" {
                    if curlyDepth == 0 && squareDepth == 0 {
                        return cursor
                    }
                    curlyDepth -= 1
                } else if character == "," && squareDepth == 0 && curlyDepth == 0 {
                    return cursor
                }
            }

            cursor = source.index(after: cursor)
        }

        return upperBound
    }

    private static func findSeparator(
        in source: String,
        range: Range<String.Index>,
        separator: Character
    ) -> String.Index? {
        var cursor = range.lowerBound
        var inQuotes = false
        var quoteCharacter: Character?

        while cursor < range.upperBound {
            let character = source[cursor]

            if inQuotes {
                if character == quoteCharacter {
                    inQuotes = false
                    quoteCharacter = nil
                }
            } else if character == "\"" || character == "'" {
                inQuotes = true
                quoteCharacter = character
            } else if character == separator {
                return cursor
            }

            cursor = source.index(after: cursor)
        }

        return nil
    }

    private static func lineRange(
        in source: String,
        startingAt start: String.Index,
        upperBound: String.Index
    ) -> Range<String.Index> {
        guard start < upperBound else {
            return start..<upperBound
        }

        if let newline = source[start..<upperBound].firstIndex(of: "\n") {
            return start..<source.index(after: newline)
        }

        return start..<upperBound
    }

    private static func trimmedLineContent(
        for lineRange: Range<String.Index>,
        in source: String
    ) -> String {
        String(source[trimmedContentRange(for: lineRange, in: source)])
    }

    private static func trimmedContentRange(
        for lineRange: Range<String.Index>,
        in source: String
    ) -> Range<String.Index> {
        let contentRange = trimmedLineExcludingNewline(for: lineRange, in: source)
        return trimWhitespace(in: source, range: contentRange)
    }

    private static func trimmedLineExcludingNewline(
        for lineRange: Range<String.Index>,
        in source: String
    ) -> Range<String.Index> {
        if lineRange.isEmpty {
            return lineRange
        }

        let end = source.index(before: lineRange.upperBound)
        if source[end] == "\n" {
            return lineRange.lowerBound..<end
        }

        return lineRange
    }

    private static func trimWhitespace(
        in source: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound

        while lower < upper, source[lower].isWhitespace {
            lower = source.index(after: lower)
        }

        while lower < upper {
            let previous = source.index(before: upper)
            guard source[previous].isWhitespace else {
                break
            }
            upper = previous
        }

        return lower..<upper
    }

    private static func skipWhitespace(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> String.Index {
        var cursor = start
        while cursor < upperBound, source[cursor].isWhitespace {
            cursor = source.index(after: cursor)
        }
        return cursor
    }

    private static func skipMarkdownWhitespace(
        in source: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> String.Index {
        var cursor = start
        while cursor < upperBound, source[cursor].isMarkdownWhitespace {
            cursor = source.index(after: cursor)
        }
        return cursor
    }

    private static func leadingSpaces(
        in source: String,
        range: Range<String.Index>
    ) -> Int {
        var count = 0
        var cursor = range.lowerBound

        while cursor < range.upperBound, source[cursor] == " " {
            count += 1
            cursor = source.index(after: cursor)
        }

        return count
    }

    private static func isQuotedString(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last else {
            return false
        }

        return (first == "\"" && last == "\"") || (first == "'" && last == "'")
    }

    private static func isDateLike(_ text: String) -> Bool {
        let pattern = #"^\d{4}-\d{2}-\d{2}([Tt ][^ ]+)?$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isNumeric(_ text: String) -> Bool {
        let pattern = #"^-?\d+(\.\d+)?$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

}

private struct HighlightCollector {
    let source: String
    var runs: [MarkdownSemanticRun] = []

    mutating func add(_ range: Range<String.Index>, role: MarkdownSemanticRole) {
        guard !range.isEmpty else {
            return
        }

        runs.append(MarkdownSemanticRun(range: NSRange(range, in: source), role: role))
    }
}

private struct FenceState {
    let marker: Character
    let count: Int
}

private struct ProtectedSpan {
    let range: Range<String.Index>
    let role: MarkdownSemanticRole
}

private struct ProtectedMatch {
    let span: ProtectedSpan
    let openerRange: Range<String.Index>
    let closerRange: Range<String.Index>
}

private struct BlockContext {
    let contentStart: String.Index
}

private struct DelimitedSpan {
    let fullRange: Range<String.Index>
    let contentRange: Range<String.Index>

    var markerRange: Range<String.Index> {
        fullRange
    }
}

private struct LinkSpan {
    let fullRange: Range<String.Index>
    let textRange: Range<String.Index>
    let destinationRange: Range<String.Index>?
}

private struct LinkDefinitionComponents {
    let label: String
    let openBracketRange: Range<String.Index>
    let labelRange: Range<String.Index>
    let closeBracketAndColonRange: Range<String.Index>
    let destinationRange: Range<String.Index>
}

private extension Character {
    var isMarkdownWhitespace: Bool {
        self == " " || self == "\t"
    }
}
