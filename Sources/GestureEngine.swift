// GestureEngine.swift
// Turns button events from the mouse into Mac actions. One button can act like the
// MX Master "gesture button": click it for one action, or hold it and move the mouse
// left / right / up / down for four more. Other buttons can trigger a single action.

import AppKit
import CoreGraphics
import Combine

/// Still exported by CoreGraphics but hidden from Swift as deprecated. After a cursor warp or a
/// synthetic event macOS ignores hardware mouse input for this interval (0.25 s by default), which
/// would swallow the swipe; KVM tools such as Barrier/Deskflow set it to 0 for the same reason.
@_silgen_name("CGSetLocalEventsSuppressionInterval")
private func cgSetLocalEventsSuppressionInterval(_ seconds: CFTimeInterval) -> CGError

struct GestureConfig: Codable, Equatable {
    var enabled = true
    var gestureButton: Int? = nil                 // slot 0-15 (normal layer) or 16-31 (Easy-Shift layer)
    var clickAction: MacAction = .missionControl
    var swipeLeft: MacAction = .desktopLeft
    var swipeRight: MacAction = .desktopRight
    var swipeUp: MacAction = .missionControl
    var swipeDown: MacAction = .appExpose
    var plainActions: [Int: MacAction] = [:]      // slot -> action for ordinary buttons
    var freezePointer = true
    var swipeThreshold: Double = 80               // pixels of movement that count as a swipe
    var macProfile: Int? = nil                    // profile that gets the firmware mapping (nil = pick automatically)

    private static let defaultsKey = "TyonControl.gestureConfig"

    static func load() -> GestureConfig {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var cfg = try? JSONDecoder().decode(GestureConfig.self, from: data) else { return GestureConfig() }
        if let g = cfg.gestureButton, !(0..<Tyon.buttonCount).contains(g) { cfg.gestureButton = nil }
        cfg.plainActions = cfg.plainActions.filter { (0..<Tyon.buttonCount).contains($0.key) && $0.value != .none }
        cfg.swipeThreshold = min(max(cfg.swipeThreshold, 20), 400)
        if let p = cfg.macProfile, !(0..<Tyon.profileCount).contains(p) { cfg.macProfile = nil }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Every slot that needs the firmware "Mac action" mapping.
    var slotsNeedingFirmwareMapping: [Int] {
        var slots = Set(plainActions.filter { $0.value != .none }.keys)
        if let g = gestureButton { slots.insert(g) }
        return slots.sorted()
    }
}

final class GestureEngine: ObservableObject {
    @Published var config: GestureConfig {
        didSet { if config != oldValue { config.save() } }
    }
    @Published private(set) var lastEvent = "No button events received yet"
    @Published private(set) var lastEventSlot: Int?
    @Published private(set) var isGesturing = false
    @Published private(set) var liveDelta = CGSize.zero
    @Published private(set) var lastGesture = "–"
    @Published private(set) var holdMethod = "–"

    /// Set by the app model: performs "next/previous profile in cycle" (needs device access).
    var profileSwitchHandler: ((_ forward: Bool) -> Void)?

    private var holdStart: Date?
    private var dx = 0.0
    private var dy = 0.0
    private var consumed = false
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var watchdog: DispatchWorkItem?
    private var pointerFrozen = false

    // Event tap (needs Accessibility): lets a background app read mouse deltas and keep the
    // pointer still by swallowing movement events. Created once, enabled only while gesturing.
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var tapActive = false
    private var anchor: CGPoint?          // where the pointer was when the hold started
    private var suppressionDisabled = false

    init() {
        config = GestureConfig.load()
    }

    deinit { unfreezePointer() }

    // MARK: Input from the mouse (main thread)

    func handle(button slot: Int, pressed: Bool) {
        guard (0..<Tyon.buttonCount).contains(slot) else { return }
        lastEventSlot = slot
        lastEvent = "\(pressed ? "Pressed" : "Released") \(TyonButton.slotName(slot))"
        guard config.enabled else { return }

        if slot == config.gestureButton {
            if pressed { beginGesture() } else { endGesture() }
        } else if pressed, let action = config.plainActions[slot], action != .none {
            run(action)
            lastGesture = "\(TyonButton.slotName(slot)) → \(action.label)"
        }
    }

    // MARK: Gesture tracking

