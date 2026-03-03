#!/usr/bin/env swift
//
// generate-dmg-background.swift
// Generates a branded DMG background image with a dark mirror/glass aesthetic.
// Output: scripts/dmg-background.png (640x480) and scripts/dmg-background@2x.png (1280x960)
//
// Usage: swift scripts/generate-dmg-background.swift
//

import AppKit
import CoreGraphics

func generateBackground(width: Int, height: Int, outputPath: String) {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)

    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        print("ERROR: Could not get graphics context")
        image.unlockFocus()
        return
    }

    // --- Dark gradient background ---
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0),   // Near-black top
        CGColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 1.0),   // Dark blue-gray middle
        CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0),   // Near-black bottom
    ] as CFArray
    let gradientLocations: [CGFloat] = [0.0, 0.5, 1.0]

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: gradientLocations) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: CGFloat(width) / 2, y: CGFloat(height)),
            end: CGPoint(x: CGFloat(width) / 2, y: 0),
            options: []
        )
    }

    // --- Subtle reflective horizontal line (the "mirror" motif) ---
    let mirrorY = CGFloat(height) * 0.45
    let mirrorHeight: CGFloat = 1.5

    // Soft glow around the line
    for i in stride(from: 20, through: 1, by: -1) {
        let alpha = 0.01 * (1.0 - CGFloat(i) / 20.0)
        context.setFillColor(CGColor(red: 0.6, green: 0.7, blue: 0.9, alpha: alpha))
        let glowRect = CGRect(
            x: CGFloat(width) * 0.1,
            y: mirrorY - CGFloat(i),
            width: CGFloat(width) * 0.8,
            height: mirrorHeight + CGFloat(i) * 2
        )
        context.fill(glowRect)
    }

    // The bright mirror line itself
    let lineGradientColors = [
        CGColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 0.0),
        CGColor(red: 0.6, green: 0.7, blue: 0.9, alpha: 0.4),
        CGColor(red: 0.8, green: 0.85, blue: 1.0, alpha: 0.6),
        CGColor(red: 0.6, green: 0.7, blue: 0.9, alpha: 0.4),
        CGColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 0.0),
    ] as CFArray
    let lineLocations: [CGFloat] = [0.0, 0.2, 0.5, 0.8, 1.0]

    context.saveGState()
    context.clip(to: CGRect(x: 0, y: mirrorY, width: CGFloat(width), height: mirrorHeight))
    if let lineGradient = CGGradient(colorsSpace: colorSpace, colors: lineGradientColors, locations: lineLocations) {
        context.drawLinearGradient(
            lineGradient,
            start: CGPoint(x: 0, y: mirrorY),
            end: CGPoint(x: CGFloat(width), y: mirrorY),
            options: []
        )
    }
    context.restoreGState()

    // --- Subtle radial glow behind where the app icon sits (left side) ---
    let iconCenterX = CGFloat(width) * 0.25  // ~160/640 or 320/1280
    let iconCenterY = CGFloat(height) * 0.50
    let glowRadius = CGFloat(min(width, height)) * 0.25

    let radialColors = [
        CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 0.08),
        CGColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 0.0),
    ] as CFArray
    let radialLocations: [CGFloat] = [0.0, 1.0]

    if let radialGradient = CGGradient(colorsSpace: colorSpace, colors: radialColors, locations: radialLocations) {
        context.drawRadialGradient(
            radialGradient,
            startCenter: CGPoint(x: iconCenterX, y: iconCenterY),
            startRadius: 0,
            endCenter: CGPoint(x: iconCenterX, y: iconCenterY),
            endRadius: glowRadius,
            options: []
        )
    }

    // --- App name text at top ---
    let titleFont = NSFont.systemFont(ofSize: CGFloat(height) * 0.05, weight: .light)
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor(calibratedRed: 0.7, green: 0.75, blue: 0.85, alpha: 0.6),
    ]
    let titleString = "VirtualMirror" as NSString
    let titleSize = titleString.size(withAttributes: titleAttributes)
    let titlePoint = NSPoint(
        x: (CGFloat(width) - titleSize.width) / 2,
        y: CGFloat(height) * 0.85
    )
    titleString.draw(at: titlePoint, withAttributes: titleAttributes)

    // --- Subtle arrow hint between icon and Applications ---
    let arrowY = CGFloat(height) * 0.50
    let arrowStartX = CGFloat(width) * 0.38
    let arrowEndX = CGFloat(width) * 0.62
    let arrowColor = CGColor(red: 0.5, green: 0.55, blue: 0.7, alpha: 0.15)

    context.setStrokeColor(arrowColor)
    context.setLineWidth(2.0)
    context.setLineCap(.round)

    // Arrow shaft
    context.move(to: CGPoint(x: arrowStartX, y: arrowY))
    context.addLine(to: CGPoint(x: arrowEndX, y: arrowY))
    context.strokePath()

    // Arrow head
    let headSize: CGFloat = CGFloat(width) * 0.015
    context.move(to: CGPoint(x: arrowEndX - headSize, y: arrowY + headSize))
    context.addLine(to: CGPoint(x: arrowEndX, y: arrowY))
    context.addLine(to: CGPoint(x: arrowEndX - headSize, y: arrowY - headSize))
    context.strokePath()

    image.unlockFocus()

    // Save as PNG
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("ERROR: Could not generate PNG data")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated: \(outputPath) (\(width)x\(height))")
    } catch {
        print("ERROR: Could not write \(outputPath): \(error)")
    }
}

// --- Main ---
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path

let path1x = "\(scriptDir)/dmg-background.png"
let path2x = "\(scriptDir)/dmg-background@2x.png"

generateBackground(width: 640, height: 480, outputPath: path1x)
generateBackground(width: 1280, height: 960, outputPath: path2x)

print("\nDMG background images generated successfully.")
print("These will be used by scripts/release.sh when creating the DMG installer.")
