// Offscreen render of each tab with sample data, for layout review without a display.
import SwiftUI
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let model = AppModel()
var s = ProfileSettings.factoryDefault
s.cpiLevels = [1000, 2000, 3000, 4400, 6200]; s.cpiActive = 1
s.lights[0].index = 7; s.lights[0].color = TyonPalette.colors[7]
s.lights[1].color = RGBColor(red: 0xff, green: 0xff, blue: 0xff); s.customColor = true
model.settings[0] = s
var b = ProfileButtons.factoryDefault
b.buttons[5] = ButtonAssignment(type: 0x05, modifier: 0x06, key: 0x33)   // shortcut ⌃⇧;
model.buttons[0] = b

@MainActor func render<V: View>(_ name: String, _ view: V, height: CGFloat = 540) {
    let wrapped = view.environmentObject(model).frame(width: 760, height: height).background(Color(nsColor: .windowBackgroundColor))
    let r = ImageRenderer(content: wrapped)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("render failed: \(name)"); return }
    try! png.write(to: URL(fileURLWithPath: "build/renders/\(name).png"))
    print("rendered \(name)")
}

Task { @MainActor in
    render("header", HeaderView(), height: 60)
    render("dpi", DPIView())
    render("pointer", SensitivityView())
    render("lighting", LightingView())
    render("buttons", ButtonsView(), height: 900)
    render("hardware", HardwareView())
    render("footer", FooterView(), height: 50)
    exit(0)
}
app.run()
