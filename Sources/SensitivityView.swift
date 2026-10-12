import SwiftUI

struct SensitivityView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.settingsBinding(model.selectedProfile)
        Form {
            Section("Sensitivity") {
                Toggle("Separate X and Y sensitivity", isOn: s.advancedSensitivity)
                SensitivitySlider(title: s.wrappedValue.advancedSensitivity ? "Horizontal (X)" : "Sensitivity",
                                  value: s.sensitivityX)
                if s.wrappedValue.advancedSensitivity {
                    SensitivitySlider(title: "Vertical (Y)", value: s.sensitivityY)
                }
                Text("Sensitivity is a firmware-side multiplier on top of DPI; 0 is neutral.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("USB polling rate") {
                Picker("Polling rate", selection: s.pollingRateRaw) {
                    ForEach(PollingRate.allCases) { r in
                        Text(r.label).tag(r.rawValue)
                    }
                    if PollingRate(rawValue: s.wrappedValue.pollingRateRaw) == nil {
                        Text("Unknown (\(s.wrappedValue.pollingRateRaw))").tag(s.wrappedValue.pollingRateRaw)
                    }
                }
                .pickerStyle(.segmented)
                Text("How often the mouse reports to the computer. 1000 Hz is the usual choice; lower values only matter for very old systems.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("TalkFX") {
                Toggle("Allow TalkFX (let games and other ROCCAT devices drive the lighting)", isOn: s.talkFXEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

struct SensitivitySlider: View {
    let title: String
    @Binding var value: Int   // 1...11 on the wire

    var body: some View {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Slider(value: Binding(get: { Double(value - Tyon.sensitivityNeutral) },
                                  set: { value = Int($0.rounded()) + Tyon.sensitivityNeutral }),
                   in: -5...5, step: 1)
            Text(value - Tyon.sensitivityNeutral > 0 ? "+\(value - Tyon.sensitivityNeutral)" : "\(value - Tyon.sensitivityNeutral)")
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }
}
