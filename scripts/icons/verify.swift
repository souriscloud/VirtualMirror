import CoreGraphics
import Foundation
import ImageIO

for file in CommandLine.arguments.dropFirst() {
  guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: file) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
    let data = context.data
  else { fatalError("Cannot decode icon: \(file)") }
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let pixels = data.assumingMemoryBound(to: UInt8.self)
  func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * image.width + x) * 4 + 3] }
  for x in 0..<image.width {
    precondition(
      alpha(x, 0) == 0 && alpha(x, image.height - 1) == 0, "Clipped vertical edge: \(file)")
  }
  for y in 0..<image.height {
    precondition(
      alpha(0, y) == 0 && alpha(image.width - 1, y) == 0, "Clipped horizontal edge: \(file)")
  }
  precondition(alpha(image.width / 2, image.height / 2) == 255, "Missing opaque body: \(file)")
  precondition(image.colorSpace?.name == CGColorSpace.sRGB, "Icon is not sRGB: \(file)")
}
print("All native sizes: sRGB, opaque body and clear outer edges verified")
