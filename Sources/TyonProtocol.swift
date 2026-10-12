// TyonProtocol.swift
// Wire format of the ROCCAT Tyon's vendor HID feature reports.
// Derived from the GPL roccat-tools project (libroccattyon) by Stefan Achatz,
// cross-checked against the live device.

import Foundation

// MARK: - Errors

enum TyonError: LocalizedError {
    case notConnected
    case openFailed(Int32)
    case transfer(String, Int32)
    case badResponse(String)
    case deviceStatus(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No ROCCAT Tyon is connected."
        case .openFailed(let r):
            return String(format: "Could not open the mouse (IOKit error 0x%08x).", UInt32(bitPattern: r))
        case .transfer(let what, let r):
            return String(format: "%@ failed (IOKit error 0x%08x).", what, UInt32(bitPattern: r))
        case .badResponse(let s):
            return "Unexpected data from the mouse: \(s)"
        case .deviceStatus(let s):
            return "The mouse rejected the command: \(s)"
        case .timeout(let s):
            return "Timed out waiting for the mouse: \(s)"
        }
    }
}

// MARK: - Constants

enum Tyon {
    static let vendorID = 0x1e7d
    static let productIDs = [0x2e4a, 0x2e4b]          // Black, White
    static let profileCount = 5
    static let cpiLevelCount = 5
    static let cpiMin = 200
    static let cpiMax = 8200
    static let cpiStep = 200                            // what the original software exposed
    static let cpiUnit = 50                             // on-device byte = cpi / 50
    static let sensitivityMin = 1                       // -5
    static let sensitivityMax = 11                      // +5
    static let sensitivityNeutral = 6                   //  0
    static let buttonCount = 32                         // 16 physical + 16 Easy-Shift
    static let physicalButtonCount = 16

    enum Report {
        static let special: UInt8 = 0x03           // input report on the misc interface, 5 bytes
        static let control: UInt8 = 0x04;          static let controlSize = 3
        static let profile: UInt8 = 0x05;          static let profileSize = 3
        static let profileSettings: UInt8 = 0x06;  static let profileSettingsSize = 30
        static let profileButtons: UInt8 = 0x07;   static let profileButtonsSize = 99
        static let info: UInt8 = 0x09;             static let infoSize = 8
        static let sensor: UInt8 = 0x0c;           static let sensorSize = 4
        static let sensorImageSize = 1028          // 3 header + 30*30 pixels + 125 padding
        static let sensorImagePixels = 900
        static let deviceState: UInt8 = 0x0e;      static let deviceStateSize = 3
        static let controlUnit: UInt8 = 0x0f;      static let controlUnitSize = 6
        static let talk: UInt8 = 0x10;             static let talkSize = 16
    }

    enum ControlRequest {
        static let check: UInt8 = 0x00
        static let profileSettings: UInt8 = 0x80
        static let profileButtons: UInt8 = 0x90
    }

    enum ControlStatus {
        static let critical1: UInt8 = 0
        static let ok: UInt8 = 1
        static let invalid: UInt8 = 2
        static let busy: UInt8 = 3
        static let critical2: UInt8 = 4
    }

    enum SensorAction {
        static let writeRegister: UInt8 = 1   // never used by this app
        static let readRegister: UInt8 = 2
        static let frameCapture: UInt8 = 3
    }

    enum ControlUnitAction {
        static let cancel: UInt8 = 0x00
        static let accept: UInt8 = 0x01
        static let off: UInt8 = 0x02
        static let undefined: UInt8 = 0xff
    }

    /// Firmware reports its version as a single byte: 134 -> "1.34".
    static func firmwareString(_ v: UInt8) -> String {
        String(format: "%u.%02u", UInt(v) / 100, UInt(v) % 100)
    }

    static func cpiFromByte(_ b: UInt8) -> Int { Int(b) * cpiUnit }
    static func byteFromCPI(_ cpi: Int) -> UInt8 {
        let clamped = min(max(cpi, cpiMin), cpiMax)
        return UInt8(min(max(clamped / cpiUnit, 1), cpiMax / cpiUnit))
    }
}

// MARK: - Simple enums

