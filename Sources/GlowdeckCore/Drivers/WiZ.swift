import Foundation

/// WiZ (Philips WiZ, many "Works with WiZ" bulbs and strips). JSON over UDP 38899, no pairing.
public final class WiZLight: LightDevice, @unchecked Sendable {
    private let host: String
    private weak var socket: UDPSocket?
    var lastSeen = Date()

    static let scenes: [(Int, String)] = [
        (1, "Ocean"), (2, "Romance"), (3, "Sunset"), (4, "Party"), (5, "Fireplace"), (6, "Cozy"),
        (7, "Forest"), (8, "Pastel colors"), (9, "Wake up"), (10, "Bedtime"), (14, "Night light"),
        (15, "Focus"), (16, "Relax"), (18, "TV time"), (20, "Spring"), (21, "Summer"), (22, "Fall"),
        (23, "Deep dive"), (24, "Jungle"), (25, "Mojito"), (26, "Club"), (27, "Christmas"),
        (28, "Halloween"), (29, "Candlelight"), (31, "Pulse"), (32, "Steampunk"),
    ]

    init(mac: String, host: String, module: String, socket: UDPSocket) {
        self.host = host
        self.socket = socket
        let rgb = module.uppercased().contains("RGB") || module.isEmpty
        super.init(id: "wiz:\(mac)", brand: "WiZ", name: "WiZ \(mac.suffix(4).uppercased())", model: module,
                   kind: module.uppercased().contains("STRIP") || module.contains("LS") ? .strip : .bulb,
                   capabilities: rgb ? [.color, .brightness, .nativeEffects] : [.temperature, .brightness, .nativeEffects],
                   maxFPS: 8, address: host)
        nativeEffects = Self.scenes.map { NativeEffect(id: "wiz.\($0.0)", name: $0.1) }
    }

    private func pilot(_ params: [String: Any]) {
        let msg: [String: Any] = ["method": "setPilot", "params": params]
        if let d = try? JSONSerialization.data(withJSONObject: msg) { socket?.send(d, to: host, port: 38899) }
    }

    public override func setPower(_ on: Bool) { queue.async { [self] in pilot(["state": on]) } }
    public override func setBrightness(_ v: Double) {
        queue.async { [self] in pilot(["dimming": max(10, min(100, Int(v * 100)))]) }
    }
    public override func setColor(_ c: RGB) {
        queue.async { [self] in
            if capabilities.contains(.color) { pilot(["state": true, "r": c.r, "g": c.g, "b": c.b]) }
            else { pilot(["state": true, "temp": Int(c.approximateKelvin)]) }
        }
    }
    public override func startNativeEffect(_ e: NativeEffect, speed: Double, color: RGB) {
        guard let id = Int(e.id.dropFirst(4)) else { return }
        queue.async { [self] in pilot(["state": true, "sceneId": id, "speed": 20 + Int(speed * 180)]) }
    }
    public override func healthCheck() {
        queue.async { [self] in
            if let d = try? JSONSerialization.data(withJSONObject: ["method": "getPilot", "params": [:]]) {
                socket?.send(d, to: host, port: 38899)
            }
            setReachable(Date().timeIntervalSince(lastSeen) < 45)
        }
    }
}

public final class WiZProvider: DeviceProvider {
    public let family = "WiZ"
    private let q = DispatchQueue(label: "glowdeck.wiz")
    private var socket: UDPSocket?
    private var lights: [String: WiZLight] = [:]
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        socket = UDPSocket(queue: q)
        socket?.onReceive = { [weak self] data, ip in self?.handle(data, from: ip) }
        scan()
    }

    public func scan() {
        guard let d = try? JSONSerialization.data(withJSONObject: ["method": "getSystemConfig", "params": [:]]) else { return }
        for b in UDPSocket.broadcastAddresses() { socket?.send(d, to: b, port: 38899) }
    }

    private func handle(_ data: Data, from ip: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj.dict("result"), let socket else { return }
        guard let mac = result.str("mac") else { return }
        if let l = lights[mac] { l.lastSeen = Date(); return }
        guard obj.str("method") == "getSystemConfig" else { return }
        let l = WiZLight(mac: mac, host: ip, module: result.str("moduleName") ?? "", socket: socket)
        lights[mac] = l
        ctx?.found(l)
    }
}
