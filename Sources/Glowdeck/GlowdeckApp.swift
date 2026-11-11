import GlowdeckCore
import ScreenCaptureKit
import SwiftUI

@MainActor
enum AppModel {
    static let isDemo = CommandLine.arguments.contains("--demo")

    static let lights: LightManager = {
        let m: LightManager
        if isDemo {
            LightManager.storeName = "demo-state"
            m = LightManager(providers: [DemoProvider()])
        } else {
            m = LightManager()
        }
        m.start()
        if isDemo { seedDemo(m) }
        return m
    }()

    /// Rooms and a lively mix of themes for screenshots.
    private static func seedDemo(_ m: LightManager) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            var rooms: [String: Room] = [:]
            for (_, _, _, _, _, roomName) in DemoProvider.lights where rooms[roomName] == nil {
                rooms[roomName] = Room(name: roomName, symbol: ["Office": "desktopcomputer", "Living room": "sofa.fill",
                                                               "Hallway": "door.left.hand.open", "Bedroom": "bed.double.fill"][roomName] ?? "house.fill")
            }
            for (id, _, _, _, _, roomName) in DemoProvider.lights { rooms[roomName]?.deviceIDs.append("demo:\(id)") }
            m.rooms = ["Office", "Living room", "Hallway", "Bedroom"].compactMap { rooms[$0] }
            let looks: [String: String] = ["desk": "Aurora", "tv": "Sunset", "lamp": "Sunset", "sofa": "Evening",
                                           "panels": "Ocean", "bed": "Calm"]
            for (id, theme) in looks {
                if let t = Theme.all.first(where: { $0.name == theme }) { m.apply(theme: t, to: .device("demo:\(id)")) }
            }
            m.target = .all
        }
    }
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
        // Uses ScreenCaptureKit so Liquid Glass renders as on screen (needs Screen Recording permission);
        // falls back to an offscreen render without the glass.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let file = URL(fileURLWithPath: args[i + 1])
                .appendingPathComponent(title.lowercased().replacingOccurrences(of: " ", with: "-") + ".png")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                Task { @MainActor in
                    if await Self.capture(w, to: file) { return }
                    guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: file)
                }
            }
        }
    }

    private static func capture(_ w: NSWindow, to file: URL) async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scw = content.windows.first(where: { $0.windowID == CGWindowID(w.windowNumber) }) else { return false }
            let cfg = SCStreamConfiguration()
            let scale = w.backingScaleFactor
            cfg.width = Int(w.frame.width * scale)
            cfg.height = Int(w.frame.height * scale)
            cfg.showsCursor = false
            cfg.ignoreShadowsSingleWindow = true
            let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: scw),
                                                                 configuration: cfg)
            let rep = NSBitmapImageRep(cgImage: img)
            try rep.representation(using: .png, properties: [:])?.write(to: file)
            return true
        } catch {
            log.notice("snapshot: ScreenCaptureKit failed: \(error.localizedDescription, privacy: .public)")
            return false
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
