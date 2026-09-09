import AppKit
import ImageIO

let sourceURL = URL(fileURLWithPath: "Resources/AppIcon.svg")
let destinationURL = URL(fileURLWithPath: "Resources/AppIcon.icns")

guard let image = NSImage(contentsOf: sourceURL) else {
    fatalError("Could not load AppIcon.svg")
}

func pngData(size: Int) -> Data {
    var proposedRect = NSRect(origin: .zero, size: NSSize(width: 1024, height: 1024))
    guard let sourceImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: size * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        fatalError("Could not rasterize AppIcon.svg")
    }

    context.interpolationQuality = .high
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let resizedImage = context.makeImage() else {
        fatalError("Could not resize AppIcon.svg")
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
        fatalError("Could not create PNG data")
    }
    CGImageDestinationAddImage(destination, resizedImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not create PNG data")
    }
    return data as Data
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var value = value.bigEndian
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}

let chunks: [(String, Data)] = [
    ("icp4", pngData(size: 16)),
    ("icp5", pngData(size: 32)),
    ("ic07", pngData(size: 128)),
    ("ic08", pngData(size: 256)),
    ("ic09", pngData(size: 512)),
    ("ic10", pngData(size: 1024))
]

var output = Data("icns".utf8)
let totalLength = chunks.reduce(8) { $0 + 8 + $1.1.count }
appendBigEndian(UInt32(totalLength), to: &output)
for (type, data) in chunks {
    output.append(contentsOf: type.utf8)
    appendBigEndian(UInt32(8 + data.count), to: &output)
    output.append(data)
}

try output.write(to: destinationURL)