enum PollingRate: UInt8, CaseIterable, Identifiable, Codable {
    case hz125 = 0, hz250 = 1, hz500 = 2, hz1000 = 3
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .hz125: return "125 Hz"
        case .hz250: return "250 Hz"
        case .hz500: return "500 Hz"
        case .hz1000: return "1000 Hz"
        }
    }
}

enum LightEffect: UInt8, CaseIterable, Identifiable, Codable {
    case off = 0, solid = 1, blinking = 2, breathing = 3, heartbeat = 4
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .off: return "All lights off"
        case .solid: return "Fully lit"
        case .blinking: return "Blinking"
        case .breathing: return "Breathing"
        case .heartbeat: return "Heartbeat"
        }
    }
}

enum ColorFlow: UInt8, CaseIterable, Identifiable, Codable {
    case off = 0, simultaneously = 1, up = 2, down = 3
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .off: return "Fixed color"
        case .simultaneously: return "Color cycle (both zones together)"
        case .up: return "Color cycle (flowing up)"
        case .down: return "Color cycle (flowing down)"
        }
    }
}

enum LiftOffDistance: UInt8, CaseIterable, Identifiable, Codable {
    case off = 0, extraLow = 1, low = 2, normal = 3
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .extraLow: return "Extra low"
        case .low: return "Low"
        case .normal: return "Normal"
        }
    }
}

struct RGBColor: Equatable, Hashable, Codable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    var hexString: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

/// The 16 colors ROCCAT's own software offered on its palette.
enum TyonPalette {
    static let colors: [RGBColor] = [
        RGBColor(red: 0x05, green: 0x90, blue: 0xfe), RGBColor(red: 0x00, green: 0x71, blue: 0xff),
        RGBColor(red: 0x00, green: 0x00, blue: 0xff), RGBColor(red: 0x5c, green: 0x18, blue: 0xe6),
        RGBColor(red: 0x81, green: 0x18, blue: 0xe6), RGBColor(red: 0xc5, green: 0x18, blue: 0xe6),
        RGBColor(red: 0xf8, green: 0x04, blue: 0x7c), RGBColor(red: 0xff, green: 0x00, blue: 0x00),
        RGBColor(red: 0xf7, green: 0x79, blue: 0x00), RGBColor(red: 0xe7, green: 0xdc, blue: 0x00),
        RGBColor(red: 0xc2, green: 0xf2, blue: 0x08), RGBColor(red: 0x00, green: 0xff, blue: 0x00),
        RGBColor(red: 0x18, green: 0xa6, blue: 0x2a), RGBColor(red: 0x13, green: 0xec, blue: 0x96),
        RGBColor(red: 0x0d, green: 0xe2, blue: 0xd9), RGBColor(red: 0x00, green: 0xbe, blue: 0xf4),
    ]
}

// MARK: - Profile settings (report 0x06, 30 bytes)

struct TyonLight: Equatable, Codable {
    var index: UInt8        // palette slot (0-15); kept as-is for custom colors
    var color: RGBColor
    var unused: UInt8 = 0   // preserved verbatim
}

struct ProfileSettings: Equatable, Codable {
    var advancedSensitivity: Bool          // separate X/Y sensitivity
    var sensitivityX: Int                  // 1...11, 6 = neutral
    var sensitivityY: Int
    var cpiLevelsEnabled: UInt8            // bit n = stage n enabled
    var cpiLevels: [Int]                   // 5 values in CPI
    var cpiActive: Int                     // 0...4
    var pollingRateRaw: UInt8              // low nibble of byte 13
    var talkFXEnabled: Bool                // high nibble of byte 13: 0 = on, 1 = off
    var lightsEnabledRaw: UInt8            // bit0 wheel, bit1 bottom, bit4 custom color
    var colorFlowRaw: UInt8
    var lightEffectRaw: UInt8
    var effectSpeed: Int                   // 1...3
    var lights: [TyonLight]                // [wheel, bottom]

    static let lightsWheelBit: UInt8 = 1 << 0
    static let lightsBottomBit: UInt8 = 1 << 1
    static let lightsCustomBit: UInt8 = 1 << 4

