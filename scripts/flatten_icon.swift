#!/usr/bin/env swift
//
// Removes the alpha channel from the app icon.
//
// App Store Connect rejects an app icon that carries an alpha channel, with
// "Invalid large app icon ... can't be transparent nor contain an alpha
// channel". Xcode does not warn about it and a local build succeeds, so it
// surfaces at upload, which is the worst moment to find out.
//
// Every pixel is drawn onto opaque white first, so anything that was
// transparent becomes white rather than black, which is what a rounded-corner
// mask would have shown anyway.
//
// Run:  swift scripts/flatten_icon.swift <path-to-png>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: flatten_icon.swift <path-to-png>\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: arguments[1])

guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("could not read \(url.path)\n".utf8))
    exit(1)
}

let width = image.width
let height = image.height

// noneSkipLast is what makes the result opaque: the byte that would hold alpha
// is present for alignment and ignored, so the encoder writes no alpha channel.
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("could not create a drawing context\n".utf8))
    exit(1)
}

context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let flattened = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else {
    FileHandle.standardError.write(Data("could not write \(url.path)\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(destination, flattened, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not finalise \(url.path)\n".utf8))
    exit(1)
}

print("flattened \(url.lastPathComponent): \(width)x\(height), no alpha")
