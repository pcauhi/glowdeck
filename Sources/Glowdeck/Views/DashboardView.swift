import GlowdeckCore
import ServiceManagement
import SwiftUI

enum Page: Hashable {
    case lights(Target)
    case add
    case settings
}

struct DashboardView: View {
    @EnvironmentObject var lights: LightManager
    @State private var page: Page? = .lights(.all)
    @State private var newRoom = false

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section("Home") {
                    Label("All lights", systemImage: "square.grid.2x2.fill")
                        .badge(lights.devices.count)
                        .tag(Page.lights(.all))
                    ForEach(lights.rooms) { room in
                        Label(room.name, systemImage: room.symbol)
                            .badge(room.deviceIDs.count)
                            .tag(Page.lights(.room(room.id)))
                            .contextMenu {
                                Button("Delete room", role: .destructive) {
                                    lights.rooms.removeAll { $0.id == room.id }
                                    page = .lights(.all)
                                }
                            }
                    }
                    Button { newRoom = true } label: {
                        Label("New room", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Section("Setup") {
                    Label("Add lights", systemImage: "antenna.radiowaves.left.and.right")
                        .badge(lights.pairings.count)
                        .tag(Page.add)
                    Label("Settings", systemImage: "gearshape.fill").tag(Page.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch page ?? .lights(.all) {
            case .lights(let t): LightsPage(target: t)
            case .add: AddLightsPage()
            case .settings: SettingsPage()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(isPresented: $newRoom) { NewRoomSheet() }
    }
}

// MARK: - Lights

struct LightsPage: View {
    @EnvironmentObject var lights: LightManager
    var target: Target
    @State private var showControls = false

    private var title: String {
        switch target {
        case .all: return "All lights"
        case .room(let id): return lights.rooms.first { $0.id == id }?.name ?? "Room"
        case .device(let id): return lights.devices.first { $0.id == id }.map { lights.displayName($0) } ?? "Light"
        }
    }

    var body: some View {
        let devices = lights.devices(in: target)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 28, weight: .bold))
                    Text("\(devices.count) light\(devices.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        let on = !devices.contains { lights.state(of: $0).power }
                        lights.update(target) { $0.power = on }
                    } label: {
                        Label("All on/off", systemImage: "power")
                    }
                    .controlSize(.large)
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Themes", symbol: "paintpalette.fill")
                        ThemeGrid(target: target, columns: 5)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Controls", symbol: "slider.horizontal.3")
                        ControlsPanel(target: target, showThemes: false)
                    }
                    .frame(width: 330)
                }
                .disabled(devices.isEmpty)

                SectionLabel(title: "Lights", symbol: "lightbulb.2.fill")
                if devices.isEmpty {
                    Text(target == .all ? "No lights found yet. Plug in a USB light or go to Add lights."
                                        : "This room is empty. Use the ••• menu on a light to move it here.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 30)
                        .frame(maxWidth: .infinity)
                        .glass(16)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                        ForEach(devices, id: \.id) { DeviceCard(device: $0) }
                    }
                }
            }
            .padding(24)
            .glassGroup(spacing: 14)
        }
        .background(ambient(devices))
    }

    /// Soft glow of the current light colours behind the glass.
    private func ambient(_ devices: [LightDevice]) -> some View {
        let cs = devices.compactMap { lights.preview[$0.id].map(RGB.average) }
        let colors = cs.isEmpty ? [Color.gray.opacity(0.2), .clear] : cs.map { Color($0).opacity(0.35) } + [.clear]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .blur(radius: 60)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: cs)
    }
}

struct DeviceCard: View {
    @EnvironmentObject var lights: LightManager
    let device: LightDevice
    @State private var renaming = false
    @State private var newName = ""
    @State private var showControls = false

