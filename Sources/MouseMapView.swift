// MouseMapView.swift
// The user's photo of the Tyon with numbered callouts for every physical button.
// Coordinates are normalized to the 700x467 photo so the map scales with the window.

import SwiftUI
import AppKit

struct MouseMapView: View {
    @Binding var highlighted: TyonButton?
    var onFocus: (TyonButton) -> Void   // badge hovered or clicked: highlight and scroll the list to it
    var onBlur: () -> Void              // pointer left a badge

    static let image: NSImage? = Bundle.main.url(forResource: "tyon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    static let aspect: CGFloat = 700.0 / 467.0

    struct Callout {
        let anchor: CGPoint   // where the control is on the photo
        let label: CGPoint    // where the numbered badge sits
        init(_ ax: CGFloat, _ ay: CGFloat, _ lx: CGFloat, _ ly: CGFloat) {
            anchor = CGPoint(x: ax / 700, y: ay / 467)
            label = CGPoint(x: lx / 700, y: ly / 467)
        }
    }

    static let callouts: [TyonButton: Callout] = [
        .left:         Callout(240, 135, 150, 70),
        .right:        Callout(318, 100, 405, 30),
        .middle:       Callout(276, 112, 245, 20),
        .thumbBack:    Callout(325, 258, 390, 330),
        .thumbForward: Callout(242, 228, 150, 285),
        .thumbPedal:   Callout(276, 332, 215, 385),
        .paddleUp:     Callout(281, 204, 150, 190),
        .paddleDown:   Callout(296, 229, 170, 240),
        .leftBack:     Callout(212, 163, 115, 140),
        .leftForward:  Callout(188, 155, 105, 100),
        .rightBack:    Callout(352, 86, 455, 70),
        .rightForward: Callout(312, 76, 335, 12),
        .finRight:     Callout(372, 124, 485, 110),
        .finLeft:      Callout(360, 145, 470, 160),
        .wheelUp:      Callout(266, 102, 195, 38),
        .wheelDown:    Callout(288, 121, 300, 48),
    ]

    var body: some View {
        if let img = Self.image {
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Canvas { ctx, canvasSize in
                        for (button, c) in Self.callouts {
                            let a = Self.point(c.anchor, canvasSize)
                            let l = Self.point(c.label, canvasSize)
                            let hl = highlighted == button
                            var line = Path()
                            line.move(to: l)
                            line.addLine(to: a)
                            ctx.stroke(line, with: .color(hl ? Color.accentColor : Color.white.opacity(0.8)), lineWidth: hl ? 2 : 1)
                            let dot = Path(ellipseIn: CGRect(x: a.x - 3, y: a.y - 3, width: 6, height: 6))
                            ctx.fill(dot, with: .color(hl ? Color.accentColor : .white))
                            ctx.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 0.5)
                        }
                    }
                    .allowsHitTesting(false)

                    ForEach(TyonButton.allCases) { button in
                        if let c = Self.callouts[button] {
                            NumberBadge(number: button.rawValue + 1, highlighted: highlighted == button, size: 20)
                                .position(Self.point(c.label, size))
                                .onTapGesture { onFocus(button) }
                                .onHover { inside in
                                    if inside {
                                        onFocus(button)
                                    } else {
                                        if highlighted == button { highlighted = nil }
                                        onBlur()
                                    }
                                }
                                .help(button.name)
                        }
                    }
                }
            }
            .aspectRatio(Self.aspect, contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.1))
                .aspectRatio(Self.aspect, contentMode: .fit)
                .overlay(Text("Photo missing from bundle").font(.caption).foregroundStyle(.secondary))
        }
    }

    private static func point(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }
}

struct NumberBadge: View {
    let number: Int
    var highlighted = false
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(highlighted ? Color.accentColor : Color.black.opacity(0.78))
            Circle().stroke(Color.white, lineWidth: 1.5)
            Text("\(number)")
                .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }
}
