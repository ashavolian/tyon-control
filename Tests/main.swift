// Reliability test: alternate two settings on profile 5 (index 4) through TyonDevice and verify each readback.
import Foundation

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

let transport = HIDTransport()
let connected = DispatchSemaphore(value: 0)
transport.onEvent = { e in if case .connected = e { connected.signal() } }
transport.start()
if !transport.isConnected { _ = connected.wait(timeout: .now() + 3) }
guard transport.isConnected else { print("not connected"); exit(1) }
let dev = TyonDevice(transport: transport)
do {
    let p = 4
    let orig = try dev.readProfileSettings(p)
    print("orig:    \(hex(orig.encoded(profileIndex: p)))")
    var red = orig
    red.lights[0].index = 7; red.lights[0].color = TyonPalette.colors[7]
    red.lights[1].index = 7; red.lights[1].color = TyonPalette.colors[7]
    print("red:     \(hex(red.encoded(profileIndex: p)))")
    var ok = 0, bad = 0
    for round in 0..<6 {
        let target = round % 2 == 0 ? red : orig
        let t0 = Date()
        try dev.writeProfileSettings(target, profile: p)
        let rb = try dev.readProfileSettings(p)
        let match = rb == target
        if match { ok += 1 } else { bad += 1 }
        print("round \(round) wrote \(round % 2 == 0 ? "red " : "orig") -> \(match ? "✓" : "✗ MISMATCH") (\(String(format: "%.2f", Date().timeIntervalSince(t0)))s)  lights=\(hex(Array(rb.encoded(profileIndex: p)[18...27])))")
    }
    // make sure we end on the original
    try dev.writeProfileSettings(orig, profile: p)
    let final = try dev.readProfileSettings(p)
    print("final restored: \(final == orig)   ok=\(ok) bad=\(bad)")
} catch {
    print("ERROR:", error.localizedDescription); exit(2)
}
transport.stop()
