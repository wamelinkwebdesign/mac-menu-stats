#!/usr/bin/env swift
import AppKit

// Original flat vector artwork. Every size is drawn directly, without bitmap resizing.
let outputDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("menu-stats-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetDirectory = temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func roundedRectangle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ path: CGPath, color: CGColor, in context: CGContext) {
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
}

func render(pixelSize: Int, logicalSize: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize,
                                        pixelsHigh: pixelSize, bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: pixelSize * 4,
                                        bitsPerPixel: 32),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create the icon bitmap")
    }
    bitmap.size = NSSize(width: logicalSize, height: logicalSize)
    let context = graphics.cgContext
    let scale = CGFloat(pixelSize) / 1024
    context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    context.translateBy(x: 0, y: CGFloat(pixelSize))
    context.scaleBy(x: scale, y: -scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let compact = logicalSize <= 32
    let plate = roundedRectangle(CGRect(x: 88, y: 80, width: 848, height: 848), radius: 190)
    fill(plate, color: color(0xFAFAFA), in: context)

    // A flat neutral outline keeps the light tile distinct on white Finder backgrounds.
    let outline = roundedRectangle(CGRect(x: 91, y: 83, width: 842, height: 842), radius: 187)
    context.addPath(outline)
    context.setStrokeColor(color(0xD3D5D8))
    context.setLineWidth(6)
    context.strokePath()

    // The small red segment locates the statistics in the menu bar.
    // A thicker compact strip keeps this accent visible in 16 and 32 point icons.
    let stripHeight: CGFloat = compact ? 40 : 24
    let stripY: CGFloat = 252 - stripHeight / 2
    fill(roundedRectangle(CGRect(x: 262, y: stripY, width: 500, height: stripHeight),
                          radius: stripHeight / 2), color: color(0xD3D5D8), in: context)
    fill(roundedRectangle(CGRect(x: 262, y: stripY, width: 128, height: stripHeight),
                          radius: stripHeight / 2), color: color(0xD6221C), in: context)

    // Solid neutral columns represent CPU, memory, and storage.
    let barWidth: CGFloat = compact ? 128 : 120
    let positions: [CGFloat] = compact ? [260, 448, 636] : [262, 452, 642]
    let tops: [CGFloat] = compact ? [544, 432, 330] : [538, 426, 320]
    let bottom: CGFloat = compact ? 736 : 744
    let barColors: [UInt32] = [0x969BA3, 0x52565E, 0x0E0F11]
    for index in 0..<3 {
        let bar = roundedRectangle(CGRect(x: positions[index], y: tops[index], width: barWidth,
                                           height: bottom - tops[index]), radius: compact ? 26 : 30)
        fill(bar, color: color(barColors[index]), in: context)
    }

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode the icon PNG")
    }
    return data
}

for logicalSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(logicalSize)x\(logicalSize)\(scale == 2 ? "@2x" : "").png"
        let data = try render(pixelSize: logicalSize * scale, logicalSize: logicalSize)
        try data.write(to: iconsetDirectory.appendingPathComponent(filename), options: .atomic)
    }
}
let master = try render(pixelSize: 1024, logicalSize: 1024)
try master.write(to: outputDirectory.appendingPathComponent("AppIcon.png"), options: .atomic)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", outputDirectory.appendingPathComponent("AppIcon.icns").path,
                     iconsetDirectory.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}
print("Rendered AppIcon.png (1024 x 1024) and AppIcon.icns (16 through 1024 pixels)")
