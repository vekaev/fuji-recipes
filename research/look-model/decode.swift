// Decode each scene's RAF on the Mac: linear sRGB primaries, no Apple tone boost, 16-bit TIFF, long side 768 px.
// Usage: decode <scenes.json> <out dir>. Skips files already done.
import CoreImage
import ImageIO
import Foundation
let args = CommandLine.arguments
let scenes = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [[String: Any]]
let out = URL(fileURLWithPath: args[2]); try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
let ctx = CIContext(options: [.workingColorSpace: linear])
var done = 0
for s in scenes {
    let raf = URL(fileURLWithPath: s["raf"] as! String)
    let dest = out.appendingPathComponent(raf.deletingPathExtension().lastPathComponent + ".tiff")
    if FileManager.default.fileExists(atPath: dest.path) { done += 1; continue }
    guard let f = CIRAWFilter(imageURL: raf) else { print("skip", raf.lastPathComponent); continue }
    f.boostAmount = 0; f.isGamutMappingEnabled = false
    guard let img = f.outputImage else { continue }
    let k = 768 / max(img.extent.width, img.extent.height)
    let small = img.transformed(by: .init(scaleX: k, y: k))
    guard let cg = ctx.createCGImage(small, from: small.extent.integral, format: .RGBA16, colorSpace: linear),
          let d = CGImageDestinationCreateWithURL(dest as CFURL, "public.tiff" as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(d, cg, nil); CGImageDestinationFinalize(d)
    done += 1; if done % 20 == 0 { print(done, "of", scenes.count) }
}
print("decoded", done, "of", scenes.count)
