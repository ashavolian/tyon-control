// SystemHotkey.swift
// Resolves the keyboard shortcuts macOS has configured for Mission Control and friends
// (System Settings → Keyboard → Keyboard Shortcuts → Mission Control) so the app posts
// exactly the combination the system expects, including the Fn/keypad flags real arrow keys carry.

import AppKit
import CoreGraphics

enum SystemHotkey {
    struct Combo: Equatable {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    // Symbolic hotkey ids and their factory defaults (keycode, Carbon modifier mask).
    static let missionControl = 32
    static let appWindows = 33
    static let showDesktop = 36
    static let moveLeftSpace = 79
    static let moveRightSpace = 81
    static let spotlight = 64

    private static let factoryDefaults: [Int: (CGKeyCode, UInt64)] = [
        32: (126, 0x840000),   // ⌃↑
        33: (125, 0x840000),   // ⌃↓
        36: (103, 0x800000),   // F11
        79: (123, 0x840000),   // ⌃←
        81: (124, 0x840000),   // ⌃→
        64: (49, 0x100000),    // ⌘Space
    ]

    /// The combination currently assigned, or nil when the user disabled that shortcut.
    static func combo(_ id: Int) -> Combo? {
        let fallback = factoryDefaults[id].map { Combo(keyCode: $0.0, flags: adjusted(CGEventFlags(rawValue: $0.1), key: $0.0)) }
        guard let table = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = table["\(id)"] as? [String: Any] else { return fallback }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return nil }
        if let value = entry["value"] as? [String: Any],
           let params = value["parameters"] as? [Any], params.count >= 3,
           let key = (params[1] as? NSNumber)?.intValue, let mods = (params[2] as? NSNumber)?.uint64Value,
           key >= 0, key < 0xffff {
            let code = CGKeyCode(key)
            return Combo(keyCode: code, flags: adjusted(CGEventFlags(rawValue: mods), key: code))
        }
        return fallback
    }

    private static func adjusted(_ flags: CGEventFlags, key: CGKeyCode) -> CGEventFlags {
        var f = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn, .maskNumericPad])
        if (123...126).contains(key) { f.insert(.maskNumericPad); f.insert(.maskSecondaryFn) }   // arrow keys
        if (96...111).contains(key) || key == 103 || key == 118 || key == 120 || key == 122 || key == 99 || key == 97 || key == 100 || key == 101 || key == 109 { f.insert(.maskSecondaryFn) } // F-keys
        return f
    }

    /// Posts the combination as a real keyboard would: modifiers down, key, modifiers up.
    static func post(_ combo: Combo) {
        let source = CGEventSource(stateID: .combinedSessionState)
        if let source = source {
            // Don't let our synthetic keystroke make macOS ignore the real mouse for 250 ms afterwards.
            source.localEventsSuppressionInterval = 0
        }
        let modifierKeys: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskShift, 56), (.maskAlternate, 58), (.maskCommand, 55)]
        var held: CGEventFlags = []
        for (flag, code) in modifierKeys where combo.flags.contains(flag) {
            held.insert(flag)
            if let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) { e.flags = held; e.post(tap: .cghidEventTap) }
            usleep(3000)
        }
        if let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false) {
            down.flags = combo.flags
            up.flags = combo.flags
            down.post(tap: .cghidEventTap)
            usleep(3000)
            up.post(tap: .cghidEventTap)
            usleep(3000)
        }
        for (flag, code) in modifierKeys.reversed() where combo.flags.contains(flag) {
            held.remove(flag)
            if let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) { e.flags = held; e.post(tap: .cghidEventTap) }
            usleep(3000)
        }
    }

    static func describe(_ combo: Combo) -> String {
        var s = ""
        if combo.flags.contains(.maskControl) { s += "⌃" }
        if combo.flags.contains(.maskAlternate) { s += "⌥" }
        if combo.flags.contains(.maskShift) { s += "⇧" }
        if combo.flags.contains(.maskCommand) { s += "⌘" }
        return s + keyName(combo.keyCode)
    }

    private static func keyName(_ k: CGKeyCode) -> String {
        let names: [CGKeyCode: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "Delete",
                                          122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
                                          105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"]
        if let n = names[k] { return n }
        let letters: [CGKeyCode: String] = [0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
                                            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9"]
        return letters[k] ?? "key \(k)"
    }
}
