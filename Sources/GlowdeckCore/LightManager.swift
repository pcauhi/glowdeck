import AppKit
import Combine
import Foundation

/// Which lights a control applies to.
public enum Target: Codable, Hashable, Sendable {
    case all
    case room(UUID)
    case device(String)
}

/// Owns every device, its desired state, the effect render loop, sleep/wake handling and persistence.
@MainActor
public final class LightManager: ObservableObject {
    @Published public private(set) var devices: [LightDevice] = []
    @Published public private(set) var pairings: [Pairing] = []
    @Published public private(set) var states: [String: LightState] = [:]
    @Published public var rooms: [Room] = [] { didSet { save() } }
    @Published public var target: Target = .all { didSet { save() } }
    @Published public var followDisplaySleep = true { didSet { save(); reapplyAll() } }
    /// Master switch from the menu bar.
    @Published public var masterPower = true { didSet { save(); reapplyAll() } }
    /// Live colours per device for previews (updated ~10×/s).
    @Published public private(set) var preview: [String: [RGB]] = [:]
    @Published public private(set) var displaysAsleep = false
    @Published public private(set) var customNames: [String: String] = [:]

    /// State used for lights we haven't seen before and for an empty target.
    public private(set) var lastUsed = LightState()

    private let providers: [DeviceProvider]
    private let renderQueue = DispatchQueue(label: "glowdeck.render", qos: .userInteractive)
    private var renderTimer: DispatchSourceTimer?
    private var healthTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var saveWork: DispatchWorkItem?

    // Render-thread copies (only touched on renderQueue).
    private nonisolated(unsafe) var rDevices: [LightDevice] = []
    private nonisolated(unsafe) var rStates: [String: LightState] = [:]
    private nonisolated(unsafe) var rActive = true
    private nonisolated(unsafe) var rPhase: [String: Double] = [:]
    private nonisolated(unsafe) var rLastSent: [String: TimeInterval] = [:]
    private nonisolated(unsafe) var rLastPreview: TimeInterval = 0
    private nonisolated(unsafe) var rLastTick = ProcessInfo.processInfo.systemUptime

    public static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glowdeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    public init(providers: [DeviceProvider]? = nil) {
        self.providers = providers ?? [
            RobobloqProvider(), WLEDProvider(), HueProvider(), LIFXProvider(), WiZProvider(),
            GoveeProvider(), YeelightProvider(), ElgatoProvider(), NanoleafProvider(), HomeAssistantProvider(),
        ]
        load()
    }

    // MARK: - Lifecycle

