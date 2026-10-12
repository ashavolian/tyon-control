// ScrollReverser.swift
// Reverses scroll direction for line-based (mouse wheel) scroll events only, leaving the
// trackpad's continuous scrolling alone. macOS offers no per-device setting for this.
// Uses one scroll-wheel-only event tap that needs Accessibility access.

import AppKit
import CoreGraphics

final class ScrollReverser {
    var enabled = false { didSet { sync() } }
    var horizontal = true

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isActive: Bool { tap != nil && enabled }

    /// Creates or enables the tap when wanted and possible; disables it otherwise.
    func sync() {
        if enabled {
            if tap == nil {
                guard Accessibility.granted else { return }
                let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
                let ctx = Unmanaged.passUnretained(self).toOpaque()
                guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                                eventsOfInterest: mask, callback: { _, type, event, refcon in
                    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<ScrollReverser>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
                }, userInfo: ctx) else {
                    NSLog("TyonControl: could not create scroll event tap")
                    return
                }
                tap = t
                let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
                source = s
                CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            }
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        } else if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
        }
    }

    func shutdown() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if enabled, let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, enabled,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {   // continuous = trackpad
            return Unmanaged.passUnretained(event)
        }
        flip(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1)
        if horizontal {
            flip(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)
        }
        return Unmanaged.passUnretained(event)
    }

    private func flip(_ e: CGEvent, _ delta: CGEventField, _ point: CGEventField, _ fixed: CGEventField) {
        e.setIntegerValueField(delta, value: -e.getIntegerValueField(delta))
        e.setIntegerValueField(point, value: -e.getIntegerValueField(point))
        e.setDoubleValueField(fixed, value: -e.getDoubleValueField(fixed))
    }
}
