// DebugSnapshot.swift
// Development aid: when TYON_SNAPSHOT_DIR is set in the environment, the app writes a PNG
// of its own window for every tab after the first successful read, then quits.
// Uses NSView.cacheDisplay, which needs no screen-recording permission.

import AppKit
import SwiftUI

enum DebugSnapshot {
    static func runIfRequested(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["TYON_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var tab = 0
        func step() {
            guard tab < 7 else { NSApp.terminate(nil); return }
            model.selectedTab = tab
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                snapshot(to: url.appendingPathComponent("tab\(tab).png"))
                tab += 1
                step()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { step() }
    }

    static func snapshot(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView else { NSLog("snapshot: no window"); return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            NSLog("snapshot: wrote %@", url.path)
        }
    }
}
