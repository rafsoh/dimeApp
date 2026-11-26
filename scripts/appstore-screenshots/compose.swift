// Composes the App Store screenshots for one locale from the raw captures (see capture.sh):
// a two-phone hero split across the first two iPhone screenshots, captioned single-phone tiles,
// and the same tiles framed as the iPhone Duo's cover screen.
//
// Usage: compose <locale> <raw dir with iphone/ and duo/> <output dir> <captions.json>
// iPhone screenshots are drawn on a 1290x2796 canvas and exported at each size in `iPhoneSizes`.

import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    FileHandle.standardError.write("Usage: compose <locale> <raw dir> <output dir> <captions.json>\n".data(using: .utf8)!)
    exit(2)
}
let locale = arguments[1]
let rawDir = arguments[2]
let outDir = arguments[3]

struct HeroCopy: Decodable {
    let lines: [String]
    let underline: String
    let award: String
}

struct Captions: Decodable {
    let hero: HeroCopy
    let input, charts, budgets, custom, dark, widgets, insights: String
}

let allCaptions = try JSONDecoder().decode([String: Captions].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[4])))
guard let captions = allCaptions[locale] else {
    FileHandle.standardError.write("No captions for \(locale)\n".data(using: .utf8)!)
    exit(1)
}

let canvasW: CGFloat = 1290
let canvasH: CGFloat = 2796
let iPhoneSizes = [CGSize(width: 1320, height: 2868), CGSize(width: 1284, height: 2778), CGSize(width: 1206, height: 2622)]
let ink = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [.workingColorSpace: cs, .outputColorSpace: cs])

// MARK: - Drawing helpers

func hex(_ s: String) -> NSColor {
    let v = Int(s.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// Approximates Apple's continuous ("squircle") corners, with separate radii for the left and right corners.
func continuousRect(_ r: CGRect, left: CGFloat, right: CGFloat) -> CGPath {
    let t: CGFloat = 0.64
    let ll = min(left * 1.28, min(r.width, r.height) / 2)
    let lr = min(right * 1.28, min(r.width, r.height) / 2)
    let p = CGMutablePath()
    func corner(_ s: CGPoint, _ c: CGPoint, _ e: CGPoint) {
        p.addLine(to: s)
        p.addCurve(to: e, control1: CGPoint(x: s.x + (c.x - s.x) * t, y: s.y + (c.y - s.y) * t), control2: CGPoint(x: e.x + (c.x - e.x) * t, y: e.y + (c.y - e.y) * t))
    }
    p.move(to: CGPoint(x: r.minX + ll, y: r.minY))
    corner(CGPoint(x: r.maxX - lr, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.minY + lr))
    corner(CGPoint(x: r.maxX, y: r.maxY - lr), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.maxX - lr, y: r.maxY))
    corner(CGPoint(x: r.minX + ll, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY - ll))
    corner(CGPoint(x: r.minX, y: r.minY + ll), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX + ll, y: r.minY))
    p.closeSubpath()
    return p
}

func continuousRect(_ r: CGRect, radius: CGFloat) -> CGPath {
    continuousRect(r, left: radius, right: radius)
}

