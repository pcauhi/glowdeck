import Foundation

/// LIFX LAN protocol (binary, UDP 56700). No pairing needed.
/// Docs: lan.developer.lifx.com
public enum LIFXProtocol {
    public static let port: UInt16 = 56700
    public enum Message: UInt16 {
        case getService = 2, stateService = 3, get = 101, setColor = 102, state = 107, setLightPower = 117
    }

    /// 36-byte header + payload. `target` = 6-byte MAC (nil → broadcast with tagged=1).
    public static func packet(_ type: Message, target: [UInt8]? = nil, source: UInt32 = 0x676C6F77,
                              sequence: UInt8 = 0, payload: [UInt8] = []) -> [UInt8] {
        var p = [UInt8]()
        func u16(_ v: UInt16) { p += [UInt8(v & 0xFF), UInt8(v >> 8)] }
        func u32(_ v: UInt32) { p += (0..<4).map { UInt8((v >> ($0 * 8)) & 0xFF) } }
        u16(UInt16(36 + payload.count))
        u16(1024 | (1 << 12) | (target == nil ? 1 << 13 : 0))  // protocol, addressable, tagged
        u32(source)
        p += (target ?? [0, 0, 0, 0, 0, 0]) + [0, 0]  // target (8)
        p += [UInt8](repeating: 0, count: 6)           // reserved
        p.append(type == .get || type == .getService ? 1 : 0)  // res_required
        p.append(sequence)
        p += [UInt8](repeating: 0, count: 8)           // reserved
        u16(type.rawValue)
        u16(0)
        return p + payload
    }

    /// SetColor payload: reserved u8, HSBK (u16 ×4), duration u32 ms.
    public static func setColor(_ c: RGB, brightness: Double, durationMs: UInt32) -> [UInt8] {
        let hsv = c.hsv
        let vals: [UInt16] = [UInt16(hsv.h * 65535), UInt16(hsv.s * 65535),
                              UInt16(max(0, min(1, hsv.v * brightness)) * 65535), 3500]
        var p: [UInt8] = [0]
        for v in vals { p += [UInt8(v & 0xFF), UInt8(v >> 8)] }
        p += (0..<4).map { UInt8((durationMs >> ($0 * 8)) & 0xFF) }
        return p
    }
}

public final class LIFXLight: LightDevice, @unchecked Sendable {
    private let mac: [UInt8]
    private let host: String
    private weak var socket: UDPSocket?
    private var color = RGB.white
    private var bri = 1.0
    private var seq: UInt8 = 0
    var lastSeen = Date()

    init(mac: [UInt8], host: String, socket: UDPSocket) {
        self.mac = mac
        self.host = host
        self.socket = socket
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        super.init(id: "lifx:\(hex)", brand: "LIFX", name: "LIFX \(hex.suffix(4))", model: "LIFX",
                   kind: .bulb, capabilities: [.color, .brightness], maxFPS: 15, address: host)
    }

    private func send(_ t: LIFXProtocol.Message, _ payload: [UInt8] = []) {
        seq &+= 1
        socket?.send(Data(LIFXProtocol.packet(t, target: mac, sequence: seq, payload: payload)), to: host, port: LIFXProtocol.port)
    }

    func gotLabel(_ label: String) {
        guard !label.isEmpty, label != name else { return }
        name = label
        changed()
    }

    public override func setPower(_ on: Bool) {
        queue.async { [self] in send(.setLightPower, [on ? 0xFF : 0, on ? 0xFF : 0, 200, 0, 0, 0]) }
    }
    public override func setBrightness(_ v: Double) {
        queue.async { [self] in bri = v; send(.setColor, LIFXProtocol.setColor(color, brightness: bri, durationMs: 150)) }
    }
    public override func setColor(_ c: RGB) {
        queue.async { [self] in color = c; send(.setColor, LIFXProtocol.setColor(c, brightness: bri, durationMs: 100)) }
    }
    public override func healthCheck() {
        queue.async { [self] in
            send(.get)
            setReachable(Date().timeIntervalSince(lastSeen) < 45)
        }
    }
}

public final class LIFXProvider: DeviceProvider {
    public let family = "LIFX"
    private let q = DispatchQueue(label: "glowdeck.lifx")
    private var socket: UDPSocket?
    private var lights: [String: LIFXLight] = [:]
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        socket = UDPSocket(queue: q)
        socket?.onReceive = { [weak self] data, ip in self?.handle(Array(data), from: ip) }
        scan()
    }

    public func scan() {
        let p = Data(LIFXProtocol.packet(.getService))
        for b in UDPSocket.broadcastAddresses() { socket?.send(p, to: b, port: LIFXProtocol.port) }
    }

    private func handle(_ d: [UInt8], from ip: String) {
        guard d.count >= 36, let socket else { return }
        let type = UInt16(d[32]) | UInt16(d[33]) << 8
        let mac = Array(d[8..<14])
        let key = mac.map { String(format: "%02x", $0) }.joined()
        if let l = lights[key] { l.lastSeen = Date() }
        switch type {
        case LIFXProtocol.Message.stateService.rawValue:
            if lights[key] == nil {
                let l = LIFXLight(mac: mac, host: ip, socket: socket)
                lights[key] = l
                ctx?.found(l)
                socket.send(Data(LIFXProtocol.packet(.get, target: mac)), to: ip, port: LIFXProtocol.port)
            }
        case LIFXProtocol.Message.state.rawValue where d.count >= 36 + 44:
            let labelBytes = d[(36 + 12)..<(36 + 44)].prefix { $0 != 0 }
            lights[key]?.gotLabel(String(decoding: labelBytes, as: UTF8.self))
        default: break
        }
    }
}
