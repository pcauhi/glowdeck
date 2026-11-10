# Contributing to Glowdeck

Thanks for helping! The most valuable contributions right now are:

1. **Hardware reports.** If you own a light marked 🧪 in the README, tell us in an issue whether discovery, colour, brightness, power and effects work.
2. **New drivers** for light families with a local (non-cloud) API.
3. **Fixes** with a short description of the light/firmware you tested on.

## Adding a driver

Create `Sources/GlowdeckCore/Drivers/<Brand>.swift` with two classes.

```swift
public final class AcmeLight: LightDevice, @unchecked Sendable {
    init(id: String, host: String) {
        super.init(id: "acme:\(id)",            // stable across launches
                   brand: "Acme", name: "Acme bulb", kind: .bulb,
                   capabilities: [.color, .brightness],
                   maxFPS: 10,                   // how fast it can take colour updates
                   address: host)
    }
    public override func setPower(_ on: Bool) { … }
    public override func setBrightness(_ v: Double) { … }   // 0...1
    public override func setColor(_ c: RGB) { … }
    // Optional: setFrame(_:) for per-LED strips (add .perLED), startNativeEffect(_:speed:color:)
    // and healthCheck() to update reachability via setReachable(_:).
}

public final class AcmeProvider: DeviceProvider {
    public let family = "Acme"
    public func start(_ ctx: ProviderContext) { /* discover, then ctx.found(AcmeLight(...)) */ }
    public func scan() { /* re-broadcast discovery */ }
}
```

Then add the provider to the list in `LightManager.init`.

Rules of thumb:

- **Never block the caller.** Do I/O on `queue` (every device has one), or use `HTTP.request` / `UDPSocket`.
- **Coalesce writes** for slow devices with `HTTP.Coalescer` so slider drags don't pile up.
- **Pairing** (buttons, tokens): call `ctx.needsPairing(Pairing(...))`, store secrets with `Credentials.set`, never in `state.json`.
- **Local only.** No cloud APIs or accounts.
- Add packet-level tests in `Tests/GlowdeckCoreTests` when the protocol is binary.

## Building

```bash
swift build && swift test
scripts/bundle.sh            # build/Glowdeck.app
build/Glowdeck.app/Contents/MacOS/Glowdeck --preview-menu --preview-dashboard   # open the UI as normal windows
```

## Style

Swift 6 toolchain, Swift 5 language mode. Keep files small and dependency-free (Apple frameworks only).