func fillGradient(_ ctx: CGContext, path: CGPath, colors: [NSColor], locations: [CGFloat], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: colors.map(\.cgColor) as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func requireImage(_ path: String) -> CGImage {
    guard let image = loadImage(path) else {
        FileHandle.standardError.write("Missing capture: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return image
}

/// Draws into a y-down canvas.
func drawImage(width: Int, height: Int, opaque: Bool = false, _ body: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    body(ctx)
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ name: String) {
    let path = "\(outDir)/\(name)"
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", path)
}

/// Saves an iPhone screenshot at every App Store size, scaled to fill and centre-cropped (the aspect ratios differ by under 0.3%).
func exportIPhone(_ img: CGImage, _ name: String) {
    for size in iPhoneSizes {
        let scale = max(size.width / CGFloat(img.width), size.height / CGFloat(img.height))
        let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
        let scaled = drawImage(width: Int(size.width), height: Int(size.height), opaque: true) { ctx in
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
        save(scaled, "\(name)-\(Int(size.width))x\(Int(size.height)).png")
    }
}

// Average luminance of the strip the home indicator sits on, to pick a light or dark indicator.
func bottomIsDark(_ img: CGImage) -> Bool {
    let w = 64, h = 8
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(img.cropping(to: CGRect(x: img.width / 4, y: img.height - 40, width: img.width / 2, height: 30))!, in: CGRect(x: 0, y: 0, width: w, height: h))
    var sum = 0.0
    for i in stride(from: 0, to: px.count, by: 4) {
        sum += 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
    }
    return sum / Double(w * h) < 110
}

/// The largest system font up to `size` at which every line fits in `maxWidth`.
func fittedFont(_ lines: [String], size: CGFloat, weight: NSFont.Weight, kern: (CGFloat) -> CGFloat, maxWidth: CGFloat) -> NSFont {
    var size = size
    while size > 40 {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let widest = lines.map { NSAttributedString(string: $0, attributes: [.font: font, .kern: kern(size)]).size().width }.max() ?? 0
        if widest <= maxWidth { return font }
        size -= 2
    }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

// MARK: - Captioned tiles

struct Tile {
    let raw: String
    let title: String
    let symbols: [String]
    let symbolColor: NSColor
    let tileColor: NSColor
    let output: String
}

func drawTileHeader(_ ctx: CGContext, _ tile: Tile, width: CGFloat, tileTop: CGFloat, capTop: CGFloat) {
    let tileRect = CGRect(x: (width - 128) / 2, y: tileTop, width: 128, height: 128)
    ctx.addPath(continuousRect(tileRect, radius: 30))
    ctx.setFillColor(tile.tileColor.cgColor)
    ctx.fillPath()

    let base = tile.symbols.lazy.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }.first!
    let template = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 80, weight: .semibold))!
    let scale = min(80 / template.size.width, 80 / template.size.height)
    let sw = template.size.width * scale, sh = template.size.height * scale
    let symbol = NSImage(size: NSSize(width: sw, height: sh), flipped: false) { rect in
        template.draw(in: rect)
        tile.symbolColor.setFill()
        rect.fill(using: .sourceIn)
        return true
    }
    symbol.draw(in: CGRect(x: tileRect.midX - sw / 2, y: tileRect.midY - sh / 2, width: sw, height: sh), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

    let font = fittedFont([tile.title], size: 96, weight: .medium, kern: { _ in -0.5 }, maxWidth: width - 120)
    let title = NSAttributedString(string: tile.title, attributes: [.font: font, .foregroundColor: ink, .kern: -0.5])
    let tw = title.size().width
    // Keeps the caption's cap height where the 96pt English captions sit.
    let lineTop = capTop - (font.ascender - font.capHeight) + (96 - font.pointSize) * 0.35
    title.draw(with: CGRect(x: (width - tw) / 2, y: lineTop, width: tw + 10, height: 200), options: [.usesLineFragmentOrigin], context: nil)
}

func renderIPhoneTile(_ tile: Tile) -> CGImage {
    let shot = requireImage("\(rawDir)/iphone/\(tile.raw)")
    return drawImage(width: Int(canvasW), height: Int(canvasH), opaque: true) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        drawTileHeader(ctx, tile, width: canvasW, tileTop: 152, capTop: 356)

        let screenW: CGFloat = 954, screenH: CGFloat = 2072, bezel: CGFloat = 34
        let body = CGRect(x: (canvasW - screenW) / 2 - bezel, y: 540, width: screenW + bezel * 2, height: screenH + bezel * 2)
        let screen = body.insetBy(dx: bezel, dy: bezel)
        let bodyRadius: CGFloat = 156
        let metalStops: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]

        func button(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) {
            let r = CGRect(x: x, y: body.minY + body.height * y0, width: 14, height: body.height * (y1 - y0))
            fillGradient(ctx, path: CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil), colors: [hex("#2C2C2E"), hex("#8E8E93"), hex("#3A3A3C")], locations: [0, 0.5, 1], from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.maxX, y: 0))
        }
        button(body.minX - 7, 0.165, 0.205)
        button(body.minX - 7, 0.255, 0.33)
        button(body.minX - 7, 0.355, 0.43)
        button(body.maxX - 7, 0.27, 0.40)

        let outer = continuousRect(body, radius: bodyRadius)
        fillGradient(ctx, path: outer, colors: [hex("#4A4A4E"), hex("#B8B8BD"), hex("#3A3A3C"), hex("#A1A1A6"), hex("#4A4A4E")], locations: metalStops, from: body.origin, to: CGPoint(x: body.maxX, y: body.maxY))
        fillGradient(ctx, path: continuousRect(body.insetBy(dx: 5, dy: 5), radius: bodyRadius - 5), colors: [hex("#2C2C2E"), hex("#6C6C70"), hex("#1C1C1E"), hex("#5A5A5E"), hex("#2C2C2E")], locations: metalStops, from: body.origin, to: CGPoint(x: body.maxX, y: body.maxY))
        ctx.addPath(continuousRect(body.insetBy(dx: 11, dy: 11), radius: bodyRadius - 11))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.addPath(outer)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.28).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        ctx.saveGState()
        ctx.addPath(continuousRect(screen, radius: bodyRadius - bezel))
        ctx.clip()
        NSImage(cgImage: shot, size: NSSize(width: shot.width, height: shot.height)).draw(in: screen, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        ctx.restoreGState()

        let island = CGRect(x: screen.midX - 135, y: screen.minY + 28, width: 270, height: 79)
        ctx.addPath(CGPath(roundedRect: island, cornerWidth: 39.5, cornerHeight: 39.5, transform: nil))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        let lens = CGRect(x: island.maxX - 53, y: island.midY - 13, width: 26, height: 26)
        ctx.setFillColor(hex("#14141F").cgColor)
        ctx.fillEllipse(in: lens)
        ctx.setFillColor(hex("#26263A").cgColor)
        ctx.fillEllipse(in: lens.insetBy(dx: 7, dy: 7))

        let indicator = CGRect(x: screen.midX - 145, y: screen.maxY - 28, width: 290, height: 11)
        ctx.addPath(CGPath(roundedRect: indicator, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
        ctx.setFillColor(bottomIsDark(shot) ? NSColor(white: 1, alpha: 0.9).cgColor : NSColor(white: 0, alpha: 0.85).cgColor)
        ctx.fillPath()
    }
}

/// The iPhone Duo's cover screen: nearly square on the hinge side (24px) and rounded on the outer side (160px) at 1398x2034.
func renderDuoTile(_ tile: Tile) -> CGImage {
    let w: CGFloat = 1398, h: CGFloat = 2034
    let shot = requireImage("\(rawDir)/duo/\(tile.raw)")
    return drawImage(width: Int(w), height: Int(h), opaque: true) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        drawTileHeader(ctx, tile, width: w, tileTop: 130, capTop: 334)

        let screenH: CGFloat = 1400
        let s = screenH / 2034
        let screenW = 1398 * s
        let bezel: CGFloat = 30, spine: CGFloat = 26
        let body = CGRect(x: (w - screenW) / 2 - bezel + spine / 2, y: 512, width: screenW + bezel * 2, height: screenH + bezel * 2)
        let screen = body.insetBy(dx: bezel, dy: bezel)
        let leftR = 24 * s + bezel * 0.6, rightR = 160 * s + bezel
        let metalStops: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]

        func button(_ r: CGRect, horizontal: Bool) {
            let from = horizontal ? CGPoint(x: 0, y: r.minY) : CGPoint(x: r.minX, y: 0)
            let to = horizontal ? CGPoint(x: 0, y: r.maxY) : CGPoint(x: r.maxX, y: 0)
            fillGradient(ctx, path: CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil), colors: [hex("#2C2C2E"), hex("#8E8E93"), hex("#3A3A3C")], locations: [0, 0.5, 1], from: from, to: to)
        }
        // Volume buttons on the top edge, side button on the right, as in the simulator's device art.
        button(CGRect(x: body.minX + body.width * 0.32, y: body.minY - 7, width: body.width * 0.09, height: 14), horizontal: true)
        button(CGRect(x: body.minX + body.width * 0.44, y: body.minY - 7, width: body.width * 0.09, height: 14), horizontal: true)
        button(CGRect(x: body.maxX - 7, y: body.minY + body.height * 0.2, width: 14, height: body.height * 0.11), horizontal: false)

        let spineRect = CGRect(x: body.minX - spine, y: body.minY + 2, width: spine + 20, height: body.height - 4)
        let spinePath = CGPath(roundedRect: spineRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        fillGradient(ctx, path: spinePath, colors: [hex("#3A3A3C"), hex("#9A9AA0"), hex("#5E5E62"), hex("#2C2C2E")], locations: [0, 0.35, 0.7, 1], from: CGPoint(x: spineRect.minX, y: 0), to: CGPoint(x: spineRect.minX + spine, y: 0))
        ctx.addPath(spinePath)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        let outer = continuousRect(body, left: leftR, right: rightR)
        fillGradient(ctx, path: outer, colors: [hex("#4A4A4E"), hex("#B8B8BD"), hex("#3A3A3C"), hex("#A1A1A6"), hex("#4A4A4E")], locations: metalStops, from: body.origin, to: CGPoint(x: body.maxX, y: body.maxY))
        fillGradient(ctx, path: continuousRect(body.insetBy(dx: 5, dy: 5), left: leftR - 5, right: rightR - 5), colors: [hex("#2C2C2E"), hex("#6C6C70"), hex("#1C1C1E"), hex("#5A5A5E"), hex("#2C2C2E")], locations: metalStops, from: body.origin, to: CGPoint(x: body.maxX, y: body.maxY))
        ctx.addPath(continuousRect(body.insetBy(dx: 11, dy: 11), left: leftR - 11, right: rightR - 11))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.addPath(outer)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.28).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        ctx.saveGState()
        ctx.addPath(continuousRect(screen, left: 24 * s, right: 160 * s))
        ctx.clip()
        NSImage(cgImage: shot, size: NSSize(width: shot.width, height: shot.height)).draw(in: screen, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        ctx.restoreGState()
    }
}

