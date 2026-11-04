#if canImport(ImageCaptureCore) && os(macOS)
import Foundation

/// `fuji doctor` / `fuji_doctor`: walks the connection one step at a time and stops at the first one that fails,
/// saying what it saw and what to do. Read-only. Steps (docs/CONNECT.md explains each):
///   1 USB      a Fujifilm (vendor 0x04CB) is on the USB bus
///   2 Camera   ImageCaptureCore offers it as a PTP camera
///   3 Session  it answers GetDeviceInfo (model, firmware)
///   4 Mode     0xD16E says USB RAW CONV./BACKUP RESTORE (refused = card reader)
///   5 Slots    the custom-slot selector answers and C1…Cn can be counted
///   +          apps that grab cameras (Preview, Photos, Image Capture, X RAW Studio, Tether app…)
public enum Doctor {
    public struct Step: Sendable { public var name: String; public var ok: Bool; public var saw: String; public var fix: String? }

    public static let grabbers = ["Preview", "Photos", "Image Capture", "FUJIFILM X RAW STUDIO", "FUJIFILM TETHER APP",
                           "X Acquire", "Adobe Lightroom", "Lightroom Classic", "Capture One"]

    public static func run() async -> (steps: [Step], apps: [String]) {
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
}
#endif
