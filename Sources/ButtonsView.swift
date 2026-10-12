import SwiftUI

struct ButtonsView: View {
    @EnvironmentObject var model: AppModel
    @State private var highlighted: TyonButton?
    @State private var scrollTarget: TyonButton?   // set only from the photo map, never from row hover

    private let groups = ["Main", "Top", "Thumb", "Fin"]

    var body: some View {
        let b = model.buttonsBinding(model.selectedProfile)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                MouseMapView(highlighted: $highlighted,
                             onFocus: { button in
                                 highlighted = button
                                 scrollTarget = button
                             },
                             onBlur: { scrollTarget = nil })
                Text("Hover a row to see where the button is; hover or click a number to find its row.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 330)
            .padding(.top, 4)

            ScrollViewReader { proxy in
                Form {
                    Section {
                        HStack {
                            Text("Button").frame(width: 170, alignment: .leading)
                            Text("Normal").frame(maxWidth: .infinity, alignment: .leading)
                            Text("With Easy-Shift[+] held").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    ForEach(groups, id: \.self) { group in
                        Section(group) {
                            ForEach(TyonButton.allCases.filter { $0.group == group }) { btn in
                                ButtonRow(button: btn, buttons: b, highlighted: highlighted == btn)
                                    .id(btn)
                                    .onHover { inside in
                                        if inside { highlighted = btn } else if highlighted == btn { highlighted = nil }
                                    }
                            }
                        }
                    }
                    Section {
                        Text("Easy-Shift[+] is the function that turns the second layer on while held; by default it sits on the thumb pedal. Macros can't be edited here, but existing ones are kept as they are.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .onChange(of: scrollTarget) { _, target in
                    if let target = target { withAnimation { proxy.scrollTo(target, anchor: .center) } }
                }
            }
        }
    }
}

struct ButtonRow: View {
    let button: TyonButton
    @Binding var buttons: ProfileButtons
    var highlighted = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NumberBadge(number: button.rawValue + 1, highlighted: highlighted, size: 18)
                .padding(.top, 3)
            Text(button.name)
                .frame(width: 140, alignment: .leading)
                .padding(.top, 3)
                .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
            AssignmentEditor(assignment: $buttons.buttons[button.rawValue])
                .frame(maxWidth: .infinity, alignment: .leading)
            AssignmentEditor(assignment: $buttons.buttons[button.rawValue + Tyon.physicalButtonCount])
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(highlighted ? Color.accentColor.opacity(0.12) : nil)
    }
}

struct AssignmentEditor: View {
    @Binding var assignment: ButtonAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: typeBinding) {
                ForEach(ButtonFunction.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(ButtonFunction.all.filter { $0.group == group && $0.code != ButtonFunction.macro }) { f in
                            Text(f.name).tag(f.code)
                        }
                    }
                }
                if ButtonFunction.named(assignment.type) == nil || assignment.type == ButtonFunction.macro {
                    Divider()
                    Text(ButtonFunction.describe(assignment.type)).tag(assignment.type)
                }
            }
            .labelsHidden()

            if assignment.type == ButtonFunction.shortcut {
                HStack(spacing: 6) {
                    ModifierToggle(symbol: "⌃", help: "Control", flag: .control, modifiers: $assignment.modifier)
                    ModifierToggle(symbol: "⌥", help: "Option", flag: .alt, modifiers: $assignment.modifier)
                    ModifierToggle(symbol: "⇧", help: "Shift", flag: .shift, modifiers: $assignment.modifier)
                    ModifierToggle(symbol: "⌘", help: "Command", flag: .command, modifiers: $assignment.modifier)
                    Picker("", selection: $assignment.key) {
                        ForEach(HIDKey.names, id: \.0) { usage, name in
                            Text(name).tag(usage)
                        }
                        if !HIDKey.names.contains(where: { $0.0 == assignment.key }) {
                            Text(HIDKey.name(assignment.key)).tag(assignment.key)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
            }
        }
    }

    private var typeBinding: Binding<UInt8> {
        Binding(
            get: { assignment.type },
            set: { newType in
                guard newType != assignment.type else { return }
                assignment.type = newType
                if newType == ButtonFunction.shortcut {
                    if assignment.key == 0 { assignment.key = 0x04 }   // "A"
                } else {
                    assignment.modifier = 0
                    assignment.key = 0
                }
            }
        )
    }
}

struct ModifierToggle: View {
    let symbol: String
    let help: String
    let flag: ShortcutModifiers
    @Binding var modifiers: UInt8

    var body: some View {
        Toggle(symbol, isOn: Binding(
            get: { ShortcutModifiers(rawValue: modifiers).contains(flag) },
            set: { on in
                var m = ShortcutModifiers(rawValue: modifiers)
                if on { m.insert(flag) } else { m.remove(flag) }
                modifiers = m.rawValue
            }))
        .toggleStyle(.button)
        .help(help)
    }
}
