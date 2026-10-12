import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    /// Keep running in the menu bar so gestures work with the window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }
}

@main
struct TyonControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Tyon Control", id: "main") {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    delegate.model = model
                    model.start()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Apply to Mouse") { model.apply() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.isDirty || model.busy || !model.connected)
                Button("Reload from Mouse") { model.reloadAll() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.busy || !model.connected)
                Divider()
                Button("Export Profile…") { model.exportProfile(model.selectedProfile) }
                    .disabled(!model.loaded)
                Button("Import into Profile…") { model.importProfile(into: model.selectedProfile) }
                    .disabled(!model.loaded)
            }
        }

        MenuBarExtra("Tyon Control", systemImage: "computermouse") {
            MenuBarContent(model: model, engine: model.gestures)
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: GestureEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Tyon Control") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Toggle("Mac controls enabled", isOn: $engine.config.enabled)
        Divider()
        Text(model.connected ? "Mouse connected · profile \(model.activeProfile + 1) active" : "Mouse not connected")
        Divider()
        Button("Quit Tyon Control") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
