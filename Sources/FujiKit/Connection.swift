#if canImport(ImageCaptureCore)
import Foundation

/// The camera the CLI, the MCP server and the app talk to: the simulated X-E5 (`--simulate` / FUJI_SIMULATE=1) or the first Fujifilm on USB.
public final class Cameras: @unchecked Sendable {
    public static let shared = Cameras()
    public var simulate = ProcessInfo.processInfo.environment["FUJI_SIMULATE"] == "1"
    private var simulated: FujiCamera?
    private var real: (AnyObject, FujiCamera)?

    public func current(wait: TimeInterval = 4) async -> FujiCamera? {
        if simulate {
            if simulated == nil { simulated = FujiCamera(transport: SimulatedCamera()) }
            return simulated
        }
        guard let t = await CameraBrowser.shared.firstFujifilm(timeout: wait) else { real = nil; return nil }
        if let real, real.0 === t { return real.1 }
        let cam = FujiCamera(transport: t)
        real = (t, cam)
        return cam
    }

    public func require() async throws -> FujiCamera {
        if let cam = await current() { return cam }
        throw CameraError(noCameraAdvice())
    }

    /// Why no camera is visible, from what USB and ImageCaptureCore see.
    public func noCameraAdvice() -> String {
        #if os(macOS)
        let usb = Shell.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-w0", "-l"])
        let fujiOnUSB = usb.contains("\"idVendor\" = 1227")
        #else
        let fujiOnUSB = false
        #endif
        let others = CameraBrowser.shared.allDevices.map(\.name)
        if fujiOnUSB {
            return "A Fujifilm camera is on USB but not as a PTP camera: it's in USB CARD READER mode. \(USBMode.howToSet)"
        }
        return "No Fujifilm camera found. Switch it on and connect a USB-C data cable. \(USBMode.howToSet)" + (others.isEmpty ? "" : " Other cameras seen: \(others.joined(separator: ", ")).")
    }
}

#if os(macOS)
public enum Shell {
    public static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
}
#endif
#endif
