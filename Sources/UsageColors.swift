import Cocoa

enum UsageColors {
    // Muted "Claude tone" palette that sits beside the brand orange (#d97757),
    // not systemRed/Green/Yellow. Hexes per spec §5.3.
    private static let safe     = NSColor(srgbRed: 0x6B / 255.0, green: 0x9B / 255.0, blue: 0x6B / 255.0, alpha: 1) // #6B9B6B sage
    private static let warn     = NSColor(srgbRed: 0xD8 / 255.0, green: 0xA2 / 255.0, blue: 0x3C / 255.0, alpha: 1) // #D8A23C amber
    private static let critical = NSColor(srgbRed: 0xC2 / 255.0, green: 0x5B / 255.0, blue: 0x4E / 255.0, alpha: 1) // #C25B4E terracotta

    // .mono -> nil: caller renders a template / labelColor for adaptive black-and-white.
    static func color(level: UsageLevel, theme: ColorTheme) -> NSColor? {
        switch theme {
        case .mono:
            return nil
        case .system:
            switch level {
            case .safe: return .systemGreen
            case .warn: return .systemYellow
            case .critical: return .systemRed
            }
        case .claude:
            switch level {
            case .safe: return safe
            case .warn: return warn
            case .critical: return critical
            }
        }
    }
}
