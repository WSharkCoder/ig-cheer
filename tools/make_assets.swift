import AppKit
import CoreGraphics

// Source art pipeline: cut the zombie out of the original illustration and
// redraw the Finder/About app icon. Run via ./tools/regenerate.sh.

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let artwork = root.appendingPathComponent("artwork", isDirectory: true)
let assets = root.appendingPathComponent("assets", isDirectory: true)
let srcPath = artwork.appendingPathComponent("zombie.png").path

try? FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

guard let srcImage = NSImage(contentsOfFile: srcPath),
      let srcCG = srcImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("cannot load artwork/zombie.png")
}

let W = srcCG.width
let H = srcCG.height
var pixels = [UInt8](repeating: 0, count: W * H * 4)
let cs = CGColorSpaceCreateDeviceRGB()

func makeContext(_ buf: inout [UInt8]) -> CGContext? {
    buf.withUnsafeMutableBytes { raw -> CGContext? in
        CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8,
                  bytesPerRow: W * 4, space: cs,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

guard let ctx = makeContext(&pixels) else { fail("no context") }
ctx.interpolationQuality = .high
ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: W, height: H))

// Flood-fill the light background from every border pixel, leaving enclosed
// white areas (eyes, teeth, flag) untouched.
var visited = [Bool](repeating: false, count: W * H)
var stack = [Int]()
func isLightBackground(_ p: Int) -> Bool {
    let i = p * 4
    let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
    let mx = max(r, max(g, b)), mn = min(r, min(g, b))
    return mx >= 196 && (mx - mn) <= 34
}
func push(_ x: Int, _ y: Int) {
    guard x >= 0, y >= 0, x < W, y < H else { return }
    let p = y * W + x
    if visited[p] { return }
    if !isLightBackground(p) { return }
    visited[p] = true
    stack.append(p)
}
for x in 0..<W { push(x, 0); push(x, H - 1) }
for y in 0..<H { push(0, y); push(W - 1, y) }
while let p = stack.popLast() {
    let x = p % W, y = p / W
    let i = p * 4
    pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
    push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
}

guard let cutCG = makeContext(&pixels)?.makeImage() else { fail("no cut image") }

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fail("png encode failed")
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

// Trim the transparent margin so later crops use the actual silhouette.
var minX = W, minY = H, maxX = 0, maxY = 0
for y in 0..<H {
    for x in 0..<W where pixels[(y * W + x) * 4 + 3] > 12 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let margin = 4
let cropRect = CGRect(x: max(0, minX - margin), y: max(0, minY - margin),
                      width: min(W, maxX + margin + 1) - max(0, minX - margin),
                      height: min(H, maxY + margin + 1) - max(0, minY - margin))
let trimmed = cutCG.cropping(to: cropRect) ?? cutCG
writePNG(trimmed, to: artwork.appendingPathComponent("zombie_cut.png").path)

// Finder / About icon: navy squircle with the IG wordmark.
let appSize: CGFloat = 1024
let appImg = NSImage(size: NSSize(width: appSize, height: appSize))
appImg.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
let squircle = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944),
                            xRadius: 210, yRadius: 210)
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
let grad = NSGradient(colors: [NSColor(calibratedRed: 0.055, green: 0.11, blue: 0.17, alpha: 1),
                               NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.31, alpha: 1)])!
grad.draw(in: squircle, angle: -70)
NSGraphicsContext.restoreGraphicsState()

let igFont = NSFont.systemFont(ofSize: 430, weight: .black)
let igStyle = NSMutableParagraphStyle(); igStyle.alignment = .center
let igAttrs: [NSAttributedString.Key: Any] = [
    .font: igFont, .foregroundColor: NSColor.white,
    .paragraphStyle: igStyle, .kern: -12
]
("IG" as NSString).draw(in: NSRect(x: 100, y: 410, width: 824, height: 470),
                        withAttributes: igAttrs)

let cnFont = NSFont(name: "PingFangSC-Semibold", size: 96)
    ?? NSFont.systemFont(ofSize: 96, weight: .semibold)
let cnStyle = NSMutableParagraphStyle(); cnStyle.alignment = .center
let cnAttrs: [NSAttributedString.Key: Any] = [
    .font: cnFont,
    .foregroundColor: NSColor(calibratedRed: 0.58, green: 0.73, blue: 0.47, alpha: 1),
    .paragraphStyle: cnStyle, .kern: 26
]
("应援" as NSString).draw(in: NSRect(x: 100, y: 280, width: 824, height: 120),
                         withAttributes: cnAttrs)

let accent = NSBezierPath(roundedRect: NSRect(x: 452, y: 246, width: 120, height: 8),
                          xRadius: 4, yRadius: 4)
NSColor(calibratedRed: 0.86, green: 0.25, blue: 0.16, alpha: 1).setFill()
accent.fill()
appImg.unlockFocus()

guard let appCG = appImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("app icon render failed")
}
writePNG(appCG, to: assets.appendingPathComponent("AppIcon1024.png").path)

print("wrote artwork/zombie_cut.png and assets/AppIcon1024.png")
