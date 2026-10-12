# Tyon Control

A small native macOS app for configuring a **ROCCAT Tyon** gaming mouse (black or white)
without ROCCAT's discontinued Swarm software. It talks to the mouse directly over USB HID
feature reports; nothing is installed system-wide and no driver is needed.

What you can change, per profile (the mouse stores five):

- **DPI** – five stages (200–8200, 200 steps), enable/disable each, pick the active one
- **Pointer** – sensitivity (optionally separate X/Y), USB polling rate, TalkFX on/off
- **Lighting** – wheel and bottom zones on/off, palette or custom colors, effect
  (solid / blinking / breathing / heartbeat / off), speed, color cycling
- **Buttons** – all 16 physical buttons, both the normal and the Easy-Shift[+] layer,
  including keyboard shortcuts with modifiers
- **Profiles** – name the five profiles and set up a profile-switch button; two neighbouring
  profiles or all five are handled by the mouse itself (works on any computer), any other set is
  switched by the app (Mac only)
- **Hardware** – lift-off distance (DCU), surface calibration (TCU), firmware info
- **Mac** – MX-Master-style gesture button (click = Mission Control, hold + move = switch desktop,
  Mission Control, App Exposé) and single-press Mac actions on other buttons. The mouse reports
  such buttons to the app (firmware type "Mac action" = quick launch), the app performs the action.
  Desktop switching and Spotlight need Accessibility access; the app stays in the menu bar when the
  window is closed and can start at login.

Everything is staged in memory; nothing is sent until you click **Apply to mouse**
(⌘S). Each write is read back and verified. Profiles can be exported/imported as JSON.

Not implemented on purpose: macro recording, firmware/sensor-firmware updates, factory reset
command. Existing macros assigned to buttons are preserved untouched.

## Build

Requires only the Xcode command-line tools (Swift 5.9+). Produces an ad-hoc-signed
`build/Tyon Control.app`.

```sh
./build.sh
open "build/Tyon Control.app"
```

Regenerate the icon with `swift Tools/make_icon.swift "$PWD/Resources"`.

The Buttons tab draws numbered callouts on a photo of the mouse. The photo is not part of this
repository; put your own 700×467 picture of a Tyon (same angle as the stock press shot: front
to the upper left, thumb side facing you) at `Resources/tyon.png` before building, or the app
shows a placeholder and the callout coordinates in `Sources/MouseMapView.swift` will need adjusting.

### Signing (optional but recommended)

macOS ties the Accessibility permission the Mac tab needs to the app's code signature, and an
ad-hoc signature changes with every build. `build.sh` therefore signs with a local certificate
named "Tyon Control Signing" when one exists in the login keychain (create one with Keychain
Access → Certificate Assistant → Create a Certificate, type "Code Signing"), and falls back to
ad-hoc signing otherwise.

## How it talks to the mouse

Protocol details come from the GPL [roccat-tools](https://sourceforge.net/projects/roccat/)
project (`tyon/libroccattyon`), verified against a real Tyon Black with firmware 1.34.

- Report `0x0e` DEVICE_STATE = 1 at connect makes the firmware report "quick launch" buttons and
  profile/DPI changes as 5-byte input reports (id `0x03`) on the misc interface.
- Report `0x04` CONTROL: select which profile's data the next read returns, and poll until
  the firmware says OK after every write.
- Report `0x05` active profile, `0x06` profile settings (30 bytes, 16-bit byte-sum
  checksum), `0x07` button map (99 bytes), `0x09` info, `0x0f` control unit (DCU/TCU),
  `0x0c` sensor frame capture (for calibration only).
- The Tyon declares its vendor feature reports on its *mouse* HID interface, which current
  macOS won't let an app open without Input Monitoring permission. The firmware answers the
  same reports on any interface, so the app opens the joystick interface (usage page 1,
  usage 4) instead and falls back to the misc interface (page 0x0a). Reads and writes were
  verified to persist through that path.

## Credits and licensing notes

The device protocol was learned from Stefan Achatz's GPL-licensed
[roccat-tools](https://sourceforge.net/projects/roccat/) and verified on real hardware; this
app is an independent Swift implementation of that protocol and contains no roccat-tools code.
ROCCAT and Tyon are trademarks of their owners; this is a hobby project with no affiliation.

## Layout

```
Sources/TyonProtocol.swift   report layouts, enums, labels, checksum
Sources/HIDTransport.swift   IOKit HID discovery, hot-plug, get/set feature report
Sources/TyonDevice.swift     select/handshake, read & write operations
Sources/AppModel.swift       staged state, apply/verify, calibration, import/export
Sources/MacActions.swift     Mac actions (whitelisted keystrokes / system apps) + Accessibility check
Sources/GestureEngine.swift  hold-and-move gesture detection, config persisted in UserDefaults
Sources/ProfilePrefs.swift   profile names + profile-switch button logic
Sources/*View.swift          SwiftUI
Tests/main.swift             a CLI harness that round-trips profile 5 against the mouse
```
