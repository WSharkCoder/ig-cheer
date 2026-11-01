import AppKit
import CoreGraphics

// Build the 22pt grayscale-bust template icon plus a 176px master used by
// make_avatar.swift. Template images are tinted by macOS, so the gray texture
// is encoded in alpha: bright areas opaque, shadows translucent, with a solid
// 1px edge to keep the silhouette readable.
// Run via ./tools/regenerate.sh.

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let artwork = root.appendingPathComponent("artwork", isDirectory: true)
let assets = root.appendingPathComponent("assets", isDirectory: true)

try? FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

guard let srcImage = NSImage(contentsOf: artwork.appendingPathComponent("zombie_cut.png")),
      let srcCG = srcImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot load artwork/zombie_cut.png; run make_assets first")
}

let MASTER = 264 // 22pt at 12x
let bustCrop = CGRect(x: 0, y: 0, width: srcCG.width,
                      height: Int(Double(srcCG.height) * 0.76))

func drawBust(into size: Int) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: size * size * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    buffer.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: size * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let image = srcCG.cropping(to: bustCrop)!
        let margin = Double(size) * 0.055
        let available = Double(size) - margin * 2
        let scale = min(available / Double(image.width), available / Double(image.height))
        let dw = Double(image.width) * scale
        let dh = Double(image.height) * scale
        ctx.draw(image, in: CGRect(x: (Double(size) - dw) / 2,
                                   y: (Double(size) - dh) / 2,
                                   width: dw, height: dh))
    }
    return buffer
}

let base = drawBust(into: MASTER)

func addSolidOutline(_ rgba: [UInt8], radius: Int) -> [UInt8] {
    let n = MASTER
    var mask = [Bool](repeating: false, count: n * n)
    for i in 0..<(n * n) { mask[i] = rgba[i * 4 + 3] > 24 }
    var out = rgba
    let r2 = radius * radius
    for y in radius..<(n - radius) {
        for x in radius..<(n - radius) {
            let i = y * n + x
            if !mask[i] { continue }
            var edge = false
            outer: for dy in -radius...radius {
                for dx in -radius...radius {
                    if dx * dx + dy * dy > r2 { continue }
                    if !mask[(y + dy) * n + (x + dx)] {
                        edge = true
                        break outer
                    }
                }
            }
            if edge { out[i * 4 + 3] = 255 }
        }
    }
    return out
}

func makeRGBA() -> [UInt8] {
    var rgba = [UInt8](repeating: 0, count: MASTER * MASTER * 4)
    for i in 0..<(MASTER * MASTER) {
        let r = Double(base[i * 4])
        let g = Double(base[i * 4 + 1])
        let b = Double(base[i * 4 + 2])
        let a = Double(base[i * 4 + 3]) / 255.0
        if a < 0.1 { continue }
        let rr = min(255, r / max(a, 0.001))
        let gg = min(255, g / max(a, 0.001))
        let bb = min(255, b / max(a, 0.001))
        let lum = (0.2126 * rr + 0.7152 * gg + 0.0722 * bb) / 255.0
        let x = max(0, min(1, (lum - 0.10) / 0.80))
        let s = x * x * (3 - 2 * x)
        let alpha = 0.18 + 0.82 * s
        rgba[i * 4] = 0
        rgba[i * 4 + 1] = 0
        rgba[i * 4 + 2] = 0
        rgba[i * 4 + 3] = UInt8(clamping: Int(alpha * a * 255))
    }
    return addSolidOutline(rgba, radius: 7)
}

func image(rgba: [UInt8]) -> NSImage {
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    let cg = CGImage(width: MASTER, height: MASTER, bitsPerComponent: 8, bitsPerPixel: 32,
                     bytesPerRow: MASTER * 4, space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: true,
                     intent: .defaultIntent)!
    return NSImage(cgImage: cg, size: NSSize(width: 22, height: 22))
}

func bitmap(_ w: Int, _ h: Int) -> (NSBitmapImageRep, NSGraphicsContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    return (rep, NSGraphicsContext(bitmapImageRep: rep)!)
}

func downsample(_ image: NSImage, to px: Int) -> NSImage {
    let (rep, ctx) = bitmap(px, px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: px, height: px))
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
               from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
               operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return NSImage(cgImage: rep.cgImage!, size: NSSize(width: px, height: px))
}

func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode \(url.lastPathComponent)")
    }
    try! png.write(to: url)
}

let icon = image(rgba: makeRGBA())
for (px, name) in [(22, "MenuIconGrayBust.png"),
                   (44, "MenuIconGrayBust@2x.png"),
                   (66, "MenuIconGrayBust@3x.png")] {
    writePNG(downsample(icon, to: px), to: assets.appendingPathComponent(name))
}

// 176px master for the dark-tile avatar; not shipped in the app bundle.
writePNG(downsample(icon, to: 176), to: artwork.appendingPathComponent("bust_gray_5_176.png"))
print("wrote MenuIconGrayBust.png/@2x/@3x and artwork/bust_gray_5_176.png")
