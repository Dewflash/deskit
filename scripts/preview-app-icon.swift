import AppKit
import Foundation

func fail(_ message: String) -> Never {
    fputs("preview-app-icon: \(message)\n", stderr)
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
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.025, dy: size * 0.025), xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.980, green: 0.982, blue: 0.986, alpha: 1),
        NSColor(calibratedRed: 0.925, green: 0.932, blue: 0.942, alpha: 1),
        NSColor(calibratedRed: 0.835, green: 0.852, blue: 0.875, alpha: 1)
    ])
    gradient?.draw(in: rect, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(calibratedWhite: 1, alpha: 0.55).setStroke()
    path.lineWidth = max(1, size * 0.012)
    path.stroke()

    let inner = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.07, dy: size * 0.07), xRadius: cornerRadius * 0.72, yRadius: cornerRadius * 0.72)
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

func makePreview(sourceURL: URL, outputURL: URL, pixelSize: Int = 1024) throws {
    guard let source = NSImage(contentsOf: sourceURL), let sourceBitmap = bitmap(from: source) else {
        fail("could not read source image: \(sourceURL.path)")
    }

    let crop = contentBounds(in: sourceBitmap)
    if ProcessInfo.processInfo.environment["DESKIT_ICON_DEBUG"] == "1" {
        fputs("crop=\(crop) source=\(sourceBitmap.pixelsWide)x\(sourceBitmap.pixelsHigh)\n", stderr)
    }
    var proposedRect = NSRect(origin: .zero, size: source.size)
    guard let cgImage = source.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
          let croppedCGImage = cgImage.cropping(to: CGRect(x: crop.minX, y: crop.minY, width: crop.width, height: crop.height)) else {
        fail("could not crop source artwork")
    }
    let croppedImage = transparentArtwork(from: croppedCGImage)
    let canvasSize = CGFloat(pixelSize)
    let artworkMaxSide = canvasSize * 0.525
    let scale = min(artworkMaxSide / crop.width, artworkMaxSide / crop.height)
    let artworkSize = NSSize(width: crop.width * scale, height: crop.height * scale)
    let artworkRect = NSRect(
        x: (canvasSize - artworkSize.width) / 2 + canvasSize * (6.0 / 1024.0),
        y: (canvasSize - artworkSize.height) / 2,
        width: artworkSize.width,
        height: artworkSize.height
    )

    guard let outputBitmap = NSBitmapImageRep(
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
        fail("could not allocate output bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outputBitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()
    drawGradientBackground(size: canvasSize)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -canvasSize * 0.025)
    shadow.shadowBlurRadius = canvasSize * 0.045
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.18)
    shadow.set()
    croppedImage.draw(in: artworkRect, from: NSRect(origin: .zero, size: croppedImage.size), operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = outputBitmap.representation(using: .png, properties: [:]) else {
        fail("could not encode png")
    }

    try png.write(to: outputURL)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("usage: preview-app-icon.swift <source-image> <output-png>")
}

try makePreview(
    sourceURL: URL(fileURLWithPath: arguments[1]),
    outputURL: URL(fileURLWithPath: arguments[2])
)
