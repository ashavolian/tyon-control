import SwiftUI

struct DPIView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.settingsBinding(model.selectedProfile)
        Form {
            Section {
                ForEach(0..<Tyon.cpiLevelCount, id: \.self) { i in
                    DPIStageRow(index: i, settings: s)
                }
            } header: {
                Text("DPI stages for profile \(model.selectedProfile + 1)")
            } footer: {
                Text("The filled circle marks the stage the mouse is using right now. DPI up / down / cycle buttons step through enabled stages only. The Tyon's sensor goes from 200 to 8200 DPI in 200 DPI steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct DPIStageRow: View {
    let index: Int
    @Binding var settings: ProfileSettings

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if settings.isCPIStageEnabled(index) { settings.cpiActive = index }
            } label: {
                Image(systemName: settings.cpiActive == index ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(settings.cpiActive == index ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Make this the active stage")
            .disabled(!settings.isCPIStageEnabled(index))

            Toggle(isOn: enabledBinding) { Text("Stage \(index + 1)") }
                .toggleStyle(.checkbox)
                .frame(width: 90, alignment: .leading)

            Slider(value: cpiBinding, in: Double(Tyon.cpiMin)...Double(Tyon.cpiMax), step: Double(Tyon.cpiStep))
                .disabled(!settings.isCPIStageEnabled(index))

            Text("\(settings.cpiLevels[index]) DPI")
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
                .foregroundStyle(settings.isCPIStageEnabled(index) ? .primary : .secondary)
        }
    }

    private var cpiBinding: Binding<Double> {
        Binding(
            get: { Double(settings.cpiLevels[index]) },
            set: { v in
                let snapped = Int((v / Double(Tyon.cpiStep)).rounded()) * Tyon.cpiStep
                settings.cpiLevels[index] = min(max(snapped, Tyon.cpiMin), Tyon.cpiMax)
            }
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isCPIStageEnabled(index) },
            set: { on in
                if !on {
                    // keep at least one stage enabled
                    let others = (0..<Tyon.cpiLevelCount).filter { $0 != index && settings.isCPIStageEnabled($0) }
                    guard let fallback = others.first else { return }
                    settings.setCPIStageEnabled(index, false)
                    if settings.cpiActive == index { settings.cpiActive = fallback }
                } else {
                    settings.setCPIStageEnabled(index, true)
                }
            }
        )
    }
}
