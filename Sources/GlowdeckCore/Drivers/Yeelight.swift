import Foundation
import Network

/// Yeelight (Xiaomi) bulbs and strips. Enable "LAN Control" in the Yeelight app first.
/// Discovery: SSDP-like M-SEARCH on 239.255.255.250:1982. Control: JSON lines over TCP 55443.
/// The bulbs allow ~60 commands per minute, so effects stream at 1 fps with smooth transitions.
public final class YeelightLight: LightDevice, @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private var conn: NWConnection?
    private var msgID = 0

    init(id: String, host: String, port: UInt16, name: String, model: String, color: Bool) {
        self.host = host
        self.port = port
        super.init(id: "yeelight:\(id)", brand: "Yeelight", name: name.isEmpty ? "Yeelight \(model)" : name,
                   model: model, kind: model.contains("strip") ? .strip : .bulb,
                   capabilities: color ? [.color, .brightness] : [.temperature, .brightness],
                   maxFPS: 1, address: host)
    }

    private func connection() -> NWConnection {
        if let c = conn, c.state != .cancelled { return c }
        let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.setReachable(true)
            case .failed, .cancelled: self?.setReachable(false); self?.conn = nil
            default: break
            }
        }
        c.start(queue: queue)
        conn = c
        return c
    }

    private func call(_ method: String, _ params: [Any]) {
        queue.async { [self] in
            msgID += 1
            let msg: [String: Any] = ["id": msgID, "method": method, "params": params]
            guard var d = try? JSONSerialization.data(withJSONObject: msg) else { return }
            d.append(contentsOf: [0x0D, 0x0A])
            connection().send(content: d, completion: .contentProcessed { _ in })
        }
    }

    public override func setPower(_ on: Bool) { call("set_power", [on ? "on" : "off", "smooth", 300]) }
    public override func setBrightness(_ v: Double) { call("set_bright", [max(1, min(100, Int(v * 100))), "smooth", 300]) }
    public override func setColor(_ c: RGB) {
        if capabilities.contains(.color) {
            call("set_rgb", [Int(c.r) << 16 | Int(c.g) << 8 | Int(c.b), "smooth", 800])
        } else {
            call("set_ct_abx", [Int(max(1700, min(6500, c.approximateKelvin))), "smooth", 800])
        }
    }
    public override func healthCheck() { call("get_prop", ["power"]) }
}

public final class YeelightProvider: DeviceProvider {
    public let family = "Yeelight"
    private let q = DispatchQueue(label: "glowdeck.yeelight")
    private var socket: UDPSocket?
    private var known = Set<String>()
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        socket = UDPSocket(queue: q)
        socket?.onReceive = { [weak self] data, _ in self?.handle(String(decoding: data, as: UTF8.self)) }
        scan()
    }

    public func scan() {
        let m = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1982\r\nMAN: \"ssdp:discover\"\r\nST: wifi_bulb\r\n"
        socket?.send(Data(m.utf8), to: "239.255.255.250", port: 1982)
    }

    /// Parses the HTTP-style discovery reply into a light.
    func handle(_ text: String) {
        var h: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n") {
            guard let i = line.firstIndex(of: ":") else { continue }
            h[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        guard let id = h["id"], !known.contains(id), let loc = h["location"],
              let url = URL(string: loc.replacingOccurrences(of: "yeelight://", with: "http://")),
              let host = url.host else { return }
        known.insert(id)
        let support = h["support"] ?? ""
        ctx?.found(YeelightLight(id: id, host: host, port: UInt16(url.port ?? 55443), name: h["name"] ?? "",
                                 model: h["model"] ?? "bulb", color: support.contains("set_rgb")))
    }
}
