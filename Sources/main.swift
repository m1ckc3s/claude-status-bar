import Cocoa

// Reads ~/.claude/statusbar/state.json (written by Claude Code hooks) and renders a
// Claude "spark" + short status label in the macOS menu bar. No window, no dock icon.

final class StatusController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statePath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/statusbar/state.json")

    var lastMTime: Date = .distantPast
    var pollTimer: Timer?
    var animTimer: Timer?
    var frameIdx = 0

    var current: [String: Any] = [:]
    var activeBase = ""        // label without the elapsed clock
    var startedAt: Double = 0  // unix seconds the current turn began (0 = no clock)
    var activeColor: NSColor? = nil

    let brand = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1) // #d97757, Anthropic's official "Orange" accent
    let amber = NSColor(srgbRed: 0.95, green: 0.73, blue: 0.18, alpha: 1) // "awaiting permission" yellow dot
    let frames: [NSImage] = StatusController.loadFrames() // 8 thinking-spark morph masks
    let spriteFPS: Double = 9 // tune: 8 frames per loop -> ~0.9s/cycle

    // Animation styles. `web` = the captured claude.ai morph (default). `code` = a
    // placeholder glyph spinner for the Claude Code terminal look, to be matched to
    // the real cadence from a screen recording.
    enum AnimStyle: String { case web, code }
    var animStyle: AnimStyle = .web
    var showTimer = true
    var iconSystem = false // false = brand Orange; true = adaptive black/white (template image)
    var iconColor: NSColor? { iconSystem ? nil : brand } // nil => render as an adaptive template
    // Claude Code spinner: forward loop through the 6 glyphs, each with its own peak
    // size (so the pulse matches the video), and a size-down / swap / size-up tween at
    // every boundary so each distinct glyph is clearly shown (no flicker, no missing ones).
    let codeGlyphs = ["✻", "✽", "✶", "✳", "✢"] // dot dropped: the shrink-to-dip already reads as it
    let codePeaks: [CGFloat] = [1.0, 1.0, 1.0, 1.0, 1.0] // every glyph grows to full size
    let codeDip: CGFloat = 0.14 // glyph shrinks to this at each swap
    let codeSub = 18            // sub-frames per glyph (tween smoothness)
    let codeCycle: Double = 3.8 // seconds for the full loop (lower = faster)
    lazy var codeGlyphMasks: [NSImage] = codeGlyphs.map { StatusController.glyphMask($0) }
    var fps: Double { animStyle == .web ? spriteFPS : Double(codeGlyphs.count * codeSub) / codeCycle }
    var frameCount: Int { animStyle == .web ? max(1, frames.count) : codeGlyphs.count * codeSub }

    override init() {
        super.init()
        let d = UserDefaults.standard
        if d.object(forKey: "showTimer") != nil { showTimer = d.bool(forKey: "showTimer") }
        if d.object(forKey: "iconSystem") != nil { iconSystem = d.bool(forKey: "iconSystem") }
        if let s = d.string(forKey: "animStyle"), let st = AnimStyle(rawValue: s) { animStyle = st }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        render(label: "", color: iconColor, animate: false, startedAt: 0)
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        tick()
        ensureHooksInstalled()
    }

    // On first launch, wire up the Claude Code hooks ourselves (runs the bundled installer),
    // so the user just drags the app in and opens it — no manual Terminal step.
    func ensureHooksInstalled() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "hooksInstalled"),
              let installer = Bundle.main.path(forResource: "install", ofType: "js") else { return }
        DispatchQueue.global().async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh") // login shell so `node` is on PATH
            task.arguments = ["-lc", "node \"\(installer)\""]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { UserDefaults.standard.set(true, forKey: "hooksInstalled") }
        }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let openItem = NSMenuItem(title: "Open Claude", action: #selector(openClaude), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let timerItem = NSMenuItem(title: "Show timer", action: #selector(toggleTimer), keyEquivalent: "")
        timerItem.target = self
        timerItem.state = showTimer ? .on : .off
        menu.addItem(timerItem)

        menu.addItem(.separator())
        for (style, name) in [(AnimStyle.web, "Claude Style"), (AnimStyle.code, "Claude Code Style")] {
            let it = NSMenuItem(title: name, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = style.rawValue
            it.state = animStyle == style ? .on : .off
            menu.addItem(it)
        }

        menu.addItem(.separator())
        for (sys, name) in [(false, "Orange"), (true, "System")] {
            let it = NSMenuItem(title: name, action: #selector(chooseColor(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = sys
            it.state = iconSystem == sys ? .on : .off
            menu.addItem(it)
        }

        menu.addItem(.separator())
        let q = NSMenuItem(title: "Quit Claude Status Bar", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
    }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func openClaude() {
        let ws = NSWorkspace.shared
        if let url = ws.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc func toggleTimer() {
        showTimer.toggle()
        UserDefaults.standard.set(showTimer, forKey: "showTimer")
        applyTitle()
    }

    @objc func chooseColor(_ sender: NSMenuItem) {
        guard let sys = sender.representedObject as? Bool else { return }
        iconSystem = sys
        UserDefaults.standard.set(iconSystem, forKey: "iconSystem")
        evaluate() // re-render the current state in the new color
    }

    @objc func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = AnimStyle(rawValue: raw) else { return }
        animStyle = st
        UserDefaults.standard.set(raw, forKey: "animStyle")
        animTimer?.invalidate(); animTimer = nil // recreate at the new style's fps
        frameIdx = 0
        evaluate()
    }

    // MARK: state polling

    func tick() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: statePath),
              let m = attrs[.modificationDate] as? Date else {
            evaluate(); return
        }
        if m != lastMTime {
            lastMTime = m
            if let data = fm.contents(atPath: statePath),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                current = obj
            }
        }
        evaluate()
    }

    func evaluate() {
        let state = current["state"] as? String ?? "idle"
        var label = current["label"] as? String ?? ""
        let ts = (current["ts"] as? NSNumber)?.doubleValue ?? 0
        let started = (current["startedAt"] as? NSNumber)?.doubleValue ?? 0
        let age = Date().timeIntervalSince1970 - ts

        var eff = state
        // The Stop hook fires on normal completion, but NOT when you interrupt (Esc/Stop).
        // In that case Claude Code appends a "[Request interrupted by user]" line to the
        // transcript and the turn ends — detect that so we don't stay stuck on "thinking".
        if state == "thinking" || state == "tool" {
            if age > 900 { eff = "idle"; label = "" } // absolute safety net
            else if let tr = current["transcript"] as? String,
                    let last = lastLine(ofFileAt: tr),
                    last.contains("interrupted by user") {
                eff = "idle"; label = ""
            }
        }

        switch eff {
        case "thinking":  render(label: label.isEmpty ? "Thinking…" : label, color: iconColor, animate: true,  startedAt: started)
        case "tool":      render(label: label.isEmpty ? "Working…"  : label, color: iconColor, animate: true,  startedAt: started)
        case "permission":render(label: "Awaiting permission", color: amber, animate: false, startedAt: 0, dot: true)
        case "waiting":   render(label: label.isEmpty ? "Waiting" : label, color: iconColor, animate: false, startedAt: 0)
        default:          render(label: "", color: iconColor, animate: false, startedAt: 0) // done + idle: just the orange spark
        }
    }

    // Read the last non-empty line of a (possibly large) file by tailing ~8KB.
    func lastLine(ofFileAt path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let chunk: UInt64 = 8192
        try? fh.seek(toOffset: size > chunk ? size - chunk : 0)
        guard let data = try? fh.readToEnd(), let s = String(data: data, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").last { !$0.isEmpty }.map(String.init)
    }

    // MARK: render

    func render(label: String, color: NSColor?, animate: Bool, startedAt: Double, dot: Bool = false) {
        guard let button = statusItem.button else { return }
        button.contentTintColor = nil // we paint the icon color ourselves; template-tint is unreliable
        activeBase = label
        activeColor = color
        self.startedAt = startedAt

        if animate {
            if animTimer == nil {
                let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in self?.animStep() }
                RunLoop.main.add(t, forMode: .common)
                animTimer = t
            }
        } else {
            animTimer?.invalidate(); animTimer = nil
            frameIdx = 0
            // paused dot for "awaiting permission"; otherwise the resting Claude logo.
            button.image = dot ? dotIcon(color: color) : restingIcon(color: color)
        }
        applyTitle()
        if button.image == nil { button.image = dot ? dotIcon(color: color) : restingIcon(color: color) }
    }

    // Reproduce the in-chat thinking spark: step through the active style's frames.
    func animStep() {
        frameIdx = (frameIdx + 1) % frameCount
        statusItem.button?.image = iconImage(color: activeColor, frame: frameIdx)
        applyTitle() // refresh the elapsed clock
    }

    func applyTitle() {
        guard let button = statusItem.button else { return }
        var text = activeBase
        if showTimer, startedAt > 0 {
            let secs = max(0, Int(Date().timeIntervalSince1970 - startedAt))
            let m = secs / 60, s = secs % 60
            text += "  " + (m > 0 ? "\(m)m \(s)s" : "\(s)s") // Claude Code style: "1m 1s" / "43s"
        }
        if text.isEmpty {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        button.imagePosition = .imageLeading
        // labelColor adapts: white on a dark menu bar, black on a light one. Monospaced
        // digits keep the elapsed clock from nudging neighboring menu bar icons.
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular),
        ]
        button.attributedTitle = NSAttributedString(string: " \(text)", attributes: attrs)
    }

    // MARK: icon

    // The 8 thinking-spark morph frames, rasterized from claude.ai's sprite into
    // alpha masks (SparkFrames.swift). Decoded once at launch.
    static func loadFrames() -> [NSImage] { decodePNGs(claudeSparkFramePNGs) }
    static func decodePNGs(_ list: [String]) -> [NSImage] {
        list.compactMap { Data(base64Encoded: $0).flatMap(NSImage.init(data:)) }
    }

    func iconImage(color: NSColor?, frame: Int) -> NSImage {
        if animStyle == .web { return tint(frames, color: color, frame: frame) }
        // Claude Code: which glyph + how big right now.
        let i = (frame / codeSub) % codeGlyphs.count
        let local = (CGFloat(frame % codeSub) + 0.5) / CGFloat(codeSub) // 0…1 within this glyph
        // Envelope: rise, hold at peak, fall — so each glyph lands before the swap.
        let env: CGFloat
        if local < 0.30 { let u = local / 0.30; env = u * u * (3 - 2 * u) }
        else if local > 0.70 { let u = (1 - local) / 0.30; env = u * u * (3 - 2 * u) }
        else { env = 1 }
        let scale = codeDip + (codePeaks[i] - codeDip) * env
        return codeIcon(color: color, glyph: i, scale: scale)
    }

    // Draw glyph mask `i` scaled about center (1.0 == ~92% of the icon). A nil color
    // produces an adaptive template image (system draws it black/white per the menu bar).
    func codeIcon(color: NSColor?, glyph: Int, scale: CGFloat) -> NSImage {
        let s: CGFloat = 18
        guard glyph < codeGlyphMasks.count else { return NSImage(size: NSSize(width: s, height: s)) }
        let mask = codeGlyphMasks[glyph]
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            let dw = s * scale
            let r = NSRect(x: (s - dw) / 2, y: (s - dw) / 2, width: dw, height: dw)
            if let c = color {
                c.setFill(); r.fill()
                mask.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1.0)
            } else {
                mask.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }

    // Rasterize a single glyph into a centered 60x60 alpha mask filling ~92%.
    static func glyphMask(_ g: String) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 180), .foregroundColor: NSColor.black,
        ]
        let str = NSAttributedString(string: g, attributes: attrs)
        let sz = str.size()
        let big = NSImage(size: sz, flipped: false) { _ in str.draw(at: .zero); return true }
        guard let rep = big.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else {
            return NSImage(size: NSSize(width: 60, height: 60))
        }
        let w = rep.pixelsWide, h = rep.pixelsHigh, data = rep.bitmapData!
        var minx = w, miny = h, maxx = -1, maxy = -1
        for y in 0..<h { for x in 0..<w where data[(y*w+x)*4+3] > 20 {
            minx = min(minx, x); maxx = max(maxx, x); miny = min(miny, y); maxy = max(maxy, y)
        }}
        guard maxx >= 0 else { return NSImage(size: NSSize(width: 60, height: 60)) }
        let bw = CGFloat(maxx - minx + 1), bh = CGFloat(maxy - miny + 1)
        let out: CGFloat = 60, fill = out * 0.92
        let scale = fill / max(bw, bh)
        let dw = bw * scale, dh = bh * scale
        // NSBitmapImageRep origin is top-left; convert the bbox to bottom-left for drawing.
        let srcRect = NSRect(x: CGFloat(minx), y: CGFloat(h - maxy - 1), width: bw, height: bh)
        return NSImage(size: NSSize(width: out, height: out), flipped: false) { _ in
            big.draw(in: NSRect(x: (out - dw)/2, y: (out - dh)/2, width: dw, height: dh),
                     from: srcRect, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    // The resting icon is always the official Claude logo, regardless of style.
    let logoSet: [NSImage] = Data(base64Encoded: claudeLogoPNG).flatMap(NSImage.init(data:)).map { [$0] } ?? []
    func restingIcon(color: NSColor?) -> NSImage { tint(logoSet.isEmpty ? frames : logoSet, color: color, frame: 0) }

    // A small filled dot — used for the paused "awaiting permission" state.
    func dotIcon(color: NSColor?) -> NSImage {
        let s: CGFloat = 18, d: CGFloat = 9
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            (color ?? .systemYellow).setFill()
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }

    // Paint `color` through a frame mask's alpha, so the same frames recolor (clay/red).
    func tint(_ set: [NSImage], color: NSColor?, frame: Int) -> NSImage {
        let s: CGFloat = 18
        guard !set.isEmpty else { return NSImage(size: NSSize(width: s, height: s)) }
        let mask = set[frame % set.count]
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            if let c = color {
                c.setFill()
                rect.fill()
                mask.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            } else {
                mask.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        img.isTemplate = (color == nil) // nil => adaptive black/white in the menu bar
        return img
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = StatusController()
app.run()
