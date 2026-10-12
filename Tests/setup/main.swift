// Make button 11 (Right top back, slot 10) a PC <-> Mac toggle and rescue the mouse from profile 3.
import Foundation
let transport = HIDTransport()
let connected = DispatchSemaphore(value: 0)
transport.onEvent = { e in if case .connected = e { connected.signal() } }
transport.start()
if !transport.isConnected { _ = connected.wait(timeout: .now() + 3) }
guard transport.isConnected else { print("not connected"); exit(1) }
let dev = TyonDevice(transport: transport)
let slot = 10
do {
    let types: [UInt8] = [0x11, 0x12, 0x12, 0x12, 0x12]   // P1 up, P2 down, P3-5 down (back towards Mac)
    for p in 0..<Tyon.profileCount {
        var b = try dev.readProfileButtons(p)
        if b.buttons[slot].type != types[p] {
            b.buttons[slot] = ButtonAssignment(type: types[p], modifier: 0, key: 0)
            try dev.writeProfileButtons(b, profile: p)
        }
        let rb = try dev.readProfileButtons(p)
        print("profile \(p + 1): button 11 = \(ButtonFunction.describe(rb.buttons[slot].type)) \(rb.buttons[slot].type == types[p] ? "✓" : "✗")")
    }
    try dev.writeActiveProfile(0)
    print("active profile now: \(try dev.readActiveProfile() + 1)")
} catch { print("ERROR:", error.localizedDescription); exit(2) }
transport.stop()
