#!/usr/bin/env swift
import Foundation
import ImageIO

let source = CGImageSourceCreateWithURL(
  URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
guard CGImageSourceGetCount(source) == 2 else {
  fputs("Expected 1x and 2x artwork\n", stderr)
  exit(1)
}
for index in 0..<2 {
  let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)! as NSDictionary
  let scale = index + 1
  guard properties[kCGImagePropertyPixelWidth] as? Int == 720 * scale,
    properties[kCGImagePropertyPixelHeight] as? Int == 440 * scale,
    abs((properties[kCGImagePropertyDPIWidth] as! Double) - Double(72 * scale)) < 0.1,
    abs((properties[kCGImagePropertyDPIHeight] as! Double) - Double(72 * scale)) < 0.1
  else {
    fputs("Artwork resolution or logical point size is incorrect\n", stderr)
    exit(1)
  }
}
print("1x/2x artwork resolutions and DPI verified")
