import Foundation

/// WLED (ESP8266/ESP32 DIY LED controllers). JSON API for state, UDP realtime (DRGB/DNRGB)
/// for per-LED frames. Docs: kno.wled.ge/interfaces/json-api, kno.wled.ge/interfaces/udp-realtime
public final class WLEDLight: LightDevice, @unchecked Sendable {
    private let host: String
    private let udp: UDPSocket?
    private let writes = HTTP.Coalescer()

    init(mac: String, host: String, name: String, ledCount: Int, version: String) {
        self.host = host
        self.udp = UDPSocket(queue: DispatchQueue(label: "glowdeck.wled.\(mac)"))
        super.init(id: "wled:\(mac)", brand: "WLED", name: name, model: "WLED \(version) · \(ledCount) LEDs",
                   kind: .strip, capabilities: [.color, .brightness, .perLED, .nativeEffects],
                   ledCount: max(1, ledCount), maxFPS: 30, address: host)
        HTTP.request("GET", "http://\(host)/json/effects") { [weak self] obj, _ in
            guard let self, let names = obj as? [String] else { return }
            self.nativeEffects = names.enumerated().filter { $0.element != "RSVD" && $0.element != "-" }
                .map { NativeEffect(id: "wled.\($0.offset)", name: $0.element) }
            self.changed()
        }
    }

    private func post(_ state: [String: Any]) {
        writes.submit { [host] done in
            HTTP.request("POST", "http://\(host)/json/state", json: state) { [weak self] _, code in
                self?.setReachable(code == 200)
                done()
            }
        }
    }

    public override func setPower(_ on: Bool) { post(["on": on]) }

    public override func setBrightness(_ value: Double) {
        post(["on": true, "bri": max(1, min(255, Int(value * 255)))])
    }

    public override func setColor(_ c: RGB) {
        post(["on": true, "seg": [["fx": 0, "col": [[c.r, c.g, c.b]]]]])
    }

    public override func setFrame(_ colors: [RGB]) {
        // DRGB (protocol 2) handles up to 490 LEDs; DNRGB (4) carries a start index for longer strips.
        let timeout: UInt8 = 2  // seconds before WLED resumes its own state
        if colors.count <= 490 {
            var d: [UInt8] = [2, timeout]
            for c in colors { d += [c.r, c.g, c.b] }
            udp?.send(Data(d), to: host, port: 21324)
        } else {
            for start in stride(from: 0, to: colors.count, by: 489) {
                var d: [UInt8] = [4, timeout, UInt8(start >> 8), UInt8(start & 0xFF)]
                for c in colors[start..<min(start + 489, colors.count)] { d += [c.r, c.g, c.b] }
                udp?.send(Data(d), to: host, port: 21324)
            }
        }
    }

    public override func startNativeEffect(_ effect: NativeEffect, speed: Double, color: RGB) {
        guard let fx = Int(effect.id.dropFirst(5)) else { return }
        post(["on": true, "seg": [["fx": fx, "sx": Int(speed * 255), "col": [[color.r, color.g, color.b]]]]])
    }

    public override func healthCheck() {
        HTTP.request("GET", "http://\(host)/json/info") { [weak self] _, code in self?.setReachable(code == 200) }
    }
}

public final class WLEDProvider: DeviceProvider {
    public let family = "WLED"
    private let bonjour = Bonjour()
    private var known = Set<String>()
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        bonjour.browse("_wled._tcp") { [weak self] svc in self?.probe(svc.host) }
    }

    public func scan() {}

    private func probe(_ host: String) {
        HTTP.request("GET", "http://\(host)/json/info") { [weak self] obj, _ in
            guard let self, let info = obj as? [String: Any], let mac = info.str("mac"), !self.known.contains(mac) else { return }
            self.known.insert(mac)
            let leds = info.dict("leds")?.int("count") ?? 30
            self.ctx?.found(WLEDLight(mac: mac, host: host, name: info.str("name") ?? "WLED",
                                      ledCount: leds, version: info.str("ver") ?? ""))
        }
    }
}
