import Foundation
import IOKit
import IOKit.hid

/// ROBOBLOQ / DX-Light USB monitor light bars.
public final class RobobloqLight: LightDevice, @unchecked Sendable {
    fileprivate let hid: IOHIDDevice
    private var seq: UInt8 = 0
    private var lastReply = Date.distantPast
    private var opened = false
    private var missedChecks = 0

    fileprivate init(hid: IOHIDDevice, location: Int) {
        self.hid = hid
        super.init(id: String(format: "robobloq:usb:%08x", location), brand: "ROBOBLOQ",
                   name: "Monitor Light Bar", model: "USB light bar", kind: .strip,
                   capabilities: [.color, .brightness, .perLED, .nativeEffects],
                   ledCount: 75, maxFPS: 25, address: "USB")
        nativeEffects = RobobloqProtocol.builtinEffects
    }

    private func nextSeq() -> UInt8 {
        seq = seq >= 254 ? 1 : seq + 1
        return seq
    }

    /// Runs on `queue`.
    private func send(_ packet: [UInt8]) {
        guard opened else { return }
        for report in RobobloqProtocol.reports(packet) {
            let rc = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(hid, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
            }
            if rc != kIOReturnSuccess {
                setReachable(false)
                return
            }
        }
    }

    fileprivate func open() {
        queue.async { [self] in
            opened = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
            send(RobobloqProtocol.readInfo(seq: nextSeq()))
            if opened { isReachable = false; setReachable(true) }
        }
    }

    fileprivate func close() {
        queue.sync {
            if opened { IOHIDDeviceClose(hid, IOOptionBits(kIOHIDOptionsTypeNone)) }
            opened = false
        }
    }

    fileprivate func received(_ report: [UInt8]) {
        queue.async { [self] in
            lastReply = Date()
            missedChecks = 0
            log.debug("robobloq reply action=\(report.count > 4 ? report[4] : 0, privacy: .public)")
            if let info = RobobloqProtocol.parseInfo(report), info.ledCount > 0, info.ledCount != ledCount {
                ledCount = info.ledCount
                model = "USB light bar · \(info.ledCount) LEDs · fw \(info.firmware)"
                changed()
            }
        }
    }

    public override func setPower(_ on: Bool) {
        // The bar has no real power command over USB; black is "off".
        if !on { queue.async { [self] in send(RobobloqProtocol.off(seq: nextSeq())) } }
    }

    public override func setBrightness(_ value: Double) {
        queue.async { [self] in send(RobobloqProtocol.brightness(value, seq: nextSeq())) }
    }

    public override func setColor(_ color: RGB) {
        queue.async { [self] in send(RobobloqProtocol.solid(color, ledCount: ledCount, seq: nextSeq())) }
    }

    public override func setFrame(_ colors: [RGB]) {
        queue.async { [self] in send(RobobloqProtocol.frame(colors, seq: nextSeq())) }
    }

    public override func startNativeEffect(_ effect: NativeEffect, speed: Double, color: RGB) {
        guard let i = nativeEffects.firstIndex(of: effect) else { return }
        queue.async { [self] in
            send(RobobloqProtocol.solid(color, ledCount: ledCount, seq: nextSeq()))
            Thread.sleep(forTimeInterval: 0.03)
            send(RobobloqProtocol.effectSpeed(speed, seq: nextSeq()))
            send(RobobloqProtocol.builtinEffect(UInt8(i), seq: nextSeq()))
        }
    }

    /// Ask the bar for its info; if it stays silent, reopen it and re-apply state.
    /// (After sleep the bar can reset to its rainbow without the USB handle noticing.)
    public override func healthCheck() {
        queue.async { [self] in
            let asked = Date()
            send(RobobloqProtocol.readInfo(seq: nextSeq()))
            queue.asyncAfter(deadline: .now() + 0.6) { [self] in
                guard lastReply < asked else { return }
                // One late answer shouldn't cost a reconnect (and a visible re-apply).
                missedChecks += 1
                guard missedChecks >= 3 else { return }
                missedChecks = 0
                log.notice("robobloq health check: 3 missed replies, reopening")
                if opened { IOHIDDeviceClose(hid, IOOptionBits(kIOHIDOptionsTypeNone)) }
                opened = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
                isReachable = false
                setReachable(opened)
            }
        }
    }
}

/// Watches USB for ROBOBLOQ bars; handles hot-plug (including monitor KVM switches).
public final class RobobloqProvider: DeviceProvider {
    public let family = "ROBOBLOQ USB"
    private let hidQueue = DispatchQueue(label: "glowdeck.hid")
    private var manager: IOHIDManager?
    private var lights: [IOHIDDevice: RobobloqLight] = [:]
    private var found: ((LightDevice) -> Void)?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    public init() {}

    public func start(_ context: ProviderContext) {
        self.found = context.found
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: RobobloqProtocol.vendorID,
            kIOHIDProductIDKey: RobobloqProtocol.productID,
            kIOHIDPrimaryUsagePageKey: RobobloqProtocol.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            Unmanaged<RobobloqProvider>.fromOpaque(ctx!).takeUnretainedValue().attached(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            Unmanaged<RobobloqProvider>.fromOpaque(ctx!).takeUnretainedValue().detached(device)
        }, ctx)
        IOHIDManagerRegisterInputReportCallback(m, { ctx, _, sender, _, _, report, length in
            guard let sender else { return }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<RobobloqProvider>.fromOpaque(ctx!).takeUnretainedValue().lights[device]?.received(bytes)
        }, ctx)

        // Order matters: callbacks and open() must happen before the queue is activated, or IOKit traps.
        // Opening through the manager is what makes it deliver the bar's replies (input reports).
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDispatchQueue(m, hidQueue)
        IOHIDManagerActivate(m)
        manager = m
    }

    public func scan() {}  // hot-plug callbacks keep the list current

    private func attached(_ device: IOHIDDevice) {
        if let existing = lights[device] { existing.open(); return }
        let loc = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int) ?? 0
        let light = RobobloqLight(hid: device, location: loc)
        lights[device] = light
        found?(light)
        light.open()
    }

    private func detached(_ device: IOHIDDevice) {
        guard let light = lights.removeValue(forKey: device) else { return }
        light.close()
        light.setReachable(false)
    }
}
