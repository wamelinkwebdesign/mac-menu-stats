#!/usr/bin/env swift
import AppKit
import CoreText

// Reproduce the installer artwork with only macOS frameworks. No font is installed globally.
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let fontURL = directory.appendingPathComponent("fonts/PlusJakartaSans.ttf")
var registrationError: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError),
      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
      let baseDescriptor = descriptors.first else {
    fatalError("Could not load the bundled Plus Jakarta Sans font")
}

func font(_ size: CGFloat, weight: CGFloat) -> CTFont {
    // OpenType 'wght' variation axis.
    let attributes: [CFString: Any] = [kCTFontVariationAttribute: [NSNumber(value: 0x77676874): weight]]
    let descriptor = CTFontDescriptorCreateCopyWithAttributes(baseDescriptor, attributes as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

let ink = color(0x0E0F11)
let secondary = color(0x52555C)
let accent = color(0xD6221C)

@discardableResult
func text(_ value: String, x: CGFloat, baseline: CGFloat, size: CGFloat, weight: CGFloat,
          color: CGColor, kern: CGFloat = 0, in context: CGContext) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font(size, weight: weight),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): kern,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
    context.saveGState()
    context.translateBy(x: x, y: baseline)
    context.scaleBy(x: 1, y: -1)
    context.textMatrix = .identity
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

func polygon(_ points: [(CGFloat, CGFloat)], x: CGFloat, y: CGFloat, scale: CGFloat,
             in context: CGContext) {
    context.beginPath()
    for (index, point) in points.enumerated() {
        let position = CGPoint(x: x + point.0 * scale, y: y + point.1 * scale)
        if index == 0 { context.move(to: position) } else { context.addLine(to: position) }
    }
    context.closePath()
    context.fillPath()
}

func wordmark(in context: CGContext) {
    let size: CGFloat = 19
    let x: CGFloat = 44
    let y: CGFloat = 34
    let capHeight = size * 0.745
    let baseline = y + capHeight
    // Exact approved open-W geometry from wamelink-redesign's wamelinkMark.ts.
    context.setFillColor(ink)
    polygon([(0, 0), (21.57, 0), (36.77, 38.99), (25.99, 66.64)],
            x: x + size * 0.011, y: y, scale: capHeight / 100, in: context)
    polygon([(34.55, 100), (56.12, 100), (82.48, 32.4), (108.84, 100), (125.75, 100),
             (164.75, 0), (143.18, 0), (117.29, 66.37), (91.41, 0), (73.55, 0)],
            x: x + size * 0.011, y: y, scale: capHeight / 100, in: context)
    let lettersX = x + size * (0.011 + 1.2274 - 0.0968)
    let width = text("AMELINK", x: lettersX, baseline: baseline, size: size, weight: 800,
                     color: ink, kern: -size * 0.02, in: context)
    // The brand uses a circle, not the font's square full stop.
    let diameter = size * 0.165
    let centerX = lettersX + width + size * (0.204 - 0.02)
    context.setFillColor(accent)
    context.fillEllipse(in: CGRect(x: centerX - diameter / 2,
                                  y: baseline + size * 0.008 - diameter,
                                  width: diameter, height: diameter))
}

func render(scale: Int) throws {
    let width = 680 * scale
    let height = 440 * scale
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: width * 4, bitsPerPixel: 32),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create background bitmap")
    }
    bitmap.size = NSSize(width: 680, height: 440)
    let context = graphics.cgContext
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    context.setFillColor(color(0xFFFFFF))
    context.fill(CGRect(x: 0, y: 0, width: 680, height: 440))
    wordmark(in: context)
    text("Menu Stats", x: 44, baseline: 116, size: 32, weight: 700, color: ink,
         kern: -0.7, in: context)
    text("Drag Menu Stats to Applications", x: 44, baseline: 146, size: 14,
         weight: 500, color: secondary, in: context)

    // Finder supplies the real draggable icons at (180, 250) and (500, 250).
    context.setStrokeColor(accent)
    context.setLineWidth(2)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 318, y: 250))
    context.addLine(to: CGPoint(x: 362, y: 250))
    context.move(to: CGPoint(x: 352, y: 240))
    context.addLine(to: CGPoint(x: 362, y: 250))
    context.addLine(to: CGPoint(x: 352, y: 260))
    context.strokePath()

    context.setStrokeColor(color(0xE7E8EB))
    context.setLineWidth(1)
    context.move(to: CGPoint(x: 44, y: 374.5))
    context.addLine(to: CGPoint(x: 636, y: 374.5))
    context.strokePath()
    text("wamelink.design", x: 44, baseline: 405, size: 11, weight: 600,
         color: secondary, in: context)
    text("macOS 13 or later", x: 538, baseline: 405, size: 11, weight: 500,
         color: secondary, in: context)

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode background PNG")
    }
    let filename = scale == 1 ? "background.png" : "background@2x.png"
    try png.write(to: directory.appendingPathComponent(filename), options: .atomic)
    print("Rendered \(filename) (\(width) x \(height))")
}

try render(scale: 1)
try render(scale: 2)