    var pollingRate: PollingRate? {
        get { PollingRate(rawValue: pollingRateRaw) }
        set { if let v = newValue { pollingRateRaw = v.rawValue } }
    }
    var colorFlow: ColorFlow? {
        get { ColorFlow(rawValue: colorFlowRaw) }
        set { if let v = newValue { colorFlowRaw = v.rawValue } }
    }
    var lightEffect: LightEffect? {
        get { LightEffect(rawValue: lightEffectRaw) }
        set { if let v = newValue { lightEffectRaw = v.rawValue } }
    }
    var wheelLightOn: Bool {
        get { lightsEnabledRaw & Self.lightsWheelBit != 0 }
        set { setLightsBit(Self.lightsWheelBit, newValue) }
    }
    var bottomLightOn: Bool {
        get { lightsEnabledRaw & Self.lightsBottomBit != 0 }
        set { setLightsBit(Self.lightsBottomBit, newValue) }
    }
    var customColor: Bool {
        get { lightsEnabledRaw & Self.lightsCustomBit != 0 }
        set { setLightsBit(Self.lightsCustomBit, newValue) }
    }
    private mutating func setLightsBit(_ bit: UInt8, _ on: Bool) {
        if on { lightsEnabledRaw |= bit } else { lightsEnabledRaw &= ~bit }
    }

    func isCPIStageEnabled(_ i: Int) -> Bool { cpiLevelsEnabled & (1 << UInt8(i)) != 0 }
    mutating func setCPIStageEnabled(_ i: Int, _ on: Bool) {
        if on { cpiLevelsEnabled |= 1 << UInt8(i) } else { cpiLevelsEnabled &= ~(1 << UInt8(i)) }
    }

    /// Sum of all bytes before the 16-bit little-endian checksum.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        bytes[0..<(Tyon.Report.profileSettingsSize - 2)].reduce(UInt16(0)) { $0 &+ UInt16($1) }
    }

    init(bytes b: [UInt8], expectedProfile: Int) throws {
        let n = Tyon.Report.profileSettingsSize
        guard b.count == n else { throw TyonError.badResponse("profile settings were \(b.count) bytes, expected \(n)") }
        guard b[0] == Tyon.Report.profileSettings else { throw TyonError.badResponse("profile settings had report id 0x\(String(b[0], radix: 16))") }
        guard b[1] == UInt8(n) else { throw TyonError.badResponse("profile settings size byte was \(b[1])") }
        guard Int(b[2]) == expectedProfile else { throw TyonError.badResponse("asked for profile \(expectedProfile + 1) but got profile \(Int(b[2]) + 1)") }
        let got = UInt16(b[28]) | UInt16(b[29]) << 8
        let want = Self.checksum(b)
        guard got == want else { throw TyonError.badResponse("profile settings checksum mismatch (\(got) vs \(want))") }

        advancedSensitivity = b[3] != 0
        sensitivityX = min(max(Int(b[4]), Tyon.sensitivityMin), Tyon.sensitivityMax)
        sensitivityY = min(max(Int(b[5]), Tyon.sensitivityMin), Tyon.sensitivityMax)
        cpiLevelsEnabled = b[6] & 0x1f
        cpiLevels = (0..<Tyon.cpiLevelCount).map { Tyon.cpiFromByte(b[7 + $0]) }
        cpiActive = min(Int(b[12]), Tyon.cpiLevelCount - 1)
        pollingRateRaw = b[13] & 0x0f
        talkFXEnabled = (b[13] >> 4) == 0
        lightsEnabledRaw = b[14]
        colorFlowRaw = b[15]
        lightEffectRaw = b[16]
        effectSpeed = min(max(Int(b[17]), 1), 3)
        lights = (0..<2).map { i in
            let o = 18 + i * 5
            return TyonLight(index: b[o], color: RGBColor(red: b[o + 1], green: b[o + 2], blue: b[o + 3]), unused: b[o + 4])
        }
    }

    func encoded(profileIndex: Int) -> [UInt8] {
        precondition((0..<Tyon.profileCount).contains(profileIndex))
        var b = [UInt8](repeating: 0, count: Tyon.Report.profileSettingsSize)
        b[0] = Tyon.Report.profileSettings
        b[1] = UInt8(Tyon.Report.profileSettingsSize)
        b[2] = UInt8(profileIndex)
        b[3] = advancedSensitivity ? 1 : 0
        b[4] = UInt8(min(max(sensitivityX, Tyon.sensitivityMin), Tyon.sensitivityMax))
        b[5] = UInt8(min(max(advancedSensitivity ? sensitivityY : sensitivityX, Tyon.sensitivityMin), Tyon.sensitivityMax))
        b[6] = cpiLevelsEnabled & 0x1f
        for i in 0..<Tyon.cpiLevelCount { b[7 + i] = Tyon.byteFromCPI(cpiLevels[i]) }
        b[12] = UInt8(min(max(cpiActive, 0), Tyon.cpiLevelCount - 1))
        b[13] = ((talkFXEnabled ? 0 : 1) << 4) | (pollingRateRaw & 0x0f)
        b[14] = lightsEnabledRaw
        b[15] = colorFlowRaw
        b[16] = lightEffectRaw
        b[17] = UInt8(min(max(effectSpeed, 1), 3))
        for i in 0..<2 {
            let o = 18 + i * 5
            b[o] = lights[i].index
            b[o + 1] = lights[i].color.red
            b[o + 2] = lights[i].color.green
            b[o + 3] = lights[i].color.blue
            b[o + 4] = lights[i].unused
        }
        let sum = Self.checksum(b)
        b[28] = UInt8(sum & 0xff)
        b[29] = UInt8(sum >> 8)
        return b
    }
}

