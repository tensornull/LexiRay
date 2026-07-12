#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: make_contact_sheet.swift <screenshot-directory> <output.png>\n", stderr)
  exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let extensions = Set(["png", "jpg", "jpeg"])
let urls = (try? FileManager.default.contentsOfDirectory(
  at: directory,
  includingPropertiesForKeys: [.isRegularFileKey],
  options: [.skipsHiddenFiles]
)) ?? []

let images: [(URL, NSImage)] = urls
  .filter { extensions.contains($0.pathExtension.lowercased()) && $0.standardizedFileURL != output.standardizedFileURL }
  .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  .compactMap { url in NSImage(contentsOf: url).map { (url, $0) } }

guard !images.isEmpty else {
  fputs("No screenshots found in \(directory.path)\n", stderr)
  exit(2)
}

let columns = min(3, images.count)
let rows = Int(ceil(Double(images.count) / Double(columns)))
let margin = 16
let imageWidth = 480
let imageHeight = 300
let labelHeight = 28
let cellWidth = imageWidth
let cellHeight = imageHeight + labelHeight
let canvasWidth = margin + columns * (cellWidth + margin)
let canvasHeight = margin + rows * (cellHeight + margin)

guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: canvasWidth,
  pixelsHigh: canvasHeight,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bitmapFormat: [],
  bytesPerRow: 0,
  bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fputs("Could not create contact sheet bitmap\n", stderr)
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)).fill()

let labelAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
  .foregroundColor: NSColor.white
]

for (index, item) in images.enumerated() {
  let column = index % columns
  let row = index / columns
  let x = margin + column * (cellWidth + margin)
  let top = canvasHeight - margin - row * (cellHeight + margin)
  let labelRect = NSRect(
    x: CGFloat(x),
    y: CGFloat(top - cellHeight),
    width: CGFloat(cellWidth),
    height: CGFloat(labelHeight)
  )
  let imageRect = NSRect(
    x: CGFloat(x),
    y: labelRect.maxY,
    width: CGFloat(imageWidth),
    height: CGFloat(imageHeight)
  )

  NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
  NSBezierPath(rect: imageRect).fill()

  let image = item.1
  let scale = min(imageRect.width / image.size.width, imageRect.height / image.size.height)
  let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
  let drawRect = NSRect(
    x: imageRect.midX - drawSize.width / 2,
    y: imageRect.midY - drawSize.height / 2,
    width: drawSize.width,
    height: drawSize.height
  )
  image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
  item.0.lastPathComponent.draw(in: labelRect.insetBy(dx: 4, dy: 5), withAttributes: labelAttributes)
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Could not encode contact sheet PNG\n", stderr)
  exit(1)
}

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: output, options: .atomic)
print(output.path)
