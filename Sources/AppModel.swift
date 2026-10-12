// AppModel.swift
// Observable state for the UI. Edits are staged in memory and only written to the
// mouse when the user clicks "Apply to mouse".

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProfileSnapshot: Codable {
    var settings: ProfileSettings
    var buttons: ProfileButtons
}

final class AppModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var identity: HIDTransport.Identity?
    @Published private(set) var firmware: String?
    @Published private(set) var activeProfile = 0
    @Published var selectedProfile = 0
    @Published var selectedTab = 0
    @Published var settings: [ProfileSettings?] = Array(repeating: nil, count: Tyon.profileCount)
    @Published var buttons: [ProfileButtons?] = Array(repeating: nil, count: Tyon.profileCount)
    @Published private(set) var deviceSettings: [ProfileSettings?] = Array(repeating: nil, count: Tyon.profileCount)
    @Published private(set) var deviceButtons: [ProfileButtons?] = Array(repeating: nil, count: Tyon.profileCount)
    @Published private(set) var controlUnit: ControlUnit?
    @Published private(set) var busy = false
    @Published private(set) var status = "Looking for a ROCCAT Tyon…"
    @Published private(set) var loaded = false
    @Published var errorMessage: String?

    let transport = HIDTransport()
    let gestures = GestureEngine()
    @Published var prefs: ProfilePrefs {
        didSet {
            if prefs != oldValue {
                prefs.save()
                syncProfileCycleSoftwareAction()
            }
        }
    }

    init() {
        prefs = ProfilePrefs.load()
        gestures.profileSwitchHandler = { [weak self] forward in self?.cycleProfile(forward: forward) }
        syncProfileCycleSoftwareAction()
    }
    private lazy var device = TyonDevice(transport: transport)
    private let work = DispatchQueue(label: "TyonControl.work", qos: .userInitiated)
    private var started = false
    private var refreshDebounce: DispatchWorkItem?

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            errorMessage = "Another copy of Tyon Control is already running. Two copies talking to the mouse at once will make both fail, so please quit one of them."
        }
        transport.onEvent = { [weak self] event in self?.handle(event) }
        transport.start()
        if transport.isConnected { handle(.connected) }
    }

    private func handle(_ event: HIDTransport.Event) {
        switch event {
        case .connected:
            guard !connected else { return }
            connected = true
            identity = transport.identity
            status = "Connected"
            reloadAll()
        case .disconnected:
            connected = false
            loaded = false
            firmware = nil
            controlUnit = nil
            status = "Mouse disconnected"
        case .special(let bytes):
            guard let ev = SpecialEvent(bytes: bytes) else { return }
            switch ev.kind {
            case .profileChanged, .cpiChanged:
                scheduleActiveRefresh()
            case .quickLaunch(let slot, let pressed):
                gestures.handle(button: slot, pressed: pressed)
            case .other:
                break
            }
        }
    }

    /// The mouse changed profile/DPI on its own (button press): re-read what's active.
    private func scheduleActiveRefresh() {
        refreshDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refreshActive() }
        refreshDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func refreshActive() {
        guard loaded, !busy else { return }
        run("Refreshing…", { dev -> (Int, ProfileSettings) in
            let active = try dev.readActiveProfile()
            return (active, try dev.readProfileSettings(active))
        }) { active, s in
            let wasClean = self.settings[active] == self.deviceSettings[active]
            self.activeProfile = active
            self.deviceSettings[active] = s
            if wasClean { self.settings[active] = s }
            self.status = "Connected"
        }
    }

    // MARK: Background execution

    private func run<T>(_ label: String, _ op: @escaping (TyonDevice) throws -> T, completion: @escaping (T) -> Void) {
        busy = true
        status = label
        let dev = device
        work.async {
            do {
                let result = try op(dev)
                DispatchQueue.main.async {
                    self.busy = false
                    completion(result)
                }
            } catch {
                NSLog("TyonControl: %@ failed: %@", label, error.localizedDescription)
                DispatchQueue.main.async {
                    self.busy = false
                    self.status = "Failed: \(label)"
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Reading

    struct FullState {
        var firmware: String
        var active: Int
        var settings: [ProfileSettings]
        var buttons: [ProfileButtons]
        var controlUnit: ControlUnit
    }

    func reloadAll() {
        run("Reading settings from mouse…", { dev -> FullState in
            let info = try dev.readInfo()
            let active = try dev.readActiveProfile()
            var s: [ProfileSettings] = []
            var b: [ProfileButtons] = []
            for i in 0..<Tyon.profileCount {
                s.append(try dev.readProfileSettings(i))
                b.append(try dev.readProfileButtons(i))
            }
            let cu = try dev.readControlUnit()
            // Ask the firmware to report "Mac action" buttons and profile/DPI changes to us.
            try dev.setDeviceState(on: true)
            return FullState(firmware: info.firmwareString, active: active, settings: s, buttons: b, controlUnit: cu)
        }) { st in
            self.firmware = st.firmware
            self.activeProfile = st.active
            self.deviceSettings = st.settings
            self.deviceButtons = st.buttons
            self.settings = st.settings
            self.buttons = st.buttons
            self.controlUnit = st.controlUnit
            if !self.loaded { self.selectedProfile = st.active }
            self.loaded = true
            self.status = "Connected"
            DebugSnapshot.runIfRequested(model: self)
        }
    }

    // MARK: Dirty tracking

    func isDirty(_ i: Int) -> Bool {
        settings[i] != deviceSettings[i] || buttons[i] != deviceButtons[i]
    }

    var isDirty: Bool { (0..<Tyon.profileCount).contains { isDirty($0) } }

    func discardChanges() {
        settings = deviceSettings
        buttons = deviceButtons
        status = "Changes discarded"
    }

    func resetProfileToFactory(_ i: Int) {
        settings[i] = ProfileSettings.factoryDefault
        buttons[i] = ProfileButtons.factoryDefault
    }

    // MARK: Profile names and the profile switch button

    func profileLabel(_ i: Int) -> String {
        let name = prefs.names[i].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "\(i + 1)" : "\(i + 1) · \(name)"
    }

    /// When the cycle is software-driven, the gesture engine must know the button triggers it.
    private func syncProfileCycleSoftwareAction() {
        var cfg = gestures.config
        // drop stale entries
        for (slot, action) in cfg.plainActions where action == .nextProfile || action == .previousProfile {
            if slot != prefs.cycleButton || prefs.mechanism != .software { cfg.plainActions.removeValue(forKey: slot) }
        }
        if let slot = prefs.cycleButton, prefs.mechanism == .software, slot != cfg.gestureButton {
            cfg.plainActions[slot] = .nextProfile
        }
        if cfg != gestures.config { gestures.config = cfg }
    }

    func stageProfileCycleMapping() {
        guard let slot = prefs.cycleButton else { return }
        for (p, assignment) in prefs.desiredAssignments() {
            guard var b = buttons[p] else { continue }
            b.buttons[slot] = assignment
            buttons[p] = b
        }
        status = "Profile switch mapping staged – click Apply to mouse"
    }

    private func profileCycleMapping(matches source: [ProfileButtons?]) -> Bool {
        guard let slot = prefs.cycleButton else { return false }
        let desired = prefs.desiredAssignments()
        guard !desired.isEmpty else { return false }
        return desired.allSatisfy { p, a in source[p]?.buttons[slot] == a }
    }

    var profileCycleMappingIsStaged: Bool { profileCycleMapping(matches: buttons) }
    var profileCycleMappingMatchesDevice: Bool { profileCycleMapping(matches: deviceButtons) }

    /// Software profile cycling (triggered by the gesture engine).
    func cycleProfile(forward: Bool) {
        guard connected, !busy, let target = prefs.next(after: activeProfile, forward: forward) else { return }
        activate(profile: target)
    }

    // MARK: Mac-action firmware mapping

    /// Profile the Mac controls are mapped into: the chosen one, else the profile named "Mac", else the active one.
    var macProfile: Int {
        if let p = gestures.config.macProfile, (0..<Tyon.profileCount).contains(p) { return p }
        if let named = prefs.names.firstIndex(where: { $0.range(of: "mac", options: .caseInsensitive) != nil }) { return named }
        return activeProfile
    }

    func isMappedForMacAction(slot: Int, profile: Int) -> Bool {
        guard (0..<Tyon.buttonCount).contains(slot), let b = buttons[profile] else { return false }
        return b.buttons[slot].type == ButtonFunction.macAction
    }

    func isMappedOnDevice(slot: Int, profile: Int) -> Bool {
        guard (0..<Tyon.buttonCount).contains(slot), let b = deviceButtons[profile] else { return false }
        return b.buttons[slot].type == ButtonFunction.macAction
    }

    /// Stage the firmware type "Mac action" on the given slots (user still has to Apply).
    func stageMacActionMapping(slots: [Int], profiles: [Int]) {
        for p in profiles where (0..<Tyon.profileCount).contains(p) {
            guard var b = buttons[p] else { continue }
            for slot in slots where (0..<Tyon.buttonCount).contains(slot) {
                b.buttons[slot] = ButtonAssignment(type: ButtonFunction.macAction, modifier: 0, key: 0)
            }
            buttons[p] = b
        }
        status = "Mapping staged – click Apply to mouse"
    }

    /// Called when the app quits: never leave the pointer frozen.
    func shutdown() {
        gestures.unfreezePointer()
        gestures.scrollReverser.shutdown()
    }

    // MARK: Writing

    struct ApplyOutcome {
        var written: [(Int, ProfileSettings, ProfileButtons)]
        var failure: String?
    }

    func apply() {
        let dirty = (0..<Tyon.profileCount).filter { isDirty($0) }
        guard !dirty.isEmpty else { return }
        let toWrite = dirty.map { i -> (Int, ProfileSettings?, ProfileButtons?) in
            (i, settings[i] != deviceSettings[i] ? settings[i] : nil,
                buttons[i] != deviceButtons[i] ? buttons[i] : nil)
        }
        run("Writing to mouse…", { dev -> ApplyOutcome in
            var outcome = ApplyOutcome(written: [])
            for (i, s, b) in toWrite {
                // Write, read back, and retry if the mouse didn't store what we sent.
                var attempt = 0
                while true {
                    attempt += 1
                    if let s = s { try dev.writeProfileSettings(s, profile: i) }
                    if let b = b { try dev.writeProfileButtons(b, profile: i) }
                    let rs = try dev.readProfileSettings(i)
                    let rb = try dev.readProfileButtons(i)
                    let settingsOK = s.map { $0 == rs } ?? true
                    let buttonsOK = b.map { $0 == rb } ?? true
                    if settingsOK && buttonsOK {
                        outcome.written.append((i, rs, rb))
                        break
                    }
                    if attempt >= 3 {
                        outcome.failure = "Profile \(i + 1) did not store the new values after \(attempt) attempts. Your edits are still shown; try Apply again."
                        return outcome
                    }
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            return outcome
        }) { outcome in
            for (i, s, b) in outcome.written {
                self.deviceSettings[i] = s
                self.deviceButtons[i] = b
                self.settings[i] = s
                self.buttons[i] = b
            }
            if let failure = outcome.failure {
                self.status = "Write failed"
                self.errorMessage = failure
            } else {
                let list = outcome.written.map { String($0.0 + 1) }.joined(separator: ", ")
                var msg = "Saved profile\(outcome.written.count == 1 ? "" : "s") \(list) to mouse"
                if !outcome.written.contains(where: { $0.0 == self.activeProfile }) {
                    msg += " – not the active profile; the mouse is on profile \(self.activeProfile + 1)"
                }
                self.status = msg
            }
        }
    }

    func activate(profile i: Int) {
        run("Switching profile…", { dev in try dev.writeActiveProfile(i) }) {
            self.activeProfile = i
            self.status = "Profile \(i + 1) is now active"
        }
    }

    func setLiftOff(_ d: LiftOffDistance) {
        run("Setting lift-off distance…", { dev -> ControlUnit in
            try dev.setLiftOffDistance(d)
            return try dev.readControlUnit()
        }) { cu in
            self.controlUnit = cu
            self.status = "Lift-off distance set to \(d.label)"
        }
    }

    // MARK: Surface calibration (Tracking Control Unit)

    struct CalibrationResult {
        var median: UInt8
        var pixels: [UInt8]
    }

    /// Takes 5 sensor frames and applies the last median as a *test* value (not persisted).
    func calibrateSurface(progress: @escaping (Int) -> Void, completion: @escaping (CalibrationResult) -> Void) {
        guard let dcu = controlUnit?.dcu else { return }
        run("Calibrating surface…", { dev -> CalibrationResult in
            var last: (median: UInt8, pixels: [UInt8]) = (0, [])
            for step in 0..<5 {
                last = try dev.sampleSurface()
                DispatchQueue.main.async { progress(step + 1) }
            }
            try dev.tcuTest(dcu: dcu, median: last.median)
            return CalibrationResult(median: last.median, pixels: last.pixels)
        }) { result in
            self.status = "Calibration ready to test"
            completion(result)
        }
    }

    func keepCalibration(_ median: UInt8) {
        guard let dcu = controlUnit?.dcu else { return }
        run("Saving calibration…", { dev -> ControlUnit in
            try dev.tcuAccept(dcu: dcu, median: median)
            return try dev.readControlUnit()
        }) { cu in
            self.controlUnit = cu
            self.status = "Surface calibration saved"
        }
    }

    func discardCalibration() {
        guard let dcu = controlUnit?.dcu else { return }
        run("Discarding calibration…", { dev -> ControlUnit in
            try dev.tcuCancel(dcu: dcu)
            return try dev.readControlUnit()
        }) { cu in
            self.controlUnit = cu
            self.status = "Calibration discarded"
        }
    }

    func turnTrackingControlOff() {
        guard let dcu = controlUnit?.dcu else { return }
        run("Turning TCU off…", { dev -> ControlUnit in
            try dev.tcuOff(dcu: dcu)
            return try dev.readControlUnit()
        }) { cu in
            self.controlUnit = cu
            self.status = "Tracking Control Unit off"
        }
    }

    // MARK: Import / export

    func exportProfile(_ i: Int) {
        guard let s = settings[i], let b = buttons[i] else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tyon Profile \(i + 1).json"
        panel.title = "Export profile \(i + 1)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(ProfileSnapshot(settings: s, buttons: b)).write(to: url, options: .atomic)
            status = "Exported profile \(i + 1)"
        } catch {
            errorMessage = "Could not export: \(error.localizedDescription)"
        }
    }

    func importProfile(into i: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import into profile \(i + 1)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 64 * 1024 else { throw TyonError.badResponse("file is too large to be a profile") }
            var snap = try JSONDecoder().decode(ProfileSnapshot.self, from: data)
            try snap.validate()
            settings[i] = snap.settings
            buttons[i] = snap.buttons
            status = "Imported into profile \(i + 1) (not yet applied)"
        } catch {
            errorMessage = "Could not import: \(error.localizedDescription)"
        }
    }
}

extension ProfileSnapshot {
    /// Make sure a file from disk can't produce an out-of-range report.
    mutating func validate() throws {
        guard settings.cpiLevels.count == Tyon.cpiLevelCount else { throw TyonError.badResponse("wrong number of DPI stages") }
        guard settings.lights.count == 2 else { throw TyonError.badResponse("wrong number of light zones") }
        guard buttons.buttons.count == Tyon.buttonCount else { throw TyonError.badResponse("wrong number of buttons") }
        settings.cpiLevels = settings.cpiLevels.map { min(max($0, Tyon.cpiMin), Tyon.cpiMax) }
        settings.cpiActive = min(max(settings.cpiActive, 0), Tyon.cpiLevelCount - 1)
        settings.sensitivityX = min(max(settings.sensitivityX, Tyon.sensitivityMin), Tyon.sensitivityMax)
        settings.sensitivityY = min(max(settings.sensitivityY, Tyon.sensitivityMin), Tyon.sensitivityMax)
        settings.effectSpeed = min(max(settings.effectSpeed, 1), 3)
        settings.cpiLevelsEnabled &= 0x1f
        if settings.cpiLevelsEnabled == 0 { settings.cpiLevelsEnabled = 1 }
        // Round-trip through the wire format so anything else is normalized exactly as the device would see it.
        settings = try ProfileSettings(bytes: settings.encoded(profileIndex: 0), expectedProfile: 0)
        buttons = try ProfileButtons(bytes: buttons.encoded(profileIndex: 0), expectedProfile: 0)
    }
}

// MARK: - Factory defaults (as shipped on an unmodified Tyon)

extension ProfileSettings {
    static let factoryDefault: ProfileSettings = {
        var b: [UInt8] = [0x06, 0x1e, 0x00, 0x00, 0x06, 0x06, 0x1f,
                          0x10, 0x20, 0x40, 0x80, 0xa4,          // 800 1600 3200 6400 8200
                          0x00, 0x03, 0x03, 0x00, 0x01, 0x02,
                          0x00, 0x05, 0x90, 0xfe, 0x00,          // wheel: palette 0
                          0x00, 0x05, 0x90, 0xfe, 0x00,          // bottom: palette 0
                          0x00, 0x00]
        let sum = ProfileSettings.checksum(b)
        b[28] = UInt8(sum & 0xff); b[29] = UInt8(sum >> 8)
        return try! ProfileSettings(bytes: b, expectedProfile: 0)
    }()
}

extension ProfileButtons {
    static let factoryDefault: ProfileButtons = {
        let types: [UInt8] = [
            0x01, 0x02, 0x03, 0x08, 0x07, 0x41, 0x82, 0x83, 0x16, 0x15, 0x8a, 0x8b, 0x0a, 0x09, 0x0d, 0x0e,
            0x08, 0x07, 0x25, 0x00, 0x00, 0x00, 0x80, 0x81, 0x12, 0x11, 0x88, 0x89, 0x86, 0x87, 0x26, 0x27,
        ]
        var b: [UInt8] = [0x07, 0x63, 0x00]
        for t in types { b += [t, 0, 0] }
        return try! ProfileButtons(bytes: b, expectedProfile: 0)
    }()
}

// MARK: - Color helpers

extension RGBColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: UInt8(clamping: Int((ns.redComponent * 255).rounded())),
                  green: UInt8(clamping: Int((ns.greenComponent * 255).rounded())),
                  blue: UInt8(clamping: Int((ns.blueComponent * 255).rounded())))
    }
}

extension TyonPalette {
    static func index(of color: RGBColor) -> Int? { colors.firstIndex(of: color) }
    static func isPaletteColor(_ light: TyonLight) -> Bool {
        Int(light.index) < colors.count && colors[Int(light.index)] == light.color
    }
}