// MARK: - Profile buttons (report 0x07, 99 bytes)

struct ButtonAssignment: Equatable, Codable {
    var type: UInt8
    var modifier: UInt8
    var key: UInt8

    static let unused = ButtonAssignment(type: 0x00, modifier: 0, key: 0)
}

struct ProfileButtons: Equatable, Codable {
    var buttons: [ButtonAssignment]   // 32 entries, see TyonButton for the slot order

    init(bytes b: [UInt8], expectedProfile: Int) throws {
        let n = Tyon.Report.profileButtonsSize
        guard b.count == n else { throw TyonError.badResponse("button map was \(b.count) bytes, expected \(n)") }
        guard b[0] == Tyon.Report.profileButtons else { throw TyonError.badResponse("button map had report id 0x\(String(b[0], radix: 16))") }
        guard b[1] == UInt8(n) else { throw TyonError.badResponse("button map size byte was \(b[1])") }
        guard Int(b[2]) == expectedProfile else { throw TyonError.badResponse("asked for profile \(expectedProfile + 1) but got profile \(Int(b[2]) + 1)") }
        buttons = (0..<Tyon.buttonCount).map { i in
            let o = 3 + i * 3
            return ButtonAssignment(type: b[o], modifier: b[o + 1], key: b[o + 2])
        }
    }

    func encoded(profileIndex: Int) -> [UInt8] {
        precondition((0..<Tyon.profileCount).contains(profileIndex))
        precondition(buttons.count == Tyon.buttonCount)
        var b = [UInt8](repeating: 0, count: Tyon.Report.profileButtonsSize)
        b[0] = Tyon.Report.profileButtons
        b[1] = UInt8(Tyon.Report.profileButtonsSize)
        b[2] = UInt8(profileIndex)
        for (i, btn) in buttons.enumerated() {
            let o = 3 + i * 3
            b[o] = btn.type; b[o + 1] = btn.modifier; b[o + 2] = btn.key
        }
        return b
    }
}

/// Physical button slots. Slot + 16 is the same button in the Easy-Shift[+] layer.
enum TyonButton: Int, CaseIterable, Identifiable {
    case left = 0, right, middle
    case thumbBack, thumbForward, thumbPedal
    case paddleUp, paddleDown
    case leftBack, leftForward, rightBack, rightForward
    case finRight, finLeft
    case wheelUp, wheelDown

