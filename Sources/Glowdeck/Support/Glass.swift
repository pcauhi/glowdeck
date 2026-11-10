import AppKit
import GlowdeckCore
import SwiftUI

extension Color {
    init(_ c: RGB) { self.init(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255) }
}

extension RGB {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }
}

/// Liquid Glass on macOS 26+, frosted material before that.
struct GlassBackground: ViewModifier {
    var radius: CGFloat
    var tint: Color?
    var interactive = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background((tint ?? .clear).opacity(0.18), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.12)))
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.35)) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    func glass(_ radius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassBackground(radius: radius, tint: tint, interactive: interactive))
    }

    /// Groups glass shapes so they blend into each other on macOS 26+.
    @ViewBuilder func glassGroup(spacing: CGFloat = 10) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// Small rounded label used for section titles.
struct SectionLabel: View {
    var title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(title.uppercased())
        }
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Glowing horizontal bar of LED colours.
struct LEDBar: View {
    var colors: [RGB]
    var height: CGFloat = 6
    var body: some View {
        let cs = colors.isEmpty ? [Color.gray.opacity(0.3)] : colors.map { Color($0) }
        Capsule()
            .fill(LinearGradient(colors: cs.count == 1 ? [cs[0], cs[0]] : cs, startPoint: .leading, endPoint: .trailing))
            .frame(height: height)
            .shadow(color: (cs.first ?? .clear).opacity(0.7), radius: height * 1.2)
            .animation(.linear(duration: 0.1), value: colors)
    }
}

/// Slider row with leading/trailing SF Symbols.
struct IconSlider: View {
    var low: String
    var high: String
    @Binding var value: Double
    var tint: Color = .accentColor
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: low).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Slider(value: $value, in: 0...1).tint(tint).controlSize(.small)
            Image(systemName: high).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 16)
        }
    }
}

/// Small rainbow circle that opens the system colour panel (SwiftUI's ColorPicker renders as a wide well on macOS).
struct ColorWellButton: View {
    var current: RGB
    var onChange: (RGB) -> Void

    var body: some View {
        Button { ColorPanelBridge.shared.open(current, onChange) } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 18, height: 18)
                .overlay(Image(systemName: "plus").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
        }
        .buttonStyle(.plain)
        .help("Pick any colour")
    }
}

@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var handler: ((RGB) -> Void)?

    func open(_ c: RGB, _ onChange: @escaping (RGB) -> Void) {
        handler = onChange
        let p = NSColorPanel.shared
        p.showsAlpha = false
        p.color = NSColor(Color(c))
        p.setTarget(self)
        p.setAction(#selector(changed(_:)))
        p.isContinuous = true
        p.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        handler?(RGB(Color(nsColor: sender.color)))
    }
}
