import Cocoa

final class ProgressBarView: NSView {
    private let title: String
    private let utilization: Double        // 0...100
    private let resetsAt: Date?
    private let fillColor: NSColor?        // nil (mono) -> labelColor

    init(title: String, utilization: Double, resetsAt: Date?,
         color: NSColor?) {
        self.title = title
        self.utilization = max(0, min(100, utilization))
        self.resetsAt = resetsAt
        self.fillColor = color
        // Widest top-level item, so the menu sizes to it and the track spans the full width.
        // Extra height past the content leaves empty space below, spacing consecutive rows apart.
        super.init(frame: NSRect(x: 0, y: 0, width: 290, height: 52))
    }

    // Never loaded from a nib; failable init returns nil instead of force-unwrapping.
    required init?(coder: NSCoder) { return nil }

    override var isFlipped: Bool { true } // top-left origin for straightforward top-down layout

    // The OWNER (StatusController) drives live redraws: while the menu is open it runs a
    // RunLoop.main `.common`-mode Timer and calls tick() so the reset countdown stays live.
    func tick() { needsDisplay = true }
}

extension ProgressBarView {
    override func draw(_ dirtyRect: NSRect) {
        let pad: CGFloat = 12
        let w = bounds.width

        // Top row: title (left) + big percent (right)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        (title as NSString).draw(at: NSPoint(x: pad, y: 5), withAttributes: titleAttrs)

        let pctText = "\(Int(utilization.rounded()))%"
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let pctSize = (pctText as NSString).size(withAttributes: pctAttrs)
        (pctText as NSString).draw(at: NSPoint(x: w - pad - pctSize.width, y: 3), withAttributes: pctAttrs)

        // Track
        let trackX = pad, trackY: CGFloat = 26, trackH: CGFloat = 5
        let trackW = w - pad * 2
        let track = NSRect(x: trackX, y: trackY, width: trackW, height: trackH)
        // Higher alpha so the full-width track reads as a bar with a partial fill on a dark menu.
        NSColor.tertiaryLabelColor.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: track, xRadius: trackH / 2, yRadius: trackH / 2).fill()

        // Fill (clamp to a pill-minimum so a tiny non-zero value stays visible)
        let fillW = trackW * CGFloat(utilization / 100)
        if fillW > 0 {
            let fillRect = NSRect(x: trackX, y: trackY, width: max(trackH, fillW), height: trackH)
            (fillColor ?? NSColor.labelColor).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: trackH / 2, yRadius: trackH / 2).fill()
        }

        // Reset countdown (left-aligned, gray to match the title, below the track)
        let reset = ProgressBarView.formatReset(resetsAt, now: Date())
        if !reset.isEmpty {
            let rAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            (reset as NSString).draw(at: NSPoint(x: pad, y: 33), withAttributes: rAttrs)
        }
    }
}

extension ProgressBarView {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    static func formatReset(_ date: Date?, now: Date) -> String {
        guard let date else { return "" }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "resetting…" }
        if remaining < 24 * 3600 {
            let h = Int(remaining) / 3600
            let m = (Int(remaining) % 3600) / 60
            return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
        }
        return "resets \(dayFormatter.string(from: date))"
    }
}
