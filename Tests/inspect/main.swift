import Foundation
let transport = HIDTransport()
let connected = DispatchSemaphore(value: 0)
transport.onEvent = { e in if case .connected = e { connected.signal() } }
transport.start()
if !transport.isConnected { _ = connected.wait(timeout: .now() + 3) }
guard transport.isConnected else { print("not connected"); exit(1) }
let dev = TyonDevice(transport: transport)
do {
    print("active profile: \(try dev.readActiveProfile() + 1)")
    for p in 0..<Tyon.profileCount {
        let b = try dev.readProfileButtons(p)
        let show = [8, 10, 5, 26].map { "\($0 + 1 <= 16 ? "#\($0 + 1)" : "shift#\($0 - 15)") \(TyonButton.slotName($0))=0x\(String(b.buttons[$0].type, radix: 16)) (\(ButtonFunction.describe(b.buttons[$0].type)))" }
        print("profile \(p + 1): " + show.joined(separator: " | "))
    }
} catch { print("ERROR:", error.localizedDescription) }
transport.stop()