    var id: Int { rawValue }
    var name: String {
        switch self {
        case .left: return "Left click"
        case .right: return "Right click"
        case .middle: return "Wheel click"
        case .thumbBack: return "Thumb back"
        case .thumbForward: return "Thumb forward"
        case .thumbPedal: return "Thumb pedal"
        case .paddleUp: return "X-Celerator paddle up"
        case .paddleDown: return "X-Celerator paddle down"
        case .leftBack: return "Left top back"
        case .leftForward: return "Left top forward"
        case .rightBack: return "Right top back"
        case .rightForward: return "Right top forward"
        case .finRight: return "Fin switch right"
        case .finLeft: return "Fin switch left"
        case .wheelUp: return "Wheel up"
        case .wheelDown: return "Wheel down"
        }
    }
    var group: String {
        switch self {
        case .left, .right, .middle, .wheelUp, .wheelDown: return "Main"
        case .thumbBack, .thumbForward, .thumbPedal, .paddleUp, .paddleDown: return "Thumb"
        case .leftBack, .leftForward, .rightBack, .rightForward: return "Top"
        case .finRight, .finLeft: return "Fin"
        }
    }
}

/// Button function codes the firmware understands (TyonButtonType).
struct ButtonFunction: Identifiable, Hashable {
    let code: UInt8
    let name: String
    let group: String
    var id: UInt8 { code }

    static let shortcut: UInt8 = 0x05
    static let macro: UInt8 = 0x30
    static let macAction: UInt8 = 0x0f   // firmware "quick launch": reported to the app, nothing sent to the OS
    static let unusedCode: UInt8 = 0x00

    static let all: [ButtonFunction] = [
        .init(code: 0x00, name: "Unused", group: "Basic"),
        .init(code: 0x01, name: "Click (left)", group: "Basic"),
        .init(code: 0x02, name: "Menu (right click)", group: "Basic"),
        .init(code: 0x03, name: "Universal scrolling (middle)", group: "Basic"),
        .init(code: 0x04, name: "Double click", group: "Basic"),
        .init(code: 0x05, name: "Keyboard shortcut…", group: "Basic"),
        .init(code: 0x06, name: "Disabled", group: "Basic"),
        .init(code: 0x07, name: "Browser forward", group: "Basic"),
        .init(code: 0x08, name: "Browser back", group: "Basic"),
        .init(code: 0x09, name: "Tilt left", group: "Scrolling"),
        .init(code: 0x0a, name: "Tilt right", group: "Scrolling"),
        .init(code: 0x0d, name: "Scroll up", group: "Scrolling"),
        .init(code: 0x0e, name: "Scroll down", group: "Scrolling"),
        .init(code: 0x0f, name: "Mac action (Tyon Control)", group: "System"),
        .init(code: 0x10, name: "Profile cycle", group: "Profile"),
        .init(code: 0x11, name: "Profile up", group: "Profile"),
        .init(code: 0x12, name: "Profile down", group: "Profile"),
        .init(code: 0x14, name: "DPI cycle", group: "DPI"),
        .init(code: 0x15, name: "DPI up", group: "DPI"),
        .init(code: 0x16, name: "DPI down", group: "DPI"),
        .init(code: 0x17, name: "Sensitivity cycle", group: "DPI"),
        .init(code: 0x18, name: "Sensitivity up", group: "DPI"),
        .init(code: 0x19, name: "Sensitivity down", group: "DPI"),
        .init(code: 0x1a, name: "Windows / Command key", group: "System"),
        .init(code: 0x1b, name: "Open driver", group: "System"),
        .init(code: 0x20, name: "Open media player", group: "Media"),
        .init(code: 0x21, name: "Previous track", group: "Media"),
        .init(code: 0x22, name: "Next track", group: "Media"),
        .init(code: 0x23, name: "Play / pause", group: "Media"),
        .init(code: 0x24, name: "Stop", group: "Media"),
        .init(code: 0x25, name: "Mute", group: "Media"),
        .init(code: 0x26, name: "Volume up", group: "Media"),
        .init(code: 0x27, name: "Volume down", group: "Media"),
        .init(code: 0x30, name: "Macro (stored on mouse)", group: "Advanced"),
        .init(code: 0x31, name: "Timer start", group: "Advanced"),
        .init(code: 0x32, name: "Timer stop", group: "Advanced"),
        .init(code: 0x33, name: "Easy-Aim: DPI stage 1", group: "Easy-Aim"),
        .init(code: 0x34, name: "Easy-Aim: DPI stage 2", group: "Easy-Aim"),
        .init(code: 0x35, name: "Easy-Aim: DPI stage 3", group: "Easy-Aim"),
        .init(code: 0x36, name: "Easy-Aim: DPI stage 4", group: "Easy-Aim"),
        .init(code: 0x37, name: "Easy-Aim: DPI stage 5", group: "Easy-Aim"),
        .init(code: 0x41, name: "Easy-Shift[+] (self)", group: "Easy-Shift"),
        .init(code: 0x42, name: "Easy-Wheel: sensitivity", group: "Easy-Wheel"),
        .init(code: 0x43, name: "Easy-Wheel: profile", group: "Easy-Wheel"),
        .init(code: 0x44, name: "Easy-Wheel: DPI", group: "Easy-Wheel"),
        .init(code: 0x45, name: "Easy-Wheel: volume", group: "Easy-Wheel"),
        .init(code: 0x46, name: "Easy-Wheel: Alt+Tab", group: "Easy-Wheel"),
        .init(code: 0x47, name: "Easy-Wheel: Aero Flip 3D", group: "Easy-Wheel"),
        .init(code: 0x51, name: "Easy-Shift[+] (other devices)", group: "Easy-Shift"),
        .init(code: 0x52, name: "Easy-Shift[+] lock (other devices)", group: "Easy-Shift"),
        .init(code: 0x53, name: "Easy-Shift[+] (all)", group: "Easy-Shift"),
        .init(code: 0x86, name: "Home", group: "Keys"),
        .init(code: 0x87, name: "End", group: "Keys"),
        .init(code: 0x88, name: "Page up", group: "Keys"),
        .init(code: 0x89, name: "Page down", group: "Keys"),
        .init(code: 0x8a, name: "Left Ctrl", group: "Keys"),
        .init(code: 0x8b, name: "Left Alt / Option", group: "Keys"),
    ]

