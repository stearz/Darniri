#!/usr/bin/env swift
import AppKit

// Run from the repository root: swift Scripts/generate-icons.swift
// Preserve the supplied artwork, add transparency outside its rounded tile,
// and leave the standard macOS margin around the icon.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = NSImage(contentsOf: root.appendingPathComponent("Resources/IconSource/AppIcon.png"))!
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(size: Int, draw: (CGFloat) -> Void) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let data = png(size: points * scale) { size in
            let tile = NSRect(x: size / 16, y: size / 16, width: size * 7 / 8, height: size * 7 / 8)
            NSBezierPath(roundedRect: tile, xRadius: size * 0.145, yRadius: size * 0.145).addClip()
            source.draw(in: tile, from: .zero, operation: .copy, fraction: 1)
        }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if points == 512 && scale == 2 {
            try data.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
        }
    }
}

// A small monochrome rendering of the artwork's three windows and orbital arc.
for scale in [1, 2] {
    let data = png(size: 18 * scale) { size in
        let transform = NSAffineTransform()
        transform.scale(by: size / 18)
        transform.concat()
        NSColor.black.setStroke()
        for rect in [
            NSRect(x: 2, y: 2, width: 5, height: 14),
            NSRect(x: 8.5, y: 8.5, width: 7.5, height: 6),
            NSRect(x: 8.5, y: 2, width: 6.5, height: 5)
        ] {
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            path.lineWidth = 1.2
            path.stroke()
        }
        let orbit = NSBezierPath()
        orbit.move(to: NSPoint(x: 0.8, y: 6))
        orbit.curve(
            to: NSPoint(x: 17.2, y: 12),
            controlPoint1: NSPoint(x: 0, y: -1),
            controlPoint2: NSPoint(x: 18.5, y: 3)
        )
        orbit.lineWidth = 1
        orbit.stroke()
    }
    let suffix = scale == 2 ? "@2x" : ""
    try data.write(to: root.appendingPathComponent("Resources/StatusIcon\(suffix).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: iconset)
