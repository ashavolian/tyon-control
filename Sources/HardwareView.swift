import SwiftUI

struct HardwareView: View {
    @EnvironmentObject var model: AppModel
    @State private var liftOff: UInt8 = 0
    @State private var showCalibration = false

    var body: some View {
        Form {
            Section {
                Picker("Lift-off distance", selection: $liftOff) {
                    ForEach(LiftOffDistance.allCases) { d in Text(d.label).tag(d.rawValue) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("How high you can lift the mouse before the sensor stops tracking. This is a device-wide setting and takes effect immediately.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Set") {
                        if let d = LiftOffDistance(rawValue: liftOff) { model.setLiftOff(d) }
                    }
                    .disabled(model.busy || liftOff == model.controlUnit?.dcu)
                }
            } header: {
                Text("Distance Control Unit")
            }

            Section {
                HStack {
                    if let cu = model.controlUnit {
                        Label(cu.tcuOn ? "Calibrated to your surface (value \(cu.median))" : "Off (sensor defaults)",
                              systemImage: cu.tcuOn ? "checkmark.seal" : "circle.dashed")
                    } else {
                        Text("Unknown")
                    }
                    Spacer()
                    if model.controlUnit?.tcuOn == true {
                        Button("Turn off") { model.turnTrackingControlOff() }
                            .disabled(model.busy)
                    }
                    Button("Calibrate…") { showCalibration = true }
                        .disabled(model.busy)
                }
                Text("Surface calibration tunes the sensor to your mousepad. Run it with the mouse resting still on the pad you actually use.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Tracking Control Unit")
            }

            Section("Device") {
                LabeledContent("Model", value: model.identity?.product ?? "–")
                LabeledContent("Serial number", value: model.identity?.serial ?? "–")
                LabeledContent("Firmware", value: model.firmware ?? "–")
                LabeledContent("Active profile", value: "\(model.activeProfile + 1)")
            }
        }
        .formStyle(.grouped)
        .onAppear { liftOff = model.controlUnit?.dcu ?? 0 }
        .onChange(of: model.controlUnit) { _, cu in liftOff = cu?.dcu ?? liftOff }
        .sheet(isPresented: $showCalibration) {
            CalibrationView()
                .environmentObject(model)
        }
    }
}

struct CalibrationView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Phase { case intro, sampling(Int), testing(UInt8, [UInt8]) }
    @State private var phase: Phase = .intro

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Surface calibration").font(.title2.bold())

            switch phase {
            case .intro:
                Text("Put the mouse on the surface you normally use and keep it completely still. The sensor will take five snapshots of the surface, which takes a few seconds.")
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Start") { start() }.buttonStyle(.borderedProminent)
                }
            case .sampling(let n):
                ProgressView(value: Double(n), total: 5) {
                    Text("Sampling the surface… \(n) of 5")
                }
                Text("Don't move the mouse.").foregroundStyle(.secondary)
            case .testing(let median, let pixels):
                HStack(alignment: .top, spacing: 16) {
                    SensorImageView(pixels: pixels)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Calibration value: \(median)").font(.headline)
                        Text("The new calibration is active for testing. Move the mouse around: if tracking feels right, keep it. Discard returns to the previous state.")
                    }
                }
                HStack {
                    Spacer()
                    Button("Discard") { model.discardCalibration(); dismiss() }
                    Button("Keep") { model.keepCalibration(median); dismiss() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func start() {
        phase = .sampling(0)
        model.calibrateSurface(progress: { n in
            if case .sampling = phase { phase = .sampling(n) }
        }, completion: { result in
            phase = .testing(result.median, result.pixels)
        })
    }
}

/// Grayscale rendering of the sensor's 30x30 frame.
struct SensorImageView: View {
    let pixels: [UInt8]

    var body: some View {
        Canvas { ctx, size in
            guard pixels.count == 900 else { return }
            let cell = size.width / 30
            for y in 0..<30 {
                for x in 0..<30 {
                    let v = Double(pixels[y * 30 + x]) / 255
                    ctx.fill(Path(CGRect(x: Double(x) * cell, y: Double(y) * cell, width: cell + 0.5, height: cell + 0.5)),
                             with: .color(Color(white: v)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
    }
}
