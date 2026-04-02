import AppKit

struct EditorColorScheme: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let backgroundColor: NSColor
    let textColor: NSColor
    let insertionPointColor: NSColor
    let headingColor: NSColor
    let codeColor: NSColor
    let linkColor: NSColor
    let linkDestinationColor: NSColor
    let strongColor: NSColor
    let emphasisColor: NSColor
    let quoteColor: NSColor
    let listColor: NSColor
    let markerColor: NSColor
    let frontMatterKeyColor: NSColor
    let frontMatterValueColor: NSColor
    let frontMatterBooleanColor: NSColor
    let frontMatterDateColor: NSColor
    let shortcodeColor: NSColor
    let templateActionColor: NSColor

    static let allPresets: [EditorColorScheme] = [
        .paperMint,
        .sunsetLedger,
        .fjord,
        .graphiteBloom,
        .copperNight
    ]

    static let defaultPreset = paperMint

    static let appStorageKey = "editorColorSchemeID"

    static let paperMint = EditorColorScheme(
        id: "paper-mint",
        name: "Paper Mint",
        description: "Soft paper background with fresh botanical accents.",
        backgroundColor: .hex(0xF6F4EC),
        textColor: .hex(0x2E312C),
        insertionPointColor: .hex(0x2C6E63),
        headingColor: .hex(0x0E7490),
        codeColor: .hex(0xB45309),
        linkColor: .hex(0x0F766E),
        linkDestinationColor: .hex(0x7C3AED),
        strongColor: .hex(0xBE185D),
        emphasisColor: .hex(0x7C3AED),
        quoteColor: .hex(0x3F6212),
        listColor: .hex(0x5B6157),
        markerColor: .hex(0x9AA19A),
        frontMatterKeyColor: .hex(0x2563EB),
        frontMatterValueColor: .hex(0xC2410C),
        frontMatterBooleanColor: .hex(0xB91C1C),
        frontMatterDateColor: .hex(0x92400E),
        shortcodeColor: .hex(0x6D28D9),
        templateActionColor: .hex(0x0F766E)
    )

    static let sunsetLedger = EditorColorScheme(
        id: "sunset-ledger",
        name: "Sunset Ledger",
        description: "Warm editorial tones with coral and plum contrast.",
        backgroundColor: .hex(0xFFF4ED),
        textColor: .hex(0x3C2F2F),
        insertionPointColor: .hex(0xC2410C),
        headingColor: .hex(0xC2410C),
        codeColor: .hex(0x7C2D12),
        linkColor: .hex(0x9D174D),
        linkDestinationColor: .hex(0x7E22CE),
        strongColor: .hex(0xBE123C),
        emphasisColor: .hex(0x7E22CE),
        quoteColor: .hex(0x166534),
        listColor: .hex(0x6B4F4F),
        markerColor: .hex(0xB7A1A1),
        frontMatterKeyColor: .hex(0xC2410C),
        frontMatterValueColor: .hex(0x9A3412),
        frontMatterBooleanColor: .hex(0xBE123C),
        frontMatterDateColor: .hex(0xA16207),
        shortcodeColor: .hex(0x7E22CE),
        templateActionColor: .hex(0xBE185D)
    )

    static let fjord = EditorColorScheme(
        id: "fjord",
        name: "Fjord",
        description: "Cool slate palette with crisp Nordic contrast.",
        backgroundColor: .hex(0xEAF2F4),
        textColor: .hex(0x20313A),
        insertionPointColor: .hex(0x155E75),
        headingColor: .hex(0x0369A1),
        codeColor: .hex(0xB45309),
        linkColor: .hex(0x0F766E),
        linkDestinationColor: .hex(0x1D4ED8),
        strongColor: .hex(0xBE185D),
        emphasisColor: .hex(0x6D28D9),
        quoteColor: .hex(0x166534),
        listColor: .hex(0x52626A),
        markerColor: .hex(0x8A9AA3),
        frontMatterKeyColor: .hex(0x1D4ED8),
        frontMatterValueColor: .hex(0xC2410C),
        frontMatterBooleanColor: .hex(0xDC2626),
        frontMatterDateColor: .hex(0x92400E),
        shortcodeColor: .hex(0x4338CA),
        templateActionColor: .hex(0x0891B2)
    )

    static let graphiteBloom = EditorColorScheme(
        id: "graphite-bloom",
        name: "Graphite Bloom",
        description: "Dark graphite base with neon floral highlights.",
        backgroundColor: .hex(0x16181D),
        textColor: .hex(0xE7E5E4),
        insertionPointColor: .hex(0xF59E0B),
        headingColor: .hex(0x60A5FA),
        codeColor: .hex(0xFB923C),
        linkColor: .hex(0x22D3EE),
        linkDestinationColor: .hex(0xA78BFA),
        strongColor: .hex(0xF472B6),
        emphasisColor: .hex(0xC084FC),
        quoteColor: .hex(0x4ADE80),
        listColor: .hex(0xA8A29E),
        markerColor: .hex(0x78716C),
        frontMatterKeyColor: .hex(0x93C5FD),
        frontMatterValueColor: .hex(0xFDBA74),
        frontMatterBooleanColor: .hex(0xF87171),
        frontMatterDateColor: .hex(0xFCD34D),
        shortcodeColor: .hex(0xA78BFA),
        templateActionColor: .hex(0x67E8F9)
    )

    static let copperNight = EditorColorScheme(
        id: "copper-night",
        name: "Copper Night",
        description: "Moody dark theme with copper, teal, and rose accents.",
        backgroundColor: .hex(0x1A1412),
        textColor: .hex(0xF3EDE8),
        insertionPointColor: .hex(0xF97316),
        headingColor: .hex(0xFB923C),
        codeColor: .hex(0xF59E0B),
        linkColor: .hex(0x2DD4BF),
        linkDestinationColor: .hex(0xFACC15),
        strongColor: .hex(0xFB7185),
        emphasisColor: .hex(0xC084FC),
        quoteColor: .hex(0x86EFAC),
        listColor: .hex(0xC4B5A5),
        markerColor: .hex(0x8C7B70),
        frontMatterKeyColor: .hex(0xF97316),
        frontMatterValueColor: .hex(0xFDBA74),
        frontMatterBooleanColor: .hex(0xF87171),
        frontMatterDateColor: .hex(0xFACC15),
        shortcodeColor: .hex(0xA78BFA),
        templateActionColor: .hex(0x5EEAD4)
    )

    static func preset(withID id: String) -> EditorColorScheme {
        allPresets.first(where: { $0.id == id }) ?? defaultPreset
    }
}

private extension NSColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
