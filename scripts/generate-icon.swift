#!/usr/bin/env swift
// Draws the Pagedrop app icon with Core Graphics and writes every size macOS expects.
//
// Usage: swift scripts/generate-icon.swift [output-directory]
// Default output: Pagedrop/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit
import CoreGraphics
import Foundation

let outputDirectory = CommandLine.arguments.dropFirst().first
    ?? "Pagedrop/Resources/Assets.xcassets/AppIcon.appiconset"

/// Draws the icon into a square context, using a 1024-point design grid.
func drawIcon(in context: CGContext, size: CGFloat) {
    let unit = size / 1024
    context.scaleBy(x: unit, y: unit)

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Background: the standard macOS icon grid leaves a margin around a rounded square.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(tilePath)
    context.setFillColor(CGColor(red: 0.25, green: 0.35, blue: 0.95, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.36, green: 0.52, blue: 1.00, alpha: 1),
            CGColor(red: 0.30, green: 0.22, blue: 0.86, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // The page, with a folded top-right corner.
    let page = CGRect(x: 292, y: 232, width: 440, height: 560)
    let fold: CGFloat = 130
    let pagePath = CGMutablePath()
    pagePath.move(to: CGPoint(x: page.minX + 28, y: page.minY))
    pagePath.addLine(to: CGPoint(x: page.maxX - 28, y: page.minY))
    pagePath.addArc(tangent1End: CGPoint(x: page.maxX, y: page.minY), tangent2End: CGPoint(x: page.maxX, y: page.minY + 28), radius: 28)
    pagePath.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    pagePath.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    pagePath.addLine(to: CGPoint(x: page.minX + 28, y: page.maxY))
    pagePath.addArc(tangent1End: CGPoint(x: page.minX, y: page.maxY), tangent2End: CGPoint(x: page.minX, y: page.maxY - 28), radius: 28)
    pagePath.addLine(to: CGPoint(x: page.minX, y: page.minY + 28))
    pagePath.addArc(tangent1End: CGPoint(x: page.minX, y: page.minY), tangent2End: CGPoint(x: page.minX + 28, y: page.minY), radius: 28)
    pagePath.closeSubpath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: CGColor(gray: 0, alpha: 0.30))
    context.addPath(pagePath)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // The fold.
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    foldPath.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold + 24))
    foldPath.addArc(tangent1End: CGPoint(x: page.maxX - fold, y: page.maxY - fold), tangent2End: CGPoint(x: page.maxX - fold + 24, y: page.maxY - fold), radius: 24)
    foldPath.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    foldPath.closeSubpath()
    context.addPath(foldPath)
    context.setFillColor(CGColor(red: 0.80, green: 0.84, blue: 0.98, alpha: 1))
    context.fillPath()

    // Text lines.
    context.setFillColor(CGColor(red: 0.80, green: 0.84, blue: 0.98, alpha: 1))
    for (index, width) in [300, 240].enumerated() {
        let line = CGRect(x: page.minX + 56, y: page.maxY - 190 - CGFloat(index) * 56, width: CGFloat(width), height: 26)
        context.addPath(CGPath(roundedRect: line, cornerWidth: 13, cornerHeight: 13, transform: nil))
        context.fillPath()
    }

    // A downward arrow: the "drop".
    let arrowColor = CGColor(red: 0.30, green: 0.30, blue: 0.92, alpha: 1)
    context.setStrokeColor(arrowColor)
    context.setLineWidth(46)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let centerX = page.midX
    context.move(to: CGPoint(x: centerX, y: page.minY + 262))
    context.addLine(to: CGPoint(x: centerX, y: page.minY + 108))
    context.strokePath()
    context.move(to: CGPoint(x: centerX - 76, y: page.minY + 186))
    context.addLine(to: CGPoint(x: centerX, y: page.minY + 105))
    context.addLine(to: CGPoint(x: centerX + 76, y: page.minY + 186))
    context.strokePath()
}

func renderPNG(pixels: Int) -> Data {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    drawIcon(in: context, size: CGFloat(pixels))
    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

struct Slot {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var fileName: String { "icon_\(points)x\(points)@\(scale)x.png" }
}

let slots = [16, 32, 128, 256, 512].flatMap { points in
    [Slot(points: points, scale: 1), Slot(points: points, scale: 2)]
}

let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for slot in slots {
    try renderPNG(pixels: slot.pixels).write(to: directory.appendingPathComponent(slot.fileName))
}

let images = slots.map { slot in
    """
        {
          "filename" : "\(slot.fileName)",
          "idiom" : "mac",
          "scale" : "\(slot.scale)x",
          "size" : "\(slot.points)x\(slot.points)"
        }
    """
}.joined(separator: ",\n")

let contents = """
{
  "images" : [
\(images)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try contents.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(slots.count) icons to \(directory.path)")
