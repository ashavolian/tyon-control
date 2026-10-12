// One-off setup: profile 1 = "PC" (red lights, button 9 -> Profile up),
// profile 2 = "Mac" (same pointer settings, white lights, factory buttons, button 9 -> Profile down).
import Foundation

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
let transport = HIDTransport()
let connected = DispatchSemaphore(value: 0)
transport.onEvent = { e in if case .connected = e { connected.signal() } }
transport.start()
if !transport.isConnected { _ = connected.wait(timeout: .now() + 3) }
guard transport.isConnected else { print("not connected"); exit(1) }
let dev = TyonDevice(transport: transport)
let slot = 8   // "Left top back" = badge 9
do {
    var pc = try dev.readProfileSettings(0)
    var pcButtons = try dev.readProfileButtons(0)
    print("P1 before: lights=\(hex(Array(pc.encoded(profileIndex: 0)[14...27])))  slot9=\(hex([pcButtons.buttons[slot].type]))")

    // PC: red (palette 7) on both zones, palette mode
    for i in 0..<2 { pc.lights[i].index = 7; pc.lights[i].color = TyonPalette.colors[7] }
    pc.customColor = false
    pc.wheelLightOn = true; pc.bottomLightOn = true
    pcButtons.buttons[slot] = ButtonAssignment(type: 0x11, modifier: 0, key: 0)   // Profile up

    // Mac: same pointer settings, white custom lights, factory buttons + Profile down on slot 9
    var mac = pc
    for i in 0..<2 { mac.lights[i].index = 7; mac.lights[i].color = RGBColor(red: 0xff, green: 0xff, blue: 0xff) }
    mac.customColor = true
    let factoryTypes: [UInt8] = [0x01, 0x02, 0x03, 0x08, 0x07, 0x41, 0x82, 0x83, 0x16, 0x15, 0x8a, 0x8b, 0x0a, 0x09, 0x0d, 0x0e,
                                 0x08, 0x07, 0x25, 0x00, 0x00, 0x00, 0x80, 0x81, 0x12, 0x11, 0x88, 0x89, 0x86, 0x87, 0x26, 0x27]
    var factoryBytes: [UInt8] = [0x07, 0x63, 0x01]
    for t in factoryTypes { factoryBytes += [t, 0, 0] }
    var macButtons = try ProfileButtons(bytes: factoryBytes, expectedProfile: 1)
    macButtons.buttons[slot] = ButtonAssignment(type: 0x12, modifier: 0, key: 0)   // Profile down

    try dev.writeProfileSettings(pc, profile: 0)
    try dev.writeProfileButtons(pcButtons, profile: 0)
    try dev.writeProfileSettings(mac, profile: 1)
    try dev.writeProfileButtons(macButtons, profile: 1)

    let rpc = try dev.readProfileSettings(0), rpcb = try dev.readProfileButtons(0)
    let rmac = try dev.readProfileSettings(1), rmacb = try dev.readProfileButtons(1)
    print("P1 (PC)  settings \(rpc == pc ? "✓" : "✗") buttons \(rpcb == pcButtons ? "✓" : "✗")  lights=\(hex(Array(rpc.encoded(profileIndex: 0)[14...27]))) slot9=0x\(String(rpcb.buttons[slot].type, radix: 16))")
    print("P2 (Mac) settings \(rmac == mac ? "✓" : "✗") buttons \(rmacb == macButtons ? "✓" : "✗")  lights=\(hex(Array(rmac.encoded(profileIndex: 1)[14...27]))) slot9=0x\(String(rmacb.buttons[slot].type, radix: 16)) dpi=\(rmac.cpiLevels) active stage \(rmac.cpiActive + 1) poll=\(rmac.pollingRate?.label ?? "?")")
    print("active profile: \(try dev.readActiveProfile() + 1)")
} catch { print("ERROR:", error.localizedDescription); exit(2) }
transport.stop()