// MARK: - Hero: two tilted phones under the headline, split across the first two screenshots

let heroScreenW: CGFloat = 1320, heroScreenH: CGFloat = 2868
let k = heroScreenW / 954
let heroBezel = 34 * k
let heroBodyRadius = 156 * k
let heroPad = 24 * k
let layerW = Int(heroScreenW + heroBezel * 2 + heroPad * 2), layerH = Int(heroScreenH + heroBezel * 2 + heroPad * 2)
let heroBody = CGRect(x: heroPad, y: heroPad, width: heroScreenW + heroBezel * 2, height: heroScreenH + heroBezel * 2)
let thickness = heroBody.width * 0.105

func frontFace(_ shot: CGImage) -> CGImage {
    drawImage(width: layerW, height: layerH) { ctx in
        let outer = continuousRect(heroBody, radius: heroBodyRadius)
        fillGradient(ctx, path: outer, colors: [hex("#5A5A5E"), hex("#C7C7CC"), hex("#3A3A3C"), hex("#AEAEB2"), hex("#5A5A5E")], locations: [0, 0.25, 0.5, 0.75, 1], from: heroBody.origin, to: CGPoint(x: heroBody.maxX, y: heroBody.maxY))
        ctx.addPath(continuousRect(heroBody.insetBy(dx: 6 * k, dy: 6 * k), radius: heroBodyRadius - 6 * k))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()

        let screen = heroBody.insetBy(dx: heroBezel, dy: heroBezel)
        ctx.saveGState()
        ctx.addPath(continuousRect(screen, radius: heroBodyRadius - heroBezel))
        ctx.clip()
        NSImage(cgImage: shot, size: NSSize(width: shot.width, height: shot.height)).draw(in: screen, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        ctx.restoreGState()

        let island = CGRect(x: screen.midX - 135 * k, y: screen.minY + 28 * k, width: 270 * k, height: 79 * k)
        ctx.addPath(CGPath(roundedRect: island, cornerWidth: island.height / 2, cornerHeight: island.height / 2, transform: nil))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        let lens = CGRect(x: island.maxX - 53 * k, y: island.midY - 13 * k, width: 26 * k, height: 26 * k)
        ctx.setFillColor(hex("#14141F").cgColor)
        ctx.fillEllipse(in: lens)
        ctx.setFillColor(hex("#26263A").cgColor)
        ctx.fillEllipse(in: lens.insetBy(dx: 7 * k, dy: 7 * k))

        let indicator = CGRect(x: screen.midX - 145 * k, y: screen.maxY - 28 * k, width: 290 * k, height: 11 * k)
        ctx.addPath(CGPath(roundedRect: indicator, cornerWidth: indicator.height / 2, cornerHeight: indicator.height / 2, transform: nil))
        ctx.setFillColor(bottomIsDark(shot) ? NSColor(white: 1, alpha: 0.9).cgColor : NSColor(white: 0, alpha: 0.85).cgColor)
        ctx.fillPath()
    }
}

/// Titanium band silhouette. Brightness streaks run diagonally so each side catches a different highlight.
func bandLayer(withButtons: Bool) -> CGImage {
    drawImage(width: layerW, height: layerH) { ctx in
        let path = CGMutablePath()
        if withButtons {
            func button(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) {
                path.addRoundedRect(in: CGRect(x: x, y: heroBody.minY + heroBody.height * y0, width: 14 * k, height: heroBody.height * (y1 - y0)), cornerWidth: 6 * k, cornerHeight: 6 * k)
            }
            button(heroBody.minX - 14 * k, 0.165, 0.205)
            button(heroBody.minX - 14 * k, 0.255, 0.33)
            button(heroBody.minX - 14 * k, 0.355, 0.43)
            button(heroBody.maxX, 0.27, 0.40)
        } else {
            path.addPath(continuousRect(heroBody, radius: heroBodyRadius))
        }
        fillGradient(ctx, path: path,
                     colors: [hex("#3A3A3C"), hex("#9A9AA0"), hex("#2C2C2E"), hex("#5E5E62"), hex("#C2C2C7"), hex("#3A3A3C"), hex("#7C7C80"), hex("#2C2C2E")],
                     locations: [0, 0.12, 0.26, 0.4, 0.52, 0.66, 0.82, 1],
                     from: heroBody.origin, to: CGPoint(x: heroBody.maxX, y: heroBody.maxY))
    }
}

struct Phone {
    let shot: CGImage
    let center: CGPoint   // canvas position of the front face's center
    let scale: CGFloat    // canvas px per local px at the face center
    let yaw: CGFloat      // degrees, + turns the face toward the right (shows the left band)
    let pitch: CGFloat    // degrees, + tips the top toward the viewer (shows the top band)
    let roll: CGFloat     // degrees, + rotates clockwise on screen
}

func project(_ phone: Phone, _ u: CGFloat, _ v: CGFloat, _ z: CGFloat) -> CGPoint {
    var x = Double(u) - Double(layerW) / 2, y = Double(v) - Double(layerH) / 2, zz = Double(z)
    let r = { (d: CGFloat) in Double(d) * .pi / 180 }
    let p = r(phone.pitch)
    (y, zz) = (y * cos(p) + zz * sin(p), -y * sin(p) + zz * cos(p))
    let w = r(phone.yaw)
    (x, zz) = (x * cos(w) - zz * sin(w), x * sin(w) + zz * cos(w))
    let ro = r(phone.roll)
    (x, y) = (x * cos(ro) - y * sin(ro), x * sin(ro) + y * cos(ro))
    let d = Double(layerH) * 3.2
    let f = d / (zz + d)
    return CGPoint(x: Double(phone.center.x) + x * f * Double(phone.scale), y: Double(phone.center.y) + y * f * Double(phone.scale))
}

func warp(_ img: CIImage, _ phone: Phone, z: CGFloat, canvasH: CGFloat) -> CIImage {
    func ci(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: canvasH - p.y) }
    let f = CIFilter(name: "CIPerspectiveTransform")!
    f.setValue(img, forKey: kCIInputImageKey)
    f.setValue(ci(project(phone, 0, 0, z)), forKey: "inputTopLeft")
    f.setValue(ci(project(phone, CGFloat(layerW), 0, z)), forKey: "inputTopRight")
    f.setValue(ci(project(phone, CGFloat(layerW), CGFloat(layerH), z)), forKey: "inputBottomRight")
    f.setValue(ci(project(phone, 0, CGFloat(layerH), z)), forKey: "inputBottomLeft")
    return f.outputImage!
}

