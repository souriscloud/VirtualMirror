// Shared Souris app icon family: data circuit, radial fade and original logo.
import AppKit
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
func arg(_ key: String, _ fallback: String = "") -> String {
  guard let i = args.firstIndex(of: key), i + 1 < args.count else { return fallback }
  return args[i + 1]
}
let name = arg("--app")
let style = "corner-original"
let side = Int(arg("--size", "1024"))!
let output = arg("--output")
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)
ctx.setShouldAntialias(true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let palettes: [String: [CGColor]] = [
  "Istrek": [color(0.25, 0.58, 0.46), color(0.10, 0.33, 0.27)],
  "OptaKube": [color(0.32, 0.60, 1), color(0.12, 0.32, 0.80)],
  "pgBrain": [color(0.57, 0.43, 0.94), color(0.32, 0.20, 0.67)],
  "VirtualMirror": [color(0.39, 0.48, 1), color(0.48, 0.29, 0.87)],
]
let body = CGPath(
  roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185,
  transform: nil)
ctx.saveGState()
ctx.setShadow(
  offset: CGSize(width: 0, height: -12 * CGFloat(side) / 1024), blur: 26 * CGFloat(side) / 1024,
  color: color(0, 0, 0, 0.24))
ctx.addPath(body)
ctx.setFillColor(palettes[name]![1])
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(body)
ctx.clip()
let gradient = CGGradient(
  colorsSpace: space, colors: palettes[name]! as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(
  gradient, start: CGPoint(x: 120, y: 940), end: CGPoint(x: 760, y: 70), options: [])
let light = CGGradient(
  colorsSpace: space, colors: [color(1, 1, 1, 0.08), color(1, 1, 1, 0)] as CFArray,
  locations: [0, 1])!
ctx.drawRadialGradient(
  light, startCenter: CGPoint(x: 290, y: 820), startRadius: 0, endCenter: CGPoint(x: 290, y: 820),
  endRadius: 770, options: [])
// Technology patterns share the user's selected radial envelope.
if side >= 32 {
  let ink = color(0.72, 0.78, 0.84)
  let layer = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  layer.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)
  layer.setStrokeColor(ink)
  layer.setFillColor(ink)
  layer.setLineWidth(0.8)
  layer.setLineCap(.round)
  func segment(_ x: CGFloat, _ y: CGFloat, _ xx: CGFloat, _ yy: CGFloat) {
    layer.move(to: CGPoint(x: x, y: y))
    layer.addLine(to: CGPoint(x: xx, y: yy))
  }
  layer.setLineWidth(3.2)
  for row in 0..<14 {
    let y = CGFloat(232 + row * 44)
    for col in 0..<9 {
      if (row * 13 + col * 7) % 4 == 0 { continue }
      let x = CGFloat(224 + col * 66)
      let flip: CGFloat = (row + col) % 2 == 0 ? 1 : -1
      segment(x, y, x + 22, y)
      segment(x + 22, y, x + 36, y + flip * 14)
      segment(x + 36, y + flip * 14, x + 56, y + flip * 14)
    }
  }
  layer.strokePath()
  for row in 0..<14 {
    for col in 0..<9 {
      if (row + col * 3) % 5 == 0 {
        let x = CGFloat(224 + col * 66)
        let y = CGFloat(232 + row * 44)
        layer.strokeEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
      }
    }
  }
  layer.setBlendMode(.destinationIn)
  let fade = CGGradient(
    colorsSpace: space,
    colors: [color(1, 1, 1, 1), color(1, 1, 1, 0.95), color(1, 1, 1, 0.55), color(1, 1, 1, 0)]
      as CFArray, locations: [0, 0.41, 0.76, 1])!
  layer.drawRadialGradient(
    fade, startCenter: CGPoint(x: 512, y: 540), startRadius: 0, endCenter: CGPoint(x: 512, y: 540),
    endRadius: 380, options: [.drawsAfterEndLocation])
  ctx.draw(layer.makeImage()!, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
}
ctx.restoreGState()
ctx.addPath(body)
ctx.setStrokeColor(color(1, 1, 1, 0.14))
ctx.setLineWidth(2)
ctx.strokePath()
ctx.setFillColor(color(1, 1, 1))
ctx.setStrokeColor(color(1, 1, 1))
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
// Familiar product metaphors, given the same optical field and visual weight.
switch name {
case "Istrek":
  for (x, y): (CGFloat, CGFloat) in [
    (-72, 125), (72, 125), (-144, 0), (0, 0), (144, 0), (-72, -125), (72, -125),
  ] {
    ctx.fillEllipse(in: CGRect(x: 512 + x - 62, y: 540 + y - 62, width: 124, height: 124))
  }
case "OptaKube":
  let top = CGPoint(x: 512, y: 760)
  let left = CGPoint(x: 304, y: 648)
  let right = CGPoint(x: 720, y: 648)
  let middle = CGPoint(x: 512, y: 536)
  let bottom = CGPoint(x: 512, y: 322)
  let bl = CGPoint(x: 304, y: 434)
  let br = CGPoint(x: 720, y: 434)
  for (points, alpha) in [
    ([top, right, middle, left], CGFloat(0.16)), ([left, middle, bottom, bl], 0.06),
    ([right, middle, bottom, br], 0.09),
  ] {
    let path = CGMutablePath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.addLine(to: $0) }
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(color(1, 1, 1, alpha))
    ctx.fillPath()
  }
  ctx.setLineWidth(side <= 16 ? 52 : (side <= 32 ? 40 : 22))
  for (a, b) in [
    (top, left), (top, right), (left, bl), (right, br), (bl, bottom), (br, bottom), (left, middle),
    (right, middle), (middle, bottom),
  ] {
    ctx.move(to: a)
    ctx.addLine(to: b)
  }
  ctx.strokePath()
case "pgBrain":
  let silhouette = CGMutablePath()
  silhouette.addRect(CGRect(x: 306, y: 354, width: 412, height: 368))
  silhouette.addEllipse(in: CGRect(x: 306, y: 302, width: 412, height: 104))
  silhouette.addEllipse(in: CGRect(x: 306, y: 670, width: 412, height: 104))
  ctx.setFillColor(color(1, 1, 1))
  ctx.addPath(silhouette)
  ctx.fillPath()
  ctx.saveGState()
  ctx.addPath(silhouette)
  ctx.clip()
  let cuts = CGMutablePath()
  for y: CGFloat in [420, 546] {
    cuts.addEllipse(in: CGRect(x: 306, y: y, width: 412, height: 100))
  }
  let cutShape = cuts.copy(
    strokingWithWidth: side <= 32 ? 23 : 18, lineCap: .round, lineJoin: .round, miterLimit: 1)
  ctx.addPath(cutShape)
  ctx.clip()
  ctx.drawLinearGradient(
    gradient, start: CGPoint(x: 120, y: 940), end: CGPoint(x: 760, y: 70), options: [])
  ctx.restoreGState()
case "VirtualMirror":
  let screen = CGPath(
    roundedRect: CGRect(x: 276, y: 435, width: 472, height: 306), cornerWidth: 24, cornerHeight: 24,
    transform: nil)
  ctx.setLineWidth(side <= 16 ? 50 : (side <= 32 ? 38 : 21))
  ctx.addPath(screen)
  ctx.strokePath()
  ctx.setFillColor(color(1, 1, 1))
  ctx.fill(CGRect(x: 496, y: 365, width: 32, height: 60))
  let base = CGPath(
    roundedRect: CGRect(x: 405, y: 342, width: 214, height: 23), cornerWidth: 11, cornerHeight: 11,
    transform: nil)
  ctx.addPath(base)
  ctx.fillPath()
  let triangle = CGMutablePath()
  triangle.move(to: CGPoint(x: 512, y: 643))
  triangle.addLine(to: CGPoint(x: 452, y: 540))
  triangle.addLine(to: CGPoint(x: 572, y: 540))
  triangle.closeSubpath()
  ctx.addPath(triangle)
  ctx.fillPath()
default: exit(1)
}
// Preserve the complete original logo without tracing, recolouring or cropping.
if side >= 64 {
  let badge = CGRect(x: 718, y: 54, width: 206, height: 206)
  let shell = CGPath(roundedRect: badge, cornerWidth: 36, cornerHeight: 36, transform: nil)
  ctx.saveGState()
  ctx.setShadow(
    offset: CGSize(width: 0, height: -5 * CGFloat(side) / 1024), blur: 10 * CGFloat(side) / 1024,
    color: color(0, 0, 0, 0.30))
  ctx.addPath(shell)
  ctx.setFillColor(color(0.025, 0.025, 0.025))
  ctx.fillPath()
  ctx.restoreGState()
  let url = URL(fileURLWithPath: arg("--logo", ""))
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let logo = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { fatalError("Original logo missing") }
  ctx.interpolationQuality = .high
  ctx.draw(logo, in: badge.insetBy(dx: 10, dy: 10))
  ctx.addPath(shell)
  ctx.setStrokeColor(color(1, 1, 1, 0.38))
  ctx.setLineWidth(2)
  ctx.strokePath()
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: side, height: side)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
