import SwiftUI
import ServiceManagement

struct MacView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        MacSettingsForm(engine: model.gestures)
            .environmentObject(model)
    }
}

struct MacSettingsForm: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var engine: GestureEngine
    @State private var accessibility = Accessibility.granted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Enable Mac controls", isOn: $engine.config.enabled)
                HStack {
                    Label(accessibility ? "Accessibility access granted" : "Accessibility access not granted",
                          systemImage: accessibility ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundStyle(accessibility ? Color.green : Color.orange)
                    Spacer()
                    if !accessibility {
                        Button("Grant access…") { Accessibility.request() }
                    }
                }
                Text("Switching desktops and Spotlight need Accessibility access (System Settings → Privacy & Security → Accessibility). Mission Control, App Exposé, Show Desktop and Launchpad work without it. The app must stay running for any of this to work; closing the window leaves it in the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Mac controls")
            }

            Section {
                Picker("Gesture button", selection: Binding(
                    get: { engine.config.gestureButton ?? -1 },
                    set: { engine.config.gestureButton = $0 < 0 ? nil : $0 })) {
                    Text("None").tag(-1)
                    Section("Buttons") {
                        ForEach(TyonButton.allCases) { b in Text(b.name).tag(b.rawValue) }
                    }
                    Section("Easy-Shift layer") {
                        ForEach(TyonButton.allCases) { b in Text("Easy-Shift + \(b.name)").tag(b.rawValue + Tyon.physicalButtonCount) }
                    }
                }
                ActionPicker("Click", $engine.config.clickAction)
                ActionPicker("Hold + move left", $engine.config.swipeLeft)
                ActionPicker("Hold + move right", $engine.config.swipeRight)
                ActionPicker("Hold + move up", $engine.config.swipeUp)
                ActionPicker("Hold + move down", $engine.config.swipeDown)
                Toggle("Keep the pointer still while holding the gesture button", isOn: $engine.config.freezePointer)
                if engine.config.freezePointer && !accessibility {
                    Text("Without Accessibility access the pointer can only be held still while Tyon Control is the active app.")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text("Movement needed for a swipe")
                    Slider(value: $engine.config.swipeThreshold, in: 20...300, step: 10)
                    Text("\(Int(engine.config.swipeThreshold)) px").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
            } header: {
                Text("Gesture button (like the MX Master thumb button)")
            } footer: {
                Text("Click the button for one action, or hold it and move the mouse for four more. Only one action fires per hold.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(0..<Tyon.physicalButtonCount, id: \.self) { slot in
                    if slot != engine.config.gestureButton {
                        ActionPicker(TyonButton.slotName(slot), plainBinding(slot))
                    }
                }
                DisclosureGroup("Easy-Shift layer") {
                    ForEach(Tyon.physicalButtonCount..<Tyon.buttonCount, id: \.self) { slot in
                        if slot != engine.config.gestureButton {
                            ActionPicker(TyonButton.slotName(slot), plainBinding(slot))
                        }
                    }
                }
            } header: {
                Text("Single-press Mac actions for other buttons")
            }

            Section {
                Picker("Use Mac controls in profile", selection: Binding(
                    get: { model.macProfile },
                    set: { engine.config.macProfile = $0 })) {
                    ForEach(0..<Tyon.profileCount, id: \.self) { i in Text(model.profileLabel(i)).tag(i) }
                }
                let slots = engine.config.slotsNeedingFirmwareMapping
                let profile = model.macProfile
                let onDevice = slots.filter { model.isMappedOnDevice(slot: $0, profile: profile) }
                let staged = slots.filter { model.isMappedForMacAction(slot: $0, profile: profile) && !model.isMappedOnDevice(slot: $0, profile: profile) }
                let missing = slots.filter { !model.isMappedForMacAction(slot: $0, profile: profile) }
                if slots.isEmpty {
                    Text("No buttons are assigned to Mac controls yet.").foregroundStyle(.secondary)
                } else {
                    if !onDevice.isEmpty {
                        Label("On the mouse in profile \(profile + 1): \(onDevice.map { TyonButton.slotName($0) }.joined(separator: ", "))", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                    if !staged.isEmpty {
                        Label("Staged, click Apply to mouse: \(staged.map { TyonButton.slotName($0) }.joined(separator: ", "))", systemImage: "arrow.down.circle")
                            .foregroundStyle(.blue)
                    }
                    if !missing.isEmpty {
                        Label("Not mapped yet in profile \(profile + 1): \(missing.map { TyonButton.slotName($0) }.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                HStack {
                    Button("Map in profile \(profile + 1)") { model.stageMacActionMapping(slots: slots, profiles: [profile]) }
                        .disabled(slots.isEmpty || missing.isEmpty)
                    Button("Map in all profiles") { model.stageMacActionMapping(slots: slots, profiles: Array(0..<Tyon.profileCount)) }
                        .disabled(slots.isEmpty)
                    Spacer()
                }
            } header: {
                Text("Firmware mapping")
            } footer: {
                Text("The mouse only reports a button to this app when that button is set to “Mac action (Tyon Control)” in that profile. Choosing a button above stages that mapping in the profile selected here; click Apply to mouse to write it. Buttons mapped this way do nothing on other computers.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(MacAction.available.filter { $0.systemHotkeyID != nil }) { a in
                    LabeledContent(a.label, value: a.howItRuns)
                }
                Text("These are read from System Settings → Keyboard → Keyboard Shortcuts → Mission Control. If one is disabled there, the matching action can't work.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("How actions are triggered")
            }

            Section("Live test") {
                LabeledContent("Last button event", value: engine.lastEvent)
                LabeledContent("Last action", value: engine.lastGesture)
                LabeledContent("Pointer hold method", value: engine.holdMethod)
                LabeledContent("Movement while holding", value: engine.isGesturing
                               ? String(format: "x %.0f  y %.0f", engine.liveDelta.width, engine.liveDelta.height)
                               : (engine.config.gestureButton == nil ? "–" : "hold the gesture button and move the mouse"))
                Text("Press a mapped button to confirm the mouse is reporting it. If nothing shows up, make sure the mapping was applied to the active profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Background") {
                Toggle("Start Tyon Control at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }))
                if let loginError = loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Text("Closing the window keeps the app running in the menu bar so gestures keep working. Quit from the menu bar icon.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: engine.config.slotsNeedingFirmwareMapping) { _, slots in
            let missing = slots.filter { !model.isMappedForMacAction(slot: $0, profile: model.macProfile) }
            if !missing.isEmpty { model.stageMacActionMapping(slots: missing, profiles: [model.macProfile]) }
        }
        .onReceive(tick) { _ in
            accessibility = Accessibility.granted
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func plainBinding(_ slot: Int) -> Binding<MacAction> {
        Binding(
            get: { engine.config.plainActions[slot] ?? .none },
            set: { new in
                if new == .none { engine.config.plainActions.removeValue(forKey: slot) } else { engine.config.plainActions[slot] = new }
            })
    }
}

struct ActionPicker: View {
    let title: String
    @Binding var action: MacAction

    init(_ title: String, _ action: Binding<MacAction>) {
        self.title = title
        self._action = action
    }

    var body: some View {
        Picker(title, selection: $action) {
            ForEach(MacAction.available) { a in
                Text(a.label + (a.needsAccessibility && !Accessibility.granted ? "  (needs Accessibility)" : "")).tag(a)
            }
        }
    }
}
