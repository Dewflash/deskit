import AppKit
import Foundation

func fail(_ message: String) -> Never {
    fputs("render-app-icon: \(message)\n", stderr)
    exit(1)
}

func bitmap(from image: NSImage) -> NSBitmapImageRep? {
    guard let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}

func contentBounds(in bitmap: NSBitmapImageRep) -> NSRect {
    var minX = bitmap.pixelsWide
    var minY = bitmap.pixelsHigh
    var maxX = 0
    var maxY = 0

    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let maxComponent = max(color.redComponent, color.greenComponent, color.blueComponent)
            let minComponent = min(color.redComponent, color.greenComponent, color.blueComponent)
            let saturation = maxComponent - minComponent
            let darkness = 1 - maxComponent
            let hasInk = color.alphaComponent > 0.08 && (darkness > 0.16 || saturation > 0.08)
            if hasInk {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    guard minX <= maxX, minY <= maxY else {
        return NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    }

    let padding = max(4, Int(Double(max(maxX - minX, maxY - minY)) * 0.03))
    return NSRect(
        x: max(0, minX - padding),
        y: max(0, minY - padding),
        width: min(bitmap.pixelsWide - max(0, minX - padding), maxX - minX + 1 + padding * 2),
        height: min(bitmap.pixelsHigh - max(0, minY - padding), maxY - minY + 1 + padding * 2)
    )
}

func drawGradientBackground(size: CGFloat) {
    let backgroundRect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225
    let path = NSBezierPath(roundedRect: backgroundRect.insetBy(dx: size * 0.025, dy: size * 0.025), xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.980, green: 0.982, blue: 0.986, alpha: 1),
        NSColor(calibratedRed: 0.925, green: 0.932, blue: 0.942, alpha: 1),
        NSColor(calibratedRed: 0.835, green: 0.852, blue: 0.875, alpha: 1)
    ])
    gradient?.draw(in: backgroundRect, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(calibratedWhite: 1, alpha: 0.55).setStroke()
    path.lineWidth = max(1, size * 0.012)
    path.stroke()

    let inner = NSBezierPath(roundedRect: backgroundRect.insetBy(dx: size * 0.07, dy: size * 0.07), xRadius: cornerRadius * 0.72, yRadius: cornerRadius * 0.72)
    NSColor(calibratedWhite: 1, alpha: 0.20).setStroke()
    inner.lineWidth = max(1, size * 0.006)
    inner.stroke()
}

func transparentArtwork(from cgImage: CGImage) -> NSImage {
    let bitmap = NSBitmapImageRep(cgImage: cgImage)

    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let maxComponent = max(color.redComponent, color.greenComponent, color.blueComponent)
            let minComponent = min(color.redComponent, color.greenComponent, color.blueComponent)
            let saturation = maxComponent - minComponent
            let darkness = 1 - maxComponent

            if darkness < 0.10 && saturation < 0.055 {
                bitmap.setColor(NSColor(calibratedRed: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: 0), atX: x, y: y)
            } else if darkness < 0.16 && saturation < 0.08 {
                let alpha = min(1, max(0, (darkness - 0.10) / 0.06))
                bitmap.setColor(NSColor(calibratedRed: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: alpha), atX: x, y: y)
            }
        }
    }

    let image = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
    image.addRepresentation(bitmap)
    return image
}

func croppedTransparentArtwork(from source: NSImage, sourceBitmap: NSBitmapImageRep) throws -> NSImage {
    let crop = contentBounds(in: sourceBitmap)
    var proposedRect = NSRect(origin: .zero, size: source.size)
    guard let cgImage = source.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
          let croppedCGImage = cgImage.cropping(to: CGRect(x: crop.minX, y: crop.minY, width: crop.width, height: crop.height)) else {
        throw NSError(domain: "DeskItIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not crop source artwork"])
    }

    return transparentArtwork(from: croppedCGImage)
}

func writeIcon(artwork: NSImage, pixelSize: Int, to outputURL: URL) throws {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "DeskItIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate icon bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

    let canvasSize = CGFloat(pixelSize)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()
    drawGradientBackground(size: canvasSize)

    let maxArtworkSide = canvasSize * 0.525
    let scale = min(maxArtworkSide / artwork.size.width, maxArtworkSide / artwork.size.height)
    let artworkSize = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
    let artworkRect = NSRect(
        x: (canvasSize - artworkSize.width) / 2 + canvasSize * (6.0 / 1024.0),
        y: (canvasSize - artworkSize.height) / 2,
        width: artworkSize.width,
        height: artworkSize.height
    )

    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -canvasSize * 0.025)
    shadow.shadowBlurRadius = canvasSize * 0.045
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.18)
    shadow.set()

    artwork.draw(
        in: artworkRect,
        from: NSRect(origin: .zero, size: artwork.size),
        operation: .sourceOver,
        fraction: 1
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DeskItIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render icon"])
    }

    try png.write(to: outputURL)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("usage: render-app-icon.swift <source-image> <iconset-dir>")
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL), let sourceBitmap = bitmap(from: sourceImage) else {
    fail("could not read source image: \(sourceURL.path)")
}

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
let artwork = try croppedTransparentArtwork(from: sourceImage, sourceBitmap: sourceBitmap)

let icons: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in icons {
    try writeIcon(artwork: artwork, pixelSize: size, to: outputURL.appendingPathComponent(filename))
}
