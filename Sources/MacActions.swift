// MacActions.swift
// Things the app can do on the Mac when a mouse button is pressed. The mouse firmware
// knows nothing about these; the app performs them by posting a fixed, whitelisted
// keystroke (needs Accessibility permission) or by launching a system app (no permission).

import AppKit
import ApplicationServices

enum MacAction: String, Codable, CaseIterable, Identifiable {
    case none
    case missionControl
    case appExpose
    case showDesktop
    case desktopLeft
    case desktopRight
    case launchpad
    case spotlight
    case nextProfile        // handled by the app: next profile in the configured cycle
    case previousProfile

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Do nothing"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé (windows of current app)"
        case .showDesktop: return "Show Desktop"
        case .desktopLeft: return "Previous desktop (space to the left)"
        case .desktopRight: return "Next desktop (space to the right)"
        case .launchpad: return "Launchpad / Apps"
        case .spotlight: return "Spotlight search"
        case .nextProfile: return "Next mouse profile in cycle"
        case .previousProfile: return "Previous mouse profile in cycle"
        }
    }

    /// Actions that only work once Accessibility access has been granted.
    var needsAccessibility: Bool {
        switch self {
        case .desktopLeft, .desktopRight, .spotlight: return true
        default: return false
        }
    }

    static var available: [MacAction] {
        allCases.filter { $0 != .launchpad || FileManager.default.fileExists(atPath: Self.launchpadPath) }
    }

    private static let missionControlPath = "/System/Applications/Mission Control.app"
    private static let launchpadPath = "/System/Applications/Launchpad.app"

    /// The macOS symbolic-hotkey id behind this action, if it is keystroke based.
    var systemHotkeyID: Int? {
        switch self {
        case .missionControl: return SystemHotkey.missionControl
        case .appExpose: return SystemHotkey.appWindows
        case .showDesktop: return SystemHotkey.showDesktop
        case .desktopLeft: return SystemHotkey.moveLeftSpace
        case .desktopRight: return SystemHotkey.moveRightSpace
        case .spotlight: return SystemHotkey.spotlight
        default: return nil
        }
    }

    /// Human-readable description of how the action will be carried out right now.
    var howItRuns: String {
        switch self {
        case .none, .nextProfile, .previousProfile: return ""
        case .launchpad: return "opens Launchpad"
        default:
            if let id = systemHotkeyID {
                if let combo = SystemHotkey.combo(id) {
                    if needsAccessibility && !Accessibility.granted { return "needs Accessibility to press \(SystemHotkey.describe(combo))" }
                    if !needsAccessibility && !Accessibility.granted { return "opens Mission Control.app" }
                    return "presses \(SystemHotkey.describe(combo))"
                }
                return needsAccessibility ? "shortcut disabled in System Settings → Keyboard" : "opens Mission Control.app (shortcut disabled)"
            }
            return ""
        }
    }

    func perform() {
        switch self {
        case .none, .nextProfile, .previousProfile:
            return
        case .launchpad:
            Self.launch(Self.launchpadPath)
        case .missionControl, .appExpose, .showDesktop:
            let fallbackArgs: [String] = self == .missionControl ? [] : (self == .appExpose ? ["2"] : ["1"])
            if Accessibility.granted, let id = systemHotkeyID, let combo = SystemHotkey.combo(id) {
                NSLog("TyonControl: %@ → key %@", rawValue, SystemHotkey.describe(combo))
                SystemHotkey.post(combo)
            } else {
                NSLog("TyonControl: %@ → Mission Control.app %@", rawValue, fallbackArgs.joined())
                Self.launch(Self.missionControlPath, arguments: fallbackArgs)
            }
        case .desktopLeft, .desktopRight, .spotlight:
            guard Accessibility.granted else { NSLog("TyonControl: %@ skipped – no Accessibility access", rawValue); return }
            guard let id = systemHotkeyID, let combo = SystemHotkey.combo(id) else { NSLog("TyonControl: %@ skipped – system shortcut disabled", rawValue); return }
            NSLog("TyonControl: %@ → key %@", rawValue, SystemHotkey.describe(combo))
            SystemHotkey.post(combo)
        }
    }

    private static func launch(_ path: String, arguments: [String] = []) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error { NSLog("TyonControl: could not launch %@: %@", path, error.localizedDescription) }
        }
    }
}

enum Accessibility {
    static var granted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (once) and opens the Accessibility pane.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
