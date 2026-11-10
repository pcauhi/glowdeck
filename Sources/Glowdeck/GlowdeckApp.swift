import GlowdeckCore
import SwiftUI

@MainActor
enum AppModel {
    static let lights: LightManager = {
        let m = LightManager()
        m.start()
        return m
    }()
}

/// Developer flags: `--preview-menu` / `--preview-dashboard` open the views in normal windows
/// (handy for screenshots and UI work, since a menu bar panel can't be opened programmatically).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--preview-menu") {
            show(MenuView(), title: "Glowdeck menu", size: NSSize(width: 344, height: 760))
        }
        if args.contains("--preview-dashboard") {
            show(DashboardView(), title: "Glowdeck", size: NSSize(width: 1100, height: 760))
        }
    }

    private func show<V: View>(_ view: V, title: String, size: NSSize) {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = title
        w.titlebarAppearsTransparent = true
        w.isOpaque = false
        w.backgroundColor = .clear
        let host = NSHostingView(rootView: view.environmentObject(AppModel.lights))
        let fx = NSVisualEffectView()
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        host.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: fx.leadingAnchor), host.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            host.topAnchor.constraint(equalTo: fx.topAnchor), host.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        w.contentView = fx
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindows.append(w)

        // `--snapshot <dir>`: save a PNG of each preview window after it settles.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                v.cacheDisplay(in: v.bounds, to: rep)
                let name = title.lowercased().replacingOccurrences(of: " ", with: "-") + ".png"
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}

@main
struct GlowdeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var lights = AppModel.lights

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(lights)
        } label: {
            Image(systemName: lights.masterPower ? "light.max" : "light.min")
        }
        .menuBarExtraStyle(.window)

        Window("Glowdeck", id: "dashboard") {
            DashboardView().environmentObject(lights)
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1020, height: 680)
    }
}
