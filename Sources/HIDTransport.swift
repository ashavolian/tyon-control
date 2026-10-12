// HIDTransport.swift
// Finds the ROCCAT Tyon over IOKit HID and moves feature reports to and from it.
//
// The Tyon exposes four USB HID interfaces. Its vendor feature reports are declared
// on the mouse interface, but modern macOS refuses to open mouse/keyboard HID
// interfaces without Input Monitoring permission. The firmware answers the same
// feature reports on the joystick interface (usage page 1, usage 4), so we talk to
// that one. The misc interface (page 0x0a, usage 0) answers reads but drops writes,
// so it is only used to receive the mouse's unsolicited event reports.

import Foundation
import IOKit.hid

final class HIDTransport {
    enum Event {
        case connected
        case disconnected
        case special([UInt8])
    }

    /// Delivered on the main queue.
    var onEvent: ((Event) -> Void)?

    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    private let stateLock = NSLock()
    private let ioLock = NSLock()
    private var matched: [IOHIDDevice] = []
    private var controlDevice: IOHIDDevice?
    private var eventDevice: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    deinit { inputBuffer.deallocate() }

    var isConnected: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return controlDevice != nil
    }

    struct Identity {
        let product: String
        let productID: Int
        let serial: String?
    }

    var identity: Identity? {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let d = controlDevice else { return nil }
        return Identity(product: Self.property(d, kIOHIDProductKey) as? String ?? "ROCCAT Tyon",
                        productID: Self.property(d, kIOHIDProductIDKey) as? Int ?? 0,
                        serial: Self.property(d, kIOHIDSerialNumberKey) as? String)
    }

    // MARK: Lifecycle

    func start() {
        guard thread == nil else { return }
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [unowned self] in
            self.runLoop = CFRunLoopGetCurrent()
            self.setUpManager()
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "TyonControl.HID"
        t.qualityOfService = .userInitiated
        t.start()
        thread = t
        ready.wait()
    }

    func stop() {
        guard let rl = runLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue) { [self] in
            stateLock.lock()
            if let d = controlDevice { IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone)) }
            if let d = eventDevice, !isSame(d, controlDevice) { IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone)) }
            controlDevice = nil; eventDevice = nil; matched.removeAll()
            stateLock.unlock()
            if let m = manager {
                IOHIDManagerUnscheduleFromRunLoop(m, rl, CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            CFRunLoopStop(rl)
        }
        CFRunLoopWakeUp(rl)
        thread = nil
    }

    private func setUpManager() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = Tyon.productIDs.map { pid -> CFDictionary in
            [kIOHIDVendorIDKey: Tyon.vendorID, kIOHIDProductIDKey: pid] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(m, matching as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx = ctx else { return }
            Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue().deviceMatched(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            guard let ctx = ctx else { return }
            Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        // This returns kIOReturnNotPermitted on current macOS because the mouse and keyboard
        // interfaces need Input Monitoring. Matching still works; we open interfaces ourselves.
        _ = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
    }

    // MARK: Device bookkeeping (runs on the HID thread)

    private static func property(_ d: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(d, key as CFString)
    }

    private static func usage(_ d: IOHIDDevice) -> (page: Int, usage: Int) {
        (property(d, kIOHIDPrimaryUsagePageKey) as? Int ?? -1, property(d, kIOHIDPrimaryUsageKey) as? Int ?? -1)
    }

    private func isSame(_ a: IOHIDDevice?, _ b: IOHIDDevice?) -> Bool {
        guard let a = a, let b = b else { return false }
        return CFEqual(a, b)
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        stateLock.lock()
        if !matched.contains(where: { CFEqual($0, device) }) { matched.append(device) }
        stateLock.unlock()
        reselect()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        stateLock.lock()
        matched.removeAll { CFEqual($0, device) }
        var lostControl = false
        if isSame(controlDevice, device) {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            controlDevice = nil
            lostControl = true
        }
        if isSame(eventDevice, device) {
            if !lostControl { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
            eventDevice = nil
        }
        stateLock.unlock()
        if lostControl { emit(.disconnected) }
        reselect()
    }

    /// Pick (and open) the interfaces we need from whatever is currently matched.
    private func reselect() {
        stateLock.lock()
        defer { stateLock.unlock() }

        let joystick = matched.first { Self.usage($0) == (1, 4) }
        let misc = matched.first { Self.usage($0) == (10, 0) }

        var becameConnected = false
        if controlDevice == nil, let joystick = joystick {
            // Only the joystick interface reliably accepts SET_REPORT: the misc interface
            // answers reads but stalls or silently drops writes (verified on firmware 1.34).
            let r = IOHIDDeviceOpen(joystick, IOOptionBits(kIOHIDOptionsTypeNone))
            if r == kIOReturnSuccess {
                controlDevice = joystick
                becameConnected = true
            } else {
                NSLog("TyonControl: could not open control interface (0x%08x)", UInt32(bitPattern: r))
            }
        }

        if eventDevice == nil, let misc = misc {
            let alreadyOpen = isSame(misc, controlDevice)
            let r = alreadyOpen ? kIOReturnSuccess : IOHIDDeviceOpen(misc, IOOptionBits(kIOHIDOptionsTypeNone))
            if r == kIOReturnSuccess {
                eventDevice = misc
                let ctx = Unmanaged.passUnretained(self).toOpaque()
                IOHIDDeviceRegisterInputReportCallback(misc, inputBuffer, 64, { ctx, _, _, _, reportID, report, length in
                    guard let ctx = ctx, reportID == UInt32(Tyon.Report.special), length > 0 else { return }
                    let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
                    Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue().emit(.special(bytes))
                }, ctx)
            }
        }

        if becameConnected { emit(.connected) }
    }

    private func emit(_ event: Event) {
        guard let handler = onEvent else { return }
        DispatchQueue.main.async { handler(event) }
    }

    // MARK: Transfers (callable from any thread; serialized)

    /// The firmware answers a control request with a USB STALL while it is still busy
    /// (for example right after another host wrote to it). Treat that as "try again".
    private static let stallRetries = 4
    private static let stallBackoff: TimeInterval = 0.25
    private static let pipeStalled: IOReturn = IOReturn(bitPattern: 0xe0005000)   // kUSBHostReturnPipeStalled

    private static func isTransient(_ r: IOReturn) -> Bool {
        r == pipeStalled || r == kIOReturnNotResponding || r == kIOReturnBusy || r == kIOReturnTimeout
    }

    private func currentControlDevice() throws -> IOHIDDevice {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let d = controlDevice else { throw TyonError.notConnected }
        return d
    }

    /// Reads a feature report. `length` includes the report-id byte; the result starts with it.
    func getFeature(reportID: UInt8, length: Int) throws -> [UInt8] {
        let device = try currentControlDevice()
        ioLock.lock(); defer { ioLock.unlock() }
        var buffer = [UInt8](repeating: 0, count: length)
        var got = CFIndex(length)
        var r: IOReturn = kIOReturnSuccess
        for attempt in 0..<Self.stallRetries {
            buffer[0] = reportID
            got = CFIndex(length)
            r = buffer.withUnsafeMutableBufferPointer { p in
                IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), p.baseAddress!, &got)
            }
            if r == kIOReturnSuccess || !Self.isTransient(r) || attempt == Self.stallRetries - 1 { break }
            Thread.sleep(forTimeInterval: Self.stallBackoff * Double(attempt + 1))
        }
        guard r == kIOReturnSuccess else {
            throw TyonError.transfer(String(format: "Reading report 0x%02X", reportID), r)
        }
        guard got == length else {
            throw TyonError.badResponse(String(format: "report 0x%02X returned %ld of %d bytes", reportID, got, length))
        }
        return buffer
    }

    /// Writes a feature report. `data[0]` must be the report id.
    func setFeature(_ data: [UInt8]) throws {
        precondition(!data.isEmpty)
        let device = try currentControlDevice()
        ioLock.lock(); defer { ioLock.unlock() }
        var r: IOReturn = kIOReturnSuccess
        for attempt in 0..<Self.stallRetries {
            r = data.withUnsafeBufferPointer { p in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(data[0]), p.baseAddress!, CFIndex(data.count))
            }
            if r == kIOReturnSuccess || !Self.isTransient(r) || attempt == Self.stallRetries - 1 { break }
            Thread.sleep(forTimeInterval: Self.stallBackoff * Double(attempt + 1))
        }
        guard r == kIOReturnSuccess else {
            throw TyonError.transfer(String(format: "Writing report 0x%02X", data[0]), r)
        }
    }
}
