#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Shared installer artwork, drawn in points and exported at explicit Retina scales.
let args = CommandLine.arguments
func argument(_ name: String, fallback: String = "") -> String {
  guard let index = args.firstIndex(of: name), args.count > index + 1 else { return fallback }
  return args[index + 1]
}
let appName = argument("--name", fallback: "Istrek")
let subtitle = argument("--subtitle", fallback: "Time well tracked. Work beautifully billed.")
let output = argument("--output")
let scale = Int(argument("--scale", fallback: "2"))!
let iconPath = argument("--icon")
guard !output.isEmpty, (1...3).contains(scale) else {
  fatalError("Use --output and --scale 1, 2 or 3")
}
let width: CGFloat = 720
let height: CGFloat = 440
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
  data: nil, width: 720 * scale, height: 440 * scale,
  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

let colors =
  [
    CGColor(srgbRed: 0.095, green: 0.100, blue: 0.143, alpha: 1),
    CGColor(srgbRed: 0.155, green: 0.160, blue: 0.210, alpha: 1),
  ] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(
  gradient, start: CGPoint(x: 0, y: height),
  end: CGPoint(x: width, y: 0), options: [])
let glow = CGGradient(
  colorsSpace: colorSpace,
  colors: [
    CGColor(srgbRed: 0.57, green: 0.62, blue: 0.78, alpha: 0.055),
    CGColor(srgbRed: 0.57, green: 0.62, blue: 0.78, alpha: 0),
  ] as CFArray,
  locations: [0, 1])!
ctx.drawRadialGradient(
  glow, startCenter: CGPoint(x: 360, y: 250), startRadius: 0,
  endCenter: CGPoint(x: 360, y: 250), endRadius: 280, options: [])
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.024))
ctx.setLineWidth(0.5)
for x in stride(from: 0, through: 720, by: 20) {
  ctx.move(to: CGPoint(x: x, y: 0))
  ctx.addLine(to: CGPoint(x: x, y: 440))
}
for y in stride(from: 0, through: 440, by: 20) {
  ctx.move(to: CGPoint(x: 0, y: y))
  ctx.addLine(to: CGPoint(x: 720, y: y))
}
ctx.strokePath()

struct Curve {
  let p0, p1, p2, p3: CGPoint
  func point(_ t: CGFloat) -> CGPoint {
    let u = 1 - t
    return CGPoint(
      x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
      y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y)
  }
  func normal(_ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let dx = 3 * u * u * (p1.x - p0.x) + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x)
    let dy = 3 * u * u * (p1.y - p0.y) + 6 * u * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
    let length = hypot(dx, dy)
    return CGPoint(x: -dy / length, y: dx / length)
  }
}
// Pressure varies across the gesture; the silhouette stays crisp at every scale.
func brush(_ curve: Curve, breadth: CGFloat, seed: CGFloat) {
  var left: [CGPoint] = []
  var right: [CGPoint] = []
  for i in 0...240 {
    let t = CGFloat(i) / 240
    let p = curve.point(t)
    let n = curve.normal(t)
    let pressure = 0.15 + 0.85 * pow(sin(.pi * t), 0.65)
    let tooth = 0.10 * sin(t * 91 + seed) + 0.07 * sin(t * 173 + seed * 3)
    let half = breadth * pressure / 2
    left.append(CGPoint(x: p.x + n.x * (half + tooth), y: p.y + n.y * (half + tooth)))
    right.append(CGPoint(x: p.x - n.x * (half - tooth), y: p.y - n.y * (half - tooth)))
  }
  let path = CGMutablePath()
  path.move(to: left[0])
  for point in left.dropFirst() { path.addLine(to: point) }
  for point in right.reversed() { path.addLine(to: point) }
  path.closeSubpath()
  ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.93, blue: 0.87, alpha: 0.90))
  ctx.addPath(path)
  ctx.fillPath()
  for offset: CGFloat in [-0.20, 0.26] {
    let strand = CGMutablePath()
    for i in 15...223 {
      let t = CGFloat(i) / 240
      let p = curve.point(t)
      let n = curve.normal(t)
      let shift = offset * breadth * pow(sin(.pi * t), 0.65)
      let v = CGPoint(x: p.x + n.x * shift, y: p.y + n.y * shift)
      if i == 15 { strand.move(to: v) } else { strand.addLine(to: v) }
    }
    ctx.addPath(strand)
    ctx.setStrokeColor(CGColor(srgbRed: 0.19, green: 0.20, blue: 0.25, alpha: 0.24))
    ctx.setLineWidth(0.45)
    ctx.strokePath()
  }
}
brush(
  Curve(
    p0: CGPoint(x: 270, y: 225), p1: CGPoint(x: 315, y: 272),
    p2: CGPoint(x: 397, y: 267), p3: CGPoint(x: 454, y: 224)), breadth: 5.9, seed: 2)
brush(
  Curve(
    p0: CGPoint(x: 448, y: 253), p1: CGPoint(x: 451, y: 242),
    p2: CGPoint(x: 456, y: 231), p3: CGPoint(x: 454, y: 223)), breadth: 4.7, seed: 5)
brush(
  Curve(
    p0: CGPoint(x: 426, y: 225), p1: CGPoint(x: 434, y: 223),
    p2: CGPoint(x: 447, y: 225), p3: CGPoint(x: 454, y: 223)), breadth: 4.7, seed: 7)

func text(
  _ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
  opacity: CGFloat, x: CGFloat = 360
) {
  let string = NSAttributedString(
    string: value,
    attributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: opacity),
    ])
  guard string.size().width <= 640 else { fatalError("Installer text exceeds safe width") }
  string.draw(at: CGPoint(x: x - string.size().width / 2, y: y))
}
text(appName, y: 366, size: 28, weight: .semibold, opacity: 0.96)
text(subtitle, y: 341, size: 13, weight: .regular, opacity: 0.70)
text("Drag to install", y: 190, size: 12, weight: .medium, opacity: 0.78)
text("Made by Souris.CLOUD", y: 22, size: 11, weight: .regular, opacity: 0.58)
if !iconPath.isEmpty {
  guard let icon = NSImage(contentsOfFile: iconPath) else { fatalError("Missing preview icon") }
  let folder = NSWorkspace.shared.icon(forFile: "/Applications")
  for (image, x) in [(icon, CGFloat(180)), (folder, CGFloat(540))] {
    image.draw(
      in: CGRect(x: x - 48, y: 177, width: 96, height: 96), from: .zero,
      operation: .sourceOver, fraction: 1, respectFlipped: false,
      hints: [.interpolation: NSImageInterpolation.high])
  }
  text(appName, y: 151, size: 13, weight: .regular, opacity: 1, x: 180)
  text("Applications", y: 151, size: 13, weight: .regular, opacity: 1, x: 540)
}
NSGraphicsContext.restoreGraphicsState()
let image = ctx.makeImage()!
let bitmap = NSBitmapImageRep(cgImage: image)
bitmap.size = NSSize(width: 720, height: 440)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Rendered \(appName): \(720*scale) × \(440*scale), sRGB")
