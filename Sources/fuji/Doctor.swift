import FujiKit
import Foundation

extension Doctor {
    static func json(_ r: (steps: [Step], apps: [String])) -> JSON {
        var o: JSON = ["ok": r.steps.allSatisfy(\.ok) && r.steps.count >= 5,
                       "steps": r.steps.map { s -> JSON in
                           var j: JSON = ["step": s.name, "ok": s.ok, "saw": s.saw]
                           if let f = s.fix { j["fix"] = f }
                           return j
                       }]
        if !r.apps.isEmpty { o["appsThatGrabCameras"] = r.apps }
        return o
    }

    static func text(_ r: (steps: [Step], apps: [String])) -> String {
        var lines = ["fuji doctor — connection check (read-only)", ""]
        for (i, s) in r.steps.enumerated() {
            lines.append("\(s.ok ? "✓" : "✗") \(i + 1). \(s.name.padding(toLength: 8, withPad: " ", startingAt: 0)) \(s.saw)")
            if let f = s.fix { lines.append("     → \(f)") }
        }
        if !r.apps.isEmpty { lines.append(""); lines.append("Running apps that can grab the camera: \(r.apps.joined(separator: ", ")). Quit them if a step fails.") }
        if r.steps.allSatisfy(\.ok) && r.steps.count >= 5 { lines += ["", "All good: fuji slots reads the camera; writes go through fuji_plan_write → approve → fuji_apply_write."] }
        else { lines += ["", "Step-by-step setup: docs/CONNECT.md (github.com/vekaev/fuji-recipes)."] }
        return lines.joined(separator: "\n")
    }
}
