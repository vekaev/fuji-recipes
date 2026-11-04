#if canImport(ImageCaptureCore)
import Foundation
import ImageCaptureCore

/// Finds Fujifilm cameras (USB vendor 0x04CB) through ImageCaptureCore. One browser per process: a second one doesn't
/// re-announce an attached camera (zgrimz 09-platform-notes). Must be started on the main thread, and the main run
/// loop must keep running for its callbacks.
public final class CameraBrowser: NSObject, ICDeviceBrowserDelegate, @unchecked Sendable {
    public static let shared = CameraBrowser()
    public static let fujifilmVendorID = 0x04CB

    private let browser = ICDeviceBrowser()
    private let lock = NSLock()
    private var found: [ICCameraDevice] = []
    private var transports: [ObjectIdentifier: ImageCaptureTransport] = [:]
    public private(set) var startedAt: Date?
    /// Called on the main thread when a Fujifilm camera arrives (true) or leaves (false).
    public var onChange: ((String, Bool) -> Void)?

    public func start() {
        guard startedAt == nil else { return }
        startedAt = Date()
        #if targetEnvironment(simulator)
        return   // the iOS Simulator's ImageCaptureCore is a stub without USB (its browser selectors don't exist)
        #endif
        browser.delegate = self
        #if os(iOS)
        // iOS needs both: Control (Settings › Privacy › Camera) and Contents (Files and Folders); without Contents the
        // camera is never announced (zgrimz 09-platform-notes).
        browser.requestControlAuthorization { _ in }
        browser.requestContentsAuthorization { _ in }
        #endif
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
        browser.start()
    }

    public var cameras: [ICCameraDevice] { lock.lock(); defer { lock.unlock() }; return found }

    /// Every camera ImageCaptureCore sees, Fujifilm or not (for "is it plugged in at all?").
    public var allDevices: [(name: String, vendor: Int)] {
        #if targetEnvironment(simulator)
        return []
        #else
        return (browser.devices ?? []).map { ($0.name ?? "camera", Int($0.usbVendorID)) }
        #endif
    }

    /// The transport for the first Fujifilm camera, waiting up to `timeout` for it to be announced.
    public func firstFujifilm(timeout: TimeInterval = 4) async -> ImageCaptureTransport? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let cam = cameras.first {
                return lock.withLock {
                    let key = ObjectIdentifier(cam)
                    if let t = transports[key] { return t }
                    let t = ImageCaptureTransport(device: cam)
                    transports[key] = t
                    return t
                }
            }
            if Date() > deadline { return nil }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let cam = device as? ICCameraDevice, Int(cam.usbVendorID) == Self.fujifilmVendorID else { return }
        lock.lock(); found.append(cam); lock.unlock()
        onChange?(cam.name ?? "Fujifilm camera", true)
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        lock.lock()
        found.removeAll { $0 === device }
        transports[ObjectIdentifier(device)] = nil
        lock.unlock()
        if Int(device.usbVendorID) == Self.fujifilmVendorID { onChange?(device.name ?? "Fujifilm camera", false) }
    }
}

/// PTP over `ICCameraDevice.requestSendPTPCommand`: we build the 12-byte command container; the data phase goes in
/// `outData` without a header; the completion gives the data-in payload and the full response container.
/// Commands are serialised, time out after 20 s, and responses are matched by callback, not transaction id
/// (ImageCaptureCore renumbers them).
public final class ImageCaptureTransport: NSObject, PTPTransport, ICCameraDeviceDelegate, @unchecked Sendable {
    public let device: ICCameraDevice
    public var displayName: String { device.name ?? "Fujifilm camera" }
    private var txid: UInt32 = 1
    private let gate = AsyncGate()

    init(device: ICCameraDevice) {
        self.device = device
        super.init()
    }

    private func openSession() async throws {
        if device.hasOpenSession { return }
        for attempt in 1...5 {
            let error: Error? = await withCheckedContinuation { cont in
                DispatchQueue.main.async {
                    self.device.delegate = self
                    self.device.requestOpenSession(options: [:]) { cont.resume(returning: $0) }
                }
            }
            if error == nil || device.hasOpenSession { return }
            let code = (error as NSError?)?.code ?? 0
            if attempt == 5 { throw CameraError("Couldn't open a session with \(displayName): \(error!.localizedDescription) (\(code)). Unplug the camera, switch it off and on, and try again.") }
            try await Task.sleep(nanoseconds: 700_000_000)   // -9954: still enumerating the card
        }
    }

    public func send(_ op: UInt16, _ params: [UInt32], data: Data?) async throws -> PTPResult {
        await gate.enter()
        defer { Task { await gate.leave() } }
        try await openSession()
        var cmd = Data()
        func w32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { cmd.append(contentsOf: $0) } }
        func w16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { cmd.append(contentsOf: $0) } }
        w32(UInt32(12 + 4 * params.count)); w16(1); w16(op); w32(txid)
        params.forEach(w32)
        txid &+= 1
        let timeout = 20.0 + Double(data?.count ?? 0) / 1_000_000
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<PTPResult, Error>) in
            let once = Once()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if once.claim() { cont.resume(throwing: CameraError(String(format: "The camera didn't answer command 0x%04X in %.0f s. Switch it off and on.", op, timeout))) }
            }
            DispatchQueue.main.async {
                self.device.requestSendPTPCommand(cmd, outData: data) { inData, response, error in
                    guard once.claim() else { return }
                    if let error, response.count < 8 { cont.resume(throwing: CameraError("PTP 0x\(String(op, radix: 16)): \(error.localizedDescription)")); return }
                    let code = response.count >= 8 ? UInt16(response[response.startIndex + 6]) | UInt16(response[response.startIndex + 7]) << 8 : PTPCode.generalError
                    cont.resume(returning: PTPResult(code: code, data: inData))
                }
            }
        }
    }

    // ICCameraDeviceDelegate / ICDeviceDelegate: nothing to do here; the browser tracks arrival and removal.
    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    public func didRemove(_ device: ICDevice) {}
    public func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {}
    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {}
    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}

/// First caller wins (a completion vs its timeout).
final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// One command in flight at a time.
actor AsyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func enter() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func leave() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}
#endif
