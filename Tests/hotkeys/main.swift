import Foundation
for (name, id) in [("Mission Control", 32), ("App windows", 33), ("Show Desktop", 36), ("Move left a space", 79), ("Move right a space", 81), ("Spotlight", 64)] {
    if let c = SystemHotkey.combo(id) {
        print("\(name): \(SystemHotkey.describe(c))  keyCode=\(c.keyCode) flags=0x\(String(c.flags.rawValue, radix: 16))")
    } else {
        print("\(name): DISABLED in System Settings")
    }
}
