// Draws the app icon and writes an .icns. Run by Scripts/bundle.sh.
//
// Generating the icon keeps binary assets out of the repository: the only source of
// truth for the artwork is this file.
import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.icns"

/// Draw one square icon at `size` points.
func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // macOS icons sit in a rounded square inset from the canvas edge.
    let inset = s * 0.086
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = CGPath(
        roundedRect: rect,
        cornerWidth: rect.width * 0.2237,
        cornerHeight: rect.height * 0.2237,
        transform: nil
    )

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let colors = [
        CGColor(red: 0.42, green: 0.36, blue: 0.90, alpha: 1),
        CGColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    context.restoreGState()

    // Three checklist rows; the top two are ticked off, the last is still open.
    let rowHeight = rect.height * 0.148
    let gap = rect.height * 0.086
    let left = rect.minX + rect.width * 0.20
    let lineWidth = max(1, s * 0.030)
    let boxSide = rowHeight * 0.92
    let totalHeight = rowHeight * 3 + gap * 2
    var top = rect.midY + totalHeight / 2 - rowHeight

    for row in 0..<3 {
        let box = CGRect(x: left, y: top, width: boxSide, height: boxSide)
        let isDone = row < 2

        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if isDone {
            context.setFillColor(CGColor(gray: 1, alpha: 0.95))
            context.addPath(CGPath(
                roundedRect: box,
                cornerWidth: boxSide * 0.26,
                cornerHeight: boxSide * 0.26,
                transform: nil
            ))
            context.fillPath()

            // Tick inside the filled box.
            context.setStrokeColor(CGColor(red: 0.28, green: 0.42, blue: 0.93, alpha: 1))
            context.setLineWidth(lineWidth * 0.95)
            context.move(to: CGPoint(x: box.minX + boxSide * 0.24, y: box.midY + boxSide * 0.02))
            context.addLine(to: CGPoint(x: box.minX + boxSide * 0.43, y: box.minY + boxSide * 0.26))
            context.addLine(to: CGPoint(x: box.minX + boxSide * 0.77, y: box.maxY - boxSide * 0.25))
            context.strokePath()
        } else {
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
            context.addPath(CGPath(
                roundedRect: box.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                cornerWidth: boxSide * 0.24,
                cornerHeight: boxSide * 0.24,
                transform: nil
            ))
            context.strokePath()
        }

        // The task text beside the box.
        let barY = box.midY
        let barStart = box.maxX + rect.width * 0.075
        let barEnd = rect.maxX - rect.width * (row == 1 ? 0.30 : 0.17)
        context.setStrokeColor(CGColor(gray: 1, alpha: isDone ? 0.55 : 0.9))
        context.setLineWidth(rowHeight * 0.40)
        context.move(to: CGPoint(x: barStart, y: barY))
        context.addLine(to: CGPoint(x: max(barStart + rowHeight, barEnd), y: barY))
        context.strokePath()

        top -= rowHeight + gap
    }

    return context.makeImage()
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("DexUI-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

// The set of sizes iconutil expects.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard
        let image = render(size: variant.size),
        let destination = CGImageDestinationCreateWithURL(
            iconset.appendingPathComponent("\(variant.name).png") as CFURL,
            "public.png" as CFString,
            1,
            nil
        )
    else {
        FileHandle.standardError.write(Data("Failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputPath]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
