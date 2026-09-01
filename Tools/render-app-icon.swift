//
//  render.swift — renders the iOS app icon from the SAME vector the Android
//  launcher icon uses (ui/src/main/res/drawable/ic_launcher_foreground.xml),
//  on the same gradient (app/src/main/res/drawable/ic_launcher_background.xml).
//
//  Not an upscale of any PNG: the glyph is the brand kit's "A" in its native
//  250x250 viewport, so it rasterises cleanly at any size.
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// The exact pathData from ic_launcher_foreground.xml.
let pathData = "M99.29,167.01l-10.87,20.66h-28.77L123.93,62.33l66.42,125.35h-29.08l-11.33-20.66h-50.66ZM124.24,111.61l-16.84,35.66,33.98-.15-17.14-35.51Z"
let viewport: CGFloat = 250

/// Splits an SVG path into commands and numbers. Handles the two forms this
/// path actually uses that a naive split gets wrong: a leading minus starting a
/// new number ("-17.14"), and a bare decimal doing the same ("-.15").
func tokenize(_ s: String) -> [String] {
    var tokens: [String] = []
    var num = ""
    func flush() { if !num.isEmpty { tokens.append(num); num = "" } }

    for ch in s {
        if ch.isLetter {
            flush()
            tokens.append(String(ch))
        } else if ch == "," || ch == " " {
            flush()
        } else if ch == "-" {
            if !num.isEmpty && !num.lowercased().hasSuffix("e") { flush() }
            num.append(ch)
        } else if ch == "." {
            if num.contains(".") { flush() }
            num.append(ch)
        } else {
            num.append(ch)
        }
    }
    flush()
    return tokens
}

func buildPath() -> CGPath {
    let path = CGMutablePath()
    let tokens = tokenize(pathData)
    var i = 0
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    var command = " " as Character

    func nextNumber() -> CGFloat {
        let v = CGFloat(Double(tokens[i])!)
        i += 1
        return v
    }

    while i < tokens.count {
        if let first = tokens[i].first, first.isLetter {
            command = first
            i += 1
            if command == "Z" || command == "z" {
                path.closeSubpath()
                current = subpathStart
                continue
            }
        }

        switch command {
        case "M", "m":
            var p = CGPoint(x: nextNumber(), y: nextNumber())
            if command == "m" { p = CGPoint(x: current.x + p.x, y: current.y + p.y) }
            path.move(to: p)
            current = p
            subpathStart = p
            // A repeated coordinate pair after a moveto is a lineto.
            command = (command == "M") ? "L" : "l"
        case "L", "l":
            var p = CGPoint(x: nextNumber(), y: nextNumber())
            if command == "l" { p = CGPoint(x: current.x + p.x, y: current.y + p.y) }
            path.addLine(to: p)
            current = p
        case "H", "h":
            let x = nextNumber()
            let p = CGPoint(x: command == "h" ? current.x + x : x, y: current.y)
            path.addLine(to: p)
            current = p
        case "V", "v":
            let y = nextNumber()
            let p = CGPoint(x: current.x, y: command == "v" ? current.y + y : y)
            path.addLine(to: p)
            current = p
        default:
            FileHandle.standardError.write("unsupported command \(command)\n".data(using: .utf8)!)
            exit(1)
        }
    }
    return path
}

// MARK: - Render

let side = 1024
let glyphPath = buildPath()
let box = glyphPath.boundingBox

/*
  How large the glyph sits on the canvas.

  Android cannot be copied directly: there the glyph is 52% of a 108dp
  adaptive canvas of which only 72dp is ever visible, so it reads as ~78% of
  the visible area. An iOS icon has no mask eating its edges — the whole 1024
  is visible — so 78% would look cramped next to every other icon on the home
  screen. 62% of the canvas is the same optical weight.
*/
let targetFraction: CGFloat = 0.62
let scale = (CGFloat(side) * targetFraction) / max(box.width, box.height)

guard let context = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    // noneSkipLast, not premultipliedLast: App Store Connect rejects an app
    // icon that carries an alpha channel.
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("could not create context") }

// Background: #312E81 → #0D6EFD, top-left to bottom-right (Android angle=315).
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(red: 0x31 / 255, green: 0x2E / 255, blue: 0x81 / 255, alpha: 1),
        CGColor(red: 0x0D / 255, green: 0x6E / 255, blue: 0xFD / 255, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: side),
    end: CGPoint(x: side, y: 0),
    options: []
)

/*
  The glyph, white, centred on its own bounding box rather than on the
  viewport. The "A" is not centred inside its 250x250 viewport — optical
  centring is what the eye reads, and centring the viewport instead would sit
  the letter low and left.

  Flipped in y because the path is in SVG coordinates (y down) and CGContext
  here is y-up.
*/
context.saveGState()
context.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
context.scaleBy(x: scale, y: -scale)
context.translateBy(x: -box.midX, y: -box.midY)
context.addPath(glyphPath)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fillPath(using: .evenOdd)   // evenOdd so the counter in the "A" stays open
context.restoreGState()

guard let image = context.makeImage() else { fatalError("could not render") }

let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not open \(out.path)")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write png") }

print("wrote \(out.path) — glyph bbox \(box), scale \(scale)")
