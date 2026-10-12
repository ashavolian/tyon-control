import SwiftUI

struct LightingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.settingsBinding(model.selectedProfile)
        Form {
            Section("Zones") {
                HStack(alignment: .top, spacing: 24) {
                    LightZoneView(title: "Scroll wheel", zone: 0, settings: s)
                    Divider()
                    LightZoneView(title: "Bottom light", zone: 1, settings: s)
                }
                HStack {
                    Button("Use wheel color for both zones") {
                        var v = s.wrappedValue
                        v.lights[1].color = v.lights[0].color
                        v.lights[1].index = v.lights[0].index
                        v.customColor = !v.lights.allSatisfy(TyonPalette.isPaletteColor)
                        s.wrappedValue = v
                    }
                    Spacer()
                }
            }

            Section("Effect") {
                Picker("Effect", selection: s.lightEffectRaw) {
                    ForEach(LightEffect.allCases) { e in Text(e.label).tag(e.rawValue) }
                    if LightEffect(rawValue: s.wrappedValue.lightEffectRaw) == nil {
                        Text("Unknown (\(s.wrappedValue.lightEffectRaw))").tag(s.wrappedValue.lightEffectRaw)
                    }
                }
                Picker("Speed", selection: s.effectSpeed) {
                    Text("Slow").tag(1)
                    Text("Medium").tag(2)
                    Text("Fast").tag(3)
                }
                .pickerStyle(.segmented)
                .disabled(![LightEffect.blinking.rawValue, LightEffect.breathing.rawValue, LightEffect.heartbeat.rawValue].contains(s.wrappedValue.lightEffectRaw) && s.wrappedValue.colorFlowRaw == 0)
                Picker("Color", selection: s.colorFlowRaw) {
                    ForEach(ColorFlow.allCases) { f in Text(f.label).tag(f.rawValue) }
                    if ColorFlow(rawValue: s.wrappedValue.colorFlowRaw) == nil {
                        Text("Unknown (\(s.wrappedValue.colorFlowRaw))").tag(s.wrappedValue.colorFlowRaw)
                    }
                }
                Text("With a color cycle the zone colors above are ignored and the mouse fades through the spectrum.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct LightZoneView: View {
    let title: String
    let zone: Int
    @Binding var settings: ProfileSettings

    private let columns = Array(repeating: GridItem(.fixed(24), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(title, isOn: zone == 0 ? $settings.wheelLightOn : $settings.bottomLightOn)
                .font(.headline)
            HStack {
                ColorPicker("Custom color", selection: colorBinding, supportsOpacity: false)
                Text(settings.lights[zone].color.hexString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(TyonPalette.colors.enumerated()), id: \.offset) { idx, c in
                    Button {
                        setPalette(idx)
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(c.swiftUIColor)
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isSelected(idx) ? Color.primary : Color.black.opacity(0.15),
                                            lineWidth: isSelected(idx) ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(c.hexString)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity((zone == 0 ? settings.wheelLightOn : settings.bottomLightOn) ? 1 : 0.5)
    }

    private func isSelected(_ idx: Int) -> Bool {
        Int(settings.lights[zone].index) == idx && settings.lights[zone].color == TyonPalette.colors[idx]
    }

    private func setPalette(_ idx: Int) {
        settings.lights[zone].index = UInt8(idx)
        settings.lights[zone].color = TyonPalette.colors[idx]
        settings.customColor = !settings.lights.allSatisfy(TyonPalette.isPaletteColor)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { settings.lights[zone].color.swiftUIColor },
            set: { newColor in
                let rgb = RGBColor(newColor)
                settings.lights[zone].color = rgb
                if let pi = TyonPalette.index(of: rgb) { settings.lights[zone].index = UInt8(pi) }
                settings.customColor = !settings.lights.allSatisfy(TyonPalette.isPaletteColor)
            }
        )
    }
}
