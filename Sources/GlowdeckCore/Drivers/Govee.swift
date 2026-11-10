import Foundation

/// Govee LAN API (UDP). The user must enable "LAN Control" for each device in the Govee Home app.
/// Discovery: multicast 239.255.255.250:4001 → replies on 4002. Commands go to <ip>:4003.
public final class GoveeLight: LightDevice, @unchecked Sendable {
    private let host: String
    private weak var socket: UDPSocket?

    init(deviceID: String, host: String, sku: String, socket: UDPSocket) {
        self.host = host
        self.socket = socket
        super.init(id: "govee:\(deviceID)", brand: "Govee", name: "Govee \(sku)", model: sku,
                   kind: sku.hasPrefix("H61") ? .strip : .bulb, capabilities: [.color, .brightness],
                   maxFPS: 10, address: host)
    }

    private func cmd(_ cmd: String, _ data: [String: Any]) {
        let msg: [String: Any] = ["msg": ["cmd": cmd, "data": data]]
        if let d = try? JSONSerialization.data(withJSONObject: msg) { socket?.send(d, to: host, port: 4003) }
    }

    public override func setPower(_ on: Bool) { queue.async { [self] in cmd("turn", ["value": on ? 1 : 0]) } }
    public override func setBrightness(_ v: Double) {
        queue.async { [self] in cmd("brightness", ["value": max(1, min(100, Int(v * 100)))]) }
    }
    public override func setColor(_ c: RGB) {
        queue.async { [self] in
            cmd("colorwc", ["color": ["r": c.r, "g": c.g, "b": c.b], "colorTemInKelvin": 0])
        }
    }
}

public final class GoveeProvider: DeviceProvider {
    public let family = "Govee"
    private let q = DispatchQueue(label: "glowdeck.govee")
    private var listener: UDPSocket?
    private var sender: UDPSocket?
    private var known = Set<String>()
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        listener = UDPSocket(port: 4002, queue: q)
        listener?.joinMulticast("239.255.255.250")
        listener?.onReceive = { [weak self] data, ip in self?.handle(data, from: ip) }
        sender = UDPSocket(queue: q)
        scan()
    }

    public func scan() {
        let msg = #"{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}"#
        sender?.send(Data(msg.utf8), to: "239.255.255.250", port: 4001)
    }

    private func handle(_ data: Data, from ip: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = obj.dict("msg"), msg.str("cmd") == "scan", let d = msg.dict("data"),
              let id = d.str("device"), !known.contains(id), let sender else { return }
        known.insert(id)
        ctx?.found(GoveeLight(deviceID: id, host: d.str("ip") ?? ip, sku: d.str("sku") ?? "light", socket: sender))
    }
}
