# Fun Fan Control

A small macOS menu bar utility for people who want a laptop that stays cool to the touch
without the fans screaming. It shows live fan RPM and CPU / GPU temperatures in a dropdown,
and lets you draw your own temperature → RPM curve and watch how it behaves in real time.

Works on Apple Silicon (tested on an M1 Pro MacBook Pro) and should work on Intel Macs;
it talks directly to the System Management Controller (SMC) through IOKit.

## Features

- **Menu bar item** with a fan icon and the current curve-input temperature.
- **Dropdown** showing each fan's RPM (with its min/max range and current target) and CPU / GPU temperature.
- **Gear button** opens the *Fan Curves* window:
  - interactive curve editor: drag points, double-click to add, Delete to remove, presets (Quiet / Balanced / Cool to the touch)
  - a live orange marker showing where the machine is right now on the curve
  - the curve is defined in percent of each fan's own min–max range, so a shared curve drives fans with different top speeds (e.g. 4296 vs 4744 RPM on an M1 Pro) at the same relative effort instead of the same RPM
  - one curve for all fans or a separate curve per fan
  - choose what drives the curve: CPU, GPU, the hottest of the two, or any custom set of sensors (e.g. a palm-rest sensor)
  - every temperature sensor the SMC exposes, grouped and live
  - smoothing (max RPM change per update, dead band) so fans never surge audibly
  - a safety threshold above which fans go to full speed regardless of the curve
- Fans are handed back to macOS automatic control when the app quits, on sleep, or when custom control is switched off.

## Build

Requires Xcode (or the Command Line Tools) with Swift 5.9+ and macOS 14+.

```bash
make app        # builds build/Fun Fan Control.app
make run        # builds and opens it
make install    # copies the app to /Applications
make probe      # prints every fan and temperature key your Mac's SMC exposes
```

## The root helper

Reading sensors needs no privileges, but *writing* a fan target does. All writes go through
`ffc-helper`, a tiny separate binary inside the app bundle that only understands three commands:

```
ffc-helper set <fan> <rpm> [<fan> <rpm> ...]   force fans to a target RPM (clamped to the fan's range)
ffc-helper auto                                hand every fan back to macOS
ffc-helper status                              show fan modes and targets
```

The first time you turn on *Custom fan curve*, click **Install helper** in the dropdown or in
Settings. You'll be asked for your password once; the helper is then marked setuid root.
`make app` stops a running copy of the app first (so it can hand the fans back to macOS)
and keeps the installed helper when the helper binary has not changed. When it has changed
you need to reinstall it, from the app or with `make install-helper`.

If the app ever finds a fan in forced mode that it is not driving (after a crash, for
example), it hands the fan back to macOS as soon as the helper is available, and the
dropdown says "Forced · not by this app" until then.

## How the control loop works

Every *n* seconds (default 2) the app reads the fans and all temperature sensors, computes the
curve-input temperature, interpolates the curve to a percent and converts it to RPM using each
fan's own range, limits how much the target may move per update, and sends the new target to the helper only if it changed by more than the
dead band. If macOS takes a fan back (after sleep, for example) the target is re-sent.

Settings live in `~/Library/Application Support/Fun Fan Control/settings.json`.

## Project layout

```
Sources/CSMC           C layer: open AppleSMC, read/write keys, enumerate keys
Sources/FanKit         Swift: SMC wrapper + codecs, sensor reader, curve model, settings, helper client
Sources/FunFanControl  SwiftUI menu bar app: engine, dropdown, curve editor, sensors, settings
Sources/ffc-helper     setuid-root helper that performs the fan writes
Sources/ffc-probe      developer tool that dumps every fan / temperature key
Resources/Info.plist   bundle metadata (LSUIElement so there is no Dock icon)
```

## Caveats

- Forcing fans below what macOS would choose can let the chip run hotter; the safety threshold
  (default 98 °C) and the fan's own hardware limits still apply, but use some judgement.
- Apple's firmware may ignore targets outside the fan's reported min/max; the helper clamps to that range.
- The app is ad-hoc signed. Gatekeeper may warn if you copy it to another Mac.