    static let groups: [String] = ["Basic", "Scrolling", "DPI", "Easy-Aim", "Profile", "Media", "Keys", "Easy-Shift", "Easy-Wheel", "System", "Advanced"]

    static func named(_ code: UInt8) -> ButtonFunction? { all.first { $0.code == code } }

    /// Gamepad-emulation codes (0x60-0x85) and anything else we don't name.
    static func describe(_ code: UInt8) -> String {
        if let f = named(code) { return f.name }
        if (0x60...0x73).contains(code) { return String(format: "XInput control 0x%02X", code) }
        if (0x74...0x85).contains(code) { return String(format: "DirectInput control 0x%02X", code) }
        return String(format: "Unknown function 0x%02X", code)
    }
}

/// Modifier bits used by the Shortcut button type.
struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt8
    static let shift = ShortcutModifiers(rawValue: 1 << 1)
    static let control = ShortcutModifiers(rawValue: 1 << 2)
    static let alt = ShortcutModifiers(rawValue: 1 << 3)
    static let command = ShortcutModifiers(rawValue: 1 << 4)   // "Win" key

    var label: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.alt) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

/// USB HID keyboard usage IDs (page 0x07) with display names.
enum HIDKey {
    static let names: [(UInt8, String)] = {
        var t: [(UInt8, String)] = []
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() { t.append((UInt8(0x04 + i), String(c).uppercased())) }
        for i in 1...9 { t.append((UInt8(0x1d + i), "\(i)")) }
        t.append((0x27, "0"))
        t += [(0x28, "Return"), (0x29, "Escape"), (0x2a, "Delete (Backspace)"), (0x2b, "Tab"), (0x2c, "Space"),
              (0x2d, "-"), (0x2e, "="), (0x2f, "["), (0x30, "]"), (0x31, "\\"), (0x33, ";"), (0x34, "'"),
              (0x35, "`"), (0x36, ","), (0x37, "."), (0x38, "/"), (0x39, "Caps Lock")]
        for i in 1...12 { t.append((UInt8(0x39 + i), "F\(i)")) }
        t += [(0x46, "Print Screen"), (0x47, "Scroll Lock"), (0x48, "Pause"), (0x49, "Insert"), (0x4a, "Home"),
              (0x4b, "Page Up"), (0x4c, "Forward Delete"), (0x4d, "End"), (0x4e, "Page Down"),
              (0x4f, "Right Arrow"), (0x50, "Left Arrow"), (0x51, "Down Arrow"), (0x52, "Up Arrow"),
              (0x53, "Num Lock / Clear"), (0x54, "Keypad /"), (0x55, "Keypad *"), (0x56, "Keypad -"), (0x57, "Keypad +"),
              (0x58, "Keypad Enter")]
        for i in 1...9 { t.append((UInt8(0x58 + i), "Keypad \(i)")) }
        t += [(0x62, "Keypad 0"), (0x63, "Keypad ."), (0x65, "Application (Menu)")]
        for i in 13...24 { t.append((UInt8(0x68 + i - 13), "F\(i)")) }
        t += [(0xe0, "Left Control"), (0xe1, "Left Shift"), (0xe2, "Left Alt / Option"), (0xe3, "Left Command"),
              (0xe4, "Right Control"), (0xe5, "Right Shift"), (0xe6, "Right Alt / Option"), (0xe7, "Right Command")]
        return t
    }()