    private func ensureTap() -> Bool {
        if tap != nil { return true }
        guard Accessibility.granted else { return false }
        let mask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue) | (1 << CGEventType.otherMouseDragged.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<GestureEngine>.fromOpaque(refcon).takeUnretainedValue().handleTap(type: type, event: event)
        }, userInfo: ctx) else {
            NSLog("TyonControl: could not create mouse event tap")
            return false
        }
        tap = t
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: false)
        return true
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap, tapActive { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard isGesturing, tapActive else { return Unmanaged.passUnretained(event) }
        accumulate(event.getDoubleValueField(.mouseEventDeltaX), event.getDoubleValueField(.mouseEventDeltaY))
        return config.freezePointer ? nil : Unmanaged.passUnretained(event)
    }

    private func beginGesture() {
        guard !isGesturing else { return }
        isGesturing = true
        holdStart = Date()
        dx = 0; dy = 0
        consumed = false
        liveDelta = .zero

        let wd = DispatchWorkItem { [weak self] in self?.endGesture(timedOut: true) }
        watchdog = wd
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: wd)

        if config.freezePointer {
            // Warping the pointer normally makes macOS ignore hardware mouse input for a moment;
            // switch that off once so snapping the pointer back doesn't eat the swipe.
            if !suppressionDisabled {
                _ = cgSetLocalEventsSuppressionInterval(0.0)
                suppressionDisabled = true
            }
            anchor = CGEvent(source: nil)?.location
            // Only honoured while this app is frontmost, but harmless otherwise.
            CGAssociateMouseAndMouseCursorPosition(0)
            pointerFrozen = true
        }

        // Preferred path: the event tap sees every movement (and swallows it while freezing)
        // no matter which app is in front.
        if ensureTap(), let t = tap {
            tapActive = true
            CGEvent.tapEnable(tap: t, enable: true)
            holdMethod = config.freezePointer ? "event tap + snap-back" : "event tap (pointer free)"
            return
        }

        holdMethod = config.freezePointer ? "monitors + snap-back (no Accessibility)" : "monitors (pointer free)"
        // Fallback without Accessibility: movement comes from global/local mouse-moved monitors.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.accumulate(e.deltaX, e.deltaY) }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.accumulate(e.deltaX, e.deltaY); return e }) {
            monitors.append(l)
        }
        if !config.freezePointer {
            var last = NSEvent.mouseLocation
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                let now = NSEvent.mouseLocation
                let ddx = now.x - last.x, ddy = last.y - now.y   // screen y grows upward; swipe "down" should be positive
                last = now
                if ddx != 0 || ddy != 0 { self?.accumulate(ddx, ddy, fromPoll: true) }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    private var monitorSawMovement = false

    private func accumulate(_ ddx: CGFloat, _ ddy: CGFloat, fromPoll: Bool = false) {
        guard isGesturing else { return }
        if fromPoll {
            // Only trust polling when the event monitors are silent, so movement isn't counted twice.
            if monitorSawMovement { return }
        } else if ddx != 0 || ddy != 0 {
            monitorSawMovement = true
        }
        dx += Double(ddx)
        dy += Double(ddy)
        liveDelta = CGSize(width: dx, height: dy)
        if config.freezePointer, let a = anchor {
            CGWarpMouseCursorPosition(a)   // undo any drift the system let through
        }
        guard !consumed else { return }
        let t = config.swipeThreshold
        guard abs(dx) >= t || abs(dy) >= t else { return }
        consumed = true
        let horizontal = abs(dx) >= abs(dy)
        let action: MacAction
        let name: String
        if horizontal {
            action = dx > 0 ? config.swipeRight : config.swipeLeft
            name = dx > 0 ? "Swipe right" : "Swipe left"
        } else {
            action = dy > 0 ? config.swipeDown : config.swipeUp
            name = dy > 0 ? "Swipe down" : "Swipe up"
        }
        lastGesture = "\(name) → \(action.label)"
        run(action)
    }

    private func run(_ action: MacAction) {
        switch action {
        case .nextProfile: profileSwitchHandler?(true)
        case .previousProfile: profileSwitchHandler?(false)
        default: action.perform()
        }
    }

    private func endGesture(timedOut: Bool = false) {
        guard isGesturing else { return }
        if tapActive, let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            tapActive = false
        }
        pollTimer?.invalidate(); pollTimer = nil
        watchdog?.cancel(); watchdog = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        monitorSawMovement = false
        unfreezePointer()
        if let a = anchor { CGWarpMouseCursorPosition(a) }
        anchor = nil
        isGesturing = false
        if !timedOut, !consumed, let start = holdStart, Date().timeIntervalSince(start) < 0.6 {
            lastGesture = "Click → \(config.clickAction.label)"
            run(config.clickAction)
        }
    }

    /// Always safe to call; makes sure the pointer is never left frozen or intercepted.
    func unfreezePointer() {
        if pointerFrozen {
            CGAssociateMouseAndMouseCursorPosition(1)
            pointerFrozen = false
        }
        if tapActive, let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            tapActive = false
        }
    }
}

extension TyonButton {
    /// Name for a 0-31 button slot (16-31 are the Easy-Shift layer).
    static func slotName(_ slot: Int) -> String {
        if slot < Tyon.physicalButtonCount, let b = TyonButton(rawValue: slot) { return b.name }
        if let b = TyonButton(rawValue: slot - Tyon.physicalButtonCount) { return "Easy-Shift + \(b.name)" }
        return "Button \(slot + 1)"
    }
}
