import Cocoa

// Renders a full-color crab frame as an adaptive TEMPLATE image for System color mode.
// A template (isTemplate=true) is drawn by macOS in one uniform system color (black on a light
// menu bar, white on a dark one, automatically), so only the alpha channel can carry detail.
// To keep the sprite's depth, brightness is mapped to opacity: the bright body stays solid, the
// darker legs/shading fade to partial (gray) ink, and the darkest pixels (eyes, outlines) drop out
// entirely as transparent holes, the same negative-space eyes as the original. Source coverage
// (anti-aliased edges) is preserved by modulating the original alpha. Run once per frame at load
// and cached by the caller, so it costs nothing during the animation.
func adaptiveCrabFrame(_ src: NSImage) -> NSImage {
    guard let tiff = src.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let cgSrc = bmp.cgImage else { return src }
    let pw = bmp.pixelsWide, ph = bmp.pixelsHigh
    let cs = CGColorSpaceCreateDeviceRGB()
    let bi = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                              bytesPerRow: pw * 4, space: cs, bitmapInfo: bi) else { return src }
    ctx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: pw, height: ph))
    guard let raw = ctx.data else { return src }
    let px = raw.bindMemory(to: UInt8.self, capacity: pw * ph * 4)

    // Tuned by eye. Brightness -> opacity: pixels below `darkCut` become transparent holes (eyes);
    // brightness from darkCut up to `bodyLevel` ramps gray -> solid, so the body reads solid and the
    // legs stay gray. `gamma` shapes that ramp (>1 keeps more of it gray, <1 fills toward solid).
    // Measured from the sprite: eyes/outlines lum <= 0.15, darker legs ~0.45, body ~0.57. So darkCut
    // sits above the eyes (they punch through as holes) and below the legs (they stay gray), and
    // bodyLevel sits at the body brightness (it goes solid). gamma deepens the legs' gray.
    let darkCut = 0.30, bodyLevel = 0.54, gamma = 1.3
    for i in 0..<(pw * ph) {
        let off = i * 4
        let rawA = px[off + 3]
        guard rawA > 0 else { continue }                 // background stays transparent
        let af = Double(rawA) / 255
        let r = Double(px[off])     / (255 * af)
        let g = Double(px[off + 1]) / (255 * af)
        let b = Double(px[off + 2]) / (255 * af)
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        px[off] = 0; px[off + 1] = 0; px[off + 2] = 0    // template ink is black
        if lum < darkCut {
            px[off + 3] = 0                              // eyes / outlines: transparent holes
        } else {
            let t = min(1, (lum - darkCut) / (bodyLevel - darkCut))
            px[off + 3] = UInt8(max(0, min(255, Double(rawA) * pow(t, gamma))))
        }
    }
    guard let outCG = ctx.makeImage() else { return src }
    let img = NSImage(cgImage: outCG, size: src.size)
    img.isTemplate = true
    return img
}
