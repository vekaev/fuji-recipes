import FujiKit
import Foundation

/// `fuji doctor` / `fuji_doctor`: walks the connection one step at a time and stops at the first one that fails,
/// saying what it saw and what to do. Read-only. Steps (docs/CONNECT.md explains each):
///   1 USB      a Fujifilm (vendor 0x04CB) is on the USB bus
///   2 Camera   ImageCaptureCore offers it as a PTP camera
///   3 Session  it answers GetDeviceInfo (model, firmware)
///   4 Mode     0xD16E says USB RAW CONV./BACKUP RESTORE (refused = card reader)
///   5 Slots    the custom-slot selector answers and C1…Cn can be counted
///   +          apps that grab cameras (Preview, Photos, Image Capture, X RAW Studio, Tether app…)
enum Doctor {
    struct Step { var name: String; var ok: Bool; var saw: String; var fix: String? }

    static let grabbers = ["Preview", "Photos", "Image Capture", "FUJIFILM X RAW STUDIO", "FUJIFILM TETHER APP",
                           "X Acquire", "Adobe Lightroom", "Lightroom Classic", "Capture One"]

    static func run() async -> (steps: [Step], apps: [String]) {
        var steps: [Step] = []
        let apps = grabbers.filter { name in !Shell.run("/usr/bin/pgrep", ["-x", name]).isEmpty }

        if Cameras.shared.simulate {
            steps.append(Step(name: "USB", ok: true, saw: "simulated X-E5 (--simulate)", fix: nil))
        } else {
            let usb = Shell.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-w0", "-l"])
            let fuji = usb.contains("\"idVendor\" = 1227")
            let name = usb.components(separatedBy: "\n").first { $0.contains("\"USB Product Name\" = \"FUJIFILM") }?
                .components(separatedBy: "= ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) ?? "Fujifilm camera"
            steps.append(Step(name: "USB", ok: fuji, saw: fuji ? "\(name) is on USB" : "no Fujifilm device on USB",
                              fix: fuji ? nil : "Switch the camera on. Use a USB-C *data* cable (charge-only cables are common), ideally ≤ 1 m, straight into the Mac. On the camera, network/USB tab ▸ USB POWER SUPPLY/COMM SETTING must be AUTO or POWER SUPPLY OFF/COMM ON (POWER SUPPLY ON/COMM OFF blocks data)."))
            guard fuji else { return (steps, apps) }
        }

        guard let cam = await Cameras.shared.current(wait: 5) else {
            steps.append(Step(name: "Camera", ok: false, saw: "on USB, but macOS doesn't offer it as a camera",
                              fix: "Unplug, wait 3 s, plug in again. If Image Capture.app doesn't list it either, restart the Mac's camera service: quit every photo app, then unplug and plug in."))
            return (steps, apps)
        }
        steps.append(Step(name: "Camera", ok: true, saw: "macOS offers it as a PTP camera", fix: nil))

        guard let info = try? await cam.deviceInfo() else {
            steps.append(Step(name: "Session", ok: false, saw: "the camera doesn't answer",
                              fix: "Another app may hold it\(apps.isEmpty ? "" : " (\(apps.joined(separator: ", ")) is running)"): quit it. Then switch the camera off, and on again."))
            return (steps, apps)
        }
        steps.append(Step(name: "Session", ok: true, saw: "\(info.model), firmware \(info.firmware)", fix: nil))

        let mode = (try? await cam.usbMode()) ?? .cardReader
        steps.append(Step(name: "Mode", ok: mode.canWriteSlots, saw: mode.label,
                          fix: mode.canWriteSlots ? nil : "\(USBMode.howToSet) In card-reader mode the camera shows its memory card instead (Preview or Photos may offer to import)."))
        guard mode.canWriteSlots else { return (steps, apps) }

        do {
            let n = try await cam.bankCount()
            steps.append(Step(name: "Slots", ok: n > 0, saw: "C1–C\(n) readable", fix: n > 0 ? nil : "This body doesn't expose custom slots over USB (X-T3, X-T30 and older)."))
        } catch {
            steps.append(Step(name: "Slots", ok: false, saw: "\(error)", fix: "Switch the camera off and on, then run fuji doctor again."))
        }
        return (steps, apps)
    }

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
