import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(0..<Tyon.profileCount, id: \.self) { i in
                    HStack {
                        Text("Profile \(i + 1)").frame(width: 80, alignment: .leading)
                        TextField("Name (optional)", text: Binding(
                            get: { model.prefs.names[i] },
                            set: { model.prefs.names[i] = String($0.prefix(24)) }))
                            .textFieldStyle(.roundedBorder)
                        if i == model.activeProfile {
                            Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Make active") { model.activate(profile: i) }.disabled(model.busy)
                        }
                    }
                }
            } header: {
                Text("Profile names")
            } footer: {
                Text("Names live in this app only; the mouse itself just counts 1 to 5.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Button", selection: Binding(
                    get: { model.prefs.cycleButton ?? -1 },
                    set: { model.prefs.cycleButton = $0 < 0 ? nil : $0 })) {
                    Text("None").tag(-1)
                    Section("Buttons") {
                        ForEach(TyonButton.allCases) { b in Text("\(b.rawValue + 1) · \(b.name)").tag(b.rawValue) }
                    }
                    Section("Easy-Shift layer") {
                        ForEach(TyonButton.allCases) { b in Text("Easy-Shift + \(b.name)").tag(b.rawValue + Tyon.physicalButtonCount) }
                    }
                }
                HStack(spacing: 14) {
                    Text("Profiles in the cycle")
                    Spacer()
                    ForEach(0..<Tyon.profileCount, id: \.self) { i in
                        Toggle(model.profileLabel(i), isOn: Binding(
                            get: { model.prefs.cycleSet.contains(i) },
                            set: { on in
                                var set = Set(model.prefs.cycleSet)
                                if on { set.insert(i) } else { set.remove(i) }
                                model.prefs.cycleSet = set.sorted()
                            }))
                            .toggleStyle(.checkbox)
                    }
                }
                mechanismText
                HStack {
                    Button("Stage button mapping") { model.stageProfileCycleMapping() }
                        .disabled(model.prefs.cycleButton == nil || model.prefs.mechanism == .needMore)
                    Spacer()
                    mappingStatus
                }
            } header: {
                Text("Profile switch button")
            } footer: {
                Text("The mouse can only step to the next or previous profile, or cycle through all five, on its own. Two neighbouring profiles (such as 1 and 2) or all five therefore work on any computer; any other set is switched by Tyon Control and only works on this Mac while the app is running.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var mechanismText: some View {
        switch model.prefs.mechanism {
        case .needMore:
            Label("Pick at least two profiles.", systemImage: "info.circle").foregroundStyle(.secondary)
        case .firmwareTwoAdjacent:
            Label("Handled by the mouse: the button is “Profile up” in profile \(model.prefs.cycleSet[0] + 1) and “Profile down” in profile \(model.prefs.cycleSet[1] + 1). Works everywhere, PC included.", systemImage: "checkmark.seal")
                .foregroundStyle(.green)
        case .firmwareAll:
            Label("Handled by the mouse with “Profile cycle” in every profile. Works everywhere.", systemImage: "checkmark.seal")
                .foregroundStyle(.green)
        case .software:
            Label("Handled by Tyon Control (the button becomes a “Mac action” in every profile). Works only on this Mac while the app runs.", systemImage: "desktopcomputer")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var mappingStatus: some View {
        if model.prefs.cycleButton != nil, model.prefs.mechanism != .needMore {
            if model.profileCycleMappingMatchesDevice {
                Label("Mapped on the mouse", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else if model.profileCycleMappingIsStaged {
                Text("Staged – click Apply to mouse").foregroundStyle(.secondary)
            } else {
                Label("Not mapped yet", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }
}
