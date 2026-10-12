// Checks the read-only half of surface calibration: trigger a sensor frame and read the 30x30 image.
import Foundation
let transport = HIDTransport()
let connected = DispatchSemaphore(value: 0)
transport.onEvent = { e in if case .connected = e { connected.signal() } }
transport.start()
if !transport.isConnected { _ = connected.wait(timeout: .now() + 3) }
guard transport.isConnected else { print("not connected"); exit(1) }
let dev = TyonDevice(transport: transport)
do {
    let cu = try dev.readControlUnit()
    print("control unit before: dcu=\(cu.dcu) tcu=\(cu.tcu) median=\(cu.median)")
    for i in 1...3 {
        let s = try dev.sampleSurface()
        let nonzero = s.pixels.filter { $0 != 0 }.count
        print("frame \(i): median=\(s.median) nonzero pixels=\(nonzero)/900 min=\(s.pixels.min()!) max=\(s.pixels.max()!)")
    }
    let after = try dev.readControlUnit()
    print("control unit after (must be unchanged): dcu=\(after.dcu) tcu=\(after.tcu) median=\(after.median) -> \(after == cu ? "unchanged ✓" : "CHANGED ✗")")
} catch { print("ERROR:", error.localizedDescription); exit(2) }
transport.stop()