    static func name(_ usage: UInt8) -> String {
        names.first { $0.0 == usage }?.1 ?? String(format: "Key 0x%02X", usage)
    }
}

// MARK: - Other reports

struct DeviceInfoReport {
    let firmwareVersion: UInt8
    let dfuVersion: UInt8
    var firmwareString: String { Tyon.firmwareString(firmwareVersion) }

    init(bytes b: [UInt8]) throws {
        guard b.count == Tyon.Report.infoSize, b[0] == Tyon.Report.info else {
            throw TyonError.badResponse("info report was \(b.count) bytes with id 0x\(String(b.first ?? 0, radix: 16))")
        }
        firmwareVersion = b[2]
        dfuVersion = b[3]
    }
}

struct ControlUnit: Equatable {
    var dcu: UInt8       // LiftOffDistance raw
    var tcu: UInt8       // 0 off, 1 on
    var median: UInt8    // surface calibration value
    var action: UInt8

    var liftOff: LiftOffDistance? { LiftOffDistance(rawValue: dcu) }
    var tcuOn: Bool { tcu == 1 }

    init(bytes b: [UInt8]) throws {
        guard b.count == Tyon.Report.controlUnitSize, b[0] == Tyon.Report.controlUnit, b[1] == UInt8(Tyon.Report.controlUnitSize) else {
            throw TyonError.badResponse("control unit report was \(b.count) bytes")
        }
        dcu = b[2]; tcu = b[3]; median = b[4]; action = b[5]
    }

    init(dcu: UInt8, tcu: UInt8, median: UInt8, action: UInt8) {
        self.dcu = dcu; self.tcu = tcu; self.median = median; self.action = action
    }

    var encoded: [UInt8] { [Tyon.Report.controlUnit, UInt8(Tyon.Report.controlUnitSize), dcu, tcu, median, action] }
}

/// Unsolicited 5-byte input report (id 0x03) the mouse sends on its misc interface
/// when something changes on the device itself (profile switch, DPI step, ...).
struct SpecialEvent {
    enum Kind {
        case profileChanged(Int)
        case cpiChanged(Int)
        case quickLaunch(slot: Int, pressed: Bool)   // a button set to the "Mac action" firmware type
        case other(UInt8)
    }
    let kind: Kind

    init?(bytes b: [UInt8]) {
        guard b.count >= 5, b[0] == Tyon.Report.special else { return nil }
        switch b[2] {
        case 0x20: kind = .profileChanged(Int(b[3]))
        case 0xb0: kind = .cpiChanged(Int(b[3]))
        case 0x60:
            guard b[3] >= 1 else { return nil }
            kind = .quickLaunch(slot: Int(b[3]) - 1, pressed: b[4] == 0)   // data is 1-based, action 0 = press
        default: kind = .other(b[2])
        }
    }
}
