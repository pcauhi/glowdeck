import Foundation

public struct Capabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Full RGB colour.
    public static let color = Capabilities(rawValue: 1 << 0)
    /// Dimmable.
    public static let brightness = Capabilities(rawValue: 1 << 1)
    /// White-only with adjustable temperature (colours get mapped to warm/cool).
    public static let temperature = Capabilities(rawValue: 1 << 2)
    /// Individually addressable LEDs that can be streamed frame by frame.
    public static let perLED = Capabilities(rawValue: 1 << 3)
    /// Has effects built into its firmware.
    public static let nativeEffects = Capabilities(rawValue: 1 << 4)
}

public struct NativeEffect: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum DeviceKind: String, Codable, Sendable {
    case strip, bulb, panel, keyLight, bridge

    public var symbol: String {
        switch self {
        case .strip: return "light.strip.2.fill"
        case .bulb: return "lightbulb.fill"
        case .panel: return "hexagon.fill"
        case .keyLight: return "light.panel.fill"
        case .bridge: return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// One controllable light. Drivers subclass this and override the `set…` methods.
///
/// All `set…` calls are fire-and-forget and must never block the caller: drivers
/// do their I/O on `queue`. Drivers call `changed()` when name/reachability changes.
open class LightDevice: Identifiable, @unchecked Sendable {
    /// Stable across launches, e.g. `robobloq:usb:0x02121000`, `lifx:d073d5aabbcc`.
    public let id: String
    public let brand: String
    public internal(set) var name: String
    public internal(set) var model: String
    public internal(set) var kind: DeviceKind
    public internal(set) var capabilities: Capabilities
    public internal(set) var ledCount: Int
    public internal(set) var nativeEffects: [NativeEffect] = []
    /// Highest useful frame rate for streamed effects. Bulbs on a hub are slow.
    public internal(set) var maxFPS: Double
    public internal(set) var address: String
    public internal(set) var isReachable: Bool = true

    /// Set by the manager; called on any queue.
    public var onChange: (() -> Void)?
    /// Set by the manager; the device came back (re-plugged, woke up) and needs its state re-applied.
    public var onNeedsReapply: (() -> Void)?

    public let queue: DispatchQueue

    public init(id: String, brand: String, name: String, model: String = "", kind: DeviceKind,
                capabilities: Capabilities, ledCount: Int = 1, maxFPS: Double = 10, address: String = "") {
        self.id = id
        self.brand = brand
        self.name = name
        self.model = model
        self.kind = kind
        self.capabilities = capabilities
        self.ledCount = ledCount
        self.maxFPS = maxFPS
        self.address = address
        self.queue = DispatchQueue(label: "glowdeck.device.\(id)")
    }

    open func setPower(_ on: Bool) {}
    /// 0...1
    open func setBrightness(_ value: Double) {}
    open func setColor(_ color: RGB) {}
    /// One colour per LED. The default sends the average colour.
    open func setFrame(_ colors: [RGB]) { setColor(.average(colors)) }
    /// speed 0...1
    open func startNativeEffect(_ effect: NativeEffect, speed: Double, color: RGB) {}
    /// Called periodically and after the Mac wakes. Re-check the connection.
    open func healthCheck() {}
    /// Release any OS resources (USB handles, sockets) before the Mac sleeps.
    open func suspend() {}

    public func changed() { onChange?() }

    func setReachable(_ r: Bool) {
        guard r != isReachable else { return }
        isReachable = r
        changed()
        if r { onNeedsReapply?() }
    }
}

/// Finds devices of one family (a USB vendor, a LAN protocol, a hub).
public protocol DeviceProvider: AnyObject {
    var family: String { get }
    /// Called once at launch.
    func start(_ context: ProviderContext)
    /// User pressed "Scan" or the network changed.
    func scan()
}
