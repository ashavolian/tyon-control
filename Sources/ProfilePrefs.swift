// ProfilePrefs.swift
// App-side profile preferences: names for the five profiles and the "profile switch"
// button configuration. The mouse itself only knows profiles 1-5.

import Foundation

struct ProfilePrefs: Codable, Equatable {
    var names: [String] = Array(repeating: "", count: Tyon.profileCount)
    var cycleButton: Int? = nil        // slot 0-31
    var cycleSet: [Int] = []           // sorted profile indices in the cycle

    private static let defaultsKey = "TyonControl.profilePrefs"

    static func load() -> ProfilePrefs {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var p = try? JSONDecoder().decode(ProfilePrefs.self, from: data) else { return ProfilePrefs() }
        if p.names.count != Tyon.profileCount { p.names = Array(repeating: "", count: Tyon.profileCount) }
        p.names = p.names.map { String($0.prefix(24)) }
        if let b = p.cycleButton, !(0..<Tyon.buttonCount).contains(b) { p.cycleButton = nil }
        p.cycleSet = Array(Set(p.cycleSet.filter { (0..<Tyon.profileCount).contains($0) })).sorted()
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// How a cycle through `cycleSet` can be realised.
    enum Mechanism: Equatable {
        case needMore                 // fewer than two profiles chosen
        case firmwareTwoAdjacent      // "Profile up" in the lower, "Profile down" in the higher profile
        case firmwareAll              // "Profile cycle" in every profile
        case software                 // app switches profiles; Mac only
    }

    var mechanism: Mechanism {
        if cycleSet.count < 2 { return .needMore }
        if cycleSet.count == 2, cycleSet[1] == cycleSet[0] + 1 { return .firmwareTwoAdjacent }
        if cycleSet.count == Tyon.profileCount { return .firmwareAll }
        return .software
    }

    /// Desired firmware assignment of the cycle button per profile (nil = leave untouched).
    func desiredAssignments() -> [Int: ButtonAssignment] {
        guard cycleButton != nil else { return [:] }
        switch mechanism {
        case .needMore:
            return [:]
        case .firmwareTwoAdjacent:
            // Inside the pair the button toggles; from any other profile it steps back towards the pair,
            // so a stray profile switch can always be undone with the same button.
            let lo = cycleSet[0], hi = cycleSet[1]
            var map: [Int: ButtonAssignment] = [:]
            for p in 0..<Tyon.profileCount {
                let type: UInt8 = p <= lo ? ButtonFunction.profileUp : ButtonFunction.profileDown
                map[p] = ButtonAssignment(type: p == lo ? ButtonFunction.profileUp : (p == hi ? ButtonFunction.profileDown : type), modifier: 0, key: 0)
            }
            return map
        case .firmwareAll:
            return Dictionary(uniqueKeysWithValues: (0..<Tyon.profileCount).map { ($0, ButtonAssignment(type: ButtonFunction.profileCycle, modifier: 0, key: 0)) })
        case .software:
            // Map it in every profile so the button also brings you back into the set.
            return Dictionary(uniqueKeysWithValues: (0..<Tyon.profileCount).map { ($0, ButtonAssignment(type: ButtonFunction.macAction, modifier: 0, key: 0)) })
        }
    }

    /// Next profile in the cycle after `current` (a non-member jumps to the first member).
    func next(after current: Int, forward: Bool) -> Int? {
        guard cycleSet.count >= 2 else { return nil }
        guard let i = cycleSet.firstIndex(of: current) else { return cycleSet.first }
        let n = cycleSet.count
        return cycleSet[(i + (forward ? 1 : n - 1)) % n]
    }
}

extension ButtonFunction {
    static let profileCycle: UInt8 = 0x10
    static let profileUp: UInt8 = 0x11
    static let profileDown: UInt8 = 0x12
}
