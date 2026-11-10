import GlowdeckCore
import SwiftUI

private let swatches: [RGB] = [
    .warm, RGB(255, 255, 255), RGB(200, 220, 255), RGB(255, 40, 40), RGB(255, 120, 0),
    RGB(255, 210, 0), RGB(40, 220, 90), RGB(0, 200, 255), RGB(40, 80, 255), RGB(160, 50, 255), RGB(255, 50, 150),
]

/// Themes grid. Tapping applies the theme to `target`.
struct ThemeGrid: View {
    @EnvironmentObject var lights: LightManager
    var target: Target
    var columns = 3

    var body: some View {
        let current = lights.state(for: target)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(Theme.all) { theme in
                let selected = theme.state.mode == current.mode && theme.state.effect == current.effect
                    && theme.state.color == current.color && (theme.state.mode != .effect || theme.state.color2 == current.color2)
                Button { lights.apply(theme: theme, to: target) } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(AngularGradient(colors: theme.preview.map { Color($0) } + [Color(theme.preview[0])], center: .center))
                                .frame(width: 30, height: 30)
                                .shadow(color: Color(theme.preview[0]).opacity(0.6), radius: 8)
                            Image(systemName: theme.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        Text(theme.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .glass(12, tint: selected ? Color(theme.preview[0]) : nil, interactive: true)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color(theme.preview[0]).opacity(0.9) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Colour, effect, built-in effect, brightness and speed for a target.
struct ControlsPanel: View {
    @EnvironmentObject var lights: LightManager
    var target: Target
    var showThemes = true

    private var state: LightState { lights.state(for: target) }
    private var targetDevices: [LightDevice] { lights.devices(in: target) }
    private var nativeEffects: [NativeEffect] { targetDevices.first { !$0.nativeEffects.isEmpty }?.nativeEffects ?? [] }

    var body: some View {
        VStack(spacing: 14) {
            if showThemes {
                VStack(spacing: 8) {
                    SectionLabel(title: "Themes", symbol: "paintpalette.fill")
                    ThemeGrid(target: target)
                }
            }

            VStack(spacing: 12) {
                Picker("", selection: Binding(get: { state.mode }, set: { m in
                    lights.update(target) { s in
                        s.mode = m
                        if m == .native, s.nativeEffect == nil { s.nativeEffect = nativeEffects.first }
                    }
                })) {
                    Text("Color").tag(LightState.Mode.solid)
                    Text("Effects").tag(LightState.Mode.effect)
                    if !nativeEffects.isEmpty { Text("Built-in").tag(LightState.Mode.native) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch state.mode {
                case .solid:
                    colorRow(\.color)
                case .effect:
                    effectGrid
                    if state.effect.usesColors {
                        colorRow(\.color)
                        if [.wave, .gradient, .comet, .sparkle].contains(state.effect) { colorRow(\.color2) }
                    }
                case .native:
                    nativeGrid
                }

                VStack(spacing: 8) {
                    IconSlider(low: "sun.min", high: "sun.max.fill", value: binding(\.brightness), tint: .yellow)
                    if state.mode != .solid {
                        IconSlider(low: "tortoise.fill", high: "hare.fill", value: binding(\.speed), tint: .cyan)
                    }
                }
            }
            .padding(12)
            .glass(16)
        }
    }

    private func binding(_ kp: WritableKeyPath<LightState, Double>) -> Binding<Double> {
        Binding(get: { state[keyPath: kp] }, set: { v in lights.update(target) { $0[keyPath: kp] = v } })
    }

    private func colorRow(_ kp: WritableKeyPath<LightState, RGB>) -> some View {
        let current = state[keyPath: kp]
        return HStack(spacing: 6) {
            ForEach(swatches, id: \.self) { c in
                Button { lights.update(target) { $0[keyPath: kp] = c } } label: {
                    Circle()
                        .fill(Color(c))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(current == c ? 0.95 : 0.15), lineWidth: current == c ? 2 : 0.5))
                        .shadow(color: Color(c).opacity(current == c ? 0.8 : 0), radius: 5)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            ColorWellButton(current: current) { c in lights.update(target) { $0[keyPath: kp] = c } }
        }
    }

    private var effectGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(Effect.allCases) { e in
                let on = state.effect == e
                Button { lights.update(target) { $0.mode = .effect; $0.effect = e } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: e.symbol).font(.system(size: 14)).symbolRenderingMode(.hierarchical)
                        Text(e.title).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .background(on ? Color.accentColor.opacity(0.28) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nativeGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(nativeEffects) { e in
                    let on = state.nativeEffect == e
                    Button { lights.update(target) { $0.mode = .native; $0.nativeEffect = e } } label: {
                        Text(e.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                            .background(on ? Color.accentColor.opacity(0.28) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 150)
    }
}
