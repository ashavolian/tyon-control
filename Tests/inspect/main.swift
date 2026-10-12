import Foundation
let transport = HIDTransport()
let connected = DispatchSemaphore(value: 0)
transport.onEvent = { e in if case .connected = e { connected.signal() } }
transport.start()
if !transport.isConnected { _ = connected.wait(timeout: .now() + 3) }
guard transport.isConnected else { print("not connected"); exit(1) }
let dev = TyonDevice(transport: transport)
do {
    let active = try dev.readActiveProfile()
    print("active profile: \(active + 1)")
    for p in 0..<2 {
        let b = try dev.readProfileButtons(p)
        let interesting = [3, 4, 5, 6, 7, 8, 12, 13]
        print("profile \(p + 1): " + interesting.map { "\(TyonButton.slotName($0))=0x\(String(b.buttons[$0].type, radix: 16))" }.joined(separator: "  "))
    }
} catch { print("ERROR:", error.localizedDescription) }
transport.stop()