func shade(_ img: CIImage, _ b: CGFloat) -> CIImage {
    img.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: b, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: b, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
    ])
}

func renderPhone(_ phone: Phone, canvas: CGSize) -> CGImage {
    let band = CIImage(cgImage: bandLayer(withButtons: false))
    let bandButtons = CIImage(cgImage: bandLayer(withButtons: true))
    let extent = CGRect(origin: .zero, size: canvas)
    var acc = CIImage(color: .clear).cropped(to: extent)
    let steps = 90
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        // Rounded band edges read darker; the flat middle catches light.
        let b = 0.55 + 0.6 * sin(.pi * min(max((t - 0.04) / 0.92, 0), 1))
        acc = shade(warp(band, phone, z: thickness * (1 - t), canvasH: canvas.height), b).composited(over: acc)
        if i % 15 == 0 { acc = CIImage(cgImage: ciContext.createCGImage(acc, from: extent)!) }
    }
    let buttonSteps = 24
    for i in 0...buttonSteps {
        let t = CGFloat(i) / CGFloat(buttonSteps)
        acc = shade(warp(bandButtons, phone, z: thickness * (0.66 - 0.32 * t), canvasH: canvas.height), 0.55 + 0.75 * sin(.pi * t)).composited(over: acc)
    }
    acc = warp(CIImage(cgImage: frontFace(phone.shot)), phone, z: 0, canvasH: canvas.height).composited(over: acc)
    return ciContext.createCGImage(acc, from: extent)!
}