    var body: some View {
        let s = lights.state(of: device)
        VStack(alignment: .leading, spacing: 12) {
            LEDBar(colors: s.power && lights.masterPower ? (lights.preview[device.id] ?? [s.color]) : [], height: 8)
            HStack(spacing: 10) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .glass(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lights.displayName(device)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(device.isReachable ? .green : .red).frame(width: 6, height: 6)
                        Text(device.isReachable ? "\(device.brand) · \(device.address)" : "Offline · \(device.brand)")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(get: { s.power }, set: { v in lights.update(.device(device.id)) { $0.power = v } }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            IconSlider(low: "sun.min", high: "sun.max.fill",
                       value: Binding(get: { s.brightness }, set: { v in lights.update(.device(device.id)) { $0.brightness = v } }),
                       tint: .yellow)
            HStack {
                Text(modeText(s)).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Controls") { showControls = true }
                    .controlSize(.small)
                    .popover(isPresented: $showControls) {
                        ControlsPanel(target: .device(device.id)).padding(14).frame(width: 330)
                    }
                Menu {
                    Menu("Move to room") {
                        Button("No room") { lights.move(device, to: nil) }
                        ForEach(lights.rooms) { r in Button(r.name) { lights.move(device, to: r) } }
                    }
                    Button("Rename…") { newName = lights.displayName(device); renaming = true }
                    Button("Identify") { identify() }
                    Divider()
                    Text(device.model)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
        .padding(14)
        .glass(18)
        .opacity(device.isReachable ? 1 : 0.6)
        .alert("Rename light", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { lights.rename(device, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func modeText(_ s: LightState) -> String {
        guard s.power else { return "Off" }
        switch s.mode {
        case .solid: return "Solid \(s.color.hex) · \(Int(s.brightness * 100))%"
        case .effect: return "\(s.effect.title) · \(Int(s.brightness * 100))%"
        case .native: return (s.nativeEffect?.name ?? "Built-in") + " · \(Int(s.brightness * 100))%"
        }
    }

    /// Blink the light white three times, then restore.
    private func identify() {
        for i in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) {
                if i % 2 == 0 { device.setColor(.white); device.setBrightness(1) } else { device.setColor(.black) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { lights.update(.device(device.id)) { _ in } ; lights.reapplyAll() }
    }
}

// MARK: - Add lights

struct AddLightsPage: View {
    @EnvironmentObject var lights: LightManager
    @State private var scanning = false

    private let brands: [(String, String, String)] = [
        ("cable.connector", "ROBOBLOQ / DX-Light USB bars", "Plug in. Works instantly, including through a monitor's USB hub or KVM."),
        ("point.3.connected.trianglepath.dotted", "Philips Hue", "Found automatically; press the bridge button once to pair."),
        ("lightbulb.led.fill", "LIFX", "Found automatically, no setup."),
        ("lightbulb.fill", "WiZ", "Found automatically, no setup."),
        ("light.strip.2.fill", "WLED", "Found automatically; full per-LED effects."),
        ("light.strip.2.fill", "Govee", "Turn on “LAN Control” for each light in the Govee Home app."),
        ("lightbulb.fill", "Yeelight", "Turn on “LAN Control” in the Yeelight app. Effects update slowly (bulb limit)."),
        ("hexagon.fill", "Nanoleaf", "Found automatically; hold the power button to pair."),
        ("light.panel.fill", "Elgato Key Light & Light Strip", "Found automatically, no setup."),
        ("house.fill", "Home Assistant", "Brings in everything else: Tuya, Matter, Zigbee, IKEA, Z-Wave… Needs a token."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add lights").font(.system(size: 28, weight: .bold))
                        Text("Glowdeck finds lights on your Wi-Fi and USB. Everything stays on your local network.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        scanning = true
                        lights.scan()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { scanning = false }
                    } label: {
                        HStack {
                            if scanning { ProgressView().controlSize(.small) }
                            Text(scanning ? "Scanning…" : "Scan network")
                        }
                    }
                    .controlSize(.large)
                    .disabled(scanning)
                }

                if !lights.pairings.isEmpty {
                    SectionLabel(title: "Needs your attention", symbol: "hand.tap.fill")
                    ForEach(lights.pairings) { PairingCard(pairing: $0) }
                }

                SectionLabel(title: "Supported", symbol: "checkmark.seal.fill")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(brands, id: \.1) { b in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: b.0).font(.system(size: 16)).frame(width: 32, height: 32).glass(9)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(b.1).font(.system(size: 13, weight: .semibold))
                                Text(b.2).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .glass(14)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct PairingCard: View {
    let pairing: Pairing
    @State private var input = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "link.badge.plus").font(.system(size: 18)).foregroundStyle(.tint)
                Text(pairing.title).font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            Text(pairing.instructions).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                if let prompt = pairing.inputPrompt {
                    SecureField(prompt, text: $input).textFieldStyle(.roundedBorder)
                }
                Button(busy ? "Pairing…" : "Pair") {
                    busy = true
                    message = nil
                    pairing.attempt(input: pairing.inputPrompt == nil ? nil : input) { result in
                        DispatchQueue.main.async {
                            busy = false
                            if case .failure(let e) = result { message = e.description }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || (pairing.inputPrompt != nil && input.isEmpty))
            }
            if let message { Text(message).font(.system(size: 11)).foregroundStyle(.orange) }
        }
        .padding(14)
        .glass(16, tint: .accentColor)
    }
}

// MARK: - Rooms & settings

struct NewRoomSheet: View {
    @EnvironmentObject var lights: LightManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "sofa.fill"
    private let symbols = ["sofa.fill", "bed.double.fill", "desktopcomputer", "fork.knife", "tv.fill",
                           "shower.fill", "figure.and.child.holdinghands", "tree.fill", "car.fill", "books.vertical.fill"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New room").font(.title2.bold())
            TextField("Name (e.g. Office)", text: $name).textFieldStyle(.roundedBorder)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 5), spacing: 8) {
                ForEach(symbols, id: \.self) { s in
                    Button { symbol = s } label: {
                        Image(systemName: s).frame(width: 32, height: 32)
                            .background(symbol == s ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    lights.rooms.append(Room(name: name.trimmingCharacters(in: .whitespaces), symbol: symbol))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct SettingsPage: View {
    @EnvironmentObject var lights: LightManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Behaviour") {
                Toggle("Turn lights off when the display sleeps", isOn: $lights.followDisplaySleep)
                Toggle("Open Glowdeck at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                Link("Source code & issues on GitHub", destination: URL(string: "https://github.com/pcauhi/glowdeck")!)
                Text("Glowdeck is open source (MIT). Want another brand supported? Drivers are small: see CONTRIBUTING.md.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