    public func start() {
        let ctx = ProviderContext(
            found: { [weak self] d in Task { @MainActor in self?.add(d) } },
            needsPairing: { [weak self] p in Task { @MainActor in self?.addPairing(p) } },
            paired: { [weak self] id in Task { @MainActor in self?.pairings.removeAll { $0.id == id } } })
        for p in providers { p.start(ctx) }

        let t = DispatchSource.makeTimerSource(queue: renderQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(4))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        renderTimer = t

        healthTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.devices.forEach { $0.healthCheck() } }
        }
        // Re-scan the network now and then so lights that join later show up.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        observeSleep()
    }

    public func scan() {
        providers.forEach { $0.scan() }
    }

    private func observeSleep() {
        let nc = NSWorkspace.shared.notificationCenter
        let sleep: (Notification) -> Void = { [weak self] _ in Task { @MainActor in self?.setDisplaysAsleep(true) } }
        let wake: (Notification) -> Void = { [weak self] _ in Task { @MainActor in self?.setDisplaysAsleep(false) } }
        observers += [
            nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: sleep),
            nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: sleep),
            nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: wake),
            nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wake),
        ]
    }

    private func setDisplaysAsleep(_ asleep: Bool) {
        guard asleep != displaysAsleep else { return }
        displaysAsleep = asleep
        if asleep {
            reapplyAll()
        } else {
            // USB hubs in monitors and Wi-Fi bulbs take a moment to come back; check, then re-apply a few times.
            devices.forEach { $0.healthCheck() }
            for delay in [0.5, 3.0, 10.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.reapplyAll() }
            }
            scan()
        }
    }

    // MARK: - Devices

    private func add(_ d: LightDevice) {
        d.onChange = { [weak self] in Task { @MainActor in self?.objectWillChange.send() } }
        d.onNeedsReapply = { [weak self, weak d] in
            Task { @MainActor in if let d { self?.apply(to: d) } }
        }
        if let i = devices.firstIndex(where: { $0.id == d.id }) {
            devices[i] = d  // same light, new handle (USB re-plug / KVM switch)
        } else {
            devices.append(d)
        }
        if states[d.id] == nil { states[d.id] = lastUsed }
        syncRender()
        apply(to: d)
    }

    private func addPairing(_ p: Pairing) {
        guard !pairings.contains(where: { $0.id == p.id }) else { return }
        pairings.append(p)
    }

    public func displayName(_ d: LightDevice) -> String { customNames[d.id] ?? d.name }

    public func rename(_ d: LightDevice, to name: String) {
        customNames[d.id] = name.isEmpty ? nil : name
        save()
    }

    public func devices(in target: Target) -> [LightDevice] {
        switch target {
        case .all: return devices
        case .device(let id): return devices.filter { $0.id == id }
        case .room(let rid):
            let ids = rooms.first { $0.id == rid }?.deviceIDs ?? []
            return devices.filter { ids.contains($0.id) }
        }
    }

    public func room(of d: LightDevice) -> Room? { rooms.first { $0.deviceIDs.contains(d.id) } }

    public func move(_ d: LightDevice, to room: Room?) {
        for i in rooms.indices { rooms[i].deviceIDs.removeAll { $0 == d.id } }
        if let room, let i = rooms.firstIndex(where: { $0.id == room.id }) { rooms[i].deviceIDs.append(d.id) }
    }

    // MARK: - State

    /// The state shown in the controls for a target (its first light, or the last used one).
    public func state(for target: Target) -> LightState {
        devices(in: target).first.flatMap { states[$0.id] } ?? lastUsed
    }

    public func state(of d: LightDevice) -> LightState { states[d.id] ?? lastUsed }

    /// Change the state of every light in `target` and push it to the hardware.
    public func update(_ target: Target? = nil, _ change: (inout LightState) -> Void) {
        let list = devices(in: target ?? self.target)
        var template = state(for: target ?? self.target)
        change(&template)
        lastUsed = template
        for d in list {
            var s = states[d.id] ?? lastUsed
            let before = s
            change(&s)
            states[d.id] = s
            if s != before { apply(to: d, previous: before) }
        }
        if !masterPower, template.power { masterPower = true }
        syncRender()
        save()
    }

    public func apply(theme: Theme, to target: Target? = nil) {
        update(target) { s in
            s = theme.state
            s.power = true
        }
    }

    public func reapplyAll() {
        syncRender()
        devices.forEach { apply(to: $0) }
    }

    private var effectivelyOn: Bool { masterPower && !(followDisplaySleep && displaysAsleep) }

    /// Push a light's state to the hardware. `previous` lets us skip unchanged parts (no flashing on slider drags).
    private func apply(to d: LightDevice, previous: LightState? = nil) {
        let s = state(of: d)
        guard effectivelyOn, s.power else {
            d.setPower(false)
            return
        }
        let full = previous == nil || previous?.power == false || previous?.mode != s.mode
        if full { d.setPower(true) }
        if full || previous?.brightness != s.brightness { d.setBrightness(s.brightness) }
        switch s.mode {
        case .solid:
            if full || previous?.color != s.color { d.setColor(s.color) }
        case .effect:
            // A solid frame first stops any firmware effect still running on the light.
            if full { d.setColor(s.effect.usesColors ? s.color : .black) }
        case .native:
            if let e = s.nativeEffect, full || previous?.nativeEffect != e || previous?.speed != s.speed || previous?.color != s.color {
                d.startNativeEffect(e, speed: s.speed, color: s.color)
            }
        }
    }

    // MARK: - Render loop

    private func syncRender() {
        let ds = devices, st = states, active = effectivelyOn
        renderQueue.async { [weak self] in
            self?.rDevices = ds
            self?.rStates = st
            self?.rActive = active
        }
    }

    private nonisolated func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.25, now - rLastTick)
        rLastTick = now
        guard rActive else { return }

        let bulbs = rDevices.filter { $0.ledCount <= 1 }
        var newPreview: [String: [RGB]] = [:]
        let wantPreview = now - rLastPreview > 0.1

        for d in rDevices where d.isReachable {
            guard let s = rStates[d.id], s.power else { continue }
            switch s.mode {
            case .solid:
                if wantPreview { newPreview[d.id] = [s.color] }
            case .native:
                if wantPreview { newPreview[d.id] = [s.color, s.color2] }
            case .effect:
                let phase = (rPhase[d.id] ?? 0) + dt * Effect.rate(forSpeed: s.speed)
                rPhase[d.id] = phase
                // Bulbs get a spot along the house so waves travel from light to light.
                let offset = d.ledCount <= 1 ? Double(bulbs.firstIndex { $0 === d } ?? 0) / Double(max(1, bulbs.count)) : 0
                let span = d.ledCount <= 1 ? 0 : 1
                let frame = s.effect.frame(count: d.ledCount, offset: offset, span: Double(span), phase: phase, s.color, s.color2)
                if now - (rLastSent[d.id] ?? 0) >= 1 / d.maxFPS {
                    rLastSent[d.id] = now
                    if d.capabilities.contains(.perLED) { d.setFrame(frame) } else { d.setColor(RGB.average(frame)) }
                }
                if wantPreview { newPreview[d.id] = frame.count > 24 ? stride(from: 0, to: frame.count, by: frame.count / 24).map { frame[$0] } : frame }
            }
        }
        if wantPreview {
            rLastPreview = now
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.preview = newPreview }
            }
        }
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        var states: [String: LightState]
        var rooms: [Room]
        var target: Target
        var followDisplaySleep: Bool
        var masterPower: Bool
        var lastUsed: LightState
        var customNames: [String: String]?
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        states = s.states
        rooms = s.rooms
        target = s.target
        followDisplaySleep = s.followDisplaySleep
        masterPower = s.masterPower
        lastUsed = s.lastUsed
        customNames = s.customNames ?? [:]
    }

    private func save() {
        saveWork?.cancel()
        let s = Stored(states: states, rooms: rooms, target: target, followDisplaySleep: followDisplaySleep,
                       masterPower: masterPower, lastUsed: lastUsed, customNames: customNames)
        let w = DispatchWorkItem {
            if let d = try? JSONEncoder().encode(s) { try? d.write(to: Self.storeURL, options: .atomic) }
        }
        saveWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: w)
    }
}
