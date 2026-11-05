// Per-scene RAW metadata for the camera proxy: the as-shot white balance (temperature, tint) and exposure as macOS
// reads them. Usage: meta <scenes.json> > meta.jsonl
import CoreImage
import Foundation
let scenes = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
for s in scenes {
    let raf = s["raf"] as! String
    guard let f = CIRAWFilter(imageURL: URL(fileURLWithPath: raf)) else { continue }
    let o: [String: Any] = ["raf": raf, "temperature": f.neutralTemperature, "tint": f.neutralTint,
                            "baseline_exposure": f.baselineExposure, "width": f.nativeSize.width, "height": f.nativeSize.height]
    print(String(decoding: try! JSONSerialization.data(withJSONObject: o), as: UTF8.self))
}
