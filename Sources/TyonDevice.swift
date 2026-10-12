// TyonDevice.swift
// High-level operations on the mouse: read/write profiles, switch profiles,
// lift-off distance and surface calibration. Every write is followed by the
// CONTROL handshake the firmware expects (poll report 0x04 until it says OK).
//
// Deliberately NOT implemented: macro upload (0x08), sensor firmware / SROM (0x0d),
// firmware update (0x1a/0x1b), sensor register writes, and device reset.

import Foundation

final class TyonDevice {
    let transport: HIDTransport
    private let lock = NSLock()   // one logical operation at a time (select + read must not interleave)

    init(transport: HIDTransport) {
        self.transport = transport
    }

    // MARK: Handshake

    /// Poll the CONTROL report until the firmware reports OK (mirrors roccat_check_write).
    private func waitReady(initialWait: TimeInterval = 0.2, busyWait: TimeInterval = 0.5, maxPolls: Int = 8) throws {
        Thread.sleep(forTimeInterval: initialWait)
        var wait = busyWait
        for _ in 0..<maxPolls {
            let c = try transport.getFeature(reportID: Tyon.Report.control, length: Tyon.Report.controlSize)
            switch c[1] {
            case Tyon.ControlStatus.ok:
                return
            case Tyon.ControlStatus.busy:
                Thread.sleep(forTimeInterval: wait)
                wait += busyWait
            case Tyon.ControlStatus.critical1, Tyon.ControlStatus.critical2:
                throw TyonError.deviceStatus("critical status \(c[1])")
            case Tyon.ControlStatus.invalid:
                throw TyonError.deviceStatus("invalid data")
            default:
                throw TyonError.deviceStatus("unknown status \(c[1])")
            }
        }
        throw TyonError.timeout("mouse stayed busy")
    }

    private func write(_ data: [UInt8]) throws {
        try transport.setFeature(data)
        try waitReady()
    }

    /// Tell the firmware which profile's data the next read of `request` should return.
    private func select(profile: Int, request: UInt8, dataIndex: UInt8 = 0) throws {
        precondition((0..<Tyon.profileCount).contains(profile))
        try write([Tyon.Report.control, dataIndex | UInt8(profile), request])
    }

    // MARK: Device info

    func readInfo() throws -> DeviceInfoReport {
        lock.lock(); defer { lock.unlock() }
        return try DeviceInfoReport(bytes: transport.getFeature(reportID: Tyon.Report.info, length: Tyon.Report.infoSize))
    }

    // MARK: Active profile

    func readActiveProfile() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let b = try transport.getFeature(reportID: Tyon.Report.profile, length: Tyon.Report.profileSize)
        guard b[1] == UInt8(Tyon.Report.profileSize), b[2] < UInt8(Tyon.profileCount) else {
            throw TyonError.badResponse("active profile report \(b)")
        }
        return Int(b[2])
    }

    func writeActiveProfile(_ index: Int) throws {
        precondition((0..<Tyon.profileCount).contains(index))
        lock.lock(); defer { lock.unlock() }
        try write([Tyon.Report.profile, UInt8(Tyon.Report.profileSize), UInt8(index)])
    }

    // MARK: Profile settings

    func readProfileSettings(_ index: Int) throws -> ProfileSettings {
        lock.lock(); defer { lock.unlock() }
        try select(profile: index, request: Tyon.ControlRequest.profileSettings)
        let b = try transport.getFeature(reportID: Tyon.Report.profileSettings, length: Tyon.Report.profileSettingsSize)
        return try ProfileSettings(bytes: b, expectedProfile: index)
    }

    func writeProfileSettings(_ settings: ProfileSettings, profile index: Int) throws {
        lock.lock(); defer { lock.unlock() }
        try write(settings.encoded(profileIndex: index))
    }

    // MARK: Profile buttons

    func readProfileButtons(_ index: Int) throws -> ProfileButtons {
        lock.lock(); defer { lock.unlock() }
        try select(profile: index, request: Tyon.ControlRequest.profileButtons)
        let b = try transport.getFeature(reportID: Tyon.Report.profileButtons, length: Tyon.Report.profileButtonsSize)
        return try ProfileButtons(bytes: b, expectedProfile: index)
    }

    func writeProfileButtons(_ buttons: ProfileButtons, profile index: Int) throws {
        lock.lock(); defer { lock.unlock() }
        try write(buttons.encoded(profileIndex: index))
    }

    // MARK: Device state

    /// Tells the firmware a driver is listening, so buttons of the "Mac action" type and
    /// profile / DPI changes are reported as events instead of being swallowed.
    func setDeviceState(on: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        try write([Tyon.Report.deviceState, UInt8(Tyon.Report.deviceStateSize), on ? 1 : 0])
    }

    // MARK: Control unit (lift-off distance + surface calibration)

    func readControlUnit() throws -> ControlUnit {
        lock.lock(); defer { lock.unlock() }
        return try ControlUnit(bytes: transport.getFeature(reportID: Tyon.Report.controlUnit, length: Tyon.Report.controlUnitSize))
    }

    /// Set the Distance Control Unit (lift-off distance). Mirrors "try" then "accept".
    func setLiftOffDistance(_ dcu: LiftOffDistance) throws {
        lock.lock(); defer { lock.unlock() }
        try write(ControlUnit(dcu: dcu.rawValue, tcu: 0xff, median: 0xff, action: Tyon.ControlUnitAction.undefined).encoded)
        try write(ControlUnit(dcu: dcu.rawValue, tcu: 0xff, median: 0xff, action: Tyon.ControlUnitAction.accept).encoded)
    }

    /// One Tracking Control Unit calibration sample: ask the sensor for a frame and return the median brightness.
    func sampleSurface() throws -> (median: UInt8, pixels: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        try write([Tyon.Report.sensor, Tyon.SensorAction.frameCapture, 1, 0])
        let img = try transport.getFeature(reportID: Tyon.Report.sensor, length: Tyon.Report.sensorImageSize)
        let pixels = Array(img[3..<(3 + Tyon.Report.sensorImagePixels)])
        let sum = pixels.reduce(0) { $0 + Int($1) }
        return (UInt8(sum / Tyon.Report.sensorImagePixels), pixels)
    }

    /// Apply a calibration value for testing (not yet persisted).
    func tcuTest(dcu: UInt8, median: UInt8) throws {
        lock.lock(); defer { lock.unlock() }
        try write(ControlUnit(dcu: dcu, tcu: 1, median: median, action: Tyon.ControlUnitAction.cancel).encoded)
    }

    /// Persist the tested calibration value.
    func tcuAccept(dcu: UInt8, median: UInt8) throws {
        lock.lock(); defer { lock.unlock() }
        try write(ControlUnit(dcu: dcu, tcu: 1, median: median, action: Tyon.ControlUnitAction.accept).encoded)
    }

    /// Abandon a test calibration.
    func tcuCancel(dcu: UInt8) throws {
        lock.lock(); defer { lock.unlock() }
        try write(ControlUnit(dcu: dcu, tcu: 1, median: 0, action: Tyon.ControlUnitAction.cancel).encoded)
    }

    /// Switch the Tracking Control Unit off.
    func tcuOff(dcu: UInt8) throws {
        lock.lock(); defer { lock.unlock() }
        try write(ControlUnit(dcu: dcu, tcu: 0, median: 0, action: Tyon.ControlUnitAction.off).encoded)
    }
}
