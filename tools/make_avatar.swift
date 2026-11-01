import AppKit
import CoreGraphics

// Convert the black+alpha 176px icon master into the white/gray avatar shown
// on the dark tile in the dropdown. Run via ./tools/regenerate.sh.

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let artwork = root.appendingPathComponent("artwork", isDirectory: true)
let assets = root.appendingPathComponent("assets", isDirectory: true)

func loadCG(_ name: String) -> CGImage {
    guard let image = NSImage(contentsOf: artwork.appendingPathComponent(name)),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("cannot load artwork/\(name)")
    }
    return cg
}

func rgba(_ cg: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                            bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
    return data
}

func bbox(_ cg: CGImage) -> CGRect {
    let pixels = rgba(cg)
    var minX = cg.width, minY = cg.height, maxX = 0, maxY = 0
    for y in 0..<cg.height {
        for x in 0..<cg.width {
            if pixels[(y * cg.width + x) * 4 + 3] > 10 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    if maxX < minX { return CGRect(x: 0, y: 0, width: cg.width, height: cg.height) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func makeAvatar(source: String, output: String, size: Int = 320) {
    let original = loadCG(source)
    let cropped = original.cropping(to: bbox(original))!
    var data = [UInt8](repeating: 0, count: size * size * 4)
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let pad = Double(size) * 0.055
        let available = Double(size) - pad * 2
        let scale = min(available / Double(cropped.width), available / Double(cropped.height))
        let w = Double(cropped.width) * scale
        let h = Double(cropped.height) * scale
        ctx.draw(cropped, in: CGRect(x: (Double(size) - w) / 2,
                                     y: (Double(size) - h) / 2,
                                     width: w, height: h))
    }

    for i in 0..<(size * size) {
        let alpha = data[i * 4 + 3]
        if alpha < 1 { continue }
        data[i * 4] = alpha
        data[i * 4 + 1] = alpha
        data[i * 4 + 2] = alpha
        data[i * 4 + 3] = alpha
    }

    let provider = CGDataProvider(data: Data(data) as CFData)!
    let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                     bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                     provider: provider, decode: nil, shouldInterpolate: true,
                     intent: .defaultIntent)!
    let rep = NSBitmapImageRep(cgImage: cg)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: assets.appendingPathComponent(output))
    print("wrote assets/\(output)")
}

makeAvatar(source: "bust_gray_5_176.png", output: "avatar_bust_white.png")
