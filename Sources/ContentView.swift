import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            Group {
                if model.connected && model.loaded {
                    TabView(selection: $model.selectedTab) {
                        DPIView().tabItem { Label("DPI", systemImage: "speedometer") }.tag(0)
                        SensitivityView().tabItem { Label("Pointer", systemImage: "cursorarrow.motionlines") }.tag(1)
                        LightingView().tabItem { Label("Lighting", systemImage: "lightbulb") }.tag(2)
                        ButtonsView().tabItem { Label("Buttons", systemImage: "computermouse") }.tag(3)
                        ProfilesView().tabItem { Label("Profiles", systemImage: "person.2") }.tag(4)
                        HardwareView().tabItem { Label("Hardware", systemImage: "gearshape.2") }.tag(5)
                        MacView().tabItem { Label("Mac", systemImage: "macwindow") }.tag(6)
                    }
                    .padding(12)
                } else {
                    PlaceholderView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            FooterView()
        }
        .frame(width: 940, height: 660)
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil },
                                                           set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.connected ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.identity?.product ?? "ROCCAT Tyon")
                        .font(.headline)
                    Text(model.connected ? "Firmware \(model.firmware ?? "…")" : "Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.loaded {
                Picker("Profile", selection: $model.selectedProfile) {
                    ForEach(0..<Tyon.profileCount, id: \.self) { i in
                        Text(profileLabel(i)).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                .labelsHidden()

                if model.selectedProfile == model.activeProfile {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 110, alignment: .leading)
                } else {
                    Button("Make active") { model.activate(profile: model.selectedProfile) }
                        .disabled(model.busy)
                        .frame(width: 110, alignment: .leading)
                }

                Menu {
                    Button("Export profile \(model.selectedProfile + 1)…") { model.exportProfile(model.selectedProfile) }
                    Button("Import into profile \(model.selectedProfile + 1)…") { model.importProfile(into: model.selectedProfile) }
                    Divider()
                    Button("Reset profile \(model.selectedProfile + 1) to factory defaults") { model.resetProfileToFactory(model.selectedProfile) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func profileLabel(_ i: Int) -> String {
        var s = model.profileLabel(i)
        if model.isDirty(i) { s += " •" }
        if i == model.activeProfile { s = "▸ " + s }
        return s
    }
}

struct FooterView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            if model.busy {
                ProgressView().controlSize(.small)
            }
            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if model.isDirty {
                Button("Discard changes") { model.discardChanges() }
                    .disabled(model.busy)
            }
            Button("Reload from mouse") { model.reloadAll() }
                .disabled(model.busy || !model.connected)
            Button("Apply to mouse") { model.apply() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.isDirty || model.busy || !model.connected)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct PlaceholderView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: model.connected ? "computermouse.fill" : "computermouse")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            if model.connected {
                ProgressView()
                Text("Reading settings from the mouse…")
                    .foregroundStyle(.secondary)
            } else {
                Text("Plug in your ROCCAT Tyon")
                    .font(.title3)
                Text("The app talks to the mouse directly over USB; no driver is needed.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared binding helpers

extension AppModel {
    func settingsBinding(_ i: Int) -> Binding<ProfileSettings> {
        Binding(
            get: { self.settings[i] ?? .factoryDefault },
            set: { self.settings[i] = $0 }
        )
    }

    func buttonsBinding(_ i: Int) -> Binding<ProfileButtons> {
        Binding(
            get: { self.buttons[i] ?? .factoryDefault },
            set: { self.buttons[i] = $0 }
        )
    }
}
