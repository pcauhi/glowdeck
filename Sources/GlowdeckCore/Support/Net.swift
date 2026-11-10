import Foundation
import Network

/// Minimal BSD UDP socket with broadcast/multicast send and an async receive handler.
public final class UDPSocket: @unchecked Sendable {
    private let fd: Int32
    private let source: DispatchSourceRead
    public var onReceive: ((Data, String) -> Void)?

    /// - Parameter port: local port to bind (0 = any).
    public init?(port: UInt16 = 0, queue: DispatchQueue) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard ok else { Darwin.close(fd); return nil }

        self.fd = fd
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 8192)
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, buf.count, 0, $0, &len)
                }
            }
            guard n > 0 else { return }
            let ip = String(cString: inet_ntoa(from.sin_addr))
            self?.onReceive?(Data(buf[0..<n]), ip)
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    deinit { source.cancel() }

    public func joinMulticast(_ group: String) {
        var mreq = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr(group)), imr_interface: in_addr(s_addr: INADDR_ANY))
        setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))
    }

    @discardableResult
    public func send(_ data: Data, to host: String, port: UInt16) -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }
        let n = data.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, raw.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return n == data.count
    }

    /// Directed broadcast addresses for every active IPv4 interface (e.g. 192.168.0.255).
    /// macOS refuses 255.255.255.255 on multi-homed machines, so we use these instead.
    public static func broadcastAddresses() -> [String] {
        var out: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return ["255.255.255.255"] }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            let flags = Int32(i.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_INET),
                  let b = i.ifa_dstaddr else { continue }
            let ip = b.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { String(cString: inet_ntoa($0.pointee.sin_addr)) }
            if !out.contains(ip) { out.append(ip) }
        }
        return out.isEmpty ? ["255.255.255.255"] : out
    }
}

/// Tiny JSON-over-HTTP helper for LAN APIs (Hue v1, Nanoleaf, Elgato, WLED, Home Assistant).
public enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4
        c.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: c)
    }()

    public static func request(_ method: String, _ url: String, json: Any? = nil, headers: [String: String] = [:],
                               completion: ((Any?, Int) -> Void)? = nil) {
        guard let u = URL(string: url) else { completion?(nil, 0); return }
        var r = URLRequest(url: u)
        r.httpMethod = method
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        if let json {
            r.httpBody = try? JSONSerialization.data(withJSONObject: json)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        session.dataTask(with: r) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
            completion?(obj, code)
        }.resume()
    }

    /// Fire-and-forget write where only the latest value matters. Drops writes while one is in flight
    /// and sends the newest one when it completes (keeps slow bridges from queueing up).
    public final class Coalescer: @unchecked Sendable {
        private let lock = NSLock()
        private var inFlight = false
        private var pending: (() -> Void)?
        public init() {}

        public func submit(_ send: @escaping (@escaping () -> Void) -> Void) {
            lock.lock()
            if inFlight {
                pending = { [weak self] in self?.submit(send) }
                lock.unlock()
                return
            }
            inFlight = true
            lock.unlock()
            send { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.inFlight = false
                let next = self.pending
                self.pending = nil
                self.lock.unlock()
                next?()
            }
        }
    }
}

/// Bonjour browser that resolves services to (name, host, port, txt).
public final class Bonjour: @unchecked Sendable {
    public struct Service { public var name: String; public var host: String; public var port: UInt16; public var txt: [String: String] }

    private var browsers: [NWBrowser] = []
    private let queue = DispatchQueue(label: "glowdeck.bonjour")

    public init() {}

    public func browse(_ type: String, found: @escaping (Service) -> Void) {
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results { self?.resolve(r, found: found) }
        }
        b.start(queue: queue)
        browsers.append(b)
    }

    private func resolve(_ result: NWBrowser.Result, found: @escaping (Service) -> Void) {
        guard case let .service(name, _, _, _) = result.endpoint else { return }
        var txt: [String: String] = [:]
        if case let .bonjour(record) = result.metadata { txt = record.dictionary }
        let params = NWParameters.tcp
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let conn = NWConnection(to: result.endpoint, using: params)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case let .hostPort(host, port) = conn.currentPath?.remoteEndpoint ?? conn.endpoint {
                    var h = "\(host)"
                    if let pct = h.firstIndex(of: "%") { h = String(h[..<pct]) }
                    found(Service(name: name, host: h, port: port.rawValue, txt: txt))
                }
                conn.cancel()
            case .failed, .cancelled:
                conn.cancel()
            default: break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { conn.cancel() }
    }
}

extension Dictionary where Key == String {
    func str(_ k: String) -> String? { self[k] as? String }
    func int(_ k: String) -> Int? { (self[k] as? NSNumber)?.intValue }
    func dict(_ k: String) -> [String: Any]? { self[k] as? [String: Any] }
}
