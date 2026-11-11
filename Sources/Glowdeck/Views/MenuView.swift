import GlowdeckCore
import SwiftUI

/// The glass popover that drops down from the menu bar.
struct MenuView: View {
    @EnvironmentObject var lights: LightManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            header
            if lights.devices.isEmpty {
                emptyState
            } else {
                targetBar
                ControlsPanel(target: lights.target)
                    .disabled(!lights.masterPower)
                    .opacity(lights.masterPower ? 1 : 0.45)
            }
            footer
        }
        .padding(14)
        .frame(width: 344)
        .glassGroup()
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.orange, .pink, .purple, .cyan, .orange], center: .center))
                    .frame(width: 30, height: 30)
                    .blur(radius: lights.masterPower ? 0 : 4)
                    .opacity(lights.masterPower ? 1 : 0.35)
                Image(systemName: "light.max").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Glowdeck").font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $lights.masterPower).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }

    private var subtitle: String {
        let n = lights.devices.count
        let offline = lights.devices.filter { !$0.isReachable }.count
        if lights.displaysAsleep && lights.followDisplaySleep { return "Sleeping with your display" }
        var s = n == 1 ? "1 light" : "\(n) lights"
        if offline > 0 { s += " · \(offline) offline" }
        if !lights.pairings.isEmpty { s += " · \(lights.pairings.count) to set up" }
        return s
    }

    private var targetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(.all, title: "All", symbol: "square.grid.2x2.fill", colors: [])
                ForEach(lights.rooms) { room in
                    chip(.room(room.id), title: room.name, symbol: room.symbol, colors: [])
                }
                ForEach(lights.devices, id: \.id) { d in
                    chip(.device(d.id), title: lights.displayName(d), symbol: d.kind.symbol,
                         colors: lights.preview[d.id] ?? [], offline: !d.isReachable)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ t: Target, title: String, symbol: String, colors: [RGB], offline: Bool = false) -> some View {
        let on = lights.target == t
        return Button { lights.target = t } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10))
                    .foregroundStyle(colors.isEmpty ? Color.primary : Color(RGB.average(colors)))
                Text(title).font(.system(size: 11, weight: on ? .semibold : .regular)).lineLimit(1)
                if offline { Circle().fill(.red).frame(width: 5, height: 5) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glass(20, tint: on ? .accentColor : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb.2").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("No lights yet").font(.system(size: 13, weight: .semibold))
            Text(lights.pairings.isEmpty
                 ? "Plug in a USB light bar, or open the dashboard to find lights on your Wi-Fi."
                 : "Found \(lights.pairings.count) hub(s) that need a quick pairing step.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add lights") { openDashboard() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .glass(16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { openDashboard() } label: {
                Label("Dashboard", systemImage: "rectangle.3.group.fill").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            Spacer()
            Toggle(isOn: $lights.followDisplaySleep) {
                Text("Sleep with display").font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            Menu {
                Button("Scan for lights") { lights.scan() }
                Divider()
                Button("Quit Glowdeck") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .foregroundStyle(.secondary)
    }

    private func openDashboard() {
        closeMenuPanel()
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// MenuBarExtra(.window) has no public "close" API; its panel is the window hosting this view.
    private func closeMenuPanel() {
        var closed = false
        for w in NSApp.windows where w.isVisible && String(describing: type(of: w)).contains("MenuBarExtra") {
            w.orderOut(nil)
            closed = true
        }
        // Fallback: the panel is the key NSPanel while its button is being clicked.
        if !closed, let key = NSApp.keyWindow, key is NSPanel { key.orderOut(nil) }
        log.notice("dashboard: closed menu panel=\(closed, privacy: .public) windows=\(NSApp.windows.map { String(describing: type(of: $0)) }.joined(separator: ","), privacy: .public)")
    }
}
