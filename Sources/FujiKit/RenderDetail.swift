import CoreGraphics
import Foundation
import ImageIO

/// Sharpens the camera's 640-px render without the camera: tones and color stay the render's, fine detail comes from
/// the big JPEG inside the RAF (4416 px on an X-E5). Each pixel = upscaled render × (preview / the preview blurred to
/// the render's size), on luminance, so crushed shadows stay crushed and a mono render stays mono. It has no grain and
/// isn't a real development: the camera's full-size render replaces it whenever the camera is there.
///
/// Works in sensor orientation, like the renders; `RenderCache` tags the result.
public struct RenderDetail: Sendable {
    public let width: Int
    public let height: Int
    private let ratio: [Float]

    /// The JPEG embedded in a RAF: the offset and length are big-endian at bytes 84 and 88.
    public static func embeddedPreview(_ raf: URL) -> Data? {
        guard let f = try? FileHandle(forReadingFrom: raf), let head = try? f.read(upToCount: 92), head.count == 92,
              head.prefix(15) == Data("FUJIFILMCCD-RAW".utf8) else { return nil }
        let be = { (at: Int) in head[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
        let offset = be(84), length = be(88)
        guard length > 0, (try? f.seek(toOffset: UInt64(offset))) != nil, let jpeg = try? f.read(upToCount: length), jpeg.count == length else { return nil }
        return jpeg
    }

    /// The detail of one RAW, reusable for all its renders (a second or so to make, ~25 MB). Nil without a preview
    /// bigger than the render.
    public init?(preview jpeg: Data, side: Int = 3000, renderWidth: Int = 640) {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let big = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceCreateThumbnailWithTransform: false,
                                                                     kCGImageSourceThumbnailMaxPixelSize: side] as CFDictionary),
              max(big.width, big.height) > renderWidth * 3 / 2 else { return nil }
        let w = big.width, h = big.height
        let small = Self.rgba(big, width: renderWidth, height: renderWidth * h / w)
        guard let small, let blurred = Self.rgba(small.image, width: w, height: h), let sharp = Self.rgba(big, width: w, height: h) else { return nil }
        var r = [Float](repeating: 1, count: w * h)
        for i in 0..<(w * h) {
            let a = Self.luma(sharp.pixels, i), b = Self.luma(blurred.pixels, i)
            r[i] = (a + 8) / (b + 8)
        }
        width = w; height = h; ratio = r
    }

    /// The render with the detail applied, as a JPEG; bars of a 4:3 camera preview are cut off. Nil if it can't be read.
    public func apply(toRender jpeg: Data, quality: Double = 0.92) -> Data? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil), let lo = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let frame = Self.withoutBars(lo, aspect: Double(width) / Double(height))
        guard let cropped = lo.cropping(to: frame), var up = Self.rgba(cropped, width: width, height: height) else { return nil }
        up.pixels.withUnsafeMutableBufferPointer { p in
            for i in 0..<(width * height) {
                let g = ratio[i]
                for c in 0..<3 { p[i * 4 + c] = UInt8(min(255, Float(p[i * 4 + c]) * g + 0.5)) }
            }
        }
        guard let out = Self.image(up.pixels, width: width, height: height) else { return nil }
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, out, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? data as Data : nil
    }

    /// The photo inside a render: the camera's previews are 640×480 with black bars around a 3:2 picture.
    static func withoutBars(_ img: CGImage, aspect: Double) -> CGRect {
        let w = Double(img.width), h = Double(img.height)
        let even = { (v: Double) in (v / 2).rounded(.down) * 2 }     // 426.67 → 426: 27 black rows above and below
        if w / h < aspect { let fit = even(w / aspect); return CGRect(x: 0, y: (h - fit) / 2, width: w, height: fit) }
        let fit = even(h * aspect)
        return CGRect(x: (w - fit) / 2, y: 0, width: fit, height: h)
    }

    private static func luma(_ p: [UInt8], _ i: Int) -> Float {
        0.2126 * Float(p[i * 4]) + 0.7152 * Float(p[i * 4 + 1]) + 0.0722 * Float(p[i * 4 + 2])
    }

    private struct Bitmap { var pixels: [UInt8]; let width: Int; let height: Int
        var image: CGImage { RenderDetail.image(pixels, width: width, height: height)! } }

    private static func rgba(_ img: CGImage, width w: Int, height h: Int) -> Bitmap? {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            c.interpolationQuality = .high
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Bitmap(pixels: px, width: w, height: h) : nil
    }

    private static func image(_ px: [UInt8], width w: Int, height h: Int) -> CGImage? {
        guard let p = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: p, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
