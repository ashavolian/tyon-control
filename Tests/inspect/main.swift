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
        print("profile \(p + 1): wheel up=0x\(String(b.buttons[14].type, radix: 16)) (\(ButtonFunction.describe(b.buttons[14].type)))  wheel down=0x\(String(b.buttons[15].type, radix: 16)) (\(ButtonFunction.describe(b.buttons[15].type)))  wheel click=0x\(String(b.buttons[2].type, radix: 16))")
    }
} catch { print("ERROR:", error.localizedDescription) }
transport.stop()