/// Right-aligned headline with a hand-drawn underline beneath one word, and the award laurel above it.
func drawHeroCopy(_ ctx: CGContext, right: CGFloat, maxWidth: CGFloat, firstBaseline: CGFloat, fontSize: CGFloat, laurelCenter: CGPoint, laurelScale: CGFloat) {
    let copy = captions.hero
    let font = fittedFont(copy.lines, size: fontSize, weight: .semibold, kern: { -$0 * 0.012 }, maxWidth: maxWidth)
    let size = font.pointSize
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .kern: -size * 0.012]
    let lineGap = fontSize * 1.14
    // Shrunk headlines stay bottom-aligned with the English one, close to the phones.
    let firstBaseline = firstBaseline + (fontSize - size) * 0.6

    for (index, line) in copy.lines.enumerated() {
        let baseline = firstBaseline + CGFloat(index) * lineGap
        let text = NSAttributedString(string: line, attributes: attrs)
        let x0 = right - text.size().width
        text.draw(at: CGPoint(x: x0, y: baseline - font.ascender))

        guard let range = line.range(of: copy.underline) else { continue }
        let prefixW = NSAttributedString(string: String(line[..<range.lowerBound]), attributes: attrs).size().width
        let wordW = NSAttributedString(string: copy.underline, attributes: attrs).size().width
        let ux0 = x0 + prefixW - size * 0.02, ux1 = x0 + prefixW + wordW + size * 0.04
        let uy = baseline + size * 0.2
        let stroke = CGMutablePath()
        stroke.move(to: CGPoint(x: ux0, y: uy + size * 0.02))
        stroke.addCurve(to: CGPoint(x: ux1, y: uy + size * 0.035),
                        control1: CGPoint(x: ux0 + (ux1 - ux0) * 0.3, y: uy - size * 0.07),
                        control2: CGPoint(x: ux0 + (ux1 - ux0) * 0.7, y: uy - size * 0.06))
        ctx.addPath(stroke)
        ctx.setStrokeColor(hex("#F2486B").cgColor)
        ctx.setLineWidth(size * 0.115)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    let s = laurelScale
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineHeightMultiple = 0.92
    let award = NSAttributedString(string: copy.award, attributes: [.font: NSFont.systemFont(ofSize: 40 * s, weight: .semibold), .foregroundColor: ink, .paragraphStyle: para, .kern: -0.3 * s])
    let ab = award.boundingRect(with: NSSize(width: 700 * s, height: 400), options: [.usesLineFragmentOrigin])
    let awardTop = laurelCenter.y - 62 * s
    award.draw(with: CGRect(x: laurelCenter.x - ab.width / 2, y: awardTop, width: ab.width, height: ab.height), options: [.usesLineFragmentOrigin])
    let apple = NSAttributedString(string: "\u{F8FF} APPLE", attributes: [.font: NSFont.systemFont(ofSize: 27 * s, weight: .semibold), .foregroundColor: NSColor(white: 0.62, alpha: 1), .kern: 0.5 * s])
    apple.draw(at: CGPoint(x: laurelCenter.x - apple.size().width / 2, y: awardTop + ab.height + 4 * s))

    for (name, side) in [("laurel.leading", -1.0), ("laurel.trailing", 1.0)] {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 150 * s, weight: .regular))!
        let h = 150 * s
        let w = base.size.width * h / base.size.height
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
            base.draw(in: r)
            ink.setFill()
            r.fill(using: .sourceIn)
            return true
        }
        let cx = laurelCenter.x + CGFloat(side) * (ab.width / 2 + w / 2 + 6 * s)
        img.draw(in: CGRect(x: cx - w / 2, y: laurelCenter.y - h / 2 + 4 * s, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

func renderHero() -> (CGImage, CGImage) {
    // The App Store spaces adjacent screenshots apart, so a gap's worth of the scene is cut out between the two.
    let tileW = canvasW, gap: CGFloat = 60
    let size = CGSize(width: tileW * 2 + gap, height: canvasH)
    let phones = [
        Phone(shot: requireImage("\(rawDir)/iphone/log.png"), center: CGPoint(x: 860, y: 1480), scale: 0.84, yaw: 26, pitch: 10, roll: -11),
        Phone(shot: requireImage("\(rawDir)/iphone/insights.png"), center: CGPoint(x: 1690, y: 2420), scale: 0.96, yaw: -26, pitch: 8, roll: 9),
    ]
    let layers = phones.map { renderPhone($0, canvas: size) }
    let scene = drawImage(width: Int(size.width), height: Int(size.height), opaque: true) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        drawHeroCopy(ctx, right: tileW + gap + 1130, maxWidth: 1000, firstBaseline: 620, fontSize: 124, laurelCenter: CGPoint(x: tileW + gap + 644, y: 290), laurelScale: 1.05)
        for layer in layers {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(layer, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
    }
    return (scene.cropping(to: CGRect(x: 0, y: 0, width: tileW, height: canvasH))!,
            scene.cropping(to: CGRect(x: tileW + gap, y: 0, width: tileW, height: canvasH))!)
}

// MARK: - Output

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let input = (captions.input, ["bolt.fill"], hex("#F84C6E"), hex("#FDC6D1"))
let charts = (captions.charts, ["chart.bar.xaxis"], hex("#6476F9"), hex("#D4D9FD"))
let budgets = (captions.budgets, ["chart.pie.fill"], hex("#FDB933"), hex("#FEECC6"))
let custom = (captions.custom, ["steeringwheel.circle.fill", "steeringwheel", "gearshape.fill"], hex("#00CC83"), hex("#B6F0DC"))
let dark = (captions.dark, ["circle.lefthalf.filled"], hex("#FE6E49"), hex("#FFD6CC"))
let widgets = (captions.widgets, ["rectangle.3.group.fill"], hex("#1B96F5"), hex("#C1E2FC"))
let insights = (captions.insights, ["chart.line.uptrend.xyaxis"], hex("#F0760D"), hex("#FED9C5"))

func tile(_ raw: String, _ style: (String, [String], NSColor, NSColor), _ output: String) -> Tile {
    Tile(raw: raw, title: style.0, symbols: style.1, symbolColor: style.2, tileColor: style.3, output: output)
}

let (heroLeft, heroRight) = renderHero()
exportIPhone(heroLeft, "01-hero-left")
exportIPhone(heroRight, "02-hero-right")

// The widgets capture needs a home screen set up by hand, so it's only included when there is one.
var iPhoneTiles = [
    tile("add.png", input, "03-input"),
    tile("insights.png", charts, "04-charts"),
    tile("budgets.png", budgets, "05-budgets"),
    tile("settings.png", custom, "06-custom"),
    tile("dark_log.png", dark, "07-dark"),
]
if FileManager.default.fileExists(atPath: "\(rawDir)/iphone/widgets.png") {
    iPhoneTiles.append(tile("widgets.png", widgets, "08-widgets"))
}
iPhoneTiles.append(tile("categories.png", insights, "09-insights"))
for t in iPhoneTiles {
    exportIPhone(renderIPhoneTile(t), t.output)
}

if FileManager.default.fileExists(atPath: "\(rawDir)/duo") {
    for t in [
        tile("add.png", input, "duo-1-input"),
        tile("insights.png", charts, "duo-2-charts"),
        tile("budgets.png", budgets, "duo-3-budgets"),
        tile("settings.png", custom, "duo-4-custom"),
        tile("dark_log.png", dark, "duo-5-dark"),
        tile("categories.png", insights, "duo-6-insights"),
    ] {
        save(renderDuoTile(t), "\(t.output).png")
    }
}
